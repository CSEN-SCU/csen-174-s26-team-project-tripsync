import 'package:http/http.dart' as http;

import 'llm_config.dart';

final class LlmClient {
  LlmClient({
    required this.config,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final LlmConfig config;
  final http.Client _http;

  void close() => _http.close();

  Future<String> completeText({
    required String userPrompt,
    String? systemPrompt,
  }) async {
    throw UnimplementedError(
      'Sprint 1: validate prompt, POST chat/completions, map errors, return text.',
    );
  }
}
