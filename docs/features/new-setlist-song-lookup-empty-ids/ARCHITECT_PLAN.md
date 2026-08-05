# ARCHITECT_PLAN — New Setlist Song Lookup Empty IDs Bug

## Feature Slug

`bug/new-setlist-song-lookup-empty-ids`

---

## Problem Summary

Users cannot add songs to a newly created setlist via the "Song Lookup" (cover-search) overlay. Two symptoms manifest:

1. **Internal/catalog song matches:** The song tile becomes permanently greyed out with no error message. The user cannot interact with the tile, and the song is not added to the setlist.
2. **External/Spotify song matches:** An error snackbar appears: _"Failed to add song: ArgumentError: bandId, setlistId, and songId cannot be empty"_

Both symptoms share the same root cause: the `setlistDetailProvider`'s state has an empty `setlistId`, causing the repository validation to reject the request.

This affects only songs added via Song Lookup on the "Create New Setlist" screen. Other song entry methods (bulk entry, original song entry) and Song Lookup on existing setlists are unaffected.

**User report:** Richey Rock (richey_rock@hotmail.com), band "Momz Attic"  
**Platform:** Web  
**App version:** 1.4.4 (243)  
**Reported:** 1:51 PM, August 5, 2026

---

## Root Cause

**Confidence: HIGH** (confirmed in code)

This is a regression from **PR #64** (commit `10be42b`, merged 2026-07-13, "fix(setlists): remove selectedSetlistProvider dependency, add band-switch guard").

### What Changed in PR #64

PR #64 changed `SetlistDetailNotifier` to eliminate its dependency on `selectedSetlistProvider`. Previously, the controller watched this provider and automatically loaded setlist data when it changed. After PR #64:

1. The controller stopped watching `selectedSetlistProvider`
2. A new public method `loadSetlist(String id, String name, {bool forceReload = false})` was added
3. `setlist_detail_screen.dart` was updated to explicitly call `loadSetlist()` in `initState` with route arguments
4. **`new_setlist_screen.dart` was NOT updated** — it still only calls `ref.read(selectedSetlistProvider.notifier).select(id: result.id, name: result.name)` after creating a setlist

### The Failure Chain

**In `new_setlist_screen.dart` (lines 160-162):**

```dart
ref
    .read(selectedSetlistProvider.notifier)
    .select(id: result.id, name: result.name);
```

This updates `selectedSetlistProvider`, but `setlistDetailProvider` no longer watches it.

**In `setlist_detail_controller.dart` (line 159):**

```dart
const SetlistDetailState({
  this.setlistId = '',  // ← Defaults to empty string
  ...
});
```

Without a call to `loadSetlist()`, `state.setlistId` remains `''`.

**When user taps a song in Song Lookup (lines 449-464 in `new_setlist_screen.dart`):**

```dart
onSongAdded: (songId, title, artist) async {
  return ref
      .read(setlistDetailProvider.notifier)
      .addSong(songId, title, artist);
},
```

**In `setlist_detail_controller.dart` (lines 1841-1843):**

```dart
final result = await _repository.addSongToSetlistEnsureCatalog(
  bandId: bandId,
  setlistId: state.setlistId,  // ← This is still ''
  songId: songId,
  ...
);
```

**In `setlist_repository.dart` (lines 3744-3745):**

```dart
if (bandId.isEmpty || setlistId.isEmpty || songId.isEmpty) {
  throw ArgumentError('bandId, setlistId, and songId cannot be empty');
}
```

This validation correctly rejects the request.

### Why Two Different Symptoms?

**Internal/catalog songs** (`_handleSongTap()` in `song_lookup_overlay.dart`, lines 238-261):

- NO try/catch around `await widget.onSongAdded(...)`
- When the exception is thrown, execution unwinds without ever reaching `_isAdding = false` (line 253)
- The tile remains greyed out permanently (`opacity: 0.5`, `onTap: null` when `_isAdding == true`)
- No error message is shown to the user

**External/Spotify songs** (`_handleExternalSongTap()` in `song_lookup_overlay.dart`, lines 276-317):

- HAS try/catch wrapping the call
- Catches the exception and calls `setState(() { _isAdding = false; })`
- Shows error snackbar: `showErrorSnackBar(context, message: 'Failed to add song: $e')`

---

## Reference Docs Consulted

- `docs/reference/architecture/architecture.md` — Riverpod patterns, state management conventions, feature-first structure
- Git history: `git show 10be42b` — verified PR #64 changes and rationale

