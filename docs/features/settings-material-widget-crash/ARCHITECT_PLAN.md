# ARCHITECT_PLAN.md

**Feature Slug:** `bug/settings-material-widget-crash`

---

## Problem Summary

Opening the Settings screen throws `No Material widget found` exception (InkWell in `_SettingsListItem`, line 479), fired 4 times, immediately followed by `A RenderFlex overflowed by 499421 pixels on the bottom`. User reports the app is on iOS device, but the root cause affects all platforms (shared cross-platform code).

During unrelated device testing on 2026-08-19, a similar but softer failure mode was observed: `ListTile background color or ink splashes may be invisible` warning fired ~47 times when opening gig/rehearsal edit sheets, indicating a broader systemic issue beyond Settings.

**Scope correction #1 (2026-08-19, post-Task 1 & 2 completion):** Physical device verification surfaced a third crash site with identical root cause: `one_calendar_settings_screen.dart` uses `Switch.adaptive` (lines 302, 452) inside `AppScaffold` → `FScaffold` (no Material ancestor), triggering same `No Material widget found` exception. This was not covered by the original plan and requires an additional task (Task 3 below).

**Scope correction #2 (2026-08-19, post-Task 3 completion):** Physical device verification surfaced a fourth crash site in the same file: `one_calendar_settings_screen.dart` uses raw `Radio<ApplyToMode>` widget (line 346 in `_ApplyToRadioTile`) inside `AppScaffold` → `FScaffold`. Confirmed live on device: `No Material widget found. Radio<ApplyToMode> widgets require a Material widget ancestor`. This requires an additional task (Task 4 below).

---

## Root Cause

**Confidence:** **HIGH** (confirmed via code inspection)

The Forui design system migration replaced Material's Scaffold with Forui's FScaffold, which provides no Material ancestor.

**Primary failure (SettingsListItem):**

- `_SettingsListItem` (line 466-526) uses raw `InkWell` widget
- `InkWell` is a Material-only widget that requires a Material ancestor for ink effects
- `AppScaffold` → `FScaffold` → body (no Material anywhere in chain)
- Result: Hard crash with `No Material widget found` exception

**Primary failure (One Calendar settings — Switch.adaptive):**

- `one_calendar_settings_screen.dart` uses raw `Switch.adaptive` widget (lines 302, 452) in `_MasterToggleCard` and `_AutoConflictToggleCard`
- `Switch.adaptive` (and its Material variant `Switch`) require a Material ancestor for rendering
- `AppScaffold` → `FScaffold` → body (no Material anywhere in chain)
- Result: Hard crash with `No Material widget found` exception (`_MaterialSwitch widgets require a Material widget ancestor`)
- Pattern inconsistency: all other settings/config screens in codebase use `AppSwitch` (Forui wrapper), not raw Material `Switch`

**Primary failure (One Calendar settings — Radio):**

- `one_calendar_settings_screen.dart` uses raw `Radio<ApplyToMode>` widget (line 346) in `_ApplyToRadioTile.build()`
- `Radio` is a Material-only widget that requires a Material ancestor for rendering
- Widget tree: `RadioGroup<ApplyToMode>` (line 147) → `AppScaffold` → `FScaffold` → body (no Material anywhere in chain)
- Result: Hard crash with `No Material widget found` exception (`Radio<ApplyToMode> widgets require a Material widget ancestor`)
- Pattern gap: No `AppRadio` facade exists in codebase, and Forui radio primitive has never been used directly — building new architecture now would be out of scope per Hard Rules
- Fix: Wrap `_ApplyToRadioTile.build()` return value in `Material(color: Colors.transparent)`, same pattern as Task 1's `_SettingsListItem` fix

**Secondary failure (navigation picker bottom sheets):**

- `showAppBottomSheet` (line 31 in `app_bottom_sheet.dart`) wraps builder content in `Material(type: MaterialType.transparency)`
- `ListTile` widgets in navigation pickers (`view_gig_drawer.dart:130-144`, `view_rehearsal_drawer.dart`, `venue_detail_screen.dart:307-321`) require a Material ancestor with **non-transparent type** for proper ink splash rendering
- `MaterialType.transparency` does NOT provide an ink surface, only a Material ancestor for type-checking
- Result: Soft warning `ListTile background color or ink splashes may be invisible` (~47 occurrences reported)

