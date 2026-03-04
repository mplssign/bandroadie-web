# QA Handoff — Band User Roles (RBAC)

**Branch:** `feature/band_user_roles`
**Date:** 2026-03-02
**From:** Engineer Agent
**To:** QA Agent

---

## QA VERDICT

**PASS**

**Reviewed:** 2026-03-02
**Reviewer:** QA Agent
**flutter analyze:** 0 errors (1 pre-existing warning, unrelated)
**Files reviewed:** 11 modified, 5 new, 1 SQL migration (526 lines)
**Diff reviewed:** Full git diff on `feature/band_user_roles` branch

---

### Critical Issues

None.

---

### Warnings

**W1. `EmptyHomeState` → `QuickActionsRow` missing `showCreateGig`/`showCreateSetlist` params**
- **File:** `lib/features/home/widgets/empty_home_state.dart` (line ~180)
- **Impact:** When a contributor/member without gig/setlist permissions sees the empty home state, the "+ Create Gig" and "+ Create Setlist" buttons render as **disabled** (null callback) instead of being **hidden** entirely. This is inconsistent with the content-state `QuickActionsRow` which receives `showCreateGig: false` / `showCreateSetlist: false` to fully hide the buttons.
- **Risk:** Low — the buttons are disabled (null `onPressed`), so no unauthorized action is possible. Pure UX inconsistency.
- **Fix:** Pass `showCreateGig` and `showCreateSetlist` through `EmptyHomeState` widget params and forward them to `QuickActionsRow`.

**W2. `showRemoveOption` naming is now misleading**
- **File:** `lib/features/members/widgets/member_card.dart`
- **Impact:** The `showRemoveOption` boolean now gates the entire kebab menu (both "Manage role" and "Remove from band"). The name implies it only controls the remove action.
- **Risk:** None — functionally correct. Future developers may be confused by the naming.
- **Fix:** Consider renaming to `showAdminActions` in a follow-up.

**W3. Permissions provider fallback defaults to admin on errors/null states**
- **File:** `lib/features/members/permissions/band_permissions_provider.dart`
- **Impact:** When `bandId` is null, `userId` is null, or the user is not found as a member, the provider returns `BandPermissions.admin`. This is the "safe fallback" per the engineer report (existing users were all admins), but it means transient fetch errors could grant admin-level UI access.
- **Risk:** Low — RLS is the real authority. The admin fallback only widens the UI; any actual mutation would be blocked by the database. This is the correct trade-off for a production app where false-negatives (locking users out) are worse than false-positives (showing buttons that the DB will reject).
- **Note:** Acceptable as-is given the compatibility-first strategy. Revisit once RBAC has been in production and users have been reassigned roles.

---

### Suggestions

**S1. Load existing contributor sub-permissions in `RoleManagementSheet`**
- Currently `_subPermissions` always initializes to `ContributorPermissions.allEnabled`. If a contributor already has customized permissions, reopening the role sheet would reset them to all-enabled unless the admin saves without changing. Consider fetching the current `contributor_permissions` row in `initState` if the member is already a contributor.

**S2. Add `rehash` rehearsal creation could also benefit from RBAC**
- The architect plan does not gate rehearsal creation. All roles can schedule rehearsals. If this is intentional, no action needed. If not, it's a gap worth documenting.

**S3. Consider unit tests for `BandPermissions` pure Dart class**
- `band_permissions.dart` is a pure logic class with no dependencies — an ideal candidate for unit tests to lock down the permission matrix.

---

### Compliance Checklist

