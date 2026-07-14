# ARCHITECT_PLAN — Setlist Detail Empty After Load (iOS)

## Feature Slug
`bug/setlist-detail-empty-after-load`

## Problem Summary
On iOS production, a user opened the "New Songs" setlist (12 songs). The loading indicator spun, resolved to completion, but displayed zero songs — despite the setlist actually containing 12 songs. Force-quitting and reopening the app resolved the issue, with the setlist then loading correctly. This suggests transient client-side state loss rather than data corruption or RLS failure.

## Root Cause
**Confidence: HIGH**

The `SetlistDetailNotifier` watches `selectedSetlistProvider` and rebuilds whenever it changes. The controller's `build()` method contains this vulnerable logic:

```dart
if (!selected.isSelected) {
  _lastLoadedSetlistId = null;
  _cachedState = null;  // <--- Discards loaded songs!
  return const SetlistDetailState();  // Empty state: isLoading=false, songs=[]
}
```

When `selectedSetlistProvider` loses its state or becomes unselected (ID or name becomes null), the controller **immediately discards any previously loaded songs** and returns an empty state with `isLoading = false` and `songs = []`.

**Primary failure scenario:**

1. User opens setlist detail screen  
2. Screen's `initState` sets selected setlist via post-frame callback  
3. Controller loads songs successfully from Supabase  
4. Songs are displayed  
5. **iOS lifecycle event occurs** (app backgrounding, system interruption, or framework rebuild during multitasking)  
6. `selectedSetlistProvider` state is lost OR explicitly cleared by an unexpected code path  
7. Controller's `build()` detects `!selected.isSelected` and **discards cached songs**, returning empty state  
8. UI shows zero songs despite successful data in `_cachedState`  

**Evidence supporting this diagnosis:**

- **User report:** "resolved by force-quitting and reopening" → confirms transient state loss, not data corruption  
- **Single occurrence:** not systematic → points to race condition or lifecycle-triggered edge case  
- **iOS-specific:** platform lifecycle differences (iOS multitasking, backgrounding patterns differ from Android/Web)  
- **Known related issue:** "band-scoped state not fully reset on band switch" documented in feature input → confirms state management brittleness in the codebase  
- **Silent success:** loading completes (not stuck) → rules out the band ID stale-data guard, which would leave `isLoading = true` forever

**Why the band ID guard is NOT the root cause:**

The `loadSongs()` method has a guard that discards results if `_bandId` changed mid-flight:

```dart
final currentBandId = _bandId;
if (currentBandId != bandId) {
  debugPrint('[SetlistDetail] Discarding stale load result...');
  return;  // <--- Early return WITHOUT setting isLoading = false
}
```

If this guard triggered, the UI would remain stuck in loading state forever. The user reported the loading **completed** with zero songs shown, ruling out this code path.

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

**Make `SetlistDetailNotifier.build()` resilient to transient `selectedSetlistProvider` state loss.**

### Changes to Controller Logic

**Current vulnerable code:**
```dart
if (!selected.isSelected) {
  _lastLoadedSetlistId = null;
  _cachedState = null;  // <--- Discards loaded songs!
  return const SetlistDetailState();
}
```

**New resilient code:**
```dart
if (!selected.isSelected) {
  // DEFENSIVE: If we have cached state with songs, preserve it
  // This handles iOS lifecycle transitions where selectedSetlistProvider
  // transiently loses state but the user is still viewing the screen.
  if (_cachedState != null && _cachedState!.songs.isNotEmpty) {
    if (kDebugMode) {
      debugPrint(
        '[SetlistDetail] selectedSetlistProvider lost state, but preserving '
        '${_cachedState!.songs.length} cached songs for ${_cachedState!.setlistName}',
      );
    }
    return _cachedState!;
  }

  // No cached state to preserve — user legitimately navigated away or screen is initializing
  _lastLoadedSetlistId = null;
  _cachedState = null;
  return const SetlistDetailState();
}
```

**Rationale:**
- If cached state exists with songs, it means the setlist loaded successfully at some point  
- Returning the cached state prevents data loss during transient provider state loss  
- Defensive logging tracks how often this recovery path is taken (helps identify root cause frequency)  
- Normal navigation (user pops screen, selects different setlist) is unaffected — cached state is cleared when `_lastLoadedSetlistId` changes  

### Additional Safeguards

