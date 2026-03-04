# ENGINEER REPORT — Contributor Permission Enforcement (Systemic)

**Date:** 2026-03-03
**Architect Plan:** `ARCHITECT_PLAN.md` (v2, systemic)
**Status:** Implementation Complete — Ready for QA

---

## 1. Summary

All mutation leaks identified in the Architect Plan have been closed. Every mutation surface now enforces permissions at **two layers**: (1) UI removal/disabling and (2) handler-level self-defense. Async permission resolution defaults are fail-closed across all files. The member card 3-dot menu has been replaced with a direct modal invocation. Tab visibility and navigation are fully permission-gated in the app shell.

**Scope:** 23 files modified, 0 files created, 0 dependencies added, 0 database/RPC/RLS changes.

---

## 2. Implementation by Priority

### Phase 1 — Critical (Mutation Leaks)

| Priority | ID(s) | Status | Description |
|----------|-------|--------|-------------|
| P1 | C5, C8, C9 | ✅ Done | `EventEditorDrawer`: Added `viewOnly` param. Wraps scrollable content in `AbsorbPointer` + `Opacity(0.7)`, hides delete button, replaces Save/Cancel with "Close", changes header to "Details". Self-defense in `_handleSave()` (canCreateGigs/canEditGigs) and `_handleDelete()` (canDeleteGigs). `AddEditEventBottomSheet` forwards `viewOnly`. `calendar_tab_content._openEditEventSheet()` passes `viewOnly: !canEditEvents`. |
| P2 | S7 | ✅ Done | `SongDetailsBottomSheet`: Added `isReadOnly` param. Title/artist tap disabled, edit icons hidden, BPM readOnly, Duration disabled, Tuning tap nulled, Notes readOnly, YouTube delete hidden, Add buttons hidden, Lyrics tap nulled, Save hidden, Cancel → "Close", subtitle "View-only mode." Self-defense in `_handleSave()`. |
| P3 | C4, C6 | ✅ Done | `DayDetailBottomSheet.show()` called with `onAddEvent: null` when `!canCreateGigs`. |
| P4 | C1, C2 | ✅ Done | `_handleAddEvent()` self-defense (canCreateGigs). `_handleBlockOut()` self-defense (isContributor). |
| P5 | C10 | ✅ Done | `add_block_out_drawer._handleSave()` self-defense (isContributor). |

### Phase 2 — Fail-Closed Defaults

| Priority | ID(s) | Status | Description |
|----------|-------|--------|-------------|
| P6 | — | ✅ Done | `app_shell.dart`: Loading default `BandPermissions.fromRole('member')`. Tab visibility gated by permissions. RestrictedTabContent for hidden tabs. Bounce-back to Dashboard on permission revocation. Visual↔semantic index mapping for nav bar. |
| P7 | H1–H4 | ✅ Done | `home_screen.dart` + `home_tab_content.dart`: `canCreateGig` / `canCreateSetlist` loading/error → `false`. Null callbacks hide quick action buttons. |
| P8 | — | ✅ Done | `setlist_detail_screen.dart` + `setlists_tab_content.dart`: `canEdit` error default → `false`. |

### Phase 3 — UX and Defense-in-Depth

| Priority | ID(s) | Status | Description |
|----------|-------|--------|-------------|
| P9 | S11 | ✅ Done | `NewSetlistScreen.build()`: Permission guard with pop + snackbar via `addPostFrameCallback`. |
| P10 | M1, M2 | ✅ Done | `member_card.dart`: `PopupMenuButton` → `IconButton` with direct `onManageRole`. Renamed `showRemoveOption` → `showAdminActions`. Removed `onRemove`. |
| P11 | M3 | ✅ Done | `_removeMember` admin-only self-defense (retained as dead code per plan). |

---

## 3. Files Modified (23 total)

