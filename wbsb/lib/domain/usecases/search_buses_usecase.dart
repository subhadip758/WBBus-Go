import '../entities/bus.dart';
import '../repositories/bus_repository.dart';

class SearchBusesUseCase {
  final BusRepository repository;
  SearchBusesUseCase(this.repository);

  Future<List<Bus>> call({String? from, String? to}) {
    return repository.search(from: from, to: to);
  }
}
