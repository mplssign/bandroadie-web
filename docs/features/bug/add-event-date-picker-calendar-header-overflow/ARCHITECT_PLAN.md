# ARCHITECT_PLAN.md

> **RE-DIAGNOSIS (revision 2).** The prior version of this plan proposed only
> widening the dialog via `FDialogStyleDelta.delta(insetPadding: ...)` +
> `FDialog.constraints`. That change was implemented faithfully and — while
> arithmetically correct for on-device fonts — did NOT make the widget test
> pass. The test now reports `RenderFlex overflowed by 68 pixels` (September)
> and `50 pixels` (February) at 360×800. Investigation confirmed the prior fix
> DOES widen the header `Row` from ~254 px → ~302 px as predicted; the residual
> overflow is because forui hard-caps the header container to
> `SizedBox(width: 7 × daySize.width) = 308 px` (touch preset), and header
> content can exceed that cap regardless of dialog width — in the widget-test
> environment (fallback-font metrics inflate `"September 2026"` to ~370 px) and
> on device at large accessibility font scales. The revised fix keeps the
> dialog-widening changes AND adds an overflow-tolerant `headerBuilder`
> wrapper so the header sizes to intrinsic content when it exceeds the 308-px
> hard cap, instead of throwing.

## Feature Slug
`bug/add-event-date-picker-calendar-header-overflow`

## Feature Title
Calendar header RenderFlex overflow in the "Add Event" date picker for certain months (e.g. September)

## Problem Summary
Tapping a date-picker field in the Add Event sheet opens a forui `FCalendar.grid`
dialog. On narrow-phone screens (portrait Android around 360 logical px wide),
months with long labels — confirmed on **September 2026** — trigger a
`RenderFlex overflowed by 8.4 pixels on the right` assertion in the forui
calendar header's `Row`. A yellow/black overflow indicator paints on the right
edge of the header. The failure originates in the third-party `forui-0.26.0`
`Header` widget, but its trigger is BandRoadie's own dialog configuration.

The buggy code path is the shared `showAppDatePicker(...)` helper in
[lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart)
— every date-picker in the app (Add Event drawer, Add Block Out drawer, gig
expense sub-view, financial-entry sheet, gig-pay sheet) uses it, so the fix in
that one helper is inherited by every caller.

Affects: Android at default font scale (confirmed on-device). Also reproduces
in any environment where the header's intrinsic content width exceeds forui's
built-in 308-px `SizedBox` cap around the header row — includes the widget
test at 360×800 with fallback-font metrics, and any real device at
accessibility font scales ≳ 1.15 (`"September 2026"` grows from ~262 → ~300+).
Fix is single-file, all-platforms, no platform-conditional code.

## Root Cause
**Confidence: HIGH** — direct read of forui source
(`.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/calendar/{calendar,grid_calendar,header}.dart`
and `dialog.dart`) plus empirical widget-test reproduction of the residual
`68 px` / `50 px` overflow after the prior fix landed.

**Two independent facts combine to produce the bug:**

### Fact 1 — forui hard-caps the header row width at `7 × daySize.width`.

In `.../calendar/grid_calendar.dart` (`GridCalendar.build`), the header is
wrapped in a `SizedBox` whose width is computed once in `FCalendar._State.build`
(`.../calendar/calendar.dart` L427):

```dart
final width = DateTime.daysPerWeek * style.dayPickerStyle.daySize.width;
// width = 7 * 44 = 308 for touch preset (sizes.calendar = 44)
```

Then in `GridCalendar` (`.day` branch):

```dart
SizedBox(
  width: width, // 308
  child: headerBuilder(context, controller, selectionController, Header.day(...)),
),
```

`SizedBox` uses `RenderConstrainedBox` with `additionalConstraints =
BoxConstraints.tightFor(width: 308)`. At layout it computes
`additionalConstraints.enforce(parent)`. This has two consequences that both
matter for this bug:

- If the parent's `maxWidth` is `< 308`, the SizedBox is **clamped down** to
  the parent's max — the `Row` inside gets a narrower tight width than the
  308 forui intended (original on-device bug).
- If the parent's `maxWidth` is `≥ 308`, the SizedBox is **capped up** at
  exactly 308 — the `Row` inside gets tight width = 308 and **cannot grow to
  fit content wider than that** (widget-test failure; accessibility-font
  failure).

