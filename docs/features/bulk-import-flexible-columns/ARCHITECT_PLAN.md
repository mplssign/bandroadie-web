# Architect Plan — Bulk Import Flexible Columns + Updated Instructional Copy

## Feature Slug

`feature/bulk-import-flexible-columns`

---

## Problem Summary

Users import songs into a setlist via the Bulk Entry / Add Songs screen (`BulkEntryScreen`) by pasting spreadsheet data into a text field, then tapping "Load Songs." The Feature Input asks for two things:

1. **Copy change (confirmed gap):** the instructional text above the paste field and the field's placeholder text do not match the desired wording.
2. **Parser behavior (unconfirmed until this diagnosis):** confirm that pasting rows with 2 (Artist+Song), 3 (+BPM), 4 (+Tuning), or 5 (+Key) columns per newline-delimited line all parse cleanly, with missing trailing columns left blank/null rather than treated as an error or shifted into the wrong field.

Per the Feature Input's explicit instruction, root cause was not assumed — the parser's row-parsing logic was read directly before any solution was designed.

---

## Root Cause

### Copy — CONFIRMED GAP, Confidence: HIGH

`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, lines 366–417 (current state, confirmed by direct read):

- Only **one** line of instructional copy is rendered above the paste field (line 367–373: `'Paste songs from a spreadsheet, then tap Load Songs.'`) — the desired end state requires **three** lines, and lines 2 and 3 do not exist at all today.
- The `TextField`'s `hintText` (lines 386–388) currently reads:
  ```
  Paste CSV or tab-delimited data here…
  Artist, Song, BPM, Tuning, Key
  e.g.: Aerosmith, Eat The Rich, 123, Standard, G
  ```
  which does not match the required placeholder: `"Column order: Artist, Song, BPM, Tuning, Key"`.

This is a pure copy/text change — no logic is involved.

### Parser variable-column handling — THIRD PASS, FINAL: CONFIRMED NO GAP. Full 2–5 column support (including Key) verified end-to-end against the real merged state. Confidence: HIGH

**This is the third and final verification pass on this question, superseding both prior passes.** Pass one (on this branch) cited code that did not exist yet and was wrong. Pass two correctly caught that the cited code (`rawKey`, `musicalKey`, `_splitCsvLine`) did not exist anywhere on this branch or `main` at that time, and correctly found a genuine functional gap — the Key column was silently dropped. Both pass-two's method and its conclusion were sound *for the state that existed then*.

**Git ancestry check (this pass, re-verified):** `git merge-base --is-ancestor 7dd9785 HEAD` returns **true** — commit `7dd9785` (`bug/csv-import-comma-and-key`, `"fix(setlists): fix CSV comma corruption in bulk import, add musical key column"`) is now genuinely an ancestor of this branch's `HEAD`. `git rev-parse HEAD` and `git rev-parse origin/main` both resolve to `7dd978585e8264f2c74dd2f43b8fe7463844a195` — identical. Unlike the previous pass, this time the merge has actually landed on both `main` and this branch. This is the fact pattern that invalidates pass two's conclusion (not pass two's method, which was correct given what was true at the time).

**Direct code evidence (fresh full reads, this pass, of the actual current file contents):**

1. `bulk_song_parser.dart`, `parse()` (lines 64–208): line 89 calls `_parseColumns()`; lines 104–108 extract all five fields positionally, each trailing column independently optional via a length guard:
   ```dart
   final artist = columns[0].trim();
   final title = columns[1].trim();
   final rawBpm = columns.length > 2 ? columns[2].trim() : '';
   final rawTuning = columns.length > 3 ? columns[3].trim() : '';
   final rawKey = columns.length > 4 ? columns[4].trim() : '';
   ```
   `rawKey` is present and is read the same way BPM/Tuning are. Lines 155–169: `rawKey` is normalized via `_normalizeKey()`; an unrecognized key produces a non-fatal `keyWarning` (row stays valid), a recognized key sets `musicalKey`. Lines 177–186: `BulkSongRow.valid(...)` is constructed with `musicalKey: musicalKey`.
2. `_normalizeKey()` (lines 420–458) and its supporting regexes/canonical set (`_kCanonicalKeys`, lines 402–408; `_minorKeyPattern`/`_majorKeyPattern`, lines 410–418) exist in full and handle major/minor key text (e.g. `"A"`, `"Am"`, `"F#"`, `"Bb minor"`) against a fixed canonical key list — confirmed by direct read, not grep-absence.
3. `_parseColumns()` (lines 216–229) now has a real `_splitCsvLine()` method (lines 237–268) that is quote-aware per RFC 4180 — a comma inside a `"..."` field is not treated as a delimiter, confirmed by reading the character-by-character state machine (`insideQuotes` toggle). `_unescapeField()` (lines 278–295) strips outer quotes and un-escapes doubled quotes/apostrophes on the already-correctly-split fields. This directly contradicts pass two's finding that `_splitCsvLine()` did not exist — it did not exist *then*; it exists now, post-merge.
4. `bulk_song_row.dart`, full read: `BulkSongRow` (lines 19–145) has a `musicalKey` field (line 38, `/// Normalized musical key (Column 5) - null if not provided`). Both `.invalid()` (lines 72–90) and `.valid()` (lines 93–113) factories accept and pass through `musicalKey`. `formattedKey` getter exists at line 122.
5. `setlist_repository.dart`: `bulkAddSongs()` (lines 3848–3993), line 3926, passes `musicalKey: row.musicalKey` into `_createOrFindSong()`. `_createOrFindSong()`'s signature (lines 4041–4050) includes `String? musicalKey`. On the existing-song enrichment path (lines 4098–4100), `musical_key` is added to the `updates` map only if a key was parsed **and** the existing DB value is null (never overwrites real data — consistent with the enrichment pattern already used for `bpm`/`tuning`/`duration_seconds`/`album_artwork`). On the new-song insert path (lines 4133–4135), `musical_key` is included in `insertData` whenever `musicalKey` is non-null/non-empty.

