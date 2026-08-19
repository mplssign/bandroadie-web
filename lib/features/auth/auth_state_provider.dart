import 'dart:async';

import 'package:flutter/widgets.dart';
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
    final session = supabase.Supabase.instance.client.auth.currentSession;

    _authSubscription?.cancel();
    _authSubscription =
        supabase.Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      AuthDebugLogger.authStateUpdated(
        isAuthenticated: data.session != null,
        trigger: 'onAuthStateChange:${data.event.name}',
      );

      // Defer state mutation to post-frame callback to avoid
      // "Tried to build dirty widget in the wrong build scope" crash
      // when auth changes happen during widget tree teardown.
      // Applies to ALL auth events (signedIn, signedOut, tokenRefreshed, etc.)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (data.event) {
          case supabase.AuthChangeEvent.signedIn:
            state = AppAuthState(session: data.session);
            break;
          case supabase.AuthChangeEvent.tokenRefreshed:
            state = AppAuthState(session: data.session);
            break;
          case supabase.AuthChangeEvent.userUpdated:
            state = AppAuthState(session: data.session);
            break;

          case supabase.AuthChangeEvent.signedOut:
            state = const AppAuthState(session: null);
            break;

          case supabase.AuthChangeEvent.initialSession:
            state = AppAuthState(session: data.session);
            break;

          default:
            if (data.session != null) {
              state = AppAuthState(session: data.session);
            }
        }
      });
    });

    ref.onDispose(() {
      debugPrint('[AuthStateNotifier] Disposing auth subscription');
      _authSubscription?.cancel();
    });

    return AppAuthState(session: session);
  }

  /// Force refresh the current session state.
  void refreshSession() {
    final currentSession =
        supabase.Supabase.instance.client.auth.currentSession;
    final currentToken = currentSession?.accessToken;
    final stateToken = state.session?.accessToken;

    final sessionPresenceChanged =
        (currentSession == null) != (state.session == null);
    final tokenChanged = currentToken != stateToken;

    if (sessionPresenceChanged || tokenChanged) {
      AuthDebugLogger.authStateUpdated(
        isAuthenticated: currentSession != null,
        trigger: 'refreshSession',
      );
      state = AppAuthState(session: currentSession);
    } else {
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
  void forceRefresh() {
    final currentSession =
        supabase.Supabase.instance.client.auth.currentSession;
    AuthDebugLogger.authStateUpdated(
      isAuthenticated: currentSession != null,
      trigger: 'forceRefresh',
    );
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