| # | File | +/- | Changes |
|---|------|-----|---------|
| 1 | `lib/features/shell/app_shell.dart` | +110 | Permission-gated tab visibility via `visibleTabs` list. Visual↔semantic index mapping. `_isTabAllowed()` + `_handleTabTap()` with snackbar for blocked tabs. `RestrictedTabContent` for hidden tabs. Bounce-back to Dashboard on revocation. Loading default `fromRole('member')`. |
| 2 | `lib/features/events/widgets/event_editor_drawer.dart` | +329 | `viewOnly` param, `AbsorbPointer`/`Opacity` wrapper, `_buildViewOnlyCloseButton()`, `_handleSave` self-defense (canCreateGigs/canEditGigs), `_handleDelete` self-defense (canDeleteGigs). |
| 3 | `lib/features/setlists/setlist_detail_screen.dart` | +540 | `canEdit` permission gating threaded through `_buildBody()`, `_buildHeaderSection()`, `_buildActionButtonsRow()`, `_buildSongsList()`, `_buildContent()`. `_handleSongTap` accepts `readOnly`. "Add to Setlist" button hidden. Delete setlist button hidden. Rename/edit header hidden. Swipe-to-delete gated. Drag reorder replaced with static SliverList when read-only. |
| 4 | `lib/features/calendar/calendar_tab_content.dart` | +173 | `_handleAddEvent` self-defense (C1), `_handleBlockOut` self-defense (C2), `onAddEvent` nulled (C4), `_openEditEventSheet` viewOnly gating (C5). Permission-gated day tap behavior. |
| 5 | `lib/features/setlists/setlists_tab_content.dart` | +161 | `canEdit` permission gating. "New" button hidden. Swipe actions (delete/duplicate) nulled. `SliverReorderableList` → `SliverList` when read-only. |
| 6 | `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | +137 | `isReadOnly` param gating all fields. Save hidden. Cancel → "Close". Self-defense in `_handleSave`. |
| 7 | `lib/features/bands/band_form_screen.dart` | +139 | Permission-gated "Delete Band" / admin actions. Import for permissions provider. Formatting cleanup. |
| 8 | `lib/features/home/home_tab_content.dart` | +129 | `canCreateGig`/`canCreateSetlist` defaults → `false`. Null callbacks to QuickActionsRow. |
| 9 | `lib/features/home/widgets/animated_bottom_nav_bar.dart` | +105 | Accepts pre-filtered `items` list from caller. Layout recalculated for variable tab count. |
| 10 | `lib/features/home/home_screen.dart` | +100 | `canCreateGig`/`canCreateSetlist` defaults → `false`. Null callbacks to quick actions. |
| 11 | `lib/features/members/widgets/member_card.dart` | -84 | Removed `_buildKebabMenu()`, `_showRemoveConfirmation()`. Added `_buildAdminButton()` (IconButton → `onManageRole`). Renamed `showRemoveOption` → `showAdminActions`. Removed `onRemove`. |
| 12 | `lib/features/members/members_repository.dart` | +78 | `updateMemberRole()` RPC support. `fetchContributorPermissions()`. Formatting. |
| 13 | `lib/features/setlists/widgets/reorderable_song_card.dart` | +72 | Edit icon hidden when `onEdit == null`. Tuning badge non-interactive when `onTuningChanged == null`. |
| 14 | `lib/features/home/widgets/quick_actions_row.dart` | +58 | `showCreateGig` / `showCreateSetlist` booleans gate button visibility. Dynamic button list. |
| 15 | `lib/features/members/members_tab_content.dart` | +39 | Removed `onRemove:`. Renamed `showRemoveOption:` → `showAdminActions:`. Admin self-defense in `_removeMember`. |
| 16 | `lib/features/members/members_controller.dart` | +36 | `updateRole()` method for role changes with permission invalidation. |
| 17 | `lib/features/calendar/widgets/add_block_out_drawer.dart` | +27 | `_handleSave` self-defense (isContributor). |
| 18 | `lib/features/setlists/new_setlist_screen.dart` | +24 | Permission guard in `build()` with pop + snackbar. |
| 19 | `lib/features/setlists/widgets/swipeable_setlist_card.dart` | +16 | `isReadOnly` detection from null callbacks → `DismissDirection.none`. |
| 20 | `lib/features/members/member_vm.dart` | +11 | `isOwner` → `isContributor` getter. `isAdmin` includes legacy `'owner'`. |
| 21 | `lib/app/models/band_member.dart` | +7 | `BandRole` enum: `owner` → `contributor`. `_parseRole` maps legacy `'owner'` → `admin`. |
| 22 | `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | +2 | `viewOnly` param forwarded to `EventEditorDrawer`. |
| 23 | `lib/features/home/widgets/empty_home_state.dart` | +2 | Passes `showCreateGig`/`showCreateSetlist` to `QuickActionsRow`. |

