import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/ride_contribution.dart';
import '../../domain/repositories/ride_tracking_repository.dart';
import '../datasources/ride_tracking_remote_datasource.dart';

class RideTrackingRepositoryImpl implements RideTrackingRepository {
  final RideTrackingRemoteDataSource _remote;

  RideTrackingRepositoryImpl(this._remote);

  @override
  Stream<List<RideContribution>> watchContributions(String busId) =>
      _remote.watchContributions(busId);

  @override
  Future<void> pushContribution({
    required String busId,
    required String sessionId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    double? speedKmh,
    double? headingDegrees,
  }) {
    return _remote.pushContribution(busId, sessionId, {
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'speedKmh': speedKmh,
      'headingDegrees': headingDegrees,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> endRide({required String busId, required String sessionId}) {
    return _remote.endRide(busId, sessionId);
  }
}
