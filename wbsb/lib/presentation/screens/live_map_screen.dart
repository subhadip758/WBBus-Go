import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/ride_tracking_repository.dart';
import '../providers/live_location_provider.dart';
import '../providers/ride_session_provider.dart';

class LiveMapScreen extends StatelessWidget {
  final Bus bus;
  const LiveMapScreen({super.key, required this.bus});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LiveLocationProvider(
        context.read<RideTrackingRepository>(),
        bus,
      )
        ..watchBus(bus.id)
        ..startViewerLocation(),
      child: _LiveMapBody(bus: bus),
    );
  }
}

class _LiveMapBody extends StatefulWidget {
  final Bus bus;
  const _LiveMapBody({required this.bus});

  @override
  State<_LiveMapBody> createState() => _LiveMapBodyState();
}

class _LiveMapBodyState extends State<_LiveMapBody> with TickerProviderStateMixin {
  late final MapController _mapController;
  LiveLocationProvider? _lastProvider;

  LatLng? _animatedBusLatLng;
  double _animatedHeading = 0.0;

  AnimationController? _markerPositionController;
  LatLng? _startLatLng;
  LatLng? _targetLatLng;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<LiveLocationProvider>(context);
    if (_lastProvider != provider) {
      _lastProvider?.removeListener(_onProviderUpdate);
      _lastProvider = provider;
      _lastProvider?.addListener(_onProviderUpdate);
    }
  }

  void _onProviderUpdate() {
    final loc = _lastProvider?.resolvedLocation;
    if (loc == null) {
      if (_animatedBusLatLng != null) {
        setState(() {
          _animatedBusLatLng = null;
          _animatedHeading = 0.0;
          _targetLatLng = null;
        });
      }
      return;
    }

    final newTarget = LatLng(loc.latitude, loc.longitude);
    final newHeading = (loc.headingDegrees ?? 0.0) * (3.141592653589793 / 180.0);

    if (_targetLatLng == null) {
      setState(() {
        _animatedBusLatLng = newTarget;
        _animatedHeading = newHeading;
        _targetLatLng = newTarget;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(newTarget, _mapController.camera.zoom);
        }
      });
    } else if (newTarget.latitude != _targetLatLng!.latitude ||
               newTarget.longitude != _targetLatLng!.longitude) {
      _startLatLng = _animatedBusLatLng ?? _targetLatLng;
      _targetLatLng = newTarget;

      _markerPositionController?.dispose();
      _markerPositionController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      );

      final startHeading = _animatedHeading;
      double endHeading = newHeading;
      double diff = endHeading - startHeading;
      while (diff < -3.141592653589793) {
        diff += 2 * 3.141592653589793;
      }
      while (diff > 3.141592653589793) {
        diff -= 2 * 3.141592653589793;
      }
      final targetHeadingFinal = startHeading + diff;

      _markerPositionController!.addListener(() {
        final t = _markerPositionController!.value;
        final lat = _startLatLng!.latitude + (_targetLatLng!.latitude - _startLatLng!.latitude) * t;
        final lng = _startLatLng!.longitude + (_targetLatLng!.longitude - _startLatLng!.longitude) * t;
        final heading = startHeading + (targetHeadingFinal - startHeading) * t;

        if (mounted) {
          setState(() {
            _animatedBusLatLng = LatLng(lat, lng);
            _animatedHeading = heading;
          });
          _mapController.move(_animatedBusLatLng!, _mapController.camera.zoom);
        }
      });

      _markerPositionController!.forward();
    }
  }

  @override
  void dispose() {
    _lastProvider?.removeListener(_onProviderUpdate);
    _markerPositionController?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liveProvider = context.watch<LiveLocationProvider>();
    final rideProvider = context.watch<RideSessionProvider>();

    final coordStops = widget.bus.routeStops.where((s) => s.hasCoordinates).toList();

    final firstCoordStop = coordStops.isEmpty ? null : coordStops.first;
    final lastCoordStop = coordStops.isEmpty ? null : coordStops.last;
    
    final sourceLatLng = firstCoordStop != null
        ? LatLng(firstCoordStop.latitude!, firstCoordStop.longitude!)
        : null;
    final destLatLng = lastCoordStop != null
        ? LatLng(lastCoordStop.latitude!, lastCoordStop.longitude!)
        : null;

    final busLatLng = _animatedBusLatLng;
    final viewerLatLng = liveProvider.viewerPosition != null
        ? LatLng(liveProvider.viewerPosition!.latitude,
            liveProvider.viewerPosition!.longitude)
        : null;

    final center =
        busLatLng ?? viewerLatLng ?? sourceLatLng ?? const LatLng(22.9, 87.5);

    final isRidingThisBus =
        rideProvider.isActive && rideProvider.activeBusId == widget.bus.id;
    final isRidingAnotherBus =
        rideProvider.isActive && rideProvider.activeBusId != widget.bus.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.bus.name} — Live Map'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isRidingThisBus ? AppColors.staleRed : AppColors.liveGreen,
        icon: Icon(isRidingThisBus
            ? Icons.stop_circle_outlined
            : Icons.directions_bus_filled_outlined),
        label: Text(isRidingThisBus ? 'End Ride' : "I'm On This Bus"),
        onPressed: rideProvider.status == RideSessionStatus.requestingPermission
            ? null
            : () async {
                if (isRidingThisBus) {
                  await rideProvider.endRide();
                } else {
                  if (isRidingAnotherBus) {
                    final confirmed = await _confirmSwitchRide(context);
                    if (confirmed != true) return;
                  }
                  await rideProvider.startRide(widget.bus.id);
                }
              },
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 8),
            children: [
              TileLayer(
                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                userAgentPackageName: 'com.wbsmartbus.app',
              ),
              PolylineLayer(
                polylines: [
                  // Background outline for Google Maps style path
                  Polyline(
                    points: liveProvider.roadRoutePoints.isNotEmpty
                        ? liveProvider.roadRoutePoints
                        : coordStops.map((s) => LatLng(s.latitude!, s.longitude!)).toList(),
                    strokeWidth: 7.5,
                    color: const Color(0xff1558b0),
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                  // Foreground main road path
                  Polyline(
                    points: liveProvider.roadRoutePoints.isNotEmpty
                        ? liveProvider.roadRoutePoints
                        : coordStops.map((s) => LatLng(s.latitude!, s.longitude!)).toList(),
                    strokeWidth: 4.5,
                    color: const Color(0xff1a73e8), // Google Maps route blue
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // Draw markers and labels for all stops on the route
                  ...coordStops.asMap().entries.map((entry) {
                    final index = entry.key;
                    final stop = entry.value;
                    final letterLabel = String.fromCharCode(65 + (index % 26)) + (index >= 26 ? '${(index / 26).floor()}' : '');

                    return Marker(
                      point: LatLng(stop.latitude!, stop.longitude!),
                      width: 150,
                      height: 32,
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '[${letterLabel}] ${stop.stopName} (Stop #${stop.sequence})'
                                '${stop.upTime != null ? ' - Scheduled: ${stop.upTime}' : ''}'
                              ),
                              duration: const Duration(seconds: 3),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xff0f172a), width: 2.5),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 3,
                                    offset: Offset(0, 1.5),
                                  )
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: const BoxDecoration(
                                    color: Color(0xff0f172a),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xeb0f172a),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Colors.white24, width: 1),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfff59e0b),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      letterLabel,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xff0f172a),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      stop.stopName ?? '',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  
                  if (viewerLatLng != null)
                    Marker(
                      point: viewerLatLng,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.person_pin_circle,
                          color: Colors.blue, size: 36),
                    ),
                  if (busLatLng != null)
                    Marker(
                      point: busLatLng,
                      width: 46,
                      height: 46,
                      child: Transform.rotate(
                        angle: _animatedHeading,
                        child: Icon(
                          Icons.navigation,
                          color: liveProvider.resolvedLocation!.isStale
                              ? AppColors.staleRed
                              : AppColors.liveGreen,
                          size: 34,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              elevation: 4,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _statusContent(liveProvider, rideProvider, widget.bus.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmSwitchRide(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch ride?'),
        content: const Text(
          "You're currently sharing location for another bus. Starting a "
          'new ride will end that one first.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch')),
        ],
      ),
    );
  }

  Widget _statusContent(
    LiveLocationProvider liveProvider,
    RideSessionProvider rideProvider,
    String busId,
  ) {
    final children = <Widget>[];

    if (liveProvider.resolvedLocation == null) {
      children.add(const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text('No passengers are currently sharing location for '
                'this bus. Be the first — tap "I\'m On This Bus" below.'),
          ),
        ],
      ));
    } else {
      final loc = liveProvider.resolvedLocation!;
      children.addAll([
        Row(
          children: [
            Icon(Icons.circle,
                size: 10,
                color: loc.isStale ? AppColors.staleRed : AppColors.liveGreen),
            const SizedBox(width: 6),
            Text(loc.isStale ? 'Location may be outdated' : 'Live',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${loc.contributorCount} rider(s) sharing',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Accuracy: ~${loc.accuracyMeters.toStringAsFixed(0)} m '
                '(confidence ${(loc.confidenceScore * 100).round()}%)',
            style: const TextStyle(fontSize: 12)),
        if (loc.speedKmh != null)
          Text('Speed: ${loc.speedKmh!.toStringAsFixed(0)} km/h',
              style: const TextStyle(fontSize: 12)),
      ]);

      if (liveProvider.tripProgress.hasSufficientData) {
        final progress = liveProvider.tripProgress;
        children.add(const SizedBox(height: 6));
        if (progress.tripCompleted) {
          children.add(const Text('Trip completed — arrived at destination.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
        } else {
          if (progress.currentStopName != null) {
            children.add(Text('Near: ${progress.currentStopName}',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.nextStopName != null) {
            children.add(Text('Next stop: ${progress.nextStopName}',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.remainingStopsCount != null) {
            children.add(Text('${progress.remainingStopsCount} stops remaining',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.remainingDistanceKm != null) {
            children.add(Text(
                '~${progress.remainingDistanceKm!.toStringAsFixed(1)} km remaining '
                '(straight-line estimate, not road distance)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)));
          }
          if (progress.etaMinutes != null) {
            children.add(Text('ETA: ~${progress.etaMinutes} min',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
          }
          if (progress.delayMinutes != null) {
            final d = progress.delayMinutes!;
            final label = d > 0
                ? 'Running ~$d min late'
                : (d < 0 ? 'Running ~${-d} min early' : 'On schedule');
            children.add(Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: d > 5 ? AppColors.staleRed : Colors.grey.shade700)));
          }
        }
      }
    }

    if (rideProvider.isActive && rideProvider.activeBusId == busId) {
      children.add(const Divider(height: 16));
      children.add(Row(
        children: const [
          Icon(Icons.wifi_tethering, color: AppColors.liveGreen, size: 18),
          SizedBox(width: 6),
          Text('You are sharing your location for this bus',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ));
    }

    if (rideProvider.errorMessage != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(rideProvider.errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
