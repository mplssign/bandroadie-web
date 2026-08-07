# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-components`

---

## Problem Summary

No unified facade layer exists beyond 7 ad hoc precedent components in `lib/components/ui/`. 129 of 318 Dart files (40.6%) directly instantiate raw Material widgets—buttons, text fields, cards, scaffolds, app bars, dialogs, snackbars, progress indicators, switches, checkboxes, dropdowns, chips, and bottom sheets. This creates brittleness: any future design-system change (Forui, custom components, or refined Material styling) requires individually touching ~100+ files across all feature folders.

**Why this is a problem:** The app has already established a precedent pattern (BrandActionButton, ConfirmActionDialog, DomainChip, etc.) demonstrating the value of semantic wrapper widgets that hide implementation details. But this pattern covers only 7 widget types. The remaining Material surface area is exposed directly to feature code, creating tight coupling between UI implementation and business logic.

**Goal of Piece 1:** Build ~15 new wrapper widgets backed by Material internally, visually and behaviorally identical to default-styled Material equivalents. Zero production call sites changed. Each wrapper has a documented prop contract clear enough that Piece 2 retrofits (rewriting ~100+ call sites folder-by-folder) are mechanical, not exploratory.

---

## Current State

**Existing precedent components (7):**

- `BrandActionButton` — Rose-outlined action button with gradient background, loading state
- `ConfirmActionDialog` — Reusable confirmation dialog with title, message, confirm/cancel buttons
- `DomainChip` — Email domain shortcut pill (e.g., @gmail.com)
- `EmailDomainShortcutBar` — Horizontal row of domain chips
- `FieldHint` — Hint text widget for form fields
- `FrostedGlassBar` — Glassmorphism bar component
- `SegmentedButtonGroup` — Multi-segment grouped button component

**Pattern observed from precedent:**

- Plain `StatelessWidget`/`StatefulWidget` (no Riverpod)
- Semantic named props (label, onPressed, domain, isSelected) rather than generic child/style passthrough
- Tokens pulled directly from `design_tokens.dart` (AppColors, Spacing, AppTextStyles) and `brand_colors.dart` (`context.colors` extension)
- Material widgets used internally (Container, GestureDetector, FilledButton, AlertDialog) but hidden from call sites
- One file per component
- No platform-conditional logic

**Raw Material widget usage (grep analysis):**

- **Buttons:** 212 call sites in 76 files (ElevatedButton, OutlinedButton, TextButton, IconButton, FilledButton)
- **Structure:** 192 call sites in 76 files (Scaffold, AppBar, TextField, TextFormField)
- **Cards/Dialogs:** 106 call sites in 47 files (Card, showDialog, showModalBottomSheet)
- **Controls/Indicators:** 115 call sites in 58 files (CircularProgressIndicator, LinearProgressIndicator, Switch, Checkbox, DropdownButton, Chip)

**Total surface area:** 129 unique files out of 318 Dart files (40.6%) call raw Material widgets directly.

**Theme configuration (verified in code):**

- Two `MaterialApp` instances in `lib/main.dart`:
  - `BandRoadieApp` (~line 147): Riverpod `themeModeProvider` wired, both `AppTheme.lightTheme` and `AppTheme.darkTheme` available
  - `ConfigErrorApp` (~line 230): Dark-only fallback for config errors
- Material 3 enabled (`useMaterial3: true`)
- Comprehensive theme configuration for all Material widgets (FilledButton, ElevatedButton, OutlinedButton, TextButton, InputDecoration, Card, AppBar, etc.)
- `TextScaler.noScaling` applied globally app-wide (font size scaling intentionally locked per existing product decision)

**Design tokens:**

- `lib/app/theme/design_tokens.dart`: Spacing constants, font sizes, radii (cardRadius: 16px, buttonRadius: 8px)
- `lib/app/theme/brand_colors.dart`: BrandColors theme extension with `context.colors` access
- `lib/app/theme/app_theme.dart`: Full Material theme definitions (light + dark)

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture
- `docs/reference/architecture/architecture.md` — General architecture overview, no design-system or component guidance found

