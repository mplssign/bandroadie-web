# ARCHITECT PLAN

**Feature Slug:** `redesign-add-event-drawer`
**Feature Title:** Redesign Add/Edit Event Drawer with Forui Dark Theme
**Branch:** `feature/redesign-add-event-drawer`
**Date:** 2026-09-02

---

## 1. Motivation / Root Cause

This is a **planned visual redesign** — not a bug. Confidence: **HIGH** (confirmed in Feature Input and code).

The current drawer (`event_editor_drawer.dart`) uses `BrandColors` / `AppTextStyles` / `AppColors` from `lib/app/theme/` for all visual properties. It renders as a bottom sheet with a drag handle, a flat header row, scrollable form fields (not grouped into section cards), and a plain two-button footer. There is no Forui `FTheme` scope inside the drawer itself — it inherits the app-level `FTheme`.

The spec requires:
- A custom `FThemeData` (dark) with a specific `FColors` palette applied **only inside the drawer**.
- A sticky header containing the event-type segmented control (currently in the scrollable body).
- A scrollable body reorganised into six named, card-bordered section cards per event type.
- Collapsed/expandable sub-sections (Load-in, Soundcheck, Gig Pay, Expenses).
- A sticky footer with a live summary line.
- All controls restyled to spec dimensions and tokens.

---

## 2. Solution Approach

### 2a. Custom `FThemeData` / colour tokens

`lib/app/theme/event_editor_theme.dart` (new file) will define:

1. All extra local colour tokens as `const Color` values — these are properties that `FColors` does not have a named field for:
   `kEdSurface`, `kEdCardBorder`, `kEdSegmentedBorder`, `kEdPopoverSurface`,
   `kEdInputFill`, `kEdPlaceholder`, `kEdMutedForegroundFaint`,
   `kEdSuccessBorder`, `kEdSuccessBg`, `kEdSuccessIcon`,
   `kEdDangerBorder`, `kEdDangerBg`.

2. A top-level function `FThemeData buildEventEditorTheme()` that constructs the `FColors` from the spec values and delegates to `FThemeData(colors: colors, touch: true)`. All widget styles auto-derive via Forui's `.inherit()` factories.

The spec's named colour fields map exactly to `FColors` constructor parameters available in Forui 0.26.0:
`primary`, `primaryForeground`, `secondary`, `secondaryForeground`,
`muted`, `mutedForeground`, `background`, `foreground`,
`border`, `destructive`, `destructiveForeground`, `error`, `errorForeground`.
The `card` field (required by `FColors`) is set to `kEdSurface`.

**Geist w500 gap**: Only Geist-Regular (400), Geist-SemiBold (600), and Geist-Bold (700) are on disk and registered in `pubspec.yaml`. The spec calls for w500 field labels. Use `FontWeight.w500` in code — Flutter will substitute the nearest registered weight (w600 SemiBold). Do NOT substitute a different font. Add `Geist-Medium.ttf` to `assets/fonts/` and register it in `pubspec.yaml` to fully satisfy the spec; without it, field labels will render at w600.

### 2b. Sticky header / scrollable body / sticky footer

The existing `build()` structure in `_EventEditorDrawerState` is already a `Column` with:
```
Column
├── drag handle
├── header Row  ← currently title + close button only
├── Flexible(SingleChildScrollView)  ← scrollable body
└── Padding(bottom actions)  ← sticky footer
```

The redesign keeps this exact structure:
- **Sticky header** — expand the existing header Row into a fixed `Column` child:
  - Row: title (20px/600) + subtitle (14px mutedForeground) + 32×32 close button
  - Below: `EventTypeSelector` (3-way segmented control) — moved here from the scrollable body
- **Scrollable body** — replace the flat field list with six `_SectionCard` widgets (one per section), each wrapping existing widget-builder calls
- **Sticky footer** — replace the existing `EventEditorBottomActions` wrapper with a new spec footer: live summary `Text` on left + Cancel + submit buttons on right

The outer `Container` is wrapped in `FTheme(data: buildEventEditorTheme(), child: ...)` so the custom colour scope is confined to the drawer. A `ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680))` wraps the Container to limit width on wider viewports.

### 2c. `_SectionCard` private widget

Add a `_SectionCard` `StatelessWidget` at the bottom of `event_editor_drawer.dart`. Fields:
- `String title` (section heading — 28px/600)
- `Widget child`

It renders a `Container` with: `kEdMuted`-fill background, 1px `kEdCardBorder` border, 12px border radius, 24px padding. Engineer must keep it `_private` (leading underscore) — it is not referenced outside this file.

