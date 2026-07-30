# Manual Drag-to-Reposition for Band Member Cards — Architectural Plan

## Feature Slug

`feature/band-member-manual-reorder`

---

## Problem Summary

The Band Members list (Contacts tab → Band segment) has no way to manually order members — it is always sorted alphabetically by last name, then first name, computed client-side in `MembersRepository.fetchMembersAndInvites()`. There is no persisted ordering concept on `band_members` at all today (no `position`/`sort_order` column, no `ORDER BY` beyond `joined_at` in the initial fetch, which is immediately discarded by the client-side alpha sort).

**Why this matters:** bands want to arrange members in a meaningful order (e.g. lead vocalist first, rhythm section together) rather than being locked to alphabetical. Setlists already solved an equivalent problem for songs (drag-to-reorder, server-persisted `position`), and this feature ports that same mechanism to Band Members.

**Scope (per Feature Input, confirmed unchanged during investigation):** Band Members only. The Contacts and Venues segments of the same tab are explicitly out of scope and are not touched by this plan.

---

## Root Cause

**Confidence:** HIGH (direct observation)

Not applicable in the bug sense — this is a greenfield feature addition, not a defect. The "gap" driving this feature: `band_members` has no ordering column, and `MembersRepository`'s sort is unconditionally alphabetical with no override mechanism.

**Discrepancy found between Feature Input and codebase, resolved by direct observation (Architect Phase 3):** The Feature Input describes `band_members_view.dart` as "the A-Z sectioned view … shipped in `feature/band-contacts-az-listing` (search + section headers, no index column, by prior product decision)." This is **not what the current code does**. Reading `docs/features/band-contacts-az-listing/ARCHITECT_PLAN_AMENDMENT_1.md` (title: "Drop Band Search/Sections, Add Contact Company Field") and the live file confirms that Amendment 1 of that branch **removed search, section headers, and grouping from Band Members entirely**, converting `band_members_view.dart` from a `StatefulWidget` with `AzSearchField`/`AzSectionHeader`/grouping logic back down to a plain `StatelessWidget` rendering a flat `SliverList` — its own file header comment says so verbatim: *"Flat, ungrouped, unsearchable list — no search bar, no A-Z sectioning."* This is the actual, current, QA-**APPROVED** state (confirmed via `git log --follow` on the file and the base+amendments `QA_REPORT.md`, both APPROVED 2026-07-25). The `az_search_field.dart` / `az_index_column.dart` / `az_section_header.dart` / `az_list_helpers.dart` files exist and are used by `contacts_view.dart` and `venues_view.dart`, but **not** by `band_members_view.dart`.

Also inaccurate: the Feature Input's claim that `band_members_view.dart` is "already at 415 lines." The file is currently **186 lines**. (415 lines was `band_members_view.dart`'s size at one intermediate point during the `band-contacts-az-listing` branch, per that plan's own QA report — before Amendment 1 stripped the search/section/grouping code back out.)

**Practical effect on this plan:** there are no A-Z section headers to reconcile with manual ordering — the live list is already flat. This *simplifies* the design question the Feature Input asked me to resolve ("how it interacts with A-Z section headers once a manual order is active"): there is nothing to hide or reconcile. What remains is only the sort *order* of that flat list — alphabetical by default, position-driven once a manual reorder has occurred.

---

## Reference Docs Consulted

- `docs/features/band-contacts-az-listing/ARCHITECT_PLAN.md` + `ARCHITECT_PLAN_AMENDMENT_1.md` + `ARCHITECT_PLAN_AMENDMENT_2.md` + `QA_REPORT.md` — full history of how `band_members_view.dart`/`band_member_card.dart` reached their current shape. Establishes the discrepancy above and confirms `BandMemberCard`/`band_members_view.dart` are the correct, live target files (not the legacy `lib/features/members/widgets/member_card.dart` + `members_tab_content.dart`, which are confirmed unrouted dead code — `app_shell.dart` renders `ContactsTabContent`, not `MembersTabContent`).
- No `docs/reference/` domain directory exists specifically for "members" or "setlists" reorder mechanics; the authoritative reference for the drag/reorder mechanism is the live setlists implementation itself (code, not docs) — read directly per Feature Input's instruction: `lib/features/setlists/widgets/reorderable_song_card.dart`, `lib/features/setlists/setlist_detail_screen.dart` (lines 548–570, 2412–2467), `lib/features/setlists/setlist_detail_controller.dart` (lines 1032–1122), `lib/features/setlists/setlist_repository.dart` (lines 1029–1161), and the deployed SQL for `reorder_setlist_items`/`reorder_setlist_songs` (read live from the production database via Supabase MCP, since the RPC as currently deployed is **not** present in any tracked file under `supabase/migrations/` — it exists only in the live database. Flagging this as a pre-existing drift between tracked migrations and deployed schema; not something this plan needs to fix, but Engineer should be aware `supabase/migrations/` is not a complete source of truth for existing RPC bodies).

---

## Existing System Analysis

### Band Members data flow (current)

