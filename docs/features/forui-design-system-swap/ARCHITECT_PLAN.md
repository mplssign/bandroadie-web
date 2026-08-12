# ARCHITECT_PLAN.md

**Feature Slug:** `forui-design-system-swap`

---

## Problem Summary

BandRoadie's UI facade layer is fully built: 15 `App*` wrapper widgets exist in `lib/components/ui/` and all ~100+ call sites across `lib/features/` have been retrofitted to use them (completed 2026-08-12). Each wrapper currently delegates internally to Material widgets with default styling.

Tony wants to evaluate the app's appearance if these wrappers' internals were swapped to use the Forui design system package instead of Material. This is the deferred customization phase explicitly called out in `docs/features/ui-facade-components/ARCHITECT_PLAN.md`: "Any design-system customization (Forui, refined styling, animation changes) is future work after Piece 2 completes."

**Critical constraint:** The facade pattern's core value proposition is that call sites never change. If a Forui component's API cannot satisfy a wrapper's existing prop contract without requiring call-site modifications, that breaks the abstraction and must be escalated — not worked around.

**This is a preview/evaluation feature, not a production deployment.** Tony needs to view the result locally before making any production decision. There is no staging environment; the only configured Supabase environment is production, so this work must remain local-only.

---

## Current State

**Existing facade wrappers (15):**

All located in `lib/components/ui/`, each wrapping Material widgets:

1. `app_scaffold.dart` — wraps `Scaffold`
2. `app_app_bar.dart` — wraps `AppBar`
3. `app_button.dart` — wraps `FilledButton`, `ElevatedButton`, `TextButton`, `OutlinedButton` based on variant
4. `app_icon_button.dart` — wraps `IconButton`
5. `app_text_field.dart` — wraps `TextField`
6. `app_text_form_field.dart` — wraps `TextFormField`
7. `app_card.dart` — wraps `Card` with optional `InkWell`
8. `app_dialog.dart` — helper function wrapping `showDialog` + `AlertDialog`
9. `app_bottom_sheet.dart` — helper function wrapping `showModalBottomSheet`
10. `app_switch.dart` — wraps `Switch`
11. `app_checkbox.dart` — wraps `Checkbox`
12. `app_dropdown.dart` — wraps `DropdownButton<T>`
13. `app_chip.dart` — wraps `Chip`, `FilterChip`, `ActionChip` based on variant
14. `app_snackbar.dart` — service helper wrapping `ScaffoldMessenger.showSnackBar`
15. `app_progress_indicator.dart` — wraps `CircularProgressIndicator`, `LinearProgressIndicator`

**Precedent components (7 — NOT in scope):**

These are specialized brand/domain widgets, not general facade wrappers:

- `brand_action_button.dart` — Rose-outlined gradient action button (BrandRoadie-specific styling)
- `confirm_action_dialog.dart` — Reusable confirmation dialog
- `domain_chip.dart` — Email domain shortcut pill
- `email_domain_shortcut_bar.dart` — Domain chip row
- `field_hint.dart` — Form field hint text
- `frosted_glass_bar.dart` — Glassmorphism bar
- `segmented_button_group.dart` — Multi-segment button group

These are off-limits. They remain Material-based.

**Theme configuration:**

- Material 3 enabled (`useMaterial3: true`)
- Dark mode only (rose accent `#F43F5E`)
- Design tokens: `lib/app/theme/design_tokens.dart` (Spacing, AppColors, AppTypography)
- Theme definitions: `lib/app/theme/app_theme.dart` (comprehensive Material theme config)
- Brand colors: `lib/app/theme/brand_colors.dart` (BrandColors theme extension)

**Flutter version:** 3.44.6 (verified 2026-08-12) — meets Forui 0.22.0+ requirement (Flutter 3.44.0+)

**Forui package:** Not yet in `pubspec.yaml`. This is a from-scratch integration.

---

## Investigation: Forui Component Catalog

Forui 0.25.0 (latest as of 2026-08-12) provides 40+ platform-agnostic widgets inspired by shadcn/ui. Confirmed via pub.dev and forui.dev documentation review.

### Mapping Table: App\* Wrappers → Forui Equivalents