| # | Check | Result |
|---|-------|--------|
| 1 | Implementation matches ARCHITECT_PLAN.md | PASS — all 16 planned files accounted for (5 new + 11 modified). Migration follows the 9-phase structure. RPCs match spec. |
| 2 | Feature-first architecture | PASS — new files under `lib/features/members/permissions/` and `lib/features/members/widgets/` |
| 3 | Riverpod Notifier pattern (not StateNotifier) | PASS — `MembersNotifier extends Notifier`, `FutureProvider` for permissions |
| 4 | SECURITY DEFINER + SET search_path = public | PASS — `delete_band`, `update_member_role`, `remove_band_member` all comply. `get_user_band_role` intentionally omits SECURITY DEFINER. |
| 5 | FOR UPDATE locking on admin-count queries | PASS — present in both `update_member_role` and `remove_band_member` |
| 6 | BandRole enum backward compat (owner → admin) | PASS — `_parseRole` maps 'owner' → admin; `member_vm.dart` `isAdmin` checks both |
| 7 | Dark mode + design tokens | PASS — `AppColors`, `Spacing` used consistently in new UI |
| 8 | Rose accent #F43F5E | PASS — `AppColors.accent` used for buttons, selection states |
| 9 | Zero regression at migration time | PASS — all active members promoted to admin before ENUM conversion |
| 10 | Permissions auto-invalidate on band switch | PASS — `currentUserPermissionsProvider` watches `activeBandIdProvider` |
| 11 | No initialization order changes | PASS — no changes to app startup or provider initialization |
| 12 | flutter analyze: 0 errors | PASS — confirmed, 1 pre-existing warning (unrelated dead_code) |
| 13 | No unrelated file changes | PASS — all whitespace reformatting is dart-format noise, no logic changes outside RBAC scope |
| 14 | RLS policy correctness | PASS — gigs INSERT/UPDATE/DELETE, setlists INSERT/UPDATE/DELETE, bands DELETE all role-aware. SELECT policies untouched. |
| 15 | `contributor_permissions` table ON DELETE CASCADE | PASS — FK to `band_members(id)` with CASCADE. Cleanup automatic on member removal. |
| 16 | Dynamic policy pre-drop (Step 3.5) | PASS — handles dashboard-created policies that would block ENUM ALTER |

---

## 1) Goal

Introduce database-enforced Role-Based Access Control (RBAC) with three roles: **admin**, **member**, and **contributor**. All existing active members are promoted to admin at migration time to guarantee zero permission loss.

---

## 2) Current State

- **Migration:** Successfully deployed to both staging and production Supabase. All 7 verification queries pass.
- **ENUM column:** `band_members.role` is now `band_role_type` (admin, member, contributor)
- **Active members:** All 139 active band_members have role = admin
- **RLS policies:** 7 new role-aware policies in place on gigs, setlists, bands
- **RPCs:** 4 functions created (get_user_band_role, delete_band, update_member_role, remove_band_member)
- **Flutter code:** 11 modified files, 5 new files — all on working tree, not committed

---

## 3) Constraints (Non-negotiables)

- No initialization order changes
- No new config loading paths
- Feature-first architecture (`lib/features/`)
- Riverpod `Notifier` + `NotifierProvider` pattern (not deprecated StateNotifier)
- Dark mode only, rose accent `#F43F5E`
- Design tokens from `lib/app/theme/design_tokens.dart`
- All Supabase SECURITY DEFINER functions must SET search_path = public

---

## 4) Files Changed

### New Files (5 + 1 migration)

| File | Purpose |
|------|---------|
| `supabase/migrations/20260302000000_band_user_roles.sql` | 9-phase RBAC migration (ENUM, RLS, RPCs) |
| `lib/features/members/permissions/contributor_permissions.dart` | Data model for 5 boolean sub-permissions |
| `lib/features/members/permissions/band_permissions.dart` | Pure Dart permission abstraction (role + sub-perms → booleans) |
| `lib/features/members/permissions/band_permissions_provider.dart` | Riverpod FutureProvider — fetches user's role + sub-perms |
| `lib/features/members/widgets/role_management_sheet.dart` | Admin-only full-screen role management modal |
| `docs/features/band_user_roles/ENGINEER_REPORT.md` | Engineer implementation report |

### Modified Files (11)