### 2d. Collapsed/expandable sections

Use `AnimatedSize` + `ClipRect` at each collapsible call site. The reveal condition uses existing state that is already present:
- **Load-in**: `_loadInHour == null` → show "+ Set Load-in" button; `!= null` → show time pickers (already exists in `GigFormFields.buildLoadInTimeSelector`)
- **Soundcheck**: `_soundcheckHour == null` → show "+ Set Soundcheck" button; `!= null` → show time pickers. **NEW state variables** in `_EventEditorDrawerState`: `_soundcheckHour`, `_soundcheckMinutes`, `_soundcheckIsPM` (all `int?`/`bool?`). These are UI-only and are **not included in `_buildFormData()`** and **not written to the database** in this redesign (saving soundcheck to a DB column is out of scope — see §10).
- **Gig Pay**: `_gigPayDetails == null` → show "+ Set gig pay" button; `!= null` → show summary row (already handled in `GigFormFields.buildGigPayButton`)

The `AnimatedSize` wraps the content that shows/hides; `ClipRect` prevents paint overflow during animation. Duration: 150ms, curve: `Cubic(0.4, 0, 0.2, 1)` (spec's cubic-bezier).

---

## 3. Files to Modify

| File | Change |
|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Restructure `build()`: wrap in `FTheme`, move segmented control to header, replace flat field list with 6 `_SectionCard` items, add `_SectionCard` private widget, add soundcheck state vars, update footer to live-summary layout |
| `lib/features/events/widgets/event_type_selector.dart` | Restyle to spec: track uses `secondary` (#141417), indicator stays `primary`, overall height 44px, border `segmentedBorder` |
| `lib/features/events/widgets/event_form_fields.dart` | Restyle date button (40px, inputFill bg), time selects, AM/PM pill toggle, ±15-min duration stepper readout, notes textarea to spec |
| `lib/features/events/widgets/gig_form_fields.dart` | Restyle all gig-specific controls (venue/name input, potential toggle, contacts, address inputs, load-in time, gig pay, expenses) to spec; add Soundcheck collapsible sub-row wired to new state callbacks passed in from drawer |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Restyle location autocomplete, potential/recurring toggles, availability grid, member grid to spec |
| `lib/features/events/widgets/event_editor_helpers.dart` | Restyle `EventTextField`, `AmPmToggleButton`, `AvailabilityButton` to spec (40px inputs, inputFill, 8px radius, 44×24 toggle pill, success/danger state colours) |
| `lib/features/events/widgets/event_editor_actions.dart` | Restyle footer: add live-summary `Text` slot (passed as a new optional `String? summary` param), update button heights/styles to spec |

---

## 4. Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Public API — all callers use this; signature must not change |
| `lib/features/events/models/event_form_data.dart` | Model layer — no changes to data shape |
| `lib/features/events/events_repository.dart` | Data layer — no DB interactions added/removed/altered |
| All files outside `lib/features/events/widgets/` and `lib/app/theme/` | Out of scope for this visual-only redesign |

---

## 5. DB / RLS / RPC Impact

**Not applicable.** This is a pure UI change. No database interactions are added, removed, or altered. No migrations, RLS policies, RPCs, or edge functions are touched. The soundcheck time fields introduced in the UI are UI-only state and are not persisted.

---

## 6. Flutter Architecture Changes

- **No new providers, controllers, or repositories.** All existing Riverpod providers are referenced unchanged.
- **No new packages.** `AnimatedSize`, `ClipRect`, `FTheme` are all already available.
- **`FTheme` scope**: The app-level `FTheme` (in `main.dart`) is not modified. The drawer creates its own inner `FTheme` scope using `buildEventEditorTheme()`. Forui widgets inside the drawer inherit the drawer-scoped theme; everything outside the drawer is unaffected.
- **`_SectionCard`** is file-private — it does not become a new public API surface.

---

## 7. Files to Create

| File | Purpose |
|---|---|
| `lib/app/theme/event_editor_theme.dart` | Extra colour token `const`s + `buildEventEditorTheme()` returning `FThemeData` |

---

## 8. Change Budget

| File | Expected net line delta |
|---|---|
| `event_editor_theme.dart` (new) | +55 |
| `event_editor_drawer.dart` | +220 (build restructure, _SectionCard, soundcheck state vars, footer summary slot) |
| `event_type_selector.dart` | +20 (restyle only) |
| `event_form_fields.dart` | +60 |
| `gig_form_fields.dart` | +90 (soundcheck sub-row is new) |
| `rehearsal_form_fields.dart` | +45 |
| `event_editor_helpers.dart` | +25 |
| `event_editor_actions.dart` | +30 (summary slot) |
| **Total** | **~545 lines net** |

New public classes/methods: 1 (`buildEventEditorTheme()`).
New dependencies: 0.

---

## 9. System Impact Map

| System | Status |
|---|---|
| Gigs | Affected (visual only — save/delete logic unchanged) |
| Rehearsals | Affected (visual only — save/delete logic unchanged) |
| Block Outs | Affected (visual only — save/delete logic unchanged) |
| Setlists | Unaffected |
| Members | Unaffected (member availability grid re-styled only) |
| Auth / Session | Unaffected |
| Routing / Deep Links | Unaffected |
| Notifications | Unaffected |
| Platforms | All platforms affected equally — no platform-conditional code introduced |
| Database / RLS / RPC | Unaffected |

---

## 10. Regression Risk

**MEDIUM.** The drawer is the single most complex stateful widget in the app (3321 lines, 30+ state variables, 3 event types, RBAC, multi-date, expenses sub-view). The business logic is untouched, but any build-method restructuring carries risk of:
- Missing a widget in the section card reorganisation (field rendered in wrong section or not rendered at all)
- Breaking the `_isEditingExpense` sub-view path (it replaces the normal body content — must stay intact in the new section-card layout)
- Soundcheck state vars not initialised in `initState` / not disposed in `dispose`

Regression risk is **not** HIGH because no save/delete code paths change and no provider wiring changes.

---

## 11. Engineer Task Breakdown

**Implement in this exact order.**

1. **Create `lib/app/theme/event_editor_theme.dart`**
   Define all extra colour tokens as `const Color` (prefix `kEd` to avoid global namespace pollution).
   Define `FThemeData buildEventEditorTheme()`:
   ```dart
   FColors(
     brightness: Brightness.dark,
     systemOverlayStyle: SystemUiOverlayStyle.light,
     barrier: const Color(0x7A000000),
     background: const Color(0x09090B),   // spec background
     foreground: const Color(0xFFFAFAFA),
     primary: const Color(0xFFfb2c5a),
     primaryForeground: Colors.white,
     secondary: const Color(0xFF141417),
     secondaryForeground: const Color(0xFFa1a1aa),
     muted: const Color(0xFF101013),
     mutedForeground: const Color(0xFF8b8b93),
     destructive: const Color(0xFFf87171),
     destructiveForeground: Colors.white,
     error: const Color(0xFFf87171),
     errorForeground: Colors.white,
     card: kEdSurface,           // 0x0c0c0e
     border: const Color(0xFF27272a),
   )
   ```
   Then `return FThemeData(colors: colors, touch: true);`

2. **Rewrite `event_type_selector.dart`**
   Same widget interface (`selectedType`, `availableTypes`, `isEditMode`, `isSaving`, `onTypeChanged`).
   Track: `Container` with `secondary` fill (#141417), 1px `segmentedBorder` (#26262b) border, 12px radius, 3px padding.
   Sliding indicator: `primary` fill, 9px radius.
   Labels: 14px Geist, w600, white when selected / `secondaryForeground` when unselected.
   Animate with `AnimatedAlign` + `AnimatedDefaultTextStyle` exactly as today.

3. **Add soundcheck state to `event_editor_drawer.dart`**
   In `_EventEditorDrawerState`, add alongside the load-in block:
   ```dart
   int? _soundcheckHour;
   int? _soundcheckMinutes;
   bool? _soundcheckIsPM;
   ```
   Add corresponding setters / `_markDirty()` wires identically to the load-in pattern.
   These three vars are NOT included in `_buildFormData()`.

4. **Restructure `build()` in `event_editor_drawer.dart`**
   a. Wrap the returned widget in `FTheme(data: buildEventEditorTheme(), child: ...)`.
   b. Wrap the `Container` in `Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680), child: ...))`.
   c. Change `Container.decoration.color` to `kEdSurface`, add `border: Border.all(color: kEdCardBorder, width: 1)`, add `boxShadow: [BoxShadow(color: Color(0x8C000000), blurRadius: 60, offset: Offset(0, 24))]`, set `borderRadius: BorderRadius.circular(14)` on both top and bottom corners.
   d. Sticky header `Column` child (fixed, not inside `Flexible`):
      - Row: title text (20px/600/foreground) + optional subtitle + 32×32 close icon button
      - `SizedBox(height: 12)`
      - `EventTypeSelector(...)` — move here from scrollable body; show in create mode only (keep `if (!_isEditMode)` guard)
      - `SizedBox(height: 16)`
   e. Scrollable body: replace the flat `Column` with six `_SectionCard` widgets inside the `SingleChildScrollView`. Preserve all existing conditionals (`_isEditingExpense`, `_eventType == EventType.blockOut`, etc.) exactly. The `GigExpenseSubView` replaces the normal body as before — it wraps the entire scrollable content area; it is NOT inside a `_SectionCard`.
   f. Map sections for **gig** type:
      - **The gig** card: `gigFormFields!` (name + potential toggle + availability grid)
      - **Schedule** card: `eventFormFields` (date + time + duration) + `gigFormFields!.buildLoadInTimeSelector(context)` + new soundcheck row
      - **Location** card: `gigFormFields!.buildAddressField(context)` + `gigFormFields.buildCityStateRow(context)`
      - **Show prep** card: `eventFormFields.buildSetlistSelector(context, ref)` + `gigFormFields.buildContactsSection(context)`
      - **Money** card: `gigFormFields!.buildGigPayButton(context)` + `gigFormFields.buildExpensesSection(context)`
      - **Notes** card: `eventFormFields.buildNotesSection()`
   g. Map sections for **rehearsal** type:
      - **Location** card: `rehearsalFormFields!.buildPotentialSection(context, ref)` + `rehearsalFormFields`
      - **Schedule** card: `eventFormFields`
      - **Notes** card: `eventFormFields.buildNotesSection()`
   h. Map sections for **blockOut** type: keep existing `_buildBlockOutForm()` unchanged, no `_SectionCard` wrapper (block-out is a simple 3-field form, not a 6-section layout).
   i. Sticky footer: pass the current event summary string to `EventEditorBottomActions` via a new `summary` param (see Task 8).

5. **Add `_SectionCard` private widget to `event_editor_drawer.dart`**
   ```dart
   class _SectionCard extends StatelessWidget {
     const _SectionCard({required this.title, required this.child});
     final String title;
     final Widget child;
     @override
     Widget build(BuildContext context) { ... }
   }
   ```
   Container: fill `kEdMuted` (#101013), border 1px `kEdCardBorder` (#1f1f23), radius 12px, padding 24px.
   Title: 28px / w600 / -0.025em letterSpacing / `foreground` colour (from `FTheme.of(context).colors`).

6. **Rewrite `event_form_fields.dart`**
   Keep the same constructor + all existing props. Restyle only:
   - Date button: 40px height, `kEdInputFill` bg, `border` outline, 8px radius, calendar icon, formatted date text.
   - Time row: hour + minutes `DropdownButton`-style selects (40px, `kEdInputFill`, 8px radius) + AM/PM pill toggle (see `AmPmToggleButton` in Task 7).
   - Duration row: `−` and `+` buttons (40px square, `kEdInputFill` bg, `border` border, 8px radius) flanking a centred readout label.
   - Notes textarea: `kEdInputFill` fill, `border` outline, 8px radius, min 3 lines.
   - Setlist chips: horizontally scrollable `Wrap` / `Row`, chip radius 999px, primary-outlined 1.5px solid border.

7. **Rewrite `event_editor_helpers.dart`**
   `EventTextField`: 40px min-height, `kEdInputFill` fill, `border` outline, 8px radius, `kEdPlaceholder` hint colour. Focus ring: `primary` border + shadow.
   `AmPmToggleButton`: 44×24 pill track on `secondary`, 20×20 thumb animates to `primary`. Replace the existing discrete pair of buttons with a single toggle track widget that owns both AM and PM. The existing call sites in `event_form_fields.dart` and `gig_form_fields.dart` already pass the two buttons separately — consolidate into a single `AmPmToggle` widget that takes `isPM` + `onChanged` + `isSaving`.
   `AvailabilityButton`: update to use `kEdSuccessBg`/`kEdSuccessBorder`/`kEdSuccessIcon` and `kEdDangerBg`/`kEdDangerBorder` instead of the old `context.colors.success` / `AppColors.error` tints.

8. **Rewrite `event_editor_actions.dart`**
   Add an optional `String? summary` parameter to `EventEditorBottomActions`. When non-null/non-empty, render a `Text(summary, ...)` above the button row (14px / `mutedForeground`). This is the "live summary left" in the spec footer. Keep existing `canSave`, `isSaving`, `isDeleting`, `primaryButtonLabel`, `onSave`, `onCancel` props unchanged.
   Cancel: outline button, 8px radius, 40px height.
   Submit: filled primary, 8px radius, 40px height.
   Padding: 16px horizontal, 12px vertical (above keyboard-safe area padding handled by the outer `Padding` in the drawer).

9. **Rewrite `gig_form_fields.dart`**
   Keep all constructor props and builder methods intact (same public surface). Restyle all controls to spec. Add a new `buildSoundcheckRow(BuildContext context)` builder method that renders the Soundcheck collapsible sub-row, wired to:
   - `soundcheckHour`, `soundcheckMinutes`, `soundcheckIsPM` props (nullable int/bool)
   - `onSoundcheckTimeSet`, `onSoundcheckTimeCleared`, `onSoundcheckHourChanged`, `onSoundcheckMinutesChanged`, `onSoundcheckAmPmChanged` callbacks
   The drawer calls `gigFormFields!.buildSoundcheckRow(context)` inside the **Schedule** section card.

10. **Rewrite `rehearsal_form_fields.dart`**
    Keep all constructor props and builder methods. Restyle to spec. No new props.

11. **Run `flutter analyze`**
    Fix all errors. Zero warnings/errors is the bar.

---

## 12. Verification Plan

### Tier 1 — pre-deploy (no live system calls)

- `flutter analyze` returns 0 errors, 0 warnings.
- Widget test in `test/features/events/widgets/event_editor_drawer_test.dart` (create the test group if it doesn't exist, add one case): pump `EventEditorDrawer` in create mode with `initialEventType: EventType.gig`, verify it renders without exception, the drawer title text is present, and the segmented control is in the header area (above the scroll region).
- Widget test: pump with `initialEventType: EventType.rehearsal`, verify no exception.
- Widget test: pump with `initialEventType: EventType.blockOut`, verify block-out form renders without section cards.

### Tier 2 — post-deploy manual checks

1. Drawer opens from the calendar and dashboard add-event buttons — no exception.
2. Sticky header shows title + subtitle + 32×32 close button; segmented control is visible below title without scrolling.
3. Switching event type (Rehearsal / Gig / Block Out) in create mode updates visible sections immediately.
4. Gig form — scroll through all 6 section cards; verify all sections are visible and labelled.
5. Load-in collapsed by default → tap "+ Set Load-in" → time pickers appear with `AnimatedSize`.
6. Soundcheck collapsed by default → tap "+ Set Soundcheck" → time pickers appear.
7. Gig Pay collapsed by default → tap button → `GigPayBottomSheet` opens; on return, pay summary appears in card.
8. Create a gig, save — verify Supabase row created correctly (name, date, time, city, contacts).
9. Edit an existing gig — verify all fields pre-populate, save updates the row, delete removes it.
10. `viewOnly: true` — verify all fields are non-interactive and save/delete are hidden.
11. Contributor RBAC — verify forced potential-only mode still locks the potential toggle on.
12. Spot-check key colours:
    - Drawer background is `#0c0c0e` (not `#18181b`).
    - Section card borders are visible at `#1f1f23`.
    - Segmented control track is `#141417`.
    - Active segment fill is `#fb2c5a`.
    - Submit button is `#fb2c5a` filled.

---

## 13. QA Regression Areas

- All three event types create and save without error.
- All three event types edit and save without error.
- All three event types delete without error.
- Block-out create, edit, delete unchanged.
- Multi-date potential gig: dates display, per-date availability grid renders.
- Expense sub-view: entering the expense editor, saving, deleting an expense.
- Setlist picker: chip row shows, tapping opens setlist selector.
- Contact autocomplete: typing shows suggestions, selecting resolves.
- Recurring rehearsal: toggle shows recurrence section, save creates series, "Delete All" deletes series.
- `viewOnly` mode: no edit controls are interactive.

---

## 14. Rollout Strategy

This is a visual-only change. Normal PR → QA → merge to `main` flow. No feature flag needed. No database migration needed. No staged rollout needed.

---

## 15. Out of Scope

- Saving soundcheck time to any database column — deferred to a future feature.
- Adding the Geist-Medium (w500) font file to the asset bundle — flagged as a gap but not blocking this plan; add the file in a separate PR.
- Theming any widget outside `lib/features/events/widgets/` with the event-editor colour tokens.
- Changing the presentation layer (`showAppBottomSheet` call in `add_edit_event_bottom_sheet.dart`).
- Any changes to the Gig Pay bottom sheet (`gig_pay_bottom_sheet.dart`).
- Any changes to the expense sub-view (`gig_expense_subview.dart`).
