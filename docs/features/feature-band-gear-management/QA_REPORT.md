# QA Report - Band Gear Management

## Feature Slug

feature/band-gear-management

## Feature Title

Band Gear Management

## Cycle Number

4

## Final Verdict

APPROVED

## Validation Summary

Cycle 4 QA independently re-validated the uncommitted implementation on branch
`feature/band-gear-management` against the cycle-3 revised
`ARCHITECT_PLAN.md` (with the contributor visibility gate scope addition
folded in) and Engineer's cycle-4 `ENGINEER_REPORT.md` (Ready For QA: Yes).
All Tier 1 QA gates pass:

- T1.1 analyzer clean at every severity across the expanded 7-file list
  (includes `contributor_permissions.dart` and `role_management_sheet.dart`).
- T1.2 gear model tests 5/5 pass.
- T1.3 full suite is 218/219 with the single reproducible failure being
  the pre-approved Deviation A (title-case typo in
  `login_screen_demo_button_test.dart`, both files unmodified by this
  branch and sharing commit `5cd1996`).
- T1.4 static SQL grep counts match plan expectations exactly across all
  four migrations.
- T1.5 isolated managed-branch migration-apply is Deviation B — Deferred
  to Tier 2 per repo-wide broken-migration-chain infra blocker precedent.

Contributor visibility gate implementation matches the plan's do-not-slip
guardrails: the RPC persists `can_view_gear` in its SET clause (the exact
bug that shipped for financials and had to be fixed in
`20260711120000_fix_update_member_role_can_view_financials.sql` is
prevented here), and `check_gear_view_permission` is a properly-locked
`SECURITY DEFINER` helper that gates only SELECT — INSERT / UPDATE / DELETE
policies are untouched.

No secrets, no `TODO` / `FIXME` / `debugPrint(` in the cycle-4 diff, no
off-limits files touched, no unauthorized architectural changes. Verdict
type: code-path analysis + command execution (analyzer, tests, SQL static
checks). No runtime app / device / simulator verification performed —
that's Tony's Tier 2 gate at apply time per the plan.

## Architect Scope Review

- Branch slug: `feature/band-gear-management` (PASS).
- Doc slugs match branch:
  - [docs/features/feature-band-gear-management/ARCHITECT_PLAN.md](docs/features/feature-band-gear-management/ARCHITECT_PLAN.md) (PASS)
  - [docs/features/feature-band-gear-management/ENGINEER_REPORT.md](docs/features/feature-band-gear-management/ENGINEER_REPORT.md) (PASS)
- Planned created files observed (12 total: 7 code + 4 migration + 1 test):
  - supabase/migrations/20260905201000_create_band_gear.sql (cycle-3 base)
  - supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql (cycle-4 new)
  - supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql (cycle-4 new)
  - supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql (cycle-4 new)
  - lib/features/gear/models/gear_item.dart
  - lib/features/gear/gear_repository.dart
  - lib/features/gear/gear_controller.dart
  - lib/features/gear/gear_screen.dart
  - lib/features/gear/widgets/gear_row.dart
  - lib/features/gear/widgets/gear_form_sheet.dart
  - lib/features/gear/widgets/gear_empty_state.dart
  - test/features/gear/gear_item_test.dart
- Planned modified files observed (5 total):
  - lib/features/members/permissions/contributor_permissions.dart (cycle-4 new field)
  - lib/features/members/permissions/band_permissions.dart (cycle-4 body swap + cycle-3 getters)
  - lib/features/members/widgets/role_management_sheet.dart (cycle-4 toggle)
  - lib/features/home/widgets/side_drawer.dart (cycle-3, unchanged)
  - lib/features/shell/app_shell.dart (cycle-3, unchanged)
- Off-limits edits detected: none. Verified by `git status --short`
  filtered to `.github/agents/` (agent-file modifications are outside
  this QA's authority per user directive and this feature's plan;
  Manager pipeline owns those). No touches to `lib/main.dart`,
  `pubspec.yaml`, `analysis_options.yaml`, `ios/`, `android/`,
  `macos/`, `web/`, or any other feature folder.
- New dependencies detected: none.
- Untracked doc scaffolding under `docs/features/feature-band-gear-management/`
  is the expected feature workspace (`ARCHITECT_PLAN.md`,
  `ENGINEER_REPORT.md`, and this `QA_REPORT.md`) — not a scope issue.

## Completeness Check

Every Architect task in the plan's Engineer Task Breakdown is complete:

- Task 1 (base migration): file present at
  `supabase/migrations/20260905201000_create_band_gear.sql`, byte-shape
  matches plan (table, 4 policies, trigger, 2 indexes,
  `band_gear_owner_shape` CHECK, `price_cents >= 0` CHECK, all FKs with
  documented cascade behavior).
