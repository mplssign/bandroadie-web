import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/financials/widgets/transaction_card_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TransactionCardSkeleton renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: TransactionCardSkeleton()),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TransactionCardSkeleton), findsOneWidget);
  });
}
