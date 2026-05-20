import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth/auth_service.dart';
import 'firebase_options.dart';
import 'trip_sync_main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const TripSyncApp());
}

class TripSyncApp extends StatelessWidget {
  const TripSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF4E5BF2);
    return MaterialApp(
      title: 'TripSync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1020),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Listens to FirebaseAuth and routes signed-in users straight to home.
/// Signed-out users see the landing screen with Google sign-in + guest fallback.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null) {
          return TripSyncMainShell(
            userName: user.displayName ?? user.email,
          );
        }
        return const TripSyncLandingScreen();
      },
    );
  }
}

class TripSyncLandingScreen extends StatefulWidget {
  const TripSyncLandingScreen({super.key});

  @override
  State<TripSyncLandingScreen> createState() => _TripSyncLandingScreenState();
}

class _TripSyncLandingScreenState extends State<TripSyncLandingScreen> {
  final TextEditingController _nameController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _signingIn = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      await _authService.signInWithGoogle();
      // AuthGate's StreamBuilder will swap to TripSyncMainShell automatically.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  void _continueAsGuest() {
    final enteredName = _nameController.text.trim();
    if (enteredName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name to continue.')),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => TripSyncMainShell(userName: enteredName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.travel_explore_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Audio-first city explorer',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'TripSync',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your voice-guided travel companion that gently pings you when unforgettable places are nearby.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _signingIn ? null : _signInWithGoogle,
                          icon: _signingIn
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            _signingIn ? 'Signing in…' : 'Sign in with Google',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'or continue as guest',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What should we call you?',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _nameController,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _continueAsGuest(),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Enter your first name',
                                hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                                filled: true,
                                fillColor: Colors.black.withValues(alpha: 0.18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.12),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: theme.colorScheme.primary,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _continueAsGuest,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(48),
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text('Continue as guest'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Guest mode keeps your name on this device only. Sign in with Google to sync preferences and saved places across devices.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.58),
                          height: 1.3,
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
}
