import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

class SearchForm extends StatefulWidget {
  final void Function(String from, String to) onSearch;
  final String? initialFrom;
  final String? initialTo;

  const SearchForm({
    super.key,
    required this.onSearch,
    this.initialFrom,
    this.initialTo,
  });

  @override
  State<SearchForm> createState() => _SearchFormState();
}

class _SearchFormState extends State<SearchForm> {
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;

  @override
  void initState() {
    super.initState();
    _fromCtrl = TextEditingController(text: widget.initialFrom ?? '');
    _toCtrl = TextEditingController(text: widget.initialTo ?? '');
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  void _swap() {
    final tmp = _fromCtrl.text;
    _fromCtrl.text = _toCtrl.text;
    _toCtrl.text = tmp;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _fromCtrl,
              decoration: InputDecoration(
                labelText: 'From',
                prefixIcon: const Icon(Icons.trip_origin),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.center,
              child: IconButton(
                icon: const Icon(Icons.swap_vert),
                onPressed: _swap,
                tooltip: 'Swap',
              ),
            ),
            TextField(
              controller: _toCtrl,
              decoration: InputDecoration(
                labelText: 'To',
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.search),
                label: const Text('Search Bus'),
                onPressed: () =>
                    widget.onSearch(_fromCtrl.text.trim(), _toCtrl.text.trim()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
