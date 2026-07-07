import 'package:flutter/material.dart';
import '../../core/utils/time_utils.dart';
import '../../domain/entities/bus.dart';

class BusCard extends StatelessWidget {
  final Bus bus;
  final VoidCallback onTap;

  const BusCard({super.key, required this.bus, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration =
        TimeUtils.durationBetween(bus.departureTime, bus.arrivalTime);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      bus.alternateName != null
                          ? '${bus.name} · ${bus.alternateName}'
                          : bus.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (bus.registrationNumber != null)
                    Text(bus.registrationNumber!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [bus.operator, bus.busType]
                    .where((s) => s != null && s.isNotEmpty)
                    .join(' · '),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _timeBlock(
                      bus.source, TimeUtils.formatDisplay(bus.departureTime)),
                  Expanded(
                    child: Column(
                      children: [
                        const Icon(Icons.directions_bus, size: 18),
                        if (duration != null)
                          Text(duration, style: const TextStyle(fontSize: 11)),
                        if (bus.routeStops.length > 2)
                          Text('${bus.routeStops.length} stops',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  _timeBlock(bus.destination,
                      TimeUtils.formatDisplay(bus.arrivalTime),
                      alignEnd: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeBlock(String place, String time, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(time,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        Text(place,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
