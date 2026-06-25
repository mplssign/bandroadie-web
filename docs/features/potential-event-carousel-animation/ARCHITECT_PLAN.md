# Architect Plan: Carousel Animation on Multi-Date Potential Event Cards

## Feature Identifier

`feature/potential-event-carousel-animation`

## Problem Statement

When a user taps a chevron button (left or right) on a potential gig or rehearsal card that has multiple proposed dates, the date/time label changes instantly without visual continuity. This creates a jarring transition that doesn't communicate the navigation direction or the relationship between dates.

## Expected Behavior

- Tap **right chevron** → current label slides out to the **left**, next label slides in from the **right**
- Tap **left chevron** → current label slides out to the **right**, next label slides in from the **left**
- Duration: **250ms** (`AppDurations.normal`)
- Easing: `AppCurves.ease` (Curves.easeOutCubic)
- Only the date/time label animates — chevrons and availability buttons stay static

## Root Cause Analysis

### Current Implementation

Both `potential_gig_card.dart` and `rehearsal_card.dart` render the date label using plain `Text` widgets:

**PotentialGigCard (lines 344-361):**

```dart
Text(
  _formatFullDate(_currentDate),
  textAlign: TextAlign.center,
  style: GoogleFonts.dmSans(...),
),
```

**RehearsalCard (lines 372-387):**

```dart
Text(
  _formatDateWithRecurrence(),
  textAlign: TextAlign.center,
  style: GoogleFonts.dmSans(...),
),
```

When the user taps a chevron, `_currentDateIndex` updates via `setState()`, which causes `_currentDate` to change, and the `Text` widget rebuilds with the new value immediately. There is no transition animation.

**Root Cause Confidence:** HIGH (confirmed by direct code inspection)

## Architecture Questions Resolved

### 1. Is `AnimatedSwitcher` sufficient?

**Answer: YES.**

`AnimatedSwitcher` is the ideal solution for this use case. It:

- Automatically detects when its child changes (via key comparison)
- Supports custom transition builders for directional animations
- Fits cleanly into the existing widget structure without refactoring

The date labels are simple `Text` widgets, which are perfect candidates for `AnimatedSwitcher`. We'll wrap each label in an `AnimatedSwitcher` with a custom `SlideTransition` builder.

### 2. Is date label rendering shared or duplicated?

**Answer: Duplicated, but animation logic will be shared.**

Each card has its own formatter:

- **PotentialGigCard:** `_formatFullDate(_currentDate)` (simple date string)
- **RehearsalCard:** `_formatDateWithRecurrence()` (includes "Weekly starting..." prefix if recurring)

However, both render the result to a `Text` widget with similar styling. To avoid duplicating animation code, we'll create a **shared widget** `AnimatedDateLabel` that:

- Wraps `AnimatedSwitcher` with directional slide transitions
- Accepts the formatted date string and text style as parameters
- Handles the slide direction logic internally

This widget will be placed in `potential_gig_card.dart` (where the existing `_DateNavButton` and `_FullWidthAvailabilityButton` already live) and imported by `rehearsal_card.dart`.

### 3. Does `_currentDate` need a direction-aware key?

**Answer: YES.**

`AnimatedSwitcher` uses `Widget.key` to determine if a child has changed. Simply using the date as the key (e.g., `ValueKey(_currentDate)`) would work for date changes, but would not communicate animation direction.

To ensure the slide animates in the correct direction:

- Add a `_navigationDirection` state variable: `1` for forward (right chevron), `-1` for backward (left chevron)
- Use a composite key: `ValueKey('$_currentDate-$_navigationDirection')`
- Update `_navigationDirection` in the chevron tap handlers **before** updating `_currentDateIndex`

This ensures `AnimatedSwitcher` sees a new key on every navigation, even if the user navigates back to a previously viewed date.

## Implementation Plan

### Files to Modify

