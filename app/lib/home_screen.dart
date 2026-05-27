import 'dart:async' show unawaited;
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'app_messenger.dart';
import 'conversation_turn.dart';
import 'groq_orpheus_tts.dart';
import 'groq_poi_narrator.dart';
import 'headset_media_bridge.dart';
import 'location_service.dart';
import 'models/trip_poi.dart';
import 'poi/poi_query_result.dart';
import 'poi/poi_repository.dart';
import 'orbit_groq_config.dart';
import 'preferences/preferences_screen.dart';

/// Home: speaks a place recommendation (headphones / system route), then listens
/// and logs your spoken reply. Background auto-pings are planned for a later build.
class OrbitHomeScreen extends StatefulWidget {
  const OrbitHomeScreen({
    super.key,
    this.userName,
    required this.interests,
  });

  final String? userName;
  final List<String> interests;

  @override
  State<OrbitHomeScreen> createState() => _OrbitHomeScreenState();
}

class _OrbitHomeScreenState extends State<OrbitHomeScreen> {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  final LocationService _locationService = const LocationService();
  final PoiRepository _poiRepository = PoiRepository();

  static const String _fallbackRecommendation =
      'No matching places nearby yet. Try moving closer to a park or landmark, or check back after we add more spots.';

  String _placeRecommendation = _fallbackRecommendation;
  TripPoi? _selectedPoi;
  bool _poiLoading = true;
  String? _nearbyPlaceLine;
  final List<ConversationTurn> _conversationHistory = [];
  bool _followUpLoading = false;

  bool _voiceReady = false;
  bool _voiceUnsupported = false;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _sessionBusy = false;
  bool _heardFinalThisSession = false;
  bool _conversationActive = false;

  /// How long you can pause mid-sentence before Orbit treats your turn as done.
  static const Duration _pauseBeforeSend = Duration(seconds: 3);

  String _statusMessage = 'Getting ready…';
  /// Always updated when Orbit speaks so you can see which engine was used.
  String _voiceEngineLabel = 'Voice: checking…';
  String? _liveTranscript;

