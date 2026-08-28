# Architect Plan — feature/enrichment-new-song-behavior-wiring

## 1. Feature Slug

`feature/enrichment-new-song-behavior-wiring`

Type: bug fix
Branch: `feature/enrichment-new-song-behavior-wiring` (cut fresh from `main`/develop — do NOT stack on `feature/song-enrichment-confidence-display`, which has its own uncommitted, unrelated changes pending)
Docs path: `docs/features/enrichment-new-song-behavior-wiring/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

The app has a fully-built, user-facing Settings screen (`enrichment_settings_screen.dart`) letting a band choose `Ask` / `Auto` / `Off` for new-song enrichment behavior, backed by a real model (`EnrichmentSettings.newSongBehavior`), repository, RPC, and Riverpod provider (`enrichmentSettingsProvider`). None of it is wired up. Both places that add a new song to the catalog hardcode "Ask" and unconditionally show a confirmation dialog, regardless of what the band has configured:

- `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` — manual/original song entry. Comment on the call site literally reads `// New song - always show confirmation dialog (Ask behavior)`.
- `lib/features/setlists/widgets/song_lookup_overlay.dart` — external (Spotify/MusicBrainz) search result tap. Comment reads `// Show review sheet (Ask behavior)`.

User-reported symptom: adding an original song always pops the "Enrich Song?" dialog; user wants new songs auto-enriched with no prompt.

---

## 3. Root Cause

| Root cause | Confidence |
| --- | --- |
| `original_song_screen.dart._handleSubmit()` calls `showEnrichmentConfirmDialog` unconditionally for every new song, never reading `EnrichmentSettings.newSongBehavior`. | HIGH |
| `song_lookup_overlay.dart._handleExternalSongTap()` calls `showSongEnrichmentReviewSheet` unconditionally, same gap. | HIGH |
| The `InlineSongEnrichmentService` used by the confirm dialog is explicitly documented as "used by 'auto' mode" but is never invoked in auto mode — only ever from inside the dialog after a user taps "Add". The auto-enrich code path already exists and is simply unreachable. | HIGH |

This is a wiring gap, not a missing feature. The Settings screen has been dead since it shipped.

---

## 4. Proposed Solution

**`original_song_screen.dart`:**
- Convert `OriginalSongScreen` / `_OriginalSongScreenState` from `StatefulWidget`/`State` to `ConsumerStatefulWidget`/`ConsumerState` (add `flutter_riverpod` import). No constructor/API change — existing 3 call sites (`setlist_detail_screen.dart`, `new_setlist_screen.dart`, `add_to_setlist_overlay.dart`) are untouched.
- In `_handleSubmit()`, before the per-entry loop, read the band's behavior once:
  ```dart
  final newSongBehavior =
      (await ref.read(enrichmentSettingsProvider.future)).newSongBehavior;
  ```
- Replace the unconditional dialog call in the "new song" branch with:
  - `NewSongBehavior.ask` → current behavior, unchanged (show dialog, respect Skip/Add, abort-all on cancel).
  - `NewSongBehavior.auto` → skip the dialog; call `widget.enrichmentService.enrichSong(title: title, artist: artist)` directly (the exact call the dialog already makes internally) and add the song with the returned bpm/musicalKey.
  - `NewSongBehavior.off` → skip enrichment entirely; add the song with `bpm: null, musicalKey: null` (identical to today's "Skip" outcome).

**`song_lookup_overlay.dart`:**
- Already `ConsumerStatefulWidget` — has `ref`.
- In `_handleExternalSongTap()`, replace the unconditional `showSongEnrichmentReviewSheet` call with the same three-way branch on `(await ref.read(enrichmentSettingsProvider.future)).newSongBehavior`:
  - `ask` → current behavior, unchanged.
  - `auto` → skip the sheet; construct `SongEnrichmentService(Supabase.instance.client)` inline (mirrors exactly what `_SongEnrichmentReviewSheetState._fetchEnrichment()` already does) and call `.lookup(title: result.title, artist: result.artist, durationSeconds: result.durationSeconds)` to get bpm/musicalKey silently; use `result.durationSeconds` as-is for duration.
  - `off` → skip enrichment; use `result.durationSeconds` for duration, `bpm: null, musicalKey: null`.

Both flows read the same provider the same way the Settings screen already does — no new repository/RPC/provider code needed.

---

## 5. Files to Modify

| File | What changes |
| --- | --- |
| `lib/features/setlists/widgets/add_to_setlist/original_song_screen.dart` | Convert to `ConsumerStatefulWidget`; branch on `newSongBehavior` instead of always showing the confirm dialog. |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | Branch `_handleExternalSongTap` on `newSongBehavior` instead of always showing the review sheet. |

## 6. Files Off-Limits

| File | Reason |
| --- | --- |
| `enrichment_settings_repository.dart`, `enrichment_settings_controller.dart`, `enrichment_settings_screen.dart`, `models/enrichment_settings.dart` | Already correct and fully working — this fix only wires existing infrastructure into the two add-song flows. No changes needed. |
| `supabase/**` | No backend change required. |
| The 3 call sites of `OriginalSongScreen` | Constructor API unchanged; no edits needed. |
| `song_enrichment_review_sheet.dart`, `enrichment_confirm_dialog.dart` | Untouched — still used as-is for the `ask` path. |

---

## 7. Regression Risk

**LOW–MEDIUM.** Converting `OriginalSongScreen` to `ConsumerStatefulWidget` is mechanical but touches every method's implicit context — verify no naming collision with an existing local var/method named `ref`, and that `WidgetsBinding`/`TickerProviderStateMixin` usage still compiles unchanged. The `ask` path in both files must remain byte-identical in behavior (this is the default and most-used setting; a regression here breaks the primary flow for every band that hasn't touched Settings). `auto` and `off` are new code paths — test all three explicitly, not just the one the user asked about.

---

## 8. Engineer Task Breakdown

1. Convert `OriginalSongScreen`/`_OriginalSongScreenState` to `ConsumerStatefulWidget`/`ConsumerState`, add the riverpod import.
2. In `_handleSubmit()`, fetch `newSongBehavior` once per submit call (not once per song) and branch the new-song path three ways as specified above.
3. In `song_lookup_overlay.dart._handleExternalSongTap()`, fetch `newSongBehavior` and branch the same three ways.
4. Run `flutter analyze` — 0 new errors, no new warnings beyond the existing baseline (currently 8).

---

## 9. Verification Plan

- Set band Settings → New Song Behavior → **Ask**. Add an original song → confirm dialog still appears exactly as before, Skip/Add/Cancel all behave as before.
- Set to **Auto**. Add an original song → confirm NO dialog appears, song is saved with BPM/Key silently filled when found.
- Set to **Off**. Add an original song → confirm NO dialog, NO lookup call, song saved with null BPM/Key.
- Repeat all three for adding a song via external search (Spotify/MusicBrainz result tap in `song_lookup_overlay.dart`).
- Confirm Settings screen itself still saves/loads correctly (unchanged, but verify the provider it shares wasn't broken).

---

## 10. Out of Scope

- Any change to the enrichment RPC, matching logic, or confidence scoring.
- Any change to the Settings screen UI or the `EnrichmentSettings` model.
- Any change to `feature/song-enrichment-confidence-display` files (separate branch, separate concern).
