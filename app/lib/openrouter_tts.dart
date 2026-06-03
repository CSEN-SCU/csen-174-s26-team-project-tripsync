import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloud_audio_playback.dart';

/// OpenRouter-hosted text-to-speech.
///
/// Returns raw MP3 bytes from the OpenRouter speech endpoint.
class OpenRouterTts {
  OpenRouterTts._();

  static const String speechUrl = 'https://openrouter.ai/api/v1/audio/speech';
  static const List<_OpenRouterTtsModel> models = [
    // Temporarily disabled while testing the xAI backup model.
    _OpenRouterTtsModel(id: 'mistralai/voxtral-mini-tts-2603', voice: 'alloy'),
    _OpenRouterTtsModel(id: 'x-ai/grok-voice-tts-1.0', voice: 'eve'),
  ];

  /// Keep chunks comfortably below the model's 4K context window.
  static const int maxChunkLength = 1400;

  static String buildSpeechInput(String plainText) =>
      plainText.replaceAll('—', ', ').replaceAll('–', ', ').trim();

  static Future<Uint8List> synthesizeMp3({
    required String apiKey,
    required String input,
    String? voice,
    String? userId,
  }) async {
    if (input.trim().isEmpty) {
      throw OpenRouterTtsException(400, 'input is empty');
    }

    const maxAttempts = 4;
    OpenRouterTtsException? lastException;
    final failures = <String>[];

    for (final model in models) {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        final response = await http.post(
          Uri.parse(speechUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://orbit.local',
            'X-Title': 'Orbit',
          },
          body: jsonEncode({
            'model': model.id,
            'voice': voice ?? model.voice,
            'input': input,
            'response_format': 'mp3',
            if (userId != null && userId.trim().isNotEmpty)
              'user': userId.trim(),
          }),
        );

        if (response.statusCode == 200) {
          return response.bodyBytes;
        }

        final snippet = response.body.length > 280
            ? '${response.body.substring(0, 280)}...'
            : response.body;
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        if (retryable && attempt < maxAttempts - 1) {
          final waitMs = 350 * (attempt + 1);
          developer.log(
            'OpenRouter speech ${model.id} HTTP ${response.statusCode}, retry in ${waitMs}ms',
            name: 'Orbit.openrouter_tts',
          );
          await Future<void>.delayed(Duration(milliseconds: waitMs));
          continue;
        }

        developer.log(
          'OpenRouter speech ${model.id} HTTP ${response.statusCode}: $snippet',
          name: 'Orbit.openrouter_tts',
        );
        failures.add('${model.id}: HTTP ${response.statusCode}: $snippet');
        lastException = OpenRouterTtsException(
          response.statusCode,
          failures.join(' | '),
        );
        break;
      }
    }

    throw lastException ??
        OpenRouterTtsException(0, 'OpenRouter speech failed after retries');
  }

  /// Plays MP3 bytes via a temp `.mp3` file.
  static Future<void> playMp3Bytes(
    Uint8List mp3Bytes, {
    void Function()? onExternalPause,
  }) => playCloudAudioBytes(
    mp3Bytes,
    fileExtension: 'mp3',
    onExternalPause: onExternalPause,
  );

  /// Stops any in-flight cloud playback so a new clip never overlaps it.
  static Future<void> stop() => stopCloudAudioPlayback();

  static List<String> chunkPlainText(
    String plainText, {
    int maxChunkChars = maxChunkLength,
  }) {
    final cleaned = buildSpeechInput(plainText);
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

    return chunks.isEmpty
        ? [cleaned.substring(0, maxChunkChars).trim()]
        : chunks;
  }

  /// Speaks long copy: synthesize and play MP3 chunks sequentially.
  static Future<void> speakLongEnglish({
    required String apiKey,
    required String plainText,
    String? voice,
    String? userId,
    void Function()? onExternalPause,
  }) async {
    final chunks = chunkPlainText(plainText);
    if (chunks.isEmpty) return;

    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final mp3 = await synthesizeMp3(
        apiKey: apiKey,
        input: buildSpeechInput(chunks[i]),
        voice: voice,
        userId: userId,
      );
      await playMp3Bytes(mp3, onExternalPause: onExternalPause);
    }
  }
}

class _OpenRouterTtsModel {
  const _OpenRouterTtsModel({required this.id, required this.voice});

  final String id;
  final String voice;
}

class OpenRouterTtsException implements Exception {
  OpenRouterTtsException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'OpenRouterTtsException($statusCode): $message';
}
