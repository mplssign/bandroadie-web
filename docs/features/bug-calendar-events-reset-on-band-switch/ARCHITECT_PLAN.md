# ARCHITECT PLAN — Calendar events reset on band switch

## Feature Slug

`bug/calendar-events-reset-on-band-switch`

## Feature Title

Calendar "This Month's Events" list resets to current month after switching bands, while calendar grid keeps the selected month

---

## Problem Summary

**Reported (TestFlight, build 26091101, iOS 26.6.1):** On the Calendar screen the user
can navigate the calendar grid to a month other than the current real-world month
(e.g. September 2026 → November 2026). While that navigation stands, "This Month's
Events" below the grid correctly filters to the visible month. As soon as the user
switches the active band via the band switcher, the calendar grid **retains** the
previously navigated month (November 2026 in the reporter's screenshots) but the
events list **silently reverts** to the real-world current month (September 2026).
The two sources go out of sync only, and always, as a side effect of switching bands.
It reproduces on every band switch, regardless of which month was displayed.

Expected: after switching bands, the events list stays on whatever month the grid is
showing, scoped to the newly active band. Actual: grid keeps the month, events list
snaps back to `DateTime.now()`.

---

## Root Cause

**Confidence: HIGH — confirmed by direct code read this session.**

The Calendar screen has **two independent stores of "which month is being viewed"**:

1. **Widget-owned:** `FWheelCalendarController _calendarController` in the state of
   both [lib/features/calendar/calendar_screen.dart](lib/features/calendar/calendar_screen.dart#L67-L87)
   and [lib/features/calendar/calendar_tab_content.dart](lib/features/calendar/calendar_tab_content.dart#L54-L66).
   The controller lives on the `State` object; band-switching does not remount the
   widget, so the controller keeps its `currentMonth` value across band changes.
2. **Riverpod-owned:** `CalendarState.selectedMonth`, produced by
   [`CalendarNotifier.build()`](lib/features/calendar/calendar_controller.dart#L170-L192).
   `build()` opens with `final bandId = ref.watch(activeBandIdProvider);` — so any
   change to the active band re-runs `build()`, which unconditionally returns
   `CalendarState(selectedMonth: DateTime.now(), ...)` on both branches (the
   `bandId == null` guard and the normal path).

The two are wired together in one direction only, via a listener attached to the
widget controller:

```dart
// calendar_screen.dart:117-120 / calendar_tab_content.dart:93-96
void _syncMonthToRiverpod() {
  final newMonth = _calendarController.currentMonth;
  ref.read(calendarProvider.notifier).setSelectedMonth(newMonth);
}
```

That listener is attached to `_calendarController.day` and only fires when the day
changes inside the widget controller. A band switch does **not** change the widget
controller's day, so the listener does not run. Meanwhile `CalendarNotifier.build()`
has already reset `state.selectedMonth` to `DateTime.now()`.

Downstream, [`CalendarState.eventsForMonth`](lib/features/calendar/calendar_controller.dart#L42-L60)
filters `allEvents` by `state.selectedMonth`, and [`_EventsSection`](lib/features/calendar/calendar_screen.dart#L562-L581)
in the "This Month's Events" section reads exactly that field — so it renders the
real-world current month's events while the grid still displays the navigated month.

**Why this class of bug exists:** `CalendarNotifier` conflates two concerns:
band-scoped data (`allEvents`, `markers`, cache, loading/error) which correctly
should reset on band switch, and view state (`selectedMonth`) which should not.
Because both live in the same state object and `build()` returns a fresh state on
every band-id change, view state is collateral damage of a data refresh.

---

## Existing System Analysis

- `CalendarNotifier` is a `Notifier<CalendarState>` (not disposed on `ref.watch`
  changes — the instance is preserved; only `build()` re-runs, and its return value
  replaces `state`). Instance fields on the notifier therefore persist across
  band-switch rebuilds. The class already relies on this via the `static final
  Map<String, MonthData> _cache` field (line 171).
- `activeBandIdProvider` is a plain `Provider<String?>` derived from
  `activeBandProvider.activeBandId`; it fires on every active-band swap.
- `setSelectedMonth(DateTime month)` (lines 453-457) is the only public writer of
  `selectedMonth`. It normalizes to `DateTime(month.year, month.month)` and is
  called exclusively from the widget-controller listener.
- `reset()` (lines 459-464) is called only from `_signOut()` in
  [calendar_screen.dart line 155](lib/features/calendar/calendar_screen.dart#L155);
  its job is to clear both the cache and any lingering view state on sign-out. It
  currently rebuilds `CalendarState` with `selectedMonth: DateTime.now()`.
- Both `calendar_screen.dart` (standalone) and `calendar_tab_content.dart`
  (IndexedStack tab content in `AppShell`) consume the same `calendarProvider`, so
  a fix on the notifier applies to both entry points uniformly.
- The band-switch pattern in the codebase (`_handleBandSelected` in
  `calendar_screen.dart`, `home_screen.dart`, `setlists_screen.dart`,
  `app_shell.dart`) explicitly calls `resetForBandChange()` on `gigProvider` and
  `rehearsalProvider` to clear band-scoped caches. It does not call anything on
  `calendarProvider` — the calendar controller already reacts to
  `activeBandIdProvider` via `ref.watch` inside `build()`.

---

## Proposed Solution

Preserve `selectedMonth` as **view state** on the `CalendarNotifier` instance so it
survives `build()` re-runs, while band-scoped data (events/markers/loading/error)
continues to reset as it does today.

Concretely, in `lib/features/calendar/calendar_controller.dart`:

1. Add an instance field on `CalendarNotifier` that holds the currently-viewed
   month across `build()` invocations:
   ```dart
   DateTime _selectedMonth = _monthOf(DateTime.now());
   ```
   with a private static helper `_monthOf(DateTime d) => DateTime(d.year, d.month)`
   (or inlined).
2. In `build()`, return `CalendarState(selectedMonth: _selectedMonth, ...)` on
   both branches (the `bandId == null` guard and the normal path), instead of
   `DateTime.now()`.
3. In `setSelectedMonth`, update the instance field before assigning `state`:
   ```dart
   void setSelectedMonth(DateTime month) {
     _selectedMonth = DateTime(month.year, month.month);
     state = state.copyWith(selectedMonth: _selectedMonth);
   }
   ```
4. In `reset()`, reset the instance field alongside the state so sign-out cleanly
   returns to "now":
   ```dart
   void reset() {
     clearCache();
     _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
     state = CalendarState(selectedMonth: _selectedMonth);
   }
   ```

That is the entire behavioural change. No widget code changes. No changes in
`calendar_tab_content.dart` — it consumes the same provider and inherits the fix.
No new providers, controllers, repositories, or dependencies.

**Why this is the minimal correct fix, not a band-aid:**

- It matches the model the system already uses for the calendar grid: the grid's
  own controller is a per-widget-instance field that survives band switches, and
  we are giving the Riverpod side the same lifecycle for the same piece of state.
- It keeps a single source of truth (`_selectedMonth` on the notifier) that both
  the widget listener writes into and `build()` reads from. The two-store split
  was itself the bug.
- It uses the same instance-field-survives-rebuild pattern the class already uses
  for its `_cache` map, so it is idiomatic for this file.

**Alternatives considered and rejected:**

- **Extract `selectedMonth` into a separate `Notifier<DateTime>` provider that does
  not depend on `activeBandIdProvider`.** This is architecturally cleanest (clean
  separation of view state vs. band-scoped data) but requires updating every read
  site (`eventsForMonth`, `_buildDayWithMarkers` in `calendar_grid.dart`,
  `_EventsSection`, both consumer screens) and inventing a new provider. It is a
  refactor, not a fix. Guardrail: smallest change that fully solves the problem.
- **Add `ref.listen(activeBandIdProvider, ...)` in both consumer widgets to
  re-sync from `_calendarController.currentMonth` after band change.** This works
  but patches the symptom in two widget files, keeps the two-store split, and
  leaves a persistent race window between `build()` returning `DateTime.now()`
  and the listener firing — the events list would flash the wrong month.
- **Have the widget listener re-fire on band change (dispatch `setSelectedMonth`
  from a `ref.listen` on `activeBandIdProvider`).** Same objections as above, plus
  couples widget lifecycle to provider dependencies.

---

## Database Impact

n/a

---

## Flutter Architecture Changes

None. No new providers, controllers, notifiers, or repositories. The fix is an
internal state-preservation change on the existing `CalendarNotifier` and does not
alter the public API of the `calendarProvider` (`build()`, `setSelectedMonth`,
`reset`, `loadEvents`, `invalidateAndRefresh`, `invalidateCacheForBand`,
`getCachedMonth`, `clearCache` all keep their existing signatures and observable
behaviour except for the specific bug fix).

---

## Files to Create

- `test/features/calendar/calendar_selected_month_preservation_test.dart` — unit
  test asserting that `state.selectedMonth` survives a band switch. See
  Verification Plan for the exact test shape and the network-avoidance strategy.

---

## Files to Modify

- `lib/features/calendar/calendar_controller.dart` — the four localized changes
  described in "Proposed Solution": add `_selectedMonth` instance field on
  `CalendarNotifier`; replace `DateTime.now()` with `_selectedMonth` in both
  `build()` return branches; update `setSelectedMonth` to write the field before
  mutating `state`; update `reset()` to reset the field alongside `state`.

No other files require modification. `calendar_screen.dart` and
`calendar_tab_content.dart` continue to work unchanged because the widget
controllers already survive band switches — the fix aligns the Riverpod side with
the behaviour those widget controllers already have.

---

## Files Off-Limits

- `lib/features/calendar/calendar_screen.dart` — no widget-level workaround is
  needed once the notifier preserves `selectedMonth`; adding a `ref.listen` here
  is an alternative that was explicitly rejected above.
- `lib/features/calendar/calendar_tab_content.dart` — same reason.
- `lib/features/calendar/widgets/calendar_grid.dart` — consumes
  `calendarState.selectedMonth` read-only; fix is upstream.
- `lib/features/bands/active_band_controller.dart` — the trigger (band switch) is
  correct behaviour; the bug is entirely in how `CalendarNotifier` reacts to it.
- All other feature directories, migrations, edge functions, platform folders
  (`ios/`, `android/`, `macos/`), Supabase config.
- `pubspec.yaml` — no new dependencies.

---

## Change Budget

| Path | Expected net line delta |
| --- | --- |
| `lib/features/calendar/calendar_controller.dart` | +6 / -3 (net +3) |
| `test/features/calendar/calendar_selected_month_preservation_test.dart` | +~90 (new file) |

- Expected new files: 1 (the test file above).
- Expected new public classes/methods on production code: 0. The single new
  identifier is a library-private instance field `_selectedMonth` on
  `CalendarNotifier`.
- Expected new dependencies: 0.

---

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Gigs | Unaffected | `gigProvider` untouched; no change to gig data flow. |
| Rehearsals | Unaffected | `rehearsalProvider` untouched. |
| Setlists | Unaffected | No overlap with setlist state. |
| Members | Unaffected | No change to `membersProvider` wiring. |
| Auth | Unaffected | `reset()` is still called from `_signOut()`; behavioural change on sign-out is that `_selectedMonth` is explicitly reset to the current month (matching current behaviour). |
| Routing / Deep Links | Unaffected | No route changes. |
| Notifications | Unaffected | No overlap. |
| Platforms (iOS / Android / macOS / Web) | All affected identically | The fix is pure Dart-level state code with no platform-conditional paths. Reporter saw this on iOS; behaviour on other platforms is identical because `CalendarNotifier` and `activeBandProvider` are shared, so the same fix resolves all platforms in one change. |
| Init order | Unaffected | No changes touching `main.dart`, `WidgetsFlutterBinding`, Supabase init, Firebase init, `DeepLinkService`, `AppVersionService`, or URL strategy. |
| RLS / RPCs / migrations | Unaffected | No database work. |

---

## Regression Risk

**LOW.**

- Surface area is one method (`build()`) plus two writers (`setSelectedMonth`,
  `reset()`) on one notifier in one file.
- No behavioural change to band-scoped data flow: `allEvents`, `markers`,
  `isLoading`, `error`, and the `_loadEventsForBand` race guard all still operate
  as they do today.
- No change to `activeBandProvider` triggers or to any consumer of
  `calendarProvider` other than the initial value of `state.selectedMonth`.
- On very first `build()` (fresh app launch, no user navigation yet),
  `_selectedMonth`'s initializer produces `DateTime(now.year, now.month)` —
  identical to the current initial value.
- On sign-out, `reset()` continues to send the state back to the current month,
  matching current behaviour.
- The only observable change is exactly the bug being fixed: `state.selectedMonth`
  survives band switches instead of snapping back to `DateTime.now()`.

---

## Engineer Task Breakdown

1. In `lib/features/calendar/calendar_controller.dart`, inside the
   `CalendarNotifier` class, add one library-private instance field immediately
   below the existing `static final Map<String, MonthData> _cache = {};` line:

   ```dart
   // View state — the month the user is currently looking at. Instance-level so
   // it survives build() re-runs triggered by activeBandIdProvider changes
   // (band switches).
   DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
   ```

2. In the same class, edit `build()` so both return branches use `_selectedMonth`
   instead of `DateTime.now()`:

   ```dart
   @override
   CalendarState build() {
     final bandId = ref.watch(activeBandIdProvider);

     if (bandId == null || bandId.isEmpty) {
       return CalendarState(
         selectedMonth: _selectedMonth,
         error: 'No band selected',
       );
     }

     _loadEventsForBand(bandId);

     return CalendarState(
       selectedMonth: _selectedMonth,
       isLoading: true,
     );
   }
   ```

3. In the same class, edit `setSelectedMonth` to write the instance field before
   mutating `state`:

   ```dart
   void setSelectedMonth(DateTime month) {
     _selectedMonth = DateTime(month.year, month.month);
     state = state.copyWith(selectedMonth: _selectedMonth);
   }
   ```

4. In the same class, edit `reset()` to reset the field alongside the state so
   sign-out returns cleanly to the current month:

   ```dart
   void reset() {
     clearCache();
     _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
     state = CalendarState(selectedMonth: _selectedMonth);
   }
   ```

5. Create `test/features/calendar/calendar_selected_month_preservation_test.dart`
   as specified under Verification Plan → Tier 1 → new unit test.

That is the entire implementation scope. Do not touch other files.

---

## Verification Plan

**Tier 1 — QA gates (mechanically executable without a running app):**

1. `flutter analyze` — must pass clean; no new warnings.
2. `flutter test test/features/calendar/` — must pass; the existing
   `calendar_markers_test.dart` remains green (it does not touch
   `selectedMonth`) and the new preservation test (below) passes.
3. Diff verification: the change budget above must match reality within one line
   per file. If the diff is materially larger (extra fields, extra methods,
   widget edits), flag it — that is scope creep against this plan.

**New unit test — `test/features/calendar/calendar_selected_month_preservation_test.dart`:**

Model the existing pattern in
`test/features/bands/active_band_controller_invalidation_test.dart`:

- Seed two `Band` fixtures, `_band1` and `_band2`, and override
  `activeBandProvider` with a `_SeededActiveBandNotifier` subclass whose `build()`
  returns `ActiveBandState(userBands: [_band1, _band2], activeBand: _band1)`, so
  `selectBand()` succeeds without hitting Supabase.
- In `setUp`, call `SharedPreferences.setMockInitialValues({})` and
  `TestWidgetsFlutterBinding.ensureInitialized()`.
- Construct a `ProviderContainer` with the override, `addTearDown` its `dispose`.

Case A — `selectedMonth` survives a band switch:

- Read `calendarProvider` once so the notifier is materialized.
- Call `container.read(calendarProvider.notifier).setSelectedMonth(DateTime(2026, 11))`.
- Assert `container.read(calendarProvider).selectedMonth == DateTime(2026, 11)`.
- Call `await container.read(activeBandProvider.notifier).selectBand(_band2)`.
- Pump the microtask queue (`await Future<void>.delayed(Duration.zero)` or
  `await container.pump()` equivalent) to let `build()` re-run.
- Assert `container.read(calendarProvider).selectedMonth == DateTime(2026, 11)`
  — this is the regression assertion for the bug being fixed.

Case B — first-band-load default is still the current month (guard against
regression on fresh app launch):

- Fresh container; read `calendarProvider`.
- Assert `state.selectedMonth.year == DateTime.now().year &&
  state.selectedMonth.month == DateTime.now().month`.

Case C — `reset()` returns `selectedMonth` to the current month (guard sign-out
behaviour):

- Read `calendarProvider.notifier`, call `setSelectedMonth(DateTime(2026, 11))`.
- Call `notifier.reset()`.
- Assert `state.selectedMonth.year == DateTime.now().year &&
  state.selectedMonth.month == DateTime.now().month`.

**Network-avoidance note for Engineer:** `CalendarNotifier.build()` fires an
un-awaited `_loadEventsForBand(bandId)` that reaches `GigRepository`,
`RehearsalRepository`, and `BlockOutRepository` — all of which use the module-level
`supabase` singleton. In the test environment `Supabase` is not initialized, so
the repository call raises inside the notifier's own `try / catch` (see lines
209–298 of `calendar_controller.dart`); the exception is swallowed and `state`
ends with `error: 'Failed to load events: ...'`. `copyWith` preserves
`selectedMonth`, so all three assertions above still hold. If flutter_test's
zone flags the caught error, wrap the `container.read(activeBandProvider.notifier).selectBand(...)`
call in `await runZonedGuarded(...)` — but on inspection of the code, the
`try/catch` block wraps every awaited repository call, so this should not be
needed. Do **not** stub out repositories to reach this test; the point is to
verify state-preservation behaviour, and repository work is intentionally
irrelevant to what is asserted.

**Tier 2 — post-deploy checks:** n/a. This is a pure client-side fix; nothing
runs against the database, no Edge Function is deployed, no migration is applied.

**Owner-run PR-test punch list (Tony, on device — QA cannot execute these):**

QA hands this to Tony verbatim once Tier 1 passes.

1. Launch the app on iOS TestFlight build containing this fix; sign in.
   Expected: Calendar tab loads; grid shows the current real-world month
   (e.g. September 2026); "This Month's Events" shows the same month's events for
   the active band.
2. On the Calendar tab, in Band A, swipe or wheel-scroll the calendar grid
   forward two months (e.g. September 2026 → November 2026).
   Expected: grid now shows November 2026; "This Month's Events" heading and
   list content also show November 2026 for Band A.
3. Tap the band avatar to open the band switcher; select Band B.
   Expected: grid continues to display November 2026 (unchanged); "This Month's
   Events" **stays on November 2026** and now shows Band B's November 2026
   events (not September's). This is the regression this fix targets.
4. Open the band switcher again; select Band A.
   Expected: grid still on November 2026; events list still on November 2026,
   now showing Band A's November 2026 events again.
5. Swipe the grid back two months to September 2026.
   Expected: events list follows to September 2026.
6. Switch to Band B, then back to Band A.
   Expected: both grid and events list stay on September 2026 through both
   switches.
7. Sign out via the drawer, sign back in, open Calendar tab.
   Expected: fresh session opens on the current real-world month in both grid
   and events list.
8. Repeat steps 2–3 on Android and web (Vercel preview) if a TestFlight-like
   build is available for those platforms. Expected behaviour identical to iOS.

---

## QA Regression Areas

Beyond the Verification Plan, QA should confirm no unintended side effects in:

- The existing calendar marker test suite (`test/features/calendar/calendar_markers_test.dart`)
  — still passes unchanged.
- `test/features/bands/active_band_controller_invalidation_test.dart` and
  `test/features/bands/active_band_controller_circular_dependency_test.dart` —
  unaffected because the fix does not touch `activeBandProvider` or the
  band-scoped invalidation set.
- Any test that reads `calendarProvider.selectedMonth` in an initial-build
  assertion — Case B above guards this class of check.

If QA discovers a pre-existing test that asserts `state.selectedMonth ==
DateTime.now()` after a specific action, that test needs to be examined against
the new behaviour — but a workspace-wide grep for `selectedMonth` in `test/`
returns zero matches today, so this is a theoretical concern.

---

## Rollout Strategy

- Ship in a normal PR against `main`.
- No feature flag needed — behaviour is either always-on (fixed) or always-off
  (broken). Nothing to gate on.
- No migration, no Edge Function redeploy, no config change. The PR is
  code-only in `lib/` and `test/`.
- On merge, standard release train: Vercel picks up web on merge; iOS/Android
  ship in the next TestFlight/internal build.
- Rollback is a straight `git revert` of the PR — pure client-side change with
  no persisted state effect.

---

## Out of Scope

- Extracting `selectedMonth` into its own `Notifier<DateTime>` provider separate
  from `CalendarNotifier`. This is a cleaner architecture but a larger refactor;
  the guardrail is minimal safe fix.
- Adding a `resetForBandChange()` method on `CalendarNotifier` and calling it
  from `_handleBandSelected` in `calendar_screen.dart`, `home_screen.dart`,
  `setlists_screen.dart`, and `app_shell.dart` in parity with `gigProvider` and
  `rehearsalProvider`. This would explicitly signal band-scope refresh and remove
  the implicit dependency via `ref.watch(activeBandIdProvider)`. Reasonable
  future cleanup; not required to fix this bug.
- Fixing the fact that `calendar_screen.dart` and `calendar_tab_content.dart`
  duplicate the `_calendarController` + listener plumbing. Duplication predates
  this ticket and does not contribute to the bug.
- Any change to how "current month" is calculated in the presence of the user's
  timezone (the notifier uses `DateTime.now()` in the device's local zone, not
  the band's timezone). Same behaviour as today; not the reported symptom.
