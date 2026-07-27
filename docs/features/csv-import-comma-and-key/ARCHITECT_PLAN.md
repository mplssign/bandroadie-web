# Architect Plan — CSV Import Comma Corruption + Musical Key Column

## Feature Slug

`bug/csv-import-comma-and-key`

This is a bundled pipeline run covering two related issues in the same parsing code path, approved by the product owner to ship together:

1. **Bug:** Quoted CSV fields containing an internal comma are corrupted during bulk/CSV song import (title truncated at the internal comma).
2. **Feature:** Add support for importing a song's musical key as a bulk-entry column (Artist, Song, BPM, Tuning, **Key**), wired through to `SetlistSong.musicalKey`.

Both issues live in the same three files (`bulk_song_parser.dart`, `bulk_song_row.dart`, `bulk_entry_screen.dart`) plus one shared repository method (`setlist_repository.dart`), so they are diagnosed and planned together.

---

## Problem Summary

Users build setlists by pasting spreadsheet/CSV text into the Bulk Entry screen (Add Songs → paste/bulk entry). The parser (`BulkSongParser`) splits each pasted line into Artist/Song/BPM/Tuning columns.

**Bug:** When a pasted line contains a quoted field with an internal comma — e.g. `"John Denver","Take Me Home, Country Road"` — the comma-delimited parsing branch splits on *every* comma, including the one inside the quoted title, corrupting the imported title to `Take Me Home` and shifting `" Country Road"` into the next (BPM) column.

**Feature gap:** `SetlistSong` already has a `musicalKey` field reading from `songs.musical_key` (confirmed to already exist in the database — see Database Impact), and a single-song edit flow (`key_picker_bottom_sheet.dart` + `updateSongMusicalKey`) already lets users set it one song at a time. The bulk/CSV import path has no equivalent — `BulkSongRow`, `BulkSongParser`, and `BulkEntryScreen` model only Artist/Song/BPM/Tuning end to end, so users cannot bulk-import a musical key alongside BPM and Tuning.

---

## Root Cause

### Bug #1 — Comma corruption

**Confidence: HIGH** (confirmed by direct code inspection, not hypothesis)

`lib/features/setlists/services/bulk_song_parser.dart`, method `_parseColumns` (lines 196–209):

```dart
List<String> _parseColumns(String line) {
  // Try TAB-delimited first (spreadsheet paste)
  if (line.contains('\t')) {
    return line.split('\t').map(_unescapeField).toList();
  }

  // Try comma-delimited (manual entry)
  if (line.contains(',')) {
    return line.split(',').map(_unescapeField).toList();   // <-- naive split
  }

  // Fall back to 2+ spaces (legacy support)
  return line.split(RegExp(r'\s{2,}')).map(_unescapeField).toList();
}
```

`line.split(',')` splits on **every** comma in the raw line with no awareness of quoted regions. For input `"John Denver","Take Me Home, Country Road"`, this produces four columns instead of two:

```
['"John Denver"', '"Take Me Home', ' Country Road"']   // 3 elements, not 2 — title cut at internal comma
```

`_unescapeField` (lines 219–236) already correctly strips wrapping quotes and un-escapes doubled quotes/apostrophes **per field**, but it only runs *after* the split has already happened, so it cannot repair a split that occurred at the wrong comma. The reporter's observed symptom (`title` truncated to `Take Me Home`, remainder lost) is exactly what this code produces: column 2 becomes `"Take Me Home` (still quote-wrapped on one side only, so `_unescapeField`'s `startsWith('"') && endsWith('"')` check fails and it's returned as-is with the leading quote intact — in practice the leading `"` typically also gets stripped/trimmed downstream by title-casing, but the ` Country Road"` fragment is shifted into the `rawBpm` column and discarded because `int.tryParse` fails on it, which matches the reporter's description of the remainder being "lost").

Per the diagnosis lead, the TAB-delimited and 2+-space fallback branches are **not** affected — real CSV-with-embedded-commas only occurs in the comma-delimited path (a genuine CSV export uses commas as its delimiter, which is precisely what creates the need for quoting in the first place; tab-delimited spreadsheet paste does not need quoting for commas since tabs are the delimiter).

### Feature #2 — Missing Key column

**Confidence: HIGH**

