# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-wrapper-gaps-2`

---

## Problem Summary

The ui-facade-retrofit-core cycle (commit ad50e71, 2026-08-06) successfully retrofitted 11 screens across profile/settings/notifications/auth to use App\* wrappers, but discovered 7 additional API gaps that blocked prop-for-prop replacement at specific call sites. These gaps were resolved by keeping the affected call sites as raw Material widgets (documented as "pre-approved boundary conditions" in ENGINEER_REPORT.md and QA_REPORT.md). This is the second wrapper-gaps closing cycle—additive-only extensions to 4 existing wrapper files, following the exact pattern established in the first wrapper-gaps cycle (docs/features/ui-facade-wrapper-gaps/).

**Why this must be fixed now:** These 7 gaps represent real usage patterns already validated by production code. Closing them enables a future micro-cycle to re-retrofit the 3 affected files (my_profile_screen.dart, login_screen.dart, invite_screen.dart) from raw Material back to App\* wrappers, completing the original retrofit-core scope. Same mechanical transformation principle: extend wrapper APIs before touching call sites.

**Scope:** Additive-only changes to 4 existing wrapper files (AppTextField, AppTextFormField, AppScaffold, AppButton) + their test files. No new files. No production call sites touched (re-retrofitting the 3 files above is a separate future micro-cycle, explicitly out of scope here). Same zero-blast-radius shape as the first wrapper-gaps cycle.

---

## Current State

**AppTextField / AppTextFormField** (lib/components/ui/app_text_field.dart, app_text_form_field.dart)

Current props (from first wrapper-gaps cycle): `controller`, `focusNode`, `decoration`, `hintText`, `labelText`, `prefixIcon`, `suffixIcon`, `obscureText`, `maxLines`, `keyboardType`, `textCapitalization`, `textInputAction`, `style`, `onChanged`, `enabled` (TextFormField adds `validator`, `onSaved`)

**Gaps discovered in retrofit-core cycle:**

