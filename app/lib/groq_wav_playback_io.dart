import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// The single active Groq playback. Tracked at module level so a new clip can
/// stop a previous one — `flutter_tts.stop()` does not touch this player, so
/// without this guard two Orpheus clips can play over each other.
AudioPlayer? _activePlayer;
int _playbackToken = 0;

/// Stops any in-flight Groq WAV playback. Safe to call when nothing is playing.
Future<void> stopGroqWavPlayback() async {
  _playbackToken++;
  final player = _activePlayer;
  _activePlayer = null;
  if (player == null) return;
  try {
    await player.stop();
    await player.dispose();
  } catch (_) {}
}

/// iOS/macOS/Android/desktop: AVPlayer is picky about WAV sources; write a real `.wav` file.
Future<void> playGroqWavBytes(
  Uint8List wavBytes, {
  void Function()? onExternalPause,
}) async {
  // Supersede any previous playback before starting this one.
  await stopGroqWavPlayback();
  final myToken = ++_playbackToken;

  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}/orpheus_${DateTime.now().microsecondsSinceEpoch}.wav';
  final file = File(path);
  await file.writeAsBytes(wavBytes, flush: true);

  final player = AudioPlayer();
  _activePlayer = player;
  StreamSubscription<PlayerState>? subscription;
  var completed = false;
  var externalPause = false;

  var hasPlayed = false;
  if (onExternalPause != null) {
    subscription = player.onPlayerStateChanged.listen((state) {
      if (completed || externalPause) return;
      // Ignore events once this playback has been superseded.
      if (myToken != _playbackToken) return;
      if (state == PlayerState.playing) hasPlayed = true;
      if (hasPlayed && state == PlayerState.paused) {
        externalPause = true;
        onExternalPause();
        unawaited(player.stop());
      }
    });
  }

  try {
    await player.play(DeviceFileSource(path));
    await player.onPlayerComplete.first;
    completed = true;
  } finally {
    await subscription?.cancel();
    // Only tear down if we are still the active playback; a newer clip may
    // have already replaced us via stopGroqWavPlayback().
    if (myToken == _playbackToken) {
      _activePlayer = null;
      try {
        await player.dispose();
      } catch (_) {}
    }
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
