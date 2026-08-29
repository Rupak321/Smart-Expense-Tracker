/// Build-time configuration for the AI assistant.
///
/// These are `String.fromEnvironment`, which means they are baked in when the
/// app is COMPILED, not read at runtime. A build without `--dart-define` ships
/// with an empty key and the assistant cannot call the API:
///
///   flutter run --dart-define=GROQ_API_KEY=gsk_your_key_here
///   flutter build apk --dart-define=GROQ_API_KEY=gsk_your_key_here
class Secrets {
  static const String groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: '',
  );

  /// Groq deprecated `llama-3.1-8b-instant` on 17 June 2026 and shuts it down
  /// on 16 August 2026; `openai/gpt-oss-20b` is Groq's stated replacement.
  /// Override with --dart-define=GROQ_MODEL=... to pin a different one.
  static const String groqModel = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'openai/gpt-oss-20b',
  );

  static bool get hasApiKey =>
      groqApiKey.isNotEmpty && groqApiKey.startsWith('gsk_');
}
