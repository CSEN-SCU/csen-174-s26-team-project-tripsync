import 'dart:typed_data';

import 'groq_wav_playback_stub.dart'
    if (dart.library.io) 'groq_wav_playback_io.dart' as wav_playback;

Future<void> playGroqWavBytes(Uint8List wavBytes) =>
    wav_playback.playGroqWavBytes(wavBytes);
