import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../onboarding/firestore_preferences_service.dart';
import '../onboarding/preferences_onboarding_screen.dart' show geoPoiOnboardingOptions;
import '../onboarding/preferences_service.dart';

/// Post-onboarding preferences editor: tags now, voice & playback later.
/// Sign-out lives at the bottom (intentionally, to discourage accidental taps).
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({
    super.key,
    required this.userId,
    this.userName,
    PreferencesService? preferencesService,
    AuthService? authService,
  })  : _preferencesService = preferencesService,
        _authService = authService;

  final String userId;
  final String? userName;
  final PreferencesService? _preferencesService;
  final AuthService? _authService;

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  late final PreferencesService _preferencesService;
  late final AuthService _authService;

  final Set<String> _selected = {};
  bool _loading = true;
  bool _saving = false;
  bool _signingOut = false;
  String? _loadError;
  Set<String> _initial = {};

  @override
  void initState() {
    super.initState();
    _preferencesService =
        widget._preferencesService ?? FirestorePreferencesService();
    _authService = widget._authService ?? AuthService();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await _preferencesService.load(widget.userId);
      if (!mounted) return;
      setState(() {
        _initial = prefs?.interests ?? {};
        _selected
          ..clear()
          ..addAll(_initial);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  bool get _hasChanges =>
      _selected.length != _initial.length ||
      !_selected.containsAll(_initial);

  void _toggle(String option) {
    if (_saving) return;
    setState(() {
      if (_selected.contains(option)) {
        _selected.remove(option);
      } else {
        _selected.add(option);
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_hasChanges) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one interest.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _preferencesService.save(widget.userId, _selected);
      if (!mounted) return;
      setState(() => _initial = Set<String>.from(_selected));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preferences saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save preferences: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out of Orbit?'),
        content: const Text(
          'You will need to sign in again to see your preferences and recommendations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handleSignOut() async {
    if (_signingOut) return;
    final confirmed = await _confirmSignOut();
    if (!confirmed || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await _authService.signOut();
      if (!mounted) return;
      // AuthGate rebuilds to the landing screen on auth-state change, but the
      // pushed preferences route would still sit on top. Pop back to the root
      // so the user lands on the freshly-rebuilt sign-in screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-out failed: $e')),
      );
      setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Preferences'),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101A38), Color(0xFF0B1020), Color(0xFF1B1840)],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loadError != null)
                            _ErrorBanner(message: _loadError!),
                          _InterestsCard(
                            selected: _selected,
                            onToggle: _toggle,
                            saving: _saving,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: (!_hasChanges || _saving)
                                ? null
                                : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                              disabledForegroundColor:
                                  Colors.white.withValues(alpha: 0.45),
                              minimumSize: const Size.fromHeight(48),
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
                                : const Text('Save changes'),
                          ),
                          const SizedBox(height: 28),
                          const _ComingSoonCard(),
                          const SizedBox(height: 32),
                          _SignOutButton(
                            signingOut: _signingOut,
                            onPressed: _handleSignOut,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _InterestsCard extends StatelessWidget {
  const _InterestsCard({
    required this.selected,
    required this.onToggle,
    required this.saving,
  });

  final Set<String> selected;
  final void Function(String) onToggle;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your interests',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Orbit uses these tags to pick which nearby places to surface.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in geoPoiOnboardingOptions)
                FilterChip(
                  label: Text(_labelForOption(option)),
                  selected: selected.contains(option),
                  onSelected: saving ? null : (_) => onToggle(option),
                  selectedColor: theme.colorScheme.primary,
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected.contains(option)
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.black.withValues(alpha: 0.18),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _labelForOption(String option) {
    return option
        .split('-')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Voice & playback',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Coming soon',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Voice selection, speech rate, and playback routing will live here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.signingOut, required this.onPressed});

  final bool signingOut;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: signingOut ? null : onPressed,
      icon: signingOut
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.logout_rounded, size: 18),
      label: Text(signingOut ? 'Signing out…' : 'Sign out'),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.colorScheme.error.withValues(alpha: 0.95),
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.55),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        'Could not load your saved preferences: $message',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error.withValues(alpha: 0.95),
          height: 1.35,
        ),
      ),
    );
  }
}
