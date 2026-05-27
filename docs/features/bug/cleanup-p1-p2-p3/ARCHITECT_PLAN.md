# ARCHITECT PLAN — bug/cleanup-p1-p2-p3

---

## 1. Feature Slug

`bug/cleanup-p1-p2-p3`

Branch: `bug/cleanup-p1-p2-p3`
Docs path: `docs/features/bug/cleanup-p1-p2-p3/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

Three independent bugs identified in `CODE_REVIEW_REPORT.md` (P1–P3):

**P1 — Dead AcousticBrainz code**
The `_fetchAcousticBrainzBpm()` function in `setlist_repository.dart` invokes a
Supabase Edge Function that calls the AcousticBrainz API. AcousticBrainz was shut down
in November 2022. Every invocation fails with a network/404 error. The failure is caught
silently inside `_attemptBpmEnrichment()`. Effect: 200–500 ms of wasted latency added to
every BPM enrichment attempt when no Spotify ID is available, plus unnecessary Supabase
Edge Function invocation quota consumption.

**P2 — Silent error swallowing in repository catch blocks**
Multiple repository functions in `members_repository.dart` and
`user_band_roles_repository.dart` catch network/database errors and return
`false`/`null`/`[]`/`{}` instead of rethrowing. This makes genuine failures
indistinguishable from legitimate "no data" results. For example, `removeMember()`
returning `false` could mean either "RPC failed" or "member not found" — the caller
cannot distinguish.

**P3 — `_lastLoadedBandId` + `Future.microtask` anti-pattern in `SetlistsNotifier`**
`SetlistsNotifier.build()` tracks `_lastLoadedBandId` and schedules loads via
`Future.microtask()` to avoid reacting to the reactive model it already participates in.
This is a known race-condition anti-pattern in the codebase (documented in
`calendar_controller.dart`). It is the last remaining instance.

---

## 3. Root Cause

### P1 — AcousticBrainz dead code

**Confidence: HIGH** — Confirmed in code.

`_attemptBpmEnrichment()` in `setlist_repository.dart` has a two-strategy BPM fetch:

```
Strategy 1: Spotify Audio Features  (working — uses live API via edge function)
Strategy 2: AcousticBrainz fallback (dead — API shut down November 2022)
```

Strategy 2 call site (lines ~3959–3969):

```dart
// Strategy 2: Fallback to AcousticBrainz if Spotify failed
if (bpm == null) {
  bpm = await _fetchAcousticBrainzBpm(title, artist);
  ...
}
```

Implementation (~lines 4049–4081):

```dart
Future<int?> _fetchAcousticBrainzBpm(String title, String artist) async {
  try {
    final response = await supabase.functions.invoke(
      'acousticbrainz_bpm',
      body: {'title': title, 'artist': artist},
    );
    ...
  } catch (e) { ... return null; }
}
```

Every invocation of the edge function silently fails. There is no mechanism to skip it.

### P2 — Silent error swallowing

**Confidence: HIGH** — Confirmed in code. Each catch block directly observed.

**`members_repository.dart`:**

| Function                        | Line | Current catch behavior | Should be                             |
| ------------------------------- | ---- | ---------------------- | ------------------------------------- |
| `removeMember()`                | ~355 | `return false`         | `rethrow`                             |
| `fetchContributorPermissions()` | ~379 | `return null`          | `rethrow`                             |
| `updateMemberRole()`            | ~421 | `rethrow`              | ✅ Already correct — no change needed |
| `isCurrentUserAdmin()`          | ~468 | `return false`         | `rethrow`                             |

Note: `updateMemberRole()` was listed in the feature input as broken, but inspection
confirms it already uses `rethrow`. No change needed for that function.

**`user_band_roles_repository.dart`:**

| Function               | Line | Current catch behavior | Should be |
| ---------------------- | ---- | ---------------------- | --------- |
| `fetchRolesForBand()`  | ~101 | `return []`            | `rethrow` |
| `fetchRolesForBands()` | ~176 | `return {}`            | `rethrow` |
| `fetchRolesForUsers()` | ~220 | `return {}`            | `rethrow` |
| `hasRolesForBand()`    | ~255 | `return false`         | `rethrow` |

### P3 — `_lastLoadedBandId` + `Future.microtask` anti-pattern

**Confidence: HIGH** — Confirmed in code. Anti-pattern directly observed.

`SetlistsNotifier.build()` already watches `activeBandIdProvider`, meaning Riverpod
will re-execute `build()` whenever the band changes. The `_lastLoadedBandId` check and
`Future.microtask()` scheduling were added to work _around_ the reactive model rather
than _with_ it. The reference fix in `calendar_controller.dart` (~line 183) shows the
correct pattern: call the async load method directly from `build()`, let Riverpod manage
the reactive lifecycle.

---

## 4. Reference Docs Consulted

This feature is not in the notifications domain. The standard reference doc path
(`docs/reference/notifications/`) is not applicable.

Files read during diagnosis:

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/general/AI_DECISIONS.md`
- `CODE_REVIEW_REPORT.md` (sections P1–P5)
- `lib/features/setlists/setlist_repository.dart` (lines 3900–4090)
- `lib/features/members/members_repository.dart` (full file)
- `lib/features/profile/user_band_roles_repository.dart` (lines 1–270)
- `lib/features/setlists/setlists_screen.dart` (full file)
- `lib/features/calendar/calendar_controller.dart` (lines 170–220)
- `lib/features/members/members_controller.dart` (lines 95–170)
- `lib/features/members/members_tab_content.dart` (lines 105–230)
- `lib/features/members/widgets/role_management_sheet.dart` (lines 60–230)
- `lib/features/profile/my_profile_screen.dart` (lines 245–300)