| BandRoadie Wrapper       | Current Material Widget                                  | Forui Equivalent           | Confidence | Notes                                                                                                                                                                                 |
| ------------------------ | -------------------------------------------------------- | -------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AppScaffold**          | Scaffold                                                 | `FScaffold`                | **HIGH**   | Similar structure: header, footer, child. Different prop names but semantically aligned.                                                                                              |
| **AppAppBar**            | AppBar                                                   | `FHeader`                  | **MEDIUM** | Different API: `actions` becomes `prefixes`/`suffixes`, `title` is Widget not String. Adapter layer needed within wrapper.                                                            |
| **AppButton**            | FilledButton, ElevatedButton, TextButton, OutlinedButton | `FButton`                  | **HIGH**   | Variant-based: primary, secondary, destructive, outline, ghost. Mapping straightforward.                                                                                              |
| **AppIconButton**        | IconButton                                               | `FButton.icon`             | **HIGH**   | Direct icon-button constructor exists.                                                                                                                                                |
| **AppTextField**         | TextField                                                | `FTextField`               | **HIGH**   | Similar API: controller, label, hint, description, error, enabled. Forui adds `size` variant.                                                                                         |
| **AppTextFormField**     | TextFormField                                            | `FTextFormField` (implied) | **HIGH**   | Forui docs reference form-field variant. Needs API verification.                                                                                                                      |
| **AppCard**              | Card + InkWell                                           | `FCard`                    | **HIGH**   | Builder-based API. Similar structure.                                                                                                                                                 |
| **AppDialog**            | showDialog + AlertDialog                                 | `showFDialog` + `FDialog`  | **HIGH**   | Builder-based. Forui has adaptive (horizontal/vertical) layout.                                                                                                                       |
| **AppBottomSheet**       | showModalBottomSheet                                     | `showFSheet`               | **HIGH**   | Forui calls it "Sheet" not "BottomSheet", but functionally equivalent.                                                                                                                |
| **AppSwitch**            | Switch                                                   | `FSwitch`                  | **HIGH**   | Similar API: value, onChange, label, description, error.                                                                                                                              |
| **AppCheckbox**          | Checkbox                                                 | `FCheckbox`                | **HIGH**   | Similar API: value, onChange, label, description, error.                                                                                                                              |
| **AppDropdown**          | DropdownButton\<T>                                       | `FSelect.rich`             | **HIGH**   | `FSelect.rich()` takes `FSelectItem.item(title: Widget, value: T)` which maps to `DropdownMenuItem<T>`. Can handle current usage.                                                    |
| **AppChip**              | Chip, FilterChip, ActionChip                             | `FBadge` + `FTappable`     | **LOW**    | **Semantic mismatch:** `FBadge` is for labels/counts. `FTappable` primitive might enable interactivity but API unclear. No confirmed Forui equivalent for interactive filter chips.   |
| **AppSnackbar**          | ScaffoldMessenger.showSnackBar                           | `showFToast` + `FToaster`  | **MEDIUM** | Forui calls it Toast. Requires `FToaster` ancestor in widget tree. Different but manageable.                                                                                          |
| **AppProgressIndicator** | CircularProgressIndicator, LinearProgressIndicator       | `FProgress`                | **MEDIUM** | Forui docs show linear only. Circular progress indicator existence unconfirmed. May need fallback to Material for circular.                                                           |

---

## Root Cause: One Blocker, One Feasible Swap

### Blocker: AppChip → FBadge + FTappable (Inconclusive)

**Investigation:** Forui provides `FTappable`, a low-level touch primitive with `selected` state that could potentially wrap `FBadge` to create interactive chips. However, the FTappable API documentation does not clearly show gesture callbacks (no `onPress` equivalent visible in docs). Without confirmed tap callback support, wrapping FBadge in FTappable cannot reliably replace AppChip's `onTap` + `isSelected` contract.

**Current AppChip usage in codebase:** Zero call sites found in `lib/features/`. Existing chip-like widgets (`_FilterChip`, `_TypeChip`, etc.) are custom-built, not using AppChip. This wrapper was created for future consistency but is unused.

**Verdict:** Keep AppChip as Material holdout due to API uncertainty. Low priority since unused.

### Feasible Swap: AppDropdown → FSelect.rich (BLOCKER RESOLVED)

**Initial assessment:** `FSelect` simple constructor uses `Map<String, T>` which cannot express `DropdownMenuItem<T>` richness.

**Re-investigation result:** `FSelect.rich()` constructor takes `List<FSelectItem>` where items are created via `.item(title: Widget, value: T)`. The `title` parameter accepts any Widget, just like `DropdownMenuItem<T>(child: Widget)`. This means FSelect.rich() CAN handle AppDropdown's current usage.

**Current AppDropdown usage in codebase:** 11 DropdownButton usages found across 5 files, all using simple Text children (no complex icons/subtitles). Example:

```dart
DropdownButton<T>(
  value: value,
  items: items.map((item) => DropdownMenuItem<T>(
    value: item,
    child: Text(labelBuilder(item)),
  )).toList(),
  onChanged: onChanged,
)
```

**Forui FSelect.rich equivalent:**

```dart
FSelect<T>.rich(
  value: value,
  children: items.map((item) => .item(
    title: Text(labelBuilder(item)),
    value: item,
  )).toList(),
  onChanged: onChanged,
)
```

**Verdict:** AppDropdown → FSelect.rich is FEASIBLE. Adapter layer within AppDropdown can convert `List<DropdownMenuItem<T>>` to FSelect.rich children without call-site changes. Blocker resolved