- Task 2 (Migration 1 of 3 — sub-permission column): single-line
  `ALTER TABLE ... ADD COLUMN IF NOT EXISTS can_view_gear BOOLEAN NOT NULL DEFAULT FALSE`.
  Direct mirror of the financials precedent.
- Task 3 (Migration 2 of 3 — RPC fix): full-body `CREATE OR REPLACE
FUNCTION public.update_member_role(UUID, UUID, TEXT, JSONB)` with
  `can_view_gear = COALESCE((p_sub_permissions->>'can_view_gear')::boolean, FALSE)`
  explicitly present in the `UPDATE public.contributor_permissions SET`
  clause. This was the do-not-slip step per plan; verified by grep
  count = 1.
- Task 4 (Migration 3 of 3 — RLS helper + SELECT swap):
  `check_gear_view_permission(UUID)` `SECURITY DEFINER` with
  `SET search_path = public`, inline `REVOKE ALL ... FROM PUBLIC, anon`,
  inline `GRANT EXECUTE ... TO authenticated`, then
  `DROP POLICY IF EXISTS "Band members can view gear"` + recreate
  `USING (public.check_gear_view_permission(band_id))`. INSERT / UPDATE /
  DELETE policies are NOT touched (grep for `FOR INSERT|FOR UPDATE|FOR DELETE`
  in the file = 0).
- Tasks 5–8 (gear model / repository / controller / permission getters):
  files present, imports contained to peer/shared code paths only.
- Task 9 (sub-permission Dart field): `ContributorPermissions.canViewGear`
  added with `fromJson` / `toJson` / `copyWith` / `allEnabled` /
  `allDisabled` / `toString` parity to `canViewFinancials`, default `false`
  in immutable constructor.
- Task 10 (`BandPermissions.canViewGear` body swap): getter body now
  returns `true` for admin/member and `subPermissions?.canViewGear ?? false`
  for contributor. `canManageGear` remains `isAdmin || isMember`
  (verified: unchanged).
