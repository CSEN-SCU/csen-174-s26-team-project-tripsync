import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'groq_wav_playback.dart';

/// Groq-hosted [Orpheus](https://console.groq.com/docs/text-to-speech/orpheus)
/// English TTS (`canopylabs/orpheus-v1-english`). OpenAI-compatible speech endpoint.
class GroqOrpheusTts {
  GroqOrpheusTts._();

  static const String speechUrl = 'https://api.groq.com/openai/v1/audio/speech';
  static const String englishModelId = 'canopylabs/orpheus-v1-english';

  /// Groq limits Orpheus `input` to **200 characters** total.
  static const int maxInputLength = 200;

  /// Optional bracketed direction, then the script (truncated to fit the cap).
  static String buildEnglishInput(
    String plainText, {
    String directionPrefix = '[friendly] ',
  }) {
    final cleaned =
        plainText.replaceAll('—', ', ').replaceAll('–', ', ').trim();
    final prefix = directionPrefix;
    final budget = maxInputLength - prefix.length;
    if (budget < 1) {
      return cleaned.length <= maxInputLength
          ? cleaned
          : '${cleaned.substring(0, maxInputLength - 1)}…';
    }
    var body = cleaned;
    if (body.length > budget) {
      body = '${body.substring(0, budget - 1)}…';
    }
    return '$prefix$body';
  }

  static Future<Uint8List> synthesizeEnglishWav({
    required String apiKey,
    required String input,
    String voice = 'troy',
  }) async {
    if (input.length > maxInputLength) {
      throw GroqOrpheusTtsException(
        400,
        'input exceeds $maxInputLength characters (${input.length})',
      );
    }

    final response = await http.post(
      Uri.parse(speechUrl),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': englishModelId,
        'voice': voice,
        'input': input,
        'response_format': 'wav',
      }),
    );

    if (response.statusCode != 200) {
      final snippet = response.body.length > 280
          ? '${response.body.substring(0, 280)}…'
          : response.body;
      developer.log(
        'Groq speech HTTP ${response.statusCode}: $snippet',
        name: 'TripSync.groq_tts',
      );
      throw GroqOrpheusTtsException(response.statusCode, snippet);
    }

    return response.bodyBytes;
  }

  /// Plays WAV bytes (e.g. from [synthesizeEnglishWav]) via a temp `.wav` file.
  /// `BytesSource` alone can fail on Darwin (AVPlayer needs a proper extension).
  static Future<void> playWavBytes(Uint8List wavBytes) =>
      playGroqWavBytes(wavBytes);
}

class GroqOrpheusTtsException implements Exception {
  GroqOrpheusTtsException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GroqOrpheusTtsException($statusCode): $message';
}
