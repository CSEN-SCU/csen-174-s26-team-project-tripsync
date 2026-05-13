import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// iOS/macOS/Android/desktop: AVPlayer is picky about WAV sources; write a real `.wav` file.
Future<void> playGroqWavBytes(Uint8List wavBytes) async {
  final dir = await getTemporaryDirectory();
  final path =
      '${dir.path}/orpheus_${DateTime.now().microsecondsSinceEpoch}.wav';
  final file = File(path);
  await file.writeAsBytes(wavBytes, flush: true);

  final player = AudioPlayer();
  try {
    await player.play(DeviceFileSource(path));
    await player.onPlayerComplete.first;
  } finally {
    await player.dispose();
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
