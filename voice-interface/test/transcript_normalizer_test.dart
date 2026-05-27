import 'package:test/test.dart';
import 'package:voice_interface/voice_interface.dart';

void main() {
  group('normalizeTranscriptForConversation', () {
    test('trims and collapses whitespace', () {
      expect(
        normalizeTranscriptForConversation('  uh   tell me about the Ferry Building  '),
        'tell me about the Ferry Building',
      );
    });
  });

  group('wake word and over', () {
    test('detects orbit wake word', () {
      expect(transcriptContainsWakeWord('hey Orbit'), isTrue);
      expect(transcriptContainsWakeWord('orbital mechanics'), isFalse);
    });

    test('detects over at end', () {
      expect(transcriptEndsWithOver('what is nearby over'), isTrue);
      expect(transcriptEndsWithOver('overlook the park'), isFalse);
    });

    test('extracts command between orbit and over', () {
      expect(
        extractCommandFromWakeTranscript(
          'Orbit what restaurants are open over',
        ),
        'what restaurants are open',
      );
    });
  });

  group('WakeWordSession', () {
    test('returns null until over is spoken', () {
      final session = WakeWordSession();
      expect(session.ingest('Orbit tell me more'), isNull);
      expect(session.awaitingCommand, isTrue);
    });

    test('returns command when over ends the phrase', () {
      final session = WakeWordSession();
      expect(session.ingest('Orbit tell me more'), isNull);
      expect(
        session.ingest('Orbit tell me more about the pier over'),
        'tell me more about the pier',
      );
      expect(session.awaitingCommand, isFalse);
    });
  });
}