**Conclusion (final):** The 2/3/4/5-column parsing behavior, including the Key column, is genuinely wired end-to-end on this branch's actual `HEAD`: raw text → positional extraction with length guards → key normalization (with graceful non-fatal fallback for unrecognized input) → `BulkSongRow.musicalKey` → `bulkAddSongs()` → `_createOrFindSong()` → persisted to `songs.musical_key` (insert or non-destructive enrichment update). There is no parser, model, or repository gap left to fix. **This is now, genuinely, a copy-only plan.** The remaining and entire scope of implementation work is the instructional/placeholder text in `bulk_entry_screen.dart` described in Proposed Solution below — those sections were written under the (originally unverified, now-confirmed-correct) assumption of copy-only and require no further changes as a result of this pass.

**Confidence: HIGH** — confirmed by full direct reads of all three files' actual current contents (not excerpts, not grep-absence reasoning) plus a `git merge-base --is-ancestor` / `git rev-parse` check proving the dependency commit is genuinely present in this branch's `HEAD` and identical to `origin/main`. No further validation is required before Engineer proceeds.

**Current state of `bulk_entry_screen.dart` (fresh read, this pass, lines 350–429):** The sibling PR's Key-aware hint text has already landed here — the `TextField`'s `hintText` (lines 386–388) already reads `Paste CSV or tab-delimited data here…\nArtist, Song, BPM, Tuning, Key\ne.g.: Aerosmith, Eat The Rich, 123, Standard, G`, mentioning Key. However, this is **not** the copy this feature requires: the instructional text above the field is still a single `Text` widget (lines 367–373, one line only — `'Paste songs from a spreadsheet, then tap Load Songs.'`), not the three lines specified in Proposed Solution, and the placeholder is still the old multi-line "e.g." form, not the required single-line `Column order: Artist, Song, BPM, Tuning, Key`. Task 1 and Task 2 in the Engineer Task Breakdown below are unchanged and still required. (A prior uncommitted attempt at this copy work was discarded during branch cleanup — nothing of diagnostic value was lost, since the required end-state copy is fully specified in this document.)

---

## Reference Docs Consulted

Per ARCHITECT.md Phase 4, `docs/reference/notifications/*.md` (`NOTIFICATION_PERMISSION_FLOW.md`, `NOTIFICATION_SYSTEM.md`, `notifications.md`) exists and was checked — **not applicable**; this feature concerns setlist bulk-import UI copy, not notifications, matching the same conclusion reached in the immediately-prior sibling plan `docs/features/csv-import-comma-and-key/ARCHITECT_PLAN.md`.

There is no `docs/reference/setlists/`, `docs/reference/catalog/`, or `docs/reference/bulk-import/` directory. The directly relevant prior plan, `docs/features/csv-import-comma-and-key/ARCHITECT_PLAN.md`, was read in full and used as precedent — this feature is an immediate follow-on to that work in the exact same file (`bulk_song_parser.dart`) and confirms that work's column-parsing logic is already flexible-column-safe (no additional changes needed there).

