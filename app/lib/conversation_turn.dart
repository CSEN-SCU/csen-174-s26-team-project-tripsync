/// A single turn in the on-screen voice conversation (Orbit or the listener).
class ConversationTurn {
  const ConversationTurn({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}
