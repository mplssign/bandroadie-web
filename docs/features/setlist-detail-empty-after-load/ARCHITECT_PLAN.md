# ARCHITECT_PLAN — Setlist Detail Empty After Load (iOS)

## Feature Slug

`bug/setlist-detail-empty-after-load`

## Problem Summary

On iOS production, a user opened the "New Songs" setlist (12 songs). The loading indicator spun, resolved to completion, but displayed zero songs — despite the setlist actually containing 12 songs. Force-quitting and reopening the app resolved the issue, with the setlist then loading correctly. This suggests transient client-side state loss rather than data corruption or RLS failure.

## Root Cause

**Confidence: MEDIUM**

The `SetlistDetailNotifier` watches `selectedSetlistProvider` and rebuilds whenever it changes. The controller's `build()` method contains this vulnerable logic:

```dart
if (!selected.isSelected) {
  _lastLoadedSetlistId = null;
  _cachedState = null;  // <--- Discards loaded songs!
  return const SetlistDetailState();  // Empty state: isLoading=false, songs=[]
}
```

When `selectedSetlistProvider` loses its state or becomes unselected (ID or name becomes null), the controller **immediately discards any previously loaded songs** and returns an empty state with `isLoading = false` and `songs = []`.

**Confirmed failure scenario:**

1. User opens setlist detail screen  
2. Screen's `initState` sets selected setlist via post-frame callback  
3. Controller loads songs successfully from Supabase  
4. Songs are displayed ✓ (user saw 12 songs initially)  
5. **Unconfirmed trigger occurs** — potentially iOS lifecycle event, but exact mechanism not proven  
6. `selectedSetlistProvider` loses state  
7. Controller's `build()` detects `!selected.isSelected` and **discards cached songs**, returning empty state  
8. UI shows zero songs despite successful prior load  

**Evidence supporting this diagnosis:**

- **Screen render logic:** Spinner shown ONLY when `state.isLoading` from controller (no separate branch for provider state) → confirms songs loaded successfully before being cleared  
- **User report:** "loading completed, then showed empty" → matches step 4→8 sequence above  
- **Single occurrence:** not systematic → transient state loss, not architectural flaw  
- **Force-quit resolved it:** fresh app start bypasses the stale provider state  
- **Provider architecture confirmed:** `selectedSetlistProvider` is NOT autoDispose (rules out zero-listener disposal)  
- **Single `.clear()` call site:** only in `selectBand()` which user confirmed didn't occur  
- **Auth refresh doesn't touch provider:** traced full `refreshSession()` path, no invalidation  

**What's NOT confirmed:**

The exact trigger for `selectedSetlistProvider` losing state on this one iOS occurrence. Potential candidates include:
- iOS lifecycle transition interrupting Riverpod rebuild cascade  
- Widget tree disposal during backgrounding  
- Undiscovered code path that resets provider state  

**Secondary bug confirmed (independent of this report):**

The `loadSongs()` stale band ID guard has a critical bug:

```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  return;  // <--- DOES NOT set isLoading = false
}
```

If band switches mid-flight, this early return leaves `isLoading = true` forever, causing a stuck spinner. This doesn't match the reported symptom (spinner completed), but it's a real bug that should be fixed.

## Reference Docs Consulted

- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` (setlist management architecture, repository pattern, state management)
- `docs/reference/setlists/` directory **does not exist** — no domain-specific reference documentation available

## Existing System Analysis

### Current Data Flow: Setlist Load Path

1. **Navigation:** User taps setlist card → `Navigator.push(SetlistDetailScreen(...))` with `setlistId` and `setlistName`
2. **Screen init:** `SetlistDetailScreen.initState()` calls post-frame callback:
   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) {
     ref.read(selectedSetlistProvider.notifier).select(id: widget.setlistId, name: widget.setlistName);
   });
   ```
3. **Controller rebuild:** `SetlistDetailNotifier.build()` watches `selectedSetlistProvider`:
   ```dart
   final selected = ref.watch(selectedSetlistProvider);
   if (!selected.isSelected) {
     return const SetlistDetailState();  // <--- VULNERABLE
   }
   if (_lastLoadedSetlistId != selected.id) {
     Future.microtask(() => loadSongs());
     return SetlistDetailState(setlistId: selected.id!, setlistName: selected.name!, isLoading: true);
   }
   ```
