import '../../domain/entities/bus.dart';
import '../../domain/entities/route_stop.dart';

/// Raw per-bus fields as they appear in buses.json (before route/stop
/// joining). [BusLocalDataSource] combines this with RouteModel +
/// TimetableEntryModel + StopModel to produce a fully hydrated [Bus].
class BusModel {
  final String busId;
  final String busName;
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

  const BusModel({
    required this.busId,
    required this.busName,
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
  });

  factory BusModel.fromJson(Map<String, dynamic> json) => BusModel(
        busId: json['bus_id'] as String,
        busName: json['bus_name'] as String,
        alternateName: json['alternate_name'] as String?,
        registrationNumber: json['registration_number'] as String?,
        agency: json['agency'] as String?,
        operator: json['operator'] as String? ?? json['bus_name'] as String,
        busType: json['bus_type'] as String?,
        contactNumber: json['contact_number'] as String?,
        alternateNumber: json['alternate_number'] as String?,
        source: json['source'] as String,
        destination: json['destination'] as String,
        routeId: json['route_id'] as String,
      );

  Bus toEntity(List<RouteStop> routeStops) => Bus(
        id: busId,
        name: busName,
        alternateName: alternateName,
        registrationNumber: registrationNumber,
        agency: agency,
        operator: operator,
        busType: busType,
        contactNumber: contactNumber,
        alternateNumber: alternateNumber,
        source: source,
        destination: destination,
        routeId: routeId,
        routeStops: routeStops,
      );
}