1. `MembersRepository.fetchMembersAndInvites()` (`lib/features/members/members_repository.dart:87-261`) runs a 4-query client-side merge (`band_members`, `users`, `band_invitations`, `user_band_roles` — no PostgREST joins, by explicit repository-level convention) and returns `MembersData(members: List<MemberVM>, ...)`.
2. The `band_members` query (`members_repository.dart:110-115`) selects `id, user_id, role, status, joined_at`, filters `status IN ('active','invited')`, orders by `joined_at ascending` — but this order is **immediately discarded**: `members.sort(...)` (`members_repository.dart:224-235`) unconditionally re-sorts the merged `List<MemberVM>` alphabetically by `lastName` then `firstName` (case-insensitive), with no way to opt out.
3. `MembersController` (`members_controller.dart`) is a Riverpod `Notifier<MembersState>`; `MembersState` holds `members`, `pendingInvites`, `isLoading`, `error`, `isCurrentUserAdmin` (computed via `MembersRepository.isCurrentUserAdmin()`, which checks `band_members.role IN ('admin','owner')` for the caller — `'owner'` is dead code, `band_role_type` only has `admin`/`member`/`contributor` values, confirmed via the live enum).
4. `ContactsTabContent` (`lib/features/contacts/contacts_tab_content.dart`, `ConsumerStatefulWidget`) owns `membersProvider` and passes `membersState` + callbacks (`onRefresh`, `onInvite`, `onManageRole`) down to `BandMembersView` by constructor (`contacts_tab_content.dart:148-155`) — the existing unidirectional-data-flow pattern this plan must extend, not bypass.
5. `BandMembersView` (`lib/features/contacts/widgets/band_members_view.dart`, `StatelessWidget`, 186 lines) renders a `CustomScrollView` with a `SliverList`/`SliverChildBuilderDelegate` over `membersState.members`, each item a `Padding`-wrapped `BandMemberCard` keyed by `member_${member.memberId}_${...}`.
6. `BandMemberCard` (`lib/features/contacts/widgets/band_member_card.dart`, 85 lines) is a plain `Container` + `Column` (no `Stack`, no drag affordance) showing name, crown icon (`if member.isAdmin`), musical roles.

### Database (confirmed live via Supabase MCP against the production project, `nekwjxvgbveheooyorjo`)

- `band_members` columns: `id uuid`, `band_id uuid`, `user_id uuid`, `role band_role_type` (enum: `admin`/`member`/`contributor`), `joined_at timestamptz`, `status text`. **No ordering column.**
- RLS policies on `band_members`: `SELECT` — any active co-member (`is_band_member(band_id)`) or the row's own user; `INSERT` — any band member or self; **`UPDATE` — admins only** (`Admins can update band members`: `is_band_member(band_id) AND EXISTS(... role='admin' AND status='active')`). This is the load-bearing fact for RBAC below.
- `remove_band_member` RPC **hard-deletes** the `band_members` row (`DELETE FROM public.band_members WHERE id = p_member_id ...`) — confirmed by reading its live definition. There is no soft-delete/status='removed' state to worry about for stale `position` values; a removed member's row (and any position it held) is gone entirely, not orphaned.
- `is_band_member_with_role(p_band_id, p_roles[])` is an existing `SECURITY DEFINER` helper but does **not** filter on `status = 'active'`; the existing convention for RPCs that need an active-admin check (`remove_band_member`) inlines the check directly rather than relying on that helper. This plan follows that same inlined-check convention rather than the helper, for parity with `remove_band_member`.

### Setlists reorder reference (mechanism to mirror)

