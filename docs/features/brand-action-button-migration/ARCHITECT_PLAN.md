# ARCHITECT_PLAN: Migrate BrandActionButton to AppButton Primary Variant

## 1. Feature Slug

`feature/brand-action-button-migration`

---

## 2. Problem Summary

BrandActionButton is a hand-rolled primary-action button component (gradient rose background + custom press animation) created before the Forui design system integration. It serves 21 files across ~24 call sites in Home, Calendar, Contacts, Bands, Gigs, Rehearsals, Profile, Members, Setlists, and Events features.

With the `feature/forui-theme-integration` merge (PR #147, commit 68af71d) now in `main`, the Forui theme uses BandRoadie's rose-primary brand accent (`AppColors.primary` = Rose-700 `#BE123C`). AppButton's primary variant now renders with rose-primary Forui styling, making BrandActionButton's custom gradient implementation redundant.

**Goal:** Migrate all BrandActionButton call sites to `AppButton(variant: AppButtonVariant.primary)` and delete the BrandActionButton widget file, consolidating on the Forui-based UI facade layer.

---

## 3. Root Cause

**Root Cause Confidence:** **HIGH**

BrandActionButton was introduced as a specialized brand-styled button before the Forui design system integration. It provided:

1. Rose-accent gradient background via `BrandButton.decoration`
2. Custom press micro-interaction (scale to 98%)
3. Loading state with white CircularProgressIndicator
4. Icon + label layout

After the Forui theme integration (PR #147):

- AppButton with `variant: AppButtonVariant.primary` maps to `FButton(variant: FButtonVariant.primary)`
- FButton primary variant inherits `FColors.primary` from the custom Forui theme
- Custom Forui theme maps `BrandColors.dark.primary` → Rose-700 `#BE123C`
- Result: AppButton primary variant renders in rose-primary, matching BrandActionButton's intent

**Why it's redundant now:**

- AppButton primary variant provides rose-primary branding (Forui theme handles color)
- AppButton supports all behavioral props: label, onPressed, icon, isLoading, fullWidth
- The only intentional change is visual: gradient background → solid rose-primary (acceptable design evolution)
- Press animation: Forui's FButton has its own press feedback (scales, but not to 98% — this is a deliberate Forui default, not a regression)

**Evidence:**

- `lib/components/ui/brand_action_button.dart` lines 79–94: Icon + label layout in Row
- `lib/components/ui/app_button.dart` lines 103–113: Identical icon + label layout
- `lib/app/theme/design_tokens.dart` lines 226–260: `BrandButton.decoration` uses `AppColors.primary` (Rose-700)
- `docs/features/forui-theme-integration/ARCHITECT_PLAN.md`: Forui theme maps `BrandColors.dark.primary` to `FColors.primary`

---

## 4. Reference Docs Consulted

**Prior UI Facade Cycles:**

- `docs/features/forui-design-system-swap/ARCHITECT_PLAN.md` — Initial 14/15 wrapper swap to Forui (PR #145)
- `docs/features/forui-style-overrides/ARCHITECT_PLAN.md` — Restored 40+ dropped props via StyleDelta (PR #146)
- `docs/features/forui-theme-integration/ARCHITECT_PLAN.md` — Integrated rose-primary Forui theme + Geist font (PR #147)
- `docs/features/ui-facade-components/ARCHITECT_PLAN.md` — Original facade layer design, explicitly listed BrandActionButton as "precedent component" (domain-specific, not general wrapper)

**Design Tokens:**

- `lib/app/theme/design_tokens.dart` — `BrandButton` class (lines 226–260), `AppColors.primary` definition
- `lib/app/theme/brand_colors.dart` — `BrandColors.dark`/`.light` palettes

**Guardrail Context:**

- This migration aligns with the facade layer's goal: consolidate on general-purpose wrappers (AppButton) instead of maintaining parallel domain-specific components (BrandActionButton) when the general wrapper now satisfies the same semantic need.

---

## 5. Existing System Analysis

### BrandActionButton Implementation

**File:** `lib/components/ui/brand_action_button.dart` (150 lines)

**Props:**

| Prop        | Type          | Default | Usage Pattern                           |
| ----------- | ------------- | ------- | --------------------------------------- |
| `label`     | String        | —       | Required, used at all call sites        |
| `onPressed` | VoidCallback? | —       | Required, null disables button          |
| `icon`      | IconData?     | null    | Used at ~15 call sites                  |
| `isLoading` | bool          | false   | Used at 5 call sites                    |
| `fullWidth` | bool          | false   | Used at ~12 call sites                  |
| `height`    | double        | 48.0    | **1 call site uses non-default (52.0)** |

**Visual Styling:**

- Background: `BrandButton.decoration` — rose-primary gradient with 1.5px border
- Press animation: `AnimatedScale(scale: _isPressed ? 0.98 : 1.0)`
- Disabled opacity: 0.5
- Loading spinner: White CircularProgressIndicator (20x20, strokeWidth 2)

**Behavioral State:**

- Stateful widget tracking `_isPressed` via GestureDetector (onTapDown, onTapUp, onTapCancel)
- Button disabled when `onPressed == null` or `isLoading == true`

### AppButton Implementation

**File:** `lib/components/ui/app_button.dart` (200 lines)

**Props:**

| Prop        | Type             | Default | AppButton Support | Notes                                       |
| ----------- | ---------------- | ------- | ----------------- | ------------------------------------------- |
| `label`     | String           | —       | ✅ Full           | Required                                    |
| `onPressed` | VoidCallback?    | —       | ✅ Full           | Required, null disables                     |
| `icon`      | IconData?        | null    | ✅ Full           | Supported                                   |
| `isLoading` | bool             | false   | ✅ Full           | Supported                                   |
| `fullWidth` | bool             | false   | ✅ Full           | Wraps in `SizedBox(width: double.infinity)` |
| `height`    | double           | —       | ❌ **MISSING**    | **Gap identified**                          |
| `variant`   | AppButtonVariant | primary | ✅ Full           | Maps to FButtonVariant                      |

**Additional AppButton props (not used by BrandActionButton call sites):**

- `backgroundColor`, `borderRadius`, `padding`, `elevation`, `disabledBackgroundColor`, `disabledForegroundColor`

**Gap Analysis:**

- **Critical gap:** `height` prop is missing from AppButton
- **Impact:** 1 call site (`lib/features/bands/band_form_screen.dart:2155`) uses `height: 52` (non-default)
- **Default behavior:** All other call sites use default 48.0 height, which Forui's FButton primary variant will handle via its default styling

### Call Site Inventory

**Total:** 21 files, ~24 instantiations (3 in `quick_actions_row.dart`, 2 in `add_block_out_drawer.dart`, 2 in `my_profile_screen.dart`)

**Call site breakdown by feature:**

| Feature    | File                           | Count | Props Used                                             |
| ---------- | ------------------------------ | ----- | ------------------------------------------------------ |
| Home       | home_tab_content.dart          | 1     | label, icon, onPressed                                 |
| Home       | empty_section_card.dart        | 1     | label, icon, onPressed                                 |
| Home       | quick_actions_row.dart         | 3     | label, onPressed                                       |
| Calendar   | calendar_tab_content.dart      | 1     | label, icon, onPressed                                 |
| Calendar   | day_detail_bottom_sheet.dart   | 1     | label, icon, onPressed, fullWidth                      |
| Calendar   | view_block_out_drawer.dart     | 1     | label, onPressed, fullWidth                            |
| Calendar   | add_block_out_drawer.dart      | 2     | label, onPressed, isLoading                            |
| Contacts   | contacts_empty_state.dart      | 1     | label, icon, onPressed                                 |
| Contacts   | venues_empty_state.dart        | 1     | label, icon, onPressed                                 |
| Contacts   | band_member_detail_drawer.dart | 1     | label, onPressed, fullWidth                            |
| Bands      | band_form_screen.dart          | 1     | label, onPressed, fullWidth, isLoading, **height: 52** |
| Gigs       | gig_notes_sheet.dart           | 1     | label, onPressed, fullWidth                            |
| Gigs       | view_gig_drawer.dart           | 1     | label, onPressed, fullWidth                            |
| Rehearsals | view_rehearsal_drawer.dart     | 1     | label, onPressed, fullWidth                            |
| Rehearsals | rehearsal_notes_sheet.dart     | 1     | label, onPressed, fullWidth                            |
| Profile    | my_profile_screen.dart         | 2     | label, onPressed (1: +fullWidth +isLoading)            |
| Members    | members_empty_state.dart       | 1     | label, icon, onPressed                                 |
| Setlists   | setlists_tab_content.dart      | 1     | label, icon, onPressed                                 |
| Setlists   | empty_setlists_state.dart      | 1     | label, icon, onPressed                                 |
| Setlists   | new_setlist_screen.dart        | 1     | label, icon, onPressed                                 |
| Events     | event_editor_actions.dart      | 1     | label, onPressed, isLoading                            |

**Prop usage summary:**

- `label` + `onPressed`: All 24 call sites (required)
- `icon`: ~15 call sites
- `fullWidth`: ~12 call sites
- `isLoading`: 5 call sites (add_block_out_drawer x2, band_form_screen, my_profile_screen, event_editor_actions)
- `height`: **1 call site** (band_form_screen.dart, non-default value 52.0)

---

## 6. Proposed Solution

### Part A: Add `height` Prop to AppButton

**File:** `lib/components/ui/app_button.dart`

**Change:**

1. Add optional `height` prop to AppButton constructor (nullable `double?`, default `null`)
2. When `height != null`, wrap the FButton in a `SizedBox(height: height, child: ...)` (similar to existing `fullWidth` pattern at lines 159–165)
3. When `height == null`, return FButton directly (no wrapper)

**Rationale:**

- Preserves the 1:1 prop contract for all BrandActionButton call sites
- Follows existing AppButton pattern for dimensional constraints (fullWidth already uses SizedBox wrapper)
- Does not require Forui StyleDelta complexity — height is a layout constraint, not a style override
- Forui's FButton does not expose a height prop, so SizedBox wrapper is the clean Flutter-idiomatic approach

**Implementation sketch:**

```dart
class AppButton extends StatelessWidget {
  const AppButton({
    // ... existing props
    this.height,  // NEW
  });

  // ... existing props
  final double? height;  // NEW

  @override
  Widget build(BuildContext context) {
    // ... existing FButton construction

    // Wrap for fullWidth
    Widget result = button;
    if (fullWidth) {
      result = SizedBox(width: double.infinity, child: result);
    }

    // NEW: Wrap for height
    if (height != null) {
      result = SizedBox(height: height, child: result);
    }

    return result;
  }
}
```

### Part B: Migrate All BrandActionButton Call Sites

**Pattern:** Replace every `BrandActionButton(...)` with `AppButton(variant: AppButtonVariant.primary, ...)`

**Prop mapping:**

| BrandActionButton Prop | AppButton Equivalent | Notes                          |
| ---------------------- | -------------------- | ------------------------------ |
| `label`                | `label`              | 1:1 mapping                    |
| `onPressed`            | `onPressed`          | 1:1 mapping                    |
| `icon`                 | `icon`               | 1:1 mapping                    |
| `isLoading`            | `isLoading`          | 1:1 mapping                    |
| `fullWidth`            | `fullWidth`          | 1:1 mapping                    |
| `height`               | `height` (NEW)       | Requires Part A implementation |

**Import changes:**

- Remove: `import 'package:bandroadie/components/ui/brand_action_button.dart';`
- Add: `import 'package:bandroadie/components/ui/app_button.dart';` (if not already present)
- Ensure: `import 'package:bandroadie/components/ui/app_button.dart';` imports `AppButtonVariant` enum

**Example transformation:**

```dart
// BEFORE
BrandActionButton(
  label: 'Save',
  icon: AppIcons.check,
  onPressed: _handleSave,
  fullWidth: true,
  isLoading: _isSaving,
)

// AFTER
AppButton(
  label: 'Save',
  icon: AppIcons.check,
  onPressed: _handleSave,
  variant: AppButtonVariant.primary,
  fullWidth: true,
  isLoading: _isSaving,
)
```

**Special case (band_form_screen.dart:2155):**

```dart
// BEFORE
BrandActionButton(
  label: label,
  fullWidth: true,
  height: 52,
  isLoading: _isSubmitting,
  onPressed: isEnabled ? _submitForm : null,
)

// AFTER
AppButton(
  label: label,
  variant: AppButtonVariant.primary,
  fullWidth: true,
  height: 52,  // NEW prop from Part A
  isLoading: _isSubmitting,
  onPressed: isEnabled ? _submitForm : null,
)
```

### Part C: Delete BrandActionButton Widget

**Files to delete:**

1. `lib/components/ui/brand_action_button.dart` (150 lines)
2. `test/components/ui/brand_action_button_test.dart` (if exists — verify with file search)

**Verification:** After deletion, run:

```bash
grep -r "BrandActionButton" lib/ --include="*.dart"
```

Expected result: **Zero matches** (all references removed)

---

## 7. Database Impact

**Assessment:** **NOT APPLICABLE**

This is a client-side UI component migration. No database schema changes, migrations, RLS policies, RPC functions, or edge functions are involved.

---

## 8. Flutter Architecture Changes

### State Management

**No state management changes required.**

- BrandActionButton is a stateful widget (tracks `_isPressed` for press animation)
- AppButton is a stateless widget (delegates press feedback to Forui's FButton)
- Press feedback behavior differs (BrandActionButton scales to 98%, Forui's FButton has its own default press feedback)
- This is an **intentional visual change**, not a regression — Forui's press feedback is the new standard

### Widget Layer

**Modified:**

- `lib/components/ui/app_button.dart` — Add `height` prop + SizedBox wrapper logic

**Deleted:**

- `lib/components/ui/brand_action_button.dart`
- `test/components/ui/brand_action_button_test.dart` (if exists)

**Call sites (21 files):** Import swap + prop mapping (see Section 10)

### Repository Layer

**No repository changes.**

### Design Tokens

**No design token changes.**

- `BrandButton` class in `lib/app/theme/design_tokens.dart` remains for backward compatibility (used by other components if any)
- If grep confirms BrandButton is only used by BrandActionButton, it can be deleted as a follow-up cleanup (out of scope for this cycle)

---

## 9. Files to Create

**NONE**

All required infrastructure exists:

- `AppButton` already defined in `lib/components/ui/app_button.dart`
- `AppButtonVariant` enum already defined in same file
- Forui theme integration complete (PR #147 merged to main)

---

## 10. Files to Modify

### A. Add `height` Prop to AppButton

**File:** `lib/components/ui/app_button.dart`

**Changes:**

1. **Line ~40 (constructor parameters):** Add `this.height,` after `this.fullWidth`
2. **Line ~85 (field declarations):** Add `final double? height;` with doc comment
3. **Line ~160 (build method):** After fullWidth SizedBox wrapper, add conditional height SizedBox wrapper

**Estimated lines changed:** ~10 (3 additions + surrounding context)

### B. Migrate Call Sites (21 Files)

| File                                                           | Line(s)     | Change Description                                                  |
| -------------------------------------------------------------- | ----------- | ------------------------------------------------------------------- |
| `lib/features/home/home_tab_content.dart`                      | ~800        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/home/widgets/empty_section_card.dart`            | ~133        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/home/widgets/quick_actions_row.dart`             | ~50, 60, 70 | Replace 3 BrandActionButtons with AppButton + variant               |
| `lib/features/calendar/calendar_tab_content.dart`              | ~396        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`   | ~207        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/calendar/widgets/view_block_out_drawer.dart`     | ~166        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`      | ~854, 895   | Replace 2 BrandActionButtons with AppButton + variant               |
| `lib/features/contacts/widgets/contacts_empty_state.dart`      | ~62         | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/contacts/widgets/venues_empty_state.dart`        | ~62         | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | ~257        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/bands/band_form_screen.dart`                     | ~2155       | Replace BrandActionButton with AppButton + variant + **height: 52** |
| `lib/features/gigs/widgets/gig_notes_sheet.dart`               | ~105        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/gigs/widgets/view_gig_drawer.dart`               | ~420        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`   | ~277        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`   | ~101        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/profile/my_profile_screen.dart`                  | ~907, 1375  | Replace 2 BrandActionButtons with AppButton + variant               |
| `lib/features/members/widgets/members_empty_state.dart`        | ~73         | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/setlists/setlists_tab_content.dart`              | ~406        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/setlists/widgets/empty_setlists_state.dart`      | ~126        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/setlists/new_setlist_screen.dart`                | ~959        | Replace BrandActionButton with AppButton + variant                  |
| `lib/features/events/widgets/event_editor_actions.dart`        | ~41         | Replace BrandActionButton with AppButton + variant                  |

**Per-file change pattern:**

1. Remove import: `import 'package:bandroadie/components/ui/brand_action_button.dart';`
2. Add/verify import: `import 'package:bandroadie/components/ui/app_button.dart';`
3. Replace widget: `BrandActionButton(` → `AppButton(variant: AppButtonVariant.primary,`
4. Preserve all existing props (label, onPressed, icon, isLoading, fullWidth, height)

### C. Delete BrandActionButton Widget

**File:** `lib/components/ui/brand_action_button.dart`

**Action:** Delete entire file (150 lines)

**File:** `test/components/ui/brand_action_button_test.dart`

**Action:** Delete if exists (verify with file search first)

---

## 11. Files Off-Limits

| File / Pattern                                    | Reason                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------- |
| `lib/main.dart`                                   | Initialization order must not change (Guardrails §1)                |
| `lib/app/theme/design_tokens.dart`                | Out of scope unless BrandButton class confirmed unused (follow-up)  |
| `lib/app/theme/brand_colors.dart`                 | Design tokens unchanged                                             |
| `lib/app/theme/app_theme.dart`                    | Material theme unchanged                                            |
| `lib/components/ui/confirm_action_dialog.dart`    | Precedent component, unrelated                                      |
| `lib/components/ui/domain_chip.dart`              | Precedent component, unrelated                                      |
| `lib/components/ui/field_hint.dart`               | Out of scope per feature input                                      |
| `lib/components/ui/frosted_glass_bar.dart`        | Out of scope per feature input                                      |
| `lib/components/ui/segmented_button_group.dart`   | Out of scope per feature input                                      |
| All other `lib/components/ui/app_*.dart`          | UI facade wrappers not modified (only app_button.dart in scope)     |
| `lib/features/financials/financials_screen.dart`  | Contains BrandActionButton in comment only (line 1112), not code    |
| Database files (migrations, schema, RPC)          | No database impact                                                  |
| Edge functions (`supabase/functions/`)            | No backend impact                                                   |
| Test files (except brand_action_button_test.dart) | Not modified unless new app_button height prop requires test update |

---

## 12. System Impact Map

| System                           | Impact     | Rationale                                                                     |
| -------------------------------- | ---------- | ----------------------------------------------------------------------------- |
| Gigs                             | affected   | view_gig_drawer.dart, gig_notes_sheet.dart use BrandActionButton              |
| Rehearsals                       | affected   | view_rehearsal_drawer.dart, rehearsal_notes_sheet.dart use BrandActionButton  |
| Setlists / Catalog               | affected   | 3 files (setlists_tab_content, empty_setlists_state, new_setlist_screen)      |
| Members / RBAC                   | affected   | members_empty_state.dart uses BrandActionButton                               |
| Auth / Session                   | unaffected | No auth-related files use BrandActionButton                                   |
| Routing                          | unaffected | Navigation logic unchanged                                                    |
| Notifications                    | unaffected | No notification-related files use BrandActionButton                           |
| Calendar                         | affected   | 4 files (calendar_tab_content, day_detail_bottom_sheet, 2 drawers)            |
| Contacts / Venues                | affected   | 3 files (contacts_empty_state, venues_empty_state, band_member_detail_drawer) |
| Bands                            | affected   | band_form_screen.dart uses BrandActionButton with **height: 52**              |
| Profile                          | affected   | my_profile_screen.dart uses BrandActionButton (2 instances)                   |
| Home                             | affected   | 3 files (home_tab_content, empty_section_card, quick_actions_row)             |
| Events                           | affected   | event_editor_actions.dart uses BrandActionButton                              |
| Platform (iOS/Android/Web/macOS) | affected   | Visual appearance change (gradient → solid rose-primary) across all platforms |

---

## 13. Regression Risk

**Overall Risk Level:** **LOW**

### Risk Factors

**Positive (mitigates risk):**

1. **Additive change to AppButton:** Adding `height` prop with conditional SizedBox wrapper is low-risk (only active when prop is passed)
2. **1:1 prop mapping:** All BrandActionButton props map directly to AppButton equivalents
3. **No behavioral changes:** Loading state, disabled state, icon layout, fullWidth behavior all preserved
4. **No state management changes:** Call sites remain stateless consumers of button widgets
5. **No database/backend impact:** Purely client-side UI migration
6. **Prior facade cycles tested:** AppButton extensively tested in PR #145, #146, #147 with 100+ existing call sites

**Negative (increases risk):**

1. **Visual change intentional:** Gradient background → solid rose-primary background (Forui's default for primary variant). This is an expected design evolution, not a regression, but users will notice the difference.
2. **Press animation differs:** BrandActionButton scales to 98%, Forui's FButton has its own press feedback. Again, intentional change aligned with Forui design system.
3. **24 call sites across 21 files:** Broad surface area increases chance of human error during migration (missed import, typo in variant)
4. **1 call site uses non-default height:** band_form_screen.dart uses `height: 52`. This requires Part A (add height prop) to be implemented correctly before Part B (migrate call sites).

### Risk Mitigation

1. **flutter analyze zero errors** — Will catch missing imports, undefined props, type mismatches
2. **Visual QA across all affected screens** — QA agent will verify all 21 files' button rendering on all platforms (Web, iOS, Android, macOS)
3. **Grep verification post-deletion** — `grep -r "BrandActionButton" lib/` must return zero results after Part C
4. **Height prop tested in isolation** — Test band_form_screen.dart specifically to confirm `height: 52` renders correctly

---

## 14. Engineer Task Breakdown

Execute tasks in strict order. Do not proceed to next task until current task is verified complete and passing `flutter analyze`.

### Task 1: Add `height` Prop to AppButton

**File:** `lib/components/ui/app_button.dart`

**Steps:**

1. Add `this.height,` to constructor parameters (after `this.fullWidth`)
2. Add field declaration: `final double? height;` with doc comment
3. In `build()` method, after fullWidth SizedBox wrapper logic (lines ~159–165), add:

```dart
// Wrap for height if specified
if (height != null) {
  result = SizedBox(height: height, child: result);
}
```

4. Run `flutter analyze` — expect zero errors
5. Commit: `feat(ui): add height prop to AppButton for dimensional control`

**Verification:**

- Constructor parameter added
- Field declaration added
- Build method wraps in SizedBox when `height != null`
- `flutter analyze` passes

### Task 2: Create Migration Test Case

**Purpose:** Validate height prop works before migrating 24 call sites

**File:** Create temporary test file or add to existing `test/components/ui/app_button_test.dart`

**Test:**

```dart
testWidgets('AppButton respects custom height', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FTheme(
        data: FTheme.neutral.dark.touch,
        child: Scaffold(
          body: AppButton(
            label: 'Test',
            variant: AppButtonVariant.primary,
            height: 52,
            onPressed: () {},
          ),
        ),
      ),
    ),
  );

  final sizedBox = tester.widget<SizedBox>(
    find.ancestor(
      of: find.byType(FButton),
      matching: find.byType(SizedBox),
    ).last, // Get outermost SizedBox (height wrapper, not fullWidth wrapper)
  );

  expect(sizedBox.height, 52);
});
```

**Verification:**

- Test passes
- Confirms height prop works as expected before bulk migration

### Task 3: Migrate Call Sites (Batch 1 — Home Feature)

**Files (4 files, 5 instances):**

1. `lib/features/home/home_tab_content.dart:800`
2. `lib/features/home/widgets/empty_section_card.dart:133`
3. `lib/features/home/widgets/quick_actions_row.dart:50, 60, 70` (3 instances)

**Per-file steps:**

1. Remove import: `import 'package:bandroadie/components/ui/brand_action_button.dart';`
2. Add import: `import 'package:bandroadie/components/ui/app_button.dart';` (if not present)
3. Replace `BrandActionButton(` with `AppButton(variant: AppButtonVariant.primary,`
4. Preserve all existing props

**Verification:**

- All 5 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Home feature to AppButton primary variant`

### Task 4: Migrate Call Sites (Batch 2 — Calendar Feature)

**Files (4 files, 5 instances):**

1. `lib/features/calendar/calendar_tab_content.dart:396`
2. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart:207`
3. `lib/features/calendar/widgets/view_block_out_drawer.dart:166`
4. `lib/features/calendar/widgets/add_block_out_drawer.dart:854, 895` (2 instances)

**Verification:**

- All 5 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Calendar feature to AppButton primary variant`

### Task 5: Migrate Call Sites (Batch 3 — Contacts Feature)

**Files (3 files, 3 instances):**

1. `lib/features/contacts/widgets/contacts_empty_state.dart:62`
2. `lib/features/contacts/widgets/venues_empty_state.dart:62`
3. `lib/features/contacts/widgets/band_member_detail_drawer.dart:257`

**Verification:**

- All 3 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Contacts feature to AppButton primary variant`

### Task 6: Migrate Call Sites (Batch 4 — Bands Feature)

**Files (1 file, 1 instance):**

1. `lib/features/bands/band_form_screen.dart:2155`

**CRITICAL:** This call site uses `height: 52` (non-default). Ensure the new `height` prop is included in the migration.

**Before:**

```dart
BrandActionButton(
  label: label,
  fullWidth: true,
  height: 52,
  isLoading: _isSubmitting,
  onPressed: isEnabled ? _submitForm : null,
)
```

**After:**

```dart
AppButton(
  label: label,
  variant: AppButtonVariant.primary,
  fullWidth: true,
  height: 52,  // NEW prop from Task 1
  isLoading: _isSubmitting,
  onPressed: isEnabled ? _submitForm : null,
)
```

**Verification:**

- Instance replaced
- `height: 52` prop preserved
- `flutter analyze` passes
- Commit: `feat(ui): migrate Bands feature to AppButton primary variant (preserve height: 52)`

### Task 7: Migrate Call Sites (Batch 5 — Gigs + Rehearsals Features)

**Files (4 files, 4 instances):**

1. `lib/features/gigs/widgets/gig_notes_sheet.dart:105`
2. `lib/features/gigs/widgets/view_gig_drawer.dart:420`
3. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart:277`
4. `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart:101`

**Verification:**

- All 4 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Gigs and Rehearsals features to AppButton primary variant`

### Task 8: Migrate Call Sites (Batch 6 — Profile + Members Features)

**Files (2 files, 3 instances):**

1. `lib/features/profile/my_profile_screen.dart:907, 1375` (2 instances)
2. `lib/features/members/widgets/members_empty_state.dart:73`

**Verification:**

- All 3 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Profile and Members features to AppButton primary variant`

### Task 9: Migrate Call Sites (Batch 7 — Setlists + Events Features)

**Files (4 files, 4 instances):**

1. `lib/features/setlists/setlists_tab_content.dart:406`
2. `lib/features/setlists/widgets/empty_setlists_state.dart:126`
3. `lib/features/setlists/new_setlist_screen.dart:959`
4. `lib/features/events/widgets/event_editor_actions.dart:41`

**Verification:**

- All 4 instances replaced
- `flutter analyze` passes
- Commit: `feat(ui): migrate Setlists and Events features to AppButton primary variant`

### Task 10: Verify Zero Remaining References

**Command:**

```bash
grep -r "BrandActionButton" lib/ --include="*.dart"
```

**Expected output:** Only 1 match — the widget file itself (`lib/components/ui/brand_action_button.dart`)

**If unexpected matches found:** Investigate and migrate any missed call sites before proceeding.

**Verification:**

- Only widget file remains
- Commit checkpoint (no code changes, just verification milestone)

### Task 11: Delete BrandActionButton Widget

**Files to delete:**

1. `lib/components/ui/brand_action_button.dart`

**Steps:**

1. `rm lib/components/ui/brand_action_button.dart`
2. Run `flutter analyze` — expect zero errors (confirms no orphaned imports)
3. Run grep verification again: `grep -r "BrandActionButton" lib/ --include="*.dart"` — expect **zero matches**
4. Commit: `chore(ui): delete BrandActionButton widget (migrated to AppButton)`

**Verification:**

- File deleted
- `flutter analyze` passes
- Grep returns zero matches
- Git diff shows deletion of 150 lines

### Task 12: Check for BrandActionButton Test File

**Command:**

```bash
find test/ -name "*brand_action_button*"
```

**If found:**

1. Delete `test/components/ui/brand_action_button_test.dart`
2. Run `flutter test` — expect zero errors (no orphaned test references)
3. Amend previous commit or create new commit: `chore(ui): delete BrandActionButton test file`

**If not found:** No action needed (test file never existed)

**Verification:**

- Test file deleted if it existed
- `flutter test` passes

### Task 13: Optional Cleanup — BrandButton Design Token

**File:** `lib/app/theme/design_tokens.dart` lines 226–260

**Investigation:**

```bash
grep -r "BrandButton" lib/ --include="*.dart" --exclude="design_tokens.dart"
```

**If zero matches:**

- BrandButton class is now unused (only referenced in design_tokens.dart itself)
- Can be deleted as cleanup
- **OUT OF SCOPE:** This is optional follow-up work, not required for feature completion

**If matches found:**

- BrandButton class is still used by other components
- Leave unchanged

**Decision:** Document finding in ENGINEER_REPORT.md, defer deletion decision to Tony

**Verification:**

- Grep result documented
- No code changes (out of scope)

### Task 14: Final Verification

**Commands:**

```bash
flutter analyze
flutter test test/components/ui/app_button_test.dart  # If height test was added
grep -r "BrandActionButton" lib/ --include="*.dart"  # Expect zero matches
```

**Verification checklist:**

- [ ] `flutter analyze` returns 0 errors
- [ ] `flutter test` passes (if new height test was added)
- [ ] Grep for "BrandActionButton" in `lib/` returns zero matches
- [ ] Git diff shows 21 files modified (call sites), 1 file modified (app_button.dart), 1 file deleted (brand_action_button.dart)
- [ ] All commits follow convention: `feat(ui):` or `chore(ui):`

**Final commit (if needed):** `docs(ui): update comments/docs referencing BrandActionButton`

---

## 15. Verification Plan

### Tier 1 — Pre-Deployment (Not Applicable)

**This feature has no database/backend component.** All verification is post-implementation.

### Tier 2 — Post-Implementation Verification

**Static Analysis:**

```bash
-- TEST 1: flutter analyze passes
flutter analyze
-- Expected: 0 errors, 0 warnings

-- TEST 2: BrandActionButton references removed
grep -r "BrandActionButton" lib/ --include="*.dart"
-- Expected: 0 matches

-- TEST 3: AppButton import present in all migrated files
grep -l "AppButton" lib/features/{home,calendar,contacts,bands,gigs,rehearsals,profile,members,setlists,events}/**/*.dart | wc -l
-- Expected: At least 21 files (exact count depends on files that already imported AppButton)
```

**Unit Tests (if app_button_test.dart exists):**

```bash
-- TEST 4: AppButton height prop test
flutter test test/components/ui/app_button_test.dart
-- Expected: All tests pass, including new height prop test
```

**Visual Regression Testing (QA Agent):**

QA agent must visually inspect all 21 files' button rendering on all platforms:

1. Web (Chrome)
2. iOS (Simulator)
3. Android (Emulator)
4. macOS (Native)

**Per-file verification (sample):**

- Home → home_tab_content.dart → "Try Again" button renders in rose-primary
- Calendar → day_detail_bottom_sheet.dart → "Add Event" button renders full-width in rose-primary
- Bands → band_form_screen.dart → Submit button renders with **height: 52** in rose-primary
- Setlists → empty_setlists_state.dart → "Create Your First Setlist" button renders in rose-primary

**Expected behavior:**

- All buttons render in solid rose-primary background (not gradient)
- All buttons show Forui's default press feedback (not 98% scale)
- All buttons respect fullWidth, isLoading, icon props
- band_form_screen.dart button is visibly taller (52px vs default ~48px)

---

## 16. QA Regression Areas

QA agent must specifically test:

### Primary: Visual Appearance of All Migrated Buttons

**Test each of the 21 files across all platforms (Web, iOS, Android, macOS):**

1. **Home Tab** (home_tab_content.dart, empty_section_card.dart, quick_actions_row.dart)
   - "Try Again" button after error state
   - Empty state CTA buttons
   - Quick actions row buttons
2. **Calendar Tab** (calendar_tab_content.dart, day_detail_bottom_sheet.dart, view_block_out_drawer.dart, add_block_out_drawer.dart)
   - "Add Event" button in calendar toolbar
   - "Add Event" button in day detail sheet
   - "Done" button in view block-out drawer
   - "Block Out Time" / "Cancel" buttons in add block-out drawer (check isLoading state)
3. **Contacts** (contacts_empty_state.dart, venues_empty_state.dart, band_member_detail_drawer.dart)
   - "Add Contact" empty state button
   - "Add Venue" empty state button
   - "Done" button in member detail drawer
4. **Bands** (band_form_screen.dart)
   - **CRITICAL:** Submit button with `height: 52` (verify visibly taller than other buttons)
   - Verify isLoading state shows spinner
5. **Gigs** (gig_notes_sheet.dart, view_gig_drawer.dart)
   - "Save" button in gig notes sheet
   - "Done" button in view gig drawer
6. **Rehearsals** (view_rehearsal_drawer.dart, rehearsal_notes_sheet.dart)
   - "Done" button in view rehearsal drawer
   - "Save" button in rehearsal notes sheet
7. **Profile** (my_profile_screen.dart)
   - "Retry" button after error
   - "Save Profile" button (verify isLoading state)
8. **Members** (members_empty_state.dart)
   - "Invite Members" empty state button
9. **Setlists** (setlists_tab_content.dart, empty_setlists_state.dart, new_setlist_screen.dart)
   - "Create Setlist" button in setlists tab
   - "Create Your First Setlist" empty state button
   - "Create" button in new setlist screen
10. **Events** (event_editor_actions.dart)
    - Save button (verify isLoading state)

### Secondary: Behavioral Regression

**Loading State:**

- band_form_screen.dart: Submit button shows spinner when `_isSubmitting` is true
- add_block_out_drawer.dart: Both buttons show spinner when `_isSaving` is true
- my_profile_screen.dart: Save button shows spinner when `_isSaving` is true
- event_editor_actions.dart: Save button shows spinner when `isSaving` is true

**Disabled State:**

- band_form_screen.dart: Submit button disabled when `!_isDirty` or form invalid
- All buttons: Disabled when `onPressed` is null (should show reduced opacity)

**Icon Rendering:**

- Verify all buttons with `icon` prop show the icon to the left of the label
- Spacing between icon and label should be consistent (8px per AppButton line 110)

### Tertiary: Press Feedback

**Expected change (intentional, not a regression):**

- Old behavior (BrandActionButton): Scales to 98% on press
- New behavior (AppButton/Forui): Forui's default press feedback (may scale differently or use opacity)

**Verification:** Press feedback is smooth and visible, even if different from old behavior. This is a design system consistency win, not a regression.

---

## 17. Rollout / Migration Strategy

**NOT APPLICABLE** — No database migrations, no staged rollout. This is a single-commit client-side migration.

**Deployment:** Standard web deploy after QA APPROVED:

```bash
./tools/deploy_web.sh
```

**Post-deploy verification:**

- Incognito load
- Navigate to Home tab → verify "Try Again" button renders in rose-primary
- Navigate to Calendar tab → verify "Add Event" button renders in rose-primary
- Navigate to Bands → Edit Band → verify Submit button height is 52px

---

## 18. Out of Scope

Explicitly out of scope for this feature:

1. **FBadge, FDialog, FSelect** — Other Forui components not touched (per feature input)
2. **field_hint, frosted_glass_bar, segmented_button_group** — Precedent components not touched (per feature input)
3. **BrandButton design token cleanup** — Optional follow-up if grep confirms unused (Task 13 deferred decision)
4. **Press animation customization** — Forui's default press feedback is intentional, not a regression. Custom 98% scale is deprecated.
5. **AppButton test file updates beyond height prop** — Existing AppButton tests assumed to pass (already validated in PR #146)
6. **Visual design refinement** — Gradient → solid rose-primary is intentional. No additional styling (shadows, borders, etc.) requested.
7. **AppButton variant exploration** — Only `variant: AppButtonVariant.primary` used. Other variants (secondary, outlined, destructive, text) not touched.
8. **Global button audit** — Only BrandActionButton call sites migrated. Other button types (TextButton, OutlinedButton, IconButton) not audited for consolidation.

---

**End of ARCHITECT_PLAN.md**
