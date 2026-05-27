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

    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
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

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      final snippet = response.body.length > 280
          ? '${response.body.substring(0, 280)}…'
          : response.body;
      final retryable = response.statusCode == 429 || response.statusCode >= 500;
      if (retryable && attempt < maxAttempts - 1) {
        final waitMs = 350 * (attempt + 1);
        developer.log(
          'Groq speech HTTP ${response.statusCode}, retry in ${waitMs}ms',
          name: 'Orbit.groq_tts',
        );
        await Future<void>.delayed(Duration(milliseconds: waitMs));
        continue;
      }

      developer.log(
        'Groq speech HTTP ${response.statusCode}: $snippet',
        name: 'Orbit.groq_tts',
      );
      throw GroqOrpheusTtsException(response.statusCode, snippet);
    }

    throw GroqOrpheusTtsException(0, 'Groq speech failed after retries');
  }

  /// Plays WAV bytes (e.g. from [synthesizeEnglishWav]) via a temp `.wav` file.
  /// `BytesSource` alone can fail on Darwin (AVPlayer needs a proper extension).
  static Future<void> playWavBytes(
    Uint8List wavBytes, {
    void Function()? onExternalPause,
  }) =>
      playGroqWavBytes(wavBytes, onExternalPause: onExternalPause);

  /// Splits [plainText] into chunks that fit Orpheus after [buildEnglishInput].
  static List<String> chunkPlainText(
    String plainText, {
    int maxChunkChars = 175,
  }) {
    final cleaned =
        plainText.replaceAll('—', ', ').replaceAll('–', ', ').trim();
    if (cleaned.isEmpty) return const [];
    if (cleaned.length <= maxChunkChars) return [cleaned];

    final chunks = <String>[];
    final sentences = cleaned.split(RegExp(r'(?<=[.!?])\s+'));
    var buffer = '';

    void flush() {
      if (buffer.trim().isNotEmpty) {
        chunks.add(buffer.trim());
      }
      buffer = '';
    }

    for (final sentence in sentences) {
      final part = sentence.trim();
      if (part.isEmpty) continue;

      if (part.length > maxChunkChars) {
        flush();
        var start = 0;
        while (start < part.length) {
          final end = (start + maxChunkChars).clamp(0, part.length);
          var slice = part.substring(start, end).trim();
          if (end < part.length) {
            final lastSpace = slice.lastIndexOf(' ');
            if (lastSpace > 40) {
              slice = slice.substring(0, lastSpace).trim();
              start += lastSpace + 1;
            } else {
              start = end;
            }
          } else {
            start = end;
          }
          if (slice.isNotEmpty) chunks.add(slice);
        }
        continue;
      }

      final candidate = buffer.isEmpty ? part : '$buffer $part';
      if (candidate.length <= maxChunkChars) {
        buffer = candidate;
      } else {
        flush();
        buffer = part;
      }
    }
    flush();

    return chunks.isEmpty ? [cleaned.substring(0, maxChunkChars).trim()] : chunks;
  }

  /// Locates the PCM `data` chunk in a RIFF WAV (Groq Orpheus uses standard WAV).
  static ({int start, int length}) _wavDataRange(Uint8List wav) {
    for (var i = 12; i + 8 < wav.length; i++) {
      if (wav[i] == 0x64 &&
          wav[i + 1] == 0x61 &&
          wav[i + 2] == 0x74 &&
          wav[i + 3] == 0x61) {
        final length = wav[i + 4] |
            (wav[i + 5] << 8) |
            (wav[i + 6] << 16) |
            (wav[i + 7] << 24);
        return (start: i + 8, length: length);
      }
    }
    if (wav.length > 44) {
      return (start: 44, length: wav.length - 44);
    }
    throw GroqOrpheusTtsException(0, 'Could not parse WAV data chunk');
  }

  /// Merges multiple WAV clips (same format) into one file for gapless playback.
  static Uint8List mergeWavFiles(List<Uint8List> wavFiles) {
    if (wavFiles.isEmpty) {
      throw GroqOrpheusTtsException(0, 'No WAV data to merge');
    }
    if (wavFiles.length == 1) return wavFiles.first;

    final firstRange = _wavDataRange(wavFiles.first);
    final pcm = BytesBuilder();
    for (final wav in wavFiles) {
      final range = _wavDataRange(wav);
      pcm.add(wav.sublist(range.start, range.start + range.length));
    }

    final headerLen = firstRange.start;
    final totalPcm = pcm.length;
    final header = Uint8List.fromList(wavFiles.first.sublist(0, headerLen));

    final dataLengthOffset = firstRange.start - 4;
    header[dataLengthOffset] = totalPcm & 0xff;
    header[dataLengthOffset + 1] = (totalPcm >> 8) & 0xff;
    header[dataLengthOffset + 2] = (totalPcm >> 16) & 0xff;
    header[dataLengthOffset + 3] = (totalPcm >> 24) & 0xff;

    final riffSize = headerLen + totalPcm - 8;
    header[4] = riffSize & 0xff;
    header[5] = (riffSize >> 8) & 0xff;
    header[6] = (riffSize >> 16) & 0xff;
    header[7] = (riffSize >> 24) & 0xff;

    final out = BytesBuilder();
    out.add(header);
    out.add(pcm.toBytes());
    return out.toBytes();
  }

  /// Speaks long copy: synthesize all chunks in parallel, merge WAV, play once.
  static Future<void> speakLongEnglish({
    required String apiKey,
    required String plainText,
    String voice = 'troy',
    void Function()? onExternalPause,
  }) async {
    final chunks = chunkPlainText(plainText);
    if (chunks.isEmpty) return;

    // Synthesize sequentially — parallel requests hit Groq 429 rate limits and
    // triggered silent fallback to on-device TTS on longer answers.
    final wavs = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final input = buildEnglishInput(
        chunks[i],
        directionPrefix: i == 0 ? '[friendly] ' : '',
      );
      wavs.add(
        await synthesizeEnglishWav(
          apiKey: apiKey,
          input: input,
          voice: voice,
        ),
      );
    }

    try {
      final merged = mergeWavFiles(wavs);
      await playWavBytes(merged, onExternalPause: onExternalPause);
      return;
    } catch (e, st) {
      developer.log(
        'WAV merge failed, playing chunks sequentially: $e',
        name: 'Orbit.groq_tts',
        stackTrace: st,
      );
    }

    Object? lastPlayError;
    for (final wav in wavs) {
      try {
        await playWavBytes(wav, onExternalPause: onExternalPause);
        return;
      } catch (e, st) {
        lastPlayError = e;
        developer.log('$e', name: 'Orbit.groq_tts', stackTrace: st);
      }
    }
    throw lastPlayError ??
        GroqOrpheusTtsException(0, 'Could not play Orpheus audio');
  }
}

class GroqOrpheusTtsException implements Exception {
  GroqOrpheusTtsException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GroqOrpheusTtsException($statusCode): $message';
}