No setlist-specific reference docs exist in `docs/reference/`.

---

## Existing System Analysis

### Current Behavior (Broken)

**Flow for new setlist creation:**

1. User taps "Create New Setlist" → `new_setlist_screen.dart` displayed
2. User enters setlist name, taps "Create Setlist"
3. `repository.createSetlist()` succeeds, returns `Setlist(id, name)`
4. Screen calls `selectedSetlistProvider.notifier.select(id, name)` (line 160-162)
5. `setlistDetailProvider` state is NOT updated (controller doesn't watch `selectedSetlistProvider`)
6. Song Lookup overlay opens — user searches and taps a song
7. Callback invokes `setlistDetailProvider.notifier.addSong(songId, title, artist)`
8. `addSong()` calls repository with `state.setlistId` (which is still `''`)
9. Repository validation throws `ArgumentError`

**For internal songs:** Exception unhandled → `_isAdding` stuck true → permanent grey-out  
**For external songs:** Exception caught → error snackbar shown

### Working Pattern (Existing Setlists)

**Flow for existing setlist:**

1. User taps a setlist from the list → `setlist_detail_screen.dart` pushed with route args
2. In `initState` (lines 133-140):
   ```dart
   WidgetsBinding.instance.addPostFrameCallback((_) {
     ref.read(setlistDetailProvider.notifier).loadSetlist(
       widget.setlistId,
       widget.setlistName,
       forceReload: true,
     );
   });
   ```
3. `loadSetlist()` updates controller's `_setlistId`, `_setlistName`, and `state.setlistId`
4. Song Lookup works correctly because `state.setlistId` is populated

---

## Proposed Solution

### Root Cause Fix

**In `new_setlist_screen.dart`, after setlist creation succeeds:**

Replace the `selectedSetlistProvider.notifier.select()` call with a direct call to `setlistDetailProvider.notifier.loadSetlist()`, mirroring the pattern used in `setlist_detail_screen.dart`.

**Before (lines 160-162):**

```dart
// Set up the provider for this setlist
ref
    .read(selectedSetlistProvider.notifier)
    .select(id: result.id, name: result.name);
```

**After:**

```dart
// Load setlist into detail controller
ref.read(setlistDetailProvider.notifier).loadSetlist(
  result.id,
  result.name,
  forceReload: true,
);
```

**Rationale:**

- Synchronizes the screen with the working pattern in `setlist_detail_screen.dart`
- Directly updates the controller's state instead of relying on a provider watch that no longer exists
- `forceReload: true` ensures state is refreshed even if the controller previously had data for this ID

**Should we also update `selectedSetlistProvider`?**
No. After grepping the codebase, `selectedSetlistProvider` is only used for write-side coordination (highlighting, navigation state). It does not need to be set here, and removing this call aligns with the intent of PR #64 to eliminate the controller's dependency on it. If other parts of the UI need to know "which setlist is selected," they should read route state or local screen state, not a global provider.

### Defense-in-Depth UX Fix

**In `song_lookup_overlay.dart`, `_handleSongTap()` method:**

Wrap the `await widget.onSongAdded(...)` call in a try/catch block, matching the error handling pattern already present in `_handleExternalSongTap()`.

**Before (lines 238-261):**

```dart
Future<void> _handleSongTap(Song song) async {
  if (_isAdding) return;

  setState(() {
    _isAdding = true;
  });

  final result = await widget.onSongAdded(song.id, song.title, song.artist);

  if (mounted) {
    if (result.success) {
      Navigator.of(context).pop();
      showAppSnackBar(context, message: result.friendlyMessage);
    } else {
      setState(() {
        _isAdding = false;
      });
      showErrorSnackBar(
        context,
        message: 'Failed to add song. Please try again.',
      );
    }
  }
}
```

**After:**

```dart
Future<void> _handleSongTap(Song song) async {
  if (_isAdding) return;

  setState(() {
    _isAdding = true;
  });

  try {
    final result = await widget.onSongAdded(song.id, song.title, song.artist);

    if (mounted) {
      if (result.success) {
        Navigator.of(context).pop();
        showAppSnackBar(context, message: result.friendlyMessage);
      } else {
        setState(() {
          _isAdding = false;
        });
        showErrorSnackBar(
          context,
          message: 'Failed to add song. Please try again.',
        );
      }
    }
  } catch (e) {
    debugPrint('[SongLookup] Internal song add error: $e');
    if (mounted) {
      setState(() {
        _isAdding = false;
      });
      showErrorSnackBar(context, message: 'Failed to add song: $e');
    }
  }
}
```

**Rationale:**

- Prevents permanent grey-out state if any future error occurs in the add-song flow
- Matches the error handling pattern already established for external songs
- Provides user feedback instead of silent failure
- Does not mask the root cause — once `loadSetlist()` is called, this catch block should never execute in normal operation

---

## Database Impact

**Not applicable.** This is a client-side state synchronization bug. No database schema, RLS policies, RPCs, or triggers are affected.

---

## Flutter Architecture Changes

### State Management

**Controller:** `SetlistDetailNotifier` (`lib/features/setlists/setlist_detail_controller.dart`)

- No changes required — `loadSetlist()` method already exists (added in PR #64)

**Screen:** `NewSetlistScreen` (`lib/features/setlists/new_setlist_screen.dart`)

- Call `setlistDetailProvider.notifier.loadSetlist()` after successful setlist creation

**Widget:** `SongLookupOverlay` (`lib/features/setlists/widgets/song_lookup_overlay.dart`)

- Add try/catch to `_handleSongTap()` method

### Repositories

**No changes.** The validation logic in `setlist_repository.dart` (lines 3744-3745) is correct and must remain unchanged.

### Widgets

Only `SongLookupOverlay`'s internal error handling is modified. No external interfaces change.

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                     | What changes                                                                                                                                    |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/new_setlist_screen.dart`          | Replace `selectedSetlistProvider.notifier.select()` with `setlistDetailProvider.notifier.loadSetlist()` after setlist creation (lines ~160-162) |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | Wrap `await widget.onSongAdded(...)` in try/catch within `_handleSongTap()` method (lines ~238-261)                                             |

---

## Files Off-Limits

| File                                                                   | Reason                                                                     |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart`                        | Validation logic is correct — bug is upstream in state synchronization     |
| `lib/features/setlists/setlist_detail_controller.dart`                 | `loadSetlist()` method already exists and works correctly                  |
| `lib/features/setlists/setlist_detail_screen.dart`                     | Already correctly calls `loadSetlist()` — reference pattern, do not modify |
| `lib/features/setlists/selected_setlist_provider.dart`                 | Do not re-introduce controller dependency removed by PR #64                |
| `lib/app/constants/app_constants.dart`                                 | No constant changes required                                               |
| Bulk entry flow (lines ~348-371 in `new_setlist_screen.dart`)          | Unaffected — uses local `_setlistId!` directly, not controller             |
| Original song entry flow (lines ~405-432 in `new_setlist_screen.dart`) | Unaffected — uses local `_setlistId!` directly, not controller             |

---

## System Impact Map

| System                                 | Impact                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                |
| Rehearsals                             | unaffected                                                                |
| Setlists / Catalog                     | **affected** — Song Lookup on newly created setlists                      |
| Members / RBAC                         | unaffected                                                                |
| Auth / Session                         | unaffected                                                                |
| Routing                                | unaffected                                                                |
| Notifications                          | unaffected                                                                |
| Platform (iOS / Android / Web / macOS) | **affected** — bug exists on all platforms (Web confirmed by user report) |

---

## Regression Risk

**Level: LOW**

**Rationale:**

- Change touches only one isolated screen (`new_setlist_screen.dart`) and one shared widget (`song_lookup_overlay.dart`)
- Existing setlists' Song Lookup flow is unaffected (already working via `setlist_detail_screen.dart`)
- Bulk entry and original song entry on new setlists are unaffected (bypass controller entirely)
- The `loadSetlist()` method is already battle-tested from PR #64 (existing setlists use it successfully)
- The try/catch addition in `song_lookup_overlay.dart` is defensive only — does not change control flow in success cases
- No database, RLS, or backend logic is touched
- No initialization order, auth, or routing changes

**Risk vectors monitored:**

- Song Lookup on existing setlists (must remain working)
- Bulk entry and original song entry on new setlists (must remain working)
- Inline editing after adding songs to new setlist (broadcast mechanism must work)

---

## Engineer Task Breakdown

### Task 1: Update New Setlist Screen to Call loadSetlist()

**File:** `lib/features/setlists/new_setlist_screen.dart`

**Location:** After successful `createSetlist()` call (lines ~160-162)

**Change 1.1: Replace selectedSetlistProvider call**

Find this block:

```dart
// Set up the provider for this setlist
ref
    .read(selectedSetlistProvider.notifier)
    .select(id: result.id, name: result.name);
```

Replace with:

```dart
// Load setlist into detail controller
ref.read(setlistDetailProvider.notifier).loadSetlist(
  result.id,
  result.name,
  forceReload: true,
);
```

**Verification:**

- `flutter analyze` must pass
- Grep for `selectedSetlistProvider.notifier.select` in the file — should have zero matches after change (if this was the only usage in this file; verify no other legitimate usages exist)
- Visual inspection: confirm `setlistDetailProvider` is imported at the top of the file

---

### Task 2: Add Try/Catch to Song Lookup Overlay Internal Song Tap Handler

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`

**Location:** `_handleSongTap()` method (lines ~238-261)

**Change 2.1: Wrap onSongAdded call in try/catch**

Find the method:

```dart
Future<void> _handleSongTap(Song song) async {
  if (_isAdding) return;

  setState(() {
    _isAdding = true;
  });

  final result = await widget.onSongAdded(song.id, song.title, song.artist);

  if (mounted) {
    if (result.success) {
      Navigator.of(context).pop();
      showAppSnackBar(context, message: result.friendlyMessage);
    } else {
      setState(() {
        _isAdding = false;
      });
      showErrorSnackBar(
        context,
        message: 'Failed to add song. Please try again.',
      );
    }
  }
}
```

Replace with:

```dart
Future<void> _handleSongTap(Song song) async {
  if (_isAdding) return;

  setState(() {
    _isAdding = true;
  });

  try {
    final result = await widget.onSongAdded(song.id, song.title, song.artist);

    if (mounted) {
      if (result.success) {
        Navigator.of(context).pop();
        showAppSnackBar(context, message: result.friendlyMessage);
      } else {
        setState(() {
          _isAdding = false;
        });
        showErrorSnackBar(
          context,
          message: 'Failed to add song. Please try again.',
        );
      }
    }
  } catch (e) {
    debugPrint('[SongLookup] Internal song add error: $e');
    if (mounted) {
      setState(() {
        _isAdding = false;
      });
      showErrorSnackBar(context, message: 'Failed to add song: $e');
    }
  }
}
```

**Verification:**

- `flutter analyze` must pass
- Pattern matches `_handleExternalSongTap()` (lines ~263-326) which already has correct try/catch structure
- Visual inspection: confirm `debugPrint` import is present (should already exist in file)

---

## Verification Plan

### Manual Testing

**Test 1: Create new setlist → Add internal song via Song Lookup**

**Steps:**

1. Log in on web (or any platform)
2. Navigate to Setlists tab
3. Tap "Create New Setlist"
4. Enter name: "Test Setlist [timestamp]"
5. Tap "Create Setlist"
6. Wait for screen to animate in (~1 second)
7. Tap "Song Lookup" button (magnifying glass icon)
8. Search for a song that exists in the Catalog (e.g., "Wonderwall")
9. Tap the song tile

**Expected:**

- Overlay closes immediately
- Snackbar appears with success message (e.g., "🎸 'Wonderwall' added to Test Setlist")
- Song appears in the setlist
- Song tile does NOT grey out permanently

**Fail criteria:**

- Song tile greys out and stays greyed out
- No snackbar appears
- Song is not added to setlist

---

**Test 2: Create new setlist → Add external song via Song Lookup**

**Steps:**

1. Continue from Test 1 (or create another new setlist)
2. Tap "Song Lookup"
3. Search for a song that does NOT exist in the Catalog (use an obscure artist/title)
4. Tap an external result (Spotify icon present)
5. Review sheet appears — confirm/edit BPM, Duration, Key
6. Tap "Add to Setlist"

**Expected:**

- Overlay closes
- Snackbar with success message
- Song appears in setlist
- Song is now in the Catalog

**Fail criteria:**

- Error snackbar: "Failed to add song: ArgumentError: bandId, setlistId, and songId cannot be empty"
- Song not added

---

**Test 3: Existing setlist → Add song via Song Lookup (regression check)**

**Steps:**

1. Navigate to Setlists tab
2. Tap an EXISTING setlist (not newly created)
3. Tap "Song Lookup"
4. Search and tap a song (internal or external)

**Expected:**

- Song adds successfully (no change from current behavior)

**Fail criteria:**

- Any regression — error, grey-out, failure to add

---

**Test 4: New setlist → Add song via Bulk Entry (unaffected path check)**

**Steps:**

1. Create new setlist
2. Tap "Bulk Entry" button
3. Paste:
   ```
   Song One - Artist A
   Song Two - Artist B
   ```
4. Tap "Add Songs"

**Expected:**

- Both songs added successfully
- No errors

**Fail criteria:**

- Bulk entry broken (should be impossible, but verify)

---

**Test 5: New setlist → Add song via Original Song Entry (unaffected path check)**

**Steps:**

1. Create new setlist
2. Tap "Original Song" button (pencil icon)
3. Enter title: "My Original Song", artist: "My Band", BPM: 120, duration: 3:30
4. Tap "Add to Catalog & Setlist"

**Expected:**

- Song added to both Catalog and setlist
- No errors

**Fail criteria:**

- Original song entry broken (should be impossible, but verify)

---

### Code Verification

**Check 1: Confirm loadSetlist() is called in new_setlist_screen.dart**

```bash
grep -n "setlistDetailProvider.notifier.loadSetlist" lib/features/setlists/new_setlist_screen.dart
```

**Expected:** One match at the location where setlist creation succeeds (around line 160-162, exact line may shift after edit)

---

**Check 2: Confirm selectedSetlistProvider.select is removed from new_setlist_screen.dart**

```bash
grep -n "selectedSetlistProvider.notifier.select" lib/features/setlists/new_setlist_screen.dart
```

**Expected:** Zero matches (assuming there were no other legitimate usages in this file)

---

**Check 3: Confirm try/catch is present in \_handleSongTap**

```bash
grep -A 5 "Future<void> _handleSongTap" lib/features/setlists/widgets/song_lookup_overlay.dart | grep "try {"
```

**Expected:** Match found

---

**Check 4: Run flutter analyze**

```bash
flutter analyze
```

**Expected:** 0 errors, 0 warnings related to these files

---

## QA Regression Areas

### Primary Testing (Must Pass)

1. **Song Lookup on new setlist (internal song)** — Test 1 above
2. **Song Lookup on new setlist (external song)** — Test 2 above
3. **Song Lookup on existing setlist** — Test 3 above
4. **Bulk entry on new setlist** — Test 4 above
5. **Original song entry on new setlist** — Test 5 above
6. **Inline editing after Song Lookup add** — After adding a song via Song Lookup on a new setlist, tap the song card and edit BPM/Duration/Tuning inline. Confirm edits save and broadcast to other open setlists (if applicable).

### Secondary Testing (Should Not Regress)

7. **Create setlist, navigate away, navigate back** — Confirm setlist loads correctly when re-opened
8. **Band switch while on new setlist screen** — Switch bands via band selector. Screen should clear or navigate away gracefully (per existing band-switch behavior).
9. **Song Lookup search performance** — No degradation in search speed or UI responsiveness

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-only bug fix with no database schema changes, no backend changes, and no data migration required.

Deploy via standard web deployment:

```bash
./tools/deploy_web.sh
```

Native app updates will receive the fix in the next release cycle.

---

## Out of Scope

The following are explicitly excluded from this fix:

1. **Re-introducing `selectedSetlistProvider` dependency in controller** — PR #64 removed this for good architectural reasons (band-switch guard). Do not revert that design.

2. **Modifying setlist creation flows in `setlist_detail_screen.dart`** — Lines 383 and 1369 create setlists as part of song copy/move operations. These do not require `loadSetlist()` calls because the user remains on the original screen context.

3. **Refactoring or consolidating setlist creation logic** — Multiple code paths for setlist creation exist with different post-creation behaviors. Do not opportunistically unify them.

4. **Modifying bulk entry or original song entry flows** — These work correctly and bypass `setlistDetailProvider` entirely by using local `_setlistId!`.

5. **Changing repository validation logic** — The `isEmpty` checks in `setlist_repository.dart` are correct and should remain unchanged.

6. **Error message customization** — The catch block in `song_lookup_overlay.dart` surfaces the raw error `$e`. This is acceptable for this fix. Future work could provide friendlier messages, but that is not required here.

7. **Investigating why `selectedSetlistProvider.select()` was originally called** — Historical context is documented in PR #64. Do not re-litigate that decision.

8. **Web vs. native behavior differences** — This bug exists on all platforms. No platform-specific fixes are required.

---

**END OF ARCHITECT PLAN**