---

## Existing System Analysis

1. User pastes text into `BulkEntryScreen`'s CSV textarea and taps **Load Songs** → `_handleCsvIngestion()` (bulk_entry_screen.dart:210).
2. `BulkSongParser.instance.parse(text, maxRows: _kMaxRows)` (bulk_song_parser.dart:64) splits on `\n`, and per non-blank line calls `_parseColumns()` (TAB → comma (quote-aware) → 2+-space priority), extracts `artist`/`title`/`rawBpm`/`rawTuning`/`rawKey` positionally with length guards, validates/normalizes BPM/Tuning/Key (each independently optional, each downgrading to a non-fatal warning on bad input — never a hard error unless Artist+Song themselves are missing), and returns a `BulkSongParseResult`.
3. `_populateTableFromParseResult()` (bulk_entry_screen.dart:268) writes parsed values into the editable table's `TextEditingController`s.
4. User may hand-edit cells, then taps the submit button → `_handleSubmit()` (bulk_entry_screen.dart:302): re-serializes every row back into tab-delimited text (all 5 fields, always present positionally even if empty — line 308–317), re-parses it through `BulkSongParser` again, and calls `widget.onSubmit(parseResult.validRows)`.
5. `onSubmit` → `SetlistRepository.bulkAddSongs()` (setlist_repository.dart:3848) → `_createOrFindSong()`, passing `bpm`, `tuning`, `musicalKey` as independently-nullable named parameters — confirmed no positional coupling at this layer either.

The only actual deficiency found anywhere in this flow is the static instructional/placeholder text in `bulk_entry_screen.dart`, which is out of sync with the desired copy in the Feature Input.

---

## Proposed Solution

Pure copy change in `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`. No parsing, model, or repository logic changes.

