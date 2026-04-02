// ========================================
// SUPABASE CONFIGURATION
//
// All credentials are injected at compile time via --dart-define.
// No runtime .env loading. See tools/deploy_web.sh and .env.example.
//
// NOTE: SUPABASE_ANON_KEY is a PUBLIC client key (publishable).
// It is safe to embed in client apps. RLS policies protect data.
// Never use service_role keys in client apps.
// ========================================

/// Supabase URL from compile-time --dart-define.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// Supabase publishable/anon key from compile-time --dart-define.
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Validates that Supabase credentials are available.
/// Returns an error message if missing, null if valid.
String? validateSupabaseConfig() {
  if (supabaseUrl.isEmpty) {
    return '''
╔══════════════════════════════════════════════════════════════════╗
║  SUPABASE_URL is missing!                                        ║
║                                                                  ║
║  All credentials must be passed via --dart-define at build time. ║
║  See .env.example for required variables.                        ║
║                                                                  ║
║  Example:                                                        ║
║    flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co║
║                --dart-define=SUPABASE_ANON_KEY=your-anon-key     ║
╚══════════════════════════════════════════════════════════════════╝
''';
  }

  if (supabaseAnonKey.isEmpty) {
    return '''
╔══════════════════════════════════════════════════════════════════╗
║  SUPABASE_ANON_KEY is missing!                                   ║
║                                                                  ║
║  Find your publishable anon key in:                              ║
║  Supabase Dashboard > Settings > API > Project API keys          ║
║  Use the "anon public" key (safe for client apps).               ║
║  Pass it via --dart-define=SUPABASE_ANON_KEY=your-key            ║
╚══════════════════════════════════════════════════════════════════╝
''';
  }

  return null; // Valid
}
