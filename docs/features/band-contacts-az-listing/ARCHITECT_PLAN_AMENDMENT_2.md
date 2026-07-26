# Band Members & Contacts A-Z Listing — Amendment 2: Band Member Detail + Edit Drawers, Crown Icon

**Amendment Date:** 2026-07-25
**Amendment Author:** Architect
**Trigger:** Product scope addition from Tony, confirmed directly. Base feature is QA-**APPROVED**. Amendment 1 is implemented on disk (per `ENGINEER_REPORT.md`'s Amendment 1 section) but **`QA_REPORT.md` contains no Amendment 1 section** — Amendment 1 has not yet been QA-verified. This amendment builds on top of Amendment 1's uncommitted changes (the `StatelessWidget` `band_members_view.dart` with no search/sections, `BandMemberCard` with the admin kebab). **QA will need to verify Amendment 1 and Amendment 2 together** — see Regression Risk below.

Confirmed on branch `feature/band-contacts-az-listing` via `git branch --show-current`. No new branch created. Nothing outside this amendment's scope was touched during planning (read-only).

**Revision note (same day, same amendment — not Amendment 3):** No implementation of this amendment has happened yet, so this file is revised in place rather than superseded by a new amendment number. This revision resolves the two decisions the original draft below explicitly flagged for Tony, both of which came back reversed from this plan's recommended default: **Decision 1** — Role Management is ported into the Edit drawer's actual functionality (a real bottom sheet containing role selection, sub-permissions, and the last-admin guard), not a link out to the existing full-screen `RoleManagementSheet` page. **Decision 3** — the role-badge icon is crown-only; the eye icon for contributors is dropped entirely. Sections rewritten below are marked **(REVISED)**; everything else (Drawer 1 / `BandMemberDetailDrawer`, Decision 2, the gig-view-drawer investigation) is unchanged from the original draft.

---

## What's Changing and Why

### 1. Band Member detail drawer (new)

Tapping a `BandMemberCard`'s body — currently a no-op (`onTap: null`, since `band_members_view.dart` never passes it) — opens a read-only bottom drawer showing the member's full details: permission role (Admin/Band Member/Contributor), musical roles, and contact info (phone/email/address/birthday) that the pre-simplification `MemberCard` used to show inline on the card itself. The drawer follows the exact mechanics of the existing "gig view drawer" (`ViewGigDrawer`, `lib/features/gigs/widgets/view_gig_drawer.dart`) — the only other bottom-drawer-with-Done/Edit-footer pattern in this codebase.

**Why:** The A-Z card redesign (base feature) intentionally stripped `MemberCard`'s contact rows and role pills down to just name + musical-roles subtitle for scannability, with an explicit note in the base plan that "there is no equivalent 'member detail screen' to push this information to." Tony now wants that screen — surfaced as a drawer, matching the Venues pattern's own precedent of pushing dropped card detail into a dedicated view (`VenueDetailScreen`).

### 2. Edit drawer — relocates Role Management's entry point (not its implementation)

Tapping "Edit" in the detail drawer's footer opens the path to `RoleManagementSheet` — today reached exclusively via `BandMemberCard`'s admin kebab (`⋮`). **The kebab is removed from `BandMemberCard`.**

**Why:** Tony wants Role Management reachable through the new tap-to-view flow rather than a separate kebab icon, consolidating the card's interactive surface into a single tap target.

### 3. Crown icon on the card

`BandMemberCard` gains a role-badge icon before the member's name, ported from the original `MemberCard`'s dropped logic (base plan: "decorative role badge icon (crown/eye), dropped during simplification").

**Why:** Tony wants at-a-glance visibility of who holds elevated permissions directly in the list, without opening the drawer.

---

## Investigation: the gig view drawer pattern

`ViewGigDrawer` (`lib/features/gigs/widgets/view_gig_drawer.dart`) is the only existing "tap a card → bottom drawer with Done + Edit" pattern in the codebase (confirmed via grep for `showModalBottomSheet` + `isScrollControlled: true` combinations; `gig_notes_sheet.dart` uses the identical shell but has no Edit footer). Its shape, quoted verbatim from the source:

**Invocation (`view_gig_drawer.dart:32-52`):**
```dart
static Future<void> show(
  BuildContext context, {
  required Gig gig,
  required String bandTimezone,
  required bool canEdit,
  required VoidCallback onEdit,
  VoidCallback? onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ViewGigDrawer(...),
  );
}
```
- `isScrollControlled: true` so the sheet can size to content up to a `MediaQuery`-relative max height.
- `backgroundColor: Colors.transparent` on the sheet itself — the actual surface color/rounding is drawn by the content widget's own `Container`, giving clean rounded corners with no square modal backdrop behind them.
- No `shape` param on `showModalBottomSheet` — corner radius lives entirely in the content widget.
- Dismissal: default barrier-tap-to-dismiss (Flutter defaults, nothing overridden) plus an explicit "Done" button.

**Outer shell (`view_gig_drawer.dart:242-268`):**
```dart
return Container(
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height * 0.9,
  ),
  decoration: BoxDecoration(
    color: context.colors.surface,
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
    ),
  ),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Drag handle — purely visual, 40x4, context.colors.border, radius 2, 12px top margin, centered
      ...
```
- Body: `Flexible(child: SingleChildScrollView(child: Column([...])))`.
- Detail rows use a private `_DetailRow` widget (label column, fixed 68px width + value + optional chevron, each row followed by a 1px `Divider`, whole row wrapped in `InkWell` when `onTap` is provided).
- Footer (`view_gig_drawer.dart:407-438`) sits **outside** the scrollable `Flexible`, in a fixed `Padding` respecting safe-area bottom inset (`MediaQuery.of(context).padding.bottom + Spacing.space16`): full-width `BrandActionButton(label: 'Done', onPressed: () => Navigator.pop())`, then conditionally (`if (canEdit)`) a full-width `TextButton` labeled "Edit" beneath it.
- The Edit button's handler (`_handleEdit`, lines 208-211) **pops the drawer first, then invokes the `onEdit` callback** — it does not open a second bottom sheet; it navigates elsewhere (a full edit flow) after closing.

`_DetailRow` is a private class (leading underscore) local to `view_gig_drawer.dart` — it cannot be imported. Following this codebase's established precedent for small, non-bug-prone presentational duplication (e.g. `VenueCard._formatCityState()` and `ContactCard._subtitle()` were each kept local rather than extracted into a shared helper, per the base plan and Amendment 1's own reasoning), this plan ports a local, private `_DetailRow` copy into the new drawer file rather than extracting a shared widget. Unlike the A-Z grouping arithmetic (which *was* extracted after causing a real bug via triplicated logic), a label/value row has no arithmetic to drift.

---

## Design Decisions

### Investigation — is `RoleManagementSheet` reachable from anywhere besides `contacts_tab_content.dart`?

Full-codebase search (`grep -rn "RoleManagementSheet"` and `grep -rln "role_management_sheet"` across every `.dart` file in the repo, not just `lib/features/contacts/`) turns up **two** call sites that push the widget, not one:

- `lib/features/contacts/contacts_tab_content.dart:117` — `_openRoleManagement()`, reached via `BandMembersView(onManageRole: _openRoleManagement)`. **Live** — routed through `app_shell.dart` → `ContactsTabContent`.
- `lib/features/members/members_tab_content.dart:140` — its own private `_openRoleManagement()`, structurally identical (same `adminCount` computation from `membersState.members.where((m) => m.isAdmin && m.isActive).length`, same `Navigator.push(fadeSlideRoute(page: RoleManagementSheet(...)))`).

`members_tab_content.dart` is the same file the base `ARCHITECT_PLAN.md` already confirmed is legacy/unrouted: `app_shell.dart` renders `ContactsTabContent`, not `MembersTabContent`, and the only other reference to `MembersTabContent` (`shared/widgets/native_app_banner_integration.dart:45`) sits inside a commented-out (`/* */`) documentation example, not live code — re-confirmed directly by grep in this session, not carried over as an assumption from the earlier plan.

**Decision:** `RoleManagementSheet` has no caller reachable from the running app other than `contacts_tab_content.dart`. Its second caller exists only inside an already-dead, unrouted widget. Once this amendment changes `_openRoleManagement()` in `contacts_tab_content.dart` to open the new ported Edit drawer instead of pushing `RoleManagementSheet` (see Decision 1, revised below), the class becomes unreferenced by any code path actually reachable in the running app — its only remaining reference in the entire repo is from within `members_tab_content.dart`, which is itself unreferenced by the running app. In other words, `role_management_sheet.dart` becomes dead in exactly the same sense `members_tab_content.dart` already is — not in some weaker "still technically used somewhere" sense.

