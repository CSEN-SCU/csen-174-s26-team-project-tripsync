import 'package:flutter/material.dart';

import 'preferences_service.dart';

const List<String> geoPoiTags = [
  'art',
  'culture',
  'family',
  'food',
  'museum',
  'nature',
  'shopping',
  'views',
  'walking',
];

const List<String> geoPoiCategories = [
  'attraction',
  'gallery',
  'historic',
  'market',
  'museum',
  'park',
];

final List<String> geoPoiOnboardingOptions = [
  ...{...geoPoiTags, ...geoPoiCategories},
]..sort();

class PreferencesOnboardingScreen extends StatefulWidget {
  const PreferencesOnboardingScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.preferencesService,
    required this.onComplete,
  });

  final String userId;
  final String? userName;
  final PreferencesService preferencesService;
  final VoidCallback onComplete;

  @override
  State<PreferencesOnboardingScreen> createState() =>
      _PreferencesOnboardingScreenState();
}

class _PreferencesOnboardingScreenState
    extends State<PreferencesOnboardingScreen> {
  final Set<String> _selectedOptions = {};
  bool _saving = false;

  Future<void> _continue() async {
    if (_selectedOptions.isEmpty || _saving) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one interest to continue.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.preferencesService.save(widget.userId, _selectedOptions);
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preferences: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleOption(String option) {
    setState(() {
      if (_selectedOptions.contains(option)) {
        _selectedOptions.remove(option);
      } else {
        _selectedOptions.add(option);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.userName?.trim();
    final greeting = name == null || name.isEmpty ? 'Welcome' : 'Welcome, $name';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101A38), Color(0xFF0B1020), Color(0xFF1B1840)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 460,
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greeting,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'What should TripSync point out for you?',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose at least one. These options combine the geo POI database tags and categories, with duplicates removed.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final option in geoPoiOnboardingOptions)
                              FilterChip(
                                label: Text(_labelForOption(option)),
                                selected: _selectedOptions.contains(option),
                                onSelected: _saving
                                    ? null
                                    : (_) => _toggleOption(option),
                                selectedColor: theme.colorScheme.primary,
                                checkmarkColor: Colors.white,
                                labelStyle: TextStyle(
                                  color: _selectedOptions.contains(option)
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w600,
                                ),
                                backgroundColor:
                                    Colors.black.withValues(alpha: 0.18),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _selectedOptions.isEmpty || _saving
                              ? null
                              : _continue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.12),
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: 0.45),
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _selectedOptions.isEmpty
                                      ? 'Select at least one'
                                      : 'Save preferences',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _labelForOption(String option) {
    return option
        .split('-')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