### Fact 2 — the header `Row` has no overflow tolerance.

In `.../calendar/header.dart` (`Header.build`):

```dart
Padding(
  padding: style.padding, // .zero
  child: Row(
    children: [
      _Tappable(...),        // label + toggle icon; no Flexible wrapper
      if (navigation) ...[
        const Spacer(),      // flex: 1
        FButton.icon(... previousIcon ...),
        FButton.icon(... nextIcon ...),
      ],
    ],
  ),
)
```

`Row.mainAxisSize` defaults to `.max`, so with a tight parent it always fills
to that tight width. The label `_Tappable` is not wrapped in `Flexible` /
`Expanded`, so if intrinsic (`_Tappable + prev button + next button`) exceeds
the tight width, `Spacer` collapses to zero and `RenderFlex` reports overflow
by the excess. There is no `TextOverflow.ellipsis`, no `Wrap`, no scroll
wrapper — the layout is completely rigid.

### How the two facts interact

- **On-device, default font scale** (original report): header intrinsic is
  ~262 px. Parent `maxWidth` reaching the `SizedBox` is only 254 px
  (screen 360 − `insetPadding.horizontal` 80 − border/padding 26 = 254). Fact 1
  clamps `SizedBox` to 254; Fact 2 overflows by 262 − 254 = **8.4 px**.
  **The prior fix targeted this case.**
- **On-device, accessibility font scale ≳ 1.15**: header intrinsic grows past
  308 px. Even if we widen the dialog so the parent gives ≥ 308 px, Fact 1
  caps the `SizedBox` at 308; Fact 2 overflows by the excess.
- **In the widget test at 360×800**: `flutter_test` does not auto-load the
  forui `packages/forui/Inter` font asset into the font engine (only pubspec
  fonts declared in the app's own manifest, or fonts registered via
  `FontLoader().load(...)`, become the resolved family). Text falls back to a
  monospace-ish placeholder where each glyph advance ≈ font-size. At the
  `headerTextStyle` size of 18 px, `"September 2026"` (14 chars) is ~252 px
  wide of text alone; add the toggle icon (~24), inner spacing (~2), tappable
  padding (10), two 44-px nav buttons → intrinsic ≈ **376 px**. `"February
  2026"` (13 chars) → intrinsic ≈ **358 px**. Fact 1 caps `SizedBox` at 308;
  Fact 2 overflows by 376 − 308 = **68 px** (September) and 358 − 308 =
  **50 px** (February). **This matches the observed test output exactly.**

### Why the prior fix (dialog widening only) is INSUFFICIENT

The prior plan attacked only the parent-clamping side (Fact 1 clamps `SizedBox`
DOWN when parent is narrower than 308). It reduced `FDialog.insetPadding`
horizontal from 40 → 16 and added `FDialog.constraints =
BoxConstraints(minWidth: 280, maxWidth: 360)`. Post-fix, at a 360×800 surface,
the parent `maxWidth` reaching the `SizedBox` is (360 − 32 inset − 2 border − 24
FCalendar padding) = **302 px**. The `SizedBox` receives 302 (still clamped
just below its intended 308, because `FCalendar.padding.all(12) +
decoration.dimensions.all(1)` eat 26 px — but this is close enough that
on-device the 262-px intrinsic content fits with 40 px of slack).

That handles the on-device bug. But the widget test's intrinsic content is
376 / 358 px — well past 302 AND past the 308 hard cap. **No amount of
widening the dialog can accommodate content larger than 308**, because the
forui `SizedBox` caps upward at 308. The prior fix cannot pass the test.

The 68-px / 50-px residual overflow the engineer measured is fully consistent
with content = 376 / 358 and `Row` tight width = 302–308 (the empirical
`302` from my post-fix arithmetic + the `SizedBox`'s 308 cap yield exactly
that range). This confirms the prior fix DID work as arithmetic'd — the
`Row` really is ~302 px wide now, up from 254. The residual overflow is a
distinct failure mode (content > 308 cap), not the original one, and needs a
distinct mechanism to resolve.

