# ARCHITECT PLAN — Contributor Read-Only Enforcement + Navigation Visibility Corrections

**Date:** 2026-03-02  
**Status:** Ready for Engineering  

---

## 1. Scope

Three changes to the BandRoadie Flutter client. **No backend changes.**

### Part 1 — Setlist Read-Only Enforcement for Contributors

A contributor with `can_view_setlists = true` can **view** setlists and songs but must not be able to **mutate** anything: no reorder, delete, duplicate, rename, add, or edit.

### Part 2 — Calendar Action Button Layout for Contributors

Contributors see customized action buttons: "Block Out" is always hidden, "Add Event" is full-width if they can create gigs, or hidden entirely if they cannot.

### Part 3 — Footer Navigation Tab Visibility

Tabs for restricted permissions are **hidden** (removed from the nav bar) instead of dimmed. Tab index mapping must remain stable despite variable item count.

---

## 2. Current State Analysis

### Part 1 — Setlist Permissions: Current Gaps

**`setlist_detail_screen.dart` and `setlists_tab_content.dart` have ZERO permission awareness.** Every mutation surface is fully exposed to all users who can view the tab.

| Mutation Surface | File | Entry Point |
|------------------|------|-------------|
| **Drag reorder songs** | `setlist_detail_screen.dart` | `SliverReorderableList.onReorder` → `_handleReorder` (line 1833) |
| **Drag reorder setlist cards** | `setlists_tab_content.dart` | `SliverReorderableList.onReorder` → `_handleReorder` (line 176) |
| **Swipe-to-delete song** (Dismissible) | `setlist_detail_screen.dart` | `Dismissible` wrapping every `ReorderableSongCard` with `direction: endToStart` (3 locations: lines ~1748, ~1910, ~1982) |
| **Swipe-to-delete setlist** (Dismissible) | `setlists_tab_content.dart` | `SwipeableSetlistCard.onDeleteConfirmed` (lines 475, 504) |
| **Swipe-to-duplicate setlist** | `setlists_tab_content.dart` | `SwipeableSetlistCard.onDuplicateConfirmed` (lines 476, 505) |
| **Swipe-to-duplicate Catalog** | `setlists_tab_content.dart` | `SwipeableSetlistCard` for catalog allows `startToEnd` swipe |
| **Delete setlist button** | `setlist_detail_screen.dart` | "Delete Setlist" `TextButton` at bottom of content (line 1495) |
| **Rename setlist** | `setlist_detail_screen.dart` | Edit (pencil) icon + `_showRenameDialog` (line 1547) |
| **Song tap → Edit drawer** | `setlist_detail_screen.dart` | `onTap: () => _handleSongTap(song)` on every `ReorderableSongCard` (lines ~1789, ~1950, ~2020) |
| **Song edit icon** | `reorderable_song_card.dart` | Edit `IconButton` in metrics row → `widget.onEdit` (line ~347) |
| **Song delete icon** | `setlist_detail_screen.dart` | `onDelete: () => _handleDelete(song.id, song.title)` callback on each card |
| **Tuning badge tap** | `reorderable_song_card.dart` | `GestureDetector.onTap: _selectTuning` (line ~407) |
| **"+ Add to Setlist" button** | `setlist_detail_screen.dart` | `_ActionButton` → `_handleOpenAddOverlay` (line 1329) |
| **"+ New" setlist button** | `setlists_tab_content.dart` | `TextButton.icon` → `_navigateToCreateSetlist` (line ~440) |
| **Select Mode** (Catalog) | `setlist_detail_screen.dart` | "Select" link → `_enterSelectMode` (line 1563) |
| **Sort button** (Catalog) | `setlist_detail_screen.dart` | `_ActionButton` → `_showSortOptions` (line 1320) |
| **Delete special items** (Dismissible) | `setlist_detail_screen.dart` | `Dismissible` wrapping `SpecialItemCard` (line 1849) |
| **Edit special items** | `setlist_detail_screen.dart` | `SpecialItemCard.onTap → _handleEditSpecialItem` |

