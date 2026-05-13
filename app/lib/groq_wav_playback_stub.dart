import 'dart:typed_data';

/// Web / non-io: Groq playback not used from [TripSyncHomeScreen] today.
Future<void> playGroqWavBytes(Uint8List _) async {
  throw UnsupportedError('Groq WAV playback is not available on this platform.');
}
