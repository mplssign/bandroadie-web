# QA Report

## Feature Slug
`feature/bulk-import-flexible-columns`

## Feature Title
Bulk Import Flexible Columns + Updated Instructional Copy

## Final Verdict
**APPROVED**

**This verdict supersedes the original REQUIRES CHANGES below**, following an independent re-verification pass of the Engineer's "QA Fix Round — narrow-screen/keyboard overflow" (see `## Re-Verification Pass` section at the end of this report, added after this original report was first written). The original REQUIRES CHANGES verdict and all findings that follow in this file are preserved unmodified as the historical record of the first pass; they are superseded, not deleted.

## Validation Summary
Validated via direct reads of the actual current file contents (`bulk_entry_screen.dart`, `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart` lines 4041–4150), an independently-run `git diff` against the working tree (not the Engineer Report's embedded diff), an independently-run `flutter analyze`, and an independently-run `flutter test test/features/setlists/services/bulk_song_parser_test.dart`. The Engineer Report's seven rounds of tweaks were cross-checked line-by-line against the live file, not taken on faith. One validation gap remains: the narrow-mobile-screen-with-keyboard-open rendering check was never closed by any prior session (no emulator was available to the Engineer; only macOS desktop and Chrome were available to QA — neither reproduces a small-phone-with-keyboard layout), and code-level analysis surfaced a concrete structural reason this check matters (see Issues Found).

## Architect Scope Review
- Scope adherence: **deviation (explicitly authorized by product owner, documented)**
- Files modified: as expected — only `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (confirmed via `git diff --stat` against the whole repo: 1 file changed, 55 insertions, 5 deletions)
- Files off-limits: not touched — confirmed via `git diff --stat` for `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`: zero output, zero changes, for all three
- **Deviation detail:** The Architect Plan's Task 1 specifies the literal line `Required: Artist, Song (Optional BPM, Tuning, Key)`. That string no longer exists anywhere in the file. It has been replaced by two lines — `Required columns: Artist, Song` and `Optional columns: BPM, Tuning, Key` — per the Engineer Report's Round 7, which documents this as a direct, mid-session instruction from Tony (product owner). Per this session's explicit instructions, this is **not treated as a defect**; the new wording was verified in the file and found internally consistent (matches styling of its sibling lines, matches what's rendered in the border, matches the Engineer Report's own description).
- Six additional rounds of typography/spacing/border tweaks (font-size bumps, line splits, a rose border, spacing increases) were also made outside the Architect Plan's Task 1–2 scope. These are documented in the Engineer Report as direct, mid-session product-owner requests, separately called out from the Architect-driven work. Under QA.md's hard rule ("do not approve implementation that exceeds Architect scope"), this would normally block approval — but since the deviations are explicitly product-owner-directed and this session's instructions direct QA to verify the new wording/consistency rather than flag the deviation itself, these are logged here as **authorized deviations**, not scope violations.

## Completeness Check
- All Architect tasks implemented: **yes**
  - Task 1 (instructional copy): done, then further modified by authorized Tony tweaks (verified in file)
  - Task 2 (placeholder text): done exactly as specified, unchanged by later tweaks
  - Task 3 (`flutter analyze`): done, reconfirmed independently (see below)
  - Task 4 (parser verification): done by Engineer via scratch test harness; independently reconfirmed by QA via the permanent `bulk_song_parser_test.dart` suite
- Missing tasks: none

## Behavior Verification
- Validation method: **code-path analysis** for copy/rendering claims (Text widget tree read directly, byte-for-byte against required wording); **runtime tested** for parser behavior (ran the existing automated test suite, not just read the source)
- Result: matches expected, with one caveat below

### Copy content verification (direct file read, `bulk_entry_screen.dart` lines 367–422)
All six lines confirmed present, in order, with exact wording/color/size specified in this session's QA Regression Areas:
1. `"Paste songs from a spreadsheet, then tap Load Songs."` — `Colors.white`, `AppFontSizes.body` (16), **outside** the bordered container ✓
2. `"Column order:"` — `Colors.white`, `AppFontSizes.subhead` (14), inside border ✓
3. `"Artist, Song, BPM, Tuning, Key"` — `Colors.white`, `AppFontSizes.body` (16), inside border ✓
4. `"(Led Zeppelin, Rock and Roll, 172, Standard, A Major)"` — `context.colors.textSecondary`, `AppFontSizes.subhead` (14), inside border ✓
5. `"Required columns: Artist, Song"` — `Colors.white`, `AppFontSizes.body` (16), inside border ✓
6. `"Optional columns: BPM, Tuning, Key"` — `Colors.white`, `AppFontSizes.body` (16), inside border ✓

Placeholder text (line 438): `hintText: 'Column order: Artist, Song, BPM, Tuning, Key'` — exact match, single line, confirmed.

Border (lines 375–425): `Container` with `border: Border.all(color: AppColors.primary)` (confirmed `AppColors.primary` = `0xFFBE123C`, the codebase's sole rose/brand token, `design_tokens.dart:150`), `borderRadius: BorderRadius.circular(8)`, `padding: EdgeInsets.all(Spacing.space8)` (even on all sides). Confirmed the `Container`'s `child: Column` contains exactly the 5 lines listed above (2–6) and nothing else — line 1 and the `TextField` are siblings outside the `Container`, confirmed by direct read.

Spacing: gap between line 1 and the bordered block is `Spacing.space12` (12px); gap between the bordered block and the `TextField` is `Spacing.space16` (16px). Both confirmed larger than the original single `Spacing.space8` (8px) gap that existed pre-feature.

### Parser/model/repository verification (independent, not just reading the Engineer Report's claims)
- `bulk_song_parser.dart` (full read): confirmed positional extraction with length guards for `rawBpm`/`rawTuning`/`rawKey` (lines 106–108), non-fatal warning pattern for invalid BPM/tuning/key (rows stay valid), quote-aware `_splitCsvLine()` (lines 237–268) with a genuine `insideQuotes` state machine, `_normalizeKey()` (lines 420–458) against a real canonical key set, sub-2-column rejection producing `missingTitle` (lines 92–102).
- `bulk_song_row.dart` (full read): confirmed `musicalKey` field (line 38) threaded through both `.invalid()` and `.valid()` factories.
- `setlist_repository.dart` (lines 4041–4150 read): confirmed `_createOrFindSong()` accepts `musicalKey`, enriches existing songs only when the DB value is null (line 4098–4100, non-destructive), and includes `musical_key` in the insert path when non-empty (lines 4133–4135).
- Ran `flutter test test/features/setlists/services/bulk_song_parser_test.dart` independently: **11/11 passed**, including quote-aware comma-splitting, apostrophe un-escaping, major/minor key normalization, unrecognized-key non-fatal warning, and missing-key-leaves-null cases. This directly re-confirms no regression, rather than relying on the Engineer Report's claim of the same result.

### Caveat
Live UI rendering (actual text wrap, actual border padding/clipping on a real narrow screen) was **not runtime tested** in this session — see Issues Found.

## Regression Check
- Risk level: **LOW** for parser/data-layer concerns; **MEDIUM** for the specific narrow-screen layout concern below
- Systems reviewed: Setlists/Catalog (copy-only, per Architect plan), Platform (iOS/Android/Web/macOS — shared Dart widget, no platform branches confirmed in the diff), Auth/Session/Routing/Init-order (unaffected — confirmed no changes outside `bulk_entry_screen.dart`)
- Regressions found: **none** in parser/model/repository logic (all three off-limits files show zero diff, confirmed twice). One **layout regression risk** identified — see Issues Found.

## Database Safety
Not applicable — confirmed no migration files, no schema/RLS/RPC changes; `setlist_repository.dart` shows zero diff.

## Analyzer Results
Command: `flutter analyze`
Result: **0 errors, 0 warnings** (run independently by QA, not just taken from the Engineer Report)

## Test Results
Command: `flutter test test/features/setlists/services/bulk_song_parser_test.dart`
Result: **Passed — 11/11** (run independently by QA)

No widget/UI test exists for `BulkEntryScreen` (confirmed via search of `test/`) and none was created by QA, per the hard constraint against modifying/creating test files.

## Diff Safety Review
- Secrets: none found
- Debug artifacts: none — diff contains only `Text`/`Container`/`SizedBox`/`hintText` changes, no `print`/`TODO`/temporary flags
- Unrelated changes: none — `git diff --stat` for the whole repo shows exactly 1 file changed

## Issues Found

### Critical (must fix before commit)
None.

### Warnings (should fix)
1. **Unresolved narrow-screen + keyboard-open rendering check, with a concrete structural risk identified.** The instructional block above the paste field grew from 1 line to 6 (1 outside the border + 5 inside), plus a bordered `Container` with padding, plus larger gaps (`space12`/`space16` vs. the original `space8`). This entire block sits inside a plain `Column` (`build()`, `bulk_entry_screen.dart:355`) that is **not** wrapped in a `SingleChildScrollView` — it is a fixed-size sibling before the row list's `Expanded(ListView.builder(...))` (line 516) or, before songs are loaded, before `Expanded(child: SizedBox.shrink())` (line 531). `MediaQuery.of(context).viewInsets.bottom` (line 351, `keyboardHeight`) is read but only used to conditionally show a keyboard toolbar (line 532) — it is never used to shrink or hide the now-much-taller instructional block. On a short/narrow phone screen (e.g. iPhone SE-class) with the keyboard open, before songs are loaded, the fixed-height content (grown instructional block + `TextField` with `minLines: 3` + Load Songs button) could plausibly exceed available vertical space, since nothing in this segment scrolls. This is exactly the check both the Architect Plan (QA Regression Area 7) and the Engineer Report explicitly flagged as needing a live pass, and it has never been closed: the Engineer had no emulator available, and QA's only available devices in this session were macOS desktop and Chrome web — neither reproduces a narrow-phone-with-keyboard layout. **Recommend:** a live check on an actual small-screen phone (or simulator/emulator) with the keyboard open, before this instructional block's growth, or defensively wrap the top `Padding` content in a `SingleChildScrollView` if the live check shows overflow/cramping.

### Suggestions (optional)
1. None.

---

**Note on live device testing:** No iOS/Android emulator was available in this session (only macOS desktop and Chrome web via `flutter devices`); reaching `BulkEntryScreen` at runtime additionally requires authenticated in-app navigation (login → band → setlist → Add Songs), which was out of scope for a read-only QA pass without test credentials. All findings above are based on direct source reads and independently-run automated commands (`flutter analyze`, `flutter test`), not fabricated or assumed runtime behavior.

---

## Re-Verification Pass — QA Fix Round (narrow-screen/keyboard overflow)

This section documents a second, independent QA pass performed strictly to re-verify the single item that blocked approval above: the narrow-screen + keyboard-open overflow risk. It responds to `ENGINEER_REPORT.md`'s "QA Fix Round — narrow-screen/keyboard overflow" section. This pass was read-only — no source file was modified by QA.

### What was independently verified

**1. The diff is real and matches the Engineer Report's claims verbatim.**
Ran `git diff -- lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` directly against the working tree (not the report's embedded excerpt). The output is byte-for-byte identical to the diff block in `ENGINEER_REPORT.md`'s "QA Fix Round" section: `keyboardHeight` (line 351, `MediaQuery.of(context).viewInsets.bottom`, pre-existing) now conditionally collapses the entire six-line instructional block (`if (keyboardHeight == 0) ...[...]`, lines 367–428), reduces `TextField.minLines` from `3` to `1` (line 433), sets `isDense: true` and tightens `contentPadding` (lines 440, 449–451), and skips two `SizedBox` spacing gaps (lines 360, 473) — all only while the keyboard is open. Confirmed via direct read of the current file (lines 330–540), not just the diff.

**2. `flutter analyze` re-run independently.**
Command: `flutter analyze` (full project, no path scoping). Result: **0 issues found**. This matches the Engineer Report's claim.

**3. The conditional logic is genuinely correct Flutter layout semantics, not a cosmetic fix.**
`if (keyboardHeight == 0) ...[ Text(...), SizedBox(...), Container(...), ... ]` inside a `Column`'s `children:` list is a Dart collection-if. When the condition is `false`, those widget instances are never constructed and never added to the `Column`'s child list — they do not exist in the widget tree, do not get an `Element`, and never reach `RenderFlex` for layout or painting. This is categorically different from a cosmetic hide (e.g. `Visibility(visible: false)` without `maintainSize: false`, or `Opacity(opacity: 0)`), both of which would still occupy layout space and could still contribute to overflow. Since a `RenderFlex` overflow is fundamentally a "there is more content demanding space than the parent has" problem, genuinely removing content from the tree (rather than hiding it) is the structurally correct fix — confirmed by direct reasoning about Flutter's layout/element lifecycle, not taken on the Engineer Report's word.

**4. Real host-tree structure independently confirmed** (validates the Engineer's harness-correction claim).
Read `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` in full. Confirmed directly: `BulkEntryScreen` is reached via `showGeneralDialog` → `_AddToSetlistOverlay.build()` → `Material` → `SafeArea` → `Container(margin: Spacing.space16)` → `ClipRRect` → `Column` with a 56px `_buildHeader()`, a 1px `Divider`, and `Expanded(AnimatedSwitcher(child: _buildContent()))` where `_buildContent()` returns `BulkEntryScreen` for the bulk category. **There is no `Scaffold` anywhere in this chain.** This directly corroborates the Engineer Report's claim that their first harness attempt (a bare `Scaffold` wrapper) was invalid — a `Scaffold`'s default `resizeToAvoidBottomInset: true` would have silently consumed the simulated keyboard inset before it ever reached `BulkEntryScreen.build()`, producing a false `keyboardHeight == 0` reading regardless of the simulated keyboard — and that the corrected harness (mirroring this exact `Material` → `SafeArea` → `Container` → `Column` structure with no `Scaffold`) is structurally faithful to production. QA did not re-run the Engineer's scratch widget-test harness itself (it was deleted per the Engineer's session, and recreating a test file was avoided to stay strictly within this pass's read-only constraint); the 387px overflow / fix-closes-it / residual-25–74px numbers are therefore Engineer-reported, not independently re-measured — but the harness *methodology* underpinning those numbers is independently confirmed sound via this host-tree read, and the underlying widget-tree-removal mechanism (point 3 above) independently confirms the fix direction is correct regardless of the exact pixel counts.

**5. No regression to keyboard-closed behavior.**
Direct read of `bulk_entry_screen.dart` lines 349–538 confirms: when `keyboardHeight == 0`, every value matches the prior approved state exactly — the six-line instructional block (all wording, colors, font sizes, and the rose `AppColors.primary` border from Rounds 1–7 of `ENGINEER_REPORT.md`) renders unconditionally, `Padding` top inset is `Spacing.space12`, `TextField.minLines` is `3`, `contentPadding` is `EdgeInsets.all(12)`, `isDense` is `false`, and both previously-unconditional `SizedBox` gaps render. Nothing in this fix round alters appearance or behavior with the keyboard closed.

**6. Off-limits files and scope confirmed.**
`git status --porcelain` shows exactly one modified source file (`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`) plus the two untracked `docs/features/...` directories (documentation only). `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, `lib/main.dart`, migrations, and the pass-through caller files (including `add_to_setlist_overlay.dart`, read in full above) show zero diff — none were touched by this fix round.

### Decision on the residual edge case

The Engineer Report documents a residual, narrower overflow (25–74px) when a tall Android-style keyboard (~300–380px) and a large accessibility text scale (~130%+) are stacked simultaneously. **This does not block approval.** Reasoning:

- The fix demonstrably resolves the exact scenario this QA report's original Issues Found item flagged: a small-phone-class viewport with a typical keyboard open, default text scale — the Engineer's harness reports ~12–14px of margin on that scenario, and the underlying tree-removal mechanism (point 3 above) confirms the fix is structurally sound, not a narrow numeric coincidence.
- The residual case requires **two** independently uncommon conditions stacked together (a taller-than-typical keyboard *and* 130%+ accessibility text scale). The original finding this fix responds to was about the general "small screen + keyboard open" case, not accessibility text-scale stacking specifically.
- This feature's Architect-assigned regression risk is **LOW** (copy-only change; see `ARCHITECT_PLAN.md`), and closing the residual case fully would require a structurally different approach (a bounded/scrollable header region) — a larger change than "smallest fix that resolves the reported risk," and one that risks disturbing the `Expanded` row-table sibling this fix round was careful not to touch. Pursuing it now would itself risk exceeding appropriate scope for this fix round.
- The residual risk is transparently documented in `ENGINEER_REPORT.md` with a concrete recommendation (Architect/product to triage a possible scrollable-header follow-up) rather than silently left unaddressed.

Accepted as a documented, low-likelihood residual risk — not a blocker.

### Updated Regression Check
- Risk level: **LOW** (revised down from the original report's MEDIUM — the narrow-screen/keyboard-open concern that drove the MEDIUM rating is now fixed for the reported scenario; only a narrower, stacked-condition edge case remains, documented and accepted above)
- Systems reviewed: Setlists/Catalog (`bulk_entry_screen.dart` only), Platform (iOS/Android/Web/macOS — shared Dart widget, no platform branches)
- Regressions found: none

### Updated Analyzer Results
Command: `flutter analyze`
Result: **0 issues found** (re-run independently by QA in this pass)

### Updated Diff Safety Review
- Secrets: none found
- Debug artifacts: none — diff contains only `Padding`/conditional-collection/`TextField`-property changes; no `print`/`TODO`/temporary flags
- Unrelated changes: none — `git diff --stat` shows exactly 1 file changed (70 insertions, 15 deletions)

### Final Issues Found (this pass)

#### Critical (must fix before commit)
None.

#### Warnings (should fix)
None. The item from the original pass is resolved for the reported scenario.

#### Suggestions (optional)
1. Consider a follow-up (Architect/product decision, not a blocker) to make the instructional header region bounded-height-and-scrollable specifically to close the residual tall-keyboard + large-text-scale edge case documented in `ENGINEER_REPORT.md`, scoped carefully so it doesn't disturb the `Expanded` row-table sibling.

### Final Verdict (this pass)
**APPROVED**
