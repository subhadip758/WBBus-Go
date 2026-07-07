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
              ? const Center(
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
