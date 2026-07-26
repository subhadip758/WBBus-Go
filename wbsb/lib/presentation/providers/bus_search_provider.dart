import 'package:flutter/foundation.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/bus_repository.dart';

class Connection {
  final Bus bus1;
  final Bus bus2;
  final String connectionStop;
  Connection({required this.bus1, required this.bus2, required this.connectionStop});
}

class BusSearchProvider extends ChangeNotifier {
  final BusRepository _repository;

  BusSearchProvider(this._repository);

  bool isLoading = false;
  String? error;
  List<Bus> allBuses = [];
  List<Bus> results = [];
  List<Connection> connectingResults = [];
  String fromQuery = '';
  String toQuery = '';
  bool hasSearched = false;

  /// Distinct source/destination pairs, used to render "Popular Routes"
  /// directly from the real dataset instead of a hardcoded list.
  List<MapEntry<String, String>> get popularRoutes {
    final seen = <String>{};
    final routes = <MapEntry<String, String>>[];
    for (final b in allBuses) {
      final key = '${b.source}=>${b.destination}';
      if (seen.add(key)) {
        routes.add(MapEntry(b.source, b.destination));
        if (routes.length >= 8) break;
      }
    }
    return routes;
  }

  Future<void> loadInitialData() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      allBuses = await _repository.getAllBuses();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> search(String from, String to) async {
    fromQuery = from;
    toQuery = to;
    isLoading = true;
    hasSearched = true;
    error = null;
    notifyListeners();
    try {
      results = await _repository.search(from: from, to: to);
      connectingResults = [];
      
      if (results.isEmpty && from.isNotEmpty && to.isNotEmpty) {
        _computeConnectingRoutes(from, to);
      }
    } catch (e) {
      error = e.toString();
      results = [];
      connectingResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// General search across bus name, alternate name, registration
  /// number, operator, agency, source, destination, and every
  /// intermediate stop — for the "search by anything" bar.
  Future<void> searchByQuery(String query) async {
    fromQuery = '';
    toQuery = '';
    isLoading = true;
    hasSearched = true;
    error = null;
    notifyListeners();
    try {
      final parsed = _parseGeneralQuery(query);
      if (parsed != null) {
        fromQuery = parsed.key;
        toQuery = parsed.value;
        results = await _repository.search(from: parsed.key, to: parsed.value);
        connectingResults = [];
        if (results.isEmpty) {
          _computeConnectingRoutes(parsed.key, parsed.value);
        }
      } else {
        results = await _repository.searchByQuery(query);
        connectingResults = [];
      }
    } catch (e) {
      error = e.toString();
      results = [];
      connectingResults = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _computeConnectingRoutes(String from, String to) {
    final fQuery = from.trim().toLowerCase();
    final tQuery = to.trim().toLowerCase();
    
    final startBuses = <Map<String, dynamic>>[];
    final endBuses = <Map<String, dynamic>>[];
    
    for (final bus in allBuses) {
      final sStops = bus.routeStops.where((stop) => 
        (stop.stopName ?? '').toLowerCase().contains(fQuery) || 
        bus.source.toLowerCase().contains(fQuery)
      ).toList();
      
      if (sStops.isNotEmpty) {
        final minSeq = sStops.map((s) => s.sequence).reduce((a, b) => a < b ? a : b);
        startBuses.add({
          'bus': bus,
          'minSeq': minSeq,
          'stopsAfter': bus.routeStops.where((s) => s.sequence > minSeq).toList()
        });
      }
      
      final dStops = bus.routeStops.where((stop) => 
        (stop.stopName ?? '').toLowerCase().contains(tQuery) || 
        bus.destination.toLowerCase().contains(tQuery)
      ).toList();
      
      if (dStops.isNotEmpty) {
        final maxSeq = dStops.map((s) => s.sequence).reduce((a, b) => a > b ? a : b);
        endBuses.add({
          'bus': bus,
          'maxSeq': maxSeq,
          'stopsBefore': bus.routeStops.where((s) => s.sequence < maxSeq).toList()
        });
      }
    }
    
    int count = 0;
    for (final b1 in startBuses) {
      final bus1 = b1['bus'] as Bus;
      final stopsAfter = b1['stopsAfter'] as List;
      
      for (final b2 in endBuses) {
        final bus2 = b2['bus'] as Bus;
        if (bus1.id == bus2.id) continue;
        
        final stopsBefore = b2['stopsBefore'] as List;
        
        for (final stop1 in stopsAfter) {
          final s1Name = (stop1.stopName ?? '').toLowerCase().trim();
          for (final stop2 in stopsBefore) {
            final s2Name = (stop2.stopName ?? '').toLowerCase().trim();
            if (s1Name == s2Name && s1Name.isNotEmpty) {
              connectingResults.add(Connection(
                bus1: bus1,
                bus2: bus2,
                connectionStop: stop1.stopName ?? '',
              ));
              count++;
              if (count >= 5) break;
            }
          }
          if (count >= 5) break;
        }
        if (count >= 5) break;
      }
      if (count >= 5) break;
    }
  }

  MapEntry<String, String>? _parseGeneralQuery(String query) {
    final q = query.trim();
    if (q.isEmpty) return null;
    
    final toRegExp = RegExp(r'\s+to\s+', caseSensitive: false);
    final arrowRegExp = RegExp(r'\s*->\s*');
    final dashRegExp = RegExp(r'\s*-\s*');
    final doubleArrowRegExp = RegExp(r'\s*↔\s*');
    
    if (toRegExp.hasMatch(q)) {
      final parts = q.split(toRegExp);
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        return MapEntry(parts[0].trim(), parts[1].trim());
      }
    }
    if (arrowRegExp.hasMatch(q)) {
      final parts = q.split(arrowRegExp);
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        return MapEntry(parts[0].trim(), parts[1].trim());
      }
    }
    if (dashRegExp.hasMatch(q)) {
      final parts = q.split(dashRegExp);
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        return MapEntry(parts[0].trim(), parts[1].trim());
      }
    }
    if (doubleArrowRegExp.hasMatch(q)) {
      final parts = q.split(doubleArrowRegExp);
      if (parts.length == 2 && parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty) {
        return MapEntry(parts[0].trim(), parts[1].trim());
      }
    }
    
    final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length == 2) {
      return MapEntry(words[0], words[1]);
    }
    
    return null;
  }
}
