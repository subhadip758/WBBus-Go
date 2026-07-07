class AgencyModel {
  final String agencyId;
  final String name;

  const AgencyModel({required this.agencyId, required this.name});

  factory AgencyModel.fromJson(Map<String, dynamic> json) => AgencyModel(
        agencyId: json['agency_id'] as String,
        name: json['name'] as String,
      );
}
