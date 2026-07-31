# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/new-song-key-enrichment`

**Note on process:** `docs/agents/ARCHITECT.md` is written around a specific worked example (a notification-delivery bug) and its Phase 4 literally says "Load Notification Domain Reference" / read `docs/reference/notifications/`. That domain has no bearing on this feature. Per the outer task instructions, Phase 4 is adapted here to the actual domain: BPM/song-catalog/Spotify reference docs (`docs/reference/bpm/*.md`, `docs/reference/architecture/*.md`, `docs/reference/general/AI_DECISIONS.md`). `docs/reference/notifications/` was not read — this feature does not touch notifications. All other phases (0–13) were followed as written.

---

## 2. Problem Summary

BandRoadie's new-song lookup flow (search → select → song lands in the Catalog) does not retrieve musical key, and saves whatever metadata it finds with no user visibility or edit step. This is Phase 1 of a larger Song Data Enrichment initiative. Scope for this pass: add key retrieval (via a new provider, GetSongBPM) alongside the existing BPM path, and insert a review/edit screen — showing Duration, BPM, and Key as found/not-found, each editable — between "user taps a search result" and "song is written to the Catalog." Tuning, lyrics, existing-song enrichment, bulk actions, dual original/performance values, and a settings screen are explicitly out of scope.

**User impact today:** a song can land in the Catalog with a wrong or missing duration/BPM and the user has no chance to notice or fix it before it's saved; key is never populated automatically at all (it's a fully manual field today, see §5).

---

## 3. Root Cause / Baseline Confirmation

Not a bug — this is new functionality. Per Phase 3 ("if the input conflicts with codebase evidence, rely on the codebase and document the discrepancy"), the Feature Input's description of "today's" behavior was checked against the live codebase and **three material discrepancies were found**. These change the shape of the plan and are called out explicitly because they affect what's actually achievable in Phase 1.

**Confidence: HIGH for all three — each independently verified this session by direct code read, not inherited from the Feature Input.**

| # | Feature Input said | Codebase actually shows |
|---|---|---|
| 1 | "There is no key column ... yet" | `songs.musical_key TEXT` **already exists** (migration `20260630000000_add_musical_key_to_songs.sql`), is in the `Song`/`SetlistSong` models, is read on every song query, is writable via `update_song_metadata` RPC, and already has a full manual edit UI (key badge on song cards, tap-to-edit picker, CSV import, print template toggle — see `docs/features/song-card-key-badge-tap-edit/`, `docs/features/csv-import-comma-and-key/`, `docs/features/cleared-song-key-reverts/`). **No new key column is needed.** What's missing is *auto-population* of this existing field at lookup time, plus the review screen. |
| 2 | "User searches... via Spotify lookup... retrieves title/artist/album/duration/spotify_id... auto-fetches BPM via spotify_audio_features" | The **search results shown in the lookup overlay do not come from Spotify at all.** `ExternalSongLookupService._performExternalSearch()` (`lib/features/songs/external_song_lookup_service.dart`) queries the free **iTunes Search API** first, falling back to the `musicbrainz_search` Edge Function — neither of which is Spotify. The `spotify_search` Edge Function exists, is deployed, and is documented, but **is never invoked from any client code** (`grep -rn "spotify_search" lib/` returns zero results). Because of this, external search results never carry a `spotify_id`, so the existing `spotify_audio_features` BPM enrichment (`_attemptBpmEnrichment` → `_fetchSpotifyBpm` in `setlist_repository.dart:4220-4327`) is effectively dead code on the new-song path today — its one call site always passes `spotifyId: null`, so Strategy 1 never runs and enrichment silently gives up. `docs/reference/bpm/*.md` documents the original (Spotify-driven) design and was never updated after a later commit (`1122fa0 "Improve song lookup ranking with canonical artist boost and Spotify ordering"`) switched the primary search source to iTunes. This is the same class of doc/code drift already remediated once in `docs/features/stale-architecture-docs/` for a different subsystem. |
| 3 | (implicit) An ISRC is available from the current identity flow | **No ISRC is available anywhere.** Neither iTunes Search nor `musicbrainz_search`'s current implementation returns ISRC, there is no `isrc` column on `songs`, and no model field. `spotify_search`'s implementation also does not currently request/return `external_ids.isrc` even though the Spotify API can supply it. |

**What this means for the plan:** Tony's directive names Spotify as the existing identity source (title/artist/album/duration/spotify_id/ISRC) and GetSongBPM's ISRC-based match as the preferred (high-confidence) path. Given finding #2, there is currently no code path that produces an ISRC (or even a reliable `spotify_id`) at song-selection time to feed that high-confidence path — and see §6.4 below, GetSongBPM's own documented API does not expose an ISRC lookup type either. **Resurrecting/wiring `spotify_search` into the primary lookup flow to manufacture an ISRC is out of scope for this minimal Phase 1** — it would mean swapping a working, already-tuned ranking algorithm (iTunes + MusicBrainz, with cover/tribute filtering and popularity scoring) for a different search source, which is a materially larger and riskier change than "add key + review screen." This plan proceeds with the **title+artist(+duration) medium-confidence path only**; the ISRC/high-confidence tier is designed into the request shape (so it activates automatically if a real ISRC ever becomes available in a later phase) but is dormant today. This is flagged explicitly per the task instructions rather than silently dropped — **Tony should confirm this reduced scope is acceptable** (see §19 Open Question). It does not block proceeding; the core deliverable (BPM+key auto-fetch with review/edit before save) is fully achievable via the medium-confidence path alone.