**Problem:** Material's `FilterChip` and `ActionChip` are interactive selection widgets with selection state and tap callbacks. Forui's `FBadge` is a static label widget (like Material's `Badge` for notification counts). It has no `onTap`, `isSelected`, or selection styling. Forui's closest interactive component is `FButton` with ghost variant, but that's semantically a button, not a chip.

**There is no Forui equivalent for interactive chips.** Options:

1. Keep `AppChip` as Material-only (breaks consistency — one wrapper stays Material while others are Forui), OR
2. Change call sites to use `AppButton` instead of `AppChip` (breaks facade promise), OR
3. Build a custom chip widget on top of Forui primitives (out of scope — this is a swap, not custom development).

**None of these options are acceptable within the stated scope.**

---

## Diagnosis

**Root cause confidence:** **HIGH**

The facade pattern assumes that the underlying design system can express the same semantic widget contracts as Material. After investigation:

- **14 of 15 wrappers:** Forui provides clean equivalents with sufficient API compatibility to swap internally without call-site changes.
- **1 wrapper (AppChip):** No confirmed Forui equivalent. `FBadge` is semantic mismatch (static label, not interactive). `FTappable` primitive might enable interactivity but lacks clear gesture callback API in documentation. Insufficient confidence to proceed.

**Key finding:** `FSelect.rich()` resolves the initial AppDropdown blocker. Its `.item(title: Widget, value: T)` API matches `DropdownMenuItem<T>` semantics, allowing adapter layer within wrapper without call-site changes.

---

## Proposed Solution

**Recommendation: Single-cycle implementation of 14 compatible wrappers, AppChip remains Material.**

### Cycle 1: Forui Integration for 14 Compatible Wrappers (This Feature)

**Scope:** Swap 14 of 15 wrappers to Forui, leaving AppChip as Material-only with explicit documentation.

**Affected wrappers:**

1. AppScaffold → FScaffold
2. AppAppBar → FHeader
3. AppButton → FButton
4. AppIconButton → FButton.icon
5. AppTextField → FTextField
6. AppTextFormField → FTextFormField
7. AppCard → FCard
8. AppDialog → FDialog
9. AppBottomSheet → FSheet
10. AppSwitch → FSwitch
11. AppCheckbox → FCheckbox
12. **AppDropdown → FSelect.rich** (blocker resolved)
13. AppSnackbar → FToast
14. AppProgressIndicator → FProgress (linear confirmed; verify circular)

**Not swapped (remains Material):**

- AppChip (no confirmed Forui equivalent — FTappable API unclear, unused in codebase)

**Why this is acceptable:**

- The facade layer remains intact — zero call sites change.
- 14 of 15 wrappers (93%) use Forui, achieving the stated goal of evaluating Forui's appearance app-wide.
- The 1 Material holdout (AppChip) is unused in the codebase (zero call sites), so visual inconsistency is non-issue for preview.
- If Tony decides to proceed to production with Forui, AppChip can be addressed later (either via FTappable investigation or custom Forui chip widget).

### Future Work: Address AppChip (Out of Scope for This Plan)

**Not part of this feature.** Only initiated if Tony approves Cycle 1 results, decides to fully commit to Forui, and AppChip usage emerges.

**Options:**

1. Investigate FTappable API more thoroughly (read source code, test gesture callbacks)
2. Build custom Forui-based chip widget using primitives
3. Replace AppChip call sites with `FButton` (ghost variant) if filter chips are needed

**Why defer this:** AppChip has zero call sites in current codebase. No urgency.

---

## Database Impact

**Database:** not applicable — this feature touches zero backend/Supabase surface. All changes are Flutter UI layer only.

---

## Flutter Architecture Changes

### Dependencies

**Add to `pubspec.yaml`:**

```yaml
dependencies:
  forui: ^0.25.0
```

**Optional (if Flutter Hooks integration desired):**

```yaml
dependencies:
  forui_hooks: ^0.25.0 # Only if hooks are needed for controllers
```

**Recommendation:** Start with `forui: ^0.25.0` only. Evaluate hooks later if needed.

### Theme Configuration

Forui requires theme setup via `FTheme`. Two integration approaches:

**Option A: Wrap existing MaterialApp (preserves Material theme for holdout wrappers)**

```dart
MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: themeModeProvider,
  builder: (context, child) => FTheme(
    data: FThemes.zinc.dark,  // Forui theme
    child: child!,
  ),
  home: ...,
)
```

**Option B: Replace MaterialApp with FTheme + MaterialApp nesting**

```dart
FTheme(
  data: FThemes.zinc.dark,
  child: MaterialApp(
    theme: AppTheme.lightTheme,  // Still needed for Material holdouts
    darkTheme: AppTheme.darkTheme,
    themeMode: themeModeProvider,
    home: ...,
  ),
)
```

**Recommendation:** **Option A** (builder approach). Cleaner integration, preserves Material theme hierarchy for the 1 holdout wrapper (AppChip) without conflicts.

### Forui Theme Customization

Forui's built-in themes (zinc, neutral, blue, etc.) likely won't match BrandRoadie's rose accent (`#F43F5E`) and dark-only aesthetic. Two paths:

**Path 1 (Initial Cycle 1 Scope): Use closest built-in theme as-is**

- Select `FThemes.zinc.dark` or `FThemes.neutral.dark` as baseline
- Accept that Forui's default styling (colors, spacing, typography) will differ from current Material theme
- This is acceptable for a preview/evaluation — Tony wants to see what Forui looks like, not pixel-perfect brand matching

**Path 2 (Optional, Post-Cycle 1): Customize FTheme to match brand**

- Use Forui CLI (`dart run forui style create`) to generate custom theme boilerplate
- Override colors, spacing, typography to match `design_tokens.dart` and `brand_colors.dart`
- Apply rose accent (`#F43F5E`) to Forui's primary color
- **Out of scope for Cycle 1.** Deferred until Tony confirms Forui is the direction.

**Recommendation for Cycle 1:** Path 1 (built-in theme). Customization is future work.

### Toast/Snackbar Integration: FToaster Ancestor Requirement

Forui's `showFToast` requires an `FToaster` ancestor in the widget tree (similar to Material's ScaffoldMessenger).

**Required change to `lib/main.dart`:**

