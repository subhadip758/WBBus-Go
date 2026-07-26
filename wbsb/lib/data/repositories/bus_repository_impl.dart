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
    final fQuery = from?.trim() ?? '';
    final tQuery = to?.trim() ?? '';
    
    if (fQuery.isEmpty && tQuery.isEmpty) return all;
    
    return all.where((bus) {
      bool matchesSource = fQuery.isEmpty;
      bool matchesDest = tQuery.isEmpty;
      
      final sourceStops = bus.routeStops.where((stop) => 
        TextMatch.fuzzyContains(stop.stopName ?? '', fQuery) || 
        TextMatch.fuzzyContains(bus.source, fQuery)
      ).toList();
      
      final destStops = bus.routeStops.where((stop) => 
        TextMatch.fuzzyContains(stop.stopName ?? '', tQuery) || 
        TextMatch.fuzzyContains(bus.destination, tQuery)
      ).toList();
      
      if (fQuery.isNotEmpty && tQuery.isNotEmpty) {
        if (sourceStops.isNotEmpty && destStops.isNotEmpty) {
          final minSourceSeq = sourceStops.map((s) => s.sequence).reduce((a, b) => a < b ? a : b);
          final maxDestSeq = destStops.map((s) => s.sequence).reduce((a, b) => a > b ? a : b);
          if (minSourceSeq < maxDestSeq) {
            matchesSource = true;
            matchesDest = true;
          }
        }
      } else if (fQuery.isNotEmpty) {
        matchesSource = sourceStops.isNotEmpty;
      } else if (tQuery.isNotEmpty) {
        matchesDest = destStops.isNotEmpty;
      }
      
      return matchesSource && matchesDest;
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
