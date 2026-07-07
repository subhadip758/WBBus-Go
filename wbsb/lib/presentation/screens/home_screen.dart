import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../providers/bus_search_provider.dart';
import '../widgets/search_form.dart';
import 'search_results_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BusSearchProvider>().loadInitialData();
    });
  }

  void _goToResults(String from, String to) {
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both From and To.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(from: from, to: to),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BusSearchProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: const Text('West Bengal Smart Bus'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: provider.loadInitialData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search bus name, reg no, operator, or any stop',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                if (value.trim().isEmpty) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SearchResultsScreen(query: value.trim()),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            SearchForm(onSearch: _goToResults),
            const SizedBox(height: 24),
            const Text('Popular Routes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.error != null)
              Text('Could not load bus dataset: ${provider.error}',
                  style: const TextStyle(color: Colors.red))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: provider.popularRoutes.map((route) {
                  return ActionChip(
                    avatar: const Icon(Icons.route, size: 16),
                    label: Text('${route.key} → ${route.value}'),
                    onPressed: () => _goToResults(route.key, route.value),
                  );
                }).toList(),
              ),
            const SizedBox(height: 24),
            Card(
              color: Colors.blue.shade50,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Live location is crowdsourced: it appears once at '
                        'least one passenger currently riding a bus taps '
                        '"I\'m On This Bus" on that bus\'s live map.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
