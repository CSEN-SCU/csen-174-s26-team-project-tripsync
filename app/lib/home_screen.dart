import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:voice_interface/voice_interface.dart';

import 'app_messenger.dart';
import 'conversation_turn.dart';
import 'groq_poi_narrator.dart';
import 'headset_media_bridge.dart';
import 'location_service.dart';
import 'models/trip_poi.dart';
import 'onboarding/firestore_preferences_service.dart';
import 'onboarding/preferences_service.dart';
import 'openrouter_tts.dart';
import 'poi/poi_repository.dart';
import 'orbit_groq_config.dart';
import 'preferences/preferences_screen.dart';

enum _InputMode { voice, keyboard }

/// Home: three vertical thirds — map, chat, input. Input is either a
/// large voice mic (with "Orbit"/"over" wake-word session for hands-free
/// follow-ups) or a typed text box, toggled inline.
class OrbitHomeScreen extends StatefulWidget {
  const OrbitHomeScreen({super.key, this.userName, required this.interests});

  final String? userName;
  final List<String> interests;

  @override
  State<OrbitHomeScreen> createState() => _OrbitHomeScreenState();
}

class _OrbitHomeScreenState extends State<OrbitHomeScreen>
    with WidgetsBindingObserver {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speech = SpeechToText();
  final WakeWordSession _wakeSession = WakeWordSession();
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

  /// True for the whole "tapped a new spot → finding + preparing a place"
  /// sequence, so the map and chat can show a clear loading state.
  bool _placeLookupLoading = false;
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
  bool _wakeListenArmed = false;
  bool _passiveWakePaused = false;
  bool _processingVoiceCommand = false;
  bool _handlingPinTap = false;
  bool _startingWakeListen = false;

  /// Bumped on each speak request so a superseded one stops cleanly instead of
  /// playing over a newer clip (e.g. a map tap during the opening greeting).
  int _speakGeneration = 0;
  Timer? _wakeRestartTimer;

  /// STT pause before the OS ends a listen segment (wake loop restarts after).
  static const Duration _wakeListenPause = Duration(seconds: 30);

  String _statusMessage = 'Getting ready…';
  String? _liveTranscript;

  LocationReading? _locationReading;
  bool _locationLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentInterests = List.of(widget.interests);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocationAndNearbyPoi();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(
        _releaseVoiceResources(updateUi: state != AppLifecycleState.detached),
      );
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _voiceReady &&
        !_passiveWakePaused &&
        _inputMode == _InputMode.voice &&
        !_isSpeaking &&
        !_followUpLoading &&
        !_heardFinalThisSession) {
      _scheduleWakeListenRestart();
    }
  }

  void _applyWakeUiState() {
    if (!mounted) return;
    final capturing = _wakeSession.awaitingCommand;
    setState(() {
      _isListening = capturing;
      _statusMessage = capturing
          ? 'Listening — say "over" when you are done.'
          : 'Say "Orbit" to ask a question, then "over" when finished.';
    });
  }

  Future<void> _releaseVoiceResources({bool updateUi = true}) async {
    _wakeRestartTimer?.cancel();
    _speakGeneration++;
    _conversationActive = false;
    _wakeListenArmed = false;
    _startingWakeListen = false;
    _wakeSession.reset();

    if (updateUi && mounted) {
      setState(() {
        _isListening = false;
        _isSpeaking = false;
        _sessionBusy = false;
        _liveTranscript = null;
      });
    }

    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();
    await OpenRouterTts.stop();
    await HeadsetMediaBridge.instance.releaseAudioSession();
  }

  void _scheduleWakeListenRestart() {
    if (_passiveWakePaused || _inputMode != _InputMode.voice) return;
    _wakeRestartTimer?.cancel();
    _wakeRestartTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_startWakeWordListening());
    });
  }

  Future<void> _loadLocationAndNearbyPoi() async {
    await _ensureLocation();
    await _fetchNearbyPoi(deferEnrich: true);
    if (!mounted) return;
    await _initVoice();
    if (!mounted || !_voiceReady) return;
    await _prepareSpokenRecommendation();
    if (!mounted) return;
    await _speakInitialGreeting();
    if (!mounted || _inputMode != _InputMode.voice) return;
    await _startWakeWordListening();
  }

  /// Groq narration for the current POI — must finish before TTS so voice
  /// matches the chat bubble (avoids speaking the generic database blurb).
  Future<void> _prepareSpokenRecommendation() async {
    await _enrichRecommendationWithGroq(useWebSearch: false);
  }

  Future<void> _fetchNearbyPoi({bool deferEnrich = false}) async {
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

    if (!deferEnrich) {
      await _enrichRecommendationWithGroq();
    } else if (mounted && _selectedPoi != null) {
      setState(() {
        _statusMessage = 'Found ${_selectedPoi!.name} nearby.';
      });
    }
  }

  Future<void> _enrichRecommendationWithGroq({bool useWebSearch = true}) async {
    final poi = _selectedPoi;
    if (poi == null) return;

    final apiKey = groqApiKeyFromEnvironment();
    if (apiKey.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Orbit is researching ${poi.name}…';
    });

    try {
      final narration =
          await GroqPoiNarrator.narrate(
            apiKey: apiKey,
            poi: poi,
            userInterests: _currentInterests,
            fallback: poi.recommendationBlurb,
            useWebSearch: useWebSearch,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () => PoiNarration(script: poi.recommendationBlurb),
          );

      if (!mounted) return;
      setState(() {
        _placeRecommendation = narration.script;
        _statusMessage =
            'Say "Orbit" to ask a question, then "over" when finished.';
      });
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.groq_enrich', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Say "Orbit" to ask a question, then "over" when finished.';
      });
    }
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
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_releaseVoiceResources(updateUi: false));
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

  Future<void> _initVoice() async {
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
          if (!mounted || _isSpeaking || _followUpLoading) return;
          if (_passiveWakePaused || _inputMode != _InputMode.voice) return;
          _scheduleWakeListenRestart();
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

      await reloadOpenRouterConfigIfNeeded();
      final openRouterKey = openRouterApiKeyFromEnvironment();
      setState(() {
        _voiceReady = true;
        _statusMessage = openRouterKey.isNotEmpty
            ? 'Say "Orbit" to ask, then "over". Or switch to keyboard.'
            : 'Add OPENROUTER_API_KEY for cloud voice. Phone voice is on.';
      });
      if (openRouterKey.isEmpty) {
        showOrbitSnack(
          'Orbit voice fallback active: add OPENROUTER_API_KEY to app/.env.',
        );
      }
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
    developer.log(
      'status=$status armed=$_wakeListenArmed active=$_conversationActive '
      'speaking=$_isSpeaking awaitingCmd=${_wakeSession.awaitingCommand}',
      name: 'Orbit.stt_status',
    );
    if (status == 'listening') {
      _applyWakeUiState();
      return;
    }

    if (status == 'notListening' || status == 'done') {
      // Do not clear the red mic while capturing a command — OS status events
      // often race ahead of the wake-word partial result.
      if (!_wakeSession.awaitingCommand) {
        setState(() => _isListening = false);
      }
      if (_wakeListenArmed &&
          _conversationActive &&
          !_heardFinalThisSession &&
          !_isSpeaking &&
          !_followUpLoading &&
          _inputMode == _InputMode.voice) {
        if (_wakeSession.awaitingCommand) {
          setState(() {
            _sessionBusy = false;
            _statusMessage =
                'Say "over" when you are done, or say "Orbit" to start again.';
          });
        } else {
          _scheduleWakeListenRestart();
        }
      } else if (!_conversationActive && !_sessionBusy) {
        setState(() => _sessionBusy = false);
      }
    }
  }

  Future<void> _speakInitialGreeting() async {
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
      _statusMessage = 'Orbit is speaking…';
    });
    _scrollChatToBottom();

    final spoke = await _speakScript(_placeRecommendation);
    if (!mounted) return;
    setState(() {
      _sessionBusy = false;
      _statusMessage = spoke
          ? 'Say "Orbit" to ask a question, then "over" when finished.'
          : 'Recommendation is on screen — say "Orbit" to ask a question.';
    });
  }

  String _shortTtsError(Object error) {
    final text = error.toString();
    if (text.contains('429')) return 'rate limited';
    if (text.contains('401')) return 'invalid API key';
    if (text.contains('OpenRouterTtsException')) {
      final reason = text.replaceFirst('OpenRouterTtsException', '').trim();
      return reason.length > 180 ? '${reason.substring(0, 180)}...' : reason;
    }
    return 'playback error';
  }

  void _onWakeWordSttResult(String recognizedWords) {
    if (!mounted ||
        _heardFinalThisSession ||
        _processingVoiceCommand ||
        _isSpeaking ||
        _followUpLoading ||
        !_wakeListenArmed) {
      return;
    }

    final command = _wakeSession.ingest(recognizedWords);
    if (command == null) {
      if (_wakeSession.awaitingCommand) {
        _applyWakeUiState();
      }
      return;
    }

    _heardFinalThisSession = true;
    _wakeListenArmed = false;
    _wakeRestartTimer?.cancel();
    setState(() => _isListening = false);
    _processingVoiceCommand = true;
    unawaited(
      _handleUserReply(command, source: _ReplySource.voice).whenComplete(() {
        _processingVoiceCommand = false;
      }),
    );
  }

  /// Passive mic: always on in voice mode, captures only after "Orbit".
  /// Never call while Orbit is speaking — that cuts off TTS.
  Future<void> _startWakeWordListening() async {
    if (!_voiceReady || _voiceUnsupported || !mounted) {
      developer.log(
        'skip listen: voiceReady=$_voiceReady unsupported=$_voiceUnsupported '
        'mounted=$mounted',
        name: 'Orbit.listen',
      );
      return;
    }
    if (_inputMode != _InputMode.voice || _passiveWakePaused) {
      developer.log(
        'skip listen: mode=$_inputMode paused=$_passiveWakePaused',
        name: 'Orbit.listen',
      );
      return;
    }
    if (_isSpeaking || _followUpLoading || _heardFinalThisSession) {
      developer.log(
        'skip listen: speaking=$_isSpeaking followUp=$_followUpLoading '
        'heardFinal=$_heardFinalThisSession',
        name: 'Orbit.listen',
      );
      return;
    }
    if (_speech.isListening) {
      developer.log('skip listen: already listening', name: 'Orbit.listen');
      return;
    }
    // Prevent two concurrent starts (e.g. the initial-load chain and a map-tap
    // chain both driving the mic) from wedging the recognizer.
    if (_startingWakeListen) {
      developer.log(
        'skip listen: start already in progress',
        name: 'Orbit.listen',
      );
      return;
    }
    _startingWakeListen = true;

    try {
      _wakeRestartTimer?.cancel();
      await _speech.stop();
      await _speech.cancel();
      await HeadsetMediaBridge.instance.configureVoiceSession();

      _wakeSession.reset();
      setState(() {
        _conversationActive = true;
        _wakeListenArmed = true;
        _heardFinalThisSession = false;
        _liveTranscript = null;
        _isListening = false;
        _sessionBusy = true;
        _statusMessage =
            'Say "Orbit" to ask a question, then "over" when you are done.';
      });

      await _armHeadsetPauseControls();

      // Give the OS time to switch the audio route from playback (Orbit's
      // voice) back to record. Too short and listen() starts before the mic is
      // ready, so the next "Orbit" is missed — common right after a narration.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted ||
          !_voiceReady ||
          !_conversationActive ||
          _passiveWakePaused) {
        developer.log(
          'abort listen after settle: mounted=$mounted '
          'active=$_conversationActive paused=$_passiveWakePaused',
          name: 'Orbit.listen',
        );
        return;
      }

      developer.log('listen: starting', name: 'Orbit.listen');
      await _speech.listen(
        onResult: (r) {
          if (!mounted || !_wakeListenArmed) return;
          setState(
            () => _liveTranscript = wakeSessionTranscriptPreview(
              r.recognizedWords,
            ),
          );
          if (_wakeSession.noteWakeIfNeeded(r.recognizedWords)) {
            _applyWakeUiState();
          }
          // Submit as soon as "over" is heard (partial or final) — ingest only
          // returns a command when the phrase ends with "over", and the
          // re-entry guards below prevent a double submit.
          _onWakeWordSttResult(r.recognizedWords);
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: _wakeListenPause,
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
        ),
      );
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.listen', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _wakeListenArmed = false;
        _sessionBusy = false;
        _isListening = false;
        _statusMessage = 'Could not start listening. Say "Orbit" to try again.';
      });
      _scheduleWakeListenRestart();
    } finally {
      _startingWakeListen = false;
    }
  }

  Future<void> _stopPassiveWakeListening() async {
    _passiveWakePaused = true;
    _wakeListenArmed = false;
    _speakGeneration++;
    _wakeRestartTimer?.cancel();
    _wakeSession.reset();
    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();
    await OpenRouterTts.stop();
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _sessionBusy = false;
      _statusMessage = 'Mic paused. Tap to resume hands-free mode.';
    });
  }

  Future<void> _endConversation() async {
    if (!_conversationActive && !_wakeListenArmed) return;
    _conversationActive = false;
    _wakeListenArmed = false;
    _heardFinalThisSession = true;
    _speakGeneration++;
    _wakeSession.reset();
    await HeadsetMediaBridge.instance.disarm();
    await _speech.stop();
    await _speech.cancel();
    await _tts.stop();
    await OpenRouterTts.stop();

    if (!mounted) return;
    setState(() {
      _isListening = false;
      _isSpeaking = false;
      _sessionBusy = false;
      _followUpLoading = false;
      _statusMessage = 'Conversation ended. Tap the mic for hands-free again.';
    });
  }

  void _notifyVoiceFallback(String reason) {
    final message = 'Orbit voice unavailable ($reason). Using phone voice.';
    showOrbitSnack(message);
    developer.log(message, name: 'Orbit.tts_route');
  }

  Future<void> _speakWithDeviceVoice(String spoken, String reason) async {
    _notifyVoiceFallback(reason);
    final myGen = _speakGeneration;
    await _tts.stop();
    final chunks = OpenRouterTts.chunkPlainText(spoken, maxChunkChars: 350);
    for (var i = 0; i < chunks.length; i++) {
      if (myGen != _speakGeneration) return;
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await _tts.speak(chunks[i]);
    }
  }

  Future<bool> _speakScript(String raw) async {
    if (!mounted) return false;

    // Supersede any prior speak: stop the mic, the device voice, and any
    // in-flight cloud TTS clip so two voices never overlap.
    final myGen = ++_speakGeneration;
    await _speech.stop();
    await _speech.cancel();
    _wakeListenArmed = false;
    _wakeSession.reset();
    await HeadsetMediaBridge.instance.disarm();
    await _tts.stop();
    await OpenRouterTts.stop();

    if (!mounted || myGen != _speakGeneration) return false;

    setState(() {
      _isListening = false;
      _isSpeaking = true;
      _liveTranscript = null;
    });

    final spoken = _ttsPhrase(raw);
    await reloadOpenRouterConfigIfNeeded();
    final openRouterKey = openRouterApiKeyFromEnvironment();
    try {
      if (myGen != _speakGeneration) return false;
      if (openRouterKey.isEmpty) {
        developer.log(
          'OPENROUTER_API_KEY missing — using on-device TTS',
          name: 'Orbit.tts_route',
        );
        await _speakWithDeviceVoice(spoken, 'no API key in app');
        return true;
      }

      await HeadsetMediaBridge.instance.configurePlaybackSession();
      developer.log(
        'Using OpenRouter TTS voice (${spoken.length} chars)',
        name: 'Orbit.tts_route',
      );
      await OpenRouterTts.speakLongEnglish(
        apiKey: openRouterKey,
        plainText: spoken,
        userId: FirebaseAuth.instance.currentUser?.uid,
        onExternalPause: _onHeadsetPauseEndConversation,
      );
      return true;
    } catch (e, st) {
      if (myGen != _speakGeneration) return false;
      developer.log('$e', name: 'Orbit.tts_speak', stackTrace: st);
      if (openRouterKey.isNotEmpty) {
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
        _statusMessage = 'Could not play audio. Check network and volume.';
      });
      return false;
    } finally {
      // Only the latest speak should flip the speaking flag off.
      if (mounted && myGen == _speakGeneration) {
        setState(() => _isSpeaking = false);
      }
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
    String cleaned;
    if (source == _ReplySource.voice) {
      _wakeListenArmed = false;
      await _speech.stop();
      await _speech.cancel();
      _wakeSession.reset();
      cleaned = normalizeTranscriptForConversation(text);
      if (cleaned.isEmpty) {
        if (!mounted) return;
        setState(() {
          _sessionBusy = false;
          _followUpLoading = false;
          _heardFinalThisSession = false;
          _statusMessage =
              'Did not catch a question. Say "Orbit", ask, then "over".';
        });
        if (_inputMode == _InputMode.voice) {
          await _startWakeWordListening();
        }
        return;
      }
    } else {
      cleaned = text.trim();
      if (cleaned.isEmpty) return;
    }

    final user = widget.userName?.trim();
    final prefix = user != null && user.isNotEmpty
        ? 'user=$user'
        : 'user=anonymous';
    developer.log(
      '[$prefix] place_response (${source.name}): $cleaned',
      name: 'Orbit.place_response',
    );

    if (!mounted) return;
    final priorTurns = List<ConversationTurn>.from(_conversationHistory);
    setState(() {
      _sessionBusy = true;
      _followUpLoading = true;
      _conversationActive = true;
      _conversationHistory.add(ConversationTurn(isUser: true, text: cleaned));
      _statusMessage = 'Thinking about your question…';
    });
    _scrollChatToBottom();

    final apiKey = groqApiKeyFromEnvironment();
    final narration = await GroqPoiNarrator.replyToFollowUp(
      apiKey: apiKey,
      userTranscript: cleaned,
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
      _statusMessage = source == _ReplySource.voice
          ? 'Answering your question…'
          : 'Orbit replied.';
    });
    _scrollChatToBottom();

    // Speak the answer for everything except typed/keyboard questions, which
    // get a text-only reply (no surprise audio playback).
    var spoke = true;
    if (source != _ReplySource.text) {
      spoke = await _speakScript(narration.script);
    }
    if (!mounted) return;

    if (_inputMode == _InputMode.voice && _conversationActive) {
      setState(() {
        _heardFinalThisSession = false;
        _sessionBusy = false;
        _statusMessage = spoke
            ? 'Say "Orbit" to ask again, then "over" when finished.'
            : 'Answer is on screen — say "Orbit" to ask again.';
      });
      await _startWakeWordListening();
      return;
    }

    setState(() {
      _sessionBusy = false;
      _statusMessage = source == _ReplySource.voice
          ? 'Say "Orbit" to ask another question.'
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
        builder: (_) =>
            PreferencesScreen(userId: user.uid, userName: widget.userName),
      ),
    );
    // After returning from preferences, re-pull saved tags and refresh
    // the POI pick if anything actually changed.
    if (!mounted) return;
    try {
      final latest = await _preferencesService.load(user.uid);
      final updated = latest?.interests.toList() ?? const <String>[];
      final changed =
          updated.length != _currentInterests.length ||
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
      unawaited(_stopPassiveWakeListening());
    } else {
      _passiveWakePaused = false;
      setState(() => _conversationActive = true);
      unawaited(_startWakeWordListening());
    }
  }

  void _showPoiRecommendationInChat() {
    if (!mounted) return;
    setState(() {
      _conversationActive = true;
      _heardFinalThisSession = false;
      _liveTranscript = null;
      _conversationHistory
        ..clear()
        ..add(ConversationTurn(isUser: false, text: _placeRecommendation));
    });
    _scrollChatToBottom();
  }

  Future<void> _speakPoiUpdate() async {
    if (!_voiceReady || _voiceUnsupported || !mounted) {
      return;
    }

    _showPoiRecommendationInChat();
    setState(() {
      _sessionBusy = true;
      _statusMessage = 'Orbit is speaking…';
    });

    final spoke = await _speakScript(_placeRecommendation);
    if (!mounted) return;
    setState(() {
      _sessionBusy = false;
      _statusMessage = spoke
          ? 'Say "Orbit" to ask a question, then "over" when finished.'
          : 'Recommendation is on screen — say "Orbit" to ask a question.';
    });
    if (_inputMode == _InputMode.voice) {
      await _startWakeWordListening();
    }
  }

  Future<void> _onDemoPinPlaced(LatLng point) async {
    // Ignore taps that land while a previous tap is still resolving so we don't
    // fire two POI lookups (and two voices) at once.
    if (_handlingPinTap) return;
    _handlingPinTap = true;
    try {
      // Supersede any current narration (e.g. the opening greeting still
      // playing) before we move to the new spot.
      _speakGeneration++;
      if (_voiceReady) {
        await _speech.stop();
        await _speech.cancel();
        _wakeListenArmed = false;
      }
      await _tts.stop();
      await OpenRouterTts.stop();

      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _placeLookupLoading = true;
        _statusMessage = 'Finding places here…';
        _locationReading = LocationReading(
          outcome: LocationOutcome.granted,
          latitude: point.latitude,
          longitude: point.longitude,
        );
      });

      await _fetchNearbyPoi(deferEnrich: true);
      if (!mounted) return;
      await _prepareSpokenRecommendation();
      if (!mounted) return;

      setState(() => _placeLookupLoading = false);

      if (_voiceReady && _inputMode == _InputMode.voice) {
        await _speakPoiUpdate();
      } else {
        _showPoiRecommendationInChat();
        if (mounted && _selectedPoi != null) {
          setState(() {
            _statusMessage =
                'Found ${_selectedPoi!.name} nearby — type a question to chat.';
          });
        }
      }
    } finally {
      _handlingPinTap = false;
      if (mounted && _placeLookupLoading) {
        setState(() => _placeLookupLoading = false);
      }
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
    final greeting = first.isEmpty
        ? "Let's explore!"
        : "Hi $first, let's explore!";

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
              _HomeHeader(greeting: greeting, onOpenSettings: _openSettings),
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
                            poiLoading: _placeLookupLoading,
                            reading: _locationReading,
                            onRetry: () {
                              setState(() {
                                _locationLoading = true;
                                _poiLoading = true;
                              });
                              _loadLocationAndNearbyPoi();
                            },
                            onPinPlaced: _onDemoPinPlaced,
                          ),
                        ),
                        SizedBox(
                          height: third,
                          child: _ChatSection(
                            history: _conversationHistory,
                            scrollController: _chatScrollController,
                            isThinking: _followUpLoading || _placeLookupLoading,
                            poiLoading:
                                (_poiLoading || _placeLookupLoading) &&
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
                            wakeListenArmed: _wakeListenArmed,
                            statusMessage: _statusMessage,
                            liveTranscript: _liveTranscript,
                            onMicPressed: () {
                              if (_isSpeaking) return;
                              if (_wakeListenArmed || _speech.isListening) {
                                _stopPassiveWakeListening();
                              } else {
                                _passiveWakePaused = false;
                                setState(() => _conversationActive = true);
                                _startWakeWordListening();
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
    this.poiLoading = false,
    this.onPinPlaced,
  });

  final bool loading;
  final bool poiLoading;
  final LocationReading? reading;
  final VoidCallback onRetry;
  final ValueChanged<LatLng>? onPinPlaced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(child: _buildMapBody(theme)),
            if (poiLoading)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: _MapLoadingBanner(theme: theme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapBody(ThemeData theme) {
    if (loading || reading == null) {
      return _MapPlaceholder(
        icon: Icons.my_location_rounded,
        title: 'Finding your location…',
        subtitle: 'Orbit uses your location to suggest places nearby.',
        theme: theme,
      );
    }

    final r = reading!;
    if (r.isGranted && r.latitude != null && r.longitude != null) {
      return _MapView(
        latitude: r.latitude!,
        longitude: r.longitude!,
        onPinPlaced: onPinPlaced,
      );
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

/// Slim translucent pill shown over the map while a new place is being found.
class _MapLoadingBanner extends StatelessWidget {
  const _MapLoadingBanner({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Finding places here…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapView extends StatefulWidget {
  const _MapView({
    required this.latitude,
    required this.longitude,
    this.onPinPlaced,
  });

  final double latitude;
  final double longitude;
  final ValueChanged<LatLng>? onPinPlaced;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void didUpdateWidget(_MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _mapController.move(
        LatLng(widget.latitude, widget.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = LatLng(widget.latitude, widget.longitude);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        onTap: widget.onPinPlaced == null
            ? null
            : (_, point) => widget.onPinPlaced!(point),
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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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
    required this.wakeListenArmed,
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
  final bool wakeListenArmed;
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
                      wakeListenArmed: wakeListenArmed,
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
    required this.wakeListenArmed,
    required this.statusMessage,
    required this.liveTranscript,
    required this.onMicPressed,
    required this.theme,
  });

  final bool voiceReady;
  final bool isListening;
  final bool isSpeaking;
  final bool sessionBusy;
  final bool wakeListenArmed;
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
              busy:
                  sessionBusy &&
                  !isListening &&
                  !isSpeaking &&
                  !wakeListenArmed,
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
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
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
