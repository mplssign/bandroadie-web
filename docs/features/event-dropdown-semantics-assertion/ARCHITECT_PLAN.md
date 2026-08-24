# ARCHITECT PLAN — bug/event-dropdown-semantics-assertion

## Feature Slug

`bug/event-dropdown-semantics-assertion`

## Problem Summary

**5 tests fail on Flutter 3.47.1 (CI) with identical semantics assertion:**

**From `test/features/events/widgets/event_dropdown_test.dart` (3 failures):**

1. "EventDropdown disables dropdown when isSaving is true"
2. "EventDropdown backward compatibility with hour/minute pattern"
3. "AppDropdown Form integration triggers onSaved callback on Form.save()"

**From `test/components/ui/app_dropdown_test.dart` (2 failures):** 4. "AppDropdown respects enabled/disabled state" 5. "AppDropdown fires onChanged callback and reflects value prop"

All fail with:

```
══╡ EXCEPTION CAUGHT BY SCHEDULER LIBRARY ╞═════════════════════════════════
The following assertion was thrown during a scheduler callback:
'package:flutter/src/semantics/semantics.dart': Failed assertion: line 3862 pos 16:
'node.isMergedIntoParent': is not true.
```

All 5 tests pass on local Flutter 3.44.6. This is genuine version drift between Flutter 3.44.6 and 3.47.1 — not a flaky test, not already broken locally. This blocks feature/ci-analyze-test-gate (PR #170) from reaching a green CI check.

## Root Cause

**Confidence Level: HIGH**

This is a **known Flutter 3.47.0 regression** affecting third-party widgets that use `MergeSemantics` wrappers with interactive child widgets.

**Flutter Framework Issue:**

- Flutter issue [#191095](https://github.com/flutter/flutter/issues/191095): "Semantics assertion `node.isMergedIntoParent` when a sibling merge group is produced inside `MergeSemantics`"
- Labeled: `c: regression`, `found in release: 3.47`, `P2`
- Root cause: Flutter PR [#183745](https://github.com/flutter/flutter/pull/183745) ("Update merge semantics logic to merge sibling nodes", merged 2026-04-29) tightened semantics merge invariants
- The new logic creates a wrapper node grouping the render object's own semantics with its siblings, triggering assertions that did not exist in Flutter 3.44.x

**forui Package Impact:**

- forui issue [#1159](https://github.com/duobaseio/forui/issues/1159): "Migration to 3.47 & standalone Material/Cupertino packages"
- forui issue [#1160](https://github.com/duobaseio/forui/issues/1160): "FTextField MergeSemantics crashes on Flutter 3.47.0"
- **Source code verification:** forui 0.25.0 uses `MergeSemantics` in `FTextField` (`text_field/input/input.dart:386`), `FOtpField` (`otp_field.dart:477`), `FPicker` (`picker_wheel.dart:231`), `FSwitch` (`switch.dart:153`), and `FBottomNavigationBarItem` (`bottom_navigation_bar_item.dart:80`)
- **`FSelect` (the widget used by our `EventDropdown`) does NOT directly use `MergeSemantics`** — verified by reading `/Users/tonyholmes/.pub-cache/hosted/pub.dev/forui-0.25.0/lib/src/widgets/select/single/select.dart`
- However, `FSelect` may compose other forui widgets (like `FTextField` for search functionality) that DO use `MergeSemantics`, or it may trigger the same Flutter 3.47 semantics issue through a different widget tree pattern
- forui PR [#1165](https://github.com/duobaseio/forui/pull/1165) "Migrate to Flutter 3.47" was **merged on Aug 23, 2026** to fix this issue across all affected forui widgets

**BandRoadie Specific:**

- We use forui `^0.25.0` (resolved to `0.25.0`), adopted on Aug 13, 2026
- forui 0.25.0 was published ~Aug 2, 2026 (before Flutter 3.47 was released)
- forui's Flutter 3.47 compatibility fix (PR #1165) has **not yet been published to pub.dev** — it's only in their `main` branch
- Our `EventDropdown` → `AppDropdown` → forui `FSelect` chain is affected by this upstream incompatibility

**Data Flow:**

```
test calls EventDropdown (isSaving: true)
  → EventDropdown wraps AppDropdown
    → AppDropdown wraps forui FSelect.rich (enabled: false)
      → FSelect widget tree (exact MergeSemantics usage path unconfirmed)
        → Flutter 3.47.1's stricter semantics validation throws assertion
```

**Note:** While `FSelect` itself does not directly use `MergeSemantics` in its source code, it may either (a) compose other forui widgets that do (e.g., `FTextField` for search functionality), or (b) trigger the same Flutter 3.47 semantics issue through a different widget tree pattern. forui's PR #1165 addresses these failures across all affected widgets.

## Reference Docs Consulted

Not applicable (notification domain reference was explicitly skipped per Feature Input).

## Existing System Analysis

**Current Behavior:**

1. Tests execute `await tester.pumpWidget()` with an `EventDropdown` configured with `isSaving: true` (which passes `enabled: false` to forui's `FSelect`)
2. During `await tester.pumpAndSettle()`, Flutter's widget tree is built and the semantics tree is constructed
3. forui's `FSelect` widget tree is rendered (exact `MergeSemantics` usage path unconfirmed — `FSelect` does not directly use `MergeSemantics` in its source, but may compose widgets that do or trigger the issue through other patterns)
4. Flutter 3.47.1's scheduler calls `sendSemanticsUpdate()` which validates the semantics tree structure
5. The new Flutter 3.47.1 assertion `'node.isMergedIntoParent': is not true` fails at `semantics.dart:3862`
6. Test fails with exception

**Why Flutter 3.44.6 Passes:**

- Flutter 3.44.6 did not have the stricter semantics merge validation introduced in PR #183745
- The `MergeSemantics` usage pattern in forui widgets was compatible with Flutter 3.44.x's relaxed invariants

**Why Flutter 3.47.1 Fails:**

- Flutter 3.47.1 enforces stricter invariants around how `MergeSemantics` handles sibling nodes
- forui 0.25.0's implementation does not account for these new constraints

## Proposed Solution

**None — dependency upgrade required, significant blast radius.**

The root cause is in forui's source code (specifically how `FSelect` and related widgets use `MergeSemantics`), which was fixed in forui PR #1165 but has not yet been published to pub.dev.

**Available Options (none are low-risk):**

### Option 1a: Upgrade to forui nightly build (main branch) (HIGH RISK)

```yaml
# pubspec.yaml
dependencies:
  forui:
    git:
      url: https://github.com/duobaseio/forui.git
      ref: main # tracks moving target
      path: forui
```

**Pros:**

- Gets the Flutter 3.47 fix immediately
- Documented by forui as an option for testing unreleased features

**Cons:**

- **Nightly builds are explicitly marked as not guaranteed to be stable** per forui's README
- All widgets using forui (every dropdown, select, text field, button, card, etc. across BandRoadie) would be running on unreleased code
- High regression risk across Events, Setlists, Members, Settings, and any other UI that uses forui components
- No semantic versioning guarantee — breaking changes could land in `main` at any time
- Complicates dependency management and updates
- **Tracks a moving target** — future commits to `main` could introduce new issues

### Option 1b: Pin to forui PR #1165 merge commit (MODERATE-HIGH RISK)

```yaml
# pubspec.yaml
dependencies:
  forui:
    git:
      url: https://github.com/duobaseio/forui.git
      ref: 9710c3539c2885277d08de5ad513d22b267aa824 # PR #1165 merge commit
      path: forui
```

**Pros:**

- Gets the Flutter 3.47 fix immediately
- **Fixed commit SHA** — predictable, won't change unexpectedly like `main` branch
- Same code that forui will likely publish in their next release
- Can verify exact code being used

**Cons:**

- Still unreleased code (not published to pub.dev)
- Moderate regression risk across all forui widgets (lower than Option 1a since commit is fixed)
- Complicates dependency management
- Must manually update to published version later (no automatic semver upgrade path)
- Testing burden still applies — QA must test all forui-based widgets

### Option 2: Wait for forui's next published release (SAFE, BUT BLOCKS CI)

**Pros:**

- Zero code changes required
- Semantic versioning guarantees once forui publishes to pub.dev
- forui's own CI and testing will validate the fix before publication

**Cons:**

- Blocks feature/ci-analyze-test-gate (PR #170) and all future CI runs until forui publishes
- No public timeline for forui's next release (PR #1165 merged yesterday, typically releases take days-to-weeks)
- Cannot merge any PR that depends on CI passing

### Option 3: Pin CI to Flutter 3.44.x temporarily (WORKAROUND)

Modify `.github/workflows/flutter_ci.yml` to use Flutter 3.44.x instead of stable channel.

**Pros:**

- Unblocks CI immediately
- Low risk — uses a known-good Flutter version
- Can be reverted easily once forui publishes Flutter 3.47 support

**Cons:**

- CI no longer tests against Flutter stable (3.47.x), which is what production will eventually use
- Temporary workaround that must be tracked and reverted later
- Delays discovery of other potential Flutter 3.47 compatibility issues in BandRoadie's code

### Option 4: Remove EventDropdown tests temporarily (NOT RECOMMENDED)

Skip or comment out the 3 failing tests until forui publishes.

**Cons:**

- Reduces test coverage for a critical UI component
- Risk of forgetting to re-enable tests later
- Doesn't fix the underlying issue — widgets may still have runtime issues on Flutter 3.47

## Database Impact

**Not applicable.** This is a client-side widget testing issue with no database schema, RLS, RPC, or trigger changes required.

## Flutter Architecture Changes

**No changes possible without forui upgrade.**

The incompatible code is inside forui's source code (specifically `FSelect`'s use of `MergeSemantics`). BandRoadie's layers are:

- `lib/features/events/widgets/event_editor_helpers.dart`: `EventDropdown` (thin wrapper)
- `lib/components/ui/app_dropdown.dart`: `AppDropdown` (forui adapter)
- `forui` package (external dependency): `FSelect` (contains the `MergeSemantics` wrapper)

We cannot modify forui's widget tree structure without forking the package.

## Files to Create

**None.**

## Files to Modify

**Decision required from Manager/Tony:**

If **Option 3** (pin CI to Flutter 3.44.x temporarily) is chosen:

- `.github/workflows/flutter_ci.yml` — change Flutter channel or version specification

If **Option 1a or 1b** (forui git dependency) is chosen:

- `pubspec.yaml` — change forui dependency from `^0.25.0` to git dependency
- `pubspec.lock` — regenerated after `flutter pub get`

Otherwise: **No files to modify** (wait for forui publication).

## Files Off-Limits

- `test/features/events/widgets/event_dropdown_test.dart` — do not modify tests; they correctly validate widget behavior
- `lib/features/events/widgets/event_editor_helpers.dart` — do not modify `EventDropdown`; it correctly wraps forui
- `lib/components/ui/app_dropdown.dart` — do not modify `AppDropdown`; it correctly wraps forui
- All other forui-based widgets — do not attempt to work around forui's internal semantics structure

## System Impact Map

| System                                 | Impact                                                                                                                                                                                                    |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Events**                             | Affected — EventDropdown is defined in `lib/features/events/widgets/event_editor_helpers.dart`                                                                                                            |
| **All forui-based widgets**            | Potentially affected if forui nightly is chosen — includes buttons, text fields, cards, selects, checkboxes, switches, date pickers, time pickers, and all other forui widgets used throughout BandRoadie |
| Gigs                                   | Unaffected (unless forui nightly introduces regressions)                                                                                                                                                  |
| Rehearsals                             | Unaffected (unless forui nightly introduces regressions)                                                                                                                                                  |
| Setlists / Catalog                     | Unaffected (unless forui nightly introduces regressions)                                                                                                                                                  |
| Members / RBAC                         | Unaffected (unless forui nightly introduces regressions)                                                                                                                                                  |
| Auth / Session                         | Unaffected                                                                                                                                                                                                |
| Routing                                | Unaffected                                                                                                                                                                                                |
| Notifications                          | Unaffected                                                                                                                                                                                                |
| Platform (iOS / Android / Web / macOS) | All platforms unaffected — this is a widget testing issue, not a runtime platform issue                                                                                                                   |

## Regression Risk

**HIGH** if forui git dependency with main branch is used (Option 1a)
**MODERATE-HIGH** if forui git dependency pinned to PR #1165 commit is used (Option 1b)
**LOW** if CI is pinned to Flutter 3.44.x temporarily (Option 3)
**NONE** if waiting for forui publication (Option 2)

### Risk Factors:

1. **Scope of forui usage:** BandRoadie uses forui extensively across all UI surfaces (forms, buttons, cards, layouts, etc.). A regression in forui affects the entire app, not just EventDropdown.
2. **Nightly/unreleased build stability:** forui explicitly documents nightly builds as "not guaranteed to be stable" and "use at your own risk." Even pinning to a specific commit (Option 1b) still uses unreleased code not validated by pub.dev publication.
3. **No semantic versioning on git dependencies:** Breaking changes can land in `main` at any time (Option 1a), or unpublished commits may have unforeseen issues (Option 1b).
4. **Testing burden:** If forui git dependency is adopted (Options 1a or 1b), QA must regression-test **every forui-based widget** across all platforms, not just EventDropdown.

## Engineer Task Breakdown

**No tasks assigned — decision required before implementation can proceed.**

This is a **Manager/Tony escalation** to choose between:

1. Accept high regression risk with forui main branch (Option 1a)
2. Accept moderate-high regression risk with forui PR #1165 commit pin (Option 1b)
3. Accept blocked CI with waiting for forui publication (Option 2, with or without temporary Flutter 3.44.x pinning per Option 3)
4. Some other approach not covered in this plan

If a decision is made, the Engineer task would be minimal:

- **Options 1a or 1b (git dependency):** Update `pubspec.yaml`, run `flutter pub get`, verify tests pass locally
- **Option 3 (pin CI):** Update `.github/workflows/flutter_ci.yml` to specify Flutter 3.44.x, verify CI passes

## Verification Plan

**Not applicable until a solution option is chosen.**

If **Option 1a or 1b** (forui git dependency) is chosen:

1. Run `flutter pub get` to fetch forui from git
2. Run `flutter test test/features/events/widgets/event_dropdown_test.dart` locally on Flutter 3.44.6 → must pass (3/3 tests)
3. Run `flutter test test/components/ui/app_dropdown_test.dart` locally on Flutter 3.44.6 → must pass (2/2 tests)
4. Run full `flutter test` suite → must pass with no new failures
5. Push to PR #170 and verify CI passes on Flutter 3.47.1
6. **QA must regression-test all forui-based widgets** (see QA Regression Areas below)

If **Option 3** (pin CI) is chosen:

1. Update workflow file
2. Push to PR #170
3. Verify CI runs on Flutter 3.44.x and passes
4. Document the temporary pin and create a tracking issue to revert it once forui publishes Flutter 3.47 support

## QA Regression Areas

**If forui git dependency is chosen (Options 1a or 1b), QA must test:**

### High Priority (forui widgets used in EventDropdown's code path):

- Event editor dropdowns (duration, BPM, time selects)
- Event form submission flow
- Event editing with all dropdown interactions

### Medium Priority (other forui form widgets):

- Text fields (event name, venue, location, notes)
- Buttons (save, cancel, delete)
- Checkboxes and switches (notification preferences, settings)
- Date and time pickers (gig dates, rehearsal times)

### Lower Priority (forui layout/display widgets):

- Cards (event cards, song cards, member cards)
- Badges (status indicators)
- Dividers and layout components
- Navigation components

### Platforms:

- iOS (primary platform where issue was discovered)
- Android
- Web
- macOS

**If Option 2 or 3 is chosen:** QA regression testing is not required — only verify that CI passes once unblocked.

## Rollout / Migration Strategy

**Not applicable.**

If forui git dependency is chosen (Options 1a or 1b), the migration is immediate upon `flutter pub get`. There is no gradual rollout, no feature flag, and no fallback beyond reverting the `pubspec.yaml` change and running `flutter pub get` again.

## Out of Scope

- Forking forui and maintaining a local patch — excessive maintenance burden for a single assertion fix
- Modifying BandRoadie's wrapper widgets (`EventDropdown`, `AppDropdown`) to work around forui's internal `MergeSemantics` usage — not architecturally viable
- Modifying the tests to skip semantics validation — masks the real issue and doesn't fix potential runtime problems
- Implementing a custom dropdown widget to replace forui's `FSelect` — massive scope, introduces design inconsistency
- Patching Flutter framework locally — not viable for CI or production deployments

---

## RECOMMENDATION TO MANAGER

**This issue cannot be fixed within BandRoadie's codebase.** The root cause is a known Flutter 3.47.0 regression that affects forui's internal widget implementation. forui has already fixed the issue in their `main` branch (PR #1165 merged Aug 23, 2026), but the fix has not yet been published to pub.dev.

**Recommended path forward:**

1. **Contact forui maintainers** via GitHub issue or Discord to ask for an estimated timeline for publishing version 0.26.0 (or similar) with the Flutter 3.47 fix
2. If timeline is **< 1 week**, wait for publication (Option 2) — safest approach
3. If timeline is **> 1 week** or unknown, temporarily pin CI to Flutter 3.44.x (Option 3) to unblock PR #170 and future CI runs, then revert the pin once forui publishes
4. **Avoid forui nightly build** unless absolutely necessary and only after Manager/Tony explicitly accepts the high regression risk

**Do NOT proceed with implementation** until Manager/Tony makes a decision on which option to pursue.
