import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/constants/tracking_constants.dart';
import '../../domain/repositories/ride_tracking_repository.dart';

enum RideSessionStatus { idle, requestingPermission, active, error }

/// Drives the "I'm On This Bus" / "End Ride" flow for the passenger
/// using this device. While active, it reads this device's real GPS
/// (via Geolocator) and pushes fixes to Firestore — there is no
/// simulated location anywhere in this class.
///
/// A device can only have one active ride at a time; starting a new
/// one automatically ends any previous session first.
class RideSessionProvider extends ChangeNotifier {
  final RideTrackingRepository _repository;
  final String sessionId; // == FirebaseAuth anonymous UID

  RideSessionProvider(this._repository, {required this.sessionId});

  RideSessionStatus status = RideSessionStatus.idle;
  String? activeBusId;
  String? errorMessage;
  Position? lastPushedPosition;
  DateTime? lastPushedAt;

  StreamSubscription<Position>? _positionSub;
  Timer? _fallbackTimer;
  Position? _latestKnownPosition;

  bool get isActive => status == RideSessionStatus.active;

  Future<void> startRide(String busId) async {
    if (activeBusId != null) {
      await endRide();
    }

    status = RideSessionStatus.requestingPermission;
    errorMessage = null;
    notifyListeners();

    final permissionOk = await _ensurePermission();
    if (!permissionOk) {
      status = RideSessionStatus.error;
      errorMessage =
          'Location permission is required to share your position with '
          'other passengers.';
      notifyListeners();
      return;
    }

    activeBusId = busId;
    status = RideSessionStatus.active;
    notifyListeners();

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: TrackingConstants.distanceFilterMeters.toInt(),
      ),
    ).listen(
      (position) {
        _latestKnownPosition = position;
        _maybePush(position);
      },
      onError: (e) {
        errorMessage = 'GPS error: $e';
        notifyListeners();
      },
    );

    // Guarantees a push at least every [maxPushInterval] even if the
    // device hasn't moved far enough to trigger the distance filter,
    // so the "last updated" timestamp other passengers see stays fresh.
    _fallbackTimer = Timer.periodic(TrackingConstants.maxPushInterval, (_) {
      if (_latestKnownPosition != null) {
        _push(_latestKnownPosition!, force: true);
      }
    });
  }

  void _maybePush(Position position) {
    final dueForPush = lastPushedAt == null ||
        DateTime.now().difference(lastPushedAt!) >=
            TrackingConstants.maxPushInterval;
    _push(position, force: dueForPush);
  }

  Future<void> _push(Position position, {required bool force}) async {
    if (activeBusId == null) return;

    // Never contribute a fix worse than the minimum acceptable
    // accuracy — a bad fix helps nobody and only adds noise for the
    // resolution logic on other passengers' devices.
    if (position.accuracy > TrackingConstants.minAcceptableAccuracyMeters &&
        !force) {
      return;
    }

    try {
      await _repository.pushContribution(
        busId: activeBusId!,
        sessionId: sessionId,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        speedKmh: position.speed * 3.6,
        headingDegrees: position.heading,
      );
      lastPushedPosition = position;
      lastPushedAt = DateTime.now();
      notifyListeners();
    } catch (e) {
      errorMessage = 'Could not sync location: $e';
      notifyListeners();
    }
  }

  Future<void> endRide() async {
    final busId = activeBusId;
    await _positionSub?.cancel();
    _positionSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    if (busId != null) {
      try {
        await _repository.endRide(busId: busId, sessionId: sessionId);
      } catch (e) {
        errorMessage = 'Could not clear your ride session cleanly: $e';
      }
    }

    activeBusId = null;
    status = RideSessionStatus.idle;
    lastPushedPosition = null;
    lastPushedAt = null;
    _latestKnownPosition = null;
    notifyListeners();
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
    _positionSub?.cancel();
    _fallbackTimer?.cancel();
    super.dispose();
  }
}
