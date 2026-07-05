class OnlineLicenseConfig {
  static const bool enabled = bool.fromEnvironment(
    'SUPABASE_LICENSE_ENABLED',
    defaultValue: true,
  );
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://kcylkaiawiftlkkkltly.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtjeWxrYWlhd2lmdGxra2tsdGx5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5NzY4MDQsImV4cCI6MjA5ODU1MjgwNH0.sQJofPmUvBS7qxLwAvhpk0S3ohRZqdfolNTVumZjfSg',
  );
  static const String activateFunction = String.fromEnvironment(
    'SUPABASE_LICENSE_ACTIVATE_FUNCTION',
    defaultValue: 'activate-license',
  );
  static const String validateFunction = String.fromEnvironment(
    'SUPABASE_LICENSE_VALIDATE_FUNCTION',
    defaultValue: 'validate-license',
  );

  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}
