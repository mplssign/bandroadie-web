import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../app/services/auth_debug_logger.dart';

/// App-level auth state that the entire app can react to.
/// This ensures routing is always in sync with authentication.
@immutable
class AppAuthState {
  final supabase.Session? session;
  final bool isLoading;
  final String? error;

  const AppAuthState({this.session, this.isLoading = false, this.error});

  bool get isAuthenticated => session != null;

  AppAuthState copyWith({
    supabase.Session? session,
    bool? isLoading,
    String? error,
    bool clearSession = false,
  }) {
    return AppAuthState(
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppAuthState &&
        other.session?.accessToken == session?.accessToken &&
        other.isLoading == isLoading &&
        other.error == error;
  }

  @override
  int get hashCode =>
      session?.accessToken.hashCode ?? 0 ^ isLoading.hashCode ^ error.hashCode;
}

/// Notifier that manages auth state and listens to Supabase auth changes.
/// This is the single source of truth for authentication state.
class AuthStateNotifier extends Notifier<AppAuthState> {
  StreamSubscription<supabase.AuthState>? _authSubscription;

  @override
  AppAuthState build() {
    // Get initial session
    final session = supabase.Supabase.instance.client.auth.currentSession;
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('🔐 AUTH STATE PROVIDER: Initializing');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('   Session: ${session != null ? "✅ Present" : "❌ None"}');
    if (session != null) {
      debugPrint('   User: ${session.user.email}');
      debugPrint(
        '   Expires: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000)}',
      );
    }
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    // Listen for auth state changes
    _authSubscription?.cancel();
    _authSubscription = supabase.Supabase.instance.client.auth.onAuthStateChange
        .listen((data) {
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
          debugPrint('🔔 AUTH EVENT: ${data.event.name}');
          debugPrint(
            '   Session: ${data.session != null ? "✅ Present" : "❌ None"}',
          );
          if (data.session != null) {
            debugPrint('   User: ${data.session!.user.email}');
          }
          debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

          AuthDebugLogger.authStateUpdated(
            isAuthenticated: data.session != null,
            trigger: 'onAuthStateChange:${data.event.name}',
          );

          switch (data.event) {
            case supabase.AuthChangeEvent.signedIn:
              debugPrint('   ↳ Updating state: SIGNED_IN');
              state = AppAuthState(session: data.session);
              break;
            case supabase.AuthChangeEvent.tokenRefreshed:
              debugPrint('   ↳ Updating state: TOKEN_REFRESHED');
              state = AppAuthState(session: data.session);
              break;
            case supabase.AuthChangeEvent.userUpdated:
              debugPrint('   ↳ Updating state: USER_UPDATED');
              state = AppAuthState(session: data.session);
              break;

            case supabase.AuthChangeEvent.signedOut:
              debugPrint('   ↳ Updating state: SIGNED_OUT');
              state = const AppAuthState(session: null);
              break;

            case supabase.AuthChangeEvent.initialSession:
              debugPrint('   ↳ Updating state: INITIAL_SESSION');
              state = AppAuthState(session: data.session);
              break;

            default:
              debugPrint('   ↳ Other event: ${data.event.name}');
              // passwordRecovery, mfaChallengeVerified, etc.
              if (data.session != null) {
                state = AppAuthState(session: data.session);
              }
          }
        });

    // Clean up subscription when provider is disposed
    ref.onDispose(() {
      debugPrint('[AuthStateNotifier] Disposing auth subscription');
      _authSubscription?.cancel();
    });

    return AppAuthState(session: session);
  }

  /// Force refresh the current session state.
  /// Useful when app resumes from background or after deep link auth.
  /// Always updates state to ensure UI rebuilds - critical for iPad multitasking.
  void refreshSession() {
    final currentSession =
        supabase.Supabase.instance.client.auth.currentSession;
    final currentToken = currentSession?.accessToken;
    final stateToken = state.session?.accessToken;

    debugPrint(
      '[AuthStateNotifier] Refresh session: current=${currentToken != null}, state=${stateToken != null}',
    );

    // Compare by access token to detect actual session changes
    // Also force update if session presence changed (null -> non-null or vice versa)
    final sessionPresenceChanged =
        (currentSession == null) != (state.session == null);
    final tokenChanged = currentToken != stateToken;

    if (sessionPresenceChanged || tokenChanged) {
      debugPrint('[AuthStateNotifier] Session changed, updating state');
      AuthDebugLogger.authStateUpdated(
        isAuthenticated: currentSession != null,
        trigger: 'refreshSession',
      );
      state = AppAuthState(session: currentSession);
    } else {
      debugPrint('[AuthStateNotifier] Session unchanged, no update needed');
      AuthDebugLogger.providerRefresh(
        provider: 'authStateProvider',
        hasSession: currentSession != null,
      );
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      state = state.copyWith(isLoading: true);
      await supabase.Supabase.instance.client.auth.signOut();
      state = const AppAuthState(session: null);
    } catch (e) {
      debugPrint('[AuthStateNotifier] Sign out error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Force an immediate state update regardless of current state.
  /// Use this as a safeguard when session state might be out of sync.
  /// This ALWAYS triggers a rebuild, even if session hasn't changed.
  void forceRefresh() {
    final currentSession =
        supabase.Supabase.instance.client.auth.currentSession;
    debugPrint(
      '[AuthStateNotifier] Force refresh: ${currentSession != null ? "authenticated" : "no session"}',
    );
    AuthDebugLogger.authStateUpdated(
      isAuthenticated: currentSession != null,
      trigger: 'forceRefresh',
    );
    // Always create new state object to guarantee rebuild
    state = AppAuthState(session: currentSession);
  }
}

/// Global auth state provider.
/// Use this to check authentication status anywhere in the app.
final authStateProvider = NotifierProvider<AuthStateNotifier, AppAuthState>(
  AuthStateNotifier.new,
);

/// Convenience provider to check if user is authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStateProvider).isAuthenticated;
});

/// Convenience provider to get the current session.
final currentSessionProvider = Provider<supabase.Session?>((ref) {
  return ref.watch(authStateProvider).session;
});
