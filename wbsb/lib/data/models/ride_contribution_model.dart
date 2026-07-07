import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/ride_contribution.dart';

class RideContributionModel extends RideContribution {
  const RideContributionModel({
    required super.sessionId,
    required super.busId,
    required super.latitude,
    required super.longitude,
    required super.accuracyMeters,
    super.speedKmh,
    super.headingDegrees,
    required super.updatedAt,
  });

  factory RideContributionModel.fromFirestore(
    String busId,
    String sessionId,
    Map<String, dynamic> data,
  ) {
    final ts = data['updatedAt'];
    final DateTime updatedAt = ts is Timestamp
        ? ts.toDate()
        : DateTime.now(); // server timestamp not yet resolved locally

    return RideContributionModel(
      sessionId: sessionId,
      busId: busId,
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      accuracyMeters: (data['accuracyMeters'] as num).toDouble(),
      speedKmh: (data['speedKmh'] as num?)?.toDouble(),
      headingDegrees: (data['headingDegrees'] as num?)?.toDouble(),
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'speedKmh': speedKmh,
        'headingDegrees': headingDegrees,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
