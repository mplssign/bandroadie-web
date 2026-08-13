import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_dialog.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppDialog', () {
    testWidgets('showAppDialog displays dialog', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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
      expect(find.byType(FDialog), findsOneWidget);
    });

    testWidgets('AppAlertDialog renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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

    testWidgets('destructive action uses destructive variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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

      expect(find.text('Delete'), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.destructive);
    });

    testWidgets('non-destructive action uses outline variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
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

      expect(find.text('OK'), findsOneWidget);
      expect(find.byType(FButton), findsOneWidget);

      final button = tester.widget<FButton>(find.byType(FButton));
      expect(button.variant, FButtonVariant.outline);
    });

    testWidgets('custom builder is used when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDialog(
                    context: context,
                    builder: (context) => const Dialog(
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: Center(child: Text('Custom Dialog Content')),
                      ),
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

      // Verify custom dialog is displayed
      expect(find.text('Custom Dialog Content'), findsOneWidget);
      // Note: Custom builder uses plain Dialog, not AppAlertDialog
    });

    testWidgets('AlertDialog pattern still works when builder is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppDialog(
                    context: context,
                    title: 'Standard Dialog',
                    message: 'Using title/message/actions',
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

      // Verify standard AlertDialog pattern is displayed
      expect(find.text('Standard Dialog'), findsOneWidget);
      expect(find.text('Using title/message/actions'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.byType(AppAlertDialog), findsOneWidget);
    });

    testWidgets('throws ArgumentError when builder is null and args incomplete',
        (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  try {
                    showAppDialog(
                      context: context,
                      title: 'Only Title',
                      // Missing message and actions
                    );
                  } catch (e) {
                    expect(e, isA<ArgumentError>());
                    expect(
                      e.toString(),
                      contains(
                        'Either provide builder or provide title, message, and actions',
                      ),
                    );
                  }
                },
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Dialog should not be displayed since ArgumentError was thrown
      expect(find.byType(AppAlertDialog), findsNothing);
    });
  });
}
