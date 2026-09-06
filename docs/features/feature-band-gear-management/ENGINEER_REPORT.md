# ENGINEER_REPORT

## Feature Slug

feature/band-gear-management

## Feature Title

Band Gear Management

## Cycle Number

6

## Goal

Cycle 6 — In-branch revert-only cycle driven by Tony's cycle-5 QA-APPROVED
state review (Manager cycle-6 note): "remove 'Gear' from the menu. It should
only be in the Quick Actions section." Cycle 5's Quick Actions surfacing
stays exactly as-is; cycle 3's side-drawer surfacing is fully reverted
(`side_drawer.dart` and `app_shell.dart` restored to main tip byte-identical).
No new code introduced this cycle.

Cycle 5 — In-branch additive scope extension driven by Tony's PR #261 6b test
finding ("i don't see a button for Gear under Quick actions"). Surface Gear
under the Home dashboard's Quick Actions row by mirroring the existing
Financials precedent exactly (`_handleOpenFinancials` + `onFinancials` /
`showFinancials` on `QuickActionsRow`). The base `ARCHITECT_PLAN.md` surfaced
Gear only via the side drawer (Task 15) — Quick Actions was not part of the
original plan; this cycle adds it as the minimal, precedent-matching wiring.
All cycle-1-through-4 work rolls forward unchanged.

Cycle 4 — Implement the contributor visibility gate scope addition from the
Architect cycle-3 revision (three follow-up RBAC migrations + Dart parity
edits) and re-run the Tier 1 verification procedure. Cycle-3 uncommitted
implementation work is unchanged and rolls forward as-is.

## Architect Tasks Completed

Cycle 6 (this cycle) — revert-only, no new architect tasks:

- Cycle 6 revert (side-drawer surfacing removed per Tony's cycle-5
  QA-APPROVED review directive): Executed. See dedicated section below.

Cycle 5 — additive scope extension:

- Cycle 5 addition (Quick Actions surfacing): Completed. See dedicated
  section below.

Cycle 4:

- Task 2 — Migration 1 of 3 (sub-permission column): Completed. Added
  `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  with `ALTER TABLE public.contributor_permissions ADD COLUMN IF NOT EXISTS
can_view_gear BOOLEAN NOT NULL DEFAULT FALSE;`, direct mirror of
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`.
- Task 3 — Migration 2 of 3 (RPC fix): Completed. Added
  `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
  with a full-body `CREATE OR REPLACE FUNCTION public.update_member_role(UUID,
UUID, TEXT, JSONB)` mirroring
  `20260711120000_fix_update_member_role_can_view_financials.sql`, adding
  exactly one SET-clause line `can_view_gear = COALESCE((p_sub_permissions->>
'can_view_gear')::boolean, FALSE),`. Terminates with `GRANT EXECUTE ON
FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`.
- Task 4 — Migration 3 of 3 (RLS helper + SELECT policy swap): Completed.
  Added `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
  with (a) `CREATE OR REPLACE FUNCTION public.check_gear_view_permission(
p_band_id UUID) RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET
search_path = public` body mirroring `check_financial_view_permission`;
  (b) `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon;` and `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(
UUID) TO authenticated;`; (c) `DROP POLICY IF EXISTS "Band members can view
gear" ON public.band_gear;` then `CREATE POLICY "Band members can view gear"
ON public.band_gear FOR SELECT USING (public.check_gear_view_permission(
band_id));`. INSERT / UPDATE / DELETE policies are not touched.
- Task 9 — Sub-permission field on Dart model: Completed. Edited
  `lib/features/members/permissions/contributor_permissions.dart` to add a
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`, defaulting
  `false` in the immutable constructor.
- Task 10 — Rewire `BandPermissions.canViewGear` body: Completed. Edited
  `lib/features/members/permissions/band_permissions.dart` to change the
  `canViewGear` getter body from `isAdmin || isMember || isContributor` to
  `isAdmin || isMember` for the admin/member branch and
  `subPermissions?.canViewGear ?? false` for the contributor branch.
  `canManageGear` unchanged.
- Task 11 — Role Management sheet toggle: Completed. Edited
  `lib/features/members/widgets/role_management_sheet.dart` to add one new
  `_buildPermissionToggle` "Can view gear" immediately after "Can view
  financials" (wired to `_subPermissions.canViewGear` /
  `copyWith(canViewGear: v)`), and extended `_permissionsEqual` to compare
  `a.canViewGear == b.canViewGear`.
- Task 16 — Model unit test: Verified (already added in cycle-3 uncommitted
  work as `test/features/gear/gear_item_test.dart`). Re-run in T1.2: 5/5
  pass.
- Task 17 — `flutter analyze` + `flutter test` iterate to green: Completed.
  Analyzer clean at every severity across the T1.1 file list; feature tests
  green; full-suite failure is the single accepted deviation A.

Inherited from cycle-3 uncommitted work (unchanged this cycle):

- Task 1 — Base migration
  `supabase/migrations/20260905201000_create_band_gear.sql` (table, indexes,
  RLS enable, four RLS policies, `set_band_gear_updated_at` trigger).
- Task 5 — `lib/features/gear/models/gear_item.dart`.
- Task 6 — `lib/features/gear/gear_repository.dart`.
- Task 7 — `lib/features/gear/gear_controller.dart`.
- Task 8 — Cycle-3 `canViewGear` / `canManageGear` getters already present in
  `lib/features/members/permissions/band_permissions.dart` (task 10 above
  swaps `canViewGear`'s body only).
- Task 12 — `lib/features/gear/widgets/gear_empty_state.dart` and
  `lib/features/gear/widgets/gear_row.dart`.
- Task 13 — `lib/features/gear/widgets/gear_form_sheet.dart`.
- Task 14 — `lib/features/gear/gear_screen.dart`.
- Task 15 — Drawer + shell wiring in
  `lib/features/home/widgets/side_drawer.dart` and
  `lib/features/shell/app_shell.dart`.

## Files Created

Cycle 5: none.

Cycle 4 (new this cycle):

- supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql
- supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql
- supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- supabase/migrations/20260905201000_create_band_gear.sql
- lib/features/gear/models/gear_item.dart
- lib/features/gear/gear_repository.dart
- lib/features/gear/gear_controller.dart
- lib/features/gear/gear_screen.dart
- lib/features/gear/widgets/gear_row.dart
- lib/features/gear/widgets/gear_form_sheet.dart
- lib/features/gear/widgets/gear_empty_state.dart
- test/features/gear/gear_item_test.dart
- docs/features/feature-band-gear-management/ENGINEER_REPORT.md

## Files Modified

Cycle 6 (new this cycle) — revert-only:

- lib/features/home/widgets/side_drawer.dart — **reverted to main tip**
  (`git checkout main -- lib/features/home/widgets/side_drawer.dart`).
  This removes the three `final VoidCallback? onGearTap;` fields on
  `SideDrawer` / `DrawerOverlay` / `DrawerOverlayContent`, the three
  matching constructor parameter additions, the
  `if (widget.onGearTap != null) ...[ DrawerNavItem ... ]` Gear nav block,
  and the `onGearTap` plumbing in the two `DrawerOverlay*` `child:` blocks.
  It also reverts the four cycle-3 collateral `Container(color:)` →
  `ColoredBox(color:)` scrim-overlay lint fixes on lines
  867 / 877 / 1086 / 1096 (of HEAD numbering). Per Manager cycle-6 note:
  "Reverting to main is the cleanest end state." Net cycle-6 diff vs main
  for this file: 0.
- lib/features/shell/app_shell.dart — **reverted to main tip**
  (`git checkout main -- lib/features/shell/app_shell.dart`). This removes
  `import '../gear/gear_screen.dart';`, the `onGearTap:` callback wiring
  block in `_MenuDrawerLayer`'s `DrawerOverlayContent` call, and the six
  narrow `// ignore: prefer_const_constructors` /
  `// ignore: avoid_redundant_argument_values` lint suppression comments
  cycle 3 added on lines 211 / 216 / 217 / 218 / 247 / 248 (of HEAD
  numbering). Confirmed pre-revert that no other symbol in `app_shell.dart`
  references `GearScreen` (`grep -n 'GearScreen\|gear_screen'` → the
  import line and the `_MenuDrawerLayer` push call were the only two
  matches). Net cycle-6 diff vs main for this file: 0.

