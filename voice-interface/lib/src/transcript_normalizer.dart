/// Wake word + common speech-to-text mishears ("or bit", "orbid", "orbot").
/// Kept tight enough that "orbital" still does NOT match (no trailing boundary).
final RegExp _wakeWordPattern = RegExp(
  r'\b(?:orbit|orbits|orbid|orbot|orbyt|or\s?bit|or\s?bid)\b',
  caseSensitive: false,
);

/// End-of-transmission phrase, tolerating "over and out" and trailing
/// punctuation that STT sometimes appends.
final RegExp _endWordPattern = RegExp(
  r'\bover\b',
  caseSensitive: false,
);

/// Normalizes on-device speech-to-text strings before they reach the conversation layer.
String normalizeTranscriptForConversation(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final collapsed = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  return _stripLeadingFillers(collapsed);
}

/// Strips wake word [orbit] and end phrase [over] from a captured command.
///
/// Uses the text between the first "orbit" and the first "over" after it so
/// earlier STT noise ("yeah tell me… orbit when is it open over") is dropped.
String extractCommandFromWakeTranscript(String raw) {
  final text = normalizeTranscriptForConversation(raw);
  if (text.isEmpty) return '';

  final wake = _wakeWordPattern.firstMatch(text);
  if (wake == null) return '';

  var commandRegion = text.substring(wake.end).trimLeft();
  commandRegion = commandRegion.replaceFirst(RegExp(r'^[,.]\s*'), '');

  final over = _endWordPattern.firstMatch(commandRegion);
  if (over == null) return '';

  return commandRegion.substring(0, over.start).trim();
}

/// Whether [text] contains the wake word as its own token.
bool transcriptContainsWakeWord(String text) {
  return _wakeWordPattern.hasMatch(text.trim());
}

/// Whether [text] ends with the end-of-transmission phrase "over".
bool transcriptEndsWithOver(String text) {
  return RegExp(r'\bover(?:\s+and\s+out)?\s*[,.!?]*\s*$', caseSensitive: false)
      .hasMatch(text.trim());
}

/// Live UI: show from "Orbit" through the first "over" once heard.
String? wakeSessionTranscriptPreview(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final wake = _wakeWordPattern.firstMatch(trimmed);
  if (wake == null) return null;

  final afterOrbit = trimmed.substring(wake.end);
  final over = _endWordPattern.firstMatch(afterOrbit);
  if (over != null) {
    return trimmed.substring(wake.start, wake.end + over.end).trim();
  }
  return trimmed.substring(wake.start).trim();
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