1. Replace the single `Text` widget above the paste field (lines 367–373) with three separate `Text` widgets (or one widget with three visually-separated lines — Engineer's call as long as each is its own line), exact copy:
   1. `Paste songs from a spreadsheet, then tap Load Songs.`
   2. `Column order: Artist, Song, BPM, Tuning, Key (Led Zeppelin, Rock and Roll, 172, Standard, A Major)`
   3. `Required: Artist, Song (Optional BPM, Tuning, Key)`
2. Replace the `TextField`'s `hintText` (lines 386–388) with exactly: `Column order: Artist, Song, BPM, Tuning, Key` (single line — the current multi-line hint with the "e.g." example is removed since the worked example now lives in instructional line 2 above the field instead).

No other files change. This plan explicitly does **not** touch `bulk_song_parser.dart`, `bulk_song_row.dart`, or `setlist_repository.dart` — the diagnosis found them already correct for the required 2–5 column behavior.

---

## Database Impact

**Not applicable.** No schema, RLS, RPC, or trigger changes — this is a static UI text change with no data-layer involvement.

---

## Flutter Architecture Changes

None. No new state, no new widgets, no new providers. `_BulkEntryScreenState.build()` (bulk_entry_screen.dart) gains two additional static `Text` widgets in the existing `Column` (replacing/extending the current single `Text`), and one string literal changes (`hintText`). This is the smallest possible diff — no new widget classes, no layout restructuring beyond adding two more `Text`/`SizedBox` siblings matching the existing style pattern already used for the first line.

---

## Files to Create

**None required.**

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Lines 367–373: replace the single instructional `Text` widget with three `Text` widgets (exact copy specified in Proposed Solution), each on its own line, matching the existing style pattern (font size, color, spacing) already used for the current line. Lines 386–388: replace `hintText` with the exact single-line placeholder `"Column order: Artist, Song, BPM, Tuning, Key"`. No other lines in this file change. |

---

## Files Off-Limits

**RESTORED (this pass, on fresh evidence):** the three rows below for `bulk_song_parser.dart`, `bulk_song_row.dart`, and `setlist_repository.dart` are restored to off-limits status — not as a formality, but because this pass's direct, full reads of the actual current file contents (see Root Cause above) confirm the 2/3/4/5-column parsing behavior, including Key, is genuinely implemented and wired end-to-end on this branch's real `HEAD`. There is no gap left in these files for the Engineer to fix.

| File | Reason |
|------|--------|
| `lib/features/setlists/services/bulk_song_parser.dart` | Confirmed by direct read (this pass): already extracts, validates, and normalizes all five columns including `rawKey`/`musicalKey`, with quote-aware CSV splitting (`_splitCsvLine`). No parsing gap. Do not modify. |
| `lib/features/setlists/models/bulk_song_row.dart` | Confirmed by direct read (this pass): `musicalKey` field already exists and is threaded through both `.invalid()` and `.valid()` factories. Do not modify. |
| `lib/features/setlists/setlist_repository.dart` | Confirmed by direct read (this pass): `bulkAddSongs()` → `_createOrFindSong()` already accepts and persists `musicalKey` to `songs.musical_key` on both the insert and non-destructive-enrichment paths. Do not modify. |
| `lib/main.dart` | Init order must not change — unrelated to this feature. |
| `supabase/migrations/*.sql` | No migration needed or relevant — this is a client-side copy-only change. Do not create a new migration file. |
| `lib/features/setlists/new_setlist_screen.dart`, `lib/features/setlists/setlist_detail_screen.dart`, `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` | Thin pass-through callers of `BulkEntryScreen`/`bulkAddSongs` — no copy or behavior in these files is affected by this change. Do not modify. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed
**New files:** none

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — instructional copy and placeholder text on the Bulk Entry screen change; no parsing/data behavior changes |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected uniformly** — shared Dart widget, no platform-specific code paths |

---

## Regression Risk

**LEVEL: LOW**

Rationale:
- No auth, session, routing, or init-order changes.
- No RLS, RPC, migration, or repository changes — this plan modifies zero lines outside of two `Text`/`hintText` string blocks in one widget file.
- No parsing logic changes at all — diagnosis confirmed the existing behavior already satisfies the Feature Input's functional requirement, so there is no risk of a functional regression to variable-column parsing because nothing in that path is touched.
- The only user-visible change is static text — no interactive behavior, no data flow, no validation logic is altered.

---

## Engineer Task Breakdown

Execute in order:

### Task 1 — Update instructional copy (`bulk_entry_screen.dart`)
1. Replace the single `Text` widget at lines 367–373 with three `Text` widgets, each on its own line, exact copy:
   - `Paste songs from a spreadsheet, then tap Load Songs.`
   - `Column order: Artist, Song, BPM, Tuning, Key (Led Zeppelin, Rock and Roll, 172, Standard, A Major)`
   - `Required: Artist, Song (Optional BPM, Tuning, Key)`
2. Match the existing text style (`color: Colors.white`, `fontSize: AppFontSizes.subhead`) for line 1; use Engineer's judgment for whether lines 2–3 should use a slightly smaller/secondary style for visual hierarchy (e.g. `AppFontSizes.caption` / `context.colors.textSecondary`) as long as all three are clearly legible and each is unambiguously its own line — the Feature Input specifies exact text content, not exact typography, for lines 2–3.
3. Add appropriate `SizedBox` spacing between the three lines and before the text field, consistent with existing spacing conventions in this file (`Spacing.space*` tokens already in use).

### Task 2 — Update placeholder text (`bulk_entry_screen.dart`)
1. Replace the `hintText` value (lines 386–388) with exactly: `Column order: Artist, Song, BPM, Tuning, Key` (single line, no trailing example — the worked example now lives in instructional line 2, not the placeholder).

### Task 3 — `flutter analyze`
Ensure `0 errors` before handing off to QA.

### Task 4 (verification only, no code change expected)
Manually paste 2, 3, 4, and 5-column rows (comma-delimited and tab-delimited) into the Bulk Entry screen and confirm each parses as expected, per the Verification Plan below — this is confirmation that the "no parser gap" diagnosis holds in the running app, not a fix.

---

## Verification Plan

No database migration or backend change is involved in this feature, so the Tier 1/Tier 2 split is adapted to a client-side-only change, consistent with the sibling `csv-import-comma-and-key` plan's precedent.

### Tier 1 — Pre-deployment (before merge)
These exercise only client-side parsing logic (already correct, unmodified by this plan) and the new static copy (modified by this plan) — no backend dependency.

- **PRE-DEPLOY TEST 1:** Open Bulk Entry screen. Confirm the three instructional lines render above the paste field, in order, with the exact text specified in Proposed Solution.
- **PRE-DEPLOY TEST 2:** Confirm the paste field's placeholder (visible when the field is empty) reads exactly `Column order: Artist, Song, BPM, Tuning, Key`.
- **PRE-DEPLOY TEST 3 (2-column row):** Paste `Led Zeppelin, Rock and Roll` and tap Load Songs. Assert one valid row: Artist=`Led Zeppelin`, Song=`Rock and Roll`, BPM/Tuning/Key blank — not an error, not skipped.
- **PRE-DEPLOY TEST 4 (3-column row):** Paste `Led Zeppelin, Rock and Roll, 172`. Assert BPM=`172`, Tuning/Key blank.
- **PRE-DEPLOY TEST 5 (4-column row):** Paste `Led Zeppelin, Rock and Roll, 172, Standard`. Assert BPM=`172`, Tuning=`Standard`, Key blank.
- **PRE-DEPLOY TEST 6 (5-column row):** Paste `Led Zeppelin, Rock and Roll, 172, Standard, A`. Assert all five fields populate correctly, Key=`A`.
- **PRE-DEPLOY TEST 7 (mixed multi-line paste):** Paste four lines in one paste, one of each column count from Tests 3–6 above (newline-delimited, per the Feature Input's stated assumption that each song is already on its own line). Assert all four rows parse correctly and independently — no column bleed between rows.
- **PRE-DEPLOY TEST 8 (tab-delimited variant):** Repeat Tests 3–6 using TAB as the delimiter instead of commas (simulating a real spreadsheet paste) — assert identical correct behavior.
- **PRE-DEPLOY TEST 9 (regression):** Paste a row with fewer than 2 columns (e.g. a single word with no delimiter) — assert it is still correctly flagged invalid ("Missing song title"), confirming the Artist+Song minimum is unchanged.

### Tier 2 — Post-deployment (after merge, in the running app)
- **POST-DEPLOY TEST 1:** Full end-to-end — paste a 2-column row, Load Songs, Add Songs. Confirm the song is added to the setlist/Catalog with `bpm`, `tuning`, `musical_key` all `null` in the database (or via the song details view) — not zero, not empty string, not an error.
- **POST-DEPLOY TEST 2:** Repeat with a 3-column and a 4-column row; confirm only the supplied fields persist and trailing omitted fields remain `null`.
- **Production verification query:** `SELECT id, title, artist, bpm, tuning, musical_key FROM songs WHERE band_id = '<test band id>' ORDER BY created_at DESC LIMIT 10;` — confirm rows created during QA show `NULL` (not empty string, not `0`) for any column that was omitted from its source paste row.

### SQL test authoring rules
Not applicable — no SQL is introduced or modified by this plan.

---

## QA Regression Areas

QA must specifically test:
1. **Primary requirement:** all three instructional copy lines render, in order, with exact wording (verbatim match — this is a literal-text requirement, not paraphrase-tolerant).
2. **Primary requirement:** placeholder text reads exactly `Column order: Artist, Song, BPM, Tuning, Key`.
3. **Primary requirement:** 2, 3, 4, and 5-column rows (both comma- and tab-delimited) all parse correctly with no error and no field-shifting, per Pre-Deploy Tests 3–8.
4. **No regression:** existing 5-column full-row import (the previously-working case) is unaffected.
5. **No regression:** quote-aware comma splitting and Key-column normalization from the immediately-prior `bug/csv-import-comma-and-key` work still function correctly (this plan does not touch that logic, but QA should confirm no incidental breakage from the copy-only diff).
6. **No regression:** rows with fewer than 2 columns are still correctly rejected as invalid.
7. **Cross-platform:** confirm copy renders correctly on at least two of Web / iOS / Android / macOS (shared Dart widget, no platform branches, but text wrapping/line-length should be visually checked on a narrow mobile screen given line 2's length).

---

## Rollout / Migration Strategy

Not applicable — pure client-side copy change, no backend deploy, no migration, no feature flag. Standard release per `docs/agents/OPERATING_MODEL.md`'s deployment protocol.

---

## Out of Scope

Explicitly excluded from this change:
1. **Any change to `bulk_song_parser.dart`, `bulk_song_row.dart`, or `setlist_repository.dart`** — diagnosis found no gap in the 2–5 column parsing behavior; modifying these files is unnecessary and would violate the "smallest change" / "no opportunistic cleanup" guardrails.
2. **Column header row styling/layout changes** in the editable preview table (`_buildColumnHeaders`, `_buildRow`) — not requested by the Feature Input and unrelated to the paste-field copy/placeholder.
3. **Localization/i18n** of the new copy — out of scope; matches existing convention (all current strings in this file are hardcoded English literals).
4. **Newline-inference for songs pasted without line breaks** — the Feature Input explicitly states each song is already on its own line when pasted from a spreadsheet, and there is no requirement to infer song boundaries without newlines.

---

**Architect Signature:** Plan complete. Ready for Engineer implementation.