- `lib/features/setlists/models/setlist_song.dart` line 39 / 109: `musicalKey` field already reads `songData['musical_key']` from the Supabase join — the **read** side is fully wired.
- `lib/features/setlists/models/bulk_song_row.dart`: models only `artist, title, bpm, tuning, tuningLabel` (lines 14–41) — no key field.
- `lib/features/setlists/services/bulk_song_parser.dart`: `_parseColumns` result is only ever indexed at `columns[0..3]` (artist, title, bpm, tuning) — a 5th column, if present, is silently discarded (line 105–106 only reads `columns[2]`/`columns[3]`).
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`: `_RowData` (lines 44–83) has controllers for `artist, song, bpm, tuning` only; the table header (`_buildColumnHeaders`, lines 481–499) renders exactly 4 columns.
- `lib/features/setlists/setlist_repository.dart`: `bulkAddSongs` (line 3848) → `_createOrFindSong` (line 4040) accepts `bpm` and `tuning` but has **no `musicalKey` parameter at all** (confirmed by direct inspection of lines 4040–4137); neither the existing-song enrichment block (4076–4103) nor the new-song `insertData` map (4108–4137) ever reference `musical_key`. The only place `musical_key` is currently written is the single-song edit RPC path (`updateSongMusicalKey`, lines 2192–2265), which is unrelated to bulk import.

So the gap is confirmed end-to-end: model → parser → UI → repository all need a new field/column, and none of them currently touch `musical_key`.

---

## Reference Docs Consulted

Per ARCHITECT.md Phase 4, `docs/reference/notifications/*.md` was checked and read (`NOTIFICATION_PERMISSION_FLOW.md`, `NOTIFICATION_SYSTEM.md`, `notifications.md`) — **this domain does not apply to this feature** (this bug/feature concerns CSV/bulk song import, not notifications; Phase 4's literal instruction is a generic template step and the notifications directory is unrelated to setlists/catalog).

There is no `docs/reference/setlists/`, `docs/reference/catalog/`, or `docs/reference/bulk-import/` directory. The closest available reference, `docs/reference/architecture/database_schema.md`, was consulted instead:
- It documents the `songs` and `setlist_songs` tables but its column list for `songs` (line 46) does **not** mention `musical_key` — this reference doc is stale relative to the actual schema (the migration adding `musical_key` predates this check by ~4 weeks). This staleness is flagged here per Phase 6 guidance but does not block diagnosis, since the migration files and `SetlistSong.fromSupabase` are direct, authoritative evidence that the column exists and is already read.

A directly relevant prior plan was also found and used as precedent for scope/format: `docs/features/bulk-entry-apostrophe-corruption/ARCHITECT_PLAN.md` — a previous bug fix to this exact same `_parseColumns`/`_unescapeField` code path (Google Sheets doubled-apostrophe corruption). That fix is what introduced `_unescapeField` itself. This plan's fix is additive to that prior work and does not revert or conflict with it.

---

## Existing System Analysis

### Current data flow (bulk import, end to end)

1. User pastes text into `BulkEntryScreen`'s CSV textarea and taps **Load Songs** → `_handleCsvIngestion()` (bulk_entry_screen.dart:201).
2. `BulkSongParser.instance.parse(text)` (bulk_song_parser.dart:63) splits on `\n`, then per line calls `_parseColumns()` (tab → comma → 2+-space priority), extracts `artist`/`title`/`rawBpm`/`rawTuning`, validates/normalizes BPM and tuning, and returns a `BulkSongParseResult` with `validRows`/`invalidRows`.
3. `_populateTableFromParseResult()` (bulk_entry_screen.dart:259) writes parsed values into the editable table's `TextEditingController`s (one `_RowData` per row).
4. User may hand-edit cells, then taps **Add N Songs** → `_handleSubmit()` (bulk_entry_screen.dart:292): re-serializes every row back into **tab-delimited** text (`buffer.writeln('$artist\t$song\t$bpm\t$tuning')`, lines 301–306), re-parses it through `BulkSongParser` again (so the table is always the source of truth, matching Guardrails §6 "submission flows must serialize cleanly, re-parse cleanly"), and calls `widget.onSubmit(parseResult.validRows)`.
5. `onSubmit` is wired by the parent screen. Two concrete call sites exist — `setlist_detail_screen.dart` (`_handleBulkSongsSubmit`, ~line 922) and `new_setlist_screen.dart` (identical shape, ~line 400) — both are thin wrappers that call `setlistRepository.bulkAddSongs(bandId:, setlistId:, rows: validRows)` with no transformation of the rows. A third pass-through exists in `add_to_setlist_overlay.dart` (line 321) which simply forwards to whichever of the above is supplied by its parent.
6. `SetlistRepository.bulkAddSongs()` (setlist_repository.dart:3848) iterates rows in batches of 50, and per row calls `_createOrFindSong(bandId:, title:, artist:, bpm: row.bpm, tuning: row.tuning)` (line 3920) — **`row.musicalKey` does not exist today and nothing is passed for key**. `_createOrFindSong` (line 4040) either enriches an existing `songs` row (filling `bpm`/`tuning`/`duration_seconds`/`album_artwork` only if currently `NULL`) or inserts a new `songs` row with `band_id, title, artist`, + conditionally `bpm`, `duration_seconds`, `album_artwork`, and `tuning` (mapped through `tuningToDbEnum()` to the DB's legacy tuning enum). The song is then added to the band's Catalog setlist and (if different) the target setlist via `addSongToSetlist()`.

### Why the tuning/BPM pattern is the right template for Key

`tuning` requires an extra enum-mapping step (`tuningToDbEnum()`) because the DB column is a legacy Postgres enum (`standard`, `drop_d`, `half_step`, `full_step`, …). `musical_key` is plain nullable `TEXT` with **no** enum/CHECK constraint (confirmed in migration below), so the Key column needs no equivalent mapping step — it is a direct pass-through, exactly like the existing `updateSongMusicalKey` RPC already does (`'p_musical_key': musicalKey` at repository line 2226).

---

## Proposed Solution

### Bug #1 — Quote-aware CSV column splitter

Add a private, quote-aware line splitter and use it **only** in the comma-delimited branch of `_parseColumns` (the tab and 2+-space branches are untouched — out of scope per the diagnosis, and touching them risks regressing the already-fixed apostrophe/quote behavior on those paths for no benefit).

New method (illustrative — Engineer may adjust naming/structure, but the algorithm must satisfy the RFC 4180 semantics below):

```dart
/// Split a comma-delimited line into fields, honoring RFC 4180 quoting:
/// a comma inside a double-quoted field is NOT a delimiter.
///
/// Quotes are preserved in the returned fields (not stripped) — stripping
/// and un-escaping remains the job of `_unescapeField`, which already runs
/// on every returned field.
List<String> _splitCsvLine(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var insideQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final char = line[i];

    if (char == '"') {
      if (insideQuotes && i + 1 < line.length && line[i + 1] == '"') {
        // Escaped quote ("") inside a quoted field — keep both chars,
        // _unescapeField collapses them later.
        buffer.write('""');
        i++;
        continue;
      }
      insideQuotes = !insideQuotes;
      buffer.write(char);
      continue;
    }

    if (char == ',' && !insideQuotes) {
      fields.add(buffer.toString());
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }
  fields.add(buffer.toString());
  return fields;
}
```

Update `_parseColumns`'s comma branch (only) from:
```dart
if (line.contains(',')) {
  return line.split(',').map(_unescapeField).toList();
}
```
to:
```dart
if (line.contains(',')) {
  return _splitCsvLine(line).map(_unescapeField).toList();
}
```

Everything downstream (`_unescapeField`, BPM/tuning validation, dedup) is unchanged — the fix is scoped to *where the comma split happens*, not what happens to each field afterward. An unterminated/unbalanced quote (malformed paste) degrades gracefully: the remainder of the line is treated as inside-quotes and not comma-split, which is acceptable best-effort behavior for a manual-paste tool and is explicitly out of scope to harden further (see Out of Scope).

### Feature #2 — Musical Key column

Thread a new optional `musicalKey` value through the same path BPM/Tuning already use, end to end:

1. **`BulkSongRow`** — add `final String? musicalKey;` (display-ready canonical form, e.g. `"Bm"` — no separate id/label split is needed since, unlike tuning, there is no legacy DB enum to translate from).
2. **`BulkSongParser`** — read an optional 5th column; normalize/validate it against the same canonical key set the existing single-song `key_picker_bottom_sheet.dart` already uses (`_kMajorKeys` / `_kMinorKeys`, 12 + 12 = 24 keys). An unrecognized key is a **non-fatal warning** (row stays valid, `musicalKey` left `null`), mirroring exactly how `unknownTuning` already behaves — never a hard error, per the Feature Input's explicit requirement.
3. **`BulkEntryScreen`** — add a 5th editable "Key" table column (controller + focus node + header + cell), include it in the tab-delimited re-serialization in `_handleSubmit`, and mention it in the CSV textarea hint text.
4. **`SetlistRepository`** — thread `musicalKey` through `bulkAddSongs` → `_createOrFindSong`, writing it as a direct `TEXT` value to `songs.musical_key` (no enum mapping), for both the new-song insert path and the existing-song "enrich if null" path — exactly parallel to how `bpm` is already handled (simple nullable scalar, no translation).

---

## Database Impact

**Migration: not required.**

Confirmed by direct inspection of `supabase/migrations/`:
- `20260630000000_add_musical_key_to_songs.sql`: `ALTER TABLE public.songs ADD COLUMN IF NOT EXISTS musical_key TEXT;` — nullable, **no CHECK constraint**, comment states "values validated by client-side picker." This column already exists in production.
- `20260630000001_add_musical_key_to_update_song_rpc.sql` and `20260703034302_fix_musical_key_clear_in_update_song_rpc.sql` already added/fixed `musical_key` support in the **single-song** `update_song_metadata` RPC (unrelated to this bulk path, not touched by this plan).

The bulk-add path (`bulkAddSongs` → `_createOrFindSong`) does **not** use an RPC — it calls `supabase.from('songs').insert(...)` / `.update(...)` directly. This plan only needs to:
- add `musical_key` to the existing `SELECT` list at repository line ~4060 (`'id, bpm, tuning, duration_seconds, album_artwork'` → add `musical_key`), and
- add a conditional key `insertData['musical_key']` / `updates['musical_key']`, matching the existing `bpm` pattern exactly.

**RLS:** unaffected. `musical_key` is a plain column on `public.songs`; there is no per-column RLS in this schema (Postgres/PostgREST row-level security applies per-row, not per-column) — the same row-level INSERT/UPDATE policy that already permits writing `bpm`/`tuning` via this path covers `musical_key`. No new policy is required.

**RPC:** not required. No signature changes to any RPC (the bulk path doesn't call one).

**Confirmation of Feature Input assumption:** the Feature Input's assumption ("no migration needed since musical_key already exists") is **confirmed correct** by the migration file inspection above.

---

## Flutter Architecture Changes

No new state management, providers, or repositories are introduced — this is a pure extension of the existing unidirectional flow (`BulkEntryScreen` owns row-editing state → serializes → `BulkSongParser` (stateless service) → `onSubmit` callback → `SetlistRepository` (existing provider) → Supabase). No provider wiring changes.

- **Widgets:** `BulkEntryScreen` (`_RowData`, header row, table row, CSV hint text) gains one more column — additive change to an existing `Row`/`Expanded` layout, no new widget classes.
- **Services:** `BulkSongParser` gains one more optional column read + one new private normalization method (`_normalizeKey`, structurally parallel to the existing `_normalizeTuning`).
- **Models:** `BulkSongRow` gains one nullable field + one new `BulkSongValidationError` enum value (`unknownKey`).
- **Repositories:** `SetlistRepository.bulkAddSongs` / `_createOrFindSong` gain one more optional parameter threaded through, following the exact `bpm` pattern (simplest of the three existing fields, since no enum translation is needed).

---

## Files to Create

**None required.**

*Recommended (not mandatory) addition:* `test/features/setlists/services/bulk_song_parser_test.dart` — there is currently **zero** automated test coverage for `BulkSongParser` or `BulkSongRow` (confirmed: no test file anywhere in `test/` references either). Given this fix touches subtle RFC 4180 quote-parsing logic exactly like the kind of logic that produced the original bug, and a second bug (apostrophe corruption) was already found in this same method previously, a focused unit test file is strongly recommended as regression insurance. This is targeted regression coverage for the exact bug being fixed, not opportunistic test-suite expansion, so it does not conflict with the "no opportunistic cleanup" guardrail. Engineer may add this file; QA must not block release solely on its absence, but its absence should be noted in the QA report.

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/services/bulk_song_parser.dart` | Add `_splitCsvLine()` quote-aware splitter; use it in the comma-delimited branch of `_parseColumns` only (bug fix). Add optional 5th-column (`rawKey`) extraction, a `_normalizeKey()` validator mirroring `_normalizeTuning()` against the canonical 24-key set, and thread `musicalKey`/`keyWarning` into the `BulkSongRow.valid(...)` construction and the warning-priority chain (`bpmWarning ?? tuningWarning ?? keyWarning`). Update class/method doc comments to mention the 5th column. |
| `lib/features/setlists/models/bulk_song_row.dart` | Add `unknownKey` to `BulkSongValidationError` enum. Add `final String? musicalKey;` field to `BulkSongRow`, threaded through the constructor and both `.valid()` and `.invalid()` factories (matching how `bpm`/`tuning` are already present in both factories). Add a `formattedKey` getter (parallel to `formattedTuning`) for preview display. |
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | `_RowData`: add `key` `TextEditingController` + `keyFocus` `FocusNode`, dispose both, include in `isEmpty` check. Add `_kFlexKey` layout constant (suggest rebalancing existing flex values, e.g. Artist 3 / Song 3 / BPM 2 / Tuning 2 / Key 2 — exact values are a cosmetic judgment call for the Engineer as long as all 5 columns + delete button remain usable on narrow screens). `_buildColumnHeaders()`: add a "Key" header cell. `_buildRow()`: add the Key `_tableCell`. `_populateTableFromParseResult()`: seed `row.key.text = parsed.musicalKey ?? ''`. `_handleSubmit()`: append the Key column to the tab-delimited re-serialization buffer. Update the CSV textarea's `hintText` to mention the Key column (e.g. `'Artist, Song, BPM, Tuning, Key'`). |
| `lib/features/setlists/setlist_repository.dart` | `bulkAddSongs()` (~line 3920): pass `musicalKey: row.musicalKey` into `_createOrFindSong(...)`. `_createOrFindSong()` (~lines 4040–4137): add `String? musicalKey` parameter; add `musical_key` to the existing-song lookup `SELECT` list (~line 4060); add enrichment branch `if (musicalKey != null && existing[0]['musical_key'] == null) updates['musical_key'] = musicalKey;` (~after line 4087); add `if (musicalKey != null && musicalKey.isNotEmpty) insertData['musical_key'] = musicalKey;` to the new-song insert map (~after line 4117). No RPC, no enum mapping needed (unlike `tuning`). |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Init order must not change — unrelated to this feature. |
| `supabase/migrations/*.sql` | No migration needed; `musical_key` column already exists. Do not create a new migration file. |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart` | Read-only reference for the canonical key list (`_kMajorKeys`/`_kMinorKeys`). This is the single-song key-picker UI, unrelated to bulk import — do not modify it. If the canonical key list needs to change in the future, that is a separate decision affecting both single-song and bulk flows. |
| `lib/features/setlists/tuning/tuning_helpers.dart` / `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` | Tuning is a separate concept from musical key (different field, different DB representation — enum vs free-text). Per the Feature Input's explicit instruction, the Key feature must not reuse the tuning field or its normalization map. Do not touch. |
| `lib/features/setlists/models/setlist_song.dart` | `musicalKey` read-side is already fully wired (line 39/109) — no change needed. |
| `lib/features/setlists/setlist_detail_controller.dart`, `song_details_bottom_sheet.dart`, `song_card.dart`, `reorderable_song_card.dart`, `setlist_print_service.dart` | These already handle `musicalKey` display/editing for the single-song flow — out of scope, no change needed for bulk import. |
| `lib/features/setlists/new_setlist_screen.dart`, `lib/features/setlists/setlist_detail_screen.dart` (the `onBulkSongsSubmitted` wrapper functions) | Both are thin pass-throughs (`repository.bulkAddSongs(rows: validRows)`) that forward `BulkSongRow` objects unchanged — no transformation logic lives here, so no change is needed once `BulkSongRow` itself carries `musicalKey`. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed (no CSV parsing package required — inline quote-aware splitter is sufficient, consistent with the prior apostrophe-corruption fix's explicit rejection of a third-party CSV dependency)
**New files:** none required; one recommended test file (see Files to Create)

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — bulk import parsing fixed + extended; every bulk-add call also always adds to the band's Catalog setlist, so Catalog is affected identically to the target setlist |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected uniformly** — shared Dart parsing/repository logic, no platform-specific code paths |

---

## Regression Risk

**LEVEL: LOW**

Rationale:
- No auth, session, routing, or init-order changes.
- No RLS policy changes; no RPC signature changes; no new migration.
- The comma-split fix only changes behavior for inputs that contain a quoted field with an internal comma — the exact case that is already broken today. Simple comma-delimited rows with no embedded commas (the common case) produce byte-identical output under the new splitter, since `_splitCsvLine` only differs from `.split(',')` when it encounters a `"` character.
- The Key column is purely additive (new optional field, new optional column, new optional UI column) — no existing field, column, or UI element is removed or renamed.
- Both call sites of `bulkAddSongs` (`new_setlist_screen.dart`, `setlist_detail_screen.dart`) are unmodified pass-throughs, so there is only one repository code path to verify.

One specific point requiring careful QA/Engineer attention (called out explicitly rather than rated as high risk): the existing-song lookup `SELECT` string in `_createOrFindSong` is a hot path executed once per row on every bulk-add call — adding `musical_key` to that select list must be verified not to break existing bpm/tuning/duration/album_artwork enrichment behavior for rows that don't specify a key.

---

## Engineer Task Breakdown

Execute in order:

### Task 1 — Fix comma corruption (`bulk_song_parser.dart`)
1. Add `_splitCsvLine()` (quote-aware comma splitter) as a new private method.
2. Update `_parseColumns`'s comma-delimited branch only, to call `_splitCsvLine(line).map(_unescapeField).toList()` instead of `line.split(',').map(_unescapeField).toList()`.
3. Do not touch the tab-delimited or 2+-space fallback branches.

### Task 2 — Add Key to the data model (`bulk_song_row.dart`)
1. Add `unknownKey` to `BulkSongValidationError`.
2. Add `final String? musicalKey;` field; thread through the main constructor and both `.valid()`/`.invalid()` factories.
3. Add `formattedKey` getter (e.g. `musicalKey ?? '-'`).
4. Leave `dedupeKey`, `==`, and `hashCode` unchanged — they already exclude `tuningLabel`/`warning` by existing design (identity is artist+title+bpm+tuning today); do not expand scope to also key on `musicalKey` unless later explicitly required.

### Task 3 — Parse and validate Key (`bulk_song_parser.dart`)
1. Extract optional 5th column: `final rawKey = columns.length > 4 ? columns[4].trim() : '';`.
2. Add `_normalizeKey(String input)` mirroring the structure of `_normalizeTuning`:
   - Canonical set = the 12 major + 12 minor keys from `key_picker_bottom_sheet.dart`'s `_kMajorKeys`/`_kMinorKeys` (duplicated locally in the parser, matching the existing precedent where tuning IDs are also locally duplicated rather than cross-imported from the picker widget — the parser is a service and should not import a widget file).
   - Case-insensitively normalize common minor-suffix variants (`m`, `min`, `minor`, with or without a preceding space) to a trailing lowercase `m`; normalize a trailing `major`/`maj` to no suffix.
   - Uppercase the root note letter; preserve `#`/`b` accidental as the second character where present.
   - If the normalized result matches a canonical key exactly, return it; otherwise return `null`.
3. If `rawKey` is non-empty and normalization fails → set `keyWarning = BulkSongValidationError.unknownKey`, `keyWarningMessage = 'Unknown key ignored'`, leave `musicalKey` as `null` (row stays valid — non-fatal, matching `unknownTuning`'s exact behavior per the Feature Input's explicit requirement).
4. Extend the warning-priority chain: `final warning = bpmWarning ?? tuningWarning ?? keyWarning;` (and matching message chain).
5. Pass `musicalKey` into the `BulkSongRow.valid(...)` call.
6. Do **not** implement enharmonic aliasing (e.g. treating "Db" as equivalent to "C#") — exact-match-after-normalization only (see Out of Scope).

### Task 4 — Add Key column to the UI (`bulk_entry_screen.dart`)
1. `_RowData`: add `key` controller + `keyFocus` node, dispose both, add to `isEmpty`.
2. Add `_kFlexKey` constant; rebalance existing flex constants for 5 columns.
3. `_buildColumnHeaders()`: add Key header cell.
4. `_buildRow()`: add Key `_tableCell`.
5. `_populateTableFromParseResult()`: seed `row.key.text = parsed.musicalKey ?? ''`.
6. `_handleSubmit()`: append `${r.key.text.trim()}` as the 5th tab-delimited field in the re-serialization buffer.
7. Update CSV textarea `hintText` to mention `Key` as a 5th column and give an example (e.g. `'Aerosmith, Eat The Rich, 123, Standard, G'`).

### Task 5 — Thread Key through the repository (`setlist_repository.dart`)
1. `bulkAddSongs()`: pass `musicalKey: row.musicalKey` to `_createOrFindSong(...)`.
2. `_createOrFindSong()`: add `String? musicalKey` parameter.
3. Add `musical_key` to the existing-song lookup's `.select(...)` string.
4. Add enrichment: `if (musicalKey != null && existing[0]['musical_key'] == null) { updates['musical_key'] = musicalKey; }`.
5. Add insert: `if (musicalKey != null && musicalKey.isNotEmpty) { insertData['musical_key'] = musicalKey; }`.

### Task 6 (recommended) — Unit tests
Add `test/features/setlists/services/bulk_song_parser_test.dart` covering at minimum: quoted-comma title (bug #1 repro case), plain comma-delimited (no regression), tab-delimited (no regression), valid/invalid/unknown key values, and the combination of an internal-comma title with a trailing Key column.

### Task 7 — `flutter analyze`
Ensure `0 errors` before handing off to QA.

---

## Verification Plan

Per ARCHITECT.md, verification is split into two tiers. **This feature involves no database migration**, so the SQL-specific Tier 1/Tier 2 mechanics (pre-deploy helper-function tests, post-deploy `pg_get_functiondef` checks) do not apply. The tiers are adapted below to this client-side-only change, keeping the same pre-deploy/post-deploy split in spirit:

### Tier 1 — Pre-deployment (before merge / before any deploy)
These can all run against the **current, unmodified** database — they exercise only client-side parsing logic and existing, unmodified repository/table behavior.

- **PRE-DEPLOY TEST 1:** Unit/manual test — paste `"John Denver","Take Me Home, Country Road"` into Bulk Entry, tap Load Songs. Assert the preview table shows exactly one row: Artist = `John Denver`, Song = `Take Me Home, Country Road` (bug #1 repro, must now pass).
- **PRE-DEPLOY TEST 2:** Regression — paste `Aerosmith, Eat The Rich, 123, Standard` (no embedded commas, per the existing UI hint text). Assert identical output to current production behavior (Artist=Aerosmith, Song=Eat The Rich, BPM=123, Tuning=Standard).
- **PRE-DEPLOY TEST 3:** Regression — repeat the three Google-Sheets-apostrophe test cases from `docs/features/bulk-entry-apostrophe-corruption/ARCHITECT_PLAN.md` (Tier 2, Tests 1–3) to confirm the new comma-splitter does not regress the prior apostrophe/quote-unescaping fix.
- **PRE-DEPLOY TEST 4:** Paste `Van Halen, Poundcake, 118, Standard, Eb` — assert Key column preview shows `Eb`.
- **PRE-DEPLOY TEST 5:** Paste a row with an unrecognized key, e.g. `Van Halen, Poundcake, 118, Standard, Zzz` — assert the row is still valid (submittable) with a non-fatal "Unknown key ignored" warning badge, and `musicalKey` is `null`.
- **PRE-DEPLOY TEST 6 (SQL, read-only, no schema change):** Confirm the assumption in a `DO $$` block / direct `SELECT` against the **existing, unmodified** database: `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'songs' AND column_name = 'musical_key';` — expect one row, `data_type = 'text'`, `is_nullable = 'YES'`. This does not touch the function being modified (there is no function being modified — the bulk path is direct table access) and requires zero schema changes.

### Tier 2 — Post-deployment (after merge, in the running app)
- **POST-DEPLOY TEST 1:** Full end-to-end — paste `"John Denver","Take Me Home, Country Road",118,Standard,G` (comma-delimited with internal comma AND a key), Load Songs, Add Songs. Assert the song appears in the setlist and in Catalog with the full title, and its key badge shows `G`.
- **POST-DEPLOY TEST 2:** Confirm via direct query (or via the app's song-details view) that `songs.musical_key = 'G'` for the newly created song — i.e. the value actually persisted, not just displayed in the preview table.
- **POST-DEPLOY TEST 3:** Edit an existing song's key via the existing single-song key picker (`key_picker_bottom_sheet.dart` flow) after it was created via bulk import with a key — confirm no conflict between the two write paths (bulk-insert vs. `updateSongMusicalKey` RPC) for the same column.
- **POST-DEPLOY TEST 4:** Re-import the *same* Artist+Song via bulk paste a second time with a different key value, where the first-created song already has a non-null key — assert the enrichment logic does **not** overwrite the existing key (matches the "never overwrite non-null" rule already established for `bpm`/`tuning`).
- **Production verification query:** `SELECT id, title, artist, musical_key FROM songs WHERE band_id = '<test band id>' ORDER BY created_at DESC LIMIT 10;` — confirm no unexpected `NULL`/malformed values were written for the rows created during QA.

### SQL test authoring rules
No SQL migrations are introduced by this plan, so no INSERT/UPDATE test cleanup rules apply beyond the standard practice of using a disposable test band/setlist for the manual QA passes above and deleting the test songs afterward.

---

## QA Regression Areas

QA must specifically test:
1. **Primary fix:** quoted CSV field with internal comma no longer truncates the song title (bug #1 repro from the Feature Input, verbatim).
2. **Key import (feature):** valid key values parse, preview, and persist correctly; unrecognized key values produce a non-fatal warning, not a hard error.
3. **No regression — plain comma-delimited paste** (the documented example format in the UI hint text).
4. **No regression — tab-delimited spreadsheet paste** (untouched code path, but must be re-verified since it shares the parser class).
5. **No regression — apostrophe/quote un-escaping** (prior fix in the same method; see `docs/features/bulk-entry-apostrophe-corruption/`).
6. **No regression — BPM/Tuning bulk import**, including the "never overwrite existing non-null value" enrichment behavior, now extended to Key.
7. **Table→submit round-trip:** manually editing the Key cell in the preview table before tapping "Add Songs" must carry through correctly (the re-serialize/re-parse path in `_handleSubmit`).
8. **Catalog + target setlist:** confirm songs added via bulk import (with title-comma and/or key) appear correctly in both the band's Catalog and the target setlist, per existing `bulkAddSongs` behavior.
9. **Cross-platform:** repeat primary fix test on Web, iOS, Android, and macOS — this is shared Dart logic with no platform branches, but must be confirmed on at least two platforms given "Affected Platforms: Web / iOS / Android / macOS" in the Feature Input.

---

## Rollout / Migration Strategy

Not applicable — pure client-side change, no backend deploy, no migration, no feature flag. Standard release: merge → build → deploy per `docs/agents/OPERATING_MODEL.md`'s deployment protocol (`./tools/deploy_web.sh` for web; standard app store / TestFlight process for iOS/Android/macOS, outside this plan's scope).

---

## Out of Scope

Explicitly excluded from this fix:
1. **Third-party CSV parsing library** — the inline quote-aware splitter is sufficient; no new dependency is introduced or needed (consistent with the prior apostrophe-corruption fix's explicit rejection of a CSV package dependency).
2. **Enharmonic key aliasing** (e.g. treating "Db" as equivalent to "C#", or "G#" as equivalent to "Ab") — only exact matches (after case/suffix normalization) against the canonical 24-key set are accepted; anything else is a non-fatal "unknown key" warning.
3. **Multi-character-delimiter or nested-quote edge cases beyond RFC 4180** — malformed/unbalanced quotes degrade gracefully (remainder of line treated as quoted) but are not specially detected or error-reported.
4. **Historical data cleanup** — songs already corrupted by the comma bug (titles already truncated in existing setlists/catalogs) are **not** automatically repaired by this fix; affected users must manually re-edit or re-import those songs. This matches the precedent set by the apostrophe-corruption fix.
5. **Bulk *edit* flows** — only the bulk *add* path (`BulkEntryScreen` → `bulkAddSongs`) is fixed; if an equivalent CSV comma-splitting bug exists elsewhere (e.g. a bulk-edit or CSV-export/re-import round trip), it is a separate ticket.
6. **Changing the canonical key list itself** — the 24-key set in `key_picker_bottom_sheet.dart` is treated as authoritative and unmodified; if it needs new keys added in the future, that's a separate decision affecting both single-song and bulk flows.
7. **Performance optimization** of the parser for very large pastes — no profiling/optimization required unless QA reports noticeable lag beyond the existing `_kMaxRows = 500` cap.

---

**Architect Signature:** Plan complete. Ready for Engineer implementation.
