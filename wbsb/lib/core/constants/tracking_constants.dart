/// Tunable thresholds for the crowdsourced tracking pipeline.
/// Centralized here so the filtering behavior is documented in one
/// place instead of scattered magic numbers.
class TrackingConstants {
  /// GPS fixes worse than this accuracy (meters) are never even sent
  /// to Firestore — no point paying a write for a useless fix.
  static const double minAcceptableAccuracyMeters = 75;

  /// When resolving the bus's current live location from all active
  /// contributors, prefer fixes at least this accurate if any exist.
  static const double preferredAccuracyMeters = 30;

  /// A contribution older than this is considered stale and excluded
  /// from resolution entirely (its contributor likely lost signal,
  /// backgrounded the app, or forgot to end their ride).
  static const Duration staleContributionAge = Duration(seconds: 90);

  /// Passenger GPS stream: only push on the network when the device
  /// has moved at least this far...
  static const double distanceFilterMeters = 15;

  /// ...but never let more than this much time pass without a push,
  /// even if the device hasn't moved (keeps the "last updated" clock
  /// meaningfully fresh for passengers watching the map).
  static const Duration maxPushInterval = Duration(seconds: 9);

  /// A ride session with no successful push in this long is treated
  /// as abandoned and cleaned up client-side on next read.
  static const Duration abandonedSessionAge = Duration(minutes: 5);

  /// When averaging multiple riders' contributions for the same bus,
  /// only fixes within this radius of the anchor fix are pooled
  /// together — riders far outside this radius are treated as noise
  /// (stale data from someone who already got off, or a different bus
  /// entirely) rather than pulled into the average.
  static const double clusterRadiusMeters = 250;

  /// A reported instantaneous speed above this is treated as a GPS
  /// glitch and the fix is discarded outright. West Bengal inter-city
  /// buses do not exceed this on any road in the dataset.
  static const double maxPlausibleSpeedKmh = 140;
}
