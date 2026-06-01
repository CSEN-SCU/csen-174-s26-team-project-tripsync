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

    test('detects common orbit mishears from speech-to-text', () {
      expect(transcriptContainsWakeWord('hey or bit what is this'), isTrue);
      expect(transcriptContainsWakeWord('orbid when is it open'), isTrue);
      expect(transcriptContainsWakeWord('orbot tell me more'), isTrue);
      // Still must not trip on unrelated words.
      expect(transcriptContainsWakeWord('orbital mechanics'), isFalse);
      expect(transcriptContainsWakeWord('order a coffee'), isFalse);
    });

    test('detects over at end', () {
      expect(transcriptEndsWithOver('what is nearby over'), isTrue);
      expect(transcriptEndsWithOver('overlook the park'), isFalse);
    });

    test('detects over with trailing punctuation or "and out"', () {
      expect(transcriptEndsWithOver('what is nearby over.'), isTrue);
      expect(transcriptEndsWithOver('what is nearby over and out'), isTrue);
    });

    test('extracts command between orbit and over', () {
      expect(
        extractCommandFromWakeTranscript(
          'Orbit what restaurants are open over',
        ),
        'what restaurants are open',
      );
      expect(
        extractCommandFromWakeTranscript(
          'Orbit when it is open over',
        ),
        'when it is open',
      );
      expect(
        extractCommandFromWakeTranscript(
          'yeah tell me Orbit when it is open over',
        ),
        'when it is open',
      );
      expect(
        extractCommandFromWakeTranscript(
          'or bit when it is open over and out',
        ),
        'when it is open',
      );
    });

    test('preview shows orbit through first over only', () {
      expect(
        wakeSessionTranscriptPreview('hello Orbit what is nearby over'),
        'Orbit what is nearby over',
      );
      expect(
        wakeSessionTranscriptPreview(
          'Orbit when it is open over extra STT noise',
        ),
        'Orbit when it is open over',
      );
      expect(wakeSessionTranscriptPreview('just talking'), isNull);
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
