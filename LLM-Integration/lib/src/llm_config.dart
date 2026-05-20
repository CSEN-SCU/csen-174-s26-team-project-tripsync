import 'llm_exceptions.dart';

/// Groq OpenAI-compatible chat (`POST …/chat/completions`).
final class LlmConfig {
  const LlmConfig({
    required this.apiKey,
    required this.model,
    required this.baseUri,
  });

  static const groqApiKeyDefine = 'GROQ_API_KEY';
  static const groqLlmModelDefine = 'GROQ_LLM_MODEL';
  static const groqLlmBaseUrlDefine = 'GROQ_LLM_BASE_URL';

  /// Keys for [fromEnvironment] (tests / scripts); same names as Flutter `--dart-define`.
  static const groqApiKey = groqApiKeyDefine;
  static const groqLlmModel = groqLlmModelDefine;
  static const groqLlmBaseUrl = groqLlmBaseUrlDefine;

  static const _defaultModel = 'llama-3.3-70b-versatile';
  static const _defaultBase = 'https://api.groq.com/openai/v1';

  final String apiKey;
  final String model;
  final Uri baseUri;

  Uri get chatCompletionsUri => baseUri.resolve('chat/completions');

  /// Map-based config (tests). Throws if API key missing.
  factory LlmConfig.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? const {};
    return _fromParts(
      rawApiKey: env[groqApiKey] ?? '',
      rawModel: env[groqLlmModel],
      rawBase: env[groqLlmBaseUrl],
      missingKeyMessage:
          'Missing $groqApiKey. For Flutter use --dart-define-from-file; '
          'for tests pass a map with $groqApiKey set.',
    );
  }

  /// Compile-time defines from `flutter run --dart-define-from-file=.env`.
  factory LlmConfig.fromGroqDartDefines() {
    const modelRaw = String.fromEnvironment(groqLlmModelDefine, defaultValue: '');
    const baseRaw = String.fromEnvironment(groqLlmBaseUrlDefine, defaultValue: '');
    return _fromParts(
      rawApiKey: const String.fromEnvironment(groqApiKeyDefine),
      rawModel: modelRaw,
      rawBase: baseRaw,
      missingKeyMessage:
          'Missing $groqApiKeyDefine. Add it via --dart-define-from-file=.env '
          '(see app/.env.example).',
    );
  }

  static LlmConfig forTests({
    String apiKey = 'sk-test-placeholder',
    String model = 'test-model',
    Uri? baseUri,
  }) {
    return LlmConfig(
      apiKey: apiKey,
      model: model,
      baseUri: _normalizeBaseUri(baseUri ?? Uri.parse('https://example.invalid/v1/')),
    );
  }

  static LlmConfig _fromParts({
    required String rawApiKey,
    String? rawModel,
    String? rawBase,
    required String missingKeyMessage,
  }) {
    final key = _stripQuotes(rawApiKey.trim());
    if (key.isEmpty) {
      throw LlmConfigurationException(missingKeyMessage);
    }
    final model = (rawModel?.trim().isNotEmpty ?? false) ? rawModel!.trim() : _defaultModel;
    final base = (rawBase?.trim().isNotEmpty ?? false) ? rawBase!.trim() : _defaultBase;
    return LlmConfig(
      apiKey: key,
      model: model,
      baseUri: _normalizeBaseUri(Uri.parse(base)),
    );
  }

  static String _stripQuotes(String key) {
    var k = key.trim();
    if (k.length >= 2) {
      final first = k[0];
      final last = k[k.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        k = k.substring(1, k.length - 1).trim();
      }
    }
    return k;
  }

  static Uri _normalizeBaseUri(Uri u) {
    final s = u.toString();
    if (s.endsWith('/')) return u;
    return Uri.parse('$s/');
  }
}
