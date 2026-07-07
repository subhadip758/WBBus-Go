class OperatorModel {
  final String operatorId;
  final String name;

  const OperatorModel({required this.operatorId, required this.name});

  factory OperatorModel.fromJson(Map<String, dynamic> json) => OperatorModel(
        operatorId: json['operator_id'] as String,
        name: json['name'] as String,
      );
}
