# ARCHITECT PLAN — Contributor Restrictions + Role Sheet UX Adjustment

**Date:** 2026-03-02  
**Status:** Ready for Engineering  

---

## 1. Scope

Two discrete changes to the BandRoadie Flutter client. **No backend changes.**

### Change 1 — Contributor with All Permissions Off

Enforce that a contributor with `can_create_gigs = false`, `can_create_potential_gigs_only = false`, `can_view_setlists = false`, `can_view_calendar = false`, `can_view_members = false` sees a fully locked-down experience:

- **Create Gig** button hidden on Dashboard
- Setlists, Calendar, Members tabs gated (already partially implemented)
- No UI flicker during permission loading

### Change 2 — Member Card 3-Dot Menu → Direct Role Sheet

Replace the `PopupMenuButton` dropdown on member cards with a direct tap that opens the `RoleManagementSheet` full-screen route. Only admins see the action. The "Remove from band" action moves into `RoleManagementSheet` (it is already there).

---

## 2. Current State Analysis

### What Already Works

| Aspect | Status | Location |
|--------|--------|----------|
| `BandPermissions` abstraction layer | ✅ Complete | `lib/features/members/permissions/band_permissions.dart` |
| `ContributorPermissions` model | ✅ Complete | `lib/features/members/permissions/contributor_permissions.dart` |
| `currentUserPermissionsProvider` (FutureProvider) | ✅ Complete | `lib/features/members/permissions/band_permissions_provider.dart` |
| Bottom nav tab gating (restricted tabs appear dimmed) | ✅ Complete | `lib/features/shell/app_shell.dart` lines 73–95 |
| `RestrictedTabContent` placeholder UI | ✅ Complete | `lib/shared/widgets/restricted_tab_content.dart` |
| Safety bounce-back to Dashboard when current tab becomes restricted | ✅ Complete | `app_shell.dart` lines 117–120 |
| QuickActionsRow hides Create Gig / Create Setlist based on bool flags | ✅ Complete | `lib/features/home/widgets/quick_actions_row.dart` |
| Dashboard reads `canCreateGigs` / `canCreateSetlists` from permissions provider | ✅ Complete | `lib/features/home/home_tab_content.dart` lines 318–330 |
| `RoleManagementSheet` full-screen route with contributor toggle UI | ✅ Complete | `lib/features/members/widgets/role_management_sheet.dart` |
| `RoleManagementSheet` already contains "Remove from band" button | ✅ Complete | `role_management_sheet.dart` lines 453–490 |
| `MembersController.updateRole()` invalidates `currentUserPermissionsProvider` after save | ✅ Complete | `lib/features/members/members_controller.dart` lines 165–195 |
| `showRemoveOption` gates kebab menu visibility (admin-only) | ✅ Complete | `member_card.dart` line 148 |

### What Needs Changing

| Gap | Description |
|-----|-------------|
| **PopupMenuButton still shown** | The kebab menu on `MemberCard` opens a 2-item dropdown (`Manage role` + `Remove from band`). It should directly open the `RoleManagementSheet` route instead. |
| **Kebab still labeled `showRemoveOption`** | The boolean that gates the kebab menu is named `showRemoveOption`, but it actually controls admin-only actions (manage role + remove). Name is misleading but does not require rename — just behavioral change. |
| **No permission flicker prevention during loading** | `currentUserPermissionsProvider` defaults to `BandPermissions.admin` while loading. This means restricted contributors briefly see full access while the async fetch completes. The default should be a **locked-down** state, not admin. |
| **"Create Gig" defaults to visible while loading** | `canCreateGig` in `home_tab_content.dart` defaults to `true` during loading (line 322). Should default to `false` to prevent flicker. |
| **"Create Setlist" defaults to visible while loading** | Same pattern at line 326. Should default to `false`. |

---

## 3. Files to Modify

### Change 1 — Contributor Restrictions (Flicker Prevention)

