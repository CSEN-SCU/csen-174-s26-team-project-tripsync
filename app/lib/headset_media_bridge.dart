import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Routes headset play/pause (e.g. AirPods) to a single callback while armed.
///
/// While listening (mic only), iOS often will not deliver pause unless the app
/// holds a media session — we loop near-silent audio so pause reaches AVPlayer.
class HeadsetMediaBridge {
  HeadsetMediaBridge._();

  static final HeadsetMediaBridge instance = HeadsetMediaBridge._();

  VoidCallback? _onPausePressed;
  AudioPlayer? _keeperPlayer;
  StreamSubscription<PlayerState>? _keeperSubscription;
  bool _armed = false;
  bool _programmaticStop = false;
  String? _silentWavPath;

  bool get isArmed => _armed;

  /// Playback-only session for generated WAV (after STT, iOS needs this route).
  Future<void> configurePlaybackSession() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        ),
      );
      await session.setActive(true);
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.playback_session', stackTrace: st);
    }
  }

  Future<void> configureVoiceSession() async {
    if (kIsWeb) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.assistanceNavigationGuidance,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
        ),
      );
      await session.setActive(true);
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.headset_session', stackTrace: st);
    }
  }

  /// Begin listening for headset pause until [disarm].
  Future<void> arm({required VoidCallback onPausePressed}) async {
    if (kIsWeb) return;

    await disarm();
    _onPausePressed = onPausePressed;
    _armed = true;
    await _startKeeperPlayback();
  }

  Future<void> disarm() async {
    _armed = false;
    _onPausePressed = null;
    _programmaticStop = true;
    await _keeperSubscription?.cancel();
    _keeperSubscription = null;
    try {
      await _keeperPlayer?.stop();
      await _keeperPlayer?.dispose();
    } catch (_) {}
    _keeperPlayer = null;
    _programmaticStop = false;
  }

  /// Fully releases the app's audio session when leaving the foreground.
  Future<void> releaseAudioSession() async {
    if (kIsWeb) return;

    await disarm();
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.audio_session_release', stackTrace: st);
    }
  }

  void notifyExternalPause() {
    if (!_armed || _programmaticStop) return;
    developer.log('Headset pause detected', name: 'Orbit.headset_pause');
    _onPausePressed?.call();
  }

  Future<void> _startKeeperPlayback() async {
    final path = await _silentWavPathAsync();
    final player = AudioPlayer();
    _keeperPlayer = player;
    _keeperSubscription = player.onPlayerStateChanged.listen((state) {
      if ((state == PlayerState.paused || state == PlayerState.stopped) &&
          _armed &&
          !_programmaticStop) {
        notifyExternalPause();
      }
    });

    await player.setReleaseMode(ReleaseMode.loop);
    await player.setVolume(0.01);
    await player.play(DeviceFileSource(path));
  }

  Future<String> _silentWavPathAsync() async {
    if (_silentWavPath != null) return _silentWavPath!;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/orbit_silent_loop.wav';
    final file = File(path);
    if (!file.existsSync()) {
      await file.writeAsBytes(_buildSilentWav(), flush: true);
    }
    _silentWavPath = path;
    return path;
  }

  /// Minimal mono 16-bit PCM WAV (~0.25s) for a looping media session.
  static Uint8List _buildSilentWav() {
    const sampleRate = 8000;
    const durationMs = 250;
    final sampleCount = (sampleRate * durationMs / 1000).floor();
    final dataSize = sampleCount * 2;
    final totalSize = 36 + dataSize;
    final bytes = ByteData(44 + dataSize);

    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    bytes.setUint32(4, totalSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeString(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    // samples already zero

    return bytes.buffer.asUint8List();
  }
}
