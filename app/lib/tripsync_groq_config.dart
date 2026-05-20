import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Groq API key resolution order:
/// 1. `--dart-define=GROQ_API_KEY=…` or `--dart-define-from-file=.env` (CI / release)
/// 2. Bundled `app/.env` loaded at startup (local Xcode / `flutter run` without flags)
String groqApiKeyFromEnvironment() {
  const fromDefine = String.fromEnvironment('GROQ_API_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;

  final fromDotenv = dotenv.maybeGet('GROQ_API_KEY')?.trim() ?? '';
  if (fromDotenv.isEmpty) return '';

  if ((fromDotenv.startsWith('"') && fromDotenv.endsWith('"')) ||
      (fromDotenv.startsWith("'") && fromDotenv.endsWith("'"))) {
    return fromDotenv.substring(1, fromDotenv.length - 1).trim();
  }
  return fromDotenv;
}

/// Loads `app/.env` into memory when present (ignored if the asset is missing).
Future<void> initializeGroqConfig() async {
  await _loadDotEnv();
}

/// Call before TTS if the compile-time define was empty (e.g. Xcode run).
Future<bool> reloadGroqConfigIfNeeded() async {
  if (groqApiKeyFromEnvironment().isNotEmpty) return true;
  await _loadDotEnv();
  return groqApiKeyFromEnvironment().isNotEmpty;
}

Future<void> _loadDotEnv() async {
  try {
    await dotenv.load(fileName: '.env');
    final key = groqApiKeyFromEnvironment();
    developer.log(
      'Groq config: key ${key.isEmpty ? "missing" : "loaded (${key.length} chars)"}',
      name: 'TripSync.groq_config',
    );
  } catch (e, st) {
    developer.log(
      'Could not load .env asset: $e',
      name: 'TripSync.groq_config',
      stackTrace: st,
    );
  }
}
