# Architect Plan

## Feature Slug

feature/ui-facade-boundary-retrofit

## Problem Summary

Three screens (login_screen.dart, invite_screen.dart, my_profile_screen.dart) still use raw Material widgets (Scaffold, TextField, TextFormField) at 5 call sites, despite the existence of facade wrappers (AppScaffold, AppTextField, AppTextFormField) that were designed to ensure consistent styling across the app. These screens were forced to use raw widgets during the initial ui-facade-retrofit-core cycle because the wrappers lacked specific props (inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus, resizeToAvoidBottomInset). The two wrapper-gaps cycles (ui-facade-wrapper-gaps and ui-facade-wrapper-gaps-2) closed all API gaps, making the wrappers feature-complete. However, the retrofit to use wrappers at these 5 boundary call sites was explicitly deferred to a future micro-cycle. This is that micro-cycle.

**Why this matters:**

- Violates architectural consistency — these 3 files are the only screens in the codebase using raw Material widgets where wrappers exist
- Increases maintenance burden — styling changes must account for both wrapper and raw widget call paths
- No functionality blockers remain — all props are now supported by wrappers

## Root Cause

**Cause:** Historical API gap deferred resolution.

**Confidence:** HIGH (confirmed by direct code inspection)

During the ui-facade-retrofit-core cycle, 5 specific call sites required props that did not exist in the wrappers at that time:

- login_screen.dart TextField: needed `autocorrect: false`, `autofillHints`, `onSubmitted`
- login_screen.dart Scaffold: needed `resizeToAvoidBottomInset: false`
- invite_screen.dart TextField: needed `onSubmitted`
- my_profile_screen.dart TextFormField: needed `inputFormatters`
- my_profile_screen.dart TextField (dialog): needed `autofocus: true`

The ui-facade-wrapper-gaps-2 Engineer Report (last section) explicitly flagged these 3 files for future retrofit:

> **Next steps (future micro-cycle, explicitly out of scope here):**
> Re-retrofit the 3 boundary-condition files (my_profile_screen.dart, login_screen.dart, invite_screen.dart) from raw Material widgets back to App\* wrappers, now that the wrapper APIs can express all required usage patterns.

All required props are now present in the wrappers. The retrofit is unblocked.

## Reference Docs Consulted

- `docs/features/ui-facade-wrapper-gaps-2/ENGINEER_REPORT.md` — confirmed all API gaps closed, listed these 3 files as deferred retrofit targets

No other domain reference docs were applicable. This is a pure architectural consistency task with no business logic or backend interaction.

## Existing System Analysis

### Current State (Before Retrofit)

**Call Site 1: login_screen.dart line 484**

- Widget: `Scaffold`
- Props: `backgroundColor`, `resizeToAvoidBottomInset: false`, `body`
- Context: Main login screen layout, keyboard-aware with manual AnimatedPadding

**Call Site 2: login_screen.dart line 628**

- Widget: `TextField`
- Props: `controller`, `focusNode`, `enabled`, `keyboardType`, `textInputAction`, `autocorrect: false`, `autofillHints: [AutofillHints.email]`, `style`, `onChanged`, `onSubmitted`, custom `decoration` with validation-dependent border colors
- Context: Email input field wrapped in `AutofillGroup` for password manager integration
- Special behavior: Custom InputDecoration changes border color based on `_validationError != null`

**Call Site 3: invite_screen.dart line 463**

- Widget: `TextField`
- Props: `controller`, `keyboardType`, `style`, custom `decoration` with error text, `onSubmitted`
- Context: Email input for accepting band invitation

**Call Site 4: my_profile_screen.dart line 458 (inside \_showAddRoleDialog)**

- Widget: `TextField`
- Props: `controller`, `autofocus: true`, `style`, custom `decoration`, `textInputAction`, `onSubmitted`
- Context: Custom role name input in an AppDialog for adding user-defined roles

**Call Site 5: my_profile_screen.dart line 1047 (inside \_buildTextField helper)**

- Widget: `TextFormField`
- Props: `controller`, `keyboardType`, `inputFormatters`, `style`, `onChanged`, `validator`, custom `decoration` with per-validation-state border colors
- Context: Reusable helper returning a Column with label + TextFormField, used 5x (First Name, Last Name, Phone, Address, Zip)
- Special behavior: Custom InputDecoration with errorBorder and focusedErrorBorder styling

### Data Flow

