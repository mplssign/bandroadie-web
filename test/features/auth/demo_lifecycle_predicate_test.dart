// Unit tests for DemoSessionService's pure, side-effect-free seams:
//   * shouldReleaseDemoOnLifecycle — decides whether a lifecycle transition
//     should release an anonymous demo slot.
//   * isPersistedSessionAnonymous — classifies a persisted session JSON blob.
//   * purgePersistedAnonymousSession — the cold-start storage purge that keeps a
//     restored anonymous demo session from resuming across a relaunch (exercises
//     the actual SharedPreferences the SDK restores from at startup).
// A new file (no existing demo-service test group to extend;
// login_screen_demo_button_test.dart is a login-screen widget test with a
// different concern).

import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/features/auth/demo_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shouldReleaseDemoOnLifecycle', () {
    test('returns true only for detached + anonymous', () {
      expect(
        DemoSessionService.shouldReleaseDemoOnLifecycle(
          AppLifecycleState.detached,
          isAnonymous: true,
        ),
        isTrue,
      );
    });

    test('returns false for detached when not anonymous (real user)', () {
      expect(
        DemoSessionService.shouldReleaseDemoOnLifecycle(
          AppLifecycleState.detached,
          isAnonymous: false,
        ),
        isFalse,
      );
    });

    test('returns false for every non-detached state, even when anonymous', () {
      for (final state in const [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        expect(
          DemoSessionService.shouldReleaseDemoOnLifecycle(
            state,
            isAnonymous: true,
          ),
          isFalse,
          reason: '$state must not release the demo slot',
        );
      }
    });
  });

  group('isPersistedSessionAnonymous', () {
    String sessionJson({required bool isAnonymous, String userId = 'u1'}) =>
        jsonEncode({
          'access_token': 'token',
          'token_type': 'bearer',
          'refresh_token': 'refresh',
          'user': {'id': userId, 'is_anonymous': isAnonymous},
        });

    test('true for an anonymous (demo) persisted session', () {
      expect(
        DemoSessionService.isPersistedSessionAnonymous(
          sessionJson(isAnonymous: true),
        ),
        isTrue,
      );
    });

    test('false for a real (non-anonymous) persisted session', () {
      expect(
        DemoSessionService.isPersistedSessionAnonymous(
          sessionJson(isAnonymous: false),
        ),
        isFalse,
      );
    });

    test('false for null (no persisted session)', () {
      expect(DemoSessionService.isPersistedSessionAnonymous(null), isFalse);
    });

    test('false for malformed JSON (fail-safe: never drops a real session)',
        () {
      expect(
        DemoSessionService.isPersistedSessionAnonymous('not json {'),
        isFalse,
      );
    });

    test('false when the user object is missing', () {
      expect(
        DemoSessionService.isPersistedSessionAnonymous('{"access_token":"t"}'),
        isFalse,
      );
    });

    test('false when is_anonymous is absent', () {
      expect(
        DemoSessionService.isPersistedSessionAnonymous('{"user":{"id":"u1"}}'),
        isFalse,
      );
    });
  });

  // Exercises the ACTUAL startup storage the SDK restores from: a persisted
  // anonymous session must be gone before Supabase.initialize() reads it (and
  // before its background recoverSession() can resurrect it), while a real
  // user's persisted session must survive. This is the coverage the pre-fix
  // truth-table predicate lacked — under the old post-init sign-out the anon
  // session was still on disk at init time and got restored.
  group('purgePersistedAnonymousSession (startup storage race)', () {
    const url = 'https://test.supabase.co';
    // Matches supabase_flutter's persist-key derivation for this url.
    const key = 'sb-test-auth-token';

    String sessionJson({required bool isAnonymous}) => jsonEncode({
          'access_token': 'token',
          'token_type': 'bearer',
          'refresh_token': 'refresh',
          'user': {'id': 'u1', 'is_anonymous': isAnonymous},
        });

    test(
      'removes a restored anonymous session so the SDK restores nothing at cold '
      'start',
      () async {
        SharedPreferences.setMockInitialValues({
          key: sessionJson(isAnonymous: true),
        });

        await DemoSessionService.purgePersistedAnonymousSession(url);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), isNull);
      },
    );

    test(
      'preserves a persisted real-user session (real-user persistence intact)',
      () async {
        final real = sessionJson(isAnonymous: false);
        SharedPreferences.setMockInitialValues({key: real});

        await DemoSessionService.purgePersistedAnonymousSession(url);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(key), real);
      },
    );

    test('no-op when there is no persisted session', () async {
      SharedPreferences.setMockInitialValues({});

      await DemoSessionService.purgePersistedAnonymousSession(url);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), isNull);
    });

    test('leaves a malformed blob untouched (fail-safe)', () async {
      SharedPreferences.setMockInitialValues({key: 'not-json'});

      await DemoSessionService.purgePersistedAnonymousSession(url);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(key), 'not-json');
    });
  });
}
