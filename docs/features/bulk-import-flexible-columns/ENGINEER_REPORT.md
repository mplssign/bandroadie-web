# Engineer Report

## Feature Slug
`feature/bulk-import-flexible-columns`

## Feature Title
Bulk Import Flexible Columns + Updated Instructional Copy

## Goal
Update the Bulk Entry screen's instructional copy (three lines above the paste field) and placeholder text to the exact wording specified by the Architect, and confirm the underlying parser correctly handles 2–5 column variable-width rows including the Key column (copy-only change, no parser logic touched).

**Note on report history:** an earlier version of this file (from before this branch was fast-forwarded to include the merged `bug/csv-import-comma-and-key` work) flagged a blocker: Key-column support did not yet exist in `bulk_song_parser.dart`/`bulk_song_row.dart`/`setlist_repository.dart`. That was accurate for the branch state at the time it was written. `ARCHITECT_PLAN.md`'s "THIRD PASS, FINAL" root-cause section documents that this branch has since been fast-forwarded so that commit `7dd9785` (which adds real Key-column parsing/storage) is now an ancestor of `HEAD`, identical to `origin/main`. This report reflects a fresh implementation and verification pass against that current, merged state, and supersedes the earlier version of this file. The blocker described previously no longer applies — see Verification below.

## Architect Tasks Completed
- [x] Task 1 — Replaced the single instructional `Text` widget with three `Text` widgets, exact copy as specified, each its own line. Line 1 kept existing style (`Colors.white` / `AppFontSizes.subhead`). Lines 2–3 use `context.colors.textSecondary` / `AppFontSizes.caption` (an existing pattern already used elsewhere in this file). Spacing uses `Spacing.space4` between the three text lines and preserves the existing `Spacing.space8` before the `TextField`.
- [x] Task 2 — Replaced `hintText` with exactly `Column order: Artist, Song, BPM, Tuning, Key` (single line, no example — the sibling PR's multi-line "e.g." hint was removed entirely).
- [x] Task 3 — `flutter analyze`: 0 errors, 0 warnings.
- [x] Task 4 (verification) — Confirmed 2/3/4/5-column parsing, comma- and tab-delimited, mixed multi-line paste, and the <2-column rejection case all behave per the plan. **The Key column is genuinely parsed and populated on this branch's current `HEAD`** — no gap found.

## Files Created
none

## Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (ran full-project; also ran scoped to the changed file with the same result)

## Test Results
Not run via `flutter test` as a permanent addition (no test file is in the Architect plan's Files to Modify/Create). The existing `test/features/setlists/services/bulk_song_parser_test.dart` was run for context and passes (11/11) — confirms no regression from this diff, and independently confirms Key-column normalization already works (e.g. `Van Halen, Poundcake, 118, Standard, Eb` → `musicalKey: 'Eb'`).

For Task 4, a temporary scratch test file (`test/_scratch_verify_bulk_columns_test.dart`) was created, run, and deleted within this session — not part of the diff or final repo state (confirmed via `git status` afterward: only `bulk_entry_screen.dart` shows as modified).

## Verification
Manual/automated steps performed (Task 4, Pre-Deploy Tests 3–9), using the temporary throwaway test harness described above, calling `BulkSongParser.instance.parse()` directly:

| Input | Result |
|---|---|
| `Led Zeppelin, Rock and Roll` (comma, 2-col) | artist=Led Zeppelin, title=Rock and Roll, bpm=null, tuning=null, musicalKey=null — valid, no error |
| `Led Zeppelin, Rock and Roll, 172` (comma, 3-col) | bpm=172, tuning=null, musicalKey=null — valid |
| `Led Zeppelin, Rock and Roll, 172, Standard` (comma, 4-col) | bpm=172, tuning=Standard, musicalKey=null — valid |
| `Led Zeppelin, Rock and Roll, 172, Standard, A` (comma, 5-col) | bpm=172, tuning=Standard, **musicalKey=A** — valid, Key correctly captured |
| Same 4 cases, tab-delimited | Identical results to comma cases, including the 5th column (Key) correctly captured |
| `SingleWordNoDelimiter` (< 2 columns) | Correctly flagged invalid — `validRows` empty, `invalidRows` length 1 |
| Mixed 4-line multi-column paste (distinct song titles per line) | All 4 rows parsed independently and correctly, no column bleed between rows |

Conclusion: Pre-Deploy Tests 3–9 all pass exactly as the Architect plan's final (third) pass predicted. Unlike the superseded version of this report, Test 6 (5-column, Key) and the Key portion of Test 8 now pass — `rawKey`/`musicalKey`/`_normalizeKey()` exist and are wired end-to-end in `bulk_song_parser.dart` on this branch's current `HEAD`.

One correction made mid-verification: the first draft of the Test 7 harness used identical Artist/Song text on all four lines, which triggered the parser's existing within-batch dedup logic (`seenKeys`/`dedupeKey` in `bulk_song_parser.dart`) and collapsed 4 rows to 1. That is correct, intentional parser behavior (avoids adding the same song twice from one paste), not a bug — the harness was corrected to use distinct song titles per line so it actually tests "no column bleed" rather than dedup.

Copy rendering (Pre-Deploy Tests 1–2) and cross-platform line-wrap (part of Test 7 in QA Regression Areas) were verified by direct code read of the edited widget tree (three `Text` widgets in order with exact strings; `hintText` exact single-line string) rather than a live app screenshot — no running emulator/simulator was available in this session. Recommend QA do a quick visual pass per the plan's Tier 1 Tests 1–2 and the narrow-mobile-screen line-wrap check called out in QA Regression Area 7.

## Deviations From Architect Plan
None. Tasks 1 and 2 were implemented exactly as specified, verbatim text, no files outside `bulk_entry_screen.dart` touched. `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, `lib/main.dart`, migrations, and the pass-through caller files were not modified, per the plan's Files Off-Limits list. Column-header layout/styling (`_buildColumnHeaders`/`_buildRow`) and other Key-column table UI added by the sibling PR were not touched.

## Blockers Encountered
None. (The prior version of this report's blocker — Key column silently dropped — was accurate for the pre-fast-forward branch state and does not apply to the current, merged `HEAD`; verified directly, not assumed.)

## Ready For QA
Yes. Copy change is complete, verbatim-correct, and analyzer-clean. Parser-level verification confirms all of Pre-Deploy Tests 3–9, including full Key-column support, pass on this branch's current state. QA should still perform the live-app visual checks (Tier 1 Tests 1–2, and the cross-platform line-wrap check in QA Regression Area 7) since no emulator was available in this session.

---

## Full git diff

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d5bb81c..ab4d684 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -371,6 +371,23 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   fontSize: AppFontSizes.subhead,
                 ),
               ),
+              const SizedBox(height: Spacing.space4),
+              Text(
+                'Column order: Artist, Song, BPM, Tuning, Key '
+                '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                style: TextStyle(
+                  color: context.colors.textSecondary,
+                  fontSize: AppFontSizes.caption,
+                ),
+              ),
+              const SizedBox(height: Spacing.space4),
+              Text(
+                'Required: Artist, Song (Optional BPM, Tuning, Key)',
+                style: TextStyle(
+                  color: context.colors.textSecondary,
+                  fontSize: AppFontSizes.caption,
+                ),
+              ),
               const SizedBox(height: Spacing.space8),
               TextField(
                 controller: _csvController,
@@ -383,9 +400,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   fontFamily: 'monospace',
                 ),
                 decoration: InputDecoration(
-                  hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning, Key\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
+                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
```

---

## Additional Tony-requested UI tweaks (mid-session, not in Architect plan)

**Scope note:** everything below was requested directly by Tony (product owner) mid-session, after the Task 1–4 work above was already implemented. It is **not** derived from `ARCHITECT_PLAN.md` and was not reviewed by the Architect. It is typography/layout-only — no text content changed from what Task 1–2 already established. Documented as a separate, separately-reviewable change so QA can scope it independently from the Architect-driven work above.

### What changed

1. **Split the combined second instructional line into two lines.** It previously rendered as a single `Text` widget:
   `Column order: Artist, Song, BPM, Tuning, Key (Led Zeppelin, Rock and Roll, 172, Standard, A Major)`
   Now it is two separate `Text` widgets, each its own line (text content unchanged, just split at the point where the parenthetical begins):
   - `Column order: Artist, Song, BPM, Tuning, Key`
   - `(Led Zeppelin, Rock and Roll, 172, Standard, A Major)`

2. **Increased font sizes on four lines**, all via `AppFontSizes` tokens (`lib/app/theme/design_tokens.dart:309-324`: `caption=13`, `subhead=14`, `body=16`, in ascending order with no token between `caption` and `subhead` or between `subhead` and `body`):
   - `Paste songs from a spreadsheet, then tap Load Songs.` — `AppFontSizes.subhead` (14) → `AppFontSizes.body` (16). This was already the largest token in use on this screen's instructional block, so the next larger token in the scale is `body`.
   - `Column order: Artist, Song, BPM, Tuning, Key` — `AppFontSizes.caption` (13) → `AppFontSizes.subhead` (14), the next token up from `caption`.
   - `(Led Zeppelin, Rock and Roll, 172, Standard, A Major)` — set to `AppFontSizes.subhead` (14) to match the line directly above it, per Tony's explicit instruction that this line take the same new size as its sibling rather than keeping its old `caption` size.
   - `Required: Artist, Song (Optional BPM, Tuning, Key)` — `AppFontSizes.caption` (13) → `AppFontSizes.subhead` (14), same reasoning as the "Column order" line.

   No `AppFontSizes` token existed between `caption`/`subhead` or between `subhead`/`body`, so each was moved to the very next token in the existing scale — no new token was introduced and no value was guessed outside the existing design-token set.

3. **Colors unchanged:** line 1 stays `Colors.white`; all other lines stay `context.colors.textSecondary` (now four lines instead of three, all secondary-colored).

4. **Spacing:** added a `SizedBox(height: Spacing.space4)` between every pair of the four lines (previously there were three lines with two `space4` gaps; now there are four lines with three `space4` gaps, consistent with the existing spacing convention already used in this block). The `Spacing.space8` gap before the `TextField` is unchanged.

### Files Modified (this section only)
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (same file as Task 1–2; no other files touched)

### Analyzer Results (this section only)
Command: `flutter analyze` (run scoped to the file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 2 (further Tony-requested tweak, same session)

After the round-1 tweaks above landed, Tony asked for one more adjustment to the "Column order" line specifically:

- **`Column order:`** — split off as its own line (previously the leading fragment of the combined `Column order: Artist, Song, BPM, Tuning, Key` line from round 1). Font size **unchanged** at `AppFontSizes.subhead` (14) — Tony's instruction was "same font-size." Color changed from `context.colors.textSecondary` to `Colors.white`, per Tony's explicit instruction.
- **`Artist, Song, BPM, Tuning, Key`** — new line, placed directly under `Column order:`. Font size bumped to `AppFontSizes.body` (16), the next token up from `subhead`, per Tony's "larger font-size" instruction. Color set to `Colors.white`, per Tony's explicit instruction.
- The parenthetical example line (`(Led Zeppelin, Rock and Roll, 172, Standard, A Major)`) and the `Required: Artist, Song (Optional BPM, Tuning, Key)` line were **not** mentioned in this round's request and were left exactly as round 1 set them (`AppFontSizes.subhead`, `context.colors.textSecondary`) — not touched.
- Spacing: kept the same `SizedBox(height: Spacing.space4)` pattern between every line; the instructional block is now five lines (was four after round 1) with four `space4` gaps between them, plus the existing `space8` gap before the `TextField`.

This means the four originally-secondary-colored lines from round 1 are now split: two lines (`Column order:` and `Artist, Song, BPM, Tuning, Key`) are white, and two lines (the parenthetical and `Required...`) remain `textSecondary`. This asymmetry is intentional per Tony's instruction, not an oversight.

#### Analyzer Results (round 2)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 3 (further Tony-requested tweak, same session)

Tony asked for more space above the paste `TextField`. The gap between the last instructional line ("Required: Artist, Song (Optional BPM, Tuning, Key)") and the `TextField` was `SizedBox(height: Spacing.space8)` (8px) — bumped to `Spacing.space16` (16px), the next commonly-used token up in the existing `Spacing` scale (`lib/app/theme/design_tokens.dart:9-28`: `space8=8`, `space10=10`, `space12=12`, `space13=13`, `space14=14`, `space16=16`). Chose `space16` rather than the immediately-adjacent `space10`/`space12`/`space13`/`space14` tokens because it's a clean doubling of the prior value and a round, commonly-reused spacing token elsewhere in this same file (used at `Padding` on line 359), giving a clearly noticeable increase rather than a marginal one. No other spacing (between the five text lines themselves) changed in this round.

#### Analyzer Results (round 3)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 4 (further Tony-requested tweak, same session)

Tony asked for more space under "Paste songs from a spreadsheet, then tap Load Songs." — i.e. the gap between line 1 and "Column order:". That gap was `SizedBox(height: Spacing.space4)` (4px) — bumped to `Spacing.space12` (12px), a tripling, for a clearly noticeable increase without pushing the instructional block to the same 16px gap already used before the `TextField` (round 3), keeping the pre-field gap visually the largest/most-separating one in the block. No other spacing in the block changed in this round.

#### Analyzer Results (round 4)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 5 (further Tony-requested tweak, same session)

Tony asked to wrap the following four lines in a rose border:
`Column order:` / `Artist, Song, BPM, Tuning, Key` / `(Led Zeppelin, Rock and Roll, 172, Standard, A Major)` / `Required: Artist, Song (Optional BPM, Tuning, Key)`

Implementation: wrapped exactly those four `Text` widgets (and the three `SizedBox(height: Spacing.space4)` gaps between them, unchanged from round 2–4) in a `Container` with:
- `decoration: BoxDecoration(border: Border.all(color: AppColors.primary), borderRadius: BorderRadius.circular(8))` — `AppColors.primary` (`lib/app/theme/design_tokens.dart:150`, `0xFFBE123C`) is the only rose token defined in this codebase's design-token file ("Palette: ... Rose-500 for brand" / "Never use `Color(0xFF...)` outside this file"), so it was used rather than a new hardcoded color.
- `borderRadius: BorderRadius.circular(8)` matches the radius already used on the `TextField`'s borders directly below in this same file, for visual consistency.
- `padding: const EdgeInsets.all(Spacing.space8)` — inset so the border doesn't sit flush against the text, using an existing `Spacing` token rather than a new literal.

"Paste songs from a spreadsheet, then tap Load Songs." (line 1) and the `Spacing.space12`/`Spacing.space16` gaps immediately above/below the bordered block (rounds 3–4) are outside the `Container` and unaffected.

#### Analyzer Results (round 5)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 6 (further Tony-requested tweak, same session)

Tony asked for `Required: Artist, Song (Optional BPM, Tuning, Key)` to match `Artist, Song, BPM, Tuning, Key`'s color and font size exactly. Changed from `context.colors.textSecondary` / `AppFontSizes.subhead` (14) to `Colors.white` / `AppFontSizes.body` (16) — an exact copy of the sibling line's `TextStyle`. Since this `Text` no longer reads `context` (was only used for `context.colors.textSecondary`), it became eligible for a `const` constructor and was marked `const` to match the sibling lines' pattern.

This leaves only the parenthetical example line (`(Led Zeppelin, Rock and Roll, 172, Standard, A Major)`) at the smaller/secondary style (`context.colors.textSecondary` / `AppFontSizes.subhead`) inside the bordered block from round 5 — everything else inside the border is now white/`body`-sized except that one line, which was not mentioned in this request and was left as-is.

#### Analyzer Results (round 6)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Round 7 (further Tony-requested tweak, same session — text content change)

**Note:** unlike rounds 1–6, this round changes actual text content, not just typography/layout. Task 1's original Architect-specified copy for this line was `Required: Artist, Song (Optional BPM, Tuning, Key)` (one line). Tony has now directly requested different wording, split across two lines. This supersedes that one piece of Task 1's exact copy — flagged explicitly here since `ARCHITECT_PLAN.md` treated the Task 1 copy as verbatim/literal-match, and this round intentionally departs from it at Tony's (the product owner's) direct instruction.

Changed the single line `Required: Artist, Song (Optional BPM, Tuning, Key)` into two separate lines, both `Colors.white` / `AppFontSizes.body` (matching the sibling `Artist, Song, BPM, Tuning, Key` line's already-established style, unchanged from round 6):
- `Required columns: Artist, Song`
- `Optional columns: BPM, Tuning, Key`

Spacing: added a `SizedBox(height: Spacing.space4)` between the two new lines, consistent with every other gap inside the bordered block. Both lines remain inside the rose-bordered `Container` from round 5 — no change to the border's placement or the `Container`'s other children (`Column order:`, `Artist, Song, BPM, Tuning, Key`, and the parenthetical example are unaffected).

#### Analyzer Results (round 7)
Command: `flutter analyze` (scoped to file, then full-project)
Result: 0 errors, 0 warnings, both runs.

### Full git diff (cumulative — Task 1–4 changes plus all seven rounds of tweaks, current working-tree state)

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d5bb81c..674b5a7 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -368,10 +368,62 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 'Paste songs from a spreadsheet, then tap Load Songs.',
                 style: TextStyle(
                   color: Colors.white,
-                  fontSize: AppFontSizes.subhead,
+                  fontSize: AppFontSizes.body,
                 ),
               ),
-              const SizedBox(height: Spacing.space8),
+              const SizedBox(height: Spacing.space12),
+              Container(
+                padding: const EdgeInsets.all(Spacing.space8),
+                decoration: BoxDecoration(
+                  border: Border.all(color: AppColors.primary),
+                  borderRadius: BorderRadius.circular(8),
+                ),
+                child: Column(
+                  crossAxisAlignment: CrossAxisAlignment.stretch,
+                  children: [
+                    const Text(
+                      'Column order:',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.subhead,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Artist, Song, BPM, Tuning, Key',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    Text(
+                      '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                      style: TextStyle(
+                        color: context.colors.textSecondary,
+                        fontSize: AppFontSizes.subhead,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Required columns: Artist, Song',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Optional columns: BPM, Tuning, Key',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                  ],
+                ),
+              ),
+              const SizedBox(height: Spacing.space16),
               TextField(
                 controller: _csvController,
                 autofocus: true,
@@ -383,9 +435,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   fontFamily: 'monospace',
                 ),
                 decoration: InputDecoration(
-                  hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning, Key\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
+                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
```

### QA scope for this section
QA should independently verify, in addition to the Task 1–4 checks above:
1. The instructional block above the paste field now renders as **six** distinct lines, in order: "Paste songs...", "Column order:", "Artist, Song, BPM, Tuning, Key", the parenthetical example, "Required columns: Artist, Song", "Optional columns: BPM, Tuning, Key".
2. Line 1 ("Paste songs...") is visibly larger than the original (16px vs original 14px).
3. "Column order:" is white and the same size it was right after round 1 (14px) — not changed in size, only color.
4. "Artist, Song, BPM, Tuning, Key" is white and visibly larger than "Column order:" (16px vs 14px).
5. **Updated (round 7):** the old single "Required: Artist, Song (Optional BPM, Tuning, Key)" line is gone — replaced by two new lines, "Required columns: Artist, Song" and "Optional columns: BPM, Tuning, Key", both white/16px, matching "Artist, Song, BPM, Tuning, Key"'s style. This is a genuine wording change from the original Architect-specified Task 1 copy — verbatim-match QA checks against the old wording no longer apply to this line; QA should verify the new wording instead.
6. Only the parenthetical example line remains secondary-colored/14px inside the bordered block.
7. There is now clearly more vertical space between the bordered block and the paste `TextField` than in the original (16px vs 8px) — confirm this reads as intentional breathing room, not a layout bug.
8. There is also now more vertical space between "Paste songs..." and the bordered block than in the original (12px vs 4px) — confirm it reads as a deliberate section break under line 1, not accidental misalignment.
9. All six lines "Paste songs..." through "Optional columns..." — specifically the four lines "Column order:", "Artist, Song, BPM, Tuning, Key", the parenthetical, "Required columns...", and "Optional columns..." (five, not four, now that Required/Optional is two lines) — are enclosed by a single rounded rose-colored border (`AppColors.primary`), with even internal padding on all sides — confirm "Paste songs..." (line 1) is clearly outside/above the border, and the border doesn't clip or crowd the enclosed text on narrow widths, especially now that the block has grown to five internal lines.
10. No visual regression on narrow mobile widths (block has grown from the original single line to five lines inside the border plus one line outside it — check overall vertical space consumption above the paste field, especially with the keyboard open).

---

## Additional Tony-requested UI tweaks #5 (direct VS Code edits — documentation catch-up)

**Scope note:** Tony made the remaining UI tweaks directly in VS Code rather than through an Engineer session, so they weren't documented at the time they landed. This section is a documentation catch-up only — **no code was changed in this pass.** Everything below was confirmed by reading the actual current state of `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` on disk and diffing it against the base (`d5bb81c`), not transcribed from any prior request list. Line numbers cited below are the file's current line numbers as read in this pass.

### What is actually in the file right now

1. **`"Column order:"` kept at its existing font size, color changed to white.**
   Lines 384–390:
   ```dart
   const Text(
     'Column order:',
     style: TextStyle(
       color: Colors.white,
       fontSize: AppFontSizes.subhead,
     ),
   ),
   ```
   `fontSize: AppFontSizes.subhead` (14) is unchanged from the size this line already had; `color: Colors.white` is the change (previously `context.colors.textSecondary` earlier in this file's history).

2. **`"Artist, Song, BPM, Tuning, Key"` added as a new line under `"Column order:"`, larger font size, white.**
   Lines 391–398:
   ```dart
                     const SizedBox(height: Spacing.space4),
                     const Text(
                       'Artist, Song, BPM, Tuning, Key',
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: AppFontSizes.body,
                       ),
                     ),
   ```
   `AppFontSizes.body` (16) is larger than `AppFontSizes.subhead` (14) used on `"Column order:"` directly above it (`lib/app/theme/design_tokens.dart:312-314`: `caption=13`, `subhead=14`, `body=16`). Color is `Colors.white`.

3. **Additional spacing added above the `TextField`.**
   Line 426, immediately before the `TextField` at line 427:
   ```dart
                 const SizedBox(height: Spacing.space16),
                 TextField(
   ```
   `Spacing.space16` (16px). The base/original gap in this spot was `Spacing.space8` (8px) — confirmed via `git diff` (below), which shows this exact line changing from `SizedBox(height: Spacing.space8)` to `SizedBox(height: Spacing.space16)`.

4. **Additional spacing added below `"Paste songs from a spreadsheet, then tap Load Songs."`.**
   Line 374, immediately after that `Text` widget (lines 367–373) and before the bordered `Container` (line 375):
   ```dart
                 const SizedBox(height: Spacing.space12),
   ```
   `Spacing.space12` (12px). The `git diff` below confirms this replaced what was originally `SizedBox(height: Spacing.space8)` in that same position in the base file.

5. **A rose-colored border wrapping the block from `"Column order:"` through `"Optional columns: BPM, Tuning, Key"`.**
   Lines 375–425:
   ```dart
                 Container(
                   padding: const EdgeInsets.all(Spacing.space8),
                   decoration: BoxDecoration(
                     border: Border.all(color: AppColors.primary),
                     borderRadius: BorderRadius.circular(8),
                   ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.stretch,
                     children: [
                       // "Column order:" ... "Optional columns: BPM, Tuning, Key"
                     ],
                   ),
                 ),
   ```
   `AppColors.primary` (`lib/app/theme/design_tokens.dart:150`, `0xFFBE123C`) is the app's brand rose token — the only rose color defined in the design-token file, per that file's own doc comment ("Rose-500 for brand" / "Never use `Color(0xFF...)` outside this file").

   **Confirmed by reading the code, exactly which lines are inside vs. outside the border:**
   - **Outside the border (above it):** `"Paste songs from a spreadsheet, then tap Load Songs."` (lines 367–373) and the `Spacing.space12` gap (line 374).
   - **Inside the border** (the `Container`'s `child` Column, lines 384–423): `"Column order:"` (384–390), `"Artist, Song, BPM, Tuning, Key"` (392–398), `"(Led Zeppelin, Rock and Roll, 172, Standard, A Major)"` (400–406), `"Required columns: Artist, Song"` (408–414), `"Optional columns: BPM, Tuning, Key"` (416–422) — five text lines total, each separated by a `SizedBox(height: Spacing.space4)`.
   - **Outside the border (below it):** the `Spacing.space16` gap (line 426), then the `TextField` (line 427 onward).

6. **`"Required columns: Artist, Song"` and `"Optional columns: BPM, Tuning, Key"` (replacing the old `"Required: Artist, Song (Optional BPM, Tuning, Key)"` line).**
   Lines 407–422:
   ```dart
                     const SizedBox(height: Spacing.space4),
                     const Text(
                       'Required columns: Artist, Song',
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: AppFontSizes.body,
                       ),
                     ),
                     const SizedBox(height: Spacing.space4),
                     const Text(
                       'Optional columns: BPM, Tuning, Key',
                       style: TextStyle(
                         color: Colors.white,
                         fontSize: AppFontSizes.body,
                       ),
                     ),
   ```
   **Confirmed both use the exact same `color`/`fontSize` as `"Artist, Song, BPM, Tuning, Key"` (lines 392–398 above):** all three share `color: Colors.white, fontSize: AppFontSizes.body` verbatim.

   **This is a text-content change, not just typography** — `ARCHITECT_PLAN.md`'s Proposed Solution (and Task 1's exact-copy instruction) specified this line as one line, verbatim: `Required: Artist, Song (Optional BPM, Tuning, Key)`. The current file no longer contains that string anywhere — it has been replaced by the two lines above, at Tony's (the product owner's) direct instruction. This explicitly supersedes `ARCHITECT_PLAN.md`'s Proposed Solution for that one line only; nothing else in the Architect plan's copy (the `"Paste songs..."` text, the `"Column order: Artist, Song, BPM, Tuning, Key"` wording split across two lines, the parenthetical example wording, or the `hintText`) has changed in wording from what the plan specified.

### Analyzer Results
Command: `flutter analyze` — run scoped to `bulk_entry_screen.dart`, then full-project (`flutter analyze` with no path).
Result: **0 errors, 0 warnings**, both runs.

### File-scope confirmation
`git status --porcelain` at the time of this pass:
```
 M lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
?? docs/features/bulk-import-flexible-columns/
?? docs/features/financials-report-breakdown/
```
- Exactly one source file is modified: `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`. No other `.dart` file shows as modified.
- **Confirmed off-limits files were not touched:** `lib/features/setlists/services/bulk_song_parser.dart`, `lib/features/setlists/models/bulk_song_row.dart`, and `lib/features/setlists/setlist_repository.dart` do not appear in `git status` output at all — untouched, exactly as `ARCHITECT_PLAN.md`'s Files Off-Limits section requires.
- The two untracked `docs/features/...` directories are documentation-only additions (this feature's own docs folder and an unrelated sibling feature's docs folder) — not code.

### Full cumulative git diff for `bulk_entry_screen.dart` (current working-tree state, base `d5bb81c`)

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d5bb81c..674b5a7 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -368,10 +368,62 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 'Paste songs from a spreadsheet, then tap Load Songs.',
                 style: TextStyle(
                   color: Colors.white,
-                  fontSize: AppFontSizes.subhead,
+                  fontSize: AppFontSizes.body,
                 ),
               ),
-              const SizedBox(height: Spacing.space8),
+              const SizedBox(height: Spacing.space12),
+              Container(
+                padding: const EdgeInsets.all(Spacing.space8),
+                decoration: BoxDecoration(
+                  border: Border.all(color: AppColors.primary),
+                  borderRadius: BorderRadius.circular(8),
+                ),
+                child: Column(
+                  crossAxisAlignment: CrossAxisAlignment.stretch,
+                  children: [
+                    const Text(
+                      'Column order:',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.subhead,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Artist, Song, BPM, Tuning, Key',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    Text(
+                      '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                      style: TextStyle(
+                        color: context.colors.textSecondary,
+                        fontSize: AppFontSizes.subhead,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Required columns: Artist, Song',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                    const SizedBox(height: Spacing.space4),
+                    const Text(
+                      'Optional columns: BPM, Tuning, Key',
+                      style: TextStyle(
+                        color: Colors.white,
+                        fontSize: AppFontSizes.body,
+                      ),
+                    ),
+                  ],
+                ),
+              ),
+              const SizedBox(height: Spacing.space16),
               TextField(
                 controller: _csvController,
                 autofocus: true,
@@ -383,9 +435,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   fontFamily: 'monospace',
                 ),
                 decoration: InputDecoration(
-                  hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning, Key\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
+                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
```

### Ready for QA
Yes. This section is documentation-only (no code changed in this pass); the underlying implementation was already analyzer-clean per Rounds 1–7 above, and re-confirmed clean in this pass. QA scope is unchanged from the checklist at the end of Round 7 above — this section exists to give QA accurate line numbers and confirm the text-content deviation on the "Required"/"Optional" line, not to add new QA surface area.

---

## QA Fix Round — narrow-screen/keyboard overflow

QA's finding: the instructional block above the paste field grew from 1 line to 6 (plus a bordered container and larger spacing) but sits in a plain, non-scrollable `Column`. `keyboardHeight` (`MediaQuery.of(context).viewInsets.bottom`, already computed at the top of `build()`) was read but never used to shrink this block — only to toggle the keyboard toolbar. On a small phone with the keyboard open, this could overflow.

### Device/emulator availability check

No physical device or already-running emulator reproduces a small-phone-with-keyboard layout in this session (`flutter devices` showed only macOS desktop and Chrome web, same as prior sessions). However, three emulators/simulators were available to **launch** (`flutter emulators`: `apple_ios_simulator`, `Medium_Phone_API_36.1`, `Pixel_9`) — unlike prior Engineer/QA sessions, which reported none available at all. I booted `apple_ios_simulator` (`xcrun simctl boot`), which resolved to an iPhone 17e — the smallest iPhone profile this Xcode's runtime offers. **Caveat: there is no true iPhone-SE-class (4.7"/375×667) simulator device installed in this environment** — the available iPhone runtimes are all modern 6.1"+ devices, none of which reproduce the actual small-screen form factor QA's finding was about.

Reaching `BulkEntryScreen` through the booted simulator requires full authenticated in-app navigation (login → band → setlist → Add Songs → Bulk Entry) — the same barrier QA noted for its own session. Rather than build/seed test credentials to drive the real simulator end-to-end, I used a more precise and directly falsifiable method: a temporary scratch widget test (`test/_scratch_bulk_entry_overflow_test.dart`, created, run, and deleted within this session — never part of the diff or final repo state, confirmed via `git status` afterward) that renders `BulkEntryScreen` directly using Flutter's real layout/render engine, with `MediaQuery` overridden to an actual iPhone SE (3rd gen) logical viewport (375×667) and `viewInsets.bottom` set to a typical iOS keyboard height (291px). `BulkEntryScreen` takes only `onSubmit`/`onBack` callbacks (no repository/auth dependency), so it renders standalone without needing the login flow.

**Critical harness correction made mid-session:** my first attempt wrapped `BulkEntryScreen` in a bare `Scaffold`, which (via its default `resizeToAvoidBottomInset: true`) silently consumed the keyboard inset before `MediaQuery.of(context).viewInsets.bottom` ever reached the widget under test — producing a false read of `keyboardHeight == 0` regardless of the simulated keyboard. I caught this by cross-checking the real host tree in `add_to_setlist_overlay.dart`: `BulkEntryScreen` is actually presented via `showGeneralDialog` (no `Scaffold` in the chain at all) → `Material` → `SafeArea` → `Container(margin: 16)` → `Column` with a 56px header, a 1px divider, and `Expanded(BulkEntryScreen)`. I rebuilt the harness to mirror that exact structure so the raw keyboard inset reaches `BulkEntryScreen.build()` exactly as it does in production.

### What I found (empirically, via the corrected harness)

- **Confirmed real overflow, pre-fix:** on the committed pre-fix code (six-line instructional block, unconditional `TextField(minLines: 3)`), the corrected harness threw `A RenderFlex overflowed by 387 pixels on the bottom` for a 375×667 viewport with a 291px keyboard inset, before songs are loaded. This is a genuine `FlutterError` raised by Flutter's real `RenderFlex`, not a guess.
- Root cause matches QA's analysis exactly: the header block (bordered container + text) is a fixed, non-flex sibling of `Expanded(SizedBox.shrink())` in `BulkEntryScreen`'s root `Column`. Per Flex layout mechanics, non-flex siblings are measured first under unbounded height; if their total exceeds the space the parent actually has, the `Expanded` sibling absorbing "whatever's left" cannot rescue it — the `Column` overflows regardless of the `Expanded` child's contents. `_buildFooter()`'s bottom padding also independently adds `MediaQuery.of(context).viewInsets.bottom + Spacing.space16` to lift the footer above the OS keyboard (since nothing here uses a `Scaffold` that would do this automatically) — this is by design and I did not touch it, but it means the keyboard height is effectively "spent twice" (once by the footer's own reservation, once by the OS actually covering that space), which is exactly why margins are tight once the header block grows.

### Fix applied

Used the existing `keyboardHeight` variable (already computed at the top of `build()`, previously only driving the keyboard toolbar) to conditionally shrink the header/paste-field region only while the keyboard is open — never touching `_buildColumnHeaders`, `_buildRow`, `_buildFooter`, or the `Expanded(ListView.builder(...))` / `Expanded(SizedBox.shrink())` siblings:

1. **Collapse the entire six-line instructional block** (the "Paste songs…" line, the rose-bordered `Column` of 5 lines, and their `SizedBox` spacers) behind `if (keyboardHeight == 0) ...[ ... ]`. When the keyboard is open, none of it renders — this was the single largest contributor (removing it alone cut the measured overflow from 387px to 46px in the harness).
2. **`TextField.minLines`**: `keyboardHeight > 0 ? 1 : 3` (was unconditionally `3`) — fewer default blank lines while the keyboard (and thus limited vertical space) is present.
3. **`TextField` decoration, only while keyboard is open**: `isDense: true` and `contentPadding` tightened from `EdgeInsets.all(12)` to `EdgeInsets.symmetric(horizontal: 12, vertical: 0)`.
4. **Spacing**: the `Padding` wrapping the whole block has its top inset reduced from `Spacing.space12` to `Spacing.space4` while the keyboard is open; the `SizedBox.space8` gap directly below the (now-hidden) header block and the one directly above the "Load Songs" button are both skipped entirely (`if (keyboardHeight == 0) const SizedBox(...)`) while the keyboard is open.

All of the above revert to their original, unconditional values the moment `keyboardHeight == 0` (keyboard closed) — the normal/default appearance and the `_hasLoadedSongs` row-table layout are completely unchanged from Rounds 1–7 above; nothing in this round alters behavior when the keyboard is closed.

**Verification, iterative, via the same corrected scratch harness:**

| Scenario | Result |
|---|---|
| iPhone-SE-class (375×667), 291px keyboard, default text scale — **the exact QA-reported scenario** | **No overflow** (harness test passes) |
| Same, keyboard pushed to 305px (margin probe) | Overflows by 12px |
| Same, keyboard pushed to 310px (margin probe) | Overflows by 17px |
| Same, 291px keyboard + 130% text scale (accessibility "Large Text") | Overflows by 25px |
| Same, 340px keyboard (Android-style suggestion-bar keyboard) + 130% text scale | Overflows by 74px |

The fix fully resolves the scenario QA actually reported and measured against (typical keyboard height, default text scale, iPhone-SE-class viewport), with roughly 12–14px of margin before a taller-than-typical keyboard alone would reopen it.

### Known residual limitation (not fixed in this round — flagging transparently)

Stacking two independent edge conditions simultaneously — a taller-than-typical software keyboard (e.g., Android keyboards with an active suggestion/autocomplete strip, which can run 300–380px vs. iOS's typical ~291px) **and** a large accessibility text-scale setting (~130%+) — can still reproduce a small residual overflow (25–74px in the harness). I did not chase this further because:
- Every further reduction available within "spacing/padding trims" (I tried `contentPadding` down to 0, `isDense`, collapsing every adjacent gap) had diminishing returns and started trading away real UI legibility (e.g., a paste field with zero internal padding) for a few more pixels — not a good trade for an edge case stacking two uncommon conditions.
- Fully closing this would require a structurally different approach (e.g., making the header block itself bounded-height-and-scrollable), which risks exactly what this task's instructions warned against — disturbing the `Expanded` row-table sibling's space allocation — and is a bigger change than "smallest fix that resolves it."
- The original QA finding described the risk as **plausible**, tied to the *typical* small-screen-plus-keyboard case, not to accessibility text-scale stacking specifically.

Recommend the Architect decide whether this residual, stacked edge case warrants a follow-up (e.g., a bounded/scrollable header region scoped carefully around the `_hasLoadedSongs` state, where the sibling `Expanded` is otherwise empty and wouldn't be disturbed).

### Files Modified (this round)
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (same file as all prior rounds; no other files touched)

### Analyzer Results (this round)
Command: `flutter analyze`
Result: **0 errors, 0 warnings**

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — 0 files changed (already formatted).

### Updated cumulative git diff (this round only — the delta on top of Round 7's state)

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d5bb81c..93875e1 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -355,37 +355,90 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     return Column(
       children: [
         Padding(
-          padding: const EdgeInsets.fromLTRB(
+          padding: EdgeInsets.fromLTRB(
             Spacing.space16,
-            Spacing.space12,
+            keyboardHeight > 0 ? Spacing.space4 : Spacing.space12,
             Spacing.space16,
             0,
           ),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
-              const Text(
-                'Paste songs from a spreadsheet, then tap Load Songs.',
-                style: TextStyle(
-                  color: Colors.white,
-                  fontSize: AppFontSizes.subhead,
+              if (keyboardHeight == 0) ...[
+                const Text(
+                  'Paste songs from a spreadsheet, then tap Load Songs.',
+                  style: TextStyle(
+                    color: Colors.white,
+                    fontSize: AppFontSizes.body,
+                  ),
                 ),
-              ),
-              const SizedBox(height: Spacing.space8),
+                const SizedBox(height: Spacing.space12),
+                Container(
+                  padding: const EdgeInsets.all(Spacing.space8),
+                  decoration: BoxDecoration(
+                    border: Border.all(color: AppColors.primary),
+                    borderRadius: BorderRadius.circular(8),
+                  ),
+                  child: Column(
+                    crossAxisAlignment: CrossAxisAlignment.stretch,
+                    children: [
+                      const Text(
+                        'Column order:',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Artist, Song, BPM, Tuning, Key',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      Text(
+                        '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                        style: TextStyle(
+                          color: context.colors.textSecondary,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Required columns: Artist, Song',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Optional columns: BPM, Tuning, Key',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                    ],
+                  ),
+                ),
+                const SizedBox(height: Spacing.space16),
+              ],
               TextField(
                 controller: _csvController,
                 autofocus: true,
                 maxLines: 5,
-                minLines: 3,
+                minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
                   fontSize: AppFontSizes.caption,
                   color: context.colors.textPrimary,
                   fontFamily: 'monospace',
                 ),
                 decoration: InputDecoration(
-                  hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning, Key\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
+                  isDense: keyboardHeight > 0,
+                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
@@ -393,7 +446,9 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   ),
                   filled: true,
                   fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: const EdgeInsets.all(12),
+                  contentPadding: keyboardHeight > 0
+                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
+                      : const EdgeInsets.all(12),
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
@@ -415,7 +470,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   ),
                 ),
               ),
-              const SizedBox(height: Spacing.space8),
+              if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
               SizedBox(
                 height: 40,
                 child: GestureDetector(
```

### Ready For QA (this round)
Yes. The exact scenario QA flagged (narrow-screen + keyboard-open overflow risk on the grown instructional block) is now empirically verified fixed via a corrected, faithful widget-test harness (real `RenderFlex`, real host-tree structure, real iPhone-SE viewport). `flutter analyze`: 0 errors, 0 warnings. Only `bulk_entry_screen.dart` changed; `_buildColumnHeaders`, `_buildRow`, `_buildFooter`, and all off-limits files (`bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`) untouched. One residual, narrower edge case (tall keyboard + large accessibility text stacked together) remains and is documented above for Architect/product to triage as a possible follow-up, not blocking this fix.

---

## Additional Tony-requested UI tweaks #6 (border color change)

Tony asked to change the rose border around the "Column order:" / "Artist, Song, BPM, Tuning, Key" / parenthetical example / "Required columns: Artist, Song" / "Optional columns: BPM, Tuning, Key" block to a lighter gray — specifically the same color already used by the paste `TextField`'s hint text.

### Before/after color values

- **Before:** `border: Border.all(color: AppColors.primary)` — `AppColors.primary` is `0xFFBE123C` (Rose-500, `lib/app/theme/design_tokens.dart:150`).
- **After:** `border: Border.all(color: context.colors.textMuted.withValues(alpha: 0.5))` — copied verbatim from this same file's existing `hintStyle.color` on the paste `TextField` (`bulk_entry_screen.dart`, hint text style), which was already `context.colors.textMuted.withValues(alpha: 0.5)` before this change and is unmodified by it.

`textMuted` is a theme-extension color defined in `lib/app/theme/brand_colors.dart` (`BrandColors`, accessed via `context.colors`): dark theme `0xFF71717A` (Zinc 500, line 57), light theme `0xFF020617` (Slate 950, line 79 — same value the light theme also uses for `textPrimary`/`textSecondary`). At `alpha: 0.5` in the dark theme (this screen's actual runtime theme, based on the surrounding `Colors.white` text), this renders as a legible mid-gray border — consistent with the hint text's existing legibility at the same alpha — not nearly invisible, so no alpha adjustment was made and the exact same color expression was used as instructed.

No other part of the border (shape, `borderRadius: BorderRadius.circular(8)`, `padding: EdgeInsets.all(Spacing.space8)`) or which lines are inside it was touched.

### Files Modified (this section only)
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (same file as all prior rounds; no other files touched)

### Analyzer Results (this round)
Command: `flutter analyze lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: **0 errors, 0 warnings** ("No issues found!")

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — 0 files changed (already formatted).

### Updated cumulative git diff (current working-tree state)

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index d5bb81c..9f53796 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -355,37 +355,92 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     return Column(
       children: [
         Padding(
-          padding: const EdgeInsets.fromLTRB(
+          padding: EdgeInsets.fromLTRB(
             Spacing.space16,
-            Spacing.space12,
+            keyboardHeight > 0 ? Spacing.space4 : Spacing.space12,
             Spacing.space16,
             0,
           ),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
-              const Text(
-                'Paste songs from a spreadsheet, then tap Load Songs.',
-                style: TextStyle(
-                  color: Colors.white,
-                  fontSize: AppFontSizes.subhead,
+              if (keyboardHeight == 0) ...[
+                const Text(
+                  'Paste songs from a spreadsheet, then tap Load Songs.',
+                  style: TextStyle(
+                    color: Colors.white,
+                    fontSize: AppFontSizes.body,
+                  ),
                 ),
-              ),
-              const SizedBox(height: Spacing.space8),
+                const SizedBox(height: Spacing.space12),
+                Container(
+                  padding: const EdgeInsets.all(Spacing.space8),
+                  decoration: BoxDecoration(
+                    border: Border.all(
+                      color: context.colors.textMuted.withValues(alpha: 0.5),
+                    ),
+                    borderRadius: BorderRadius.circular(8),
+                  ),
+                  child: Column(
+                    crossAxisAlignment: CrossAxisAlignment.stretch,
+                    children: [
+                      const Text(
+                        'Column order:',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Artist, Song, BPM, Tuning, Key',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      Text(
+                        '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                        style: TextStyle(
+                          color: context.colors.textSecondary,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Required columns: Artist, Song',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                      const SizedBox(height: Spacing.space4),
+                      const Text(
+                        'Optional columns: BPM, Tuning, Key',
+                        style: TextStyle(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.body,
+                        ),
+                      ),
+                    ],
+                  ),
+                ),
+                const SizedBox(height: Spacing.space16),
+              ],
               TextField(
                 controller: _csvController,
                 autofocus: true,
                 maxLines: 5,
-                minLines: 3,
+                minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
                   fontSize: AppFontSizes.caption,
                   color: context.colors.textPrimary,
                   fontFamily: 'monospace',
                 ),
                 decoration: InputDecoration(
-                  hintText: 'Paste CSV or tab-delimited data here…\n'
-                      'Artist, Song, BPM, Tuning, Key\n'
-                      'e.g.: Aerosmith, Eat The Rich, 123, Standard, G',
+                  isDense: keyboardHeight > 0,
+                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
                   hintStyle: TextStyle(
                     fontSize: AppFontSizes.caption,
                     color: context.colors.textMuted.withValues(alpha: 0.5),
@@ -393,7 +448,9 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   ),
                   filled: true,
                   fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: const EdgeInsets.all(12),
+                  contentPadding: keyboardHeight > 0
+                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
+                      : const EdgeInsets.all(12),
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
@@ -415,7 +472,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                   ),
                 ),
               ),
-              const SizedBox(height: Spacing.space8),
+              if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
               SizedBox(
                 height: 40,
                 child: GestureDetector(
```

### Ready For QA (this round)
Yes. Single-line color-only change, verified against the exact existing `hintStyle` color expression in the same file. `flutter analyze`: 0 errors, 0 warnings. Border shape, padding, and enclosed content unchanged. No other files touched.
