import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app_messenger.dart';
import 'auth/auth_service.dart';
import 'firebase_options.dart';
import 'home_screen.dart';
import 'onboarding/firestore_preferences_service.dart';
import 'onboarding/preferences_onboarding_screen.dart';
import 'onboarding/user_preferences.dart';
import 'orbit_groq_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeGroqConfig();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const OrbitApp());
}

class OrbitApp extends StatelessWidget {
  const OrbitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF4E5BF2);
    return MaterialApp(
      scaffoldMessengerKey: orbitMessengerKey,
      title: 'Orbit',
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

/// Listens to FirebaseAuth and routes signed-in users into home (or onboarding).
/// Signed-out users see the landing screen with a single Google sign-in button.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final FirestorePreferencesService _preferencesService =
      FirestorePreferencesService();
  String? _loadedPrefsForUserId;
  Future<UserPreferences?>? _preferencesFuture;

  Future<UserPreferences?> _preferencesFor(String userId) {
    if (_loadedPrefsForUserId != userId) {
      _loadedPrefsForUserId = userId;
      _preferencesFuture = _preferencesService.load(userId);
    }
    return _preferencesFuture!;
  }

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
          final userName = user.displayName ?? user.email;
          return FutureBuilder(
            future: _preferencesFor(user.uid),
            builder: (context, preferencesSnapshot) {
              if (preferencesSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final preferences = preferencesSnapshot.data;
              if (preferences != null && preferences.interests.isNotEmpty) {
                return OrbitHomeScreen(
                  userName: userName,
                  interests: preferences.interests.toList(),
                );
              }

              return PreferencesOnboardingScreen(
                userId: user.uid,
                userName: userName,
                preferencesService: _preferencesService,
                onComplete: () {
                  _loadedPrefsForUserId = null;
                  _preferencesFuture = null;
                  setState(() {});
                },
              );
            },
          );
        }
        return const OrbitLandingScreen();
      },
    );
  }
}

class OrbitLandingScreen extends StatefulWidget {
  const OrbitLandingScreen({super.key});

  @override
  State<OrbitLandingScreen> createState() => _OrbitLandingScreenState();
}

class _OrbitLandingScreenState extends State<OrbitLandingScreen> {
  AuthService? _authService;
  bool _signingIn = false;

  Future<void> _signInWithGoogle() async {
    if (_signingIn) return;
    setState(() => _signingIn = true);
    try {
      (_authService ??= AuthService());
      await _authService!.signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orbit',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Your voice-guided travel companion.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 32),
                        _GoogleSignInButton(
                          loading: _signingIn,
                          onPressed: _signInWithGoogle,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.4),
      child: InkWell(
        onTap: loading ? null : onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF4E5BF2)),
                  ),
                )
              else
                const _GoogleGlyph(size: 22),
              const SizedBox(width: 14),
              Text(
                loading ? 'Signing in…' : 'Sign in with Google',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF1F1F1F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple multi-color "G" mark drawn with overlapping arcs. Avoids shipping an
/// asset and keeps the sign-in button recognisable as Google's brand.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGlyphPainter()),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    final stroke = size.width * 0.18;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);

    final segments = <(double startDeg, double sweepDeg, Color color)>[
      (-70, 70, Color(0xFF4285F4)),
      (0, 90, Color(0xFF34A853)),
      (90, 110, Color(0xFFFBBC05)),
      (200, 90, Color(0xFFEA4335)),
    ];

    for (final (start, sweep, color) in segments) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        rect,
        start * 3.1415926535 / 180,
        sweep * 3.1415926535 / 180,
        false,
        paint,
      );
    }

    final bar = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius * 0.7, center.dy),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
