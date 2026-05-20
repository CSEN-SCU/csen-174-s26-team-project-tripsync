import 'llm_exceptions.dart';

/// Validates user input, blocks obvious injection / abuse, wraps content for the model.
///
/// Best-effort only; the model still receives untrusted data inside delimiters.
abstract final class LlmPromptGuardrails {
  static const int maxUserCharacters = 4000;

  static const _open = '<<<USER_INPUT>>>';
  static const _close = '<<<END_USER_INPUT>>>';

  static final List<RegExp> _injectionPatterns = [
    RegExp(r'ignore\s+(all\s+)?(previous|prior)\s+instructions', caseSensitive: false),
    RegExp(r'disregard\s+(the\s+)?(above|prior)', caseSensitive: false),
    RegExp(r'you\s+are\s+now\s+(a|an|the)\b', caseSensitive: false),
    RegExp(r'new\s+system\s+prompt', caseSensitive: false),
    RegExp(r'<\s*/\s*system\s*>', caseSensitive: false),
  ];

  /// High-confidence non-travel / unsafe patterns (avoid blocking real trip questions).
  static final List<RegExp> _offTopicPatterns = [
    RegExp(
      r'\b(write|generate|debug|refactor)\s+(me\s+)?(a\s+)?(python|java|javascript|typescript|rust|go|c\+\+|csharp|kotlin|swift)\s+(code|script|program|function|class)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b(exec|eval)\s*\(', caseSensitive: false),
    RegExp(r'\b(curl|wget)\s+https?://', caseSensitive: false),
    RegExp(r'\b(rm\s+-rf|format\s+c:)\b', caseSensitive: false),
    RegExp(r'\b(reveal|print|dump)\s+(your|the)\s+(system|hidden)\s+prompt\b', caseSensitive: false),
    RegExp(r'\b(api[_\s-]?key|secret|password)\s*[:=]\s*\S+', caseSensitive: false),
  ];

  static String prepareFencedUserPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw LlmConfigurationException('Input is empty after trimming.');
    }
    if (trimmed.length > maxUserCharacters) {
      throw LlmConfigurationException(
        'Input exceeds the maximum length of $maxUserCharacters characters.',
      );
    }
    _throwIfMatches(
      _injectionPatterns,
      trimmed,
      'That message cannot be sent because it may contain disallowed instructions. '
      'Rephrase as a simple travel or destination question.',
    );
    _throwIfMatches(
      _offTopicPatterns,
      trimmed,
      'TripSync only accepts travel- and destination-related messages. '
      'This looks like a non-travel technical or unsafe request; rephrase as a normal visitor question.',
    );

    final sanitized = _sanitizeText(trimmed);
    final neutral = _neutralizeDelimiters(sanitized);
    return '$_open\n$neutral\n$_close';
  }

  static void _throwIfMatches(List<RegExp> patterns, String input, String message) {
    for (final re in patterns) {
      if (re.hasMatch(input)) {
        throw LlmConfigurationException(message);
      }
    }
  }

  static String _sanitizeText(String s) {
    final buf = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x0A || r == 0x0D || r == 0x09) {
        buf.writeCharCode(r);
      } else if (r >= 0x20 && r != 0x7F) {
        buf.writeCharCode(r);
      } else if (r == 0x20) {
        buf.write(' ');
      }
    }
    final out = buf.toString().trim();
    if (out.isEmpty) {
      throw LlmConfigurationException('Input contained no usable text after sanitization.');
    }
    return out;
  }

  static String _neutralizeDelimiters(String s) {
    return s
        .replaceAll(_open, '«USER_INPUT»')
        .replaceAll(_close, '«END_USER_INPUT»');
  }
}
