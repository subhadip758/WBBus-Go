import '../entities/bus.dart';

abstract class BusRepository {
  /// Loads the full generated dataset (bundled assets, Hive-cached for
  /// offline use), fully joined: each Bus carries its ordered,
  /// timed, coordinate-annotated route stops.
  Future<List<Bus>> getAllBuses();

  /// Route search: matches [from] against source and [to] against
  /// destination, case-insensitive/partial/typo-tolerant.
  Future<List<Bus>> search({String? from, String? to});

  /// General search across bus name, alternate name, registration
  /// number, operator, agency, source, destination, and every
  /// intermediate stop name — case-insensitive/partial/typo-tolerant.
  Future<List<Bus>> searchByQuery(String query);

  Future<Bus?> getById(String id);
}