**No relevant design-system guidance exists in reference docs.** Proceeded with codebase inspection per ARCHITECT.md fallback protocol.

---

## Proposed Solution

Create 15 new wrapper widgets in `lib/components/ui/` that internally delegate to Material widgets but expose semantic prop contracts aligned with the app's actual usage patterns. Each wrapper:

1. Follows the precedent component pattern (plain StatelessWidget/StatefulWidget, design tokens, semantic props)
2. Delegates to default-styled Material widgets internally (respecting theme configuration from `app_theme.dart`)
3. Is visually and behaviorally identical to Material equivalents (no custom styling or behavior changes in Piece 1)
4. Has no platform-conditional logic (must work uniformly on Web, iOS, Android, macOS)
5. Has a prop surface sufficient to replace ~100+ real call sites in Piece 2 (determined by spot-checking actual usage patterns across 2-3 representative files per widget type)

**The 15 wrappers:**

| Wrapper                              | Replaces                                                 | Key Props                                                                                                                                         |
| ------------------------------------ | -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| **AppScaffold**                      | Scaffold                                                 | appBar, body, floatingActionButton, bottomNavigationBar, backgroundColor (optional override)                                                      |
| **AppAppBar**                        | AppBar                                                   | title, leading, actions, backgroundColor (optional override), centerTitle                                                                         |
| **AppButton**                        | ElevatedButton, FilledButton, OutlinedButton, TextButton | label, onPressed, icon (optional), variant (primary/secondary/text/outlined), isLoading, fullWidth                                                |
| **AppIconButton**                    | IconButton                                               | icon, onPressed, color (optional), size (optional)                                                                                                |
| **AppTextField**                     | TextField                                                | controller, hintText, labelText (optional), prefixIcon (optional), suffixIcon (optional), obscureText, maxLines, keyboardType, onChanged, enabled |
| **AppTextFormField**                 | TextFormField                                            | All AppTextField props + validator, onSaved                                                                                                       |
| **AppCard**                          | Card                                                     | child, onTap (optional), padding (optional override)                                                                                              |
| **AppDialog** (helper + widget)      | showDialog + AlertDialog                                 | title, message, actions (list of button specs), barrierDismissible                                                                                |
| **AppBottomSheet** (helper function) | showModalBottomSheet                                     | builder, isDismissible, useRootNavigator                                                                                                          |
| **AppSwitch**                        | Switch                                                   | value, onChanged, activeColor (optional)                                                                                                          |
| **AppCheckbox**                      | Checkbox                                                 | value, onChanged, activeColor (optional)                                                                                                          |
| **AppDropdown**                      | DropdownButton                                           | value, items, onChanged, hint                                                                                                                     |
| **AppChip**                          | Chip, FilterChip, ActionChip                             | label, onTap (optional), isSelected (optional), variant                                                                                           |
| **AppSnackbar** (service helper)     | ScaffoldMessenger.showSnackBar                           | message, action (optional), duration, type (info/success/error)                                                                                   |
| **AppProgressIndicator**             | CircularProgressIndicator, LinearProgressIndicator       | type (circular/linear), value (optional), color (optional)                                                                                        |

**Constraints:**

