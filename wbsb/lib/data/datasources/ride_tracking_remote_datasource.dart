import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ride_contribution_model.dart';

/// Talks to `ride_sessions/{busId}/active/{sessionId}` in Firestore.
/// Every document here is a real, currently-active passenger
/// contribution — there is no synthetic or simulated data path.
class RideTrackingRemoteDataSource {
  final FirebaseFirestore _firestore;

  RideTrackingRemoteDataSource({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _activeCollection(String busId) =>
      _firestore.collection('ride_sessions').doc(busId).collection('active');

  Stream<List<RideContributionModel>> watchContributions(String busId) {
    return _activeCollection(busId).snapshots().map((snap) {
      return snap.docs
          .map((doc) =>
              RideContributionModel.fromFirestore(busId, doc.id, doc.data()))
          .toList();
    });
  }

  Future<void> pushContribution(
    String busId,
    String sessionId,
    Map<String, dynamic> data,
  ) async {
    await _activeCollection(busId)
        .doc(sessionId)
        .set(data, SetOptions(merge: true));
  }

  Future<void> endRide(String busId, String sessionId) async {
    await _activeCollection(busId).doc(sessionId).delete();
  }
}