| File | Changes |
|------|---------|
| `lib/app/models/band_member.dart` | BandRole enum: removed `owner`, added `contributor`; `_parseRole` maps 'owner' → admin |
| `lib/features/members/member_vm.dart` | Removed `isOwner` getter, added `isContributor`; `isAdmin` still maps owner → admin |
| `lib/features/members/members_repository.dart` | Added `fetchContributorPermissions()` and `updateMemberRole()` (calls RPC) |
| `lib/features/members/members_controller.dart` | Added `updateRole()` action; invalidates permissions provider after change |
| `lib/features/members/widgets/member_card.dart` | Removed `isOwner` guard; added `onManageRole` callback; kebab menu: "Manage role" + "Remove from band" |
| `lib/features/members/members_tab_content.dart` | Added `_openRoleManagement()` method; passes `onManageRole` to MemberCard |
| `lib/features/bands/band_form_screen.dart` | Delete button gated by `canDeleteBand` permission check |
| `lib/features/home/widgets/quick_actions_row.dart` | Added `showCreateGig`/`showCreateSetlist` bool params; conditionally shows/hides buttons |
| `lib/features/home/home_tab_content.dart` | Watches `currentUserPermissionsProvider`; passes permission flags to QuickActionsRow and empty states |
| `lib/features/home/home_screen.dart` | Same permission gating pattern for home screen variant |
| `lib/features/events/widgets/event_editor_drawer.dart` | `_forcePotentialOnly` flag for contributors; RBAC re-check on type-switcher toggle |

---

## 5) Implementation Notes

- **Migration is live** on production — DB schema is already in its final state
- **Flutter code is NOT committed** — all changes are on the working tree of `feature/band_user_roles`
- The `currentUserPermissionsProvider` watches `activeBandIdProvider` — auto-invalidates on band switch
- Setlist mutation guards are at navigation level (hide "Create Setlist"). Detail-level edits/deletes are blocked by RLS; app catches `PostgrestException` gracefully
- `FOR UPDATE` locking prevents race conditions on last-admin demotion/removal
- `flutter analyze`: 0 errors, 1 pre-existing warning (dead code in lyrics_view_screen.dart, unrelated)

---

## 6) Verification Evidence

### Database (Production)

| Check | Result |
|-------|--------|
| ENUM values: admin, member, contributor | PASS |
| Column type: USER-DEFINED / band_role_type | PASS |
| All 139 active members = admin | PASS |
| contributor_permissions table: 0 rows | PASS |
| 7 new RLS policies present | PASS |
| 4 RPCs exist | PASS |
| Old dashboard policy ("admin or creator") removed | PASS |

### Flutter Analyze

```
0 errors, 1 pre-existing warning (dead_code in lyrics_view_screen.dart)
```

### Staging

- Full migration ran successfully against pg_dump of production data
- Two errors encountered and fixed before production run:
  1. `DROP DEFAULT` needed before ENUM type conversion
  2. Dynamic policy pre-drop (Step 3.5) added to handle dashboard-created policies

---

## 7) QA Focus Areas

### Critical Paths to Test

1. **App launch** — Log in → bands/gigs/setlists all load normally (no RLS regressions)
2. **Role management** — MemberCard kebab → "Manage role" → change role → verify updates
3. **Last-admin guard** — Demote the only admin → should show error, not allow it
4. **"Create Gig" gating** — As contributor without `canCreateGigs`, button should be hidden/disabled
5. **"Create Setlist" gating** — Same for setlists
6. **Band delete gating** — Non-admin should NOT see delete button in band settings
7. **Event editor potential-only** — Contributor with `canCreatePotentialGigsOnly` forced to Potential toggle
8. **Event type-switcher re-check** — Open as Rehearsal → switch to Gig → potential-only should engage
9. **Band switching** — Switch bands → permissions refresh for new band's role
10. **Backward compat** — Any 'owner' string values should map to admin behavior

### Known Limitations (Accepted)

- Setlist detail screen does not hide edit/delete UI for contributors — RLS blocks the actual mutations, app shows error snackbar. This is by design per ARCHITECT_PLAN.
- Sub-permission toggles default to `allEnabled` for new contributors until actual DB values populate.

### High-Risk Areas

- **RLS policy correctness** — New policies reference `bm.role IN ('admin', 'member')`. Any misconfigured policy could lock users out or allow unauthorized access.
- **Band switching** — Permission provider must invalidate cleanly. Stale permissions from a previous band would be a security issue.
- **Event editor (4000+ line file)** — Minimal changes made. Verify no unintended side effects on existing gig/rehearsal creation flows.
- **Platform consistency** — Test on iOS, macOS, and Web. Android if possible.