```dart
MaterialApp(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: themeModeProvider,
  builder: (context, child) => FTheme(
    data: FThemes.zinc.dark,
    child: FToaster(child: child!),  // Add FToaster here
  ),
  home: ...,
)
```

**Impact:** Low. This is a one-line wrapper addition to `main.dart`. No other files change.

---

## Files to Modify

### Cycle 1: Core Forui Swap (13 wrappers)

| File                                            | Change Description                                                                              |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `pubspec.yaml`                                  | Add `forui: ^0.25.0` to dependencies                                                            |
| `lib/main.dart`                                 | Add `FTheme` wrapper with built-in theme, add `FToaster` ancestor for toast support (~10 lines) |
| `lib/components/ui/app_scaffold.dart`           | Replace `Scaffold` with `FScaffold` (~30 lines)                                                 |
| `lib/components/ui/app_app_bar.dart`            | Replace `AppBar` with `FHeader`, map props (~40 lines)                                          |
| `lib/components/ui/app_button.dart`             | Replace Material button widgets with `FButton`, map variants (~50 lines)                        |
| `lib/components/ui/app_icon_button.dart`        | Replace `IconButton` with `FButton.icon` (~20 lines)                                            |
| `lib/components/ui/app_text_field.dart`         | Replace `TextField` with `FTextField`, map props (~60 lines)                                    |
| `lib/components/ui/app_text_form_field.dart`    | Replace `TextFormField` with `FTextFormField`, map props (~60 lines)                            |
| `lib/components/ui/app_card.dart`               | Replace `Card` with `FCard`, use builder API (~30 lines)                                        |
| `lib/components/ui/app_dialog.dart`             | Replace `showDialog`/`AlertDialog` with `showFDialog`/`FDialog` (~60 lines)                     |
| `lib/components/ui/app_bottom_sheet.dart`       | Replace `showModalBottomSheet` with `showFSheet` (~30 lines)                                    |
| `lib/components/ui/app_switch.dart`             | Replace `Switch` with `FSwitch` (~30 lines)                                                     |
| `lib/components/ui/app_checkbox.dart`           | Replace `Checkbox` with `FCheckbox` (~30 lines)                                                 |
| `lib/components/ui/app_snackbar.dart`           | Replace `ScaffoldMessenger.showSnackBar` with `showFToast` (~40 lines)                          |
| `lib/components/ui/app_progress_indicator.dart` | Replace Material progress indicators with `FProgress`, verify circular support (~40 lines)      |

**Documentation:**

| File                                | Purpose                                                           |
| ----------------------------------- | ----------------------------------------------------------------- |
| `lib/components/ui/README.md` (new) | Document which wrappers use Forui, which remain Material, and why |

### Files Off-Limits

| File                                               | Reason                                                                           |
| -------------------------------------------------- | -------------------------------------------------------------------------------- |
| `lib/components/ui/app_dropdown.dart`              | **Remains Material** — Forui FSelect API incompatibility (see Blocker 1)         |
| `lib/components/ui/app_chip.dart`                  | **Remains Material** — No Forui equivalent for interactive chips (see Blocker 2) |
| `lib/components/ui/brand_action_button.dart`       | Precedent component, not a facade wrapper — out of scope                         |
| `lib/components/ui/confirm_action_dialog.dart`     | Precedent component — out of scope                                               |
| `lib/components/ui/domain_chip.dart`               | Precedent component — out of scope                                               |
| `lib/components/ui/email_domain_shortcut_bar.dart` | Precedent component — out of scope                                               |
| `lib/components/ui/field_hint.dart`                | Precedent component — out of scope                                               |
| `lib/components/ui/frosted_glass_bar.dart`         | Precedent component — out of scope                                               |
| `lib/components/ui/segmented_button_group.dart`    | Precedent component — out of scope                                               |
| All files in `lib/features/`                       | **Zero call site changes** — facade pattern promise                              |
| All files in `lib/shared/`                         | **Zero call site changes**                                                       |
| `lib/app/theme/app_theme.dart`                     | Material theme still needed for holdout wrapper (AppChip)                         |
| `lib/app/theme/design_tokens.dart`                 | Unchanged — Forui theme customization is post-Cycle 1 work                       |
| `lib/app/theme/brand_colors.dart`                  | Unchanged                                                                        |

---

## System Impact Map

| System                                 | Impact                                                                                              |
| -------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Gigs                                   | **Affected** — UI appearance changes app-wide (Forui visual design)                                 |
| Rehearsals                             | **Affected** — UI appearance changes                                                                |
| Setlists / Catalog                     | **Affected** — UI appearance changes                                                                |
| Members / RBAC                         | **Affected** — UI appearance changes                                                                |
| Auth / Session                         | **Affected** — UI appearance changes                                                                |
| Routing                                | **Unaffected** — No navigation logic changes                                                        |
| Notifications                          | **Affected** — AppSnackbar becomes FToast (different visual style)                                  |
| Platform (iOS / Android / Web / macOS) | **Affected** — Forui is platform-agnostic, may render differently per platform (needs verification) |

**Critical verification areas:**

- **Platform consistency:** Forui claims to be platform-agnostic, but its touch-first design may render differently on desktop (macOS, Web) vs. mobile (iOS, Android). Explicit cross-platform testing required.
- **Form validation:** AppTextFormField → FTextFormField must preserve validator and form-field contract.
- **Dialog behavior:** FDialog's adaptive layout (horizontal vs. vertical based on screen size) may change dialog appearance on tablets/web.

