import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/event_editor_theme.dart';
import 'package:bandroadie/components/ui/app_switch.dart';
import 'package:forui/forui.dart';

void main() {
  group('AppSwitch', () {
    testWidgets('renders without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
    });

    testWidgets('reflects value state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: true, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);

      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      expect(switchWidget.value, isTrue);
    });

    testWidgets('calls onChanged callback', (tester) async {
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppSwitch(
                value: value,
                onChanged: (newValue) {
                  setState(() => value = newValue);
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppSwitch));
      await tester.pumpAndSettle();

      expect(value, isTrue);
    });

    testWidgets('activeColor applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppSwitch(
              value: true,
              onChanged: (_) {},
              activeColor: Colors.green,
            ),
          ),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      // Verify style is a delta (proving activeColor was applied)
      expect(switchWidget.style, isA<FSwitchStyleDelta>());
    });

    testWidgets('activeTrackColor applies StyleDelta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: AppSwitch(
              value: true,
              onChanged: (_) {},
              activeTrackColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      // Verify style is a delta (proving activeTrackColor was applied)
      expect(switchWidget.style, isA<FSwitchStyleDelta>());
    });

    testWidgets('disables when onChanged is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: const Scaffold(body: AppSwitch(value: false, onChanged: null)),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);

      final switchWidget = tester.widget<FSwitch>(find.byType(FSwitch));
      expect(switchWidget.onChange, isNull);
      expect(switchWidget.enabled, isFalse);
    });
    testWidgets(
        'renders under AppTheme.foruiTheme with distinct on-state track and thumb colors',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: true, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final element = tester.element(find.byType(FSwitch));
      final switchStyle = FTheme.of(element).switchStyle;

      expect(
        switchStyle.trackColor.resolve(<FVariant>{FSwitchVariant.selected}),
        AppColors.primarySoft,
      );
      expect(
        switchStyle.thumbColor.resolve(<FVariant>{}),
        Colors.white,
      );
    });

    testWidgets(
        'off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: AppTheme.foruiTheme(Brightness.dark),
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final element = tester.element(find.byType(FSwitch));
      final switchStyle = FTheme.of(element).switchStyle;

      expect(
        switchStyle.trackColor.resolve(<FVariant>{}),
        AppColors.switchTrackOff,
      );
    });

    testWidgets(
        'off-state track resolves to AppColors.switchTrackOff under buildEventEditorTheme',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: buildEventEditorTheme(),
            child: child!,
          ),
          home: Scaffold(body: AppSwitch(value: false, onChanged: (_) {})),
        ),
      );

      expect(find.byType(FSwitch), findsOneWidget);
      final element = tester.element(find.byType(FSwitch));
      final switchStyle = FTheme.of(element).switchStyle;

      expect(
        switchStyle.trackColor.resolve(<FVariant>{}),
        AppColors.switchTrackOff,
      );
    });

    testWidgets(
        'renders label and toggles when label is tapped when leadingLabel is true',
        (tester) async {
      bool? captured;
      bool value = false;

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => FTheme(
            data: FTheme.neutral.dark.touch,
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => AppSwitch(
                value: value,
                onChanged: (v) {
                  setState(() {
                    value = v;
                    captured = v;
                  });
                },
                label: const Text('Enable X'),
                leadingLabel: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Enable X'), findsOneWidget);
      await tester.tap(find.text('Enable X'));
      await tester.pumpAndSettle();
      expect(captured, isTrue);
    });
  });
}