---

## 5. Existing System Analysis

### P1 — BPM enrichment data flow

```
Song created in _createSong()
  └─> _attemptBpmEnrichment() [fire-and-forget, never awaited]
        ├─> Strategy 1: _fetchSpotifyBpm()  [WORKS — edge fn calls Spotify]
        │     └─> If bpm != null: update via RPC update_song_metadata
        └─> Strategy 2: _fetchAcousticBrainzBpm()  [DEAD]
              └─> Calls edge fn 'acousticbrainz_bpm' → 404 / network error
                  └─> Caught silently, returns null
                        └─> "Give up if both strategies failed" → returns
```

After Strategy 1 succeeds, Strategy 2 is only executed when `bpm == null` (Spotify
failed). There is no case where the AcousticBrainz call can succeed. Removing it
eliminates wasted latency and invocation quota on the fallback path.

### P2 — Error visibility chain

Current chain for `removeMember` as an example:

```
repository.removeMember()
  catch(e) → return false              ← swallows error at repo layer

members_controller.removeMember()
  catch(e) → return false              ← swallows error at controller layer

role_management_sheet._removeMember()
  if (success == false) → showErrorSnackBar  ← shows message, but not the actual error
```

The user does see "Failed to remove member" in the UI, but:

1. The actual exception is lost before it reaches any logger or crash reporter.
2. `false` on network failure is indistinguishable from `false` on "member not found".

After the fix, the repository rethrows, the controller receives the real exception, and
logging/crash reporting (if added later) receives a stack trace.

### P3 — Current `build()` flow

```
build() {
  bandId = ref.watch(activeBandIdProvider)    ← correct: watches reactive source
  if (bandId != _lastLoadedBandId) {          ← anti-pattern: manual change tracking
    _lastLoadedBandId = bandId
    Future.microtask(() => loadSetlists())    ← anti-pattern: deferred scheduling
    return SetlistsState(isLoading: true)
  }
  if (_cachedState != null) return _cachedState!
  Future.microtask(() => loadSetlists())      ← anti-pattern: second microtask path
  return SetlistsState(isLoading: true)
}
```

Because `activeBandIdProvider` is the only watched dependency in `build()`, Riverpod
will re-execute `build()` exactly when the band changes. There is no need for
`_lastLoadedBandId` to track that change manually.

---

## 6. Proposed Solution

### P1 — Remove AcousticBrainz dead code

**Minimal change:**

1. Delete the Strategy 2 block (~4 lines) in `_attemptBpmEnrichment()`.
2. Delete the `_fetchAcousticBrainzBpm()` method (~33 lines).
3. Record the removal in `docs/reference/general/AI_DECISIONS.md` as DECISION-002.

The `supabase/functions/acousticbrainz_bpm/` directory on disk must **not** be deleted —
Tony will undeploy it manually via `supabase functions delete acousticbrainz_bpm`.

After the change, `_attemptBpmEnrichment()` has one strategy (Spotify) and then gives
up. All existing guard logic (bpm clamping, WHERE bpm IS NULL RPC call) is unchanged.

### P2 — Fix silent error swallowing

**Minimal change:** Replace each `return false/null/[]/{}` in the identified catch
blocks with `rethrow`. No new exception types, no new wrappers, no signature changes.

Because no typed `RepositoryException` class exists in the codebase, use bare `rethrow`
throughout. The existing `print(...)` log line in each catch block must be retained so
error context is still logged before rethrowing.

One call site requires a try/catch wrapper to be added (see Section 10 — Files to
Modify for details):

