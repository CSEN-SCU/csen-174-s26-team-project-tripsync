/// Normalizes on-device speech-to-text strings before they reach the conversation layer.
String normalizeTranscriptForConversation(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  return _stripLeadingFillers(collapsed);
}

/// Strips wake word [orbit] and end phrase [over] from a captured command.
String extractCommandFromWakeTranscript(String raw) {
  var text = normalizeTranscriptForConversation(raw);
  if (text.isEmpty) return '';

  text = text.replaceFirst(
    RegExp(r'^orbit\b[,.]?\s*', caseSensitive: false),
    '',
  );
  text = text.replaceFirst(
    RegExp(r'\s+over\s*[,.!?]?\s*$', caseSensitive: false),
    '',
  );
  text = text.replaceFirst(
    RegExp(r'^over\s*[,.!?]?\s*$', caseSensitive: false),
    '',
  );

  return text.trim();
}

/// Whether [text] contains the wake word as its own token.
bool transcriptContainsWakeWord(String text) {
  return RegExp(r'\borbit\b', caseSensitive: false).hasMatch(text.trim());
}

/// Whether [text] ends with the end-of-transmission phrase "over".
bool transcriptEndsWithOver(String text) {
  return RegExp(r'\bover\s*[,.!?]?\s*$', caseSensitive: false)
      .hasMatch(text.trim());
}

/// Live UI: once "Orbit" is heard, show only from that word onward.
String? wakeSessionTranscriptPreview(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final match =
      RegExp(r'\borbit\b.*', caseSensitive: false).firstMatch(trimmed);
  return match?.group(0)?.trim();
}

String _stripLeadingFillers(String text) {
  var result = text;
  const fillers = ['uh', 'um', 'uhh', 'umm'];
  var changed = true;
  while (changed) {
    changed = false;
    for (final filler in fillers) {
      final pattern = RegExp('^$filler\\b[,\\s]*', caseSensitive: false);
      final next = result.replaceFirst(pattern, '');
      if (next != result) {
        result = next.trimLeft();
        changed = true;
      }
    }
  }
  return result.trim();
}
