class StopModel {
  final String stopId;
  final String stopName;
  final double? latitude;
  final double? longitude;

  const StopModel({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  factory StopModel.fromJson(Map<String, dynamic> json) => StopModel(
        stopId: json['stop_id'] as String,
        stopName: json['stop_name'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