Per this branch's own established precedent (`members_tab_content.dart` was confirmed dead in the base plan and explicitly left in place — "not cleaned up as part of this feature"), this amendment does **not** delete `role_management_sheet.dart`. It stays on disk, unmodified, off-limits. It is stated plainly here that it becomes unreferenced by live code; its removal (and, at that point, `members_tab_content.dart`'s own removal, since deleting one without the other would leave a dangling import) is a future, separate decision — not part of this amendment.

### Decision 1 (REVISED) — Role Management is ported into the Edit drawer's actual functionality, not linked out to the existing full-screen page

**This reverses the original Decision 1 above.** Tony's answer to the flagged question: *"Role Management should now be a part of the Edit view drawer."* The "second drawer" was meant literally: the Edit affordance in `BandMemberDetailDrawer`'s footer must open an actual bottom-sheet-style drawer — matching `BandMemberDetailDrawer`'s and `ViewGigDrawer`'s chrome (rounded top corners, drag handle, scrollable body, fixed footer) — and that drawer must contain Role Management's real functionality: role selection, contributor sub-permission toggles, the last-admin self-guard, and Save/error handling. It is not a link out to the existing full-screen `RoleManagementSheet` page.

**What this changes relative to the original Decision 1:** a new file, `band_member_edit_drawer.dart`, is created containing a full, faithful port of `RoleManagementSheet`'s state and behavior (detailed in Proposed Solution → "Drawer 2" below), and `ContactsTabContent._openRoleManagement()` is edited to open that new drawer via `showModalBottomSheet` instead of pushing `RoleManagementSheet` via `Navigator.push(fadeSlideRoute(...))`. `role_management_sheet.dart` itself is **not modified** — its logic is copied into the new drawer, not extracted or shared, consistent with this codebase's established treatment of small-to-medium presentational/state logic that doesn't need a shared abstraction (see the `_DetailRow` precedent above). Per the Investigation above, this is safe: there is no other live caller whose behavior this change could break.

**Why a full port and not a thin wrapper around the existing widget:** `RoleManagementSheet` is a `Scaffold` with an `AppBar` and a `Scaffold`-level bottom bar — it cannot be dropped into `showModalBottomSheet`'s builder as-is and produce the drawer chrome Tony asked for (rounded top corners, drag handle, no app bar). Getting the chrome right requires the state and callbacks to live in a new widget shaped like `BandMemberDetailDrawer`/`ViewGigDrawer`, not the existing one.

**Risk called out explicitly:** the last-admin guard (`_isSelfAndLastAdmin`/`_isLastAdmin`) is the single highest-risk piece of this amendment to get wrong, because it is a permission/safety guard, not cosmetic chrome. Its exact conditions and exact effects (which buttons disable, the exact warning copy, which actions are hidden vs. merely disabled) must be preserved byte-for-byte, not approximated or "re-derived to look similar." Server-side enforcement (`PostgrestException` messages such as `'at least one admin must remain'`) remains the true backstop and is unchanged — but the client-side UX guard is what QA can actually observe, and a subtly-wrong port would ship a working-looking drawer that lets a user attempt (and get server-rejected) something the original UI correctly prevented before the request was even made.

### Decision 2 — "Edit" is gated to admins only, via the same `isCurrentUserAdmin` boolean the kebab used

**Evidence:** Today, the kebab is conditionally rendered on `BandMemberCard` via `if (showAdminActions) _buildAdminButton(context)` (`band_member_card.dart:59`), where `showAdminActions` is passed in as `membersState.isCurrentUserAdmin` from `band_members_view.dart:107`. Non-admins never see the kebab and have no path to `RoleManagementSheet` today. `isCurrentUserAdmin` is computed server-side via `MembersRepository.isCurrentUserAdmin(bandId)` (`members_repository.dart:399`) and stored on `MembersState`.

`RoleManagementSheet` itself performs no "is the caller an admin" check internally — it trusts its caller and relies on server-side RLS/RPC rejection as the backstop for unauthorized *writes*, but there's no evidence the *read* (opening the sheet, seeing another member's role-change UI) is itself blocked server-side.

**The call:** Gate the detail drawer's "Edit" button behind the exact same `membersState.isCurrentUserAdmin` boolean, applied consistently with the kebab's existing gate. The detail drawer's read-only body (role/instruments/contact info) is shown to **everyone** who taps a card — that's the whole point of the new feature and matches how the pre-simplification `MemberCard` showed this same info to any viewer with card access. Only the "Edit" affordance is admin-gated, exactly replacing the kebab's existing gate rather than loosening it. Not gating "Edit" would be a permission regression: a non-admin could reach `RoleManagementSheet`'s UI (even if a save attempt were ultimately rejected server-side), which is strictly worse than today's behavior where non-admins have no path there at all.

### Decision 3 (REVISED) — Crown only; no eye icon for contributors

**This reverses the original Decision 3 above.** The original draft flagged an ambiguity — replicate `MemberCard._buildRoleIcon()`'s full three-way logic (crown for owner/admin, eye for contributor, none for member) versus a crown-only binary — rather than guess. Tony's answer: *"Crown only."* Admin/Owner get a crown icon. Contributor and plain Member both get **no icon** — the eye-icon/contributor case is dropped entirely, it is not wanted.

**Reference for context** — the original, pre-simplification three-way logic being partially replicated, `MemberCard._buildRoleIcon()` (`member_card.dart:366-384`), gated by `if (_normalizedBandRole != 'member')` (`member_card.dart:128`):
```dart
switch (_normalizedBandRole) {
  case 'owner':
  case 'admin':
    icon = AppIcons.crown;
    break;
  case 'contributor':
    icon = Icons.visibility_outlined;
    break;
  default:
    return const SizedBox.shrink();
}
```
Only the `owner`/`admin` → crown branch is ported. The `contributor` → eye branch is not implemented anywhere in `BandMemberCard`.

**Simplification this enables:** `MemberVM` already exposes `bool get isAdmin => bandRole == 'admin' || bandRole == 'owner';` (`member_vm.dart:226`). Since the only remaining case is a binary crown/no-crown decision, `BandMemberCard`'s ported logic can be `if (member.isAdmin) crown else nothing` — a direct call to the existing `isAdmin` getter — rather than porting `member_card.dart`'s private `_normalizedBandRole` string-normalization-plus-switch machinery. This is a smaller, more direct port than a literal copy of the three-way switch would be, and it's correct precisely because there are only two outcomes now, not three. Icon size 18, color `AppColors.primary`, `top: 6, right: 10` padding immediately before the name `Text` in the header `Row` — unchanged from the original draft's styling.

---

## Proposed Solution

### Drawer 1 — `BandMemberDetailDrawer` (new, read-only)

New file `lib/features/contacts/widgets/band_member_detail_drawer.dart`. `StatelessWidget` with a static `show()` method, structurally identical to `ViewGigDrawer.show()`:

```dart
static Future<void> show(
  BuildContext context, {
  required MemberVM member,
  required bool isAdmin,
  required VoidCallback onManageRole,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BandMemberDetailDrawer(
      member: member,
      isAdmin: isAdmin,
      onManageRole: onManageRole,
    ),
  );
}
```

`build()` shell: identical `Container` (maxHeight 90% of screen height, top-only 20px `BorderRadius`, `context.colors.surface` fill) + drag handle, ported verbatim from `ViewGigDrawer`.

**Body contents (in order), each rendered via a locally-ported private `_DetailRow` widget (label + value + optional chevron/tap, divider below), only rendered when the underlying field is non-null/non-empty — matching `ViewGigDrawer`'s conditional-row pattern:**

