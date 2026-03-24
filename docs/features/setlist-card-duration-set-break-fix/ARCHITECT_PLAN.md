# ARCHITECT PLAN — Setlist Card Duration Excludes Set Break Duration

## Feature Slug

`bug/setlist-card-duration-set-break-fix`

---

## 1. Problem Summary

The total duration shown on setlist cards in the list view excludes set break
(and pause) durations. The setlist detail screen header correctly includes them.
This causes the two surfaces to display different values for the same setlist —
e.g. "1h 44m" on the card vs "1h 59m" in the detail header — with the
difference exactly equal to the total set break duration.

---

## 2. Existing System Analysis

### Card path (INCORRECT — list view)

1. `SetlistRepository._fetchSetlistsForBandInternal()` queries the `setlists`
   table and reads the stored `total_duration` column.
2. `total_duration` is maintained by a PostgreSQL trigger
   `update_setlist_duration()`, which fires on INSERT/UPDATE/DELETE of
   `setlist_songs` rows.
3. The trigger computes:
   ```sql
   SELECT COALESCE(SUM(duration_seconds), 0)
   FROM public.setlist_songs
   WHERE setlist_id = ...
   ```
4. For song rows, `setlist_songs.duration_seconds` is populated → included.
5. For set break / pause rows, `setlist_songs.duration_seconds` is **NULL**
   (the actual duration lives in `setlist_special_items.duration_minutes` /
   `duration_seconds`) → contributes **0** to the sum.
6. `Setlist.fromSupabase()` reads this incomplete `total_duration` →
   `Setlist.formattedDuration` → displayed on the card.

### Detail header path (CORRECT — reference implementation)

1. `SetlistDetailController` loads the full `items` list (unified
   `SetlistItem` objects that wrap either `SetlistSong` or `SpecialItem`).
2. `SetlistDetailState.totalDuration` iterates all items:
   ```dart
   items.fold(Duration.zero, (sum, item) {
     if (item.contributesToRuntime) {
       return sum + Duration(seconds: item.durationSeconds);
     }
     return sum;
   });
   ```
3. For set breaks: `SetlistItem.durationSeconds` →
   `SpecialItem.totalDurationSeconds` → `durationMinutes * 60` → **included**.
4. `state.formattedDuration` → displayed in the detail header
   (`setlist_detail_screen.dart` line 1656).

### Query structure (list fetch)

The list query currently selects:

```
id, name, band_id, total_duration, is_catalog, position,
created_at, updated_at, setlist_songs(item_type)
```

It fetches the nested `setlist_songs(item_type)` to compute `songCount`,
`pauseCount`, and `setBreakCount` client-side (lines ~338–353 of
`setlist_repository.dart`). The counts are correct. Only the duration is wrong
because it reads the stored `total_duration` instead of computing it from items.

---

## 3. Root Cause

**Root cause:** The `setlist_songs.duration_seconds` column is NULL for special
item rows (set breaks and pauses). The `add_special_item_to_setlist` RPC
(migration 085) does not populate this column when inserting special items. The
trigger `update_setlist_duration()` sums only `setlist_songs.duration_seconds`,
so special item durations are excluded from the stored `setlists.total_duration`.

**Confidence: HIGH** — confirmed by direct code inspection:

- Trigger: `lib/supabase/migrations/007_update_setlists_schema_fixed.sql` L155
- Insert RPC: `lib/supabase/migrations/085_add_special_item_to_setlist_rpc.sql` L40–47
  (inserts with `song_id = NULL`, no `duration_seconds`)
- `SpecialItem.contributesToRuntime` confirms set breaks always contribute

---

## 4. Proposed Solution

**Client-side fix in `setlist_repository.dart`**. Compute total duration from
actual item data during list fetch, instead of relying on the stored (incomplete)
`total_duration` column.

### Changes:

1. **Expand the nested select** in all 4 query variants within
   `_fetchSetlistsForBandInternal()`:

   Before:

   ```
   setlist_songs(item_type)
   ```

   After:

   ```
   setlist_songs(item_type, duration_seconds, setlist_special_items(duration_minutes, duration_seconds))
   ```

   This joins `setlist_special_items` via the existing FK
   (`setlist_songs.special_item_id` → `setlist_special_items.id`).
   For song rows, `setlist_special_items(...)` returns null (no FK value).
   For special item rows, it returns the template with duration fields.

