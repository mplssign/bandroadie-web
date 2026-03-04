# ARCHITECT PLAN — Contributor Permission Enforcement (Systemic)

**Date:** 2026-03-02
**Supersedes:** ARCHITECT_PLAN_v1.md
**Status:** Ready for Implementation
**Scope:** Eliminate all mutation leaks for permission-restricted contributors. Correct 3-dot member card behavior. Harden async permission resolution.

---

## 1. Problem Statement

Contributors with all permissions OFF can still:

- Create events (via DayDetailBottomSheet "Add Event" button, event card tap → edit mode)
- Block out dates (if any code path bypasses `_buildActionButtons`)
- Edit gigs and rehearsals (tap any event card → full EventEditorDrawer with zero permission checks)
- Edit setlists (song details bottom sheet has no read-only mode)
- Reorder songs, delete songs, edit song metadata (gated cosmetically at parent but no self-defense at sheet level)
- Duplicate setlists (gated cosmetically)
- Access `NewSetlistScreen` via any direct navigation

Additionally:

- The 3-dot menu on member cards opens a `PopupMenuButton` dropdown instead of directly invoking the Manage Role modal.
- The app shell defaults to `BandPermissions.admin` during loading — fail-open for tab visibility.
- Error branches in setlist screens default to `canEdit = true` — fail-open on error.
- `canEditGigs` and `canDeleteGigs` are defined in `BandPermissions` but never consumed anywhere in the UI.
- `EventPermissionHelper` is ownership-based (block outs) but has no role-based awareness.

---

## 2. Files to Modify

