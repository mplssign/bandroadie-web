# ARCHITECT_PLAN.md

**Feature Identifier:** `feature/calendar-forui-wheel-grid`  
**Type:** feature  
**Branch:** `feature/calendar-forui-wheel-grid`  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-16

---

## Problem Statement

Replace the bespoke 705-line `calendar_grid.dart` (custom spring-physics swipe navigation, hand-painted day cells, prev/next-only month header) with Forui's native `FCalendar.wheel` to gain:

1. Full Forui theming and visual consistency
2. Tap-to-open month/year wheel picker for fast navigation (current implementation only supports prev/next stepping)
3. Native swipe animations and physics (replacing custom spring simulation)
4. Reduced maintenance surface (delegate calendar grid rendering to Forui)

**Acceptance:** Event markers (gig/green, rehearsal/blue, block-out/rose, potential/orange) remain visible and distinguishable per day. Tapping a day still opens `DayDetailBottomSheet`. Minor visual drift from Forui's native day-cell styling is acceptable (exact pixel-parity not required). Swipe gestures work on mobile; header arrows work on desktop (Web/macOS).

---

## Root Cause Analysis

**Current State:**  
`calendar_grid.dart` reimplements calendar grid functionality that Forui provides natively:

- Custom `GestureDetector` with `onHorizontalDrag*` handlers (~100 lines)
- Custom `SpringSimulation` animation for swipe transitions (~50 lines)
- Manual day-cell grid layout with `Row`/`Column` (~200 lines)
- Custom month header with prev/next arrows (~80 lines)
- No fast month/year picker (header only supports one-month-at-a-time stepping)

**Forui Capability:**  
`FCalendar.wheel` (version 0.25.0) provides:

- `FWheelCalendarController` with bounded date range (start/end), `currentMonth` property, `toggleMonthYearPicker()` method
- Built-in `dayBuilder` callback for custom per-day content (can render event markers via `CalendarState.getMarkers(date)`)
- Built-in `onDayPress` / `onDayLongPress` callbacks (no selection state required via `selectionControl: .none()`)
- Native swipe navigation via internal `PageView.builder` (mobile) with `onPrevious`/`onNext` header controls (desktop)
- Month/year wheel picker opened via header tap (fast navigation to any month/year within range)

**Gap:**  
Adopting Forui requires migrating navigation state ownership. Today, `calendarProvider`'s `CalendarNotifier` owns `selectedMonth` and exposes `previousMonth()`/`nextMonth()`/`goToToday()` methods. Forui's `FWheelCalendarController` owns month navigation internally (read-only `currentMonth` property, writable via `day.jumpTo(month)` or user gestures). Two options:

1. **Let Forui own navigation (recommended):** `FWheelCalendarController.currentMonth` is the source of truth. Riverpod's `selectedMonth` becomes derived/synced via controller listener (reactive). Programmatic navigation uses controller methods (`jumpToDayPicker`, `animateToDayPicker`).
2. **Drive Forui from Riverpod:** Attempt to keep `CalendarNotifier.selectedMonth` as source of truth and programmatically call `controller.day.jumpTo()` on every Riverpod state change. Awkward: Forui controller expects to own state, not be driven externally.

**Decision:** Option 1. Let `FWheelCalendarController` own month navigation. Sync `CalendarNotifier.selectedMonth` from controller listener for read-only purposes (e.g., filtering `eventsForMonth`). Remove `previousMonth()`/`nextMonth()`/`goToToday()` public API (navigation happens via Forui controller directly).

**Confidence:** HIGH (confirmed via installed package source at `~/.pub-cache/hosted/pub.dev/forui-0.25.0/`)

---

## Proposed Solution

### Phase 1: Extract CalendarColors Constants

**File:** Create `lib/features/calendar/calendar_colors.dart`

**Action:** Extract `CalendarColors` class from `calendar_grid.dart` (lines 23-37) to new file. Keep exact hex values (Figma-pinned):

- `gigIndicator` = `#65A30D`
- `rehearsalIndicator` = `#2563EB`
- `blockOutIndicator` = `#F43F5E`
- `potentialIndicator` = `#EA580C`

**Rationale:** `calendar_grid.dart` will be replaced; constants must persist. Single import point prevents duplication.

---

### Phase 2: Replace CalendarGrid with FCalendar.wheel

**File:** `lib/features/calendar/widgets/calendar_grid.dart`

**Current:**

```dart
class CalendarGrid extends StatefulWidget {
  final DateTime selectedMonth;
  final CalendarState calendarState;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final void Function(DateTime date)? onDayTap;
  // ... 705 lines of custom grid/swipe/animation
}
```

**New:**

