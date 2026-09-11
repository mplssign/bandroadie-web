# ARCHITECT_PLAN — profile-role-chips-full-width

## Feature Slug

`feature/profile-role-chips-full-width`

## Feature Title

Role-in-band chips on the My Profile screen should extend edge to edge

## Problem Summary

On the "My Profile" screen (`MyProfileScreen`), the horizontally-scrolling row of role chips ("+ Add", "Remove/Done", plus predefined and custom roles) is currently inset by the same 24 px horizontal padding that scopes every other form section (name row, phone, address, birthday). The requirement is that this specific chip row extends edge-to-edge (no horizontal inset), while every other element on the screen retains its existing 24 px inset unchanged.

The scope is purely visual layout. No state, data, auth, routing, or platform-conditional behavior is affected.

## Root Cause

**Confidence: HIGH** — confirmed by direct code inspection of [lib/features/profile/my_profile_screen.dart](lib/features/profile/my_profile_screen.dart#L903-L989).

The form is currently structured as:

```
Form
 └── Column
      ├── Expanded
      │    └── SingleChildScrollView(padding: EdgeInsets.all(24))   ← 24 px HORIZONTAL and vertical padding, ambient
      │         └── Column (crossAxisAlignment: start)
      │              ├── subtitle Text
      │              ├── _buildTwoCol(firstName, lastName)
      │              ├── phone field
      │              ├── _buildTwoCol(address, zip)
      │              ├── _buildBirthdaySection()
      │              └── _buildRoleSection()                         ← inherits the 24 px horizontal ambient padding
      └── _buildFooter()
```

`_buildRoleSection()` ([lib/features/profile/my_profile_screen.dart](lib/features/profile/my_profile_screen.dart#L1168-L1287)) returns a `Column` whose last child is a `SizedBox(height: 36)` wrapping a horizontal `SingleChildScrollView` of role pills. Because the ambient 24 px horizontal padding is applied at the outer `SingleChildScrollView` in `_buildForm()`, every direct or transitive child — including the pill row — is inset by 24 px on each side. The pill row itself does not opt out and there is no layout escape hatch present.

The `SingleChildScrollView.padding: EdgeInsets.all(24)` in `_buildForm()` is the sole cause; there is no other padding applied within `_buildRoleSection()` itself.

## Existing System Analysis

**Login screen precedent (`lib/features/auth/login_screen.dart`).** The Feature Input references `_buildDomainPills()` as a full-width sibling escaping shared ambient padding. On direct inspection ([lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L612-L629) and [lib/features/auth/login_screen.dart](lib/features/auth/login_screen.dart#L446-L469)) that widget does not actually go edge-to-edge — it wraps `EmailDomainShortcutBar` in `SizedBox(width: maxWidth)` where `maxWidth = constraints.maxWidth - 64`, matching the email field width and remaining inside the outer `Padding(EdgeInsets.symmetric(horizontal: 32))`. That is an inset-matched pattern, not an edge-escape pattern. This does not change what the profile screen needs to do — the Feature Input explicitly states the reference is for approach, not verbatim copy, and the intent for the profile screen is unambiguous: chip row spans edge to edge. Flagging the discrepancy for record only.

**Role section internal structure.** `_buildRoleSection()` currently contains three logical parts under one `Column`:

1. `Text('Role in Band')` label
2. Optional band selector block (only rendered in multi-band mode: label `'Select Band'` + horizontally scrolling row of `_BandPill`s)
3. The horizontally scrolling role pill row itself

The Feature Input scopes the change to the role chip row only — the section label and the multi-band band selector row must remain inset unchanged.

**Test coverage.** There are no existing widget or golden tests under `test/features/profile/**` for `my_profile_screen.dart` (confirmed via search). No test regression risk from the restructure.

**Footer and outer scaffold.** `_buildFooter()` sits outside the scrollable region as a sibling of the `Expanded` in `_buildForm()` and is unaffected. The outer `AppScaffold` + `AppAppBar` in `build()` are unaffected.

## Proposed Solution

Restructure `_buildForm()` and `_buildRoleSection()` so the 24 px horizontal inset is applied one level deeper — around all form content **except** the role pill row — leaving the role pill row as a direct child of the scroll view's inner `Column` with no horizontal padding above it.

**High-level structural change:**

```
Form
 └── Column
      ├── Expanded
      │    └── SingleChildScrollView(padding: EdgeInsets.symmetric(vertical: 24))   ← horizontal padding removed here
      │         └── Column (crossAxisAlignment: start)
      │              ├── Padding(EdgeInsets.symmetric(horizontal: 24))              ← single wrapper for ALL padded content
      │              │    └── Column
      │              │         ├── subtitle Text
      │              │         ├── _buildTwoCol(firstName, lastName)
      │              │         ├── phone field
      │              │         ├── _buildTwoCol(address, zip)
      │              │         ├── _buildBirthdaySection()
      │              │         └── _buildRoleSectionHeader()   ← label + optional multi-band selector
      │              ├── SizedBox(height: 12)                                       ← same spacer that was inside _buildRoleSection
      │              └── _buildRolePillRow()                                        ← edge-to-edge, no ambient horizontal padding
      └── _buildFooter()
```

**`_buildRoleSection()` is split into two private helpers:**

- `_buildRoleSectionHeader()` — returns the `Column` fragment containing the `'Role in Band'` label and, when `_isMultiBandMode` is true, the `'Select Band'` label plus the `_BandPill` selector row. This is rendered inside the padded outer wrapper, preserving the existing 24 px inset for the label and band selector.
- `_buildRolePillRow()` — returns the `SizedBox(height: 36)` wrapping the horizontal `SingleChildScrollView` of role pills. This is rendered as a sibling **outside** the padded wrapper, so it inherits no horizontal inset and stretches to the scroll view's full width (i.e. the full screen width).

Both helpers use exactly the same widget subtrees that already exist in `_buildRoleSection()` today — no rebuilding of pills, no changes to `_RolePill`, no state changes, no callback wiring changes. The `SizedBox(height: 12)` spacer that currently sits between the header block and the pill row inside `_buildRoleSection` moves to the outer `Column` between the two new helper calls, preserving the identical vertical rhythm.

**Design decision — first-pill horizontal position.** The Feature Input specifies "no horizontal inset" and "stretch to both screen edges." The proposed structure honors that literally: the pill row's `SingleChildScrollView` receives no `padding` and no wrapping `Padding`, so the first pill (`+ Add`) renders flush against the screen's left edge, distinctly offset from the `Role in Band` label above it which remains at 24 px inset. This is the direct read of the request and matches the escape-from-ambient-padding intent. Flagging explicitly because a common alternative for this pattern is edge-to-edge scroll region with a 24 px content padding on the inner `SingleChildScrollView` (so the first pill aligns visually with the label above). The Feature Input rules out the alternative by phrasing ("no horizontal inset"), so the plan implements the literal reading; if Tony wants the aligned-first-pill variant, that is a one-line change (add `padding: EdgeInsets.symmetric(horizontal: 24)` on the pill row's inner `SingleChildScrollView`) at PR review.

## Database Impact

n/a

## Flutter Architecture Changes

n/a — no new providers, no new controllers, no new repositories, no changes to state management. Refactor is a private-method split within a single existing widget class, plus one `Padding` wrapper reorg inside its `build`-adjacent helper.

## Files to Create

n/a

## Files to Modify

- **[lib/features/profile/my_profile_screen.dart](lib/features/profile/my_profile_screen.dart)**
  - `_buildForm()`: change `SingleChildScrollView(padding: EdgeInsets.all(24))` to `SingleChildScrollView(padding: EdgeInsets.symmetric(vertical: 24))`. Wrap the existing inner `Column`'s form-section children (subtitle through `_buildBirthdaySection()` and the new `_buildRoleSectionHeader()` call) in a single `Padding(padding: EdgeInsets.symmetric(horizontal: 24))`. Add the `SizedBox(height: 12)` spacer and `_buildRolePillRow()` call as siblings after that padded block, then the trailing `SizedBox(height: 32)`.
  - Delete `_buildRoleSection()` and replace it with two private helpers `_buildRoleSectionHeader()` and `_buildRolePillRow()`, each containing the exact widget subtree that currently lives in the corresponding portion of `_buildRoleSection()`. No changes to `_RolePill`, `_BandPill`, `_toggleRole`, `_toggleDeleteMode`, `_showAddRoleDialog`, `_addCustomRole`, `_deleteCustomRole`, `_onBandSelected`, or any state field.

## Files Off-Limits

- `lib/features/auth/login_screen.dart` — referenced by the Feature Input for pattern context only. Do not modify.
- `lib/components/ui/email_domain_shortcut_bar.dart` — irrelevant to profile screen; do not modify.
- `lib/features/profile/profile_screen.dart` and `lib/features/profile/profile_tab_content.dart` — different screens (viewing another member's profile / profile tab shell). Not the "My Profile" editor; do not modify.
- `lib/features/profile/user_band_roles_repository.dart` — data layer. This is a UI-only fix; do not touch.
- `lib/app/theme/design_tokens.dart` and any shared spacing tokens — do not introduce new tokens or edit existing ones for this fix; hard-coded `24` matches existing local usage in this file.
- Any other feature under `lib/features/**` — this fix is scoped to a single screen.
- All `supabase/`, `database/`, `test/`, migrations, config, assets, lockfiles.

## Change Budget

- **Expected net line delta:** `lib/features/profile/my_profile_screen.dart` ≈ +15 lines net (one added outer `Padding` wrapper, one split of `_buildRoleSection` into two helpers, one moved `SizedBox` spacer). Range: +10 to +20.
- **Expected new files:** 0.
- **Expected new public classes / methods:** 0 (both new helpers are private and replace one existing private method).
- **Expected new dependencies:** 0.

## System Impact Map

- **Gigs:** unaffected.
- **Rehearsals:** unaffected.
- **Setlists:** unaffected.
- **Members:** unaffected at the data layer. Members page reads roles from `user_band_roles` via `MembersRepository`; this fix does not touch that path.
- **Auth:** unaffected.
- **Routing:** unaffected.
- **Notifications:** unaffected.
- **Platforms:** all platforms (iOS, Android, macOS, Web) — same code path, no platform-conditional logic touched. Init order guardrail is not touched (no changes to `main.dart` or any bootstrap file). Firebase / `DeepLinkService` untouched. `--dart-define` config untouched.

## Regression Risk

**LOW.**

- Single file, single widget class, pure layout restructure.
- No auth, session, routing, init order, RLS, RPC, or database code touched.
- All widget subtrees for form fields, birthday picker, role pills, band pills, save/cancel footer, and dirty-state save are used verbatim — only their ancestor `Padding` structure changes.
- The horizontally scrolling role pill row was already a `SingleChildScrollView(scrollDirection: Axis.horizontal)`; expanding its available horizontal width does not create clipping or overflow risk — a horizontal scroll view is unbounded in its scroll axis by definition.
- No existing tests reference `my_profile_screen.dart` (confirmed by search under `test/**/profile*`), so no test suite regression pressure. The wider `flutter test` suite must still pass unchanged.

## Engineer Task Breakdown

1. In `_buildForm()` in [lib/features/profile/my_profile_screen.dart](lib/features/profile/my_profile_screen.dart), change the `SingleChildScrollView` padding from `EdgeInsets.all(24)` to `EdgeInsets.symmetric(vertical: 24)`. Restructure its child `Column` so the existing form-section children (from the subtitle `Text` through `_buildBirthdaySection()` **and** the call to the new `_buildRoleSectionHeader()`) are wrapped together inside a single `Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...]))`. Then, as siblings of that padded wrapper (still inside the outer `Column`), add `const SizedBox(height: 12)`, then `_buildRolePillRow()`, then the existing trailing `const SizedBox(height: 32)`.
2. Delete the existing `_buildRoleSection()` method. In its place, add two private helper methods on the same `State` class:
    - `Widget _buildRoleSectionHeader()` returning a `Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...])` containing exactly the `Text('Role in Band')` label followed by, when `_isMultiBandMode` is true, the `SizedBox(height: 12)` + `Text('Select Band')` + `SizedBox(height: 8)` + `SizedBox(height: 36, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: _userBands.map((band) => Padding(padding: const EdgeInsets.only(right: 8), child: _BandPill(...)))))` block. Copy the widget subtree verbatim from the current `_buildRoleSection()` — do not alter any labels, spacings, callback wiring, or `_BandPill` construction.
    - `Widget _buildRolePillRow()` returning the existing `SizedBox(height: 36.0, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: allRolePills.expand(...).toList()..removeLast())))` block, along with the `final allRolePills = <Widget>[...]` list construction that currently lives at the top of `_buildRoleSection()`. Move the list construction into `_buildRolePillRow()` verbatim. Do not add `padding` on the `SingleChildScrollView` and do not wrap the returned `SizedBox` in any `Padding`.
3. Do not touch `_RolePill`, `_BandPill`, `_toggleRole`, `_toggleDeleteMode`, `_showAddRoleDialog`, `_validateAndSubmitRole`, `_addCustomRole`, `_deleteCustomRole`, `_onBandSelected`, `_initializeMultiBandRoles`, `_extractCustomRolesFromSelected`, `_saveProfile`, `_cancel`, `_buildFooter`, `_buildBody`, `_buildBirthdaySection`, `_buildTextField`, `_buildTwoCol`, `build`, or any state field or lifecycle method.
4. Run `flutter analyze`; resolve any analyzer errors introduced by the refactor (expected: none). Run `flutter test` to confirm the existing suite still passes.

## Verification Plan

**Tier 1 — Pre-deploy (QA-executable, mechanical, no running app):**

1. `flutter analyze` returns clean (no new warnings or errors) on the branch.
2. `flutter test` passes with the full suite unchanged. No test files under `test/features/profile/**` exist today; none should be added by Engineer for this fix (proportional-to-risk: pure layout, single file, single widget class, no state or data touched).
3. Static diff review of `lib/features/profile/my_profile_screen.dart`:
    - Confirm the `SingleChildScrollView` in `_buildForm` has `padding: EdgeInsets.symmetric(vertical: 24)` (no horizontal component).
    - Confirm exactly one `Padding(padding: EdgeInsets.symmetric(horizontal: 24), ...)` wraps the form-section stack ending at `_buildRoleSectionHeader()`.
    - Confirm `_buildRolePillRow()` is a direct sibling of that `Padding` inside the inner `Column`, not wrapped in any `Padding`, and the pill row's `SingleChildScrollView` has no `padding` argument.
    - Confirm `_buildRoleSection` is gone and no other call sites of it exist (grep should return zero matches).
    - Confirm no other file has been modified.

**Tier 2 — Owner-run at PR-test / apply-release time (Tony's punch list; not a QA gate because it requires a running app):**

1. Check out the branch. Run `./run.sh macos` (or an available device target).
2. Sign in as a normal user (not the demo band). Reach the "My Profile" screen (bottom nav / drawer entry to the current user's own profile editor).
3. Scroll to the "Role in Band" section. **Expect:** the label `Role in Band` is inset roughly 24 px from the left screen edge — visually aligned with the labels above it (`First Name`, `Phone Number`, `Address`, etc.).
4. Look immediately below the label. **Expect:** the first pill (`+ Add`) sits flush against the left screen edge (zero inset). The pill row visibly extends past the right screen edge into the horizontal scroll region.
5. Swipe left on the pill row. **Expect:** it scrolls horizontally, revealing additional predefined and custom roles. Scrolling behavior is unchanged from before.
6. Tap a predefined role (e.g. `Guitar`). **Expect:** it toggles selected state as before. Tap `Remove` — enters delete mode as before. Tap `Done` — exits. Tap `+ Add` — the add-custom-role dialog opens as before. Add a custom role — it appears in the row and is selected. Delete it via delete mode — it is removed.
7. Confirm the save/cancel footer at the bottom is visually unchanged. Change a field, tap `Save` — dirty save works as before. Tap `Cancel` — reverts as before.
8. If the current signed-in user belongs to 2+ bands (multi-band mode), confirm the `Select Band` label and the horizontal band selector row above the role pill row are still inset at 24 px (unchanged), and switching bands still updates the role pill selection state correctly.
9. Verify on at least one second platform (e.g. iOS simulator or Web) that the same edge-to-edge behavior holds. Native and web share this widget code path with no platform-conditional branching; parity is expected.
10. If Tony wants the first pill to align with the label at 24 px inset instead of flush at 0 px (see Proposed Solution — Design decision), that is a one-line change at PR review: add `padding: const EdgeInsets.symmetric(horizontal: 24)` to the pill row's inner `SingleChildScrollView` inside `_buildRolePillRow()`.

## QA Regression Areas

- `MyProfileScreen` in both `isGated: false` (normal edit) and `isGated: true` (first-time onboarding) modes — layout only; no state code changed, so both modes should render and save identically.
- Role pill tap behavior (toggle, add, remove, delete-mode entry/exit).
- Custom role add/remove flows including duplicate-name validation.
- Multi-band band selector rendering, band switch, and per-band role editing.
- Dirty-state save button enable/disable and the `_cancel()` revert path.
- Footer Save / Cancel button rendering and behavior.
- No regressions expected in `MembersScreen`, gigs, rehearsals, or setlists (this fix does not touch any code they consume).

## Rollout Strategy

- Standard PR to `main`. No feature flag. No migration. No coordination with Supabase edge functions or the backend.
- No `--dart-define` changes required.
- After merge, next standard release picks it up on all platforms simultaneously (iOS, Android, macOS, Web).

## Out of Scope

- Restyling role pills (colors, size, shape, typography).
- Restyling the multi-band band selector row or making it edge-to-edge.
- Restyling any other form section on the profile screen.
- Any change to `_RolePill`, `_BandPill`, or their tap animations / delete-mode visuals.
- Any change to `login_screen.dart` or `EmailDomainShortcutBar` (referenced for pattern only).
- Introducing new spacing tokens or shared "edge-to-edge chip row" helpers or reusable components — the Feature Input asks for a minimal scoped fix on one screen, not a design-system change.
- Golden tests or new widget tests for this screen — proportional to risk on a pure-layout restructure with no existing coverage on this file; if Tony wants coverage introduced, that is a separate task.
- Any change to how role data is persisted (`user_band_roles` upserts, `SECURITY DEFINER` RPCs, RLS policies).
