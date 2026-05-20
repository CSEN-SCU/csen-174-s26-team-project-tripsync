import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'auth/auth_service.dart';
import 'groq_orpheus_tts.dart';
import 'location_service.dart';
import 'tripsync_groq_config.dart';

/// Home: speaks a place recommendation (headphones / system route), then listens
/// and logs your spoken reply. Background auto-pings are planned for a later build.
class TripSyncHomeScreen extends StatefulWidget {
  const TripSyncHomeScreen({super.key, this.userName});

  final String? userName;

  @override
  State<TripSyncHomeScreen> createState() => _TripSyncHomeScreenState();
}

class _TripSyncHomeScreenState extends State<TripSyncHomeScreen> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  final LocationService _locationService = const LocationService();
  final AuthService _authService = AuthService();
  bool _signingOut = false;

  /// Static copy for now; later this can come from location + LLM.
  static const String _placeRecommendation =
      'Crissy Field East Beach — flat walk, Golden Gate views, and room to spread out. Worth a stop if you are near the Marina.';

  bool _voiceReady = false;
  bool _voiceUnsupported = false;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _sessionBusy = false;
  bool _heardFinalThisSession = false;

  String _statusMessage = 'Getting voice ready…';
  String? _liveTranscript;
  String _ttsSourceLine =
      'TTS: checking… (Groq Orpheus uses up to 200 characters per request.)';

  LocationReading? _locationReading;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapVoice();
      _ensureLocation();
    });
  }

  Future<void> _ensureLocation() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _locationReading = const LocationReading(
          outcome: LocationOutcome.error,
          errorMessage: 'Location is only available on iOS or Android.',
        );
      });
      return;
    }

    final reading = await _locationService.ensureConsentAndRead();
    if (!mounted) return;
    setState(() {
      _locationLoading = false;
      _locationReading = reading;
    });
  }

  @override
  void dispose() {
    unawaited(() async {
      await _tts.stop();
      await _speech.stop();
      await _speech.cancel();
    }());
    super.dispose();
  }

  String _ttsPhrase(String raw) =>
      raw.replaceAll('—', ', ').replaceAll('–', ', ');

  Future<void> _bootstrapVoice() async {
    if (kIsWeb) {
      if (!mounted) return;
      setState(() {
        _voiceUnsupported = true;
        _statusMessage = 'Voice playback and capture need iOS or Android (not web).';
      });
      return;
    }

    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          const [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          ],
          IosTextToSpeechAudioMode.voiceChat,
        );
      }

      final ok = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (e) {
          developer.log(
            e.errorMsg,
            name: 'TripSync.stt_error',
            error: e.permanent,
          );
        },
      );

      if (!mounted) return;
      if (!ok) {
        setState(() {
          _voiceUnsupported = true;
          _statusMessage = 'Speech recognition is not available. Check mic permissions in Settings.';
        });
        return;
      }

      setState(() {
        _voiceReady = true;
        _statusMessage = 'Starting…';
        _ttsSourceLine = groqApiKeyFromEnvironment().isNotEmpty
            ? 'TTS: Groq Orpheus — canopylabs/orpheus-v1-english, voice troy (max 200 chars per line).'
            : 'TTS: on-device — add GROQ_API_KEY (see app/.env.example), then flutter run --dart-define-from-file=.env';
      });
      await _runSpeakThenListen();
    } catch (e, st) {
      developer.log('$e', name: 'TripSync.voice_boot', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _voiceUnsupported = true;
        _statusMessage = 'Voice setup failed. Try again from the previous screen.';
      });
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      setState(() {
        _isListening = true;
        _statusMessage = 'Listening — answer out loud.';
      });
      return;
    }

    if (status == 'notListening' || status == 'done') {
      setState(() => _isListening = false);
      if (!_heardFinalThisSession) {
        final fallback = _liveTranscript?.trim() ?? '';
        if (fallback.isNotEmpty) {
          _heardFinalThisSession = true;
          _logVoiceReply(fallback);
        } else if (_voiceReady && !_isSpeaking) {
          setState(() {
            _statusMessage = 'Did not catch that. Tap “Replay suggestion” and try again.';
          });
        }
      }
      setState(() => _sessionBusy = false);
    }
  }

  Future<void> _runSpeakThenListen() async {
    if (!_voiceReady || _voiceUnsupported || !mounted) return;

    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();

    if (!mounted) return;
    setState(() {
      _sessionBusy = true;
      _heardFinalThisSession = false;
      _liveTranscript = null;
      _isSpeaking = true;
      _statusMessage = 'Playing suggestion through your headphones or speaker…';
    });

    final spoken = _ttsPhrase(_placeRecommendation);
    final groqKey = groqApiKeyFromEnvironment();
    try {
      if (groqKey.isNotEmpty) {
        final orpheusInput = GroqOrpheusTts.buildEnglishInput(spoken);
        final wav = await GroqOrpheusTts.synthesizeEnglishWav(
          apiKey: groqKey,
          input: orpheusInput,
          voice: 'troy',
        );
        await GroqOrpheusTts.playWavBytes(wav);
      } else {
        await _tts.speak(spoken);
      }
    } catch (e, st) {
      developer.log('$e', name: 'TripSync.tts_speak', stackTrace: st);
      if (groqKey.isNotEmpty) {
        try {
          await _tts.speak(spoken);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Groq TTS failed; used on-device voice for this playback.'),
            ),
          );
        } catch (e2, st2) {
          developer.log('$e2', name: 'TripSync.tts_fallback', stackTrace: st2);
          if (!mounted) return;
          setState(() {
            _sessionBusy = false;
            _isSpeaking = false;
            _statusMessage =
                'Could not play audio (Groq and on-device). Check network and volume.';
          });
          return;
        }
      } else {
        if (!mounted) return;
        setState(() {
          _sessionBusy = false;
          _isSpeaking = false;
          _statusMessage = 'Could not play audio. Check volume and try replay.';
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      _isListening = true;
      _statusMessage = 'Listening — answer out loud.';
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || !_voiceReady) return;

    try {
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          setState(() => _liveTranscript = r.recognizedWords);
          if (r.finalResult) {
            final text = r.recognizedWords.trim();
            if (text.isEmpty) return;
            if (!_heardFinalThisSession) {
              _heardFinalThisSession = true;
              _logVoiceReply(text);
            }
            unawaited(_speech.stop());
          }
        },
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e, st) {
      developer.log('$e', name: 'TripSync.listen', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _sessionBusy = false;
        _statusMessage = 'Could not start listening. Tap replay to try again.';
      });
    }
  }

  void _logVoiceReply(String text) {
    final user = widget.userName?.trim();
    final prefix =
        user != null && user.isNotEmpty ? 'user=$user' : 'user=anonymous';

    debugPrint('[$prefix] place_response (voice): $text');
    developer.log(
      '[$prefix] place_response (voice): $text',
      name: 'TripSync.place_response',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged what we heard.')),
    );
    setState(() {
      _statusMessage = 'Reply logged. Tap replay for another round.';
      _sessionBusy = false;
    });
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
    final hadFirebaseUser = _authService.currentUser != null;
    try {
      await _authService.signOut();
      if (!mounted) return;
      // Guests reach this screen via Navigator.push from the landing screen,
      // so pop back. Firebase users are at the AuthGate root and will rebuild
      // to the landing screen automatically once authStateChanges emits null.
      if (!hadFirebaseUser && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-out failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = widget.userName?.trim();
    final hasGreeting = greeting != null && greeting.isNotEmpty;
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: hasGreeting
                              ? Text(
                                  'Hi, $greeting',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        TextButton.icon(
                          onPressed: _signingOut ? null : _handleSignOut,
                          icon: _signingOut
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.logout_rounded, size: 18),
                          label: Text(_signingOut ? 'Signing out…' : 'Sign out'),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Voice suggestion',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _placeRecommendation,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _ttsSourceLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.5),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _LocationPanel(
                      loading: _locationLoading,
                      reading: _locationReading,
                      onRetry: () {
                        setState(() => _locationLoading = true);
                        _ensureLocation();
                      },
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isSpeaking
                                    ? Icons.headphones_rounded
                                    : _isListening
                                        ? Icons.mic_rounded
                                        : Icons.graphic_eq_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _statusMessage,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_liveTranscript != null &&
                              _liveTranscript!.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Live transcript',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _liveTranscript!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (!_voiceReady ||
                                _voiceUnsupported ||
                                _sessionBusy ||
                                _isSpeaking ||
                                _isListening)
                            ? null
                            : () => _runSpeakThenListen(),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Replay suggestion & listen again'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Later: TripSync will be able to run in the background and ping you with nearby suggestions when you turn that on.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                        height: 1.35,
                      ),
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

/// Inline interactive map centered on the user's current position.
///
/// Uses OpenStreetMap tiles (no API key, free for low volume; we set
/// `userAgentPackageName` so OSM can identify the client per their policy).
/// Pan + pinch-zoom are enabled via `InteractiveFlag.all`. Sprint 2 will
/// add a `MarkerLayer` for nearby POIs at the spot marked below.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'edu.scu.orbit',
              tileProvider: NetworkTileProvider(),
            ),
            // TODO(sprint-2): replace with a MarkerLayer fed by nearby POIs.
            MarkerLayer(
              markers: [
                Marker(
                  point: center,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.45,
                          ),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationPanel extends StatelessWidget {
  const _LocationPanel({
    required this.loading,
    required this.reading,
    required this.onRetry,
  });

  final bool loading;
  final LocationReading? reading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, headline, detail) = _renderContent();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (_grantedCoords() case final coords?) ...[
            const SizedBox(height: 12),
            _MapPreview(latitude: coords.$1, longitude: coords.$2),
          ],
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
                height: 1.35,
              ),
            ),
          ],
          if (_shouldShowRetry()) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _shouldShowRetry() {
    if (loading) return false;
    final outcome = reading?.outcome;
    return outcome == LocationOutcome.denied ||
        outcome == LocationOutcome.servicesDisabled ||
        outcome == LocationOutcome.error;
  }

  /// Returns (lat, lng) when the reading is granted with coordinates;
  /// `null` otherwise. Used to decide whether the map preview should render.
  (double, double)? _grantedCoords() {
    final r = reading;
    if (r == null || !r.isGranted) return null;
    final lat = r.latitude;
    final lng = r.longitude;
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  (IconData, String, String?) _renderContent() {
    if (loading || reading == null) {
      return (
        Icons.my_location_rounded,
        'Checking your location…',
        'TripSync uses your location to suggest places nearby.',
      );
    }

    final r = reading!;
    switch (r.outcome) {
      case LocationOutcome.granted:
        final lat = r.latitude?.toStringAsFixed(5) ?? '?';
        final lng = r.longitude?.toStringAsFixed(5) ?? '?';
        final acc = r.accuracyMeters;
        final accLine = acc != null ? ' · ±${acc.toStringAsFixed(0)} m' : '';
        return (
          Icons.location_on_rounded,
          'Location found',
          '$lat, $lng$accLine',
        );
      case LocationOutcome.denied:
        return (
          Icons.location_off_rounded,
          'Location access denied',
          'TripSync needs your location to find nearby places. Tap "Try again" to grant access.',
        );
      case LocationOutcome.deniedForever:
        return (
          Icons.location_disabled_rounded,
          'Location permission turned off',
          'Open Settings → TripSync → Location and switch to "While Using the App".',
        );
      case LocationOutcome.servicesDisabled:
        return (
          Icons.gps_off_rounded,
          'Device location is off',
          'Turn on Location Services in your phone\'s Settings, then tap "Try again".',
        );
      case LocationOutcome.error:
        return (
          Icons.error_outline_rounded,
          'Could not read your location',
          r.errorMessage ?? 'Something went wrong. Tap "Try again".',
        );
    }
  }
}
