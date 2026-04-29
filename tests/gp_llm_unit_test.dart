import 'package:llm_integration/llm_integration.dart';
import 'package:test/test.dart';

void main() {
  // GP — consolidation plan: AI integration (narration + follow-up answers).

  test(
    'gp: when the app has Orbit LLM settings and I ask a question, I get plain model text back for the voice layer',
    () async {
      // As a traveler using Orbit hands-free, I hear an answer string our app can speak without me parsing JSON in my head.
      // Arrange
      final env = {
        LlmConfig.orbitLlmApiKey: 'sk-test',
        LlmConfig.orbitLlmModel: 'test-model',
        LlmConfig.orbitLlmBaseUrl: 'https://llm.example/v1/',
      };
      final config = LlmConfig.fromEnvironment(env);
      final client = LlmClient(config: config);

      // Act
      final answer = await client.completeText(
        userPrompt: 'Is the Ferry Building kid-friendly?',
      );

      // Assert
      expect(answer.trim(), isNotEmpty);
      expect(answer.contains('{'), isFalse, reason: 'Callers should get speakable text, not raw JSON');
      client.close();
    },
  );
}