### Part 2 — Calendar: Current State

The `calendar_tab_content.dart` renders a hardcoded `Row` with two `Expanded` `BrandActionButton`s:
- "Add Event" → `_handleAddEvent` (opens `AddEditEventBottomSheet`)
- "Block Out" → `_handleBlockOut` (opens `BlockOutDrawer`)

There is **no permission check** — both buttons are always visible to all users.

### Part 3 — Footer Nav: Current State

The `AnimatedBottomNavBar` always renders all 4 tabs (`kDefaultNavItems`). Restricted tabs are shown **dimmed** via `restrictedIndices`. Tapping a restricted tab shows a snackbar.

`AppShell` uses a hardcoded `IndexedStack` with positional indices 0–3. The `NavTabIndex` constants map 1:1 to these positions.

---

## 3. Files to Modify

### Part 1 — Setlist Read-Only Enforcement

| File | What to Change |
|------|---------------|
| **`lib/features/setlists/setlist_detail_screen.dart`** | Accept and consume `BandPermissions`. Gate ALL mutation entry points. See §4.1 for complete list. |
| **`lib/features/setlists/setlists_tab_content.dart`** | Watch `currentUserPermissionsProvider`. Pass `isReadOnly` flag to `SwipeableSetlistCard`. Gate: swipe-to-delete, swipe-to-duplicate, drag reorder of setlist cards, "+ New" button. |
| **`lib/features/setlists/widgets/swipeable_setlist_card.dart`** | Add `isReadOnly` flag. When true, set `direction: DismissDirection.none` to disable all swipe gestures. |
| **`lib/features/setlists/widgets/reorderable_song_card.dart`** | Add `isReadOnly` flag. When true: hide edit icon, disable tuning badge tap, suppress delete icon area. Keeps card tappable for lyrics view (read-only action). |
| **`lib/features/members/permissions/band_permissions.dart`** | Add convenience getter `bool get isSetlistReadOnly => isContributor;` — contributors can view but never mutate setlists. This consolidates the check to one place. |

### Part 2 — Calendar Action Button Layout

| File | What to Change |
|------|---------------|
| **`lib/features/calendar/calendar_tab_content.dart`** | Import and watch `currentUserPermissionsProvider`. Replace hardcoded `Row` of two buttons with conditional layout: contributor with gig perms → full-width "Add Event" only; contributor without gig perms → no buttons; admin/member → both buttons as-is. |

### Part 3 — Footer Navigation Visibility

| File | What to Change |
|------|---------------|
| **`lib/features/home/widgets/animated_bottom_nav_bar.dart`** | Replace `restrictedIndices: Set<int>` with `hiddenIndices: Set<int>`. Filter `kDefaultNavItems` to exclude hidden items. Build a mapping from filtered-item-index → original-tab-index so `onItemTapped` reports the correct semantic tab index. Adjust highlight animation to work with variable item count. |
| **`lib/features/shell/app_shell.dart`** | Compute `hiddenTabs` instead of `restrictedTabs`. Pass to `AnimatedBottomNavBar` as `hiddenIndices`. Keep the `IndexedStack` children at fixed positions 0–3 (unchanged). The `currentTab` provider still stores the **semantic** tab index (0–3), not the visual position. This decouples visual nav from content layout. |
| **`lib/features/shell/tab_provider.dart`** | No changes needed — it stores semantic index. |

---

## 4. Detailed Design

### 4.1 Setlist Read-Only: Gating Strategy

**Approach:** `SetlistDetailScreen` is a `ConsumerStatefulWidget`. It will watch `currentUserPermissionsProvider` and derive a local `bool isReadOnly` (true when `perms.isContributor`). This single boolean gates all mutation surfaces.

**New getter on `BandPermissions`:**

```dart
/// Contributors with can_view_setlists can view but never mutate.
/// Admin and Member can always mutate.
bool get canEditSetlists => isAdmin || isMember;
```

This getter already exists in `band_permissions.dart` (line ~108). It returns `true` for admin/member, `false` for contributor. We use this directly.