| File | What to Change |
|------|---------------|
| `lib/features/members/permissions/band_permissions_provider.dart` | Change the `loading:` and `error:` fallbacks. Instead of `BandPermissions.admin`, return a **locked-down default** (new static const on `BandPermissions`) OR keep admin default but add a loading sentinel. See §4.1 for recommended approach. |
| `lib/features/members/permissions/band_permissions.dart` | Add `static const BandPermissions loading` — a permission object with role `'_loading'` where all `canView*` and `canCreate*` getters return `false`. This is used ONLY during the async gap. |
| `lib/features/shell/app_shell.dart` | Change the `loading:` branch on line 108 from `BandPermissions.admin` to `BandPermissions.loading`. Change the `error:` branch similarly OR keep admin for error (see §6 edge cases). |
| `lib/features/home/home_tab_content.dart` | Change `loading: () => true` on lines 322 and 327 to `loading: () => false`. This hides Create Gig / Create Setlist until permissions resolve. |

### Change 2 — Member Card 3-Dot Menu → Direct Role Sheet

| File | What to Change |
|------|---------------|
| `lib/features/members/widgets/member_card.dart` | Replace `_buildKebabMenu()` (the `PopupMenuButton` widget) with a simple `IconButton` that calls `widget.onManageRole?.call()` directly. Remove the `_showRemoveConfirmation()` method — it is redundant because `RoleManagementSheet` already has a remove button with its own confirmation dialog. |
| `lib/features/members/widgets/member_card.dart` | Remove `onRemove` callback parameter from `MemberCard`. It is no longer needed since remove lives in the role sheet. This is a **breaking API change** to the widget — all callers must be updated. |
| `lib/features/members/members_tab_content.dart` | Remove `onRemove: () => _removeMember(member.memberId)` from the `MemberCard(...)` constructor call (line 293). Remove the `_removeMember` method (lines 120–132) since it is now dead code — `RoleManagementSheet` handles this independently. |

---

## 4. Detailed Design

### 4.1 Flicker Prevention Strategy

**Problem:** `currentUserPermissionsProvider` is a `FutureProvider`. On first load (and on band switch), there is an async gap where `AsyncValue.loading` is the state. During this gap, the UI defaults to `BandPermissions.admin`, giving a contributor momentary admin-level visibility.

**Recommended approach — Loading Sentinel:**

Add to `BandPermissions`:

```dart
/// Sentinel used during async loading. All permissions return false.
/// Prevents privilege flicker before real permissions resolve.
static const BandPermissions loading = BandPermissions._(role: '_loading');
```

All boolean getters already check `isAdmin || isMember` first, so a role of `'_loading'` will naturally return `false` for everything except the contributor sub-permission branches, which also return `false` because `subPermissions` is `null`.

Verify getter behavior for `_loading` role:
- `isAdmin` → `false` ✅
- `isMember` → `false` ✅  
- `isContributor` → `false` ✅
- `canCreateGigs` → falls through to `return false` ✅
- `canViewSetlists` → falls through to `return false` ✅
- `canViewCalendar` → falls through to `return false` ✅
- `canViewMembers` → falls through to `return false` ✅
- `canEditBandSettings` → `false` ✅
- `canChangeRoles` → `false` ✅

This is the correct locked-down state.

**In `app_shell.dart`:**

```dart
final perms = permissionsAsync.when(
  data: (p) => p,
  loading: () => BandPermissions.loading,  // ← locked while loading
  error: (_, __) => BandPermissions.admin,  // ← admin on error (safe fallback)
);
```

**Rationale for keeping `admin` on error:** If permissions fail to fetch, locking the user out of all tabs is worse UX than showing full access. The backend RLS remains authoritative. The error case is rare (network failure, Supabase outage) and transient.

**In `home_tab_content.dart`:**

```dart
final canCreateGig = permissionsAsync.when(
  data: (perms) => perms.canCreateGigs,
  loading: () => false,  // ← hidden while loading
  error: (_, __) => true,
);
```

Same pattern for `canCreateSetlist`.

### 4.2 Member Card Kebab → Direct Route

