# Architect Plan — Song Card Key Badge + Tap-to-Edit

## Feature Slug

`feature/song-card-key-badge-tap-edit`

## Problem Summary

Song cards in Catalog and regular setlists currently display an edit icon/button that opens the song edit drawer, but they do not surface the song's musical key at a glance. Tony wants the key visible on the card (when entered) and wants the edit icon removed in favor of making the whole card tappable to open edit view.

**User Impact:**

- Musicians cannot see song keys on cards during rehearsal planning
- Edit icon is redundant (full-card tap already opens edit view)
- Key is editable in song details but invisible on the card

## Root Cause

**Confidence: HIGH** (direct observation in code)

**Primary:** Musical key badge UI component does not exist in song card widgets.

**Secondary:** Edit icon present in `ReorderableSongCard` metrics row (lines 354-367) is redundant — full-card tap already opens the same edit view via `onTap` callback.

**Evidence:**

1. `musicalKey` field exists in Song and SetlistSong models (`lib/features/setlists/models/song.dart` line 20, `setlist_song.dart` line 39)
2. `musical_key` column exists in database (migration `20260630000000_add_musical_key_to_songs.sql`)
3. Read queries include `musical_key` (`lib/features/setlists/setlist_repository.dart` line 622)
4. Edit infrastructure exists: `showSongDetailsBottomSheet` + `updateSongMusicalKey` (`setlist_detail_screen.dart` lines 1120, 1221)
5. Full-card tap already wired to `_handleSongTap` (line 2260)
6. Musical key badge is NOT rendered in either `ReorderableSongCard` or `SongCard` widgets

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — verified songs table schema
- `docs/reference/architecture/architecture.md` — setlist architecture, file size warnings
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — project context, song card UX
- `lib/features/setlists/models/song.dart` — Song model structure
- `lib/features/setlists/models/setlist_song.dart` — SetlistSong model structure
- `lib/features/setlists/widgets/reorderable_song_card.dart` — current card layout
- `lib/features/setlists/widgets/song_card.dart` — Catalog card layout
- `lib/features/setlists/setlist_detail_screen.dart` — edit flow wiring
- `lib/features/setlists/tuning/tuning_helpers.dart` — tuning badge color system
- `lib/app/theme/design_tokens.dart` — design tokens, AppColors

## Existing System Analysis

### Data Layer (Confirmed Working)

- **Column:** `songs.musical_key TEXT` (nullable)
- **Model field:** `Song.musicalKey` and `SetlistSong.musicalKey`
- **Read:** Included in all song queries (`setlist_repository.dart` line 622)
- **Write:** `updateSongMusicalKey` RPC exists and is called from edit bottom sheet
- **Scope:** Global property (stored in `songs` table, NOT per-setlist override)

### UI Layer (Current State)

**ReorderableSongCard** (used in setlist detail with drag-and-drop):

- **Top row:** Title/Artist (left) + Lyrics icon (right, conditional)
- **Metrics row:** `[BPM] ←--equal space--→ [Duration] ←--equal space--→ [Edit Icon] ←--equal space--→ [Tuning Badge]`
- **Edit icon:** Lines 354-367, only shown when `onEdit != null`
- **Full-card tap:** Already implemented via `onTap` callback (line 148)
- **Drag handle:** Isolated to left 36px via `ReorderableDragStartListener` (lines 177-199)

**SongCard** (Catalog uses same card in non-drag list mode):

- **Top row:** Title/Artist (left) + Lyrics icon (right, conditional)
- **Metrics row:** `[BPM (70px)] [gutter] [Duration (60px)] [spacer] [Tuning Badge (right-aligned)]`
- **NO edit icon** (Catalog has no separate edit icon — consistent with regular setlists after this change)
- **Full-card tap:** Already implemented via `onTap` callback (line 99), opens editable bottom sheet when user has edit permissions

**Edit Flow:**