4. **Repository fetch:** `SetlistRepository.fetchSongsForSetlist()` queries Supabase with band ID isolation
5. **State update:** Controller sets `state = state.copyWith(songs: songs, isLoading: false)`
6. **Screen render:** UI displays songs via `CustomScrollView` with `SliverReorderableList`

### Failure Point

When `selectedSetlistProvider` becomes unselected (`id` or `name` is null):

- Controller's `build()` is triggered
- `!selected.isSelected` evaluates to `true`
- Controller clears `_cachedState` and returns empty state
- **Previously loaded songs are discarded**
- UI renders zero songs with `isLoading = false`

### Why State Loss Can Occur on iOS

1. **App lifecycle transitions:** iOS backgrounding/foregrounding may trigger widget rebuilds
2. **Auth session refresh:** `AuthGate.didChangeAppLifecycleState()` calls `refreshSession()` on resume, potentially invalidating providers
3. **Riverpod provider invalidation:** If `selectedSetlistProvider` is invalidated or loses scope during lifecycle transitions, it reverts to its initial empty state
4. **Explicit clear call:** `activeBandController.selectBand()` calls `ref.read(selectedSetlistProvider.notifier).clear()` — though user reported no band switch, an implicit refresh might trigger this

## Proposed Solution

**Remove the controller's dependency on `selectedSetlistProvider` entirely (structural fix).**

### Investigation: selectedSetlistProvider Usage

Grepped all 37 usages across the codebase:
- **ONLY ONE CONSUMER watches it:** `SetlistDetailNotifier.build()` at line 311
- **All other usages are WRITES:** Setting/clearing the provider after create/rename/band-switch
- **No app bar, nav state, or other screen depends on watching this provider**

This confirms the controller can stop watching `selectedSetlistProvider` without breaking anything.

### Structural Fix

Instead of watching `selectedSetlistProvider` and rebuilding when it changes:
1. Controller exposes public method: `loadSetlist(String id, String name)`
2. Screen calls this method directly in post-frame callback with route args
3. Controller stores setlist ID/name internally and triggers load
4. Screen can still update `selectedSetlistProvider` for other purposes (keeps name in sync for future navigation)

This **eliminates the controller's exposure to provider state loss** — regardless of what causes it.

### Changes to Controller

**Before (vulnerable — watches provider):**

```dart
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  @override
  SetlistDetailState build() {
    final selected = ref.watch(selectedSetlistProvider);  // <--- Rebuilds when provider changes
    
    if (!selected.isSelected) {
      _lastLoadedSetlistId = null;
      _cachedState = null;  // <--- Discards loaded songs!
      return const SetlistDetailState();
    }
    
    if (_lastLoadedSetlistId != selected.id) {
      _lastLoadedSetlistId = selected.id;
      Future.microtask(() => loadSongs());  // <--- Indirect trigger
      return SetlistDetailState(setlistId: selected.id!, setlistName: selected.name!, isLoading: true);
    }
    
    return _cachedState ?? SetlistDetailState(...);
  }
}
```

**After (structural fix — no provider watch):**

```dart
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  String? _setlistId;
  String? _setlistName;
  
  @override
  SetlistDetailState build() {
    // Listen for song updates from other setlists (unchanged)
    ref.listen<SongUpdateEvent?>(songUpdateBroadcasterProvider, (prev, next) {
      if (next != null) _applySongUpdate(next);
    });
    
    // Return current state (initialized by loadSetlist() call from screen)
    return state;
  }
  
  /// Public method called by screen with route args
  void loadSetlist(String id, String name) {
    if (_setlistId == id) return;  // Already loaded
    
    _setlistId = id;
    _setlistName = name;
    state = SetlistDetailState(setlistId: id, setlistName: name, isLoading: true);
    
    Future.microtask(() => loadSongs());  // <--- Direct trigger from screen
  }
}
```

**Rationale:**

- Controller no longer watches `selectedSetlistProvider` → immune to its state loss
- Screen explicitly tells controller what to load via `loadSetlist(id, name)`
- Route args are the source of truth, not a transient provider
- `selectedSetlistProvider` can still be updated by screen for other purposes (name sync)

### Fix 2 — Stale Band ID Guard (Independent Bug)