**Complete gating map for `setlist_detail_screen.dart`:**

| Surface | Gate Mechanism |
|---------|---------------|
| `SliverReorderableList.onReorder` | Pass `null` callback when `!canEditSetlists` — `SliverReorderableList` ignores null |
| `Dismissible` wrapping songs | Set `direction: DismissDirection.none` when `!canEditSetlists` |
| `Dismissible` wrapping special items | Same: `direction: DismissDirection.none` |
| `ReorderableSongCard.isDraggable` | Set `false` when `!canEditSetlists` (hides drag handle) |
| `ReorderableSongCard.onTap` | When `!canEditSetlists`: route to lyrics-only view if song has lyrics, else do nothing. Do NOT open `showSongDetailsBottomSheet`. |
| `ReorderableSongCard.onEdit` | Pass `null` when `!canEditSetlists` |
| `ReorderableSongCard.onDelete` | Pass `null` when `!canEditSetlists` |
| `ReorderableSongCard.onTuningChanged` | Pass `null` when `!canEditSetlists` |
| `_buildActionButtonsRow` — "+ Add to Setlist" | Hide entirely when `!canEditSetlists` |
| `_buildActionButtonsRow` — "Sort" (Catalog) | **Keep** — sorting is a view-layer action, not a mutation |
| `_buildActionButtonsRow` — Search/Filter | **Keep** — read-only action |
| "Select" link (Catalog) | Hide when `!canEditSetlists` (Select is for adding songs to another setlist) |
| "Delete Setlist" button | Hide when `!canEditSetlists` |
| Rename icon (pencil) | Hide when `!canEditSetlists` |
| Print icon | **Keep** — read-only action |
| Share icon | **Keep** — read-only action |

**Complete gating map for `setlists_tab_content.dart`:**

| Surface | Gate Mechanism |
|---------|---------------|
| `SwipeableSetlistCard.onDeleteConfirmed` | Pass `null` when `!canEditSetlists` |
| `SwipeableSetlistCard.onDuplicateConfirmed` | Pass `null` when `!canEditSetlists` |
| `SliverReorderableList` for setlist cards | Use `SliverList` instead when `!canEditSetlists` (removes reorder entirely) |
| "+ New" `TextButton.icon` | Hide when `!canEditSetlists` |
| `SetlistCard.onTap` | **Keep** — tapping to view the setlist detail is a read action |

**Changes to `SwipeableSetlistCard`:**

When both `onDeleteConfirmed` and `onDuplicateConfirmed` are `null`, set the `Dismissible.direction` to `DismissDirection.none`. This completely disables swipe gestures without changing the child widget.

**Changes to `ReorderableSongCard`:**

When `onEdit` is `null` → hide the edit `IconButton` from the metrics row.  
When `onTuningChanged` is `null` → the tuning badge renders as a non-interactive label (remove `GestureDetector`).  
When `onDelete` is `null` → no behavioral change needed (delete is handled by parent `Dismissible`, not the card itself).

The card's `onTap` callback still fires for lyrics viewing — the parent (`setlist_detail_screen`) decides what that tap does.

### 4.2 Calendar Action Button Layout

**Permissions to check:**
- `perms.canCreateGigs` — can the user create gigs (includes rehearsals/events)?
- `perms.isContributor` — is this a contributor? (Contributors never see Block Out)

**Layout matrix:**

| Role | canCreateGigs | Buttons |
|------|--------------|---------|
| Admin / Member | (always true) | `[Add Event] [Block Out]` — current layout, two `Expanded` in `Row` |
| Contributor | `true` | `[Add Event]` — single full-width button. Use `BrandActionButton(fullWidth: true)` |
| Contributor | `false` | No buttons. `SizedBox.shrink()` replaces the entire button row. |

**Implementation pattern:**

