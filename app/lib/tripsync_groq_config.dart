/// Groq API credentials are supplied at **compile time** via `--dart-define`
/// (recommended: `--dart-define-from-file` pointing at a local `.env` file).
///
/// See `app/.env.example` for the exact variable name and run examples.
String groqApiKeyFromEnvironment() {
  const key = String.fromEnvironment('GROQ_API_KEY');
  return key;
}