Both reverted files are no longer feature-touched. The feature's cycle-6
end state carries **zero** diff-vs-main for either file. They remain in the
T1.1 file list this cycle to prove no regression, per Manager cycle-6 note.

Cycle 5 (unchanged, still modified — Quick Actions surfacing preserved):

- lib/features/home/widgets/quick_actions_row.dart — added `onGear`
  callback field, `showGear` bool field (default `true`), constructor
  parameters, extended `hasVisibleButtons` to include `|| showGear`, and
  appended a `Gear` button block after the Financials block using the same
  `_buildQuickActionButton` helper with matching `SizedBox(width: 12)`
  separator handling. Label is `'Gear'` (no `+` prefix — matches
  Financials style since it opens an existing screen rather than creates a
  new entity). Also removed pre-existing redundant `width: 1` on
  `BorderSide` inside `_buildQuickActionButton` (default is 1) — see
  Cycle 5 pre-existing lint sweep note below.
- lib/features/home/home_tab_content.dart — added `../gear/gear_screen.dart`
  import; added `_handleOpenGear` method next to `_handleOpenFinancials`
  pushing `GearScreen` via `MaterialPageRoute`; read `perms.canViewGear`
  alongside `canViewFinancials` in the `build` method; threaded `canViewGear`
  through `_buildContentState`'s `required` parameter list; extended the
  Quick Actions Builder's `hasAnyButton` check with `|| canViewGear`; passed
  `onGear: canViewGear ? _handleOpenGear : null` and `showGear: canViewGear`
  on the `QuickActionsRow` call. Also swept six pre-existing info-level
  lints in the same file — see Cycle 5 pre-existing lint sweep note below.

Cycle 4:

- lib/features/members/permissions/contributor_permissions.dart — added
  `canViewGear` field with `fromJson` / `toJson` / `copyWith` / `allEnabled`
  / `allDisabled` / `toString` parity to `canViewFinancials`.
- lib/features/members/permissions/band_permissions.dart — swapped the body
  of the existing `canViewGear` getter from unconditional
  `isAdmin || isMember || isContributor` to admin/member-always plus
  contributor-consults-sub-permission; `canManageGear` untouched.
- lib/features/members/widgets/role_management_sheet.dart — added one new
  "Can view gear" `_buildPermissionToggle` after the existing "Can view
  financials" toggle; extended `_permissionsEqual` with
  `a.canViewGear == b.canViewGear`.

Inherited from cycle-3 uncommitted work (byte-identical to cycle 3):

- lib/features/home/widgets/side_drawer.dart
- lib/features/shell/app_shell.dart

## Cycle 5 addition — Quick Actions surfacing

**Trigger.** Tony tested PR #261 and reported: "i don't see a button for
Gear under Quick actions." This is a REQUIRES CHANGES finding from the
Step 6b test.

