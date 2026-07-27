# QA Report

## Feature Slug
`bug/csv-import-comma-and-key`

## Feature Title
CSV Import Comma Corruption + Musical Key Column

## Final Verdict
**APPROVED**

## Validation Summary
Verified via full-file `git diff` review against `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md`, static code-path tracing of the new `_splitCsvLine`/`_normalizeKey` logic and the repository enrich/insert paths, and execution of `flutter analyze` (0 issues) and `flutter test` (29/29 passing, including the 12 new tests in `bulk_song_parser_test.dart`). All 9 QA Regression Areas from the Architect Plan were validated at the Tier 1 (pre-deployment, client-side/parsing) level via automated tests and manual trace of the algorithm against hand-picked inputs. **Tier 2 (post-deployment) tests — the ones requiring a running app with live Supabase writes — were NOT executed**, consistent with the Architect Plan's own two-tier design (Tier 2 is explicitly scoped as "after merge, in the running app") and the Engineer's explicit flag; this QA session has read-only file access and no interactive device/UI-automation tooling, so these must be run by a human (or an app-driving session) post-merge per the plan's Verification Plan.

## Architect Scope Review
- Scope adherence: compliant
- Files modified: exactly as expected — `bulk_song_parser.dart`, `bulk_song_row.dart`, `bulk_entry_screen.dart`, `setlist_repository.dart`, plus the recommended (not mandatory) new test file `test/features/setlists/services/bulk_song_parser_test.dart`
- Files off-limits: not touched — explicitly re-verified via `git diff --stat` against every file in the plan's "Files Off-Limits" table (`lib/main.dart`, `supabase/migrations/*`, `key_picker_bottom_sheet.dart`, `tuning_helpers.dart`, `tuning_picker_bottom_sheet.dart`, `setlist_song.dart`, `setlist_detail_controller.dart`, `new_setlist_screen.dart`, `setlist_detail_screen.dart`) — zero diff output for all

## Completeness Check
- All Architect tasks implemented: yes (Tasks 1–7, including the recommended Task 6 unit-test file)
- Missing tasks: none

## Behavior Verification
- Validation method: code-path analysis + automated unit tests (Tier 1 only — no runtime/device testing performed in this session)
- Result: matches expected

Detail:
- **Task 1 (comma-splitter):** Hand-traced `_splitCsvLine` character-by-character against `"John Denver","Take Me Home, Country Road"` — confirms exactly 2 fields are produced (title preserved with internal comma intact), matching the checked-in test and the bug repro in the plan. The splitter differs from `.split(',')` only when a `"` is encountered, so plain comma rows with no quoting are byte-identical to prior behavior (confirmed by the "plain comma-delimited" test still passing).
- **`_unescapeField` regression:** confirmed **byte-identical** to the prior apostrophe-corruption fix — the diff shows no changes to this function, only new code added around it. This guarantees the prior fix (doubled-apostrophe/doubled-quote un-escaping) cannot regress from this change, independent of test coverage.
- **`_normalizeKey`:** hand-traced the minor/major regex patterns against ambiguous inputs (`Bb` vs `Bm`, `Ebm`, `C# minor`, `bm`, `B min`) to confirm no false-positive minor/major misclassification; all traces match canonical output and match the checked-in test assertions (all passing).
- **Repository enrichment/insert:** read `_createOrFindSong` in full — `musical_key` enrichment follows the exact "only set if row is currently null" pattern already used for `bpm`/`tuning`/`duration_seconds`/`album_artwork` (line ~4098), and the new-song insert conditionally sets `musical_key` only if non-empty (line ~4133), mirroring the `bpm` pattern precisely as the plan required.
- **Catalog + target setlist:** read `bulkAddSongs` in full — Step 3 always adds the song to Catalog, Step 4 adds to the target setlist if different; this logic is completely unmodified by the diff (only `musicalKey: row.musicalKey` was added to the `_createOrFindSong` call), so no regression risk here at the code level.
- **Table→submit round-trip:** read `_handleSubmit`'s re-serialization — 5 tab-delimited fields written in the order `artist\tsong\tbpm\ttuning\tkey`, exactly matching the parser's `columns[0..4]` indexing. Re-parse goes through the same `BulkSongParser.parse` already covered by the unit suite, so a manually-edited Key cell (e.g. typing `C# minor`) round-trips correctly per the same normalization logic already verified.
- **Database assumption confirmed:** read `supabase/migrations/20260630000000_add_musical_key_to_songs.sql` directly — nullable `TEXT`, no `CHECK` constraint, matching the plan's claim exactly.

## Regression Check
- Risk level: **LOW**
- Systems reviewed: Setlists/Catalog (bulk import parsing + repository write path), Platform (checked for platform-conditional code — none present in the diff, confirming the plan's "affected uniformly, no platform branches" claim)
- Regressions found: none

## Database Safety
Verified. No migration in this diff (correctly — column already exists per `20260630000000_add_musical_key_to_songs.sql`, confirmed nullable TEXT with no CHECK constraint). No RLS policy changes. No RPC signature changes (bulk path uses direct table access, not an RPC). `musical_key` enrichment/insert logic follows the established `bpm` pattern exactly — no privilege escalation, no destructive/cascade behavior.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!" (confirms Engineer Report's claim)

## Test Results
Passed — `flutter test`: 29/29 passed, including all 12 new tests in `test/features/setlists/services/bulk_song_parser_test.dart` (quoted-comma title repro, plain comma-delimited regression, tab-delimited regression, apostrophe un-escaping regression, comma+Key combination, valid key normalization incl. minor-suffix variants and "major" suffix, unknown-key non-fatal warning, no-enharmonic-aliasing, missing Key column). No pre-existing tests regressed.

## Diff Safety Review
- Secrets: none found
- Debug artifacts: none of concern — two new `debugPrint(...)` calls in `_normalizeKey` are gated behind `kDebugMode`, exactly mirroring the pre-existing pattern already used by `_normalizeTuning` in the same file. Not a new pattern, not left-over scaffolding.
- Unrelated changes: none — diff is scoped exactly to the four approved files plus the one recommended test file; no formatting-only churn observed anywhere in the diff

## Issues Found

### Critical (must fix before commit)
None.

### Warnings (should fix)
None.

### Suggestions (optional)
1. **Tier 2 post-deployment tests remain outstanding** (Verification Plan Tests 1–4: end-to-end Catalog/setlist persistence via a running app, single-song key-picker write-path conflict check, and the re-import "never overwrite non-null key" check under live Supabase). These require a running app instance with UI interaction and a live Supabase project — this QA session had read-only file access and no device/UI-automation tooling to execute them. They should be run by a human tester (or an app-driving agent session) immediately after merge, per the Architect Plan's own "Tier 2 — Post-deployment (after merge, in the running app)" framing — this is not a pre-merge blocker per the plan's own design, but should not be silently skipped either.
2. No explicit test exists for a comma-delimited field combining an internal comma **and** an escaped double-quote in the same title (e.g. `"Say ""Hi"", Bob",120,Standard`) — a narrow edge case not required by the plan's regression areas list. Hand-trace during this QA session confirmed correct behavior for this combination, but a regression test would be cheap insurance given this exact code path (RFC 4180 quote/comma interaction) produced the original bug and a prior apostrophe bug.
