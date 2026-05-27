import 'transcript_normalizer.dart';

/// Tracks idle (waiting for "Orbit") vs command capture (until "over").
class WakeWordSession {
  bool _awaitingCommand = false;

  bool get awaitingCommand => _awaitingCommand;

  /// Processes a partial or final STT string. Returns a command to send to the
  /// LLM when the user finishes with "over", or null while still listening.
  String? ingest(String recognizedWords) {
    final raw = recognizedWords.trim();
    if (raw.isEmpty) return null;

    if (!_awaitingCommand) {
      if (!transcriptContainsWakeWord(raw)) return null;
      _awaitingCommand = true;
    }

    if (!transcriptEndsWithOver(raw)) return null;

    final command = extractCommandFromWakeTranscript(raw);
    reset();
    if (command.isEmpty) return null;
    return command;
  }

  /// Called when wake word is heard so UI can show command-capture state.
  bool noteWakeIfNeeded(String recognizedWords) {
    if (_awaitingCommand) return false;
    if (!transcriptContainsWakeWord(recognizedWords)) return false;
    _awaitingCommand = true;
    return true;
  }

  void reset() {
    _awaitingCommand = false;
  }
}
