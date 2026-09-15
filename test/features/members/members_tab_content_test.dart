// Regression coverage for the member-invitations-after-phone-change fix:
// MembersTabContent's invite entry point must push InviteMembersScreen
// (never BandFormScreen) from both the empty-state CTA and the populated
// "Add" header button.

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
import 'package:bandroadie/components/ui/app_button.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';
import 'package:bandroadie/features/bands/band_form_screen.dart';
import 'package:bandroadie/features/contacts/widgets/invite_members_screen.dart';
import 'package:bandroadie/features/members/member_vm.dart';
import 'package:bandroadie/features/members/members_controller.dart';
import 'package:bandroadie/features/members/members_tab_content.dart';

final _band = Band(
  id: 'test-band-1',
  name: 'Test Band',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _SeededActiveBandNotifier extends ActiveBandNotifier {
  @override
  ActiveBandState build() =>
      ActiveBandState(userBands: [_band], activeBand: _band);
}

class _FixedMembersNotifier extends MembersNotifier {
  _FixedMembersNotifier(this._seed);

  final MembersState _seed;

  @override
  MembersState build() => _seed;

  @override
  Future<void> loadMembers(String? bandId, {bool forceRefresh = false}) async {
    // No-op — state is pre-seeded for this test, avoids a live Supabase call.
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? pushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

MemberVM _member(String id) => MemberVM(
      userId: 'user-$id',
      memberId: 'member-$id',
      name: 'Member $id',
      email: 'member$id@example.com',
      bandRole: 'member',
      status: 'active',
      joinedAt: DateTime(2024),
      hasUserRow: true,
      profileCompleted: true,
    );

Future<void> _pumpMembersTab(
  WidgetTester tester, {
  required MembersState membersState,
  NavigatorObserver? navigatorObserver,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeBandProvider.overrideWith(_SeededActiveBandNotifier.new),
        membersProvider.overrideWith(() => _FixedMembersNotifier(membersState)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [if (navigatorObserver != null) navigatorObserver],
        builder: (context, child) => FTheme(
          data: FTheme.neutral.dark.touch,
          child: child!,
        ),
        home: const MembersTabContent(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    try {
      await Supabase.initialize(
        url: 'https://test.supabase.co',
        publishableKey: 'test-anon-key',
        httpClient: MockClient((request) async {
          if (request.url.path.contains('/rest/v1/band_invitations')) {
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          return http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false,
          persistSession: false,
        ),
      );
    } catch (_) {
      // Already initialized by a previous test run in this process.
    }
  });

  testWidgets(
    'empty state invite CTA pushes InviteMembersScreen route, not BandFormScreen',
    (tester) async {
      final observer = _RecordingNavigatorObserver();
      await _pumpMembersTab(
        tester,
        membersState: const MembersState(),
        navigatorObserver: observer,
      );

      final inviteButton = tester.widget<AppButton>(find.byType(AppButton));
      inviteButton.onPressed!.call();
      expect(observer.pushedRoute, isNotNull);

      final navigatorContext = tester.element(find.byType(Navigator));
      final pushedRoute = observer.pushedRoute as PageRoute<dynamic>;
      final pushedPage = pushedRoute.buildPage(
        navigatorContext,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
      );

      expect(pushedPage, isA<InviteMembersScreen>());
      expect(pushedPage, isNot(isA<BandFormScreen>()));
    },
  );

  testWidgets(
    'populated members view shows Add control that pushes InviteMembersScreen route',
    (tester) async {
      final observer = _RecordingNavigatorObserver();
      await _pumpMembersTab(
        tester,
        membersState: MembersState(members: [_member('1'), _member('2')]),
        navigatorObserver: observer,
      );

      final addButton = find.text('Add');
      expect(addButton, findsOneWidget);

      final addTextButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Add'),
      );
      addTextButton.onPressed!.call();
      expect(observer.pushedRoute, isNotNull);

      final navigatorContext = tester.element(find.byType(Navigator));
      final pushedRoute = observer.pushedRoute as PageRoute<dynamic>;
      final pushedPage = pushedRoute.buildPage(
        navigatorContext,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
      );

      expect(pushedPage, isA<InviteMembersScreen>());
      expect(pushedPage, isNot(isA<BandFormScreen>()));
    },
  );
}
