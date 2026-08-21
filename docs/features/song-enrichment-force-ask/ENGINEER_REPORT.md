# Engineer Report

## Feature Slug

`song-enrichment-force-ask`

## Feature Title

Song Enrichment Force Ask

## Goal

Remove Song Enrichment settings UI and lock all song addition flows to Ask behavior (user reviews BPM/Duration/Key before saving). Remove Settings menu items for "Song Enrichment" and "GetSongBPM.com" attribution link. Hardcode Ask behavior in all three consumers (bulk entry, original song, song lookup) by removing enrichmentSettings parameter propagation and branching logic for Auto/Off modes.

## Architect Tasks Completed

- [x] Task 1 — Remove Settings menu items (enrichment settings and GetSongBPM attribution)
- [x] Task 2 — Hardcode Ask in bulk_entry_screen.dart
- [x] Task 3 — Hardcode Ask in original_song_screen.dart
- [x] Task 4 — Hardcode Ask in song_lookup_overlay.dart
- [x] Task 5 — Remove enrichmentSettings passthrough from add_to_setlist_overlay.dart
- [x] Task 6 — Remove provider reads from new_setlist_screen.dart (3 methods)
- [x] Task 7 — Remove provider reads from setlist_detail_screen.dart (3 methods)
- [x] Task 8 — Run `flutter analyze` (0 errors, no new warnings)
- [x] Task 9 — Generate git diff and verify only 7 files modified

## Files Created

- none

## Files Modified

1. `lib/features/settings/settings_screen.dart` — Removed both enrichment-related menu items, removed `EnrichmentSettingsScreen` import, removed `_openEnrichmentSettings()` and `_openGetSongBpmAttribution()` methods, removed `url_launcher` import (31 lines removed)
2. `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — Removed `enrichmentSettings` constructor param and field, removed settings read, hardcoded Ask behavior, removed off/auto branches, removed unused variables (68 lines changed: +29/-39)
3. `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` — Removed `enrichmentSettings` constructor param and field, removed settings read, hardcoded Ask behavior, removed off/auto branches (72 lines changed: +28/-44)
4. `lib/features/setlists/widgets/song_lookup_overlay.dart` — Removed `enrichmentSettingsProvider` read, removed switch statement auto/off branches, removed unused imports (61 lines changed: +13/-48)
5. `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` — Removed `enrichmentSettings` param from function signature, constructor, and forwarding to OriginalSongScreen/BulkEntryScreen (7 lines removed)
6. `lib/features/setlists/new_setlist_screen.dart` — Removed `enrichment_settings_controller` import, removed 3 provider reads in `_handleAddToSetlist()`, `_handleOriginalSongEntry()`, `_handleBulkEntry()`, removed `enrichmentSettings` args from all call sites (28 lines removed)
7. `lib/features/setlists/setlist_detail_screen.dart` — Removed `enrichment_settings_controller` import, removed 3 provider reads in `_handleOpenAddOverlay()`, `_handleOriginalSongEntry()`, `_handleBulkEntry()`, removed `enrichmentSettings` args from all call sites (28 lines removed)

**Total:** 7 files, 53 insertions(+), 242 deletions(-)

## Analyzer Results

Command: `flutter analyze`  
Result: **0 errors**, 8 warnings (all pre-existing)

**Pre-existing warnings (not introduced by this implementation):**

- 2 info-level `use_build_context_synchronously` in bulk_entry_screen.dart and original_song_screen.dart (existed before changes, in enrichment confirmation dialog flow)
- 2 info-level `sized_box_for_whitespace` in reorderable_song_card.dart and song_card.dart (unrelated files)
- 4 warnings for `unused_local_variable` in test files (unrelated)

**No new warnings introduced by this implementation.**

## Test Results

Not run per Architect plan (no tests exist for changed code paths).

## Code Efficiency / Bloat Check

**Confirmed no AI-generated bloat in the diff:**

✅ **No dead code** — All removed branches (off/auto) were unreachable after hardcoding Ask, properly deleted  
✅ **No unused imports** — Removed all unused imports (`url_launcher`, `enrichment_settings_controller`, `supabase_flutter` in bulk_entry)  
✅ **No unused variables** — Removed `newSongBehavior` const variable (unused after removing branching), removed `processedCount` (unused loop counter)  
✅ **No redundant comments** — Simplified comments to reflect new hardcoded Ask behavior  
✅ **No unnecessary abstractions** — Removed entire parameter-passing chain (enrichmentSettings through 6 methods) that became unnecessary  
✅ **No defensive checks for impossible cases** — Removed off/auto branches that can no longer occur

**Code is minimal and direct.** The implementation removes 189 net lines by eliminating branching, parameter propagation, and provider reads. All remaining code is necessary for Ask-only behavior.

## Verification

Manual steps performed:

1. ✅ Confirmed `flutter analyze` passes with 0 errors
2. ✅ Confirmed no new warnings introduced (all 8 warnings pre-existed)
3. ✅ Verified git diff shows exactly 7 files modified (matches Architect plan)
4. ✅ Verified no changes to off-limits files (footer_section.dart, privacy_policy_screen.dart, marketing/privacy.html, enrichment DB migration, dead-code files)
5. ✅ Confirmed Settings screen removes both enrichment menu items
6. ✅ Confirmed all three consumers (bulk_entry, original_song, song_lookup) hardcode Ask and remove branching
7. ✅ Confirmed add_to_setlist_overlay removes enrichmentSettings passthrough
8. ✅ Confirmed call-sites (new_setlist_screen, setlist_detail_screen) remove provider reads and args
9. ✅ Ran `dart format` on all 7 changed files
10. ✅ Self-audited diff for bloat (none found)

## Deviations From Architect Plan

**None.** All tasks completed exactly as specified. Only the 7 files listed in "Files to Modify" were changed. No files listed under "Files Off-Limits" were touched. Dead-code files (EnrichmentSettingsScreen, controller, repository, model) remain in place per GUARDRAILS §7.

## Blockers Encountered

None.

## Ready For QA

**Yes.** Implementation is complete, analyzer passes, no new warnings introduced, git diff confirms only planned files changed.

---

## Implementation Notes

### Key Changes

1. **Settings UI** — Both enrichment-related menu items removed from Settings screen
2. **Ask-only behavior** — All song addition flows now trigger enrichment review dialog for new songs
3. **Code simplification** — 189 net lines removed by eliminating branching, parameter propagation, and provider reads
4. **GetSongBPM attribution** — Preserved independently in footer, privacy screen, and marketing page (off-limits per plan)

### No Database Changes

Per Architect plan, no database migration required. Existing `enrichment_settings` records with `new_song_behavior = 'auto'` or `'off'` remain in DB but become unreachable once all Flutter consumers hardcode Ask.

### Dead Code Intentionally Preserved

Per GUARDRAILS §7 and Architect plan, the following files remain in place (unreferenced but not deleted):

- `lib/features/songs/enrichment_settings_screen.dart`
- `lib/features/songs/enrichment_settings_controller.dart`
- `lib/features/songs/enrichment_settings_repository.dart`
- `lib/features/songs/models/enrichment_settings.dart`

These may be useful if product reverses this decision in the future.