**Current flow:**  
Tap `⋮` → `PopupMenuButton` opens dropdown → user picks "Manage role" → `onManageRole` callback fires → `Navigator.push(RoleManagementSheet)`

**New flow:**  
Tap `⋮` → `onManageRole` callback fires immediately → `Navigator.push(RoleManagementSheet)`

The `RoleManagementSheet` already contains:
- Role selection (Admin / Member / Contributor)
- Contributor sub-permission toggles
- "Remove from band" button with confirmation dialog
- Save / Cancel buttons
- Last-admin safeguards

Therefore the `PopupMenuButton` dropdown is fully redundant. The `onRemove` callback on `MemberCard` is also redundant.

**The ⋮ icon remains** — it is visually familiar as an "actions" affordance and is only rendered when `showRemoveOption == true` (i.e., admin). Renaming `showRemoveOption` to `showAdminActions` would be ideal but is deferred to avoid scope creep. The name mismatch is non-functional.

### 4.3 Visibility vs. Disabling (UX Decision)

**Decision: HIDE, do not disable.**

Rationale:
1. Disabled buttons on a dark theme are visually ambiguous — dim text on dark backgrounds is hard to distinguish from enabled.
2. BandRoadie's existing pattern is **hide** (see `QuickActionsRow` which uses `if (showCreateGig)` to omit the button entirely).
3. Showing a disabled "Create Gig" button with no tooltip or explanation creates confusion. The restricted tab content screen (`RestrictedTabContent`) already handles the "you don't have access" messaging for gated tabs.
4. Contributors with all permissions off will see: Dashboard (data only, no action buttons) + dimmed nav tabs with snackbar on tap attempt.

**The bottom nav tabs remain visible but dimmed** (existing behavior via `restrictedIndices`). This is the correct pattern — hiding nav tabs would cause layout shift and confusion about where features went. The dimmed + snackbar pattern communicates restriction clearly.

---

## 5. What NOT to Modify

| Do NOT Touch | Reason |
|-------------|--------|
| Supabase RPC functions | No backend contract changes |
| RLS policies | Backend remains authoritative |
| `contributor_permissions` table schema | Already correct |
| `ContributorPermissions` model | Already correct |
| `BandPermissions` getters (except adding `loading` sentinel) | Logic is already correct |
| `RoleManagementSheet` | Already has all needed functionality |
| `MembersController.updateRole()` | Already invalidates permissions provider |
| `currentUserPermissionsProvider` fetch logic | Already fetches correctly |
| Setlist ordering logic | Completely unrelated |
| Auth / session initialization | Completely unrelated |
| `AnimatedBottomNavBar` | Already handles `restrictedIndices` correctly |
| `RestrictedTabContent` | Already correct |
| `event_permission_helper.dart` | Block out / event edit logic is orthogonal |
| `MembersRepository` | No data-layer changes needed |

---

## 6. Edge Cases

### 6.1 Contributor with ALL Permissions Off

- **Dashboard:** Shows gig/rehearsal data (read-only view from the band calendar). No quick action buttons visible. The user can still pull-to-refresh.
- **Bottom nav:** Setlists, Calendar, Members tabs are dimmed. Tapping shows snackbar: "🎸 You don't have access to this section — ask a band admin."
- **Deep links:** If a contributor with no permissions arrives via deep link to a setlist or calendar route, the tab gating in `AppShell` will bounce them to Dashboard. No route-level guards needed beyond what exists.

### 6.2 Contributor with Partial Permissions

- Example: `can_view_setlists = true`, all others `false`.
- Setlists tab is accessible. Calendar, Members tabs are dimmed.
- Create Gig button hidden on Dashboard. Create Setlist button visibility depends on `canCreateSetlists` (which is `false` for contributors — `BandPermissions.canCreateSetlists` returns `isAdmin || isMember`).
- This is correct: contributors can VIEW setlists but not CREATE them.

### 6.3 Permission Change While App is Open

