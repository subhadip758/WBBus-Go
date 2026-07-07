import '../../core/utils/text_match.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/bus_repository.dart';
import '../datasources/bus_local_datasource.dart';

class BusRepositoryImpl implements BusRepository {
  final BusLocalDataSource _localDataSource;

  BusRepositoryImpl(this._localDataSource);

  @override
  Future<List<Bus>> getAllBuses() async {
    final hydrated = await _localDataSource.loadAllHydrated();
    return hydrated.map((h) => h.model.toEntity(h.routeStops)).toList();
  }

  @override
  Future<Bus?> getById(String id) async {
    final all = await getAllBuses();
    for (final b in all) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Future<List<Bus>> search({String? from, String? to}) async {
    final all = await getAllBuses();
    return all.where((bus) {
      if (from != null && from.trim().isNotEmpty) {
        if (!TextMatch.fuzzyContains(bus.source, from)) return false;
      }
      if (to != null && to.trim().isNotEmpty) {
        if (!TextMatch.fuzzyContains(bus.destination, to)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<List<Bus>> searchByQuery(String query) async {
    if (query.trim().isEmpty) return getAllBuses();
    final all = await getAllBuses();
    return all
        .where((bus) => TextMatch.fuzzyContains(bus.searchBlob, query))
        .toList();
  }
}
