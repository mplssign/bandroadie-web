// Tests for `_SummaryHeader`, a private widget in
// lib/features/financials/financials_screen.dart. Exercised indirectly by
// pumping the full FinancialsScreen with an overridden financialsProvider —
// see ARCHITECT_PLAN.md Task 6 / Verification Plan → Tier 1
// (summary_header_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/app_dropdown.dart';
import 'package:bandroadie/features/financials/financials_controller.dart';
import 'package:bandroadie/features/financials/financials_screen.dart';
import 'package:bandroadie/features/financials/models/financial_entry.dart';
import 'package:bandroadie/features/members/permissions/band_permissions.dart';
import 'package:bandroadie/features/members/permissions/band_permissions_provider.dart';

class _FakeFinancialsNotifier extends FinancialsNotifier {
  _FakeFinancialsNotifier(this._state);
  final FinancialsState _state;
  @override
  FinancialsState build() => _state;
}

FinancialEntry _entry({
  required String id,
  required int amountCents,
  required bool isIncome,
  DateTime? entryDate,
}) {
  final date = entryDate ?? DateTime(2026, 1, 15);
  return FinancialEntry(
    id: id,
    bandId: 'band-1',
    entryType:
        isIncome ? FinancialEntryType.gigPay : FinancialEntryType.expense,
    category: isIncome ? 'Gig Pay' : 'Equipment',
    amountCents: amountCents,
    isIncome: isIncome,
    entryDate: date,
    createdBy: 'user-1',
    createdAt: date,
    updatedAt: date,
  );
}

