# Calendar FCalendar.wheel Implementation — Amendment 2: Height Fix & Today Border

**Amendment Date:** 2026-08-16 (Revised 2026-08-16)  
**Amendment Author:** Architect  
**Trigger:** On-device screenshot from Tony (phone-width viewport, portrait) shows the calendar card is now too tall: the month/year header and weekday-label row (Su/Mo/Tu...) have scrolled above the visible viewport, and "This Month's Events" is barely visible at the bottom even after scrolling. Tony wants to see the top portion of the first "This Month's Events" card without excessive scrolling. The full-width responsive fix from Amendment 1 is otherwise working correctly (no gutters, day borders visible in screenshot).

**Status:** ✅ **READY FOR IMPLEMENTATION** — Two changes finalized: (1) Reduce calendar height by ~35px via daySize.height formula adjustment (2) Apply rose border to current day's cell.

---

## Investigation Summary: Calendar Component Height Analysis

### Investigation History & Resolution

**Initial Approach:**  
Original analysis calculated calendar component height difference as ~40px and proposed reducing `daySize.height` formula from `cellWidth + 16` to `cellWidth + 11` (saving ~35px).

**Apparent Discrepancy (Screenshot Evidence):**  
Second screenshot from Tony appeared to show ~300–400px of content scrolled out of view, vastly exceeding the 35-40px height reduction proposed. This triggered concerns that the calendar component measurement was incomplete or that external layout factors (AppBar, SafeArea, ScrollView positioning) were the primary culprits.

**Rigorous Remeasurement:**  
Architect re-measured both implementations line-by-line from source code and confirmed:

- **Original calendar:** 474px total height
- **Current FCalendar.wheel:** 511px total height
- **Real difference:** 37px (not 300-400px)

**Resolution:**  
Tony confirmed the apparent 300-400px gap was **scroll position at the moment the screenshot was taken** — he had scrolled down before capturing the image. This was not a layout discrepancy but user interaction state. The rigorous measurement (511px vs 474px = 37px excess) is correct and sufficient.

**Conclusion:**  
The originally-proposed fix (reduce `daySize.height` formula by 5px, saving ~35px) now closely matches the actual measured excess (37px) and is adequate to restore the original calendar height. No further investigation into AppBar/SafeArea/ScrollView is needed.

---

## Measured Calendar Component Heights (Corrected Analysis)

### Current Forui FCalendar.wheel Implementation

**Measured on 375px-wide phone viewport (touch platform):**

**Source tracing:** `~/.pub-cache/hosted/pub.dev/forui-0.25.0/lib/src/widgets/calendar/`

1. **Container padding** (`calendar.dart` L507):
   - `EdgeInsets.all(12)` (default)
   - **Vertical contribution:** 12px top + 12px bottom = **24px**

2. **Header Row** (`header.dart` L162-186):
   - `Padding(padding: style.padding)` wraps Row (style.padding defaults to `EdgeInsets.zero`)
   - Row contains:
     - `_Tappable` (month/year text + toggle icon): ~32px (text 20-24px + tappablePadding 8px vertical)
     - `FButton.icon` (prev button): **44px** (minHeight constraint from `button.dart` L516)
     - `FButton.icon` (next button): **44px**
   - **Row height:** max(32px, 44px, 44px) = **44px**

3. **Header spacing** (`day_picker.design.dart` L21):
   - `headerSpacing: 0` (default)
   - **0px**

4. **Day grid** (`calendar_grid.dart` L43-51 + `day_picker.dart` L333-338):
   - Available width: 375px (viewport) - 32px (pagePadding) - 24px (FCalendar padding) = 319px
   - Cell width: 319px / 7 = **45.57px**
   - Cell height (Amendment 1 formula): **cellWidth + 16 = 61.57px**
   - Grid structure: 1 weekday row + 6 day rows = 7 total rows
   - Row spacing (`day_picker.dart` L452): `daySpacing = 2` (default)
   - **Day grid total:** (7 rows × 61.57px) + (6 gaps × 2px) = 430.99 + 12 = **443px**