```dart
// Pseudocode for the button section
final perms = permissionsAsync.when(...);

Widget buttonSection;
if (!perms.isContributor) {
  // Admin/Member: both buttons
  buttonSection = Row(children: [Expanded(AddEvent), SizedBox(12), Expanded(BlockOut)]);
} else if (perms.canCreateGigs) {
  // Contributor with gig permission: full-width Add Event only
  buttonSection = BrandActionButton(label: 'Add Event', fullWidth: true, ...);
} else {
  // Contributor without gig permission: no buttons
  buttonSection = const SizedBox.shrink();
}
```

**Block Out restriction rationale:** Block outs are personal time-off markers. While contributors could theoretically set block outs, the specification explicitly requires hiding the Block Out button for contributors. This avoids confusion about scope (contributors have limited band-level authority).

**Day tap behavior for contributors:** When a contributor taps a day with no events and `canCreateGigs` is false, show a snackbar instead of opening the `AddEditEventBottomSheet`. When `canCreateGigs` is true, the `AddEditEventBottomSheet` opens normally.

### 4.3 Footer Navigation: Hidden Tabs

**Current approach (dimmed):**
- All 4 tabs always rendered
- Restricted tabs dimmed at 35% opacity
- Tap shows snackbar

**New approach (hidden):**
- Only permitted tabs rendered
- Tab count is variable (2–4 items)
- `selectedIndex` must map correctly between semantic index (0–3) and visual position

**Index mapping strategy:**

The `AnimatedBottomNavBar` receives:
1. `items: List<NavItem>` — the filtered list of visible nav items
2. `selectedIndex: int` — the **visual position** of the active tab within the filtered list
3. `onItemTapped: ValueChanged<int>` — reports the **semantic tab index** (not visual position)

`AppShell` computes the mapping:

```
visibleTabs = [
  (NavTabIndex.dashboard, NavItem(...)),  // Always
  if (canViewSetlists) (NavTabIndex.setlists, NavItem(...)),
  if (canViewCalendar) (NavTabIndex.calendar, NavItem(...)),
  if (canViewMembers) (NavTabIndex.members, NavItem(...)),
]
```

When the nav bar reports visual tap at position `i`, `AppShell` resolves it to `visibleTabs[i].semanticIndex` and calls `setTab(semanticIndex)`.

When converting `currentTab` (semantic) to visual position for the nav bar's `selectedIndex`, `AppShell` finds the visual position of the semantic index in the `visibleTabs` list.

**If the current tab becomes hidden** (permissions change), bounce-back logic already sends the user to Dashboard.

**IndexedStack stays at 4 children with fixed positions.** The `IndexedStack` child list does NOT change. Only the nav bar item list changes. This means:
- No index-out-of-range risk on the `IndexedStack`
- Tab content widgets maintain their state
- The `RestrictedTabContent` placeholders are still in the `IndexedStack` but unreachable via the nav bar

**Highlight animation:** The spring animation in `AnimatedBottomNavBar` animates `_currentPosition` from 0.0 to `items.length - 1`. With variable items, the animation range naturally adapts. The highlight width calculation (`1 / items.length`) also adapts. No special handling needed.

**Hot reload safety:** On hot reload, `currentUserPermissionsProvider` may re-initialize. During the loading gap, all tabs should be shown (admin fallback) to prevent jarring layout changes. Once permissions resolve, hidden tabs animate out. This matches the existing behavior where the loading fallback is `BandPermissions.admin`.

---

## 5. Files NOT to Modify

| File | Reason |
|------|--------|
| All `supabase/` files | No RPC or RLS changes |
| `setlist_repository.dart` | Data layer unchanged — RLS is the final authority |
| `setlist_detail_controller.dart` | Controller actions are only reachable through UI; gating happens at the UI layer. Controller methods remain callable for admin/member paths. |
| `setlists_screen.dart` (provider/notifier) | State management layer unchanged |
| `special_item_repository.dart` | No changes to special item data access |
| Auth / session files | Unrelated |
| `contributor_permissions.dart` | Model already complete |
| `band_permissions_provider.dart` | Provider already fetches permissions correctly |
| `song_details_bottom_sheet.dart` | The sheet itself is unchanged — it's simply never opened for contributors |
| `tuning_picker_bottom_sheet.dart` | Never opened for contributors |
| `add_to_setlist_overlay.dart` | Never opened for contributors |
| `new_setlist_screen.dart` | Never navigated to by contributors |
| `restricted_tab_content.dart` | Still used for IndexedStack fallback, but hidden tabs make it unreachable in normal flow |
| `tab_provider.dart` | Stores semantic index — unchanged |
| `add_edit_event_bottom_sheet.dart` | Unchanged — it's gated by the calendar's button visibility |
| `add_block_out_drawer.dart` | Unchanged — button is hidden |

