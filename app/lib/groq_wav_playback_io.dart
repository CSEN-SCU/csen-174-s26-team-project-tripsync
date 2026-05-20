import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// iOS/macOS/Android/desktop: AVPlayer is picky about WAV sources; write a real `.wav` file.
Future<void> playGroqWavBytes(
  Uint8List wavBytes, {
  void Function()? onExternalPause,
}) async {
  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}/orpheus_${DateTime.now().microsecondsSinceEpoch}.wav';
  final file = File(path);
  await file.writeAsBytes(wavBytes, flush: true);

  final player = AudioPlayer();
  StreamSubscription<PlayerState>? subscription;
  var completed = false;
  var externalPause = false;

  var hasPlayed = false;
  if (onExternalPause != null) {
    subscription = player.onPlayerStateChanged.listen((state) {
      if (completed || externalPause) return;
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
    await player.dispose();
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
