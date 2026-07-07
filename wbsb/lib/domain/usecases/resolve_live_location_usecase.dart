import 'dart:math' as math;

import '../../core/constants/tracking_constants.dart';
import '../../core/utils/geo_utils.dart';
import '../entities/live_location.dart';
import '../entities/ride_contribution.dart';

/// Turns the raw, possibly-noisy set of passenger GPS contributions
/// for a bus into a single trusted [LiveLocation], or null if none of
/// the current contributions are trustworthy enough to use.
///
/// Pipeline:
/// 1. Drop contributions older than [TrackingConstants.staleContributionAge]
///    ("stale GPS removal").
/// 2. Drop contributions less accurate than
///    [TrackingConstants.minAcceptableAccuracyMeters] ("accuracy filtering").
/// 3. Drop contributions reporting a physically implausible speed for
///    a road vehicle ("speed validation") — a common signature of a
///    corrupted or spoofed fix.
/// 4. Among what's left, find the largest cluster of contributions
///    that are close enough together to plausibly be describing the
///    same physical bus, and combine them with inverse-variance
///    weighted averaging (weight = 1/accuracy²) — the statistically
///    correct way to combine independent noisy measurements of one
///    true position, and a real implementation of "weighted averaging
///    with minimum active users" (minimum 2 clustered contributors).
/// 5. If contributions disagree too much to cluster (implying they
///    aren't all the same bus, or one is bad data), averaging is
///    skipped in favor of the single most recent accurate fix —
///    averaging genuinely different positions would place the bus on
///    nobody's actual path, which is worse than one real fix.
/// 6. A 0.0-1.0 confidence score is derived from cluster size and
///    accuracy, for the UI to show passengers directly.
class ResolveLiveLocationUseCase {
  /// Contributions within this distance of each other are treated as
  /// plausibly describing the same physical bus.
  static const double clusterRadiusMeters = 250;

  /// A road vehicle in West Bengal traffic won't realistically exceed
  /// this — used to reject a corrupted/spoofed fix.
  static const double maxPlausibleSpeedKmh = 130;

  LiveLocation? call(String busId, List<RideContribution> contributions) {
    final now = DateTime.now();

    final fresh = contributions
        .where((c) =>
            now.difference(c.updatedAt) <= TrackingConstants.staleContributionAge)
        .toList();

    final accurateEnough = fresh
        .where((c) =>
            c.accuracyMeters <= TrackingConstants.minAcceptableAccuracyMeters)
        .toList();

    final speedValid = accurateEnough
        .where((c) => c.speedKmh == null || c.speedKmh! <= maxPlausibleSpeedKmh)
        .toList();

    if (speedValid.isEmpty) return null;

    final cluster = _largestCluster(speedValid);

    if (cluster.length >= 2) {
      final averaged = _weightedAverageLatLng(cluster);
      final combinedAccuracy = _combinedAccuracyMeters(cluster);
      return LiveLocation(
        busId: busId,
        latitude: averaged.$1,
        longitude: averaged.$2,
        accuracyMeters: combinedAccuracy,
        speedKmh: _averageOf(cluster.map((c) => c.speedKmh)),
        headingDegrees: _averageOf(cluster.map((c) => c.headingDegrees)),
        updatedAt:
            cluster.map((c) => c.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b),
        contributorCount: speedValid.length,
        clusteredContributorCount: cluster.length,
        confidenceScore: _confidenceScore(cluster.length, combinedAccuracy),
      );
    }

    // No agreeing cluster of 2+ — fall back to the single most recent
    // accurate fix rather than guessing which contributor is "right".
    final sorted = [...speedValid]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final best = sorted.first;
    return LiveLocation(
      busId: busId,
      latitude: best.latitude,
      longitude: best.longitude,
      accuracyMeters: best.accuracyMeters,
      speedKmh: best.speedKmh,
      headingDegrees: best.headingDegrees,
      updatedAt: best.updatedAt,
      contributorCount: speedValid.length,
      clusteredContributorCount: 1,
      confidenceScore: _confidenceScore(1, best.accuracyMeters),
    );
  }

  /// Greedy clustering: for each contribution, count how many others
  /// fall within [clusterRadiusMeters] of it, and keep the largest
  /// such group. Sufficient for the handful of concurrent riders
  /// expected on a single bus.
  List<RideContribution> _largestCluster(List<RideContribution> pool) {
    List<RideContribution> best = [];
    for (final seed in pool) {
      final group = pool.where((c) {
        final distKm = GeoUtils.haversineKm(
            seed.latitude, seed.longitude, c.latitude, c.longitude);
        return distKm * 1000 <= clusterRadiusMeters;
      }).toList();
      if (group.length > best.length) best = group;
    }
    return best;
  }

  (double, double) _weightedAverageLatLng(List<RideContribution> cluster) {
    double sumLatW = 0, sumLngW = 0, sumW = 0;
    for (final c in cluster) {
      final w = 1 / (c.accuracyMeters * c.accuracyMeters);
      sumLatW += c.latitude * w;
      sumLngW += c.longitude * w;
      sumW += w;
    }
    return (sumLatW / sumW, sumLngW / sumW);
  }

  /// Standard error propagation for an inverse-variance-weighted
  /// average: combined variance = 1 / sum(1/variance_i).
  double _combinedAccuracyMeters(List<RideContribution> cluster) {
    double sumInverseVariance = 0;
    for (final c in cluster) {
      sumInverseVariance += 1 / (c.accuracyMeters * c.accuracyMeters);
    }
    if (sumInverseVariance <= 0) return cluster.first.accuracyMeters;
    return math.sqrt(1 / sumInverseVariance);
  }

  double? _averageOf(Iterable<double?> values) {
    final nonNull = values.whereType<double>().toList();
    if (nonNull.isEmpty) return null;
    return nonNull.reduce((a, b) => a + b) / nonNull.length;
  }

  /// Simple, documented confidence heuristic: starts from an
  /// accuracy-based score (1.0 at 0m error, 0.0 at
  /// minAcceptableAccuracyMeters or worse), then boosted by how many
  /// contributors agreed, capped at 1.0.
  double _confidenceScore(int clusterSize, double accuracyMeters) {
    final accuracyScore = (1 -
            (accuracyMeters / TrackingConstants.minAcceptableAccuracyMeters))
        .clamp(0.0, 1.0);
    final agreementBoost = (clusterSize - 1) * 0.15;
    return (accuracyScore + agreementBoost).clamp(0.0, 1.0);
  }
}
