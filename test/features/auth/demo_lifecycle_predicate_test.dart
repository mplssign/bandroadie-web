// Unit tests for DemoSessionService.shouldReleaseDemoOnLifecycle — the pure,
// side-effect-free seam that decides whether a lifecycle transition should
// release an anonymous demo slot. A new file (no existing demo-service test
// group to extend; login_screen_demo_button_test.dart is a login-screen widget
// test with a different concern).

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:bandroadie/features/auth/demo_session_service.dart';

void main() {
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
}
