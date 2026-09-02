## Bug Fix: Song key/tempo manual changes overwritten by web enrichment

Reported by Scott Lotspeich (HonkyTonk band, iOS, v1.4.5 (245), Aug 31 2026):

> "When I change a key or tempo on the song catalog, it defaults back to pulling
> the info from the web instead of keeping the change."

### Root Cause

Two compounding bugs in the song metadata write path:

**Bug 1 (primary — reported):** Enrichment hardcoded `overwriteExisting=true` and there was no user-locked flag on `songs`, so every enrichment run overwrote manually-edited BPM and key values.

**Bug 2 (regression from migration 20260827183550):** `update_song_metadata` with `p_allow_enrich_overwrite=FALSE` used fill-missing-only semantics for BPM/key, so manual edits on songs that *already had* a value silently failed — the stored value was never updated.

### Solution

Two new per-field boolean columns on `songs`:
- `bpm_manual_override BOOLEAN NOT NULL DEFAULT FALSE`
- `musical_key_manual_override BOOLEAN NOT NULL DEFAULT FALSE`

**Manual edit path** (`p_allow_enrich_overwrite=FALSE`): always writes the value and sets the flag. Fixes Bug 2.

**Enrichment path** (`p_allow_enrich_overwrite=TRUE`): skips the field if its flag is `TRUE`. Fixes Bug 1.

**Clearing a field** (`clear_song_metadata`): resets the flag to `FALSE`, allowing future enrichment to fill the field again.

All existing songs default to `FALSE` — no behavior change at deploy time.

### Changes

**Migrations:**
- `20260902120000`: `ADD COLUMN IF NOT EXISTS` for both override flags (schema-only, no behavior change)
- `20260902120001`: Rewrite `update_song_metadata` (eligibility guards, flag lifecycle) and `clear_song_metadata` (flag reset on field clear). Same signatures; existing grants re-asserted idempotently.

**Flutter:**
- `Song` model: two new `bool` fields (`bpmManualOverride`, `musicalKeyManualOverride`), default `false`, parsed from Supabase response
- `fetchSongsForBand`: new columns added to column select (orchestrator path only)
- `SongEnrichmentOrchestrator`: override guards added at both `needsBpm`/`needsKey` sites — locked songs report `EnrichmentFieldResult.unchanged` rather than calling the RPC

### Not Changed

- Enrichment selector UI (`overwriteExisting=true` is correct product behavior; DB flags now enforce correctness)
- `updateSongBpmOverride` / `updateSongMusicalKey` repository methods (already omit `p_allow_enrich_overwrite`, which now means always-write + set flag — no call-site changes needed)
- `SetlistSong` display model and all `setlist_songs` queries
- Duration/tuning fields (not enriched; no flags needed)

### Deploy Order

1. Migration `20260902120000` (schema)
2. Migration `20260902120001` (RPC logic)
3. Flutter build — all platforms simultaneously

### Verification

T1-5 and T1-6 (`has_function_privilege` grant checks) confirmed against live remote DB via `supabase db query --linked` — both functions: `authenticated=TRUE, anon=FALSE`. `flutter analyze` → 0 issues.
