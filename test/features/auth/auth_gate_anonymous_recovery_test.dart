// Tests for AuthGate anonymous cold-start recovery.
// Verifies _reconcileOrphanedAnonymousSession() — the guard and recovery added
// to fix the black-screen hang when a stale anonymous session is cold-started.
//
// Tier-1 (this file, fully offline):
//   A: isAuthenticated=false, bands in notifier → guard blocks loadUserBands call.
//   B: isAuthenticated=false, multi-pump → counter stays 0 (no deferred reconcile).
//   C: isAuthenticated=false → LoginScreen rendered, counter = 0.
//   D: anonymous session primed, ZERO bands → reconcile calls loadUserBands once
//      and signs out globally, clearing the local session.
//   E: anonymous session primed, ONE band → reconcile calls loadUserBands once
//      but preserves the session (no sign-out; still anonymous).
//
// How D and E run fully offline:
//   The build-phase Riverpod exception ("Tried to modify a provider while the
//   widget tree was building") that previously blocked these scenarios is
//   RESOLVED — auth_gate.dart now schedules the reconcile via
//   WidgetsBinding.addPostFrameCallback, so loadUserBands()'s synchronous state
//   mutation lands after the build phase instead of during it.  The only
//   remaining obstacle was priming a genuine anonymous session offline:
//     * The SDK's setSession(refreshToken, accessToken:) is NOT usable offline —
//       it calls getUser(accessToken), an HTTP round trip, to populate
//       currentUser (gotrue 2.27.2 gotrue_client.dart:962).
//     * GoTrueClient.recoverSession(jsonStr) IS the offline-clean equivalent: it
//       parses a hand-crafted session JSON locally (User.isAnonymous is read
//       from the embedded user object, and JWT decoding is signature-free), sets
//       the in-memory session, and makes no network call.
//   Combined with the fake activeBandProvider notifier (so loadUserBands() never
//   hits the network) and a MockClient for signOut(global)'s admin logout call,
//   D and E are deterministic offline.
//
// Remaining Tier-2 (on-device only): server-side confirmation that
// SignOutScope.global actually revoked the refresh token — only observable
// against a real Supabase backend or a second device — and the end-to-end macOS
// restore-loop check.  Test D asserts the LOCAL session clear that signOut
// performs before its network call; the server-side revocation is not
// offline-observable.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/auth/auth_gate.dart';
import 'package:bandroadie/features/auth/login_screen.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _LoadCounter {
  int count = 0;
}

/// Fake band notifier — returns caller-controlled bands and records
/// how many times loadUserBands() is called without making network calls.
///
/// [initialBands] is what build() reports (the state before any reconcile);
/// [loadedBands] is what loadUserBands() resolves to (defaults to
/// [initialBands]).  Test E uses distinct values so the first frame renders the
/// lightweight anonymous spinner rather than the heavy AppShell.
///
/// [loadedIsLoading] keeps the post-load state on AuthGate's `isLoading`
/// spinner branch so a rebuild never reaches the AppShell branch (which spins
/// up HomeTabContent timers/network) — while still exposing a non-empty
/// `userBands` to the reconcile's hasBands check.
class _FakeActiveBandNotifier extends ActiveBandNotifier {
  final List<Band> _initialBands;
  final List<Band> _loadedBands;
  final bool _loadedIsLoading;
  final _LoadCounter _counter;

  _FakeActiveBandNotifier(
    this._initialBands,
    this._counter, {
    List<Band>? loadedBands,
    bool loadedIsLoading = false,
  })  : _loadedBands = loadedBands ?? _initialBands,
        _loadedIsLoading = loadedIsLoading;

  @override
  ActiveBandState build() {
    final activeBand = _initialBands.isNotEmpty ? _initialBands.first : null;
    return ActiveBandState(userBands: _initialBands, activeBand: activeBand);
  }

  @override
  Future<void> loadUserBands() async {
    _counter.count++;
    final activeBand = _loadedBands.isNotEmpty ? _loadedBands.first : null;
    state = ActiveBandState(
      userBands: _loadedBands,
      activeBand: activeBand,
      isLoading: _loadedIsLoading,
    );
  }
}

Widget _testApp(ActiveBandNotifier Function() bandFactory) => ProviderScope(
      overrides: [activeBandProvider.overrideWith(bandFactory)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: const AuthGate(),
        ),
      ),
    );

