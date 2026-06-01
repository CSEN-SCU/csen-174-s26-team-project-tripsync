import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import 'groq_orpheus_tts.dart';
import 'groq_wav_playback.dart';
import 'orbit_groq_config.dart';

/// Gemini speech via Firebase AI Logic **Vertex Live API** only.
///
/// Does not call the Gemini Developer API (`googleAI()` / AI Studio prepay).
/// Requires **Vertex AI Gemini API** enabled in Firebase Console → AI Logic.
class FirebaseGeminiTts {
  FirebaseGeminiTts._();

  /// Native-audio Live model (Vertex AI Gemini API).
  static const String defaultLiveModelId =
      'gemini-2.5-flash-native-audio-preview-12-2025';

  static const String defaultVoiceName = 'Kore';

  static const int _pcmSampleRate = 24000;
  static const int _pcmChannels = 1;
  static const int _pcmBitsPerSample = 16;

  static String _liveModelId() {
    final override = appConfigValue('FIREBASE_TTS_MODEL').trim();
    return override.isEmpty ? defaultLiveModelId : override;
  }

  static LiveGenerativeModel _liveModel() {
    return FirebaseAI.vertexAI().liveGenerativeModel(
      model: _liveModelId(),
      liveGenerationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModalities.audio],
        speechConfig: SpeechConfig(voiceName: defaultVoiceName),
      ),
      systemInstruction: Content.system(
        'You are an audio tour guide for the Orbit travel app. '
        'Speak only the text the user gives you. Do not add extra commentary.',
      ),
    );
  }

  static String buildTtsPrompt(
    String plainText, {
    bool leadChunk = true,
  }) {
    final cleaned =
        plainText.replaceAll('—', ', ').replaceAll('–', ', ').trim();
    if (cleaned.isEmpty) return '';
    if (!leadChunk) return cleaned;
    return 'Speak this in a warm, friendly tour-guide tone: $cleaned';
  }

  static Future<Uint8List> synthesizeEnglishWav({
    required String plainText,
    bool leadChunk = true,
  }) async {
    final prompt = buildTtsPrompt(plainText, leadChunk: leadChunk);
    if (prompt.isEmpty) {
      throw FirebaseGeminiTtsException(0, 'empty TTS prompt');
    }

    final session = await _liveModel().connect();
    final pcm = BytesBuilder();
    String? mimeType;

    try {
      await session.send(input: Content.text(prompt), turnComplete: true);
      await for (final response in session.receive()) {
        final message = response.message;
        if (message is! LiveServerContent || message.modelTurn == null) {
          continue;
        }
        for (final part in message.modelTurn!.parts) {
          if (part is InlineDataPart) {
            final mt = part.mimeType.toLowerCase();
            if (mt.contains('audio') || mt.contains('pcm')) {
              mimeType ??= part.mimeType;
              pcm.add(part.bytes);
            }
          }
        }
      }
    } on FirebaseAIException catch (e, st) {
      developer.log('$e', name: 'Orbit.firebase_tts', stackTrace: st);
      throw FirebaseGeminiTtsException(0, e.message);
    } finally {
      await session.close();
    }

    if (pcm.length == 0) {
      throw FirebaseGeminiTtsException(
        0,
        'Vertex Live API returned no audio (model=${_liveModelId()}). '
        'Check Firebase AI Logic → Vertex AI Gemini API and GCP billing on Blaze.',
      );
    }
    developer.log(
      'Vertex Live audio: ${pcm.length} bytes, mime=${mimeType ?? "audio/pcm"}',
      name: 'Orbit.firebase_tts',
    );
    return _toPlayableWav(mimeType ?? 'audio/pcm', pcm.toBytes());
  }

  static Uint8List _toPlayableWav(String mimeType, Uint8List bytes) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('wav')) {
      return bytes;
    }
    if (normalized.contains('mpeg') || normalized.contains('mp3')) {
      throw FirebaseGeminiTtsException(
        0,
        'unsupported audio mime $mimeType (expected wav or pcm)',
      );
    }
    return _pcmToWav(bytes);
  }

  static Uint8List _pcmToWav(Uint8List pcm) {
    const byteRate = _pcmSampleRate * _pcmChannels * _pcmBitsPerSample ~/ 8;
    const blockAlign = _pcmChannels * _pcmBitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final header = ByteData(44);
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, 36 + dataSize, Endian.little);
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, _pcmChannels, Endian.little);
    header.setUint32(24, _pcmSampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, _pcmBitsPerSample, Endian.little);
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataSize, Endian.little);

    final out = Uint8List(44 + dataSize);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, 44 + dataSize, pcm);
    return out;
  }

  static Future<void> playWavBytes(
    Uint8List wavBytes, {
    void Function()? onExternalPause,
  }) =>
      playGroqWavBytes(wavBytes, onExternalPause: onExternalPause);

  static Future<void> speakLongEnglish({
    required String plainText,
    void Function()? onExternalPause,
  }) async {
    final chunks = GroqOrpheusTts.chunkPlainText(
      plainText,
      maxChunkChars: 380,
    );
    if (chunks.isEmpty) return;

    final wavs = <Uint8List>[];
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      wavs.add(
        await synthesizeEnglishWav(
          plainText: chunks[i],
          leadChunk: i == 0,
        ),
      );
    }

    try {
      final merged = GroqOrpheusTts.mergeWavFiles(wavs);
      await playWavBytes(merged, onExternalPause: onExternalPause);
      return;
    } catch (e, st) {
      developer.log(
        'Vertex WAV merge failed, playing chunks sequentially: $e',
        name: 'Orbit.firebase_tts',
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
        developer.log('$e', name: 'Orbit.firebase_tts', stackTrace: st);
      }
    }
    throw lastPlayError ??
        FirebaseGeminiTtsException(0, 'Could not play Vertex Live audio');
  }
}

class FirebaseGeminiTtsException implements Exception {
  FirebaseGeminiTtsException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'FirebaseGeminiTtsException($statusCode): $message';

  String get userMessage {
    final lower = message.toLowerCase();
    if (lower.contains('billing') ||
        lower.contains('quota') ||
        lower.contains('permission')) {
      return 'Vertex AI billing or quota — check GCP billing on your Blaze project';
    }
    if (lower.contains('no audio') || lower.contains('returned no audio')) {
      return 'Vertex Live returned no audio — enable Vertex AI Gemini API in AI Logic';
    }
    if (message.length > 120) {
      return '${message.substring(0, 117)}…';
    }
    return message;
  }
}

/// User-facing summary when Vertex TTS fails before Groq / phone fallback.
String firebaseTtsFailureSummary(Object error) {
  if (error is FirebaseGeminiTtsException) return error.userMessage;
  if (error is FirebaseAIException) {
    final msg = error.message;
    if (msg.length > 120) return '${msg.substring(0, 117)}…';
    return msg;
  }
  return 'Vertex voice unavailable';
}