- Admin changes a contributor's permissions via `RoleManagementSheet`.
- `MembersController.updateRole()` calls `ref.invalidate(currentUserPermissionsProvider)`.
- This triggers re-fetch. `AppShell` watches the provider — it rebuilds with new permissions.
- If the currently viewed tab becomes restricted, the bounce-back logic (`addPostFrameCallback`) redirects to Dashboard.
- **No flicker** because the provider transitions from `data(oldPerms)` → `loading` → `data(newPerms)`. During the `loading` phase, `BandPermissions.loading` locks down, then real permissions restore. This is a brief flicker (sub-200ms) but always toward "less access temporarily," which is the safe direction.

### 6.4 Hot Reload Permission Flicker

- On hot reload, Riverpod providers may re-initialize.
- `currentUserPermissionsProvider` will briefly be in `loading` state.
- With the `BandPermissions.loading` sentinel, the UI will briefly show locked-down state before permissions resolve.
- This is acceptable — preferable to the current behavior of briefly showing admin access.
- Duration: typically < 100ms on macOS, imperceptible.

### 6.5 Band Switch

- `activeBandProvider` change causes `currentUserPermissionsProvider` to re-evaluate (it `ref.watch`es `activeBandIdProvider`).
- During the switch, `loading` sentinel locks UI down.
- `AppShell` bounce-back logic handles the case where the new band has different permissions.
- Band switcher already navigates to Dashboard tab on switch (line 316 of `app_shell.dart`), so restricted tabs won't be active.

### 6.6 Self-Viewing Admin on Member Card

- Admin sees the `⋮` icon on their own card.
- Tapping opens `RoleManagementSheet` for self.
- `RoleManagementSheet` already handles last-admin safeguard (`_isSelfAndLastAdmin`).
- With the new direct-open behavior, nothing changes here — the safeguard is in the sheet, not the menu.

### 6.7 Non-Admin Viewing Member Cards

- `showRemoveOption: membersState.isCurrentUserAdmin` is `false` for non-admins.
- The `if (widget.showRemoveOption) _buildKebabMenu()` condition prevents the icon from rendering.
- Non-admins (including contributors with `can_view_members = true`) see member cards without any action affordance.
- This is correct — only admins can manage roles.

### 6.8 `RoleManagementSheet` Navigator After Async

- `_saveRole()` and `_removeMember()` in `RoleManagementSheet` already check `if (mounted)` before calling `Navigator.of(context).pop()` and `showSuccessSnackBar()`.
- No changes needed. No new async paths introduced.

---

## 7. Lifecycle Considerations

### 7.1 Provider Rebuild Chain

```
activeBandIdProvider (changes)
    ↓ ref.watch
currentUserPermissionsProvider (re-fetches)
    ↓ ref.watch
AppShell.build (rebuilds IndexedStack + bottom nav)
    ↓ ref.watch
HomeTabContent.build (rebuilds quick actions)
```

This chain is already established. No new watchers are introduced. No rebuild loops possible because the chain is strictly one-directional (no provider writes back to `activeBandIdProvider`).

### 7.2 IndexedStack and Restricted Tabs

`AppShell` uses `IndexedStack` with conditional children:

```dart
if (perms.canViewSetlists)
  const SetlistsTabContent()
else
  const RestrictedTabContent(featureName: 'Setlists'),
```

When permissions change, the `IndexedStack` child at index 1 swaps between `SetlistsTabContent` and `RestrictedTabContent`. This destroys the old widget and its state. This is correct and desired — if a contributor loses setlist access, the tab should fully reset.

### 7.3 MemberCard Lifecycle

Replacing `PopupMenuButton` with `IconButton` simplifies the widget tree. No animation controllers to dispose. No overlay management to worry about. The `PopupMenuButton` currently manages its own overlay lifecycle — removing it eliminates a potential source of "setState called after dispose" if the card is removed while the popup is open.

---

## 8. State Considerations

### 8.1 No New State Introduced

Both changes are purely UI-layer adjustments. No new providers, no new state classes, no new controllers.

### 8.2 Existing State Dependencies (Unchanged)

