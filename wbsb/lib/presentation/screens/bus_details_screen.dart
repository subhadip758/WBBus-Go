import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/time_utils.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/bus_repository.dart';
import 'live_map_screen.dart';

class BusDetailsScreen extends StatelessWidget {
  final String busId;
  const BusDetailsScreen({super.key, required this.busId});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<BusRepository>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('Bus Details'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<Bus?>(
        future: repository.getById(busId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bus = snapshot.data;
          if (bus == null) {
            return const Center(child: Text('Bus not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _headerCard(bus),
              const SizedBox(height: 16),
              Text('Full Route (${bus.routeStops.length} stops)',
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _stopsTable(bus),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Track Live Location'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => LiveMapScreen(bus: bus)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _headerCard(Bus bus) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(bus.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                ),
                if (bus.alternateName != null)
                  Chip(
                    label: Text(bus.alternateName!,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(bus.operator, style: TextStyle(color: Colors.grey.shade700)),
            if (bus.agency != null)
              Text(bus.agency!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const Divider(height: 24),
            if (bus.registrationNumber != null)
              _row('Reg No', bus.registrationNumber!),
            if (bus.busType != null) _row('Bus Type', bus.busType!),
            if (bus.contactNumber != null)
              _row('Contact', bus.contactNumber!),
            if (bus.alternateNumber != null)
              _row('Alt. Contact', bus.alternateNumber!),
            const Divider(height: 24),
            _row('Source', bus.source),
            _row('Destination', bus.destination),
            _row('Departure', TimeUtils.formatDisplay(bus.departureTime)),
            _row('Arrival', TimeUtils.formatDisplay(bus.arrivalTime)),
          ],
        ),
      ),
    );
  }

  Widget _stopsTable(Bus bus) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: bus.routeStops.map((stop) {
          final name = stop.stopName ?? '(unreadable in source scan)';
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor:
                  stop.stopName == null ? Colors.orange.shade200 : null,
              child: Text('${stop.sequence}',
                  style: const TextStyle(fontSize: 10)),
            ),
            title: Text(name,
                style: stop.stopName == null
                    ? const TextStyle(fontStyle: FontStyle.italic)
                    : null),
            trailing: Text(
              TimeUtils.formatDisplay(stop.upTime),
              style: const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
