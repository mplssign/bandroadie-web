# ARCHITECT PLAN — Song Enrichment Force Ask

## Feature Slug

`feature/song-enrichment-force-ask`

## Problem Summary

Settings currently exposes two enrichment-related menu items: "Song Enrichment" (which opens a screen allowing bands to choose Ask/Auto/Off for new song behavior) and "Song tempo & key data via GetSongBPM.com" (an attribution link). Product requirement: remove both menu items and lock enrichment behavior so it always follows the Ask path (user reviews BPM/Duration/Key before saving), making Auto and Off unreachable for all bands, including those with stored DB values of `'auto'` or `'off'`.

## Root Cause

**Confidence:** `HIGH` — confirmed in code through direct observation.

This is not a bug; it is a product decision to simplify enrichment UX. The current implementation allows three behaviors (Ask/Auto/Off) via a settings screen and corresponding DB schema. The requirement is to lock to Ask-only by removing the settings UI and hardcoding the behavior in all consumers, without migrating the DB schema (stored `'auto'`/`'off'` values become unreachable but harmless once all consumers hardcode Ask).

## Reference Docs Consulted

None — no enrichment or song reference documentation exists in `docs/reference/`.

## Existing System Analysis

**Current architecture:**

1. **Settings entry point** (`lib/features/settings/settings_screen.dart` lines 68-79):
   - Menu item "Song Enrichment" → navigates to `EnrichmentSettingsScreen`
   - Menu item "Song tempo & key data via GetSongBPM.com" → opens `https://getsongbpm.com`

2. **EnrichmentSettingsScreen** (`lib/features/songs/enrichment_settings_screen.dart`):
   - Displays radio options: Ask / Auto / Off
   - Calls `enrichmentSettingsProvider.notifier.updateSettings()` on change
   - Existing Song Behavior already locked to Fill-Missing-Only (post revert, out of scope)

3. **Controller/Repository** (`enrichment_settings_controller.dart`, `enrichment_settings_repository.dart`):
   - `enrichmentSettingsProvider` (AsyncNotifier) fetches settings via `get_or_create_enrichment_settings` RPC
   - Watches `activeBandProvider` to auto-refresh on band switch
   - `updateSettings()` calls `update_enrichment_settings` RPC with validated enum strings

4. **Three consumers** (all read `enrichmentSettingsProvider` and branch on `newSongBehavior`):
   - **bulk_entry_screen.dart** (line 374):
     ```dart
     final newSongBehavior = settings?.newSongBehavior ?? NewSongBehavior.off;
     ```
     Branches: `ask` → show confirm dialog, `auto` → enrich in background, `off` → skip enrichment
   - **original_song_screen.dart** (line 195):
     ```dart
     final newSongBehavior = settings?.newSongBehavior ?? NewSongBehavior.off;
     ```
     Same branching as bulk_entry
   - **song_lookup_overlay.dart** (line 293):
     ```dart
     final newSongBehavior = settingsAsync.whenOrNull(
           data: (settings) => settings.newSongBehavior,
         ) ??
         NewSongBehavior.ask; // fallback to ask if loading/error
     ```
     Same branching as bulk_entry but fallback differs (inconsistency, becomes moot)

5. **add_to_setlist_overlay.dart** (passthrough):
   - Declares `enrichmentSettings` as a constructor parameter (line 69 in `showAddToSetlistOverlay()`, line 140 in `_AddToSetlistOverlay`)
   - Forwards `enrichmentSettings` to `OriginalSongScreen` (line 338) and `BulkEntryScreen` (line 352)
   - Called from `new_setlist_screen.dart` (line 288 via `showAddToSetlistOverlay()`) and `setlist_detail_screen.dart` (line 773 via `showAddToSetlistOverlay()`)
   - Does NOT read from `enrichmentSettingsProvider` itself — relies on call-site to pass the value