- `role_management_sheet.dart:_loadExistingPermissions()` — currently calls
  `fetchContributorPermissions()` with no exception handler. After the repository
  rethrows, this unguarded await will propagate as an unhandled exception. A try/catch
  must be added.

### P3 — Remove `_lastLoadedBandId` + `Future.microtask`

**Minimal change, following the reference implementation in `calendar_controller.dart`:**

1. Remove the `_lastLoadedBandId` field declaration.
2. Remove the `_cachedState` field declaration and all assignment sites.
3. Rewrite `build()` to call `loadSetlists()` directly without `Future.microtask()`.
4. Remove the four `_cachedState = ...` assignment lines from `loadSetlists()`,
   `deleteSetlist()`, `reorderLocal()`, and `persistReorder()`.

**Why `_cachedState` is also removed:**
`_cachedState` was introduced alongside the `_lastLoadedBandId` pattern to return
stale-but-non-flashing state when `build()` re-ran without a band change. In the
reactive model (where `build()` only re-runs on a genuine `activeBandIdProvider`
change), this cache is unnecessary. The reference implementation (CalendarNotifier)
does not use it. Retaining it would require keeping logic that determines when to
populate it — which re-introduces the same complexity being removed.

**What does NOT change:**

- `loadSetlists()` logic, Supabase queries, error handling
- `SetlistsState` shape (all fields unchanged)
- `deleteSetlist()`, `reorderLocal()`, `persistReorder()` logic
  (only the `_cachedState = ...` side-effect lines are removed)
- The `setlistsProvider` declaration
- The `SetlistsScreen` widget and all UI code

---

## 7. Database Impact

Not applicable.

No migrations, RLS policy changes, RPC signature changes, or trigger modifications
are required for any of the three tasks.

The `update_song_metadata` RPC called by `_attemptBpmEnrichment()` is not modified and
continues to be called by Strategy 1 (Spotify) when successful.

---

## 8. Flutter Architecture Changes

### P1

- One repository method removed (`_fetchAcousticBrainzBpm`).
- One call site removed within the same file.
- Fire-and-forget enrichment behavior is unchanged.

### P2

- Seven repository catch blocks changed from silent returns to `rethrow`.
- One widget method (`_loadExistingPermissions`) gains a try/catch guard.
- No state shape changes. No provider changes. No new classes or files.

### P3

- `SetlistsNotifier` loses two fields (`_lastLoadedBandId`, `_cachedState`) and
  simplified `build()` method.
- Provider declaration, state shape, and all public methods are unchanged.
- Widget layer (`SetlistsScreen`, `_SetlistsScreenState`) is unchanged.

---

## 9. Files to Create

`docs/features/bug/cleanup-p1-p2-p3/ARCHITECT_PLAN.md` — this file (already created).

No other new files required.

---

## 10. Files to Modify

### Task 1 — P1

| File                                            | Change                                                                                           |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_repository.dart` | Delete Strategy 2 block in `_attemptBpmEnrichment()` + delete `_fetchAcousticBrainzBpm()` method |
| `docs/reference/general/AI_DECISIONS.md`        | Append DECISION-002 entry documenting the removal                                                |

**Exact deletions in `setlist_repository.dart`:**

Delete this block in `_attemptBpmEnrichment()` (~lines 3959–3969):

```dart
      // Strategy 2: Fallback to AcousticBrainz if Spotify failed
      if (bpm == null) {
        bpm = await _fetchAcousticBrainzBpm(title, artist);
        if (bpm != null) {
          if (kDebugMode) {
            debugPrint(
              '[SetlistRepository] ✓ AcousticBrainz BPM=$bpm for "$title"',
            );
          }
        }
      }
```

Delete the entire `_fetchAcousticBrainzBpm()` method (~lines 4049–4081):

```dart
  /// Fetch BPM from AcousticBrainz API via Edge Function.
  /// Returns null on any failure (never throws).
  Future<int?> _fetchAcousticBrainzBpm(String title, String artist) async {
    try {
      final response = await supabase.functions.invoke(
        'acousticbrainz_bpm',
        body: {'title': title, 'artist': artist},
      );

      final data = response.data;
      if (data is! Map || data['bpm'] == null) {
        return null;
      }

      final bpm = data['bpm'];
      if (bpm is int) {
        return bpm;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SetlistRepository] AcousticBrainz BPM fetch failed: $e');
      }
      return null;
    }
  }
```

Also delete the `// HYBRID BPM ENRICHMENT (SPOTIFY → ACOUSTICBRAINZ FALLBACK)`
section comment and update to reflect the Spotify-only strategy. Rename the section
comment to:

```
// HYBRID BPM ENRICHMENT (SPOTIFY ONLY)
```

And update the doc comment on `_attemptBpmEnrichment()` accordingly:

- Change `/// 2. Fallback to AcousticBrainz` line to remove it
- Change `/// 3. Give up if both fail` to `/// 2. Give up if Spotify fails`

**AI_DECISIONS.md entry to append:**

```markdown
## [DECISION-002] Remove AcousticBrainz BPM Fallback

**Date:** 2026-05-27
**Feature:** bug/cleanup-p1-p2-p3
**Agent:** Architect
**Status:** Active

### Context

`_fetchAcousticBrainzBpm()` in `setlist_repository.dart` invoked a Supabase Edge
Function (`acousticbrainz_bpm`) that called the AcousticBrainz API. AcousticBrainz
was permanently shut down in November 2022. Every invocation failed silently, adding
200–500 ms latency to the BPM enrichment fallback path and consuming Edge Function
invocation quota.

### Decision

Remove the `_fetchAcousticBrainzBpm()` method and its call site in
`_attemptBpmEnrichment()`. The Supabase Edge Function source code
(`supabase/functions/acousticbrainz_bpm/`) is retained on disk for Tony to undeploy
manually via `supabase functions delete acousticbrainz_bpm`.

### Rationale

The API is permanently gone. There is no recovery path. The Spotify fallback
(Strategy 1) is the only working BPM source. Removing the dead code eliminates
latency and invocation waste with zero functional regression.

### Constraints Imposed

BPM enrichment now relies solely on Spotify Audio Features. Any future BPM fallback
source (e.g., MusicBrainz, AcoustID) must be implemented as a new named strategy
with its own edge function and decision log entry.
```

---

### Task 2 — P2

| File                                                      | Change                                                                      |
| --------------------------------------------------------- | --------------------------------------------------------------------------- |
| `lib/features/members/members_repository.dart`            | Replace `return false/null` with `rethrow` in three catch blocks            |
| `lib/features/profile/user_band_roles_repository.dart`    | Replace `return []/{}` / `return false` with `rethrow` in four catch blocks |
| `lib/features/members/widgets/role_management_sheet.dart` | Add try/catch to `_loadExistingPermissions()`                               |

**Exact changes in `members_repository.dart`:**

1. `removeMember()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     // ignore: avoid_print
     print('[MembersRepository] Failed to remove member: $e');
     return false;
   }

   // AFTER
   } catch (e) {
     // ignore: avoid_print
     print('[MembersRepository] Failed to remove member: $e');
     rethrow;
   }
   ```

2. `fetchContributorPermissions()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     // ignore: avoid_print
     print('[MembersRepository] Failed to fetch contributor permissions: $e');
     return null;
   }

   // AFTER
   } catch (e) {
     // ignore: avoid_print
     print('[MembersRepository] Failed to fetch contributor permissions: $e');
     rethrow;
   }
   ```

3. `isCurrentUserAdmin()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     return false;
   }

   // AFTER
   } catch (e) {
     rethrow;
   }
   ```

**Exact changes in `user_band_roles_repository.dart`:**

4. `fetchRolesForBand()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     // On error, return empty list and don't cache
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error fetching roles: $e');
     return [];
   }

   // AFTER
   } catch (e) {
     // On error, don't cache — rethrow so caller can handle
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error fetching roles: $e');
     rethrow;
   }
   ```

5. `fetchRolesForBands()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error batch fetching roles: $e');
     return {};
   }

   // AFTER
   } catch (e) {
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error batch fetching roles: $e');
     rethrow;
   }
   ```

6. `fetchRolesForUsers()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error fetching roles for users: $e');
     return {};
   }

   // AFTER
   } catch (e) {
     // ignore: avoid_print
     print('[UserBandRolesRepository] Error fetching roles for users: $e');
     rethrow;
   }
   ```

7. `hasRolesForBand()` catch block:

   ```dart
   // BEFORE
   } catch (e) {
     return false;
   }

   // AFTER
   } catch (e) {
     rethrow;
   }
   ```

**Exact change in `role_management_sheet.dart`:**

`_loadExistingPermissions()` — add try/catch:

```dart
// BEFORE
Future<void> _loadExistingPermissions() async {
  final repo = ref.read(membersRepositoryProvider);
  final existing = await repo.fetchContributorPermissions(
    bandMemberId: widget.member.memberId,
  );
  if (mounted && existing != null) {
    setState(() {
      _subPermissions = existing;
      _initialSubPermissions = existing;
    });
  }
}

// AFTER
Future<void> _loadExistingPermissions() async {
  final repo = ref.read(membersRepositoryProvider);
  try {
    final existing = await repo.fetchContributorPermissions(
      bandMemberId: widget.member.memberId,
    );
    if (mounted && existing != null) {
      setState(() {
        _subPermissions = existing;
        _initialSubPermissions = existing;
      });
    }
  } catch (e) {
    debugPrint('[RoleManagement] Failed to load contributor permissions: $e');
    // Permissions fail silently — sheet still opens with defaults
  }
}
```

