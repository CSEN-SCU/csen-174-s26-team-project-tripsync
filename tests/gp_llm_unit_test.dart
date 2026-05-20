import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llm_integration/llm_integration.dart';
import 'package:test/test.dart';

void main() {
  test(
    'gp: when the app has Groq LLM settings and I ask a question, I get plain model text back for the voice layer',
    () async {
      final env = {
        LlmConfig.groqApiKey: 'sk-test',
        LlmConfig.groqLlmModel: 'test-model',
        LlmConfig.groqLlmBaseUrl: 'https://llm.example/v1/',
      };
      final config = LlmConfig.fromEnvironment(env);

      String? capturedBody;
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          'https://llm.example/v1/chat/completions',
        );
        expect(request.headers['Authorization'], 'Bearer sk-test');
        capturedBody = request.body;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content':
                      'Yes — the Ferry Building has kid-friendly food halls and space to wander.',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = LlmClient(config: config, httpClient: mock);
      final answer = await client.completeText(
        userPrompt: 'Is the Ferry Building kid-friendly?',
      );

      expect(answer.trim(), isNotEmpty);
      expect(answer.contains('{'), isFalse, reason: 'Callers should get speakable text, not raw JSON');
      expect(capturedBody, isNotNull);
      final decoded = jsonDecode(capturedBody!) as Map<String, dynamic>;
      final messages = decoded['messages'] as List<dynamic>;
      final userMsg = messages.cast<Map<String, dynamic>>().firstWhere((m) => m['role'] == 'user');
      final content = userMsg['content'] as String;
      expect(content, contains('<<<USER_INPUT>>>'));
      expect(content, contains('<<<END_USER_INPUT>>>'));
      client.close();
    },
  );

  test('gp: HTTP error maps to LlmProviderException', () async {
    final config = LlmConfig.fromEnvironment({
      LlmConfig.groqApiKey: 'sk-test',
      LlmConfig.groqLlmModel: 'm',
      LlmConfig.groqLlmBaseUrl: 'https://llm.example/v1/',
    });
    final mock = MockClient(
      (_) async => http.Response('{"error":{"message":"bad"}}', 429),
    );
    final client = LlmClient(config: config, httpClient: mock);
    await expectLater(
      client.completeText(userPrompt: 'Hello'),
      throwsA(isA<LlmProviderException>().having((e) => e.statusCode, 'status', 429)),
    );
    client.close();
  });

  test('gp: missing API key in map throws fromEnvironment', () {
    expect(
      () => LlmConfig.fromEnvironment({LlmConfig.groqLlmModel: 'x'}),
      throwsA(isA<LlmConfigurationException>()),
    );
  });
}