**Total Forui calendar height:**

```
12px   (top padding)
44px   (header row)
0px    (headerSpacing)
443px  (day grid: weekday + 6 day rows + spacing)
12px   (bottom padding)
────────────────────────────
511px  TOTAL
```

---

### Original Bespoke Calendar Implementation

**Source:** `git show main:lib/features/calendar/widgets/calendar_grid.dart`

1. **Container padding:**
   - `EdgeInsets.all(Spacing.space16)` = 16px on all sides
   - **Vertical contribution:** 16px top + 16px bottom = **32px**

2. **\_MonthHeader:**
   - Simple `Row` with `Icon(size: 24)` wrapped in `Padding(8px all sides)`
   - Icon button height: 24px + 16px padding = **40px**

3. **Spacing:** `SizedBox(height: Spacing.space16)` = **16px**

4. **\_DayHeaders:**
   - Text widgets in `SizedBox(width: 40)` (no explicit height)
   - Natural text height: **~22px** (AppTextStyles.callout with 16px font size)

5. **Spacing:** `SizedBox(height: Spacing.space8)` = **8px**

6. **\_CalendarDaysGrid:**
   - Day cells: `SizedBox(width: 40, height: 56)` = **56px per row**
   - 6 rows: 6 × 56px = **336px**
   - Row spacing: `SizedBox(height: Spacing.space4)` × 5 gaps = **20px**
   - **Grid total:** 336 + 20 = **356px**

**Total original calendar height:**

```
16px   (top padding)
40px   (month header)
16px   (spacing)
22px   (day headers)
8px    (spacing)
356px  (day grid: 6 rows + spacing)
16px   (bottom padding)
────────────────────────────
474px  TOTAL
```

---

### Height Difference Breakdown

| Component         | Original    | Current (Forui) | Difference   |
| ----------------- | ----------- | --------------- | ------------ |
| Top padding       | 16px        | 12px            | **-4px**     |
| Header row        | 40px        | 44px            | **+4px**     |
| Spacing           | 16px        | 0px             | **-16px**    |
| Weekday row       | 22px        | 61.57px         | **+39.57px** |
| Spacing           | 8px         | _(in grid)_     | **-8px**     |
| Day grid (6 rows) | 356px       | 369.42px        | **+13.42px** |
| Row spacing       | _(in grid)_ | 12px            | **+12px**    |
| Bottom padding    | 16px        | 12px            | **-4px**     |
| **TOTAL**         | **474px**   | **511px**       | **+37px**    |

**Calendar component is 7.8% taller, not 60-80% taller as screenshot evidence suggests.**

---

## Proposed Changes

### Change 1: Reduce Calendar Height by ~35px

**File:** `lib/features/calendar/widgets/calendar_grid.dart`  
**Line:** 42 (in LayoutBuilder callback)

**Current Code:**

```dart
// Cell height needs room for: day number + 2px gap + 14px marker area
// Use cellWidth + 16 to provide adequate vertical space (not strictly square)
final daySize = Size(cellWidth, cellWidth + 16);
```

**Proposed Code:**

```dart
// Cell height needs room for: day number + 2px gap + 14px marker area
// Use cellWidth + 11 to match original calendar height (~474px total)
final daySize = Size(cellWidth, cellWidth + 11);
```

**Rationale:**

- Original calendar total height: **474px**
- Current FCalendar.wheel height: **511px** (37px excess)
- This formula change reduces day grid height by ~5px per row × 7 rows = **~35px total**
- Final height: **~476px** (within 2px of original)
- Restores ability to see "This Month's Events" without excessive scrolling

**Impact:**

- Day cells remain touch-friendly (still >45px tall on phone)
- Event markers (14px) still have adequate spacing
- No impact on horizontal layout, gutters, or borders

**Confidence:** **HIGH** — Measured height difference (37px) closely matches proposed fix (~35px). Scroll position confusion resolved.

---

### Change 2: Apply Rose Border to Current Day

**File:** `lib/features/calendar/widgets/calendar_grid.dart`  
**Lines:** 48–64 (within LayoutBuilder callback, customStyle definition)