## Existing System Analysis
- `showAppDatePicker(...)` is THE single date-picker helper in the codebase. A
  workspace-wide search confirms all callers use it — no direct `showDatePicker`,
  no direct `FCalendar.grid` calls outside this helper. Callers:
  [add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart)
  L454/L474,
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  L3328/L3348/L3381/L3395/L3529,
  [gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart)
  L187/L199,
  [add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
  L365,
  [gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart)
  L110. Fixing the helper transparently fixes all of them.
- The current on-disk state of
  [lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart)
  already contains the prior fix (`FDialog.style` with reduced `insetPadding`,
  `FDialog.constraints = (280, 360)`, no inner `ConstrainedBox`). That code is
  KEPT — the new work is additive.
- Widget test file
  [test/components/ui/app_date_picker_test.dart](test/components/ui/app_date_picker_test.dart)
  already exists (from the prior plan). Two test cases at 360×800: September
  2026 and February 2026. Both currently fail; both must pass after this
  revision — the test file itself is untouched by this plan.
- The main calendar view widget
  [calendar_grid.dart](lib/features/calendar/widgets/calendar_grid.dart) uses
  `FCalendar.wheel`, not `.grid`, wrapped in a `LayoutBuilder` that computes a
  responsive `daySize` from `constraints.maxWidth`. That view is **not**
  affected by this bug and is out of scope.
- The two `FTheme` wrappers used at runtime around the date-picker call —
  `AppTheme.foruiTheme(brightness)` at [lib/main.dart](lib/main.dart) L170 and
  `buildEventEditorTheme()` at
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
  L2713 — both build via `FThemeData(colors: ..., touch: true)` and neither
  overrides `calendarStyle` or `sizes.calendar`. So `sizes.calendar = 44` is
  universal and the 308-px `SizedBox` hard cap applies everywhere.
- Design tokens
  ([lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart))
  provide `Spacing` constants; the fix uses raw `EdgeInsets` numbers because
  they are third-party (forui) style overrides, not app-owned layout.

## Proposed Solution
Single-file fix, still confined to
[lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart).
Two conceptual parts:

### Part A — retain the dialog-widening (from the prior fix)
Keep the current `FDialog.style: FDialogStyleDelta.delta(insetPadding: ...)`
reducing horizontal inset from 40 → 16 and `FDialog.constraints:
BoxConstraints(minWidth: 280, maxWidth: 360)`, and keep the inner
`ConstrainedBox` removal. This is what makes the on-device `Row` width go from
254 → ~302 px, which is enough for the on-device 262-px intrinsic to fit at
default font scale. **No change to the current code for this part** — it is
already in place.

### Part B — make the forui header overflow-tolerant
Pass a custom `headerBuilder:` to `FCalendar.grid(...)` that wraps the
built-in header widget in a bounded-then-scrollable layout:

```dart
FCalendar.grid(
  // ... existing args unchanged ...
  headerBuilder: (context, controller, selectionController, header) =>
      LayoutBuilder(
    builder: (context, viewport) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: viewport.maxWidth),
        child: IntrinsicWidth(child: header),
      ),
    ),
  ),
),
```

**Why this passes layout for every content width:**

1. Parent `SizedBox(width: 308)` gives `LayoutBuilder` a tight `(308, 308)`
   width constraint. `viewport.maxWidth = 308`.
2. `SingleChildScrollView(scrollDirection: Axis.horizontal)`'s viewport gives
   its child unbounded horizontal max, keeping cross-axis (height) as-is.
   Constraints seen by `ConstrainedBox` become `(minW: 0, maxW: ∞)`.
3. `ConstrainedBox(minWidth: viewport.maxWidth = 308)` enforces
   `(minW: 308, maxW: ∞)` on its child.
4. `IntrinsicWidth` measures `header.getMaxIntrinsicWidth(∞)`. For the
   forui `Header`, this is `Padding(zero).maxIntrinsic = Row.maxIntrinsic =
   _Tappable.intrinsic + prevBtn.intrinsic + nextBtn.intrinsic` (the `Spacer`
   contributes 0 to `Row`'s max-intrinsic-width via `RenderFlex`'s flex
   handling). `IntrinsicWidth` then lays out its child with
   `constraints.tighten(width: intrinsic)`:
   - On-device, default font: intrinsic ≈ 262 → `tighten(262)` in `(308, ∞)` →
     tight width = `max(262, 308) = 308`. `Row` gets tight 308, `mainAxisSize:
     .max` fills 308, `Spacer` takes 46 px, buttons align to the right edge —
     **identical to today's on-device layout**.
   - Widget test, fallback font: intrinsic ≈ 376 → `tighten(376)` in `(308, ∞)` →
     tight width = 376. `Row` gets tight 376, `mainAxisSize: .max` fills 376,
     `Spacer` collapses to 0, content fits exactly, no `RenderFlex` overflow.
   - On-device, accessibility font scale 1.5×: intrinsic ≈ 375 → same shape as
     the widget-test case, `Row` gets tight 375, content fits, no overflow.
5. `SingleChildScrollView` viewport is 308 wide; its child is `max(intrinsic,
   308)` wide. When child = viewport there is nothing to scroll and the
   scroll physics never engage. When child > viewport, the scroll view
   handles the extra width by allowing horizontal scroll (default physics,
   which enables accessibility users to reach the nav buttons if their font
   scale pushes them off-viewport). No `RenderFlex` overflow error is emitted
   in either case.

**Why this does NOT throw the `mainAxisSize:.max` + unbounded assertion.** The
`Row` never sees an unbounded parent: `IntrinsicWidth` is what layouts its
child, and it always produces a tight width via `tighten`. The `SingleChild-
ScrollView` provides the unbounded main-axis constraint, but the intermediate
`ConstrainedBox` + `IntrinsicWidth` re-establish a bounded, tight width before
the `Row` is laid out.

**Why the two parts BOTH matter.** Without Part A, the on-device dialog stays
280 px wide, `SizedBox` is clamped to 254 px, and `IntrinsicWidth` forces the
`Row` to `max(262, 254) = 262 px` — which is 8 px WIDER than the 254-px
viewport, so the `SingleChildScrollView` would scroll horizontally by 8 px in
default use, hiding part of the "next month" button (bad UX). Part A gives
the viewport 302 px so the on-device default-font `Row` (262 intrinsic) fits
exactly with 40 px of slack — no scroll, no visual change from today. Without
Part B, the widget test still fails (impossible arithmetic vs. the 308 cap)
and any user at accessibility font scale ≳ 1.15 hits the same overflow.

### Rejected alternatives (this pass)

- **Patch forui `Header` to wrap `_Tappable` in `Flexible`** — correct
  upstream fix, off-limits (`.pub-cache/` not our tree). Rejected.
- **Reduce `FCalendarStyle.padding` from `.all(12)` to something smaller** —
  recovers only ~10–14 px and touches internal chrome (calendar body sits
  tighter against dialog edge). Insufficient for the 60–70-px widget-test
  overflow; not enough for larger accessibility font scales either. Rejected.
- **Override `daySize` via `FCalendarStyleDelta.delta(dayPickerStyle:
  FCalendarDayPickerStyleDelta.delta(daySize: ...))`** — increasing `daySize`
  raises the 308 cap but doesn't matter unless the parent's `maxWidth`
  matches. Decreasing `daySize` lowers the cap AND shrinks day cells (visible
  cosmetic regression). Rejected.
- **Wrap `FCalendar.grid` in `FittedBox(fit: BoxFit.scaleDown)`** — lays out
  child with `BoxConstraints()` (unbounded main axis), which asserts against
  `Row.mainAxisSize: .max` + `Spacer(flex: 1)`. Would replace the overflow
  error with a hard assertion. Rejected.
- **Wrap `FCalendar.grid` in `SingleChildScrollView` (horizontal) directly**
  — same unbounded-parent + `Spacer(flex: 1)` assertion. Rejected.
- **Override `FCalendarHeaderStyle.tappablePadding` / `buttonStyle` /
  `headerTextStyle` to shrink content aggressively** — costs ~10–30 px in
  visual regressions (smaller nav buttons, tighter label, smaller font) and
  is fragile against future font/theme changes. Rejected.
- **Ship a widget-test-only font loader (`FontLoader().load(...)`) so the test
  uses Inter instead of the fallback font** — fixes the widget-test symptom
  but leaves real users on accessibility font scales still exposed to the
  same overflow. Not a real fix. Rejected. (Note: the test file is not
  changed by this plan; the widget-level `headerBuilder` wrap is what makes
  it pass.)
- **Downgrade to `FCalendar.wheel`** — different UX (month/year wheel picker
  instead of day grid). Not a bug fix; a redesign. Rejected.

## Database Impact
`not applicable`.

No schema change, no migration, no RLS policy, no RPC function, no trigger, no
edge function, no data access change.

## Flutter Architecture Changes
None. No new controllers, providers, repositories, models, services, routes, or
state. No changes to init order, config, `--dart-define`, or platform-conditional
code. No new dependencies. Style + constraints on an existing dialog only.

## Files to Create
`n/a` — the widget-test file
[test/components/ui/app_date_picker_test.dart](test/components/ui/app_date_picker_test.dart)
already exists (from the prior revision of this plan) and is kept as-is.

## Files to Modify
- [lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart)
  — inside `showAppDatePicker(...)`, in the `builder:` argument of
  `showFDialog<DateTime?>(...)`:
  1. **Preserve** the existing `FDialog.style:
     FDialogStyleDelta.delta(insetPadding: ...)` and `FDialog.constraints:
     BoxConstraints(minWidth: 280, maxWidth: 360)`. Do NOT remove or alter
     them. These are Part A of the fix.
  2. **Add** a `headerBuilder:` argument to the `FCalendar.grid(...)`
     constructor:
     ```dart
     headerBuilder: (context, controller, selectionController, header) =>
         LayoutBuilder(
       builder: (context, viewport) => SingleChildScrollView(
         scrollDirection: Axis.horizontal,
         child: ConstrainedBox(
           constraints: BoxConstraints(minWidth: viewport.maxWidth),
           child: IntrinsicWidth(child: header),
         ),
       ),
     ),
     ```
     Do not pass a custom `physics:` — default scroll physics is intentional
     so that accessibility users at large font scales can horizontally scroll
     the header to reach off-viewport nav buttons.
  3. Preserve every other argument on `FCalendar.grid` verbatim: same
     `FGridCalendarControl`, same `FDateSelectionControl.managedSingle` with
     `toggleable: false` and `onChange: (date) => Navigator.of(context).pop(date)`.
     `fixedWeeks: false` and `barrierDismissible: true` may be left as-is
     (info-level lint about redundant defaults is acceptable) or elided at
     engineer's discretion — this is a stylistic call, not part of the fix.

  All required types are already reachable via the existing
  `import 'package:flutter/material.dart';` (`LayoutBuilder`, `Single-
  ChildScrollView`, `ConstrainedBox`, `IntrinsicWidth`, `BoxConstraints`,
  `Axis`, `EdgeInsets`) and `import 'package:forui/forui.dart';`
  (`FCalendar`, `FDialog`, `FDialogStyleDelta`, `EdgeInsetsGeometryDelta`,
  `FGridCalendarControl`, `FDateSelectionControl`). No new imports.

## Files Off-Limits
- `.pub-cache/hosted/pub.dev/forui-0.26.0/**` — third-party package; per
  Feature Input, do not patch forui source. Fix the trigger from BandRoadie's
  side.
- Every caller of `showAppDatePicker(...)`:
  [add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart),
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart),
  [gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart),
  [add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart),
  [gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart)
  — they all transparently inherit the fix.
