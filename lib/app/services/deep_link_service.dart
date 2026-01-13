import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_state_provider.dart';
import 'auth_debug_logger.dart';

/// Deep link service that handles magic links in all app states:
/// 1. App launched from link (cold start)
/// 2. App resumed from background via link
/// 3. App already open when link tapped
///
/// Works on iOS, Android, and macOS. Web uses different flow (URL-based).
class DeepLinkService {
  static DeepLinkService? _instance;
  static DeepLinkService get instance => _instance ??= DeepLinkService._();

  DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _initialized = false;

  /// Reference to the Riverpod container for notifying auth state changes
  ProviderContainer? _container;

  /// Callback for successful auth from deep link
  VoidCallback? onAuthSuccess;

  /// Callback for deep link processing errors
  void Function(String error)? onAuthError;

  /// Set the provider container for auth state updates.
  /// Call this from main.dart after ProviderScope is created.
  void setContainer(ProviderContainer container) {
    _container = container;
  }

  /// Initialize the deep link service.
  /// Call this once in main.dart after Supabase is initialized.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Skip on web - Supabase handles web auth via URL params
    if (kIsWeb) {
      debugPrint('[DeepLinkService] Skipping - web uses URL-based auth');
      return;
    }

    debugPrint('[DeepLinkService] Initializing...');

    // Handle initial link (cold start - app launched from link)
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('[DeepLinkService] Initial link: $initialLink');
        AuthDebugLogger.linkReceived(
          source: 'cold_start',
          scheme: initialLink.scheme,
          host: initialLink.host,
        );
        await _handleDeepLink(initialLink, source: 'cold_start');
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Error getting initial link: $e');
      AuthDebugLogger.error(step: 'getInitialLink', message: '$e');
    }

    // Listen for links while app is running (background resume + already open)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        debugPrint('[DeepLinkService] Received link while running: $uri');
        AuthDebugLogger.linkReceived(
          source: 'foreground_or_background',
          scheme: uri.scheme,
          host: uri.host,
        );
        await _handleDeepLink(uri, source: 'runtime');
      },
      onError: (error) {
        debugPrint('[DeepLinkService] Link stream error: $error');
        AuthDebugLogger.error(step: 'uriLinkStream', message: '$error');
      },
    );

    debugPrint('[DeepLinkService] Initialized and listening');
  }

  /// Handle an incoming deep link URI
  Future<void> _handleDeepLink(Uri uri, {String source = 'unknown'}) async {
    debugPrint('[DeepLinkService] Processing: $uri');

    // Check if this is an auth callback
    if (!_isAuthCallback(uri)) {
      debugPrint('[DeepLinkService] Not an auth callback, ignoring');
      return;
    }

    try {
      // Extract auth parameters
      // PKCE flow uses ?code= parameter
      // Implicit flow uses #access_token (fragment)
      final code = uri.queryParameters['code'];
      final accessToken = uri.fragment.isNotEmpty
          ? Uri.splitQueryString(uri.fragment)['access_token']
          : null;
      final refreshToken = uri.fragment.isNotEmpty
          ? Uri.splitQueryString(uri.fragment)['refresh_token']
          : null;

      AuthDebugLogger.paramsExtracted(
        hasCode: code != null,
        hasAccessToken: accessToken != null,
      );

      if (code != null) {
        // PKCE flow - exchange code for session
        debugPrint('[DeepLinkService] PKCE flow - exchanging code: ${code.substring(0, 10)}...');
        try {
          final response = await Supabase.instance.client.auth
              .exchangeCodeForSession(code);
          debugPrint(
            '[DeepLinkService] PKCE exchange successful, user: ${response.session.user.email}',
          );

          AuthDebugLogger.sessionExchange(success: true);

          // Verify session is now set (triggers onAuthStateChange automatically)
          final session = Supabase.instance.client.auth.currentSession;
          if (session != null) {
            debugPrint(
              '[DeepLinkService] Session confirmed for user: ${session.user.email}',
            );
          } else {
            debugPrint('[DeepLinkService] WARNING: Session is null after successful exchange!');
          }

          // Force refresh auth provider state to ensure UI updates
          // This is a safety net in case onAuthStateChange event is missed
          _notifyAuthStateChanged();

          onAuthSuccess?.call();
        } on AuthException catch (e) {
          debugPrint('[DeepLinkService] PKCE exchange AuthException: ${e.message}');
          debugPrint('[DeepLinkService] This usually means the code verifier was lost (e.g., app restart or logout before link clicked)');
          AuthDebugLogger.sessionExchange(success: false, errorType: 'pkce_verifier_missing');
          onAuthError?.call('Login link expired or was opened incorrectly. Please request a new magic link.');
        }
      } else if (accessToken != null && refreshToken != null) {
        // Implicit flow - set session directly
        debugPrint('[DeepLinkService] Implicit flow - setting session...');
        final response = await Supabase.instance.client.auth.setSession(
          refreshToken,
        );
        debugPrint(
          '[DeepLinkService] Session set successfully, user: ${response.session?.user.email}',
        );

        AuthDebugLogger.sessionExchange(success: true);

        // Force refresh auth provider state
        _notifyAuthStateChanged();

        onAuthSuccess?.call();
      } else {
        // Check for error in callback
        final error = uri.queryParameters['error'];
        final errorDescription = uri.queryParameters['error_description'];
        if (error != null) {
          final message = errorDescription ?? error;
          debugPrint('[DeepLinkService] Auth error from callback: $message');
          AuthDebugLogger.sessionExchange(success: false, errorType: error);
          onAuthError?.call(message);
        } else {
          debugPrint('[DeepLinkService] No auth params found in URI');
          AuthDebugLogger.error(
            step: 'paramsExtraction',
            message: 'No code or token found',
          );
        }
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Error processing auth: $e');
      AuthDebugLogger.sessionExchange(
        success: false,
        errorType: e.runtimeType.toString(),
      );
      onAuthError?.call('Failed to complete sign in. Please try again.');
    }
  }

  /// Notify the auth state provider that session has changed.
  /// This is a safety net for cases where onAuthStateChange might be missed,
  /// especially on iPad where multitasking can cause timing issues.
  void _notifyAuthStateChanged() {
    if (_container != null) {
      debugPrint('[DeepLinkService] Notifying auth provider of session change');
      // Use a small delay to ensure Supabase has fully processed the session
      // This helps with iPad timing issues during multitasking
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_container != null) {
          _container!.read(authStateProvider.notifier).refreshSession();
        }
      });
    } else {
      debugPrint(
        '[DeepLinkService] No container set, cannot notify auth provider',
      );
    }
  }

  /// Check if URI is an auth callback
  bool _isAuthCallback(Uri uri) {
    // Match bandroadie://login-callback/ or bandroadie://login-callback
    if (uri.scheme == 'bandroadie' && uri.host == 'login-callback') {
      return true;
    }

    // Also check for code/token params on any bandroadie:// URI
    if (uri.scheme == 'bandroadie') {
      final hasCode = uri.queryParameters.containsKey('code');
      final hasToken = uri.fragment.contains('access_token');
      return hasCode || hasToken;
    }

    return false;
  }

  /// Clean up resources
  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _container = null;
    _initialized = false;
    debugPrint('[DeepLinkService] Disposed');
  }
}
