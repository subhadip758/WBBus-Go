/// A single raw GPS fix contributed by one passenger currently riding
/// a bus. Many of these can exist concurrently for the same busId —
/// [ResolveLiveLocationUseCase] is what turns a list of these into one
/// trusted "current location" for the bus.
class RideContribution {
  /// Equal to the contributing device's Firebase Anonymous Auth UID.
  /// Firestore rules enforce that a client can only write the
  /// contribution document matching their own UID, which is the only
  /// practical spoofing protection available without requiring
  /// verified driver accounts.
  final String sessionId;
  final String busId;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double? speedKmh;
  final double? headingDegrees;
  final DateTime updatedAt;

  const RideContribution({
    required this.sessionId,
    required this.busId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.speedKmh,
    this.headingDegrees,
    required this.updatedAt,
  });

  bool get isStale =>
      DateTime.now().difference(updatedAt) > const Duration(seconds: 90);
}