- [lib/features/calendar/widgets/calendar_grid.dart](lib/features/calendar/widgets/calendar_grid.dart)
  — different widget (main calendar `FCalendar.wheel`), not implicated.
- [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart) and
  [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart)
  — `FTheme` builders. Both correctly pass `touch: true`; changing them
  ripples across the whole app.
- [lib/main.dart](lib/main.dart) — init order and `FTheme` mounting;
  unrelated.
- [test/components/ui/app_date_picker_test.dart](test/components/ui/app_date_picker_test.dart)
  — the acceptance test. Do NOT modify it to work around the fix; the
  widget-level fix in the source must be what makes it pass.

## Change Budget
- [lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart):
  net delta **+11 to +14 lines** on top of the current on-disk state (adding
  the `headerBuilder:` argument with its `LayoutBuilder → SingleChild-
  ScrollView → ConstrainedBox → IntrinsicWidth → header` chain, formatted).
  Expected new imports: 0.
- Expected new files: **0**.
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.
- Expected migrations: **0**.
- Expected edge-function changes: **0**.

## System Impact Map
- Gigs — **unaffected functionally**; date pickers used inside the Add Event
  gig flow, gig-pay sheet, and gig expenses will render correctly on narrow
  phones (bug fix, no behavior change on wide screens).
