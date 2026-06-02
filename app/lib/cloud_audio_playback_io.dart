import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// The single active cloud TTS playback. Tracked at module level so a new clip can
/// stop a previous one — `flutter_tts.stop()` does not touch this player, so
/// without this guard two generated clips can play over each other.
AudioPlayer? _activePlayer;
int _playbackToken = 0;

/// Stops any in-flight generated audio playback. Safe to call when nothing is playing.
Future<void> stopCloudAudioPlayback() async {
  _playbackToken++;
  final player = _activePlayer;
  _activePlayer = null;
  if (player == null) return;
  try {
    await player.stop();
    await player.dispose();
  } catch (_) {}
}

/// iOS/macOS/Android/desktop playback is most reliable from a real temp file.
Future<void> playCloudAudioBytes(
  Uint8List audioBytes, {
  required String fileExtension,
  void Function()? onExternalPause,
}) async {
  // Supersede any previous playback before starting this one.
  await stopCloudAudioPlayback();
  final myToken = ++_playbackToken;

  final safeExtension = fileExtension.replaceAll(RegExp(r'[^a-z0-9]'), '');
  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}/cloud_tts_${DateTime.now().microsecondsSinceEpoch}.$safeExtension';
  final file = File(path);
  await file.writeAsBytes(audioBytes, flush: true);

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
    // have already replaced us via stopCloudAudioPlayback().
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