---

## 4. Reference Docs Consulted

- `docs/reference/bpm/BPM_FEATURE_IMPLEMENTATION.md`, `BPM_FEATURE_DEPLOYMENT.md`, `BPM_QUICK_REFERENCE.md` — describe the original Spotify-driven design; **confirmed stale** per §3 finding #2 (kept as historical reference only, not relied on for current behavior).
- `docs/reference/architecture/database_schema.md` — confirmed current `songs` schema (§5).
- `docs/reference/architecture/supabase_functions.md` — confirmed deployed Edge Functions, auth model, secrets pattern.
- `docs/reference/general/AI_DECISIONS.md` — read in full; DECISION-002 (AcousticBrainz removal) confirms `acousticbrainz_bpm` must stay dead, not be resurrected (matches Feature Input directive). No other logged decision conflicts with this plan. This plan adds a new external service (GetSongBPM) — per the "Categories Requiring a Logged Decision" list at the bottom of that file, **a new AI_DECISIONS.md entry is required** (see §16, Engineer Task 1).
- `docs/agents/PROJECT_CONTEXT.md` — tech stack, file-size warnings on `setlist_repository.dart` / `setlist_detail_screen.dart`, RBAC, brand voice (superseded here per Feature Input's explicit no-🎸 instruction).
- `docs/features/song-card-key-badge-tap-edit/ARCHITECT_PLAN.md`, `docs/features/csv-import-comma-and-key/ARCHITECT_PLAN.md`, `docs/features/cleared-song-key-reverts/ARCHITECT_PLAN.md` — established that `musical_key` is a fully-shipped, tested field; used as the pattern reference for key handling.
- `docs/features/stale-architecture-docs/ARCHITECT_PLAN.md` — precedent for how this codebase has previously handled doc/code drift (document it, fix only what's in scope, flag the rest).
- Direct code reads (not docs, but load-bearing for this plan): `lib/features/songs/external_song_lookup_service.dart`, `lib/features/setlists/setlist_repository.dart` (relevant sections only — see §9), `lib/features/setlists/widgets/song_lookup_overlay.dart`, `lib/features/setlists/widgets/song_details_bottom_sheet.dart`, `lib/features/setlists/widgets/{bpm_input_dialog,duration_input_dialog,key_picker_bottom_sheet}.dart`, `lib/components/ui/segmented_button_group.dart`, `lib/features/setlists/models/song.dart`, `supabase/functions/spotify_search/index.ts`, `supabase/migrations/20260630000000_add_musical_key_to_songs.sql` and its two follow-up migrations, `lib/features/settings/settings_screen.dart`.

---

## 5. Existing System Analysis

### 5.1 Search / identity (today)

```
User types in Song Lookup overlay
  → ExternalSongLookupService.searchExternalSongs()
      → iTunes Search API (public, no auth) — PRIMARY
          on empty/error → musicbrainz_search Edge Function — FALLBACK
      → _rankResults(): title match + popularity + API-position + cover/tribute penalty scoring
  → SongLookupResult { title, artist, bpm: null, durationSeconds, albumArtwork, spotifyId: null, musicbrainzId?, source }
```
`bpm` is always `null` from iTunes; `musicbrainzId` is only set for MusicBrainz-sourced results; `spotifyId` is **never** set by any current search path.

### 5.2 Selection → save (today)

`song_lookup_overlay.dart:_handleExternalSongTap()`:
1. Calls `setlistRepository.upsertExternalSong(bandId, title, artist, bpm, durationSeconds, albumArtwork, spotifyId, musicbrainzId)` — **writes to `songs` immediately**, no review step.
2. Inside `upsertExternalSong` (`setlist_repository.dart:3295-3455`): if song doesn't exist, inserts it; if `bpm == null`, fires `_attemptBpmEnrichment()` fire-and-forget (Strategy 1: Spotify Audio Features via `spotifyId` — **always a no-op today** per §3 finding #2).
3. Calls `onSongAdded(songId, title, artist)` to add it to the current setlist.

No key is ever populated on this path — `musical_key` is simply never referenced in `upsertExternalSong`, even though the column, model field, and RPC support all exist (confirmed via `_createOrFindSong`, a *different* private method used by the CSV/bulk-import path, which does already handle `musicalKey` — see `setlist_repository.dart:4041-4197`).

### 5.3 Existing manual key/BPM/duration edit UI (reusable)

`song_details_bottom_sheet.dart` (edits an *existing* catalog song) already has exactly the editing primitives this feature needs, each in its own small, isolated file:
- `showBpmInputDialog()` (`bpm_input_dialog.dart`, 219 lines) — validated numeric BPM entry, returns `DialogCancelled | DialogCleared | DialogValue<int>`.
- `showDurationInputDialog()` (`duration_input_dialog.dart`, 205 lines) — mm:ss masked entry, same result-type pattern.
- `showKeyPickerBottomSheet()` (`key_picker_bottom_sheet.dart`, 174 lines) — picker over the canonical 24-key set (`C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B` and their `m` minor equivalents), returns `String?` (`''` = cleared).
- `SegmentedButtonGroup` (`lib/components/ui/segmented_button_group.dart`, 122 lines) — the exact "label + value, tap to edit" row layout already used for the BPM/Duration/Tuning/Key 4-up row in the existing sheet.

This is the reuse target for the new review screen (§6.2) — no new input widgets need to be built.

---

## 6. Proposed Solution

### 6.1 What changes, in one sentence

Insert a review/edit step between "user taps an external search result" and "song is written to the Catalog": fetch BPM + Key from a new GetSongBPM Edge Function (by title/artist, best-effort), show Duration/BPM/Key as found-or-not with the existing edit widgets, then save with whatever values the user confirms.

### 6.2 New review screen

New file `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` (modal bottom sheet, modeled directly on `song_details_bottom_sheet.dart`'s structure and the `SegmentedButtonGroup` row):

- Opens immediately when the user taps an **external** (not-yet-catalogued) search result — i.e. it replaces the *body* of `_handleExternalSongTap`, not `_handleSongTap` (existing in-Catalog songs are unaffected — tapping them still adds directly, no review step, per Feature Input scope: "new-song lookup").
- Shows title/artist/artwork (read-only, from the tapped search result) plus a 3-row `SegmentedButtonGroup`: Duration | BPM | Key.
  - **Duration**: pre-filled from the search result immediately (iTunes/MusicBrainz already supply this synchronously — no fetch needed). Shows "Not found" if the result had none. Editable via the existing `showDurationInputDialog`.
  - **BPM** and **Key**: start in a loading state, call the new enrichment service (§6.3) in `initState`, populate on response (or "Not found" on failure/timeout/no-match). Editable via the existing `showBpmInputDialog` / `showKeyPickerBottomSheet` **immediately**, even before the fetch resolves — a user who already knows the key shouldn't have to wait.
- **Save is never gated on the fetch completing.** If GetSongBPM is slow, down, or returns nothing, the user can save with blank BPM/Key exactly as today, or fill them in manually — this preserves the existing "BPM is a convenience, not a dependency" principle (`BPM_FEATURE_IMPLEMENTATION.md`) and satisfies the Feature Input's explicit "missing/low-confidence fields do not block saving."
- No provider name ("GetSongBPM") appears anywhere on this screen — matches Feature Input's "no provider names in primary UI."
- On Save: calls the extended `upsertExternalSong(..., musicalKey:, isrc: null, skipBackgroundEnrichment: true)` (§6.5), then the existing `onSongAdded` setlist-attach flow, unchanged.
- On Cancel: identical discard semantics to `song_details_bottom_sheet.dart`'s `_handleCancel` (no changes if nothing edited; confirm dialog if the user edited a field then backs out) — no new song is created.

Target size: this is a single-purpose sheet with ~3 fields; expect roughly 300-400 lines given the existing sheet's proportions, comfortably within the "Feature widgets: 400 lines" guardrail target.

### 6.3 New Dart service: enrichment client

New file `lib/features/songs/song_enrichment_service.dart` (mirrors `ExternalSongLookupService`'s shape — plain class wrapping `supabase.functions.invoke`, no state management dependency):

```dart
class SongEnrichmentResult {
  final int? bpm;
  final String? musicalKey; // normalized to the app's 24-key set, or null
  final String confidence;  // 'medium' | 'low' | 'none'
}

class SongEnrichmentService {
  Future<SongEnrichmentResult> lookup({
    required String title,
    required String artist,
    int? durationSeconds,
    String? isrc, // accepted for forward-compat; not populated by any caller today (see §3)
  });
  // Never throws. Returns confidence:'none' with null fields on any failure.
}
```

### 6.4 New Edge Function: `getsongbpm_lookup`

**Provider viability — GetSongBPM (per explicit instruction to verify before designing further):**

| Question | Finding | Confidence |
|---|---|---|
| Auth | Static `api_key` query param, no OAuth/token exchange. Free, requires only a registered email at getsongbpm.com/api. | High — consistent across all secondary sources checked |
| Rate limit | 3,000 requests/hour. Generous for this use case (one lookup per new-song save). | High |
| Endpoints | `GET https://api.getsongbpm.com/search/?api_key=...&type={song\|artist\|both}&lookup=...` for text search; a separate `/song/?api_key=...&id=...` / `/artist/?...&id=...` for direct ID lookup. | Medium — confirmed by two independent secondary sources (a maintained Perl client, a technical blog with a live example URL); the primary docs page at `getsongbpm.com/api` returned HTTP 403 to automated fetch and could not be read directly this session |
| Response fields | Song objects include `tempo` (BPM) and `key_of` (e.g. `"Em"`) — confirmed via a real example snippet. Exact full response envelope (nesting under `search`, artist sub-object shape, whether duration is included) **not fully confirmed**. | Medium |
| **ISRC-based lookup** | **Not found in any documented `type=` value.** Documented types are `artist`, `song`, `both`/`multi` — all name-based text search, not code-based. No evidence GetSongBPM exposes an ISRC endpoint. | Medium-high (absence of evidence, not proof of absence — the blocked primary-docs page is the one place this could be definitively confirmed or denied) |
| Attribution | **Mandatory.** Terms require a backlink to GetSongBPM.com in the app or website; explicitly enforced with account suspension for non-compliance. | High |
| Key notation | Example (`"Em"`) matches the app's existing 24-key set exactly (`key_picker_bottom_sheet.dart`) — but full enumeration of what GetSongBPM can return (e.g. enharmonic spellings like `D#` vs `Eb`, or Camelot notation) is not confirmed. | Low-medium |

**Verdict: GetSongBPM is viable for the medium-confidence title+artist path** (auth is simple and free, rate limit is a non-issue, the two fields this feature needs are confirmed to exist). **It is not viable for the ISRC/high-confidence path as originally envisioned** — both because nothing in the current app supplies an ISRC (§3) and because the API itself does not appear to support ISRC lookup. This is a reduced-scope pass, not an unworkable one — proceeding per the instruction that an unworkable provider means stop-and-report, and this one is workable, just not at the fidelity originally assumed. **Do not treat the remaining uncertainty (exact response envelope, full key-notation range, whether `both`/`multi` accepts a combined `song:artist` query) as resolved** — Engineer Task 1 (§16) is a mandatory live spike against the real API (with a real key Tony provides) to nail these down *before* writing the production Edge Function body, exactly as would be done for any newly-integrated third-party contract.

**Design** (Deno/TS, same shape as `spotify_search`/`musicbrainz_search` — `verify_jwt: true`, secret pulled from Supabase Vault via `get_secrets` RPC with env-var fallback, per `spotify_search/index.ts`'s existing pattern):

- Input: `{ title: string, artist: string, duration_seconds?: number, isrc?: string }`
- If `isrc` is present: **do not attempt an unverified ISRC query.** Log it (for future-phase telemetry) and fall through to the title+artist path. (If Engineer Task 1's live spike *does* turn up a working ISRC parameter, this is the one place in the whole plan where deviating from "as designed" is pre-approved — swap in the verified call, keep everything else identical. Otherwise leave as documented here.)
- Else: call `type=song&lookup=<title>` (exact query shape to be confirmed/adjusted in Engineer Task 1), filter results for an artist-name match (case-insensitive, normalized), score similarly to `_rankResults` in spirit but far simpler (this is disambiguation among a handful of candidates, not ranking a full search UI):
  - Exactly one candidate with a strong artist-name match → `confidence: 'medium'`, return its `tempo`/`key_of`.
  - Multiple candidates with no single clear artist match, or zero candidates → `confidence: 'none'`, return nulls (Feature Input: "flag for review rather than auto-filling" — Phase 1 satisfies this by simply not pre-filling; the field shows "Not found" and is manually editable, same as any other miss).
- **Key normalization is mandatory**: map GetSongBPM's `key_of` to the app's exact 24-key vocabulary (`C, C#, D, Eb, E, F, F#, G, Ab, A, Bb, B` / minor `m` suffix set), including common enharmonic equivalents (`D#`→`Eb`, `G#`→`Ab`, `A#`→`Bb`, and their minors). If the returned value can't be normalized to one of the 24, return `musicalKey: null` rather than passing through a string the app's key picker can't represent — this is a correctness requirement, not a nice-to-have, since an un-normalized value would silently corrupt the review screen's pre-selection.
- Never throws; any failure (network, 4xx/5xx, malformed response, missing secret) returns `{ ok: true, data: { bpm: null, musicalKey: null, confidence: 'none' } }` — same "never block, never surface a provider error to the user" contract as `spotify_audio_features`.
- Output: `{ ok: boolean, data?: { bpm: number|null, musicalKey: string|null, confidence: 'medium'|'none' }, error?: string }`

### 6.5 `upsertExternalSong` extension (`setlist_repository.dart`)

Add three optional parameters to the existing method (signature-additive, fully backward compatible — the method has exactly one caller today, confirmed via `grep -rn "upsertExternalSong(" lib/`):

```dart
Future<String?> upsertExternalSong({
  required String bandId,
  required String title,
  required String artist,
  int? bpm,
  int? durationSeconds,
  String? albumArtwork,
  String? spotifyId,
  String? musicbrainzId,
  String? musicalKey,              // NEW
  String? isrc,                    // NEW — always null from this caller today, see §3
  bool skipBackgroundEnrichment = false, // NEW
}) async { ... }
```

- Insert path: add `if (musicalKey != null && musicalKey.isNotEmpty) insertData['musical_key'] = musicalKey;` and the equivalent for `isrc`, mirroring the exact existing pattern for `spotifyId`/`musicbrainzId` at lines 3394-3398.
- Existing-song (conflict) update path: add the same "update missing fields only" conditional for `musical_key`/`isrc` mirroring lines 3343-3358 (never overwrite a non-null existing value — same non-destructive contract as every other field here).
- **`skipBackgroundEnrichment`**: when `true`, do not call `_attemptBpmEnrichment()` after insert. The new review flow already did BPM/key lookup synchronously before Save; firing the old fire-and-forget Spotify strategy afterward would be redundant today (harmless no-op, since `spotifyId` is still always null) but would become a **silent-overwrite bug** the moment any future phase starts supplying a real `spotifyId` — it could quietly refill a BPM value the user explicitly reviewed and left blank on purpose. Fixing this now, while touching this exact code path anyway, is cheap and directly serves "should not preclude future phases." The call site in `song_lookup_overlay.dart` passes `skipBackgroundEnrichment: true`. Default `false` preserves current behavior for any other/future caller.
- **`_attemptBpmEnrichment`/`_fetchSpotifyBpm` themselves are not modified or removed** — out of scope; they remain available as-is. (Whether they're worth deleting entirely as dead code is a reasonable follow-up, not part of this plan — no opportunistic cleanup.)

### 6.6 Attribution (minimal, non-per-song)

GetSongBPM's terms mandate a backlink "in your app or website." Per Feature Input's explicit instruction ("not inline per-song"), add one static, non-conditional line to `lib/features/settings/settings_screen.dart` (492 lines today — already over the 350-line container-widget guardrail target; this is a ~10-line addition, which GUARDRAILS.md explicitly permits for oversized files when "the change is minimal and does not worsen maintainability"): a tappable row/text — e.g. "Song tempo & key data via GetSongBPM.com" — opening `https://getsongbpm.com` via `url_launcher` (already a project dependency, already used identically in `song_details_bottom_sheet.dart:_openYouTubeLink`). No 🎸 emoji, no per-song badge, no mention of the provider anywhere else in the UI — matches both the attribution requirement and the "no provider names in primary UI" instruction simultaneously.

---

## 7. Database Impact

**Migration required: yes — one new additive column.**

New file `supabase/migrations/20260730120000_add_isrc_to_songs.sql`:

```sql
-- Add isrc column to songs table.
-- Nullable TEXT — International Standard Recording Code, intended as a future
-- high-confidence match key for external metadata providers. No CHECK constraint
-- (mirrors musical_key's precedent in 20260630000000_add_musical_key_to_songs.sql) —
-- format not enforced since not every source returns canonical ISRC formatting.
-- Not currently populated by any active code path — see
-- docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md §3/§6.5.
ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS isrc TEXT;

COMMENT ON COLUMN public.songs.isrc IS
  'International Standard Recording Code, when known. Nullable — accepted by upsertExternalSong() for forward compatibility but not populated by any active identity-lookup path as of 2026-07.';
```

**`musical_key`: no migration needed** — column, model field, RPC support, and RLS-safe write path already exist (§3 finding #1).

**RLS impact: none.** This is a nullable additive column on a table that already has RLS enabled and working; no new policy, no policy change, no new RPC. `isrc` is written exactly the way `spotify_id`/`musicbrainz_id` already are — through the existing client-side `insert`/`update` on `songs`, gated by the existing band-membership RLS policy (same code path, just two more optional keys in the map).

**`update_song_metadata` RPC: not modified.** `isrc` is not user-editable in this phase (no UI exposes it), so it doesn't need to flow through the manual-edit RPC — only through `upsertExternalSong`'s direct insert/update, same as `spotify_id` today.

**Affected / unaffected summary:**
| Area | Status |
|---|---|
| `songs` table | **Affected** — one new nullable column (`isrc`) |
| RLS policies | Unaffected |
| `update_song_metadata` RPC | Unaffected |
| Any other RPC | Unaffected |
| Existing rows | Unaffected — `isrc` defaults to `NULL`, no backfill |

---

## 8. Flutter Architecture Changes

- **State management:** no new provider/controller needed. The review sheet is a self-contained `StatefulWidget` (same pattern as `_SongDetailsSheet`), reads `setlistRepositoryProvider` via `ref.read` exactly once (on Save), same as the existing overlay does today. No Riverpod provider changes.
- **New service class:** `SongEnrichmentService`, plain Dart class (not a Riverpod provider) — matches `ExternalSongLookupService`'s existing pattern of being instantiated directly in the consuming widget's `initState` (`_externalService = ExternalSongLookupService(Supabase.instance.client);`).
- **Repository:** `SetlistRepository.upsertExternalSong()` gains three optional parameters (§6.5). No new repository class.
- **Widgets:** one new bottom sheet (`song_enrichment_review_sheet.dart`); `song_lookup_overlay.dart`'s `_handleExternalSongTap` changes to open it instead of upserting directly.

---

## 9. Files to Create

| File | Justification |
|---|---|
| `supabase/migrations/20260730120000_add_isrc_to_songs.sql` | New `songs.isrc` column (§7) |
| `supabase/functions/getsongbpm_lookup/index.ts` | New provider integration; must be server-side per Feature Input directive (holds `GETSONGBPM_API_KEY`) — same reasoning as every existing `spotify_*`/`musicbrainz_*` function |
| `supabase/functions/getsongbpm_lookup/deno.json` | Sibling config file, same as `spotify_search/deno.json` and `musicbrainz_search/deno.json` |
| `lib/features/songs/song_enrichment_service.dart` | New client for the new Edge Function; mirrors `ExternalSongLookupService`'s existing shape (§6.3) — keeps `setlist_repository.dart` from growing further (see Files Off-Limits) |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | The review/edit screen itself (§6.2) — new, isolated file, not an addition to `setlist_detail_screen.dart` or `song_details_bottom_sheet.dart` |

---

## 10. Files to Modify

| File | Changes |
|---|---|
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | `_handleExternalSongTap()`: instead of calling `upsertExternalSong` + `onSongAdded` directly, open `song_enrichment_review_sheet.dart` with the tapped `SongLookupResult`; on confirmed Save, call the extended `upsertExternalSong(..., musicalKey:, isrc: null, skipBackgroundEnrichment: true)` then the existing `onSongAdded`. `_handleSongTap()` (in-Catalog results) is **unchanged**. |
| `lib/features/setlists/setlist_repository.dart` | Surgical addition only, inside the existing `upsertExternalSong` method (§6.5): 3 new optional params, 2 new conditional map assignments in the insert path, 2 in the update-existing path, 1 new guard around the `_attemptBpmEnrichment` call. No other part of this 4,027-line file is touched. |
| `lib/features/settings/settings_screen.dart` | One new static, non-conditional attribution row (§6.6) |
| `docs/reference/architecture/supabase_functions.md` | Add `getsongbpm_lookup` row to the Deployed Edge Functions table and the Required Secrets table (`GETSONGBPM_API_KEY`) — keeps this doc from immediately going stale the way `docs/reference/bpm/*.md` already has (§3 finding #2); small, directly-relevant, low-risk doc update |
| `docs/reference/general/AI_DECISIONS.md` | New `[DECISION-004]` entry — new external service added to the stack requires a logged decision per that file's own "Categories Requiring a Logged Decision" list |

---

## 11. Files Off-Limits

| File | Reason |
|---|---|
| `lib/main.dart` | Init order must not change; unrelated to this feature |
| `lib/features/setlists/setlist_detail_screen.dart` (2,788 lines) | Not touched — the review screen is reached only from the new-song lookup overlay, never from the existing-song detail/edit flow this file owns |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Existing-song manual edit flow is unchanged; this feature only affects the *new*-song path |
| `lib/features/songs/external_song_lookup_service.dart` | Search source (iTunes + MusicBrainz) is deliberately left as-is — not resurrecting `spotify_search` for identity/ISRC in this phase (§3) |
| `supabase/functions/spotify_search/*`, `supabase/functions/spotify_audio_features` (deployed, no local source) | Untouched — unrelated to GetSongBPM integration; `spotify_audio_features` continues to exist as dormant Strategy 1 code in `_attemptBpmEnrichment`, now explicitly bypassed (not deleted) on the reviewed-save path per §6.5 |
| `supabase/functions/acousticbrainz_bpm/*` | Confirmed dead per DECISION-002 and Feature Input directive — do not touch, do not resurrect |
| `lib/features/setlists/models/song.dart`, `lib/features/setlists/models/setlist_song.dart` | `musicalKey` field already exists on both; `isrc` is not added to these models in Phase 1 (it's written but not read/displayed anywhere in the UI — no model field needed until a future phase surfaces it) |
| `supabase/migrations/20260630000001_add_musical_key_to_update_song_rpc.sql`, `20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` (and the RPC they define) | `update_song_metadata` is not modified — `isrc` doesn't flow through it in this phase (§7) |

---

## 12. System Impact Map

| System | Impact |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — new-song lookup/save flow gains a review step; existing setlists/songs untouched |
| Members / RBAC | unaffected — same insert/update path, same RLS gate as today |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected** — shared Flutter UI code, all four platforms get the review screen identically; no platform-specific branching needed (Edge Function call is platform-agnostic, same as existing Spotify/MusicBrainz calls) |

---

## 13. Regression Risk

**Level: LOW-MEDIUM**

**Toward LOW:**
- New schema change is a single nullable column addition with no constraint, no RLS change, no RPC signature change — the safest possible migration shape (same shape as the already-shipped `musical_key` addition).
- `upsertExternalSong` changes are additive/optional parameters only; the one existing caller is being updated in the same PR, so there's no dangling old-signature caller.
- New Edge Function is entirely new surface — cannot regress any existing function.
- New review sheet is a new file; existing `song_details_bottom_sheet.dart` (existing-song edit) is untouched.
- Save is never blocked by the new fetch — matches existing "BPM is a convenience" principle, no new failure mode that can break song creation.

**Toward MEDIUM (why not LOW):**
- This changes the **primary interaction shape** of adding a new song from search — previously one tap = song added; now one tap = review screen = second tap to confirm. This is a deliberate, requested UX change, but it is the single highest-visibility change in the plan and the one most likely to surprise users if the review screen has any friction (e.g., feels like an extra required step even though it's fast).
- `getsongbpm_lookup`'s exact request/response contract has residual uncertainty (§6.4) — Engineer Task 1's live spike could surface a contract different enough from what's designed here to require adjusting the Edge Function mid-implementation. This is contained (Edge Function is new/isolated, can't break existing behavior even if the spike changes its internals), but it's real uncertainty going into implementation, not a fully closed spec.
- Touches `setlist_repository.dart`, a 4,027-line file with known "silent error swallowing" debt noted in `PROJECT_CONTEXT.md` — the change here is small and localized, but any touch to this file carries slightly elevated review burden.

No auth, session, routing, or init-order changes. No shared code path with notifications, gigs, or rehearsals.

---

## 14. Engineer Task Breakdown

Execute in order. Task 1 gates Tasks 4-6 — do not write the Edge Function body against assumed request/response shapes without completing Task 1 first.

1. **Live API spike (blocking, do first).** Using a real GetSongBPM API key (Tony to provide — see §17 prerequisite), make direct HTTPS calls (`curl` or a scratch script, not yet inside the Edge Function) against `https://api.getsongbpm.com/search/?api_key=...&type=song&lookup=<test title>` for 3-5 known songs. Confirm: exact response envelope shape, whether `type=both`/`multi` with a combined query is real and how it's formatted, whether duration is present in results, the actual range of `key_of` notations returned (test at least one sharp-key and one flat-key song to check enharmonic spelling), and whether any ISRC-shaped parameter is accepted (try `type=isrc` or an `isrc=` param defensively — if it 400s/404s, that confirms §6.4's finding; if it works, note the exact shape and use it). Write findings as a short comment block at the top of the new Edge Function file. If the API turns out to not exist as documented, or the free tier is gated differently than found here, **stop and report back to Tony before proceeding** — do not substitute a different provider.
2. Add `[DECISION-004]` to `docs/reference/general/AI_DECISIONS.md` documenting the new GetSongBPM external service, following the existing entry format, referencing this plan.
3. Write and apply migration `20260730120000_add_isrc_to_songs.sql` (§7).
4. Create `supabase/functions/getsongbpm_lookup/` (index.ts + deno.json), incorporating Task 1's confirmed contract. Implement per §6.4: request shape, artist-match disambiguation, key normalization to the app's 24-key set, `confidence` field, never-throws error handling matching `spotify_search`'s try/catch structure.
5. Deploy the function (`supabase functions deploy getsongbpm_lookup`) and set the secret (`supabase secrets set GETSONGBPM_API_KEY=...`) — Tony must supply the key (§17).
6. Update `docs/reference/architecture/supabase_functions.md` with the new function's row (§10).
7. Create `lib/features/songs/song_enrichment_service.dart` (§6.3) calling the new function, never throwing, always returning a `SongEnrichmentResult`.
8. Create `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` (§6.2), reusing `SegmentedButtonGroup`, `showBpmInputDialog`, `showDurationInputDialog`, `showKeyPickerBottomSheet` exactly as `song_details_bottom_sheet.dart` does. No 🎸 emoji anywhere in copy (Feature Input directive overrides `PROJECT_CONTEXT.md`'s brand-voice example for this feature).
9. Extend `setlist_repository.dart`'s `upsertExternalSong()` per §6.5 (additive params, insert/update map entries, `skipBackgroundEnrichment` guard). Do not touch any other method in this file.
10. Wire `song_lookup_overlay.dart:_handleExternalSongTap()` to open the review sheet and pass its result into the extended `upsertExternalSong` call (§10). Confirm `_handleSongTap()` is untouched.
11. Add the attribution row to `lib/features/settings/settings_screen.dart` (§6.6).
12. Run `flutter analyze` — 0 errors before proceeding.
13. Manual verification per §15.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (before `supabase db push` / before the migration is applied)

- **PRE-DEPLOY TEST 1:** Confirm `isrc` does not already exist (guards against re-running an already-applied migration silently succeeding for the wrong reason):
  ```sql
  SELECT column_name FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name = 'isrc';
  -- Expected: 0 rows, before migration
  ```
- **PRE-DEPLOY TEST 2:** Confirm `musical_key` already exists and is untouched by this change (baseline, no schema drift assumption):
  ```sql
  SELECT column_name, data_type FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name = 'musical_key';
  -- Expected: 1 row, data_type = 'text' — unchanged by this migration
  ```
- **PRE-DEPLOY TEST 3:** Confirm `update_song_metadata`'s current signature (11 params, includes `p_musical_key`, does not include `p_isrc`) — this RPC is not touched, so its current shape *is* the expected post-deploy shape too:
  ```sql
  SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'update_song_metadata';
  -- Expected: signature unchanged, no p_isrc parameter
  ```
- These are runnable against the live schema with zero changes applied — none depend on the new migration or new Edge Function.

### Tier 2 — Post-deployment (after migration + Edge Function deploy)

- **POST-DEPLOY TEST 1:** Confirm the new column exists with correct type/nullability:
  ```sql
  SELECT column_name, data_type, is_nullable FROM information_schema.columns
  WHERE table_name = 'songs' AND column_name = 'isrc';
  -- Expected: 1 row, data_type = 'text', is_nullable = 'YES'
  ```
- **POST-DEPLOY TEST 2:** Confirm no existing row was touched by the migration (additive-only sanity check):
  ```sql
  SELECT COUNT(*) FILTER (WHERE isrc IS NOT NULL) AS non_null_isrc, COUNT(*) AS total
  FROM songs;
  -- Expected: non_null_isrc = 0 immediately post-deploy (no backfill occurred)
  ```
- **POST-DEPLOY TEST 3:** `getsongbpm_lookup` Edge Function invocation smoke test (Supabase dashboard "Invoke" or `curl` with a real user JWT) for a well-known song — confirm `ok: true` and a plausible `bpm`/`musicalKey`, and separately for a nonsense title/artist — confirm graceful `confidence: 'none'`, not an error/exception.

### Manual end-to-end verification (Tony to run — per instruction, this must be an actually-runnable manual check)

1. Open any band's setlist or Catalog → tap "+ Add Song" → Song Lookup overlay.
2. Search for a well-known song not already in this band's Catalog (e.g. an artist/title you're confident isn't already there).
3. Confirm results appear under "External Results" (not "In Catalog").
4. Tap an external result → **confirm the new review screen opens** (does not immediately add the song).
5. Confirm Duration shows a value (from search) or "Not found"; confirm BPM and Key show a brief loading state, then either a found value or "Not found."
6. Edit at least one field (e.g. tap Key, pick a different key) — confirm the edit sticks in the review screen.
7. Tap Save — confirm the overlay closes, the song is added to the current setlist, and a success message appears (no provider name mentioned).
8. Open the song's card in Catalog — confirm the edited/found Duration, BPM, and Key values are all present and match what was shown/edited in the review screen.
9. Repeat steps 2-4 with a very obscure/made-up title unlikely to be in GetSongBPM's database — confirm BPM/Key both resolve to "Not found," the screen does not hang or error, and Save still works with blank BPM/Key (non-blocking requirement).
10. Check Settings screen — confirm the new GetSongBPM attribution line is present, tappable, and opens the correct URL; confirm it appears nowhere else in the app (no per-song badge, no provider name on the review screen or song cards).
11. Tap an **In-Catalog** search result (not external) — confirm it still adds directly with no review screen (regression check on the unchanged path).

---

## 16. QA Regression Areas

1. **New-song review flow:** all steps in §15's manual verification, on at least one native platform (iOS or Android) and web, per `PROJECT_CONTEXT.md`'s platform-differences caution.
2. **In-Catalog tap path (unchanged):** tapping an existing catalog song in the lookup overlay still adds directly with no review screen — this is the regression most likely to be silently broken by a careless edit to `_handleSongTap` vs `_handleExternalSongTap`.
3. **CSV/bulk import path (unchanged):** confirm `_createOrFindSong` (the separate method CSV import uses) still works and still handles `musicalKey` correctly — this plan does not touch that method, but QA should confirm it wasn't accidentally affected by the `upsertExternalSong` edits nearby in the same file.
4. **Existing manual key/BPM/duration editing** (`song_details_bottom_sheet.dart`, unrelated file): confirm tap-to-edit on an existing catalog song still works exactly as before — regression check that nothing in the shared dialog widgets (`bpm_input_dialog.dart` etc.) was altered by being reused in the new sheet.
5. **Non-blocking save:** with network throttled/offline for the Edge Function call specifically (if testable) or by temporarily using a bad API key, confirm the review screen still lets the user save with blank BPM/Key rather than hanging or erroring.
6. **Duplicate-song race:** search and add the same new song from two rapid taps / two devices — confirm the existing unique-constraint race handling in `upsertExternalSong` (`PostgrestException code 23505`) still resolves to a single song, now also carrying `musical_key`/`isrc` from whichever request won.
7. **Attribution line:** present, correct URL, doesn't regress unrelated Settings screen content.
8. **`flutter analyze`:** 0 errors.

---

## 17. Rollout / Migration Strategy

**Prerequisite (Tony, before Engineer starts Task 4+):** Register at getsongbpm.com/api, obtain an API key. This cannot be done by an agent — it requires a real email registration per GetSongBPM's terms.

1. Engineer completes Task 1 (live spike) using that key locally/via `curl` — does not require deploying anything yet.
2. `supabase db push` — applies the new `isrc` column. Safe, additive, no downtime, no data risk (matches the already-proven `musical_key` migration shape).
3. `supabase secrets set GETSONGBPM_API_KEY=... --project-ref nekwjxvgbveheooyorjo`.
4. `supabase functions deploy getsongbpm_lookup --project-ref nekwjxvgbveheooyorjo`.
5. Deploy Flutter app changes via `./tools/deploy_web.sh` (web) / normal store/TestFlight process (iOS/Android/macOS) — standard for this repo, no special sequencing needed since the new Edge Function and column can exist before the client ships (client that doesn't call them yet = no-op; no version-skew risk).
6. Post-deploy: run §15 Tier 2 tests, then the manual end-to-end check.

**Rollback:** Flutter changes revert via normal git revert (no data written by the new UI is destructive — worst case, some songs saved during the window have `isrc = NULL`, which is the pre-existing default anyway). Edge Function can be deleted/disabled without breaking anything else (no other function or client code depends on `getsongbpm_lookup`). The `isrc` column can remain even if the feature is rolled back — same reasoning as the existing BPM feature's rollback plan ("column can remain, no need to drop").

---

## 18. Out of Scope

Explicitly not part of this pass (per Feature Input and this plan's own scope discipline):

1. Tuning and lyrics enrichment.
2. Enrichment for existing songs already in the Catalog (single or bulk).
3. "Enrich All Songs" catalog-wide action with progress/summary.
4. Original-vs-performance dual values for BPM/key/tuning.
5. Data-source settings screen.
6. Resurrecting/wiring `spotify_search` into the primary identity flow to manufacture a real ISRC (§3) — flagged as a possible follow-up, not built here.
7. Adding ISRC support to `musicbrainz_search` (MusicBrainz recordings do carry ISRC data; the current Edge Function doesn't request it) — a cheaper possible path to a real ISRC than resurrecting Spotify, but still a separate change with its own scope, not bundled into this plan.
8. Fully de-staling `docs/reference/bpm/*.md` (§3) — only the one directly-relevant doc (`supabase_functions.md`) is updated here; the deeper narrative rewrite of the BPM feature docs is flagged, not fixed, matching the precedent in `docs/features/stale-architecture-docs/`.
9. Deleting the now-further-dormant `_attemptBpmEnrichment`/`_fetchSpotifyBpm` Spotify strategy code — bypassed on the new reviewed-save path (§6.5), not removed.
10. Any change to `acousticbrainz_bpm` (stays dead per DECISION-002).

---

## 19. Open Question for Tony (does not block starting Engineer work on Tasks 1-3)

Per §3, the "prefer ISRC-based lookup (high confidence)" tier of the directive is currently unreachable — no code path in the app produces an ISRC, and GetSongBPM's documented API doesn't appear to expose ISRC lookup either. This plan proceeds with medium-confidence (title+artist) matching only, with the ISRC parameter wired through end-to-end but dormant, so it activates automatically if a real ISRC source appears in a later phase. **Please confirm this is acceptable for Phase 1**, or indicate if you'd rather fold in the MusicBrainz-ISRC option (Out of Scope #7) now instead of later — that would be a scope addition to this plan, not a blocker to starting the rest of it.