**Add mounted guard in screen's post-frame callback:**
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) {  // <--- Add mounted check
    ref.read(selectedSetlistProvider.notifier).select(...);
  }
});
```

This prevents setting selected setlist on a disposed widget (edge case, but good hygiene).

## Database Impact
**Not applicable** — client-side state management fix only. No migrations, RLS policies, RPCs, or triggers involved.

## Flutter Architecture Changes

### State Management (Riverpod)

**Modified:**
- `SetlistDetailNotifier.build()` — add fallback to `_cachedState` when `selected.isSelected` is false

**Unchanged:**
- `selectedSetlistProvider` (provider itself not modified)
- `activeBandProvider` (band switching logic unaffected)
- State setter override (still caches state on every update)

### Widgets

**Modified:**
- `SetlistDetailScreen.initState()` — add `mounted` guard to post-frame callback (defensive, not critical)

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
| [lib/features/setlists/setlist_detail_controller.dart](lib/features/setlists/setlist_detail_controller.dart) | Modify `SetlistDetailNotifier.build()`: add fallback to `_cachedState` when `!selected.isSelected` but cached songs exist; add debug logging for recovery path |
| [lib/features/setlists/setlist_detail_screen.dart](lib/features/setlists/setlist_detail_screen.dart) | Add `mounted` guard in `initState` post-frame callback before calling `selectedSetlistProvider.notifier.select()` |

## Files Off-Limits

| File | Reason |
|------|--------|
| [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart) | Repository fetch logic is correct — not the failure point |
| [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) | Band switching logic is independent; no evidence it's the trigger |
| [lib/features/auth/auth_gate.dart](lib/features/auth/auth_gate.dart) | Auth session refresh is necessary for persistent login; not the root cause |
| [lib/main.dart](lib/main.dart) | Init order must not change per guardrails |
| Any migration files in `supabase/migrations/` | No database changes required |

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — fix applies to setlist detail load path |
| Members / RBAC | unaffected |
| Auth / Session | **related** — iOS lifecycle/auth refresh may trigger the race condition, but no changes to auth logic |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS affected** (primary report), unknown if Android/Web/macOS exhibit same issue |

## Regression Risk
**Level: LOW**

**Rationale:**
- **Single controller file changed** — no database, auth, or routing modifications  
- **Defensive fix** — only adds a fallback path when provider state is unexpectedly lost  
- **Existing happy path unchanged** — normal navigation and load flow unaffected  
- **No async lifecycle changes** — no new `setState` calls, no new `mounted` risks beyond one defensive guard  
- **Other features isolated** — gigs, rehearsals, members, auth all unaffected  

**Risk areas to monitor:**
- **Stale data edge case:** If a setlist is deleted server-side while the screen shows cached songs, the cached state would persist. Mitigation: user can navigate away and back to trigger fresh load.  
- **Catalog vs. non-Catalog:** Both code paths use `_cachedState`, so the fix applies equally.  

## Engineer Task Breakdown

### Task 1 — Modify SetlistDetailNotifier.build()

**File:** `lib/features/setlists/setlist_detail_controller.dart`

**Change 1.1:** Modify the `!selected.isSelected` branch to preserve cached state

**Location:** `SetlistDetailNotifier.build()` method, first conditional block

**Before:**
```dart
if (!selected.isSelected) {
  _lastLoadedSetlistId = null;
  _cachedState = null;
  return const SetlistDetailState();
}
```

**After:**
```dart
if (!selected.isSelected) {
  // DEFENSIVE: If we have cached state with songs, preserve it.
  // This handles iOS lifecycle transitions where selectedSetlistProvider
  // transiently loses state but the user is still viewing the screen.
  if (_cachedState != null && _cachedState!.songs.isNotEmpty) {
    if (kDebugMode) {
      debugPrint(
        '[SetlistDetail] selectedSetlistProvider lost state, but preserving '
        '${_cachedState!.songs.length} cached songs for ${_cachedState!.setlistName}',
      );
    }
    return _cachedState!;
  }

  // No cached state to preserve — user legitimately navigated away or screen is initializing
  _lastLoadedSetlistId = null;
  _cachedState = null;
  return const SetlistDetailState();
}
```

**Validation:**
- Compile with `flutter analyze` — must pass with 0 errors  
- Verify debug log appears in console when recovery path is taken  
- Confirm existing navigation flows (tapping setlist card, popping screen) work unchanged  

---

### Task 2 — Add mounted guard to screen's post-frame callback

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Change 2.1:** Add `mounted` check before calling `select()`

**Location:** `_SetlistDetailScreenState.initState()` method, inside `addPostFrameCallback`

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
  if (mounted) {
    ref
        .read(selectedSetlistProvider.notifier)
        .select(id: widget.setlistId, name: widget.setlistName);
  }
});
```

**Validation:**
- Compile with `flutter analyze` — must pass with 0 errors  
- Test rapid navigation (open setlist, immediately pop) — no crashes  

---

### Task 3 — Run analyzer and commit

**Commands:**
```bash
flutter analyze
git add lib/features/setlists/setlist_detail_controller.dart lib/features/setlists/setlist_detail_screen.dart
git commit -m "fix(setlists): preserve cached songs when selectedSetlistProvider loses state (iOS)"
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

#### Test 2: iOS Background/Foreground Cycle While Viewing Setlist

**Platform:** iOS physical device (lifecycle behavior differs from simulator)  
**Preconditions:** Band with setlist containing 5+ songs  

**Steps:**
1. Open setlist detail screen (songs displayed)  
2. Press home button (app backgrounds)  
3. Wait 5 seconds  
4. Tap app icon to resume  
5. **Expected:** Setlist still shows songs (not empty)  
6. **Expected (if bug is triggered):** Console shows:  
   ```
   [SetlistDetail] selectedSetlistProvider lost state, but preserving 12 cached songs for New Songs
   ```

**Pass criteria:**  
- Songs remain visible after resume  
- If defensive log appears, it confirms the fix prevented data loss  
- If no log appears, the bug did not trigger (also acceptable)  

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

1. **Investigate root cause of selectedSetlistProvider state loss** — this fix makes the controller resilient, but does not prevent the underlying trigger (iOS lifecycle, Riverpod invalidation, or band refresh logic). If logs show frequent state loss, a follow-up investigation is warranted.  

2. **Global provider state preservation on iOS lifecycle transitions** — broader architectural fix to ensure all Riverpod providers survive backgrounding. This would require audit of all `NotifierProvider` instances and potential framework changes.  

3. **Band switch state reset improvements** — known issue mentioned in feature input. Separate from this bug, but related to state management brittleness.  

4. **Reproduce on demand** — single-occurrence bug, not yet reliably reproduced. This fix is defensive based on code analysis and symptom correlation.  

5. **Add to setlist from lookup/bulk entry** — feature works correctly, no changes needed for this bug fix.  
