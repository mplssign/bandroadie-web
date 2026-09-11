import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/events/widgets/potential_event_availability_section.dart';
import 'package:bandroadie/features/members/member_vm.dart';

void main() {
  testWidgets('lists every member response beneath each potential date',
      (tester) async {
    String? savedDateKey;
    String? savedResponse;
    String? officialDateKey;
    final members = [
      _member(userId: 'member-1', name: 'Alex Rivera'),
      _member(userId: 'member-2', name: 'Sam Chen'),
      _member(userId: 'member-3', name: 'Jordan Lee'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PotentialEventAvailabilitySection(
                dates: [
                  PotentialEventDateAvailability(
                    responseKey: 'primary',
                    date: DateTime(2026, 9, 12),
                    timeRange: '7:00 PM - 10:00 PM',
                  ),
                  PotentialEventDateAvailability(
                    responseKey: 'additional',
                    date: DateTime(2026, 9, 13),
                    timeRange: '8:00 PM - 10:00 PM',
                  ),
                ],
                members: members,
                isLoadingMembers: false,
                currentUserId: 'member-1',
                loadResponses: () async => {
                  'primary': {
                    'member-1': 'yes',
                    'member-2': 'no',
                  },
                  'additional': {
                    'member-1': 'no',
                    'member-2': 'yes',
                  },
                },
                onRespond: (responseKey, response) async {
                  savedDateKey = responseKey;
                  savedResponse = response;
                },
                selectedOfficialDateKeys: const {'primary'},
                onMakeOfficial: (date) {
                  officialDateKey = date.responseKey;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saturday, September 12, 2026'), findsOneWidget);
    expect(find.text('Sunday, September 13, 2026'), findsOneWidget);
    expect(find.text('Alex Rivera'), findsNWidgets(2));
    expect(find.text('Sam Chen'), findsNWidgets(2));
    expect(find.text('Jordan Lee'), findsNWidgets(2));
    expect(find.text('Yes'), findsNWidgets(2));
    expect(find.text('No'), findsNWidgets(2));
    expect(find.text('??'), findsNWidgets(2));
    expect(find.text('No response'), findsNothing);
    final badgeSizes = tester
        .widgetList<SizedBox>(
          find.byKey(const ValueKey('availability-badge')),
        )
        .map((badge) => badge.width)
        .toSet();
    expect(badgeSizes, {44.0});
    expect(find.text('NO'), findsNWidgets(2));
    expect(find.text('YES'), findsNWidgets(2));
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Make Official'), findsOneWidget);

    final additionalContainer = find.byKey(
      const ValueKey('potential-date-additional'),
    );
    await tester.tap(
      find.descendant(
        of: additionalContainer,
        matching: find.text('Make Official'),
      ),
    );
    await tester.pumpAndSettle();

    expect(officialDateKey, 'additional');

    final primaryContainer = find.byKey(
      const ValueKey('potential-date-primary'),
    );
    await tester.tap(
      find.descendant(of: primaryContainer, matching: find.text('NO')),
    );
    await tester.pumpAndSettle();

    expect(savedDateKey, 'primary');
    expect(savedResponse, 'no');
    expect(
      find.descendant(of: primaryContainer, matching: find.text('No')),
      findsNWidgets(2),
    );
  });
}

MemberVM _member({required String userId, required String name}) {
  return MemberVM(
    userId: userId,
    memberId: 'band-$userId',
    name: name,
    email: '$userId@example.com',
    bandRole: 'member',
    status: 'active',
    joinedAt: DateTime(2025),
    hasUserRow: true,
    profileCompleted: true,
  );
}
