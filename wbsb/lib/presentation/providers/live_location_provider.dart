import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/entities/bus.dart';
import '../../domain/entities/live_location.dart';
import '../../domain/entities/ride_contribution.dart';
import '../../domain/entities/trip_progress.dart';
import '../../domain/repositories/ride_tracking_repository.dart';
import '../../domain/usecases/calculate_trip_progress_usecase.dart';
import '../../domain/usecases/resolve_live_location_usecase.dart';

/// Drives the live map screen's view of a bus: the resolved crowd-
/// sourced position (from real passenger contributions in Firestore),
/// derived trip progress (current/next stop, ETA, delay), plus the
/// viewing device's own real GPS position (a "you are here" marker —
/// separate from actively riding/contributing).
class LiveLocationProvider extends ChangeNotifier {
  final RideTrackingRepository _repository;
  final ResolveLiveLocationUseCase _resolve;
  final CalculateTripProgressUseCase _calculateProgress;
  final Bus _bus;

  List<LatLng> roadRoutePoints = [];

  LiveLocationProvider(
    this._repository,
    this._bus, {
    ResolveLiveLocationUseCase? resolver,
    CalculateTripProgressUseCase? progressCalculator,
  })  : _resolve = resolver ?? ResolveLiveLocationUseCase(),
        _calculateProgress = progressCalculator ?? CalculateTripProgressUseCase() {
    _fetchOSRMRoute();
  }

  Future<void> _fetchOSRMRoute() async {
    final coordStops = _bus.routeStops.where((s) => s.hasCoordinates).toList();
    if (coordStops.length < 2) return;
    
    // Deduplicate consecutive/nearby waypoints to prevent OSRM Routing conflicts
    final uniqueStops = <dynamic>[];
    final seenCoords = <String>{};
    for (final stop in coordStops) {
      final key = '${stop.latitude!.toStringAsFixed(5)},${stop.longitude!.toStringAsFixed(5)}';
      if (!seenCoords.contains(key)) {
        seenCoords.add(key);
        uniqueStops.add(stop);
      }
    }

    // Helper to sample stops to stay within OSRM limits and avoid rate-limiting/timeouts
    List<dynamic> sampleWaypoints(List<dynamic> stops, int maxWaypoints) {
      if (stops.length <= maxWaypoints) return stops;
      final sampled = <dynamic>[];
      sampled.add(stops.first); // origin
      final double step = (stops.length - 1) / (maxWaypoints - 1);
      for (int i = 1; i < maxWaypoints - 1; i++) {
        final idx = (i * step).round();
        if (idx > 0 && idx < stops.length - 1) {
          sampled.add(stops[idx]);
        }
      }
      sampled.add(stops.last); // destination
      return sampled;
    }

    Future<List<LatLng>> queryOSRM(List<dynamic> stops) async {
      final coordsString = stops.map((s) => '${s.longitude},${s.latitude}').join(';');
      final url = 'https://router.project-osrm.org/route/v1/driving/$coordsString?overview=full&geometries=geojson';
      
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geom = data['routes'][0]['geometry']['coordinates'] as List<dynamic>;
          final points = geom.map((c) {
            final lng = (c[0] as num).toDouble();
            final lat = (c[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();
          client.close();
          return points;
        }
      }
      client.close();
      throw Exception('OSRM query failed: ${response.statusCode}');
    }
    
    try {
      // First try with sampled waypoints (max 10) for high success rate and immediate response
      final sampledStops = sampleWaypoints(uniqueStops, 10);
      roadRoutePoints = await queryOSRM(sampledStops);
      notifyListeners();
      return;
    } catch (e) {
      if (kDebugMode) {
        print('OSRM sampled routing failed: $e. Trying full list...');
      }
      try {
        // Fallback: try entire list of stops at once
        roadRoutePoints = await queryOSRM(uniqueStops);
        notifyListeners();
        return;
      } catch (fullErr) {
        if (kDebugMode) {
          print('OSRM single routing failed: $fullErr. Trying segment-by-segment...');
        }
      }
    }
      
      // Segment-by-segment fallback
      final segmentsGeometry = <LatLng>[];
      for (int i = 0; i < uniqueStops.length - 1; i++) {
        final s1 = uniqueStops[i];
        final s2 = uniqueStops[i + 1];
        final segCoords = '${s1.longitude},${s1.latitude};${s2.longitude},${s2.latitude}';
        final segUrl = 'https://router.project-osrm.org/route/v1/driving/$segCoords?overview=full&geometries=geojson';
        
        try {
          await Future.delayed(const Duration(milliseconds: 50));
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(segUrl)).timeout(const Duration(seconds: 5));
          final response = await request.close();
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final data = jsonDecode(body);
            if (data['routes'] != null && data['routes'].isNotEmpty) {
              final geom = data['routes'][0]['geometry']['coordinates'] as List<dynamic>;
              final points = geom.map((c) {
                final lng = (c[0] as num).toDouble();
                final lat = (c[1] as num).toDouble();
                return LatLng(lat, lng);
              }).toList();
              segmentsGeometry.addAll(points);
            } else {
              throw Exception('No routes for segment');
            }
          } else {
            throw Exception('HTTP ${response.statusCode}');
          }
          client.close();
        } catch (segErr) {
          if (kDebugMode) {
            print('OSRM segment $i routing failed, using straight line: $segErr');
          }
          segmentsGeometry.add(LatLng(s1.latitude!, s1.longitude!));
          segmentsGeometry.add(LatLng(s2.latitude!, s2.longitude!));
        }
      }
      
      if (segmentsGeometry.isNotEmpty) {
        // Deduplicate consecutive identical points
        final dedupedGeom = <LatLng>[];
        for (final pt in segmentsGeometry) {
          if (dedupedGeom.isEmpty) {
            dedupedGeom.add(pt);
          } else {
            final last = dedupedGeom.last;
            if ((last.latitude - pt.latitude).abs() > 0.00001 || 
                (last.longitude - pt.longitude).abs() > 0.00001) {
              dedupedGeom.add(pt);
            }
          }
        }
        roadRoutePoints = dedupedGeom;
        notifyListeners();
      }
    }
  }

  StreamSubscription<List<RideContribution>>? _contributionsSub;
  StreamSubscription<Position>? _viewerSub;

  LiveLocation? resolvedLocation;
  TripProgress tripProgress = const TripProgress.insufficientData();
  Position? viewerPosition;
  String? locationError;

  void watchBus(String busId) {
    _contributionsSub?.cancel();
    _contributionsSub =
        _repository.watchContributions(busId).listen((contributions) {
      resolvedLocation = _resolve(busId, contributions);
      tripProgress = resolvedLocation != null
          ? _calculateProgress(_bus, resolvedLocation!)
          : const TripProgress.insufficientData();
      notifyListeners();
    }, onError: (e) {
      locationError = 'Could not load live location: $e';
      notifyListeners();
    });
  }

  Future<void> startViewerLocation() async {
    final ok = await _ensurePermission();
    if (!ok) {
      locationError = 'Location permission denied.';
      notifyListeners();
      return;
    }

    _viewerSub?.cancel();
    _viewerSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      viewerPosition = pos;
      notifyListeners();
    }, onError: (e) {
      locationError = e.toString();
      notifyListeners();
    });
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    return permission != LocationPermission.deniedForever;
  }

  @override
  void dispose() {
    _contributionsSub?.cancel();
    _viewerSub?.cancel();
    super.dispose();
  }
}