None. This is a pure UI widget substitution with zero state, repository, or backend interaction changes.

## Proposed Solution

Replace all 5 raw Material widget call sites with their App\* wrapper equivalents, preserving all existing props, styling, and behavior.

**Changes:**

1. **login_screen.dart:**
   - Line 484: Replace `Scaffold(...)` with `AppScaffold(...)`
   - Line 628: Replace `TextField(...)` with `AppTextField(...)` (keep AutofillGroup wrapper)
   - Add import: `package:bandroadie/components/ui/app_text_field.dart`

2. **invite_screen.dart:**
   - Line 463: Replace `TextField(...)` with `AppTextField(...)`
   - Add import: `package:bandroadie/components/ui/app_text_field.dart`

3. **my_profile_screen.dart:**
   - Line 458: Replace `TextField(...)` with `AppTextField(...)`
   - Line 1047: Replace `TextFormField(...)` with `AppTextFormField(...)`
   - Add imports: `package:bandroadie/components/ui/app_text_field.dart`, `package:bandroadie/components/ui/app_text_form_field.dart`

**Why this is safe:**

- All wrappers are thin delegates to the underlying Material widgets with identical prop signatures
- Wrappers pass through all props directly to the Material widget
- Custom `decoration` overrides are explicitly supported via the wrappers' `decoration` parameter
- No theme changes, no state changes, no controller changes
- AutofillGroup wrapping is preserved (it wraps the widget, not nested inside it)

## Database Impact

Not applicable. This feature touches only client-side UI widget calls with no state, repository, or backend interaction changes.

## Flutter Architecture Changes

**State:** No changes. All controllers, focus nodes, and validation logic remain unchanged.

**Widgets:** 5 call sites switch from raw Material widgets to App\* wrappers. Widget tree structure is preserved (e.g., AutofillGroup still wraps the email TextField, Column structure in \_buildTextField helper is unchanged).

**Repositories:** No changes.

**Controllers:** No changes.

**Providers:** No changes.

## Files to Create

None.

## Files to Modify

| File                                          | What changes                                                                                                                                                          |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart`         | Add import for AppTextField. Replace raw Scaffold at line 484 with AppScaffold. Replace raw TextField at line 628 with AppTextField (keep AutofillGroup wrapper).     |
| `lib/features/auth/invite_screen.dart`        | Add import for AppTextField. Replace raw TextField at line 463 with AppTextField.                                                                                     |
| `lib/features/profile/my_profile_screen.dart` | Add imports for AppTextField and AppTextFormField. Replace raw TextField at line 458 with AppTextField. Replace raw TextFormField at line 1047 with AppTextFormField. |

## Files Off-Limits

| File                                         | Reason                                                                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_text_field.dart`      | Wrapper is feature-complete. No new props required. If modifications are discovered to be necessary, this represents scope creep and must be escalated. |
| `lib/components/ui/app_text_form_field.dart` | Wrapper is feature-complete. No new props required. If modifications are discovered to be necessary, this represents scope creep and must be escalated. |
| `lib/components/ui/app_scaffold.dart`        | Wrapper is feature-complete. No new props required. If modifications are discovered to be necessary, this represents scope creep and must be escalated. |
| `lib/main.dart`                              | Init order must not change.                                                                                                                             |
| `lib/app/theme/*.dart`                       | No theme changes.                                                                                                                                       |
| All other feature files                      | Only the 3 explicitly identified files touch Material widget call sites.                                                                                |

## System Impact Map

| System                                 | Impact                                                                           |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                       |
| Rehearsals                             | unaffected                                                                       |
| Setlists / Catalog                     | unaffected                                                                       |
| Members / RBAC                         | unaffected                                                                       |
| Auth / Session                         | unaffected (login screen UI only, no auth flow changes)                          |
| Routing                                | unaffected                                                                       |
| Notifications                          | unaffected                                                                       |
| Platform (iOS / Android / Web / macOS) | unaffected (visual output and behavior must be pixel-identical before and after) |

## Regression Risk

**Level:** LOW

**Rationale:**

- Zero systems in the impact map are affected (all marked "unaffected")
- No auth, session, routing, or init order changes
- No database mutations
- No state management changes
- No controller, repository, or provider changes
- All changes are isolated to UI widget substitution with identical prop pass-through
- Wrappers are thin delegates with identical signatures to Material widgets
- All wrapper props are already covered by existing widget tests from wrapper-gaps cycles