| State | Used By | Impact |
|-------|---------|--------|
| `currentUserPermissionsProvider` | `AppShell`, `HomeTabContent` | Only the `loading` fallback value changes |
| `membersProvider.isCurrentUserAdmin` | `MembersTabContent` → `MemberCard.showRemoveOption` | Unchanged — still gates the ⋮ icon |
| `overlayStateProvider` | `AppShell` | Unchanged |
| `currentTabProvider` | `AppShell` | Unchanged |

---

## 9. Verification Checklist

### Change 1 — Contributor Restrictions

- [ ] **Contributor with ALL permissions off:** Dashboard shows no quick action buttons (Create Gig, Create Setlist hidden). Bottom nav Setlists/Calendar/Members tabs are dimmed. Tapping dimmed tab shows snackbar. Cannot navigate to restricted tabs.
- [ ] **Contributor with partial permissions:** Only permitted tabs are accessible. Create Gig hidden if `canCreateGigs` is false. Create Setlist hidden if `canCreateSetlists` is false (always false for contributors).
- [ ] **No permission flicker on initial load:** When a contributor logs in or switches to a band where they have restricted permissions, there is no brief flash of admin-level UI. Quick action buttons do not appear and then disappear.
- [ ] **No permission flicker on hot reload:** After hot reload, a restricted contributor does not briefly see full access.
- [ ] **Error fallback is admin:** If permissions fail to load (network error), user gets full access rather than being locked out. Backend RLS still enforces.
- [ ] **Band switch resets correctly:** Switching from a band where user is admin to a band where user is restricted contributor properly locks down UI.
- [ ] **Admin experience unchanged:** Admins see all tabs, all quick actions, all member card actions. No regression.
- [ ] **Band Member experience unchanged:** Band Members (non-admin, non-contributor) have full view access and gig/setlist creation. No regression.

### Change 2 — Member Card 3-Dot Menu

- [ ] **Admin taps ⋮ → goes directly to RoleManagementSheet:** No dropdown menu appears. The full-screen role management route opens immediately.
- [ ] **RoleManagementSheet retains all functionality:** Role selection, contributor toggles, remove button, save/cancel, last-admin safeguards all work.
- [ ] **Non-admin does not see ⋮:** Band Members and Contributors do not see the kebab icon on member cards. Verified by checking `showRemoveOption` (which is `isCurrentUserAdmin`).
- [ ] **No duplicate remove flows:** The old `_removeMember` method in `MembersTabContent` is removed. The old `_showRemoveConfirmation` method in `MemberCard` is removed. Remove only happens via `RoleManagementSheet`.
- [ ] **No Navigator / mounted issues:** `RoleManagementSheet` already handles `mounted` checks before `Navigator.pop()` and snackbar calls.
- [ ] **No rebuild loops:** Removing `PopupMenuButton` and replacing with `IconButton` does not introduce any new state watchers or provider dependencies.
- [ ] **`onRemove` parameter removed from MemberCard:** All callers updated. No compile errors.

### General

- [ ] `flutter analyze` is clean (zero warnings, zero errors).
- [ ] No new dependencies added to `pubspec.yaml`.
- [ ] No Supabase RPC, RLS, or migration changes.
- [ ] No changes to setlist ordering logic.
- [ ] No changes to auth / session initialization.

---

## 10. Implementation Order

1. **Add `BandPermissions.loading` sentinel** to `band_permissions.dart`.
2. **Update `AppShell`** `loading:` fallback to use `BandPermissions.loading`.
3. **Update `HomeTabContent`** `loading:` fallback for `canCreateGig` and `canCreateSetlist` to `false`.
4. **Replace `PopupMenuButton` in `MemberCard`** with `IconButton` calling `onManageRole`.
5. **Remove `onRemove` parameter** from `MemberCard` and update `MembersTabContent`.
6. **Remove dead code** (`_showRemoveConfirmation` in `MemberCard`, `_removeMember` in `MembersTabContent`).
7. **Run `flutter analyze`** — must be clean.
8. **Manual QA** per verification checklist.
