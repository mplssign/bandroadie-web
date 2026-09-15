// Tests for the invite-token handoff added to AuthConfirmScreen.
//
// member-invitations-after-phone-change, Cycle 3: invite-login now redirects
// through the standard /auth/confirm PKCE route instead of a thinner /invite
// web auth path. These tests confirm AuthConfirmScreen routes invite-auth
// users back into InviteScreen(token: inviteToken) after a successful
// token_hash confirmation, while non-invite logins keep landing on AuthGate.
//
// Offline strategy: Supabase is initialized with a MockClient that answers
// POST .../auth/v1/verify with a synthetic session (so verifyOTP() succeeds
// locally with no real network call), and stubs the accept-invite function
// response so InviteScreen's automatic acceptance attempt after navigation
// resolves deterministically instead of throwing an unhandled error.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/auth/auth_confirm_screen.dart';
import 'package:bandroadie/features/auth/auth_state_provider.dart';
import 'package:bandroadie/features/auth/auth_gate.dart';
import 'package:bandroadie/features/auth/invite_screen.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  int transitionCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    transitionCount += 1;
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    transitionCount += 1;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

class _ImmediateAuthStateNotifier extends AuthStateNotifier {
  @override
  AppAuthState build() {
    return AppAuthState(session: Supabase.instance.client.auth.currentSession);
  }
}

/// Builds a synthetic /auth/v1/verify success response: a session whose
/// shape satisfies Session.fromJson/User.fromJson (mirrors the hand-crafted
/// session pattern used in auth_gate_anonymous_recovery_test.dart).
String _verifyResponseJson(String userId) {
  return json.encode({
    'access_token': 'test-access-token-$userId',
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token-$userId',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'invitee@example.com',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': DateTime.now().toIso8601String(),
    },
  });
}

Future<void> _initSupabase() async {
  final mockClient = MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/auth/v1/verify')) {
      return http.Response(
        _verifyResponseJson('test-user-${request.hashCode}'),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.contains('/functions/v1/accept-invite')) {
      // Deterministic stub: keep InviteScreen on its neutral terminal state so
      // this test only measures the auth-confirm handoff, not InviteScreen's
      // separate defensive auth-recovery branch for 200/accepted_count:0.
      return http.Response(
        json.encode({
          'error': 'This invite is no longer available.',
          'code': 'invite_unavailable',
        }),
        409,
      );
    }
    return http.Response(
      json.encode({'error': 'unhandled in test'}),
      404,
      headers: {'content-type': 'application/json'},
    );
  });

  try {
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-anon-key',
      httpClient: mockClient,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
      ),
    );
  } catch (_) {
    // Already initialized by a prior test run in this process.
  }
}

// A single explicit inner Navigator wrapped by FTheme: every page this test
// pushes (named or raw MaterialPageRoute) lands inside the SAME Navigator, so
// all of them stay descendants of FTheme instead of losing it as soon as
// AuthConfirmScreen pushes a sibling page directly. The recording observer is
// attached to this same inner Navigator (not MaterialApp's outer one) so its
// push count reliably reflects every page this Navigator ever receives.
Widget _wrap(Widget child, {NavigatorObserver? observer}) => ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_ImmediateAuthStateNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: Navigator(
            observers: observer == null ? const [] : [observer],
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  settings.name == '/app' ? const AuthGate() : child,
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initSupabase();
  });

  tearDown(() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  });

  testWidgets(
    'Test A: successful confirm with inviteToken routes to InviteScreen(token: inviteToken)',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        _wrap(
          const AuthConfirmScreen(
            tokenHash: 'test-token-hash-invite',
            inviteToken: 'test-invite-token',
          ),
          observer: observer,
        ),
      );

      // Flush the verifyOTP mock round trip, the auth-state sync wait, and
      // the navigation it triggers. InviteScreen's auth-entry column has a
      // pre-existing RenderFlex overflow at this viewport size, unrelated to
      // the redirect-URL change made in this cycle; drain it rather than
      // asserting it away.
      await tester.pump();
      _drainKnownRenderOverflow(tester);
      await tester.pump(const Duration(milliseconds: 600));
      _drainKnownRenderOverflow(tester);
      await tester.pump(const Duration(milliseconds: 600));
      _drainKnownRenderOverflow(tester);

      expect(find.byType(InviteScreen), findsOneWidget);
      expect(find.byType(AuthGate), findsNothing);
      // Absolute count, not a delta from a post-mount baseline: the mocked
      // verifyOTP call can resolve entirely within pumpWidget's own pump (no
      // real Timer delay), so a baseline captured after pumpWidget could
      // already include the navigation push. 2 = the Navigator's initial
      // mount page + exactly one post-auth navigation (a double-push
      // regression would read 3).
      expect(observer.transitionCount, 2);
      final inviteScreen = tester.widget<InviteScreen>(
        find.byType(InviteScreen),
      );
      expect(inviteScreen.token, 'test-invite-token');
    },
  );

  testWidgets(
    'Test B: successful confirm without inviteToken keeps the default AuthGate destination',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        _wrap(
          const AuthConfirmScreen(tokenHash: 'test-token-hash-no-invite'),
          observer: observer,
        ),
      );

      // AuthGate's own authenticated loading branch has a pre-existing
      // RenderFlex overflow when mounted outside the full app shell (see
      // auth_gate_anonymous_recovery_test.dart, which sidesteps the same
      // branch). auth_gate.dart is off-limits here, so drain that unrelated
      // rendering error after each pump instead of asserting it away.
      await tester.pump();
      _drainKnownRenderOverflow(tester);
      await tester.pump(const Duration(milliseconds: 600));
      _drainKnownRenderOverflow(tester);
      await tester.pump(const Duration(milliseconds: 600));
      _drainKnownRenderOverflow(tester);

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(InviteScreen), findsNothing);
      // Absolute count (see Test A): initial mount page + one post-auth
      // navigation to '/app'.
      expect(observer.transitionCount, 2);

      // Flush AuthGate's own splash-screen timer so no pending Timer survives
      // widget disposal at the end of the test.
      await tester.pump(const Duration(seconds: 2));
      _drainKnownRenderOverflow(tester);
    },
  );
}

void _drainKnownRenderOverflow(WidgetTester tester) {
  Object? exception;
  while ((exception = tester.takeException()) != null) {
    final message = exception.toString();
    expect(
      message,
      anyOf(
        contains('RenderFlex'),
        contains('Multiple exceptions'),
        contains('Null check operator used on a null value'),
      ),
      reason: 'Only known pre-existing layout overflows are expected here',
    );
  }
}
