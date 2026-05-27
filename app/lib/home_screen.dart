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
import 'onboarding/firestore_preferences_service.dart';
import 'onboarding/preferences_service.dart';
import 'poi/poi_repository.dart';
import 'orbit_groq_config.dart';
import 'preferences/preferences_screen.dart';

enum _InputMode { voice, keyboard }

/// Home: three vertical thirds — map, chat, input. Input is either a
/// large voice mic or a typed text box, toggled inline.
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
  final PreferencesService _preferencesService = FirestorePreferencesService();

  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _textInputController = TextEditingController();
  final FocusNode _textInputFocus = FocusNode();

  late List<String> _currentInterests;
  _InputMode _inputMode = _InputMode.voice;

  static const String _fallbackRecommendation =
      'No matching places nearby yet. Try moving closer to a park or landmark, or check back after we add more spots.';

  String _placeRecommendation = _fallbackRecommendation;
  TripPoi? _selectedPoi;
  bool _poiLoading = true;
  final List<ConversationTurn> _conversationHistory = [];
  bool _followUpLoading = false;

  bool _voiceReady = false;
  bool _voiceUnsupported = false;
  bool _isSpeaking = false;
  bool _isListening = false;
  bool _sessionBusy = false;
  bool _heardFinalThisSession = false;
  bool _conversationActive = false;
  bool _sendingText = false;

  /// How long you can pause mid-sentence before Orbit treats your turn as done.
  static const Duration _pauseBeforeSend = Duration(seconds: 3);

  String _statusMessage = 'Getting ready…';
  String? _liveTranscript;

  LocationReading? _locationReading;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _currentInterests = List.of(widget.interests);
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
        if (reading != null) {
          _statusMessage = 'Turn on location to find places near you.';
        }
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _poiLoading = true;
      _statusMessage = 'Finding places near you…';
    });

    final result = await _poiRepository.findBestNearby(
      latitude: reading.latitude!,
      longitude: reading.longitude!,
      interestTags: _currentInterests,
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
      userInterests: _currentInterests,
      fallback: poi.recommendationBlurb,
    );

    if (!mounted) return;
    setState(() {
      _placeRecommendation = narration.script;
    });
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
    return 'Something went wrong. Try again from settings.';
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
    _chatScrollController.dispose();
    _textInputController.dispose();
    _textInputFocus.dispose();
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
        _statusMessage = 'Voice needs iOS or Android. Use keyboard mode here.';
        _inputMode = _InputMode.keyboard;
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
          _statusMessage = 'Mic unavailable. Use keyboard mode to chat.';
          _inputMode = _InputMode.keyboard;
        });
        return;
      }

      await reloadGroqConfigIfNeeded();
      final groqKey = groqApiKeyFromEnvironment();
      setState(() {
        _voiceReady = true;
        _statusMessage = groqKey.isNotEmpty
            ? 'Tap the mic to start, or switch to keyboard.'
            : 'Add GROQ_API_KEY for full voice. Phone voice is on.';
      });
      if (groqKey.isEmpty) {
        showOrbitSnack(
          'Orbit voice fallback active: add GROQ_API_KEY to app/.env.',
        );
      }
      // Auto-greet on first load via voice mode (default).
      await _runSpeakThenListen();
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.voice_boot', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _voiceUnsupported = true;
        _statusMessage = 'Voice setup failed. Use keyboard mode to chat.';
        _inputMode = _InputMode.keyboard;
      });
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'listening') {
      setState(() {
        _isListening = true;
        _statusMessage = 'Listening — pause when you are done.';
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
          unawaited(_handleUserReply(fallback, source: _ReplySource.voice));
        } else if (!_isSpeaking && !_followUpLoading) {
          setState(() {
            _sessionBusy = false;
            _statusMessage = 'Did not catch that. Tap the mic to retry.';
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
      _statusMessage = 'Orbit is speaking…';
    });
    _scrollChatToBottom();

    final spoke = await _speakScript(_placeRecommendation);
    if (!spoke) return;
    if (!mounted) return;

    if (_inputMode == _InputMode.voice) {
      await _startListening();
    } else {
      setState(() {
        _isSpeaking = false;
        _sessionBusy = false;
        _statusMessage = 'Type a follow-up to keep the conversation going.';
      });
    }
  }

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
    if (_inputMode != _InputMode.voice) return;

    await HeadsetMediaBridge.instance.configureVoiceSession();

    setState(() {
      _conversationActive = true;
      _heardFinalThisSession = false;
      _liveTranscript = null;
      _isListening = true;
      _isSpeaking = false;
      _sessionBusy = true;
      _statusMessage = 'Listening — pause when done.';
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
            unawaited(_handleUserReply(text, source: _ReplySource.voice));
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
        _statusMessage = 'Could not start listening. Tap the mic again.';
      });
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _sessionBusy = false;
      _statusMessage = 'Stopped listening. Tap the mic to resume.';
    });
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
      _statusMessage = 'Conversation ended. Tap the mic to start again.';
    });
  }

  void _notifyVoiceFallback(String reason) {
    final message = 'Orbit voice unavailable ($reason). Using phone voice.';
    showOrbitSnack(message);
    developer.log(message, name: 'Orbit.tts_route');
  }

  Future<void> _speakWithDeviceVoice(String spoken, String reason) async {
    _notifyVoiceFallback(reason);
    await _tts.speak(spoken);
  }

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
      return true;
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.tts_speak', stackTrace: st);
      if (groqKey.isNotEmpty) {
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
        _statusMessage = 'Could not play audio. Check network and volume.';
      });
      return false;
    }
  }

  Future<void> _handleTextSend() async {
    final text = _textInputController.text.trim();
    if (text.isEmpty || _sendingText) return;
    _textInputController.clear();
    setState(() => _sendingText = true);
    try {
      await _handleUserReply(text, source: _ReplySource.text);
    } finally {
      if (mounted) setState(() => _sendingText = false);
    }
  }

  Future<void> _handleUserReply(
    String text, {
    required _ReplySource source,
  }) async {
    if (source == _ReplySource.voice) {
      await _speech.stop();
    }

    final user = widget.userName?.trim();
    final prefix =
        user != null && user.isNotEmpty ? 'user=$user' : 'user=anonymous';
    developer.log(
      '[$prefix] place_response (${source.name}): $text',
      name: 'Orbit.place_response',
    );

    if (!mounted) return;
    final priorTurns = List<ConversationTurn>.from(_conversationHistory);
    setState(() {
      _sessionBusy = true;
      _followUpLoading = true;
      _conversationActive = true;
      _conversationHistory.add(ConversationTurn(isUser: true, text: text));
      _statusMessage = 'Thinking about your question…';
    });
    _scrollChatToBottom();

    final apiKey = groqApiKeyFromEnvironment();
    final narration = await GroqPoiNarrator.replyToFollowUp(
      apiKey: apiKey,
      userTranscript: text,
      orbitSuggestion: _placeRecommendation,
      poi: _selectedPoi,
      userInterests: _currentInterests,
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
      _isSpeaking = source == _ReplySource.voice;
      _statusMessage = source == _ReplySource.voice
          ? 'Answering your question…'
          : 'Orbit replied.';
    });
    _scrollChatToBottom();

    // Only speak aloud when the user is in voice mode; keyboard users
    // generally don't want surprise audio playback.
    var spoke = true;
    if (source == _ReplySource.voice) {
      spoke = await _speakScript(narration.script);
    }
    if (!mounted) return;

    if (_inputMode == _InputMode.voice && _conversationActive) {
      setState(() {
        _isSpeaking = false;
        _statusMessage = spoke
            ? 'Orbit replied — listening when you are ready.'
            : 'Reply is on screen — tap the mic to keep going.';
      });
      await _startListening();
      return;
    }

    setState(() {
      _isSpeaking = false;
      _sessionBusy = false;
      _statusMessage = source == _ReplySource.voice
          ? 'Tap the mic again for another round.'
          : 'Type another message to keep chatting.';
    });
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openSettings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to manage preferences.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreferencesScreen(
          userId: user.uid,
          userName: widget.userName,
        ),
      ),
    );
    // After returning from preferences, re-pull saved tags and refresh
    // the POI pick if anything actually changed.
    if (!mounted) return;
    try {
      final latest = await _preferencesService.load(user.uid);
      final updated = latest?.interests.toList() ?? const <String>[];
      final changed = updated.length != _currentInterests.length ||
          !updated.toSet().containsAll(_currentInterests);
      if (changed) {
        setState(() => _currentInterests = updated);
        await _fetchNearbyPoi();
      }
    } catch (_) {
      // Best-effort refresh; ignore failures here since prefs already saved.
    }
  }

  void _setInputMode(_InputMode mode) {
    if (mode == _inputMode) return;
    setState(() => _inputMode = mode);
    if (mode == _InputMode.keyboard) {
      unawaited(_speech.stop());
      // Cancel a pending auto-listen if Orbit just finished speaking.
      if (_isListening) {
        unawaited(_stopListening());
      }
    } else if (mode == _InputMode.voice && _conversationActive && !_isSpeaking) {
      unawaited(_startListening());
    }
  }

  String _firstName() {
    final raw = widget.userName?.trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.split(RegExp(r'[\s@]')).first;
  }

  @override
  Widget build(BuildContext context) {
    final first = _firstName();
    final greeting = first.isEmpty ? "Let's explore!" : "Hi $first, let's explore!";

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
          child: Column(
            children: [
              _HomeHeader(
                greeting: greeting,
                onOpenSettings: _openSettings,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final third = constraints.maxHeight / 3;
                    return Column(
                      children: [
                        SizedBox(
                          height: third,
                          child: _HomeMapSection(
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
                        ),
                        SizedBox(
                          height: third,
                          child: _ChatSection(
                            history: _conversationHistory,
                            scrollController: _chatScrollController,
                            isThinking: _followUpLoading,
                            poiLoading: _poiLoading &&
                                _conversationHistory.isEmpty,
                          ),
                        ),
                        SizedBox(
                          height: third,
                          child: _InputSection(
                            mode: _inputMode,
                            onModeChanged: _setInputMode,
                            voiceReady: _voiceReady && !_voiceUnsupported,
                            isListening: _isListening,
                            isSpeaking: _isSpeaking,
                            sessionBusy: _sessionBusy,
                            statusMessage: _statusMessage,
                            liveTranscript: _liveTranscript,
                            onMicPressed: () {
                              if (_isListening) {
                                _stopListening();
                              } else if (_isSpeaking || _sessionBusy) {
                                // Treat as cancel: end and start fresh.
                                _endConversation();
                              } else {
                                _conversationActive = true;
                                _startListening();
                              }
                            },
                            textController: _textInputController,
                            textFocus: _textInputFocus,
                            sending: _sendingText || _followUpLoading,
                            onSend: _handleTextSend,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReplySource { voice, text }

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, required this.onOpenSettings});

  final String greeting;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              greeting,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_rounded),
            color: Colors.white.withValues(alpha: 0.9),
            iconSize: 26,
          ),
        ],
      ),
    );
  }
}