Future<void> _pump(WidgetTester tester, FinancialsState state) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        financialsProvider.overrideWith(() => _FakeFinancialsNotifier(state)),
        currentUserPermissionsProvider
            .overrideWith((ref) async => BandPermissions.admin),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: const FinancialsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _pumpWithContainer(
  WidgetTester tester,
  FinancialsState state,
) async {
  final container = ProviderContainer(overrides: [
    financialsProvider.overrideWith(() => _FakeFinancialsNotifier(state)),
    currentUserPermissionsProvider
        .overrideWith((ref) async => BandPermissions.admin),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: FTheme(
          data: AppTheme.foruiTheme(Brightness.dark),
          child: const FinancialsScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
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
    'total for two income entries formats as the combined dollar amount, '
    'no prefix',
    (tester) async {
      final entries = [
        _entry(id: 'e1', amountCents: 10000, isIncome: true),
        _entry(id: 'e2', amountCents: 25050, isIncome: true),
      ];
      await _pump(
        tester,
        FinancialsState(allEntries: entries),
      );

      expect(find.text('\$350.50'), findsOneWidget);
    },
  );

  testWidgets(
    'label reads TOTAL INCOME under income mode, TOTAL EXPENSES under '
    'expenses mode',
    (tester) async {
      final incomeEntry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [incomeEntry]),
      );
      expect(find.text('TOTAL INCOME'), findsOneWidget);
      expect(find.text('TOTAL EXPENSES'), findsNothing);

      final expenseEntry = _entry(id: 'e2', amountCents: 5000, isIncome: false);
      await _pump(
        tester,
        FinancialsState(
            allEntries: [expenseEntry], viewMode: FinancialViewMode.expenses),
      );
      expect(find.text('TOTAL EXPENSES'), findsOneWidget);
      expect(find.text('TOTAL INCOME'), findsNothing);
    },
  );

  testWidgets(
    'default state has dateFilter = FinancialDateFilter.thisYear and the '
    'AppDropdown shows "This year"',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );
      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        find.byType(AppDropdown<FinancialDateFilter>),
      );
      expect(dropdown.value, FinancialDateFilter.thisYear);
      expect(find.text('This year'), findsOneWidget);
    },
  );

  testWidgets(
    'setting dateFilter to allTime causes the AppDropdown to render '
    '"All time" and the trailing text to read the unfiltered count',
    (tester) async {
      final previousYear = DateTime.now().year - 1;
      final entries = [
        _entry(
          id: 'e1',
          amountCents: 5000,
          isIncome: true,
          entryDate: DateTime(previousYear, 3, 15),
        ),
        _entry(id: 'e2', amountCents: 3000, isIncome: true),
      ];
      await _pump(
        tester,
        FinancialsState(
          allEntries: entries,
          dateFilter: FinancialDateFilter.allTime,
        ),
      );
      expect(find.text('All time'), findsOneWidget);
      expect(find.text(' • 2 transactions'), findsOneWidget);
    },
  );

  testWidgets(
    'renders the dropdown and count as adjacent widgets separated by " • "',
    (tester) async {
      final threeEntries = [
        _entry(id: 'e1', amountCents: 1000, isIncome: true),
        _entry(id: 'e2', amountCents: 2000, isIncome: true),
        _entry(id: 'e3', amountCents: 3000, isIncome: true),
      ];
      await _pump(
        tester,
        FinancialsState(allEntries: threeEntries),
      );
      expect(find.byType(AppDropdown<FinancialDateFilter>), findsOneWidget);
      expect(find.text(' • 3 transactions'), findsOneWidget);
    },
  );

  testWidgets(
    'count phrasing is singular for one entry, plural for multiple entries',
    (tester) async {
      final oneEntry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [oneEntry]),
      );
      expect(find.text(' • 1 transaction'), findsOneWidget);

      final threeEntries = [
        _entry(id: 'e1', amountCents: 1000, isIncome: true),
        _entry(id: 'e2', amountCents: 2000, isIncome: true),
        _entry(id: 'e3', amountCents: 3000, isIncome: true),
      ];
      await _pump(
        tester,
        FinancialsState(allEntries: threeEntries),
      );
      expect(find.text(' • 3 transactions'), findsOneWidget);
    },
  );

  testWidgets(
    'AppDropdown<FinancialDateFilter> value is non-null in every default '
    'state (thisYear)',
    (tester) async {
      await _pump(tester, const FinancialsState());
      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        find.byType(AppDropdown<FinancialDateFilter>),
      );
      expect(dropdown.value, isNotNull);
      expect(dropdown.value, FinancialDateFilter.thisYear);
    },
  );

  testWidgets(
    'AppDropdown format renders "This year" text, not a year numeral, for '
    'the thisYear case',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );
      expect(find.text('This year'), findsOneWidget);
      expect(find.text('${DateTime.now().year}'), findsNothing);
    },
  );

  testWidgets(
    'AppDropdown items list contains exactly the three FinancialDateFilter '
    'values in enum-declaration order (allTime, thisYear, thisMonth)',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );
      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        find.byType(AppDropdown<FinancialDateFilter>),
      );
      final values = dropdown.items!.map((i) => i.value).toList();
      expect(values, [
        FinancialDateFilter.allTime,
        FinancialDateFilter.thisYear,
        FinancialDateFilter.thisMonth,
      ]);
    },
  );

  testWidgets(
    'AppDropdown items render Text children with the exact strings '
    '"All time", "This year", "This month"',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );
      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        find.byType(AppDropdown<FinancialDateFilter>),
      );
      const expectedLabels = {
        FinancialDateFilter.allTime: 'All time',
        FinancialDateFilter.thisYear: 'This year',
        FinancialDateFilter.thisMonth: 'This month',
      };
      for (final item in dropdown.items!) {
        final child = item.child as Text;
        expect(child.data, expectedLabels[item.value]);
      }
    },
  );

  testWidgets(
    'invoking AppDropdown.onChanged(FinancialDateFilter.allTime) dispatches '
    'setDateFilter on the notifier',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      final container = await _pumpWithContainer(
        tester,
        FinancialsState(allEntries: [entry]),
      );
      expect(
        container.read(financialsProvider).dateFilter,
        FinancialDateFilter.thisYear,
      );
      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        find.byType(AppDropdown<FinancialDateFilter>),
      );
      dropdown.onChanged(FinancialDateFilter.allTime);
      await tester.pumpAndSettle();
      expect(
        container.read(financialsProvider).dateFilter,
        FinancialDateFilter.allTime,
      );
    },
  );

  testWidgets(
    'inline dropdown remains visible and its onChanged callback wired when '
    'filteredEntries is empty for the selected filter',
    (tester) async {
      final priorYear = DateTime.now().year - 1;
      final entry = _entry(
        id: 'e1',
        amountCents: 5000,
        isIncome: true,
        entryDate: DateTime(priorYear, 3, 15),
      );
      final container = await _pumpWithContainer(
        tester,
        FinancialsState(allEntries: [entry]),
      );

      expect(find.text('No entries yet'), findsOneWidget);
      expect(find.text('TOTAL INCOME'), findsOneWidget);
      final dropdownFinder = find.byType(AppDropdown<FinancialDateFilter>);
      expect(dropdownFinder, findsOneWidget);

      final dropdown = tester.widget<AppDropdown<FinancialDateFilter>>(
        dropdownFinder,
      );
      expect(dropdown.items!.map((i) => i.value).toList(), [
        FinancialDateFilter.allTime,
        FinancialDateFilter.thisYear,
        FinancialDateFilter.thisMonth,
      ]);

      dropdown.onChanged(FinancialDateFilter.allTime);
      await tester.pumpAndSettle();

      expect(
        container.read(financialsProvider).dateFilter,
        FinancialDateFilter.allTime,
      );
      expect(find.text('No entries yet'), findsNothing);
      expect(find.text('\$50.00'), findsWidgets);
    },
  );

  testWidgets(
    'View Savings Balance and Generate Report links are each followed by an '
    'AppIcons.forward chevron',
    (tester) async {
      final entry = _entry(id: 'e1', amountCents: 5000, isIncome: true);
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );

      expect(find.text('View Savings Balance'), findsOneWidget);
      expect(find.text('Generate Report'), findsOneWidget);

      final viewSavingsRow = find
          .ancestor(
            of: find.text('View Savings Balance'),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(
            of: viewSavingsRow, matching: find.byIcon(AppIcons.forward)),
        findsOneWidget,
      );

      final generateReportRow = find
          .ancestor(
            of: find.text('Generate Report'),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(
            of: generateReportRow, matching: find.byIcon(AppIcons.forward)),
        findsOneWidget,
      );
    },
  );
}