---

## 6. State Management Implications

### 6.1 Provider Dependency Chain

```
activeBandIdProvider
    ↓ ref.watch
currentUserPermissionsProvider (FutureProvider<BandPermissions>)
    ↓ ref.watch
AppShell.build ──► AnimatedBottomNavBar (visible items, selectedIndex mapping)
                ├─► IndexedStack children (unchanged positions 0–3)
                ├─► SetlistsTabContent.build ──► SwipeableSetlistCard (swipe disabled)
                ├─► CalendarTabContent.build ──► Button row layout
                └─► SetlistDetailScreen.build ──► All mutation surfaces gated
```

No new providers introduced. No new state classes. The single existing `currentUserPermissionsProvider` feeds all three changes.

### 6.2 SetlistDetailScreen Permission Access

`SetlistDetailScreen` is a `ConsumerStatefulWidget`. It should `ref.watch(currentUserPermissionsProvider)` inside its `build()` method and derive:

```dart
final permsAsync = ref.watch(currentUserPermissionsProvider);
final canEdit = permsAsync.when(
  data: (p) => p.canEditSetlists,
  loading: () => false,  // Fail closed while loading (no mutation flicker)
  error: (_, __) => true, // Admin fallback on error
);
```

**Loading default = `false`:** A contributor must never briefly see edit controls. Defaulting to `false` during loading means edit controls are hidden until permissions confirm admin/member status. Admins see a brief moment without edit controls (~100ms) — acceptable.

### 6.3 No Rebuild Loops

Each change adds a single `ref.watch(currentUserPermissionsProvider)` to widgets that already rebuild on band changes. The permission provider caches results and only re-fetches when `activeBandIdProvider` changes. No circular dependencies.

---

## 7. Lifecycle Considerations

### 7.1 SetlistDetailScreen

This screen is pushed onto the Navigator stack from `SetlistsTabContent`. It has its own lifecycle:
- **`initState`**: Sets up animations, loads data. No permission check needed here.
- **`build`**: Watches permissions and gates UI. Safe — `ref.watch` in `build` is standard Riverpod practice.
- **Async operations**: `_handleSongTap`, `_handleDelete`, etc. are gated at the UI level — the buttons/gestures that call them are hidden/disabled. Even if called via race condition, RLS blocks the write.
- **`mounted` checks**: All existing `mounted` checks remain sufficient. No new async paths introduced.

### 7.2 AnimatedBottomNavBar with Variable Items

The highlight animation uses `_currentPosition` (a double). When items are removed:
- `didUpdateWidget` detects `selectedIndex` change and animates to new position
- If the old `_currentPosition` exceeds the new item count, the spring animation naturally converges to the target position
- No clamp needed — the spring math handles overshoot gracefully

### 7.3 Hot Reload

On hot reload:
1. Permissions provider may re-initialize → loading state
2. Loading fallback = admin → all tabs visible, all edit controls hidden (loading defaults to `canEdit = false` for setlists, but all tabs visible)
3. Permissions resolve → UI settles to correct state
4. No flicker because the transient state is "more visible tabs, fewer edit controls" which is non-disruptive

---

## 8. Edge Cases

### 8.1 Contributor with `can_view_setlists = true`, All Others Off

- Sees Dashboard + Setlists tab in footer (2 tabs)
- Can open any setlist, view songs
- All edit controls hidden: no drag handles, no swipe, no Add/Edit/Delete buttons
- Tuning badges are non-interactive labels
- Print and Share remain accessible
- Sort (Catalog) remains accessible
- Search/Filter remains accessible

