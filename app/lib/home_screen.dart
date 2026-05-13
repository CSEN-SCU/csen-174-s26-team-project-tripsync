import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.userName != null &&
                        widget.userName!.trim().isNotEmpty) ...[
                      Text(
                        'Hi, ${widget.userName!.trim()}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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
          '$lat, $lng$accLine — nearby place pings coming next sprint.',
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