class _HomeMapSection extends StatelessWidget {
  const _HomeMapSection({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _buildMapBody(theme),
      ),
    );
  }

  Widget _buildMapBody(ThemeData theme) {
    if (loading || reading == null) {
      return _MapPlaceholder(
        icon: Icons.my_location_rounded,
        title: 'Finding your location…',
        subtitle:
            'Orbit uses your location to suggest places nearby.',
        theme: theme,
      );
    }

    final r = reading!;
    if (r.isGranted && r.latitude != null && r.longitude != null) {
      return _MapView(latitude: r.latitude!, longitude: r.longitude!);
    }

    final (icon, title, subtitle) = switch (r.outcome) {
      LocationOutcome.denied => (
          Icons.location_off_rounded,
          'Location access denied',
          'Orbit needs your location to find nearby places. Tap retry.',
        ),
      LocationOutcome.deniedForever => (
          Icons.location_disabled_rounded,
          'Permission turned off',
          'Open Settings → Orbit → Location to enable it.',
        ),
      LocationOutcome.servicesDisabled => (
          Icons.gps_off_rounded,
          'Device location is off',
          'Turn on Location Services then tap retry.',
        ),
      LocationOutcome.error => (
          Icons.error_outline_rounded,
          'Could not read your location',
          r.errorMessage ?? 'Tap retry to try again.',
        ),
      LocationOutcome.granted => (
          Icons.my_location_rounded,
          'Locating…',
          'One moment.',
        ),
    };

    return _MapPlaceholder(
      icon: icon,
      title: title,
      subtitle: subtitle,
      theme: theme,
      onRetry: onRetry,
    );
  }
}