1. **inputFormatters** — [lib/features/profile/my_profile_screen.dart:1021-1110](lib/features/profile/my_profile_screen.dart#L1021-L1110) `_buildTextField` helper uses `TextFormField(inputFormatters: [PhoneNumberInputFormatter()])` for phone field. AppTextFormField doesn't expose this prop, so the entire helper (4 fields) was kept as raw Material.

2. **autocorrect** — [lib/features/auth/login_screen.dart:492](lib/features/auth/login_screen.dart#L492) email TextField uses `autocorrect: false` to disable autocorrect for email input. AppTextField doesn't expose this prop.

3. **autofillHints** — [lib/features/auth/login_screen.dart:492](lib/features/auth/login_screen.dart#L492) email TextField uses `autofillHints: [AutofillHints.email]` for password manager integration. AppTextField doesn't expose this prop.

4. **onSubmitted** — [lib/features/auth/login_screen.dart:492](lib/features/auth/login_screen.dart#L492), [lib/features/auth/invite_screen.dart:520](lib/features/auth/invite_screen.dart#L520), and [lib/features/profile/my_profile_screen.dart:464](lib/features/profile/my_profile_screen.dart#L464) all use `onSubmitted` callback for "Enter to submit" UX. AppTextField doesn't expose this prop.

5. **autofocus** — [lib/features/profile/my_profile_screen.dart:464](lib/features/profile/my_profile_screen.dart#L464) custom role dialog TextField uses `autofocus: true` for immediate typing when dialog opens. AppTextField doesn't expose this prop.

**Confidence:** HIGH — directly observed in retrofit-core QA_REPORT.md and ENGINEER_REPORT.md, with exact line numbers and usage context.

**AppScaffold** (lib/components/ui/app_scaffold.dart)

Current props: `appBar`, `body`, `floatingActionButton`, `bottomNavigationBar`, `backgroundColor`

**Gap discovered in retrofit-core cycle:**

6. **resizeToAvoidBottomInset** — [lib/features/auth/login_screen.dart:480](lib/features/auth/login_screen.dart#L480) main Scaffold uses `resizeToAvoidBottomInset: false` for keyboard-aware logo animation. AppScaffold doesn't expose this prop, so the main Scaffold was kept as raw Material.

**Confidence:** HIGH — directly observed in retrofit-core QA_REPORT.md with exact line number and usage context.

**AppButton** (lib/components/ui/app_button.dart)

Current variants: `AppButtonVariant.primary` (FilledButton), `AppButtonVariant.secondary` (ElevatedButton), `AppButtonVariant.text` (TextButton), `AppButtonVariant.outlined` (OutlinedButton)

**Gap discovered in retrofit-core cycle:**

7. **Destructive action styling** — [lib/features/settings/settings_screen.dart:195](lib/features/settings/settings_screen.dart#L195) "Delete Account" button in `_showDeleteConfirmation` dialog uses `TextButton.styleFrom(backgroundColor: AppColors.error, padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))` with white bold text. AppButton has no semantic destructive/error-color variant—only the 4 existing variants which use theme colors, none of which map to error/destructive styling. The button was kept as raw Material `TextButton` with explicit `AppColors.error` background.

**Confidence:** HIGH — directly observed in retrofit-core QA_REPORT.md with exact line number and usage context. Real usage shows: filled button (not text-only), error-colored background (not theme primary/secondary), 8px border radius, white text, used for dangerous/irreversible actions (account deletion).

---

## Reference Docs Consulted

**docs/reference/notifications/:** Irrelevant to this feature (per Phase 4 override—this is a UI facade feature, not a notification domain feature).

**docs/reference/ui/:** Known empty of relevant guidance from first wrapper-gaps cycle. No design-system documentation exists for wrapper prop coverage or variant taxonomy.

**No relevant reference documentation.** Proceeded with codebase inspection and precedent analysis per ARCHITECT.md fallback protocol for missing/irrelevant reference directories.

---

## Existing System Analysis

**First wrapper-gaps cycle precedent (docs/features/ui-facade-wrapper-gaps/):**

- Additive-only pattern: new props added as optional/nullable with sensible defaults, zero breaking changes to existing API
- Direct passthrough to Material: no custom logic, just delegation (e.g., `focusNode: focusNode`, `textCapitalization: textCapitalization`)
- Optional props default to Material's own defaults when null (e.g., `textInputAction?` passed as-is, TextField handles null by using its default)
- Wrapper tests verify delegation only—no custom rendering logic tested because wrappers don't add custom logic
- 77 original Piece 1 tests continued passing unmodified—backward compatibility preserved

**Current wrapper implementations (post-first-gaps-cycle):**

1. **AppTextField / AppTextFormField** — Already extended with focusNode, textCapitalization, textInputAction, style, decoration. Missing: inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus. All 5 missing props are standard TextField/TextFormField props, all optional/nullable in Material API.

2. **AppScaffold** — Minimal wrapper with 5 props. Missing: resizeToAvoidBottomInset. This prop is optional/nullable in Scaffold (defaults to true when null).

3. **AppButton** — Enum-based variant system (primary/secondary/text/outlined), delegates to Material button widgets based on variant. Missing: destructive/error-color variant for dangerous actions. Current variants are semantic (primary = main action, secondary = alternate, text = low priority, outlined = neutral emphasis), not style-override props (no `color: Color` prop exists—design is semantic-first).

**Data flow:** No data flow changes—wrappers are presentational delegates to Material widgets. This work only extends the API surface of 4 existing wrapper files. No state management, no controllers, no backend surface touched.

---

## Proposed Solution

Extend 4 wrapper files with 7 missing props/features, following the precedent pattern from first wrapper-gaps cycle. All additions are optional (nullable/default-valued), maintaining backward compatibility with existing API. No new files created. No production call sites modified.

### Solution 1: AppTextField / AppTextFormField — Add 5 Missing Props

**Add 5 new optional props to both AppTextField and AppTextFormField:**

1. `inputFormatters: List<TextInputFormatter>?` — passed directly to TextField/TextFormField
2. `autocorrect: bool` — default `true` (matches TextField's default), passed directly to TextField/TextFormField
3. `autofillHints: Iterable<String>?` — passed directly to TextField/TextFormField
4. `onSubmitted: ValueChanged<String>?` — passed directly to TextField/TextFormField
5. `autofocus: bool` — default `false` (matches TextField's default), passed directly to TextField/TextFormField

**Why this design:**

- Minimal API change — 5 new props, all optional
- Direct passthrough to Material API — no custom logic, just delegation (same pattern as focusNode, textCapitalization, textInputAction, style from first cycle)
- Defaults match Material's own defaults (`autocorrect: true`, `autofocus: false`) so wrappers behave identically to raw Material when props are not provided
- All 5 props are standard TextField/TextFormField props, well-documented in Flutter API
- No breaking changes — existing call sites (including all tests from Piece 1 + first-gaps-cycle) continue working identically

**Implementation detail:** Both AppTextField and AppTextFormField get identical new props—TextFormField inherits all TextField props, so the same 5 additions apply to both.

### Solution 2: AppScaffold — Add resizeToAvoidBottomInset

**Add 1 new optional prop:**

- `resizeToAvoidBottomInset: bool?` — passed directly to Scaffold

**Why this design:**

- Minimal API change — 1 new prop, optional/nullable
- Direct passthrough to Material API — no custom logic
- Nullable (not `bool` with default) so Scaffold's own default (true) applies when null—preserves Material's default behavior exactly
- Matches Scaffold's API surface directly (Scaffold.resizeToAvoidBottomInset is nullable)

**Why nullable instead of `bool` with default `true`:** Scaffold's default is `true`, but making the wrapper prop `bool? = null` and passing it directly allows Scaffold to apply its own default when null. This is safer than hardcoding `true` in the wrapper—if Scaffold's default changes in future Flutter versions, the wrapper automatically inherits the new default. Same pattern used for optional props in first-gaps-cycle where Material has its own defaults.

### Solution 3: AppButton — Add Destructive Variant

**Add 1 new variant to AppButtonVariant enum:**

```dart
enum AppButtonVariant {
  primary,
  secondary,
  text,
  outlined,
  destructive,  // NEW: error-colored filled button for dangerous actions
}
```

**Internal mapping for `AppButtonVariant.destructive`:**

- Base widget: `FilledButton` (filled, not text-only or outlined—matches real usage in settings_screen.dart)
- Background color: `AppColors.error` (red, visually distinct from primary/secondary which use theme colors)
- Foreground color: `Colors.white` (high contrast against error background)
- Shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))` (8px corner radius—matches real usage and other button variants)
- Padding: Delegate to `FilledButton` theme defaults (no custom padding—real usage's `EdgeInsets.symmetric(horizontal: 20, vertical: 10)` is a layout constraint, not a button style prop; the `SizedBox` wrapper or parent layout can control sizing if needed)

**Why this design (semantic variant, not color-override prop):**

1. **Consistency with wrapper philosophy:** All 15 wrappers use semantic props, not raw style passthroughs. AppButton already uses variant enum (primary/secondary/text/outlined), not a `color: Color` prop. Adding `destructive` as a 5th variant maintains this semantic-first design. Matches AppChip's similar variant pattern elsewhere in the codebase.

2. **Matches real usage semantics:** The "Delete Account" button is not "a button with a custom color"—it's "a destructive action button." The semantic meaning (dangerous/irreversible action) is more important than the visual style (happens to be red). Future destructive buttons (e.g., "Delete Band", "Leave Band", "Cancel Gig") will have the same semantic meaning and should automatically get consistent styling via the same variant.

3. **Prevents style fragmentation:** If we added a generic `backgroundColor: Color?` prop instead, every dangerous button would need manual `AppColors.error` + `Colors.white` text styling at every call site. Semantic variant centralizes the "destructive action" style in one place, keeping call sites simple (`AppButton(variant: AppButtonVariant.destructive)` vs. `AppButton(backgroundColor: AppColors.error, textColor: Colors.white)`).

4. **Aligns with Material 3 guidelines:** Material Design defines semantic button types (primary, secondary, tertiary, error/destructive) as distinct variants, not as color overrides. Flutter's own Material 3 button system uses separate widgets (FilledButton, ElevatedButton, TextButton, OutlinedButton) for semantic roles, not a single Button widget with style props.

5. **Type-safe and discoverable:** Enum value is autocomplete-discoverable and type-checked. `AppButton(variant: AppButtonVariant.destructive)` is self-documenting at call sites—the variant name conveys intent. A `color` prop would require documentation/comments to explain when to use `AppColors.error`.

**Alternative considered and rejected:** Generic `backgroundColor: Color?` and `foregroundColor: Color?` props. Rejected because:

- Breaks semantic-first wrapper design (all 15 wrappers avoid raw style props)
- Requires manual color + text color pairing at every call site (error-prone—easy to forget white text on red background)
- Fragments styling—no single source of truth for "what does a destructive button look like?"
- Doesn't scale—if we later need "warning" (yellow) or "success" (green) button variants, we'd still need semantic variants, making the color props redundant

**Why `FilledButton` not `TextButton`:** Real usage in settings_screen.dart shows a filled button (`backgroundColor: AppColors.error`), not a text-only button. Filled buttons have higher visual weight, appropriate for dangerous actions that need user attention. TextButton would be visually weak for a destructive action.

---

## Database Impact

**Database:** not applicable — this feature touches zero backend/Supabase surface. All changes are Flutter UI layer only.

---

## Flutter Architecture Changes

**State Management:** None. Wrappers remain plain StatelessWidget with no Riverpod dependencies.

**Widget Tree:** No new widgets created. Modifications only to 4 existing wrapper files (AppTextField, AppTextFormField, AppScaffold, AppButton).

**Repositories:** None.

**Controllers/Notifiers:** None.

---

## Files to Create

**None.** This feature only modifies existing wrapper files from Piece 1 + first wrapper-gaps cycle.

---

## Files to Modify

| File                                               | What changes                                                                                                                                                                                                    |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_text_field.dart`            | Add 5 new optional props: `inputFormatters`, `autocorrect` (default `true`), `autofillHints`, `onSubmitted`, `autofocus` (default `false`). Pass all 5 directly to TextField.                                   |
| `lib/components/ui/app_text_form_field.dart`       | Add same 5 new optional props as AppTextField. Pass all 5 directly to TextFormField.                                                                                                                            |
| `lib/components/ui/app_scaffold.dart`              | Add 1 new optional prop: `resizeToAvoidBottomInset` (nullable). Pass directly to Scaffold.                                                                                                                      |
| `lib/components/ui/app_button.dart`                | Add `destructive` value to `AppButtonVariant` enum. Update `build()` switch to handle `destructive` case: FilledButton with `AppColors.error` background, `Colors.white` foreground, 8px border radius.         |
| `test/components/ui/app_text_field_test.dart`      | Add 5 new tests: inputFormatters delegation, autocorrect delegation, autofillHints delegation, onSubmitted delegation, autofocus delegation.                                                                    |
| `test/components/ui/app_text_form_field_test.dart` | Add same 5 new tests as AppTextField (verify delegation to TextFormField).                                                                                                                                      |
| `test/components/ui/app_scaffold_test.dart`        | Add 1 new test: resizeToAvoidBottomInset delegation to Scaffold.                                                                                                                                                |
| `test/components/ui/app_button_test.dart`          | Add 2 new tests: (1) `AppButtonVariant.destructive` renders FilledButton with error background and white text, (2) destructive variant with icon renders correctly (same icon+label pattern as other variants). |

---

## Files Off-Limits

| File                                                                               | Reason                                                                                                                                                 |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                                    | Init order must not change                                                                                                                             |
| `lib/app/theme/*.dart`                                                             | Theme configuration is stable—wrappers delegate to it, never override it (exception: destructive button is a new semantic variant, not a theme change) |
| All files in `lib/features/`                                                       | No call site modifications until re-retrofit micro-cycle (separate future pipeline cycle—explicitly out of scope here)                                 |
| All files in `lib/shared/`                                                         | No call site modifications until re-retrofit micro-cycle                                                                                               |
| All other wrapper files in `lib/components/ui/`                                    | Only the 4 identified wrappers (AppTextField, AppTextFormField, AppScaffold, AppButton) have gaps. Do not modify the other 11 wrappers.                |
| Existing precedent components (`lib/components/ui/brand_action_button.dart`, etc.) | Already stable, do not modify                                                                                                                          |

---

## System Impact Map

| System                                 | Impact                                                                                                                                                                        |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (no call sites changed)                                                                                                                                            |
| Rehearsals                             | unaffected                                                                                                                                                                    |
| Setlists / Catalog                     | unaffected                                                                                                                                                                    |
| Members / RBAC                         | unaffected                                                                                                                                                                    |
| Auth / Session                         | unaffected                                                                                                                                                                    |
| Routing                                | unaffected                                                                                                                                                                    |
| Notifications                          | unaffected                                                                                                                                                                    |
| Platform (iOS / Android / Web / macOS) | affected (new props must render correctly across all 4 platforms—but all 7 new features are direct passthroughs to Material APIs, so platform equivalence is high confidence) |

---

## Regression Risk

**Risk Level:** LOW

**Rationale:**

- **Additive-only changes** — all new props are optional with sensible defaults, all existing tests (77 from Piece 1 + 18 from first-gaps-cycle = 95 tests) continue passing with zero modifications
- **Zero modifications to production call sites** — wrappers are already in use post-retrofit-core, but the 3 files with documented boundary conditions (my_profile_screen, login_screen, invite_screen) are not being re-retrofitted in this cycle. No call sites change.
- **No new files** — only extending 4 existing wrapper files
- **No backend/database surface touched** — pure Flutter UI layer change
- **No init order, routing, or auth flow changes** — `lib/main.dart` untouched
- **Platform impact limited to rendering** — all 7 new features are direct passthroughs to Material widget APIs (inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus, resizeToAvoidBottomInset, destructive button variant backed by FilledButton + AppColors.error). Material already handles cross-platform equivalence for these props/styles, so wrappers inherit that stability.
- **Backward compatibility guaranteed** — all new props are optional with defaults matching Material's own defaults. Existing call sites and tests continue working identically.
- **Destructive button variant is additive** — existing 4 variants (primary/secondary/text/outlined) unchanged. New variant is opt-in only. No existing call sites are affected.

**Primary risk:** Destructive button styling might not match theme expectations on all platforms—but this is mitigated by using `AppColors.error` (already used in the codebase for error states) and `Colors.white` (high-contrast, platform-agnostic). The 8px border radius matches other button variants (standard Material 3 rounded rectangle). Insufficient testing of the new destructive variant is also a risk—mitigated by requiring 2 dedicated tests (one for basic rendering, one for icon+label pattern).

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Extend AppTextField with 5 missing props

- **File:** `lib/components/ui/app_text_field.dart`
- **Add 5 new props to constructor:**
  - `inputFormatters: List<TextInputFormatter>?`
  - `autocorrect: bool` (default `true`)
  - `autofillHints: Iterable<String>?`
  - `onSubmitted: ValueChanged<String>?`
  - `autofocus: bool` (default `false`)
- **Add import:** `import 'package:flutter/services.dart';` (for `TextInputFormatter`)
- **Implementation:**
  - Add all 5 props to `TextField()` call in `build()` method
  - Pass props directly: `inputFormatters: inputFormatters`, `autocorrect: autocorrect`, etc.
- **Doc comments:** Document each prop with standard Flutter convention (/// comment above prop)
- **Verification:** Widget compiles, passes existing tests (no modifications to tests yet)

### Task 2: Extend AppTextFormField with 5 missing props

- **File:** `lib/components/ui/app_text_form_field.dart`
- **Add same 5 new props as AppTextField** (identical names, types, defaults)
- **Add import:** `import 'package:flutter/services.dart';` (for `TextInputFormatter`)
- **Implementation:** Add all 5 props to `TextFormField()` call in `build()` method
- **Verification:** Widget compiles, passes existing tests

### Task 3: Extend AppScaffold with resizeToAvoidBottomInset

- **File:** `lib/components/ui/app_scaffold.dart`
- **Add 1 new prop to constructor:**
  - `resizeToAvoidBottomInset: bool?` (nullable, no default)
- **Implementation:** Add prop to `Scaffold()` call in `build()` method: `resizeToAvoidBottomInset: resizeToAvoidBottomInset`
- **Doc comment:** Document prop with standard Flutter convention
- **Verification:** Widget compiles, passes existing tests

### Task 4: Extend AppButton with destructive variant

- **File:** `lib/components/ui/app_button.dart`
- **Add 1 new value to AppButtonVariant enum:**
  ```dart
  enum AppButtonVariant {
    primary,
    secondary,
    text,
    outlined,
    destructive, // Error-colored filled button for dangerous actions
  }
  ```
- **Add import:** `import 'package:bandroadie/app/theme/design_tokens.dart';` (for `AppColors.error`)
- **Update `build()` method switch statement:** Add new case for `AppButtonVariant.destructive`:
  ```dart
  case AppButtonVariant.destructive:
    button = FilledButton(
      onPressed: effectiveOnPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.error,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: content,
    );
  ```
- **Doc comment:** Update `AppButtonVariant` enum doc comment to describe destructive variant
- **Verification:** Widget compiles, passes existing tests

### Task 5: Add tests for AppTextField new props

- **File:** `test/components/ui/app_text_field_test.dart`
- **Add 5 new tests:**
  1. Test inputFormatters delegation: Provide `inputFormatters: [LengthLimitingTextInputFormatter(5)]`, verify TextField props contain the formatter (note: TextField doesn't expose props directly, so test may need to verify behavior instead—e.g., widget renders without error)
  2. Test autocorrect delegation: Provide `autocorrect: false`, verify TextField props (same note as above)
  3. Test autofillHints delegation: Provide `autofillHints: [AutofillHints.email]`, verify TextField props
  4. Test onSubmitted delegation: Provide `onSubmitted: (value) { ... }`, verify callback fires on submit (use `tester.testTextInput.receiveAction(TextInputAction.done)`)
  5. Test autofocus delegation: Provide `autofocus: true`, verify TextField props (or verify widget renders without error)
- **Note:** AppTextField from first-gaps-cycle has 13 existing tests. New tests bring total to 18.
- **Verification:** All 18 tests pass

### Task 6: Add tests for AppTextFormField new props

- **File:** `test/components/ui/app_text_form_field_test.dart`
- **Add same 5 new tests as Task 5** (verify delegation to TextFormField instead of TextField)
- **Note:** AppTextFormField from first-gaps-cycle has 12 existing tests. New tests bring total to 17.
- **Verification:** All 17 tests pass

### Task 7: Add test for AppScaffold resizeToAvoidBottomInset

- **File:** `test/components/ui/app_scaffold_test.dart`
- **Add 1 new test:**
  - Test resizeToAvoidBottomInset delegation: Provide `resizeToAvoidBottomInset: false`, verify Scaffold renders correctly (note: Scaffold doesn't expose props directly, so test verifies widget renders without error and no assertions fail)
- **Note:** AppScaffold has existing tests. New test adds 1 more.
- **Verification:** All tests pass

### Task 8: Add tests for AppButton destructive variant

- **File:** `test/components/ui/app_button_test.dart`
- **Add 2 new tests:**
  1. Test destructive variant basic rendering: `AppButton(label: 'Delete', onPressed: () {}, variant: AppButtonVariant.destructive)` renders FilledButton with error background and white text (verify widget renders, find FilledButton in tree)
  2. Test destructive variant with icon: `AppButton(label: 'Delete', icon: Icons.delete, onPressed: () {}, variant: AppButtonVariant.destructive)` renders with both icon and label (verify Row with Icon + Text children exists)
- **Note:** AppButton has existing tests for primary/secondary/text/outlined variants. New tests add 2 more for destructive variant.
- **Verification:** All tests pass

### Task 9: Run all widget tests

- **Command:** `flutter test test/components/ui/`
- **Expected output:** All tests pass. Existing tests from Piece 1 + first-gaps-cycle (95 tests) + new tests from this cycle (5 + 5 + 1 + 2 = 13 new tests) = 108 total tests.
- **If failures:** Fix them before proceeding

### Task 10: Verify zero files modified outside target files

- **Command:** `git diff --stat`
- **Expected output:** Only 8 files modified:
  - `lib/components/ui/app_text_field.dart`
  - `lib/components/ui/app_text_form_field.dart`
  - `lib/components/ui/app_scaffold.dart`
  - `lib/components/ui/app_button.dart`
  - `test/components/ui/app_text_field_test.dart`
  - `test/components/ui/app_text_form_field_test.dart`
  - `test/components/ui/app_scaffold_test.dart`
  - `test/components/ui/app_button_test.dart`
- **Regression guard:** Confirms no other files were accidentally touched, no production call sites changed

### Task 11: Run flutter analyze

- **Command:** `flutter analyze`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding

### Task 12: Build app for web (mandatory)

- **Command:** `flutter build web --release`
- **Expected output:** Build succeeds, `build/web/` directory contains compiled output
- **Note:** Best-effort for non-web platforms per toolchain availability

### Task 13: Manual verification — spot-check new props against real call sites

- **Read-only verification:** Manually inspect the 3 identified files and their specific boundary-condition call sites:
  1. [lib/features/profile/my_profile_screen.dart:1021-1110](lib/features/profile/my_profile_screen.dart#L1021-L1110) — verify AppTextFormField can now express `inputFormatters: [PhoneNumberInputFormatter()]`, `autofocus`, `onSubmitted`
  2. [lib/features/auth/login_screen.dart:480](lib/features/auth/login_screen.dart#L480) — verify AppScaffold can now express `resizeToAvoidBottomInset: false`
  3. [lib/features/auth/login_screen.dart:492](lib/features/auth/login_screen.dart#L492) — verify AppTextField can now express `autocorrect: false`, `autofillHints: [AutofillHints.email]`, `onSubmitted`
  4. [lib/features/auth/invite_screen.dart:520](lib/features/auth/invite_screen.dart#L520) — verify AppTextField can now express `onSubmitted`
  5. [lib/features/settings/settings_screen.dart:195](lib/features/settings/settings_screen.dart#L195) — verify AppButton can now express `variant: AppButtonVariant.destructive` for "Delete Account" button (replacing raw TextButton with error background)
- **Do not modify call sites** — this is verification only, re-retrofitting is a separate future micro-cycle
- **Document in ENGINEER_REPORT.md:** Confirm that all 7 gaps can now be expressed via wrapper APIs

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

### Test 2: All widget tests pass

```bash
flutter test test/components/ui/
```

**Expected output:** All tests pass. This includes:

- Piece 1 + first-gaps-cycle tests (95 tests, unchanged, must still pass)
- New tests for AppTextField (5 tests covering inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus)
- New tests for AppTextFormField (5 tests, same coverage as AppTextField)
- New test for AppScaffold (1 test covering resizeToAvoidBottomInset)
- New tests for AppButton (2 tests covering destructive variant basic rendering and icon+label)

Minimum total test count: 95 + 5 + 5 + 1 + 2 = 108 tests.

### Test 3: flutter build web succeeds

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Expected output:** Build succeeds, `build/web/` directory contains compiled output.

### Test 4: git diff confirms only 8 files modified

```bash
git diff --stat
```

**Expected output:** Exactly 8 files modified:

- 4 wrapper files (app_text_field.dart, app_text_form_field.dart, app_scaffold.dart, app_button.dart)
- 4 test files (corresponding \*\_test.dart files)

Zero other files touched. This is the primary regression guard—confirms no production call sites were changed, no unrelated wrappers were modified, no theme files touched.

### Test 5: App still runs completely unchanged

- Run app on web: `flutter run -d chrome`
- **Expected behavior:** App launches, all screens render identically to before, no runtime errors. This confirms new props don't interfere with existing code (wrappers are already in use post-retrofit-core, but no call sites use the new props yet—next micro-cycle will re-retrofit the 3 boundary-condition files).

### Test 6: Spot-check new props against real call sites (read-only)

- Manually inspect 5 identified call sites (referenced in Task 13):
  1. my_profile_screen.dart:1021-1110 — verify AppTextFormField can express inputFormatters + autofocus + onSubmitted
  2. login_screen.dart:480 — verify AppScaffold can express resizeToAvoidBottomInset
  3. login_screen.dart:492 — verify AppTextField can express autocorrect + autofillHints + onSubmitted
  4. invite_screen.dart:520 — verify AppTextField can express onSubmitted
  5. settings_screen.dart:195 — verify AppButton can express destructive variant
- Confirm each new prop/variant can express the real usage pattern (do not modify call sites—verification only)
- Document verification result in ENGINEER_REPORT.md

---

## QA Regression Areas

Since this feature does not modify any call sites, there is no user-facing behavior change to validate (same as first-gaps-cycle). QA verification focuses on confirming the isolation boundary held and new props/variant are correctly implemented:

1. **Confirm only 8 files modified:** Review `git diff --stat` output—exactly 4 wrapper files and 4 test files modified, zero other files touched.
2. **Confirm app still builds and runs identically:** Run app on web, navigate through all major screens (auth, home, setlists, gigs, rehearsals, profile, settings), confirm no visual or behavioral changes (wrappers are in use post-retrofit-core, but new props are unused until re-retrofit micro-cycle).
3. **Confirm new props/variant are tested:** Review test additions—each new prop must have at least one test proving it delegates correctly to the underlying Material widget. Destructive button variant must have 2 tests (basic rendering + icon+label).
4. **Confirm no runtime errors introduced:** Run `flutter analyze`, confirm 0 errors.
5. **Confirm backward compatibility:** All existing tests (95 from Piece 1 + first-gaps-cycle) continue passing without modification—new props are optional and don't break existing usage.
6. **Spot-check new props against real call sites:** For each of the 5 identified call sites (my_profile_screen, login_screen x2, invite_screen, settings_screen), manually verify the wrapper API can now express the real usage pattern (read-only, no modifications).

**No regression testing of feature behavior required** — wrappers are already in use post-retrofit-core, but new props are unused until re-retrofit micro-cycle. This QA pass is purely a build/compile/render/API-correctness smoke test (same as first-gaps-cycle).

---

## Rollout / Migration Strategy

Not applicable — this feature introduces no user-facing changes, no database migrations, no backend changes. Rollout is a standard git merge + deploy (no special sequencing required). Same as first-gaps-cycle.

---

## Out of Scope

The following are explicitly deferred to a separate future pipeline cycle (re-retrofit micro-cycle):

1. **Re-retrofitting the 3 boundary-condition files:** This feature only extends wrapper APIs. Rewriting the 3 files with documented boundary conditions (my_profile_screen.dart, login_screen.dart, invite_screen.dart) from raw Material back to App\* wrappers is a separate future micro-cycle, explicitly out of scope here.
2. **Discovery of additional API gaps:** This feature only addresses the 7 gaps documented by retrofit-core's QA_REPORT.md and ENGINEER_REPORT.md. If the re-retrofit micro-cycle discovers additional missing props, those will be handled via the same additive pattern (extend wrapper, add tests, no call-site changes until verified).
3. **Custom styling or behavior changes:** Wrappers remain visually and behaviorally identical to Material defaults (exception: destructive button variant uses `AppColors.error` background, which is an intentional new semantic variant). Any design-system customization beyond this is future work.
4. **Platform-specific wrapper logic:** Wrappers continue working uniformly across all platforms. Any platform-specific divergence is future work (not anticipated).

---

**Architect:** AI Agent  
**Date:** 2026-08-07  
**Worktree:** `/Users/tonyholmes/apps/bandroadie-ui-experiment`  
**Branch:** `experiment/ui-facade` (existing—not creating new branch per Phase 13 override)
