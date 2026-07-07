/// A single stop within a bus's route, in scheduled order.
/// stopName/latitude/longitude may be null if that stop's identity or
/// coordinates could not be confidently read from source material —
/// this is recorded honestly rather than guessed (see routes.json
/// data_quality_notes for exactly which entries this applies to).
class RouteStop {
  final int sequence;
  final String? stopId;
  final String? stopName;
  final double? latitude;
  final double? longitude;
  final String? upTime; // 24hr "HH:mm", null if not known
  final String? downTime;

  const RouteStop({
    required this.sequence,
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required this.upTime,
    required this.downTime,
  });

  bool get hasCoordinates => latitude != null && longitude != null;
}