**Scope classification.** In-branch, additive-only scope extension. The
base `ARCHITECT_PLAN.md` surfaced Gear only via the side drawer (Task 15
in `lib/features/home/widgets/side_drawer.dart` + `lib/features/shell/
app_shell.dart`); Quick Actions surfacing was not part of the original
plan. No architect re-diagnosis was required — the precedent is
already in-repo for Financials, and this cycle mirrors that precedent
exactly. Manager cycle-5 note authorizes this as the equivalent scope
addition, mirroring the Financials-precedent QuickActionsRow wiring.

**Financials precedent mirrored exactly.** In
`lib/features/home/home_tab_content.dart`, the shipped Financials wiring is:

- `_handleOpenFinancials` pushes `const FinancialsScreen()` via
  `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const
FinancialsScreen()))`.
- `canViewFinancials` is read from `permissionsAsync.when(...)` in the
  `build` method (fail-closed defaults `false`).
- `canViewFinancials` is threaded as a `required` parameter through
  `_buildContentState`.
- Inside the Quick Actions `Builder`, `hasAnyButton` includes the
  Financials-visibility term, and the `QuickActionsRow` is called with
  `onFinancials: canViewFinancials ? _handleOpenFinancials : null` and
  `showFinancials: canViewFinancials`.

Cycle 5 adds the identical shape for Gear:

- `_handleOpenGear` pushes `const GearScreen()` via `Navigator.of(context)
.push(MaterialPageRoute(builder: (_) => const GearScreen()))` — literal
  mirror.
- `canViewGear` read from `permissionsAsync.when(...)` immediately after
  `canViewFinancials`.
- `canViewGear` threaded as a `required` parameter through
  `_buildContentState` immediately after `canViewFinancials`.
- `hasAnyButton` extended with `|| canViewGear` so the section still
  renders for a contributor with only the gear toggle enabled.
- `QuickActionsRow` receives `onGear: canViewGear ? _handleOpenGear : null`
  and `showGear: canViewGear`.

**QuickActionsRow parity.** `lib/features/home/widgets/quick_actions_row.
dart` gains `onGear` / `showGear` alongside the existing
`onFinancials` / `showFinancials`, with the Gear button appended after
the Financials button in `build`. Constructor parameters follow the same
positional/named parity. `hasVisibleButtons` now includes `|| showGear`.
Label is `'Gear'` (no `+` prefix — matches Financials which opens an
existing screen rather than creating a new entity).

**Files NOT touched, per Manager cycle-5 note precedent.**
`lib/features/home/home_screen.dart` and
`lib/features/home/widgets/empty_home_state.dart` — verified via
`grep -F 'Financials'` on both files: neither wires Financials. Cycle 5
matches that precedent and does not introduce Gear wiring where
Financials has none. `lib/features/home/widgets/side_drawer.dart` and
`lib/features/shell/app_shell.dart` remain byte-identical to cycle 3 —
Gear drawer navigation is untouched.

**Off-limits list respected.** Per `ARCHITECT_PLAN.md#L656`,
`lib/features/home/` is not on the off-limits list; `pubspec.yaml`,
`main.dart`, `analysis_options.yaml`, `supabase/**`, and every platform
directory remain untouched. No new dependency, no new named route, no new
provider.

**Cycle 5 pre-existing lint sweep note.** The T1.1 expanded file list
(`home_tab_content.dart` + `quick_actions_row.dart`) surfaced 7 pre-
existing info-level lints that the cycle-4 T1.1 command did not run
against because those files were not in cycle 4's file list. Per the
Engineer mode instruction "pre-existing violation in a file you did touch
does — fix it if it's trivial, or report it if fixing it would exceed
scope," all 7 were fixed as trivial one-line no-op equivalents (each
analyzer suggestion is a provably-safe rewrite of semantically identical
code):

- `home_tab_content.dart` line 391 (was): `fullscreenDialog: false` on
  the `MaterialPageRoute` in `_handleOpenFinancials` — removed (matches
  default). Kept `_handleOpenGear` symmetric (also without
  `fullscreenDialog: false`) — that removal is my own cycle-5 self-audit
  fix.
- `home_tab_content.dart` line 730 (was): `Container(color:)` in
  `_buildLoadingState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 775 (was): `Container(color:)` in
  `_buildErrorState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 820 (was): `variant:
AppButtonVariant.primary` on `AppButton` in `_buildErrorState` — removed
  (verified default in `lib/components/ui/app_button.dart:36`).
- `home_tab_content.dart` line 852 (was): `Container(color:)` in
  `_buildContentState` → `ColoredBox(color:)`.
- `home_tab_content.dart` line 911 (was): `const Duration(milliseconds:
0)` on the first `_AnimatedCardEntrance.delay` → `Duration.zero`
  (canonical form; `_AnimatedCardEntrance.delay` is required so the arg
  itself cannot be removed).
- `quick_actions_row.dart` line 114 (was): `width: 1` on `BorderSide`
  inside `_buildQuickActionButton` — removed (default is 1).

All fixes documented here for QA to distinguish from the additive gear-
surfacing changes.

## Cycle 6 revision — drawer entry removed

**Trigger.** Tony reviewed the cycle-5 QA-APPROVED state (PR #261 6b
iteration) and directed via Manager cycle-6 note: "remove 'Gear' from the
menu. It should only be in the Quick Actions section." This is a
revert-only cycle: cycle 5's Quick Actions surfacing (the shipped answer
to Tony's earlier PR #261 6b test finding) stays exactly as it landed;
cycle 3's side-drawer surfacing is fully removed so Gear surfaces via
Quick Actions only.

**Scope classification.** In-branch, subtractive-only revert. No new
files created, no new code introduced. Manager cycle-6 note explicitly
authorized the file-list contraction and provided the two `git checkout
main -- ...` commands used to execute the revert.

**Reverts executed.**