2. **Compute total duration in the existing parsing loop** (alongside the
   existing count logic):

   ```dart
   int totalDurationSeconds = 0;

   for (final item in items) {
     final itemType = (item is Map) ? item['item_type'] : null;
     switch (itemType) {
       case 'set_break':
         setBreakCount++;
         final special = (item is Map) ? item['setlist_special_items'] : null;
         if (special is Map) {
           totalDurationSeconds += ((special['duration_minutes'] as int? ?? 0) * 60);
         }
         break;
       case 'pause':
         pauseCount++;
         final special = (item is Map) ? item['setlist_special_items'] : null;
         if (special is Map) {
           totalDurationSeconds += (special['duration_seconds'] as int? ?? 0);
         }
         break;
       default:
         songCount++;
         totalDurationSeconds += ((item is Map) ? (item['duration_seconds'] as int? ?? 0) : 0);
         break;
     }
   }
   ```

3. **Override `total_duration` in `flatJson`** before calling
   `Setlist.fromSupabase()`:

   ```dart
   flatJson['total_duration'] = totalDurationSeconds;
   ```

### Why client-side instead of fixing the trigger?

- The feature input states "No database or schema changes are expected."
- A client-side fix ships immediately with a Flutter deploy — no database
  migration coordination needed.
- The stored `total_duration` column becomes effectively superseded for the
  list view, but no other system depends on its accuracy.
- A future improvement (out of scope) could fix the trigger for full
  consistency.

---

## 5. Database Impact

**Not applicable.** No migrations, no schema changes, no trigger modifications,
no RPC changes, no data backfills.

---

## 6. RLS / RPC Changes

**None.** The nested select `setlist_special_items(...)` is resolved through the
existing FK relationship and governed by the existing RLS policies on
`setlist_special_items` (which already allow band members to read).

---

## 7. Flutter Architecture Changes

No new controllers, providers, repositories, or state management. No widget
changes. The fix is entirely within the data-fetching layer of the existing
repository method.

---

## 8. Exact Files to Create

**None.**

---

## 9. Exact Files to Modify

| File                                            | What Changes                                                                                                                                                                                                                                                                                       |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_repository.dart` | 1) Expand nested select in 4 query variants to include `duration_seconds` and nested `setlist_special_items(duration_minutes, duration_seconds)`. 2) Add duration computation in existing parsing loop (~lines 338–353). 3) Override `flatJson['total_duration']` with computed value (~line 359). |

---

## 10. Risks / Edge Cases

| Risk                                                                               | Mitigation                                                                                                                       |
| ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| PostgREST nested join returns unexpected format                                    | Use defensive null/type checks (`as int? ?? 0`, `is Map` guards). Same pattern already used in the parsing loop.                 |
| Song `duration_seconds` on `setlist_songs` may be stale if song metadata is edited | Pre-existing issue, not introduced by this fix. The stored `total_duration` column has the same staleness. Out of scope.         |
| Catalog setlists have no special items                                             | No impact — `totalDurationSeconds` for Catalog setlists equals sum of song durations, which matches the stored `total_duration`. |
| Empty setlists (0 items)                                                           | `totalDurationSeconds` stays 0. Same as current behavior.                                                                        |
| `_generateShareText()` in detail screen also excludes set breaks                   | Pre-existing issue in a different code path. Out of scope for this bug. Noted for future fix.                                    |
| Performance: nested join adds data to list query                                   | Negligible — only adds 2 int fields per special item row. Typical setlist has 0–3 special items.                                 |

---

## 11. Verification Plan

### Engineer validation commands:

```bash
flutter analyze   # Must pass with 0 errors
flutter test      # Must pass (existing tests must not break)
```

### Manual verification:

1. Create a setlist with songs and at least one set break (e.g. 15-minute break).
2. Return to setlist list view.
3. Verify the card duration includes the set break time.
4. Open the setlist detail — verify the header duration matches the card.
5. Verify a setlist with NO set breaks still shows the correct song-only duration.
6. Verify the Catalog card shows correct duration.
7. Add a set break to a setlist, return to list — verify card updates.
8. Remove a set break from a setlist, return to list — verify card updates.

---

## 12. Engineer Task Breakdown

| #   | Task                                                                                   | File                      | Lines (approx) |
| --- | -------------------------------------------------------------------------------------- | ------------------------- | -------------- |
| 1   | Expand nested select in primary query variant (with `is_catalog` + `position`)         | `setlist_repository.dart` | ~252           |
| 2   | Expand nested select in fallback query variant (without `position`)                    | `setlist_repository.dart` | ~271           |
| 3   | Expand nested select in fallback query variant (without `position` and `is_catalog`)   | `setlist_repository.dart` | ~286           |
| 4   | Expand nested select in fallback query variant (without `is_catalog`, with `position`) | `setlist_repository.dart` | ~305           |
| 5   | Add `totalDurationSeconds` variable and duration computation to the parsing loop       | `setlist_repository.dart` | ~338–353       |
| 6   | Override `flatJson['total_duration']` with computed value                              | `setlist_repository.dart` | ~359           |
| 7   | Run `flutter analyze` — must pass with 0 errors                                        | —                         | —              |
| 8   | Run `flutter test` — must pass                                                         | —                         | —              |
| 9   | Manual verification per Verification Plan above                                        | —                         | —              |

---

## 13. Rollout / Migration Strategy

**No migration required.** This is a client-side computation fix.

Deploy via standard web build + Vercel deploy:

```bash
flutter build web --release
cd build/web && vercel --prod
```

Native builds (iOS, Android, macOS) will pick up the fix on next release cycle.

No data backfill needed. No database coordination needed.

---

## 14. Out of Scope

- Fixing the PostgreSQL trigger `update_setlist_duration()` to include special
  item durations (future improvement — would require a migration).
- Fixing `_generateShareText()` in the detail screen to include set break
  durations (separate bug, different code path).
- Addressing potential staleness of `setlist_songs.duration_seconds` when song
  metadata is edited (pre-existing issue).
- Fixing the stored `total_duration` column via backfill (not needed since
  client computes correctly).

---

## 15. Widget Contracts (Public API)

No widget API changes. The `SetlistCard` widget receives a `Setlist` object via
constructor. The `Setlist.formattedDuration` getter is unchanged. The fix is
upstream in how `totalDuration` is computed before constructing the `Setlist`
model.

---

## 16. Data Flow Architecture

### Before (BROKEN):

```
PostgreSQL trigger
  └─ SUM(setlist_songs.duration_seconds)  ← NULL for special items
      └─ stored in setlists.total_duration  ← excludes set breaks
          └─ Setlist.fromSupabase() reads total_duration
              └─ Setlist.formattedDuration
                  └─ SetlistCard displays "1h 44m"  ← WRONG