**Tertiary failure (RenderFlex overflow):**

- Downstream cascade from primary exception
- When Material exception corrupts the build tree during widget construction, layout calculations fail, producing garbage overflow error
- Same failure pattern as `bug/inherited-widget-crash-investigation` (merged 2026-08-19, commit 49a24cf)
- Not an independent root cause — will resolve automatically when primary failure is fixed

---

## Reference Docs Consulted

- `docs/features/forui-design-system-swap/ARCHITECT_PLAN.md` — Confirmed Forui migration design decision, FScaffold replacement strategy, Material → Forui component mapping
- `docs/features/forui-design-system-swap/ENGINEER_REPORT.md` — Confirmed AppScaffold Scaffold → FScaffold swap completed in Task 3
- `docs/features/forui-design-system-swap/QA_REPORT.md` — No Material-only widget gaps flagged during QA (regression)
- `docs/agents/GUARDRAILS.md` — Confirmed constraints: prefer smallest change, no opportunistic cleanup, weigh regression risk for high-blast-radius changes

No Settings-specific or Material/Forui architecture reference docs found in `docs/reference/ui/` or `docs/reference/architecture/`.

---

## Existing System Analysis

**Current behavior:**

1. User opens Settings from drawer
2. `SettingsScreen` renders via `AppScaffold` wrapper
3. `AppScaffold.build()` returns `FScaffold(header: appBar, footer: bottomNavigationBar, child: body)`
4. Settings body contains `ListView.builder` of `_SettingsListItem` widgets (Notifications, Song Enrichment, GetSongBPM, One Calendar if 2+ bands, Delete Account)
5. Each `_SettingsListItem.build()` returns `InkWell(onTap: item.onTap, child: ...)`
6. Flutter framework attempts to render `InkWell` → searches widget tree for Material ancestor → finds none → throws exception
7. Exception corrupts build tree → layout calculations produce RenderFlex overflow
8. Exception logged 4 times (one per list item + Delete Account item)

**Data flow:** None — pure UI rendering issue, no data layer involved.

**Affected widget tree path:**

```
MaterialApp → Navigator → SettingsScreen → AppScaffold → FScaffold →
  body (ListView) → _SettingsListItem → InkWell [NO MATERIAL ANCESTOR]
```

**Bottom sheet failure path:**

```
MaterialApp → Navigator → [screen] → showAppBottomSheet → FSheet →
  Material.transparency → SafeArea → [navigation picker content] → ListTile
  [TRANSPARENT MATERIAL — INSUFFICIENT FOR INK EFFECTS]
```

---

## Proposed Solution

**Minimal fix with lowest blast radius:** Local Material wrappers for affected widgets only. Do NOT modify `AppScaffold` globally (used by 30 call sites across 22 files — too high regression risk for a narrowly-scoped bug).

### Fix 1: Settings screen InkWell (primary failure)

Wrap `InkWell` in `_SettingsListItem.build()` with `Material(color: Colors.transparent)`:

```dart
return Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: item.onTap,
    child: Padding(
      // ... existing content
    ),
  ),
);
```

**Rationale:**

- Provides Material ancestor for InkWell ink effects
- `Colors.transparent` maintains visual appearance (no added background chrome)
- Unlike `MaterialType.transparency`, `Material(color: Colors.transparent)` provides a proper ink surface
- Localized to one widget (26 lines) — zero blast radius beyond Settings

### Fix 2: Bottom sheet ListTile warnings (secondary failure)

