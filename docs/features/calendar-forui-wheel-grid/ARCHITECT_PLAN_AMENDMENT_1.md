# Calendar FCalendar.wheel Implementation — Amendment 1: Responsive Grid + Day Cell Outlines

**Amendment Date:** 2026-08-16  
**Amendment Author:** Architect  
**Trigger:** Visual regression identified during on-device review (screenshot feedback from Tony). Base feature is implemented on disk and passes analyzer but **not yet committed or pushed** — this amendment lands before any of it ships, so it modifies the working tree directly rather than reopening a merged feature.

---

## What's Changing and Why

### 1. Calendar day grid must expand responsively to fill container width

**Current behavior:** The day grid renders at a fixed width determined by `FCalendarDayPickerStyle.daySize` (default: `Size(44, 44)` on desktop/web, `Size(32, 32)` on mobile), resulting in a constant grid width of `7 × daySize.width`. When the container is wider than this fixed width, visible gutters appear on either side — the grid is horizontally centered but does not fill the available space.

**Expected behavior:** The day grid should expand to fill the horizontal space within its container (minus any intentional padding), making efficient use of screen real estate on larger devices (iPad landscape, desktop browser windows).

**Why this matters:** A fixed-width grid that doesn't adapt to container width wastes horizontal space and creates visual asymmetry on wide screens. Responsive sizing is a baseline expectation for modern calendar UIs, especially in a cross-platform Flutter app targeting mobile, tablet, desktop, and web.

### 2. Day cells should support visual outline/border

**Current behavior:** Day cells have no border or outline. The only visual distinction between days is the `today` variant (rose background, white text).

**Expected behavior:** Day cells should have a subtle border to visually separate them in the grid, improving scannability and making the grid structure more explicit.

**Why this matters:** Without cell borders, the day grid can appear as a floating cloud of numbers on high-contrast backgrounds or when event markers are sparse. A subtle outline provides grid definition without visual noise.

---

## Existing System State (post base-feature, pre-amendment)

Confirmed by reading the current working-tree files and the installed Forui package source (`~/.pub-cache/hosted/pub.dev/forui-0.25.0/`):

### Current Implementation (calendar_grid.dart)

- `CalendarGrid` is a `StatelessWidget` that renders `FCalendar.wheel` with a custom `dayBuilder` for event markers
- `dayBuilder` receives `FCalendarDayStyles`, resolves the style for the current day's variants, and renders a `DecoratedBox` with `style.background` wrapping the day number + event marker stack
- Event markers (`_buildGigMarker`, `_buildRehearsalMarker`, `_buildPotentialMarker`, `_buildBlockOutMarker`) are hardcoded to `width: 35` pixels, sized to fit within a ~40px cell width (the approximate default for `FSizes.calendar` on desktop)
- No `LayoutBuilder` or responsive sizing logic exists — `FCalendar.wheel` is instantiated without a custom `style` parameter, so it uses Forui's default `FCalendarStyle` with fixed `daySize`

### Forui API (confirmed via package source)

**FCalendar.wheel constructor:**

```dart
FCalendar.wheel({
  FCalendarStyleDelta style = const .context(),  // ← accepts style customization
  // ... other params
})
```

**FCalendarStyle structure:**

```dart
FCalendarStyleDelta.delta({
  FCalendarHeaderStyleDelta? headerStyle,
  FCalendarDayPickerStyleDelta? dayPickerStyle,  // ← contains daySize
  EdgeInsetsGeometryDelta? padding,              // ← defaults to EdgeInsets.all(12)
  // ... other style components
})
```

**FCalendarDayPickerStyle:**

- `daySize`: `Size` (fixed dimensions for each day cell, default `Size(FSizes.calendar, FSizes.calendar)` where `FSizes.calendar` = 44 on desktop, 32 on mobile)
- `daySpacing`: `double` (vertical spacing between day rows)
- `dayStyles`: `FCalendarDayStyles` (variant-based styling for day cells via `FVariantsDelta`)

