import 'package:flutter_dotenv/flutter_dotenv.dart';

// ========================================
// SUPABASE CONFIGURATION
//
// Credentials are loaded in this priority order:
// 1. --dart-define (compile-time, highest priority)
// 2. .env file (runtime, loaded via flutter_dotenv)
//
// For development: create a .env file in project root
// For CI/production: use --dart-define flags
//
// NOTE: SUPABASE_ANON_KEY is a PUBLIC client key (publishable).
// It is safe to embed in client apps. RLS policies protect data.
// Never use service_role keys in client apps.
// ========================================

/// Get Supabase URL from environment
String get supabaseUrl {
  // First check compile-time dart-define
  const dartDefineUrl = String.fromEnvironment('SUPABASE_URL');
  if (dartDefineUrl.isNotEmpty) return dartDefineUrl;

  // Fall back to .env file
  return dotenv.env['SUPABASE_URL'] ?? '';
}

/// Get Supabase publishable/anon key from environment.
/// This is a PUBLIC key safe to use in client apps.
String get supabaseAnonKey {
  // First check compile-time dart-define
  const dartDefineKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (dartDefineKey.isNotEmpty) return dartDefineKey;

  // Fall back to .env file
  return dotenv.env['SUPABASE_ANON_KEY'] ?? '';
}

/// Load .env file. Call this early in main() before accessing config.
/// Fails silently if .env doesn't exist (allows --dart-define fallback).
Future<void> loadEnvConfig() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // .env file not found - that's okay, we'll use --dart-define
    // This is expected in CI/production builds
  }
}

/// Validates that Supabase credentials are available.
/// Returns an error message if missing, null if valid.
String? validateSupabaseConfig() {
  if (supabaseUrl.isEmpty) {
    return '''
╔══════════════════════════════════════════════════════════════════╗
║  SUPABASE_URL is missing!                                        ║
║                                                                  ║
║  Option 1: Create a .env file in project root with:              ║
║    SUPABASE_URL=https://xxx.supabase.co                          ║
║    SUPABASE_ANON_KEY=your-anon-key                               ║
║                                                                  ║
║  Option 2: Run with --dart-define flags:                         ║
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
║  Add it to .env or use --dart-define.                            ║
╚══════════════════════════════════════════════════════════════════╝
''';
  }

  return null; // Valid
}