### 8.2 Contributor with Full Permissions

- Sees all 4 tabs
- Calendar shows full-width "Add Event" (no Block Out)
- Setlists are read-only (contributors NEVER get setlist-edit permissions regardless of sub-permissions — `canEditSetlists` is `isAdmin || isMember`)
- Dashboard shows "Create Gig" button (if `canCreateGigs`)

### 8.3 Contributor with No Permissions

- Sees Dashboard only (1 tab in footer)
- No Setlists, Calendar, or Members tabs
- Dashboard has no quick action buttons
- Still has hamburger menu, band switcher, profile

### 8.4 Admin Regression

- All 4 tabs visible, all edit controls present
- Swipe-to-delete, drag reorder, song edit drawer, etc. all work
- Calendar shows both "Add Event" and "Block Out"
- No behavioral change for admins

### 8.5 Member Regression

- Same as admin — `canEditSetlists` returns `true` for members
- All setlist mutation surfaces available
- Calendar shows both buttons

### 8.6 Band Switch Mid-Session

- User switches from Band A (admin) to Band B (contributor)
- `activeBandIdProvider` changes → `currentUserPermissionsProvider` re-fetches
- During loading: edit controls hidden (fail closed), all tabs visible (admin fallback)
- After resolution: correct contributor view renders
- If currently on Setlist Detail screen: edit controls disappear seamlessly (no pop/push needed)

### 8.7 Permission Change While on Setlist Detail

- Admin changes contributor's permissions via Role Management
- Contributor is on `SetlistDetailScreen` reading songs
- `currentUserPermissionsProvider` is invalidated → re-fetches
- UI rebuilds: edit controls remain hidden (contributor never has `canEditSetlists`)
- No crash, no race condition

### 8.8 Tab Index with Dynamic Items

| Scenario | Visible tabs | Dashboard visual index | Semantic mapping |
|----------|-------------|----------------------|------------------|
| All visible | Dashboard, Setlists, Calendar, Members | 0 | 0→0, 1→1, 2→2, 3→3 |
| No Calendar | Dashboard, Setlists, Members | 0 | 0→0, 1→1, 2→3 |
| No Members | Dashboard, Setlists, Calendar | 0 | 0→0, 1→1, 2→2 |
| No Calendar, No Members | Dashboard, Setlists | 0 | 0→0, 1→1 |
| Only Dashboard | Dashboard | 0 | 0→0 |

The semantic index stored in `currentTabProvider` is always one of {0, 1, 2, 3}. The visual position is derived at render time.

### 8.9 Deep Link to Hidden Tab

If a deep link or programmatic navigation sets `currentTab` to a hidden tab index (e.g., Members when `can_view_members = false`), the existing bounce-back logic in `AppShell` redirects to Dashboard. The `IndexedStack` still has the `RestrictedTabContent` at that position, so there's no index error — it's just never visually selected.

### 8.10 Lyrics View Remains Accessible

`ReorderableSongCard.onTap` is repurposed for contributors: instead of opening the edit drawer (`showSongDetailsBottomSheet`), it opens the lyrics view (`showLyricsViewScreen`) if the song has lyrics, or does nothing if not. The `onLyricsView` callback remains unchanged.

**Decision:** In read-only mode, tapping a song card opens the lyrics view if available. If no lyrics, the tap is absorbed with no action. This gives contributors a useful read interaction without exposing edit surfaces.

---

## 9. Verification Checklist

### Part 1 — Setlist Read-Only