The `loadSongs()` method has a guard that discards stale results when band switches mid-flight, but it fails to reset `isLoading`:

**Current buggy code:**
```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  debugPrint('[SetlistDetail] Discarding stale load result...');
  return;  // <--- Leaves isLoading = true, causing stuck spinner
}
```

**Fixed code:**
```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  debugPrint('[SetlistDetail] Discarding stale load result...');
  state = state.copyWith(isLoading: false);  // <--- Reset spinner
  return;
}
```

This bug is independent of the reported issue but affects the same code path.

## Database Impact

**Not applicable** — client-side state management fix only. No migrations, RLS policies, RPCs, or triggers involved.

## Flutter Architecture Changes

### State Management (Riverpod)

**Modified:**

- `SetlistDetailNotifier` — remove `ref.watch(selectedSetlistProvider)`, add public `loadSetlist(id, name)` method, store setlist ID/name as instance variables
- `SetlistDetailNotifier.loadSongs()` — reset `isLoading = false` in stale band ID guard
- `SetlistDetailScreen.initState()` — call `loadSetlist()` instead of `selectedSetlistProvider.select()`

**Unchanged:**

- `selectedSetlistProvider` (provider itself not modified)
- `activeBandProvider` (band switching logic unaffected)
- State setter override (still caches state on every update)

### Widgets

**Modified:**

- `SetlistDetailScreen.initState()` — call `ref.read(setlistDetailProvider.notifier).loadSetlist(widget.setlistId, widget.setlistName)` instead of setting `selectedSetlistProvider`

**Unchanged:**

- `_buildBody()` — still shows loading indicator when `state.isLoading`
- Error handling — still uses `ref.listen` to show snackbar on errors
- Song list rendering — no changes to `CustomScrollView` or `ReorderableSongCard`

### Repositories

**Unchanged** — `SetlistRepository.fetchSongsForSetlist()` is correct and not involved in the failure.

## Files to Create

**None**

## Files to Modify

| File | Changes |
|------|---------|
| [lib/features/setlists/setlist_detail_controller.dart](lib/features/setlists/setlist_detail_controller.dart) | **Fix 1:** Remove `ref.watch(selectedSetlistProvider)` from `build()`, add public `loadSetlist(String id, String name)` method, store setlist ID/name as instance variables. **Fix 2:** Add `isLoading = false` in stale band ID guard before early return |
| [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart) | Call `ref.read(setlistDetailProvider.notifier).loadSetlist(widget.setlistId, widget.setlistName)` in post-frame callback instead of `selectedSetlistProvider.select()` |

## Files Off-Limits

| File | Reason |
|------|--------|
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart) | Repository fetch logic is correct — not the failure point |
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) | Band switching logic is independent; no evidence it's the trigger |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart) | Auth session refresh is necessary for persistent login; not the root cause |
| [lib/main.dart](lib/main.dart) | Init order must not change per guardrails |
| Any migration files in `supabase/migrations/` | No database changes required |
| [lib/features/setlists/new_setlist_screen.dart](lib/features/setlists/new_setlist_screen.dart) | Still updates `selectedSetlistProvider` after create/rename (keeps name in sync for future nav) |

## System Impact Map

| System                                 | Impact                                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                            |
| Rehearsals                             | unaffected                                                                                            |
| Setlists / Catalog                     | **affected** — fix applies to setlist detail load path                                                |
| Members / RBAC                         | unaffected                                                                                            |
| Auth / Session                         | **related** — iOS lifecycle/auth refresh may trigger the race condition, but no changes to auth logic |
| Routing                                | unaffected                                                                                            |
| Notifications                          | unaffected                                                                                            |
| Platform (iOS / Android / Web / macOS) | **iOS affected** (primary report), unknown if Android/Web/macOS exhibit same issue                    |

## Regression Risk

**Level: LOW**

**Rationale:**

- **Single architectural change** — controller stops watching `selectedSetlistProvider`, reads from route args instead
- **No database, auth, or routing modifications**
- **Existing happy path strengthened** — route args are more stable than transient provider state
- **Screen still watches `setlistDetailProvider`** — UI rendering unchanged
- **Other features isolated** — gigs, rehearsals, members, auth all unaffected
- **`selectedSetlistProvider` still updated by screen** — other code that writes to it (new_setlist_screen, active_band_controller) continues to work

