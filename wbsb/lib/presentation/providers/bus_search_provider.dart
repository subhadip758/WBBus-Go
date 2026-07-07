import 'package:flutter/foundation.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/bus_repository.dart';

class BusSearchProvider extends ChangeNotifier {
  final BusRepository _repository;

  BusSearchProvider(this._repository);

  bool isLoading = false;
  String? error;
  List<Bus> allBuses = [];
  List<Bus> results = [];
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
    } catch (e) {
      error = e.toString();
      results = [];
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
      results = await _repository.searchByQuery(query);
    } catch (e) {
      error = e.toString();
      results = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