class _MapView extends StatelessWidget {
  const _MapView({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = LatLng(latitude, longitude);
    return FlutterMap(
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
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 26,
              height: 26,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                      blurRadius: 14,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.theme,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ThemeData theme;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.3,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatSection extends StatelessWidget {
  const _ChatSection({
    required this.history,
    required this.scrollController,
    required this.isThinking,
    required this.poiLoading,
  });

  final List<ConversationTurn> history;
  final ScrollController scrollController;
  final bool isThinking;
  final bool poiLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: history.isEmpty && !isThinking
            ? _EmptyChatState(theme: theme, loading: poiLoading)
            : ListView.builder(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: history.length + (isThinking ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == history.length && isThinking) {
                    return const _ThinkingBubble();
                  }
                  return _ChatBubble(turn: history[index]);
                },
              ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.theme, required this.loading});

  final ThemeData theme;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loading ? Icons.travel_explore_rounded : Icons.chat_bubble_outline,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            loading ? 'Finding places near you…' : 'Say hi or type a question.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.turn});

  final ConversationTurn turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = turn.isUser;
    final bg = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.08);
    final fg = Colors.white.withValues(alpha: isUser ? 0.96 : 0.92);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUser ? 'You' : 'Orbit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      turn.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: fg,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Orbit is thinking…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({
    required this.mode,
    required this.onModeChanged,
    required this.voiceReady,
    required this.isListening,
    required this.isSpeaking,
    required this.sessionBusy,
    required this.statusMessage,
    required this.liveTranscript,
    required this.onMicPressed,
    required this.textController,
    required this.textFocus,
    required this.sending,
    required this.onSend,
  });

  final _InputMode mode;
  final ValueChanged<_InputMode> onModeChanged;
  final bool voiceReady;
  final bool isListening;
  final bool isSpeaking;
  final bool sessionBusy;
  final String statusMessage;
  final String? liveTranscript;
  final VoidCallback onMicPressed;
  final TextEditingController textController;
  final FocusNode textFocus;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          children: [
            _ModeToggle(mode: mode, onChanged: onModeChanged),
            const SizedBox(height: 8),
            Expanded(
              child: mode == _InputMode.voice
                  ? _VoiceInputBody(
                      voiceReady: voiceReady,
                      isListening: isListening,
                      isSpeaking: isSpeaking,
                      sessionBusy: sessionBusy,
                      statusMessage: statusMessage,
                      liveTranscript: liveTranscript,
                      onMicPressed: onMicPressed,
                      theme: theme,
                    )
                  : _KeyboardInputBody(
                      controller: textController,
                      focusNode: textFocus,
                      sending: sending,
                      onSend: onSend,
                      statusMessage: statusMessage,
                      theme: theme,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _InputMode mode;
  final ValueChanged<_InputMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget pill(_InputMode value, IconData icon, String label) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(_InputMode.voice, Icons.mic_rounded, 'Voice'),
        const SizedBox(width: 8),
        pill(_InputMode.keyboard, Icons.keyboard_rounded, 'Keyboard'),
      ],
    );
  }
}