---

### Task 3 — P3

| File                                         | Change                                                                                                                |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlists_screen.dart` | Remove `_lastLoadedBandId` and `_cachedState` fields; rewrite `build()`; remove `_cachedState = ...` lines throughout |

**Exact changes in `setlists_screen.dart`:**

Remove from `SetlistsNotifier`:

```dart
// DELETE these two field declarations:
String? _lastLoadedBandId;
SetlistsState? _cachedState;
```

Replace `build()`:

```dart
// BEFORE
@override
SetlistsState build() {
  // Watch the active band - when it changes, refetch setlists
  final bandId = ref.watch(activeBandIdProvider);

  if (bandId == null || bandId.isEmpty) {
    _lastLoadedBandId = null;
    _cachedState = null;
    return const SetlistsState(error: 'No band selected');
  }

  // Only trigger load if band actually changed
  if (bandId != _lastLoadedBandId) {
    _lastLoadedBandId = bandId;
    _cachedState = null;
    Future.microtask(() => loadSetlists());
    return const SetlistsState(isLoading: true);
  }

  // Band hasn't changed - return cached state if available
  // This handles provider invalidation without triggering a reload
  if (_cachedState != null) {
    return _cachedState!;
  }

  // Fallback: trigger a load (shouldn't normally reach here)
  Future.microtask(() => loadSetlists());
  return const SetlistsState(isLoading: true);
}

// AFTER
@override
SetlistsState build() {
  // Watch the active band — Riverpod re-executes build() only when
  // activeBandIdProvider changes, so a direct call is safe and correct.
  // This replaces the old _lastLoadedBandId + Future.microtask() pattern.
  final bandId = ref.watch(activeBandIdProvider);

  if (bandId == null || bandId.isEmpty) {
    return const SetlistsState(error: 'No band selected');
  }

  // Direct async call — no microtask deferral needed.
  // Band-id guard inside loadSetlists() discards stale results on rapid switching.
  loadSetlists();
  return const SetlistsState(isLoading: true);
}
```

Remove `_cachedState = ...` lines from four methods:

In `loadSetlists()` — remove three lines:

```dart
// DELETE: final loadingState = state.copyWith(isLoading: true, clearError: true);
// DELETE: state = loadingState;
// DELETE: _cachedState = loadingState;