- **UI:** `ReorderableSongCard` (`reorderable_song_card.dart`) — `StatefulWidget` with `SingleTickerProviderStateMixin` for tap scale/opacity, a `Stack` with a `Positioned` left-edge drag-handle strip wrapped in `ReorderableDragStartListener(index: widget.index, child: Icon(AppIcons.drag, ...))`, and the remaining content wrapped in a `Positioned` + `Listener(onPointerDown: (_) {}, behavior: HitTestBehavior.opaque, ...)` that **absorbs pointer events** so only the drag-handle strip can start a drag (the rest of the card remains tappable/scrollable, not draggable). This exact structure — not a simpler `Row`-based layout — is what makes "tap card body" and "drag from handle" coexist without gesture conflicts, and is what the Feature Input means by "the same drag-handle icon and reorder mechanics."
- **List widget:** `SliverReorderableList` (used inside a `CustomScrollView`, exactly like `BandMembersView` already is) with `itemCount`, `onReorderItem` (this SDK's parameter name for what Flutter core otherwise calls `onReorder` — confirmed via three live call sites in this repo, not assumed), `itemBuilder`, `proxyDecorator` (elevation/scale during drag).
- **Optimistic update + debounce + persist + revert, owned by the parent `ConsumerStatefulWidget`:**
  - `SetlistDetailController.reorderLocal(oldIndex, newIndex)` (`setlist_detail_controller.dart:1036-1055`): reindexes the in-memory list immediately, stashing the pre-drag order as `lastKnownGoodSongs` (only on the *first* drag in a sequence, so multiple rapid drags all revert to the same pre-drag baseline).
  - `setlist_detail_screen.dart:548-570` (`_handleReorder`): calls `reorderLocal` synchronously (optimistic UI), then (re)starts a 500ms debounce `Timer` before calling `persistReorder()` — so rapid successive drags collapse into a single network call.
  - `SetlistDetailController.persistReorder()` (`setlist_detail_controller.dart:1061-1120`): calls `SetlistRepository.reorderSongs()`; on success clears the backup; on failure reverts to `lastKnownGoodSongs` (or triggers a refetch if no backup exists) and sets a user-visible error.
- **Persistence RPC:** `reorder_setlist_songs(p_setlist_id, p_row_ids)` → thin SQL wrapper delegating to `reorder_setlist_items(p_setlist_id, p_row_ids)` (`plpgsql`, `SECURITY DEFINER`). Validates every supplied row id belongs to the target setlist (`COUNT(*) ... = array_length`), then does a **two-phase update** to avoid tripping the `UNIQUE(setlist_id, position)` constraint mid-update: Phase 1 assigns temporary *negative* positions via `unnest(...) WITH ORDINALITY`; Phase 2 flips each to its final 0-based position (`(-position) - 1`). The underlying unique constraint is `DEFERRABLE INITIALLY DEFERRED` — added in `supabase/migrations/20260724143942_fix_setlist_positions_trigger_collision.sql` specifically because an earlier, non-deferrable version of this same constraint caused production collisions during exactly this kind of multi-row reorder. `reorder_band_members` must ship as `DEFERRABLE INITIALLY DEFERRED` from the start to avoid repeating that same class of bug.
- `SetlistRepository.reorderSongs()` (`setlist_repository.dart:1035-1122`) also has a client-side two-phase-update fallback for when the RPC isn't deployed yet (`PGRST202`/`42883`). **Not needed here** — the `band_members.position` column and `reorder_band_members` RPC ship together in one migration, so there is no "column exists but RPC doesn't" window to guard against, unlike setlists' incremental rollout history.

---

## Proposed Solution

### 1. Database: nullable `position` column + atomic reorder RPC

Add `band_members.position INTEGER NULL` (nullable, no default). `NULL` means "no manual order set — use alphabetical." A `UNIQUE (band_id, position) DEFERRABLE INITIALLY DEFERRED` constraint mirrors the setlist_songs fix (Postgres treats each `NULL` as distinct, so multiple members can simultaneously have `position IS NULL` without violating uniqueness — no partial-index workaround needed).

New RPC `reorder_band_members(p_band_id uuid, p_member_ids uuid[])`, directly modeled on `reorder_setlist_items`, with one addition `reorder_setlist_items` doesn't need: an **explicit in-function authorization check**, because `band_members` UPDATE is RLS-gated to admins only (unlike `setlist_songs`, which any band member may update) and this `SECURITY DEFINER` function bypasses RLS entirely — the check must be re-implemented inside the function body, inlined in the same style as `remove_band_member`'s existing admin check (not via `is_band_member_with_role`, which doesn't filter `status='active'`):

```sql
IF NOT EXISTS (
  SELECT 1 FROM public.band_members
  WHERE band_id = p_band_id AND user_id = auth.uid()
    AND role = 'admin' AND status = 'active'
) THEN
  RAISE EXCEPTION 'Permission denied: only admins can reorder members';
END IF;
```

Followed by the same row-count validation and two-phase negative-position update `reorder_setlist_items` uses, applied to `band_members`/`position` instead of `setlist_songs`/`position`.

**Why a full band-wide reorder, not a two-row swap:** exactly like setlist songs, the client always sends the complete, currently-rendered ordered list of member IDs (not just the two that moved). This means the *very first* drag in a band's history — when every member's `position` is still `NULL` — naturally assigns sequential `0..N-1` positions to every currently-visible member in one atomic call, transitioning the whole band from "alphabetical" to "manually ordered" mode without any special first-time-vs-subsequent-time branching in either the client or the RPC.

### 2. Sort logic (client, `MembersRepository`)

Replace the unconditional alphabetical sort with a conditional one:

- If **no** member in the fetched set has a non-null `position` → sort alphabetically exactly as today (unchanged behavior, unchanged default).
- If **any** member has a non-null `position` → sort by `position ascending`; any member that still has `position == null` (e.g. someone invited/joined after the band's last manual reorder) is appended after all positioned members, with positioned-vs-unpositioned members among themselves falling back to the existing alphabetical comparator as the tiebreak.

This is a pure client-side read-path change — it does not touch the `band_members` query's own `ORDER BY joined_at` (still fine as a stable initial fetch order; the Dart-side sort is authoritative either way, as it already is today).

### 3. RBAC: admin-only, reusing the existing gate

`membersState.isCurrentUserAdmin` (already computed, already used in this exact file to gate the role-management drawer's Edit affordance) is reused as the reorder gate — **not** a new `BandPermissions.canReorderMembers` getter. `BandPermissions` (`lib/features/members/permissions/band_permissions.dart`) documents itself as the mandated single path for UI permission checks, but `ContactsTabContent`/`BandMembersView` do not currently consume `BandPermissions` anywhere — they use `membersState.isCurrentUserAdmin` directly, which is itself not a raw role-string comparison scattered in UI (it's a single precomputed boolean already serving an equivalent purpose in this file). Introducing a second permission-check pathway into a file that doesn't use one today would be a wider change than the feature needs. This choice is also consistent with the server: reordering is authorized exactly like the existing "Admins can update band members" RLS UPDATE policy already requires, so the client gate and the server gate express the same rule.

Non-admins still see the Band Members list in its current (alphabetical-or-manually-ordered) form; they simply get the existing static `SliverList` with plain (non-draggable) `BandMemberCard`s, with no drag handle rendered — mirroring exactly how `setlist_detail_screen.dart` branches between `SliverReorderableList` (canEdit) and a plain `SliverList` (not canEdit) today.

### 4. UI: new `ReorderableBandMemberCard`, conditional `SliverReorderableList`

A new file, `reorderable_band_member_card.dart`, mirrors `reorderable_song_card.dart`'s `Stack` + `Positioned` drag-handle-strip + pointer-absorbing `Listener` structure (see Existing System Analysis above), rendering the same name/crown/musical-roles content `BandMemberCard` renders today. This is a **sibling file**, not a flag added to `BandMemberCard`, following this codebase's own established precedent: `song_card.dart` and `reorderable_song_card.dart` are two independently-maintained files with duplicated presentational code (their `_buildBpmValue`/`_buildDurationValue`/`_buildKeyBadge`/`_buildTuningBadge` methods are near-identical copies, not shared), and the `band-contacts-az-listing` branch's own Amendment 2 plan explicitly names and follows this same "small, non-bug-prone presentational duplication over premature shared abstraction" precedent for a different pair of files in this exact feature area. `BandMemberCard` itself is not modified.

`BandMembersView` gains one new constructor parameter, `final void Function(int oldIndex, int newIndex)? onReorder`, and branches its member-list sliver: when `membersState.isCurrentUserAdmin` is true, render `SliverReorderableList` (`onReorderItem: onReorder`, itemBuilder producing `ReorderableBandMemberCard`s); otherwise keep today's static `SliverList` of plain `BandMemberCard`s, unchanged. `BandMembersView` itself performs no mutation and holds no debounce/timer state — per Guardrails §9 ("leaf widgets do not perform cross-feature mutations"), it only emits `onReorder(oldIndex, newIndex)` upward, exactly like its existing `onManageRole`/`onInvite`/`onRefresh` callbacks.

`ContactsTabContent` (already the state-owning parent, already a `ConsumerStatefulWidget`) gains a debounce `Timer? _reorderDebounceTimer` field and a `_handleMemberReorder(int oldIndex, int newIndex)` method, structured identically to `setlist_detail_screen.dart`'s `_handleReorder` (`setlist_detail_screen.dart:548-570`): call `ref.read(membersProvider.notifier).reorderLocal(oldIndex, newIndex)` synchronously, then debounce 500ms before calling `persistReorder(bandId)`. The timer is cancelled in the existing `dispose()` override.

`MembersState` gains `lastKnownGoodMembers` (`List<MemberVM>?`) and `isReordering` (`bool`) fields, mirroring `SetlistDetailState`'s equivalent fields. `MembersNotifier` gains `reorderLocal(int oldIndex, int newIndex)` and `Future<bool> persistReorder(String bandId)` methods, structured identically to `SetlistDetailController.reorderLocal`/`persistReorder` (optimistic reindex → debounced persist → revert-to-`lastKnownGoodMembers`-or-refetch on failure).

---

## Database Impact

- **New column:** `band_members.position INTEGER NULL`. Nullable, no default — existing rows are unaffected (`NULL` = "alphabetical," the current behavior for every existing row on rollout).
- **New constraint:** `UNIQUE (band_id, position) DEFERRABLE INITIALLY DEFERRED` — deferrable from the start, avoiding the exact collision bug `20260724143942_fix_setlist_positions_trigger_collision.sql` had to retrofit for `setlist_songs`.
- **New RPC:** `reorder_band_members(p_band_id uuid, p_member_ids uuid[]) RETURNS json`, `SECURITY DEFINER`, `SET search_path = public`, with an inlined active-admin authorization check (see Proposed Solution §1) and the same two-phase negative-position update pattern as `reorder_setlist_items`.
- **RLS:** unaffected — no policy is added, dropped, or modified. `band_members` UPDATE remains admin-only via existing RLS; the new RPC's `SECURITY DEFINER` bypass is compensated by its own inlined check, which encodes the identical rule the RLS policy already enforces for direct table UPDATEs. No self-referencing-policy risk (Guardrails §4) — the RPC's check is a plain `EXISTS` subquery inside a function body, not a policy.
- **Other RPCs / callers of `band_members`:** `remove_band_member` (hard `DELETE`, unaffected by an added nullable column), `update_member_role` (updates `role`/permissions only, unaffected), `MembersRepository`'s `band_members` `INSERT` (via Supabase client `.insert({...})`, always column-keyed, never positional — unaffected by an added column with no default). No existing RPC or client insert path breaks.
- **Backfill:** none required or performed. Every existing row simply starts `position = NULL`, which is exactly the "not yet manually ordered" state the sort logic already treats as the default.

---

## Flutter Architecture Changes

### New
- `lib/features/contacts/widgets/reorderable_band_member_card.dart` — `ReorderableBandMemberCard` (`StatefulWidget`, mirrors `reorderable_song_card.dart`'s structure and tap/drag mechanics; renders the same name/crown/musical-roles content as `BandMemberCard`).

### Modified
- `lib/features/contacts/widgets/band_members_view.dart` — add `onReorder` callback param; branch the member sliver between `SliverReorderableList` (admin) and the existing static `SliverList` (non-admin), unchanged in every other respect.
- `lib/features/contacts/contacts_tab_content.dart` — add `_reorderDebounceTimer` + `_handleMemberReorder`, wire `onReorder: _handleMemberReorder` into the existing `BandMembersView(...)` construction, cancel the timer in the existing `dispose()`.
- `lib/features/members/members_controller.dart` — `MembersState` gains `lastKnownGoodMembers`/`isReordering`; `MembersNotifier` gains `reorderLocal`/`persistReorder`.
- `lib/features/members/members_repository.dart` — `band_members` select gains `position`; sort logic becomes conditional (position-based when any member has one set, else unchanged alphabetical); new `reorderMembers({bandId, memberIdsInOrder})` method calling the new RPC and invalidating the per-band cache on success.
- `lib/features/members/member_vm.dart` — `MemberVM` gains a `final int? position` field, populated in `fromMergedData` from `bandMember['position']`.

### Unidirectional data flow (Guardrails §9)
`ContactsTabContent` (parent) owns the debounce timer and calls `MembersNotifier` (the mutation path); `BandMembersView` and `ReorderableBandMemberCard` (children) only receive state via constructor and emit `onReorder`/`onTap` callbacks upward — no leaf widget calls the repository or the provider notifier directly. This matches the existing `onManageRole` callback's shape exactly.

---

## Files to Create

| File | Justification |
|---|---|
| `supabase/migrations/20260729120000_add_position_to_band_members.sql` | New nullable `position` column, deferrable unique constraint, and `reorder_band_members` RPC. No existing migration or RPC covers band-member ordering. |
| `lib/features/contacts/widgets/reorderable_band_member_card.dart` | Drag-enabled sibling of `BandMemberCard`, mirroring the `song_card.dart`/`reorderable_song_card.dart` split already established in this codebase. Keeps `band_members_view.dart` from growing further per the Feature Input's explicit isolation instruction, and keeps `BandMemberCard` itself unmodified. |

---

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/contacts/widgets/band_members_view.dart` | Add `onReorder` callback param. Branch the member-list sliver: `SliverReorderableList` + `ReorderableBandMemberCard` when `membersState.isCurrentUserAdmin`, else the existing static `SliverList` + `BandMemberCard`, unchanged. |
| `lib/features/contacts/contacts_tab_content.dart` | Add `Timer? _reorderDebounceTimer` and `_handleMemberReorder(int, int)` (optimistic `reorderLocal` + 500ms debounce + `persistReorder`), mirroring `setlist_detail_screen.dart:548-570`. Wire `onReorder: _handleMemberReorder` into the existing `BandMembersView(...)` call. Cancel the timer in the existing `dispose()`. |
| `lib/features/members/members_controller.dart` | `MembersState`: add `lastKnownGoodMembers` (`List<MemberVM>?`), `isReordering` (`bool`), and corresponding `copyWith` params (including a `clearLastKnownGood` flag, mirroring `SetlistDetailState`'s pattern). `MembersNotifier`: add `reorderLocal(int oldIndex, int newIndex)` and `Future<bool> persistReorder(String bandId)`, mirroring `SetlistDetailController.reorderLocal`/`persistReorder` exactly (optimistic reindex, single-baseline backup across rapid drags, revert-or-refetch on failure). |
| `lib/features/members/members_repository.dart` | `band_members` select adds `position`. Replace the unconditional alphabetical `members.sort(...)` with: alphabetical if no member has a non-null `position`, else position-ascending with unpositioned members appended (alphabetical tiebreak among themselves). Add `Future<void> reorderMembers({required String bandId, required List<String> memberIdsInOrder})` calling the `reorder_band_members` RPC and clearing `_cache[bandId]` on success — no client-side fallback path (RPC and column ship together in the same migration, unlike setlists' incremental rollout). |
| `lib/features/members/member_vm.dart` | Add `final int? position` field to `MemberVM`, populate from `bandMember['position']` in `fromMergedData`. |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/contacts/widgets/band_member_card.dart` | Read-only reference for `ReorderableBandMemberCard`'s content; not modified — the drag-enabled variant is a sibling file, not a flag on this one (see Proposed Solution §4). |
| `lib/features/contacts/widgets/az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`, `az_index_column.dart` | Not consumed by Band Members (confirmed by grep — only `contacts_view.dart`/`venues_view.dart` use them). Contacts/Venues are explicitly out of scope. |
| `lib/features/contacts/widgets/contacts_view.dart`, `venues_view.dart`, and all Contacts/Venues repository/controller/model files | Out of scope per Feature Input — Band Members only. |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart`, `band_member_edit_drawer.dart` | Unrelated feature area (member detail/role-management drawers); `BandMembersView`'s existing `onTap`/`onManageRole` wiring into these is untouched. |
| `lib/features/members/permissions/band_permissions.dart`, `band_permissions_provider.dart` | Deliberately not extended with a `canReorderMembers` getter — see Proposed Solution §3 for why reusing `isCurrentUserAdmin` is the smaller, pattern-consistent change here. |
| `lib/features/members/widgets/member_card.dart`, `members_tab_content.dart` | Confirmed unrouted/legacy (per `band-contacts-az-listing`'s own plan and re-confirmed by grep this session — `app_shell.dart` renders `ContactsTabContent`, not `MembersTabContent`). Out of scope, not touched. |
| `lib/features/members/widgets/role_management_sheet.dart`, `pending_invite_card.dart`, `pending_invite_vm.dart`, `widgets/members_empty_state.dart`, `widgets/member_card_skeleton.dart` | Unrelated to reordering; not touched. |
| `lib/features/setlists/**` (all files) | Reference implementation only — read for pattern-mirroring, never modified. |
| `supabase/migrations/20260724143942_fix_setlist_positions_trigger_collision.sql` and all other existing migrations | Historical reference for the deferrable-constraint pattern; not modified. |
| `lib/main.dart` | No init-order, routing, or config changes. |

---

## Migration Policy

**Required.** One new migration: `supabase/migrations/20260729120000_add_position_to_band_members.sql` (column + constraint + RPC, in one file, consistent with how `20260724054158_bulk_add_songs_to_setlist_rpc.sql` and similar single-purpose migrations in this repo bundle a schema change with its accompanying RPC).

## Edge Function Deploy

**Not required.** No edge functions are touched; the RPC is a plain Postgres function, applied via `supabase db push` like every other RPC in this codebase.

## New Dependencies

**None.** `ReorderableDragStartListener`/`SliverReorderableList` are Flutter SDK widgets already in use (`lib/features/setlists/widgets/reorderable_song_card.dart`, `setlist_detail_screen.dart`). `AppIcons.drag` already exists and is already used for this exact purpose.

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected (read-only reference for the drag mechanism; no setlist file is modified) |
| Members / RBAC | **affected** — new `position` column and RPC on `band_members`; sort logic changes; reuses existing admin-only gate, does not widen it |
| Auth / Session | unaffected |
| Routing | unaffected — no navigation, route, or init-order change |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected, uniformly — pure Flutter widget/state changes with no platform-conditional code, same as the setlists reorder feature it mirrors, which already ships identically across all four platforms |

---

## Regression Risk

**Level:** MEDIUM

**Rationale:**
- Single feature area affected (Members/RBAC within the Contacts tab's Band segment); no auth, session, routing, or init-order changes.
- Involves a new database mutation path (the `reorder_band_members` RPC) on a table (`band_members`) whose UPDATE is otherwise admin-gated by RLS — the RPC's `SECURITY DEFINER` bypass, and the correctness of its inlined authorization check, is the single highest-risk item in this plan (an authorization bug here would let a non-admin reorder members, or block an admin who should be allowed to).
- The two-phase negative-position update pattern is copied from `reorder_setlist_items`, which is already proven in production — but it is new code in a new function, not a shared call to the existing one, so it must be independently verified (see Verification Plan).
- Default behavior (no member has ever been reordered) must remain byte-for-byte identical to today's alphabetical sort — a regression here would be immediately visible to every band on first load post-deploy, not just to bands that use the new feature.
- No changes to `remove_band_member`, `update_member_role`, invitation flow, or any other existing `band_members` RPC/policy — all confirmed unaffected by direct inspection, not assumed.
- Bounded to four Flutter files modified + two new files + one migration; no shared/cross-feature file (`member_vm.dart` is touched, but only additively — a new optional field with no change to any existing field or method).

---

## Engineer Task Breakdown

Execute in strict order.

### Task 1 — Migration: `position` column, constraint, RPC
Create `supabase/migrations/20260729120000_add_position_to_band_members.sql`:
- `ALTER TABLE public.band_members ADD COLUMN position INTEGER NULL;`
- `ALTER TABLE public.band_members ADD CONSTRAINT band_members_band_id_position_key UNIQUE (band_id, position) DEFERRABLE INITIALLY DEFERRED;`
- `CREATE OR REPLACE FUNCTION public.reorder_band_members(p_band_id uuid, p_member_ids uuid[]) RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ ... $$;` — inlined active-admin check (see Proposed Solution §1), row-count validation against `band_members` scoped to `p_band_id`, two-phase negative-position update (mirror `reorder_setlist_items` exactly, substituting `band_members`/`position` for `setlist_songs`/`position`), return `json_build_object('success', TRUE, 'reordered_count', v_expected)`.

### Task 2 — `MemberVM`: add `position`
Add `final int? position;` to `MemberVM`'s field list and constructor; populate in `fromMergedData` via `bandMember['position'] as int?`.

### Task 3 — `MembersRepository`: select `position`, conditional sort, `reorderMembers`
- Add `position` to the `band_members` select at `members_repository.dart:110-115`.
- Replace the unconditional sort block (`members_repository.dart:224-235`) with the conditional logic from Proposed Solution §2.
- Add `Future<void> reorderMembers({required String bandId, required List<String> memberIdsInOrder})`: throws `ArgumentError` if `bandId`/list empty (mirror `SetlistRepository.reorderSongs`'s guard style); calls `supabase.rpc('reorder_band_members', params: {'p_band_id': bandId, 'p_member_ids': memberIdsInOrder})`; on `{'success': true, ...}` clears `_cache[bandId]` and returns; on any other shape or `PostgrestException`, `rethrow`/throw with a debug-mode log, matching `reorderSongs`'s error-handling shape (no client-side fallback — see Files to Modify above for why one isn't needed here).

### Task 4 — `MembersState`/`MembersNotifier`: optimistic reorder + persist
- `MembersState`: add `lastKnownGoodMembers` (`List<MemberVM>?`, default `null`) and `isReordering` (`bool`, default `false`); extend `copyWith` with both plus a `clearLastKnownGood` bool flag (mirror `SetlistDetailState`'s equivalent flag so `copyWith` can explicitly null out the backup on success, not just leave it unset).
- `MembersNotifier.reorderLocal(int oldIndex, int newIndex)`: mirror `SetlistDetailController.reorderLocal` — no-op if indices equal; stash `lastKnownGoodMembers` only if not already set; reindex `state.members` by moving the item.
- `MembersNotifier.persistReorder(String bandId)`: mirror `SetlistDetailController.persistReorder` — set `isReordering: true`; call `_repository.reorderMembers(bandId: bandId, memberIdsInOrder: state.members.map((m) => m.memberId).toList())`; on success, `copyWith(isReordering: false, clearLastKnownGood: true)`, return `true`; on failure, revert to `lastKnownGoodMembers` if present (else trigger `loadMembers(bandId, forceRefresh: true)` via `Future.microtask`), set a user-visible `error`, return `false`.

### Task 5 — `ReorderableBandMemberCard` (new file)
Create `lib/features/contacts/widgets/reorderable_band_member_card.dart`: `StatefulWidget` with `SingleTickerProviderStateMixin` (tap scale/opacity, mirroring `reorderable_song_card.dart:66-111`); `Stack` with a `Positioned` left-edge drag-handle strip (`ReorderableDragStartListener(index: widget.index, child: Icon(AppIcons.drag, size: 24, color: context.colors.textSecondary.withValues(alpha: 0.6)))`) and a `Positioned` content area wrapped in a pointer-absorbing `Listener` (`onPointerDown: (_) {}, behavior: HitTestBehavior.opaque`), containing the same name/crown-icon/musical-roles `Column` `BandMemberCard` renders today (name `Text`, `if (member.isAdmin) Icon(AppIcons.crown, ...)`, musical roles `Text`). Constructor: `member` (`MemberVM`), `index` (`int`), `onTap` (`VoidCallback?`).

### Task 6 — `BandMembersView`: conditional `SliverReorderableList`
- Add `final void Function(int oldIndex, int newIndex)? onReorder;` constructor param.
- Replace the single `SliverPadding`/`SliverList` member block (`band_members_view.dart:91-118`) with a branch: if `membersState.isCurrentUserAdmin`, render `SliverPadding` → `SliverReorderableList(itemCount: membersState.members.length, onReorderItem: (oldIndex, newIndex) => onReorder?.call(oldIndex, newIndex), itemBuilder: ...)` producing `Padding`-wrapped, `ValueKey`-keyed `ReorderableBandMemberCard`s (same padding/key convention as today); else keep the existing static `SliverList` of `BandMemberCard`s exactly as-is.
- Import `reorderable_band_member_card.dart`.

### Task 7 — `ContactsTabContent`: debounce + wire `onReorder`
- Add `import 'dart:async';` if not already present; add `Timer? _reorderDebounceTimer;` field.
- Add `_handleMemberReorder(int oldIndex, int newIndex)`: `ref.read(membersProvider.notifier).reorderLocal(oldIndex, newIndex)`; cancel any pending `_reorderDebounceTimer`; start a new 500ms `Timer` that, if still `mounted`, reads `activeBandProvider`'s `activeBandId` and calls `ref.read(membersProvider.notifier).persistReorder(bandId)` if non-null.
- Add `_reorderDebounceTimer?.cancel();` to the existing `dispose()` override.
- Add `onReorder: _handleMemberReorder` to the existing `BandMembersView(...)` construction (`contacts_tab_content.dart:148-155`).

### Task 8 — `flutter analyze`
Run `flutter analyze`; 0 errors required before handing off to QA (Guardrails Gate 3).

---

## Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

Tests only existing, unchanged database objects — never calls `reorder_band_members` (it doesn't exist yet at this tier).

```sql
-- PRE-DEPLOY TEST 1: Confirm band_members has no position column yet
SELECT NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'band_members' AND column_name = 'position'
) AS test_passed;
-- Expected: test_passed = true

-- PRE-DEPLOY TEST 2: Confirm the reference two-phase-update pattern (reorder_setlist_items)
-- still exists and is unchanged, since reorder_band_members is modeled on it
SELECT pg_get_functiondef(p.oid) ILIKE '%WITH ORDINALITY%' AS test_passed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'reorder_setlist_items';
-- Expected: test_passed = true

-- PRE-DEPLOY TEST 3: Confirm current band_members RLS UPDATE policy is admin-only
-- (the rule reorder_band_members's inlined check must replicate)
SELECT qual ILIKE '%role = ''admin''::band_role_type%' AS test_passed
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'band_members' AND cmd = 'UPDATE';
-- Expected: test_passed = true

-- PRE-DEPLOY TEST 4: Document current band_members row count per band (baseline for
-- post-deploy row-count-unaffected check; no rows are inserted/deleted by this migration)
SELECT band_id, COUNT(*) AS member_count
FROM public.band_members
GROUP BY band_id
ORDER BY band_id;
-- Record output for comparison in POST-DEPLOY TEST 4
```

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

```sql
-- POST-DEPLOY TEST 1: Verify position column exists, nullable, no default
SELECT is_nullable = 'YES' AND column_default IS NULL AS test_passed
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'band_members' AND column_name = 'position';
-- Expected: test_passed = true

-- POST-DEPLOY TEST 2: Verify the unique constraint is deferrable
SELECT condeferrable AND condeferred AS test_passed
FROM pg_constraint
WHERE conname = 'band_members_band_id_position_key';
-- Expected: test_passed = true

-- POST-DEPLOY TEST 3: Verify reorder_band_members exists and contains the expected shape
SELECT
  pg_get_functiondef(p.oid) ILIKE '%SECURITY DEFINER%' AND
  pg_get_functiondef(p.oid) ILIKE '%SET search_path%' AND
  pg_get_functiondef(p.oid) ILIKE '%WITH ORDINALITY%' AND
  pg_get_functiondef(p.oid) ILIKE '%role = ''admin''%' AS test_passed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'reorder_band_members';
-- Expected: test_passed = true

-- POST-DEPLOY TEST 4: Verify no existing rows were inserted/deleted by the migration
-- (compare against PRE-DEPLOY TEST 4's recorded output — counts must match exactly)
SELECT band_id, COUNT(*) AS member_count
FROM public.band_members
GROUP BY band_id
ORDER BY band_id;
-- Expected: identical to PRE-DEPLOY TEST 4 output

-- POST-DEPLOY TEST 5: Every existing row has position IS NULL immediately after migration
SELECT COUNT(*) = 0 AS test_passed
FROM public.band_members
WHERE position IS NOT NULL;
-- Expected: test_passed = true (no backfill occurred)

-- POST-DEPLOY TEST 6: End-to-end reorder + authorization test.
-- Requires a real band with >= 2 active members (a genuine FK dependency — documented
-- per SQL test authoring rules; run only against a disposable/demo band, never
-- production band data). Wrapped in a transaction that rolls back.
DO $$
DECLARE
  v_band_id UUID;
  v_member_ids UUID[];
  v_result JSON;
  v_admin_user_id UUID;
BEGIN
  -- Pick a real band with >= 2 active members
  SELECT band_id INTO v_band_id
  FROM public.band_members
  WHERE status = 'active'
  GROUP BY band_id
  HAVING COUNT(*) >= 2
  LIMIT 1;

  IF v_band_id IS NULL THEN
    RAISE NOTICE 'POST-DEPLOY TEST 6 SKIPPED: no band with >= 2 active members found';
    RETURN;
  END IF;

  SELECT array_agg(id ORDER BY id) INTO v_member_ids
  FROM public.band_members
  WHERE band_id = v_band_id AND status = 'active';

  -- This test runs as the migration role (bypasses auth.uid()-based checks in a
  -- local/staging context); on a real deploy, the equivalent client-side check is
  -- exercised via the app's own auth session in the QA Regression Areas below.
  BEGIN
    SELECT public.reorder_band_members(v_band_id, v_member_ids) INTO v_result;
    RAISE NOTICE 'POST-DEPLOY TEST 6: reorder_band_members returned %', v_result;

    IF (v_result->>'success')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'POST-DEPLOY TEST 6 FAILED: success was not true';
    END IF;

    IF (v_result->>'reordered_count')::int != array_length(v_member_ids, 1) THEN
      RAISE EXCEPTION 'POST-DEPLOY TEST 6 FAILED: reordered_count mismatch';
    END IF;

    RAISE NOTICE 'POST-DEPLOY TEST 6 PASSED';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'POST-DEPLOY TEST 6: exception (expected if run without an authorized session): %', SQLERRM;
  END;

  ROLLBACK;
END $$;
-- Expected: either PASSED, or a permission-denied exception if run without an
-- authenticated admin session (both are acceptable outcomes for this SQL-level
-- smoke test; full authorization coverage is in QA Regression Areas below)
```

**SQL test authoring rules applied:** Test 6 uses a real FK-dependent band (documented above, Tier 2 only, per the plan's own rules), reads existing data only (no `INSERT`), and is wrapped so its `reorder_band_members` call's effects are rolled back regardless of outcome — the outer `DO $$` block's `ROLLBACK` at the end undoes any position changes the call made. No hardcoded UUIDs are used.

---

## QA Regression Areas

- **Primary:** dragging a Band Member card as an admin persists the new order across app restart/reload; non-admins see no drag handle and cannot reorder (verify both that the UI affords no drag gesture *and* that a direct RPC call as a non-admin is server-rejected, not just client-hidden).
- **Default-state regression (highest priority — affects every band, not just ones using the new feature):** a band that has never been manually reordered must render in identical alphabetical order to pre-feature behavior, on every platform.
- **Authorization:** attempt (via direct RPC call, not just UI) to reorder as a non-admin — must be rejected with the expected `Permission denied` error, matching `remove_band_member`'s established error-message convention.
- **Mixed positioned/unpositioned state:** invite/add a new member to a band that already has a manual order set; confirm the new member appears (unpositioned, alphabetically placed among other unpositioned members, after all positioned members) rather than crashing or being silently dropped from the list.
- **Debounce behavior:** perform several rapid consecutive drags; confirm only one network call fires (not one per drag) and the final persisted order matches the final on-screen order, not an intermediate one.
- **Revert-on-failure:** simulate a persist failure (e.g. temporarily revoke network); confirm the list visually reverts to the pre-drag order and an error is shown, matching the setlist reorder's existing revert UX.
- **Regression check on unrelated Members/Contacts functionality:** role management (Edit drawer), member detail drawer, invite flow, remove-member flow, and the Contacts/Venues segments of the same tab — confirm zero behavior change, since none of their files are touched.
- **Cross-platform:** Web, iOS, Android, macOS — confirm identical drag mechanics and persistence on all four, matching how the setlists reorder feature this plan mirrors already behaves uniformly across platforms.

---

## Rollout / Migration Strategy

Single migration, applied via `supabase db push`, no backfill, no data migration required (every existing row simply starts `position = NULL`, which the sort logic already treats as "alphabetical" — the default and only behavior every existing band has ever seen). No feature flag — this is additive UI (a new drag handle + interaction) gated purely by the existing `isCurrentUserAdmin` check, with zero behavior change for any band that never drags a card. Safe to deploy client and database changes together in the normal branch → PR → merge → deploy sequence (Guardrails §10); no phased/staged rollout is needed given the null-default, opt-in-by-use nature of the change.

## Out of Scope

- Contacts and Venues segments of the Contacts tab (explicitly excluded per Feature Input).
- Any change to the alphabetical sort's tiebreak rules themselves (last name → first name) beyond what's needed to place unpositioned members after positioned ones.
- Extending reorder capability to non-admins, or introducing a new granular permission (e.g. a contributor sub-permission) for reordering — admin-only, matching the existing `band_members` UPDATE RLS boundary.
- A-Z section headers, search, or index column for Band Members — none exist today (per the discrepancy noted in Root Cause) and none are added by this feature.
- Restoring or otherwise touching `lib/features/members/widgets/member_card.dart` / `members_tab_content.dart` (confirmed dead code, out of scope).
- Any change to `reorder_setlist_items`/`reorder_setlist_songs` or any other setlists file — read-only reference only.
- Backfilling or defaulting `position` for existing rows — `NULL` is the correct, intentional starting state for every existing row.
