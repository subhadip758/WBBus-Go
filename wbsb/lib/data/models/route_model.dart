class RouteModel {
  final String routeId;
  final String routeName;
  final String source;
  final String destination;
  final double? estimatedDistanceKm;
  final int? estimatedTravelTimeMin;
  /// Ordered stop IDs; entries may be null where the source scan was
  /// illegible at that position (see data_quality_notes in routes.json).
  final List<String?> stopSequence;
  final List<String> dataQualityNotes;

  const RouteModel({
    required this.routeId,
    required this.routeName,
    required this.source,
    required this.destination,
    required this.estimatedDistanceKm,
    required this.estimatedTravelTimeMin,
    required this.stopSequence,
    required this.dataQualityNotes,
  });

  factory RouteModel.fromJson(Map<String, dynamic> json) => RouteModel(
        routeId: json['route_id'] as String,
        routeName: json['route_name'] as String,
        source: json['source'] as String,
        destination: json['destination'] as String,
        estimatedDistanceKm: (json['estimated_distance_km'] as num?)?.toDouble(),
        estimatedTravelTimeMin: (json['estimated_travel_time_min'] as num?)?.toInt(),
        stopSequence: (json['stop_sequence'] as List<dynamic>)
            .map((e) => e as String?)
            .toList(),
        dataQualityNotes: (json['data_quality_notes'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}