- No modifications to any files outside `lib/components/ui/`
- No modifications to existing precedent components (BrandActionButton, ConfirmActionDialog, etc.)
- No Riverpod dependencies in wrappers (use plain StatelessWidget/StatefulWidget)
- No call site retrofits (that's Piece 2—separate future pipeline cycle)
- Each wrapper pulls styling from `design_tokens.dart` and `brand_colors.dart` to match theme
- Wrappers must not interfere with `TextScaler.noScaling` (no text scaling overrides)
- Each wrapper's prop surface is determined by spot-checking 2-3 real call sites per widget type to ensure Piece 2 retrofits will be mechanical

---

## Database Impact

**Database:** not applicable — this feature touches zero backend/Supabase surface. All changes are Flutter UI layer only.

---

## Flutter Architecture Changes

**State Management:** None. Wrappers are plain widgets with no Riverpod dependencies.

**Widget Tree:** 15 new wrapper widgets created in `lib/components/ui/`. Zero modifications to existing widget tree (no call sites changed).

**Repositories:** None.

**Controllers/Notifiers:** None.

---

## Files to Create

| File                                            | Purpose                                                   |
| ----------------------------------------------- | --------------------------------------------------------- |
| `lib/components/ui/app_scaffold.dart`           | Scaffold wrapper                                          |
| `lib/components/ui/app_app_bar.dart`            | AppBar wrapper                                            |
| `lib/components/ui/app_button.dart`             | Button wrapper (primary/secondary/text/outlined variants) |
| `lib/components/ui/app_icon_button.dart`        | IconButton wrapper                                        |
| `lib/components/ui/app_text_field.dart`         | TextField wrapper                                         |
| `lib/components/ui/app_text_form_field.dart`    | TextFormField wrapper                                     |
| `lib/components/ui/app_card.dart`               | Card wrapper                                              |
| `lib/components/ui/app_dialog.dart`             | Dialog helper function + AppAlertDialog widget            |
| `lib/components/ui/app_bottom_sheet.dart`       | Bottom sheet helper function                              |
| `lib/components/ui/app_switch.dart`             | Switch wrapper                                            |
| `lib/components/ui/app_checkbox.dart`           | Checkbox wrapper                                          |
| `lib/components/ui/app_dropdown.dart`           | DropdownButton wrapper                                    |
| `lib/components/ui/app_chip.dart`               | Chip wrapper (default/filter/action variants)             |
| `lib/components/ui/app_snackbar.dart`           | Snackbar service helper                                   |
| `lib/components/ui/app_progress_indicator.dart` | Progress indicator wrapper (circular/linear)              |

**Justification:** Each wrapper replaces 10-100+ call sites across the codebase. Consolidating these into a single facade layer reduces future refactor surface from 129 files to 15 files.

---

## Files to Modify

**None.** Piece 1 only creates new files. Zero production call sites are modified.

---

## Files Off-Limits

| File                                                                               | Reason                                                                   |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `lib/main.dart`                                                                    | Init order, routing, and MaterialApp configuration must not change       |
| `lib/app/theme/*.dart`                                                             | Theme configuration is stable—wrappers delegate to it, never override it |
| All files in `lib/features/`                                                       | No call site modifications in Piece 1 (that's Piece 2)                   |
| All files in `lib/shared/`                                                         | No call site modifications in Piece 1                                    |
| Existing precedent components (`lib/components/ui/brand_action_button.dart`, etc.) | Already stable, do not modify                                            |

---

## System Impact Map

| System                                 | Impact                                                           |
| -------------------------------------- | ---------------------------------------------------------------- |
| Gigs                                   | unaffected (no call sites changed)                               |
| Rehearsals                             | unaffected                                                       |
| Setlists / Catalog                     | unaffected                                                       |
| Members / RBAC                         | unaffected                                                       |
| Auth / Session                         | unaffected                                                       |
| Routing                                | unaffected                                                       |
| Notifications                          | unaffected                                                       |
| Platform (iOS / Android / Web / macOS) | affected (wrappers must render correctly across all 4 platforms) |

---

## Regression Risk

**Risk Level:** LOW

**Rationale:**

- **Zero modifications to existing files** — only new files created under `lib/components/ui/`
- **No call sites changed** — wrappers are unused until Piece 2 (separate pipeline cycle)
- **No backend/database surface touched** — pure Flutter UI layer change
- **No init order, routing, or auth flow changes** — `lib/main.dart` untouched
- **Platform impact limited to rendering** — wrappers delegate to Material widgets with default theme config, so visual/behavioral equivalence is high confidence. Easily testable via `flutter build web` + `flutter build ios` + `flutter build apk` + `flutter build macos`.
- **No cross-feature dependencies** — wrappers are standalone widgets with no Riverpod or shared state

**Primary risk:** Prop contract insufficiency—Piece 2 discovers a wrapper prop is missing during retrofit. This is trivially resolved by adding the missing prop to the wrapper without touching any call sites, making it a low-severity, high-tractability risk.

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Create AppScaffold wrapper

- **File:** `lib/components/ui/app_scaffold.dart`
- **Props:** appBar (PreferredSizeWidget?), body (Widget), floatingActionButton (Widget?), bottomNavigationBar (Widget?), backgroundColor (Color? optional override)
- **Implementation:** Wrap `Scaffold`, delegate all props directly, respect theme's scaffoldBackgroundColor unless backgroundColor is provided
- **Verification:** Widget compiles, renders identically to `Scaffold(...)` with default theme

### Task 2: Create AppAppBar wrapper

- **File:** `lib/components/ui/app_app_bar.dart`
- **Props:** title (String or Widget), leading (Widget?), actions (List<Widget>?), backgroundColor (Color? optional override), centerTitle (bool, default from theme)
- **Implementation:** Wrap `AppBar`, delegate all props directly, respect theme's appBarTheme unless overridden
- **Verification:** Widget compiles, renders identically to `AppBar(...)` with default theme

### Task 3: Create AppButton wrapper with variant support

- **File:** `lib/components/ui/app_button.dart`
- **Props:** label (String), onPressed (VoidCallback?), icon (IconData?), variant (enum: primary/secondary/text/outlined), isLoading (bool, default false), fullWidth (bool, default false)
- **Implementation:**
  - Define `AppButtonVariant` enum with 4 values
  - Map variant to underlying Material widget: primary → FilledButton, secondary → ElevatedButton, text → TextButton, outlined → OutlinedButton
  - Respect theme configuration for each button type
  - Show `CircularProgressIndicator` when isLoading is true, disable button interaction
  - If fullWidth is true, wrap in `SizedBox(width: double.infinity, child: ...)`
- **Spot-check call sites:** Review 2-3 real button usages in `lib/features/auth/`, `lib/features/setlists/`, `lib/features/gigs/` to confirm prop surface is sufficient
- **Verification:** Widget compiles, all 4 variants render identically to their Material equivalents

### Task 4: Create AppIconButton wrapper

- **File:** `lib/components/ui/app_icon_button.dart`
- **Props:** icon (IconData), onPressed (VoidCallback?), color (Color? optional), size (double? optional)
- **Implementation:** Wrap `IconButton`, delegate all props, respect theme's iconTheme unless overridden
- **Verification:** Widget compiles, renders identically to `IconButton(...)` with default theme

### Task 5: Create AppTextField wrapper

- **File:** `lib/components/ui/app_text_field.dart`
- **Props:** controller (TextEditingController?), hintText (String?), labelText (String?), prefixIcon (IconData?), suffixIcon (Widget?), obscureText (bool, default false), maxLines (int, default 1), keyboardType (TextInputType?), onChanged (ValueChanged<String>?), enabled (bool, default true)
- **Implementation:** Wrap `TextField`, delegate all props, respect theme's inputDecorationTheme
- **Spot-check call sites:** Review 2-3 real TextField usages to confirm prop surface
- **Verification:** Widget compiles, renders identically to `TextField(...)` with default theme

### Task 6: Create AppTextFormField wrapper

- **File:** `lib/components/ui/app_text_form_field.dart`
- **Props:** All AppTextField props + validator (FormFieldValidator<String>?), onSaved (FormFieldSetter<String>?)
- **Implementation:** Wrap `TextFormField`, delegate all props, respect theme's inputDecorationTheme
- **Verification:** Widget compiles, renders identically to `TextFormField(...)` with default theme

### Task 7: Create AppCard wrapper

- **File:** `lib/components/ui/app_card.dart`
- **Props:** child (Widget), onTap (VoidCallback? optional), padding (EdgeInsets? optional override)
- **Implementation:**
  - Wrap `Card`, delegate child
  - If onTap is provided, wrap in `InkWell` for tap feedback
  - Apply padding to child if provided, otherwise use default spacing
  - Respect theme's cardTheme (color, elevation, shape, margin)
- **Spot-check call sites:** Review 2-3 real Card usages to confirm prop surface
- **Verification:** Widget compiles, renders identically to `Card(...)` with default theme

### Task 8: Create AppDialog helper and widget

- **File:** `lib/components/ui/app_dialog.dart`
- **Helper function:** `showAppDialog({required BuildContext context, required String title, required String message, required List<DialogAction> actions, bool barrierDismissible = true}) → Future<T?>`
- **Widget:** `AppAlertDialog` wrapping `AlertDialog`
- **DialogAction class:** Simple data class with label (String), onPressed (VoidCallback?), isDestructive (bool)
- **Implementation:**
  - `showAppDialog` calls `showDialog` with `AppAlertDialog` builder
  - `AppAlertDialog` wraps `AlertDialog`, respects theme's dialogTheme
  - Maps DialogAction list to TextButton/FilledButton children based on isDestructive flag
- **Spot-check call sites:** Review 2-3 real showDialog usages
- **Verification:** Dialog renders identically to `showDialog` with `AlertDialog`

### Task 9: Create AppBottomSheet helper

- **File:** `lib/components/ui/app_bottom_sheet.dart`
- **Helper function:** `showAppBottomSheet({required BuildContext context, required WidgetBuilder builder, bool isDismissible = true, bool useRootNavigator = false}) → Future<T?>`
- **Implementation:** Wrap `showModalBottomSheet`, delegate all props, respect theme's bottomSheetTheme
- **Verification:** Bottom sheet renders identically to `showModalBottomSheet(...)`

### Task 10: Create AppSwitch wrapper

- **File:** `lib/components/ui/app_switch.dart`
- **Props:** value (bool), onChanged (ValueChanged<bool>?), activeColor (Color? optional)
- **Implementation:** Wrap `Switch`, delegate all props, respect theme's switchTheme unless activeColor is provided
- **Verification:** Widget compiles, renders identically to `Switch(...)` with default theme

### Task 11: Create AppCheckbox wrapper

- **File:** `lib/components/ui/app_checkbox.dart`
- **Props:** value (bool?), onChanged (ValueChanged<bool?>?), activeColor (Color? optional)
- **Implementation:** Wrap `Checkbox`, delegate all props, respect theme's checkboxTheme unless activeColor is provided
- **Verification:** Widget compiles, renders identically to `Checkbox(...)` with default theme

### Task 12: Create AppDropdown wrapper

- **File:** `lib/components/ui/app_dropdown.dart`
- **Props:** value (T?), items (List<DropdownMenuItem<T>>), onChanged (ValueChanged<T?>?), hint (Widget?)
- **Implementation:** Wrap `DropdownButton<T>`, delegate all props, respect theme's dropdownMenuTheme
- **Spot-check call sites:** Review 1-2 real DropdownButton usages
- **Verification:** Widget compiles, renders identically to `DropdownButton(...)` with default theme

### Task 13: Create AppChip wrapper with variant support

- **File:** `lib/components/ui/app_chip.dart`
- **Props:** label (String), onTap (VoidCallback? optional), isSelected (bool? optional), variant (enum: default/filter/action)
- **Implementation:**
  - Define `AppChipVariant` enum with 3 values
  - Map variant to underlying Material widget: default → Chip, filter → FilterChip, action → ActionChip
  - Respect theme's chipTheme
- **Verification:** Widget compiles, all 3 variants render identically to their Material equivalents

### Task 14: Create AppSnackbar service helper

- **File:** `lib/components/ui/app_snackbar.dart`
- **Helper functions:**
  - `showAppSnackbar({required BuildContext context, required String message, SnackBarAction? action, Duration? duration, SnackbarType type = SnackbarType.info})`
  - Define `SnackbarType` enum with 3 values: info, success, error
- **Implementation:**
  - Call `ScaffoldMessenger.of(context).showSnackBar(...)`
  - Map type to background color (info → theme default, success → green, error → red)
  - Respect theme's snackBarTheme
- **Note:** Existing `shared/utils/snackbar_helper.dart` may have similar functionality—review for consistency but do not modify it
- **Verification:** Snackbar renders identically to `ScaffoldMessenger.showSnackBar(...)`

### Task 15: Create AppProgressIndicator wrapper

- **File:** `lib/components/ui/app_progress_indicator.dart`
- **Props:** type (enum: circular/linear), value (double? optional for determinate progress), color (Color? optional)
- **Implementation:**
  - Define `ProgressIndicatorType` enum with 2 values
  - Map type to underlying Material widget: circular → CircularProgressIndicator, linear → LinearProgressIndicator
  - Respect theme's progressIndicatorTheme unless color is provided
- **Verification:** Widget compiles, both types render identically to their Material equivalents

### Task 16: Create widget tests for all 15 wrappers

- **Directory:** `test/components/ui/`
- **Test files:** One test file per wrapper (e.g., `app_button_test.dart`, `app_scaffold_test.dart`, etc.)
- **Test coverage per wrapper:**
  - Widget renders without errors
  - Props are correctly delegated to underlying Material widget
  - Behavior is equivalent to Material widget (e.g., AppButton with variant=primary behaves like FilledButton)
  - Theme configuration is respected (e.g., AppCard inherits cardTheme radius)
- **Minimum bar:** 1 widget test per wrapper proving it renders and behaves equivalently to its default-styled Material counterpart
- **Run tests:** `flutter test test/components/ui/` — all tests must pass

### Task 17: Verify zero files modified outside lib/components/ui/

- **Command:** `git diff --stat`
- **Expected output:** Only new files under `lib/components/ui/`, no modifications to any file outside that directory
- **Regression guard:** This confirms no call sites were accidentally touched

### Task 18: Run flutter analyze

- **Command:** `flutter analyze`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding

### Task 19: Build app for all platforms

- **Commands:**
  - `flutter build web --release`
  - `flutter build ios --release --no-codesign` (macOS host only)
  - `flutter build apk --release`
  - `flutter build macos --release`
- **Expected output:** All builds succeed, no runtime errors
- **Note:** Wrappers are unused, so builds should succeed identically to before. This verifies no import/compile errors were introduced.

### Task 20: Spot-check wrapper API sufficiency

- **Manual review:** For each of the 15 wrappers, manually inspect 2-3 real call sites across different features (e.g., auth, setlists, gigs, profile) to confirm the wrapper's prop surface can plausibly replace the Material widget call
- **Do not modify call sites** — this is a read-only verification step
- **Document any insufficiencies:** If a real call site requires a prop not exposed by the wrapper, note it in ENGINEER_REPORT.md under "API Gaps Discovered" with file path + line number + missing prop name
- **This informs Piece 2:** Any gaps discovered here can be trivially added to the wrapper before Piece 2 retrofits begin

---

## Verification Plan

**Tier 1 — Pre-deployment (N/A for this feature—no migrations):**

This feature has no database migrations, edge functions, or backend changes. All verification is Flutter-local.

**Tier 2 — Post-implementation:**

### Test 1: flutter analyze passes with 0 errors

```bash
cd /Users/tonyholmes/apps/bandroadie-ui-experiment
flutter analyze
```

**Expected output:** 0 errors, 0 warnings.

### Test 2: flutter build web succeeds

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Expected output:** Build succeeds, `build/web/` directory contains compiled output.

### Test 3: Widget tests pass for all 15 wrappers

```bash
flutter test test/components/ui/
```

**Expected output:** All widget tests pass. Each of the 15 wrappers has at least one test proving it renders and behaves equivalently to its Material counterpart.

### Test 4: git diff confirms zero files modified outside lib/components/ui/

```bash
git diff --stat
```

**Expected output:** Only new files under `lib/components/ui/`, zero modifications to any file outside that directory. This is the primary regression guard—confirms no call sites were accidentally touched.

### Test 5: App still builds and runs completely unchanged

- Run app on web: `flutter run -d chrome`
- Run app on macOS: `flutter run -d macos`
- **Expected behavior:** App launches, all screens render identically to before, no runtime errors. This confirms wrappers don't interfere with existing code (since they're unused).

### Test 6: Spot-check wrapper API sufficiency (read-only)

- Manually inspect 2-3 real call sites per wrapper type across different features (auth, setlists, gigs, profile)
- Confirm each wrapper's prop surface can plausibly replace its Material equivalent
- Document any API gaps in ENGINEER_REPORT.md (these can be trivially added before Piece 2)

---

## QA Regression Areas

Since Piece 1 does not modify any call sites, there is no user-facing behavior change to validate. QA verification focuses on confirming the isolation boundary held:

1. **Confirm zero files modified outside `lib/components/ui/`**: Review `git diff --stat` output—only new files should appear.
2. **Confirm app still builds and runs identically**: Run app on web + macOS, navigate through all major screens (auth, home, setlists, gigs, rehearsals, profile, settings), confirm no visual or behavioral changes.
3. **Confirm each wrapper renders correctly**: Review widget test coverage report, confirm all 15 wrappers have passing tests.
4. **Confirm no runtime errors introduced**: Run `flutter analyze`, confirm 0 errors.
5. **Spot-check wrapper API sufficiency**: For 3-5 randomly selected wrappers, manually review 2-3 real call sites in feature code and confirm the wrapper's prop surface is sufficient to replace the Material widget (read-only, no modifications).

**No regression testing of feature behavior required** — wrappers are unused until Piece 2. This QA pass is purely a build/compile/render smoke test.

---

## Rollout / Migration Strategy

Not applicable — this feature introduces no user-facing changes, no database migrations, no backend changes. Rollout is a standard git merge + deploy (no special sequencing required).

---

## Out of Scope

The following are explicitly deferred to Piece 2 (separate future pipeline cycle):

1. **Retrofitting existing call sites** — Piece 1 only builds the wrapper layer. Rewriting ~100+ call sites across `lib/features/` to use the new wrappers is Piece 2 work, folder-by-folder: profile/settings/notifications/auth first, then members/venues/calendar/rehearsals, gigs/setlists last.
2. **Custom styling or behavior changes** — Piece 1 wrappers are visually and behaviorally identical to Material defaults. Any design-system customization (Forui, refined styling, animation changes) is future work after Piece 2 completes.
3. **Platform-specific wrapper logic** — Piece 1 wrappers work uniformly across all platforms. Any platform-specific divergence is future work (not anticipated).
4. **Web-specific wrapper variants** — No web-only wrapper logic in Piece 1.
5. **Accessibility enhancements** — Wrappers inherit Material's accessibility behavior. Any enhancements are future work.
6. **Performance optimization** — Piece 1 focuses on API correctness, not performance. Optimization (if needed) is future work.
7. **Documentation of wrapper usage patterns** — Piece 1 creates the widgets. Developer-facing documentation (e.g., "when to use AppButton vs BrandActionButton") is Piece 2 work once real retrofits reveal usage patterns.
