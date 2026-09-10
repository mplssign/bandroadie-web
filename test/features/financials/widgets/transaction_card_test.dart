// Tests for `_TransactionCard`, a private widget in
// lib/features/financials/financials_screen.dart. Exercised indirectly by
// pumping the full FinancialsScreen with an overridden financialsProvider —
// see ARCHITECT_PLAN.md Task 6 / Verification Plan → Tier 1
// (transaction_card_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
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
  required FinancialEntryType entryType,
  required bool isIncome,
  required String category,
  int amountCents = 10000,
  String? payerName,
  String? paidToName,
  bool isReimbursed = false,
  Map<String, int>? disbursements,
}) {
  final date = DateTime(DateTime.now().year, 1, 15);
  return FinancialEntry(
    id: id,
    bandId: 'band-1',
    entryType: entryType,
    category: category,
    amountCents: amountCents,
    isIncome: isIncome,
    entryDate: date,
    isReimbursed: isReimbursed,
    payerName: payerName,
    paidToName: paidToName,
    disbursements: disbursements,
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
    'expense with paidToName shows paidToName as title, category as subtitle',
    (tester) async {
      final entry = _entry(
        id: 'e1',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      expect(find.text('Guitar Center'), findsOneWidget);
      expect(find.text('Equipment'), findsOneWidget);
    },
  );

  testWidgets(
    'expense with null paidToName falls back to category for the title',
    (tester) async {
      final entry = _entry(
        id: 'e2',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      // Title and subtitle both fall back to "Equipment".
      expect(find.text('Equipment'), findsNWidgets(2));
    },
  );

  testWidgets(
    'income with payerName shows payerName as the title',
    (tester) async {
      final entry = _entry(
        id: 'e3',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'The Venue',
      );
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );

      expect(find.text('The Venue'), findsOneWidget);
    },
  );

  testWidgets(
    'expense with isReimbursed true shows the Reimbursed badge',
    (tester) async {
      final entry = _entry(
        id: 'e4',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
        isReimbursed: true,
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      expect(find.text('Reimbursed'), findsOneWidget);
    },
  );

  testWidgets(
    'expense with isReimbursed false shows no Reimbursed badge',
    (tester) async {
      final entry = _entry(
        id: 'e5',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      expect(find.text('Reimbursed'), findsNothing);
    },
  );

  testWidgets(
    'income with non-empty disbursements shows the Disbursed badge',
    (tester) async {
      final entry = _entry(
        id: 'e6',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'The Venue',
        disbursements: const {'member-a-id': 5000},
      );
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );

      expect(find.text('Disbursed'), findsOneWidget);
    },
  );

  testWidgets(
    'income with null or empty disbursements shows no Disbursed badge',
    (tester) async {
      final nullEntry = _entry(
        id: 'e7',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'Venue A',
      );
      final emptyEntry = _entry(
        id: 'e8',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'Venue B',
        disbursements: const {},
      );
      await _pump(
        tester,
        FinancialsState(
          allEntries: [nullEntry, emptyEntry],
        ),
      );

      expect(find.text('Disbursed'), findsNothing);
    },
  );

  testWidgets(
    'expense with disbursements never shows the Disbursed badge '
    '(never on the opposite entry type)',
    (tester) async {
      final entry = _entry(
        id: 'e9',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
        disbursements: const {'m': 100},
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      expect(find.text('Disbursed'), findsNothing);
    },
  );

  testWidgets(
    'income with isReimbursed true never shows the Reimbursed badge '
    '(never on the opposite entry type)',
    (tester) async {
      final entry = _entry(
        id: 'e10',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'The Venue',
        isReimbursed: true,
      );
      await _pump(
        tester,
        FinancialsState(allEntries: [entry]),
      );

      expect(find.text('Reimbursed'), findsNothing);
    },
  );

  testWidgets(
    'amount renders with a minus prefix and error color on expenses, '
    'no prefix and success color on income',
    (tester) async {
      final expense = _entry(
        id: 'e11',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
        amountCents: 10050,
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [expense], viewMode: FinancialViewMode.expenses),
      );
      final elementsRightBefore = find.text('−\$100.50').evaluate();
      final expenseText = elementsRightBefore.single.widget as Text;
      expect(expenseText.style?.color, AppColors.error);

      final income = _entry(
        id: 'e12',
        entryType: FinancialEntryType.gigPay,
        isIncome: true,
        category: 'Gig Pay',
        payerName: 'The Venue',
        amountCents: 15000,
      );
      await _pump(
        tester,
        FinancialsState(allEntries: [income]),
      );
      final incomeCardContainer = find
          .ancestor(
            of: find.text('The Venue'),
            matching: find.byType(Container),
          )
          .first;
      final incomeText = tester.widget<Text>(find.descendant(
        of: incomeCardContainer,
        matching: find.text('\$150.00'),
      ));
      expect(incomeText.style?.color, BrandColors.dark.success);
    },
  );

  testWidgets(
    'card renders exactly one Icon (the trailing chevron) — '
    'regression guard against reintroducing a leading category icon',
    (tester) async {
      final entry = _entry(
        id: 'e13',
        entryType: FinancialEntryType.expense,
        isIncome: false,
        category: 'Equipment',
        paidToName: 'Guitar Center',
        isReimbursed: true,
      );
      await _pump(
        tester,
        FinancialsState(
            allEntries: [entry], viewMode: FinancialViewMode.expenses),
      );

      final cardContainer = find
          .ancestor(
            of: find.text('Guitar Center'),
            matching: find.byType(Container),
          )
          .first;
      expect(
        find.descendant(of: cardContainer, matching: find.byType(Icon)),
        findsOneWidget,
      );
    },
  );
}