1. **`lib/features/home/widgets/potential_gig_card.dart`**
   - Add `int _navigationDirection = 1` state variable
   - Create `AnimatedDateLabel` widget (new, at bottom of file near other shared widgets)
   - Update chevron tap handlers to set `_navigationDirection` before updating `_currentDateIndex`
   - Replace the date `Text` widget with `AnimatedDateLabel`
   - Replace the time `Text` widget with `AnimatedDateLabel` (time also needs to animate)

2. **`lib/features/home/widgets/rehearsal_card.dart`**
   - Import `AnimatedDateLabel` from `potential_gig_card.dart`
   - Add `int _navigationDirection = 1` state variable
   - Update chevron tap handlers to set `_navigationDirection` before updating `_currentDateIndex`
   - Replace the date `Text` widget with `AnimatedDateLabel` in `_buildPotentialCard()`
   - Replace the time `Text` widget with `AnimatedDateLabel`

### Detailed Changes

#### 1. Create `AnimatedDateLabel` widget (potential_gig_card.dart)

Add this new widget at the bottom of the file, after `_FullWidthAvailabilityButton`:

```dart
/// Animated date label with horizontal slide transition.
/// Slides out to the left when navigating forward, right when navigating backward.
class AnimatedDateLabel extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int direction; // 1 = forward (slides in from right), -1 = backward (slides in from left)
  final int? maxLines;
  final TextOverflow? overflow;

  const AnimatedDateLabel({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.direction = 1,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppDurations.normal, // 250ms
      switchInCurve: AppCurves.ease,
      switchOutCurve: AppCurves.ease,
      transitionBuilder: (Widget child, Animation<double> animation) {
        // Slide direction based on navigation direction
        // Forward (direction=1): new slides in from right (1.0 → 0.0), old slides out to left (0.0 → -1.0)
        // Backward (direction=-1): new slides in from left (-1.0 → 0.0), old slides out to right (0.0 → 1.0)
        final offsetAnimation = Tween<Offset>(
          begin: Offset(direction.toDouble(), 0.0),
          end: Offset.zero,
        ).animate(animation);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      child: Text(
        text,
        key: ValueKey('$text-$direction'), // Unique key per text + direction
        textAlign: textAlign,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
```

#### 2. Update PotentialGigCard state (potential_gig_card.dart)

Add navigation direction tracking to the state class:

**After line 55** (after `Map<String?, bool> _savingInProgress = {};`):

```dart
/// Navigation direction: 1 = forward (right), -1 = backward (left)
int _navigationDirection = 1;
```

#### 3. Update chevron tap handlers (potential_gig_card.dart)

**Replace lines ~457-467** (the chevron `Row` in multi-date mode):

Change:

```dart
onTap: () => setState(() => _currentDateIndex--),
```

To:

```dart
onTap: () => setState(() {
  _navigationDirection = -1;
  _currentDateIndex--;
}),
```

Change:

```dart
onTap: () => setState(() => _currentDateIndex++),
```

To:

```dart
onTap: () => setState(() {
  _navigationDirection = 1;
  _currentDateIndex++;
}),
```

#### 4. Replace date/time rendering (potential_gig_card.dart)

**Replace lines ~344-361** (date Text widget):

Change:

```dart
Text(
  _formatFullDate(_currentDate),
  textAlign: TextAlign.center,
  style: GoogleFonts.dmSans(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.1,
  ),
),
```

To:

```dart
AnimatedDateLabel(
  text: _formatFullDate(_currentDate),
  direction: _navigationDirection,
  style: GoogleFonts.dmSans(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.1,
  ),
),
```

**Replace lines ~365-377** (time Text widget):

Change:

```dart
Text(
  TimeFormatter.formatRangeLocal(
    widget.gig.startTime,
    widget.gig.endTime,
    widget.gig.date,
    widget.bandTimezone,
  ),
  textAlign: TextAlign.center,
  style: GoogleFonts.dmSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.2,
  ),
),
```

To:

```dart
AnimatedDateLabel(
  text: TimeFormatter.formatRangeLocal(
    widget.gig.startTime,
    widget.gig.endTime,
    widget.gig.date,
    widget.bandTimezone,
  ),
  direction: _navigationDirection,
  style: GoogleFonts.dmSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.2,
  ),
),
```

#### 5. Update RehearsalCard state (rehearsal_card.dart)

**After the imports** (around line 11), add:

```dart
import 'potential_gig_card.dart' show AnimatedDateLabel;
```

**After line 71** (after `Map<String?, bool> _savingInProgress = {};`):

```dart
/// Navigation direction: 1 = forward (right), -1 = backward (left)
int _navigationDirection = 1;
```

#### 6. Update chevron tap handlers (rehearsal_card.dart)

**In the `_buildPotentialCard` method, around lines ~434-454** (the multi-date `Builder` with chevrons):

Change:

```dart
onTap: () => setState(() => _currentDateIndex--),
```

To:

```dart
onTap: () => setState(() {
  _navigationDirection = -1;
  _currentDateIndex--;
}),
```

Change:

```dart
onTap: () => setState(() => _currentDateIndex++),
```

To:

```dart
onTap: () => setState(() {
  _navigationDirection = 1;
  _currentDateIndex++;
}),
```

#### 7. Replace date/time rendering (rehearsal_card.dart)

**Replace lines ~372-387** (date Text widget in `_buildPotentialCard`):

Change:

```dart
Text(
  _formatDateWithRecurrence(),
  textAlign: TextAlign.center,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: GoogleFonts.dmSans(
    fontSize: widget.rehearsal.isRecurring &&
            widget.rehearsal.recurrenceFrequency != null
        ? 17
        : 21,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.1,
  ),
),
```

To:

```dart
AnimatedDateLabel(
  text: _formatDateWithRecurrence(),
  direction: _navigationDirection,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  style: GoogleFonts.dmSans(
    fontSize: widget.rehearsal.isRecurring &&
            widget.rehearsal.recurrenceFrequency != null
        ? 17
        : 21,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    height: 1.1,
  ),
),
```

**Replace lines ~391-401** (time Text widget in `_buildPotentialCard`):

Change:

```dart
Text(
  _formatTimeLine(widget.rehearsal),
  textAlign: TextAlign.center,
  style: GoogleFonts.dmSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.2,
  ),
),
```

To:

```dart
AnimatedDateLabel(
  text: _formatTimeLine(widget.rehearsal),
  direction: _navigationDirection,
  style: GoogleFonts.dmSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.2,
  ),
),
```

## System Impact Analysis

| System               | Impact                                                                                |
| -------------------- | ------------------------------------------------------------------------------------- |
| Gigs                 | **affected** — UI animation only, no data model or persistence changes                |
| Rehearsals           | **affected** — UI animation only, no data model or persistence changes                |
| Setlists / Catalog   | **unaffected**                                                                        |
| Members / RBAC       | **unaffected**                                                                        |
| Auth / Session       | **unaffected**                                                                        |
| Routing              | **unaffected**                                                                        |
| Keyboard Navigation  | **unaffected** — focus management and key handlers remain unchanged                   |
| Response Persistence | **unaffected** — `onRespondForDate` callbacks and optimistic state handling unchanged |

## Database Impact

**Not applicable.** This is a UI-only change. No database schema, RLS policies, RPCs, or triggers are affected.

## Risk Assessment

### Low Risk

- Animation is purely visual — no data flow changes
- Existing keyboard navigation and focus management are untouched
- Response handling (`_handleResponse`, `_savingInProgress`) is unaffected
- `AnimatedSwitcher` is a stable, well-tested Flutter widget
- Uses existing design tokens (`AppDurations.normal`, `AppCurves.ease`)
- No new dependencies

### Potential Issues