- `lib/features/home/widgets/side_drawer.dart` restored to main tip via
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/home/widgets/side_drawer.dart`.
  Net cycle-6 diff vs main: 0. Removes cycle-3 additions listed in the
  Files Modified section above.
- `lib/features/shell/app_shell.dart` restored to main tip via
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/shell/app_shell.dart`.
  Net cycle-6 diff vs main: 0. Removes cycle-3 additions listed in the
  Files Modified section above.

**Files NOT touched this cycle, per Manager cycle-6 step 3.** All cycle-4
RBAC files (`contributor_permissions.dart`, `band_permissions.dart`,
`role_management_sheet.dart`), all cycle-5 Quick Actions files
(`home_tab_content.dart`, `quick_actions_row.dart`), all
`lib/features/gear/*`, `test/features/gear/*`, all four gear migrations,
and `.github/agents/*.md` are untouched by cycle 6.

**Cycle-6 T1.1 scope contraction — Manager Option D decision.** After
the reverts, `side_drawer.dart` and `app_shell.dart` carry 0 diff vs
main and are no longer feature-touched files. Per Manager Option D
decision (cycle-6 finalization note), T1.1 is now scoped to the 7 files
this feature actually touches, dropping `side_drawer.dart` and
`app_shell.dart` from the command. This matches the standard treatment
of every other unmodified file in the repo: pre-existing lints in files
a feature doesn't touch are not that feature's gate. Not a deviation —
it's the same rule QA applies to every other file the feature leaves
untouched. Not procedural overhead — recording an 8-lint baseline as a
Deviation C would have been overhead purely to keep an outdated 9-item
gate list intact; contracting the gate to match the actual touched-files
scope is the cleaner and correct end state.

**Cycle-6 end state, feature-touched files (diff-vs-main):**

- `lib/features/gear/**` — all cycle-3-created files (unchanged).
- `lib/features/home/home_tab_content.dart` — cycle-5 Quick Actions
  wiring + 5 pre-existing lint sweeps (unchanged from cycle 5).
- `lib/features/home/widgets/quick_actions_row.dart` — cycle-5
  `onGear` / `showGear` additions + 1 pre-existing lint sweep
  (unchanged from cycle 5).
- `lib/features/members/permissions/band_permissions.dart` — cycle-4
  `canViewGear` body swap (unchanged from cycle 4).
- `lib/features/members/permissions/contributor_permissions.dart` —
  cycle-4 `canViewGear` sub-permission field (unchanged from cycle 4).
- `lib/features/members/widgets/role_management_sheet.dart` — cycle-4
  "Can view gear" toggle + `_permissionsEqual` extension (unchanged from
  cycle 4).
- `supabase/migrations/20260905201000_create_band_gear.sql` — base gear
  migration (unchanged from cycle 3).
- `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
  — cycle-4 sub-permission column (unchanged from cycle 4).
- `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
  — cycle-4 RPC fix (unchanged from cycle 4).
- `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
  — cycle-4 RLS helper + SELECT policy swap (unchanged from cycle 4).
- `test/features/gear/gear_item_test.dart` — cycle-3 model tests
  (unchanged).

## Analyzer Results

### Cycle 6 T1.1 — clean (7-item scope per Manager Option D)

Command run:

```
flutter analyze lib/features/gear lib/features/home/home_tab_content.dart lib/features/home/widgets/quick_actions_row.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 2.9s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. Scope reflects Manager Option D decision:
`side_drawer.dart` and `app_shell.dart` are byte-identical to main
(0 diff) and no longer feature-touched, so per the standard
"pre-existing lints in files a feature doesn't touch are not that
feature's gate" rule they are out of scope for this feature's T1.1.

### Cycle 6 T1.1 — earlier 9-item run (retained for evidence)

The earlier 9-item T1.1 run (executed before Manager's Option D
decision) surfaced 8 pre-existing info-severity lints resident on main
tip (`80bad0a`) in `side_drawer.dart` (2 × `use_colored_box`) and
`app_shell.dart` (3 × `prefer_const_constructors` + 3 ×
`avoid_redundant_argument_values`). Isolated audit against main-tip
content of both files returned identical output at the same locations,
confirming the lints pre-date the `feature/band-gear-management` branch
entirely. Manager Option D contracts the T1.1 command to the 7 files
this feature actually modifies, which resolves the gate cleanly without
introducing new suppression collateral or a new deviation.

### Cycle 5 T1.1 (retained for evidence, unchanged)

Command run:

```
flutter analyze lib/features/gear lib/features/home/widgets/side_drawer.dart lib/features/home/widgets/quick_actions_row.dart lib/features/home/home_tab_content.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart lib/features/shell/app_shell.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 9 items...
No issues found! (ran in 2.9s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`. `dart fix --dry-run` on both cycle-5-touched
files (`home_tab_content.dart`, `quick_actions_row.dart`) reports
`Nothing to fix!`.

### Cycle 4 T1.1 (retained for evidence)

Command run:

```
flutter analyze lib/features/gear lib/features/home/widgets/side_drawer.dart lib/features/members/permissions/band_permissions.dart lib/features/members/permissions/contributor_permissions.dart lib/features/members/widgets/role_management_sheet.dart lib/features/shell/app_shell.dart test/features/gear/gear_item_test.dart
```

Output:

```
Analyzing 7 items...
No issues found! (ran in 3.0s)
```

0 errors, 0 warnings, 0 infos — clean at every severity per
`analysis_options.yaml`.

## Test Results

### Cycle 6 T1.2

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output: `00:00 +5: All tests passed!` — 5/5 pass. Cycle 6 introduced no
code change to `lib/features/gear/**` or to the test file, so this run
confirms the revert did not regress the model-level tests transitively.

### Cycle 5 T1.2 — retained for evidence (unchanged)

Command run: `flutter test test/features/gear/gear_item_test.dart`