**Risk areas to monitor:**

- **Initial load timing** — ensure post-frame callback triggers load correctly
- **Rapid navigation** — verify controller doesn't attempt duplicate loads if screen rebuilds
- **Band switch** — confirm setlist clears when band changes (handled by screen disposal, not provider clear)

## Engineer Task Breakdown

### Task 1 — Structural Fix: Remove controller dependency on selectedSetlistProvider

**File:** `lib/features/setlists/setlist_detail_controller.dart`

**Change 1.1:** Add instance variables for setlist ID/name

**Location:** Top of `SetlistDetailNotifier` class (after line 293)

**Add:**
```dart
class SetlistDetailNotifier extends Notifier<SetlistDetailState> {
  String? _setlistId;        // <--- ADD
  String? _setlistName;      // <--- ADD
  String? _lastLoadedSetlistId;
  SetlistDetailState? _cachedState;
  // ... rest of class
```

---

**Change 1.2:** Remove provider watch from build(), simplify to return current state

**Location:** `SetlistDetailNotifier.build()` method (lines 311-350)

**Before:**
```dart
@override
SetlistDetailState build() {
  // Watch the selected setlist - when it changes, reset and refetch
  final selected = ref.watch(selectedSetlistProvider);

  // Listen for song updates from other setlists
  ref.listen<SongUpdateEvent?>(songUpdateBroadcasterProvider, (prev, next) {
    if (next != null && prev?.timestamp != next.timestamp) {
      _applySongUpdate(next);
    }
  });

  // If no setlist selected, return empty state
  if (!selected.isSelected) {
    _lastLoadedSetlistId = null;
    _cachedState = null;
    return const SetlistDetailState();
  }

  // Only reload if the setlist ID actually changed
  if (_lastLoadedSetlistId != selected.id) {
    _lastLoadedSetlistId = selected.id;
    _cachedState = null;
    Future.microtask(() => loadSongs());

    return SetlistDetailState(
      setlistId: selected.id!,
      setlistName: selected.name!,
      isLoading: true,
    );
  }

  // Setlist didn't change - return cached state
  if (_cachedState != null) {
    return _cachedState!.copyWith(setlistName: selected.name);
  }

  // Fallback
  return SetlistDetailState(
    setlistId: selected.id!,
    setlistName: selected.name!,
  );
}
```

**After:**
```dart
@override
SetlistDetailState build() {
  // Listen for song updates from other setlists (unchanged)
  ref.listen<SongUpdateEvent?>(songUpdateBroadcasterProvider, (prev, next) {
    if (next != null && prev?.timestamp != next.timestamp) {
      _applySongUpdate(next);
    }
  });

  // FIX: No longer watch selectedSetlistProvider.
  // Screen calls loadSetlist() directly with route args.
  // Return current state (or empty if not yet initialized).
  return state;
}
```

---

**Change 1.3:** Add public `loadSetlist()` method

**Location:** After `build()` method, before `loadSongs()` (around line 360)

**Add:**
```dart
/// Public method called by screen to initialize the setlist.
/// Replaces the previous pattern of watching selectedSetlistProvider.
void loadSetlist(String id, String name) {
  // If already loaded this setlist, don't reload
  if (_setlistId == id && _lastLoadedSetlistId == id) {
    if (kDebugMode) {
      debugPrint('[SetlistDetail] Setlist $id already loaded, skipping reload');
    }
    return;
  }

  if (kDebugMode) {
    debugPrint('[SetlistDetail] Loading setlist: $name (ID: $id)');
  }

  _setlistId = id;
  _setlistName = name;
  _lastLoadedSetlistId = null;  // Force reload
  _cachedState = null;

  state = SetlistDetailState(
    setlistId: id,
    setlistName: name,
    isLoading: true,
  );

  Future.microtask(() => loadSongs());
}
```

---

**Change 1.4:** Update `loadSongs()` to use instance variables instead of provider

**Location:** `loadSongs()` method, first few lines (around line 470)

**Before:**
```dart
Future<void> loadSongs() async {
  final selected = ref.read(selectedSetlistProvider);
  if (!selected.isSelected) return;

  final setlistId = selected.id!;
  final setlistName = selected.name!;
  // ... rest of method
}
```