- Task 11 (Role Management sheet toggle): new
  `_buildPermissionToggle(label: 'Can view gear', ...)` placed
  immediately after the existing "Can view financials" toggle in
  [lib/features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart#L376);
  `_permissionsEqual` extended with `a.canViewGear == b.canViewGear` at
  [line 129](lib/features/members/widgets/role_management_sheet.dart#L129).
- Tasks 12–15 (widgets, screen, drawer/shell wiring): files present with
  correct import paths; drawer adds one `DrawerNavItem` "Gear" gated on
  optional `onGearTap`; shell wires `Navigator.of(context).push(
MaterialPageRoute(builder: (_) => const GearScreen()))`.
- Task 16 (model unit test): `test/features/gear/gear_item_test.dart`
  present with 5 cases (round-trip both `owner_type` values,
  `GearOwnerType.fromDbValue` mapping, owner-shape assert invariant).
- Task 17 (analyzer + tests green): verified below.

No partial implementations. No missing edge cases the plan specified.

## Behavior Verification

Verification type: code-path analysis + static SQL analysis + command
execution (analyzer, tests, grep counts). **No runtime app / device /
simulator verification performed** — that's Tier 2 owner-run at apply
time per the plan.

Contributor visibility gate — code-path findings:

- Client gate:
  [`BandPermissions.canViewGear`](lib/features/members/permissions/band_permissions.dart#L155)
  branches `if (isAdmin || isMember) return true;`, then contributor
  branch `return subPermissions?.canViewGear ?? false;`. Fail-closed if
  `subPermissions` is null. Matches plan spec exactly.
- Client write gate:
  [`BandPermissions.canManageGear`](lib/features/members/permissions/band_permissions.dart#L166)
  is `isAdmin || isMember` — unchanged, contributors always blocked from
  writes regardless of toggle.
- Server SELECT gate: helper `check_gear_view_permission(band_id)` in
  Migration D runs admin/member always-pass then
  `SELECT COALESCE(cp.can_view_gear, FALSE)` from the contributor's
  `contributor_permissions` row. Default `FALSE` when row is absent.
- Server SELECT policy: `DROP POLICY IF EXISTS "Band members can view gear"
ON public.band_gear;` then `CREATE POLICY ... FOR SELECT USING
(public.check_gear_view_permission(band_id));` — policy name preserved
  verbatim so name-based structural checks still match.
- Server INSERT / UPDATE / DELETE gates: untouched (grep confirms no
  `FOR INSERT|FOR UPDATE|FOR DELETE` in Migration D). Base migration's
  admin+member-only policies remain in force.
- Server RPC persistence: `update_member_role` UPDATE SET clause
  includes `can_view_gear = COALESCE(...FALSE)` on the same line-shape as
  `can_view_financials`. This is the exact do-not-slip guardrail from
  the plan; the equivalent bug had to be patched for financials in
  `20260711120000_fix_update_member_role_can_view_financials.sql` and
  is prevented here.
- Toggle UI: `role_management_sheet.dart` adds one
  `_buildPermissionToggle` for "Can view gear" using the same
  `_subPermissions.copyWith(canViewGear: v)` shape as the financials
  toggle. `_permissionsEqual` extended so dirty-state detection covers
  the new field. Save/load already flow through `updateRole` → RPC and
  `fetchContributorPermissions`, so no repo/controller edits were
  required (correct per plan).

Feature-general code-path findings:

- Gear navigation is wired from drawer callback to `MaterialPageRoute`
  push of `GearScreen`; matches Settings / Tips / Bug Report drawer-push
  pattern.
- Form/model enforce owner-shape rules (member-owned requires member
  id; band-owned clears member id); DB CHECK constraint
  `band_gear_owner_shape` backs it up.
- Owner picker source uses `membersProvider` and filters to active
  members only.
- Band switch listener resets and reloads gear state.
- Feature remains inventory-only; no notifications, deep links, tabs,
  routes, or platform config added.

## Regression Check

**Regression risk: LOW.**

Every affected system from the plan's System Impact Map reviewed against
the actual diff:

| System                                  | Rating | Verification                                                                                                                                                              |
| --------------------------------------- | :----: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Auth / Session                          |  LOW   | No init-order, PKCE, deep-link, or magic-link touch. `login_screen.dart` unmodified by this branch (git log confirms shared commit `5cd1996` with the failing test file). |
| Routing                                 |  LOW   | No `onGenerateRoute` change; `GearScreen` push-only via `MaterialPageRoute`.                                                                                              |
| Bottom nav / AppShell tab structure     |  LOW   | `visibleTabs`, `IndexedStack`, `visibleNavItems` untouched. Only `_MenuDrawerLayer` gained one callback wire.                                                             |
| Side drawer                             |  LOW   | Additive `onGearTap` optional callback plumbed through three drawer widgets; conditional `DrawerNavItem` gated on non-null `onGearTap`. Backward-compatible default.      |
| RBAC / `BandPermissions`                |  LOW   | `canViewGear` body swap follows the exact shape of `canViewFinancials` (same file). `canManageGear` unchanged. No signature change on any getter.                         |
| RBAC / `ContributorPermissions`         |  LOW   | Additive `canViewGear` field with full parity to `canViewFinancials`. `fromJson` / `toJson` / `copyWith` / `allEnabled` / `allDisabled` / `toString` all updated.         |
| Members / Role Management sheet         |  LOW   | One additive `_buildPermissionToggle` next to financials; `_permissionsEqual` extended by one AND-clause. Save/load flow unchanged.                                       |
| Members RPC (`update_member_role`)      |  LOW   | Signature `(UUID, UUID, TEXT, JSONB)` unchanged; only one added SET-clause line for `can_view_gear`. `can_view_financials` line preserved (grep count = 1).               |
| `contributor_permissions` table         |  LOW   | Additive column, `NOT NULL DEFAULT FALSE` fills existing rows atomically; no backfill.                                                                                    |
| Bands / `activeBandProvider`            |  LOW   | Read-only dependency; provider unchanged.                                                                                                                                 |
| Gigs / Rehearsals / Setlists / etc.     |  LOW   | Peer features untouched.                                                                                                                                                  |
| Notifications                           |  LOW   | v1 gear does not fan out; `notifications.type` enum unchanged.                                                                                                            |
| Init order                              |  LOW   | `main.dart` not modified.                                                                                                                                                 |
| Platforms (iOS / Android / macOS / Web) |  LOW   | Pure Flutter + Supabase; no platform-conditional code added. Native config directories untouched.                                                                         |

No `setState` after async gap issues, controller/FocusNode disposal
issues, or rebuild-storm triggers introduced by this diff (verified by
reading the modified Dart files and confirming the analyzer's
`use_build_context_synchronously` (error-level) check passed).

## Database Safety

Static SQL evidence per plan T1.4 — grep counts run against all four
migration files. Every count matches plan expectations exactly.

### Migration A — `supabase/migrations/20260905201000_create_band_gear.sql`

| Check                                               | Expected | Observed |
| --------------------------------------------------- | :------: | :------: |
| `SECURITY DEFINER`                                  |    0     |    0     |
| `GRANT` / `REVOKE`                                  |    0     |    0     |
| `ENABLE ROW LEVEL SECURITY`                         |    1     |    1     |
| `^CREATE POLICY`                                    |    4     |    4     |
| Policy predicate refs `band_gear` (recursion guard) |    0     |    0     |
| `band_gear_owner_shape`                             |    1     |    1     |
| `price_cents IS NULL OR price_cents >= 0`           |    1     |    1     |
| `REFERENCES public.bands(id) ON DELETE CASCADE`     |    1     |    1     |
| `REFERENCES public.users(id) ON DELETE SET NULL`    |    2     |    2     |
| Redeclares `update_updated_at_column`               |    0     |    0     |
| `set_band_gear_updated_at` trigger present          |    1     |    1     |
| `idx_band_gear_*` indexes                           |    2     |    2     |
| Base SELECT policy present (superseded by D)        |    1     |    1     |

### Migration B — `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`

| Check                                                        | Expected | Observed |
| ------------------------------------------------------------ | :------: | :------: |
| `^ALTER TABLE`                                               |    1     |    1     |
| References `contributor_permissions`                         |   ≥ 1    |    2     |
| References `can_view_gear`                                   |   ≥ 1    |    2     |
| `can_view_gear BOOLEAN NOT NULL DEFAULT FALSE` (fail-closed) |    1     |    1     |
| `ADD COLUMN IF NOT EXISTS` (idempotent)                      |    1     |    1     |
| New function / policy                                        |    0     |    0     |
| `SECURITY DEFINER`                                           |    0     |    0     |

### Migration C — `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`

| Check                                                   | Expected | Observed |
| ------------------------------------------------------- | :------: | :------: |
| `^CREATE OR REPLACE FUNCTION public.update_member_role` |    1     |    1     |
| `update_member_role(` signature occurrences             |   ≥ 2    |    2     |
| `SECURITY DEFINER`                                      |    1     |    1     |
| `SET search_path = public`                              |    1     |    1     |
| **SET clause writes `can_view_gear`** (do-not-slip)     |    1     |    1     |
| `can_view_gear` fail-closed `FALSE` default             |    1     |    1     |
| `can_view_financials` line preserved                    |    1     |    1     |
| `GRANT EXECUTE ... TO authenticated`                    |    1     |    1     |
| New `^CREATE POLICY` (unrelated policy churn)           |    0     |    0     |

### Migration D — `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`

| Check                                                                                        | Expected | Observed |
| -------------------------------------------------------------------------------------------- | :------: | :------: |
| `^CREATE OR REPLACE FUNCTION ... check_gear_view_permission(UUID)`                           |    1     |    1     |
| `SET search_path = public`                                                                   |   ≥ 1    |    1     |
| `RETURNS BOOLEAN`                                                                            |    1     |    1     |
| `can_view_gear` references                                                                   |   ≥ 1    |    4     |
| `IN ('admin', 'member')` role list                                                           |   ≥ 1    |    1     |
| `REVOKE ALL ... FROM PUBLIC, anon`                                                           |    1     |    1     |
| `GRANT EXECUTE ... TO authenticated`                                                         |    1     |    1     |
| `DROP POLICY IF EXISTS "Band members can view gear" ON public.band_gear`                     |    1     |    1     |
| `USING (public.check_gear_view_permission(band_id))`                                         |    1     |    1     |
| New `^ALTER TABLE` / `^CREATE TRIGGER`                                                       |    0     |    0     |
| **`FOR INSERT` / `FOR UPDATE` / `FOR DELETE` statements (write policies MUST be untouched)** |    0     |    0     |

Isolated migration-apply (T1.5 / owner-run grants sanity):

- **Deferred to Tier 2** per pre-approved Deviation B. See
  [Deviations](#deviations) below.
- Consequently, `has_function_privilege` verification of the new
  `check_gear_view_permission(UUID)` helper (my QA guardrail for new
  `SECURITY DEFINER` functions) is deferred to Tony's Tier 2 owner-run
  checks at apply time — the plan's Tier 2 punch list (steps 5–7)
  already specifies the exact `has_function_privilege('authenticated',
..., 'EXECUTE')` / `has_function_privilege('anon', ...)` /
  `has_function_privilege('PUBLIC', ...)` triple that Tony runs. The
  inline `REVOKE ALL ... FROM PUBLIC, anon` + `GRANT EXECUTE ... TO
authenticated` pair in Migration D is code-confirmed correct; runtime
  ACL confirmation is Tony's responsibility.

## Analyzer Results

Command run (verbatim from T1.1 in the plan, expanded to include
`contributor_permissions.dart` and `role_management_sheet.dart` per
cycle-4 scope):

```
flutter analyze lib/features/gear \
  lib/features/home/widgets/side_drawer.dart \
  lib/features/members/permissions/band_permissions.dart \
  lib/features/members/permissions/contributor_permissions.dart \
  lib/features/members/widgets/role_management_sheet.dart \
  lib/features/shell/app_shell.dart \
  test/features/gear/gear_item_test.dart
```

Result:

```
Analyzing 7 items...
No issues found! (ran in 3.1s)
```

**PASS** — clean at every severity (0 errors, 0 warnings, 0 infos) per
`analysis_options.yaml` policy.

## Test Results

### T1.2 — Feature unit tests

```
flutter test test/features/gear/gear_item_test.dart
```

Result: **PASS 5/5**.

- GearOwnerType fromDbValue maps known values
- GearOwnerType fromDbValue falls back to band for unknown values
- GearItem fromJson/toJson round-trip for band-owned item
- GearItem fromJson/toJson round-trip for member-owned item
- GearItem constructor enforces owner shape invariant

### T1.3 — Full-suite regression guard

```
flutter test
```

Result: **PASS with one accepted deviation.**

- Second full-suite run (deterministic baseline): **218 passed, 1 failed**.
- Single reproducible failure: `test/features/auth/login_screen_demo_button_test.dart`
  `Test A: "Check Out the Demo Band" button is visible on LoginScreen` —
  the pre-approved Deviation A.
- Evidence Deviation A is unrelated to this branch:
  `GIT_OPTIONAL_LOCKS=0 git log --oneline -1 -- lib/features/auth/login_screen.dart
test/features/auth/login_screen_demo_button_test.dart` returned
  `5cd1996 feat(demo): interactive demo band experience with isolated
anonymous sessions (#255)` — both files last touched together in
  commit `5cd1996` and unmodified by `feature/band-gear-management`.
  `login_screen.dart:657` renders `'Check out the demo band'`
  (lowercase `out`) versus the test's title-case assertion.
- Intermittent flake (called out for Tony's awareness, not a blocker):
  the **first** full-suite run of this cycle also showed
  `Test B: retired 7-tap easter-egg hint text is not present` failing
  in the same file. Running the same test file in isolation shows Test B
  passing, and the deterministic second full-suite run also had Test B
  passing. This is pre-existing test-isolation pollution in a file
  unmodified by this branch (same commit `5cd1996`), not a regression.
  Same file, same commit lineage — same accepted-deviation scope.

## Diff Safety Review

- **Secrets / API keys:** none detected in cycle-4 diff scope
  (`grep -rEnI 'sk_live_|pk_live_|-----BEGIN|api[_-]?key=...|password=...'`
  over all touched files returned zero hits).
- **`TODO` / `FIXME` / `debugPrint(` scan:** none in cycle-4 diff scope
  (`grep -rEn 'TODO|FIXME|debugPrint\('` over `lib/features/gear`, the
  four new migrations, and `test/features/gear` returned zero hits).
- **Accidental destructive edits / deletions:** none. `git diff --numstat`
  shows only additive edits on modified files (net +26/-4, +13/-0,
  +8/-2, +10/-2, +13/-0 — the `-4` and `-2` deletions are
  substitutions verified below).
- **Leftover test scaffolding:** none.
- **Off-limits touches:** none. Manager-tracked `.github/agents/*.md`
  modifications are outside this QA cycle's authority per user
  directive and are the Manager pipeline's responsibility.

## Change Budget Review

New file count vs. plan:

- Plan expected: 11 net-new (7 code + 3 migration + 1 test), measured
  from cycle-3 baseline. From HEAD (main): 12 net-new (7 code +
  4 migration + 1 test — includes cycle-3 base migration
  `20260905201000_create_band_gear.sql` which was uncommitted in
  cycle 3). Consistent with plan intent — cycle-4 added exactly 3
  net-new migrations on top of cycle-3's uncommitted work.

New-file line counts vs. plan Change Budget table:

| File                                                                                | Budget       | Actual | Status                 |
| ----------------------------------------------------------------------------------- | ------------ | :----: | ---------------------- |
| supabase/migrations/20260905201000_create_band_gear.sql (already present)           | 0 (cycle-3)  |   88   | Unchanged from cycle 3 |
| supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql | +6 to +12    |   6    | Within                 |
| supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql         | +100 to +115 |  106   | Within                 |
| supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql                    | +55 to +80   |   69   | Within                 |
| lib/features/gear/models/gear_item.dart                                             | +90 to +130  |   86   | Slightly under         |
| lib/features/gear/gear_repository.dart                                              | +130 to +180 |  105   | Under                  |
| lib/features/gear/gear_controller.dart                                              | +130 to +180 |  127   | Slightly under         |
| lib/features/gear/gear_screen.dart                                                  | +200 to +300 |  250   | Within                 |
| lib/features/gear/widgets/gear_row.dart                                             | +80 to +130  |   94   | Within                 |
| lib/features/gear/widgets/gear_form_sheet.dart                                      | +250 to +380 |  487   | ~1.28x max — noted     |
| lib/features/gear/widgets/gear_empty_state.dart                                     | +40 to +70   |   72   | ~1.03x max — trivial   |
| test/features/gear/gear_item_test.dart                                              | +60 to +100  |   85   | Within                 |

Modified-file churn (`git diff --numstat` vs. HEAD):

| File                                                          | Budget     | Actual   | Status                                                                                                                      |
| ------------------------------------------------------------- | ---------- | -------- | --------------------------------------------------------------------------------------------------------------------------- |
| lib/features/members/permissions/contributor_permissions.dart | +8 to +14  | +8 / -2  | Within (deletions are substitutions in `allDisabled` — see Suggestion S1)                                                   |
| lib/features/members/permissions/band_permissions.dart        | +5 to +10  | +13 / 0  | ~1.3x max — combines cycle-3 getter add + cycle-4 body swap; still under 1.5x                                               |
| lib/features/members/widgets/role_management_sheet.dart       | +10 to +16 | +10 / -2 | Within (net +8, the `-2` line is `fullWidth: false,` removed — see S4)                                                      |
| lib/features/home/widgets/side_drawer.dart (cycle-3 applied)  | 0          | +26 / -4 | Cycle-3 uncommitted delta; `Container→ColoredBox` swaps required by `use_colored_box` info-lint to keep T1.1 clean — see S5 |
| lib/features/shell/app_shell.dart (cycle-3 applied)           | 0          | +13 / 0  | Cycle-3 uncommitted delta; four `// ignore:` suppressions on pre-existing widgets — see S2                                  |

Assessment: no file exceeds the 1.5x tolerance for Warning-level bloat,
and no new file / public class / dependency outside the plan-declared
list. `gear_form_sheet.dart` at 487 vs. 380 max is 1.28x — noted, not
a Warning. Additional pre-existing symbol reuse verified: `GearItem`,
`GearOwnerType`, `NoBandSelectedGearError`, `GearRepository`,
`GearState`, `GearNotifier`, `gearProvider`, `GearScreen`, `GearRow`,
`GearFormSheet`, `GearEmptyState`, `check_gear_view_permission`, and
`contributor_permissions.can_view_gear` all match the plan's expected
new-symbol list — none is a duplicate of an existing helper.

## Code Efficiency Review

- `NoBandSelectedGearError` pattern is consistent with existing
  repository-boundary error types (`NoBandSelectedContactsError`, etc.).
- Owner-label helper and formatting logic are straightforward and
  feature-local. No cross-feature helper leaks.
- No extra provider / notifier / dependency introduced beyond plan.
- Migrations are direct mirrors of already-shipped precedents
  (`20260604000001`, `20260711120000`, `20260814120001`) — same shape,
  same guardrails, same file skeleton with `financials → gear`
  substitution. No divergent structure.
- No barrel files, no single-use `_buildX()` methods, no dead code,
  no unused fields.
- `dart fix --dry-run` was run by Engineer per report; no automated
  fixes remained.

## Manual Verification Punch List

The plan's Tier 2 owner-run section (see
[ARCHITECT_PLAN.md § Tier 2](docs/features/feature-band-gear-management/ARCHITECT_PLAN.md))
already specifies the exact numbered live-app RBAC walkthrough (steps
8–14) with expected results per step. QA does not re-state or replace
that block — Tony executes it verbatim at apply time. Two additional
QA-generated items for Tony's Tier 2 pass:

1. **Migration apply order enforcement (Deviation B).** Apply the four
   migrations in this exact order using Tony's standard `supabase db
push --linked` or equivalent — applying Migration D before Migration
   B errors on `can_view_gear` column reference in the helper body:
   1. `supabase/migrations/20260905201000_create_band_gear.sql`
   2. `supabase/migrations/20260906120000_add_can_view_gear_to_contributor_permissions.sql`
   3. `supabase/migrations/20260906120001_fix_update_member_role_can_view_gear.sql`
   4. `supabase/migrations/20260906120002_fix_band_gear_select_rbac.sql`
      Expected: each `psql`/CLI reports one `CREATE TABLE` + 2 `CREATE
INDEX` + 1 `ALTER TABLE` + 4 `CREATE POLICY` + 1 `CREATE TRIGGER`
      for A; one `ALTER TABLE` for B; one `CREATE OR REPLACE FUNCTION` +
      one `GRANT` for C; one `CREATE OR REPLACE FUNCTION` + one `REVOKE`
   - one `GRANT` + one `DROP POLICY` + one `CREATE POLICY` for D. No
     errors, no warnings.
2. **`has_function_privilege` triple check on the new helper**
   (already specified verbatim in the plan's Tier 2 step 5 — repeated
   here for the punch list so Tony has one flat checklist):
   ```sql
   SELECT
     has_function_privilege('authenticated',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE') AS authenticated_can_execute,   -- expect: t
     has_function_privilege('anon',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE') AS anon_can_execute,             -- expect: f
     has_function_privilege('PUBLIC',
       'public.check_gear_view_permission(uuid)'::regprocedure,
       'EXECUTE') AS public_can_execute;          -- expect: f
   ```
   Rationale: `has_function_privilege` is the only reliable check —
   a `PUBLIC` grant would satisfy a role-specific check for every role
   even without an explicit named grant.

## Deviations

Both deviations pre-approved by Tony's cycle-3 BLOCKED-escalation
review and folded into the plan's Verification Plan section under
"Accepted deviations (cycle-4 QA report MUST record these)".

**Deviation A — Tier 1.3 pre-existing typo failure. Accepted.**

- Failing case: `test/features/auth/login_screen_demo_button_test.dart`
  `Test A: "Check Out the Demo Band" button is visible on LoginScreen`.
- Root cause: `lib/features/auth/login_screen.dart:657` renders
  `'Check out the demo band'` (lowercase `out`) versus the test's
  title-case assertion `'Check Out the Demo Band'`.
- QA verification: `GIT_OPTIONAL_LOCKS=0 git log --oneline -1 --
lib/features/auth/login_screen.dart
test/features/auth/login_screen_demo_button_test.dart` returned the
  single expected shared commit `5cd1996`. Both files unmodified by
  `feature/band-gear-management`.
- Impact: 218/219 full-suite pass; the one failure is this specific
  case. Does not block APPROVED per plan.
- Follow-up: separate one-line typo/bug fix outside this feature's
  scope, per plan.

**Deviation B — Tier 1.5 deferral to Tier 2. Accepted.**

- Rationale: The isolated managed-Supabase-branch migration-apply
  procedure remains blocked project-wide by the historical migration
  chain defect at `073_fix_gig_responses_unique_constraint.sql`. Every
  fresh managed branch enters `MIGRATIONS_FAILED` on that boundary.
  This is a repo-level infra defect, not a defect of this feature.
- Precedent: same accepted-deferral treatment as
  [interactive-demo-band-experience/QA_REPORT.md#L15](docs/features/interactive-demo-band-experience/QA_REPORT.md#L15).
- QA action: T1.5 marked **DEFERRED to Tier 2** in this report; not
  executed in cycle 4. Tier 2 owner-run migration-apply + full RLS/
  RPC/helper behavior matrix runs against production at Tony's
  standard apply time per the plan's Tier 2 section and Rollout
  Strategy. Does not block APPROVED per plan.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

1. **S1 — `ContributorPermissions.allDisabled` literal drift.**
   - Issue Category: `code-quality`
   - Evidence: plan spec says "`allDisabled` static includes
     `canViewGear: false`", and pre-existing state had
     `canViewFinancials: false` explicitly. Engineer's implementation
     removed both explicit `false` assignments and relies on the
     immutable-constructor default `false` for `canViewGear` and
     `canViewFinancials`. Diff line:
     `- canViewFinancials: false,` in
     [contributor_permissions.dart](lib/features/members/permissions/contributor_permissions.dart#L36-L40).
   - Impact: functionally identical (constructor default is `false`
     for both fields). Reads slightly less explicit than the plan
     literal.
   - Rationale for Suggestion (not Warning): behavior parity with plan
     is preserved; no user-visible impact.

2. **S2 — `app_shell.dart` uses `// ignore:` to satisfy `prefer_const_constructors`
   / `avoid_redundant_argument_values` on pre-existing widgets rather
   than adding `const`.**
   - Issue Category: `code-quality`
   - Evidence: four new comment lines in
     [app_shell.dart](lib/features/shell/app_shell.dart) targeting
     `Positioned`, `NativeAppBanner`, `Center`, and
     `CircularProgressIndicator` — three of these widgets are
     pre-existing code paths the engineer only opened to add
     `onGearTap`. Necessary because T1.1 requires analyzer clean at
     every severity, and `analysis_options.yaml`'s `linter/rules:`
     block has these lints enabled.
   - Ideal fix would be to add `const` keywords to those constructor
     calls; the shortcut of `// ignore: ...` keeps the analyzer clean
     without the additional const-ification churn.
   - Rationale for Suggestion: scope-appropriate given the alternative
     (const-ifying) would touch more unrelated pre-existing code
     paths; the plan's off-limits list doesn't forbid `// ignore:`.

3. **S3 — `gear_form_sheet.dart` at 487 lines vs. plan max 380 (1.28x).**
   - Issue Category: `code-quality`
   - Evidence: `wc -l` = 487; plan Change Budget range 250-380.
   - Rationale for Suggestion (not Warning): within the 1.5x tolerance
     from the QA guardrail. The form is feature-rich (date pickers,
     member picker, currency input formatting, dual-mode owner
     control, validation, save + delete-with-confirmation) — none of
     which is obvious bloat.

4. **S4 — `role_management_sheet.dart` removes `fullWidth: false,` on
   the destructive remove-member `AppButton`.**
   - Issue Category: `code-quality`
   - Evidence: diff line `- fullWidth: false,` in
     [role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart).
     Not authorized by the plan's file-modification instructions for
     this file (plan only calls for the "Can view gear" toggle and the
     `_permissionsEqual` extension).
   - Impact: minor unrelated churn to satisfy
     `avoid_redundant_argument_values` info-level lint. Removes an
     explicit default value; behavior unchanged.
   - Rationale for Suggestion: single-line lint-satisfying edit; no
     user-visible impact. Could have been a `// ignore:` line-comment
     instead to keep the change purely additive.

5. **S5 — `side_drawer.dart` includes 4 `Container(color: ...)` →
   `ColoredBox(color: ...)` substitutions unrelated to gear.**
   - Issue Category: `code-quality`
   - Evidence: 4 substitutions at 2 sites in
     [side_drawer.dart](lib/features/home/widgets/side_drawer.dart)
     inside `DrawerOverlay` and `DrawerOverlayContent`. Pre-existing
     `Container(color: ...)` widgets swapped to satisfy
     `use_colored_box` info-lint.
   - Impact: no behavior change; `ColoredBox` and `Container(color:)`
     render identically at the paint layer. Necessary because T1.1
     requires the file analyzer-clean.
   - Rationale for Suggestion: same scope-creep-vs-analyzer-clean
     trade-off as S2; scope-appropriate.

## Operational Verification

- **Pipeline lock:** Manager-held lock instruction honored — QA did
  **not** acquire, modify, or release `pipeline.lock`.
  `cat pipeline.lock` confirmed
  `manager|feature/band-gear-management|2026-09-06T11:37:26Z` at start
  of cycle.
- **Preflight:** `bash scripts/clear_stale_git_lock.sh` ran with
  `no lock files present, nothing to do`.
- **Branch check (at start of QA):** `GIT_OPTIONAL_LOCKS=0 git branch
--show-current` returned `feature/band-gear-management`.
- **Working tree review:** `GIT_OPTIONAL_LOCKS=0 git diff` against
  `HEAD`, plus direct reads of newly created files under
  `lib/features/gear/`, `supabase/migrations/2026090612000{0,1,2}_*.sql`,
  and `test/features/gear/gear_item_test.dart`.
- **No test / migration / config / source edits by QA.** Only the doc
  edit to this `QA_REPORT.md` file, per QA authority.
- **No live application launched.** No `flutter run`, `./run.sh`,
  simulator, DTD, driver, `integration_test`, or browser automation.
  Runtime UI verification is Tony's Tier 2 responsibility per plan.
- **No git-write commands issued by QA** (verified: only read-only
  `git branch --show-current` / `git status` / `git diff` /
  `git log` / `git ls-files` / `git check-ignore` / `git show`
  were run).

### Environmental note (Manager attention)

During this QA cycle, a mid-session branch switch and commit were
performed outside the QA cycle. `git reflog` after report write shows:

```
61b2a1e HEAD@{0}: commit: chore(supabase): restore orphaned demo-seed
                          migrations lost in rescue sweep
80bad0a HEAD@{1}: checkout: moving from feature/band-gear-management
                          to chore/restore-orphaned-demo-migrations
80bad0a HEAD@{2}: checkout: moving from main to feature/band-gear-management
```

Commit `61b2a1e` on `chore/restore-orphaned-demo-migrations` (author:
Tony, timestamp `Sun Sep 6 07:23:14 2026 -0500`) captured the four
gear migration files (`20260905201000_create_band_gear.sql` +
`20260906120000/1/2`) together with three unrelated demo-seed
restoration migrations, and was pushed to origin. This corresponds to
Tony's separate infra work to fix the repo-wide broken-migration-chain
KNOWN INFRA BLOCKER referenced in the plan (unrelated to this feature's
scope). It happened between my test runs and my QA_REPORT.md write.

**Impact on this QA verdict:** none — all Tier 1 evidence (analyzer,
tests, T1.4 SQL grep counts, code-path inspection of all modified
Dart files and all four migrations) was captured while the shell was
on `feature/band-gear-management` with the full uncommitted working
tree present. The on-disk content of every file I evaluated is
unchanged (byte-for-byte the same objects that got committed to the
other branch). The QA_REPORT.md write and this operational note are
the only actions I took after the switch, and neither depended on
branch context.

**Impact on Manager's release step:** the branch `feature/band-gear-
management` at HEAD is still `80bad0a` (identical to `main`) — no
cycle-4 work is committed on it. The uncommitted working-tree
modifications (5 modified Dart files) and the two remaining
untracked directories (`lib/features/gear/`, `test/features/gear/`)
still represent the correct implementation and are ready for
Manager's release step. However, the four migration files that were
part of this feature's implementation are now committed on
`chore/restore-orphaned-demo-migrations` at commit `61b2a1e` (and
pushed to origin). Manager needs to reconcile: either (a) rebase /
cherry-pick / merge `chore/restore-orphaned-demo-migrations` into
`feature/band-gear-management`, or (b) recognize that the migrations
have effectively already shipped on a different branch and adjust
the release plan accordingly. This reconciliation is Manager's call
and outside QA authority.

Because none of this invalidates the technical evidence for the
cycle-4 gate, the **APPROVED verdict stands.** The environmental
disruption is called out for Manager's attention only.