Output: `00:02 +5: All tests passed!` — 5/5 pass. No cycle-5 code paths
regressed the gear model unit tests.

### Cycle 5 T1.3 (not re-run)

Per Manager cycle-5 note: "Do NOT re-run T1.3 unless something breaks —
the accepted Deviation A still applies." Cycle 4's T1.3 result rolls
forward. No cycle-5 change touches the auth login screen or its test
file. No cycle-5 change adds any new widget test.

### Cycle 4 T1.2 / T1.3 (retained for evidence)

Commands run:

- `flutter test test/features/gear/gear_item_test.dart` (T1.2)
- `flutter test` (T1.3)

Results:

- T1.2 `flutter test test/features/gear/gear_item_test.dart`:
  `00:01 +5: All tests passed!` — 5/5 pass.
- T1.3 `flutter test`: `00:26 +218 -1: Some tests failed.` The single
  failure is:

  ```
  /Users/tonyholmes/apps/bandroadie/test/features/auth/login_screen_demo_button_test.dart: Test A: "Check Out the Demo Band" button is visible on LoginScreen
  ```

  This is Deviation A — the pre-existing, unrelated typo mismatch pre-
  approved by Tony's cycle-3 review. `lib/features/auth/login_screen.dart:657`
  renders `'Check out the demo band'` (lowercase `out`) while the test
  asserts title case; both files were last touched together in commit
  `5cd1996` and are unmodified by `feature/band-gear-management`. All 218
  other tests pass, satisfying the T1.3 gate per the plan's accepted-
  deviation clause.

## T1.4 Static SQL Evidence

Commands run in `supabase/migrations/`.

### 20260905201000_create_band_gear.sql (base, unchanged from cycle 3)

- `^CREATE POLICY`: **4** (SELECT / INSERT / UPDATE / DELETE)
- `ENABLE ROW LEVEL SECURITY`: **1**
- `^CREATE TRIGGER set_band_gear_updated_at`: **1**
- `^CREATE INDEX idx_band_gear_`: **2** (`_band_id`, `_owner_user_id`)
- `CONSTRAINT band_gear_owner_shape CHECK`: **1**
- `price_cents.*CHECK`: **1** (`price_cents INTEGER CHECK (price_cents IS
NULL OR price_cents >= 0)`)
- `REFERENCES public.bands(id) ON DELETE CASCADE`: **1**
- `REFERENCES public.users(id) ON DELETE SET NULL`: **2**
- `SECURITY DEFINER`: **0**
- `^GRANT|^REVOKE`: **0** (base migration relies solely on RLS)

### 20260906120000_add_can_view_gear_to_contributor_permissions.sql

- `ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE`:
  **1**
- Body is a single `ALTER TABLE public.contributor_permissions` statement;
  no other DDL/DML.

### 20260906120001_fix_update_member_role_can_view_gear.sql

- `CREATE OR REPLACE FUNCTION public.update_member_role`: **1**
- `^GRANT EXECUTE`: **1** (`GRANT EXECUTE ON FUNCTION
public.update_member_role(UUID, UUID, TEXT, JSONB) TO authenticated;`)
- `can_view_gear = COALESCE`: **1** (single new SET-clause line
  `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean,
FALSE),`)
- Header carries `LANGUAGE plpgsql / SECURITY DEFINER`; body opens with
  `SET search_path = public;` per Architect guardrail.

### 20260906120002_fix_band_gear_select_rbac.sql

- `CREATE OR REPLACE FUNCTION public.check_gear_view_permission`: **1**
- `SECURITY DEFINER`: **1**
- `SET search_path = public`: **1**
- `REVOKE ALL ON FUNCTION public.check_gear_view_permission(UUID) FROM
PUBLIC, anon`: **1**
- `GRANT EXECUTE ON FUNCTION public.check_gear_view_permission(UUID) TO
authenticated`: **1**
- `DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear`:
  **1**
- `CREATE POLICY "Band members can view gear" ON public.band_gear`: **1**
- `USING (public.check_gear_view_permission(band_id))`: **1**
- `FOR INSERT|FOR UPDATE|FOR DELETE`: **0** — INSERT / UPDATE / DELETE
  policies untouched, as required.

## T1.5 — Isolated Migration Apply-Check

**Deferred to Tier 2** per accepted Deviation B. The isolated apply-check
remains blocked by the repo-wide broken-migration-chain infra defect at
`073_fix_gig_responses_unique_constraint.sql` (see plan's KNOWN INFRA
BLOCKER section). Per the demo-band precedent
(`docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`), Tony
runs the migration apply at production apply time as part of the Rollout
Strategy. This deferral is pre-approved and does not block APPROVED.

## Code Efficiency/Bloat Check

Cycle 5 additions kept minimal by direct mirror of the shipped Financials
Quick Actions precedent:

- `quick_actions_row.dart` gains exactly one new field (`onGear`), one
  new bool field (`showGear` with default `true`), the corresponding
  constructor entries, one new term in `hasVisibleButtons`, and one new
  `_buildQuickActionButton` call block for the Gear button reusing the
  existing helper. No new helper, no new widget class, no new state, no
  duplicated helper. Searched `lib/` for pre-existing "quick action
  button" helpers before adding: `_buildQuickActionButton` inside
  `quick_actions_row.dart` is the sole helper and remains private;
  reusing it in place is the least-bloat option.
