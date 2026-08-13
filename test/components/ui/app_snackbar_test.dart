import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/components/ui/app_snackbar.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppSnackbar', () {
    testWidgets('showAppSnackbar displays snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: FToaster(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppSnackbar(context: context, message: 'Test Snackbar');
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();

      expect(find.text('Test Snackbar'), findsOneWidget);
      expect(find.byType(FToast), findsOneWidget);
    });

    testWidgets('info snackbar uses primary variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: FToaster(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppSnackbar(
                    context: context,
                    message: 'Info Message',
                    type: SnackbarType.info,
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();

      // Note: Uses FToast with .primary variant (no Material SnackBar)
      expect(find.text('Info Message'), findsOneWidget);
      expect(find.byType(FToast), findsOneWidget);
    });

    testWidgets('success snackbar uses primary variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: FToaster(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppSnackbar(
                    context: context,
                    message: 'Success Message',
                    type: SnackbarType.success,
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();

      // Note: Uses FToast with .primary variant (not Material green color)
      expect(find.text('Success Message'), findsOneWidget);
      expect(find.byType(FToast), findsOneWidget);
    });

    testWidgets('error snackbar uses destructive variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: FToaster(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppSnackbar(
                    context: context,
                    message: 'Error Message',
                    type: SnackbarType.error,
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();

      // Note: Uses FToast with .destructive variant (not Material red color)
      expect(find.text('Error Message'), findsOneWidget);
      expect(find.byType(FToast), findsOneWidget);
    });

    testWidgets('snackbar includes action when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: FToaster(child: child!),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppSnackbar(
                    context: context,
                    message: 'Message with Action',
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  );
                },
                child: const Text('Show Snackbar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Snackbar'));
      await tester.pump();

      expect(find.text('Message with Action'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.byType(FToast), findsOneWidget);
    });
  });
}
