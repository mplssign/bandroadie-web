// Tests for the "Check Out the Demo Band" button introduced in the
// interactive-demo-band-experience feature, and retirement of the 7-tap easter egg.
//
// Assertion scope: LoginScreen._checkExistingSession() calls
// Supabase.instance.client.auth.currentSession, so Supabase must be
// initialized before pumping the widget. We use dummy credentials — no
// network calls occur because SharedPreferences has no stored token and
// currentSession only reads in-memory GoTrue state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/auth/login_screen.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // ignore: invalid_use_of_visible_for_testing_member
    try {
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        publishableKey: 'test-anon-key',
      );
    } catch (_) {
      // Already initialized by a previous test run in this process.
    }
  });

  testWidgets(
    'Test A: "Check Out the Demo Band" button is visible on LoginScreen',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: FTheme(
              data: AppTheme.foruiTheme(Brightness.dark),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
      // One frame is enough — FadeTransition with opacity 0 still exists in the
      // widget tree and is found by text search.
      await tester.pump();

      expect(find.text('Check Out the Demo Band'), findsOneWidget);
    },
  );

  testWidgets(
    'Test B: retired 7-tap easter-egg hint text is not present',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: FTheme(
              data: AppTheme.foruiTheme(Brightness.dark),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      // The old easter egg showed incremental hints like "Keep tapping…" or
      // a tap-count badge. Verify no such copy survives in the rendered tree.
      expect(find.textContaining('tapping'), findsNothing);
      expect(find.textContaining('demo mode'), findsNothing);
    },
  );
}
