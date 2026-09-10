import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/app_dropdown.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:bandroadie/components/ui/sheet_footer.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';
import 'package:bandroadie/features/contacts/contacts_controller.dart';
import 'package:bandroadie/features/contacts/venues_controller.dart';
import 'package:bandroadie/features/financials/models/financial_entry.dart';
import 'package:bandroadie/features/financials/widgets/add_financial_entry_bottom_sheet.dart';
import 'package:bandroadie/features/gigs/gig_controller.dart';
import 'package:bandroadie/features/members/member_vm.dart';
import 'package:bandroadie/features/members/permissions/band_permissions.dart';
import 'package:bandroadie/features/members/permissions/band_permissions_provider.dart';

// Stubs so the sheet's initState() providers never touch Supabase/network.
class _StubContactsNotifier extends ContactsNotifier {
  @override
  ContactsState build() => const ContactsState();

  @override
  Future<void> load(String? bandId) async {}
}

class _StubVenuesNotifier extends VenuesNotifier {
  @override
  VenuesState build() => const VenuesState();

  @override
  Future<void> load(String? bandId) async {}
}

class _StubGigNotifier extends GigNotifier {
  @override
  GigState build() => const GigState();

  @override
  Future<void> loadGigs() async {}

  @override
  Future<void> refresh() async {}
}

final _baseOverrides = [
  contactsProvider.overrideWith(_StubContactsNotifier.new),
  venuesProvider.overrideWith(_StubVenuesNotifier.new),
  gigProvider.overrideWith(_StubGigNotifier.new),
  activeBandIdProvider.overrideWithValue('test-band-id'),
  currentUserPermissionsProvider.overrideWith(
    (ref) async => BandPermissions.admin,
  ),
];

List<MemberVM> _testMembers() => [
      MemberVM(
        userId: 'user-1',
        memberId: 'member-1',
        name: 'Buster B.',
        firstName: 'Buster',
        lastName: 'B.',
        email: 'buster@example.com',
        bandRole: 'admin',
        status: 'active',
        joinedAt: DateTime(2024),
        hasUserRow: true,
        profileCompleted: true,
      ),
      MemberVM(
        userId: 'user-2',
        memberId: 'member-2',
        name: 'George Michael B.',
        firstName: 'George',
        lastName: 'Michael B.',
        email: 'gob@example.com',
        bandRole: 'member',
        status: 'active',
        joinedAt: DateTime(2024),
        hasUserRow: true,
        profileCompleted: true,
      ),
    ];

Future<void> _pumpSheet(
  WidgetTester tester, {
  FinancialEntry? initialEntry,
  bool initialIsIncome = true,
  List<MemberVM> members = const [],
  VoidCallback? onDelete,
}) async {
  // Taller viewport (same width as the default test surface) so every
  // section + switch is on-screen and tappable without needing to scroll.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: _baseOverrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAddFinancialEntrySheet(
                context,
                onSave: ({
                  required entryType,
                  required category,
                  required amountCents,
                  required entryDate,
                  description,
                  is1099Expected,
                  payerName,
                  paidToName,
                  paidToUserId,
                  disbursements,
                  depositToSavings,
                  depositToSavingsCents,
                  gigId,
                  isReimbursed,
                  reimbursedDate,
                  reimbursementMethod,
                  notes,
                }) async {},
                onDelete: onDelete,
                initialIsIncome: initialIsIncome,
                initialEntry: initialEntry,
                members: members,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

FinancialEntry _stubEntry({required bool isIncome}) => FinancialEntry(
      id: 'entry-1',
      bandId: 'test-band-id',
      entryType:
          isIncome ? FinancialEntryType.merchSale : FinancialEntryType.expense,
      category: isIncome ? 'Merch Sale' : 'Rent',
      amountCents: 25000,
      isIncome: isIncome,
      entryDate: DateTime(2026, 7, 4),
      createdBy: 'user-1',
      createdAt: DateTime(2026, 7, 4),
      updatedAt: DateTime(2026, 7, 4),
    );

// Finds the FTextField nested inside the same small Column as [label] —
// matches how CurrencyTextField/AppTextField pair a Text label with a field.
Finder _fieldLabelled(String label) {
  return find.descendant(
    of: find
        .ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        )
        .first,
    matching: find.byType(FTextField),
  );
}

// Finds the FTextField inside the same Row as a member's name label — used
// for per-member split amounts, which render with an empty CurrencyTextField
// label (no Text sibling of their own).
Finder _splitFieldNear(String memberLabel) {
  return find.descendant(
    of: find
        .ancestor(
          of: find.text(memberLabel),
          matching: find.byType(Row),
        )
        .first,
    matching: find.byType(FTextField),
  );
}