| File | Purpose of Change |
|------|-------------------|
| `lib/features/shell/app_shell.dart` | Fail-closed permission default during loading |
| `lib/features/setlists/setlist_detail_screen.dart` | Fix error branch to fail-closed; pass `canEdit` to SongDetailsBottomSheet |
| `lib/features/setlists/setlists_tab_content.dart` | Fix error branch to fail-closed |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add `isReadOnly` parameter; gate all editing fields |
| `lib/features/setlists/new_setlist_screen.dart` | Add self-contained permission guard (early pop with snackbar) |
| `lib/features/calendar/calendar_tab_content.dart` | Gate event card tap, gate DayDetailBottomSheet callbacks, gate `_handleAddEvent`/`_handleBlockOut` handlers |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` | Accept and respect `canAddEvent` / `canEditEvent` parameters |
| `lib/features/events/widgets/event_editor_drawer.dart` | Add permission-aware guard in `_handleSave`; add `isReadOnly` mode |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Pass permission context through to drawer |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Add self-defense permission check in `_handleSave` |
| `lib/features/members/widgets/member_card.dart` | Replace `PopupMenuButton` with direct `IconButton` → modal |
| `lib/features/members/members_tab_content.dart` | Wire new member card behavior |
| `lib/features/home/home_screen.dart` | Fix fail-open loading/error defaults |
| `lib/features/home/home_tab_content.dart` | Fix fail-open loading/error defaults |

## 3. Files NOT to Modify

| File | Reason |
|------|--------|
| `lib/features/members/permissions/band_permissions.dart` | Permission model is correct as-is |
| `lib/features/members/permissions/contributor_permissions.dart` | Schema is correct |
| `lib/features/members/permissions/band_permissions_provider.dart` | Provider logic is correct (internal admin fallback is acceptable since it catches its own errors) |
| `supabase/` (all files) | No RLS, RPC, or migration changes |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Already uses nullable callbacks correctly; parent is responsible |
| `lib/features/setlists/widgets/swipeable_setlist_card.dart` | Already uses nullable callbacks correctly; parent is responsible |
| `lib/features/setlists/widgets/add_to_setlist/` (all files) | Delegate-only overlays; parent gates access |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | Delegate-only; parent gates access |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` | Pure selection UI; returns value to caller |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` | Pure selection UI |
| `lib/features/members/widgets/role_management_sheet.dart` | Already admin-only via caller gating |
| `lib/shared/utils/event_permission_helper.dart` | Ownership-based logic is correct; role gating is a separate concern |
| `lib/features/auth/` (all files) | Auth/session bootstrap untouched |
| `lib/features/setlists/setlist_detail_controller.dart` | Ordering atomic logic untouched |

---

## 4. Explicit Mutation Surface Table

### 4.1 Setlist Domain

| # | Surface | File | Widget/Handler | Current Gating | Gap | Required Fix |
|---|---------|------|----------------|----------------|-----|-------------|
| S1 | Rename setlist | `setlist_detail_screen.dart` | `_showRenameDialog` via GestureDetector | `canEdit` hides icon | None (structurally removed) | No change |
| S2 | Delete song (swipe) | `setlist_detail_screen.dart` | `_confirmDeleteSong` via Dismissible | `canEdit` → `DismissDirection.none` | None | No change |
| S3 | Drag-reorder songs | `setlist_detail_screen.dart` | `_handleReorder` / `_handleItemReorder` via SliverReorderableList | `canEdit` switches to SliverList | None | No change |
| S4 | Add songs overlay | `setlist_detail_screen.dart` | `_handleOpenAddOverlay` | `canEdit` hides "Add" button | None (structurally removed) | No change |
| S5 | Delete special item | `setlist_detail_screen.dart` | `_handleDeleteSpecialItem` via Dismissible | `canEdit` → `DismissDirection.none` | None | No change |
| S6 | Edit special item | `setlist_detail_screen.dart` | `_handleEditSpecialItem` | `canEdit` null-gates `onTap` | None | No change |
| S7 | **Edit song details** | `setlist_detail_screen.dart` → `song_details_bottom_sheet.dart` | `_handleSongTap` → `showSongDetailsBottomSheet` | `canEdit` null-gates `onEdit`/`onTap` | **Sheet has no read-only mode; all fields always editable** | **Add `isReadOnly` param; caller passes `!canEdit`** |
| S8 | Delete setlist | `setlist_detail_screen.dart` | `_handleDeleteSetlist` | `canEdit` hides button | None | No change |
| S9 | Multi-select + add to another setlist | `setlist_detail_screen.dart` | `_handleAddToSetlist` | `canEdit` hides Select button | None | No change |
| S10 | New setlist (+) button | `setlists_tab_content.dart` | `_navigateToCreateSetlist` | `canEdit` hides button | None (button hidden) | No change |
| S11 | **NewSetlistScreen (destination)** | `new_setlist_screen.dart` | Entire screen | **None** | **No self-defense; reachable via deep link or direct push** | **Add permission guard on build** |
| S12 | Delete setlist (swipe) | `setlists_tab_content.dart` | `_confirmDelete` | `canEdit` null-gates callback | None | No change |
| S13 | Duplicate setlist (swipe) | `setlists_tab_content.dart` | `_confirmDuplicate` | `canEdit` null-gates callback | None | No change |
| S14 | Drag-reorder setlists | `setlists_tab_content.dart` | `_handleReorder` | `canEdit` switches to static SliverList | None | No change |
| S15 | Tuning change (badge tap) | `reorderable_song_card.dart` | `_selectTuning` → `showTuningPickerBottomSheet` | `onTuningChanged` nullable (null = non-interactive) | None (nullable callback) | No change |
| S16 | Edit song (pencil icon) | `reorderable_song_card.dart` | `widget.onEdit` | `onEdit` nullable (null = hidden) | None | No change |

### 4.2 Calendar Domain

| # | Surface | File | Widget/Handler | Current Gating | Gap | Required Fix |
|---|---------|------|----------------|----------------|-----|-------------|
| C1 | **Add Event button** | `calendar_tab_content.dart` | `_handleAddEvent` | Button hidden for restricted contributors | **Handler has no self-defense** | **Add early return with permission check inside `_handleAddEvent`** |
| C2 | **Block Out button** | `calendar_tab_content.dart` | `_handleBlockOut` | Button hidden for contributors | **Handler has no self-defense** | **Add early return with permission check inside `_handleBlockOut`** |
| C3 | Empty day tap → create event | `calendar_tab_content.dart` | `_handleDayTap` (empty day branch) | Contributor `!canCreateGigs` → snackbar | Properly gated | No change |
| C4 | **Day with events tap → DayDetailBottomSheet** | `calendar_tab_content.dart` | `_handleDayTap` (events exist branch) | **None** | **`onAddEvent` callback passed unconditionally** | **Null out `onAddEvent` when `!perms.canCreateGigs` or when contributor** |
| C5 | **Event card tap → edit event** | `calendar_tab_content.dart` | `_openEditEventSheet` | Block outs: ownership check. **Gigs/rehearsals: NO check** | **Any contributor can tap event card → full edit mode** | **Add `canEditGigs` check; open in viewOnly mode for restricted users** |
| C6 | **DayDetail "Add Event" button** | `day_detail_bottom_sheet.dart` | `onAddEvent` callback | Rendered when `onAddEvent != null` | **Caller doesn't null it out for restricted users** | **Fix at caller (C4)** |
| C7 | **DayDetail event card tap → edit** | `day_detail_bottom_sheet.dart` | `onEventTap` callback | **None** | **All events tappable regardless of permission** | **Caller wraps with permission-gated callback (C5)** |
| C8 | **Event editor save** | `event_editor_drawer.dart` | `_handleSave` | `_isSaving`, form validation | **Zero permission checks; directly writes to DB** | **Add permission guard at top of `_handleSave`** |
| C9 | **Event editor delete** | `event_editor_drawer.dart` | `_handleDelete` | `_isEditMode` gates button visibility | **Zero permission checks in handler** | **Add `canDeleteGigs` guard** |
| C10 | **Block out save** | `add_block_out_drawer.dart` | `_handleSave` | `_isReadOnly` mode (caller must set) | **`_handleSave` has no permission self-defense** | **Add permission guard** |
| C11 | Block out delete | `add_block_out_drawer.dart` | `_handleDelete` | `_isReadOnly`/`_isEditMode` + ownership | Already gated | No change |

### 4.3 Members Domain

| # | Surface | File | Widget/Handler | Current Gating | Gap | Required Fix |
|---|---------|------|----------------|----------------|-----|-------------|
| M1 | **3-dot menu → Manage Role** | `member_card.dart` | `PopupMenuButton` → `onManageRole` | `showRemoveOption` hides entire menu | **Uses dropdown intermediate; should directly open modal** | **Replace PopupMenuButton with IconButton → `onManageRole`** |
| M2 | **3-dot menu → Remove** | `member_card.dart` | `PopupMenuButton` → `_showRemoveConfirmation` | `showRemoveOption` hides entire menu | Same as M1 | **Merge into direct modal approach** |
| M3 | Remove member handler | `members_tab_content.dart` | `_removeMember` | `isCurrentUserAdmin` hides trigger | Handler has no self-defense | **Add inline admin check** |

### 4.4 Home / Dashboard Domain

| # | Surface | File | Widget/Handler | Current Gating | Gap | Required Fix |
|---|---------|------|----------------|----------------|-----|-------------|
| H1 | Create Gig quick action | `home_screen.dart` | `onCreateGig` | `canCreateGigs` null-gates callback | **Defaults to `true` on loading/error** | **Change to `false` on loading/error** |
| H2 | Create Setlist quick action | `home_screen.dart` | `onCreateSetlist` | `canCreateSetlists` null-gates callback | **Defaults to `true` on loading/error** | **Change to `false` on loading/error** |
| H3 | Create Gig quick action | `home_tab_content.dart` | `onCreateGig` | Same as H1 | **Same gap** | **Same fix** |
| H4 | Create Setlist quick action | `home_tab_content.dart` | `onCreateSetlist` | Same as H2 | **Same gap** | **Same fix** |

---

## 5. Permission Matrix

### 5.1 Source of Truth (`BandPermissions` getters)

| Permission Getter | Admin | Member | Contributor (all ON) | Contributor (all OFF) |
|-------------------|:-----:|:------:|:--------------------:|:--------------------:|
| `canEditBandSettings` | ✅ | ❌ | ❌ | ❌ |
| `canInviteMembers` | ✅ | ❌ | ❌ | ❌ |
| `canRemoveMembers` | ✅ | ❌ | ❌ | ❌ |
| `canChangeRoles` | ✅ | ❌ | ❌ | ❌ |
| `canDeleteBand` | ✅ | ❌ | ❌ | ❌ |
| `canCreateGigs` | ✅ | ✅ | ✅ (flag) | ❌ |
| `canCreatePotentialGigsOnly` | ❌ | ❌ | flag | flag |
| `canEditGigs` | ✅ | ✅ | ❌ | ❌ |
| `canDeleteGigs` | ✅ | ✅ | ❌ | ❌ |
| `canCreateSetlists` | ✅ | ✅ | ❌ | ❌ |
| `canEditSetlists` | ✅ | ✅ | ❌ | ❌ |
| `canViewSetlists` | ✅ | ✅ | flag | ❌ |
| `canViewCalendar` | ✅ | ✅ | flag | ❌ |
| `canViewMembers` | ✅ | ✅ | flag | ❌ |

### 5.2 Capability → Gate Mapping

Each mutation surface maps to exactly one permission getter:

| Capability | Gate | Controls |
|-----------|------|----------|
| Create/edit/delete setlists, songs, ordering | `canEditSetlists` | S1–S16 |
| Create events (gigs/rehearsals) | `canCreateGigs` | C1, C3, C4, C6 |
| Edit existing gigs/rehearsals | `canEditGigs` | C5, C7, C8 |
| Delete existing gigs/rehearsals | `canDeleteGigs` | C9 |
| Create block outs | `!isContributor` (admin/member only) | C2, C10 |
| Edit/delete block outs | Ownership via `EventPermissionHelper` | C11 (already working) |
| Manage roles | `canChangeRoles` (admin only) | M1, M2 |
| Remove members | `canRemoveMembers` (admin only) | M3 |
| Create setlist (destination screen) | `canCreateSetlists` | S11 |
| Dashboard quick actions | `canCreateGigs` / `canCreateSetlists` | H1–H4 |

---

## 6. Structural Gating Strategy

### 6.1 Principle: Defense in Depth

Every mutation must be gated at **two levels**:

1. **UI level** — Remove or disable the trigger widget (structurally, not cosmetically)
2. **Handler level** — Early return with no-op if permission check fails (self-defense)

This ensures that even if a widget is somehow rendered (hot reload, race condition, future refactor), the mutation handler rejects the operation.

### 6.2 Per-Surface Gating Specification

---

#### S7 — Song Details Bottom Sheet (`song_details_bottom_sheet.dart`)

**Current:** No `isReadOnly` parameter. All fields always editable.

**Required changes to `showSongDetailsBottomSheet()`:**
- Add `bool isReadOnly = false` named parameter.
- Forward to `_SongDetailsSheet` constructor.

**Required changes to `_SongDetailsSheet` (internal widget):**
- Accept `bool isReadOnly`.
- When `isReadOnly == true`:
  - **Title field:** Render as plain `Text` widget. Remove `GestureDetector` wrapping that starts editing.
  - **Artist field:** Same — plain `Text`, no tap-to-edit.
  - **BPM field:** Display formatted value only, no `TextField` or tap handler.
  - **Duration field:** Display formatted value only, no tap handler.
  - **Tuning badge:** Remove `GestureDetector`. Render as static `Container` with tuning label.
  - **Notes field:** Display as plain `Text`, not a `TextField`.
  - **YouTube links:** Display link list only. Hide the "Add YouTube Link" button and remove (X) delete icons.
  - **Lyrics section:** Display lyrics text (if present). Hide "Edit Lyrics" / "Add Lyrics" button.
  - **Save button:** Replace with `SizedBox.shrink()`.
  - **Cancel button:** Change label to "Close" or "Done".
- `_handleSave()`: Add early return at top: `if (widget.isReadOnly) return;`

**Required changes to caller (`setlist_detail_screen.dart`):**
- In `_handleSongTap()`, pass `isReadOnly: !canEdit` to `showSongDetailsBottomSheet()`.

---

#### S11 — New Setlist Screen (`new_setlist_screen.dart`)

**Current:** No permission guard. Any navigation to this screen allows setlist creation.

**Required changes:**
- In `build()`, watch `currentUserPermissionsProvider`.
- Derive: `final canCreate = permissionsAsync.when(data: (p) => p.canCreateSetlists, loading: () => false, error: (_, __) => false);`
- If `!canCreate`:
  - In a `addPostFrameCallback`, pop the screen.
  - Show snackbar: `"🎸 You don't have permission to create setlists."`
- Return an empty `Scaffold` body during the guard frame (prevents any UI flash).

---

#### C1 — Add Event Handler (`calendar_tab_content.dart`)

**Current:** `_handleAddEvent()` has no self-defense.

**Required change:**
- At the top of `_handleAddEvent()`:
  - Read `currentUserPermissionsProvider`.
  - Extract `perms` via `.valueOrNull`.
  - If `perms == null` (still loading), early return.
  - If `perms.isContributor && !perms.canCreateGigs`, show snackbar and early return.

---

#### C2 — Block Out Handler (`calendar_tab_content.dart`)

**Current:** `_handleBlockOut()` has no self-defense.

**Required change:**
- At the top of `_handleBlockOut()`:
  - Read `currentUserPermissionsProvider`.
  - If `perms?.isContributor == true`, show snackbar: `"🎸 Block outs are for admins and members."` and early return.

---

#### C4 — DayDetailBottomSheet `onAddEvent` (`calendar_tab_content.dart`)

**Current:** `onAddEvent` callback always passed in `_handleDayTap`.

**Required change:**
- In `_handleDayTap`, when opening `DayDetailBottomSheet`:
  - Read permissions.
  - Pass `onAddEvent: (perms != null && perms.canCreateGigs) ? _handleAddEvent : null`.
  - When `onAddEvent` is `null`, the bottom sheet already hides the "Add Event" button (existing `if (onAddEvent != null)` check).

---

#### C5 — Event Card Tap → Edit (`calendar_tab_content.dart`)

**Current:** `_openEditEventSheet` opens full edit mode for gigs/rehearsals with no role check.

**Required changes to `_openEditEventSheet`:**
- Read `currentUserPermissionsProvider`.
- For gigs and rehearsals (non-block-out events):
  - If `!perms.canEditGigs`:
    - Open `AddEditEventBottomSheet.show()` with a new `viewOnly: true` parameter.
    - Contributor can still **view** event details but cannot save changes.
  - If `perms.canEditGigs`:
    - Open normally (current behavior).
- Block out logic is unchanged (already has ownership-based gating).

---

#### C7 — DayDetail Event Card Tap (`calendar_tab_content.dart` → `day_detail_bottom_sheet.dart`)

**Current:** `onEventTap` fires unconditionally.

**Required change:**
- No change needed in `day_detail_bottom_sheet.dart` itself.
- The fix is at the caller: `_openEditEventSheet` (C5 above) now has permission checks.
- The `onEventTap` callback passed from `_handleDayTap` already routes through `_openEditEventSheet`.

---

#### C8 — Event Editor Save (`event_editor_drawer.dart`)

**Current:** `_handleSave()` has zero permission checks. Directly writes to repository.

**Required changes to `EventEditorDrawer`:**

1. Add `bool viewOnly = false` constructor parameter.
2. When `viewOnly == true`:
   - Wrap form body in `AbsorbPointer(absorbing: true)` with `Opacity(opacity: 0.7)`.
   - Hide the primary "Save" / "Update" button.
   - Hide the "Delete" button.
   - Change "Cancel" button label to "Close".
   - All form fields become non-interactive.
3. In `_handleSave()`, add as first line:
   - Read `currentUserPermissionsProvider`.
   - In create mode: If `!perms.canCreateGigs`, early return with snackbar.
   - In edit mode: If `!perms.canEditGigs`, early return with snackbar.
4. In `_handleDelete()`, add:
   - If `!perms.canDeleteGigs`, early return with snackbar.

**Required changes to `AddEditEventBottomSheet.show()`:**
- Accept optional `bool viewOnly = false` parameter.
- Forward to `EventEditorDrawer`.

---

#### C9 — Event Editor Delete (`event_editor_drawer.dart`)

**Covered by C8 above.** Delete button is hidden when `viewOnly` and handler has self-defense via `canDeleteGigs`.

---

#### C10 — Block Out Save (`add_block_out_drawer.dart`)

**Current:** `_handleSave()` has no permission check.

**Required change:**
- At the top of `_handleSave()`:
  - Read `currentUserPermissionsProvider`.
  - If `perms?.isContributor == true`, show snackbar and early return.
  - This is self-defense; primary gate is caller-side (C2).

---

#### M1/M2 — Member Card 3-Dot Menu (`member_card.dart`)

**Current:** `PopupMenuButton` with two items ("Manage role", "Remove from band"). Tapping shows a dropdown menu, then user taps a menu item.

**Required changes to `member_card.dart`:**

1. **Remove** `_buildKebabMenu()` method entirely.
2. **Remove** `_showRemoveConfirmation()` method entirely.
3. **Add** new `_buildAdminButton()` method:
   - Returns `IconButton` with `Icons.more_vert` icon.
   - `onPressed: () => widget.onManageRole?.call()`.
   - Styled consistently: icon size 20, color `AppColors.textSecondary`.
4. **Rename** constructor parameter `showRemoveOption` → `showAdminActions`.
5. **Remove** constructor parameter `onRemove` (no longer needed — removal handled inside `RoleManagementSheet`).
6. **Update** rendering condition: `if (widget.showAdminActions) _buildAdminButton()`.

**Required changes to `members_tab_content.dart`:**

1. **Remove** `onRemove: () => _removeMember(member.memberId)` from `MemberCard`.
2. **Rename** `showRemoveOption:` → `showAdminActions:`.
3. **Keep** `onManageRole: () => _openRoleManagement(member)`.

**Verification:** Confirm `RoleManagementSheet` already contains "Remove from band" functionality. It does — the sheet has its own remove button and calls the members controller.

---

#### M3 — Remove Member Handler (`members_tab_content.dart`)

**Current:** `_removeMember` calls controller directly with no permission check.

**Required change:**
- At the top of `_removeMember`:
  - If `!membersState.isCurrentUserAdmin`, early return.

---

#### H1–H4 — Home Screen Quick Actions (`home_screen.dart`, `home_tab_content.dart`)

**Current:** `canCreateGig` and `canCreateSetlist` default to `true` on loading and error.

**Required change in both files:**
- `loading: () => false`
- `error: (_, __) => false`
- Buttons remain hidden until permissions resolve (~100ms).

---

## 7. Async Permission Resolution Strategy

### 7.1 Fail-Closed Default Principle

During loading, all mutation capabilities default to `false`. The user sees a minimal, read-only UI until permissions resolve.

### 7.2 Required Default Changes

| File | Branch | Current Default | Required Default |
|------|--------|----------------|-----------------|
| `app_shell.dart` | `loading:` | `BandPermissions.admin` | `BandPermissions.fromRole('member')` |
| `app_shell.dart` | `error:` | `BandPermissions.admin` | `BandPermissions.admin` (keep — dead code path) |
| `setlist_detail_screen.dart` | `loading:` | `false` | `false` (keep) |
| `setlist_detail_screen.dart` | `error:` | `true` | **`false`** |
| `setlists_tab_content.dart` | `loading:` | `false` | `false` (keep) |
| `setlists_tab_content.dart` | `error:` | `true` | **`false`** |
| `home_screen.dart` | `loading:` | `true` | **`false`** |
| `home_screen.dart` | `error:` | `true` | **`false`** |
| `home_tab_content.dart` | `loading:` | `true` | **`false`** |
| `home_tab_content.dart` | `error:` | `true` | **`false`** |
| `calendar_tab_content.dart` (build) | `loading:` | `null` (buttons hidden) | No change (already correct) |

### 7.3 App Shell Loading Default Rationale

Using `BandPermissions.fromRole('member')` as the loading default:

- **Shows all 4 tabs** — member can view everything. No layout shift when permissions resolve.
- **Blocks admin-only actions** — role management, band settings not exposed during loading.
- **Mutation blocked at tab level** — individual tab contents (`setlists_tab_content`, `calendar_tab_content`) have their own `loading: false` gates, so no mutation flicker occurs even though the shell defaults to member.
- **No new API needed** — `BandPermissions.fromRole('member')` already works.

### 7.4 Preventing Transient Admin UI Exposure

With the loading default changed from `admin` → `member`:
- Admin-specific chrome (role management, band settings) is hidden during loading.
- All tabs remain visible (correct for all non-restricted roles).
- Mutation UI hidden at the tab-content level.
- After ~100ms when permissions resolve, real permissions take effect with no jarring transition.

### 7.5 Avoiding Rebuild Storms

- Each screen watches `currentUserPermissionsProvider` independently.
- The provider is a `FutureProvider` → emits exactly once (`loading → data`) per band switch.
- `ref.watch` triggers exactly one rebuild when permissions resolve.
- No circular dependencies exist.
- `ref.invalidate(currentUserPermissionsProvider)` in `members_controller.dart` after role change triggers a single fresh fetch.

---

## 8. Navigation Stability Strategy

### 8.1 Current Architecture (Confirmed Correct)

Fixed-size `IndexedStack` with 4 children at semantic indices 0–3:

```
[DashboardTabContent, SetlistsTabContent, CalendarTabContent, MembersTabContent]
```

When a tab is restricted, its child is replaced with `RestrictedTabContent`. No index shifting.

### 8.2 Nav Bar Filtering

`visibleTabs` list of `(semanticIndex, NavItem)` tuples. Visual-to-semantic index mapping converts tap positions. Only permitted tabs appear in the nav bar.

**No changes needed.** Architecture is stable.

### 8.3 Bounce-Back Logic

When `currentTab` is not in `visibleTabs`, `addPostFrameCallback` resets to `NavTabIndex.dashboard`.

**Minor improvement:** Add guard `if (currentTab != NavTabIndex.dashboard)` before scheduling callback to prevent redundant resets.

### 8.4 Live Role Change Mid-Session

1. Admin changes a member's role via `RoleManagementSheet`.
2. `members_controller.dart` calls `ref.invalidate(currentUserPermissionsProvider)`.
3. All watchers rebuild.
4. Tabs update, mutation surfaces update, bounce-back fires if needed.

**No changes needed.** Works correctly.

### 8.5 Deep Link to Restricted Screen

- `NewSetlistScreen` self-defense guard (S11) fires.
- `addPostFrameCallback` pops screen, shows snackbar.
- User lands on previous screen.

### 8.6 Hot Reload Stability

- Hot reload re-runs `build()` but preserves state.
- Permission providers retain cached value.
- No flicker or reset.

---

## 9. 3-Dot Member Card Behavior — Detailed Spec

### 9.1 Current Behavior

```
MemberCard → PopupMenuButton (3-dot icon)
  ├── "Manage role" → widget.onManageRole?.call()
  └── "Remove from band" → _showRemoveConfirmation() → AlertDialog → widget.onRemove?.call()
