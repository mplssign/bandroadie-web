import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/models/rehearsal.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/home/widgets/confirmed_gig_card.dart';
import 'package:bandroadie/features/home/widgets/potential_gig_card.dart';
import 'package:bandroadie/features/home/widgets/rehearsal_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Rehearsal _buildRehearsal({
  required bool isPotential,
  String? setlistId,
}) {
  return Rehearsal(
    id: 'rehearsal-1',
    bandId: 'band-1',
    date: DateTime(2026, 9, 13),
    startTime: '18:00',
    endTime: '21:00',
    location: 'Test Studio',
    setlistId: setlistId,
    createdAt: DateTime(2026, 9),
    updatedAt: DateTime(2026, 9),
    isPotential: isPotential,
  );
}

Gig _buildGig({
  required bool isPotential,
  String? setlistId,
  String? setlistName,
}) {
  return Gig(
    id: 'gig-1',
    bandId: 'band-1',
    name: 'Test Gig',
    date: DateTime(2026, 9, 13),
    startTime: '19:00',
    endTime: '22:00',
    location: 'Test Venue',
    setlistId: setlistId,
    setlistName: setlistName,
    isPotential: isPotential,
    createdAt: DateTime(2026, 9),
    updatedAt: DateTime(2026, 9),
  );
}

void main() {
  group('RehearsalCard confirmed No Setlist Selected badge', () {
    testWidgets(
      'renders "No Setlist Selected" when rehearsal.setlistId is null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: false,
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );

        expect(find.text('No Setlist Selected'), findsOneWidget);
      },
    );

    testWidgets(
      'renders existing selected pill and no "No Setlist Selected" '
      'when both id and name are non-null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: false,
                  setlistId: 'setlist-1',
                ),
                bandTimezone: 'America/Chicago',
                setlistName: 'Road Set',
              ),
            ),
          ),
        );

        expect(find.text('Road Set'), findsOneWidget);
        expect(find.text('No Setlist Selected'), findsNothing);
      },
    );

    testWidgets(
      'renders neither pill when setlistId is non-null but setlistName '
      'is null (loading race)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: false,
                  setlistId: 'setlist-1',
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );

        expect(find.text('No Setlist Selected'), findsNothing);
        expect(find.text('Road Set'), findsNothing);
      },
    );
  });

  group('RehearsalCard potential No Setlist Selected badge', () {
    testWidgets(
      'renders "No Setlist Selected" when rehearsal.setlistId is null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: true,
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render "No Setlist Selected" when '
      'rehearsal.setlistId is non-null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: true,
                  setlistId: 'setlist-1',
                ),
                bandTimezone: 'America/Chicago',
                setlistName: 'Road Set',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsNothing);
      },
    );

    testWidgets(
      'does not render "No Setlist Selected" when setlistId is non-null '
      'but setlistName is null (loading race)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: RehearsalCard(
                rehearsal: _buildRehearsal(
                  isPotential: true,
                  setlistId: 'setlist-1',
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsNothing);
      },
    );
  });

  group('ConfirmedGigCard No Setlist Selected badge', () {
    testWidgets(
      'renders "No Setlist Selected" when gig.setlistId is null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ConfirmedGigCard(
                gig: _buildGig(
                  isPotential: false,
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );

        expect(find.text('No Setlist Selected'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render "No Setlist Selected" when gig.setlistId is non-null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ConfirmedGigCard(
                gig: _buildGig(
                  isPotential: false,
                  setlistId: 'setlist-1',
                  setlistName: 'Road Set',
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );

        expect(find.text('No Setlist Selected'), findsNothing);
      },
    );
  });

  group('PotentialGigCard No Setlist Selected badge', () {
    testWidgets(
      'renders "No Setlist Selected" when gig.setlistId is null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PotentialGigCard(
                gig: _buildGig(
                  isPotential: true,
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render "No Setlist Selected" when gig.setlistId is non-null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PotentialGigCard(
                gig: _buildGig(
                  isPotential: true,
                  setlistId: 'setlist-1',
                  setlistName: 'Road Set',
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsNothing);
      },
    );

    testWidgets(
      'renders "No Setlist Selected" when gig.setlistId is null but '
      'setlistName is stale (delete_setlist cascade)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PotentialGigCard(
                gig: _buildGig(
                  isPotential: true,
                  setlistName: 'Old Set',
                ),
                bandTimezone: 'America/Chicago',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('No Setlist Selected'), findsOneWidget);
      },
    );
  });
}
