class TimetableEntryModel {
  final String busId;
  final String? stopId;
  final int sequence;
  final String? upTime;
  final String? downTime;

  const TimetableEntryModel({
    required this.busId,
    required this.stopId,
    required this.sequence,
    required this.upTime,
    required this.downTime,
  });

  factory TimetableEntryModel.fromJson(Map<String, dynamic> json) =>
      TimetableEntryModel(
        busId: json['bus_id'] as String,
        stopId: json['stop_id'] as String?,
        sequence: (json['sequence'] as num).toInt(),
        upTime: json['up_time'] as String?,
        downTime: json['down_time'] as String?,
      );
}
