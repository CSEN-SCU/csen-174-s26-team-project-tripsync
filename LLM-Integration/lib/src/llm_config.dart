final class LlmConfig {
  const LlmConfig({
    required this.apiKey,
    required this.model,
    required this.baseUri,
  });

  final String apiKey;
  final String model;
  final Uri baseUri;

  factory LlmConfig.fromEnvironment([Map<String, String>? environment]) {
    throw UnimplementedError(
      'Sprint 1: read ORBIT_LLM_API_KEY, ORBIT_LLM_MODEL, ORBIT_LLM_BASE_URL '
      'from the process environment or the optional override map.',
    );
  }

  static const orbitLlmApiKey = 'ORBIT_LLM_API_KEY';
  static const orbitLlmModel = 'ORBIT_LLM_MODEL';
  static const orbitLlmBaseUrl = 'ORBIT_LLM_BASE_URL';

  static LlmConfig forTests({
    String apiKey = 'sk-test-placeholder',
    String model = 'test-model',
    Uri? baseUri,
  }) {
    return LlmConfig(
      apiKey: apiKey,
      model: model,
      baseUri: baseUri ?? Uri.parse('https://example.invalid/v1/'),
    );
  }
}
