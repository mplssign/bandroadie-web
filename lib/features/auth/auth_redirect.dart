// ============================================================================
// AUTH REDIRECT — Single source of truth for all authentication redirect URLs
//
// WHY THIS EXISTS:
// All Supabase magic link calls (signInWithOtp) need an emailRedirectTo URL.
// On web, this MUST use the current runtime origin (Uri.base.origin) so that
// staging, preview, and production deployments each redirect correctly.
// On native, this uses the app's deep link scheme.
//
// RULES:
// 1. Every signInWithOtp call MUST use a function from this file.
// 2. NEVER hardcode "https://bandroadie.com" in any auth redirect.
// 3. NEVER inline redirect URL construction in screen code.
// 4. To add a new auth entry point, call authRedirectUrl() or
//    authRedirectUrlWithPath() from here — do not duplicate the logic.
//
// DEEP LINK SCHEME (native):
//   bandroadie://login-callback
//
// WEB REDIRECT PATTERN:
//   ${Uri.base.origin}/path  (e.g., https://bandroadie-staging.vercel.app/app)
// ============================================================================

import 'package:flutter/foundation.dart' show kIsWeb;

/// Native deep link scheme + host for auth callbacks.
/// Must match the scheme registered in AndroidManifest.xml and Info.plist,
/// and the pattern matched in DeepLinkService.
const String _nativeAuthCallback = 'bandroadie://login-callback';

/// Returns the auth redirect URL for the login flow.
///
/// - Web: `${currentOrigin}/app`
/// - Native: `bandroadie://login-callback`
String authRedirectUrl() => authRedirectUrlWithPath('/app');

/// Returns the auth redirect URL with a custom path (e.g., for invite flow).
///
/// - Web: `${currentOrigin}${path}`  (path must start with `/`)
/// - Native: `bandroadie://login-callback`
///
/// Example:
/// ```dart
/// authRedirectUrlWithPath('/invite?token=abc123')
/// // Web:    https://bandroadie-staging.vercel.app/invite?token=abc123
/// // Native: bandroadie://login-callback
/// ```
String authRedirectUrlWithPath(String path) {
  assert(path.startsWith('/'), 'Auth redirect path must start with /');

  if (kIsWeb) {
    return '${Uri.base.origin}$path';
  }
  return _nativeAuthCallback;
}
