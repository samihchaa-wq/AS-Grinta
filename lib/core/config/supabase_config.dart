abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ovzijmqrnsgcmryinkfa.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_YjiJqFuuQPelzQtnuyTXnA_6thtFIgl',
  );

  static void validate() {
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL et SUPABASE_ANON_KEY doivent être fournis via --dart-define.',
      );
    }
  }
}