**Potential risks (mitigated):**

- AutofillGroup interaction with AppTextField: Mitigated by preserving wrapper structure (AutofillGroup wraps AppTextField, not nested inside it). AutofillGroup works with any TextField descendant.
- Custom InputDecoration per-validation-state styling: Mitigated by wrappers' `decoration` parameter allowing arbitrary InputDecoration override, including conditional border colors.
- TextInputFormatter behavior (PhoneNumberInputFormatter in my_profile_screen.dart): Mitigated by AppTextFormField passing `inputFormatters` prop directly to TextFormField.

## Engineer Task Breakdown

Execute in strict order:

**Task 1 — Retrofit login_screen.dart Scaffold**

- Add import for `package:bandroadie/components/ui/app_text_field.dart` (if not already present from existing AppScaffold import)
- Replace raw `Scaffold` at line 484 with `AppScaffold`, preserving all props: `backgroundColor`, `resizeToAvoidBottomInset: false`, `body`

**Task 2 — Retrofit login_screen.dart TextField**

- Replace raw `TextField` at line 628 with `AppTextField`, preserving all props: `controller`, `focusNode`, `enabled`, `keyboardType`, `textInputAction`, `autocorrect`, `autofillHints`, `style`, `onChanged`, `onSubmitted`, `decoration`
- Verify AutofillGroup wrapper is preserved exactly as-is (AutofillGroup wraps AppTextField)

**Task 3 — Retrofit invite_screen.dart TextField**

- Add import for `package:bandroadie/components/ui/app_text_field.dart`
- Replace raw `TextField` at line 463 with `AppTextField`, preserving all props: `controller`, `keyboardType`, `style`, `decoration`, `onSubmitted`

**Task 4 — Retrofit my_profile_screen.dart dialog TextField**

- Add import for `package:bandroadie/components/ui/app_text_field.dart`
- Replace raw `TextField` at line 458 (inside \_showAddRoleDialog) with `AppTextField`, preserving all props: `controller`, `autofocus`, `style`, `decoration`, `textInputAction`, `onSubmitted`

**Task 5 — Retrofit my_profile_screen.dart \_buildTextField helper**

- Add import for `package:bandroadie/components/ui/app_text_form_field.dart`
- Replace raw `TextFormField` at line 1047 (inside \_buildTextField helper) with `AppTextFormField`, preserving all props: `controller`, `keyboardType`, `inputFormatters`, `style`, `onChanged`, `validator`, `decoration`

**Task 6 — Run flutter analyze**

- Execute: `flutter analyze`
- Expect: 0 errors, 0 warnings
- If any errors or warnings: diagnose and resolve before proceeding

**Task 7 — Run flutter build web --release**

- Execute: `flutter build web --release`
- Expect: build succeeds with no new errors
- Ignore pre-existing WASM warnings from image/gotrue third-party packages (documented in wrapper-gaps-2 report)

**Task 8 — Generate git diff**

- Execute: `git diff --stat`
- Verify exactly 3 files modified (login_screen.dart, invite_screen.dart, my_profile_screen.dart)
- Execute: `git diff`
- Verify only widget substitutions and import additions, no other changes

**Task 9 — Manual visual verification (optional but recommended)**

- Run `flutter run -d macos` (or chrome)
- Navigate to login screen: verify email field autofill behavior, validation border colors, keyboard handling
- Navigate to invite screen: verify email field styling and onSubmitted behavior
- Navigate to profile screen: verify form fields (First Name, Last Name, Phone, Address, Zip) and custom role dialog
- Confirm pixel-identical appearance before and after

**Task 10 — Write ENGINEER_REPORT.md**

- Document all tasks completed
- Include analyzer output, build output, git diff output
- State deviations (expect none) or blockers (expect none)
- Mark ready for QA

## Verification Plan

This feature involves no database, RPC, or migration changes. All verification is client-side.

**Tier 1 — Pre-deployment (not applicable)**

- No backend changes. Skip.

**Tier 2 — Post-implementation (client-side validation)**

**Test 1 — Static analysis**

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings

**Test 2 — Build verification**

```bash
flutter build web --release
```

Expected: Build succeeds with no new errors. Pre-existing WASM warnings from image/gotrue packages are acceptable.

**Test 3 — Diff boundary verification**

```bash
git diff --stat
```

Expected: Exactly 3 files modified:

- lib/features/auth/login_screen.dart
- lib/features/auth/invite_screen.dart
- lib/features/profile/my_profile_screen.dart

**Test 4 — Diff content verification**

```bash
git diff
```

Expected:

- Import additions for AppTextField and/or AppTextFormField
- Widget name substitutions (Scaffold → AppScaffold, TextField → AppTextField, TextFormField → AppTextFormField)
- Prop lists unchanged (all props passed identically)
- No theme changes, no controller changes, no state changes

**Test 5 — AutofillGroup structure verification (manual code inspection)**

- Open lib/features/auth/login_screen.dart
- Verify AutofillGroup still wraps AppTextField (not nested inside it)
- Confirm structure: `AutofillGroup(child: AppTextField(...))`

**Test 6 — Custom decoration preservation verification (manual code inspection)**

- Open lib/features/auth/login_screen.dart line ~628
- Verify `decoration` parameter contains full InputDecoration with enabledBorder, focusedBorder, and validation-dependent styling
- Open lib/features/profile/my_profile_screen.dart line ~1047
- Verify `decoration` parameter contains full InputDecoration with errorBorder and focusedErrorBorder styling

## QA Regression Areas

QA must specifically test:

**Critical paths:**

1. **Login screen (lib/features/auth/login_screen.dart):**
   - Email field autofill behavior (password managers should detect the email field)
   - Email field validation: trigger validation error (e.g., invalid email), verify red border appears
   - Email field focus behavior: tap field, verify primary-colored border on focus
   - Email field onSubmitted: type email, press Enter, verify magic link flow triggers
   - Keyboard handling: open keyboard, verify content lifts smoothly (AnimatedPadding behavior)
   - AutofillGroup integration: verify no regression in password manager detection

2. **Invite screen (lib/features/auth/invite_screen.dart):**
   - Email field styling: verify consistent appearance with login screen
   - Email field onSubmitted: type email, press Enter, verify magic link flow triggers
   - Email field error display: trigger error (e.g., invalid email), verify error text displays

3. **Profile screen (lib/features/profile/my_profile_screen.dart):**
   - Form fields (First Name, Last Name, Phone, Address, Zip): verify all 5 fields render correctly
   - Phone field formatting: type phone number, verify PhoneNumberInputFormatter applies formatting
   - Form validation: leave required field empty, verify error message displays
   - Form error styling: trigger validation error, verify red border appears on error fields
   - Custom role dialog: tap "Add Role", verify dialog opens, type custom role name, verify autofocus on text field, press Enter, verify role added

**Visual verification:**

- All text fields must be pixel-identical to the previous implementation (same colors, borders, padding, typography)
- No layout shifts, no spacing changes, no font changes

**Behavioral verification:**

- Keyboard interactions unchanged (onSubmitted callbacks fire correctly)
- Validation behavior unchanged (errors display at the correct time)
- Autofill behavior unchanged (password managers detect fields)

**Platform-specific verification:**

- Web: verify keyboard Enter key triggers onSubmitted
- iOS: verify email keyboard appears, verify autofill suggestions
- Android: verify email keyboard appears, verify autofill suggestions
- macOS: verify keyboard Enter key triggers onSubmitted

## Rollout / Migration Strategy

Not applicable. This is a client-side UI refactor with no backend changes, no database changes, and no user-visible behavior changes. Deploy via standard web deployment after QA approval.

## Out of Scope

Explicitly excluded:

1. **Any wrapper file modifications** — All wrappers are feature-complete. If modifications are discovered to be necessary during implementation, escalate immediately. Do not proceed with wrapper changes.

2. **Any new wrapper props** — All required props already exist. If new props are discovered to be needed, this represents a scope-changing discovery and must be escalated.

3. **Any behavior changes** — Visual output and app behavior must be pixel-identical before and after. Any behavior change is a regression, not a feature.

4. **Any other screens** — Only the 3 explicitly identified files (login_screen.dart, invite_screen.dart, my_profile_screen.dart) are in scope. Do not retrofit other screens even if they use raw Material widgets.

5. **Any test additions or modifications** — Existing wrapper tests from wrapper-gaps cycles already cover all wrapper functionality. No new tests are required.

6. **Any theme changes** — Wrappers respect existing theme configuration. No theme file modifications are allowed.

7. **Opportunistic cleanup** — No refactoring, no formatting, no comment updates, no variable renames, no other changes to the 3 target files beyond the explicit widget substitutions.