Change `Material(type: MaterialType.transparency)` to `Material(color: Colors.transparent)` in `showAppBottomSheet` (line 31, `app_bottom_sheet.dart`):

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(
    color: Colors.transparent,  // Changed from type: MaterialType.transparency
    child: builder(context),
  ),
  // ...
);
```

**Rationale:**

- `Material(color: Colors.transparent)` provides a proper ink surface for ListTile ink effects while maintaining visual transparency
- Fixes all 9 ListTile usages across 4 files (gig/rehearsal/venue navigation pickers) in one change
- Medium blast radius (all bottom sheets), but visual impact is zero (transparent → transparent, only ink surface behavior changes)
- Aligns with Material design guidelines: ink effects require non-transparent Material type

**Alternative considered and rejected:**

- Wrap each ListTile individually in Material widget → requires changes in 4 files (gig, rehearsal, venue, setlists), more complex, harder to maintain
- Change to `MaterialType.canvas` or `MaterialType.card` → adds unwanted background color, breaks visual design

---

## Database Impact

**Database:** Not applicable. This is a pure Flutter widget layer issue. No migrations, RLS policies, RPCs, or triggers affected.

---

## Flutter Architecture Changes

**State management:** No changes. Issue is in stateless presentation layer only.

**Widgets affected:**

- `lib/features/settings/settings_screen.dart` — `_SettingsListItem` widget (lines 466-526)
- `lib/components/ui/app_bottom_sheet.dart` — `showAppBottomSheet` function (line 31)
- `lib/features/calendar/one_calendar_settings_screen.dart` — `_MasterToggleCard`, `_AutoConflictToggleCard` (Switch.adaptive → AppSwitch), `_ApplyToRadioTile` (Radio Material wrapper)

**Repositories:** None

**Controllers/Providers:** None

---

## Files to Create

**None.** All fixes are modifications to existing files.

---

## Files to Modify

| File                                                      | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/settings_screen.dart`              | Wrap `InkWell` in `_SettingsListItem.build()` (line 479) with `Material(color: Colors.transparent)` wrapper. Add 2 lines (Material open/close), indent InkWell and children by 2 spaces. Total delta: ~4 lines changed.                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/components/ui/app_bottom_sheet.dart`                 | Change `Material(type: MaterialType.transparency, child: builder(context))` (line 31) to `Material(color: Colors.transparent, child: builder(context))`. Single-line parameter change.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/calendar/one_calendar_settings_screen.dart` | **Task 3:** Replace `Switch.adaptive` with `AppSwitch` (2 instances: lines 302, 452). Add import: `import '../../components/ui/app_switch.dart';`. Replace `Switch.adaptive(value: enabled, onChanged: onChanged, activeTrackColor: AppColors.primary)` with `AppSwitch(value: enabled, onChanged: onChanged, activeTrackColor: AppColors.primary)`. Total delta: 1 import + 2 widget swaps. **Task 4:** Wrap `_ApplyToRadioTile.build()` returned `Container` (around line 314) in `Material(color: Colors.transparent)` wrapper, same pattern as Settings InkWell fix. Add 2 lines (Material open/close), indent Container and children by 2 spaces. Total delta: ~3 lines changed. |

---

## Files Off-Limits

