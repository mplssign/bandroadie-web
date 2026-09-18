import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/home/widgets/gig_card_skeleton.dart';
import 'package:bandroadie/features/home/widgets/rehearsal_card_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RehearsalCardSkeleton renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: RehearsalCardSkeleton()),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(RehearsalCardSkeleton), findsOneWidget);
  });

  testWidgets('GigCardSkeleton renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: GigCardSkeleton()),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(GigCardSkeleton), findsOneWidget);
  });
}