```dart
class CalendarGrid extends StatefulWidget {
  final FWheelCalendarController controller;  // NEW: Forui controller
  final CalendarState calendarState;
  final void Function(DateTime date)? onDayTap;
  // Remove: selectedMonth, onPreviousMonth, onNextMonth (controller owns navigation)
}
```

**Implementation:**

1. **Initialize Forui controller in parent (see Phase 3)**, not in `CalendarGrid` state
2. **Render `FCalendar.wheel`:**
   ```dart
   FCalendar.wheel(
     control: FWheelCalendarControl(
       controller: widget.controller,  // Passed from parent
     ),
     selectionControl: FDateSelectionControl.none(),  // Display-only
     dayBuilder: _buildDayWithMarkers,
     onDayPress: (date) => widget.onDayTap?.call(date),
     fixedWeeks: false,  // Adaptive height (4-6 week rows)
     start: DateTime.utc(2020, 1, 1),  // Reasonable bounds
     end: DateTime.utc(2030, 12, 31),
   )
   ```
3. **Custom `dayBuilder`:**

   ```dart
   Widget _buildDayWithMarkers(
     BuildContext context,
     FCalendarDayStyles styles,
     FLocalizations localizations,
     DateTime date,
     Set<FCalendarDayVariant> variants,
   ) {
     final markers = widget.calendarState.getMarkers(date);
     final isToday = variants.contains(FCalendarDayVariant.today);
     final style = styles.resolve(variants);

     return DecoratedBox(
       decoration: style.background,  // Forui's base styling
       child: Column(
         children: [
           // Day number (use Forui's foreground/textStyle)
           DecoratedBox(
             decoration: style.foreground,
             child: Center(
               child: Text(
                 DateFormat.d(localizations.localeName).format(date),
                 style: style.textStyle,
               ),
             ),
           ),
           // Event marker stack (reuse logic from old _buildMarkerStack)
           _buildMarkerStack(markers, isToday, /* sortedEventTypes from calendarState */),
         ],
       ),
     );
   }
   ```

4. **Preserve marker rendering logic:** Extract `_buildGigMarker()`, `_buildRehearsalMarker()`, `_buildBlockOutMarker()`, `_buildPotentialMarker()` methods from current `_DayCell` class. Stack them in `_buildMarkerStack()` using `calendarState.eventsForDate(date)` to determine order (by start time, block-outs last).
5. **Delete:** All custom swipe handling (`_onHorizontalDrag*`, `_animateToOffset`, `_dragOffset`, `SpringSimulation`), custom month header (`_MonthHeader`), custom grid layout (`_CalendarDaysGrid`, `_DayCell`), custom day headers (`_DayHeaders` — Forui renders these).

**Lines Removed:** ~600 lines (custom swipe, animation, grid, header)  
**Lines Added:** ~150 lines (FCalendar.wheel setup, dayBuilder, marker stack)  
**Net:** ~450 lines removed

---

### Phase 3: Update CalendarScreen

**File:** `lib/features/calendar/calendar_screen.dart`

**Changes:**

1. **Create `FWheelCalendarController` in `_CalendarScreenState.initState()`:**

   ```dart
   late FWheelCalendarController _calendarController;

   @override
   void initState() {
     super.initState();
     _calendarController = FWheelCalendarController(
       initial: DateTime.now(),
       start: DateTime.utc(2020, 1, 1),
       end: DateTime.utc(2030, 12, 31),
     );
     _calendarController.day.addListener(_syncMonthToRiverpod);
   }

   void _syncMonthToRiverpod() {
     // Sync controller's month to Riverpod state (read-only)
     final newMonth = _calendarController.currentMonth;
     ref.read(calendarProvider.notifier).setSelectedMonth(newMonth);
   }

   @override
   void dispose() {
     _calendarController.day.removeListener(_syncMonthToRiverpod);
     _calendarController.dispose();
     super.dispose();
   }
   ```

2. **Pass `controller` to `CalendarGrid`:**
   ```dart
   CalendarGrid(
     controller: _calendarController,
     calendarState: calendarState,
     onDayTap: _handleDayTap,
     // Remove: selectedMonth, onPreviousMonth, onNextMonth
   )
   ```
3. **Remove references to:**
   ```dart
   // DELETE THESE LINES (~line 474-477):
   onPreviousMonth: () => ref.read(calendarProvider.notifier).previousMonth(),
   onNextMonth: () => ref.read(calendarProvider.notifier).nextMonth(),
   ```

**Lines Changed:** ~10 (remove 2 callback wires, add controller init/dispose/sync)

---

### Phase 4: Update CalendarTabContent

**File:** `lib/features/calendar/calendar_tab_content.dart`

