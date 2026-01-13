import 'package:flutter/foundation.dart';

/// Debug-only logger for tracking the magic link authentication flow.
/// Provides clear step-by-step logging to help diagnose auth issues.
///
/// All logging is automatically disabled in release builds via kDebugMode.
/// No sensitive data (tokens, codes, emails) is logged.
class AuthDebugLogger {
  AuthDebugLogger._();

  static const _tag = '🔐 AUTH';

  /// Step 1: Magic link received
  static void linkReceived({
    required String source, // 'cold_start', 'background', 'foreground'
    required String scheme,
    required String host,
  }) {
    _log('STEP 1/4 ─ LINK RECEIVED');
    _log('  Source: $source');
    _log('  URI: $scheme://$host/...');
  }

  /// Step 2: Auth parameters extracted
  static void paramsExtracted({
    required bool hasCode,
    required bool hasAccessToken,
  }) {
    _log('STEP 2/4 ─ PARAMS EXTRACTED');
    _log('  Has PKCE code: $hasCode');
    _log('  Has access token: $hasAccessToken');
  }

  /// Step 3: Session exchange result
  static void sessionExchange({required bool success, String? errorType}) {
    _log('STEP 3/4 ─ SESSION EXCHANGE');
    _log('  Success: $success');
    if (errorType != null) {
      _log('  Error: $errorType');
    }
  }

  /// Step 4: Auth state updated
  static void authStateUpdated({
    required bool isAuthenticated,
    required String
    trigger, // 'onAuthStateChange', 'refreshSession', 'deep_link_notify'
  }) {
    _log('STEP 4/4 ─ AUTH STATE UPDATED');
    _log('  Authenticated: $isAuthenticated');
    _log('  Trigger: $trigger');
  }

  /// Router transition logging
  static void routerTransition({
    required String from, // 'login', 'profile_gate', 'no_band', 'app_shell'
    required String to,
    required String reason,
  }) {
    _log('ROUTER ─ TRANSITION');
    _log('  From: $from → To: $to');
    _log('  Reason: $reason');
  }

  /// Lifecycle event logging
  static void lifecycleEvent({required String from, required String to}) {
    _log('LIFECYCLE ─ $from → $to');
  }

  /// Provider refresh logging
  static void providerRefresh({
    required String provider,
    required bool hasSession,
  }) {
    _log('PROVIDER ─ REFRESH');
    _log('  Provider: $provider');
    _log('  Session present: $hasSession');
  }

  /// Log an error in the auth flow
  static void error({required String step, required String message}) {
    _log('❌ ERROR at $step');
    _log('  $message');
  }

  /// Internal logging method - only logs in debug mode
  static void _log(String message) {
    if (kDebugMode) {
      debugPrint('$_tag $message');
    }
  }
}