| File                                                                                                                  | Reason                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_scaffold.dart`                                                                                 | Used by 30 call sites across 22 files. Adding Material wrapper here would fix the issue globally but carries too high regression risk (subtle theme inheritance changes, potential double-Material stacking in screens that already add their own Material widgets). Per Hard Rules: prefer smallest change. Local fixes are sufficient.                                                                                                                                                                                                                                                                 |
| `lib/main.dart`                                                                                                       | Init order must not change (Guardrail #1). Not relevant to this bug.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| All test files                                                                                                        | No test changes required — this is a runtime rendering issue, not a behavioral change. Existing tests do not validate Material ancestor presence.                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| All files with ListTile not inside AppScaffold context                                                                | `band_form_screen.dart` (uses `showModalBottomSheet`, Material's bottom sheet, already has proper Material ancestor), `setlists/widgets/key_picker_bottom_sheet.dart` (same). No changes needed.                                                                                                                                                                                                                                                                                                                                                                                                         |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart` (Switch widgets) | Both files use raw `Switch` widget (not `Switch.adaptive`) at lines 883, 908, 987 (add_financial_entry) and 487 (gig_pay). However, both are shown via `showModalBottomSheet` (Flutter's Material bottom sheet, line 82 in add_financial_entry), NOT via `showAppBottomSheet`. `showModalBottomSheet` provides a Material ancestor automatically. These switches are NOT affected by this bug. No changes needed. Confirmed via code inspection: `showAddFinancialEntrySheet()` and `GigPayBottomSheet` presentation via `showModalBottomSheet` in event_editor_drawer.dart:2396 and financials screens. |

---

## System Impact Map

| System                                 | Impact                                                                                                                                        |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Settings                               | **affected** — InkWell crash fixed by Material wrapper                                                                                        |
| Gigs                                   | **affected** — navigation picker ListTile warnings fixed by bottom sheet Material type change                                                 |
| Rehearsals                             | **affected** — navigation picker ListTile warnings fixed by bottom sheet Material type change                                                 |
| Venues                                 | **affected** — navigation picker ListTile warnings fixed by bottom sheet Material type change                                                 |
| Setlists / Catalog                     | **unaffected** — no raw Material widgets in AppScaffold context; bottom sheet fix improves ink effects if ListTile is used in future overlays |
| Members / RBAC                         | **unaffected**                                                                                                                                |
| Auth / Session                         | **unaffected**                                                                                                                                |
| Routing                                | **unaffected**                                                                                                                                |
| Notifications                          | **unaffected**                                                                                                                                |
| Financials                             | **unaffected** — uses Material `Scaffold`, not `AppScaffold`                                                                                  |
| Platform (iOS / Android / Web / macOS) | **all affected** — AppScaffold and AppBottomSheet are shared cross-platform code; fixes apply universally                                     |

---

## Regression Risk

**Overall risk:** **LOW**

**Rationale:**

**Fix 1 (Settings InkWell):**

- **Blast radius:** 1 widget in 1 screen (Settings only)
- **Risk:** Minimal. Material(color: Colors.transparent) is a standard Flutter pattern for providing Material ancestor without visual chrome. Used extensively in existing codebase (21 files, 31 usages confirmed via grep).
- **Visual impact:** Zero — transparent → transparent
- **Behavioral impact:** Adds ink splash effect to Settings list items (currently broken/invisible due to missing Material ancestor) — this is the **intended** behavior

**Fix 2 (Bottom sheet Material type):**

- **Blast radius:** All bottom sheets opened via `showAppBottomSheet` (medium blast radius)
- **Risk:** Low. Material(color: Colors.transparent) vs MaterialType.transparency only affects ink surface availability, not visual rendering. Both are transparent. Change enables ListTile ink effects that were previously invisible/broken.
- **Visual impact:** Zero under normal conditions. Only affects ink splash rendering when ListTile or InkWell are used inside bottom sheets — currently broken, fix restores intended behavior.
- **Behavioral impact:** Restores proper ink splash effects for ListTile widgets in bottom sheets (navigation pickers). May enable ink effects for any future InkWell/Ink widgets added to bottom sheet content (desirable, not a regression).

**Why NOT fixing AppScaffold globally:**

- AppScaffold is used by 30 call sites across 22 files
- Adding Material wrapper inside AppScaffold could:
  - Create double-Material stacking where screens add their own Material widgets (e.g., dialogs, overlays)
  - Subtly alter theme inheritance behavior (Material introduces a Material theme scope)
  - Affect elevation/shadow rendering if Material elevation is non-zero
  - Break assumptions in screens that explicitly avoid Material chrome (e.g., auth screens with custom backgrounds)
- Local fixes are surgical, testable in isolation, and carry zero risk of unintended side effects

**Mitigation:**

- Test Settings screen specifically: tap each list item, verify ink splash renders correctly
- Test navigation picker bottom sheets (gig/rehearsal/venue "Open with" → tap Apple Maps/Google Maps/Waze), verify ListTile ink splash renders correctly
- Visual regression test: compare Settings and navigation pickers before/after on iOS device (user's repro platform)
- No automated test changes required — this is a visual/runtime rendering fix, not a behavioral change

---

## Engineer Task Breakdown

Execute in order. Do not skip tasks. Each task must be atomic and testable independently.

### Task 1: Fix Settings screen InkWell Material ancestor

**File:** `lib/features/settings/settings_screen.dart`

**Action:** Modify `_SettingsListItem.build()` method (lines 472-526).

**Current code (line 479):**

```dart
return InkWell(
  onTap: item.onTap,
  child: Padding(
    // ... existing content
  ),
);
```

**New code:**

```dart
return Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: item.onTap,
    child: Padding(
      // ... existing content
    ),
  ),
);
```

**Validation:**

- No additional imports required (`Material` and `Colors` are already imported via `package:flutter/material.dart`)
- Build succeeds (`flutter analyze` passes)
- Open Settings screen → tap each list item (Notifications, Song Enrichment, GetSongBPM, One Calendar if 2+ bands, Delete Account) → verify ink splash renders correctly, no console exceptions

### Task 2: Fix bottom sheet Material type for ListTile ink effects

**File:** `lib/components/ui/app_bottom_sheet.dart`

**Action:** Modify `showAppBottomSheet` function (line 31).

**Current code:**

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(
    type: MaterialType.transparency,
    child: builder(context),
  ),
  // ...
);
```

**New code:**

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(
    color: Colors.transparent,
    child: builder(context),
  ),
  // ...
);
```

**Validation:**

- No additional imports required (`Material` and `Colors` are already imported via `package:flutter/material.dart`)
- Build succeeds (`flutter analyze` passes)
- Open gig detail drawer → tap venue/location → tap "Open with" → bottom sheet appears with Apple Maps/Google Maps/Waze options → tap each option → verify ListTile ink splash renders correctly, no console warnings
- Repeat for rehearsal detail drawer and venue detail screen

### Task 3: Replace Switch.adaptive with AppSwitch in One Calendar settings

**File:** `lib/features/calendar/one_calendar_settings_screen.dart`

**Action:** Replace 2 instances of `Switch.adaptive` with `AppSwitch` component (lines 302, 452).

**Rationale:**

- `AppSwitch` wraps Forui's `FSwitch`, which does not require Material ancestor (already part of Forui design system migration)
- Codebase pattern: all other settings/config screens already use `AppSwitch` (notifications, gig form, rehearsal form, etc.) — this fix removes the inconsistency
- Simpler than wrapping in Material (no nesting, direct replacement)
- Same blast radius as Material wrapper (just this screen), but follows established project convention

**Step 1: Add import** (after existing imports, before first widget):

```dart
import '../../components/ui/app_switch.dart';
```

**Step 2: Replace first Switch.adaptive** (line 302 in `_MasterToggleCard.build()`):

**Current code:**

```dart
Switch.adaptive(
  value: enabled,
  onChanged: onChanged,
  activeTrackColor: AppColors.primary,
),
```

**New code:**

```dart
AppSwitch(
  value: enabled,
  onChanged: onChanged,
  activeTrackColor: AppColors.primary,
),
```

**Step 3: Replace second Switch.adaptive** (line 452 in `_AutoConflictToggleCard.build()`):

**Current code:**

```dart
Switch.adaptive(
  value: enabled,
  onChanged: onChanged,
  activeTrackColor: AppColors.primary,
),
```

**New code:**

```dart
AppSwitch(
  value: enabled,
  onChanged: onChanged,
  activeTrackColor: AppColors.primary,
),
```

**Validation:**

- Import `AppSwitch` from `lib/components/ui/app_switch.dart`
- Build succeeds (`flutter analyze` passes)
- Navigate to Settings → One Calendar (requires 2+ bands) → verify both toggles render correctly
- Toggle "One Calendar" master switch → verify state updates, no console exceptions
- Toggle "Automatically block conflicting dates" → verify state updates, no console exceptions
- Verify switches render with rose accent color when enabled (AppColors.primary)
- No `No Material widget found` exceptions in console

### Task 4: Fix One Calendar Radio Material ancestor

**File:** `lib/features/calendar/one_calendar_settings_screen.dart`

**Action:** Modify `_ApplyToRadioTile.build()` method (around line 330).

**Current code:**

```dart
@override
Widget build(BuildContext context) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: Spacing.space16,
      vertical: Spacing.space12,
    ),
    decoration: BoxDecoration(
      // ... existing decoration
    ),
    child: Row(
      children: [
        Radio<ApplyToMode>(
          value: value,
          activeColor: AppColors.primary,
        ),
        // ... rest of row children
      ],
    ),
  );
}
```

**New code:**

```dart
@override
Widget build(BuildContext context) {
  return Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.space16,
        vertical: Spacing.space12,
      ),
      decoration: BoxDecoration(
        // ... existing decoration
      ),
      child: Row(
        children: [
          Radio<ApplyToMode>(
            value: value,
            activeColor: AppColors.primary,
          ),
          // ... rest of row children
        ],
      ),
    ),
  );
}
```

**Validation:**

- No additional imports required (`Material` and `Colors` are already imported via `package:flutter/material.dart`)
- Build succeeds (`flutter analyze` passes)
- Navigate to Settings → One Calendar → toggle master switch ON → "Apply To" section expands
- Tap each radio option (All Bands, Specific Bands) → verify radio selection updates correctly, no console exceptions
- Console check: Zero `No Material widget found` exceptions, zero `Radio<ApplyToMode> widgets require a Material widget ancestor` errors

### Task 5: Manual visual regression test (iOS device)

**Platform:** iOS (user's repro platform)

**Action:** Deploy to iOS device and verify:

1. Settings screen opens without console exceptions
2. Settings list items show ink splash effect on tap (light ripple animation)
3. No RenderFlex overflow error in console
4. Navigation picker bottom sheets (gig/rehearsal/venue "Open with") show ListTile ink splash on tap
5. No "ListTile background color or ink splashes may be invisible" warnings in console
6. Visual appearance is unchanged (both fixes use transparent Material, no added chrome)

**Expected console output:**

- Before fix: 4× `No Material widget found` (Settings), 2× `_MaterialSwitch widgets require a Material widget ancestor` (One Calendar switches), 2× `Radio<ApplyToMode> widgets require a Material widget ancestor` (One Calendar radio options), ~47× `ListTile background color or ink splashes may be invisible` (navigation pickers), 1× `RenderFlex overflowed by 499421 pixels`
- After fix: Zero exceptions, zero warnings

---

## Verification Plan

This is a pure UI rendering fix. No database changes, no RPC calls, no data flow changes. Verification is manual visual testing only.

**Tier 1 — Pre-deployment:** Not applicable (no database changes).

**Tier 2 — Post-deployment:** Not applicable (no deployment, local device testing only).

**Manual verification (iOS device — user's repro platform):**

1. **Settings screen InkWell fix:**
   - Clean build: `flutter clean && flutter pub get && flutter run -d <ios-device-id>`
   - Open Settings from drawer
   - **Expected:** Screen renders correctly, no console exceptions
   - Tap "Notifications" → **Expected:** Ink splash renders, navigation occurs, no console errors
   - Tap "Song Enrichment" → **Expected:** Same
   - Tap "GetSongBPM Attribution" → **Expected:** Same
   - Tap "One Calendar" (if visible with 2+ bands) → **Expected:** Same
   - Tap "Delete Account" → **Expected:** Same
   - **Console check:** Zero `No Material widget found` exceptions, zero `RenderFlex overflowed` errors

2. **One Calendar Switch.adaptive fix:**
   - From Settings, tap "One Calendar" (requires 2+ bands in user account)
   - **Expected:** Screen renders correctly, no console exceptions
   - Verify both toggle switches render correctly (master toggle at top, auto-conflict toggle below)
   - Toggle "One Calendar" master switch on → **Expected:** Switch animates, state updates, "Apply To" section expands below, no console exceptions
   - Toggle "Automatically block conflicting dates" on → **Expected:** Switch animates, state updates, no console exceptions
   - Toggle both switches off → **Expected:** State updates correctly, no console exceptions
   - **Console check:** Zero `No Material widget found` exceptions, zero `_MaterialSwitch widgets require a Material widget ancestor` errors

3. **One Calendar Radio fix:**
   - From One Calendar settings screen (Settings → One Calendar with 2+ bands)
   - Toggle "One Calendar" master switch ON → "Apply To" section expands
   - **Expected:** Section renders correctly, two radio options visible ("All Bands", "Specific Bands"), no console exceptions
   - Tap "All Bands" radio option → **Expected:** Radio selection updates, visual state changes (blue border, bold text), no console exceptions
   - Tap "Specific Bands" radio option → **Expected:** Radio selection updates, visual state changes, band checkboxes appear below, no console exceptions
   - Tap "All Bands" again → **Expected:** Radio selection updates, band checkboxes collapse, no console exceptions
   - **Console check:** Zero `No Material widget found` exceptions, zero `Radio<ApplyToMode> widgets require a Material widget ancestor` errors

4. **Bottom sheet ListTile fix:**

- Navigate to Calendar tab → tap any gig → tap venue/location field → "Open with" bottom sheet appears
- **Expected:** Bottom sheet renders, ListTile items visible
- Tap "Apple Maps" → **Expected:** Ink splash renders (light ripple), bottom sheet closes, no console warnings
- Repeat: Open bottom sheet → tap "Google Maps" → **Expected:** Same
- Repeat: Open bottom sheet → tap "Waze" → **Expected:** Same
- **Console check:** Zero `ListTile background color or ink splashes may be invisible` warnings
- Repeat above for rehearsal detail drawer (if available in calendar) and venue detail screen

5. **Visual regression check:**
   - Compare Settings screen appearance before/after fix → **Expected:** Identical (Material.transparent adds zero visual chrome)
   - Compare One Calendar settings appearance before/after fix → **Expected:** Identical, switches and radio options render correctly
   - Compare navigation picker bottom sheet appearance before/after fix → **Expected:** Identical (transparent → transparent)
   - Ink splash behavior before fix: broken/invisible due to missing ink surface
   - Ink splash behavior after fix: visible light ripple (standard Material ink effect)

---

## QA Regression Areas

QA must specifically test the following to confirm no unintended side effects:

### Primary: Settings screen

- Open Settings → verify all list items render correctly
- Tap each item → verify ink splash effect renders (light ripple animation)
- Verify no console exceptions (`No Material widget found`, `RenderFlex overflowed`)
- Verify navigation to detail screens works (Notifications, Song Enrichment, etc.)
- Verify Delete Account item renders and responds correctly

### Secondary: One Calendar settings (Switch and Radio fixes)

- Navigate to Settings → One Calendar (requires 2+ bands)
- Verify both toggle switches render correctly (master toggle, auto-conflict toggle)
- Toggle switches on/off → verify state updates correctly, no console exceptions
- Toggle master switch ON → "Apply To" section expands
- Tap each radio option (All Bands, Specific Bands) → verify radio selection updates, visual state changes correctly
- Verify no console exceptions (`_MaterialSwitch widgets require a Material widget ancestor`, `Radio<ApplyToMode> widgets require a Material widget ancestor`)

### Tertiary: Navigation picker bottom sheets

- **Gigs:** Open gig detail → tap venue → "Open with" → tap Apple Maps/Google Maps/Waze → verify ink splash renders on tap
- **Rehearsals:** Open rehearsal detail → tap location → "Open with" → tap options → verify ink splash renders
- **Venues:** Open venue detail → tap address → "Open with" → tap options → verify ink splash renders
- Verify no console warnings (`ListTile background color or ink splashes may be invisible`)

### Quaternary: Other bottom sheets (smoke test)

- Open any other bottom sheet in the app (setlist picker, add song, bulk entry, etc.)
- **Expected:** No visual regressions, no new console warnings
- Material.transparent change should be transparent (no pun intended) — only ink surface availability changes, not rendering

### Platform coverage

- **iOS:** Primary testing platform (user's repro device)
- **Android:** Smoke test Settings + one navigation picker to confirm cross-platform fix
- **Web/macOS:** Optional — shared code, but lower priority

---

## Rollout / Migration Strategy

**Not applicable.** This is a local device fix, no deployment required. No database migrations, no edge function changes, no API changes.

**Testing only:** User will test on iOS device, verify fix resolves both hard crash (Settings) and soft warnings (navigation pickers).

---

## Out of Scope

Explicitly **NOT** in scope for this phase:

1. **Systematic audit of all Material-only widgets in AppScaffold contexts:**
   - Grep search found 17 InkWell usages and 9 ListTile usages across the codebase
   - Most are inside bottom sheets (AppBottomSheet → fixed by Task 2) or dialogs (Material's showDialog provides Material ancestor)
   - Some are in screens using Material `Scaffold`, not `AppScaffold` (e.g., `financials_screen.dart`)
   - Only Settings screen confirmed broken by testing; other screens may be latent issues or may have proper Material ancestors through other paths
   - **Recommendation:** Create follow-up issue to audit all Material-only widget usages (InkWell, ListTile, Ink, InkResponse, InkDecoration) and either (a) wrap in Material locally, (b) replace with Forui equivalents (FTappable, FButton, etc.), or (c) confirm they have proper Material ancestors through dialogs/sheets/other paths

2. **Replacing Material-only widgets with Forui equivalents:**
   - Settings `InkWell` could be replaced with `FTappable.static` or custom `AppListTile` wrapper using Forui primitives
   - Navigation picker `ListTile` could be replaced with Forui components (FButton with list styling)
   - This is a **larger architectural change** (introducing new abstractions, changing visual appearance) and belongs in a separate feature after verifying the minimal fix works
   - Out of scope per Hard Rules: "do not introduce new architecture unless existing pattern cannot solve the problem"

3. **Modifying AppScaffold to provide Material ancestor globally:**
   - Rejected due to high blast radius (30 call sites, 22 files)
   - Regression risk too high for this narrowly-scoped bug
   - Local fixes are sufficient and safer

4. **Changing FloatingActionButton support in AppScaffold:**
   - Not related to this bug (FAB is not supported by FScaffold, already documented as preview cycle limitation)
   - Out of scope

5. **Fixing other potential Material-only widget issues discovered during grep:**
   - Only Settings and navigation pickers are confirmed broken by user testing
   - Other InkWell/ListTile usages may work correctly (proper Material ancestors through other paths)
   - Premature to fix without confirming breakage
   - Document as follow-up audit item (see #1 above)

---

## Follow-Up Items

Create these issues for future work:

1. **Audit and fix all Material-only widgets in non-Material contexts** (Medium priority)
   - Grep for InkWell, ListTile, Ink, InkResponse, InkDecoration across `lib/features/` and `lib/components/`
   - For each usage, verify:
     - Is it in an AppScaffold context? (Check parent widget tree)
     - Is it in an AppBottomSheet context? (Will be fixed by Task 2, but verify)
     - Is it in a Material-based dialog/sheet? (Has proper Material ancestor, OK)
     - Is it in a custom overlay/modal that might lack Material ancestor?
   - For any confirmed broken widgets, apply same fix pattern (wrap in Material.transparent locally)
   - Estimated scope: 17 InkWell + 9 ListTile = 26 potential locations, likely 5-10 need fixes after filtering

2. **Create AppListTile wrapper using Forui primitives** (Low priority, post-audit)
   - Replacement for Material `ListTile` that works in non-Material contexts
   - Use `FTappable.static` or `GestureDetector` + Forui styling
   - Migrate all ListTile usages to AppListTile over time
   - Aligns with Forui migration strategy (facade pattern, no Material dependencies)

3. **Document Material-only widget constraints in Forui migration guide** (Low priority)
   - Add to `docs/reference/architecture/` or `docs/features/forui-design-system-swap/`
   - List Material-only widgets that require Material ancestor (InkWell, ListTile, Ink, etc.)
   - Document workaround patterns (wrap in Material.transparent, or use Forui equivalents)
   - Prevents future regressions when adding new UI components

---

**End of ARCHITECT_PLAN.md**
