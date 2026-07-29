# QA Report

## Feature Slug
bug/bulk-entry-instructions-cutoff-ios

## Feature Title
Bulk Entry Modal Missing Instructions + Undersized Paste Field on iOS

## Final Verdict
**APPROVED**

## Validation Summary
This is the final, comprehensive QA pass covering the entire ticket history: the original Architect plan, nine addenda, and two logged direct product-owner deviations, spanning two files (`bulk_entry_screen.dart`, `MainActivity.kt`). `ARCHITECT_PLAN.md` (2,045 lines) and `ENGINEER_REPORT.md` (2,491 lines) were read in full, in chunked passes, including all nine addenda and every logged deviation/correction. The true current `git diff` for both files was captured independently of the cumulative diffs quoted inside `ENGINEER_REPORT.md` (which are intermediate snapshots), and the CURRENT full content of both files was read directly and cross-referenced against each addendum's claimed change. `flutter analyze` was run project-wide (0 issues) and `flutter build apk --debug` was run to completion (build succeeded, validating the Kotlin change from Addendum 8, which `flutter analyze` does not cover). Validation was performed via **code-path analysis and direct reading of the current source** — no device or simulator was available to this QA session, so no interactive tap-testing was performed here (see Behavior Verification for what Tony has separately confirmed at runtime).