6. **Call-site pattern** (six methods across two screens read `enrichmentSettingsProvider` and forward to consumers):
   - **new_setlist_screen.dart**:
     - `_handleAddToSetlist()` (lines 276-280) → passes to `showAddToSetlistOverlay()` at line 293
     - `_handleOriginalSongEntry()` (lines 517-521) → passes directly to `OriginalSongScreen` at line 550
     - `_handleBulkEntry()` (lines 597-601) → passes directly to `BulkEntryScreen` at line 630
   - **setlist_detail_screen.dart**:
     - `_handleOpenAddOverlay()` (lines 736-740) → passes to `showAddToSetlistOverlay()` at line 780
     - `_handleOriginalSongEntry()` (lines 1167-1171) → passes directly to `OriginalSongScreen` at line 1200
     - `_handleBulkEntry()` (lines 1246-1250) → passes directly to `BulkEntryScreen` at line 1279

7. **Database** (`supabase/migrations/20260810000000_enrichment_settings.sql`):
   - Table: `enrichment_settings` with CHECK constraint `new_song_behavior IN ('ask', 'auto', 'off')`
   - RPC: `get_or_create_enrichment_settings` (SECURITY INVOKER, inserts 'ask' default if missing)
   - RPC: `update_enrichment_settings` (SECURITY INVOKER, validates enum at lines 103-105)
   - RLS policies: band members can view/insert, admins+members can update

8. **GetSongBPM attribution** (required by API terms, already satisfied independently):
   - `lib/features/landing/widgets/footer_section.dart` (line 76): `_AttributionLink` widget in footer
   - `lib/features/legal/privacy_policy_screen.dart` (line 103): "Third-Party Data Providers" section
   - `marketing/privacy.html` (line 167): canonical privacy page (SEO-indexed, authoritative)

**Data flow for new song addition:**

1. User adds song via bulk entry / original song / external lookup
2. Consumer reads `enrichmentSettingsProvider`
3. If `newSongBehavior == ask`: show enrichment confirm dialog with fetched BPM/Key values, user reviews/edits, then saves
4. If `newSongBehavior == auto`: enrich in background, save without review
5. If `newSongBehavior == off`: skip enrichment, save with nulls

## Proposed Solution

**Lock to Ask behavior at Flutter call-site level only. Do NOT migrate DB schema.**

### Changes

1. **Remove Settings menu items** (`lib/features/settings/settings_screen.dart`):
   - Delete lines 68-79 (both "Song Enrichment" and "GetSongBPM.com" items from `_buildSettingsItems()`)
   - Remove `EnrichmentSettingsScreen` import (line 14)
   - Remove `_openEnrichmentSettings()` method (lines 118-124)
   - Remove `_openGetSongBpmAttribution()` method (lines 133-139)

2. **Hardcode Ask in bulk_entry_screen.dart**:
   - Remove `enrichmentSettings` constructor param and field
   - Replace line 374 `final newSongBehavior = settings?.newSongBehavior ?? NewSongBehavior.off;` with `const newSongBehavior = NewSongBehavior.ask;`
   - Delete lines 383, 424-441 (the `off` and `auto` branches — only `ask` branch remains)
   - Remove `EnrichmentSettings` import

3. **Hardcode Ask in original_song_screen.dart**:
   - Remove `enrichmentSettings` constructor param and field
   - Replace line 195 `final newSongBehavior = settings?.newSongBehavior ?? NewSongBehavior.off;` with `const newSongBehavior = NewSongBehavior.ask;`
   - Delete lines 207-217, 256-268 (the `off` and `auto` branches)
   - Remove `EnrichmentSettings` import

4. **Hardcode Ask in song_lookup_overlay.dart**:
   - Remove `enrichmentSettingsProvider` import (line 13)
   - Replace lines 292-296 with `const newSongBehavior = NewSongBehavior.ask;`
   - Delete the switch statement's `auto` branch (lines 314-338) and `off` branch (lines 339-343)
   - Only the `ask` case remains

5. **Remove enrichmentSettings passthrough from add_to_setlist_overlay.dart**:
   - Remove `EnrichmentSettings` import (line 8)
   - Remove `enrichmentSettings` parameter from `showAddToSetlistOverlay()` function signature (line 69)
   - Remove `enrichmentSettings` parameter from `_AddToSetlistOverlay` constructor (lines 140, 157)
   - Remove `enrichmentSettings: widget.enrichmentSettings,` from `OriginalSongScreen` call (line 338)
   - Remove `enrichmentSettings: widget.enrichmentSettings,` from `BulkEntryScreen` call (line 352)

