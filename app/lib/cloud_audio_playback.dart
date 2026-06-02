import 'dart:typed_data';

import 'cloud_audio_playback_stub.dart'
    if (dart.library.io) 'cloud_audio_playback_io.dart'
    as audio_playback;

Future<void> playCloudAudioBytes(
  Uint8List audioBytes, {
  required String fileExtension,
  void Function()? onExternalPause,
}) => audio_playback.playCloudAudioBytes(
  audioBytes,
  fileExtension: fileExtension,
  onExternalPause: onExternalPause,
);

/// Stops any in-flight generated audio playback (no-op on platforms without it).
Future<void> stopCloudAudioPlayback() =>
    audio_playback.stopCloudAudioPlayback();
