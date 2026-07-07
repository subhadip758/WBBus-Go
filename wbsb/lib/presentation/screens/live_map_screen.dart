import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../domain/entities/bus.dart';
import '../../domain/repositories/ride_tracking_repository.dart';
import '../providers/live_location_provider.dart';
import '../providers/ride_session_provider.dart';

class LiveMapScreen extends StatelessWidget {
  final Bus bus;
  const LiveMapScreen({super.key, required this.bus});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LiveLocationProvider(
        context.read<RideTrackingRepository>(),
        bus,
      )
        ..watchBus(bus.id)
        ..startViewerLocation(),
      child: _LiveMapBody(bus: bus),
    );
  }
}

class _LiveMapBody extends StatelessWidget {
  final Bus bus;
  const _LiveMapBody({required this.bus});

  @override
  Widget build(BuildContext context) {
    final liveProvider = context.watch<LiveLocationProvider>();
    final rideProvider = context.watch<RideSessionProvider>();

    final firstCoordStop =
        bus.routeStops.where((s) => s.hasCoordinates).isEmpty
            ? null
            : bus.routeStops.where((s) => s.hasCoordinates).first;
    final lastCoordStop =
        bus.routeStops.where((s) => s.hasCoordinates).isEmpty
            ? null
            : bus.routeStops.where((s) => s.hasCoordinates).last;
    final sourceLatLng = firstCoordStop != null
        ? LatLng(firstCoordStop.latitude!, firstCoordStop.longitude!)
        : null;
    final destLatLng = lastCoordStop != null
        ? LatLng(lastCoordStop.latitude!, lastCoordStop.longitude!)
        : null;

    final busLatLng = liveProvider.resolvedLocation != null
        ? LatLng(liveProvider.resolvedLocation!.latitude,
            liveProvider.resolvedLocation!.longitude)
        : null;
    final viewerLatLng = liveProvider.viewerPosition != null
        ? LatLng(liveProvider.viewerPosition!.latitude,
            liveProvider.viewerPosition!.longitude)
        : null;

    final center =
        busLatLng ?? viewerLatLng ?? sourceLatLng ?? const LatLng(22.9, 87.5);

    final isRidingThisBus =
        rideProvider.isActive && rideProvider.activeBusId == bus.id;
    final isRidingAnotherBus =
        rideProvider.isActive && rideProvider.activeBusId != bus.id;

    return Scaffold(
      appBar: AppBar(
        title: Text('${bus.name} — Live Map'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isRidingThisBus ? AppColors.staleRed : AppColors.liveGreen,
        icon: Icon(isRidingThisBus
            ? Icons.stop_circle_outlined
            : Icons.directions_bus_filled_outlined),
        label: Text(isRidingThisBus ? 'End Ride' : "I'm On This Bus"),
        onPressed: rideProvider.status == RideSessionStatus.requestingPermission
            ? null
            : () async {
                if (isRidingThisBus) {
                  await rideProvider.endRide();
                } else {
                  if (isRidingAnotherBus) {
                    final confirmed = await _confirmSwitchRide(context);
                    if (confirmed != true) return;
                  }
                  await rideProvider.startRide(bus.id);
                }
              },
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 8),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.wbsmartbus.app',
              ),
              PolylineLayer(
                polylines: [
                  if (sourceLatLng != null && destLatLng != null)
                    Polyline(
                      points: [sourceLatLng, destLatLng],
                      strokeWidth: 3,
                      color: AppColors.primary.withOpacity(0.5),
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (sourceLatLng != null)
                    Marker(
                      point: sourceLatLng,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.trip_origin,
                          color: Colors.grey, size: 28),
                    ),
                  if (destLatLng != null)
                    Marker(
                      point: destLatLng,
                      width: 40,
                      height: 40,
                      child:
                          const Icon(Icons.flag, color: Colors.black87, size: 28),
                    ),
                  if (viewerLatLng != null)
                    Marker(
                      point: viewerLatLng,
                      width: 44,
                      height: 44,
                      child: const Icon(Icons.person_pin_circle,
                          color: Colors.blue, size: 36),
                    ),
                  if (busLatLng != null)
                    Marker(
                      point: busLatLng,
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.directions_bus,
                        color: liveProvider.resolvedLocation!.isStale
                            ? AppColors.staleRed
                            : AppColors.liveGreen,
                        size: 34,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              elevation: 4,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: _statusContent(liveProvider, rideProvider, bus.id),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmSwitchRide(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch ride?'),
        content: const Text(
          "You're currently sharing location for another bus. Starting a "
          'new ride will end that one first.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Switch')),
        ],
      ),
    );
  }

  Widget _statusContent(
    LiveLocationProvider liveProvider,
    RideSessionProvider rideProvider,
    String busId,
  ) {
    final children = <Widget>[];

    if (liveProvider.resolvedLocation == null) {
      children.add(const Row(
        children: [
          Icon(Icons.info_outline, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text('No passengers are currently sharing location for '
                'this bus. Be the first — tap "I\'m On This Bus" below.'),
          ),
        ],
      ));
    } else {
      final loc = liveProvider.resolvedLocation!;
      children.addAll([
        Row(
          children: [
            Icon(Icons.circle,
                size: 10,
                color: loc.isStale ? AppColors.staleRed : AppColors.liveGreen),
            const SizedBox(width: 6),
            Text(loc.isStale ? 'Location may be outdated' : 'Live',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('${loc.contributorCount} rider(s) sharing',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Accuracy: ~${loc.accuracyMeters.toStringAsFixed(0)} m '
                '(confidence ${(loc.confidenceScore * 100).round()}%)',
            style: const TextStyle(fontSize: 12)),
        if (loc.speedKmh != null)
          Text('Speed: ${loc.speedKmh!.toStringAsFixed(0)} km/h',
              style: const TextStyle(fontSize: 12)),
      ]);

      if (liveProvider.tripProgress.hasSufficientData) {
        final progress = liveProvider.tripProgress;
        children.add(const SizedBox(height: 6));
        if (progress.tripCompleted) {
          children.add(const Text('Trip completed — arrived at destination.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
        } else {
          if (progress.currentStopName != null) {
            children.add(Text('Near: ${progress.currentStopName}',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.nextStopName != null) {
            children.add(Text('Next stop: ${progress.nextStopName}',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.remainingStopsCount != null) {
            children.add(Text('${progress.remainingStopsCount} stops remaining',
                style: const TextStyle(fontSize: 12)));
          }
          if (progress.remainingDistanceKm != null) {
            children.add(Text(
                '~${progress.remainingDistanceKm!.toStringAsFixed(1)} km remaining '
                '(straight-line estimate, not road distance)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)));
          }
          if (progress.etaMinutes != null) {
            children.add(Text('ETA: ~${progress.etaMinutes} min',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
          }
          if (progress.delayMinutes != null) {
            final d = progress.delayMinutes!;
            final label = d > 0
                ? 'Running ~$d min late'
                : (d < 0 ? 'Running ~${-d} min early' : 'On schedule');
            children.add(Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: d > 5 ? AppColors.staleRed : Colors.grey.shade700)));
          }
        }
      }
    }

    if (rideProvider.isActive && rideProvider.activeBusId == busId) {
      children.add(const Divider(height: 16));
      children.add(Row(
        children: const [
          Icon(Icons.wifi_tethering, color: AppColors.liveGreen, size: 18),
          SizedBox(width: 6),
          Text('You are sharing your location for this bus',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ));
    }

    if (rideProvider.errorMessage != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(rideProvider.errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 12)),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
