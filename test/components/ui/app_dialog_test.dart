import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';

void main() {
  group('AppDialog', () {
    testWidgets('showAppDialog displays dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDialog(
                    context: context,
                    title: 'Test Title',
                    message: 'Test Message',
                    actions: [
                      DialogAction(
                        label: 'OK',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Message'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('AppAlertDialog renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AppAlertDialog(
                      title: 'Alert',
                      message: 'This is an alert',
                      actions: [
                        DialogAction(
                          label: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                        ),
                        DialogAction(
                          label: 'Delete',
                          isDestructive: true,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Alert'), findsOneWidget);
      expect(find.text('This is an alert'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('destructive action renders as FilledButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDialog(
                    context: context,
                    title: 'Confirm',
                    message: 'Are you sure?',
                    actions: [
                      DialogAction(
                        label: 'Delete',
                        isDestructive: true,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('non-destructive action renders as TextButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDialog(
                    context: context,
                    title: 'Info',
                    message: 'Information',
                    actions: [
                      DialogAction(
                        label: 'OK',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  );
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(TextButton), findsOneWidget);
    });
  });
}