class _VoiceInputBody extends StatelessWidget {
  const _VoiceInputBody({
    required this.voiceReady,
    required this.isListening,
    required this.isSpeaking,
    required this.sessionBusy,
    required this.statusMessage,
    required this.liveTranscript,
    required this.onMicPressed,
    required this.theme,
  });

  final bool voiceReady;
  final bool isListening;
  final bool isSpeaking;
  final bool sessionBusy;
  final String statusMessage;
  final String? liveTranscript;
  final VoidCallback onMicPressed;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final transcript = liveTranscript?.trim() ?? '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: _MicButton(
              listening: isListening,
              speaking: isSpeaking,
              busy: sessionBusy && !isListening && !isSpeaking,
              enabled: voiceReady,
              onTap: voiceReady ? onMicPressed : null,
              theme: theme,
            ),
          ),
        ),
        if (transcript.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              transcript,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            statusMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.listening,
    required this.speaking,
    required this.busy,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  final bool listening;
  final bool speaking;
  final bool busy;
  final bool enabled;
  final VoidCallback? onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.colorScheme.primary;
    final color = !enabled
        ? Colors.white.withValues(alpha: 0.18)
        : listening
            ? Colors.redAccent
            : speaking
                ? Colors.amber
                : primary;
    final icon = !enabled
        ? Icons.mic_off_rounded
        : listening
            ? Icons.stop_rounded
            : speaking
                ? Icons.graphic_eq_rounded
                : Icons.mic_rounded;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: 0.95), color],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.06),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: listening ? 0.55 : 0.35),
                    blurRadius: listening ? 28 : 18,
                    spreadRadius: listening ? 2 : 0,
                  ),
                ]
              : null,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
            width: 2,
          ),
        ),
        child: busy
            ? const Center(
                child: SizedBox(
                  height: 28,
                  width: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              )
            : Icon(icon, size: 40, color: Colors.white),
      ),
    );
  }
}

class _KeyboardInputBody extends StatelessWidget {
  const _KeyboardInputBody({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
    required this.statusMessage,
    required this.theme,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;
  final String statusMessage;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    final borderColor = Colors.white.withValues(alpha: 0.12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            enabled: !sending,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Ask Orbit anything about places nearby…',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
              ),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.18),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                statusMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: sending
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(sending ? 'Sending…' : 'Send'),
            ),
          ],
        ),
      ],
    );
  }
}
