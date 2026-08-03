class Secrets {
  static const String groqApiKey = String.fromEnvironment(
        'GROQ_API_KEY',
        defaultValue: '',
      );

  static const String groqModel = String.fromEnvironment(
    'GROQ_MODEL',
    defaultValue: 'llama-3.1-8b-instant',
  );
}
