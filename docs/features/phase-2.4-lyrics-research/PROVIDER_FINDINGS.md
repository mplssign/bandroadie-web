# Lyrics Provider Research — Phase 2.4

**Date:** 2026-08-10  
**Research Context:** Evaluate candidate lyrics/chord data providers for ChordPro-compatible integration

---

## Executive Summary

**Recommendation:** **No viable automatic chord provider found for production launch.** Recommend **manual-entry-only** lyrics system with ChordPro format for Phase 2.4. The "chords on/off toggle" would control visibility of manually-entered chord annotations only — no auto-populated chord data.

**Key Finding:** No researched provider offers:

1. A legal, documented public API for commercial use
2. Lyrics text with inline chord annotations (ChordPro-ready)
3. Reasonable licensing terms for a paid/freemium app

All candidate providers either lack chord data entirely (lyrics-only), have no public API (requires scraping with high legal/ToS risk), or have prohibitive licensing restrictions for commercial apps.

**Fallback Strategy:**

- **Retrofit existing lyrics feature** (shipped v1.1.7, touched in PR #49) to support ChordPro format
- Migrate `songs.lyrics` storage from JSON (current `LyricsData`/`LyricsBlock` model with section highlights) to plain-text ChordPro
- Add ChordPro parsing to existing lyrics viewer to render `[Chord]` annotations above lyrics text
- Add chords-on/off toggle to lyrics viewer (shows/hides inline chord annotations)
- Consider Phase 2.5 optional: lyrics-only provider (e.g., Musixmatch) for **text-only** auto-fetch, with chords always manual

**⚠️ Breaking Change:** Existing lyrics feature uses JSON with section-level formatting (`LyricsHighlight` enum: verse/chorus/bridge with color tints). ChordPro has no equivalent for this formatting — migration will lose or require conversion strategy for existing section highlights.

---

## Research Methodology

For each provider, evaluated:

1. **Chord data availability:** Returns chords at all? Inline/aligned with lyrics or separate?
2. **ChordPro compatibility:** Data format requires conversion? Feasibility?
3. **API access model:** Public API? Auth model? Rate limits?
4. **Licensing/ToS:** Commercial use permitted? Attribution requirements? Scraping policy?
5. **Catalog coverage:** Breadth for typical cover-band repertoire (classic rock, pop, country)

Sources: Official API docs, developer ToS, public GitHub integrations, community discussions (Reddit, Stack Overflow), and provider privacy/terms pages as of August 2026.

---

## Provider Evaluations

### 1. Musixmatch

**Verdict:** **NOT VIABLE** for chord data (lyrics-only provider)

**Findings:**

| Criterion            | Assessment                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chord data**       | ❌ None — lyrics text only. No chord annotations, no timing data for alignment                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| **API access**       | ✅ Public REST API (`api.musixmatch.com`) — requires free developer key from developer.musixmatch.com                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| **Rate limits**      | Free tier: 2,000 requests/day; 500 lyrics.get calls/day                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| **Licensing**        | ⚠️ **Commercial restrictions:** ToS commercial-use restriction confirmed directionally via public documentation summaries (exact section number not independently verified — verify against developer.musixmatch.com before relying on this in a legal/licensing decision). Prohibits "Commercial Use" without a paid partnership. "Commercial Use" explicitly includes apps with in-app purchases or subscriptions. Free tier limited to personal/educational projects. Paid partnership pricing not publicly listed — requires enterprise contact. |
| **Attribution**      | ✅ Required — "Lyrics powered by Musixmatch" with clickable logo (design guidelines in API docs)                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Catalog coverage** | ✅ Excellent — 14M+ songs (largest lyrics database globally), strong for mainstream/classic rock/pop/country                                                                                                                                                                                                                                                                                                                                                                                                                                         |

**API Endpoints:**

- `matcher.lyrics.get` — lyrics via title+artist match
- `track.lyrics.get` — lyrics via Musixmatch track ID
- Response includes: `lyrics_body` (plain text), `lyrics_copyright`, `lyrics_language`
- **No** `chords`, `chord_annotations`, or `chord_pro` fields in any documented response shape

**Use Case for BandRoadie:**  
Could be used for **lyrics text only** in a future "Phase 2.5 — Lyrics Text Auto-Fetch" if licensing resolved (paid partnership or free-tier-only release model). Chords would remain 100% manual-entry.

**References:**

- API Docs: https://developer.musixmatch.com/documentation
- ToS Commercial Use restrictions: https://about.musixmatch.com/apiterms (section number unverified)

---

### 2. Ultimate Guitar (ultimateguitar.com)

**Verdict:** **NOT VIABLE** — No public API; scraping explicitly prohibited by ToS

**Findings:**

| Criterion            | Assessment                                                                                                                                                                                                                                                                                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chord data**       | ✅ Extensive — tabs/chords for 1.6M+ songs, includes ChordPro-like plain-text format with `[Am]`, `[C]` inline annotations                                                                                                                                                                                                                                       |
| **API access**       | ❌ **No public API.** Mobile apps use undocumented private GraphQL API (requires reverse-engineering). Several community scraper projects exist (GitHub: `ugs-scraper`, `ultimate-guitar-scraper-api`) but all rely on HTML parsing or intercepted mobile API calls.                                                                                             |
| **Rate limits**      | N/A (no official API)                                                                                                                                                                                                                                                                                                                                            |
| **Licensing/ToS**    | ❌ **Scraping explicitly prohibited.** ToS §6.3 ("Restrictions") limits access to personal, non-commercial use only. ToS §6.4 ("Intellectual Property Rights") bans reverse-engineering, capturing/storing content, redistribution, and any commercial exploitation. Community scrapers operate in gray area — no legal cases found, but ToS violation is clear. |
| **Catalog coverage** | ✅ Excellent — best chord catalog for guitar-based covers (classic rock, metal, folk, country standards)                                                                                                                                                                                                                                                         |

**Why it's tempting but risky:**  
Ultimate Guitar's chord transcriptions are exactly what BandRoadie needs (plain-text format, inline annotations, aligned with lyrics), and community scrapers demonstrate technical feasibility. However:

- **Legal risk:** ToS violation = grounds for cease-and-desist, API blocking, or litigation if BandRoadie scaled
- **Stability risk:** Undocumented API changes with no notice; HTML structure changes break scrapers constantly (observed in GitHub issue trackers for existing scrapers)
- **Ethical:** Ultimate Guitar's business model is ad-supported + Pro subscriptions; scraping circumvents this

**Architect decision:** Do not recommend scraping-based integration. If Ultimate Guitar launches a paid developer API in the future, re-evaluate.

**References:**

- Ultimate Guitar ToS: https://www.ultimate-guitar.com/about/tos.htm (§6.3, §6.4)
- Community scraper examples (educational reference only):
  - https://github.com/masterT/ultimate-guitar-scraper
  - https://github.com/arthurdenner/ultimate-guitar-scraper-api

---

### 3. Chordie (chordie.com)

**Verdict:** **NOT VIABLE** — No public API; limited chord accuracy/coverage

**Findings:**

| Criterion            | Assessment                                                                                                                                                                                                                                                           |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chord data**       | ⚠️ Yes, but **quality inconsistent** — Chordie aggregates chord sheets from multiple sources (Ultimate Guitar, E-Chords, etc.) with user-submitted corrections. Formatting varies widely (some ChordPro-like, some not). Many entries are low-quality or incomplete. |
| **API access**       | ❌ No public API documented. Site appears to use server-side rendering (not a modern REST/GraphQL API). No developer portal or terms.                                                                                                                                |
| **Catalog coverage** | ⚠️ Moderate — claims 1M+ songs, but many are duplicates or variants. Coverage weaker than Ultimate Guitar for mainstream repertoire.                                                                                                                                 |
| **Licensing/ToS**    | ❌ Ambiguous — no clear developer terms; appears to aggregate content from other sites (potential secondary copyright issues).                                                                                                                                       |

**Why it's not recommended:**  
Even if scraping were legally/technically feasible, Chordie's inconsistent quality and lack of authoritative chord data make it a poor choice for a production app where users expect reliable metadata. Acts more as a search aggregator than a primary data source.

---

### 4. Songsterr (songsterr.com)

**Verdict:** **NOT VIABLE** — No public API; proprietary tab player format (not ChordPro)

**Findings:**

| Criterion            | Assessment                                                                                                                                                                                                                                     |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Chord data**       | ⚠️ Yes, but **locked in proprietary format** — Songsterr provides interactive, note-for-note guitar tabs (not simple chord sheets). Data is in a custom binary/JSON format tied to their web player, not exportable as ChordPro or plain-text. |
| **API access**       | ❌ No public API. Mobile apps use undocumented private API. Community projects exist (e.g., `songsterr-api-node`) but rely on reverse-engineering.                                                                                             |
| **Catalog coverage** | ✅ Good for note-level tabs, weaker for simple "campfire chord sheets" which is what most cover bands need.                                                                                                                                    |
| **Licensing/ToS**    | ❌ Scraping prohibited (standard "no automated access" clause). Tabs licensed from publishers; redistribution forbidden.                                                                                                                       |

**Why it's not a match:**  
Songsterr is a **tab player**, not a chord-sheet provider. Their data model is instrument-specific (guitar/bass/drums tracks) and far more granular than BandRoadie's needs. Extracting simplified "chords over lyrics" would require complex parsing and wouldn't align with their licensing model.

---

### 5. ChordPro Native Databases / Open-Source Collections

**Verdict:** **VIABLE WITH SEVERE CAVEATS** — Technically possible but tiny catalogs

**Findings:**

Searched for:

- Open ChordPro file repositories (GitHub, SourceForge)
- Community-maintained ChordPro databases
- Public domain / Creative Commons chord collections

**What exists:**

- **Small hobbyist collections:** GitHub repos with 50-500 songs (e.g., `chordpro-songs`, `christian-chordpro-songs`). Often niche (hymns, folk standards, worship music).
- **LilyPond / ABC notation archives:** Music notation formats, not ChordPro (wrong use case).
- **OLGA archives (historical):** On-Line Guitar Archive shut down in 2006 due to copyright lawsuits; mirrors exist but legal status unclear.

**Why not viable for Phase 2.4:**

- **Catalog too small:** Even the largest open collections have <1% of a typical cover band's repertoire.
- **No centralized API:** Would require bundling files in-app (1M+ songs = gigabytes) or hosting a custom API.
- **Copyright risk:** Most contain copyrighted songs transcribed without permission (fair use defense untested for this context).

**Possible future use:** Could seed a "community-contributed ChordPro library" feature where bands share chord sheets peer-to-peer (with explicit copyright disclaimer). Out of scope for Phase 2.4.

---

### 6. Other Investigated Options

#### 6.1 Chordify (chordify.net)

- **Business model:** Freemium web app that auto-detects chords from YouTube/SoundCloud audio via AI
- **API:** None public (web app only)
- **Chord data:** Available as on-screen overlays; not exportable as ChordPro
- **Licensing:** Subscription service ($4-6/month) — chord data tied to user account, no bulk export or API for third-party apps
- **Verdict:** NOT VIABLE (no API, no export)

#### 6.2 MuseScore (musescore.com)

- **Content:** Sheet music in MusicXML format (not chord sheets)
- **Use case mismatch:** BandRoadie users need simple chord-over-lyrics, not full notation
- **API:** Public API exists but for sheet music metadata/rendering, not chord extraction
- **Verdict:** NOT VIABLE (wrong format)

#### 6.3 Genius (genius.com)

- **Content:** Lyrics + annotations (cultural/meaning notes)
- **Chord data:** ❌ None — pure lyrics, no musical metadata
- **API:** Public API exists (`api.genius.com`) — lyrics text only
- **Licensing:** Similar to Musixmatch — free tier for non-commercial use; commercial requires partnership
- **Verdict:** NOT VIABLE for chords (same as Musixmatch — could be lyrics-only fallback)

---

## Realistic Fallback: Retrofit Existing Lyrics Feature for ChordPro

⚠️ **Important Context:** BandRoadie **already has a shipped, mature lyrics feature** (v1.1.7, most recently touched in PR #49). Phase 2.4 is a **retrofit/migration task**, not greenfield construction.

**Current lyrics implementation:**

- **Data model:** `LyricsData`/`LyricsBlock` JSON stored in `songs.lyrics` (TEXT column)
- **Editor:** Full-screen `lyrics_editor_sheet.dart` with formatting toolbar (font size, bold, section highlighting)
- **Viewer:** `lyrics_view_screen.dart` with auto-scroll, font size adjustment, section-based rendering
- **Section formatting:** `LyricsHighlight` enum (intro/verse/pre-chorus/chorus/bridge/outro) with colored background tints and labels
- **No chord support:** Lyrics text only — no `[Chord]` annotations, no chord display

**Phase 2.4 retrofit scope:**

1. **Migrate storage format:** JSON (current) → plain-text ChordPro
   - Current: `{"blocks": [{"text": "...", "highlight": "verse", "fontSize": 22}]}`
   - Target: `[Am]When you try your [C]best but you [G]don't succeed`
2. **Adapt existing editor:** Update `lyrics_editor_sheet.dart` to edit plain-text ChordPro (strip formatting toolbar, add ChordPro syntax helper)
3. **Enhance existing viewer:** Add ChordPro parser to `lyrics_view_screen.dart` to render `[Chord]` above aligned lyrics text
4. **Add chords-on/off toggle:** New switch control in viewer — shows/hides `[Chord]` annotations
5. **Storage:** Plain-text ChordPro string in existing `songs.lyrics` TEXT column

### Critical Issue: Loss of Existing Formatting

⚠️ **Architect Decision Required:**

The current `LyricsHighlight` block-level formatting (verse/chorus/bridge with color tints) has **no equivalent in ChordPro's plain-text format**. ChordPro supports section labels (`{start_of_chorus}`, `{end_of_chorus}`) but these are semantic markers, not color/formatting metadata.

**Migration strategy options:**

1. **Lossy conversion (simplest):**
   - Parse existing JSON blocks
   - Concatenate `text` fields with double-newline separators
   - Discard formatting metadata (fontSize, fontWeight, highlight)
   - Write back as plain text
   - **Trade-off:** Users who entered formatted lyrics lose section colors/labels

2. **Partial preservation via ChordPro section labels:**
   - Map `LyricsHighlight.verse` → `{start_of_verse}` / `{end_of_verse}` directives
   - Map `chorus`, `bridge`, etc. similarly
   - Preserve semantic structure, but lose color tints (ChordPro viewers typically don't color sections)
   - **Trade-off:** More complex migration logic; ChordPro directives clutter plain text

3. **Dual-format storage (most complex, not recommended):**
   - Keep JSON in `songs.lyrics`, add new `songs.chordpro` column
   - UI chooses format based on presence of chords
   - **Trade-off:** Schema complexity, two code paths, unclear user model

**Recommendation for Architect:** Use **lossy conversion (Option 1)** with advance notice in release notes. BandRoadie's model is band-coordinated editing — if formatting is important, bands can re-enter it manually. Prioritize ChordPro compatibility over backward compatibility for a niche formatting feature.

### What "Retrofit" Means for Implementation

**Reuse existing UI patterns:**

- **Editor:** Adapt `lyrics_editor_sheet.dart` (already full-screen, save/cancel, text input)
  - Remove: Formatting toolbar (font size ±, bold, highlight color chips)
  - Add: ChordPro syntax helper (tooltip or help button)
  - Keep: Full-screen modal presentation, save/cancel flow
- **Viewer:** Adapt `lyrics_view_screen.dart` (already full-screen, auto-scroll, font size)
  - Remove: Section-based rendering with colored highlight backgrounds
  - Add: ChordPro parser (regex: `\[([^\]]+)\]` → render chord above next word)
  - Add: Chords-on/off toggle switch at top
  - Keep: Auto-scroll, font size adjustment, full-screen presentation

**Storage format change:**

- **Before (JSON):**

  ```json
  {
    "blocks": [
      {
        "text": "When you try your best...",
        "highlight": "verse",
        "fontSize": 22
      },
      {
        "text": "Fix you",
        "highlight": "chorus",
        "fontSize": 22,
        "isBold": true
      }
    ]
  }
  ```

- **After (ChordPro plain text):**

  ```
  [Am]When you try your [C]best but you [G]don't succeed
  [Am]When you get what you [C]want but not what you [G]need

  {start_of_chorus}
  [F]Lights will [C]guide you [G]home
  {end_of_chorus}
  ```

**Migration impact:**

- **Pre-deploy audit required:** Query production DB for songs with non-null `lyrics`
- If count > 0, requires data migration script
- Announce breaking change in release notes: "Lyrics section formatting will be converted to plain text. Section labels can be preserved as ChordPro directives."

---

## What the "Chords On/Off Toggle" Means in Retrofit Context

**User expectation** (from product decision context):  
"Chords-on/off view toggle" implies automatic chord data that can be shown/hidden.

**Reality without provider:**

- Toggle controls visibility of **manually-entered chords only**
- If a song has no chords entered, toggle does nothing (lyrics-only in both states)
- Chords must be transcribed by the band or sourced externally (e.g., typed from a chord book, copied from a legal tab site while viewing in a browser)
- **Existing lyrics** (currently without chords) remain unchanged unless user manually adds `[Chord]` annotations

**UX Messaging:**  
Avoid implying automatic chord lookup in UI copy. Suggested phrasing:

- "Add chords to lyrics using ChordPro format (e.g., `[G]` above a word)"
- "Toggle chords on/off when viewing"
- Help link to ChordPro syntax guide (or in-app tooltip: "Type `[Am]` before a word to show chord above it")

This sets accurate expectations: BandRoadie provides the **tool** to store/view chords, but not a **database** of chord transcriptions.

**Migration UX consideration:**  
For songs with existing lyrics (no chords), the toggle will have no visible effect initially. Users can:

1. Tap "Edit Lyrics" → manually add `[Chord]` annotations to existing text
2. Or continue using lyrics-only (toggle remains functional but has no effect)

---

## Possible Phase 2.5 Enhancement: Lyrics-Only Auto-Fetch (Musixmatch)

If Phase 2.4 ships successfully with manual-entry-only, a future **Phase 2.5** could add:

**Feature:** "Fetch Lyrics Text" button (similar to existing "Enrich Song Data" for BPM/key)

- Calls Musixmatch API with title+artist
- Populates `songs.lyrics` with plain-text lyrics (no chords)
- User can then manually add `[Chord]` annotations via editor

**Requirements for Phase 2.5:**

1. **Licensing resolution:** Either:
   - Paid Musixmatch partnership (contact sales for commercial API tier), OR
   - Restrict feature to free BandRoadie users only (paid plans cannot use lyrics fetch due to ToS)
2. **Attribution UI:** "Lyrics powered by Musixmatch" with required logo/link in lyrics viewer
3. **Fail gracefully:** Many songs won't have Musixmatch entries (indie/local bands, deep cuts) — must handle gracefully like current BPM lookup ("Lyrics not available for this song")

**Architect decision:** Phase 2.5 is optional and depends on licensing feasibility. Do not block Phase 2.4 (manual-entry) on this.

---

## Comparison Table: All Evaluated Providers

| Provider              | Chord Data                               | API Access            | Commercial Licensing                            | Catalog Coverage                   | ChordPro-Ready?            | Verdict                            |
| --------------------- | ---------------------------------------- | --------------------- | ----------------------------------------------- | ---------------------------------- | -------------------------- | ---------------------------------- |
| **Musixmatch**        | ❌ None (lyrics only)                    | ✅ Public API         | ⚠️ Restricted (enterprise partnership required) | ✅ Excellent (14M+)                | N/A                        | NOT VIABLE (no chords)             |
| **Ultimate Guitar**   | ✅ Extensive, inline                     | ❌ No public API      | ❌ Scraping prohibited by ToS                   | ✅ Excellent (1.6M+)               | ✅ Yes (plain-text format) | NOT VIABLE (legal/stability risk)  |
| **Chordie**           | ⚠️ Inconsistent quality                  | ❌ No API             | ❌ Ambiguous licensing                          | ⚠️ Moderate (1M+, many duplicates) | ⚠️ Partial                 | NOT VIABLE (quality + legal)       |
| **Songsterr**         | ⚠️ Proprietary format (tabs, not chords) | ❌ No public API      | ❌ Scraping prohibited                          | ✅ Good for tabs                   | ❌ No (custom format)      | NOT VIABLE (format mismatch)       |
| **ChordPro Open DBs** | ✅ Yes (native format)                   | ⚠️ No centralized API | ⚠️ Copyright unclear                            | ❌ Tiny (<500 songs)               | ✅ Yes                     | VIABLE WITH CAVEATS (tiny catalog) |
| **Chordify**          | ✅ Yes (AI-detected)                     | ❌ No API             | ❌ Subscription-only, no export                 | ✅ Good (YouTube catalog)          | ❌ No (overlay-only)       | NOT VIABLE (no API)                |
| **Genius**            | ❌ None (lyrics + annotations)           | ✅ Public API         | ⚠️ Restricted (similar to Musixmatch)           | ✅ Excellent (lyrics)              | N/A                        | NOT VIABLE (no chords)             |
| **MuseScore**         | N/A (sheet music, not chord sheets)      | ✅ Public API         | ✅ Open (MusicXML)                              | ✅ Large (sheet music)             | ❌ No (wrong format)       | NOT VIABLE (use case mismatch)     |

---

## Decision Log: Why Manual-Entry Is the Right Phase 2.4 Scope

1. **Legal safety:** All auto-chord providers require scraping (ToS violation) or have no API. Manual-entry avoids third-party licensing entirely.
2. **Quality control:** User-entered chords can be tailored to the band's specific arrangement/key (important for cover bands who transpose).
3. **No external dependency:** No rate limits, no API costs, no third-party service outages.
4. **Aligns with BandRoadie's model:** Already manual-entry for tuning, notes, setlists — chords fit this pattern.
5. **Extensibility:** Plain-text ChordPro storage allows future enhancements (section labels, transposition, per-musician capo settings) without re-architecting.

**Trade-off acknowledged:** Users must transcribe chords themselves (copy from legal sources, or transcribe by ear). This is additional work, but it's work bands already do when learning songs — BandRoadie now stores it in a structured, shareable format.

---

## Recommended Next Steps

### For Phase 2.4 (Retrofit Existing Lyrics for ChordPro):

1. **Architect pass:**
   - ⚠️ **Critical:** Review existing lyrics feature implementation (`lib/features/lyrics/`) to understand current data model and UI patterns
   - **Decision required:** Choose migration strategy for `LyricsHighlight` formatting (lossy vs. section labels vs. dual-format)
   - Audit production DB: `SELECT COUNT(*) FROM songs WHERE lyrics IS NOT NULL` — scope migration impact
   - Specify ChordPro parser behavior (render `[Chord]` above text, handle edge cases)
   - Design chords-on/off toggle UX (placement in existing viewer toolbar, default state)
   - Plan breaking change communication (release notes, in-app migration notice)

2. **Engineer tasks:**
   - **Retrofit editor:** Strip formatting toolbar from `lyrics_editor_sheet.dart`, add ChordPro syntax helper
   - **Retrofit viewer:** Add ChordPro parser to `lyrics_view_screen.dart` (regex-based: `\[([^\]]+)\]` → extract chord, render above next word)
   - **Add toggle:** Chords-on/off switch in viewer toolbar (persist per-user preference)
   - **Data migration:** Script to convert existing JSON lyrics to plain-text ChordPro (with chosen strategy for highlights)
   - **Update models:** Deprecate or remove `LyricsData`/`LyricsBlock` classes if no longer needed (or keep for rollback/dual-format scenarios)

3. **QA validation:**
   - Test ChordPro parser with real-world songs (edge cases: multiple chords per word, chords at line end, empty lines, section labels)
   - Test migration script with production data snapshot (verify no data loss, highlight conversion works)
   - Verify toggle behavior (chords show/hide, layout doesn't break, persists across sessions)
   - Test backward compatibility: songs with existing JSON lyrics (pre-migration) render correctly post-migration
   - Test backup/restore/export with ChordPro lyrics (ensure plain text survives round-trip)

### For Optional Phase 2.5 (Lyrics-Only Auto-Fetch):

1. **Business decision:** Evaluate Musixmatch licensing options (paid partnership vs. free-tier-only restriction)
2. **If proceeding:**
   - Architect: Design "Fetch Lyrics" flow (similar to Enrich Song Data, lyrics-text-only with manual chord entry afterward)
   - Implement Musixmatch Edge Function (same pattern as `getsongbpm_lookup`)
   - Add attribution UI per Musixmatch guidelines

---

## References

### Provider Documentation

- Musixmatch API: https://developer.musixmatch.com/documentation
- Musixmatch Terms: https://about.musixmatch.com/apiterms (section numbers unverified)
- Ultimate Guitar ToS: https://www.ultimate-guitar.com/about/tos.htm (§6.3, §6.4)
- Genius API: https://docs.genius.com/

### ChordPro Format

- Official ChordPro spec: https://www.chordpro.org/chordpro/chordpro-file-format-specification/
- Syntax examples: https://www.chordpro.org/chordpro/chordpro-introduction/

### Community Resources (Educational Only)

- Ultimate Guitar scrapers (GitHub) — reference only, not recommended for production use
- Open ChordPro collections (GitHub search: "chordpro songs") — small hobbyist collections

---

## Appendix: GetSongBPM Integration as Reference Pattern

For context, BandRoadie's existing song enrichment (Phase 1, Phase 2.1) integrates with GetSongBPM as follows:

**What GetSongBPM provides:**

- BPM (tempo)
- Musical key (normalized to 24-key vocabulary: C, C#, D, Eb, etc.)
- Confidence score

**What it does NOT provide:**

- Duration (comes from iTunes/MusicBrainz search)
- Lyrics
- Chords
- Tuning

**Integration pattern:**

1. **Edge Function:** `supabase/functions/getsongbpm_lookup/index.ts` (server-side, holds API key)
2. **Client Service:** `lib/features/songs/song_enrichment_service.dart` (calls Edge Function)
3. **Repository:** Writes results via `update_song_metadata` RPC
4. **UI:** "Enrich Song Data" button → selector drawer (checkboxes for BPM/Key/Duration) → progress UI → results summary

**Phase 2.4 lyrics differs:**  
No equivalent provider exists, so no Edge Function or enrichment service. Lyrics flow is a retrofit of the existing feature: user taps "Edit Lyrics" → existing `lyrics_editor_sheet.dart` (adapted for ChordPro) → manually types ChordPro text → saves to `songs.lyrics`. Chords-on/off toggle is a **viewer setting** added to the existing `lyrics_view_screen.dart`, not an enrichment feature.

---

**Document Status:** Research complete  
**Next Action:** Architect review → scope Phase 2.4 feature plan OR defer lyrics feature to post-launch roadmap