- **Performance:** `AnimatedSwitcher` creates a new widget tree on every transition. On low-end devices, this could cause brief frame drops if the card is very complex. **Mitigation:** The card content is already rendered; only the date/time labels animate. Minimal performance impact expected.
- **Accessibility:** Screen readers may announce date changes twice (once on exit, once on enter). **Mitigation:** `AnimatedSwitcher` uses `Semantics` appropriately. If this becomes an issue, we can wrap the `AnimatedDateLabel` in a `Semantics` widget with `excludeSemantics: true` on the exit animation.

## Validation Criteria

### Functional Tests (Manual)

1. **Forward navigation:**
   - Create a test gig with multiple dates (or use existing multi-date gig)
   - Tap right chevron
   - **Verify:** Current date slides out to the left, next date slides in from the right
   - **Verify:** Animation duration feels smooth (~250ms)
   - **Verify:** Time label also animates in sync with date

2. **Backward navigation:**
   - Tap left chevron
   - **Verify:** Current date slides out to the right, previous date slides in from the left
   - **Verify:** Animation direction is reversed from forward navigation

3. **Rapid navigation:**
   - Tap right chevron multiple times quickly
   - **Verify:** Animations queue properly, no visual glitches
   - **Verify:** Final displayed date is correct

4. **Keyboard navigation:**
   - Focus the right chevron (Tab key)
   - Press Enter or Space
   - **Verify:** Animation plays correctly
   - **Verify:** Focus remains on the chevron button

5. **Single-date cards:**
   - View a single-date potential gig or rehearsal
   - **Verify:** No chevrons displayed
   - **Verify:** Date/time labels render normally (no animation)

6. **Rehearsal recurrence label:**
   - Create a recurring rehearsal with multiple proposed dates
   - Navigate between dates
   - **Verify:** "Weekly starting..." prefix animates with the date

### Platform Testing

- **macOS:** Verify in desktop mode (current development platform)
- **Web:** Verify in Chrome/Safari
- **iOS/Android:** Verify on physical device (animation performance)

### Regression Tests

- **Response persistence:** Tap YES on date 1, navigate to date 2, navigate back to date 1 → YES should still be selected
- **Multi-date chip label:** "POTENTIAL GIG: Multiple Dates" should remain static during animation
- **Card press feedback:** Tapping the card body (not buttons) should still show scale-down animation
- **Loading states:** Tap YES, immediately tap chevron → loading indicator should remain visible until save completes

## Out of Scope

- No changes to date selection logic, persistence, or Supabase calls
- No changes to availability response handling (`_handleResponse`, `_savingInProgress`)
- No changes to keyboard focus behavior or tab order
- No changes to chevron button styling or layout
- No changes to the chip label ("POTENTIAL GIG: Multiple Dates")
- No animation on venue/location labels (these are gig-level properties, not date-specific)

## Dependencies

- None. Uses existing Flutter SDK widgets (`AnimatedSwitcher`, `SlideTransition`)
- No new packages required

## Design Tokens Used

- **Duration:** `AppDurations.normal` (250ms)
- **Curve:** `AppCurves.ease` (Curves.easeOutCubic)

These are already defined in `lib/app/theme/design_tokens.dart` and used throughout the app.

## Notes for Engineer

- The `AnimatedDateLabel` widget should be made public (no leading underscore) since it will be imported by `rehearsal_card.dart`
- The `ValueKey` must include both the text AND the direction to ensure `AnimatedSwitcher` triggers on every tap, even when navigating back to a previously viewed date
- Keyboard event handlers (`_handleKeyEvent`) should NOT set `_navigationDirection` — they already call `setState(() => _currentDateIndex++)` directly. Add the direction assignment to those `setState` blocks.
- The time label uses `TimeFormatter.formatRangeLocal()` which may return the same time for all dates (if the gig has a single time slot). The animation will still play because the key includes `_navigationDirection`.
- Do not animate the venue/location label. It is a gig-level property and does not change per date.

## Approval

**Architect:** AI Agent  
**Date:** 2026-06-24

This plan is approved for implementation.
