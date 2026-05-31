import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'conversation_turn.dart';
import 'models/trip_poi.dart';

/// Result of Groq narration (optional web search via Compound).
class PoiNarration {
  const PoiNarration({
    required this.script,
    this.usedWebSearch = false,
    this.sourceUrls = const [],
  });

  final String script;
  final bool usedWebSearch;
  final List<String> sourceUrls;
}

/// Uses Groq chat (and optionally Compound web search) for POI tour scripts.
class GroqPoiNarrator {
  GroqPoiNarrator._();

  static const String _chatUrl = 'https://api.groq.com/openai/v1/chat/completions';

  /// Built-in web search (Tavily). See https://console.groq.com/docs/tool-use/built-in-tools/web-search
  static const String _compoundMiniModel = 'groq/compound-mini';

  /// Fallback when Compound is unavailable or errors.
  static const String _fallbackModel = 'llama-3.3-70b-versatile';

  static const String _introSystemPrompt = '''
You are Orbit, a warm audio travel guide. The listener is on foot nearby.

Write a spoken suggestion about the place: what it is, what makes it interesting, and why it fits their interests. Sound natural and concise, like a friend—not a brochure.

Rules:
- Prefer facts from web search results when provided; otherwise use the database fields only.
- Do not invent hours, prices, or exhibits that are not supported by your sources.
- No markdown, bullets, emojis, or labels like "Tip:".
- 2–4 short sentences. Stay under 380 characters total.
''';

  static const String _followUpSystemPrompt = '''
You are Orbit, a warm audio travel guide. The listener is on foot near a place you told them about.

Answer their latest follow-up using the conversation so far. Use web search when the question needs specific facts (artists, exhibits, hours, history, who/what/when).

Rules:
- Give the full answer in this response. NEVER say you will research, look it up, check later, or "let me find out" — search now and speak the facts.
- Start by addressing what they asked (paraphrase their question in your first sentence).
- Stay grounded in the place context; do not invent facts unsupported by search or the database.
- If the transcript is garbled or not a clear question, say you did not quite catch it and ask them to repeat. Do NOT repeat generic place info unrelated to their question.
- No markdown, bullets, emojis, or "As an AI".
- 2–5 short sentences. Stay under 420 characters total.
''';

  /// Opening suggestion for a nearby POI.
  static Future<PoiNarration> narrate({
    required String apiKey,
    required TripPoi poi,
    required List<String> userInterests,
    String? fallback,
    bool useWebSearch = true,
  }) async {
    final base = fallback ?? poi.recommendationBlurb;
    if (apiKey.trim().isEmpty) {
      return PoiNarration(script: base);
    }

    final key = apiKey.trim();
    final userPrompt = _buildIntroUserPrompt(
      poi: poi,
      userInterests: userInterests,
      useWebSearch: useWebSearch,
    );

    return _completeWithFallback(
      apiKey: key,
      systemPrompt: _introSystemPrompt,
      userPrompt: userPrompt,
      messages: null,
      fallback: base,
      useWebSearch: useWebSearch,
    );
  }

  /// Answers a spoken follow-up using the same Compound + search stack when possible.
  static Future<PoiNarration> replyToFollowUp({
    required String apiKey,
    required String userTranscript,
    required String orbitSuggestion,
    TripPoi? poi,
    List<String> userInterests = const [],
    List<ConversationTurn> priorTurns = const [],
    bool useWebSearch = true,
  }) async {
    final fallback =
        "I heard you. Add GROQ_API_KEY to get a spoken answer, or tap replay to try again.";
    final trimmed = userTranscript.trim();
    if (trimmed.isEmpty) {
      return PoiNarration(script: "I didn't catch a question. Try asking again.");
    }
    if (apiKey.trim().isEmpty) {
      return PoiNarration(script: fallback);
    }

    final key = apiKey.trim();
    final messages = _buildFollowUpMessages(
      poi: poi,
      userTranscript: trimmed,
      orbitSuggestion: orbitSuggestion,
      userInterests: userInterests,
      priorTurns: priorTurns,
      useWebSearch: useWebSearch,
      forceSearch: false,
    );

    var result = await _completeWithFallback(
      apiKey: key,
      systemPrompt: _followUpSystemPrompt,
      messages: messages,
      fallback:
          "I'm not sure about that right now. Try asking something simpler about the place nearby.",
      useWebSearch: useWebSearch,
    );

    final shouldRetry = useWebSearch &&
        (_isDeferralResponse(result.script) ||
            (_questionLikelyNeedsSearch(trimmed) && !result.usedWebSearch));

    if (shouldRetry) {
      developer.log(
        'Follow-up retrying with forced web search (deferral=${_isDeferralResponse(result.script)} '
        'usedSearch=${result.usedWebSearch})',
        name: 'Orbit.groq_follow_up',
      );
      final retryMessages = _buildFollowUpMessages(
        poi: poi,
        userTranscript: trimmed,
        orbitSuggestion: orbitSuggestion,
        userInterests: userInterests,
        priorTurns: priorTurns,
        useWebSearch: true,
        forceSearch: true,
      );
      final retry = await _completeWithFallback(
        apiKey: key,
        systemPrompt: _followUpSystemPrompt,
        messages: retryMessages,
        fallback: result.script,
        useWebSearch: true,
      );
      if (retry.script.isNotEmpty && !_isDeferralResponse(retry.script)) {
        result = retry;
      }
    }

    return result;
  }