**Current Code:**

```dart
// Build custom style with computed daySize and day cell borders
final customStyle = FCalendarStyleDelta.delta(
  dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
    daySize: daySize,
    dayStyles: FVariantsDelta.delta([
      FVariantOperation.all(
        FCalendarDayStyleDelta.delta(
          background: DecorationDelta.boxDelta(
            border: Border.all(
              color: context.theme.colors.border,
              width: 1,
            ),
          ),
        ),
      ),
    ]),
  ),
);
```

**Proposed Code:**

```dart
// Build custom style with computed daySize and day cell borders
final customStyle = FCalendarStyleDelta.delta(
  dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
    daySize: daySize,
    dayStyles: FVariantsDelta.delta([
      // Apply neutral border to all day cells
      FVariantOperation.all(
        FCalendarDayStyleDelta.delta(
          background: DecorationDelta.boxDelta(
            border: Border.all(
              color: context.theme.colors.border,
              width: 1,
            ),
          ),
        ),
      ),
      // Override with rose border for today specifically
      FVariantOperation.exact(
        {.today},
        FCalendarDayStyleDelta.delta(
          background: DecorationDelta.boxDelta(
            border: Border.all(
              color: AppColors.primary, // rose #F43F5E
              width: 1,
            ),
          ),
        ),
      ),
    ]),
  ),
);
```

**Import Required:**

```dart
import 'package:bandroadie/app/theme/design_tokens.dart'; // For AppColors.primary
```

**API Reference:**  
Source: `~/.pub-cache/hosted/pub.dev/forui-0.25.0/lib/src/theme/variants.dart` L320–335

````dart
/// Applies [delta] to the base and associates the result with each constraint
/// in [constraints].
///
/// Unlike [FVariantOperation.match], this creates exact entries rather than
/// matching existing variants.
///
/// ```dart
/// // Given base: 0, {a: 1, b: 1}
/// .exact({b, c}, AddDelta(2)) // {a: 1, b: 3, c: 2}
/// ```
FVariantOperation.exact(Set<K> constraints, D delta)
````

**Rationale:**

- Amendment 1 applied `context.theme.colors.border` (neutral) uniformly to all day cells via `FVariantOperation.all(...)`
- User request: Current day should have a rose border (`AppColors.primary`, #F43F5E) to visually distinguish it
- `FVariantOperation.exact({.today}, delta)` targets only the `.today` variant, leaving all other cells (`.disabled`, `.selected`, base) with neutral borders
- Delta operations are applied sequentially: `.all(...)` sets the base, `.exact(...)` overrides only the today variant

**Impact:**

- Current day's cell gets a 1px rose border (`#F43F5E`)
- All other days retain the 1px neutral border from `.all()` operation
- No changes to background colors, text styles, or marker rendering
- Aligns with BandRoadie brand identity (rose accent throughout app)

**Confidence:** **HIGH** — API method (`FVariantOperation.exact`) confirmed from installed package source. Variant constraint `.today` is a standard forui calendar variant (tier 2 semantic variant, similar to `.disabled`, `.selected`).

---

## Implementation Notes for Engineer

**Testing Checklist:**

1. **Height verification (Change 1):**
   - Run on phone-width viewport (375px) in portrait
   - Verify calendar header, weekday row, and all 6 day rows are visible without scrolling
   - Verify top portion of first "This Month's Events" card is visible below the calendar
   - Compare with original screenshot from `main` branch

2. **Today border verification (Change 2):**
   - Run on any device/viewport
   - Verify current day's cell has a 1px rose border (`#F43F5E`)
   - Verify all other days (past, future, disabled, selected) have neutral gray borders
   - Verify no regression to background colors or event markers

3. **Cross-platform (both changes):**
   - Test on iOS, Android, Web (phone-width)
   - Verify touch targets remain >44px (accessibility)
   - Verify borders are visible on all platforms (no anti-aliasing issues)

**No database changes required.**  
**No new dependencies required** (AppColors.primary already exists in design_tokens.dart).
