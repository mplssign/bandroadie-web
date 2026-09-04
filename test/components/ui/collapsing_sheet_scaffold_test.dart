import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_test/flutter_test.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/components/ui/collapsing_sheet_scaffold.dart';
import 'package:bandroadie/components/ui/sheet_footer.dart';
import 'package:forui/forui.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget child, {MediaQueryData? mediaQueryOverride}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (context, c) {
      final inner = FTheme(data: FTheme.neutral.dark.touch, child: c!);
      if (mediaQueryOverride != null) {
        return MediaQuery(data: mediaQueryOverride, child: inner);
      }
      return inner;
    },
    home: Scaffold(body: child),
  );
}

FixedScrollMetrics _makeMetrics({double maxScrollExtent = 1000.0}) =>
    FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: maxScrollExtent,
      pixels: 0,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1,
    );

/// Dispatches [notification] from [context], which must be inside the
/// CollapsingSheetScaffold's NotificationListener subtree so it bubbles at
/// depth 0.
void _dispatch(BuildContext context, Notification notification) {
  notification.dispatch(context);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Returns the first SizeTransition in the tree (wraps the header, if any)
  // and the last (wraps the footer).

  group('CollapsingSheetScaffold', () {
    // ------------------------------------------------------------------
    // 1. Collapses footer (and header when present) on reverse scroll
    // ------------------------------------------------------------------
    testWidgets('collapses footer on reverse scroll', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(
                  30,
                  (_) => const SizedBox(height: 60),
                ),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(0.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 2. Reveals footer on forward scroll (after collapse)
    // ------------------------------------------------------------------
    testWidgets('reveals footer on forward scroll', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(30, (_) => const SizedBox(height: 60)),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      // Collapse first.
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      // Then reveal.
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.forward,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 3. Reveals footer on scroll-end (idle) — primary UX safeguard
    // ------------------------------------------------------------------
    testWidgets('reveals footer on scroll-end notification', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(30, (_) => const SizedBox(height: 60)),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      // Collapse first.
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      // Reveal via scroll-end.
      _dispatch(
        ctx,
        ScrollEndNotification(metrics: _makeMetrics(), context: ctx),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 4. Header collapses when present; no header slot when null
    // ------------------------------------------------------------------
    testWidgets('collapses header+footer when header slot present', (
      tester,
    ) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            header: const Text('Header'),
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(30, (_) => const SizedBox(height: 60)),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final transitions = tester
          .widgetList<SizeTransition>(find.byType(SizeTransition))
          .toList();
      expect(transitions.length, 2); // header + footer
      for (final st in transitions) {
        expect(st.sizeFactor.value, closeTo(0.0, 0.01));
      }
    });

    testWidgets('no header SizeTransition when header is null', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(30, (_) => const SizedBox(height: 60)),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final transitions = tester
          .widgetList<SizeTransition>(find.byType(SizeTransition))
          .toList();
      expect(transitions.length, 1); // footer only
      expect(transitions.first.sizeFactor.value, closeTo(0.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 5. Respects the 6-pixel anti-flicker threshold (ScrollUpdateNotification)
    // ------------------------------------------------------------------
    testWidgets('respects 6-pixel anti-flicker threshold', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: List.generate(30, (_) => const SizedBox(height: 60)),
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      final metrics = _makeMetrics();

      // Two 3-px updates: accumulated = 6, not > 6, no collapse.
      _dispatch(
        ctx,
        ScrollUpdateNotification(
          metrics: metrics,
          context: ctx,
          scrollDelta: 3.0,
        ),
      );
      _dispatch(
        ctx,
        ScrollUpdateNotification(
          metrics: metrics,
          context: ctx,
          scrollDelta: 3.0,
        ),
      );
      await tester.pumpAndSettle();

      SizeTransition st =
          tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01)); // not collapsed

      // One 7-px update: accumulated = 13, > 6, collapse.
      _dispatch(
        ctx,
        ScrollUpdateNotification(
          metrics: metrics,
          context: ctx,
          scrollDelta: 7.0,
        ),
      );
      await tester.pumpAndSettle();

      st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(0.0, 0.01)); // collapsed
    });

    // ------------------------------------------------------------------
    // 6. Ignores notifications at depth != 0 (nested scrollable)
    // ------------------------------------------------------------------
    testWidgets('ignores nested scroll notifications (depth != 0)', (
      tester,
    ) async {
      final bodyKey = GlobalKey();
      final nestedKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => ListView(
                children: [
                  Builder(
                    key: nestedKey,
                    builder: (_) => const SizedBox(height: 200),
                  ),
                  ...List.generate(30, (_) => const SizedBox(height: 60)),
                ],
              ),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      // Dispatch from the nested Builder (inside the ListView viewport):
      // notification depth will be 1 as it passes through the outer viewport.
      final nestedCtx = tester.element(find.byKey(nestedKey));
      _dispatch(
        nestedCtx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: nestedCtx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01)); // not collapsed
    });

    // ------------------------------------------------------------------
    // 7. No-op when body has no overflow
    // ------------------------------------------------------------------
    testWidgets('is a no-op when body has no overflow', (tester) async {
      final bodyKey = GlobalKey();
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: Builder(
              key: bodyKey,
              builder: (ctx) => const SizedBox(height: 50),
            ),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));

      // Explicitly signal no overflow.
      _dispatch(
        ctx,
        ScrollMetricsNotification(
          metrics: _makeMetrics(maxScrollExtent: 0),
          context: ctx,
        ),
      );

      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(maxScrollExtent: 0),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 8. Suppresses collapse when keyboard is open
    // ------------------------------------------------------------------
    testWidgets('suppresses collapse when keyboard is open', (tester) async {
      final bodyKey = GlobalKey();

      // Scaffold strips viewInsets from its body's MediaQuery when
      // resizeToAvoidBottomInset is true (the default). Inject the override
      // *inside* the Scaffold body so CollapsingSheetScaffold sees it.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) =>
              FTheme(data: FTheme.neutral.dark.touch, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  viewInsets: const EdgeInsets.only(bottom: 300),
                ),
                child: CollapsingSheetScaffold(
                  body: Builder(
                    key: bodyKey,
                    builder: (ctx) => ListView(
                      children:
                          List.generate(30, (_) => const SizedBox(height: 60)),
                    ),
                  ),
                  footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 9. Disables collapse under reduced motion
    // ------------------------------------------------------------------
    testWidgets('disables collapse under reduced motion', (tester) async {
      final bodyKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) {
            return FTheme(
              data: FTheme.neutral.dark.touch,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            );
          },
          home: Scaffold(
            body: CollapsingSheetScaffold(
              body: Builder(
                key: bodyKey,
                builder: (ctx) => ListView(
                  children:
                      List.generate(30, (_) => const SizedBox(height: 60)),
                ),
              ),
              footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
            ),
          ),
        ),
      );
      await tester.pump();

      final ctx = tester.element(find.byKey(bodyKey));
      _dispatch(
        ctx,
        UserScrollNotification(
          metrics: _makeMetrics(),
          context: ctx,
          direction: ScrollDirection.reverse,
        ),
      );
      await tester.pumpAndSettle();

      final st = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(st.sizeFactor.value, closeTo(1.0, 0.01));
    });

    // ------------------------------------------------------------------
    // 10. Footer child is the untouched SheetFooter (safe-area preserved)
    // ------------------------------------------------------------------
    testWidgets('footer child is untouched SheetFooter without extra SafeArea',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          CollapsingSheetScaffold(
            body: const SizedBox.expand(),
            footer: SheetFooter(primaryLabel: 'Save', onPrimary: () {}),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SheetFooter), findsOneWidget);

      // The SizeTransition wrapping the footer must not insert an extra
      // SafeArea between itself and SheetFooter.
      final st = tester.widget<SizeTransition>(
        find.byType(SizeTransition),
      );
      final safeAreaBetween = find.descendant(
        of: find.byWidget(st),
        matching: find.byType(SafeArea),
      );
      expect(safeAreaBetween, findsNothing);
    });
  });
}