---

## Regression Risk

**Risk Level:** **MEDIUM-HIGH**

**Rationale:**

- **Visual change scope:** This is an app-wide visual redesign. Every screen that uses any of the 13 swapped wrappers (which is all of them) will render with Forui's design system instead of Material. This is materially different from the prior Material-only facade retrofit, which was designed to be pixel-invisible.
- **No user-facing functional changes expected:** Business logic, data flow, and interactions remain identical. Buttons still trigger the same callbacks, forms still validate the same way, dialogs still block interaction. But the appearance changes significantly.
- **Rollback complexity:** If the visual result is unacceptable, rollback requires reverting 14 file changes (13 wrappers + main.dart) and removing the Forui dependency. Rollback is straightforward but non-trivial.
- **Platform divergence risk:** Forui's platform-agnostic design may render inconsistently across iOS, Android, macOS, and Web. Material provides platform-specific adaptations (e.g., Cupertino-style widgets on iOS); Forui does not. This could create unexpected visual differences that Material users are accustomed to seeing.
- **Theme mismatch:** Using an out-of-the-box Forui theme (zinc.dark or neutral.dark) means colors, spacing, and typography will differ from BandRoadie's current Material theme. This is acceptable for preview but may be jarring for Tony.

**Mitigation:**

- **Local-only preview:** This feature must not be deployed. Tony views it locally via `./run.sh <device>` across all platforms (Web, macOS, iOS, Android) before making any production decision.
- **Explicit documentation:** README.md in `lib/components/ui/` explains which wrappers are Forui, which are Material, and why.
- **Incremental validation:** Test each wrapper individually after swap (see Verification Plan) before declaring the cycle complete.

**Primary risk factors:**

1. **Forui theme not matching brand:** Colors/spacing/typography differ from Material theme → Tony may find it visually inconsistent with BandRoadie's identity.
2. **Platform inconsistency:** Forui's touch-first design may not translate well to desktop (macOS, Web) → navigation, button sizes, spacing may feel awkward on large screens.
3. **FProgress circular support:** If Forui's `FProgress` doesn't support circular indicators, AppProgressIndicator must fall back to Material for circular, breaking consistency.
4. **Form field behavior drift:** FTextFormField's validation/error display may differ from Material's TextFormField → form UX may change subtly.

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Add Forui dependency

- **File:** `pubspec.yaml`
- **Change:** Add `forui: ^0.25.0` to dependencies
- **Verification:** Run `flutter pub get` — no conflicts, dependency resolves cleanly

### Task 2: Integrate FTheme and FToaster into main.dart

- **File:** `lib/main.dart`
- **Change:** Wrap `MaterialApp` builder with `FTheme(data: FThemes.zinc.dark, child: FToaster(child: child!))`
- **Verification:** App launches, no runtime errors. Material theme still applies to existing widgets.

### Task 3: Swap AppScaffold to FScaffold

- **File:** `lib/components/ui/app_scaffold.dart`
- **Props mapping:**
  - `appBar` → `header` (type change: `PreferredSizeWidget?` → `Widget?`)
  - `body` → `child`
  - `floatingActionButton` → Not directly supported by FScaffold; investigate if `footer` can be repurposed or if this prop must be dropped
  - `bottomNavigationBar` → `footer`
  - `backgroundColor` → Not directly supported by FScaffold; apply via `scaffoldStyle.backgroundColor` delta
  - `resizeToAvoidBottomInset` → FScaffold has `resizeToAvoidBottomInset` prop, map directly
- **Verification:** App launches, all screens using AppScaffold render correctly (header, body, footer visible)

### Task 4: Swap AppAppBar to FHeader

- **File:** `lib/components/ui/app_app_bar.dart`
- **Props mapping:**
  - `title` (String or Widget) → `title` (Widget only)
  - `leading` → `prefixes` (List<Widget>, wrap in list)
  - `actions` → `suffixes` (List<Widget>)
  - `backgroundColor` → Not directly supported; apply via `style` delta if needed, or drop for preview
  - `centerTitle` → `titleAlignment` (map true → Alignment.center, false → Alignment.start)
- **Implementation:** Adapter layer within AppAppBar to convert Material API to FHeader API
- **Verification:** All screens with AppBar render correctly, title and actions visible

### Task 5: Swap AppButton to FButton

- **File:** `lib/components/ui/app_button.dart`
- **Variant mapping:**
  - `AppButtonVariant.primary` → `FButton` with default (primary) style
  - `AppButtonVariant.secondary` → `FButton` with `.secondary` style
  - `AppButtonVariant.text` → `FButton` with `.ghost` style (closest equivalent)
  - `AppButtonVariant.outlined` → `FButton` with `.outline` style
  - `AppButtonVariant.destructive` → `FButton` with `.destructive` style
- **Props mapping:**
  - `label` → `child: Text(label)`
  - `onPressed` → `onPress`
  - `icon` → Use `FButton` with icon in builder, or prefix icon if supported
  - `isLoading` → Show `CircularProgressIndicator` in child (same pattern as Material)
  - `fullWidth` → Wrap in `SizedBox(width: double.infinity, child: ...)`
- **Verification:** All button variants render correctly, loading state works

### Task 6: Swap AppIconButton to FButton.icon

