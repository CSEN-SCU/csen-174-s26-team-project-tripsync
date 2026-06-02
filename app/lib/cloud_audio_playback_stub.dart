import 'dart:typed_data';

/// Web / non-io: generated audio playback is not used from [OrbitHomeScreen] today.
Future<void> playCloudAudioBytes(
  Uint8List _, {
  required String fileExtension,
  void Function()? onExternalPause,
}) async {
  throw UnsupportedError(
    'Generated audio playback is not available on this platform.',
  );
}

/// No-op on platforms without generated audio playback.
Future<void> stopCloudAudioPlayback() async {}