**Changes:** Identical to Phase 3. Create `_calendarController` in `_CalendarTabContentState`, wire listener to sync `selectedMonth`, pass to `CalendarGrid`, remove prev/next callbacks.

**Lines Changed:** ~10

---

### Phase 5: Update CalendarNotifier

**File:** `lib/features/calendar/calendar_controller.dart`

**Changes:**

1. **Add `setSelectedMonth(DateTime month)` method:**
   ```dart
   void setSelectedMonth(DateTime month) {
     state = state.copyWith(
       selectedMonth: DateTime(month.year, month.month, 1),  // Normalize to first-of-month
     );
   }
   ```
2. **Mark as deprecated or remove (decision required):**

   ```dart
   // Option A: Mark deprecated (keep for programmatic control if needed later)
   @Deprecated('Use FWheelCalendarController.animateToDayPicker() instead')
   void previousMonth() { /* ... */ }

   @Deprecated('Use FWheelCalendarController.animateToDayPicker() instead')
   void nextMonth() { /* ... */ }

   @Deprecated('Use FWheelCalendarController.animateToDayPicker(DateTime.now()) instead')
   void goToToday() { /* ... */ }

   // Option B: Delete methods entirely (cleaner, but removes fallback)
   ```

**Recommendation:** Option B (delete). If programmatic navigation is needed later (e.g., "jump to today" button), use `_calendarController.animateToDayPicker(DateTime.now())` directly. No downstream code calls these methods outside `calendar_screen.dart` / `calendar_tab_content.dart` (confirmed via grep).

**Lines Changed:** ~5 (add setSelectedMonth, remove 3 methods)

---

### Phase 6: Update Imports

**Files:** `calendar_screen.dart`, `calendar_tab_content.dart`, `calendar_grid.dart`

**Add:**

```dart
import 'package:forui/forui.dart';
import 'package:bandroadie/features/calendar/calendar_colors.dart';  // New file
```

**Remove from `calendar_grid.dart`:**

```dart
import 'package:flutter/physics.dart';  // No longer using SpringSimulation
```

---

## Files Modified

| File                                               | Action      | Lines Changed | Description                                     |
| -------------------------------------------------- | ----------- | ------------- | ----------------------------------------------- |
| `lib/features/calendar/calendar_colors.dart`       | **Create**  | +40           | Extract CalendarColors constants                |
| `lib/features/calendar/widgets/calendar_grid.dart` | **Replace** | -600, +150    | Swap custom grid for FCalendar.wheel            |
| `lib/features/calendar/calendar_screen.dart`       | **Modify**  | ~10           | Add controller, remove prev/next callbacks      |
| `lib/features/calendar/calendar_tab_content.dart`  | **Modify**  | ~10           | Same as calendar_screen                         |
| `lib/features/calendar/calendar_controller.dart`   | **Modify**  | ~5            | Add setSelectedMonth, remove navigation methods |

**Total:** 5 files modified/created

---

## Database / RLS / RPC Impact

**Database:** Not applicable (UI-only change)  
**RLS Policies:** Not applicable  
**RPC Functions:** Not applicable  
**Supabase Migrations:** Not applicable

---

## System Impact Matrix

| System         | Impact                   | Rationale                                                                                |
| -------------- | ------------------------ | ---------------------------------------------------------------------------------------- |
| Calendar       | **Affected**             | Direct modification — calendar grid rendering and navigation state ownership             |
| Gigs           | **Unaffected**           | CalendarGrid consumes `CalendarState.getMarkers()` and `eventsForDate()` — API unchanged |
| Rehearsals     | **Unaffected**           | Same as Gigs                                                                             |
| Block Outs     | **Unaffected**           | Same as Gigs                                                                             |
| Members / RBAC | **Unaffected**           | Calendar screen RBAC logic (`canCreateGigs`) unmodified                                  |
| Auth / Session | **Unaffected**           | No auth flow changes                                                                     |
| Routing        | **Unaffected**           | No route changes                                                                         |
| Setlists       | **Unaffected**           | No shared state                                                                          |
| Theming        | **Potentially affected** | FCalendar.wheel uses Forui theme — verify rose accent and dark mode apply correctly      |

---

## Platform-Specific Considerations

| Platform    | Behavior                                                             | Fallback Required?                |
| ----------- | -------------------------------------------------------------------- | --------------------------------- |
| **iOS**     | Native swipe gestures via PageView.builder                           | No                                |
| **Android** | Native swipe gestures via PageView.builder                           | No                                |
| **Web**     | Mouse drag may not trigger swipe; header prev/next arrows functional | No (Forui header provides arrows) |
| **macOS**   | Trackpad swipe may work; header arrows functional                    | No                                |

