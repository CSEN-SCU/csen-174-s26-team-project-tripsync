import 'package:flutter/material.dart';
import 'package:llm_integration/llm_integration.dart';

import 'orbit_groq_config.dart';

/// Groq chat (text in / text-out): place descriptions + travel Q&A. Logic lives in `llm_integration`.
class LlmIntegrationScreen extends StatefulWidget {
  const LlmIntegrationScreen({super.key, this.userName});

  final String? userName;

  @override
  State<LlmIntegrationScreen> createState() => _LlmIntegrationScreenState();
}

/// Matches landing / voice screens.
const _kScreenGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF101A38), Color(0xFF0B1020), Color(0xFF1B1840)],
  ),
);

const _kMaxFieldChars = 2000;

const _kSamplePlaceNotes =
    'Crissy Field East Beach — flat walk, Golden Gate views, picnic-friendly.';

/// Trusted task lines (not user-controlled).
const _kTaskDescription = 'Write 2–3 short sentences: a welcoming visitor description for this place. '
    'No bullet list; plain sentences only.';

const _kTaskQuestion = 'Answer clearly in 2–5 sentences as Orbit for a traveler (any destination: cities, parks, '
    'beaches, transit, day trips, logistics). If you are unsure, say what you do know and what to double-check.';

class _LlmIntegrationScreenState extends State<LlmIntegrationScreen> {
  late final LlmClient _client;
  /// Shared cap: **3** LLM starts / rolling minute for description + Q&A combined.
  final _sendThrottle = LlmChatRateLimiter();
  final _placeNotes = TextEditingController(text: _kSamplePlaceNotes);
  final _question = TextEditingController();

  String? _descriptionResult;
  String? _answerResult;
  String? _errorLine;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = LlmClient(config: LlmConfig.fromGroqDartDefines());
  }

  @override
  void dispose() {
    _client.close();
    _placeNotes.dispose();
    _question.dispose();
    super.dispose();
  }

  bool get _hasKey => groqApiKeyFromEnvironment().isNotEmpty;

  /// Shared request path: busy flag, errors, [mounted] checks.
  Future<void> _complete({
    required String userPrompt,
    required String systemPrompt,
    required void Function(String text) applyResult,
    bool clearDescription = false,
    bool clearAnswer = false,
  }) async {
    if (!_hasKey || _busy) return;
    final blocked = _sendThrottle.rejectReason();
    if (blocked != null) {
      setState(() => _errorLine = blocked);
      return;
    }
    _sendThrottle.recordSendStarted();
    _busy = true;
    setState(() {
      _errorLine = null;
      if (clearDescription) _descriptionResult = null;
      if (clearAnswer) _answerResult = null;
    });
    try {
      final text = await _client.completeText(
        userPrompt: userPrompt,
        systemPrompt: systemPrompt,
      );
      if (!mounted) return;
      setState(() => applyResult(text));
    } on LlmException catch (e) {
      if (!mounted) return;
      setState(() => _errorLine = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorLine = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runDescription() => _complete(
        userPrompt: _placeNotes.text.trim(),
        systemPrompt: _kTaskDescription,
        clearDescription: true,
        applyResult: (t) => _descriptionResult = t,
      );

  Future<void> _runQuestion() async {
    final q = _question.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type a question first.')),
      );
      return;
    }
    await _complete(
      userPrompt: q,
      systemPrompt: _kTaskQuestion,
      clearAnswer: true,
      applyResult: (t) => _answerResult = t,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: _kScreenGradient,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Header(userName: widget.userName, theme: theme),
                    _EnvHint(theme: theme, hasKey: _hasKey),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Auto-generated description',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Place notes (editable)',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _placeNotes,
                            maxLines: 3,
                            maxLength: _kMaxFieldChars,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(theme, 'What should the model describe?'),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: (!_hasKey || _busy) ? null : _runDescription,
                              icon: Icon(
                                _busy ? Icons.hourglass_top_rounded : Icons.auto_awesome_rounded,
                              ),
                              label: Text(_busy ? 'Working…' : 'Generate description'),
                            ),
                          ),
                          if (_descriptionResult != null)
                            _ResultBlock(theme: theme, label: 'Result', text: _descriptionResult!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Answer a question',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _question,
                            maxLines: 3,
                            maxLength: _kMaxFieldChars,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration(
                              theme,
                              'e.g. Is Joshua Tree crowded on weekends?',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: (!_hasKey || _busy) ? null : _runQuestion,
                              icon: const Icon(Icons.question_answer_rounded),
                              label: Text(_busy ? 'Working…' : 'Ask Orbit'),
                            ),
                          ),
                          if (_answerResult != null)
                            _ResultBlock(theme: theme, label: 'Answer', text: _answerResult!),
                        ],
                      ),
                    ),
                    if (_errorLine != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorLine!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error.withValues(alpha: 0.95),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(ThemeData theme, String hint) {
  final borderColor = Colors.white.withValues(alpha: 0.12);
  final radius = BorderRadius.circular(16);
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
    filled: true,
    fillColor: Colors.black.withValues(alpha: 0.18),
    border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
    enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: borderColor)),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: theme.colorScheme.secondary, width: 1.5),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.userName, required this.theme});

  final String? userName;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final name = userName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name != null && name.isNotEmpty) ...[
          Text(
            'Hi, $name',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'LLM (text in / text out)',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EnvHint extends StatelessWidget {
  const _EnvHint({required this.theme, required this.hasKey});

  final ThemeData theme;
  final bool hasKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Same compile-time defines as Orpheus TTS: GROQ_API_KEY. '
          'Optional: GROQ_LLM_MODEL, GROQ_LLM_BASE_URL (see app/.env.example). '
          'Run: flutter run --dart-define-from-file=.env',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.35,
          ),
        ),
        if (!hasKey) ...[
          const SizedBox(height: 12),
          Text(
            'GROQ_API_KEY is empty in this build. Add it to app/.env and rebuild with --dart-define-from-file=.env',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error.withValues(alpha: 0.95),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.theme, required this.label, required this.text});

  final ThemeData theme;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