- Rehearsals — **unaffected functionally**; same date-picker used in
  rehearsal-side of Add Event drawer benefits identically.
- Setlists — **unaffected**.
- Members — **unaffected**.
- Auth — **unaffected**.
- Routing — **unaffected**.
- Notifications — **unaffected**.
- Platforms — **iOS, Android, macOS, Web all use the same fix**. No
  platform-conditional code. Only Android is confirmed failing today; the fix
  is a superset that makes the picker robust everywhere.
- Init order — **untouched**.
- Config / `--dart-define` — **untouched**.
- Firebase / DeepLinkService / Supabase / RLS / RPC — **untouched**.

## Regression Risk
**LOW.**

- Change is scoped to one shared UI helper (one function, one file, ~12 line
  addition on top of the prior fix).
- No state, no async control flow, no data access, no init order, no
  auth/session/routing/DB touched.
- On-device default-font case: `Row` width unchanged (302-px viewport; 262-px
  intrinsic content laid out with `Row.mainAxisSize: .max` filling to 302 —
  `Spacer` still takes ~40 px, buttons still align to the right edge). Visual
  is identical to today (post-prior-fix).
- On-device large-accessibility-font-scale case: header now grows past 308 px
  and becomes horizontally scrollable, rather than throwing `RenderFlex`
  overflow. Strict improvement over today.