6. **Remove provider reads from call sites**:
   - **new_setlist_screen.dart**:
     - Remove `enrichment_settings_controller` import (line 39)
     - In `_handleAddToSetlist()`: Remove enrichmentSettingsAsync read (lines 276-280), remove `enrichmentSettings` arg from `showAddToSetlistOverlay()` (line 293)
     - In `_handleOriginalSongEntry()`: Remove enrichmentSettingsAsync read (lines 517-521), remove `enrichmentSettings` arg from `OriginalSongScreen` (line 550)
     - In `_handleBulkEntry()`: Remove enrichmentSettingsAsync read (lines 597-601), remove `enrichmentSettings` arg from `BulkEntryScreen` (line 630)
   - **setlist_detail_screen.dart**:
     - Remove `enrichment_settings_controller` import (line 50)
     - In `_handleOpenAddOverlay()`: Remove enrichmentSettingsAsync read (lines 736-740), remove `enrichmentSettings` arg from `showAddToSetlistOverlay()` (line 780)
     - In `_handleOriginalSongEntry()`: Remove enrichmentSettingsAsync read (lines 1167-1171), remove `enrichmentSettings` arg from `OriginalSongScreen` (line 1200)
     - In `_handleBulkEntry()`: Remove enrichmentSettingsAsync read (lines 1246-1250), remove `enrichmentSettings` arg from `BulkEntryScreen` (line 1279)

**Rationale:**

- Flutter call-site lock is sufficient — stored 'auto'/'off' DB values become unreachable once all consumers hardcode Ask
- No DB migration required (simpler, lower risk)
- No RLS/RPC changes required
- Existing enrichment review UI (confirm dialog / review sheet) stays unchanged
- GetSongBPM attribution preserved independently in footer, privacy screen, and marketing page (satisfies API terms)

## Database Impact

**Not applicable.** No schema changes, RLS changes, or RPC modifications required. Existing `enrichment_settings` table, CHECK constraint, and RPCs remain unchanged. Stored `'auto'` and `'off'` values become unreachable but harmless once all Flutter consumers hardcode Ask behavior.

## Flutter Architecture Changes

**State management:**

- `enrichmentSettingsProvider` becomes unreachable (no longer read by any active code path after Settings nav entry removed)
- No new providers created
- No existing providers modified

**Widgets affected:**

- `settings_screen.dart` — menu items removed
- `bulk_entry_screen.dart` — `enrichmentSettings` param removed, Ask hardcoded
- `original_song_screen.dart` — `enrichmentSettings` param removed, Ask hardcoded
- `song_lookup_overlay.dart` — `enrichmentSettingsProvider` read removed, Ask hardcoded
- `add_to_setlist_overlay.dart` — `enrichmentSettings` param removed, forwarding removed
- `new_setlist_screen.dart` — provider reads removed (3 methods), enrichmentSettings args removed from all call sites
- `setlist_detail_screen.dart` — provider reads removed (3 methods), enrichmentSettings args removed from all call sites

**Repositories:**

- No repository changes

## Files to Create

**None.**

## Files to Modify

