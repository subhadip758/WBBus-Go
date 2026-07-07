import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import '../../domain/entities/route_stop.dart';
import '../models/agency_model.dart';
import '../models/bus_model.dart';
import '../models/operator_model.dart';
import '../models/route_model.dart';
import '../models/stop_model.dart';
import '../models/timetable_entry_model.dart';

/// Loads and joins all six normalized datasets (buses, routes, stops,
/// timetable, operators, agencies) into fully hydrated [BusModel] +
/// [RouteStop] data. Each raw JSON file is cached independently in
/// Hive so the app keeps working offline, and so a future update to
/// just one file (e.g. a corrected timetable.json) doesn't require
/// re-caching everything else.
class BusLocalDataSource {
  static const String boxName = 'wbsb_dataset_cache';

  static const _busesAsset = 'assets/data/buses.json';
  static const _routesAsset = 'assets/data/routes.json';
  static const _stopsAsset = 'assets/data/stops.json';
  static const _timetableAsset = 'assets/data/timetable.json';
  static const _operatorsAsset = 'assets/data/operators.json';
  static const _agenciesAsset = 'assets/data/agencies.json';

  List<BusModel>? _busCache;
  Map<String, RouteModel>? _routesById;
  Map<String, StopModel>? _stopsById;
  Map<String, List<TimetableEntryModel>>? _timetableByBusId;
  List<OperatorModel>? _operatorsCache;
  List<AgencyModel>? _agenciesCache;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await Hive.openBox<String>(boxName);
    }
  }

  Future<String> _loadRaw(String assetPath, String cacheKey) async {
    final box = Hive.box<String>(boxName);
    try {
      final raw = await rootBundle.loadString(assetPath);
      await box.put(cacheKey, raw);
      return raw;
    } catch (assetError) {
      final cached = box.get(cacheKey);
      if (cached == null) {
        throw BusDatasetException(
          'Could not load "$assetPath" from the app bundle and no offline '
          'copy exists in Hive yet. Original error: $assetError',
        );
      }
      return cached;
    }
  }

  Future<Map<String, RouteModel>> _loadRoutes() async {
    if (_routesById != null) return _routesById!;
    final raw = await _loadRaw(_routesAsset, 'routes_json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = (decoded['routes'] as List<dynamic>)
        .map((e) => RouteModel.fromJson(e as Map<String, dynamic>));
    _routesById = {for (final r in list) r.routeId: r};
    return _routesById!;
  }

  Future<Map<String, StopModel>> _loadStops() async {
    if (_stopsById != null) return _stopsById!;
    final raw = await _loadRaw(_stopsAsset, 'stops_json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = (decoded['stops'] as List<dynamic>)
        .map((e) => StopModel.fromJson(e as Map<String, dynamic>));
    _stopsById = {for (final s in list) s.stopId: s};
    return _stopsById!;
  }

  Future<Map<String, List<TimetableEntryModel>>> _loadTimetable() async {
    if (_timetableByBusId != null) return _timetableByBusId!;
    final raw = await _loadRaw(_timetableAsset, 'timetable_json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = (decoded['timetable'] as List<dynamic>)
        .map((e) => TimetableEntryModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final grouped = <String, List<TimetableEntryModel>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.busId, () => []).add(entry);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.sequence.compareTo(b.sequence));
    }
    _timetableByBusId = grouped;
    return grouped;
  }

  Future<List<OperatorModel>> loadOperators() async {
    if (_operatorsCache != null) return _operatorsCache!;
    final raw = await _loadRaw(_operatorsAsset, 'operators_json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _operatorsCache = (decoded['operators'] as List<dynamic>)
        .map((e) => OperatorModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return _operatorsCache!;
  }

  Future<List<AgencyModel>> loadAgencies() async {
    if (_agenciesCache != null) return _agenciesCache!;
    final raw = await _loadRaw(_agenciesAsset, 'agencies_json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _agenciesCache = (decoded['agencies'] as List<dynamic>)
        .map((e) => AgencyModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return _agenciesCache!;
  }

  /// Loads every dataset and returns fully hydrated buses, each with
  /// its ordered, coordinate-and-time-annotated route stops attached.
  Future<List<BusModel>> loadAll() => loadAllHydrated().then(
        (hydrated) => hydrated.map((h) => h.model).toList(),
      );

  Future<List<HydratedBus>> loadAllHydrated() async {
    final rawBuses = await _loadRaw(_busesAsset, 'buses_json');
    final decoded = jsonDecode(rawBuses) as Map<String, dynamic>;
    final busModels = (decoded['buses'] as List<dynamic>)
        .map((e) => BusModel.fromJson(e as Map<String, dynamic>))
        .toList();

    final routesById = await _loadRoutes();
    final stopsById = await _loadStops();
    final timetableByBusId = await _loadTimetable();

    final result = <HydratedBus>[];
    for (final bus in busModels) {
      final timetableEntries = timetableByBusId[bus.busId] ?? const [];
      final routeStops = timetableEntries.map((entry) {
        final stop = entry.stopId != null ? stopsById[entry.stopId] : null;
        return RouteStop(
          sequence: entry.sequence,
          stopId: entry.stopId,
          stopName: stop?.stopName,
          latitude: stop?.latitude,
          longitude: stop?.longitude,
          upTime: entry.upTime,
          downTime: entry.downTime,
        );
      }).toList();
      result.add(HydratedBus(model: bus, routeStops: routeStops));
    }
    return result;
  }

  void invalidateCache() {
    _busCache = null;
    _routesById = null;
    _stopsById = null;
    _timetableByBusId = null;
    _operatorsCache = null;
    _agenciesCache = null;
  }
}

class HydratedBus {
  final BusModel model;
  final List<RouteStop> routeStops;
  const HydratedBus({required this.model, required this.routeStops});
}

class BusDatasetException implements Exception {
  final String message;
  BusDatasetException(this.message);

  @override
  String toString() => 'BusDatasetException: $message';
}