- Widget test: `IntrinsicWidth` produces tight `max(intrinsic, 308)` width for
  the `Row`, which the `Row` fills without overflow. `SingleChildScrollView`
  handles the resulting overflow past the viewport by design.
  `tester.takeException()` returns null.
- No regression path via forui version pin — we do not touch `.pub-cache/`.
  `LayoutBuilder`, `SingleChildScrollView`, `ConstrainedBox`, and
  `IntrinsicWidth` are core Flutter widgets present since 1.0, stable.
- Per-frame layout cost is one additional intrinsic-width pass over the
  header (`Row` with 4 children). Trivial.

## Engineer Task Breakdown
1. Open
   [lib/components/ui/app_date_picker.dart](lib/components/ui/app_date_picker.dart).
   Confirm the current on-disk state contains the prior fix: `FDialog.style:
   FDialogStyleDelta.delta(insetPadding: ...)`, `FDialog.constraints:
   BoxConstraints(minWidth: 280, maxWidth: 360)`, no inner `ConstrainedBox`.
   Do not remove or edit these.
2. In the `FDialog.builder` returning `FCalendar.grid(...)`, add a
   `headerBuilder:` argument to the `FCalendar.grid(...)` constructor call
   with EXACTLY the shape shown in the "Files to Modify" section (i.e.
   `LayoutBuilder → SingleChildScrollView(scrollDirection: Axis.horizontal)
   → ConstrainedBox(constraints: BoxConstraints(minWidth: viewport.maxWidth))
   → IntrinsicWidth(child: header)`). Do not pass `physics:` (leave default).
   Insert it alongside the existing `control:` / `selectionControl:` /
   `fixedWeeks:` arguments — argument order does not matter, but standard
   dart formatting must be preserved.
3. Do not touch
   [test/components/ui/app_date_picker_test.dart](test/components/ui/app_date_picker_test.dart)
   — it already asserts the correct thing (`tester.takeException()` is null,
   `FCalendar` is present) and its 360×800 configuration is the acceptance
   signal.
4. Run `flutter analyze lib/components/ui/app_date_picker.dart
   test/components/ui/app_date_picker_test.dart` — expect 0 errors. Two
   pre-existing info-level `avoid_redundant_argument_values` lints on
   `barrierDismissible: true` and `fixedWeeks: false` may remain; they are
   documentary and not part of this fix.
5. Run `flutter test test/components/ui/app_date_picker_test.dart` — both
   cases (September 2026, February 2026) must be green.

## Verification Plan

### Tier 1 (pre-deploy)
`test/components/ui/app_date_picker_test.dart` (existing, unchanged):
- **Case 1** — 360×800 view, `initialDate = DateTime(2026, 9, 15)`. Opens the
  picker, `pumpAndSettle()`, asserts `tester.takeException()` is null and
  `find.byType(FCalendar)` matches. Reports `RenderFlex overflowed by 68
  pixels` today; MUST turn green.