// Finds the AppDropdown nested inside the same small Column as [label].
Finder _dropdownLabelled(String label) {
  return find.descendant(
    of: find
        .ancestor(
          of: find.text(label),
          matching: find.byType(Column),
        )
        .first,
    matching: find.byType(AppDropdown<String?>),
  );
}

// Reads the current rendered text of an [FTextField] found by [finder] via
// its underlying [FTextFieldManagedControl] controller — the only way to
// observe a CurrencyTextField's displayed value from outside the widget.
String _controllerText(WidgetTester tester, Finder finder) {
  final control = tester.widget<FTextField>(finder).control;
  return (control as FTextFieldManagedControl).controller?.text ?? '';
}

void main() {
  group('_AddFinancialEntryBottomSheet header', () {
    testWidgets('add mode shows title and subtitle', (tester) async {
      await _pumpSheet(tester);

      // "Add Transaction" also appears as the footer's primary button label,
      // so scope the title check to the header block next to the subtitle.
      final headerColumn = find
          .ancestor(
            of: find.text("Track your band's income or expense."),
            matching: find.byType(Column),
          )
          .first;
      expect(
        find.descendant(
            of: headerColumn, matching: find.text('Add Transaction')),
        findsOneWidget,
      );
      expect(
        find.text("Track your band's income or expense."),
        findsOneWidget,
      );
    });

    testWidgets('edit mode shows title without subtitle', (tester) async {
      await _pumpSheet(tester, initialEntry: _stubEntry(isIncome: true));

      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(
        find.text("Track your band's income or expense."),
        findsNothing,
      );
    });
  });

  group('_AddFinancialEntryBottomSheet sections', () {
    testWidgets('income mode shows About, Payment Details, Distribution, Notes',
        (tester) async {
      await _pumpSheet(tester);

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('Distribution'), findsOneWidget);
      expect(find.text('Reimbursement'), findsNothing);
      expect(find.text('Notes'), findsOneWidget);
    });

    testWidgets(
        'expense mode shows About, Payment Details, Reimbursement, Notes',
        (tester) async {
      await _pumpSheet(tester, initialIsIncome: false);

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Payment Details'), findsOneWidget);
      expect(find.text('Reimbursement'), findsOneWidget);
      expect(find.text('Distribution'), findsNothing);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  group('_AddFinancialEntryBottomSheet footer', () {
    testWidgets('add mode primary label is Add Transaction', (tester) async {
      await _pumpSheet(tester);

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.primaryLabel, 'Add Transaction');
    });

    testWidgets('edit mode primary label is Save with destructive delete',
        (tester) async {
      await _pumpSheet(
        tester,
        initialEntry: _stubEntry(isIncome: true),
        onDelete: () {},
      );

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.primaryLabel, 'Save');
      expect(footer.destructiveLabel, 'Delete Income');
    });

    testWidgets('edit mode destructive label is Delete Expense for expenses',
        (tester) async {
      await _pumpSheet(
        tester,
        initialEntry: _stubEntry(isIncome: false),
        onDelete: () {},
      );

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.destructiveLabel, 'Delete Expense');
    });
  });

  group('_AddFinancialEntryBottomSheet reimbursement section', () {
    testWidgets(
        'toggling Reimbursed by Band reveals date + method, Other reveals free text',
        (tester) async {
      await _pumpSheet(tester, initialIsIncome: false);

      expect(find.widgetWithText(FTextField, 'e.g., PayPal'), findsNothing);

      await tester.tap(find.byType(AppSwitch).first);
      await tester.pumpAndSettle();

      expect(find.text('Reimbursed on'), findsOneWidget);
      expect(find.text('Method'), findsOneWidget);

      // Open the method dropdown and select "Other".
      await tester.tap(_dropdownLabelled('Method'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is FTextField && w.hint == 'e.g., PayPal',
        ),
        findsOneWidget,
      );
    });
  });

  group('_AddFinancialEntryBottomSheet distribution auto-balance', () {
    testWidgets(
        'reducing a member split below the even share auto-enables Deposit to Savings',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      // Enter total amount: $250.00 (25000 cents, POS digit-entry).
      await tester.enterText(_fieldLabelled('Amount'), '25000');
      await tester.pumpAndSettle();

      // Turn on Disburse to Band (first switch is the 1099 switch, second is
      // Disburse to Band).
      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();

      // Reduce the first member's split to $30.00 (3000 cents). With 2 test
      // members and $250.00 total, the even split is $125.00 each.
      await tester.enterText(_splitFieldNear('Buster B.'), '3000');
      await tester.pumpAndSettle();

      // Savings Amount field should now be visible with the shortfall
      // ($250.00 - $30.00 - $125.00 = $95.00), and Deposit to Savings
      // should have auto-enabled.
      expect(find.text('Savings Amount'), findsOneWidget);
      expect(
        find.text('Automatically calculated from remaining amount.'),
        findsOneWidget,
      );
    });
  });

  group('distribution auto-fill and validation', () {
    testWidgets(
        'Deposit to Savings ON with Disburse OFF auto-fills full Amount',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '20000');
      await tester.pumpAndSettle();

      // Switches: 0 = 1099, 1 = Disburse to Band, 2 = Deposit to Savings.
      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(2));
      await tester.pumpAndSettle();

      expect(
        _controllerText(tester, _fieldLabelled('Savings Amount')),
        r'$200.00',
      );

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNotNull);
    });

    testWidgets(
        'Deposit to Savings ON with Disburse ON and splits fully covering Amount fills \$0',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '25000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(1)); // Disburse to Band
      await tester.pumpAndSettle();

      await tester.tap(switches.at(2)); // Deposit to Savings
      await tester.pumpAndSettle();

      // Splits ($125.00 x 2) already cover the full $250.00 amount, so the
      // remainder-based fill leaves Savings at zero — no double-count.
      expect(
        _controllerText(tester, _fieldLabelled('Savings Amount')),
        '',
      );

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNotNull);
    });

    testWidgets(
        'Deposit to Savings ON with Disburse ON and positive remainder fills remainder — REGRESSION GUARD',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '25000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(1)); // Disburse to Band
      await tester.pumpAndSettle();

      // Reduce the first member's split to $30.00. With 2 members and
      // $250.00 total, the even split is $125.00 each, leaving a $95.00
      // remainder ($250.00 - $30.00 - $125.00).
      await tester.enterText(_splitFieldNear('Buster B.'), '3000');
      await tester.pumpAndSettle();

      // Deposit to Savings auto-flipped ON.
      expect(tester.widget<AppSwitch>(switches.at(2)).value, isTrue);
      expect(
        _controllerText(tester, _fieldLabelled('Savings Amount')),
        r'$95.00',
      );
      expect(find.text('Exceeds remaining balance'), findsNothing);
    });

    testWidgets(
        'Typing a split that exceeds Amount shows inline error on that split and disables Save',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '25000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(1)); // Disburse to Band
      await tester.pumpAndSettle();

      // Push member 1's split well above the total amount.
      await tester.enterText(_splitFieldNear('Buster B.'), '50000');
      await tester.pumpAndSettle();

      expect(find.text('Exceeds remaining balance'), findsOneWidget);

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNull);
    });

    testWidgets(
        'Correcting the offending split clears the error and re-enables Save',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '25000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(1)); // Disburse to Band
      await tester.pumpAndSettle();

      await tester.enterText(_splitFieldNear('Buster B.'), '50000');
      await tester.pumpAndSettle();
      expect(find.text('Exceeds remaining balance'), findsOneWidget);

      // Restore the even split ($125.00).
      await tester.enterText(_splitFieldNear('Buster B.'), '12500');
      await tester.pumpAndSettle();

      expect(find.text('Exceeds remaining balance'), findsNothing);

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNotNull);
    });

    testWidgets(
        'Typing a Savings value that exceeds Amount shows inline error on Savings and disables Save',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '20000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(2)); // Deposit to Savings (Disburse OFF)
      await tester.pumpAndSettle();

      // Savings auto-filled to $200.00; push it above the $200.00 Amount.
      await tester.enterText(_fieldLabelled('Savings Amount'), '30000');
      await tester.pumpAndSettle();

      expect(find.text('Exceeds remaining balance'), findsOneWidget);
      expect(
        find.text('Automatically calculated from remaining amount.'),
        findsNothing,
      );

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNull);
    });

    testWidgets(
        'Correcting the offending Savings value clears the error and re-enables Save',
        (tester) async {
      final members = _testMembers();
      await _pumpSheet(tester, members: members);

      await tester.enterText(_fieldLabelled('Amount'), '20000');
      await tester.pumpAndSettle();

      final switches = find.byType(AppSwitch);
      await tester.tap(switches.at(2)); // Deposit to Savings (Disburse OFF)
      await tester.pumpAndSettle();

      await tester.enterText(_fieldLabelled('Savings Amount'), '30000');
      await tester.pumpAndSettle();
      expect(find.text('Exceeds remaining balance'), findsOneWidget);

      // Correct Savings back to a value within the $200.00 Amount.
      await tester.enterText(_fieldLabelled('Savings Amount'), '15000');
      await tester.pumpAndSettle();

      expect(find.text('Exceeds remaining balance'), findsNothing);

      final footer = tester.widget<SheetFooter>(find.byType(SheetFooter));
      expect(footer.onPrimary, isNotNull);
    });
  });
}
