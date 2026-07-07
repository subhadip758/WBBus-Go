/// The resolved, trusted "current position" for a bus, computed by
/// ResolveLiveLocationUseCase from one or more real passenger GPS
/// contributions via confidence-weighted averaging. This is never
/// itself written to Firestore — it's derived on-device from the raw
/// contribution stream.
class LiveLocation {
  final String busId;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? speedKmh;
  final double? headingDegrees;
  final DateTime updatedAt;

  /// How many valid (non-stale, accurate-enough) contributors fed into
  /// this resolved position overall.
  final int contributorCount;

  /// How many of those contributors were close enough together to be
  /// included in the weighted-average calculation (outliers — e.g. a
  /// stray fix from a different part of a long bus, or a bad GPS
  /// bounce — are excluded from the average but still counted above).
  final int clusteredContributorCount;

  /// 0.0-1.0 confidence in this resolved position: higher with more
  /// clustered contributors and better accuracy among them.
  final double confidenceScore;

  const LiveLocation({
    required this.busId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.speedKmh,
    this.headingDegrees,
    required this.updatedAt,
    required this.contributorCount,
    required this.clusteredContributorCount,
    required this.confidenceScore,
  });

  bool get isStale =>
      DateTime.now().difference(updatedAt) > const Duration(seconds: 90);
}