| File                                                                       | Changes                                                                                                                                                                                                                                                                                       |
| -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/settings/settings_screen.dart`                               | Remove lines 68-79 (both enrichment menu items from `_buildSettingsItems()`), remove `EnrichmentSettingsScreen` import (line 14), remove `_openEnrichmentSettings()` method (lines 118-124), remove `_openGetSongBpmAttribution()` method (lines 133-139)                                     |
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`      | Remove `enrichmentSettings` constructor param and field, replace line 374 with `const newSongBehavior = NewSongBehavior.ask;`, delete `off` and `auto` branches (lines 383, 424-441), remove `EnrichmentSettings` import                                                                      |
| `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`   | Remove `enrichmentSettings` constructor param and field, replace line 195 with `const newSongBehavior = NewSongBehavior.ask;`, delete `off` and `auto` branches (lines 207-217, 256-268), remove `EnrichmentSettings` import                                                                  |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`                   | Remove `enrichmentSettingsProvider` import (line 13), replace lines 292-296 with `const newSongBehavior = NewSongBehavior.ask;`, delete `auto` and `off` switch branches (lines 314-343)                                                                                                      |
| `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` | Remove `enrichmentSettings` param from `showAddToSetlistOverlay()` function (line 69) and `_AddToSetlistOverlay` constructor (lines 140, 157), remove forwarding to `OriginalSongScreen` (line 338) and `BulkEntryScreen` (line 352), remove `EnrichmentSettings` import (line 8)             |
| `lib/features/setlists/new_setlist_screen.dart`                            | Remove `enrichment_settings_controller` import (line 39), remove THREE enrichmentSettingsAsync reads (lines 276-280, 517-521, 597-601), remove `enrichmentSettings` args from `showAddToSetlistOverlay()` (line 293), `OriginalSongScreen` (line 550), and `BulkEntryScreen` (line 630)       |
| `lib/features/setlists/setlist_detail_screen.dart`                         | Remove `enrichment_settings_controller` import (line 50), remove THREE enrichmentSettingsAsync reads (lines 736-740, 1167-1171, 1246-1250), remove `enrichmentSettings` args from `showAddToSetlistOverlay()` (line 780), `OriginalSongScreen` (line 1200), and `BulkEntryScreen` (line 1279) |

## Files Off-Limits

| File                                                         | Reason                                                                                                 |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| `lib/features/landing/widgets/footer_section.dart`           | GetSongBPM attribution required by API terms, already exists independently in landing page footer      |
| `lib/features/legal/privacy_policy_screen.dart`              | GetSongBPM privacy disclosure required, already exists independently                                   |
| `marketing/privacy.html`                                     | Canonical SEO-indexed privacy page, already contains GetSongBPM disclosure                             |
| `supabase/migrations/20260810000000_enrichment_settings.sql` | No DB changes required — Flutter call-site lock is sufficient                                          |
| `lib/features/songs/enrichment_settings_screen.dart`         | Dead code — leave in place per GUARDRAILS §7 (no cleanup required, may be useful if decision reversed) |
| `lib/features/songs/enrichment_settings_controller.dart`     | Dead code — leave in place per GUARDRAILS §7                                                           |
| `lib/features/songs/enrichment_settings_repository.dart`     | Dead code — leave in place per GUARDRAILS §7                                                           |
| `lib/features/songs/models/enrichment_settings.dart`         | Dead code — leave in place per GUARDRAILS §7                                                           |

## System Impact Map

| System                                 | Impact                                                                           |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                       |
| Rehearsals                             | unaffected                                                                       |
| Setlists / Catalog                     | **affected** — song addition always uses Ask path (review before save)           |
| Members / RBAC                         | unaffected                                                                       |
| Auth / Session                         | unaffected                                                                       |
| Routing                                | **affected** — Settings nav entry removed (EnrichmentSettingsScreen unreachable) |
| Notifications                          | unaffected                                                                       |
| Platform (iOS / Android / Web / macOS) | **affected** — all share Settings UI, all song addition flows locked to Ask      |

## Regression Risk

**Level:** `LOW`

**Rationale:**

- Touches 7 files, all in song addition flow
- Does not touch auth, session, or init order
- Routing change is removal only (one nav entry)
- No database mutations
- Only one system impacted (Setlists/Catalog)
- Change is mostly code removal + constant substitution — no new logic
- Existing enrichment review UI (confirm dialog, review sheet) stays unchanged
- GetSongBPM attribution preserved independently (verified in 3 locations)
- Dead code left in place (zero risk of accidental deletion-related breakage)
- Pre-existing fallback inconsistency (off vs ask) becomes moot once all hardcoded to ask

## Engineer Task Breakdown

**Task 1:** Remove Settings menu items

- Edit `lib/features/settings/settings_screen.dart`:
  - Delete lines 68-79 (both SettingsItem entries for Song Enrichment and GetSongBPM attribution)
  - Remove `EnrichmentSettingsScreen` import (line 14: `import '../songs/enrichment_settings_screen.dart';`)
  - Remove `_openEnrichmentSettings()` method (lines 118-124)
  - Remove `_openGetSongBpmAttribution()` method (lines 133-139)

**Task 2:** Hardcode Ask in bulk_entry_screen.dart

- Edit `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`:
  - Remove `enrichmentSettings` from constructor params (line 131) and field (line 132)
  - Remove `EnrichmentSettings` import (line 14: `import '../../../songs/models/enrichment_settings.dart';`)
  - Replace line 374 with: `const newSongBehavior = NewSongBehavior.ask;`
  - Delete line 373 (`final settings = widget.enrichmentSettings;`)
  - Delete lines 383-387 (the `if (exists || newSongBehavior == NewSongBehavior.off)` branch)
  - Delete lines 424-441 (the `else if (newSongBehavior == NewSongBehavior.auto)` branch)
  - Only the `if (newSongBehavior == NewSongBehavior.ask)` branch remains, and the condition check becomes unnecessary once the constant is set

**Task 3:** Hardcode Ask in original_song_screen.dart

- Edit `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart`:
  - Remove `enrichmentSettings` from constructor params (line 82) and field (line 83)
  - Remove `EnrichmentSettings` import (line 14: `import '../../../songs/models/enrichment_settings.dart';`)
  - Replace line 195 with: `const newSongBehavior = NewSongBehavior.ask;`
  - Delete line 194 (`final settings = widget.enrichmentSettings;`)
  - Delete lines 207-217 (the `if (exists || newSongBehavior == NewSongBehavior.off)` branch)
  - Delete lines 256-268 (the `else if (newSongBehavior == NewSongBehavior.auto)` branch)
  - Only the `if (newSongBehavior == NewSongBehavior.ask)` branch remains

**Task 4:** Hardcode Ask in song_lookup_overlay.dart

- Edit `lib/features/setlists/widgets/song_lookup_overlay.dart`:
  - Remove `enrichment_settings_controller` import (line 13: `import '../../songs/enrichment_settings_controller.dart';`)
  - Replace lines 292-296 with: `const newSongBehavior = NewSongBehavior.ask;`
  - Delete the `switch (newSongBehavior)` statement's `auto` branch (lines 314-338)
  - Delete the `off` branch (lines 339-343)
  - Only the `ask` case remains

**Task 5:** Remove enrichmentSettings passthrough from add_to_setlist_overlay.dart

- Edit `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart`:
  - Remove `EnrichmentSettings` import (line 8: `import '../../../songs/models/enrichment_settings.dart';`)
  - Remove `enrichmentSettings` parameter from `showAddToSetlistOverlay()` function signature (line 69)
  - Remove `enrichmentSettings` parameter from `_AddToSetlistOverlay` constructor (line 140)
  - Remove `this.enrichmentSettings` from constructor initializer list (line 157)
  - Remove `final EnrichmentSettings? enrichmentSettings;` field declaration (line 140)
  - Remove `enrichmentSettings: widget.enrichmentSettings,` from `OriginalSongScreen` constructor call (line 338)
  - Remove `enrichmentSettings: widget.enrichmentSettings,` from `BulkEntryScreen` constructor call (line 352)
  - Remove the assertions referencing `enrichmentSettings` (if any)

**Task 6:** Remove provider reads from new_setlist_screen.dart

- Edit `lib/features/setlists/new_setlist_screen.dart`:
  - Remove `enrichment_settings_controller` import (line 39: `import '../songs/enrichment_settings_controller.dart';`)
  - In `_handleAddToSetlist()` method:
    - Remove lines 276-280 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `showAddToSetlistOverlay()` call (line 293)
  - In `_handleOriginalSongEntry()` method:
    - Remove lines 517-521 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `OriginalSongScreen` constructor call (line 550)
  - In `_handleBulkEntry()` method:
    - Remove lines 597-601 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `BulkEntryScreen` constructor call (line 630)

**Task 7:** Remove provider reads from setlist_detail_screen.dart

- Edit `lib/features/setlists/setlist_detail_screen.dart`:
  - Remove `enrichment_settings_controller` import (line 50: `import '../songs/enrichment_settings_controller.dart';`)
  - In `_handleOpenAddOverlay()` method:
    - Remove lines 736-740 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `showAddToSetlistOverlay()` call (line 780)
  - In `_handleOriginalSongEntry()` method:
    - Remove lines 1167-1171 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `OriginalSongScreen` constructor call (line 1200)
  - In `_handleBulkEntry()` method:
    - Remove lines 1246-1250 (enrichmentSettingsAsync read + `.when()`)
    - Remove `enrichmentSettings: enrichmentSettings,` from `BulkEntryScreen` constructor call (line 1279)

**Task 8:** Run `flutter analyze`

- Confirm 0 errors
- Confirm no new warnings introduced by this change

**Task 9:** Generate git diff and verify no unintended changes

- Run `git diff` and review all modifications
- Confirm only the 7 files listed in "Files to Modify" are changed
- Confirm no changes to off-limits files
- Confirm no accidental deletions or formatting changes

## Verification Plan

### Tier 1 — Pre-deployment (Flutter analyzer and manual code review)

**Test 1: Analyzer pass**

```bash
flutter analyze
```

Expected: 0 errors. Confirm no new warnings introduced by this change.

**Test 2: Settings screen isolation**

- Manually inspect `lib/features/settings/settings_screen.dart`
- Confirm "Song Enrichment" and "GetSongBPM.com" menu items are removed from `_buildSettingsItems()`
- Confirm `EnrichmentSettingsScreen` import removed
- Confirm `_openEnrichmentSettings()` and `_openGetSongBpmAttribution()` methods removed
- Confirm no other changes to settings screen

**Test 3: Attribution preservation**

- Manually inspect `lib/features/landing/widgets/footer_section.dart` — confirm unchanged
- Manually inspect `lib/features/legal/privacy_policy_screen.dart` — confirm unchanged
- Manually inspect `marketing/privacy.html` — confirm unchanged
- Confirm GetSongBPM attribution exists in all three locations (satisfies API terms)

**Test 4: Consumer hardcoding**

- Manually inspect `bulk_entry_screen.dart` — confirm `const newSongBehavior = NewSongBehavior.ask;` and no branching
- Manually inspect `original_song_screen.dart` — confirm `const newSongBehavior = NewSongBehavior.ask;` and no branching
- Manually inspect `song_lookup_overlay.dart` — confirm `const newSongBehavior = NewSongBehavior.ask;` and no switch
- Confirm `enrichmentSettings` param removed from all three

**Test 5: Overlay passthrough cleanup**

- Manually inspect `add_to_setlist_overlay.dart` — confirm `enrichmentSettings` param removed from function signature, constructor, field declaration, and both forwarding sites (OriginalSongScreen, BulkEntryScreen)
- Confirm `EnrichmentSettings` import removed

**Test 6: Call-site cleanup**

- Manually inspect `new_setlist_screen.dart` — confirm THREE methods (`_handleAddToSetlist`, `_handleOriginalSongEntry`, `_handleBulkEntry`) have no `enrichmentSettingsProvider` read, no `enrichmentSettings` args
- Manually inspect `setlist_detail_screen.dart` — confirm THREE methods (`_handleOpenAddOverlay`, `_handleOriginalSongEntry`, `_handleBulkEntry`) have no `enrichmentSettingsProvider` read, no `enrichmentSettings` args

**Test 7: Dead code isolation**

- Confirm `EnrichmentSettingsScreen`, controller, repository, model files still exist on disk (not deleted)
- Confirm no imports of these files remain in any active code path

### Tier 2 — Post-deployment (manual device testing)

**Test 8: Settings screen navigation**

- Open Settings
- Confirm "Song Enrichment" menu item does NOT appear
- Confirm "Song tempo & key data via GetSongBPM.com" menu item does NOT appear
- Confirm remaining items (Notifications, One Calendar if applicable, Delete Account) still present and functional

**Test 9: Bulk entry enrichment (Ask flow)**

- Open a setlist
- Tap "Add songs" → "Add multiple"
- Paste or type 2+ new song entries
- Tap "Add Songs"
- Confirm enrichment confirm dialog appears for each new song (Ask flow)
- Confirm BPM/Duration/Key values displayed as found or empty
- Confirm user can edit values before saving
- Confirm songs save with reviewed/edited values
- Confirm no console errors

**Test 10: Original song enrichment (Ask flow)**

- Open a setlist
- Tap "Add songs" → "Original song"
- Enter title and artist for a new original song
- Tap "Add song"
- Confirm enrichment confirm dialog appears (Ask flow)
- Confirm BPM/Key values displayed as found or empty
- Confirm user can edit values before saving
- Confirm song saves with reviewed/edited values
- Confirm no console errors

**Test 11: Song lookup enrichment (Ask flow)**

- Open a setlist
- Tap "Add songs" → Search
- Search for a new song (not in catalog)
- Tap an external result
- Confirm enrichment review sheet appears (Ask flow)
- Confirm BPM/Duration/Key values displayed
- Confirm user can edit values before saving
- Confirm song saves with reviewed/edited values
- Confirm no console errors

**Test 12: Existing song (catalog) addition**

- Open a setlist
- Tap "Add songs" → Search
- Search for a song already in the catalog
- Tap the catalog result
- Confirm song is added immediately (no enrichment prompt — expected, song already exists)
- Confirm no console errors

**Test 13: Band with stored 'auto' or 'off' value**

- If a test band has `enrichment_settings.new_song_behavior = 'auto'` or `'off'` in the DB:
  - Add a new song via any path (bulk, original, lookup)
  - Confirm Ask flow still triggers (DB value is ignored, Flutter hardcoded Ask wins)
- If no such band exists, skip this test and document "not applicable — no bands with auto/off in test DB"

**Test 14: GetSongBPM attribution verification**

- Open landing page (if accessible on web)
- Scroll to footer
- Confirm "Song tempo & key data via GetSongBPM.com" link present and functional
- Open Privacy Policy screen (from Settings or web)
- Scroll to "Third-Party Data Providers" section
- Confirm GetSongBPM disclosure present
- Load `https://bandroadie.com/privacy` in browser
- Confirm GetSongBPM disclosure present (canonical page)

