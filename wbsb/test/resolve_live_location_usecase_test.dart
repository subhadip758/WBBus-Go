import 'package:flutter_test/flutter_test.dart';
import 'package:west_bengal_smart_bus/domain/entities/ride_contribution.dart';
import 'package:west_bengal_smart_bus/domain/usecases/resolve_live_location_usecase.dart';

void main() {
  final resolver = ResolveLiveLocationUseCase();
  const busId = 'bus_1';

  RideContribution fix({
    required String sessionId,
    double accuracy = 10,
    Duration age = Duration.zero,
    double lat = 22.5,
    double lng = 88.3,
    double? speedKmh,
  }) {
    return RideContribution(
      sessionId: sessionId,
      busId: busId,
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      speedKmh: speedKmh,
      updatedAt: DateTime.now().subtract(age),
    );
  }

  test('returns null when there are no contributions', () {
    expect(resolver(busId, []), isNull);
  });

  test('returns null when every contribution is stale', () {
    final result = resolver(busId, [
      fix(sessionId: 'a', age: const Duration(minutes: 5)),
    ]);
    expect(result, isNull);
  });

  test('returns null when every contribution is too inaccurate', () {
    final result = resolver(busId, [fix(sessionId: 'a', accuracy: 500)]);
    expect(result, isNull);
  });

  test('discards a fix reporting an implausible speed for a bus', () {
    final result = resolver(busId, [
      fix(sessionId: 'a', speedKmh: 300),
    ]);
    expect(result, isNull);
  });

  test('single accurate fix resolves with clusteredContributorCount 1', () {
    final result = resolver(busId, [fix(sessionId: 'a', accuracy: 10)]);
    expect(result, isNotNull);
    expect(result!.clusteredContributorCount, 1);
    expect(result.contributorCount, 1);
  });

  test('two nearby accurate fixes are weighted-averaged together', () {
    final a = fix(sessionId: 'a', accuracy: 10, lat: 22.5000, lng: 88.3000);
    final b = fix(sessionId: 'b', accuracy: 10, lat: 22.5001, lng: 88.3001);
    final result = resolver(busId, [a, b]);
    expect(result, isNotNull);
    expect(result!.clusteredContributorCount, 2);
    // Averaged point should land strictly between the two inputs.
    expect(result.latitude, greaterThan(22.5000));
    expect(result.latitude, lessThan(22.5001));
  });

  test('a far-away outlier is excluded from the average, not blended in', () {
    final a = fix(sessionId: 'a', accuracy: 10, lat: 22.5000, lng: 88.3000);
    final b = fix(sessionId: 'b', accuracy: 10, lat: 22.5001, lng: 88.3001);
    final outlier = fix(sessionId: 'c', accuracy: 10, lat: 25.0, lng: 90.0);
    final result = resolver(busId, [a, b, outlier]);
    expect(result, isNotNull);
    // Cluster should be the two nearby fixes; outlier counted overall
    // (it's accurate enough) but not blended into the resolved position.
    expect(result!.clusteredContributorCount, 2);
    expect(result.contributorCount, 3);
    expect(result.latitude, lessThan(23.0));
  });

  test('more accurate contributors yield a smaller combined accuracy value',
      () {
    final onePrecise = resolver(busId, [fix(sessionId: 'a', accuracy: 5)]);
    final twoPrecise = resolver(busId, [
      fix(sessionId: 'a', accuracy: 5, lat: 22.5000, lng: 88.3000),
      fix(sessionId: 'b', accuracy: 5, lat: 22.5000, lng: 88.3000),
    ]);
    expect(twoPrecise!.accuracyMeters, lessThan(onePrecise!.accuracyMeters));
  });

  test('confidenceScore increases with more agreeing, accurate contributors',
      () {
    final single = resolver(busId, [fix(sessionId: 'a', accuracy: 10)]);
    final agreeing = resolver(busId, [
      fix(sessionId: 'a', accuracy: 10, lat: 22.5000, lng: 88.3000),
      fix(sessionId: 'b', accuracy: 10, lat: 22.5000, lng: 88.3000),
      fix(sessionId: 'c', accuracy: 10, lat: 22.5000, lng: 88.3000),
    ]);
    expect(agreeing!.confidenceScore, greaterThan(single!.confidenceScore));
  });
}
