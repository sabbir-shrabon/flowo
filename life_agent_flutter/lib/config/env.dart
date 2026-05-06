/// Build-time environment configuration.
///
/// Use `--dart-define` to provide values:
/// - `SUPABASE_URL`
/// - `SUPABASE_ANON_KEY`
/// - `API_BASE_URL`
///
/// Example:
/// `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... --dart-define=API_BASE_URL=http://10.0.2.2:8000`
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Optional override; if not provided we fall back to platform defaults
  /// in `ApiConfig`.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String requireSupabaseUrl() {
    if (supabaseUrl.trim().isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL. Run with --dart-define=SUPABASE_URL=...',
      );
    }
    return supabaseUrl;
  }

  static String requireSupabaseAnonKey() {
    if (supabaseAnonKey.trim().isEmpty) {
      throw StateError(
        'Missing SUPABASE_ANON_KEY. Run with --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    return supabaseAnonKey;
  }
}