- **File:** `lib/components/ui/app_icon_button.dart`
- **Props mapping:**
  - `icon` → `child: Icon(icon)`
  - `onPressed` → `onPress`
  - `color` → Apply via `style` delta if needed
  - `size` → Apply via `style` delta if needed
- **Verification:** Icon buttons render correctly, tap interaction works

### Task 7: Swap AppTextField to FTextField

- **File:** `lib/components/ui/app_text_field.dart`
- **Props mapping:**
  - `controller` → `controller` (same)
  - `focusNode` → `focusNode` (same)
  - `hintText` → `hint`
  - `labelText` → `label: Text(labelText)`
  - `prefixIcon` → Not directly supported by FTextField; may need custom decoration or drop for preview
  - `suffixIcon` → Not directly supported; may need custom decoration or drop for preview
  - `obscureText` → Use `FTextField.password` constructor
  - `maxLines` → Use `FTextField.multiline` if >1, else default
  - `keyboardType` → Map to appropriate keyboard type
  - `onChanged` → `onChanged` (same)
  - `enabled` → `enabled` (same)
- **Verification:** Text fields render correctly, typing works, validation displays

### Task 8: Swap AppTextFormField to FTextFormField

- **File:** `lib/components/ui/app_text_form_field.dart`
- **Props mapping:** Same as AppTextField + validator/onSaved
- **Verification:** Form fields validate correctly, error messages display

### Task 9: Swap AppCard to FCard

- **File:** `lib/components/ui/app_card.dart`
- **Props mapping:**
  - `child` → Pass via `builder` parameter
  - `onTap` → Wrap FCard in `GestureDetector` or use Forui's tappable wrapper if available
  - `padding` → Apply via `style` delta
- **Verification:** Cards render correctly, tap interaction works

### Task 10: Swap AppDialog to FDialog

- **File:** `lib/components/ui/app_dialog.dart`
- **Helper function:** Replace `showDialog` with `showFDialog`
- **Widget:** Replace `AlertDialog` with `FDialog` (use adaptive layout if appropriate)
- **Props mapping:**
  - `title` → Pass in builder
  - `message` → Pass in builder
  - `actions` → Build as buttons within dialog builder
  - `barrierDismissible` → Map to FDialog's dismissibility settings
- **Verification:** Dialogs display correctly, actions work, barrier dismissal behaves as expected

### Task 11: Swap AppBottomSheet to FSheet

- **File:** `lib/components/ui/app_bottom_sheet.dart`
- **Helper function:** Replace `showModalBottomSheet` with `showFSheet`
- **Props mapping:**
  - `builder` → `builder` (same)
  - `isDismissible` → Map to FSheet's dismissibility settings
  - `useRootNavigator` → Check if FSheet supports this, may need workaround
- **Verification:** Bottom sheets display correctly, drag-to-dismiss works

### Task 12: Swap AppSwitch to FSwitch

- **File:** `lib/components/ui/app_switch.dart`
- **Props mapping:**
  - `value` → `value` (same)
  - `onChanged` → `onChange`
  - `activeColor` → Apply via `style` delta if needed
- **Verification:** Switches render correctly, toggle interaction works

### Task 13: Swap AppCheckbox to FCheckbox

- **File:** `lib/components/ui/app_checkbox.dart`
- **Props mapping:**
  - `value` → `value` (same)
  - `onChanged` → `onChange`
  - `activeColor` → Apply via `style` delta if needed
- **Verification:** Checkboxes render correctly, toggle interaction works

### Task 14: Swap AppSnackbar to FToast

- **File:** `lib/components/ui/app_snackbar.dart`
- **Helper function:** Replace `ScaffoldMessenger.showSnackBar` with `showFToast`
- **Props mapping:**
  - `message` → `title` or `description`
  - `action` → `suffixBuilder` for action button
  - `duration` → `duration` (same)
  - `type` (info/success/error) → Map to Forui's toast style variants
- **Verification:** Toasts display correctly, dismiss correctly, action buttons work

### Task 15: Swap AppProgressIndicator to FProgress

- **File:** `lib/components/ui/app_progress_indicator.dart`
- **Props mapping:**
  - `type` (circular/linear) → `FProgress` for linear (confirmed); **investigate if Forui has circular progress**
  - `value` → `value` (for determinate progress)
  - `color` → Apply via `style` delta if needed
- **Critical:** If Forui does not support circular progress, **fall back to Material CircularProgressIndicator** with documentation. This breaks consistency but is acceptable for Cycle 1.
- **Verification:** Linear progress renders correctly. Circular progress either uses FProgress (if supported) or Material fallback.

### Task 16: Document Material holdout

- **File:** `lib/components/ui/README.md` (create)
- **Content:**
  - List all 15 wrappers
  - Mark which use Forui (14) and which remain Material (1: AppChip)
  - Explain why AppChip remains Material (FTappable API unclear, no confirmed interactive chip equivalent, unused in codebase)
  - Note that this is a preview/evaluation configuration, not final
- **Verification:** README is clear and accurate

### Task 17: Run flutter pub get

- **Command:** `flutter pub get`
- **Verification:** Forui dependency installs, no conflicts

### Task 18: Run flutter analyze

- **Command:** `flutter analyze`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding (likely import errors or API mismatches)

### Task 19: Build app for all platforms (compile verification only)

**Responsibility:** Engineer

- **Commands:**
  - `flutter build web --release`
  - `flutter build ios --release --no-codesign` (macOS host only)
  - `flutter build apk --release`
  - `flutter build macos --release`
