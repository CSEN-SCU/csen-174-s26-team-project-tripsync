import 'dart:typed_data';

/// Web / non-io: Groq playback not used from [OrbitHomeScreen] today.
Future<void> playGroqWavBytes(
  Uint8List _, {
  void Function()? onExternalPause,
}) async {
  throw UnsupportedError('Groq WAV playback is not available on this platform.');
}

/// No-op on platforms without Groq WAV playback.
Future<void> stopGroqWavPlayback() async {}