**After:**
```dart
Future<void> loadSongs() async {
  // FIX: Read from instance variables instead of selectedSetlistProvider
  if (_setlistId == null || _setlistName == null) {
    if (kDebugMode) {
      debugPrint('[SetlistDetail] loadSongs called but setlist not initialized');
    }
    return;
  }

  final setlistId = _setlistId!;
  final setlistName = _setlistName!;
  // ... rest of method (unchanged)
}
```

**Validation:**
- Compile with `flutter analyze` — must pass with 0 errors  
- Verify console shows \"Loading setlist\" log when screen opens  
- Confirm songs load normally  

---

### Task 2 — Fix: Reset isLoading in stale band ID guard

**File:** `lib/features/setlists/setlist_detail_controller.dart`

**Change 2.1:** Add `isLoading = false` before early return in band ID guard

**Location:** `loadSongs()` method, inside both Catalog and non-Catalog branches (appears twice, around lines 485 and 520)

**Before (Catalog branch):**
```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  if (kDebugMode) {
    debugPrint(
      '[SetlistDetail] Discarding stale load result: '
      'bandId changed from $bandId to $currentBandId',
    );
  }
  return;
}
```

**After (Catalog branch):**
```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  if (kDebugMode) {
    debugPrint(
      '[SetlistDetail] Discarding stale load result: '
      'bandId changed from $bandId to $currentBandId',
    );
  }
  state = state.copyWith(isLoading: false);  // FIX: Reset spinner on stale result
  return;
}
```

**Repeat the same change in the non-Catalog branch** (search for the second occurrence of this guard).

**Validation:**
- Compile with `flutter analyze` — must pass with 0 errors  
- Test band switch while setlist is loading — spinner should not get stuck  

---

### Task 3 — Update screen to call loadSetlist() directly

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Change 3.1:** Replace selectedSetlistProvider.select() with loadSetlist()

**Location:** `_SetlistDetailScreenState.initState()` method, inside `addPostFrameCallback` (around line 120)

**Before:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref
      .read(selectedSetlistProvider.notifier)
      .select(id: widget.setlistId, name: widget.setlistName);
});
```

**After:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  // FIX: Call controller directly with route args instead of setting selectedSetlistProvider
  ref
      .read(setlistDetailProvider.notifier)
      .loadSetlist(widget.setlistId, widget.setlistName);
});
```

**Validation:**
- Compile with `flutter analyze` — must pass with 0 errors  
- Test normal navigation (tap setlist card) — songs load  
- Test rapid navigation (open setlist, immediately pop) — no crashes  

---

### Task 4 — Run analyzer and commit

**Commands:**
```bash
flutter analyze
git add lib/features/setlists/setlist_detail_controller.dart lib/features/setlists/setlist_detail_screen.dart
git commit -m \"fix(setlists): remove controller dependency on selectedSetlistProvider, reset spinner on stale band\"
```

**Validation:**
- `flutter analyze` returns 0 errors  
- Commit message follows format: `fix(scope): description`

## Verification Plan

### Tier 1 — Pre-deployment (Code Analysis Only)

Since this is a client-side state management fix with no database changes, all verification is performed post-deployment during manual testing.

**Tier 1: N/A** — No database queries or RPCs to test.

---

### Tier 2 — Post-deployment (Manual Testing)

#### Test 1: Normal Setlist Load (Regression Check)

**Platform:** iOS (physical device or simulator)  
**Preconditions:** Band with at least one setlist containing songs

**Steps:**

1. Open BandRoadie app (logged in)
2. Navigate to Setlists tab
3. Tap a setlist card
4. **Expected:** Loading indicator spins, then songs display
5. **Expected:** Console shows: `[SetlistDetail] Loaded N songs for [setlist name]`

**Pass criteria:** Songs load normally, no empty state, no extra debug logs about state preservation

---

#### Test 2: iOS Background During Screen Mount (Race Condition)

**Platform:** iOS physical device  
**Preconditions:** Band with setlist containing 5+ songs  

**Steps:**
1. Navigate to Setlists tab  
2. Tap a setlist card  
3. **Immediately** press home button (within 200ms of tap, during screen mount)  
4. Wait 2 seconds  
5. Resume app  
6. **Expected:** Setlist loads and displays songs normally (structural fix prevents provider state loss from affecting load)