- `home_tab_content.dart` gains exactly: one new import
  (`../gear/gear_screen.dart`), one new `_handleOpenGear` method (7
  lines mirroring `_handleOpenFinancials`), one new `canViewGear` read
  from `permissionsAsync.when` (5 lines mirroring `canViewFinancials`),
  one new `canViewGear: canViewGear` argument at the `_buildContentState`
  call site, one new `required bool canViewGear,` parameter on
  `_buildContentState`, one new `|| canViewGear` term on `hasAnyButton`,
  and two new arguments (`onGear`, `showGear`) on the `QuickActionsRow`
  call. Searched `lib/` for pre-existing "open gear screen" navigation
  helpers before adding: no equivalent existed; `_handleOpenFinancials`
  is the closest sibling, and `_handleOpenGear` mirrors it exactly.
- Cycle-5 diff totals `+43` insertions, `-9` deletions across only the
  two files, well under any file-size target from the mode guardrails.
- Cycle-5 pre-existing lint sweep: 7 provably-safe no-op equivalents,
  each documented under the Cycle-5 pre-existing lint sweep note above.
  Every fix is what the analyzer literally suggests, not a discretionary
  rewrite.
- `dart fix --dry-run` on both cycle-5-touched files: `Nothing to fix!`.
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-5 edits.
- No new provider, no new notifier, no new named route, no new helper,
  no new barrel file, no new `_buildX()` single-use method, no new model
  field, no new imports beyond the required `gear_screen.dart`.

Cycle 4 additions kept minimal by direct mirror of already-shipped
precedent files:

- Migration 1 mirrors
  `20260604000001_add_can_view_financials_to_contributor_permissions.sql`
  verbatim except `financials → gear`. No new helper, no rewrite.
- Migration 2 mirrors
  `20260711120000_fix_update_member_role_can_view_financials.sql` verbatim
  with the single new SET-clause line for `can_view_gear`. `CREATE OR
REPLACE` is used because the RPC already exists; not a fresh function
  definition.
- Migration 3 mirrors
  `20260814120001_fix_financial_entries_select_rbac.sql` for shape; the
  `REVOKE ALL FROM PUBLIC, anon` + `GRANT EXECUTE ... TO authenticated`
  pattern is inline in the same file (avoids the two-step pattern the
  financials feature had to ship later per
  `20260822120001_revoke_anon_batch_2_rls_helpers.sql`).
- `contributor_permissions.dart` edit reuses the existing field-parity
  pattern (`canViewFinancials`); no new helper, no new `copyWith` layout —
  one field added per method / static.
- `band_permissions.dart` change is a body swap on the existing
  `canViewGear` getter matching the exact shape of `canViewSetlists` /
  `canViewCalendar` / `canViewMembers` / `canViewFinancials`. No new
  getter, no removal, `canManageGear` untouched.
- `role_management_sheet.dart` change is one extra
  `_buildPermissionToggle` call reusing the existing helper, and one extra
  boolean AND in `_permissionsEqual`. No new widget, no new state field.
- Searched `lib/` for pre-existing "contributor toggle" or "permissions-
  equal" helpers before adding: the existing `_permissionsEqual` in
  `role_management_sheet.dart` is the only such helper and remains
  private; extending it in place is the least-bloat option.
- `dart fix --dry-run` executed against the changed files; no automated
  fixes applicable.
- No `TODO` / `FIXME` / `debugPrint(` introduced in cycle-4 edits.
- No new helpers, no barrel files, no new providers, no `_buildX()` single-
  use methods, no dead SQL grants.

## Verification (manual steps performed)

Cycle 6:

- Read Manager cycle-6 note in full; confirmed cycle 6 is a revert-only
  cycle driven by Tony's cycle-5 QA-APPROVED review directive ("remove
  'Gear' from the menu. It should only be in the Quick Actions section")
  and that Manager preserved the cycle-6 Cycle Number at 6 (not reset).
- Confirmed pipeline.lock is held by Manager (`manager|feature/band-gear-management|2026-09-06T12:47:32Z`);
  cycle 6 did not acquire or release the lock (Manager cycle-6 note:
  "do NOT acquire your own lock").
- Ran `GIT_OPTIONAL_LOCKS=0 git branch --show-current` →
  `feature/band-gear-management`, and `GIT_OPTIONAL_LOCKS=0 git status
  --short` → four cycle-5 uncommitted files as expected (`docs/features/feature-band-gear-management/ENGINEER_REPORT.md`,
  `.../QA_REPORT.md`, `lib/features/home/home_tab_content.dart`,
  `lib/features/home/widgets/quick_actions_row.dart`) with no other
  tracked-file drift and no orphaned untracked work outside
  `docs/features/feature-band-gear-management/`.
- Verified main tip sha (`GIT_OPTIONAL_LOCKS=0 git rev-parse main` →
  `80bad0a9a1384919c8b939900ed842d27415d636`) matches the Manager
  cycle-6-stated `80bad0a`; HEAD sha (`26b5fed`) matches the Manager
  cycle-6-stated commit.
- Pre-revert grep in `lib/features/shell/app_shell.dart`
  (`grep -n 'GearScreen\|gear_screen'`) returned exactly two matches:
  the cycle-3 import on line 18 and the `_MenuDrawerLayer` push call on
  line 306. Confirmed no other symbol in `app_shell.dart` references
  `GearScreen`, so reverting to main removes both cleanly.