## Architect Scope Review
- Scope adherence: **compliant**
- Files modified: as expected — `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` and `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`, confirmed via `git status` and `git diff --stat` (193 insertions, 161 deletions across exactly these two files — matches expected). No other file is modified, created, or deleted anywhere in the working tree.
- Files off-limits: not touched. `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`, `bulk_song_parser.dart`, `bulk_song_row.dart`, `add_to_setlist_overlay.dart`, `AndroidManifest.xml`, `styles.xml` (either variant), `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift` — all confirmed untouched by `git status` (clean except the two expected files) and by direct inspection where relevant (e.g., `AndroidManifest.xml`'s pre-existing `uiMode` entry in `android:configChanges` was read and confirmed unmodified).

Every hunk in the current diff traces to a specific addendum or logged deviation:
- `autofocus: true` removal → original plan, Task 1.
- `key: const ValueKey('bulk-entry-csv-field')` on the CSV `TextField` → Addendum 1, Task A.
- Instructional info-box border removed; paste field `fillColor` (0.04→0.08) and `border`/`enabledBorder` width (→1.5) → logged "Out-of-Plan Change" / "Deviation" (Tony's direct, explicit, in-session request as product owner).
- `key`s on `_buildKeyboardToolbar()`'s and `_buildFooter()`'s `Container`s → Addendum 2, Task A (the Task B/C diagnostic instrumentation that also shipped in that session was fully stripped by Addendum 3, Task F — confirmed zero `TEMP-DEBUG` remain in the current file).
- `pasteUiBlock` extraction, `showFullPasteUi`, footer-visibility `if (_hasLoadedSongs || keyboardHeight == 0)` → Addendum 4, Tasks I/J/K.
- Outer `Column`'s first-child slot made an unconditional, type-stable `Flexible`/`SingleChildScrollView` (varying only `flex`/`physics`) → Addendum 5, Task N.
- `showExpandedPasteField` decoupling `minLines`/`isDense`/`contentPadding` from `keyboardHeight`; unconditional trailing spacer → Addendum 6, Task Q.
- Column-width constants (`_kFlexArtist=5`, `_kFlexSong=5`, `_kFlexBpm=3`, `_kFlexTuning=4`, `_kFlexKey=3`, `_kDeleteWidth=16`), plain-`flex`-only `_headerCell`/`_tableCell` signatures, removal of `_buildColumnHeaders()`/`_buildRow()`'s horizontal padding → logged "Correction" + "Investigation" (resolved not-a-bug) + "Correction 2" entries, which **supersede** Addendum 7's original fixed-width (`_kNarrowColumnWidth`) design per Tony's direct instruction (see Completeness Check).
- `MainActivity.kt`'s `attachBaseContext()` override → Addendum 8, Task Y.
- `_csvFocusNode`, `_isPasteFieldFocused`, widened `showExpandedPasteField`/table-visibility/footer-visibility conditions → Addendum 9, Tasks R/S.

No hunk in either file's current diff is untraced. The two logged cosmetic deviations exceed the *original* Architect plan's line-item scope but are transparently documented by the Engineer at the time they were made (not hidden), confined to the single already-authorized file, purely cosmetic (no logic/state/conditional change), and made at the explicit, direct instruction of Tony as product owner — consistent with this ticket's established and repeatedly-exercised pattern (Addendum 6's own text cites this same precedent). This is noted as a Warning below for completeness, not a scope violation that blocks approval.

## Completeness Check
- All Architect tasks implemented: **yes**
- Missing tasks: none. Cross-referencing each addendum's tasks against the CURRENT file (not just diff hunks in isolation):
  - Original Task 1–2: confirmed — no `autofocus` anywhere in the file (`grep -n autofocus` returns zero matches).
  - Addendum 1 Task A: confirmed — `key: const ValueKey('bulk-entry-csv-field')` present on the CSV `TextField` (current line 437).
  - Addendum 2 Task A: confirmed — both `_buildKeyboardToolbar()` (line 761) and `_buildFooter()` (line 812) carry their stable, distinct keys.
  - Addendum 3 Task F: confirmed — zero `TEMP-DEBUG` matches anywhere in the file or diff; no `_csvScrollController`, no wrapping debug `Container`, no `autocorrect`/`enableSuggestions` overrides remain.
  - Addendum 4 Tasks I/J/K: confirmed — `pasteUiBlock` extracted as a local variable; footer gated on `(_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0` (widened further by Addendum 9, see below); `showFullPasteUi` present and gating the intro/info-box block and padding-top only, as Addendum 6 refined it to.
  - Addendum 5 Task N: confirmed — outer `Column`'s first child (lines 531–539) is unconditionally `Flexible(flex: ..., child: SingleChildScrollView(physics: ..., child: pasteUiBlock))` in every state; only `flex` and `physics` vary with `keyboardHeight`.
  - Addendum 6 Task Q: confirmed — `showExpandedPasteField` (line 364) drives `minLines` (441), `isDense` (448), `contentPadding` (457–459); trailing spacer (line 483) is unconditional.
  - **Addendum 7: intentionally superseded, not incomplete.** Addendum 7's original plan (equal 1:1 flex for Artist/Song + a fixed `_kNarrowColumnWidth = 68.0` for BPM/Tuning/Key) was implemented first, then explicitly superseded by Tony's direct follow-up instruction for exact 25/25/15/20/15 percentage widths (logged "Correction" entry), further refined by a "not a bug" investigation and a second "Correction 2" narrowing the delete-icon gutter (36→16) and removing the table's horizontal padding for edge-to-edge rendering. The CURRENT file (`_kFlexArtist=5`, `_kFlexSong=5`, `_kFlexBpm=3`, `_kFlexTuning=4`, `_kFlexKey=3`, `_kDeleteWidth=16`, plain `flex`-only `_headerCell`/`_tableCell` signatures, no horizontal padding on `_buildColumnHeaders()`/`_buildRow()`) matches the logged deviation exactly, not Addendum 7's original spec. This is expected and correct per this ticket's own explicit instruction; it is not flagged as a missing/incomplete task.
  - Addendum 8 Task Y: confirmed — `MainActivity.kt`'s `attachBaseContext()` override matches the Architect's proposed code verbatim, including the `UI_MODE_NIGHT_MASK.inv()` clear-then-OR pattern.
  - Addendum 9 Tasks R/S: confirmed — `_csvFocusNode`/`_isPasteFieldFocused` fields present (lines 132, 138); `_handleCsvFocusChange()` listener registered in `initState()` (line 150) and disposed in `dispose()` (line 167); `showExpandedPasteField = !_hasLoadedSongs || _isPasteFieldFocused` (line 364); table-visibility widened to `_hasLoadedSongs && !showExpandedPasteField` (line 540); footer-visibility widened to `(_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0` (line 560).

## Behavior Verification
- Validation method: **code-path analysis and direct reading of the current source**, performed by QA in this session. No device or simulator was available in this session, so no interactive tap-testing, focus-cycle testing, or visual/screenshot verification was performed by QA here — this is stated plainly rather than attempting unreliable coordinate-based Simulator automation, which prior Engineer/QA sessions in this ticket's own history already documented as unreliable for this exact screen (misfired taps, incorrect window-geometry capture).
- Result: matches expected per code-path analysis, for every addendum's claimed change (see Completeness Check for specifics).

Per this session's explicit instructions, the following behaviors are **confirmed at runtime by Tony (product owner), not independently re-verified by QA in this session**:
- The focus/glitch fix (smooth keyboard rise, no flash/flicker/reset, focus holds across repeated tap cycles) — Addenda 1, 3, 5.
- The table-population fix (parsed songs appear as rows, not just headers) — Addendum 4, Task K.
- The paste-field sizing (expanded height/normal padding with the keyboard open) — Addendum 6.
- The column-width/delete-button layout (25/25/15/20/15 split, narrowed edge-to-edge delete gutter) — the logged Corrections superseding Addendum 7.
- The Android keyboard dark-mode fix — Addendum 8.
- Addendum 9's re-focus-to-expand behavior (tapping back into the paste field after songs are loaded re-expands the view).

QA's own contribution this session is independent, direct verification that the CURRENT code on disk correctly implements the mechanism behind each of these already-device-confirmed behaviors, and that no later addendum silently undid an earlier one — not a re-performance of the device testing itself.

## Regression Check
- Risk level: **LOW**
- Systems reviewed: Setlists/Catalog (Bulk Entry modal — focus/keyboard-collapse behavior, table population, column layout), Platform (iOS/Android native keyboard theming), CSV parsing/submission path (`_handleCsvIngestion`, `_populateTableFromParseResult`, `BulkSongParser`, `BulkSongRow` — all confirmed unmodified by direct read), Android native Activity lifecycle (`MainActivity.kt`).
- Regressions found: **none**, confirmed by direct reading of the current file against each specific historical regression class in this ticket:
  1. **CSV paste `TextField` stable key**: confirmed present — `key: const ValueKey('bulk-entry-csv-field')` (line 437), unchanged since Addendum 1.
  2. **Outer wrapper type-stability**: confirmed. The outer `Column`'s first child (lines 531–539) is `Flexible(flex: keyboardHeight > 0 ? 1 : 0, child: SingleChildScrollView(physics: ..., child: pasteUiBlock))` in **every** build, unconditionally — the widget type at that slot never varies with `keyboardHeight`/`_hasLoadedSongs`/`_isPasteFieldFocused`; only `flex` and `physics` (non-structural properties) vary. This is exactly the type-stable pattern Addendum 5 introduced to fix Addendum 4 Task I's self-inflicted regression (a conditional `Padding`/`Flexible` swap that changed `runtimeType` at that slot), and it remains intact after Addendum 6's and Addendum 9's later edits — neither touched this wrapper.
  3. **Addendum 9's `FocusNode` — no repeat of the Addendum 2 mistake**: confirmed. `_csvFocusNode` (line 132) is a plain `State` field, wired onto the existing CSV `TextField` as an additional named argument (`focusNode: _csvFocusNode`, line 439) alongside the unchanged `key:`/`controller:`. No new wrapping widget was introduced around the field — the `TextField` remains a direct, unwrapped child of `pasteUiBlock`'s inner `Column`, exactly as Addendum 3 restored it. This is categorically different from Addendum 2's mistake (wrapping the field in an unkeyed `Container`, which hid the key one level too deep from `Element.updateChildren`'s reconciliation) — adding a constructor argument to an unchanged widget type/key is not a slot-type change.
  4. **FocusNode disposal**: confirmed — `_csvFocusNode.dispose();` present in `dispose()` (line 167), alongside `_csvController.dispose()`, satisfying Guardrails §5.
  5. No `setState`-after-`async`-gap violations: `_handleCsvFocusChange()` (line 153) includes a `mounted` guard before `setState`; `_handleSubmit()`'s `await widget.onSubmit(...)` call (line 341) is followed by `mounted` guards before both branches' `setState`/`Navigator.pop()` calls (lines 343–346), unchanged by this ticket and Guardrails-compliant.