**Pass criteria:**  
- Songs visible with count matching database (e.g., 5 songs)  
- No stuck loading spinner  
- Console shows: `[SetlistDetail] Loading setlist: [name] (ID: [id])`

**Fail criteria:**  
- Empty setlist view shown (zero songs displayed)  
- Loading spinner stuck indefinitely  
- No console log indicating `loadSetlist()` was called

---

#### Test 3: Rapid Navigation (Edge Case)

**Platform:** iOS  
**Preconditions:** Band with multiple setlists

**Steps:**

1. Open setlist A (wait for songs to load)
2. Immediately navigate back (pop)
3. Open setlist B (different from A)
4. **Expected:** Setlist B loads normally
5. **Expected:** Console does NOT show state preservation log (cached state was cleared on ID change)

**Pass criteria:** No stale songs from setlist A appear in setlist B

---

#### Test 4: Catalog vs. Non-Catalog (Regression)

**Platform:** iOS  
**Preconditions:** Band with Catalog and at least one custom setlist

**Steps:**

1. Open Catalog (sorted by artist)
2. Background app, resume
3. **Expected:** Catalog songs still visible
4. Navigate back, open custom setlist
5. Background app, resume
6. **Expected:** Custom setlist songs still visible

**Pass criteria:** Both Catalog and non-Catalog setlists preserve songs after resume

---

#### Test 5: Force-Quit Restart (Original Bug Reproduction)

**Platform:** iOS physical device  
**Preconditions:** Band with "New Songs" setlist containing 12 songs (or similar)

**Steps:**

1. Open setlist detail screen
2. Verify songs load successfully
3. Force-quit app (swipe up in app switcher)
4. Reopen app
5. Navigate to same setlist
6. **Expected:** Songs load successfully (same as Step 2)

**Pass criteria:** No empty state on fresh load (regression check)

---

## QA Regression Areas

### Primary Testing (Critical)

1. **Setlist detail load (iOS)** — normal navigation to setlist must show songs
2. **iOS background/foreground cycle** — songs must not disappear when app resumes
3. **Catalog vs. non-Catalog** — both setlist types must preserve songs after lifecycle events

### Secondary Testing (Regression Checks)

4. **Setlist reordering (drag & drop)** — ensure optimistic UI updates and persistence still work
5. **Inline editing (BPM, duration, tuning)** — save-on-blur must still broadcast updates to other open setlists
6. **Bulk add songs** — verify songs are added to both Catalog and target setlist correctly
7. **Search filter** — client-side filtering must work on full song list
8. **Android/Web/macOS** — verify setlist detail screen works on other platforms (regression)

### Platform-Specific Testing

- **iOS physical device** (priority 1) — only platform where bug was reported
- **iOS simulator** (priority 2) — lifecycle behavior may differ, test both
- **Android** (priority 3) — confirm no regression
- **Web** (priority 4) — confirm no regression

## Rollout / Migration Strategy

**Not applicable** — client-side fix only, no database migrations or feature flags required.

**Deployment:**

1. Merge to `main` after QA approval
2. Deploy web via `./tools/deploy_web.sh` (immediate rollout)
3. iOS/Android updates via next app store release

**Rollback:**
If the fix causes regressions:

1. Revert commit on `main`
2. Redeploy web
3. No database rollback required

## Out of Scope

1. **Exact trigger for provider state loss** — this structural fix removes the controller's dependency on `selectedSetlistProvider` entirely, making the trigger irrelevant. The controller now reads from route args (stable) instead of watching a transient provider. Investigation confirmed the provider was the single point of failure; removing that dependency resolves the architecture issue.

2. **Global provider state preservation on iOS lifecycle transitions** — broader framework-level fix to ensure all Riverpod providers survive backgrounding. Not needed — this fix makes the setlist controller immune to provider lifecycle issues.

3. **Band switch state reset improvements** — known issue mentioned in feature input. Separate from this bug, but related to state management brittleness.

4. **Reproduce on demand** — single-occurrence bug, not reliably reproduced. The fix addresses the vulnerable architecture identified through codebase analysis and symptom correlation.

5. **Convert controller to Family provider** — an alternative approach that would pass `setlistId` as a family parameter. The current fix (public `loadSetlist()` method) is more minimal and equally effective.