1. Header block (not a `_DetailRow` — matches `ViewGigDrawer`'s header treatment): role-badge icon (crown-only, per revised Decision 3 — admin/owner get a crown, contributor and plain member get no icon) + `member.name` as a headline-style `Text`, same visual weight as `ViewGigDrawer`'s `gig.name` header.
2. `Divider(height: 1)`.
3. **Role** — always shown. Value derived from `member.bandRole` via a small mapping: `isAdmin` (owner/admin) → `'Admin'`, `isContributor` → `'Contributor'`, else → `'Band Member'`. Not tappable.
4. **Instruments** — shown only if `member.musicalRoles.isNotEmpty`. Value: `member.musicalRoles.join(', ')`. Not tappable.
5. **Phone** — shown only if `member.phone != null && member.phone!.isNotEmpty`. Value: `formatPhoneNumber(member.phone!)` (existing shared util, `lib/app/utils/phone_formatter.dart` — imported, not duplicated). Tappable: `onTap` launches `tel:<digits>` via a locally-ported `_launchPhone()` (same `RegExp(r'[^\d+]')` digit-stripping and `canLaunchUrl`/`launchUrl` try/catch-fail-silently pattern as `member_card.dart:276-289`).
6. **Email** — shown only if `member.email.isNotEmpty`. Value: `member.email`. Tappable: `onTap` launches `mailto:` via a locally-ported `_launchEmail()` (same pattern as `member_card.dart:293-304`).
7. **Address** — shown only if address/city/zip has any non-empty value (`_hasAddress` check, ported from `member_card.dart:236-240`). Value: comma-joined `address, city, zip` (ported `_formatAddress`, `member_card.dart:242-254`). Not tappable.
8. **Birthday** — shown only if `member.birthday != null`. Value: "Month Day" format (ported `_formatBirthday`, `member_card.dart:256-272`). Not tappable.

**Footer** (fixed, outside the scroll area, safe-area-aware padding — identical structure to `ViewGigDrawer`'s footer):
- `BrandActionButton(label: 'Done', fullWidth: true, onPressed: () => Navigator.of(context).pop())`.
- If `isAdmin`: full-width `TextButton` labeled `'Edit'` beneath it, styled identically to `ViewGigDrawer`'s Edit button (`AppTextStyles.calloutEmphasized.copyWith(color: AppColors.primary)`), `onPressed` pops the drawer then calls `onManageRole()` — mirroring `ViewGigDrawer._handleEdit()` exactly (pop-then-callback, not callback-then-pop, so the drawer is gone before `RoleManagementSheet` is pushed).
- If not `isAdmin`: no Edit button rendered at all (not disabled/greyed — omitted entirely, matching how the kebab is omitted today rather than shown-but-disabled).

### Drawer 2 — `BandMemberEditDrawer` (new, ported Role Management functionality)

As established in the revised Decision 1: this is a **new** file, `lib/features/contacts/widgets/band_member_edit_drawer.dart`, containing a full functional port of `RoleManagementSheet`'s state and behavior wrapped in the drawer chrome established by `BandMemberDetailDrawer`/`ViewGigDrawer`. `role_management_sheet.dart` is not modified and not invoked by this drawer — its logic is copied, not called.

`BandMemberEditDrawer` is a `ConsumerStatefulWidget` (needs `ref` for `membersProvider.notifier.updateRole()`, `membersRepositoryProvider.fetchContributorPermissions()`, `activeBandProvider`, and `membersProvider.notifier.removeMember()` — the same four calls `RoleManagementSheet` already makes) with a static `show()` method:

```dart
static Future<void> show(
  BuildContext context, {
  required MemberVM member,
  required int adminCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BandMemberEditDrawer(member: member, adminCount: adminCount),
  );
}
```

**State — ported verbatim from `_RoleManagementSheetState`, field-for-field, method-for-method:**
- `_selectedRole`, `_initialRole`, `_subPermissions`, `_initialSubPermissions`, `_isSaving`, `_isRemoving` — same fields, same `initState()` logic (owner→admin normalization, `ContributorPermissions.allEnabled` defaults, post-frame `_loadExistingPermissions()` fetch for existing contributors).
- `_isSelfAndLastAdmin` / `_isLastAdmin` — ported **exactly**, condition-for-condition:
  ```dart
  bool get _isSelfAndLastAdmin {
    final currentUserId = supabase.auth.currentUser?.id;
    return widget.member.userId == currentUserId &&
        widget.member.isAdmin &&
        widget.adminCount <= 1;
  }
  bool get _isLastAdmin => widget.member.isAdmin && widget.adminCount <= 1;
  ```
- `_hasChanges`, `_permissionsEqual()` — ported verbatim (dirty-detection driving the Save button's enabled state).
- `_saveRole()` — ported verbatim, including the exact `PostgrestException` message-substring mapping (`'at least one admin must remain'` → *"Cannot demote: at least one admin must remain"*, `'Permission denied'` → *"Only admins can change roles"*, `'Member not found'` → *"Member not found in this band"*, `'Could not find the function'` → *"Server update needed — please try again in a moment"*, generic fallback otherwise) and the success path (`showSuccessSnackBar` + close the drawer via `Navigator.of(context).pop()` instead of the original's page-pop — same call, different route type).
- `_removeMember()` — ported verbatim, including the confirmation `AlertDialog` (title `'Remove ${widget.member.name}?'`, body copy, Cancel/Remove actions, error-red styling) and the success/failure snackbar + pop behavior.

**Chrome — adapted from `BandMemberDetailDrawer`/`ViewGigDrawer`, not from `RoleManagementSheet`'s `Scaffold`/`AppBar`:**
- Outer shell: `Container` (maxHeight 90% of screen height via `MediaQuery`, top-only 20px `BorderRadius`, `context.colors.surface` fill) + drag handle — identical construction to `BandMemberDetailDrawer`'s shell.
- No `AppBar`/close-X. In its place: a header area inside the shell — `'Manage Role'` label, then `member.name` + current role display (the exact content `RoleManagementSheet`'s scrollable body opened with today), then `Divider(height: 1)`. Dismissal without saving is via backdrop-tap (standard `showModalBottomSheet` behavior) or the Cancel button in the footer — this matches `ViewGigDrawer`'s own dismissal model (barrier-tap plus an explicit button, no dedicated close icon) rather than inventing new chrome.
- Body: `Flexible(child: SingleChildScrollView(...))` containing, in the same order as today: "Change role" section + the three role toggle buttons (`_buildRoleButton`, ported verbatim including each button's exact `enabled:` expression — `!(_isLastAdmin && _selectedRole == 'admin')` for Admin, `!_isSelfAndLastAdmin` for Member and Contributor), the contributor sub-permission toggles block (all six `_buildPermissionToggle` calls, shown only `if (_selectedRole == 'contributor')`), the last-admin warning `Container` (shown only `if (_isSelfAndLastAdmin)`, exact copy *"You are the only admin. You cannot change your own role."*, exact warning styling), and the "Remove from band" button (shown only `if (!_isLastAdmin)`).
- Footer: fixed, outside the scrollable `Flexible`, safe-area-aware padding (`MediaQuery.of(context).padding.bottom + Spacing.space16`, matching the drawer-footer convention) — `_buildFixedBottomActions()` ports over almost as-is, since its existing shape (full-width primary Save button with `_hasChanges && !_isSaving`-gated enabled state, secondary Cancel `TextButton` beneath it) already matches a drawer footer's conventions; it only moves from being a `Scaffold`'s bottom `Column` child to being the fixed last child of the new drawer's outer `Column`, same as `ViewGigDrawer`'s Done/Edit footer sits outside its own `Flexible`.

**What is not ported:** the `Scaffold`, `AppBar`, and their associated `SafeArea` wrapper — those are chrome specific to a full-screen page and are replaced by the `Container`/drag-handle/header shell described above. Everything else — every field, every getter, every method, every conditional render, every string — is a direct port.

### `BandMemberCard` changes

- **Kebab removed.** Delete `_buildAdminButton()`, the `showAdminActions` and `onManageRole` constructor params, and the conditional `if (showAdminActions) _buildAdminButton(context)` in the header `Row`. The card's interactive surface becomes a single tap target (the whole card, via the already-declared `onTap` param) — no more secondary icon-button tap target.
- **Crown icon added (crown only, per revised Decision 3).** Insert a role-badge icon as the first child of the header `Row`, before the `Expanded(child: Text(member.name...))`, using `top: 6, right: 10` padding and 18px/`AppColors.primary` styling matching `member_card.dart`'s `_buildRoleIcon()`. Logic: `if (member.isAdmin) Icon(AppIcons.crown, ...) else nothing` — a direct use of `MemberVM.isAdmin` (`member_vm.dart:226`), not a ported switch statement, since crown-only collapses to a binary check. Requires adding the `app_icons.dart` import (not currently imported by this file).
- `onTap` (already declared, currently always `null` from the only call site) now gets wired by the caller to open `BandMemberDetailDrawer.show(...)`.

### `BandMembersView` changes

In the `BandMemberCard(...)` construction (`band_members_view.dart:105-109`), replace the removed `showAdminActions`/`onManageRole` args with:
```dart
child: BandMemberCard(
  member: member,
  onTap: () => BandMemberDetailDrawer.show(
    context,
    member: member,
    isAdmin: membersState.isCurrentUserAdmin,
    onManageRole: () => onManageRole(member),
  ),
),
```
`BandMembersView`'s own `onManageRole` constructor param (`void Function(MemberVM) onManageRole`, fed by `ContactsTabContent` as `_openRoleManagement`) is **unchanged in signature** — only its trigger point moves from the card's kebab to the drawer's Edit button.

---

## Database Impact

**Not applicable.** Confirmed by direct inspection, not assumed:

- `MemberVM` already declares `phone`, `address`, `city`, `zip`, `birthday` (`member_vm.dart:37-52`) alongside the already-used `musicalRoles`/`bandRole`.
- `MembersRepository`'s `users` table query already selects all five: `select('id, email, first_name, last_name, phone, address, city, zip, birthday, roles, profile_completed, created_at')` (`members_repository.dart:133-138`).
- `MemberVM.fromMergedData` genuinely maps each field from the queried row (`member_vm.dart:128-134`, `196-200`) — not defaulted to null. This data is already fetched on every load of the Band segment today; this amendment only adds UI that reads fields that were already present on `membersState.members[i]` and simply not rendered by the simplified card.
- **No new columns, queries, RPCs, or RLS changes.** No migration.
- `BandMemberEditDrawer` calls the exact same repository/provider methods `RoleManagementSheet` already calls today — `membersProvider.notifier.updateRole()`, `membersProvider.notifier.removeMember()`, `membersRepositoryProvider`'s `fetchContributorPermissions()` — with identical parameters. No new repository or controller method is added; this is a UI-layer port of an existing call pattern, not a new data-access path.
- **Visibility note (not a new exposure):** these same fields (phone/address/birthday) were already rendered, to the same audience (any user who can see the card), by the original pre-simplification `MemberCard` before the base feature shipped. This amendment restores that visibility via a drawer instead of inline card rows — it does not broaden who can see what relative to that established precedent. A repository-level RLS audit of the `users` table select was attempted during planning; the migration this select's RLS depends on (referenced in a code comment as `056_users_rls_band_members.sql`) was not found in `supabase/migrations/` (numbering jumps 075→084), so the exact policy text could not be directly verified — but since the query and its result are already live and already exposed via the currently-shipped simplified card's underlying `MemberVM` (just unrendered), this amendment introduces no new query surface to audit.

---

## Flutter Architecture Changes

### New files
- `lib/features/contacts/widgets/band_member_detail_drawer.dart` — `BandMemberDetailDrawer` (`StatelessWidget` + static `show()`), private `_DetailRow` widget (local copy).
- `lib/features/contacts/widgets/band_member_edit_drawer.dart` — `BandMemberEditDrawer` (`ConsumerStatefulWidget` + static `show()`), a full functional port of `RoleManagementSheet`'s state/behavior wrapped in drawer chrome (see Proposed Solution → "Drawer 2" above).

### Modified widgets
- `lib/features/contacts/widgets/band_member_card.dart` — remove kebab/`showAdminActions`/`onManageRole`; add crown-only role-badge icon (`member.isAdmin`); wire `onTap` (already declared) to be actually passed by the caller.
- `lib/features/contacts/widgets/band_members_view.dart` — `BandMemberCard` construction updated: drop `showAdminActions`/`onManageRole` args, add `onTap` that opens `BandMemberDetailDrawer.show(...)`. `BandMembersView`'s own `onManageRole` prop signature is unchanged.
- `lib/features/contacts/contacts_tab_content.dart` — `_openRoleManagement()` rewritten to call `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)` instead of `Navigator.push(fadeSlideRoute(page: RoleManagementSheet(...)))`. `adminCount` computation is unchanged. Import of `role_management_sheet.dart` removed; import of the new `band_member_edit_drawer.dart` added. The `BandMembersView(onManageRole: _openRoleManagement)` wiring itself — the callback's signature and where it's threaded — is unchanged; only `_openRoleManagement`'s own implementation changes.

### Unchanged
- `lib/features/members/widgets/role_management_sheet.dart` — not modified. Its logic is ported (copied) into the new `BandMemberEditDrawer`, not called by it. Per the Investigation above, this file becomes unreferenced by any live code path once `_openRoleManagement()` changes — left in place, off-limits, not deleted.
- `lib/features/members/member_vm.dart`, `members_controller.dart`, `members_repository.dart` — unchanged; all consumed fields/methods already exist and are already used identically by the code being ported from.
- `lib/features/members/widgets/member_card.dart` — unchanged (still serves legacy `members_tab_content.dart`); its role-icon logic is the reference this amendment partially ports from (crown branch only), not modifies.
- Venues, Contacts segments, all shared `az_*` helper files — untouched by this amendment.

### Unidirectional data flow (Guardrails §9)
`ContactsTabContent` still owns the `onManageRole` mutation-trigger callback and passes it down by constructor; `BandMembersView` still passes state/callbacks down to `BandMemberCard` by constructor; `BandMemberDetailDrawer`'s Edit button still pops itself and then invokes the same `onManageRole` callback chain rather than performing the mutation itself — consistent with "leaf widgets do not perform cross-feature mutations." What changes: `_openRoleManagement()` — the function `onManageRole` ultimately resolves to, owned by `ContactsTabContent` — now opens a second modal bottom sheet (`BandMemberEditDrawer`) instead of pushing a full-screen route; the mutation itself (`updateRole`/`removeMember` via `membersProvider.notifier`) still happens no higher than the drawer that directly triggers it, same as it did inside `RoleManagementSheet` before.

---

## Files to Create

| File | Justification |
|---|---|
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | New read-only detail drawer, replicating the `ViewGigDrawer` bottom-sheet pattern. No existing widget serves this purpose. |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart` | New Edit drawer containing a full functional port of `RoleManagementSheet` (role selection, contributor sub-permissions, last-admin guard, save/error handling) wrapped in the same drawer chrome as `BandMemberDetailDrawer`/`ViewGigDrawer`. Required because `RoleManagementSheet` itself is a `Scaffold`/`AppBar` page, not a bottom-sheet-shaped widget, and per Tony's explicit decision, Role Management is now part of the Edit drawer's actual functionality — not a link out to the existing page. |

---

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/contacts/widgets/band_member_card.dart` | Remove kebab (`_buildAdminButton`, `showAdminActions`, `onManageRole` params). Add crown-only role-badge icon before the name (`if (member.isAdmin) crown else nothing`, per revised Decision 3 — no eye icon). `onTap` param stays (already declared), now actually wired by the caller. |
| `lib/features/contacts/widgets/band_members_view.dart` | `BandMemberCard(...)` construction: drop `showAdminActions`/`onManageRole` args, add `onTap: () => BandMemberDetailDrawer.show(context, member: member, isAdmin: membersState.isCurrentUserAdmin, onManageRole: () => onManageRole(member))`. `BandMembersView`'s own constructor signature (including its `onManageRole` param) is unchanged. |
| `lib/features/contacts/contacts_tab_content.dart` | `_openRoleManagement()` rewritten to compute `adminCount` (unchanged logic) and call `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)` instead of `Navigator.push(fadeSlideRoute(page: RoleManagementSheet(...)))`. Remove the `role_management_sheet.dart` import; add the `band_member_edit_drawer.dart` import. No other change to this file. |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/members/widgets/role_management_sheet.dart` | Not modified — its logic is ported (copied) into the new `BandMemberEditDrawer`, not reused by reference. Per the Investigation above, it becomes unreferenced by any live code path once `contacts_tab_content.dart` changes, but is left in place rather than deleted, matching this branch's established precedent for confirmed-dead files (`members_tab_content.dart`). Its removal is a future, separate decision. |
| `lib/features/members/member_vm.dart` | All needed fields (`phone`, `address`, `city`, `zip`, `birthday`, `musicalRoles`, `bandRole`, `isAdmin`) already present and already correctly populated; confirmed by inspection, not assumed. |
| `lib/features/members/members_controller.dart`, `members_repository.dart` | `membersProvider` is shared app-wide; this amendment reads already-fetched fields, no query change needed. |
| `lib/features/members/widgets/member_card.dart` | Reference/source for ported logic (role icon, contact-row formatting) — not modified. Still serves legacy `members_tab_content.dart`. |
| `lib/features/members/members_tab_content.dart` | Confirmed unrouted/legacy (base plan). Out of scope, not touched. |
| `lib/features/contacts/widgets/venues_view.dart`, `venue_card.dart`, `venue_detail_screen.dart`, `venue_form_screen.dart`, `venues_controller.dart`, `venues_repository.dart` | Out of scope — Venues untouched. |
| `lib/features/contacts/widgets/contacts_view.dart`, `contact_card.dart`, `contact_form_screen.dart`, `contacts_controller.dart`, `contacts_repository.dart`, `models/contact.dart` | Out of scope — Contacts untouched by this amendment. |
| `lib/features/contacts/widgets/az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`, `az_index_column.dart` | Not consumed by this amendment (Band Members has no search/sections/index-column, per Amendment 1). Unaffected. |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Reference pattern only — read, not modified. |
| `lib/app/utils/phone_formatter.dart` | Existing shared util, imported as-is by the new drawer; not modified. |
| `supabase/migrations/*` | No database changes — see Database Impact. |
| `lib/main.dart` | No routing/init changes — uses `showModalBottomSheet`/existing `Navigator.push` only. |

---

## Migration Policy

**Not required.** No database changes.

---

## Edge Function Deploy

**Not required.** No backend changes.

---

## New Dependencies

**None.** `url_launcher` (for `tel:`/`mailto:` launches in the new drawer) is already a dependency, already used identically by `member_card.dart`.

---

## Regression Risk

**Level:** HIGH (up from the original draft's MEDIUM)

**Rationale — why this is a meaningfully bigger change than the original draft's rationale accounted for:**

- **The original Decision 1 was a reachability-path change only** — `role_management_sheet.dart` stayed untouched, so the only new risk was "does the same, unmodified, already-QA-relevant screen still open correctly from a new entry point." **The revised Decision 1 is not that.** It requires re-implementing a working, stateful, permission-sensitive UI — role selection with three interdependent enabled/disabled states, six contributor sub-permission toggles with async load-on-open, dirty-detection gating Save, four distinct `PostgrestException` message mappings, a destructive confirm-then-remove flow — inside new chrome, from scratch, in a new file. This is a full reimplementation of business logic, not a relocation of a button. The regression surface is the entire Role Management feature, not just "does tapping Edit still lead somewhere."
- **The last-admin guard is a permission/safety guard, not cosmetic UI**, and it is now duplicated logic living in two files (the original, now-dead-but-still-compiled `role_management_sheet.dart`, and the new `band_member_edit_drawer.dart`) that must independently produce identical behavior. A subtle divergence — a `<=` written as `<`, a missed `mounted` check, a warning shown under slightly different conditions — would not fail loudly; it would silently let a user attempt (and get server-rejected) an action the original UI correctly prevented from being attempted at all. This class of bug is exactly why the Verification Plan Addendum below expands Test AM2-2 to cover every role-transition case and the guard specifically, rather than a single happy-path check.
- **This amendment still touches the admin-role-management flow's entry point and, now, its implementation, for the second time in this branch's history** — Amendment 1 already changed `band_members_view.dart` from `StatefulWidget` back to `StatelessWidget` around the same flow, and QA's base-feature pass already called the kebab→`RoleManagementSheet` flow "the highest-risk item" once. Stacking a full logic port on top of that history, in the same uncommitted branch, compounds rather than resets that risk.
- **Amendment 1 has not yet been QA-approved** (`QA_REPORT.md` has no Amendment 1 section). This amendment's `band_members_view.dart`/`band_member_card.dart` edits land on top of Amendment 1's uncommitted, unverified changes to the same two files. QA should treat Band Members as needing a **combined regression pass covering base feature + Amendment 1 + Amendment 2 together**, not Amendment 2 in isolation — Amendment 1's own admin-kebab-survives-refactor verification (Test AM1, item 7) has not yet happened and this amendment removes the very kebab that test was written to check, so that specific test as written is now moot and must be superseded by this amendment's drawer-based equivalent (see Verification Plan Addendum below).
- **Behavior change for every user, not just admins:** previously, tapping a `BandMemberCard`'s body was a documented no-op for everyone. Now it opens a drawer for everyone — this is new interactive surface for non-admin users who previously had zero card-tap behavior to regress.
- Read-only data exposure in the new detail drawer (phone/address/birthday) is not a *new* exposure — it matches the original pre-simplification `MemberCard`'s established visibility — but should still be spot-checked as part of QA's pass since it's newly re-surfaced UI.
- No backend/database changes at all, and the port calls the exact same repository/provider methods with the exact same parameters (see Database Impact above) — this bounds the risk to the Flutter client layer and to faithful reproduction of existing state logic, not to any new data-access surface. This is the one thing keeping this at HIGH rather than the higher end of what a from-scratch permission UI would otherwise warrant.

---

## Engineer Task Breakdown

Continuing from Amendment 1's Task 18. Execute in strict order. This section covers only this amendment's delta — do not re-do Tasks 1–18. **Engineer must confirm Amendment 1's changes are present on disk (`band_members_view.dart` is currently a `StatelessWidget`, `band_member_card.dart` has the admin kebab) before starting** — if not, stop and report to Architect, since this amendment assumes Amendment 1 landed first.

### Task 19: Create `BandMemberDetailDrawer`

- Create `lib/features/contacts/widgets/band_member_detail_drawer.dart`:
  - `BandMemberDetailDrawer` (`StatelessWidget`): `member` (`MemberVM`), `isAdmin` (`bool`), `onManageRole` (`VoidCallback`).
  - Static `show(BuildContext, {required MemberVM member, required bool isAdmin, required VoidCallback onManageRole})` → `showModalBottomSheet<void>(context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: ...)`, ported from `ViewGigDrawer.show()`.
  - `build()`: `Container` shell (maxHeight 90%, top-20px-radius, `context.colors.surface`) + drag handle, ported verbatim from `ViewGigDrawer.build()` lines 242-268.
  - Header block: role-badge icon (per revised Decision 3, crown-only: `owner`/`admin` → `AppIcons.crown`, `contributor`/`member` → no icon; 18px, `AppColors.primary`) + `member.name` headline text.
  - `Divider(height: 1)`.
  - Local private `_DetailRow` widget, ported from `view_gig_drawer.dart:451-511` (label/value/optional-chevron/optional-onTap/divider-below).
  - Rows: Role (always, label mapped from `member.bandRole` via `isAdmin`/`isContributor` → 'Admin'/'Contributor'/'Band Member'), Instruments (if `musicalRoles.isNotEmpty`), Phone (if present, tappable `tel:` via locally-ported `_launchPhone`, formatted via `formatPhoneNumber` from `lib/app/utils/phone_formatter.dart`), Email (if present, tappable `mailto:` via locally-ported `_launchEmail`), Address (if `_hasAddress`, via locally-ported `_formatAddress`/`_hasAddress`), Birthday (if present, via locally-ported `_formatBirthday`) — all four ported verbatim from `member_card.dart`'s equivalent private methods.
  - Footer: `BrandActionButton(label: 'Done', fullWidth: true, onPressed: () => Navigator.of(context).pop())`; if `isAdmin`, a full-width `TextButton` labeled `'Edit'` beneath it (`AppTextStyles.calloutEmphasized.copyWith(color: AppColors.primary)`), `onPressed: () { Navigator.of(context).pop(); onManageRole(); }` — pop-then-call, matching `ViewGigDrawer._handleEdit()`.

### Task 20: Update `BandMemberCard` — remove kebab, add crown-only icon

- Edit `band_member_card.dart`: remove `_buildAdminButton()`, the `showAdminActions` and `onManageRole` constructor params, and the `if (showAdminActions) _buildAdminButton(context)` line in the header `Row`.
- Add role-badge icon as the first child of the header `Row` (before the `Expanded` name `Text`), `top: 6, right: 10` padding, 18px, `AppColors.primary`: `if (member.isAdmin) Icon(AppIcons.crown, ...) else nothing` — crown only, per revised Decision 3 (**do not** port the `contributor` → eye branch; it is explicitly dropped). Add `import 'package:bandroadie/app/theme/app_icons.dart';`.
- `onTap` param stays as-is (already declared, already optional) — no change needed to the widget itself beyond removing the two deleted params.

### Task 21: Wire `BandMembersView` to open the new detail drawer

- Edit `band_members_view.dart`: in the `BandMemberCard(...)` construction, remove `showAdminActions: membersState.isCurrentUserAdmin` and `onManageRole: () => onManageRole(member)`, add `onTap: () => BandMemberDetailDrawer.show(context, member: member, isAdmin: membersState.isCurrentUserAdmin, onManageRole: () => onManageRole(member))`.
- Add `import 'band_member_detail_drawer.dart';`.
- No change to `BandMembersView`'s own constructor/params.

### Task 22: Create `BandMemberEditDrawer` — port `RoleManagementSheet`'s full functionality into drawer chrome

- Create `lib/features/contacts/widgets/band_member_edit_drawer.dart`:
  - `BandMemberEditDrawer` (`ConsumerStatefulWidget`): `member` (`MemberVM`), `adminCount` (`int`). Static `show(BuildContext, {required MemberVM member, required int adminCount})` → `showModalBottomSheet<void>(context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: ...)`.
  - Port, field-for-field and method-for-method, from `_RoleManagementSheetState` (`role_management_sheet.dart`): `_selectedRole`, `_initialRole`, `_subPermissions`, `_initialSubPermissions`, `_isSaving`, `_isRemoving`, `initState()` (including the post-frame `_loadExistingPermissions()` call for existing contributors), `_loadExistingPermissions()`, `_isSelfAndLastAdmin`, `_isLastAdmin`, `_hasChanges`, `_permissionsEqual()`, `_saveRole()` (including the exact `PostgrestException` message-substring-to-copy mapping), `_removeMember()` (including the confirmation `AlertDialog`), `_buildRoleButton()`, `_buildPermissionToggle()`, `_roleDisplayName()`. Every condition, string, and enabled-state expression must match the source exactly — this is a port, not a rewrite.
  - Chrome: outer `Container` shell (maxHeight 90%, top-only 20px `BorderRadius`, `context.colors.surface`) + drag handle, ported from `BandMemberDetailDrawer`'s/`ViewGigDrawer`'s shell (not from `RoleManagementSheet`'s `Scaffold`/`AppBar`). Header area inside the shell: `'Manage Role'` label + `member.name` + current role display (the same content `RoleManagementSheet`'s body opened with) + `Divider(height: 1)`. No close-X — dismissal is via backdrop-tap or the footer's Cancel button.
  - Body: `Flexible(child: SingleChildScrollView(...))` rendering, in original order: "Change role" section + three role buttons, contributor sub-permission toggles (`if (_selectedRole == 'contributor')`), last-admin warning block (`if (_isSelfAndLastAdmin)`, exact copy), "Remove from band" button (`if (!_isLastAdmin)`).
  - Footer: fixed, outside the `Flexible`, safe-area-aware padding — port `_buildFixedBottomActions()` near-verbatim (full-width Save `FilledButton` gated by `_hasChanges && !_isSaving`, Cancel `TextButton` beneath it that pops the drawer).
  - Required imports mirror `role_management_sheet.dart`'s: `supabase_client.dart` (for `supabase.auth.currentUser`), `snackbar_helper.dart`, `active_band_controller.dart`, `member_vm.dart`, `members_controller.dart`, `members_repository.dart`, `contributor_permissions.dart`, `app_icons.dart`, `brand_colors.dart`, `design_tokens.dart`, plus `package:supabase_flutter/supabase_flutter.dart show PostgrestException`.

### Task 23: Update `ContactsTabContent._openRoleManagement()` to open the new Edit drawer

- Edit `contacts_tab_content.dart`: in `_openRoleManagement(MemberVM member)`, keep the existing `adminCount` computation (`membersState.members.where((m) => m.isAdmin && m.isActive).length`) unchanged. Replace `Navigator.of(context).push(fadeSlideRoute(page: RoleManagementSheet(member: member, adminCount: adminCount)))` with `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)`.
- Remove the now-unused `import '../members/widgets/role_management_sheet.dart';`. Add `import 'widgets/band_member_edit_drawer.dart';`.
- No other change to this file — the `BandMembersView(onManageRole: _openRoleManagement)` wiring itself is untouched.

### Task 24: Cross-platform manual verification

- Web (per established precedent — static `flutter build web` release build, real Supabase demo account). iOS/Android/macOS if available.
- Exercise per the Verification Plan Addendum below.

---

## Verification Plan Addendum

In addition to (not replacing) the base plan's Verification Plan and Amendment 1's Addendum — all Venues/Contacts items and Amendment 1's Test AM2 (Contacts company field) remain in force, unaffected by this amendment. **Amendment 1's Test AM1 item 7** ("admin kebab still opens RoleManagementSheet") is superseded by Test AM2-2/AM2-3 below, since the kebab no longer exists after this amendment — QA should run the combined Band Members test below in place of the now-obsolete kebab-specific check.

### Test AM2-1: Detail Drawer — Read-Only Content

1. Navigate to Contacts tab → Band segment.
2. Tap a member card body (not on any button). Confirm the drawer opens with the `ViewGigDrawer`-style mechanics: slides up from bottom, rounded top corners, drag handle, dims background, dismissible by tapping the backdrop.
3. Confirm the drawer header shows the member's name with the correct role icon per revised Decision 3 (crown for an admin/owner member, **no icon** for a contributor or plain member) — test with at least an admin/owner and a non-admin member if the demo band has them, otherwise flag as not fully exercised.
4. Confirm "Role" row shows the correct human-readable label (Admin/Band Member/Contributor) matching the member's actual `bandRole`.
5. Confirm "Instruments" row shows comma-joined musical roles, or is omitted (not blank) if the member has none.
6. Confirm Phone/Email/Address/Birthday rows appear only when the underlying data is present, each correctly formatted (phone via existing formatter, birthday as "Month Day", address as comma-joined).
7. Tap the Phone row → confirm the device dialer opens (or fails silently if unavailable) — no crash.
8. Tap the Email row → confirm the mail client opens (or fails silently) — no crash.
9. Confirm "Done" closes the drawer with no side effects.

### Test AM2-2: Edit Drawer — Ported Role Management Logic (highest-risk item in this amendment)

This supersedes the original draft's "verify `RoleManagementSheet` still opens" scope. `RoleManagementSheet`'s logic has been **re-implemented** inside `BandMemberEditDrawer`, not merely relocated — every case below must be verified against the new drawer directly, since there is no longer an unmodified reference screen in the live path to fall back on if something is subtly wrong.

**Chrome / entry:**
1. As an admin: open a member's detail drawer, confirm an "Edit" text button appears beneath "Done".
2. Tap "Edit" → confirm the detail drawer closes, then `BandMemberEditDrawer` opens as a **second modal bottom sheet** (slides up from bottom, rounded top corners, drag handle, dims background) — not a full-screen page push.
3. Confirm the drawer header shows "Manage Role", the member's name, and their current role label, matching what `RoleManagementSheet`'s body used to show at the top.

**Role selection — every transition case:**
4. For a member currently on "Band Member": confirm tapping Admin/Contributor selects it (radio indicator updates), confirm Save is disabled until a role actually changes, then enabled once it does.
5. For a member currently on "Contributor": confirm the six sub-permission toggles appear immediately (pre-populated from the member's actual saved permissions, not defaulted to all-enabled — verify against a contributor whose permissions are known/were previously set to a non-default mix). Toggle at least two, confirm Save becomes enabled, confirm untoggling back to the original state disables Save again (dirty-detection must compare against the *loaded* permissions, not just "any toggle touched").
6. Switch a contributor's role to Admin or Member: confirm the sub-permission section disappears.
7. Save a role change for a non-self member: confirm success snackbar, drawer closes, list reflects the new role. Revert to the original value afterward (test-data-cleanup discipline, matching prior QA practice).

**Last-admin guard — both conditions, independently:**
8. Open the **current logged-in admin's own** drawer where they are the sole admin (`adminCount <= 1`) → Edit: confirm the Member and Contributor buttons are visibly disabled, confirm the Admin button is also disabled (since `_isLastAdmin && _selectedRole == 'admin'` is also true here), confirm the warning container renders with the exact copy **"You are the only admin. You cannot change your own role."**, confirm Save stays disabled throughout (no possible state change), confirm the "Remove from band" button does **not** render.
9. If a second admin exists (so `adminCount > 1`): open that admin's own drawer → confirm the self-guard does *not* trigger (no warning, Member/Contributor selectable), confirm "Remove from band" *is* rendered (since `_isLastAdmin` is false).
10. Open a **different** member's drawer while the viewer is the sole admin (guard is member-specific, not viewer-specific in general — but confirm `_isSelfAndLastAdmin` is false here since `widget.member.userId != currentUserId`): confirm no self-guard warning, confirm that other member's Admin/Member/Contributor buttons behave normally.

**Error handling:**
11. If reproducible without corrupting test data (e.g. via a second browser tab racing a demote against a delete, or by temporarily disconnecting network mid-save): confirm at least one non-happy-path save shows an error snackbar rather than a silent failure or crash. Full reproduction of all four `PostgrestException` message-substring branches is not required if not independently triggerable, but at minimum confirm the generic catch-all error path produces a visible, non-crashing error state.

**Remove from band:**
12. Tap "Remove from band" (on a member where it's rendered, not the last admin) → confirm the confirmation `AlertDialog` appears with the exact copy ("Remove {name}?" / cannot-be-undone body / Cancel / Remove). Cancel → confirm no removal, dialog closes, drawer remains open. Confirm on a disposable test member → confirm success snackbar, drawer closes, member no longer appears in the list.

**Cancel / dismissal:**
13. Make an unsaved role change, then tap Cancel → confirm the drawer closes with **no** change persisted (reload the list/reopen the drawer to confirm the original role is intact).
14. Make an unsaved change, then dismiss via backdrop-tap instead of Cancel → confirm identical no-op behavior (no accidental save on dismiss).

### Test AM2-3: Edit Flow — Non-Admin Gating

1. As a non-admin (or contributor): open a member's detail drawer. Confirm **no "Edit" button appears** — only "Done".
2. Confirm the read-only content (role/instruments/contact info) still displays fully — gating applies only to Edit, not to viewing.

### Test AM2-4: Crown-Only Icon on Card List

1. In the Band Members list (not the drawer), confirm an admin/owner member's card shows a crown icon before their name.
2. Confirm a contributor's card shows **no icon** before their name — per Tony's confirmed "Crown only" decision, contributors do not get the eye icon (or any icon).
3. Confirm a plain "member"-role member's card shows no icon, matching today's un-iconed appearance.
4. Confirm card layout doesn't visually break (name truncation, alignment) with the icon present, matching `member_card.dart`'s existing spacing.

### Test AM2-5: Kebab Removal — No Dead Affordance

1. Confirm no kebab (⋮) icon appears anywhere on any `BandMemberCard`, for admin or non-admin viewers.
2. Confirm no dead tap zone or visual artifact remains where the kebab used to be.

---

## QA Regression Areas Addendum

### Primary (this amendment's changes)

1. Detail drawer opens on card tap, for all users (admin and non-admin), with correct read-only content (role label, instruments, phone/email tappable, address, birthday, all conditionally rendered).
2. Detail drawer mechanics match `ViewGigDrawer`'s established pattern (slide-up, rounded corners, drag handle, backdrop dismiss, safe-area-aware footer).
3. Edit button present only for admins; tapping it correctly closes the detail drawer and opens the new `BandMemberEditDrawer` as a second modal bottom sheet.
4. **`BandMemberEditDrawer`'s ported logic is a faithful, byte-for-byte-equivalent reimplementation of `RoleManagementSheet`'s behavior** — role selection (every transition), all six contributor sub-permission toggles (including correct pre-population from saved values), the last-admin self-guard's exact conditions and exact effects (disabled buttons, exact warning copy, hidden Remove-from-band), Save's dirty-detection gating, and error-message handling. This is **not** a reachability-path check — treat it as validating a new implementation of an existing feature, per Test AM2-2's expanded coverage.
5. Non-admins/contributors see no Edit button and cannot reach `BandMemberEditDrawer` via the card at all (matches today's kebab-gating precedent).
6. Crown-only rendering on `BandMemberCard`: admin/owner → crown, contributor → no icon, member → no icon. No eye icon anywhere.
7. No kebab remains anywhere on `BandMemberCard`.
8. `role_management_sheet.dart` is confirmed to have no live caller after this change (only the already-dead `members_tab_content.dart` still references it) — not a functional test, but worth a sanity `grep` re-check during QA if convenient.

### Regression (existing functionality touched by this amendment)

9. **This must be tested together with Amendment 1's still-pending items**, since both land in the same two files (`band_members_view.dart`, `band_member_card.dart`): Band Members list rendering (no search/sections, per Amendment 1), loading/error/zero-members states, pull-to-refresh, and the Contacts `company` field round-trip (Amendment 1, unaffected by this amendment but sharing the same QA pass).
10. Other `membersProvider` consumers (financials, events forms, home, profile) — unaffected in theory since `MemberVM`/`membersProvider`/`members_repository.dart` are untouched by this amendment; spot-check per prior regression areas.
11. Venues and Contacts segments — fully unaffected, zero files touched by this amendment.

---

## System Impact Map (Amendment 2 Delta)

| System | Impact |
|---|---|
| Gigs | unaffected — `ViewGigDrawer` is read/referenced as a pattern only, not modified |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | **affected** — `BandMemberCard`'s interactive surface changes (kebab removed, tap-to-view added); Role Management's implementation is ported into a new `BandMemberEditDrawer`, and `RoleManagementSheet` is no longer invoked from any live code path; `membersProvider`/`MembersState`/`MembersRepository`/`MemberVM` themselves untouched (same methods called, same parameters) |
| Auth / Session | unaffected |
| Routing | **affected in one respect** — `contacts_tab_content.dart`'s `Navigator.push(fadeSlideRoute(page: RoleManagementSheet(...)))` call is **removed**, replaced by a second `showModalBottomSheet` call (not a named route). No new named routes are added anywhere. |
| Notifications | unaffected |
| Database | unaffected — no migration, no query change (see Database Impact) |
| Platform (iOS / Android / Web / macOS) | affected — UI-only, no platform-conditional code introduced |

---

## Out of Scope

1. **Deleting `role_management_sheet.dart`** — per the Investigation above, it becomes unreferenced by any live code path once this amendment lands, but it is left in place unmodified, matching this branch's established precedent for confirmed-dead files (`members_tab_content.dart`). Removal is a future, separate decision, not part of this amendment.
2. **A detail/edit drawer for Venues or Contacts** — not requested; `VenueDetailScreen` and `ContactFormScreen` already serve equivalent roles for those segments and are untouched.
3. **Editing any field from the detail drawer directly** (e.g. inline phone/email edit) — the detail drawer (`BandMemberDetailDrawer`) is explicitly read-only; all mutation continues to flow through the new `BandMemberEditDrawer` (role only) or the existing member invite/profile-edit flows (contact info), neither of which this amendment touches beyond the role-management port itself.
4. **A non-admin secondary view of Role Management** (e.g. read-only role display for non-admins beyond the drawer's own "Role" row) — the detail drawer's Role row already covers "what's my/their role" for non-admins; no separate mechanism is added.
5. **The crown-vs-crown+eye question** — resolved by Tony's explicit "Crown only" answer (revised Decision 3); no longer an open flag.
6. **Any change to `member_card.dart`, `members_tab_content.dart`, or the legacy (unrouted) member flows** — out of scope, confirmed dead code path per the base plan. This includes not touching `members_tab_content.dart`'s own, still-present call to `RoleManagementSheet` — it remains dead code exactly as before.
7. **RLS/policy audit or hardening of the `users` table select** — flagged as unverifiable-via-grep during planning (see Database Impact), but this amendment doesn't change the query or its exposure, so auditing it is a separate concern, not a blocker for this amendment.
8. **Extracting shared logic between `role_management_sheet.dart` and `band_member_edit_drawer.dart`** — the two files now contain duplicated role-management logic (one dead, one live). No shared helper is introduced to de-duplicate them, consistent with Guardrails §7 (no opportunistic refactors) and this amendment's own precedent (`_DetailRow` kept local, not extracted). If `role_management_sheet.dart` is deleted in a future amendment, this duplication resolves itself by removal, not by extraction.

---

## Amendment Summary

**This revision reverses both decisions the prior draft flagged as open, per Tony's direct answers.**

This amendment adds a two-drawer flow to Band Members: tapping a card opens a new, read-only `BandMemberDetailDrawer` (built by replicating `ViewGigDrawer`'s exact bottom-sheet mechanics — rounded top corners, drag handle, scrollable body of conditional detail rows, fixed Done/Edit footer) showing the member's permission role, musical roles, and contact info that the pre-simplification `MemberCard` used to render inline. Its "Edit" button — visible to admins only, gated by the same `membersState.isCurrentUserAdmin` boolean that gated the removed kebab — closes the detail drawer and opens a **new** `BandMemberEditDrawer` (Decision 1, reversed): a second bottom sheet, matching the same drawer chrome, that contains a full functional port of `RoleManagementSheet`'s role selection, contributor sub-permission toggles, last-admin self-guard (`_isSelfAndLastAdmin`/`_isLastAdmin`, ported condition-for-condition and effect-for-effect), and Save/error handling — not a link out to the existing full-screen page. A full-codebase search confirmed `RoleManagementSheet` has exactly one live caller (`contacts_tab_content.dart`) plus one caller inside the already-confirmed-dead, unrouted `members_tab_content.dart`; once `_openRoleManagement()` is repointed at the new drawer, `role_management_sheet.dart` becomes unreferenced by any live code path in the same sense `members_tab_content.dart` already is — it is left in place, unmodified, not deleted, matching this branch's established precedent for confirmed-dead files. `BandMemberCard` loses its kebab and gains a **crown-only** role-badge icon (Decision 3, reversed): admin/owner get a crown, contributors and plain members get no icon — the eye-icon/contributor case flagged in the prior draft is dropped entirely, not implemented. No database changes. **Regression risk is HIGH** (up from the prior draft's MEDIUM) — this is now a meaningfully larger change than a relocated entry point: it is a from-scratch reimplementation of a stateful, permission-sensitive UI (role transitions, six sub-permission toggles, a safety guard, destructive-action confirmation, four distinct error-message mappings) inside new chrome, stacked on top of Amendment 1's still-QA-pending changes to the same files. QA must verify the ported logic directly — every role-transition case and the last-admin guard specifically (Test AM2-2) — not merely confirm that tapping Edit still leads somewhere, and should treat Band Members as needing one combined pass across the base feature, Amendment 1, and this amendment together.

---

## Addendum — Detail Drawer Label/Layout Changes

**Addendum Date:** 2026-07-25
**Addendum Author:** Architect
**Trigger:** Product refinement from Tony, confirmed directly, on top of Amendment 2 as already implemented (`band_member_detail_drawer.dart` exists on disk with the `_DetailRow` list described in Amendment 2's Proposed Solution → Drawer 1). Four label/layout changes to the read-only detail rows — no data, state, or logic change.

### What's Changing and Why

Two of the six detail-row labels are being renamed for clarity, one row is moving position, and the label column is widening to fit the new longest label without wrapping:

1. **"Instruments" → "Role in band."** Same value (`member.musicalRoles.join(', ')`), same conditional (shown only when non-empty). Rename only.
2. **"Role" → "Access."** Same value (`_roleLabel(member)`), same unconditional (always shown). Rename only.
3. **"Access" (formerly "Role") moves to the bottom of the row list, after Birthday.** Every other row keeps its existing relative order and its existing conditional-render guard, unchanged.
4. **`_DetailRow`'s fixed label-column width widens** so "Role in band" — now the longest label — doesn't wrap to a second line.

**Why:** Product refinement from Tony — "Role in band" reads more clearly than "Instruments" for a field that shows musical roles/positions, "Access" is clearer than "Role" for the permission-level field once both role-shaped rows are on screen together, and putting the permission-level row last (after the personal/contact-info rows) reads better than leading with it. Confirmed directly, not inferred.

### Revised Proposed Solution — Drawer 1 (`BandMemberDetailDrawer`)

This supersedes only the **row list and column width** described in Amendment 2's "Proposed Solution → Drawer 1" section; everything else about the drawer (shell, drag handle, header block with the crown-only icon + name, footer, `_launchPhone`/`_launchEmail`/`_hasAddress`/`_formatAddress`/`_formatBirthday` logic) is unchanged.

**Revised row order and labels**, each still rendered via the existing local `_DetailRow` widget, each still only rendered when its underlying field is non-null/non-empty (except the last row, which is unconditional, same as today):

1. **Role in band** — shown only if `member.musicalRoles.isNotEmpty`. Value unchanged: `member.musicalRoles.join(', ')`. Not tappable. (Was labeled "Instruments"; was the second row, now the first.)
2. **Phone** — unchanged: shown only if `member.phone != null && member.phone!.isNotEmpty`. Value/tap behavior unchanged.
3. **Email** — unchanged: shown only if `member.email.isNotEmpty`. Value/tap behavior unchanged.
4. **Address** — unchanged: shown only if `_hasAddress(member)`. Value unchanged.
5. **Birthday** — unchanged: shown only if `member.birthday != null`. Value unchanged.
6. **Access** — always shown, unconditional. Value unchanged: `_roleLabel(member)`. Not tappable. (Was labeled "Role"; was the first row, now the last.)

Net effect: the row that was first (`Role`/`Access`) becomes last; every other row keeps its existing position relative to each other, just shifted up by one slot since the first row left. No row's conditional-render guard changes, no row's value/formatting logic changes, no row gains or loses tap behavior.

### Label-Column Width — Derivation

`_DetailRow`'s label `Text` uses `AppTextStyles.callout` (`design_tokens.dart:356-361`): `fontFamily: 'DM Sans'`, `fontSize: AppFontSizes.body` = **16px**, `fontWeight: FontWeight.w400`. The current fixed column is `SizedBox(width: 68)` (`band_member_detail_drawer.dart:307`).

This session has no runtime text-measurement tool available (Architect Hard Rules prohibit running `flutter analyze`/`flutter test`/any build command, and a bare `dart run` script cannot load/shape a custom font like DM Sans outside the Flutter engine), so the width below is derived from the style's actual font size using a standard proportional-sans average-advance-width approximation (~0.5em per character for mixed-case UI text), applied uniformly to all six labels rather than picked as an arbitrary round number:

At 16px, 0.5em ≈ **8px average advance width per character**. Applying that uniformly, by character count (letters + spaces):

| Label | Characters | Estimated width (8px × count) |
|---|---|---|
| Role in band | 12 | **96px** |
| Birthday | 8 | 64px |
| Address | 7 | 56px |
| Access | 6 | 48px |
| Phone | 5 | 40px |
| Email | 5 | 40px |

"Role in band" is the widest by a comfortable margin (32px more than the next-longest, "Birthday") — consistent with it being the longest label after this change, as expected. **Resolved column width: `SizedBox(width: 96)`**, replacing the current `width: 68`. This is the direct output of the calculation above (12 characters × 8px/char), not a rounded-up guess, and every other label has at least 32px of slack under it at this same per-character estimate — enough margin to absorb normal cross-platform font-rendering variance without any label wrapping. If real-device rendering shows `AppFontSizes.body`/DM Sans running slightly wider than this estimate in practice, the same 32px margin on "Birthday" (the next-longest label) is the number to watch; "Role in band" itself has no slack built in beyond the estimate, so a quick visual check on-device is still worthwhile (folded into the Engineer task below, not a separate verification pass).

### Engineer Task Breakdown

Continuing from Amendment 2's Task 24. This is the only task this addendum adds.

### Task 25: Rename, reorder, and widen `BandMemberDetailDrawer`'s detail rows

- Edit `lib/features/contacts/widgets/band_member_detail_drawer.dart`:
  - Change the `_DetailRow(label: 'Instruments', ...)` row's label to `'Role in band'`. No other change to that row (keep its `if (member.musicalRoles.isNotEmpty)` guard and `member.musicalRoles.join(', ')` value).
  - Change the `_DetailRow(label: 'Role', value: _roleLabel(member))` row's label to `'Access'`. No other change to that row's value or its (unconditional) render.
  - Reorder the six `_DetailRow` entries in `build()`'s scrollable body so `Access` (the renamed `Role` row) is moved from first to last, after `Birthday`. Resulting order: Role in band (if present) → Phone (if present) → Email (if present) → Address (if present) → Birthday (if present) → Access (always).
  - In the private `_DetailRow` widget, change `SizedBox(width: 68)` to `SizedBox(width: 96)`.
- No other file changes. This is presentational-only: `BandMemberEditDrawer`, `BandMemberCard`, `contacts_tab_content.dart`, `member_vm.dart`, and every other file touched or left off-limits by Amendment 2 remain exactly as Amendment 2 specified — nothing in this addendum requires touching any of them. Confirm via `git diff`/`git status` after implementation that `band_member_detail_drawer.dart` is the only file that changed.

### Files Created / Modified / Off-Limits

No new tables — this addendum modifies zero new files. `lib/features/contacts/widgets/band_member_detail_drawer.dart` already appears in Amendment 2's "Files to Create" table (it was created by Task 19) and is the sole file this addendum touches. Amendment 2's "Files Off-Limits" table remains in force unchanged; nothing in this addendum requires expanding it.

### Database Impact

Not applicable — no data, state, or logic change; purely label text, row order, and a fixed-width constant.

### Regression Risk

**Level:** LOW. Presentational-only change to a single, already-QA-pending file — label text, row order, and a layout constant, no conditional-render guard, value, formatter, or callback changes. Does not touch `BandMemberEditDrawer`'s ported role-management logic (still the highest-risk item in Amendment 2, unaffected here), does not touch `BandMemberCard`, and does not touch any Venues/Contacts file.

### QA Regression Areas Addendum

Folds into Amendment 2's Test AM2-1 (Detail Drawer — Read-Only Content), which QA has not yet run:
- Confirm the six rows render in the new order (Role in band → Phone → Email → Address → Birthday → Access), each still gated by its existing presence check, with "Access" always present regardless of the other five.
- Confirm the "Role in band" and "Access" labels render on a single line (no wrap) for the demo band's members, and that "Phone"/"Email"/"Address"/"Birthday" labels are unaffected by the wider column (still left-aligned, still followed by their values with the existing gap).
- Confirm values, tap-to-launch behavior (Phone/Email), and formatting (Address, Birthday) are otherwise identical to Amendment 2's pre-addendum behavior.
