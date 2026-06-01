import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';

String _dartDefineValue(String name) {
  switch (name) {
    case 'GROQ_API_KEY':
      return const String.fromEnvironment('GROQ_API_KEY');
    case 'FIREBASE_TTS_MODEL':
      return const String.fromEnvironment('FIREBASE_TTS_MODEL');
    case 'FIREBASE_PROJECT_ID':
      return const String.fromEnvironment('FIREBASE_PROJECT_ID');
    case 'FIREBASE_MESSAGING_SENDER_ID':
      return const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    case 'FIREBASE_STORAGE_BUCKET':
      return const String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    case 'FIREBASE_ANDROID_API_KEY':
      return const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    case 'FIREBASE_ANDROID_APP_ID':
      return const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    case 'FIREBASE_ANDROID_OAUTH_CLIENT_ID':
      return const String.fromEnvironment('FIREBASE_ANDROID_OAUTH_CLIENT_ID');
    case 'FIREBASE_IOS_API_KEY':
      return const String.fromEnvironment('FIREBASE_IOS_API_KEY');
    case 'FIREBASE_IOS_APP_ID':
      return const String.fromEnvironment('FIREBASE_IOS_APP_ID');
    case 'FIREBASE_IOS_CLIENT_ID':
      return const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');
    case 'FIREBASE_IOS_BUNDLE_ID':
      return const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');
    default:
      return '';
  }
}

String _dotenvValue(String name) {
  var fromDotenv = dotenv.maybeGet(name)?.trim() ?? '';
  if (fromDotenv.isEmpty) return '';

  if ((fromDotenv.startsWith('"') && fromDotenv.endsWith('"')) ||
      (fromDotenv.startsWith("'") && fromDotenv.endsWith("'"))) {
    fromDotenv = fromDotenv.substring(1, fromDotenv.length - 1).trim();
  }
  return fromDotenv;
}

/// Reads a config value from `--dart-define` first, then bundled `app/.env`.
String appConfigValue(String name) {
  final fromDefine = _dartDefineValue(name);
  if (fromDefine.isNotEmpty) return fromDefine;
  return _dotenvValue(name);
}

String appConfigValueRequired(String name) {
  final value = appConfigValue(name);
  if (value.isEmpty) {
    throw StateError(
      'Missing $name. Add it to app/.env (see .env.example) or pass '
      '--dart-define-from-file=.env, then run '
      'bash scripts/write_firebase_native_config.sh for iOS/Android native files.',
    );
  }
  return value;
}

/// Groq API key resolution order:
/// 1. `--dart-define=GROQ_API_KEY=…` or `--dart-define-from-file=.env` (CI / release)
/// 2. Bundled `app/.env` loaded at startup (local Xcode / `flutter run` without flags)
String groqApiKeyFromEnvironment() => appConfigValue('GROQ_API_KEY');

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
      name: 'Orbit.groq_config',
    );
  } catch (e, st) {
    developer.log(
      'Could not load .env asset: $e',
      name: 'Orbit.groq_config',
      stackTrace: st,
    );
  }
}