// REPLACE with:
state = state.copyWith(isLoading: true, clearError: true);
```

And in each result/error path inside `loadSetlists()`, remove:

```dart
// DELETE: _cachedState = newState;
```

(Keep `state = newState` — only the `_cachedState` assignment is removed.)

In `deleteSetlist()` — remove:

```dart
// DELETE: _cachedState = newState;
```

In `reorderLocal()` — remove:

```dart
// DELETE: _cachedState = newState;
```

In `persistReorder()` — remove two lines:

```dart
// DELETE: _cachedState = revertState;
// (in the rollback path)
```

---

## 11. Files Off-Limits

| File                                                                | Reason                                                                       |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `supabase/functions/acousticbrainz_bpm/`                            | Tony must undeploy manually; do not delete source                            |
| `lib/features/setlists/setlist_repository.dart` beyond P1 deletions | P2/P3 constraints: no other changes to this file                             |
| `lib/features/members/members_controller.dart`                      | P2 scope: controller-level catch blocks are a separate concern, out of scope |
| Any Supabase migration files                                        | No schema changes required or permitted                                      |
| `lib/main.dart`                                                     | Init order must not change                                                   |
| Any file not listed in Section 10                                   | GUARDRAILS §7: modify only files in the Architect plan                       |

---

## 12. Call Site Analysis — Task 2 (P2)

Full trace of every external call site for each affected function:

### `removeMember()` (members_repository.dart)

| Call site                                               | File                         | Line | Exception handling?                                                                             |
| ------------------------------------------------------- | ---------------------------- | ---- | ----------------------------------------------------------------------------------------------- |
| `MembersController.removeMember()`                      | `members_controller.dart`    | 140  | Yes — `try/catch`, returns `false` on error. Caller of the controller (UI) shows error message. |
| `_SetlistsScreenState._removeMember()` (via controller) | `members_tab_content.dart`   | 121  | Yes — calls through controller which has try/catch.                                             |
| `RoleManagementSheet._removeMember()` (via controller)  | `role_management_sheet.dart` | 211  | Yes — outer try/catch in `_removeMember()`, shows error snackbar.                               |

**Assessment:** All call sites reach `removeMember()` through `MembersController.removeMember()` which already has `try/catch`. Repository rethrow propagates to the controller's existing handler. **No additional wrappers needed.**

### `fetchContributorPermissions()` (members_repository.dart)

| Call site                                        | File                         | Line | Exception handling?               |
| ------------------------------------------------ | ---------------------------- | ---- | --------------------------------- |
| `RoleManagementSheet._loadExistingPermissions()` | `role_management_sheet.dart` | 73   | ❌ No try/catch. Unguarded await. |

**Assessment:** **Requires a try/catch wrapper in `_loadExistingPermissions()`.** Failure to add this will cause an unhandled exception when the repository rethrows. The sheet should fail silently (open with default permissions) if loading fails — contributor permissions are optional for the sheet to function.

### `isCurrentUserAdmin()` (members_repository.dart)

| Call site                          | File                      | Line | Exception handling?                                     |
| ---------------------------------- | ------------------------- | ---- | ------------------------------------------------------- |
| `MembersController._loadMembers()` | `members_controller.dart` | 106  | Yes — inside outer `try/catch` that sets `state.error`. |

**Assessment:** Exception propagates to the existing controller catch block, which sets error state. **No additional wrapper needed.**

### `fetchRolesForBand()` (user_band_roles_repository.dart)

| Call site                          | File | Line | Exception handling? |
| ---------------------------------- | ---- | ---- | ------------------- |
| (none — no external callers found) | —    | —    | N/A                 |

**Assessment:** Function is defined but not called externally. Safe to rethrow with no wrapper changes needed.

### `fetchRolesForBands()` (user_band_roles_repository.dart)

| Call site                                     | File                     | Line | Exception handling?                                                                                                                   |
| --------------------------------------------- | ------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `MyProfileScreen._initializeMultiBandRoles()` | `my_profile_screen.dart` | 278  | Yes — `_initializeMultiBandRoles()` is called from inside `_loadProfileData()` which has an outer `try/catch` that sets `_loadError`. |

**Assessment:** Exception propagates to the existing outer catch block. **No additional wrapper needed.**

### `fetchRolesForUsers()` (user_band_roles_repository.dart)

| Call site                                    | File                      | Line | Exception handling?                                                                                                                          |
| -------------------------------------------- | ------------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `MembersRepository.fetchMembersAndInvites()` | `members_repository.dart` | 221  | Yes — explicit `try/catch` with comment: "If query fails, just use empty map (fall back to global roles)". Intentional graceful degradation. |

**Assessment:** The catch in `fetchMembersAndInvites()` is intentional — band-specific roles are optional, global roles are the fallback. Repository rethrow propagates to this existing handler. **No additional wrapper needed.** Behavior is unchanged.

### `hasRolesForBand()` (user_band_roles_repository.dart)

| Call site                          | File | Line | Exception handling? |
| ---------------------------------- | ---- | ---- | ------------------- |
| (none — no external callers found) | —    | —    | N/A                 |

**Assessment:** Function is defined but not called externally. Safe to rethrow with no wrapper changes needed.

---

## 13. System Impact Map

| System                                 | Task 1                         | Task 2                     | Task 3              |
| -------------------------------------- | ------------------------------ | -------------------------- | ------------------- |
| Setlists / Catalog                     | affected (BPM enrichment path) | unaffected                 | affected (notifier) |
| Members / RBAC                         | unaffected                     | affected                   | unaffected          |
| Profile                                | unaffected                     | affected (user_band_roles) | unaffected          |
| Gigs                                   | unaffected                     | unaffected                 | unaffected          |
| Rehearsals                             | unaffected                     | unaffected                 | unaffected          |
| Auth / Session                         | unaffected                     | unaffected                 | unaffected          |
| Routing                                | unaffected                     | unaffected                 | unaffected          |
| Notifications                          | unaffected                     | unaffected                 | unaffected          |
| Platform (iOS / Android / Web / macOS) | unaffected                     | unaffected                 | unaffected          |

---

## 14. Regression Risk

**Overall: LOW**

Rationale by task:

**P1 — LOW**
Deleting a dead code path. Strategy 1 (Spotify) is unaffected. No callers are
unaware of this method. The only behavioral change is ~200–500 ms less latency
when Spotify BPM fails. No UI change.

**P2 — LOW**
Replacing `return false/null/[]` with `rethrow` in seven catch blocks. All external
call sites were traced. One call site required a new try/catch (already specified
in Section 10). The remaining call sites already had try/catch handlers that will
now receive the real exception rather than a sentinel value. UI behavior at the
user level is unchanged — error messages were already shown for most paths, now
they are also logged with stack traces.

**P3 — LOW**
Simplifying `build()` to follow the reference implementation. The only behavioral
change is that provider invalidation (e.g., `ref.invalidate(setlistsProvider)`)
will now trigger a reload, where before it returned cached state. Invalidation is
called after successful mutations (delete, duplicate, reorder) via `loadSetlists()`
already, so this has no practical effect. The race condition risk (microtask
scheduling) is eliminated.

---

## 15. Engineer Task Breakdown

Tasks are independent. They may be executed in any order or in parallel (per
`OPERATING_MODEL.md` parallelization policy — different files, no shared state).

---

### Engineer Task E1 — Remove AcousticBrainz dead code (P1)

**File:** `lib/features/setlists/setlist_repository.dart`

1. In `_attemptBpmEnrichment()`, delete the Strategy 2 block:
   - The `// Strategy 2: Fallback to AcousticBrainz if Spotify failed` comment
   - The `if (bpm == null) { bpm = await _fetchAcousticBrainzBpm(...); ... }` block
     (~7 lines including the inner `if (bpm != null) { debugPrint(...); }`)