- Both `onTap` and `onEdit` callbacks call `_handleSongTap(song)` in `setlist_detail_screen.dart` (line 1119)
- Opens `showSongDetailsBottomSheet` which already supports editing musical key (line 1120)
- Save logic exists: `notifier.updateSongMusicalKey(song.id, result.musicalKey)` (line 1221)

### Drag-and-Drop Compatibility

- Drag is initiated ONLY via `ReorderableDragStartListener` on drag handle (left 36px area)
- Content area wrapped in `Listener` that absorbs pointer events (line 225)
- Full-card tap gestures are isolated from drag gestures — no conflict

## Proposed Solution

### Minimal Changes

1. **Add key badge to ReorderableSongCard:**
   - Position between Duration and Tuning Badge in metrics row
   - Only render when `song.musicalKey` is not null
   - Match tuning badge visual style (pill shape, filled background, no border)
   - Use Green color `AppColors.success` / `#22C55E` (distinct from all tuning colors)
   - Display format: just the key value (e.g., "C", "Am", "G#", "Dbm")

2. **Remove edit icon from ReorderableSongCard:**
   - Delete lines 354-367 (IconButton with edit icon)
   - Metrics row becomes: `[BPM] ←--equal space--→ [Duration] ←--equal space--→ [Key Badge] ←--equal space--→ [Tuning Badge]`
   - Layout remains `MainAxisAlignment.spaceBetween` for equidistant spacing

3. **Add key badge to SongCard (Catalog variant):**
   - Position between Duration and Tuning Badge
   - Same visual style and color as ReorderableSongCard
   - Layout: `[BPM (70px)] [gutter] [Duration (60px)] [gutter] [Key Badge] [spacer] [Tuning Badge (right-aligned)]`

4. **Full-card tap behavior (no changes needed):**
   - Already wired via `onTap` in both widgets
   - Lyrics icon preserves its own tap handler (GestureDetector, lines 270-282 in ReorderableSongCard)
   - Tuning badge preserves its own tap handler (GestureDetector, lines 442-452 in ReorderableSongCard)

### Key Badge Implementation Details

**Visual Design:**

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: AppColors.success, // Green #22C55E (green-500)
    borderRadius: BorderRadius.circular(100), // Pill shape
  ),
  child: Text(
    song.musicalKey!, // e.g., "C", "Am", "F#m"
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF1F1F1F), // Dark text for light background
      height: 1,
    ),
  ),
)
```

**Conditional Rendering:**

```dart
// Only show key badge when musicalKey is not null
if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
  _buildKeyBadge(),
