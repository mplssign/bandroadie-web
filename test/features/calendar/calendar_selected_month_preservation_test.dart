// Verifies CalendarNotifier.selectedMonth survives a band switch instead of
// resetting to DateTime.now() (see ARCHITECT_PLAN.md for
// bug/calendar-events-reset-on-band-switch). CalendarNotifier.build() fires an
// un-awaited _loadEventsForBand(bandId) call that reaches Supabase-backed
// repositories; Supabase is not initialized in this test environment, so that
// call throws inside the notifier's own try/catch and state ends with a
// 'Failed to load events: ...' error. copyWith preserves selectedMonth, so
// that swallowed error does not affect the assertions below — repository
// behavior is intentionally irrelevant to what this test verifies.
//
// The first repository future to reject leaves its unawaited siblings
// (created eagerly before any await) without an error handler; those surface
// as zone-level uncaught errors on the next microtask. _guarded() runs the
// build-triggering call inside runZonedGuarded so those expected echoes don't
// fail the test.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';
import 'package:bandroadie/features/calendar/calendar_controller.dart';

Future<T> _guarded<T>(T Function() body) {
  final completer = Completer<T>();
  runZonedGuarded(() {
    completer.complete(body());
  }, (error, stack) {
    // Expected: orphaned sibling repository futures rejecting because
    // Supabase isn't initialized in tests. See file header.
  });
  return completer.future;
}

final _band1 = Band(
  id: 'test-band-1',
  name: 'Band One',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

final _band2 = Band(
  id: 'test-band-2',
  name: 'Band Two',
  createdAt: DateTime(2024),
  updatedAt: DateTime(2024),
);

class _SeededActiveBandNotifier extends ActiveBandNotifier {
  @override
  ActiveBandState build() => ActiveBandState(
        userBands: [_band1, _band2],
        activeBand: _band1,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarNotifier preserves selectedMonth across band switches', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer(
        overrides: [
          activeBandProvider.overrideWith(_SeededActiveBandNotifier.new),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('selectedMonth survives a band switch', () async {
      await _guarded(() => container.read(calendarProvider));
      await Future<void>.delayed(Duration.zero);

      container
          .read(calendarProvider.notifier)
          .setSelectedMonth(DateTime(2026, 11));
      expect(
        container.read(calendarProvider).selectedMonth,
        DateTime(2026, 11),
      );

      await _guarded(
        () => container.read(activeBandProvider.notifier).selectBand(_band2),
      );
      await Future<void>.delayed(Duration.zero);

      // NotifierProvider rebuilds are pull-based: selectBand() only
      // invalidates calendarProvider, and build() actually re-runs here, on
      // the next read — so this read must stay inside the zone guard too.
      final state = await _guarded(() => container.read(calendarProvider));
      await Future<void>.delayed(Duration.zero);

      expect(state.selectedMonth, DateTime(2026, 11));
    });

    test('first-band-load default is the current month', () async {
      final state = await _guarded(() => container.read(calendarProvider));
      await Future<void>.delayed(Duration.zero);
      final now = DateTime.now();

      expect(state.selectedMonth.year, now.year);
      expect(state.selectedMonth.month, now.month);
    });

    test('reset() returns selectedMonth to the current month', () async {
      await _guarded(() => container.read(calendarProvider));
      await Future<void>.delayed(Duration.zero);

      final notifier = container.read(calendarProvider.notifier);
      notifier.setSelectedMonth(DateTime(2026, 11));

      notifier.reset();

      final state = container.read(calendarProvider);
      final now = DateTime.now();

      expect(state.selectedMonth.year, now.year);
      expect(state.selectedMonth.month, now.month);
    });
  });
}