**Verification:** Test swipe on iOS/Android physical device, verify header arrows work on Web/macOS desktop.

---

## Testing Requirements

### Functional Tests

1. **Month navigation:**
   - Swipe left/right on mobile (iOS/Android) advances/retreats month
   - Header prev/next arrows advance/retreat month on all platforms
   - Tapping month/year header opens wheel picker
   - Selecting month/year in wheel picker updates day grid
2. **Event markers:**
   - Days with gigs show green marker
   - Days with rehearsals show blue marker
   - Days with block-outs show rose marker (split into segments if multiple members)
   - Days with potential gigs/rehearsals show orange marker (deduplicated if both types on same day)
   - Marker stacking order matches start time (earliest event first, block-outs last)
3. **Day tap:**
   - Tapping a day with events opens `DayDetailBottomSheet`
   - Tapping a day without events opens `DayDetailBottomSheet` with empty state (or add-event prompt if permitted)
4. **Today indicator:**
   - Current day highlighted with rose background and white text
5. **Band switching:**
   - Switching bands reloads events correctly (existing `activeBandProvider` listener unchanged)

### Visual Regression

1. **Forui theming:**
   - Day grid uses dark mode colors from `context.colors`
   - Rose accent (`AppColors.primary`) applies to today cell
   - Header month/year text uses `AppTextStyles.headline`
2. **Event markers:**
   - Marker colors match CalendarColors constants (no drift)
   - Marker size/spacing acceptable (minor drift from current 35px width × 3px height × 2px gap is OK)
   - Block-out segment splitting renders correctly for 1, 2, 3+ members

### Platform Tests

1. **Mobile (iOS/Android):**
   - Swipe gestures smooth, no jank
   - Wheel picker opens via header tap, scrolls smoothly
2. **Desktop (Web/macOS):**
   - Header arrows functional
   - Wheel picker opens and scrolls via mouse/trackpad
   - No console errors related to touch events

### Edge Cases

1. **Month boundaries:**
   - Events spanning multiple days (block-outs) render markers on all affected days
   - Swiping to a month with no events shows empty grid (no crash)
2. **Date range bounds:**
   - Cannot swipe/navigate before 2020-01-01 or after 2030-12-31 (Forui enforces via `start`/`end`)
3. **Rapid navigation:**
   - Rapidly swiping months does not desync Riverpod `selectedMonth` from controller state

---

## Rollback Plan

If QA fails or critical visual regression detected:

1. **Git revert:** Single commit revert restores `calendar_grid.dart` and removes Forui integration
2. **No database rollback required** (UI-only change)
3. **No migration rollback required**

---

## Success Criteria

- [ ] `flutter analyze` passes with 0 errors
- [ ] All existing calendar functionality works (day tap, event markers, band switching)
- [ ] Month/year wheel picker opens via header tap and navigates correctly
- [ ] Swipe gestures work on mobile (iOS/Android)
- [ ] Header arrows work on all platforms
- [ ] Event marker colors match `CalendarColors` constants (green/blue/rose/orange)
- [ ] Today cell highlighted correctly (rose background, white text)
- [ ] No console errors or visual regressions on Web
- [ ] QA verdict: **APPROVED**

---

## Additional Context

**Forui Version:** 0.25.0 (installed via `pubspec.yaml` line 17, confirmed via `pubspec.lock` line 450)  
**Package Source:** Verified via local cache at `~/.pub-cache/hosted/pub.dev/forui-0.25.0/lib/src/widgets/calendar/`  
**Web Docs Reference:** https://forui.dev/docs/widgets/data/calendar#month-year-wheel (client-rendered, used as guidance only — installed package source is ground truth)

**Known Limitations:**

- Forui's `dayBuilder` receives a `Set<FCalendarDayVariant>` for styling variants (today, selected, disabled, etc.). Current implementation does not use selection state, so only `today` variant is relevant.
- Marker rendering logic must fit within Forui's day cell layout constraints (likely ~40px × 40px cell + space below for markers). If markers don't fit, reduce marker count or size (acceptable per Tony's guidance).
- `FWheelCalendarController.currentMonth` is read-only — to programmatically navigate, use `controller.animateToDayPicker(targetMonth)` or `controller.jumpToDayPicker(targetMonth)`.

**Design Decision Record:**  
Navigation state ownership transferred from `CalendarNotifier` to `FWheelCalendarController`. Riverpod `selectedMonth` becomes derived (synced via listener) rather than authoritative. Programmatic navigation (if needed) uses controller methods, not Riverpod actions.

---

**Architect Sign-Off:** Ready for implementation.  
**Next Step:** Engineer implements per this plan, produces `ENGINEER_REPORT.md` and `git diff`.