2. Delete the entire `_fetchAcousticBrainzBpm()` method (~33 lines including doc comment).

3. Update the section header comment from:
   `// HYBRID BPM ENRICHMENT (SPOTIFY → ACOUSTICBRAINZ FALLBACK)`
   to:
   `// BPM ENRICHMENT (SPOTIFY)`

4. Update the doc comment on `_attemptBpmEnrichment()`:
   - Remove: `/// 2. Fallback to AcousticBrainz`
   - Change: `/// 3. Give up if both fail` → `/// 2. Give up if Spotify fails`

**File:** `docs/reference/general/AI_DECISIONS.md`

5. Append the DECISION-002 entry exactly as specified in Section 10.

**Verification:** `flutter analyze` passes. `_fetchAcousticBrainzBpm` does not appear
anywhere in the codebase. The string `acousticbrainz_bpm` does not appear in any `.dart`
file.

---

### Engineer Task E2 — Fix silent error swallowing (P2)

**File:** `lib/features/members/members_repository.dart`

1. `removeMember()` catch block: replace `return false;` with `rethrow;`
2. `fetchContributorPermissions()` catch block: replace `return null;` with `rethrow;`
3. `isCurrentUserAdmin()` catch block: replace `return false;` with `rethrow;`
   (Also remove the `// ignore: avoid_print` + `print(...)` line if absent — add
   the print log before rethrowing to match the style of the other functions.)

**File:** `lib/features/profile/user_band_roles_repository.dart`

4. `fetchRolesForBand()` catch block: replace `return [];` with `rethrow;`
   Update the comment from `// On error, return empty list and don't cache` to
   `// On error, don't cache — rethrow so caller can handle`
5. `fetchRolesForBands()` catch block: replace `return {};` with `rethrow;`
6. `fetchRolesForUsers()` catch block: replace `return {};` with `rethrow;`
7. `hasRolesForBand()` catch block: replace `return false;` with `rethrow;`

**File:** `lib/features/members/widgets/role_management_sheet.dart`

8. Wrap the body of `_loadExistingPermissions()` in try/catch as specified in
   Section 10. The catch block must log the error with `debugPrint` and allow
   the sheet to continue with default permissions (silent failure).

**Verification:** `flutter analyze` passes. `grep` for `return false` / `return null` /
`return \[\]` / `return {}` in the affected catch blocks returns 0 matches. The
`_loadExistingPermissions()` method has a try/catch.

---

### Engineer Task E3 — Remove `_lastLoadedBandId` + microtask anti-pattern (P3)

**File:** `lib/features/setlists/setlists_screen.dart`

1. Delete the two field declarations at the top of `SetlistsNotifier`:
   - `String? _lastLoadedBandId;`
   - `SetlistsState? _cachedState;`

2. Replace the `build()` method body with the simplified version from Section 10.

3. In `loadSetlists()`:
   - Replace the three-line block:
     ```dart
     final loadingState = state.copyWith(isLoading: true, clearError: true);
     state = loadingState;
     _cachedState = loadingState;
     ```
     With the single line:
     ```dart
     state = state.copyWith(isLoading: true, clearError: true);
     ```
   - Remove every `_cachedState = newState;` and `_cachedState = loadingState;`
     line in all code paths (success, SetlistQueryError, NoBandSelectedError,
     generic catch).

4. In `deleteSetlist()`: remove `_cachedState = newState;`

5. In `reorderLocal()`: remove `_cachedState = newState;`

6. In `persistReorder()`: remove `_cachedState = revertState;`

**Verification:** `flutter analyze` passes. `grep` for `_lastLoadedBandId` and
`_cachedState` in `setlists_screen.dart` returns 0 matches. `grep` for
`Future.microtask` in `setlists_screen.dart` returns 0 matches.

