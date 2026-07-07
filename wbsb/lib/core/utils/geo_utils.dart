import 'dart:math' as math;

/// Great-circle (straight-line) distance helpers. These are explicitly
/// NOT road-following distances — computing real road distance/ETA
/// requires a routing engine (OSRM/GraphHopper) which needs network
/// access this environment does not have. Straight-line distance is
/// used as a documented, honest approximation; swap in a real routing
/// API call at the marked extension point once you have connectivity
/// (see README).
class GeoUtils {
  static const double _earthRadiusKm = 6371.0;

  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
}
