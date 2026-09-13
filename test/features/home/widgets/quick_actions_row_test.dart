// ignore_for_file: avoid_redundant_argument_values

import 'package:bandroadie/features/home/widgets/quick_actions_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders quick actions in the required order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickActionsRow(
            onAddEvent: () {},
            onCreateSetlist: () {},
            onFinancials: () {},
            showAddEvent: true,
            showCreateSetlist: true,
            showFinancials: true,
          ),
        ),
      ),
    );

    final labels = tester
        .widgetList<OutlinedButton>(find.byType(OutlinedButton))
        .map((button) => (button.child as Text).data)
        .toList();

    expect(
      labels,
      equals(['+ Add Event', 'Financials', '+ Create Setlist']),
    );
  });
}