/// Primes a genuine-looking anonymous session into the in-memory GoTrue client
/// with no network call (see file header). recoverSession() parses the session
/// JSON locally; is_anonymous comes from the embedded user object and the JWT
/// is decoded without signature verification, so a hand-crafted token works.
Future<void> _primeAnonymousSession({required String userId}) async {
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(json.encode(claims))).replaceAll('=', '');
  final accessToken = [
    segment({'alg': 'HS256', 'typ': 'JWT'}),
    segment({
      'sub': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'iat': nowSeconds,
      'exp': nowSeconds + 3600,
      'is_anonymous': true,
    }),
    base64Url.encode(utf8.encode('signature')).replaceAll('=', ''),
  ].join('.');
  final sessionJson = json.encode({
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'test-anon-refresh-token',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'is_anonymous': true,
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': DateTime.now().toIso8601String(),
    },
  });
  await Supabase.instance.client.auth.recoverSession(sessionJson);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        publishableKey: 'test-anon-key',
        // Only the reconcile's signOut(global) admin/logout call is expected to
        // reach the network offline; answer it so the local clear is not masked
        // by an unhandled connection error.
        httpClient: MockClient((_) async => http.Response('', 204)),
        // Keep everything in-memory and deterministic: no auto-refresh ticker
        // touching primed sessions, no cross-test storage leakage.
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          persistSession: false,
        ),
      );
    } catch (_) {
      // Already initialized by a prior test run in this process.
    }
  });

  // Wipe any auth state the Supabase singleton may have accumulated so tests
  // cannot inherit each other's session.
  tearDown(() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  });

  // Test A and B: guard is gated on isAuthenticated, not on band count.
  // These replace the original Tests A/B whose anonymous-session scenarios
  // require on-device execution (see Tier-2 note at top of file).

  testWidgets(
    'Test A: no session with bands available — reconcile guard blocks loadUserBands',
    (tester) async {
      // ForUI's FTheme/FScaffold leaves frame state that shrinks subsequent test
      // viewports to ~300 px; set an explicit size and reset it in teardown.
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);

      // Verify no session so this test targets the isAuthenticated guard,
      // not the isAnonymous check or the band-count check.
      expect(Supabase.instance.client.auth.currentSession, isNull);

      final now = DateTime.now();
      final testBand = Band(
        id: 'test-band-guard-001',
        name: 'Guard Test Band',
        createdAt: now,
        updatedAt: now,
      );
      final counter = _LoadCounter();

      await tester.pumpWidget(
        _testApp(() => _FakeActiveBandNotifier([testBand], counter)),
      );
      await tester.pump();

      expect(
        counter.count,
        0,
        reason:
            'reconcile must not fire when authState.isAuthenticated is false, '
            'even when the notifier has bands configured',
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Test B: no session — loadUserBands counter stays 0 across multiple pump cycles',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);

      // Guards against a deferred or post-frame reconcile invocation sneaking
      // through after the initial build completes.
      expect(Supabase.instance.client.auth.currentSession, isNull);

      final counter = _LoadCounter();

      await tester.pumpWidget(
        _testApp(() => _FakeActiveBandNotifier([], counter)),
      );
      // Three pumps mirror the cadence used by the original anonymous-session
      // tests, ensuring no microtask or post-frame callback triggers the reconcile.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        counter.count,
        0,
        reason:
            'no deferred loadUserBands call must execute for an unauthenticated cold start',
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Test C: unauthenticated cold start does not invoke recovery',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);

      expect(Supabase.instance.client.auth.currentSession, isNull);

      final counter = _LoadCounter();
      final notifier = _FakeActiveBandNotifier([], counter);

      await tester.pumpWidget(_testApp(() => notifier));
      await tester.pump();

      expect(
        counter.count,
        0,
        reason:
            'recovery guard must block when authState.isAuthenticated is false',
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    },
  );

  // Test D and E prime a genuine anonymous session offline (see file header) so
  // the reconcile decision logic runs end-to-end without a real backend.

  testWidgets(
    'Test D: anonymous session with zero bands — reconcile signs out and clears '
    'the local session',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);

      await _primeAnonymousSession(userId: 'anon-user-d');
      expect(
        Supabase.instance.client.auth.currentUser?.isAnonymous,
        isTrue,
        reason: 'priming must produce an anonymous currentUser with no network',
      );

      final counter = _LoadCounter();
      await tester.pumpWidget(
        _testApp(() => _FakeActiveBandNotifier(const [], counter)),
      );
      // A single pump fires the post-frame reconcile; loadUserBands() resolves
      // to an empty list and the reconcile proceeds to signOut(global), which
      // clears the local session synchronously before its mocked network call.
      // Deliberately not pumped further: the very next frame would build the
      // transient authenticated-but-no-user state that renders NoBandShell,
      // whose logo SVG is a known out-of-scope missing asset.
      await tester.pump();

      expect(
        counter.count,
        1,
        reason: 'reconcile must call loadUserBands exactly once',
      );
      expect(
        Supabase.instance.client.auth.currentSession,
        isNull,
        reason: 'signOut(global) clears the local session even when the admin '
            'network call is mocked/unreachable',
      );
    },
  );

  testWidgets(
    'Test E: anonymous session with one band — reconcile preserves the session',
    (tester) async {
      tester.view.physicalSize = const Size(2400, 3600);
      addTearDown(tester.view.resetPhysicalSize);

      await _primeAnonymousSession(userId: 'anon-user-e');
      expect(
        Supabase.instance.client.auth.currentUser?.isAnonymous,
        isTrue,
      );

      final now = DateTime.now();
      final band = Band(
        id: 'anon-band-e-001',
        name: 'Reconciled Demo Band',
        createdAt: now,
        updatedAt: now,
      );
      final counter = _LoadCounter();
      // build() reports no bands (first frame is the lightweight anonymous
      // spinner, not AppShell); loadUserBands() resolves to one band with
      // isLoading:true so the reconcile's hasBands check is true (→ no sign-out)
      // while any rebuild stays on AuthGate's loading-spinner branch instead of
      // building AppShell.
      await tester.pumpWidget(
        _testApp(
          () => _FakeActiveBandNotifier(
            const [],
            counter,
            loadedBands: [band],
            loadedIsLoading: true,
          ),
        ),
      );
      // One pump runs the reconcile without pumping the rebuild that would
      // render AppShell.
      await tester.pump();

      expect(
        counter.count,
        1,
        reason: 'reconcile must call loadUserBands exactly once',
      );
      expect(
        Supabase.instance.client.auth.currentSession,
        isNotNull,
        reason: 'a session backed by at least one band must not be signed out',
      );
      expect(
        Supabase.instance.client.auth.currentUser?.isAnonymous,
        isTrue,
        reason: 'the anonymous session is preserved intact',
      );
    },
  );
}