**FCalendarDayStyle:**

- `background`: `Decoration` (painted behind the day content)
- `foreground`: `Decoration` (painted in front of the background)
- `textStyle`: `TextStyle` (day number text style)

**Day grid width calculation (observed in `day_picker.dart`):**

```dart
final size = style.daySize;
final width = DateTime.daysPerWeek * size.width;  // 7 × daySize.width = fixed grid width
```

This fixed width is then used to size the day grid container, which is horizontally centered within its parent. No responsive stretching occurs.

**FCalendarStyle.padding default:**  
`EdgeInsets.all(12)` (confirmed by Tony's package research) — this padding is applied around the header + picker as a whole, inside the `FCalendar` widget.

### Current Container Context (calendar_screen.dart & calendar_tab_content.dart)

Both files wrap `CalendarGrid` in a `SingleChildScrollView` with:

```dart
padding: const EdgeInsets.symmetric(horizontal: Spacing.pagePadding)  // 16px
```

So the current padding stack is:

- **App's wrapper:** 16px left/right (`Spacing.pagePadding`)
- **FCalendar's internal padding:** 12px on all sides (`FCalendarStyle.padding`)
- **Total horizontal padding:** 16 + 12 = 28px on each side

The day grid renders at its fixed width (e.g., `7 × 44 = 308px` on desktop), centered within `(viewport width - 32px)`, leaving visible gutters when the viewport is wider than `308 + 56 = 364px`.

### Known Nits from Implementation Gate (to be resolved in this amendment)

1. **Unused parameter:** `_buildMarkerStack` (line ~130 in `calendar_grid.dart`) accepts an `isToday` parameter that is never used within the method — either use it to adjust marker rendering for today's cell, or remove it.
2. **Roundabout import:** `calendar_colors.dart` (line 2) imports `'../calendar/calendar_markers.dart'` when both files are in `lib/features/calendar/` — should be `'calendar_markers.dart'` (no `../calendar/` prefix).

---

## Root Cause Analysis

### Issue 1: Fixed Day Grid Width

**Why the grid doesn't stretch:**  
`FCalendarDayPickerStyle.daySize` is a fixed `Size`, and Forui's day picker uses `7 × daySize.width` to calculate the grid width (confirmed in `day_picker.dart`). This fixed width is then horizontally centered within the available space. There is no built-in responsive sizing mechanism in Forui's `FCalendar.wheel` — `daySize` is a constant, not a function of available width.

**Solution approach:**  
To make the grid responsive, `CalendarGrid` must:

1. Measure available width using `LayoutBuilder`
2. Compute a custom `daySize` such that `7 × daySize.width` (plus inter-column spacing, if any) equals the available width (minus any intentional padding)
3. Pass a custom `FCalendarStyle` (via `FCalendarStyleDelta.delta(...)`) with the computed `dayPickerStyle` into `FCalendar.wheel`'s `style` parameter

**Key unknowns resolved:**

- **Is there inter-column spacing?** Grep of `day_picker.dart` shows `daySpacing` is documented as "vertical spacing between days" (row spacing), not horizontal. Visual inspection of Forui's default rendering shows no horizontal gaps between day columns — the 7 day cells are placed contiguously. Therefore: **no horizontal spacing adjustment needed**.
- **Does FCalendar.wheel accept a custom style?** Yes — confirmed constructor signature: `FCalendarStyleDelta style = const .context()`.
- **Can we override daySize via style delta?** Yes — `FCalendarDayPickerStyleDelta.delta({Size? daySize, ...})` allows passing a custom `Size`.

**Implementation path:**  
Wrap the existing `FCalendar.wheel` instantiation in a `LayoutBuilder`, compute `daySize` from `constraints.maxWidth`, and build a custom style:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final availableWidth = constraints.maxWidth;
    // Compute square daySize to fill width
    final cellWidth = availableWidth / 7;
    final daySize = Size(cellWidth, cellWidth);

    // Build custom style with computed daySize
    final customStyle = FCalendarStyleDelta.delta(
      dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
        daySize: daySize,
      ),
    );

    return FCalendar.wheel(
      style: customStyle,
      // ... other params unchanged
    );
  },
)
```

**Note on padding decision:**  
Forui's default 12px internal padding (`FCalendarStyle.padding`) will remain unchanged in this amendment. The app's 16px horizontal wrapper padding (from `SingleChildScrollView`) provides the primary breathing room; Forui's 12px adds consistent spacing around the header/grid as a cohesive card-like unit. Zeroing out Forui's padding would tighten the layout but is not required to achieve responsive width — the grid will fill `(availableWidth - 24px)` (accounting for Forui's left/right 12px padding), which is sufficient. If Tony requests tighter visual density in a future amendment, we can add `padding: EdgeInsetsGeometryDelta.delta(...)` to zero it out.

### Issue 2: Event Markers Don't Scale with Cell Width

**Current state:**  
Marker bars are hardcoded to `width: 35` in `_buildGigMarker()`, `_buildRehearsalMarker()`, `_buildPotentialMarker()`, and `_buildBlockOutMarker()`. This was sized for a ~40px cell (the approximate default `FSizes.calendar` on desktop). When `daySize` becomes dynamic and potentially larger (e.g., 50px on a wide desktop window), the 35px markers will appear undersized relative to the cell.

**Decision:**  
Markers should **scale proportionally** with `daySize.width` to maintain visual balance. Specifically:

- **Target ratio:** `35 / 44 ≈ 0.795` (the original marker-to-cell-width ratio for Forui's default desktop size)
- **New marker width:** `daySize.width × 0.8` (rounded to a clean factor; 0.8 is close to 0.795 and easier to reason about)

**Why not keep markers fixed-width?**  
Fixed-width markers (e.g., always 35px) would:

- Look proportionally smaller in larger cells (50px+ on wide desktops)
- Look proportionally larger in smaller cells (<32px on narrow mobile screens if Forui's defaults are overridden)
- Break the visual rhythm of the grid, where all other elements (day numbers, cell padding) scale with `daySize`

Proportional scaling keeps the design consistent across device sizes and viewport widths.

**Implementation:**  
Pass the computed `daySize` into the `dayBuilder` via `CalendarGrid`'s build context, then compute marker width as `daySize.width × 0.8` in each marker builder method. The `dayBuilder` callback doesn't receive `daySize` as a parameter, but `CalendarGrid` can store it as a local variable in the `LayoutBuilder` scope and reference it inside the `dayBuilder` closure.

### Issue 3: No Day Cell Border/Outline

**Current state:**  
The `dayBuilder` renders day cells with `style.background` and `style.foreground` decorations, but the default Forui theme does not include borders on day cells. The only variant-specific styling is for `today` (rose background, white text).

**Design decision: Where to apply the border?**

Options:

1. **Add border to all day variants via `dayStyles` delta** — apply a subtle border to every day cell, including `today`.
2. **Add border only to non-today days** — keep `today` borderless (since it already has a distinct rose background) to avoid visual clutter.

**Chosen approach: Option 1 — border on all days, including today.**

**Rationale:**

- **Consistency:** Borders on all cells define the grid structure uniformly. Exempting `today` would create a visual hole in the grid that draws unintended attention.
- **Precedent:** Many calendar UIs (Google Calendar, Apple Calendar) apply cell borders uniformly, even to highlighted days.
- **Forui's decoration layering:** Both `background` and `foreground` can accept `BoxDecoration` with `border`. Applying the border via `background` (painted first) ensures it sits beneath the day number text and event markers, while still defining the cell boundary. The `today` variant's rose background will render atop the border, which will remain visible as a subtle outline.

**Border styling:**

- **Color:** `context.colors.border` (Forui's theme border color, adapts to dark mode)
- **Width:** `1px` (subtle, non-intrusive)
- **Sides:** All four sides (`Border.all(...)`)

**Which `Decoration` property: background or foreground?**  
Use **`background`** for the border. Forui's rendering order is:

1. `background` decoration (painted first)
2. Day content (text, event markers)
3. `foreground` decoration (painted on top)

Placing the border in `background` ensures:

- It sits beneath all content (day number, markers)
- It doesn't obscure the day number text or markers
- The `today` rose background still renders correctly atop the border, with the border visible as a subtle frame

**Implementation:**  
Customize `dayStyles` via `FCalendarDayPickerStyleDelta.delta(...)` to add a border to the `background` decoration of all day variants:

```dart
dayStyles: FVariantsDelta.delta([
  FVariantOperation.all(
    FCalendarDayStyleDelta.delta(
      background: DecorationDelta.boxDelta(
        border: Border.all(
          color: context.colors.border,
          width: 1,
        ),
      ),
    ),
  ),
]),
```

**Note:** This delta modifies only the `background` decoration's border — it does not replace the entire decoration, so the `today` variant's rose background (defined elsewhere in Forui's theme) will still apply, layered atop the border.

### Issue 4: Nits from Implementation Gate

1. **Unused `isToday` parameter in `_buildMarkerStack`:**  
   The parameter is passed from `dayBuilder` but never used within the method. Since marker rendering is currently uniform regardless of whether the cell is today, the parameter should be **removed** to avoid dead code.

   If future logic requires today-specific marker styling (e.g., bolder markers on today's cell), the parameter can be re-added at that time.

2. **Roundabout import in `calendar_colors.dart`:**  
   Line 2 imports `'../calendar/calendar_markers.dart'`. Both files are in `lib/features/calendar/`, so the import should be simplified to `'calendar_markers.dart'`.

---

## Proposed Solution

### Change 1: Make day grid responsive via LayoutBuilder

**File:** `lib/features/calendar/widgets/calendar_grid.dart`

**Modify `build()` method:**

Replace the current direct instantiation of `FCalendar.wheel` with a `LayoutBuilder` that computes `daySize` from available width and builds a custom `FCalendarStyle`:

```dart
@override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      // Compute responsive day cell size to fill container width
      // Subtract FCalendar's internal horizontal padding (12px left + 12px right = 24px total)
      final availableWidth = constraints.maxWidth - 24;
      final cellWidth = availableWidth / 7;
      final daySize = Size(cellWidth, cellWidth);  // Square cells

      // Compute marker width proportional to cell size (80% of cell width)
      final markerWidth = cellWidth * 0.8;

      // Build custom style with computed daySize and day cell borders
      final customStyle = FCalendarStyleDelta.delta(
        dayPickerStyle: FCalendarDayPickerStyleDelta.delta(
          daySize: daySize,
          dayStyles: FVariantsDelta.delta([
            FVariantOperation.all(
              FCalendarDayStyleDelta.delta(
                background: DecorationDelta.boxDelta(
                  border: Border.all(
                    color: context.colors.border,
                    width: 1,
                  ),
                ),
              ),
            ),
          ]),
        ),
      );

      return FCalendar.wheel(
        control: FWheelCalendarControl(controller: widget.controller),
        selectionControl: FDateSelectionControl.none(),
        style: customStyle,  // ← NEW: pass computed style
        dayBuilder: (context, styles, localizations, date, variants) =>
            _buildDayWithMarkers(context, styles, localizations, date, variants, markerWidth),
        onDayPress: (date) => widget.onDayTap?.call(date),
        fixedWeeks: false,
      );
    },
  );
}
```

**Key changes:**

1. Wrap `FCalendar.wheel` in `LayoutBuilder` to access `constraints.maxWidth`
2. Compute `cellWidth = (maxWidth - 24) / 7` (subtracting Forui's 12px left/right padding)
3. Create square `daySize = Size(cellWidth, cellWidth)`
4. Compute `markerWidth = cellWidth × 0.8` for proportional marker sizing
5. Build `FCalendarStyleDelta.delta(...)` with custom `dayPickerStyle` containing:
   - Computed `daySize`
   - Border on all day cells via `dayStyles: FVariantsDelta.delta([FVariantOperation.all(...)])`
6. Pass `customStyle` to `FCalendar.wheel`'s `style` parameter
7. Pass `markerWidth` into `_buildDayWithMarkers` via an additional parameter (see Change 2)

**Why subtract 24px from maxWidth?**  
Forui's default `FCalendarStyle.padding` is `EdgeInsets.all(12)`, which adds 12px on the left and 12px on the right (24px total horizontal padding) inside the `FCalendar` widget. The day grid itself renders within this padded area, so the available width for the 7-column grid is `maxWidth - 24`. Computing `cellWidth` from this adjusted width ensures the grid fills the space correctly without overflowing or leaving unexpected gutters.

### Change 2: Scale event markers proportionally

**File:** `lib/features/calendar/widgets/calendar_grid.dart`

**Add `markerWidth` parameter to `_buildDayWithMarkers`:**

Update the method signature to accept the computed marker width:

```dart
Widget _buildDayWithMarkers(
  BuildContext context,
  FCalendarDayStyles styles,
  FLocalizations localizations,
  DateTime date,
  Set<FCalendarDayVariant> variants,
  double markerWidth,  // ← NEW: pass computed marker width
)
```

**Update marker builder methods:**

Replace hardcoded `width: 35` with the `markerWidth` parameter in all four marker methods:

```dart
Widget _buildGigMarker(double width) {
  return Container(
    width: width,  // ← was: 35
    height: 3,
    decoration: BoxDecoration(
      color: CalendarColors.gigIndicator,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );
}
```

(Repeat for `_buildRehearsalMarker`, `_buildPotentialMarker`, `_buildBlockOutMarker`)

**Update marker stack builder calls:**

In `_buildMarkerStack`, pass `markerWidth` to each marker builder:

```dart
switch (eventType) {
  case CalendarEventType.gig:
    activeMarkers.add(_buildGigMarker(markerWidth));
    break;
  case CalendarEventType.rehearsal:
    activeMarkers.add(_buildRehearsalMarker(markerWidth));
    break;
  case CalendarEventType.blockOut:
    activeMarkers.add(_buildBlockOutMarker(markers.blockOutCount, markerWidth));
    break;
}
```

**Add `markerWidth` parameter to `_buildMarkerStack`:**

```dart
Widget _buildMarkerStack(
  List<CalendarEventType> sortedEventTypes,
  CalendarDayMarkers markers,
  double markerWidth,  // ← NEW
)
```

And call it from `_buildDayWithMarkers`:

```dart
_buildMarkerStack(sortedEventTypes, markers, markerWidth),
```

**For `_buildBlockOutMarker` (multi-segment logic):**

The method currently computes segment widths based on a hardcoded `totalWidth = 35.0`. Replace with the `markerWidth` parameter:

```dart
Widget _buildBlockOutMarker(int blockOutCount, double markerWidth) {
  final count = blockOutCount > 0 ? blockOutCount : 1;

  if (count == 1) {
    return Container(
      width: markerWidth,  // ← was: 35
      height: 3,
      decoration: BoxDecoration(
        color: CalendarColors.blockOutIndicator,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  // Multiple block outs - split into segments with 1px gaps
  const gapWidth = 1.0;
  final totalGaps = count - 1;
  final segmentWidth = (markerWidth - (gapWidth * totalGaps)) / count;  // ← was: (35.0 - ...)

  return SizedBox(
    width: markerWidth,  // ← was: 35
    height: 3,
    child: Row(
      children: [
        for (int i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: gapWidth),
          Container(
            width: segmentWidth,
            height: 3,
            decoration: BoxDecoration(
              color: CalendarColors.blockOutIndicator,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ],
    ),
  );
}
```

### Change 3: Remove unused `isToday` parameter from `_buildMarkerStack`

**File:** `lib/features/calendar/widgets/calendar_grid.dart`

**Before (line ~130):**

```dart
Widget _buildMarkerStack(
  List<CalendarEventType> sortedEventTypes,
  CalendarDayMarkers markers,
  bool isToday,  // ← UNUSED
)
```

**After:**

```dart
Widget _buildMarkerStack(
  List<CalendarEventType> sortedEventTypes,
  CalendarDayMarkers markers,
  double markerWidth,  // ← NEW (from Change 2), replaces unused isToday
)
```

**Update call site in `_buildDayWithMarkers`:**

```dart
// Before:
_buildMarkerStack(sortedEventTypes, markers, isToday),

// After:
_buildMarkerStack(sortedEventTypes, markers, markerWidth),
```

### Change 4: Fix roundabout import in `calendar_colors.dart`

**File:** `lib/features/calendar/calendar_colors.dart`

**Line 2, before:**

```dart
import '../calendar/calendar_markers.dart';
```

**Line 2, after:**

```dart
import 'calendar_markers.dart';
```

Both files are in `lib/features/calendar/`, so no relative parent path (`../calendar/`) is needed.

---

## Files Modified

| File                                               | Action     | Lines Changed | Description                                                                                                                                                                                                           |
| -------------------------------------------------- | ---------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/calendar/widgets/calendar_grid.dart` | **Modify** | ~50           | Wrap `FCalendar.wheel` in `LayoutBuilder`, compute responsive `daySize` and `markerWidth`, build `FCalendarStyleDelta` with day borders, pass `markerWidth` through marker methods, remove unused `isToday` parameter |
| `lib/features/calendar/calendar_colors.dart`       | **Modify** | 1             | Fix import path (`'calendar_markers.dart'` instead of `'../calendar/calendar_markers.dart'`)                                                                                                                          |

**Total:** 2 files modified

---

## Database / RLS / RPC Impact

**Database:** Not applicable (UI-only change)

---

## System Impact

| System             | Impact                               |
| ------------------ | ------------------------------------ |
| Gigs               | Unaffected (calendar rendering only) |
| Rehearsals         | Unaffected (calendar rendering only) |
| Setlists / Catalog | Unaffected                           |
| Members / RBAC     | Unaffected                           |
| Auth / Session     | Unaffected                           |
| Routing            | Unaffected                           |

---

## Risk Assessment

**Low risk.** Changes are localized to `calendar_grid.dart`'s rendering logic:

1. Responsive sizing is computed via `LayoutBuilder` — standard Flutter pattern, no custom layout logic
2. Forui's style delta system is already proven in this codebase (see `app_button.dart`, `app_card.dart`, `app_checkbox.dart`)
3. Marker scaling is a simple proportional calculation (`× 0.8`) — no new business logic
4. Import fix is a one-line path correction with zero behavioral impact

**Potential edge case:**  
On extremely narrow screens (<224px wide, the width of 7×32px cells), the computed `cellWidth` could shrink below Forui's minimum cell size, causing day numbers to overflow or markers to become illegibly small. However:

- The app's minimum supported viewport width (iPhone SE: 375px) provides ample space: `(375 - 32 - 24) / 7 ≈ 45px per cell` — larger than the current desktop default of 44px.
- On narrower viewports (if supported in the future), Forui's internal layout logic will handle text scaling, and markers will scale proportionally down to ~36px (45px × 0.8) — still visible.

**No analyzer regressions expected:** All Forui APIs used here are public, documented, and already in use elsewhere in the codebase. The amendment adds no new dependencies or experimental features.

---

## QA Validation Checklist (appends to base feature QA)

Beyond the base feature's QA checklist (swipe navigation, wheel picker, event markers, day tap, band switching), this amendment adds:

### Responsive Grid Sizing

- [ ] **Desktop/web (wide viewport):** Open Calendar in a wide browser window (>800px). Verify the day grid expands to fill the horizontal space (no visible gutters on either side). Day cells should be noticeably larger than the old fixed 44px size.
- [ ] **Mobile (narrow viewport):** Open Calendar on iPhone (375px width). Verify the day grid still fits within the screen width with symmetric margins. Day cells should be slightly larger than 32px (approximately `(375 - 32 - 24) / 7 ≈ 45px`).
- [ ] **Tablet landscape:** Open Calendar on iPad in landscape orientation. Verify the grid stretches to fill the wider container, with proportionally larger cells.
- [ ] **Resize browser window (web only):** Open Calendar on Chrome/Safari, resize the browser window from narrow to wide. Verify the day grid dynamically reflows to fill the new width (may require hot-reload to re-render).

### Event Marker Scaling

- [ ] **Marker proportions:** Inspect day cells with event markers (gig/green, rehearsal/blue, potential/orange, block-out/rose). Verify markers appear roughly 80% of the cell width, centered beneath the day number. Markers should not overflow the cell or appear disproportionately small/large.
- [ ] **Block-out segmentation:** On a day with multiple block-outs (2+ band members unavailable), verify the rose marker splits into segments with 1px gaps, and the total marker width still matches other markers (80% of cell width).

### Day Cell Borders

- [ ] **Border visibility:** Verify all day cells (including today's rose-highlighted cell) have a subtle 1px border defining the grid structure.
- [ ] **Border color:** Verify the border adapts to dark mode (uses Forui's `context.colors.border` — should be a muted neutral that doesn't clash with event marker colors).
- [ ] **Today cell:** Verify today's rose background renders atop the border, with the border visible as a subtle frame around the cell (not obscured by the background).

### Regression Checks

- [ ] **All base feature functionality:** Re-run the base QA checklist (swipe navigation, wheel picker, event markers, day tap, band switching) to confirm no regressions.
- [ ] **Analyzer:** `flutter analyze` returns 0 errors (no new warnings introduced by this amendment).

---

## Implementation Notes for Engineer

1. **LayoutBuilder placement:** Wrap only the `FCalendar.wheel` instantiation, not the entire `CalendarGrid.build()` method. The `LayoutBuilder` should be the direct return value of `build()`.

2. **Style delta composition:** `FCalendarStyleDelta.delta(...)` takes a `dayPickerStyle` parameter of type `FCalendarDayPickerStyleDelta?`. Nest the `daySize` and `dayStyles` customizations within `FCalendarDayPickerStyleDelta.delta(...)`.

3. **Border delta syntax:** Use `DecorationDelta.boxDelta(border: Border.all(...))` — this is the correct Forui API (confirmed via existing usage in `app_card.dart`). Do not attempt to use `FVariantsDelta.all(...)` — that constructor does not exist (the correct form is `FVariantsDelta.delta([FVariantOperation.all(...)])`).

4. **Marker width threading:** The computed `markerWidth` must be accessible inside the `dayBuilder` closure. Since `dayBuilder` is defined inline within the `LayoutBuilder`'s builder function, `markerWidth` is already in scope (closure captures it). Pass it as an explicit parameter to `_buildDayWithMarkers` for clarity, then thread it through to `_buildMarkerStack` and each marker builder.

5. **Avoid recomputing markerWidth per day:** Compute `markerWidth = cellWidth × 0.8` once in the `LayoutBuilder` scope, not inside `_buildDayWithMarkers` (which is called for every day in the grid). This prevents redundant calculations (e.g., 35 times per month view).

6. **Test on both platforms:** Run on macOS (`flutter run -d macos`) and iOS Simulator (`flutter run -d ios`) to verify responsive sizing and border rendering on different screen sizes. Web testing (`flutter run -d chrome`) is optional but recommended for wide-viewport validation.

---

## Confidence Level

**HIGH** — All API details confirmed via installed Forui package source (`~/.pub-cache/hosted/pub.dev/forui-0.25.0/`), not speculation. Responsive sizing pattern is standard Flutter (`LayoutBuilder`). Forui's style delta system is already proven in this codebase with zero historical issues. Marker scaling is straightforward proportional math. Import fix is trivial. No new architecture, no database changes, no RLS/RPC complexity.
