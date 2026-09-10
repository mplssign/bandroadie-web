// Regression test: the transaction list must actually scroll. Exercised by
// pumping the full FinancialsScreen with enough entries to exceed one
// viewport, then dragging the ListView and asserting the scroll offset moves
// and that an item scrolls out of the initial viewport.

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

List<FinancialEntry> _manyEntries(int count) {
  return List.generate(count, (i) {
    final date = DateTime(2026, 8).subtract(Duration(days: i));
    return FinancialEntry(
      id: 'e$i',
      bandId: 'band-1',
      entryType: FinancialEntryType.gigPay,
      category: 'Gig Pay',
      payerName: 'Payer $i',
      amountCents: 10000 + i,
      isIncome: true,
      entryDate: date,
      createdBy: 'user-1',
      createdAt: date,
      updatedAt: date,
    );
  });
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
    'dragging the transaction list moves its scroll offset and scrolls the '
    'first item out of the initial viewport',
    (tester) async {
      final entries = _manyEntries(30);
      await _pump(tester, FinancialsState(allEntries: entries));

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      final firstItemText = 'Payer 0';
      expect(find.text(firstItemText), findsOneWidget);

      final scrollableFinder = find.descendant(
        of: listFinder,
        matching: find.byType(Scrollable),
      );
      final scrollableState = tester.state<ScrollableState>(scrollableFinder);
      expect(scrollableState.position.pixels, 0.0);

      await tester.drag(listFinder, const Offset(0, -1000));
      await tester.pump();

      expect(scrollableState.position.pixels, greaterThan(0.0));
      expect(find.text(firstItemText), findsNothing);
    },
  );

  testWidgets(
    'the transaction ListView uses AlwaysScrollableScrollPhysics '
    '(precise regression guard: the drag-based test above cannot reliably '
    'distinguish this specific physics bug on its own — see ENGINEER_REPORT)',
    (tester) async {
      final entries = _manyEntries(30);
      await _pump(tester, FinancialsState(allEntries: entries));

      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
    },
  );
}
