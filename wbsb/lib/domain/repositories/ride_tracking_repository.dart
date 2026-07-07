import '../entities/ride_contribution.dart';

abstract class RideTrackingRepository {
  /// Real-time stream of every currently-active passenger contribution
  /// for [busId]. Empty list means nobody is currently riding with the
  /// app open and location sharing on — that is a normal, honest state,
  /// not an error.
  Stream<List<RideContribution>> watchContributions(String busId);

  /// Called repeatedly (every 5-10s or on significant movement) while
  /// a passenger has an active ride. [sessionId] must equal the
  /// caller's Firebase Auth UID — enforced by Firestore rules.
  Future<void> pushContribution({
    required String busId,
    required String sessionId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    double? speedKmh,
    double? headingDegrees,
  });

  /// Called when the passenger taps "End Ride", or automatically if
  /// the app is disposing the session. Removes the contribution
  /// document immediately so stale data never lingers.
  Future<void> endRide({required String busId, required String sessionId});
}
