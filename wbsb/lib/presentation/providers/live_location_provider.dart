import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
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

  LiveLocationProvider(
    this._repository,
    this._bus, {
    ResolveLiveLocationUseCase? resolver,
    CalculateTripProgressUseCase? progressCalculator,
  })  : _resolve = resolver ?? ResolveLiveLocationUseCase(),
        _calculateProgress = progressCalculator ?? CalculateTripProgressUseCase();

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