  static Future<PoiNarration> _completeWithFallback({
    required String apiKey,
    required String systemPrompt,
    String? userPrompt,
    List<Map<String, dynamic>>? messages,
    required String fallback,
    required bool useWebSearch,
  }) async {
    if (useWebSearch) {
      try {
        final withSearch = await _complete(
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          messages: messages,
          model: _compoundMiniModel,
          useWebSearch: true,
        );
        if (withSearch.script.isNotEmpty) return withSearch;
      } catch (e, st) {
        developer.log(
          'Compound web search failed, falling back to LLM: $e',
          name: 'Orbit.groq_chat',
          stackTrace: st,
        );
      }
    }

    try {
      final plain = await _complete(
        apiKey: apiKey,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        messages: messages,
        model: _fallbackModel,
        useWebSearch: false,
      );
      if (plain.script.isNotEmpty) return plain;
    } catch (e, st) {
      developer.log('$e', name: 'Orbit.groq_chat', stackTrace: st);
    }

    return PoiNarration(script: fallback);
  }

  static Future<PoiNarration> _complete({
    required String apiKey,
    required String systemPrompt,
    String? userPrompt,
    List<Map<String, dynamic>>? messages,
    required String model,
    required bool useWebSearch,
  }) async {
    final messageList = messages ??
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt ?? ''},
        ];

    final body = <String, dynamic>{
      'model': model,
      'messages': messageList,
      'temperature': 0.65,
      'max_tokens': 320,
    };

    if (useWebSearch) {
      body['search_settings'] = {
        'country': 'united states',
      };
    }

    final response = await http
        .post(
          Uri.parse(_chatUrl),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(
          const Duration(seconds: 18),
          onTimeout: () => throw GroqPoiNarratorException(
            408,
            'Groq request timed out after 18s',
          ),
        );

    if (response.statusCode != 200) {
      final snippet = response.body.length > 280
          ? '${response.body.substring(0, 280)}…'
          : response.body;
      throw GroqPoiNarratorException(response.statusCode, snippet);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw GroqPoiNarratorException(0, 'Empty choices in Groq response');
    }

    final choice = choices.first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>? ?? {};
    final content = message['content']?.toString() ?? '';
    final sources = useWebSearch ? _extractSourceUrls(message) : <String>[];
    final searched = useWebSearch && _usedWebSearchTool(message);

    return PoiNarration(
      script: _cleanScript(content),
      usedWebSearch: searched,
      sourceUrls: sources,
    );
  }

  static bool _usedWebSearchTool(Map<String, dynamic> message) {
    final tools = message['executed_tools'] as List<dynamic>?;
    if (tools == null || tools.isEmpty) return false;

    for (final tool in tools) {
      if (tool is! Map<String, dynamic>) continue;
      if (tool['search_results'] != null) return true;
    }
    return false;
  }

  static String _buildIntroUserPrompt({
    required TripPoi poi,
    required List<String> userInterests,
    required bool useWebSearch,
  }) {
    final searchInstruction = useWebSearch
        ? '''
First, search the web for "${poi.name}" ${poi.city.isEmpty ? 'San Francisco Bay Area' : poi.city} to learn what this place is and what visitors notice. Use search results for specific, accurate details.
Then write the spoken suggestion.
'''
        : '';

    return '''
$searchInstruction
${_placeContext(poi, userInterests)}
''';
  }

  static List<Map<String, dynamic>> _buildFollowUpMessages({
    required TripPoi? poi,
    required String userTranscript,
    required String orbitSuggestion,
    required List<String> userInterests,
    required List<ConversationTurn> priorTurns,
    required bool useWebSearch,
    required bool forceSearch,
  }) {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _followUpSystemPrompt},
    ];

    if (priorTurns.isEmpty) {
      messages.add({'role': 'assistant', 'content': orbitSuggestion});
    } else {
      for (final turn in priorTurns) {
        messages.add({
          'role': turn.isUser ? 'user' : 'assistant',
          'content': turn.text,
        });
      }
    }

    messages.add({
      'role': 'user',
      'content': _buildFollowUpUserPrompt(
        poi: poi,
        userTranscript: userTranscript,
        userInterests: userInterests,
        useWebSearch: useWebSearch,
        forceSearch: forceSearch,
      ),
    });

    return messages;
  }

  static String _buildFollowUpUserPrompt({
    required TripPoi? poi,
    required String userTranscript,
    required List<String> userInterests,
    required bool useWebSearch,
    required bool forceSearch,
  }) {
    final placeBlock = poi != null
        ? _placeContext(poi, userInterests)
        : 'Place context: (general nearby area)';

    final placeName = poi?.name ?? 'this place';
    final city = poi?.city.isNotEmpty == true ? poi!.city : 'nearby';

    final searchInstruction = useWebSearch
        ? forceSearch
            ? '''
REQUIRED: Search the web right now for "$placeName" $city — specifically: $userTranscript
Use those search results and answer in this response. Do not say you will research later.
'''
            : '''
First, search the web for "$placeName" $city — focus on: $userTranscript
Then give your spoken answer using facts from search.
'''
        : '';

    return '''
$searchInstruction
$placeBlock

Listener's latest question (speech-to-text — answer THIS):
"$userTranscript"

Write Orbit's spoken answer now.
''';
  }

  static bool _isDeferralResponse(String script) {
    final lower = script.toLowerCase();
    return RegExp(
      r"(let me|lemme|i'll|i will|give me a (moment|sec)|hang on).{0,40}(research|look (that )?up|check|find out|search)",
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static bool _questionLikelyNeedsSearch(String transcript) {
    final lower = transcript.toLowerCase();
    return RegExp(
      r'\b(who|what|when|where|which|how many|how old|artist|artists|exhibit|exhibits|'
      r'collection|painting|sculpture|architect|founded|history|hour|hours|open|closed|'
      r'admission|ticket|price|famous|known for|display|gallery|museum)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static String _placeContext(TripPoi poi, List<String> userInterests) {
    final interests =
        userInterests.where((t) => t.trim().isNotEmpty).join(', ');
    return '''
Place name: ${poi.name}
Category: ${poi.category.isEmpty ? 'point of interest' : poi.category}
City: ${poi.city.isEmpty ? 'nearby' : poi.city}
Tags: ${poi.tags.isEmpty ? 'general' : poi.tags.join(', ')}
User interests: ${interests.isEmpty ? 'exploring the area' : interests}
${_distanceLine(poi.distanceMeters)}
Coordinates: ${poi.latitude.toStringAsFixed(5)}, ${poi.longitude.toStringAsFixed(5)}
Database description: ${poi.description.isEmpty ? '(none provided)' : poi.description}
''';
  }

  static List<String> _extractSourceUrls(Map<String, dynamic> message) {
    final urls = <String>[];
    final tools = message['executed_tools'] as List<dynamic>?;
    if (tools == null) return urls;

    for (final tool in tools) {
      if (tool is! Map<String, dynamic>) continue;
      final searchResults = tool['search_results'];
      if (searchResults is! Map<String, dynamic>) continue;
      final results = searchResults['results'] as List<dynamic>?;
      if (results == null) continue;

      for (final result in results) {
        if (result is! Map<String, dynamic>) continue;
        final url = result['url']?.toString().trim();
        if (url != null && url.isNotEmpty && !urls.contains(url)) {
          urls.add(url);
        }
      }
    }

    return urls.take(3).toList();
  }

  static String _distanceLine(double? meters) {
    if (meters == null) return 'Distance: unknown';
    if (meters < 160) {
      return 'Distance: about ${meters.round()} meters (${(meters * 3.28084).round()} feet)';
    }
    final miles = meters / 1609.344;
    if (miles < 0.2) {
      return 'Distance: about ${(meters * 3.28084).round()} feet';
    }
    return 'Distance: about ${miles.toStringAsFixed(1)} miles';
  }

  static String _cleanScript(String raw) {
    var text = raw.trim();
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      text = text.substring(1, text.length - 1).trim();
    }
    return text
        .replaceAll('—', ', ')
        .replaceAll('–', ', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class GroqPoiNarratorException implements Exception {
  GroqPoiNarratorException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'GroqPoiNarratorException($statusCode): $message';
}
