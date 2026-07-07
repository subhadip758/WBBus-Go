import '../../core/utils/geo_utils.dart';
import '../entities/bus.dart';
import '../entities/live_location.dart';
import '../entities/route_stop.dart';
import '../entities/trip_progress.dart';

/// Computes current/next stop, remaining stops/distance, ETA, delay,
/// and trip completion from a resolved live location plus the bus's
/// route stops. Pure and unit-testable — no Firebase/Flutter imports.
///
/// Honesty constraints this class follows:
/// - Distances are straight-line (haversine), not road-following —
///   see GeoUtils for why, and the README for how to upgrade this
///   once a routing API is available.
/// - ETA falls back to an assumed average speed only when the live
///   GPS speed reading is missing or implausible for a bus (outside
///   10-80 km/h); this assumption is a documented approximation, not
///   a measured fact.
/// - Delay is only computed when the nearest stop actually has a
///   scheduled up_time in the source data — no interpolated/guessed
///   schedule times are used.
class CalculateTripProgressUseCase {
  static const double _assumedAverageSpeedKmh = 30.0;
  static const double _minPlausibleSpeedKmh = 10.0;
  static const double _maxPlausibleSpeedKmh = 80.0;
  static const double _tripCompletionRadiusKm = 0.3;

  TripProgress call(Bus bus, LiveLocation location) {
    final stopsWithCoords =
        bus.routeStops.where((s) => s.hasCoordinates).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence));

    if (stopsWithCoords.length < 2) {
      return const TripProgress.insufficientData();
    }

    // Find nearest stop-with-coordinates to the live position.
    RouteStop nearest = stopsWithCoords.first;
    double nearestDistKm = GeoUtils.haversineKm(
      location.latitude,
      location.longitude,
      nearest.latitude!,
      nearest.longitude!,
    );
    for (final stop in stopsWithCoords.skip(1)) {
      final d = GeoUtils.haversineKm(
        location.latitude,
        location.longitude,
        stop.latitude!,
        stop.longitude!,
      );
      if (d < nearestDistKm) {
        nearest = stop;
        nearestDistKm = d;
      }
    }

    final nearestIndex = stopsWithCoords.indexOf(nearest);
    final isLastCoordStop = nearestIndex == stopsWithCoords.length - 1;

    // Trip completion: at/near the final stop of the route (by
    // sequence, not just the last one with coordinates) and close by.
    final finalStop =
        bus.routeStops.reduce((a, b) => a.sequence > b.sequence ? a : b);
    final tripCompleted = nearest.sequence == finalStop.sequence &&
        nearestDistKm <= _tripCompletionRadiusKm;

    final nextStop = isLastCoordStop ? null : stopsWithCoords[nearestIndex + 1];

    final remainingStopsCount = bus.routeStops
        .where((s) => s.sequence > nearest.sequence)
        .length;

    // Remaining distance: from current position to the nearest stop,
    // then hop-by-hop through every subsequent coordinate-bearing
    // stop. If the last coordinate-bearing stop isn't actually the
    // route's final stop, the true remaining distance is understated —
    // flagged via hasSufficientData staying true but the caller should
    // treat this as a floor, not an exact figure, when
    // stopsWithCoords.last != finalStop.
    double remainingDistanceKm = nearestDistKm;
    for (var i = nearestIndex; i < stopsWithCoords.length - 1; i++) {
      remainingDistanceKm += GeoUtils.haversineKm(
        stopsWithCoords[i].latitude!,
        stopsWithCoords[i].longitude!,
        stopsWithCoords[i + 1].latitude!,
        stopsWithCoords[i + 1].longitude!,
      );
    }

    final speedForEta =
        (location.speedKmh != null &&
                location.speedKmh! >= _minPlausibleSpeedKmh &&
                location.speedKmh! <= _maxPlausibleSpeedKmh)
            ? location.speedKmh!
            : _assumedAverageSpeedKmh;

    final etaMinutes = tripCompleted
        ? 0
        : ((remainingDistanceKm / speedForEta) * 60).round();

    final delayMinutes = _computeDelayMinutes(nearest, location.updatedAt);

    return TripProgress(
      hasSufficientData: true,
      currentStopName: nearest.stopName,
      nextStopName: nextStop?.stopName,
      remainingStopsCount: remainingStopsCount,
      remainingDistanceKm: remainingDistanceKm,
      etaMinutes: etaMinutes,
      delayMinutes: delayMinutes,
      tripCompleted: tripCompleted,
    );
  }

  int? _computeDelayMinutes(RouteStop nearest, DateTime observedAt) {
    final scheduled = nearest.upTime;
    if (scheduled == null) return null;
    final parts = scheduled.split(':');
    if (parts.length != 2) return null;
    final schedH = int.tryParse(parts[0]);
    final schedM = int.tryParse(parts[1]);
    if (schedH == null || schedM == null) return null;

    final scheduledMinutes = schedH * 60 + schedM;
    final actualMinutes = observedAt.hour * 60 + observedAt.minute;
    return actualMinutes - scheduledMinutes;
  }
}