  LocationReading? _locationReading;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocationAndNearbyPoi();
    });
  }

  Future<void> _loadLocationAndNearbyPoi() async {
    await _ensureLocation();
    await _fetchNearbyPoi();
    if (!mounted) return;
    await _bootstrapVoice();
  }

  Future<void> _fetchNearbyPoi() async {
    final reading = _locationReading;
    if (reading == null || !reading.isGranted) {
      if (!mounted) return;
      setState(() {
        _poiLoading = false;
        _selectedPoi = null;
        _placeRecommendation = _fallbackRecommendation;
        _nearbyPlaceLine = null;
        if (reading != null) {
          _statusMessage = 'Turn on location to find places near you.';
        }
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _poiLoading = true;
      _nearbyPlaceLine = null;
      _statusMessage = 'Finding places near you…';
    });

    final result = await _poiRepository.findBestNearby(
      latitude: reading.latitude!,
      longitude: reading.longitude!,
      interestTags: widget.interests,
    );

    developer.log(
      'nearby=${result.nearbyCount} tagged=${result.taggedCount} '
      'tagFallback=${result.usedTagFallback} nearestFallback=${result.usedNearestFallback} '
      'poi=${result.poi?.id} err=${result.errorMessage}',
      name: 'Orbit.poi_query',
    );

    if (!mounted) return;
    setState(() {
      _poiLoading = false;
      _selectedPoi = result.poi;
      _placeRecommendation =
          result.poi?.recommendationBlurb ?? _fallbackRecommendation;
      _nearbyPlaceLine = _nearbyPlaceSubtitle(result);
      if (result.hasError) {
        _statusMessage = _friendlyError(result.errorMessage);
      }
    });

    await _enrichRecommendationWithGroq();
  }

  Future<void> _enrichRecommendationWithGroq() async {
    final poi = _selectedPoi;
    if (poi == null) return;

    final apiKey = groqApiKeyFromEnvironment();
    if (apiKey.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Orbit is researching ${poi.name}…';
    });

    final narration = await GroqPoiNarrator.narrate(
      apiKey: apiKey,
      poi: poi,
      userInterests: widget.interests,
      fallback: poi.recommendationBlurb,
    );

    if (!mounted) return;
    setState(() {
      _placeRecommendation = narration.script;
    });
  }

  String? _nearbyPlaceSubtitle(PoiQueryResult result) {
    final poi = result.poi;
    if (poi == null) return null;

    final distanceFt = poi.distanceMeters != null
        ? (poi.distanceMeters! * 3.28084).round()
        : null;
    if (distanceFt != null) {
      return '${poi.name} · ~$distanceFt ft away';
    }
    return poi.name;
  }

  String _friendlyError(String? raw) {
    final msg = raw?.toLowerCase() ?? '';
    if (msg.contains('permission') || msg.contains('denied')) {
      return 'Could not load places. Check your connection and try again.';
    }
    if (msg.contains('firestore') || msg.contains('seed')) {
      return 'No places loaded yet. Try again in a moment.';
    }
    if (msg.contains('within') && msg.contains('mi')) {
      return 'Nothing nearby right now. Try again when you are closer.';
    }
    return 'Something went wrong. Tap Try again on location.';
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
      await HeadsetMediaBridge.instance.disarm();
      await _tts.stop();
      await _speech.stop();
      await _speech.cancel();
    }());
    super.dispose();
  }

  void _onHeadsetPauseEndConversation() {
    if (!mounted || !_conversationActive) return;
    unawaited(_endConversation());
  }

  Future<void> _armHeadsetPauseControls() async {
    if (kIsWeb) return;
    await HeadsetMediaBridge.instance.arm(
      onPausePressed: _onHeadsetPauseEndConversation,
    );
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
      await HeadsetMediaBridge.instance.configureVoiceSession();
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
            name: 'Orbit.stt_error',
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

      await reloadGroqConfigIfNeeded();
      final groqKey = groqApiKeyFromEnvironment();
      setState(() {
        _voiceReady = true;
        _voiceEngineLabel = groqKey.isNotEmpty
            ? 'Voice: Orbit (Groq) ready'
            : 'Voice: phone only — GROQ_API_KEY not loaded';
        _statusMessage = groqKey.isNotEmpty
            ? 'Starting…'
            : 'Starting with phone voice — add GROQ_API_KEY to app/.env and rebuild.';
      });
      if (groqKey.isEmpty) {
        showOrbitSnack(
          'Orbit voice off: GROQ_API_KEY missing. Use app/.env and run flutter run from app/.',
        );
      }
      await _runSpeakThenListen();
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.voice_boot', stackTrace: st);
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
        _statusMessage =
            'Listening — pause when done, or tap AirPods pause to end.';
      });
      return;
    }

    if (status == 'notListening' || status == 'done') {
      if (!mounted) return;
      setState(() => _isListening = false);
      if (!_heardFinalThisSession && _conversationActive) {
        final fallback = _liveTranscript?.trim() ?? '';
        if (fallback.isNotEmpty) {
          _heardFinalThisSession = true;
          unawaited(_handleVoiceReply(fallback));
        } else if (!_isSpeaking && !_followUpLoading) {
          setState(() {
            _sessionBusy = false;
            _statusMessage =
                'Did not catch that. Keep talking after Orbit speaks.';
          });
        }
      } else if (!_conversationActive && !_sessionBusy) {
        setState(() => _sessionBusy = false);
      }
    }
  }

  Future<void> _runSpeakThenListen() async {
    if (!_voiceReady || _voiceUnsupported || !mounted) return;

    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();

    if (!mounted) return;
    setState(() {
      _conversationActive = true;
      _sessionBusy = true;
      _heardFinalThisSession = false;
      _liveTranscript = null;
      _conversationHistory.clear();
      _conversationHistory.add(
        ConversationTurn(isUser: false, text: _placeRecommendation),
      );
      _followUpLoading = false;
      _isSpeaking = true;
      _statusMessage =
          'Orbit is speaking… (AirPods pause ends conversation)';
    });

    final spoke = await _speakScript(_placeRecommendation);
    if (!spoke) return;

    if (!mounted) return;
    await _startListening();
  }

  /// Listens until you pause briefly (~3s), then sends your words to Orbit.
  String _shortTtsError(Object error) {
    final text = error.toString();
    if (text.contains('429')) return 'rate limited';
    if (text.contains('401')) return 'invalid API key';
    if (text.contains('GroqOrpheusTtsException')) {
      return text.replaceFirst('GroqOrpheusTtsException', '').trim();
    }
    return 'playback error';
  }

  Future<void> _startListening() async {
    if (!_voiceReady || _voiceUnsupported || !mounted) return;

    await HeadsetMediaBridge.instance.configureVoiceSession();

    setState(() {
      _conversationActive = true;
      _heardFinalThisSession = false;
      _liveTranscript = null;
      _isListening = true;
      _sessionBusy = true;
      _statusMessage =
          'Listening — pause when done, or tap AirPods pause to end.';
    });

    await _armHeadsetPauseControls();

    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || !_voiceReady || !_conversationActive) return;

    try {
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          setState(() => _liveTranscript = r.recognizedWords);
          if (r.finalResult) {
            final text = r.recognizedWords.trim();
            if (text.isEmpty || _heardFinalThisSession) return;
            _heardFinalThisSession = true;
            unawaited(_handleVoiceReply(text));
          }
        },
        listenFor: const Duration(seconds: 90),
        pauseFor: _pauseBeforeSend,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.listen', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _conversationActive = false;
        _sessionBusy = false;
        _isListening = false;
        _statusMessage = 'Could not start listening. Tap Listen again.';
      });
    }
  }

  Future<void> _endConversation() async {
    if (!_conversationActive) return;
    _conversationActive = false;
    _heardFinalThisSession = true;
    await HeadsetMediaBridge.instance.disarm();
    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();

    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isSpeaking = false;
      _sessionBusy = false;
      _followUpLoading = false;
      _statusMessage =
          'Conversation ended. Tap Listen again to start over.';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation ended.')),
      );
    }
  }

  void _setVoiceEngineLabel(String label) {
    if (!mounted) return;
    setState(() => _voiceEngineLabel = label);
  }

  void _notifyVoiceFallback(String reason) {
    final message = 'Orbit voice unavailable ($reason). Using phone voice.';
    _setVoiceEngineLabel('Voice: phone (fallback — $reason)');
    showOrbitSnack(message);
    developer.log(message, name: 'Orbit.tts_route');
  }

  Future<void> _speakWithDeviceVoice(String spoken, String reason) async {
    _notifyVoiceFallback(reason);
    await _tts.speak(spoken);
  }

  /// Speaks [raw] via Groq Orpheus or on-device TTS. Returns false if playback failed.
  Future<bool> _speakScript(String raw) async {
    final spoken = _ttsPhrase(raw);
    await reloadGroqConfigIfNeeded();
    final groqKey = groqApiKeyFromEnvironment();
    await HeadsetMediaBridge.instance.disarm();
    try {
      if (groqKey.isEmpty) {
        developer.log(
          'GROQ_API_KEY missing — using on-device TTS',
          name: 'Orbit.tts_route',
        );
        await _speakWithDeviceVoice(spoken, 'no API key in app');
        return true;
      }

      _setVoiceEngineLabel('Voice: Orbit (Groq)…');
      await HeadsetMediaBridge.instance.configurePlaybackSession();
      developer.log(
        'Using Groq Orpheus voice (${spoken.length} chars)',
        name: 'Orbit.tts_route',
      );
      await GroqOrpheusTts.speakLongEnglish(
        apiKey: groqKey,
        plainText: spoken,
        voice: 'troy',
        onExternalPause: _onHeadsetPauseEndConversation,
      );
      _setVoiceEngineLabel('Voice: Orbit (Groq)');
      return true;
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.tts_speak', stackTrace: st);
      if (groqKey.isNotEmpty) {
        developer.log(
          'Groq voice failed, falling back to on-device TTS: $e',
          name: 'Orbit.tts_route',
        );
        try {
          await _speakWithDeviceVoice(spoken, _shortTtsError(e));
          return true;
        } catch (e2, st2) {
          developer.log('$e2', name: 'Orbit.tts_fallback', stackTrace: st2);
        }
      }
      if (!mounted) return false;
      setState(() {
        _sessionBusy = false;
        _isSpeaking = false;
        _voiceEngineLabel = 'Voice: failed — check volume and network';
        _statusMessage = groqKey.isNotEmpty
            ? 'Could not play audio (Groq and on-device). Check network and volume.'
            : 'Could not play audio. Check volume and try replay.';
      });
      return false;
    }
  }

  Future<void> _handleVoiceReply(String text) async {
    await _speech.stop();

    final user = widget.userName?.trim();
    final prefix =
        user != null && user.isNotEmpty ? 'user=$user' : 'user=anonymous';

    debugPrint('[$prefix] place_response (voice): $text');
    developer.log(
      '[$prefix] place_response (voice): $text',
      name: 'Orbit.place_response',
    );

    if (!mounted) return;
    final priorTurns = List<ConversationTurn>.from(_conversationHistory);
    setState(() {
      _sessionBusy = true;
      _followUpLoading = true;
      _conversationHistory.add(ConversationTurn(isUser: true, text: text));
      _statusMessage = 'Thinking about your question…';
    });

    final apiKey = groqApiKeyFromEnvironment();
    final narration = await GroqPoiNarrator.replyToFollowUp(
      apiKey: apiKey,
      userTranscript: text,
      orbitSuggestion: _placeRecommendation,
      poi: _selectedPoi,
      userInterests: widget.interests,
      priorTurns: priorTurns,
    );

    developer.log(
      'follow_up search=${narration.usedWebSearch} sources=${narration.sourceUrls.length}',
      name: 'Orbit.groq_follow_up',
    );

    if (!mounted) return;
    setState(() {
      _followUpLoading = false;
      _conversationHistory.add(
        ConversationTurn(isUser: false, text: narration.script),
      );
      _isSpeaking = true;
      _statusMessage = 'Answering your question…';
    });

    final spoke = await _speakScript(narration.script);
    if (!mounted) return;

    if (!mounted) return;

    if (_conversationActive) {
      setState(() {
        _isSpeaking = false;
        _statusMessage = spoke
            ? 'Orbit replied — listening when you are ready.'
            : 'Answer is on screen — listening when you are ready.';
      });
      await _startListening();
      return;
    }

    setState(() {
      _isSpeaking = false;
      _sessionBusy = false;
      _statusMessage = spoke
          ? 'Tap Listen again for another round.'
          : 'Answer is on screen. Tap Listen again to retry voice.';
    });

    if (mounted && spoke) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Orbit replied.')),
      );
    }
  }

  Future<void> _openPreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign in to manage preferences.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreferencesScreen(
          userId: uid,
          userName: widget.userName,
        ),
      ),
    );
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
                        IconButton(
                          tooltip: 'Preferences',
                          onPressed: _openPreferences,
                          icon: Icon(
                            Icons.settings_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nearby',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_conversationHistory.isEmpty)
                      Text(
                        _placeRecommendation,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.35,
                        ),
                      ),
                    if (_nearbyPlaceLine != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _nearbyPlaceLine!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (_poiLoading) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Finding places near you…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _LocationPanel(
                      loading: _locationLoading,
                      reading: _locationReading,
                      onRetry: () {
                        setState(() {
                          _locationLoading = true;
                          _poiLoading = true;
                        });
                        _loadLocationAndNearbyPoi();
                      },
                    ),
                    if (_conversationHistory.isNotEmpty || _followUpLoading) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Conversation',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._conversationHistory.map(
                        (turn) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                turn.isUser ? 'You' : 'Orbit',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: turn.isUser
                                      ? Colors.white.withValues(alpha: 0.55)
                                      : theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                turn.text,
                                style: (turn.isUser
                                        ? theme.textTheme.bodyMedium
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                  color: Colors.white.withValues(
                                    alpha: turn.isUser ? 0.85 : 0.92,
                                  ),
                                  fontStyle: turn.isUser
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_followUpLoading) ...[
                        Text(
                          'Orbit',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Researching an answer…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.65),
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (_conversationHistory.any((t) => t.isUser)) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Doesn\'t look right? Tap Listen again and ask once more.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
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
                          const SizedBox(height: 8),
                          Text(
                            _voiceEngineLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _voiceEngineLabel.contains('Orbit (Groq)')
                                  ? theme.colorScheme.primary
                                  : Colors.orange.shade300,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                          if (_liveTranscript != null &&
                              _liveTranscript!.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Hearing you',
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
                    if (_conversationActive &&
                        (_isListening || _isSpeaking || _followUpLoading)) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              _followUpLoading ? null : _endConversation,
                          child: const Text('End conversation'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: (!_voiceReady ||
                                _voiceUnsupported ||
                                _sessionBusy ||
                                _followUpLoading ||
                                _isSpeaking)
                            ? null
                            : () {
                                _conversationActive = false;
                                _runSpeakThenListen();
                              },
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(
                          _conversationActive
                              ? 'Start over'
                              : 'Listen again',
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
        'Orbit uses your location to suggest places nearby.',
      );
    }

    final r = reading!;
    switch (r.outcome) {
      case LocationOutcome.granted:
        final lat = r.latitude;
        final lng = r.longitude;
        final accLine = r.accuracyMeters != null
            ? ' (${r.accuracyMeters!.round()} m accuracy)'
            : '';
        final coordsDetail = lat != null && lng != null
            ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}$accLine'
            : 'Using your position to find nearby spots.';
        return (
          Icons.location_on_rounded,
          'Location found',
          coordsDetail,
        );
      case LocationOutcome.denied:
        return (
          Icons.location_off_rounded,
          'Location access denied',
          'Orbit needs your location to find nearby places. Tap "Try again" to grant access.',
        );
      case LocationOutcome.deniedForever:
        return (
          Icons.location_disabled_rounded,
          'Location permission turned off',
          'Open Settings → Orbit → Location and switch to "While Using the App".',
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
