abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String usernameDomain = String.fromEnvironment(
    'USERNAME_DOMAIN',
  );
  static const String publicAppUrl = String.fromEnvironment('PUBLIC_APP_URL');
  static const String version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  static void validate() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      if (usernameDomain.isEmpty) 'USERNAME_DOMAIN',
      if (publicAppUrl.isEmpty) 'PUBLIC_APP_URL',
    ];

    if (missing.isNotEmpty) {
      throw StateError(
        'Configuration manquante : ${missing.join(', ')}. '
        'Utilise --dart-define-from-file=config/production.json.',
      );
    }
  }
}