- Android (Addendum 8) is reviewed independently below and carries no interaction with the Dart-side focus/glitch regression history — confirmed no shared code path.

## Database Safety
Not applicable. Confirmed directly: `git diff --stat` shows only `bulk_entry_screen.dart` (a pure UI widget) and `MainActivity.kt` (native Android Activity lifecycle code) — no `supabase/migrations/*.sql`, no `setlist_repository.dart`, no RPC call site, and a full-diff grep for `supabase`, `.rpc(`, `migration`, and `sql` (case-insensitive) returns zero matches. `_handleCsvIngestion()` and `_populateTableFromParseResult()` — the only methods in this file that touch data — were confirmed unmodified by direct read of the current file, consistent with every addendum's explicit "not touched" declaration.

## Analyzer Results
Command: `flutter analyze`
Result: **0 errors, 0 warnings** — "No issues found! (ran in 6.1s)"

## Test Results
Not run. Confirmed via the Engineer's own repeated checks (and independently, no test file references `bulk_entry_screen` or `MainActivity` anywhere in `test/`) that no existing automated test covers either changed file, and the Architect plan does not require adding one for this ticket (pure UI/native-config change, no data-layer logic to unit test).

Additionally, `flutter build apk --debug` was run to completion as required by this session's scope (this validates the Kotlin change from Addendum 8, which `flutter analyze` does not cover, since it is a Dart-only analyzer):
Command: `flutter build apk --debug`
Result: **Success** — `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (Gradle `assembleDebug` completed in 11.9s). One pre-existing, unrelated warning was emitted (Flutter's Kotlin-version-support notice for KGP 2.1.0, present in the project regardless of this ticket's changes — confirmed unrelated to `MainActivity.kt`'s content).

## Diff Safety Review
- Secrets: none found — confirmed via a full-diff grep for API-key/secret/password/token/service-role patterns (zero matches).
- Debug artifacts: **none**. Grepped the ENTIRE current file and diff for `TEMP-DEBUG` — zero matches, confirming Addendum 2's diagnostic instrumentation (added, then claimed stripped by Addendum 3) remains fully stripped after five further addenda (4–9) layered on top since then; it was not reintroduced. Also grepped for stray `debugPrint`, `Colors.red`, `Colors.lime`, and `ColoredBox` (the debug-coloring pattern used in the later, separately-resolved "Investigation" session) — the only `debugPrint` match in the file is a pre-existing, unrelated one in `_handleSubmit()`'s `catch` block (`debugPrint('[BulkEntryScreen] Submit error: $e')`, line 349), outside every diff hunk and unrelated to this ticket's diagnostic history — legitimate production error logging, not a leftover.
- Unrelated changes: none. `git diff --stat` shows exactly 193 insertions / 161 deletions across the two expected files, matching the pre-verified baseline; no formatting-only churn in any unrelated file.

### Addendum 8 (Android/Kotlin) — Independently Verified
Reviewed separately from the Dart focus-bug regression analysis above, as it is an unrelated, app-wide Android keyboard dark-mode fix. Current `MainActivity.kt` content:
```kotlin
package com.bandroadie.app

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun attachBaseContext(newBase: Context) {
        val configuration = Configuration(newBase.resources.configuration)
        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            Configuration.UI_MODE_NIGHT_YES
        super.attachBaseContext(newBase.createConfigurationContext(configuration))
    }
}
```
This matches the Architect's Addendum 8 proposed solution verbatim. `AndroidManifest.xml` was independently confirmed (via direct grep) to already list `uiMode` in `android:configChanges` prior to this change, so forcing this value does not trigger an unwanted Activity recreation. **Guardrails §1 (Initialization Order) is not violated**: `attachBaseContext()` is an Android-native `Activity`/`ContextWrapper` lifecycle hook that runs prior to and independently of Flutter's Dart entrypoint (`main()`); it does not touch, reorder, or interact with any step of the documented sequence (`WidgetsFlutterBinding.ensureInitialized()` → URL strategy → orientation lock → `AppVersionService.init()` → `validateSupabaseConfig()` → `Supabase.initialize()` → `Firebase.initializeApp()` → `DeepLinkService` setup → `runApp()`). `lib/main.dart` is confirmed untouched (not in the diff). No `AI_DECISIONS.md` entry is required, consistent with the Architect's own explicit determination, since no init-order, config-loading, auth-flow, RLS, or new-dependency change is involved.

## Issues Found
None.

### Warnings (should fix)
1. Two cosmetic changes (instructional info-box border removed; paste-field `fillColor`/border-width increased) and the column-width/delete-gutter scheme were made as direct, in-session, product-owner instructions rather than through a formal Architect addendum at the time each was made. Both were transparently logged in `ENGINEER_REPORT.md` as deviations at the time (not hidden), are purely cosmetic/layout, carry no logic or data risk, and are consistent with this ticket's own repeatedly-exercised, established pattern of Tony reviewing on-device and issuing direct corrections that supersede a prior addendum's design judgment. No action required before commit; noted here per QA.md Phase 4/10 for full transparency in the historical record.
2. `bulk_entry_screen.dart` is 944 lines, exceeding the Guardrails §8 "Feature widgets" target of 400 lines. This predates this ticket (the file was already large before Addendum 1) and every addendum's changes were minimal, localized, in-place edits rather than opportunistic refactors — consistent with Guardrails §7's "prefer localized in-place edits" and §8's allowance for the Architect to permit localized modification of an oversized file when the change is minimal and doesn't worsen maintainability. Not a blocker; flagged for awareness only, as a candidate for a future, separate refactor ticket.

### Suggestions (optional)
1. This ticket's nine-addendum history is a strong practical case study in the value of stable `Key`s and type-stable wrapper widgets in `Column`/`Row` children lists whose siblings are conditionally present. Consider extracting a short internal note (e.g., in `docs/reference/setlists/` or a Flutter-patterns doc) documenting the specific failure mode (conditional-sibling reordering silently defeating reconciliation, and conditional-wrapper-type-swapping doing the same one level up) for future reference, given how many rounds it took to fully resolve in this exact file.