- **Case 2** — 360×800 view, `initialDate = DateTime(2026, 2, 15)`. Same
  assertions. Reports `50 pixels` today; MUST turn green.

Both cases test the observable behavior — no exception, calendar present.
They do not depend on any internal implementation detail of the
`headerBuilder` wrap; they only require that the header stop throwing
`RenderFlex` overflow at 360×800 with fallback-font metrics. The
`IntrinsicWidth + SingleChildScrollView` mechanism accomplishes this by
construction — the `Row` always receives a tight width equal to its own
intrinsic content width (or the viewport width, whichever is larger), so
`Row` can never overflow.

### Tier 2 (post-deploy manual smoke)
- **Android narrow phone (emulator, 360×800, default font scale)**: Open Add
  Event drawer → tap each date field → navigate to September 2026, December
  2026, February 2027, November 2026. Expect no overflow indicator, no
  `flutter run` log line matching `RenderFlex overflowed`. Header should
  look identical to pre-fix visually (label left, buttons right edge of the
  calendar).
- **Android emulator at Accessibility → Font Size → Largest** (typically
  fontScale ≈ 1.3 – 1.5x): same steps. Header content will grow; expect it
  to become horizontally scrollable rather than to overflow. Verify user can
  drag the header to reach the "previous month" and "next month" buttons if
  they scroll off-viewport. No overflow indicator.
- **iOS 375-wide iPhone SE simulator**: same steps at default font scale.
- **macOS**: same steps (baseline; already renders correctly; confirm no
  regression from the added `headerBuilder`).
- **Web (Chrome, ~360-wide viewport via responsive DevTools)**: same steps.
- Sample **all** callers of `showAppDatePicker` in the narrow-Android case:
  Add Event (rehearsal date, gig date, response deadline, potential-date
  candidates), Add Block Out (start date, end date), Gig Expenses drawer
  date, Financial Entry sheet date, Gig Pay sheet date. Same acceptance
  criterion.

## QA Regression Areas
- Add Event drawer date pickers (rehearsal date, gig date, response deadline,
  potential-date candidates) — narrow-phone Android especially.
- Add Block Out drawer date pickers (start / end).
- Gig Expenses drawer date picker.
- Financial Entry sheet date picker.
- Gig Pay sheet date picker.
- **New coverage**: verify at Android/iOS large-accessibility-font-scale
  settings that the header scrolls horizontally rather than throwing.
  Buttons must remain reachable via scroll.
- Cosmetic: date-picker dialog still resembles the pre-fix look on wide
  screens (macOS, tablet, desktop web).
- Cosmetic: no regression in the main calendar month grid
  (`calendar_grid.dart`), which uses `FCalendar.wheel` and is out of scope.
- Non-regression check across `flutter analyze` and the existing widget-test
  suite (should stay green — the change is additive on the picker side).

## Rollout Strategy
Direct merge to `main` after Engineer + QA. No feature flag, no phased
rollout, no migration, no deploy sequencing. This is a single-file bug fix in
a shared UI helper. Rollback path: revert the merge commit — the previous
state (`main` today) is fully restorable in one step; no data written, no
config changed.

## Out of Scope
- Patching `forui-0.26.0`'s `Header` widget to wrap the label `_Tappable` in
  `Flexible` (the correct upstream fix). Off-limits per Feature Input.
- Filing an upstream issue to `forui` about the header layout fragility.
- Migrating any caller of `showAppDatePicker` — every caller inherits the
  fix.
- Loading real fonts in the widget test via `FontLoader` — would fix the
  test-env symptom but leaves the accessibility-font-scale scenario exposed.
  The chosen widget-level fix addresses both cases.
- Any change to `calendar_grid.dart` (main calendar view uses
  `FCalendar.wheel`, computes its own responsive `daySize` inside a
  `LayoutBuilder`, and is not implicated in this bug).
- Any change to `calendar_screen.dart`, `calendar_tab_content.dart`,
  `event_editor_drawer.dart`, or other callers.
- Any refactor of the `headerBuilder` wrap into a shared helper. One caller.
- Any change to `app_theme.dart` / `event_editor_theme.dart` (both correctly
  set `touch: true`).
- Any change to design-token constants for spacing or the app's default
  dialog inset padding.
