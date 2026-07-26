import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../providers/bus_search_provider.dart';
import '../widgets/bus_card.dart';
import 'bus_details_screen.dart';

class SearchResultsScreen extends StatefulWidget {
  /// Route search mode: provide both.
  final String? from;
  final String? to;

  /// General query mode (bus name / reg no / operator / agency /
  /// intermediate stop): provide this instead.
  final String? query;

  const SearchResultsScreen({super.key, this.from, this.to, this.query})
      : assert(
          (from != null && to != null) || query != null,
          'Provide either from+to for a route search, or query for a general search.',
        );

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<BusSearchProvider>();
      if (widget.query != null) {
        provider.searchByQuery(widget.query!);
      } else {
        provider.search(widget.from!, widget.to!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BusSearchProvider>();
    final title = widget.query != null
        ? 'Results for "${widget.query}"'
        : '${widget.from} → ${widget.to}';

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.results.isEmpty
              ? provider.connectingResults.isNotEmpty
                  ? ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: provider.connectingResults.length,
                      itemBuilder: (context, index) {
                        final conn = provider.connectingResults[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: AppColors.primary.withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                color: AppColors.primary.withOpacity(0.08),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.alt_route, size: 16, color: AppColors.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          '1-STOP CONNECTION',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'VIA ${conn.connectionStop.toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              
                              // First Leg
                              InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BusDetailsScreen(busId: conn.bus1.id),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '1',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade800,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              conn.bus1.busName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              '${conn.bus1.source} → ${conn.bus1.destination}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                              
                              Divider(height: 1, color: Colors.grey.shade200, indent: 48),
                              
                              // Second Leg
                              InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BusDetailsScreen(busId: conn.bus2.id),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            '2',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green.shade800,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              conn.bus2.busName,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            Text(
                                              '${conn.bus2.source} → ${conn.bus2.destination}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No buses found.\n'
                          'Try a nearby major stop, the operator name, or part '
                          'of a registration number.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: provider.results.length,
                  itemBuilder: (context, index) {
                    final bus = provider.results[index];
                    return BusCard(
                      bus: bus,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusDetailsScreen(busId: bus.id),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