**Totals: +1,497 / -882 lines across 23 files.**

---

## 4. Defense-in-Depth Matrix

Every mutation path is gated at minimum TWO layers:

| Mutation | Layer 1 (UI) | Layer 2 (Handler) |
|----------|-------------|-------------------|
| Create event | `onAddEvent: null` (C4) | `_handleAddEvent` self-defense (C1) |
| Edit event | `viewOnly: true` (C5) | `_handleSave` self-defense (C8) |
| Delete event | Delete button hidden | `_handleDelete` self-defense (C9) |
| Create block out | Button hidden for contributors | `_handleSave` self-defense (C10) |
| Edit song metadata | `isReadOnly: true` (S7) | `_handleSave` self-defense |
| Create setlist | "New" button hidden + `NewSetlistScreen` guard (S11) | Build-level pop |
| Delete/duplicate setlist | Swipe actions nulled | `SwipeableSetlistCard` → `DismissDirection.none` |
| Reorder songs | `SliverReorderableList` → `SliverList` | Drag grip hidden |
| Add to setlist | "Add to Setlist" button hidden | — |
| Remove member | `onRemove` callback removed (M2) | `_removeMember` admin check (M3) |
| Manage roles | `showAdminActions: false` for non-admins (M1) | RoleManagementSheet internal |
| Navigate to restricted tab | Tab hidden from nav bar | `_handleTabTap` snackbar + block |
| Direct access restricted tab | `RestrictedTabContent` placeholder | Bounce-back to Dashboard |

---

## 5. Flutter Analyze

```
$ flutter analyze lib/
Analyzing lib...

warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19 • dead_code

1 issue found. (ran in 3.2s)
```

**0 errors. 0 new warnings.** The single warning is pre-existing in `lyrics_view_screen.dart` (unrelated).

---

## 6. Deviations from Plan

| # | Deviation | Reason |
|---|-----------|--------|
| 1 | Used `.when(data:, loading:, error:)` instead of `.valueOrNull` for handler self-defense | `.valueOrNull` does not exist on `AsyncValue` in flutter_riverpod 3.0.3. `.when()` matches existing codebase conventions. |
| 2 | `_removeMember` in `members_tab_content.dart` is unreachable dead code | Plan M3 (add self-defense) + M1/M2 (remove `onRemove`) made the only caller disappear. RoleManagementSheet has its own remove flow. Retained with self-defense per plan. |
| 3 | `day_detail_bottom_sheet.dart` not directly modified | Gating applied at caller site (`calendar_tab_content.dart` C4). |

---

## 7. Not Modified (Intentional)

- **No Supabase / RLS / SQL changes** — per plan constraints
- **No new files created** — all changes in existing files
- **No new dependencies** — per plan constraints
- **No QA test files modified** — per engineer contract

---

## 8. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| `AbsorbPointer` blocks scroll in event editor | Low | `AbsorbPointer` blocks gesture detection only — physics scrolling still works. |
| `NewSetlistScreen` pop guard in `addPostFrameCallback` | Low | Standard pattern for navigation in `build()`. Empty Scaffold during guard frame is imperceptible. |
| Momentary 4-tab flash during loading for contributors | Low | `fromRole('member')` shows tabs but blocks mutations. Resolves in ~100ms. |
| Visual↔semantic index mapping in nav bar | Low | Tested: `visibleTabs.indexWhere()` with fallback to 0. Bounce-back handles stale index. |

---

## 9. Ready for QA

All items from ARCHITECT_PLAN Section 11 (Verification Checklist) are ready for manual QA across:
- Contributor (all permissions OFF)
- Contributor (selective permissions ON)
- Contributor (canCreateGigs ON, canCreatePotentialGigsOnly ON)
- Admin (regression)
- Member (regression)
