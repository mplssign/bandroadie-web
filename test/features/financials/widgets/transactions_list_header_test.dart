// Tests for `_TransactionsListHeader`, a private widget in
// lib/features/financials/financials_screen.dart. Exercised indirectly by
// pumping the full FinancialsScreen with a controlled financialsProvider
// override seeded with distinguishable entries — see ARCHITECT_PLAN.md
// Task 6 / Verification Plan → Tier 1 (transactions_list_header_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
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
  required DateTime entryDate,
  required String paidToName,
  int amountCents = 10000,
}) {
  return FinancialEntry(
    id: id,
    bandId: 'band-1',
    entryType: FinancialEntryType.expense,
    category: 'Equipment',
    amountCents: amountCents,
    isIncome: false,
    entryDate: entryDate,
    paidToName: paidToName,
    createdBy: 'user-1',
    createdAt: entryDate,
    updatedAt: entryDate,
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FinancialsState state,
) async {
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

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

  final entries = [
    _entry(id: 'e1', entryDate: DateTime(2026, 3, 20), paidToName: 'Newest'),
    _entry(id: 'e2', entryDate: DateTime(2026, 3, 10), paidToName: 'Middle'),
    _entry(id: 'e3', entryDate: DateTime(2026, 3), paidToName: 'Oldest'),
  ];

  FinancialsState buildState() => FinancialsState(
        allEntries: entries,
        viewMode: FinancialViewMode.expenses,
      );

  testWidgets(
    'default render (before any tap): label reads "Newest first ▾" and '
    'entries render newest-first',
    (tester) async {
      await _pump(tester, buildState());

      expect(find.text('Newest first ▾'), findsOneWidget);
      expect(find.text('Oldest first ▾'), findsNothing);

      final newestY = tester.getTopLeft(find.text('Newest')).dy;
      final middleY = tester.getTopLeft(find.text('Middle')).dy;
      final oldestY = tester.getTopLeft(find.text('Oldest')).dy;
      expect(newestY, lessThan(middleY));
      expect(middleY, lessThan(oldestY));
    },
  );

  testWidgets(
    'after a single tap: label reads "Oldest first ▾" and the list order '
    'reverses',
    (tester) async {
      await _pump(tester, buildState());

      await tester.tap(find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.text('Oldest first ▾'), findsOneWidget);
      expect(find.text('Newest first ▾'), findsNothing);

      final newestY = tester.getTopLeft(find.text('Newest')).dy;
      final middleY = tester.getTopLeft(find.text('Middle')).dy;
      final oldestY = tester.getTopLeft(find.text('Oldest')).dy;
      expect(oldestY, lessThan(middleY));
      expect(middleY, lessThan(newestY));
    },
  );

  testWidgets(
    'after a second tap: label and list order return to the original',
    (tester) async {
      await _pump(tester, buildState());

      final sortInkWell = find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(sortInkWell);
      await tester.pumpAndSettle();
      await tester.tap(find
          .ancestor(
            of: find.text('Oldest first ▾'),
            matching: find.byType(InkWell),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.text('Newest first ▾'), findsOneWidget);
      final newestY = tester.getTopLeft(find.text('Newest')).dy;
      final middleY = tester.getTopLeft(find.text('Middle')).dy;
      final oldestY = tester.getTopLeft(find.text('Oldest')).dy;
      expect(newestY, lessThan(middleY));
      expect(middleY, lessThan(oldestY));
    },
  );

  testWidgets(
    'tapping the sort control does not mutate financialsProvider state',
    (tester) async {
      final container = await _pump(tester, buildState());
      final before = container.read(financialsProvider);

      await tester.tap(find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first);
      await tester.pumpAndSettle();

      final after = container.read(financialsProvider);
      expect(identical(before, after), isTrue);
    },
  );

  testWidgets(
    'sort control tap target is at least 48px tall',
    (tester) async {
      await _pump(tester, buildState());

      final sortInkWell = find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first;
      final size = tester.getSize(sortInkWell);
      expect(size.height, greaterThanOrEqualTo(48));
    },
  );

  testWidgets(
    'summary header total, count, and date-range label are unchanged '
    'before and after the sort toggle',
    (tester) async {
      await _pump(tester, buildState());

      expect(find.text('\$300.00'), findsOneWidget);
      expect(find.text('3 transactions'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);

      await tester.tap(find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.text('\$300.00'), findsOneWidget);
      expect(find.text('3 transactions'), findsOneWidget);
      expect(find.text('All time'), findsOneWidget);
    },
  );

  testWidgets(
    'the ▾ glyph is present in the label string in both sort states',
    (tester) async {
      await _pump(tester, buildState());
      expect(find.textContaining('▾'), findsOneWidget);

      await tester.tap(find
          .ancestor(
            of: find.text('Newest first ▾'),
            matching: find.byType(InkWell),
          )
          .first);
      await tester.pumpAndSettle();

      expect(find.textContaining('▾'), findsOneWidget);
    },
  );
}
