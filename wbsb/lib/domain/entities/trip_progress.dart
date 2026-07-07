/// Computed, on-device trip progress for a bus currently being
/// tracked. Every field can be null/false when the underlying route's
/// stop coordinates aren't rich enough to compute it — this is
/// reported honestly via [hasSufficientData] rather than silently
/// showing a guessed value.
class TripProgress {
  final bool hasSufficientData;
  final String? currentStopName;
  final String? nextStopName;
  final int? remainingStopsCount;
  final double? remainingDistanceKm;
  final int? etaMinutes;
  final int? delayMinutes; // positive = running late, negative = early
  final bool tripCompleted;

  const TripProgress({
    required this.hasSufficientData,
    required this.currentStopName,
    required this.nextStopName,
    required this.remainingStopsCount,
    required this.remainingDistanceKm,
    required this.etaMinutes,
    required this.delayMinutes,
    required this.tripCompleted,
  });

  const TripProgress.insufficientData()
      : hasSufficientData = false,
        currentStopName = null,
        nextStopName = null,
        remainingStopsCount = null,
        remainingDistanceKm = null,
        etaMinutes = null,
        delayMinutes = null,
        tripCompleted = false;
}