```

**Color Rationale:**

**Tuning badge colors verified in `lib/features/setlists/tuning/tuning_helpers.dart` (lines 222-305):**
- Blue #2563EB (Standard), #1E40AF (D Standard)
- Fuchsia #C026D3 (Half-Step)
- Lime #65A30D (Drop D)
- Orange #EA580C (Full-Step)
- Cyan #06B6D4 (Drop C), #0891B2 (C Standard)
- Purple #581C87 (Drop Db), #312E81 (B Standard)
- Dark Green #14532D (Drop B), #065F46 (Drop A)
- Teal #0D9488 (A Standard)
- Rose shades #F43F5E, #E11D48, #BE123C, #9F1239, #881337 (Open G/D/E/A/C)
- Pink #DB2777 (DADGAD)
- **Amber #F59E0B (Nashville) ← CONFLICT if used for key badge**
- Slate #64748B (Custom)

**Key badge color: Green #22C55E (`AppColors.success` / green-500)**

**Rationale:**
- Distinct from ALL tuning badge colors listed above
- Available in `AppColors` design tokens (no inline constant needed)
- Semantically appropriate — keys are valuable information, green conveys positive/helpful
- Good contrast for dark text (readability confirmed)

## Database Impact

**Not applicable** — no schema, RLS, RPC, or migration changes required.

- `musical_key` column already exists (migration `20260630000000_add_musical_key_to_songs.sql`)
- Read queries already include `musical_key` (verified in `setlist_repository.dart` line 622)
- Update RPC already supports `musical_key` (migration `20260630000001_add_musical_key_to_update_song_rpc.sql`)

## Flutter Architecture Changes

**State:** No changes — musical key already flows through SetlistSong model and state providers.

**Widgets:**

- `ReorderableSongCard`: Add key badge, remove edit icon, update metrics row layout
- `SongCard`: Add key badge, update metrics row layout

**Repositories:** No changes — `updateSongMusicalKey` already exists and works.

## Files to Create

None.

## Files to Modify

| File                                                       | Changes                                                                                                                                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | 1. Add `_buildKeyBadge()` helper method (modeled after `_buildTuningBadge()`, lines 410-453)<br>2. Remove edit icon block (delete lines 354-367)<br>3. Update `_buildMetricsRow()` to include key badge conditionally before tuning badge<br>4. Metrics row elements: `[BPM]` `[Duration]` `[Key Badge if not null]` `[Tuning Badge]` with `MainAxisAlignment.spaceBetween` |
| `lib/features/setlists/widgets/song_card.dart`             | 1. Add `_buildKeyBadge()` helper method (modeled after `_buildTuningBadge()`, lines 269-329)<br>2. Update `_buildMetricsRow()` to include key badge conditionally before tuning badge<br>3. Add gutter spacing before key badge                                                                                                                                             |

## Files Off-Limits

| File                                               | Reason                                                                             |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `lib/main.dart`                                    | Init order must not change                                                         |
| `lib/features/setlists/setlist_repository.dart`    | Already reads `musical_key`; no changes needed (4,027 lines — avoid adding bulk)   |
| `lib/features/setlists/setlist_detail_screen.dart` | Already wires `onTap` to edit; no changes needed (2,788 lines — avoid adding bulk) |
| `lib/features/setlists/models/song.dart`           | Model already has `musicalKey` field                                               |
| `lib/features/setlists/models/setlist_song.dart`   | Model already has `musicalKey` field                                               |
| `lib/app/theme/design_tokens.dart`                 | No new global colors — use AppColors.success token                                 |
| `supabase/migrations/*`                            | No database changes required                                                       |

## System Impact Map

| System                                 | Impact                                              |
| -------------------------------------- | --------------------------------------------------- |
| Gigs                                   | unaffected                                          |
| Rehearsals                             | unaffected                                          |
| Setlists / Catalog                     | **affected** — song card UI modified                |
| Members / RBAC                         | unaffected                                          |
| Auth / Session                         | unaffected                                          |
| Routing                                | unaffected                                          |
| Notifications                          | unaffected                                          |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms use same UI components |

## Regression Risk

**Level: LOW**

**Rationale:**

1. **Only UI changes** — no database, RPC, state management, or business logic modifications
2. **Isolated scope** — changes limited to two widget files (ReorderableSongCard, SongCard)
3. **Full-card tap already works** — just removing redundant edit icon, not changing tap behavior
4. **Drag-and-drop isolated** — drag gestures handled by separate listener on drag handle only
5. **Preserved behaviors:**
   - Lyrics icon tap handler unchanged
   - Tuning badge tap handler unchanged (opens tuning picker)
   - Edit bottom sheet flow unchanged
6. **Musical key infrastructure already tested** — edit and save logic deployed and working
7. **No cross-feature impact** — only setlists/catalog affected

**Minor risks:**

- Layout shift if key badge width exceeds available space on narrow screens → mitigated by using `MainAxisAlignment.spaceBetween` which adjusts spacing
- Visual confusion if key badge color too similar to existing badges → mitigated by using distinct Green color (AppColors.success), verified not used by any tuning badge

## Engineer Task Breakdown

Execute in strict order. Each task must complete successfully before proceeding to next.

1. **Add key badge to ReorderableSongCard:**
   - Read current `_buildTuningBadge()` method (lines 410-453) as reference
   - Add `_buildKeyBadge()` helper method below `_buildDurationValue()`
   - Badge should:
     - Use Green color `AppColors.success` for background
     - Use dark text `const Color(0xFF1F1F1F)` for contrast
     - Match tuning badge dimensions (12px horizontal padding, 6px vertical, pill shape)
     - Display `widget.song.musicalKey!` text value

2. **Remove edit icon from ReorderableSongCard:**
   - Delete lines 354-367 (entire `if (widget.onEdit != null)` block with IconButton)
   - Do NOT delete any other code — only the edit icon block

3. **Update ReorderableSongCard metrics row layout:**
   - Locate `_buildMetricsRow()` method (lines 329-376)
   - In the `children` list (lines 339-373):
     - Keep BPM (line 343)
     - Keep Duration (line 348)
     - Replace Edit Icon block (lines 354-367) with conditional key badge:
       ```dart
       // Key badge - shown only when musical key is set
       if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
         _buildKeyBadge(),
       ```
     - Keep Tuning Badge (line 372)
   - Verify `MainAxisAlignment.spaceBetween` remains (line 337)

4. **Add key badge to SongCard (Catalog variant):**
   - Read current `_buildTuningBadge()` method (lines 269-329) as reference
   - Add `_buildKeyBadge()` helper method below `_buildDurationValue()`
   - Same visual specs as ReorderableSongCard (Green/AppColors.success, dark text, pill shape)

5. **Update SongCard metrics row layout:**
   - Locate `_buildMetricsRow()` method (lines 208-244)
   - After Duration column (lines 225-233), add:

     ```dart
     // Gutter before key badge (only if key exists)
     if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
       const SizedBox(width: SongCardLayout.metricsGutter),

     // Key badge column
     if (widget.song.musicalKey != null && widget.song.musicalKey!.isNotEmpty)
       _buildKeyBadge(),
     ```

   - Keep Expanded + Tuning Badge block unchanged (lines 236-241)

6. **Verify changes compile:**
   - Run `flutter analyze` — must return 0 errors
   - Fix any type errors or missing imports
   - Do NOT proceed if analyze fails

7. **Manual verification (dev environment):**
   - Run app on one platform (macOS or web recommended)
   - Navigate to a setlist with songs that have `musicalKey` set
   - Verify key badge appears to the left of tuning badge
   - Verify key badge does NOT appear for songs without musical key
   - Tap full card area (not lyrics/tuning) — song edit bottom sheet should open
   - Verify edit icon is gone
   - Verify drag-and-drop still works (drag via grip icon on left)
   - Navigate to Catalog — verify key badge appears there too

## Verification Plan

### Pre-Implementation Verification

**Verify current state before any code changes:**

1. Confirm `musical_key` column exists in database:

   ```sql
   SELECT column_name, data_type
   FROM information_schema.columns
   WHERE table_name = 'songs' AND column_name = 'musical_key';
   ```

   Expected: Returns 1 row with `data_type = 'text'`

2. Confirm queries include musical_key:
   - Open `lib/features/setlists/setlist_repository.dart`
   - Search for line 622: should read `musical_key` in select list

3. Confirm models have musicalKey field:
   - Open `lib/features/setlists/models/song.dart` line 20
   - Open `lib/features/setlists/models/setlist_song.dart` line 39
   - Both should have `final String? musicalKey;`

### Post-Implementation Verification

**After Engineer completes implementation:**

1. **Static analysis:**

   ```bash
   flutter analyze
   ```

   Expected: 0 errors, 0 warnings

2. **Visual verification (dev environment):**
   - Run on macOS or web: `flutter run -d macos` or `flutter run -d chrome`
   - **Test Case 1 — Key badge appears:**
     - Navigate to a setlist
     - Find a song with musical key set (if none exist, edit one to add key)
     - Verify key badge displays to the left of tuning badge
     - Verify Green color `#22C55E` (AppColors.success) background
     - Verify key text is readable (dark text on light background)
   - **Test Case 2 — No key badge when null:**
     - Find a song without musical key
     - Verify NO key badge appears (no empty placeholder)
   - **Test Case 3 — Edit icon removed:**
     - Verify no edit icon appears in metrics row
     - Metrics should show: BPM | Duration | Key (if set) | Tuning
   - **Test Case 4 — Full-card tap opens edit:**
     - Tap anywhere on the song card (not lyrics icon, not tuning badge)
     - Verify song details bottom sheet opens
     - Verify it's editable (not read-only)
   - **Test Case 5 — Lyrics/tuning taps preserved:**
     - Tap lyrics icon (if song has lyrics) — verify lyrics view opens
     - Tap tuning badge — verify tuning picker opens
   - **Test Case 6 — Drag-and-drop still works:**
     - In a non-Catalog setlist (where drag is enabled)
     - Drag a song by the grip icon (left edge)
     - Verify reorder works
     - Verify tapping card (not grip) does NOT initiate drag
   - **Test Case 7 — Catalog view:**
     - Navigate to Catalog
     - Verify key badge appears for songs with keys
     - Verify layout matches setlist view

3. **Cross-platform spot check:**
   - Test on iOS simulator or Android emulator
   - Verify key badge renders correctly
   - Verify tap-to-edit works
   - No need for exhaustive testing — Flutter renders identically across platforms

## QA Regression Areas

QA must specifically test these areas after deployment:

1. **Song card display:**
   - Key badge visibility (when key is set vs. not set)
   - Key badge color (Green #22C55E, distinct from tuning badges including Nashville amber)
   - Badge alignment and spacing
   - Text readability

2. **Edit functionality:**
   - Full-card tap opens song edit bottom sheet
   - Edit bottom sheet is editable (not read-only) when user has edit permissions
   - Edit icon is absent (removed)
   - Musical key can still be edited and saved via bottom sheet

3. **Preserved tap behaviors:**
   - Lyrics icon tap opens lyrics view (when song has lyrics)
   - Tuning badge tap opens tuning picker (in editable setlists)
   - Tapping empty space on card opens edit (not just text areas)

4. **Drag-and-drop:**
   - Reordering works via drag handle (grip icon on left)
   - Full-card tap does NOT initiate drag
   - Dragged card shows elevation and scale animation

5. **Layout consistency:**
   - Key badge does not break card layout on narrow screens
   - Spacing between badges is uniform
   - Catalog view matches setlist view

6. **Catalog and Setlist consistency:**
   - Key badge appears in both Catalog and regular setlists
   - Tap behavior identical: full-card tap opens editable bottom sheet (when user has edit permissions)
   - Visual appearance identical across both contexts
   - Verify Catalog delete semantics still work (delete from Catalog = delete from all setlists)

## Rollout / Migration Strategy

**Not applicable** — this is a pure UI change with no data migration required.

**Deployment:**

1. Merge PR to main
2. Deploy web via `./tools/deploy_web.sh`
3. No backend changes required
4. No database migration required

**Rollback:**
If key badge causes layout issues or confusion, simply revert the PR. No data is affected.

## Out of Scope

Explicitly NOT included in this feature:

1. **Key badge tap interaction** — key badge is read-only display, not editable inline
2. **Key color coding** — all key badges use the same Green color regardless of key value
3. **Key signature display** — shows just the key (e.g., "C"), not full signature notation
4. **Per-setlist key override** — musical key is global (stored in songs table), not per-setlist
5. **Key detection from audio** — key must be manually entered via edit bottom sheet
6. **Key transposition** — no automatic key changes or capo offset calculations
7. **SongCard edit icon removal** — Catalog variant already has no edit icon
8. **Drag handle visual changes** — grip icon appearance unchanged
9. **Bottom sheet UI changes** — song edit view already supports key editing