- [ ] **Contributor views setlist list:** Sees all setlists. No "+ New" button. No swipe-to-delete or swipe-to-duplicate gestures work. Setlist cards cannot be reordered.
- [ ] **Contributor opens setlist detail:** Sees songs with title, artist, BPM, duration, tuning. No drag handles. No "Add to Setlist" button. No "Delete Setlist" button. No rename icon.
- [ ] **Contributor taps song card:** Opens lyrics view if lyrics exist. No edit drawer opens. If no lyrics, tap is no-op.
- [ ] **Contributor cannot swipe songs:** `Dismissible` direction is `none`. No swipe gesture triggers.
- [ ] **Contributor sees tuning as label:** Tuning badge is non-interactive. No `TuningPickerBottomSheet` opens.
- [ ] **Contributor sees edit icon hidden:** The pencil/edit `IconButton` in the metrics row is not rendered.
- [ ] **Contributor in Catalog:** No "Select" link. No "Add to Setlist" button. Sort and Search/Filter remain available.
- [ ] **Contributor on special items:** Cannot swipe to delete set breaks/pauses. Cannot tap to edit.
- [ ] **Admin sees all edit controls:** Full regression — drag, swipe, edit, delete, add, rename all work.
- [ ] **Member sees all edit controls:** Same as admin.
- [ ] **No RPC calls from contributor:** Even if a mutation path were theoretically accessible, no network request for reorder/delete/edit fires for contributor.

### Part 2 — Calendar Layout

- [ ] **Admin/Member:** Both "Add Event" and "Block Out" buttons visible in `Row`, each `Expanded`.
- [ ] **Contributor with `canCreateGigs`:** Single "Add Event" button, full width. No "Block Out" button. No layout gap or overflow.
- [ ] **Contributor without `canCreateGigs`:** No buttons shown. No empty space where buttons were.
- [ ] **Contributor taps empty day with `canCreateGigs`:** `AddEditEventBottomSheet` opens.
- [ ] **Contributor taps empty day without `canCreateGigs`:** Snackbar appears, no drawer opens.
- [ ] **No permission flicker on load:** Buttons do not briefly flash before settling.

### Part 3 — Footer Navigation

- [ ] **Admin:** 4 tabs visible: Dashboard, Setlists, Calendar, Members.
- [ ] **Contributor all false:** 1 tab visible: Dashboard only. No layout break.
- [ ] **Contributor setlists-only:** 2 tabs: Dashboard, Setlists. Tab spacing is even.
- [ ] **Contributor setlists + calendar:** 3 tabs: Dashboard, Setlists, Calendar. No Members tab.
- [ ] **Tab tap reports correct semantic index:** Tapping the 2nd visible tab (when it's Calendar at semantic index 2) correctly navigates to the calendar content.
- [ ] **Highlight animation works with 2–4 tabs:** Spring-animated highlight moves correctly between variable number of items.
- [ ] **Tab bounce-back on permission change:** If permissions change and current tab becomes hidden, user is redirected to Dashboard.
- [ ] **Hot reload safe:** Footer does not flash or corrupt after hot reload.
- [ ] **IndexedStack stable:** Content at all 4 semantic positions remains intact regardless of footer tab count.

### General

- [ ] `flutter analyze` is clean (zero warnings, zero errors).
- [ ] No new dependencies added to `pubspec.yaml`.
- [ ] No Supabase RPC, RLS, or migration changes.
- [ ] No changes to setlist ordering atomic logic.
- [ ] No changes to auth / session initialization.

---

## 10. Implementation Order

1. **Add `ref.watch(currentUserPermissionsProvider)` to `setlists_tab_content.dart`.** Gate: "+ New" button, swipeable card callbacks, reorderable list → SliverList swap.
2. **Update `SwipeableSetlistCard`** to accept null callbacks and set `DismissDirection.none` accordingly.
3. **Add `ref.watch(currentUserPermissionsProvider)` to `setlist_detail_screen.dart`.** Gate all mutation surfaces per §4.1 table.
4. **Update `ReorderableSongCard`** to conditionally hide edit icon and disable tuning tap when callbacks are null.
5. **Update `calendar_tab_content.dart`** to watch permissions and conditionally render button row.
6. **Refactor `AnimatedBottomNavBar`** from `restrictedIndices` (dimmed) to `hiddenIndices` (removed). Implement index mapping.
7. **Update `AppShell`** to compute `hiddenTabs` set and pass filtered items + index mapping to nav bar.
8. **Run `flutter analyze`** — must be clean.
9. **Manual QA** per verification checklist.