**Test 15: Cross-platform consistency**

- Run Tests 8-14 on at least two platforms (e.g., iOS + Web, or macOS + Web)
- Confirm Ask flow triggers consistently across platforms
- Confirm Settings screen menu items removed consistently
- Confirm no platform-specific regressions

## QA Regression Areas

**Primary validation:**

- Settings screen — "Song Enrichment" and "GetSongBPM.com" menu items removed
- Bulk entry (new songs) — always triggers Ask flow (enrichment confirm dialog)
- Original song entry (new songs) — always triggers Ask flow (enrichment confirm dialog)
- Song lookup (external results) — always triggers Ask flow (enrichment review sheet)
- Existing catalog songs — added without enrichment prompt (expected, no change)

**Regression checks:**

- Settings screen — remaining items (Notifications, One Calendar, Delete Account) still functional
- GetSongBPM attribution — present and functional in footer, privacy screen, marketing page
- Band switching — no enrichment-related console errors when switching bands
- Existing enrichment UI — confirm dialog and review sheet display correctly, editable fields work
- Cross-platform consistency — Settings removal and Ask-only behavior consistent on iOS, Android, Web, macOS

**Out-of-scope (do not test):**

- Existing song enrichment (song details sheet "Enrich" action) — unrelated feature, already shipped
- ExistingSongBehavior — already locked to Fill-Missing-Only (prior work, out of scope)
- Database schema or RPC behavior — no changes made

## Rollout / Migration Strategy

**Not applicable.** No data migration required. Existing `enrichment_settings` records with `new_song_behavior = 'auto'` or `'off'` remain in the database unchanged but become unreachable once all Flutter consumers hardcode Ask behavior. If product reverses this decision in the future, the stored settings can be restored by un-hardcoding the consumers and re-adding the Settings menu item.

## Out of Scope

- **Existing song enrichment** (song details sheet "Enrich" action) — already shipped, separate feature
- **ExistingSongBehavior** — already locked to `fillMissingOnly`, no changes needed
- **Database schema changes** — not required, Flutter call-site lock is sufficient
- **RLS/RPC changes** — not required
- **GetSongBPM attribution** in footer, privacy screen, marketing page — already exists independently, off-limits per plan
- **Dead code cleanup** — EnrichmentSettingsScreen, controller, repository, model files intentionally left in place per GUARDRAILS §7
- **Pre-existing fallback inconsistency** (bulk/original default to `off`, lookup defaults to `ask`) — becomes moot once all hardcoded to `ask`
- **Bands with stored `'auto'` or `'off'` values** — will automatically follow Ask path once consumers are hardcoded, no explicit migration needed