- Executed the two Manager-provided reverts:
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/home/widgets/side_drawer.dart`
  and
  `GIT_OPTIONAL_LOCKS=0 git checkout main -- lib/features/shell/app_shell.dart`.
  Post-revert `GIT_OPTIONAL_LOCKS=0 git diff --stat main` no longer lists
  either file — both are byte-identical to main tip.
- Ran T1.1 with Manager cycle-6's 9-item file list against the post-
  revert worktree — output surfaced 8 info-severity lints in
  `side_drawer.dart` and `app_shell.dart` (details in the **Analyzer
  Results** section above).
- Isolated-state audit to confirm the 8 lints are main-baseline, not
  Engineer-introduced: (i) `git stash push -u` the 6 modified files;
  (ii) `git checkout main -- side_drawer.dart app_shell.dart` (idempotent
  — they were already at main state); (iii)
  `flutter analyze lib/features/home/widgets/side_drawer.dart
  lib/features/shell/app_shell.dart` → identical 8-lint output at same
  locations. Then restored worktree via `git checkout HEAD -- ...` +
  `git stash pop`, verified `git diff --stat main` still shows the two
  files at zero net diff (post-revert state preserved).
- Ran T1.2 (`flutter test test/features/gear/gear_item_test.dart`) —
  5/5 pass, no regression from the revert.
- Did NOT re-run T1.3 per Manager cycle-6 step 6 (accepted Deviation A
  still applies; cycle 6 does not touch the auth login screen or its
  test file).
- Confirmed cycle-5 uncommitted files (`home_tab_content.dart`,
  `quick_actions_row.dart`) are untouched by cycle 6 — `git diff` on
  those two files matches the cycle-5 shape reported in cycle-5's
  ENGINEER_REPORT.md verbatim.
- Confirmed all cycle-4 RBAC files
  (`contributor_permissions.dart`, `band_permissions.dart`,
  `role_management_sheet.dart`) and all cycle-3 gear files
  (`lib/features/gear/*`, `test/features/gear/*`, all four gear
  migrations) are untouched by cycle 6.
- Confirmed `.github/agents/*.md` and `PR_BODY.md` are untouched by
  cycle 6.
- Ran final `GIT_OPTIONAL_LOCKS=0 git diff --stat main` — 20 files
  total changed vs main, all matching the pre-cycle-6 (cycle-5-shipped)
  set except that `side_drawer.dart` and `app_shell.dart` no longer
  appear in the diff list. Cycle 6's net change to the worktree is
  entirely subtractive.

Cycle 5:

- Read Manager cycle-5 note in full; confirmed the scope extension is
  in-branch, additive-only, and mirrors the shipped Financials Quick
  Actions precedent exactly.
- Confirmed `lib/features/home/` is not on `ARCHITECT_PLAN.md#L656`'s
  Files Off-Limits list.
- Verified via `grep -F 'Financials'` that neither
  `lib/features/home/home_screen.dart` nor
  `lib/features/home/widgets/empty_home_state.dart` wires Financials —
  cycle 5 matches that precedent and does not introduce Gear wiring
  where Financials has none.
- Confirmed `GearScreen` is exported by
  `lib/features/gear/gear_screen.dart:20` and is const-constructible
  (`class GearScreen extends ConsumerStatefulWidget { const
GearScreen({super.key}); ... }`), matching `FinancialsScreen`'s shape
  so `MaterialPageRoute(builder: (_) => const GearScreen())` compiles.
- Confirmed `perms.canViewGear` is defined in
  `lib/features/members/permissions/band_permissions.dart:157` (cycle-4
  work) so the new `canViewGear = permissionsAsync.when(...)` read has
  a defined getter to hit.
- Ran `flutter analyze` on the cycle-5 expanded file list — clean at
  every severity, `No issues found!`.
- Ran `flutter test test/features/gear/gear_item_test.dart` — 5/5 pass;
  no cycle-5 code path regresses the model-level tests.
- Ran `dart fix --dry-run` on `home_tab_content.dart` and
  `quick_actions_row.dart` — `Nothing to fix!` on both.
- Ran `dart format` on `home_tab_content.dart` and
  `quick_actions_row.dart` — 0 files changed.
- Confirmed `git diff --stat` shows exactly two files touched
  (`lib/features/home/home_tab_content.dart +33 -9`,
  `lib/features/home/widgets/quick_actions_row.dart +19 -0`); no other
  file changed.
- Confirmed `pipeline.lock` shows Manager holds the lock; this cycle did
  not acquire or release the lock (Manager cycle-5 note: "do NOT acquire
  your own lock").

Cycle 4:

- Read the Architect cycle-3 revision in full; confirmed the scope
  addition targets only the six files this cycle actually touches (three
  new migrations + three modified Dart files) and does not require any
  edit to files off-limits.
- Confirmed the three modified Dart files still compile clean via T1.1.
- Confirmed `_permissionsEqual` covers all seven contributor sub-permission
  fields (`canCreateGigs`, `canCreatePotentialGigsOnly`, `canViewSetlists`,
  `canViewCalendar`, `canViewMembers`, `canViewFinancials`, `canViewGear`)
  so dirty-detection tracks the new toggle.
- Confirmed the new "Can view gear" toggle in `role_management_sheet.dart`
  sits immediately after the existing "Can view financials" toggle and
  uses the same `_buildPermissionToggle` shape.
- Confirmed migration 3 does not include any `FOR INSERT` / `FOR UPDATE`
  / `FOR DELETE` policy statements — INSERT / UPDATE / DELETE gates
  remain the base migration's admin-and-member-only policies (`grep -Ec
"FOR INSERT|FOR UPDATE|FOR DELETE"` returned 0).
- Confirmed T1.4 static counts against all four migrations (evidence
  block above).
- Confirmed `pipeline.lock` shows Manager holds the lock; this cycle did
  not acquire or release the lock.
- Confirmed working tree carries only the six expected cycle-4 code
  additions/modifications plus untracked doc/gear scaffolding from cycle
  3; no out-of-plan file changed.

## Deviations From Plan

- **Cycle 6 revert-only in-branch scope contraction (authorized by
  Manager cycle-6 note).** The base `ARCHITECT_PLAN.md` Task 15 wired
  Gear surfacing via the side drawer (`side_drawer.dart` +
  `app_shell.dart`). Tony's cycle-5 QA-APPROVED state review directed
  removal of that surface: "remove 'Gear' from the menu. It should only
  be in the Quick Actions section." Cycle 6 reverts both files
  byte-identical to main tip. This subtracts Task 15 from the shipped
  feature surface; Gear now surfaces exclusively via the cycle-5 Quick
  Actions wiring. Manager cycle-6 note explicitly authorizes this scope
  contraction and provided the `git checkout main -- ...` commands used.
- **Cycle 6 T1.1 scope contraction to touched-files-only (authorized by
  Manager Option D cycle-6 finalization decision).** After the reverts,
  `side_drawer.dart` and `app_shell.dart` carry 0 diff vs main and are
  no longer feature-touched. T1.1 is now scoped to the 7 files this
  feature actually modifies. This is not a deviation from the
  ARCHITECT_PLAN — the plan's T1.1 command was updated in the same
  Manager cycle-6 finalization pass to reflect the actual touched-files
  scope. It's the same rule QA applies to every other file the feature
  leaves untouched: pre-existing lints in a file the feature doesn't
  modify are not that feature's gate. Recorded here for QA traceability
  because earlier cycles ran T1.1 against a broader 9-item list.
- **Cycle 5 in-branch scope extension (authorized by Manager cycle-5
  note).** The base `ARCHITECT_PLAN.md` did not list Quick Actions
  surfacing for Gear — Task 15 surfaced Gear only via the side drawer.
  Cycle 5 adds Quick Actions surfacing as an additive scope extension
  driven by Tony's PR #261 6b test finding, mirroring the shipped
  Financials Quick Actions precedent exactly. Manager cycle-5 note
  authorizes this: "The scope addition mirrors the existing Financials
  precedent — no architect re-diagnosis needed, but Engineer MUST
  document this as an in-branch cycle-5 additive scope extension in
  ENGINEER_REPORT.md and note that the base ARCHITECT_PLAN.md did not
  list Quick Actions surfacing." Files touched:
  `lib/features/home/widgets/quick_actions_row.dart` and
  `lib/features/home/home_tab_content.dart`. Neither is on the
  ARCHITECT_PLAN's Files Off-Limits list.
- **Cycle 5 pre-existing lint sweep in touched files (authorized by
  Engineer mode instruction).** The T1.1 expanded file list surfaced 7
  pre-existing info-level lints in
  `home_tab_content.dart` + `quick_actions_row.dart` that the cycle-4
  T1.1 command did not run against because those files were not in
  cycle 4's file list. Per the Engineer mode instruction "pre-existing
  violation in a file you did touch does — fix it if it's trivial, or
  report it if fixing it would exceed scope," all 7 were fixed as
  provably-safe no-op equivalents (documented under the Cycle 5
  pre-existing lint sweep note above). This is the minimum work
  necessary to satisfy Manager's cycle-5 T1.1 outcome directive of
  `No issues found`.
- **Deviation A (pre-approved by Tony's cycle-3 review).** Tier 1.3 full-
  suite regression carries exactly one failure at
  `test/features/auth/login_screen_demo_button_test.dart` Test A. Root
  cause: `lib/features/auth/login_screen.dart:657` renders `'Check out the
demo band'` (lowercase `out`) but the test asserts title-case
  `'Check Out the Demo Band'`. Both files were last touched together in
  commit `5cd1996` and are unmodified by `feature/band-gear-management`.
  Filed as a separate one-line typo/bug fix. Per the plan's accepted-
  deviation clause, this failure does not block Ready For QA; all 218
  other tests pass. Cycle 5 did not re-run T1.3 per Manager cycle-5 note
  ("Do NOT re-run T1.3 unless something breaks — the accepted Deviation
  A still applies"). Nothing in cycle 5 touches the auth login screen or
  its test.
- **Deviation B (pre-approved by Tony's cycle-3 review).** Tier 1.5
  isolated migration-apply check remains deferred to Tier 2 owner-run
  checks under the repo-wide broken-migration-chain infra blocker
  precedent used for
  `docs/features/interactive-demo-band-experience/QA_REPORT.md#L15`. Tony
  runs the migration apply at production apply time. This deferral does
  not block Ready For QA.

## Blockers Encountered

**Cycle 6 — none at finalization.** The cycle-6 T1.1 scope question
(originally raised as Options A / B / C / D against the earlier 9-item
gate list) was resolved by Manager's cycle-6 finalization decision:
Option D — contract T1.1 to the 7 files this feature actually modifies.
Rationale (Manager, verbatim in the cycle-6 finalization note): since
`side_drawer.dart` and `app_shell.dart` are now byte-identical to main,
they are no longer feature-touched files; T1.1 is a gate on files this
feature actually modifies, not a broader baseline audit — the same rule
QA applies to every other file the feature leaves untouched. The
ARCHITECT_PLAN's T1.1 command was updated in the same finalization pass
to the 7-item scope. The 7-item T1.1 command returned `No issues found`
at every severity (see **Analyzer Results** above); T1.2 gear tests
5/5 pass. No open blockers.

Cycle 5: none.

Cycle 4: none.

## Ready For QA

Yes. Cycle 6 T1.1 (7-item scope per Manager Option D) returned
`No issues found!` at every severity (0 errors, 0 warnings, 0 infos).
Cycle 6 T1.2 gear tests 5/5 pass. T1.3 not re-run per Manager cycle-6
step 6 (accepted Deviation A still applies). Cycle 4 T1.4 static SQL
evidence unchanged. Cycle 4 T1.5 remains deferred to Tier 2 per
accepted Deviation B. Cycle 6 net-new worktree change scoped to the
two byte-identical-to-main reverts of `side_drawer.dart` and
`app_shell.dart` (0 diff each vs main; both fall out of the feature's
touched-files set); cycle 5 modifications to `home_tab_content.dart`
and `quick_actions_row.dart` preserved unchanged.
