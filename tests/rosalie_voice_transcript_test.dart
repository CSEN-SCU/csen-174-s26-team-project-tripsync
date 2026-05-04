import 'package:test/test.dart';
import 'package:voice_interface/voice_interface.dart';

void main() {
  group('rosalie: speech-to-text shaping for the conversation layer', () {
    test(
      'when I dictate with pauses and filler, Orbit sends cleaned text to the guide so my intent is clear',
      () {
        // As a traveler using hands-free voice, I want mumbling and extra gaps stripped so the guide understands what I asked.

        // Arrange
        const raw = '  uh   tell me about the Ferry Building  ';

        // Act
        final normalized = normalizeTranscriptForConversation(raw);

        // Assert
        expect(
          normalized,
          'tell me about the Ferry Building',
          reason: 'STT output should be trimmed and have collapsed whitespace, without changing words',
        );
      },
    );
  });
}