```

### After (FIXED):

```
Supabase query (expanded nested select)
  └─ setlist_songs(item_type, duration_seconds,
  │     setlist_special_items(duration_minutes, duration_seconds))
  └─ Repository parsing loop computes totalDurationSeconds:
  │     songs: item['duration_seconds']
  │     set_break: special['duration_minutes'] * 60
  │     pause: special['duration_seconds']
  └─ flatJson['total_duration'] = totalDurationSeconds  ← CORRECT
      └─ Setlist.fromSupabase() reads total_duration
          └─ Setlist.formattedDuration
              └─ SetlistCard displays "1h 59m"  ← CORRECT
```

---

## 17. Exact Code Locations

### Queries to modify (4 variants):

| Variant                                 | File                      | Approximate Line | Current Select             |
| --------------------------------------- | ------------------------- | ---------------- | -------------------------- |
| Primary (is_catalog + position)         | `setlist_repository.dart` | ~247–253         | `setlist_songs(item_type)` |
| Fallback (no position)                  | `setlist_repository.dart` | ~266–273         | `setlist_songs(item_type)` |
| Fallback (no position, no is_catalog)   | `setlist_repository.dart` | ~281–287         | `setlist_songs(item_type)` |
| Fallback (no is_catalog, with position) | `setlist_repository.dart` | ~300–307         | `setlist_songs(item_type)` |

### Parsing loop to modify:

| Location              | File                      | Approximate Lines | What to Add                                                           |
| --------------------- | ------------------------- | ----------------- | --------------------------------------------------------------------- |
| Item counting loop    | `setlist_repository.dart` | ~338–353          | Add `totalDurationSeconds` accumulator alongside existing count logic |
| flatJson construction | `setlist_repository.dart` | ~359              | Add `flatJson['total_duration'] = totalDurationSeconds;`              |

### Reference implementation (do not modify — for comparison only):

| Component                          | File                             | Line  |
| ---------------------------------- | -------------------------------- | ----- |
| `SetlistDetailState.totalDuration` | `setlist_detail_controller.dart` | ~166  |
| Header display                     | `setlist_detail_screen.dart`     | ~1656 |
| `SpecialItem.totalDurationSeconds` | `models/special_item.dart`       | ~38   |
| `SpecialItem.contributesToRuntime` | `models/special_item.dart`       | ~47   |
| `SetlistItem.durationSeconds`      | `models/setlist_item.dart`       | ~43   |
