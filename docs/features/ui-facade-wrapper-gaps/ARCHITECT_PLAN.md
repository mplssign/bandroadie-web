# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-wrapper-gaps`

---

## Problem Summary

Piece 1 of the UI facade layer (shipped 2026-08-06, commit 6a76eae on `experiment/ui-facade`) created 15 wrapper widgets backed by Material components. QA's read-only spot-check against real call sites identified specific missing props on 3 of the 15 wrappers: `AppTextField`/`AppTextFormField`, `showAppBottomSheet`, and `showAppDialog`. These gaps will block Piece 2's mechanical retrofit process (replacing ~100+ Material call sites with wrapper equivalents) because the prop surfaces are insufficient to support prop-for-prop replacement at identified call sites.

**Why this must be fixed now:** Piece 2's entire premise is that call-site swaps are mechanical transformations (e.g., `TextField(...)` → `AppTextField(...)`), not exploratory refactors. If wrapper props are missing, each retrofit becomes a research task ("how do I express this with the limited API?"), violating the minimal-change principle and introducing risk. Closing these gaps before Piece 2 starts preserves the zero-exploration, high-confidence retrofit model.

**Scope:** Additive-only changes to 3 existing wrapper files. No new files. No production call sites touched (Piece 2 still hasn't started). Same zero-blast-radius shape as Piece 1.

---

## Current State

**AppTextField / AppTextFormField** (lib/components/ui/app_text_field.dart, app_text_form_field.dart)

Current props: `controller`, `hintText`, `labelText`, `prefixIcon`, `suffixIcon`, `obscureText`, `maxLines`, `keyboardType`, `onChanged`, `enabled` (TextFormField adds `validator`, `onSaved`)

Real usage at [lib/features/events/widgets/gig_form_fields.dart:219](lib/features/events/widgets/gig_form_fields.dart#L219) requires:

- `focusNode: FocusNode` — for managing focus between sequential fields (e.g., tab through address, city, state)
- `textCapitalization: TextCapitalization` — for auto-capitalizing input (e.g., `.words` for address fields)
- `textInputAction: TextInputAction` — for keyboard action buttons (e.g., `.next` to advance to next field)
- `style: TextStyle` — for custom text style overrides beyond theme defaults
- Full `decoration: InputDecoration` — current implementation only exposes 4 decoration props (hintText, labelText, prefixIcon, suffixIcon). Real usage requires `filled`, `fillColor`, `contentPadding`, `border`, `hintStyle`, and other InputDecoration properties.

**Confidence:** HIGH — directly observed in code, exact line numbers provided by QA report.

**showAppBottomSheet** (lib/components/ui/app_bottom_sheet.dart)

Current props: `builder`, `isDismissible`, `useRootNavigator`

Real usage at [lib/features/bands/band_form_screen.dart:542](lib/features/bands/band_form_screen.dart#L542) requires:

- `backgroundColor: Color` — for custom sheet background (e.g., `context.colors.surface`)
- `shape: ShapeBorder` — for custom border radius via `RoundedRectangleBorder`
- `isScrollControlled: bool` — for full-height bottom sheets that respond to content size

**Confidence:** HIGH — directly observed in code, exact line number provided by QA report.

**showAppDialog** (lib/components/ui/app_dialog.dart)

Current implementation: Standard AlertDialog pattern only (title/message/actions)

Real usage at [lib/features/setlists/setlist_detail_screen.dart:1389](lib/features/setlists/setlist_detail_screen.dart#L1389) requires:

- Custom builder pattern — wraps `Card` with `CircularProgressIndicator`, not an AlertDialog at all
- Uses `PopScope(canPop: false)` to prevent dismissal during async operations
- Current `showAppDialog` API cannot express this pattern (requires title/message/actions, all strings)

**Confidence:** HIGH — directly observed in code, exact line number provided by QA report.

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture

**No relevant design-system guidance exists in reference docs.** Proceeded with codebase inspection per ARCHITECT.md fallback protocol for missing/irrelevant reference directories.

---

## Existing System Analysis

**Piece 1 wrapper pattern (established precedent):**

- Plain StatelessWidget/StatefulWidget (no Riverpod)
- Semantic named props (label, onPressed, value) delegate directly to underlying Material widget
- Design tokens respected by delegating to theme configuration (no custom styling in Piece 1)
- Material widgets used internally but hidden from call sites
- No platform-conditional logic (uniform behavior across Web, iOS, Android, macOS)

**Current wrapper implementations:**

1. **AppTextField / AppTextFormField** — Construct InputDecoration inline from individual props (hintText, labelText, prefixIcon, suffixIcon). This is insufficient for real usage requiring full decoration control (borders, padding, fill color, etc.).

2. **showAppBottomSheet** — Directly wraps `showModalBottomSheet` but only exposes 3 of ~12 available parameters. Missing props prevent expressing custom styling (background color, shape, scroll control).

3. **showAppDialog / AppAlertDialog** — Only supports AlertDialog pattern (title/message/actions). Real usage sometimes requires custom builders for non-AlertDialog patterns (e.g., loading indicators wrapped in Card, custom layouts with no standard title/message structure).

**Data flow:** No data flow changes — wrappers are still unused until Piece 2. This work only extends the API surface of existing wrapper files.

---

## Proposed Solution

Extend the 3 affected wrapper files with missing props, following the precedent pattern established in Piece 1. All additions are optional (nullable with sensible defaults), maintaining backward compatibility with Piece 1's API. No new files created. No production call sites modified.

### Solution 1: AppTextField / AppTextFormField — Add Missing Props + Full Decoration Support

**Add 4 new direct props:**

- `focusNode: FocusNode?` — passed directly to TextField/TextFormField
- `textCapitalization: TextCapitalization` — default `TextCapitalization.none`
- `textInputAction: TextInputAction?` — passed directly to TextField/TextFormField
- `style: TextStyle?` — passed directly to TextField/TextFormField

**Add full decoration support via `decoration` prop:**

- `decoration: InputDecoration?` — when provided, use it directly instead of constructing from individual props
- When `decoration` is null (default), fall back to current behavior (construct InputDecoration from hintText, labelText, prefixIcon, suffixIcon)
- This preserves backward compatibility with existing Piece 1 tests while enabling full decoration customization for Piece 2 retrofits

**Why this design:**

- Minimal API change — 5 new props, all optional
- Backward compatible — existing tests continue passing (they don't provide `decoration`, so they use the simplified props)
- Forward compatible — Piece 2 retrofits can use either the simplified props (for simple cases) or the full `decoration` object (for complex cases like gig_form_fields.dart)
- Consistent with Material API — TextField/TextFormField accept both a `decoration` prop and have defaults when not provided

**Implementation detail:** When `decoration` is provided, ignore `hintText`, `labelText`, `prefixIcon`, `suffixIcon` (explicit wins over implicit). Document this in prop comments.

### Solution 2: showAppBottomSheet — Add Missing Props

**Add 3 new props:**

- `backgroundColor: Color?` — passed directly to showModalBottomSheet
- `shape: ShapeBorder?` — passed directly to showModalBottomSheet
- `isScrollControlled: bool` — default `false`, passed directly to showModalBottomSheet

**Why this design:**

- Minimal API change — 3 new props, all optional
- Direct passthrough to Material API — no custom logic, just delegation
- Maintains theme defaults when props are null

### Solution 3: showAppDialog — Add Custom Builder Support

**Add 1 new optional prop:**

- `builder: WidgetBuilder?` — when provided, use this custom builder instead of constructing AppAlertDialog

**Modified function signature:**

```dart
Future<T?> showAppDialog<T>({
  required BuildContext context,
  String? title,              // now optional (only required for AlertDialog pattern)
  String? message,            // now optional (only required for AlertDialog pattern)
  List<DialogAction>? actions, // now optional (only required for AlertDialog pattern)
  bool barrierDismissible = true,
  WidgetBuilder? builder,     // NEW: custom builder
})
```

**Behavior:**

- When `builder` is provided: use it directly, ignore title/message/actions
- When `builder` is null: construct AppAlertDialog from title/message/actions (current behavior)
- When `builder` is null but title/message/actions are also null: throw ArgumentError with helpful message

**Why this design:**

- Minimal API change — 1 new prop, makes 3 existing props optional
- Supports both patterns: standard AlertDialog (via title/message/actions) and custom builders (via builder)
- Backward compatible — existing calls providing title/message/actions continue working identically
- Forward compatible — Piece 2 can use `builder` for custom dialog patterns like the loading indicator in setlist_detail_screen.dart

**Alternative considered and rejected:** Create a separate `showAppCustomDialog` function. Rejected because it fragments the dialog API (two functions for the same underlying `showDialog` call) and requires Piece 2 to decide which function to use. Single function with optional builder is simpler and more discoverable.

---

## Database Impact

**Database:** not applicable — this feature touches zero backend/Supabase surface. All changes are Flutter UI layer only.

---

## Flutter Architecture Changes

**State Management:** None. Wrappers remain plain StatelessWidget with no Riverpod dependencies.

**Widget Tree:** No new widgets created. Modifications only to 3 existing wrapper files (AppTextField, AppTextFormField, showAppBottomSheet, showAppDialog).

**Repositories:** None.

**Controllers/Notifiers:** None.

---

## Files to Create

**None.** This feature only modifies existing wrapper files from Piece 1.

---

## Files to Modify

| File                                               | What changes                                                                                                                                                                                                         |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_text_field.dart`            | Add 5 new optional props: `focusNode`, `textCapitalization`, `textInputAction`, `style`, `decoration`. When `decoration` is provided, use it directly; otherwise construct from simplified props (current behavior). |
| `lib/components/ui/app_text_form_field.dart`       | Add same 5 new optional props as AppTextField (inheritance of TextField props).                                                                                                                                      |
| `lib/components/ui/app_bottom_sheet.dart`          | Add 3 new optional props to `showAppBottomSheet` function: `backgroundColor`, `shape`, `isScrollControlled`.                                                                                                         |
| `lib/components/ui/app_dialog.dart`                | Add 1 new optional prop `builder` to `showAppDialog` function. Make `title`, `message`, `actions` optional. Use `builder` when provided, otherwise use AlertDialog pattern.                                          |
| `test/components/ui/app_text_field_test.dart`      | Add tests for new props: focusNode delegation, textCapitalization, textInputAction, style, full decoration override.                                                                                                 |
| `test/components/ui/app_text_form_field_test.dart` | Add tests for new props (same as AppTextField).                                                                                                                                                                      |
| `test/components/ui/app_bottom_sheet_test.dart`    | Add tests for new props: backgroundColor, shape, isScrollControlled.                                                                                                                                                 |
| `test/components/ui/app_dialog_test.dart`          | Add tests for custom builder pattern, verify title/message/actions are optional when builder is provided.                                                                                                            |

---

## Files Off-Limits

| File                                                                               | Reason                                                                                                            |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                    | Init order must not change                                                                                        |
| `lib/app/theme/*.dart`                                                             | Theme configuration is stable—wrappers delegate to it, never override it                                          |
| All files in `lib/features/`                                                       | No call site modifications until Piece 2 (separate future pipeline cycle)                                         |
| All files in `lib/shared/`                                                         | No call site modifications until Piece 2                                                                          |
| All other wrapper files in `lib/components/ui/`                                    | Only the 3 identified wrappers (text field, bottom sheet, dialog) have gaps. Do not modify the other 12 wrappers. |
| Existing precedent components (`lib/components/ui/brand_action_button.dart`, etc.) | Already stable, do not modify                                                                                     |

---

## System Impact Map

| System                                 | Impact                                                                                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Gigs                                   | unaffected (no call sites changed)                                                                                                                                       |
| Rehearsals                             | unaffected                                                                                                                                                               |
| Setlists / Catalog                     | unaffected                                                                                                                                                               |
| Members / RBAC                         | unaffected                                                                                                                                                               |
| Auth / Session                         | unaffected                                                                                                                                                               |
| Routing                                | unaffected                                                                                                                                                               |
| Notifications                          | unaffected                                                                                                                                                               |
| Platform (iOS / Android / Web / macOS) | affected (new props must render correctly across all 4 platforms—but all new props are direct passthroughs to Material APIs, so platform equivalence is high confidence) |

---

## Regression Risk

**Risk Level:** LOW

**Rationale:**

- **Additive-only changes** — all new props are optional, all existing Piece 1 tests continue passing with zero modifications
- **Zero modifications to production call sites** — wrappers are still unused until Piece 2 (separate pipeline cycle)
- **No new files** — only extending 3 existing wrapper files
- **No backend/database surface touched** — pure Flutter UI layer change
- **No init order, routing, or auth flow changes** — `lib/main.dart` untouched
- **Platform impact limited to rendering** — all new props are direct passthroughs to Material widget APIs (focusNode, textCapitalization, textInputAction, style, decoration, backgroundColor, shape, isScrollControlled, builder). Material already handles cross-platform equivalence for these props, so wrappers inherit that stability.
- **Backward compatibility guaranteed** — all new props are optional with sensible defaults. Existing tests from Piece 1 continue passing without modification.

**Primary risk:** Insufficient testing of new props — if a new prop is not tested, Piece 2 might discover it doesn't work as expected during retrofits. Mitigated by requiring comprehensive test coverage for each new prop in the Verification Plan.

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Extend AppTextField with missing props

- **File:** `lib/components/ui/app_text_field.dart`
- **Add 5 new props:**
  - `focusNode: FocusNode?`
  - `textCapitalization: TextCapitalization` (default `TextCapitalization.none`)
  - `textInputAction: TextInputAction?`
  - `style: TextStyle?`
  - `decoration: InputDecoration?`
- **Implementation:**
  - When `decoration` is provided, pass it directly to TextField, ignore simplified props
  - When `decoration` is null, construct InputDecoration from `hintText`, `labelText`, `prefixIcon`, `suffixIcon` (current behavior)
  - Pass all new props directly to TextField
- **Doc comments:** Document that `decoration` overrides simplified props when provided
- **Verification:** Widget compiles, passes existing tests (no modifications to tests yet)

### Task 2: Extend AppTextFormField with missing props

- **File:** `lib/components/ui/app_text_form_field.dart`
- **Add same 5 new props as AppTextField**
- **Implementation:** Identical logic to Task 1, but delegate to TextFormField instead of TextField
- **Verification:** Widget compiles, passes existing tests

### Task 3: Extend showAppBottomSheet with missing props

- **File:** `lib/components/ui/app_bottom_sheet.dart`
- **Add 3 new props to function signature:**
  - `backgroundColor: Color?`
  - `shape: ShapeBorder?`
  - `isScrollControlled: bool` (default `false`)
- **Implementation:** Pass all 3 new props directly to showModalBottomSheet
- **Verification:** Function compiles, passes existing tests

### Task 4: Extend showAppDialog with custom builder support

- **File:** `lib/components/ui/app_dialog.dart`
- **Modify function signature:**
  - Make `title`, `message`, `actions` optional (String? / List<DialogAction>?)
  - Add `builder: WidgetBuilder?`
- **Implementation:**
  - When `builder` is provided: call `showDialog(context: context, barrierDismissible: barrierDismissible, builder: builder)`
  - When `builder` is null and title/message/actions are all non-null: construct AppAlertDialog (current behavior)
  - When `builder` is null and any of title/message/actions are null: throw ArgumentError with message "Either provide builder or provide title/message/actions"
- **Verification:** Function compiles, passes existing tests (they provide title/message/actions, so they use AlertDialog path)

### Task 5: Add tests for AppTextField new props

- **File:** `test/components/ui/app_text_field_test.dart`
- **Add 6 new tests:**
  1. `focusNode` is delegated to TextField
  2. `textCapitalization` is delegated to TextField
  3. `textInputAction` is delegated to TextField
  4. `style` is delegated to TextField
  5. Full `decoration` object is delegated when provided
  6. Simplified props (hintText, labelText, prefixIcon, suffixIcon) are ignored when `decoration` is provided
- **Verification:** All new tests pass

### Task 6: Add tests for AppTextFormField new props

- **File:** `test/components/ui/app_text_form_field_test.dart`
- **Add same 6 new tests as Task 5** (verify delegation to TextFormField instead of TextField)
- **Verification:** All new tests pass

### Task 7: Add tests for showAppBottomSheet new props

- **File:** `test/components/ui/app_bottom_sheet_test.dart`
- **Add 3 new tests:**
  1. `backgroundColor` is passed to showModalBottomSheet
  2. `shape` is passed to showModalBottomSheet
  3. `isScrollControlled` is passed to showModalBottomSheet
- **Verification:** All new tests pass

### Task 8: Add tests for showAppDialog custom builder

- **File:** `test/components/ui/app_dialog_test.dart`
- **Add 3 new tests:**
  1. Custom `builder` is used when provided (verify dialog contains custom widget, not AppAlertDialog)
  2. AlertDialog pattern still works when builder is null and title/message/actions are provided (existing test, ensure it still passes)
  3. ArgumentError is thrown when builder is null and title/message/actions are incomplete
- **Verification:** All new tests pass

### Task 9: Run all widget tests

- **Command:** `flutter test test/components/ui/`
- **Expected output:** All tests pass (Piece 1's 77 tests + new tests from Tasks 5-8)
- **If failures:** Fix them before proceeding

### Task 10: Verify zero files modified outside target files

- **Command:** `git diff --stat`
- **Expected output:** Only 8 files modified:
  - `lib/components/ui/app_text_field.dart`
  - `lib/components/ui/app_text_form_field.dart`
  - `lib/components/ui/app_bottom_sheet.dart`
  - `lib/components/ui/app_dialog.dart`
  - `test/components/ui/app_text_field_test.dart`
  - `test/components/ui/app_text_form_field_test.dart`
  - `test/components/ui/app_bottom_sheet_test.dart`
  - `test/components/ui/app_dialog_test.dart`
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

- **Read-only verification:** Manually inspect the 3 identified call sites (gig_form_fields.dart:219, band_form_screen.dart:542, setlist_detail_screen.dart:1389) and confirm each new prop can now express the real usage pattern
- **Do not modify call sites** — this is verification only, Piece 2 will perform the actual retrofits
- **Document in ENGINEER_REPORT.md:** Confirm that AppTextField now supports all props used in gig_form_fields.dart, showAppBottomSheet now supports all props used in band_form_screen.dart, and showAppDialog now supports custom builder pattern used in setlist_detail_screen.dart

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

- Piece 1's 77 original tests (unchanged, must still pass)
- New tests for AppTextField (6 tests covering focusNode, textCapitalization, textInputAction, style, decoration, decoration override behavior)
- New tests for AppTextFormField (6 tests, same coverage as AppTextField)
- New tests for showAppBottomSheet (3 tests covering backgroundColor, shape, isScrollControlled)
- New tests for showAppDialog (3 tests covering custom builder, AlertDialog pattern backward compatibility, ArgumentError on invalid args)

Minimum total test count: 77 + 6 + 6 + 3 + 3 = 95 tests.

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

- 4 wrapper files (app_text_field.dart, app_text_form_field.dart, app_bottom_sheet.dart, app_dialog.dart)
- 4 test files (corresponding \*\_test.dart files)

Zero other files touched. This is the primary regression guard—confirms no production call sites were changed, no unrelated wrappers were modified.

### Test 5: App still runs completely unchanged

- Run app on web: `flutter run -d chrome`
- **Expected behavior:** App launches, all screens render identically to before, no runtime errors. This confirms new props don't interfere with existing code (wrappers are still unused until Piece 2).

### Test 6: Spot-check new props against real call sites (read-only)

- Manually inspect identified call sites:
  1. [lib/features/events/widgets/gig_form_fields.dart:219](lib/features/events/widgets/gig_form_fields.dart#L219) — verify AppTextField now has all required props (focusNode, textCapitalization, textInputAction, style, full decoration)
  2. [lib/features/bands/band_form_screen.dart:542](lib/features/bands/band_form_screen.dart#L542) — verify showAppBottomSheet now has all required props (backgroundColor, shape, isScrollControlled)
  3. [lib/features/setlists/setlist_detail_screen.dart:1389](lib/features/setlists/setlist_detail_screen.dart#L1389) — verify showAppDialog can now express custom builder pattern
- Confirm each new prop can express the real usage pattern (do not modify call sites—verification only)
- Document verification result in ENGINEER_REPORT.md

---

## QA Regression Areas

Since this feature does not modify any call sites, there is no user-facing behavior change to validate. QA verification focuses on confirming the isolation boundary held and new props are correctly implemented:

1. **Confirm only 8 files modified:** Review `git diff --stat` output—exactly 4 wrapper files and 4 test files modified, zero other files touched.
2. **Confirm app still builds and runs identically:** Run app on web, navigate through all major screens (auth, home, setlists, gigs, rehearsals, profile, settings), confirm no visual or behavioral changes.
3. **Confirm new props are tested:** Review test additions—each new prop must have at least one test proving it delegates correctly to the underlying Material widget.
4. **Confirm no runtime errors introduced:** Run `flutter analyze`, confirm 0 errors.
5. **Confirm backward compatibility:** All Piece 1 tests continue passing without modification—new props are optional and don't break existing usage.
6. **Spot-check new props against real call sites:** For each of the 3 identified call sites (gig_form_fields.dart:219, band_form_screen.dart:542, setlist_detail_screen.dart:1389), manually verify the wrapper API can now express the real usage pattern (read-only, no modifications).

**No regression testing of feature behavior required** — wrappers are still unused until Piece 2. This QA pass is purely a build/compile/render/API-correctness smoke test.

---

## Rollout / Migration Strategy

Not applicable — this feature introduces no user-facing changes, no database migrations, no backend changes. Rollout is a standard git merge + deploy (no special sequencing required).

---

## Out of Scope

The following are explicitly deferred to Piece 2 (separate future pipeline cycle):

1. **Retrofitting existing call sites** — This feature only extends wrapper APIs. Rewriting the 3+ identified call sites (and ~100+ other Material call sites) to use the extended wrappers is Piece 2 work.
2. **Discovery of additional API gaps** — This feature only addresses the 3 gaps documented by Piece 1's QA report. If Piece 2 discovers additional missing props during retrofits, those will be handled via the same additive pattern (extend wrapper, add tests, no call-site changes until verified).
3. **Custom styling or behavior changes** — Wrappers remain visually and behaviorally identical to Material defaults. Any design-system customization is future work after Piece 2 completes.
4. **Platform-specific wrapper logic** — Wrappers continue working uniformly across all platforms. Any platform-specific divergence is future work (not anticipated).

---

**Architect:** AI Agent  
**Date:** 2026-08-06  
**Worktree:** `/Users/tonyholmes/apps/bandroadie-ui-experiment`  
**Branch:** `experiment/ui-facade` (existing—not creating new branch per override)