---

## 16. Verification Plan

No database migrations are involved. All verification is Flutter-only.

### Tier 1 — Pre-deployment (no schema changes required)

Not applicable — these changes involve no database objects. There are no SQL tests.

### Tier 2 — Post-implementation (run after `flutter analyze` passes)

**T2-1: P1 — AcousticBrainz removal**

```
Manual: Trigger BPM enrichment for a song without a Spotify ID (create a new song
with no spotifyId). Confirm via debug logs:
  ✓ "[SetlistRepository] 🎵 Attempting BPM enrichment..."
  ✓ "[SetlistRepository] No BPM found for ..." (if Spotify also fails)
  ✗ ABSENT: any log containing "AcousticBrainz"

grep check: grep -r "acousticbrainz" lib/ → 0 results
grep check: grep -r "_fetchAcousticBrainzBpm" lib/ → 0 results
```

**T2-2: P1 — BPM enrichment with Spotify still works**

```
Manual: Create a song known to have a Spotify match. Confirm BPM is populated
after song creation. Confirm debug log shows Spotify strategy succeeding.
```

**T2-3: P2 — removeMember rethrows on error**

```
flutter analyze: 0 errors.
Code inspection: removeMember() catch block contains rethrow, not return false.
Manual: disconnect network, attempt to remove a member → UI shows error snackbar
(error propagates from repository → controller catch → returns false → UI shows msg).
```

**T2-4: P2 — fetchContributorPermissions — sheet opens on error**

```
Manual: open role management sheet for a contributor member while on poor/no network.
Confirm sheet opens successfully with default permissions (no crash, no red screen).
Confirm debug log shows "[RoleManagement] Failed to load contributor permissions: ..."
```

**T2-5: P2 — No regression in members loading**

```
Manual: switch bands, open Members tab, confirm members load correctly.
Manual: update a member's role, confirm success.
```

**T2-6: P2 — No regression in profile roles**

```
Manual: open My Profile, confirm band roles load correctly.
Manual: update a band role, save, confirm change persists.
```

**T2-7: P3 — Setlists load on band switch**

```
Manual: switch between two bands, confirm setlists update correctly for each band.
Confirm no flash or stale state visible during switch.
Confirm debug log shows "[SetlistsNotifier] Loaded X setlists from repository" after
each band switch.
```

**T2-8: P3 — Setlists load on app launch**

```
Manual: cold-start app, navigate to Setlists tab.
Confirm setlists load and display.
```

**T2-9: P3 — Delete, duplicate, reorder still work**

```
Manual: delete a setlist → confirm it disappears.
Manual: duplicate a setlist → confirm new copy appears.
Manual: reorder setlists → confirm order persists after navigating away and back.
```

**T2-10: flutter analyze**

```
flutter analyze
Expected: 0 errors
```

---

## 17. QA Regression Areas

QA must specifically verify:

1. **BPM enrichment (P1):** Songs with Spotify IDs receive BPM. Songs without do not crash. No "AcousticBrainz" log entries appear.
2. **Member removal (P2):** Removing a member via role management sheet succeeds and shows success snackbar. Failure shows error snackbar.
3. **Role management sheet (P2):** Sheet opens for contributor members without crash. Permissions load correctly. Changing role works.
4. **Members tab (P2):** Members load on band switch. Member count and names are correct.
5. **Profile roles (P2):** Band-specific roles display and save correctly in My Profile.
6. **Setlists tab (P3):** Setlists load on initial launch and on band switch. Delete/duplicate/reorder all function correctly. No loading flash on rapid band switch.

---

## 18. Rollout / Migration Strategy

Not applicable. No database migrations. No edge function deploy required (the
`acousticbrainz_bpm` function undeploy is Tony's responsibility via CLI, not part
of this Engineer task).

---

## 19. Out of Scope

The following are explicitly excluded from this plan:

- Deleting `supabase/functions/acousticbrainz_bpm/` from disk — Tony will undeploy manually
- Fixing `MembersController.removeMember()` controller-level catch block (returns false) — separate concern, not in P2 scope
- `members_tab_content.dart:_removeMember()` success/false handling — unchanged
- P4 (`.select()` narrowing for `activeBandProvider`) — separate feature
- P5 (batch setlist/song reorder queries) — separate feature
- Any Supabase schema, RLS, or migration changes
- Any changes to `SetlistsState` shape
- Any changes to `SetlistsScreen` widget or `_SetlistsScreenState`
- Any changes to `setlist_repository.dart` beyond the AcousticBrainz deletion
- Any opportunistic cleanup in files touched by this plan
