// Tests for `_AddFinancialEntryBottomSheet` (private) in
// lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart.
// Pumped via the public `showAddFinancialEntrySheet` entry point with an
// overridden gigProvider — see ARCHITECT_PLAN.md Cycle 8 Task 10 /
// Verification Plan → Tier 1 (add_financial_entry_bottom_sheet_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/gig.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/app_dropdown.dart';
import 'package:bandroadie/components/ui/app_text_field.dart';
import 'package:bandroadie/features/financials/models/financial_entry.dart';
import 'package:bandroadie/features/financials/widgets/add_financial_entry_bottom_sheet.dart';
import 'package:bandroadie/features/gigs/gig_controller.dart';
import 'package:bandroadie/shared/widgets/currency_input_field.dart';

/// Structurally matches the private `_SaveCallback` typedef so a function
/// literal passed as `onSave` type-checks against it (Dart function types
/// are structural, not nominal).
typedef _TestSaveCallback = Future<void> Function({
  required FinancialEntryType entryType,
  required String category,
  required int amountCents,
  required DateTime entryDate,
  String? description,
  String? notes,
  String? gigId,
  bool? is1099Expected,
  String? payerName,
  String? paidToName,
  String? paidToUserId,
  Map<String, int>? disbursements,
  bool? depositToSavings,
  int? depositToSavingsCents,
});

Future<void> _noopSave({
  required FinancialEntryType entryType,
  required String category,
  required int amountCents,
  required DateTime entryDate,
  String? description,
  String? notes,
  String? gigId,
  bool? is1099Expected,
  String? payerName,
  String? paidToName,
  String? paidToUserId,
  Map<String, int>? disbursements,
  bool? depositToSavings,
  int? depositToSavingsCents,
}) async {}

class _FakeGigNotifier extends GigNotifier {
  _FakeGigNotifier(this._state);
  final GigState _state;
  @override
  GigState build() => _state;
}

FinancialEntry _entry({
  String id = 'e1',
  FinancialEntryType entryType = FinancialEntryType.expense,
  bool isIncome = false,
  String category = 'Equipment',
  int amountCents = 10000,
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

Future<void> _pump(
  WidgetTester tester, {
  required _TestSaveCallback onSave,
  FinancialEntry? initialEntry,
  bool initialIsIncome = true,
  GigState gigState = const GigState(),
}) async {
  // Default test canvas (600 logical px tall, 800 wide) doesn't reflect any
  // real device; simulate a real phone so scroll/off-screen assertions mean
  // something (matches financial_entry_details_bottom_sheet_test.dart).
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAddFinancialEntrySheet(
                  context,
                  onSave: onSave,
                  initialIsIncome: initialIsIncome,
                  initialEntry: initialEntry,
                ),
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
    'field order matches spec: Type, Amount, Date, Description, Paid to, '
    'Purchased by, Needed for gig, Notes',
    (tester) async {
      await _pump(tester, onSave: _noopSave);

      const orderedLabels = [
        'Type',
        'Amount',
        'Date',
        'Description (optional)',
        'Paid to (optional)',
        'Purchased by (optional)',
        'Needed for gig (optional)',
        'Notes (optional)',
      ];
      final positions = orderedLabels
          .map((label) => tester.getTopLeft(find.text(label)).dy)
          .toList();
      for (var i = 0; i < positions.length - 1; i++) {
        expect(
          positions[i],
          lessThan(positions[i + 1]),
          reason: '"${orderedLabels[i]}" should render above '
              '"${orderedLabels[i + 1]}"',
        );
      }
    },
  );

  testWidgets(
    'labels are fixed regardless of income/expense mode',
    (tester) async {
      await _pump(tester, onSave: _noopSave);

      expect(find.text('Paid to (optional)'), findsOneWidget);
      expect(find.text('Purchased by (optional)'), findsOneWidget);

      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      expect(find.text('Paid to (optional)'), findsOneWidget);
      expect(find.text('Purchased by (optional)'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a gig from the picker sets _selectedGigId and passes gigId '
    'through to onSave',
    (tester) async {
      String? capturedGigId;
      await _pump(
        tester,
        onSave: ({
          required entryType,
          required category,
          required amountCents,
          required entryDate,
          description,
          notes,
          gigId,
          is1099Expected,
          payerName,
          paidToName,
          paidToUserId,
          disbursements,
          depositToSavings,
          depositToSavingsCents,
        }) async {
          capturedGigId = gigId;
        },
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      final amountField =
          tester.widget<CurrencyTextField>(find.byType(CurrencyTextField));
      amountField.controller.cents = 5000;
      await tester.pump();

      // "Paid to" is the first AppDropdown<String?>; "Needed for gig" is
      // the second.
      await tester.tap(find.byType(AppDropdown<String?>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summer Bash').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(capturedGigId, 'gig-1');
    },
  );

  testWidgets(
    'notes field passes through to onSave.notes',
    (tester) async {
      String? capturedNotes;
      await _pump(
        tester,
        onSave: ({
          required entryType,
          required category,
          required amountCents,
          required entryDate,
          description,
          notes,
          gigId,
          is1099Expected,
          payerName,
          paidToName,
          paidToUserId,
          disbursements,
          depositToSavings,
          depositToSavingsCents,
        }) async {
          capturedNotes = notes;
        },
      );

      final amountField =
          tester.widget<CurrencyTextField>(find.byType(CurrencyTextField));
      amountField.controller.cents = 5000;
      await tester.pump();

      final notesField = find.descendant(
        of: find.byWidgetPredicate(
          (w) =>
              w is AppTextField &&
              w.hintText == 'e.g. Reimbursed via Venmo, receipt in email',
        ),
        matching: find.byType(FTextField),
      );
      await tester.enterText(notesField, 'Reimbursed via Venmo');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(capturedNotes, 'Reimbursed via Venmo');
    },
  );

  testWidgets(
    'editing an entry with a mid-list type auto-scrolls the pill row so the '
    'selected type is visible',
    (tester) async {
      final entry = _entry(category: 'Off-screen Type');
      await _pump(tester, onSave: _noopSave, initialEntry: entry);

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final pillRect = tester.getRect(find.text('Off-screen Type'));

      expect(pillRect.left, greaterThanOrEqualTo(0));
      expect(pillRect.right, lessThanOrEqualTo(screenWidth));
    },
  );

  testWidgets(
    'gig picker shows "No gig selected" as the default option when '
    '_selectedGigId is null',
    (tester) async {
      await _pump(
        tester,
        onSave: _noopSave,
        gigState: GigState(allGigs: [_gig(id: 'gig-1', name: 'Summer Bash')]),
      );

      // Open the picker — the collapsed field shows a generic placeholder
      // until a value is chosen, so the default item is verified in the
      // opened menu instead.
      await tester.tap(find.byType(AppDropdown<String?>).at(1));
      await tester.pumpAndSettle();

      expect(find.text('No gig selected'), findsOneWidget);
    },
  );
}
