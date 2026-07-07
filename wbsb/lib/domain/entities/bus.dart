import 'route_stop.dart';

/// Core domain entity for a single scheduled bus service, fully
/// hydrated with its ordered route stops (joined from routes.json +
/// timetable.json + stops.json at load time — see BusLocalDataSource).
class Bus {
  final String id;
  final String name;
  final String? alternateName;
  final String? registrationNumber;
  final String? agency;
  final String operator;
  final String? busType;
  final String? contactNumber;
  final String? alternateNumber;
  final String source;
  final String destination;
  final String routeId;
  final List<RouteStop> routeStops;

  const Bus({
    required this.id,
    required this.name,
    required this.alternateName,
    required this.registrationNumber,
    required this.agency,
    required this.operator,
    required this.busType,
    required this.contactNumber,
    required this.alternateNumber,
    required this.source,
    required this.destination,
    required this.routeId,
    required this.routeStops,
  });

  String? get departureTime =>
      routeStops.isNotEmpty ? routeStops.first.upTime : null;

  /// IMPORTANT: "up_time" is this bus's own direction of travel for
  /// every route in the dataset — confirmed because it is the column
  /// consistently populated at each route's first stop (matching that
  /// bus's known departure). "down_time" represents the paired
  /// reverse-direction working over the same physical stops, not this
  /// bus's own schedule, so it must NOT be used for this bus's arrival.
  String? get arrivalTime =>
      routeStops.isNotEmpty ? routeStops.last.upTime : null;

  /// Text blob used for fuzzy search matching — covers everything a
  /// passenger might reasonably search by, including intermediate stops.
  String get searchBlob {
    final stopNames = routeStops
        .map((s) => s.stopName)
        .whereType<String>()
        .join(' ');
    return '$name ${alternateName ?? ''} $operator ${agency ?? ''} '
            '${registrationNumber ?? ''} $source $destination $stopNames'
        .toLowerCase();
  }
}
