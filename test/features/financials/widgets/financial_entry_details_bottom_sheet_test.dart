// Tests for `_FinancialEntryDetailsSheet` (private) in
// lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart.
// Pumped via the public `showFinancialEntryDetailsSheet` entry point with an
// overridden gigProvider — see ARCHITECT_PLAN.md Task 6 / Verification Plan →
// Tier 1 (financial_entry_details_bottom_sheet_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/financials/models/financial_entry.dart';
import 'package:bandroadie/features/financials/widgets/financial_entry_details_bottom_sheet.dart';
import 'package:bandroadie/features/gigs/gig_controller.dart';

class _FakeGigNotifier extends GigNotifier {
  _FakeGigNotifier(this._state);
  final GigState _state;
  @override
  GigState build() => _state;
}

FinancialEntry _entry({
  required String id,
  FinancialEntryType entryType = FinancialEntryType.expense,
  bool isIncome = false,
  String category = 'Equipment',
  int amountCents = 10000,
  String? payerName,
  String? paidToName,
  String? description,
  String? notes,
  bool isReimbursed = false,
  String? gigId,
}) {
  final date = DateTime(2026, 1, 15);
  return FinancialEntry(
    id: id,
    bandId: 'band-1',
    entryType: entryType,
    category: category,
    amountCents: amountCents,
    isIncome: isIncome,
    entryDate: date,
    description: description,
    notes: notes,
    isReimbursed: isReimbursed,
    payerName: payerName,
    paidToName: paidToName,
    gigId: gigId,
    createdBy: 'user-1',
    createdAt: date,
    updatedAt: date,
  );
}

Gig _gig({required String id, required String name}) {
  final date = DateTime(2026);
  return Gig(
    id: id,
    bandId: 'band-1',
    name: name,
    date: date,
    startTime: '19:00',
    endTime: '22:00',
    location: 'Test Venue',
    // ignore: avoid_redundant_argument_values
    isPotential: false,
    createdAt: date,
    updatedAt: date,
  );
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required FinancialEntry entry,
  required GigState gigState,
}) async {
  // Default test canvas (600 logical px tall) is shorter than any real
  // device and clips the sheet's now-longer row list; simulate a real phone.
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gigProvider.overrideWith(() => _FakeGigNotifier(gigState)),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showFinancialEntryDetailsSheet(context, ref, entry),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
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
      );
    } catch (_) {
      // Already initialized by a previous test run in this process.
    }
  });

  testWidgets(
    'sheet footer has no icons — Done primary and Edit cancel are both '
    'text-only',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        payerName: 'Jane Doe',
        description: 'Notes text',
      );
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      expect(find.byType(Icon), findsNothing);
    },
  );

  testWidgets(
    'renamed labels "Purchased by", "Paid to", "Needed for gig" are present; '
    'old labels "Paid by", "Paid To", "Related to gig" are absent',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        payerName: 'Jane Doe',
        description: 'A description',
        gigId: 'gig-1',
      );
      await _pumpSheet(
        tester,
        entry: entry,
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      expect(find.text('Purchased by'), findsOneWidget);
      expect(find.text('Paid to'), findsOneWidget);
      expect(find.text('Needed for gig'), findsOneWidget);
      expect(find.text('Paid by'), findsNothing);
      expect(find.text('Paid To'), findsNothing);
      expect(find.text('Related to gig'), findsNothing);
    },
  );

  testWidgets(
    'expense with isReimbursed false shows a "Reimbursed" row with value No',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        gigId: 'gig-1',
      );
      await _pumpSheet(
        tester,
        entry: entry,
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      expect(find.text('Reimbursed'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
    },
  );

  testWidgets(
    'expense with isReimbursed true shows a "Reimbursed" row with value Yes '
    'AND the _ReimbursedBadge still above the divider',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        isReimbursed: true,
        gigId: 'gig-1',
      );
      await _pumpSheet(
        tester,
        entry: entry,
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      final reimbursedTexts = find.text('Reimbursed');
      expect(reimbursedTexts, findsNWidgets(2));

      final dividerY = tester.getTopLeft(find.byType(Divider)).dy;
      final badgeY = tester.getTopLeft(reimbursedTexts.at(0)).dy;
      final rowLabelY = tester.getTopLeft(reimbursedTexts.at(1)).dy;
      expect(badgeY, lessThan(dividerY));
      expect(rowLabelY, greaterThan(dividerY));
    },
  );

  testWidgets(
    'entry with gigId null shows "Needed for gig" value No',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'The Venue',
      );
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      expect(find.text('No'), findsOneWidget);
    },
  );

  testWidgets(
    'entry with gigId matching a known gig shows "Yes • <name>"',
    (tester) async {
      final entry = _entry(id: 'e1', gigId: 'gig-1');
      await _pumpSheet(
        tester,
        entry: entry,
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      expect(find.text('Yes • Summer Bash'), findsOneWidget);
    },
  );

  testWidgets(
    'entry with gigId not present in allGigs shows "Yes" alone',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        gigId: 'gig-unknown',
      );
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      expect(find.text('Yes'), findsOneWidget);
    },
  );

  testWidgets(
    'footer buttons read "Done" (primary) and "Edit" (cancel), not "Edit '
    'Entry"',
    (tester) async {
      final entry = _entry(id: 'e1');
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Edit Entry'), findsNothing);
    },
  );

  testWidgets(
    'primary Done button dismisses the sheet via Navigator.pop',
    (tester) async {
      final entry = _entry(id: 'e1');
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets(
    'secondary Edit button opens the add sheet with the entry pre-filled',
    (tester) async {
      final entry = _entry(id: 'e1');
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Entry'), findsOneWidget);
    },
  );

  testWidgets(
    'Description and Notes render as separate rows for an entry with both '
    'fields populated',
    (tester) async {
      final entry = _entry(id: 'e1', description: 'desc', notes: 'notes');
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('desc'), findsOneWidget);
      expect(find.text('notes'), findsOneWidget);
    },
  );

  testWidgets(
    'Notes row falls back to em-dash when entry.notes is null',
    (tester) async {
      final entry = _entry(id: 'e1', description: 'desc');
      await _pumpSheet(tester, entry: entry, gigState: const GigState());

      final notesRow = find.ancestor(
        of: find.text('Notes'),
        matching: find.byType(Row),
      );
      expect(notesRow, findsOneWidget);
      expect(
        find.descendant(of: notesRow, matching: find.text('—')),
        findsOneWidget,
      );
    },
  );
}