```

Two-tap interaction: tap 3-dot → dropdown appears → tap menu item.

### 9.2 Required Behavior

```
MemberCard → IconButton (3-dot icon, admin-only)
  └── onPressed → widget.onManageRole?.call()
       └── RoleManagementSheet opens directly (contains "Remove from band" internally)
```

Single-tap interaction: tap 3-dot → `RoleManagementSheet` opens immediately.

### 9.3 Changes

**`member_card.dart`:**
1. Remove `_buildKebabMenu()` method.
2. Remove `_showRemoveConfirmation()` method.
3. Add `_buildAdminButton()` → `IconButton(icon: Icons.more_vert, onPressed: widget.onManageRole)`.
4. Rename parameter `showRemoveOption` → `showAdminActions`.
5. Remove `onRemove` callback parameter entirely.
6. Change render condition: `if (widget.showAdminActions) _buildAdminButton()`.

**`members_tab_content.dart`:**
1. Remove `onRemove:` from `MemberCard` instantiation.
2. Rename `showRemoveOption:` → `showAdminActions:`.

---

## 10. Lifecycle Considerations

### 10.1 Permission Provider Lifecycle

- `currentUserPermissionsProvider` is a `FutureProvider` — auto-disposed when no watchers exist.
- Re-fetches when `activeBandIdProvider` changes (band switch).
- Cached while watchers are active.

### 10.2 Band Switch

- `activeBandIdProvider` updates → permission provider re-fetches.
- Loading window: ~100ms with fail-closed defaults.
- All dependent UI rebuilds automatically.

### 10.3 Logout / Session Expiry

- `supabase.auth.currentUser` becomes null.
- Permission provider returns admin fallback (internal catch).
- Auth guard redirects to login before any mutation can occur.
- Acceptable: auth layer is primary gate for unauthenticated access.

### 10.4 No New Dependencies

- No new packages.
- No new files created (all changes are to existing files).
- No new providers introduced.
- No database/RPC/RLS changes.

---

## 11. Verification Checklist

### 11.1 Contributor (All Permissions OFF)

- [ ] Setlists tab: Not visible in nav bar
- [ ] Calendar tab: Not visible in nav bar
- [ ] Members tab: Not visible in nav bar
- [ ] Dashboard: "Create Gig" quick action hidden
- [ ] Dashboard: "Create Setlist" quick action hidden
- [ ] Direct navigation to `NewSetlistScreen`: Bounced back with snackbar
- [ ] Deep link to restricted tab: Bounced to Dashboard

### 11.2 Contributor (canViewSetlists ON, canViewCalendar ON, canCreateGigs OFF)

**Setlists tab (visible, read-only):**
- [ ] No "+ New" button
- [ ] No swipe-to-delete on setlists
- [ ] No swipe-to-duplicate on setlists
- [ ] No drag-reorder grip on setlists
- [ ] Song cards: Tap opens SongDetailsBottomSheet in **read-only mode**
- [ ] Song details: Title, artist, BPM, tuning, lyrics, YouTube all non-editable
- [ ] Song details: No Save button; only "Close" button
- [ ] No "Add to Setlist" button
- [ ] No rename icon on setlist header
- [ ] No delete button in setlist header
- [ ] Catalog: No "Select" mode
- [ ] Print and Share remain functional (read-only actions)

**Calendar tab (visible, restricted):**
- [ ] No "Add Event" button
- [ ] No "Block Out" button
- [ ] Tap empty day: Snackbar "no permission"
- [ ] Tap day with events: DayDetailBottomSheet opens
  - [ ] No "Add Event" button in sheet
  - [ ] Tap event card: Opens event viewer in **view-only mode**
- [ ] Tap event card in monthly list: Opens event viewer in **view-only mode**
- [ ] Event viewer: All fields disabled, no Save button, no Delete button
- [ ] Calendar subscription link: Still functional (read-only)

### 11.3 Contributor (canCreateGigs ON, canCreatePotentialGigsOnly ON)

- [ ] Calendar tab: "Add Event" button visible
- [ ] Tap "Add Event": Opens event editor in create mode
- [ ] Gig type: "Potential" toggle forced ON, switch disabled
- [ ] Save: Succeeds (creates potential gig)
- [ ] Edit existing gig: **View-only mode** (contributor cannot edit even self-created gigs — `canEditGigs` is admin/member only)
- [ ] Dashboard: "Create Gig" quick action visible

### 11.4 Admin Regression

- [ ] All 4 tabs visible
- [ ] All mutation surfaces functional (create, edit, delete, reorder, duplicate)
- [ ] 3-dot menu on member cards: **Single tap opens RoleManagementSheet directly**
- [ ] Role management: Can change roles, remove members
- [ ] Event editor: Full create/edit/delete access
- [ ] Song details: Full edit mode
- [ ] Setlist management: Full CRUD
- [ ] Block out: Create/edit/delete own block outs

### 11.5 Member Regression

- [ ] All 4 tabs visible
- [ ] All setlist mutation surfaces functional
- [ ] All calendar mutation surfaces functional (create, edit, delete events + block outs)
- [ ] Member card: **No 3-dot menu** (not admin)
- [ ] Cannot change roles or remove members

### 11.6 Live Role Change Mid-Session

- [ ] Admin changes contributor from "all OFF" to "canViewSetlists ON": Setlists tab appears immediately
- [ ] Admin changes member to contributor (all OFF): Restricted tabs disappear, bounce-back to Dashboard
- [ ] Admin changes contributor to admin: All tabs and mutations appear
- [ ] No flicker during transition
- [ ] Mutation surfaces update atomically (no transient edit-allowed state)

### 11.7 Edge Cases

- [ ] Deep link to setlist creation as contributor (all OFF): Bounced back with snackbar
- [ ] Hot reload while on restricted tab: Tab remains restricted, no crash
- [ ] Kill app and reopen as contributor: Permissions load fail-closed, then resolve correctly
- [ ] Band switch from admin-band to contributor-band: UI updates, restricted tabs hidden
- [ ] Network error during permission fetch: UI remains fail-closed (no mutation surfaces visible)
- [ ] `flutter analyze`: Zero warnings, zero errors
- [ ] No new linter violations introduced

---

## 12. Implementation Priority

### Phase 1 — Critical (mutation leaks)

| Priority | ID(s) | Description |
|----------|-------|-------------|
| P1 | C5, C8, C9 | Event card tap → unguarded edit mode. Add `canEditGigs`/`canDeleteGigs` checks in `_openEditEventSheet`, `viewOnly` mode in `EventEditorDrawer`, self-defense in `_handleSave`/`_handleDelete`. |
| P2 | S7 | Song details bottom sheet always editable. Add `isReadOnly` parameter, gate all fields. |
| P3 | C4, C6 | DayDetailBottomSheet `onAddEvent` passed unconditionally. Null it out based on permissions. |
| P4 | C1, C2 | Handler self-defense in `_handleAddEvent` / `_handleBlockOut`. |
| P5 | C10 | Block out save self-defense in `add_block_out_drawer.dart`. |

### Phase 2 — Fail-closed defaults

| Priority | ID(s) | Description |
|----------|-------|-------------|
| P6 | — | `app_shell.dart`: Loading default from `admin` → `member`. |
| P7 | H1–H4 | `home_screen.dart` / `home_tab_content.dart`: Loading/error defaults to `false`. |
| P8 | — | `setlist_detail_screen.dart` / `setlists_tab_content.dart`: Error default from `true` → `false`. |

### Phase 3 — UX and defense-in-depth

| Priority | ID(s) | Description |
|----------|-------|-------------|
| P9 | S11 | `NewSetlistScreen` self-defense guard. |
| P10 | M1, M2 | Member card 3-dot menu → direct modal. Rename `showRemoveOption` → `showAdminActions`. Remove `onRemove`. |
| P11 | M3 | `_removeMember` self-defense. |

### Phase 4 — Verification

| Priority | Description |
|----------|-------------|
| P12 | Run full verification checklist (Section 11). |
| P13 | `flutter analyze` — must be clean. |
| P14 | Manual QA per role matrix. |

---

## 13. Summary

This plan eliminates **all identified mutation leaks** by enforcing permissions at two layers (UI removal + handler self-defense) across **14 files**. The most critical fix is gating event card tap → edit mode (`C5/C8/C9`), which currently allows any contributor to edit any gig or rehearsal with zero permission checks at any layer.

**Key architectural decisions:**
- Song details sheet gains an `isReadOnly` parameter (no read-only mode exists today).
- Event editor gains a `viewOnly` parameter (contributors see details but cannot mutate).
- All async permission defaults changed to fail-closed (loading → no mutation).
- Member card dropdown eliminated in favor of direct modal invocation.
- No new dependencies, files, or database changes.

**Total scope:** ~14 files modified, 0 files created, 0 dependencies added.