- **Expected output:** All builds succeed, no compile errors
- **Note:** Forui is platform-agnostic, but this verifies no platform-specific compile errors. Does NOT include running the app or visual inspection—that's Task 20 (Tony's job).

### Task 20: Tony's local visual verification

**Responsibility:** Tony (NOT Engineer/QA—this is explicitly Tony's job to evaluate Forui appearance)

- **Run app on each platform:**
  - Web: `flutter run -d chrome`
  - macOS: `flutter run -d macos`
  - iOS: `./run.sh <device-id>`
  - Android: `flutter run -d <android-device-id>`
- **Test coverage per platform:**
  1. Auth flow (login screen, magic link)
  2. Home dashboard
  3. Setlists screen (list + detail + add/edit song)
  4. Gigs screen (list + detail + create gig)
  5. Rehearsals screen
  6. Profile/Settings screen
  7. Dialogs (delete confirmation, error alerts)
  8. Bottom sheets (if used in app)
  9. Snackbars/toasts (trigger success/error messages)
  10. Form fields (text input, validation errors)
- **Verification criteria:**
  - All screens render without runtime errors
  - Visual appearance is Forui-styled (not Material-styled)
  - Interactions work (buttons, forms, dialogs, navigation)
  - Note any visual inconsistencies between platforms (expected due to Forui's platform-agnostic design)
  - Assess whether Forui's visual design is acceptable for BandRoadie (this is Tony's evaluation decision)

---

## Verification Plan

**Tier 1 — Pre-deployment (N/A for this feature—no migrations):**

This feature has no database migrations, edge functions, or backend changes. All verification is Flutter-local.

**Tier 2 — Post-implementation:**

### Test 1: flutter analyze passes with 0 errors

```bash
flutter analyze
```

**Expected output:** 0 errors, 0 warnings.

### Test 2: flutter build succeeds for all platforms (Engineer responsibility)

```bash
flutter clean
flutter pub get
flutter build web --release
flutter build ios --release --no-codesign
flutter build apk --release
flutter build macos --release
```

**Expected output:** All builds succeed, no compile errors.

**Responsibility:** Engineer. This is compile-only verification, not visual inspection.

### Test 3: App renders with Forui styling across all platforms (Tony's responsibility)

**Responsibility:** Tony (NOT Engineer/QA—Tony must visually evaluate Forui appearance)

**Platforms:** Web (Chrome), macOS, iOS (simulator or device), Android (emulator or device)

**Test cases per platform:**

1. **Auth flow:** Login screen renders, text field uses FTextField styling, button uses FButton styling, magic link flow completes
2. **Home dashboard:** Scaffold uses FScaffold, header uses FHeader, navigation works
3. **Setlists screen:** Cards use FCard, buttons use FButton, add/edit dialogs use FDialog, forms use FTextField/FTextFormField
4. **Gigs screen:** Same as setlists
5. **Rehearsals screen:** Same as setlists
6. **Profile/Settings screen:** Switches use FSwitch, checkboxes use FCheckbox (if used), chips use Material AppChip if present (visual inconsistency expected but unused in current codebase)
7. **Dialogs:** FDialog renders, actions work, barrier dismissal works
8. **Bottom sheets:** FSheet renders, drag-to-dismiss works
9. **Toasts/Snackbars:** FToast renders, auto-dismiss works, action buttons work
10. **Progress indicators:** FProgress linear renders, circular renders (Forui or Material fallback)

**Expected outcome:**

- App renders with Forui's visual design (colors, spacing, typography differ from Material)
- All interactions work (no functional regressions)
- Chips visually stand out as Material if used (expected—AppChip is holdout, though unused in current codebase)
- Note any platform-specific visual inconsistencies (e.g., touch targets too small on desktop, spacing awkward on mobile)

### Test 4: Confirm zero files modified outside lib/components/ui/ and lib/main.dart

```bash
git diff --stat
```

**Expected output:**

- `pubspec.yaml` (1 line added)
- `lib/main.dart` (~10 lines changed — FTheme + FToaster wrapper)
- `lib/components/ui/app_*.dart` (14 files modified, 1 unchanged — AppChip)
- `lib/components/ui/README.md` (new file)
- **Zero modifications to any file in `lib/features/` or `lib/shared/`**

This is the primary regression guard—confirms no call sites were touched.

### Test 5: Spot-check holdout wrapper remains Material

- Manually verify AppChip file still uses Material widgets (Chip, FilterChip, ActionChip)
- If AppChip is used in any screen (currently 0 usages), confirm Material styling (not Forui)

---

## QA Regression Areas

**Focus:** Visual consistency, interaction fidelity, and cross-platform behavior.

1. **Confirm Forui visual theme applied:** All 14 swapped wrappers render with Forui styling (not Material)
2. **Confirm holdout wrapper remains Material:** AppChip unchanged (Material-styled if used, though currently unused in codebase)
3. **Confirm zero call sites touched:** Review `git diff --stat`, no changes outside `lib/components/ui/` and `lib/main.dart`
4. **Cross-platform visual verification:** Test on Web, macOS, iOS, Android — note any platform-specific inconsistencies
5. **Form validation:** Text fields validate correctly, error messages display
6. **Dialog behavior:** Dialogs block interaction, dismiss correctly
7. **Toast behavior:** Toasts display, auto-dismiss, action buttons work
8. **Progress indicators:** Linear and circular progress render correctly
9. **Navigation:** Routing and deep linking unaffected

**No functional regression testing required** — business logic is untouched. This QA pass is purely visual/interaction validation.

---

## Rollout / Migration Strategy

**Not applicable — this is a local preview feature, not a production deployment.**

**Constraints:**

- No deployment to production
- No staging environment exists
- Tony must view the result locally via `./run.sh <device>` before making any production decision

**If Tony approves Forui after Cycle 1 preview:**

Future work (separate feature cycle) would include:

1. Forui theme customization to match BrandRoadie's rose accent and dark-only aesthetic
2. Cycle 2: Refactor AppDropdown and AppChip call sites to use Forui-compatible alternatives
3. Deployment to production via `./tools/deploy_web.sh` + App Store/Play Store releases

**None of that is part of this feature.**

---

## Out of Scope

The following are explicitly deferred or excluded:

1. **Deployment to production:** This feature is local preview only. Deployment is a separate decision after Tony reviews the result.
2. **Forui theme customization:** Using an out-of-the-box Forui theme (zinc.dark or neutral.dark) is acceptable for preview. Matching BrandRoadie's rose accent and brand colors is future work.
3. **AppChip Forui swap:** Remains Material due to FTappable API uncertainty (see Blocker). Addressing it requires deeper API investigation or custom Forui chip widget (future work contingent on Tony's approval of Cycle 1 and emergence of AppChip usage).
4. **Platform-specific Forui optimizations:** Forui is platform-agnostic. If desktop (macOS, Web) rendering is awkward, optimizations are future work.
5. **Accessibility enhancements:** Forui's accessibility behavior is inherited from its widgets. Any enhancements are future work.
6. **Performance optimization:** Cycle 1 focuses on visual/interaction correctness, not performance. Optimization (if needed) is future work.
7. **Precedent components (7 widgets):** BrandActionButton, ConfirmActionDialog, DomainChip, etc. remain Material — out of scope.
8. **Widget tests for Forui wrappers:** The original Material wrappers have widget tests (created in facade retrofit cycles). Updating these tests to verify Forui behavior is deferred to post-Cycle 1 work if Tony approves. For Cycle 1, manual visual verification is sufficient.

---

## Cycle Splitting Recommendation

**Recommendation: Single Cycle 1 for 14 Wrappers**

**Rationale:**

- The 14 compatible wrappers are independent — swapping one does not block swapping another.
- Each swap is localized to a single file (plus `main.dart` for theme setup).
- Total scope: 15 files modified (14 wrappers + main.dart), 1 file created (README.md), 1 dependency added (pubspec.yaml).
- Estimated implementation time: 3-4 hours for an experienced Flutter developer familiar with both Material and Forui APIs.
- **Atomic preview value:** Tony needs to see the _overall_ app appearance with Forui, not piecemeal. Splitting into smaller cycles would require multiple preview rounds, slowing down the evaluation.

**No cycle splitting needed.** Proceed with full 14-wrapper swap in one implementation pass.

---

## Blockers for Production Decision

If Tony decides to proceed to production with Forui after Cycle 1 preview, the following must be resolved first:

1. **Forui theme customization:** Match rose accent (`#F43F5E`), dark-only mode, and BrandRoadie's spacing/typography.
3. **AppChip future investigation or refactoring:** If chip usage emerges, investigate FTappable API further or build custom Forui chip widget (~5-10 call sites estimated if usage appears).
4. **Cross-platform optimization:** Address any platform-specific visual inconsistencies discovered in Cycle 1 (e.g., desktop touch targets, mobile spacing).
5. **Widget test updates:** Update wrapper tests to verify Forui behavior instead of Material behavior.

**None of these blockers prevent Cycle 1 from proceeding.** They are follow-on work contingent on Tony's approval.

---

## Confidence Levels

| Area                                                          | Confidence | Rationale                                                                                                                                             |
| ------------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| **13 wrapper swaps (AppScaffold, AppButton, etc.)**           | **HIGH**   | Forui provides clean equivalents, APIs are similar enough to map within wrappers without call-site changes.                                           |
| **AppAppBar → FHeader mapping**                               | **MEDIUM** | API differs (actions → prefixes/suffixes), but adapter layer is straightforward. Visual result may differ (Forui's header style vs. Material AppBar). |
| **AppTextField/AppTextFormField → FTextField/FTextFormField** | **HIGH**   | APIs are very similar, form validation should work identically.                                                                                       |
| **AppProgressIndicator circular support**                     | **LOW**    | Forui docs only show linear progress. If circular is unsupported, fallback to Material is required, breaking consistency.                             |
| **FToaster integration**                                      | **HIGH**   | Straightforward — add FToaster wrapper in main.dart, call showFToast in AppSnackbar.                                                                  |
| **Cross-platform visual consistency**                         | **MEDIUM** | Forui claims platform-agnostic design, but touch-first philosophy may not translate well to desktop. Verification required.                           |
| **Rollback complexity**                                       | **HIGH**   | Rollback is clean — revert 14 file changes, remove forui dependency, redeploy. No database or backend changes to unwind.                              |

---

**Architect Signature:** This plan is approved for Engineer implementation pending Tony's review and explicit approval to proceed with Cycle 1. Do not begin implementation until Tony confirms.
