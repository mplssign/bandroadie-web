# Engineer Report

## Feature Slug
bug/bulk-entry-instructions-cutoff-ios

## Feature Title
Bulk Entry Modal Missing Instructions + Undersized Paste Field on iOS

## Goal
Remove the spurious `autofocus: true` on the Bulk Entry paste `TextField` so the on-screen keyboard no longer auto-triggers on modal open, which was causing `keyboardHeight > 0` to be true on the first frame and hiding the instructional block / shrinking the paste field on iOS (and likely Android) before the user had done anything.

## Architect Tasks Completed
- [x] Task 1 — Removed `autofocus: true,` from the paste `TextField` (line 433) in `bulk_entry_screen.dart`. No other property of that `TextField` (`controller`, `maxLines`, `minLines`, `style`, `decoration`) was touched. The five `_TableTextField` instances were not touched.
- [x] Task 2 — `flutter analyze` run: 0 errors, 0 warnings.
- [ ] Task 3 — Attempted, not completed. See Verification section below.

## Files Created
- none

## Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found! (ran in 3.2s)"

## Test Results
Not run. No existing test covers `bulk_entry_screen.dart` (confirmed via `grep -rl "bulk_entry_screen" test/` — no matches), and the Architect plan does not require adding one. `dart format` was run on the single changed file; it reported 0 changes needed.

## Verification
Manual steps performed:
- Confirmed the `TextField` at line 431 and the removed line matched the plan's line numbers exactly before editing.
- Booted the iPhone 17 simulator (previously shut down) and ran the app on it via `flutter run -d <iPhone 17 UDID> --dart-define-from-file=dart_defines.json` with the fix in place, to attempt Task 3 / Tier 1 pre-deploy verification.
- The app built and launched successfully on iOS (Xcode build succeeded, Supabase/DeepLink init logged, login screen rendered).
- I attempted to drive the UI (log in via the 7-tap demo-login easter egg, then navigate Setlists → a setlist → "Add to setlist" → "Bulk Entry") using `cliclick` against the Simulator window, translating device-pixel screenshot coordinates to macOS window coordinates.
- **This coordinate-mapping approach was not reliable.** The Simulator window's logical point size and the device screenshot's pixel size did not convert with a single consistent scale factor (likely because the Simulator's device-bezel chrome inset the actual tappable screen area within the window in a way I could not calibrate without an accessibility/UI-automation inspector). Taps landed on unpredictable parts of the screen — the session ended up authenticated and jumping between unrelated screens (a "Set Break" modal, an "Income & Expenses" report, then the Dashboard) that I had not intentionally navigated to, and I could not get a reliable, repeatable tap onto the "Setlists" tab afterward.
- Given this, **I did not reach the Bulk Entry modal and cannot confirm Tier 1 Tests 1–7 or Task 3 from direct observation.** Continuing to fumble blind taps against production-like demo data risked incidental, unintended writes to the demo band's data, so I stopped rather than keep guessing.
- I terminated the `flutter run` process (PID 1760) cleanly and shut the simulator back down afterward, leaving the environment as I found it. No repo files were touched by this verification attempt (`git status` shows only the one intended source file modified plus the pre-existing untracked `docs/features/.../` directory).

**I do not have a reliable way to complete Task 3 / Tier 1 manual verification in this session.** I have simulator access, but not a working UI-automation/accessibility harness for this app, so I'm reporting this honestly rather than claiming the on-device visual behavior was confirmed. QA (or a human with hands-on simulator/device access) should perform Tier 1 Tests 1–7 as written in `ARCHITECT_PLAN.md`.

## Deviations From Architect Plan
None in the code change itself. Task 3 (explicitly "verification only, no code change expected") was attempted but not completed for the reasons above — this is a shortfall on a best-effort bonus task, not a deviation in implementation scope.

## Blockers Encountered
- No reliable UI-automation/accessibility-inspector tooling available in this session to drive precise taps in the iOS Simulator, which blocked completing Task 3's on-device visual confirmation. The code change itself (Task 1) and static analysis (Task 2) were completed with no blockers.

## Ready For QA
Yes. The implementation (Task 1) is complete, minimal, and matches the plan exactly (single line removed, no other changes). `flutter analyze` passes with 0 errors. Task 3's on-device visual confirmation is outstanding and should be performed by QA with direct interactive simulator/device access — this is a low-regression-risk, one-line change per the Architect's own risk assessment, so it should not block QA from proceeding, but Tier 1 Tests 1–7 in `ARCHITECT_PLAN.md` still need a real pass before merge.

## Git Diff

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..ae86f39 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -430,7 +430,6 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
               ],
               TextField(
                 controller: _csvController,
-                autofocus: true,
                 maxLines: 5,
                 minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
```

---

## Addendum — 2026-07-28 — Bottom Sheet Glitch on Manual Tap

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios (unchanged)

### Goal
Add a stable `Key` to the paste `TextField` so Flutter's list-reconciliation algorithm can match its element by key (instead of losing it to positional-reordering) across every `keyboardHeight` transition, preventing the element (and its implicit `FocusNode`) from being destroyed and recreated unfocused when the user taps into the field.

### Architect Tasks Completed (Addendum)
- [x] Task A — Added `key: const ValueKey('bulk-entry-csv-field'),` to the paste `TextField` (`controller: _csvController`) in `bulk_entry_screen.dart`, as the first named argument, immediately before `controller:`. No other property (`controller`, `maxLines`, `minLines`, `style`, `decoration`) was changed. No `Key` was added to any other widget in the file. The prior commit removing `autofocus: true` was not touched, reverted, or modified.
- [x] Task B — `flutter analyze` run: 0 errors, 0 warnings.
- [ ] Task C — Attempted, not completed interactively. See Verification section below.

### Files Modified (Addendum)
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results (Addendum)
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found! (ran in 3.9s)"

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` run: 0 files changed (already correctly formatted).

### Verification (Addendum)
No iOS Simulator was booted in this session (`xcrun simctl list devices booted` returned no booted devices), and this session has no verified working interactive touch-input/UI-automation tooling — the prior session's attempt at coordinate-mapped taps via `cliclick` against the Simulator window was already found unreliable (documented above) and led to unintended navigation in demo data, so it was not repeated.

**I did not perform Task C's interactive tap-testing (tap into field → confirm no flicker/reset → confirm focus holds and text is retained → dismiss and re-tap 2–3 times to confirm repeatability).** I am reporting this gap plainly rather than fabricating a result, per this session's explicit instruction — this is exactly the class of gap that caused the previous QA pass to miss the underlying bug.

What was verified: the code change is a single, additive `key:` argument with no other lines touched (confirmed via `git diff`), `flutter analyze` passes clean, and `dart format` made no changes. Static reasoning about the fix's mechanism (Flutter's `Element.updateChildren` middle-region key-based matching) is documented in the Architect's addendum and is not re-derived here — this report only attests to what was actually run.

**This session cannot close the Task C / Verification Plan Addendum (PRE-DEPLOY TESTS 8–10) verification gap.** QA or a human with hands-on Simulator/device access must perform the real interactive tap-cycle test before this addendum can be considered fully verified, consistent with the Architect's own note that this fix is "not independently runtime-confirmed via interactive tap in this session."

### Deviations From Architect Plan (Addendum)
None in the code change itself. Task C (explicitly verification-only) was attempted but not completed, for the reasons above — a reporting gap on a task this session lacked tooling for, not a scope deviation.

### Blockers Encountered (Addendum)
- No booted Simulator and no reliable interactive touch-automation harness available in this session, blocking Task C's on-device confirmation. The code change (Task A) and static analysis (Task B) completed with no blockers.

### Ready For QA (Addendum)
Yes, with the same caveat as the original report: the implementation (Task A) is complete, minimal, and matches the addendum exactly (single `key:` argument added, nothing else touched). `flutter analyze` passes with 0 errors. Task C's interactive tap/focus/repeatability confirmation is outstanding and must be performed by QA (or Tony) with real touch input on a Simulator or device before this addendum is considered verified — per the Architect's addendum, this is precisely the check that must not be waived in favor of code-path analysis alone.

### Git Diff (Addendum)

Correction: the `autofocus: true` removal from the original Task 1 is **not yet committed** — `git log` on this file shows no commit past `f3e400c` (the commit that introduced `autofocus: true` in the first place), and `git status` shows the file as an uncommitted working-tree modification. Both the autofocus removal and this addendum's `key:` addition currently coexist as one uncommitted diff against `HEAD`. Per this session's instructions, the autofocus removal was not touched, reverted, or modified — only the `key:` line was added on top of it. The combined working-tree diff is:

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..1993ca6 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -429,8 +429,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 const SizedBox(height: Spacing.space16),
               ],
               TextField(
+                key: const ValueKey('bulk-entry-csv-field'),
                 controller: _csvController,
-                autofocus: true,
                 maxLines: 5,
                 minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
```

This addendum's isolated contribution within that diff is solely the `+ key: const ValueKey('bulk-entry-csv-field'),` line.

---

## Out-of-Plan Change — 2026-07-28 — Instructional Box Border Removed, Paste Field Made More Prominent

### Status
**Not authorized by `ARCHITECT_PLAN.md` or its addendum.** Made at Tony's direct, explicit request in-session, as product owner, after Task A/B/C above. Logged here per his instruction rather than silently folded into the addendum's scope. Not yet reflected in the Architect plan's Files to Modify table, System Impact Map, or QA Regression Areas — QA should treat this as a distinct, unreviewed visual change alongside the `Key`-fix addendum.

### What Changed
Both changes are in the same already-authorized file, `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, and touch only styling — no logic, no state, no conditionals added or removed:

1. **Removed the border around the instructional info box** (the `Column order:` / example / required-optional block, `keyboardHeight == 0` branch): deleted the `BoxDecoration` (`Border.all(color: context.colors.textMuted.withValues(alpha: 0.5))`, `borderRadius: BorderRadius.circular(8)`) from that `Container`. Its `padding: const EdgeInsets.all(Spacing.space8)` and content were left unchanged.
2. **Made the paste `TextField` more prominent**: increased `fillColor` opacity from `Colors.white.withValues(alpha: 0.04)` to `0.08`, and increased `border`/`enabledBorder` width from the implicit default (1) to `1.5`. `focusedBorder` (already `AppColors.primary`, width 2) was left unchanged as the most prominent state.

### Why
Direct product-owner request in this session: "remove the border around the instructional text. make the text field a bit more prominent." No further specification was given; width/opacity values were my judgment call for a "bit more prominent" without overshooting into a larger visual redesign.

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (same file as Task A; no other file touched)

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found! (ran in 5.5s)"

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` run: 0 files changed.

### Verification
Not visually verified in a running app or Simulator in this session (same tooling gap as Task C above — no booted Simulator, no reliable interactive UI-automation harness). This is a pure styling diff with no logic change, so `flutter analyze` passing is the only automated signal available; Tony or QA should eyeball it in the running app before merge, particularly to confirm the instructional box still reads clearly without its border (e.g., against the background it no longer visually separates from) and that the field's increased prominence doesn't clash with the surrounding dark theme.

### Deviations From Architect Plan
Yes — this entire section is a deviation. It was not requested or authorized by `ARCHITECT_PLAN.md` or its addendum. Justification: small, purely cosmetic, single-file, no logic/state change, explicit direct instruction from the product owner. Recommend the Architect plan be updated (or a follow-up addendum written) if this is to be treated as permanent scope, so QA's regression checklist accounts for it.

### Blockers Encountered
None for implementation. Visual/on-device verification blocked by the same Simulator/tooling gap noted under Task C.

### Ready For QA
Yes for code correctness (`flutter analyze` clean, minimal diff), but this change has had **zero visual verification** — QA should specifically eyeball both the instructional box (border removed) and the paste field (increased fill/border prominence) in the running app, since neither Engineer nor this session confirmed the actual rendered appearance.

### Git Diff

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..1d44712 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -375,12 +375,6 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 const SizedBox(height: Spacing.space12),
                 Container(
                   padding: const EdgeInsets.all(Spacing.space8),
-                  decoration: BoxDecoration(
-                    border: Border.all(
-                      color: context.colors.textMuted.withValues(alpha: 0.5),
-                    ),
-                    borderRadius: BorderRadius.circular(8),
-                  ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.stretch,
                     children: [
@@ -429,8 +423,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 const SizedBox(height: Spacing.space16),
               ],
               TextField(
+                key: const ValueKey('bulk-entry-csv-field'),
                 controller: _csvController,
-                autofocus: true,
                 maxLines: 5,
                 minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
@@ -447,7 +441,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                     fontFamily: 'monospace',
                   ),
                   filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
+                  fillColor: Colors.white.withValues(alpha: 0.08),
                   contentPadding: keyboardHeight > 0
                       ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
                       : const EdgeInsets.all(12),
@@ -455,12 +449,14 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
                       color: context.colors.border,
+                      width: 1.5,
                     ),
                   ),
                   enabledBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
                       color: context.colors.border,
+                      width: 1.5,
                     ),
                   ),
                   focusedBorder: OutlineInputBorder(
```

Note: this diff is cumulative against `HEAD` (includes the still-uncommitted autofocus removal and `Key` addition from earlier sections of this report). This section's isolated contribution is the border removal on the instructional `Container` and the `fillColor`/border-width changes on the paste `TextField`'s `border`/`enabledBorder`.

---

## Deviation — 2026-07-28 — Direct visual tweak by Tony

### What Changed

Confirmed via `git diff -- lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, on top of the addendum's `Key` fix, exactly two additional changes:

1. **Instructional info-box border removed.** The `Container` wrapping the "Column order:" / example / required-optional block lost its `decoration: BoxDecoration(border: Border.all(color: context.colors.textMuted.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(8))`. Before: bordered box with 8px rounded corners. After: no decoration at all — `padding: const EdgeInsets.all(Spacing.space8)` and the content `Column` are unchanged.
2. **Paste field made more visually prominent.**
   - `fillColor`: `Colors.white.withValues(alpha: 0.04)` → `Colors.white.withValues(alpha: 0.08)`.
   - `border` (`OutlineInputBorder`'s `borderSide`): implicit default width (1) → explicit `width: 1.5`.
   - `enabledBorder` (`OutlineInputBorder`'s `borderSide`): implicit default width (1) → explicit `width: 1.5`.
   - `focusedBorder`: unchanged (still `AppColors.primary`, width 2).

No other lines in the file were touched; no widgets, dependencies, or conditionals were added or removed.

### Who Made It

Tony, directly, outside the Architect plan — a manual edit to the working tree, not implemented by the Engineer agent per `ARCHITECT_PLAN.md` or its addendum.

### Why Logged as a Deviation Rather Than Rejected

- Small and purely cosmetic — no logic, state, or conditional change.
- Confined to the single file (`bulk_entry_screen.dart`) already authorized for this branch.
- No new widgets, dependencies, or conditionals introduced.

### Scope Note for QA

This expands the diff QA must review. The info-box border removal and the paste field's increased prominence (`fillColor` opacity, `border`/`enabledBorder` width) are new visual changes not covered by the original Architect plan's Verification Plan or QA Regression Areas. QA should review these for diff safety (Phase 10) and basic visual sanity, though they carry no functional/logic risk.

### Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found! (ran in 4.3s)"

### Formatting

Command: `dart format --output=none --set-exit-if-changed lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: exit code 0, 0 files would change ("Formatted 1 file (0 changed)").

Both checks were run independently in this session and confirm Tony's report that both already pass.

---

## Addendum 2 — 2026-07-28 — Container Identity-Collision Fix + Temporary Diagnostic Instrumentation

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios (unchanged)

### Context
Confirmed at session start via `git branch --show-current` (`bug/bulk-entry-instructions-cutoff-ios`) and `git status`/`git diff` that the working tree exactly matched the state described above (autofocus removed, `Key` on the CSV field, the two out-of-plan cosmetic tweaks) — nothing had drifted. This session implemented exactly Tasks A–D from `ARCHITECT_PLAN.md`'s "Addendum 2 — Key Fix Did Not Resolve the Bug," all confined to `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`. `lib/shared/widgets/keyboard_aware_wrapper.dart` was explicitly not touched, per the addendum's Stop-Condition flag. No Simulator UI-automation was attempted (Task E) — this diagnostic is designed for Tony to run by hand with real touch input.

### Architect Tasks Completed (Addendum 2)

- [x] **Task A (permanent fix)** — Added `key: const ValueKey('bulk-entry-keyboard-toolbar')` to the `Container` returned by `_buildKeyboardToolbar()`, and `key: const ValueKey('bulk-entry-footer')` to the `Container` returned by `_buildFooter()`. This closes the unkeyed-`Container`-identity-collision defect Addendum 2 identified in the outer `Column` (both bare `Container`s previously had the same `runtimeType`/no key, so `Widget.canUpdate` treated them as interchangeable across `keyboardHeight` transitions, updating one element in place with the other's completely different subtree). No other property of either method changed.
- [x] **Task B (temporary diagnostics, all tagged `// TEMP-DEBUG`)** — Added:
  - `_csvFocusNode` (`FocusNode(debugLabel: 'DEBUG-bulk-entry-csv')`) and `_csvScrollController` (`ScrollController(debugLabel: 'DEBUG-bulk-entry-csv-scroll')`) as new `State` fields.
  - Listeners on both, registered in `initState()`, that `debugPrint` a `[DEBUG-BULK-ENTRY]` line on every focus change (`hasFocus`, the node's `identityHashCode`, a timestamp) and every internal-scroll-offset change (offset, timestamp).
  - Disposal of both in `dispose()`.
  - A `debugPrint` at the top of `build()` logging `keyboardHeight` and a timestamp on every rebuild.
  - `focusNode: _csvFocusNode` and `scrollController: _csvScrollController` wired onto the CSV paste `TextField` (previously implicit/unmanaged).
  - The CSV `TextField` wrapped in a `Container` with a 4px solid red border for visual identification.
  - `_buildKeyboardToolbar()`'s `Container` border temporarily changed from `Border(top: BorderSide(color: context.colors.border, width: 1))` to a 4px solid lime border (original value preserved in an adjacent `// TEMP-DEBUG` comment for exact restoration), so it is visually distinguishable from the red CSV field and the unmodified Footer.
- [x] **Task C (temporary controlled experiment, tagged `// TEMP-DEBUG`)** — Added `autocorrect: false` and `enableSuggestions: false` to the CSV `TextField`, to directly test whether iOS's native QuickType/predictive-text bar is a contributing or sole cause.
- [x] **Task D** — `flutter analyze` run: 0 errors, 0 warnings, both immediately after implementation and again after `dart format`.

### Files Modified (Addendum 2)
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` (only file touched)

### TEMP-DEBUG Line Inventory (for unambiguous future removal)
Confirmed via `grep -n "TEMP-DEBUG" lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` — every line below must be removed (along with the `_csvFocusNode`/`_csvScrollController` fields, their listeners, and the wrapping red-bordered `Container`, per the addendum) before this bug can be considered commit-ready. Line numbers are current, post-`dart format`:

- L133, L135 — `_csvFocusNode` / `_csvScrollController` field declarations
- L153, L156, L158, L162 — `initState()` listener registration (focus + scroll)
- L172, L173 — `dispose()` cleanup
- L370 — `build()`-entry `debugPrint`
- L445, L448 — wrapping red-bordered `Container` (`decoration`)
- L452, L453, L454, L455 — `focusNode`, `scrollController`, `autocorrect`, `enableSuggestions` on the CSV `TextField`
- L499, L500 — closing braces for the wrapping `Container`/`TextField`
- L775, L776 — `_buildKeyboardToolbar()`'s lime border (comment records the original border value: `Border(top: BorderSide(color: context.colors.border, width: 1))`)

19 tagged lines total (plus the 2 untagged-but-Task-A-permanent `key:` lines at L768/L818, which are the real fix and must **not** be removed when TEMP-DEBUG is stripped).

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!" (run once immediately after implementation, once more after `dart format`).

### Formatting
Command: `dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: 1 file reformatted (wrapping/line-break adjustments only — no semantic change, re-confirmed clean via a second `flutter analyze` pass after formatting).

### Verification
No Simulator or device testing was performed in this session, per Task E — this diagnostic is explicitly designed for Tony to run by hand with real touch input and read the debug console himself, not for the Engineer to attempt Simulator UI-automation (which two prior sessions already found unreliable for this exact screen). `flutter analyze` is the only automated signal for this session; the actual diagnostic verification (console output, border-color identification, autocorrect/enableSuggestions on/off comparison, repeatability across taps) is Tony's to perform and report back, per the Diagnostic Protocol in Addendum 2.

### Deviations From Architect Plan
None. Tasks A–D were implemented exactly as specified, confined to the one authorized file. `lib/shared/widgets/keyboard_aware_wrapper.dart` was not modified. Task E (no Simulator automation) was respected by omission.

### Blockers Encountered
None.

### Ready For QA
Not applicable in the usual sense — per Addendum 2, this session's pipeline pauses after Tasks A–D for Tony's diagnostic report before any further fix is designed. Task A (the `Key` additions to `_buildKeyboardToolbar()`/`_buildFooter()`) is a genuine, low-risk, permanent fix ready for eventual QA review once the TEMP-DEBUG instrumentation is stripped. Tasks B/C must not ship — all 19 tagged lines above must be removed once Tony's diagnostic session is complete.

### Git Diff (Addendum 2)

Cumulative diff against `HEAD` for this file (includes all prior uncommitted work described earlier in this report, plus this session's Task A–C additions):

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..04c0c6d 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -129,6 +129,10 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   bool _isSubmitting = false;
   final ScrollController _scrollController = ScrollController();
   final TextEditingController _csvController = TextEditingController();
+  final FocusNode _csvFocusNode =
+      FocusNode(debugLabel: 'DEBUG-bulk-entry-csv'); // TEMP-DEBUG
+  final ScrollController _csvScrollController =
+      ScrollController(debugLabel: 'DEBUG-bulk-entry-csv-scroll'); // TEMP-DEBUG
 
   int _focusedRowIndex = 0;
   bool _isLoadingSongs = false;
@@ -145,6 +149,17 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     for (var i = 0; i < _kInitialRows; i++) {
       _rows.add(_createRow());
     }
+    _csvFocusNode.addListener(() {
+      // TEMP-DEBUG
+      debugPrint('[DEBUG-BULK-ENTRY] focus hasFocus=${_csvFocusNode.hasFocus} '
+          'node=${identityHashCode(_csvFocusNode)} time=${DateTime.now().toIso8601String()}');
+    }); // TEMP-DEBUG
+    _csvScrollController.addListener(() {
+      // TEMP-DEBUG
+      debugPrint(
+          '[DEBUG-BULK-ENTRY] internal scroll offset=${_csvScrollController.offset} '
+          'time=${DateTime.now().toIso8601String()}');
+    }); // TEMP-DEBUG
   }
 
   @override
@@ -154,6 +169,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     }
     _scrollController.dispose();
     _csvController.dispose();
+    _csvFocusNode.dispose(); // TEMP-DEBUG
+    _csvScrollController.dispose(); // TEMP-DEBUG
     super.dispose();
   }
 
@@ -349,6 +366,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   @override
   Widget build(BuildContext context) {
     final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
+    debugPrint(
+        '[DEBUG-BULK-ENTRY] build() keyboardHeight=$keyboardHeight time=${DateTime.now().toIso8601String()}'); // TEMP-DEBUG
     final validCount = _validRowCount;
     final hasValid = validCount > 0;
 
@@ -428,50 +447,63 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 ),
                 const SizedBox(height: Spacing.space16),
               ],
-              TextField(
-                controller: _csvController,
-                autofocus: true,
-                maxLines: 5,
-                minLines: keyboardHeight > 0 ? 1 : 3,
-                style: TextStyle(
-                  fontSize: AppFontSizes.caption,
-                  color: context.colors.textPrimary,
-                  fontFamily: 'monospace',
-                ),
-                decoration: InputDecoration(
-                  isDense: keyboardHeight > 0,
-                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
-                  hintStyle: TextStyle(
+              Container(
+                // TEMP-DEBUG
+                decoration: BoxDecoration(
+                    border:
+                        Border.all(color: Colors.red, width: 4)), // TEMP-DEBUG
+                child: TextField(
+                  key: const ValueKey('bulk-entry-csv-field'),
+                  controller: _csvController,
+                  focusNode: _csvFocusNode, // TEMP-DEBUG
+                  scrollController: _csvScrollController, // TEMP-DEBUG
+                  autocorrect: false, // TEMP-DEBUG
+                  enableSuggestions: false, // TEMP-DEBUG
+                  maxLines: 5,
+                  minLines: keyboardHeight > 0 ? 1 : 3,
+                  style: TextStyle(
                     fontSize: AppFontSizes.caption,
-                    color: context.colors.textMuted.withValues(alpha: 0.5),
+                    color: context.colors.textPrimary,
                     fontFamily: 'monospace',
                   ),
-                  filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: keyboardHeight > 0
-                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
-                      : const EdgeInsets.all(12),
-                  border: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  decoration: InputDecoration(
+                    isDense: keyboardHeight > 0,
+                    hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
+                    hintStyle: TextStyle(
+                      fontSize: AppFontSizes.caption,
+                      color: context.colors.textMuted.withValues(alpha: 0.5),
+                      fontFamily: 'monospace',
                     ),
-                  ),
-                  enabledBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                    filled: true,
+                    fillColor: Colors.white.withValues(alpha: 0.08),
+                    contentPadding: keyboardHeight > 0
+                        ? const EdgeInsets.symmetric(
+                            horizontal: 12, vertical: 0)
+                        : const EdgeInsets.all(12),
+                    border: OutlineInputBorder(
+                      borderRadius: BorderRadius.circular(8),
+                      borderSide: BorderSide(
+                        color: context.colors.border,
+                        width: 1.5,
+                      ),
                     ),
-                  ),
-                  focusedBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: const BorderSide(
-                      color: AppColors.primary,
-                      width: 2,
+                    enabledBorder: OutlineInputBorder(
+                      borderRadius: BorderRadius.circular(8),
+                      borderSide: BorderSide(
+                        color: context.colors.border,
+                        width: 1.5,
+                      ),
+                    ),
+                    focusedBorder: OutlineInputBorder(
+                      borderRadius: BorderRadius.circular(8),
+                      borderSide: const BorderSide(
+                        color: AppColors.primary,
+                        width: 2,
+                      ),
                     ),
                   ),
-                ),
-              ),
+                ), // TEMP-DEBUG (closes TextField)
+              ), // TEMP-DEBUG (closes wrapping Container)
               if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
               SizedBox(
                 height: 40,
@@ -739,13 +765,15 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildKeyboardToolbar() {
     return Container(
+      key: const ValueKey('bulk-entry-keyboard-toolbar'),
       padding: const EdgeInsets.symmetric(
         horizontal: Spacing.space16,
         vertical: Spacing.space8,
       ),
       decoration: BoxDecoration(
         color: context.colors.surfaceElevated,
-        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
+        // TEMP-DEBUG: original was `Border(top: BorderSide(color: context.colors.border, width: 1))`
+        border: Border.all(color: Colors.lime, width: 4), // TEMP-DEBUG
       ),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end,
@@ -787,6 +815,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildFooter(bool hasValid, int validCount) {
     return Container(
+      key: const ValueKey('bulk-entry-footer'),
       padding: EdgeInsets.fromLTRB(
         Spacing.pagePadding,
         Spacing.space12,
```


---
---

## Addendum 3 Engineer Report — 2026-07-28 — Tasks F–G (Strip Diagnostic Instrumentation)

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios

### Branch Confirmed
`git branch --show-current` → `bug/bulk-entry-instructions-cutoff-ios` (existing branch, not created)

### Goal
Strip all of Addendum 2's Task B (diagnostic instrumentation: `_csvFocusNode`/`_csvScrollController`, their listeners/disposal, the `debugPrint` calls, the red-bordered wrapping `Container`) and Task C (`autocorrect: false, enableSuggestions: false` experiment) from `bulk_entry_screen.dart`, restoring the CSV paste field to exactly Addendum 1's original spec — a single, directly-keyed, unwrapped `TextField`. Restore `_buildKeyboardToolbar()`'s border to its original value. This addendum's own root-cause finding was that the diagnostic wrapper itself (an unkeyed `Container` placed around the correctly-keyed `TextField`) defeated Addendum 1's `Key` fix by hiding the key one level too deep for Flutter's `Element.updateChildren` reconciliation to see — so removing the wrapper is the fix being tested, not new code.

### Architect Tasks Completed (Addendum 3)
- [x] Task F — Stripped all Addendum 2 Task B/C diagnostic code from `bulk_entry_screen.dart`:
  - Removed `_csvFocusNode` and `_csvScrollController` field declarations.
  - Removed both `addListener` registrations for them in `initState()`.
  - Removed both `.dispose()` calls for them in `dispose()`.
  - Removed the `debugPrint(...)` call at the top of `build()`; the `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` line directly above it (original, non-diagnostic code) was left untouched.
  - Replaced the red-bordered wrapping `Container` + inner `TextField` (which also carried `focusNode:`, `scrollController:`, `autocorrect: false`, `enableSuggestions: false`) with a single bare `TextField` — `key: const ValueKey('bulk-entry-csv-field')`, `controller: _csvController`, `maxLines: 5`, `minLines: keyboardHeight > 0 ? 1 : 3`, `style`, and `decoration` all preserved exactly as they were (minus the diagnostic-only parameters). No `focusNode`, no `scrollController`, no `autocorrect`, no `enableSuggestions`, no wrapping `Container`.
  - In `_buildKeyboardToolbar()`, restored `border: Border(top: BorderSide(color: context.colors.border, width: 1))` in place of the lime debug border, and removed the `// TEMP-DEBUG` comment. `key: const ValueKey('bulk-entry-keyboard-toolbar')` (Addendum 2 Task A's permanent fix) was left untouched.
  - Confirmed `_buildFooter()`'s `key: const ValueKey('bulk-entry-footer')` is untouched.
  - Grepped the file for `TEMP-DEBUG` after all edits: zero matches (`grep -n "TEMP-DEBUG" ... ; echo "grep exit: $?"` → exit code 1, no output).
- [x] Task G — `flutter analyze` run on the changed file and project-wide: 0 errors, 0 warnings, both before and after `dart format`.
- Task H (verification-only, real-device) is explicitly out of scope for this Engineer session per the task input — reserved for Tony to run on a physical device. No Simulator UI-automation was attempted, consistent with Addendum 2 Task E's instruction not to re-attempt it.

### Files Created
- none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: `No issues found! (ran in 0.9s)`

Command: `flutter analyze` (project-wide)
Result: `No issues found! (ran in 5.6s)`

Re-ran the single-file analyze after `dart format` as a final sanity check: `No issues found! (ran in 0.3s)`.

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` → `Formatted 1 file (1 changed) in 0.01 seconds.` Only this file was formatted; no other files touched.

### TEMP-DEBUG Confirmation
`grep -n "TEMP-DEBUG" lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` returns zero matches (confirmed both immediately after the edits and again after `dart format`, in case formatting shifted anything).

### Test Results
Not run. No existing test covers `bulk_entry_screen.dart` (per the prior Engineer Report's confirmation, unchanged in this session), and the Architect plan does not require adding one for Task F/G.

### Verification
Manual steps performed:
- Confirmed current branch via `git branch --show-current` before making any change.
- Read `ARCHITECT_PLAN.md` in full, including all three addenda, before implementing.
- Grepped the file for all `TEMP-DEBUG`, `_csvFocusNode`, `_csvScrollController`, `debugPrint`, and the three permanent `ValueKey`s to locate exact line numbers before editing.
- Made each of Task F's six sub-edits individually, confirming via the IDE diagnostics hook (surfaced automatically after the first edit, showing expected transient "undefined name" errors for `_csvFocusNode`/`_csvScrollController` references not yet removed) that no edit was applied out of order or left a dangling reference.
- Ran `flutter analyze` twice (single-file, then project-wide) confirming 0 errors both times.
- Ran `dart format` on the single changed file only.
- Re-confirmed zero `TEMP-DEBUG` matches after formatting.
- Task H (real-device interactive verification) was **not** attempted in this session per the task instructions — reserved for Tony on a physical device, consistent with Addendum 2 Task E's explicit instruction not to re-attempt Simulator UI-automation.

### Deviations From Architect Plan
None. Task F was implemented exactly as specified, including preserving Addendum 2 Task A's two permanent `Key`s (`_buildKeyboardToolbar()`, `_buildFooter()`) untouched. Task H was intentionally not attempted, per this session's explicit task input (not a deviation — it was scoped out of this Engineer session from the start).

### Blockers Encountered
None.

### Ready For QA
Yes, for Tasks F–G (code-level). Task H (real-device confirmation that the clean, unwrapped, fully-keyed `TextField` resolves the focus-loss/glitch bug on iOS and Android) is outstanding and must be performed by Tony on a real device before this addendum can be considered fully verified — per the Architect's own framing, this is the first time the combination of Addendum 1's key fix and Addendum 2 Task A's toolbar/footer keys will be tested with zero instrumentation, and code-path analysis alone is not sufficient given the history of this bug (two prior HIGH-confidence, code-only diagnoses both failed real-device verification).

### Git Diff (Addendum 3 session — cumulative uncommitted diff against HEAD)

Note: this is the complete `git diff` for the file at the end of this session, which reflects the cumulative uncommitted state of the branch (Addendum 1's key + autofocus removal, the two out-of-plan cosmetic tweaks noted in Addendum 2's Context section, Addendum 2 Task A's toolbar/footer keys, and this session's Task F removals), since none of the prior addenda's work has been committed yet. The hunks touching `_csvFocusNode`/`_csvScrollController`, the `debugPrint` calls, the red-bordered `Container` wrapper, and the lime toolbar border — all introduced by Addendum 2 Task B/C and removed by this session's Task F — net out to zero net diff against `HEAD` for those specific lines, since they were added and removed entirely within uncommitted working-tree state and do not appear in the diff below.

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..02a2aa4 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -375,12 +375,6 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 const SizedBox(height: Spacing.space12),
                 Container(
                   padding: const EdgeInsets.all(Spacing.space8),
-                  decoration: BoxDecoration(
-                    border: Border.all(
-                      color: context.colors.textMuted.withValues(alpha: 0.5),
-                    ),
-                    borderRadius: BorderRadius.circular(8),
-                  ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.stretch,
                     children: [
@@ -429,8 +423,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                 const SizedBox(height: Spacing.space16),
               ],
               TextField(
+                key: const ValueKey('bulk-entry-csv-field'),
                 controller: _csvController,
-                autofocus: true,
                 maxLines: 5,
                 minLines: keyboardHeight > 0 ? 1 : 3,
                 style: TextStyle(
@@ -447,7 +441,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                     fontFamily: 'monospace',
                   ),
                   filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
+                  fillColor: Colors.white.withValues(alpha: 0.08),
                   contentPadding: keyboardHeight > 0
                       ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
                       : const EdgeInsets.all(12),
@@ -455,12 +449,14 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
                       color: context.colors.border,
+                      width: 1.5,
                     ),
                   ),
                   enabledBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(8),
                     borderSide: BorderSide(
                       color: context.colors.border,
+                      width: 1.5,
                     ),
                   ),
                   focusedBorder: OutlineInputBorder(
@@ -739,13 +735,16 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildKeyboardToolbar() {
     return Container(
+      key: const ValueKey('bulk-entry-keyboard-toolbar'),
       padding: const EdgeInsets.symmetric(
         horizontal: Spacing.space16,
         vertical: Spacing.space8,
       ),
       decoration: BoxDecoration(
         color: context.colors.surfaceElevated,
-        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
+        border: Border(
+          top: BorderSide(color: context.colors.border, width: 1),
+        ),
       ),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end,
@@ -787,6 +786,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildFooter(bool hasValid, int validCount) {
     return Container(
+      key: const ValueKey('bulk-entry-footer'),
       padding: EdgeInsets.fromLTRB(
         Spacing.pagePadding,
         Spacing.space12,
```

---

## Addendum 4 Engineer Report — 2026-07-28 — Tasks I–L (Overflow Fix, Footer Visibility, Paste-UI Collapse on Load)

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios

### Branch Confirmed
`git branch --show-current` → `bug/bulk-entry-instructions-cutoff-ios` (existing branch, not created)

### Goal
Implement Addendum 4's three independent, real-device-reported issues in `bulk_entry_screen.dart`'s `build()`: (I) a `RenderFlex` overflow when the keyboard is open, fixed by wrapping the paste-UI block in a `Flexible`/`SingleChildScrollView` only when `keyboardHeight > 0`; (J) the footer floating above the keyboard while unusable, fixed by hiding it whenever `!_hasLoadedSongs && keyboardHeight > 0`; (K) the table showing only column headers after "Load Songs," fixed by widening the paste-UI collapse condition from `keyboardHeight == 0` to a new `showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs` so the block stays compact once songs are loaded, freeing space for the table.

### Architect Tasks Completed (Addendum 4)
- [x] Task I — Extracted the existing paste-UI `Padding` subtree (intro text, info box, `TextField`, "Load Songs" button, ingestion-summary text) into a local `pasteUiBlock` variable, content byte-for-byte unchanged except for Task K's substitutions applied within it (Task I and K necessarily land in the same edit since K's substitutions live inside the block I is extracting). Replaced the outer `Column`'s first child with `keyboardHeight > 0 ? Flexible(child: SingleChildScrollView(child: pasteUiBlock)) : pasteUiBlock`. Did not touch `_buildKeyboardToolbar()`, `_buildFooter()`, or the `if (_hasLoadedSongs) [...] else Expanded(...)` branch.
- [x] Task J — Changed the footer's line in the outer `Column` from unconditional `_buildFooter(hasValid, validCount),` to `if (_hasLoadedSongs || keyboardHeight == 0) _buildFooter(hasValid, validCount),`. Did not modify `_buildFooter()`'s own body or `_buildKeyboardToolbar()`.
- [x] Task K — Added `final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;` immediately after the `keyboardHeight` line. Applied all six substitutions from Addendum 4's Issue 3 "Proposed Solution" table exactly as specified:
  - Padding top value: `keyboardHeight > 0 ? Spacing.space4 : Spacing.space12` → `showFullPasteUi ? Spacing.space12 : Spacing.space4`
  - Instructional block gate: `if (keyboardHeight == 0) ...[` → `if (showFullPasteUi) ...[`
  - `minLines: keyboardHeight > 0 ? 1 : 3` → `minLines: showFullPasteUi ? 3 : 1`
  - `isDense: keyboardHeight > 0` → `isDense: !showFullPasteUi`
  - `contentPadding` ternary → `showFullPasteUi ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 12, vertical: 0)`
  - Trailing spacer gate: `if (keyboardHeight == 0) const SizedBox(height: Spacing.space8)` → `if (showFullPasteUi) const SizedBox(height: Spacing.space8)`
  - Did not modify `_handleCsvIngestion()` or `_populateTableFromParseResult()` — neither was touched, per the plan's explicit instruction that both are already confirmed correct.
- [x] Task L — `flutter analyze` run on the changed file and project-wide: 0 errors, 0 warnings.
- Task M (real-device verification of all three issues) is explicitly verification-only per the task input — reserved for Tony to run on a real device, not attempted in this session.

### Files Created
- none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: `No issues found! (ran in 0.8s)`

Command: `flutter analyze` (project-wide)
Result: `No issues found! (ran in 5.1s)`

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` → `Formatted 1 file (0 changed) in 0.01 seconds.` No formatting changes were needed; only this file was targeted.

### Test Results
Not run. No existing test covers `bulk_entry_screen.dart` (unchanged from prior addenda's confirmation), and the Architect plan does not require adding one for Tasks I–L.

### Verification
Manual steps performed:
- Confirmed current branch via `git branch --show-current` before making any change.
- Read `ENGINEER.md`, `GUARDRAILS.md`, and the full `ARCHITECT_PLAN.md` (all prior addenda plus Addendum 4 in full) before implementing, per this session's task input.
- Confirmed via `git diff` at session start that the working tree already reflected Addenda 1–3's fixes (autofocus removed, `Key`s on the `TextField`/toolbar/footer, the two logged out-of-plan cosmetic tweaks) with nothing drifted.
- Read the current `build()` method in full (lines 350–539) to get exact, current line content before editing — line numbers had shifted slightly from the plan's references due to Addenda 1–3's prior edits, so all edits were matched against actual current file content rather than the plan's line numbers.
- Applied Tasks I and K in a single edit (unavoidable — Task I extracts the very subtree Task K's substitutions live inside), then Task J as part of the same edit since it's the adjacent closing line of the same `Column`. Verified afterward that all three tasks' distinct behaviors are each independently traceable in the diff (Task I: the `Flexible`/`SingleChildScrollView` wrap and `pasteUiBlock` extraction; Task J: the footer's new `if` guard; Task K: the `showFullPasteUi` declaration and its six substitution sites).
- Ran `flutter analyze` on the single file and project-wide: 0 errors, 0 warnings both times.
- Ran `dart format` on the single changed file; no changes needed.
- Task M (real-device confirmation of no overflow, correct footer visibility, and populated table after load) was **not** attempted in this session — reserved for Tony on a physical device, per the task input.

### Deviations From Architect Plan
None. Tasks I, J, and K were implemented exactly as specified in Addendum 4's Engineer Task Breakdown, confined entirely to `bulk_entry_screen.dart`. `_handleCsvIngestion()` and `_populateTableFromParseResult()` were not touched. `_buildKeyboardToolbar()`'s and `_buildFooter()`'s own bodies were not touched beyond the pre-existing `Key`s from Addendum 2. Task M was intentionally not attempted, per this session's explicit task input (not a deviation — scoped out of this Engineer session from the start).

### Blockers Encountered
None.

### Ready For QA
Yes, for Tasks I–L (code-level: 0 analyzer errors, changes confined to the single authorized file, no touch to the parsing/state-update path or the already-fixed focus/glitch behavior). Task M (real-device confirmation that no `RenderFlex` overflow appears with the keyboard open, that the footer hides/reappears exactly per the new condition, and that the table shows populated rows rather than only headers after "Load Songs") is outstanding and must be performed by Tony on a real device before this addendum can be considered fully verified — consistent with this ticket's established practice of not closing a layout-math diagnosis on code-path confidence alone.

### Git Diff (Addendum 4 session — cumulative uncommitted diff against HEAD)

Note: this is the complete `git diff` for the file at the end of this session, reflecting the cumulative uncommitted state of the branch (Addendum 1's key + autofocus removal, the two out-of-plan cosmetic tweaks logged in Addendum 2's Context section, Addendum 2 Task A's toolbar/footer keys, Addendum 3's diagnostic-instrumentation strip, and this session's Tasks I/J/K), since none of the prior addenda's work has been committed yet.

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..b2b51a8 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -349,174 +349,175 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   @override
   Widget build(BuildContext context) {
     final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
+    final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
     final validCount = _validRowCount;
     final hasValid = validCount > 0;
 
-    return Column(
-      children: [
-        Padding(
-          padding: EdgeInsets.fromLTRB(
-            Spacing.space16,
-            keyboardHeight > 0 ? Spacing.space4 : Spacing.space12,
-            Spacing.space16,
-            0,
-          ),
-          child: Column(
-            crossAxisAlignment: CrossAxisAlignment.stretch,
-            children: [
-              if (keyboardHeight == 0) ...[
-                const Text(
-                  'Paste songs from a spreadsheet, then tap Load Songs.',
-                  style: TextStyle(
-                    color: Colors.white,
-                    fontSize: AppFontSizes.body,
-                  ),
-                ),
-                const SizedBox(height: Spacing.space12),
-                Container(
-                  padding: const EdgeInsets.all(Spacing.space8),
-                  decoration: BoxDecoration(
-                    border: Border.all(
-                      color: context.colors.textMuted.withValues(alpha: 0.5),
+    final pasteUiBlock = Padding(
+      padding: EdgeInsets.fromLTRB(
+        Spacing.space16,
+        showFullPasteUi ? Spacing.space12 : Spacing.space4,
+        Spacing.space16,
+        0,
+      ),
+      child: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          if (showFullPasteUi) ...[
+            const Text(
+              'Paste songs from a spreadsheet, then tap Load Songs.',
+              style: TextStyle(
+                color: Colors.white,
+                fontSize: AppFontSizes.body,
+              ),
+            ),
+            const SizedBox(height: Spacing.space12),
+            Container(
+              padding: const EdgeInsets.all(Spacing.space8),
+              child: Column(
+                crossAxisAlignment: CrossAxisAlignment.stretch,
+                children: [
+                  const Text(
+                    'Column order:',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.subhead,
                     ),
-                    borderRadius: BorderRadius.circular(8),
                   ),
-                  child: Column(
-                    crossAxisAlignment: CrossAxisAlignment.stretch,
-                    children: [
-                      const Text(
-                        'Column order:',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Artist, Song, BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      Text(
-                        '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
-                        style: TextStyle(
-                          color: context.colors.textSecondary,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Required columns: Artist, Song',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Optional columns: BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                    ],
-                  ),
-                ),
-                const SizedBox(height: Spacing.space16),
-              ],
-              TextField(
-                controller: _csvController,
-                autofocus: true,
-                maxLines: 5,
-                minLines: keyboardHeight > 0 ? 1 : 3,
-                style: TextStyle(
-                  fontSize: AppFontSizes.caption,
-                  color: context.colors.textPrimary,
-                  fontFamily: 'monospace',
-                ),
-                decoration: InputDecoration(
-                  isDense: keyboardHeight > 0,
-                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
-                  hintStyle: TextStyle(
-                    fontSize: AppFontSizes.caption,
-                    color: context.colors.textMuted.withValues(alpha: 0.5),
-                    fontFamily: 'monospace',
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Artist, Song, BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
+                    ),
                   ),
-                  filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: keyboardHeight > 0
-                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
-                      : const EdgeInsets.all(12),
-                  border: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  Text(
+                    '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                    style: TextStyle(
+                      color: context.colors.textSecondary,
+                      fontSize: AppFontSizes.subhead,
                     ),
                   ),
-                  enabledBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Required columns: Artist, Song',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
-                  focusedBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: const BorderSide(
-                      color: AppColors.primary,
-                      width: 2,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Optional columns: BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
+                ],
+              ),
+            ),
+            const SizedBox(height: Spacing.space16),
+          ],
+          TextField(
+            key: const ValueKey('bulk-entry-csv-field'),
+            controller: _csvController,
+            maxLines: 5,
+            minLines: showFullPasteUi ? 3 : 1,
+            style: TextStyle(
+              fontSize: AppFontSizes.caption,
+              color: context.colors.textPrimary,
+              fontFamily: 'monospace',
+            ),
+            decoration: InputDecoration(
+              isDense: !showFullPasteUi,
+              hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
+              hintStyle: TextStyle(
+                fontSize: AppFontSizes.caption,
+                color: context.colors.textMuted.withValues(alpha: 0.5),
+                fontFamily: 'monospace',
+              ),
+              filled: true,
+              fillColor: Colors.white.withValues(alpha: 0.08),
+              contentPadding: showFullPasteUi
+                  ? const EdgeInsets.all(12)
+                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
+              border: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
-              SizedBox(
-                height: 40,
-                child: GestureDetector(
-                  onTap: _isLoadingSongs ? null : _handleCsvIngestion,
-                  child: Container(
-                    decoration: BoxDecoration(
-                      color: _isLoadingSongs
-                          ? AppColors.primary.withValues(alpha: 0.4)
-                          : AppColors.primary,
-                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
-                    ),
-                    alignment: Alignment.center,
-                    child: _isLoadingSongs
-                        ? const SizedBox(
-                            width: 18,
-                            height: 18,
-                            child: CircularProgressIndicator(
-                              strokeWidth: 2,
-                              color: Colors.white,
-                            ),
-                          )
-                        : Text(
-                            'Load Songs',
-                            style: AppTextStyles.button.copyWith(
-                              color: Colors.white,
-                              fontSize: AppFontSizes.subhead,
-                            ),
-                          ),
-                  ),
+              enabledBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (_ingestionSummary != null) ...[
-                const SizedBox(height: Spacing.space8),
-                Text(
-                  _ingestionSummary!,
-                  style: AppTextStyles.body.copyWith(
-                    color: context.colors.textSecondary,
-                    fontSize: AppFontSizes.caption,
-                  ),
+              focusedBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: const BorderSide(
+                  color: AppColors.primary,
+                  width: 2,
                 ),
-              ],
-            ],
+              ),
+            ),
           ),
-        ),
+          if (showFullPasteUi) const SizedBox(height: Spacing.space8),
+          SizedBox(
+            height: 40,
+            child: GestureDetector(
+              onTap: _isLoadingSongs ? null : _handleCsvIngestion,
+              child: Container(
+                decoration: BoxDecoration(
+                  color: _isLoadingSongs
+                      ? AppColors.primary.withValues(alpha: 0.4)
+                      : AppColors.primary,
+                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
+                ),
+                alignment: Alignment.center,
+                child: _isLoadingSongs
+                    ? const SizedBox(
+                        width: 18,
+                        height: 18,
+                        child: CircularProgressIndicator(
+                          strokeWidth: 2,
+                          color: Colors.white,
+                        ),
+                      )
+                    : Text(
+                        'Load Songs',
+                        style: AppTextStyles.button.copyWith(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+              ),
+            ),
+          ),
+          if (_ingestionSummary != null) ...[
+            const SizedBox(height: Spacing.space8),
+            Text(
+              _ingestionSummary!,
+              style: AppTextStyles.body.copyWith(
+                color: context.colors.textSecondary,
+                fontSize: AppFontSizes.caption,
+              ),
+            ),
+          ],
+        ],
+      ),
+    );
+
+    return Column(
+      children: [
+        keyboardHeight > 0
+            ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
+            : pasteUiBlock,
         if (_hasLoadedSongs) ...[
           const SizedBox(height: Spacing.space12),
           _buildColumnHeaders(),
@@ -537,7 +538,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
         ] else
           const Expanded(child: SizedBox.shrink()),
         if (keyboardHeight > 0) _buildKeyboardToolbar(),
-        _buildFooter(hasValid, validCount),
+        if (_hasLoadedSongs || keyboardHeight == 0)
+          _buildFooter(hasValid, validCount),
       ],
     );
   }
@@ -739,13 +741,16 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildKeyboardToolbar() {
     return Container(
+      key: const ValueKey('bulk-entry-keyboard-toolbar'),
       padding: const EdgeInsets.symmetric(
         horizontal: Spacing.space16,
         vertical: Spacing.space8,
       ),
       decoration: BoxDecoration(
         color: context.colors.surfaceElevated,
-        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
+        border: Border(
+          top: BorderSide(color: context.colors.border, width: 1),
+        ),
       ),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end,
@@ -787,6 +792,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildFooter(bool hasValid, int validCount) {
     return Container(
+      key: const ValueKey('bulk-entry-footer'),
       padding: EdgeInsets.fromLTRB(
         Spacing.pagePadding,
         Spacing.space12,
```

---

## Addendum 5 Engineer Report — 2026-07-28 — Task N (Type-Stable Wrapper Fix)

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios

### Branch Confirmed
`git branch --show-current` → `bug/bulk-entry-instructions-cutoff-ios` (existing branch, not created)

### Goal
Fix the self-inflicted focus/glitch regression Addendum 4's Task I introduced at the outer `Column`'s first-child slot: the conditional `keyboardHeight > 0 ? Flexible(child: SingleChildScrollView(child: pasteUiBlock)) : pasteUiBlock` changed that slot's `runtimeType` across every `keyboardHeight` transition, defeating reconciliation and tearing down the entire subtree (including the already-keyed `TextField`) on every keyboard open/close. Task N replaces this with an unconditional `Flexible(child: SingleChildScrollView(child: pasteUiBlock))` wrapper present in every state, varying only `flex` (`0`/`1`) and `physics` (`NeverScrollableScrollPhysics`/`ClampingScrollPhysics`) based on `keyboardHeight`, so the slot's widget type never changes and the subtree is always updated in place.

### Architect Tasks Completed (Addendum 5)
- [x] Task N — In `build()`, replaced the outer `Column`'s first child:
  ```dart
  keyboardHeight > 0
      ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
      : pasteUiBlock,
  ```
  with:
  ```dart
  Flexible(
    flex: keyboardHeight > 0 ? 1 : 0,
    child: SingleChildScrollView(
      physics: keyboardHeight > 0
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: pasteUiBlock,
    ),
  ),
  ```
  Did not touch `pasteUiBlock`'s own definition, `_buildKeyboardToolbar()`, `_buildFooter()`, the `if (_hasLoadedSongs) [...] else Expanded(...)` branch, or Task J's footer-visibility condition.
- [x] Task O — `flutter analyze` run project-wide: 0 errors, no issues found.
- Task P (real-device verification on iOS and Android, full stop/restart) is explicitly verification-only per the task input — reserved for Tony, not attempted in this session.

### Files Created
- none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze`
Result: `No issues found! (ran in 5.3s)` — 0 errors.

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` → `Formatted 1 file (0 changed) in 0.00 seconds.` No formatting changes were needed; only this file was targeted.

### Test Results
Not run. No existing test covers `bulk_entry_screen.dart`, and the Architect plan does not require adding one for Task N.

### Verification
Manual steps performed:
- Confirmed current branch via `git branch --show-current` before making any change.
- Read `ENGINEER.md`, `GUARDRAILS.md`, and the full `ARCHITECT_PLAN.md` (all five addenda) before implementing, per this session's task input.
- Located the exact current outer-`Column` first-child slot (lines 518–520) via `grep -n` and direct read, confirmed it matched the plan's cited code byte-for-byte before editing.
- Applied the single edit specified by Task N, confined to those four lines.
- Ran `flutter analyze`: 0 errors, no issues found.
- Ran `dart format` on the single changed file: no changes needed.
- Task P (real-device confirmation of smooth keyboard rise with no flash/flicker/reset, on both iOS and Android, across repeated tap cycles) was **not** attempted in this session — reserved for Tony on real devices, per the task input.

### Deviations From Architect Plan
None. Task N was implemented exactly as specified in Addendum 5's Engineer Task Breakdown, confined entirely to the outer `Column`'s first-child slot in `bulk_entry_screen.dart`. `pasteUiBlock`'s own definition, `_buildKeyboardToolbar()`, `_buildFooter()`, the `if (_hasLoadedSongs) [...] else Expanded(...)` branch, and Task J's footer-visibility condition were not touched.

### Blockers Encountered
None.

### Ready For QA
Yes, for Task N (code-level: 0 analyzer errors, change confined to the single authorized slot, no touch to `pasteUiBlock`'s content or any of the other listed off-limits regions). Task P (real-device confirmation on iOS and Android, full stop/restart, of smooth focus acquisition with no flash/flicker/reset across repeated cycles, no `RenderFlex` overflow with the keyboard open, and unchanged Task I/J/K/Addendum-1 behavior) is outstanding and must be performed by Tony on real devices before this addendum can be considered fully verified — consistent with this ticket's established practice of not closing a reconciliation-mechanics diagnosis on code-path confidence alone.

### Git Diff (Addendum 5 session — cumulative uncommitted diff against HEAD)

Note: this is the complete `git diff` for the file at the end of this session, reflecting the cumulative uncommitted state of the branch (all of Addenda 1–4's prior work plus this session's Task N), since none of the prior addenda's work has been committed yet.

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..4760bcc 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -349,172 +349,179 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   @override
   Widget build(BuildContext context) {
     final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
+    final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
     final validCount = _validRowCount;
     final hasValid = validCount > 0;
 
-    return Column(
-      children: [
-        Padding(
-          padding: EdgeInsets.fromLTRB(
-            Spacing.space16,
-            keyboardHeight > 0 ? Spacing.space4 : Spacing.space12,
-            Spacing.space16,
-            0,
-          ),
-          child: Column(
-            crossAxisAlignment: CrossAxisAlignment.stretch,
-            children: [
-              if (keyboardHeight == 0) ...[
-                const Text(
-                  'Paste songs from a spreadsheet, then tap Load Songs.',
-                  style: TextStyle(
-                    color: Colors.white,
-                    fontSize: AppFontSizes.body,
-                  ),
-                ),
-                const SizedBox(height: Spacing.space12),
-                Container(
-                  padding: const EdgeInsets.all(Spacing.space8),
-                  decoration: BoxDecoration(
-                    border: Border.all(
-                      color: context.colors.textMuted.withValues(alpha: 0.5),
+    final pasteUiBlock = Padding(
+      padding: EdgeInsets.fromLTRB(
+        Spacing.space16,
+        showFullPasteUi ? Spacing.space12 : Spacing.space4,
+        Spacing.space16,
+        0,
+      ),
+      child: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          if (showFullPasteUi) ...[
+            const Text(
+              'Paste songs from a spreadsheet, then tap Load Songs.',
+              style: TextStyle(
+                color: Colors.white,
+                fontSize: AppFontSizes.body,
+              ),
+            ),
+            const SizedBox(height: Spacing.space12),
+            Container(
+              padding: const EdgeInsets.all(Spacing.space8),
+              child: Column(
+                crossAxisAlignment: CrossAxisAlignment.stretch,
+                children: [
+                  const Text(
+                    'Column order:',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.subhead,
                     ),
-                    borderRadius: BorderRadius.circular(8),
                   ),
-                  child: Column(
-                    crossAxisAlignment: CrossAxisAlignment.stretch,
-                    children: [
-                      const Text(
-                        'Column order:',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Artist, Song, BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      Text(
-                        '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
-                        style: TextStyle(
-                          color: context.colors.textSecondary,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Required columns: Artist, Song',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Optional columns: BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                    ],
-                  ),
-                ),
-                const SizedBox(height: Spacing.space16),
-              ],
-              TextField(
-                controller: _csvController,
-                autofocus: true,
-                maxLines: 5,
-                minLines: keyboardHeight > 0 ? 1 : 3,
-                style: TextStyle(
-                  fontSize: AppFontSizes.caption,
-                  color: context.colors.textPrimary,
-                  fontFamily: 'monospace',
-                ),
-                decoration: InputDecoration(
-                  isDense: keyboardHeight > 0,
-                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
-                  hintStyle: TextStyle(
-                    fontSize: AppFontSizes.caption,
-                    color: context.colors.textMuted.withValues(alpha: 0.5),
-                    fontFamily: 'monospace',
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Artist, Song, BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
+                    ),
                   ),
-                  filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: keyboardHeight > 0
-                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
-                      : const EdgeInsets.all(12),
-                  border: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  Text(
+                    '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                    style: TextStyle(
+                      color: context.colors.textSecondary,
+                      fontSize: AppFontSizes.subhead,
                     ),
                   ),
-                  enabledBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Required columns: Artist, Song',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
-                  focusedBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: const BorderSide(
-                      color: AppColors.primary,
-                      width: 2,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Optional columns: BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
+                ],
+              ),
+            ),
+            const SizedBox(height: Spacing.space16),
+          ],
+          TextField(
+            key: const ValueKey('bulk-entry-csv-field'),
+            controller: _csvController,
+            maxLines: 5,
+            minLines: showFullPasteUi ? 3 : 1,
+            style: TextStyle(
+              fontSize: AppFontSizes.caption,
+              color: context.colors.textPrimary,
+              fontFamily: 'monospace',
+            ),
+            decoration: InputDecoration(
+              isDense: !showFullPasteUi,
+              hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
+              hintStyle: TextStyle(
+                fontSize: AppFontSizes.caption,
+                color: context.colors.textMuted.withValues(alpha: 0.5),
+                fontFamily: 'monospace',
+              ),
+              filled: true,
+              fillColor: Colors.white.withValues(alpha: 0.08),
+              contentPadding: showFullPasteUi
+                  ? const EdgeInsets.all(12)
+                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
+              border: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
-              SizedBox(
-                height: 40,
-                child: GestureDetector(
-                  onTap: _isLoadingSongs ? null : _handleCsvIngestion,
-                  child: Container(
-                    decoration: BoxDecoration(
-                      color: _isLoadingSongs
-                          ? AppColors.primary.withValues(alpha: 0.4)
-                          : AppColors.primary,
-                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
-                    ),
-                    alignment: Alignment.center,
-                    child: _isLoadingSongs
-                        ? const SizedBox(
-                            width: 18,
-                            height: 18,
-                            child: CircularProgressIndicator(
-                              strokeWidth: 2,
-                              color: Colors.white,
-                            ),
-                          )
-                        : Text(
-                            'Load Songs',
-                            style: AppTextStyles.button.copyWith(
-                              color: Colors.white,
-                              fontSize: AppFontSizes.subhead,
-                            ),
-                          ),
-                  ),
+              enabledBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (_ingestionSummary != null) ...[
-                const SizedBox(height: Spacing.space8),
-                Text(
-                  _ingestionSummary!,
-                  style: AppTextStyles.body.copyWith(
-                    color: context.colors.textSecondary,
-                    fontSize: AppFontSizes.caption,
-                  ),
+              focusedBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: const BorderSide(
+                  color: AppColors.primary,
+                  width: 2,
+                ),
+              ),
+            ),
+          ),
+          if (showFullPasteUi) const SizedBox(height: Spacing.space8),
+          SizedBox(
+            height: 40,
+            child: GestureDetector(
+              onTap: _isLoadingSongs ? null : _handleCsvIngestion,
+              child: Container(
+                decoration: BoxDecoration(
+                  color: _isLoadingSongs
+                      ? AppColors.primary.withValues(alpha: 0.4)
+                      : AppColors.primary,
+                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                 ),
-              ],
-            ],
+                alignment: Alignment.center,
+                child: _isLoadingSongs
+                    ? const SizedBox(
+                        width: 18,
+                        height: 18,
+                        child: CircularProgressIndicator(
+                          strokeWidth: 2,
+                          color: Colors.white,
+                        ),
+                      )
+                    : Text(
+                        'Load Songs',
+                        style: AppTextStyles.button.copyWith(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+              ),
+            ),
+          ),
+          if (_ingestionSummary != null) ...[
+            const SizedBox(height: Spacing.space8),
+            Text(
+              _ingestionSummary!,
+              style: AppTextStyles.body.copyWith(
+                color: context.colors.textSecondary,
+                fontSize: AppFontSizes.caption,
+              ),
+            ),
+          ],
+        ],
+      ),
+    );
+
+    return Column(
+      children: [
+        Flexible(
+          flex: keyboardHeight > 0 ? 1 : 0,
+          child: SingleChildScrollView(
+            physics: keyboardHeight > 0
+                ? const ClampingScrollPhysics()
+                : const NeverScrollableScrollPhysics(),
+            child: pasteUiBlock,
           ),
         ),
         if (_hasLoadedSongs) ...[
@@ -537,7 +544,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
         ] else
           const Expanded(child: SizedBox.shrink()),
         if (keyboardHeight > 0) _buildKeyboardToolbar(),
-        _buildFooter(hasValid, validCount),
+        if (_hasLoadedSongs || keyboardHeight == 0)
+          _buildFooter(hasValid, validCount),
       ],
     );
   }
@@ -739,13 +747,16 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildKeyboardToolbar() {
     return Container(
+      key: const ValueKey('bulk-entry-keyboard-toolbar'),
       padding: const EdgeInsets.symmetric(
         horizontal: Spacing.space16,
         vertical: Spacing.space8,
       ),
       decoration: BoxDecoration(
         color: context.colors.surfaceElevated,
-        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
+        border: Border(
+          top: BorderSide(color: context.colors.border, width: 1),
+        ),
       ),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end,
@@ -787,6 +798,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildFooter(bool hasValid, int validCount) {
     return Container(
+      key: const ValueKey('bulk-entry-footer'),
       padding: EdgeInsets.fromLTRB(
         Spacing.pagePadding,
         Spacing.space12,

```

---

## Addendum 6 Engineer Report — 2026-07-28 — Task Q (Decouple Field Density From Keyboard State, Unconditional Spacer)

### Feature Slug
bug/bulk-entry-instructions-cutoff-ios

### Branch Confirmed
`git branch --show-current` → `bug/bulk-entry-instructions-cutoff-ios` (existing branch, not created)

### Goal
Fix two purely cosmetic complaints from a real-device screenshot: the paste `TextField` collapses to a cramped single visible line whenever the keyboard is open (`minLines`/`isDense`/`contentPadding` were gated on `showFullPasteUi`, which is `false` any time `keyboardHeight > 0`), and there is no visible gap between the field and "Load Songs" (the trailing spacer was gated on the same condition). Task Q introduces a new derived boolean, `showExpandedPasteField = !_hasLoadedSongs`, that drops the `keyboardHeight` dependency from these three field-density properties while preserving the `_hasLoadedSongs` dependency Task K still needs, and makes the trailing spacer unconditional.

### Architect Tasks Completed (Addendum 6)
- [x] Task Q — In `build()`, immediately after `final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;`, added `final showExpandedPasteField = !_hasLoadedSongs;`. Rewired `minLines` (`showExpandedPasteField ? 3 : 1`), `isDense` (`!showExpandedPasteField`), and the `contentPadding` ternary's condition (same two `EdgeInsets` branches, values unchanged) from `showFullPasteUi` to `showExpandedPasteField`. Changed the trailing `if (showFullPasteUi) const SizedBox(height: Spacing.space8),` to an unconditional `const SizedBox(height: Spacing.space8),`. Did not touch the padding-top ternary, the intro-text/info-box gate, `showFullPasteUi`'s own declaration, `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, or the Task N `Flexible`/`SingleChildScrollView` wrapper.
- [x] Task R — `flutter analyze` run project-wide: 0 errors, no issues found.
- Task S (real-device verification on iOS, Android best-effort, full stop/restart) is explicitly verification-only per the task input — reserved for Tony, not attempted in this session.

### Files Created
- none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`
Result: `No issues found! (ran in 0.8s)` — 0 errors.

### Formatting
`dart format lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` → `Formatted 1 file (0 changed) in 0.00 seconds.` No formatting changes were needed; only this file was targeted.

### Test Results
Not run. No existing test covers `bulk_entry_screen.dart`, and the Architect plan does not require adding one for Task Q.

### Verification
Manual steps performed:
- Confirmed current branch via `git branch --show-current` before making any change.
- Read `ENGINEER.md`, `GUARDRAILS.md`, and the full `ARCHITECT_PLAN.md` (all six addenda) before implementing, per this session's task input.
- Grepped the file for `showFullPasteUi`/`_hasLoadedSongs` and confirmed the current line numbers matched the plan's cited code (six `showFullPasteUi` usages at lines 352, 359, 366, 428, 435, 444, 470) before editing.
- Applied the five edits specified by Task Q, confined to those lines.
- Ran `flutter analyze`: 0 errors, no issues found.
- Ran `dart format` on the single changed file: no changes needed.
- Task S (real-device confirmation that the field shows its expanded height and a visible gap before "Load Songs" while the keyboard is open, with no overflow regression and no change to the already-shipped keyboard-closed/loaded-state behavior) was **not** attempted in this session — reserved for Tony, per the task input.

### Deviations From Architect Plan
None. Task Q was implemented exactly as specified in Addendum 6's Engineer Task Breakdown, confined entirely to the five listed edits in `bulk_entry_screen.dart`. `showFullPasteUi`'s own declaration and its two remaining uses (padding-top, intro-text/info-box gate), `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, and the Task N wrapper were not touched.

### Blockers Encountered
None.

### Ready For QA
Yes, for Task Q (code-level: 0 analyzer errors, change confined to the five authorized edits, no touch to any off-limits region listed in the plan). Task S (real-device confirmation on iOS, Android best-effort, full stop/restart, of the field's expanded height and visible spacer with the keyboard open, no `RenderFlex` overflow at the taller size, and unchanged behavior in the other three `(keyboardHeight, _hasLoadedSongs)` states) is outstanding and must be performed by Tony on a real device before this addendum can be considered fully verified — consistent with this ticket's established practice of not closing a layout change on code-path confidence alone.

### Git Diff (Addendum 6 session — cumulative uncommitted diff against HEAD)

Note: this is the complete `git diff` for the file at the end of this session, reflecting the cumulative uncommitted state of the branch (all of Addenda 1–5's prior work plus this session's Task Q), since none of the prior addenda's work has been committed yet.

```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
index 9f53796..af2cfdf 100644
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -349,172 +349,180 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   @override
   Widget build(BuildContext context) {
     final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
+    final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
+    final showExpandedPasteField = !_hasLoadedSongs;
     final validCount = _validRowCount;
     final hasValid = validCount > 0;
 
-    return Column(
-      children: [
-        Padding(
-          padding: EdgeInsets.fromLTRB(
-            Spacing.space16,
-            keyboardHeight > 0 ? Spacing.space4 : Spacing.space12,
-            Spacing.space16,
-            0,
-          ),
-          child: Column(
-            crossAxisAlignment: CrossAxisAlignment.stretch,
-            children: [
-              if (keyboardHeight == 0) ...[
-                const Text(
-                  'Paste songs from a spreadsheet, then tap Load Songs.',
-                  style: TextStyle(
-                    color: Colors.white,
-                    fontSize: AppFontSizes.body,
-                  ),
-                ),
-                const SizedBox(height: Spacing.space12),
-                Container(
-                  padding: const EdgeInsets.all(Spacing.space8),
-                  decoration: BoxDecoration(
-                    border: Border.all(
-                      color: context.colors.textMuted.withValues(alpha: 0.5),
+    final pasteUiBlock = Padding(
+      padding: EdgeInsets.fromLTRB(
+        Spacing.space16,
+        showFullPasteUi ? Spacing.space12 : Spacing.space4,
+        Spacing.space16,
+        0,
+      ),
+      child: Column(
+        crossAxisAlignment: CrossAxisAlignment.stretch,
+        children: [
+          if (showFullPasteUi) ...[
+            const Text(
+              'Paste songs from a spreadsheet, then tap Load Songs.',
+              style: TextStyle(
+                color: Colors.white,
+                fontSize: AppFontSizes.body,
+              ),
+            ),
+            const SizedBox(height: Spacing.space12),
+            Container(
+              padding: const EdgeInsets.all(Spacing.space8),
+              child: Column(
+                crossAxisAlignment: CrossAxisAlignment.stretch,
+                children: [
+                  const Text(
+                    'Column order:',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.subhead,
                     ),
-                    borderRadius: BorderRadius.circular(8),
                   ),
-                  child: Column(
-                    crossAxisAlignment: CrossAxisAlignment.stretch,
-                    children: [
-                      const Text(
-                        'Column order:',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Artist, Song, BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      Text(
-                        '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
-                        style: TextStyle(
-                          color: context.colors.textSecondary,
-                          fontSize: AppFontSizes.subhead,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Required columns: Artist, Song',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                      const SizedBox(height: Spacing.space4),
-                      const Text(
-                        'Optional columns: BPM, Tuning, Key',
-                        style: TextStyle(
-                          color: Colors.white,
-                          fontSize: AppFontSizes.body,
-                        ),
-                      ),
-                    ],
-                  ),
-                ),
-                const SizedBox(height: Spacing.space16),
-              ],
-              TextField(
-                controller: _csvController,
-                autofocus: true,
-                maxLines: 5,
-                minLines: keyboardHeight > 0 ? 1 : 3,
-                style: TextStyle(
-                  fontSize: AppFontSizes.caption,
-                  color: context.colors.textPrimary,
-                  fontFamily: 'monospace',
-                ),
-                decoration: InputDecoration(
-                  isDense: keyboardHeight > 0,
-                  hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
-                  hintStyle: TextStyle(
-                    fontSize: AppFontSizes.caption,
-                    color: context.colors.textMuted.withValues(alpha: 0.5),
-                    fontFamily: 'monospace',
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Artist, Song, BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
+                    ),
                   ),
-                  filled: true,
-                  fillColor: Colors.white.withValues(alpha: 0.04),
-                  contentPadding: keyboardHeight > 0
-                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0)
-                      : const EdgeInsets.all(12),
-                  border: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  Text(
+                    '(Led Zeppelin, Rock and Roll, 172, Standard, A Major)',
+                    style: TextStyle(
+                      color: context.colors.textSecondary,
+                      fontSize: AppFontSizes.subhead,
                     ),
                   ),
-                  enabledBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: BorderSide(
-                      color: context.colors.border,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Required columns: Artist, Song',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
-                  focusedBorder: OutlineInputBorder(
-                    borderRadius: BorderRadius.circular(8),
-                    borderSide: const BorderSide(
-                      color: AppColors.primary,
-                      width: 2,
+                  const SizedBox(height: Spacing.space4),
+                  const Text(
+                    'Optional columns: BPM, Tuning, Key',
+                    style: TextStyle(
+                      color: Colors.white,
+                      fontSize: AppFontSizes.body,
                     ),
                   ),
+                ],
+              ),
+            ),
+            const SizedBox(height: Spacing.space16),
+          ],
+          TextField(
+            key: const ValueKey('bulk-entry-csv-field'),
+            controller: _csvController,
+            maxLines: 5,
+            minLines: showExpandedPasteField ? 3 : 1,
+            style: TextStyle(
+              fontSize: AppFontSizes.caption,
+              color: context.colors.textPrimary,
+              fontFamily: 'monospace',
+            ),
+            decoration: InputDecoration(
+              isDense: !showExpandedPasteField,
+              hintText: 'Column order: Artist, Song, BPM, Tuning, Key',
+              hintStyle: TextStyle(
+                fontSize: AppFontSizes.caption,
+                color: context.colors.textMuted.withValues(alpha: 0.5),
+                fontFamily: 'monospace',
+              ),
+              filled: true,
+              fillColor: Colors.white.withValues(alpha: 0.08),
+              contentPadding: showExpandedPasteField
+                  ? const EdgeInsets.all(12)
+                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
+              border: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),
-              SizedBox(
-                height: 40,
-                child: GestureDetector(
-                  onTap: _isLoadingSongs ? null : _handleCsvIngestion,
-                  child: Container(
-                    decoration: BoxDecoration(
-                      color: _isLoadingSongs
-                          ? AppColors.primary.withValues(alpha: 0.4)
-                          : AppColors.primary,
-                      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
-                    ),
-                    alignment: Alignment.center,
-                    child: _isLoadingSongs
-                        ? const SizedBox(
-                            width: 18,
-                            height: 18,
-                            child: CircularProgressIndicator(
-                              strokeWidth: 2,
-                              color: Colors.white,
-                            ),
-                          )
-                        : Text(
-                            'Load Songs',
-                            style: AppTextStyles.button.copyWith(
-                              color: Colors.white,
-                              fontSize: AppFontSizes.subhead,
-                            ),
-                          ),
-                  ),
+              enabledBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: BorderSide(
+                  color: context.colors.border,
+                  width: 1.5,
                 ),
               ),
-              if (_ingestionSummary != null) ...[
-                const SizedBox(height: Spacing.space8),
-                Text(
-                  _ingestionSummary!,
-                  style: AppTextStyles.body.copyWith(
-                    color: context.colors.textSecondary,
-                    fontSize: AppFontSizes.caption,
-                  ),
+              focusedBorder: OutlineInputBorder(
+                borderRadius: BorderRadius.circular(8),
+                borderSide: const BorderSide(
+                  color: AppColors.primary,
+                  width: 2,
+                ),
+              ),
+            ),
+          ),
+          const SizedBox(height: Spacing.space8),
+          SizedBox(
+            height: 40,
+            child: GestureDetector(
+              onTap: _isLoadingSongs ? null : _handleCsvIngestion,
+              child: Container(
+                decoration: BoxDecoration(
+                  color: _isLoadingSongs
+                      ? AppColors.primary.withValues(alpha: 0.4)
+                      : AppColors.primary,
+                  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
                 ),
-              ],
-            ],
+                alignment: Alignment.center,
+                child: _isLoadingSongs
+                    ? const SizedBox(
+                        width: 18,
+                        height: 18,
+                        child: CircularProgressIndicator(
+                          strokeWidth: 2,
+                          color: Colors.white,
+                        ),
+                      )
+                    : Text(
+                        'Load Songs',
+                        style: AppTextStyles.button.copyWith(
+                          color: Colors.white,
+                          fontSize: AppFontSizes.subhead,
+                        ),
+                      ),
+              ),
+            ),
+          ),
+          if (_ingestionSummary != null) ...[
+            const SizedBox(height: Spacing.space8),
+            Text(
+              _ingestionSummary!,
+              style: AppTextStyles.body.copyWith(
+                color: context.colors.textSecondary,
+                fontSize: AppFontSizes.caption,
+              ),
+            ),
+          ],
+        ],
+      ),
+    );
+
+    return Column(
+      children: [
+        Flexible(
+          flex: keyboardHeight > 0 ? 1 : 0,
+          child: SingleChildScrollView(
+            physics: keyboardHeight > 0
+                ? const ClampingScrollPhysics()
+                : const NeverScrollableScrollPhysics(),
+            child: pasteUiBlock,
           ),
         ),
         if (_hasLoadedSongs) ...[
@@ -537,7 +545,8 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
         ] else
           const Expanded(child: SizedBox.shrink()),
         if (keyboardHeight > 0) _buildKeyboardToolbar(),
-        _buildFooter(hasValid, validCount),
+        if (_hasLoadedSongs || keyboardHeight == 0)
+          _buildFooter(hasValid, validCount),
       ],
     );
   }
@@ -739,13 +748,16 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildKeyboardToolbar() {
     return Container(
+      key: const ValueKey('bulk-entry-keyboard-toolbar'),
       padding: const EdgeInsets.symmetric(
         horizontal: Spacing.space16,
         vertical: Spacing.space8,
       ),
       decoration: BoxDecoration(
         color: context.colors.surfaceElevated,
-        border: Border(top: BorderSide(color: context.colors.border, width: 1)),
+        border: Border(
+          top: BorderSide(color: context.colors.border, width: 1),
+        ),
       ),
       child: Row(
         mainAxisAlignment: MainAxisAlignment.end,
@@ -787,6 +799,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
 
   Widget _buildFooter(bool hasValid, int validCount) {
     return Container(
+      key: const ValueKey('bulk-entry-footer'),
       padding: EdgeInsets.fromLTRB(
         Spacing.pagePadding,
         Spacing.space12,

```

---

## Addendum 7 Engineer Report — 2026-07-28 — Tasks T–W (Loaded-Songs Table Column Widths)

### Feature Slug
`bug/bulk-entry-instructions-cutoff-ios`

### Goal
Convert the loaded-songs table's BPM/Tuning/Key columns from flex-based `Expanded` widths to a single shared fixed width, while widening Artist/Song to equally-weighted `Expanded` columns, so the table spans its full width with Artist/Song as the widest columns and BPM/Tuning/Key sized only to fit their header text — per Addendum 7 of `ARCHITECT_PLAN.md`.

### Architect Tasks Completed
- [x] Task T — Replaced `_kFlexBpm`/`_kFlexTuning`/`_kFlexKey` with `const double _kNarrowColumnWidth = 68.0;`; changed `_kFlexArtist`/`_kFlexSong` to `1` each; left `_kDeleteWidth`/`_kCellHeight` untouched.
- [x] Task U — Changed `_headerCell()` to `_headerCell(String label, {int? flex, double? width})` with an assert enforcing exactly one is provided; extracted the existing `Padding`/`Text` content unchanged into a local `content`, returning `Expanded`/`SizedBox` accordingly; updated all five `_buildColumnHeaders()` call sites (Artist/Song → `flex:`, BPM/Tuning/Key → `width: _kNarrowColumnWidth`).
- [x] Task V — Changed `_tableCell()` to accept `{int? flex, double? width}` with the same assert convention; extracted the existing `SizedBox(height: _kCellHeight, child: _TableTextField(...))` unchanged into a local `content`; updated all five `_buildRow()` call sites the same way as Task U. `controller`, `focusNode`, `hint`, `rowIndex`, `keyboardType`, `inputFormatters`, and `textCapitalization` were left unchanged at every call site. `_TableTextField` itself was not touched.
- [x] Task W — `flutter analyze` run, 0 errors, 0 warnings.
- [ ] Task X — Verification-only, on-device confirmation of `_kNarrowColumnWidth = 68.0` not wrapping "Tuning" and other on-device checks. Not performed in this session (no running device/simulator available to this Engineer); left for Tony per the plan's own framing of Task X.

### Files Created
none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (project-wide, not just the changed file)

### Test Results
Not run — not required by the Architect plan for this addendum, and no automated test covers the changed table-layout code.

### Verification
Manual steps performed:
- Read the current file state before editing to confirm line numbers/content matched the plan's description (constants at lines 99–105, `_buildColumnHeaders()`/`_headerCell()` at 558–595, `_buildRow()`/`_tableCell()` at 601–706).
- Confirmed via `flutter analyze` (both scoped to the file and project-wide) that the new `{flex, width}` signatures and all ten call sites (five in `_buildColumnHeaders()`, five in `_buildRow()`) type-check with 0 errors.
- Ran `dart format` on the changed file — no changes needed (already correctly formatted).
- Did not perform on-device/simulator verification (Task X) — no running device available in this session.

### Deviations From Architect Plan
None.

### Blockers Encountered
None.

### Ready For QA
Yes, with the caveat that Task X (on-device confirmation that `_kNarrowColumnWidth = 68.0` doesn't wrap "Tuning" and that columns render/align as expected) is outstanding and requires a real device or simulator, per the plan's own framing of Task X as verification-only.

### Git Diff (Tasks T–V)
```diff
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -96,11 +96,9 @@ class _RowData {
 const int _kInitialRows = 5;
 const int _kMaxRows = 500;
 
-const int _kFlexArtist = 3;
-const int _kFlexSong = 3;
-const int _kFlexBpm = 2;
-const int _kFlexTuning = 2;
-const int _kFlexKey = 2;
+const int _kFlexArtist = 1;
+const int _kFlexSong = 1;
+const double _kNarrowColumnWidth = 68.0;
 const double _kDeleteWidth = 36;
 const double _kCellHeight = 42;
 
@@ -565,27 +563,37 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
       ),
       child: Row(
         children: [
-          _headerCell('Artist', _kFlexArtist),
-          _headerCell('Song', _kFlexSong),
-          _headerCell('BPM', _kFlexBpm),
-          _headerCell('Tuning', _kFlexTuning),
-          _headerCell('Key', _kFlexKey),
+          _headerCell('Artist', flex: _kFlexArtist),
+          _headerCell('Song', flex: _kFlexSong),
+          _headerCell('BPM', width: _kNarrowColumnWidth),
+          _headerCell('Tuning', width: _kNarrowColumnWidth),
+          _headerCell('Key', width: _kNarrowColumnWidth),
           const SizedBox(width: _kDeleteWidth),
         ],
       ),
     );
   }
 
-  Widget _headerCell(String label, int flex) {
-    return Expanded(
-      flex: flex,
-      child: Padding(
-        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
-        child: Text(
-          label,
-          style: AppTextStyles.label.copyWith(
-            color: context.colors.textSecondary,
-            fontSize: AppFontSizes.caption,
-            fontWeight: FontWeight.w600,
-            letterSpacing: 0.5,
-          ),
+  Widget _headerCell(String label, {int? flex, double? width}) {
+    assert(
+      (flex == null) != (width == null),
+      'Provide exactly one of flex or width',
+    );
+    final content = Padding(
+      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
+      child: Text(
+        label,
+        style: AppTextStyles.label.copyWith(
+          color: context.colors.textSecondary,
+          fontSize: AppFontSizes.caption,
+          fontWeight: FontWeight.w600,
+          letterSpacing: 0.5,
         ),
       ),
     );
+    return flex != null
+        ? Expanded(flex: flex, child: content)
+        : SizedBox(width: width, child: content);
   }
 
   // -------------------------------------------------------
@@ -623,7 +634,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           _tableCell(
             controller: row.bpm,
             focusNode: row.bpmFocus,
-            flex: _kFlexBpm,
+            width: _kNarrowColumnWidth,
             hint: '-',
             rowIndex: index,
             keyboardType: TextInputType.number,
@@ -632,7 +643,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           _tableCell(
             controller: row.tuning,
             focusNode: row.tuningFocus,
-            flex: _kFlexTuning,
+            width: _kNarrowColumnWidth,
             hint: '-',
             rowIndex: index,
             textCapitalization: TextCapitalization.words,
@@ -640,7 +651,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           _tableCell(
             controller: row.key,
             focusNode: row.keyFocus,
-            flex: _kFlexKey,
+            width: _kNarrowColumnWidth,
             hint: '-',
             rowIndex: index,
           ),
@@ -673,27 +684,32 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   Widget _tableCell({
     required TextEditingController controller,
     required FocusNode focusNode,
-    required int flex,
+    int? flex,
+    double? width,
     required String hint,
     required int rowIndex,
     TextInputType keyboardType = TextInputType.text,
     List<TextInputFormatter>? inputFormatters,
     TextCapitalization textCapitalization = TextCapitalization.none,
   }) {
-    return Expanded(
-      flex: flex,
-      child: SizedBox(
-        height: _kCellHeight,
-        child: _TableTextField(
-          controller: controller,
-          focusNode: focusNode,
-          hint: hint,
-          keyboardType: keyboardType,
-          inputFormatters: inputFormatters,
-          textCapitalization: textCapitalization,
-        ),
+    assert(
+      (flex == null) != (width == null),
+      'Provide exactly one of flex or width',
+    );
+    final content = SizedBox(
+      height: _kCellHeight,
+      child: _TableTextField(
+        controller: controller,
+        focusNode: focusNode,
+        hint: hint,
+        keyboardType: keyboardType,
+        inputFormatters: inputFormatters,
+        textCapitalization: textCapitalization,
       ),
     );
+    return flex != null
+        ? Expanded(flex: flex, child: content)
+        : SizedBox(width: width, child: content);
   }
 
   // -------------------------------------------------------
```

## Correction — 2026-07-28 — Column Widths Changed to Explicit Percentages Per Tony's Direct Instruction

### Context
Immediately after Addendum 7's implementation (fixed `_kNarrowColumnWidth = 68.0` for BPM/Tuning/Key, equal 1:1 flex for Artist/Song) landed, Tony gave a direct correction: the loaded-songs table's columns should be **Artist 25%, Song 25%, BPM 15%, Tuning 20%, Key 15%** of the table width — not the header-text-fit fixed-width scheme Addendum 7's design decision had chosen. This supersedes Addendum 7's `_kNarrowColumnWidth` approach; it is not a change to the Architect plan document, but a direct instruction from Tony (the product owner) taking priority over Addendum 7's own stated design judgment call, per this ticket's established pattern of Tony reviewing on-device and issuing corrections when the plan's font-metric/aesthetic reasoning doesn't match his actual intent (see Addendum 6's precedent).

### Implementation
Fixed-pixel widths do not scale proportionally with screen/table width, so a literal percentage requirement is implemented via `Expanded` flex ratios (which do scale with available width) rather than fixed `SizedBox` widths. The five requested percentages (25/25/15/20/15, summing to 100%) reduce exactly to the integer flex ratio **5:5:3:4:3** (sum 20), so each column's share of the row's flexible space is exactly its requested percentage:

```dart
const int _kFlexArtist = 5; // 25%
const int _kFlexSong = 5; // 25%
const int _kFlexBpm = 3; // 15%
const int _kFlexTuning = 4; // 20%
const int _kFlexKey = 3; // 15%
```

`_kNarrowColumnWidth` was removed. Since every column is flex-based again, the `{int? flex, double? width}` dual-parameter design added to `_headerCell()`/`_tableCell()` in Addendum 7 (Tasks U/V) had no remaining caller passing `width:`, so both methods were reverted to their original plain `flex`-only signatures (`_headerCell(String label, int flex)` / `_tableCell({..., required int flex, ...})`) to avoid leaving unused dead code paths. All ten call sites (five in `_buildColumnHeaders()`, five in `_buildRow()`) were updated to pass the new flex constants by name. No other parameter (`controller`, `focusNode`, `hint`, `rowIndex`, `keyboardType`, `inputFormatters`, `textCapitalization`) changed at any call site. `_TableTextField` was not touched.

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (project-wide)

### Test Results
Not run — no automated test covers this table-layout code.

### Verification
- Confirmed via `flutter analyze` (project-wide) that the reverted signatures and all ten updated call sites type-check with 0 errors/warnings.
- Ran `dart format` on the changed file — no changes needed.
- Did not perform on-device verification of the resulting on-screen percentages — no running device/simulator available in this session; left for Tony, consistent with Addendum 7's Task X framing.

### Deviations From Architect Plan
Addendum 7's specific column-width scheme (`_kNarrowColumnWidth = 68.0` fixed width for BPM/Tuning/Key, 1:1 flex for Artist/Song) is superseded by this correction, per Tony's direct instruction for exact 25/25/15/20/15 percentage widths. The underlying mechanism Addendum 7 established — headers and rows sharing one set of constants via matching call-site conventions, so alignment can't drift — is preserved; only the constant values (and, as a result, the now-unneeded `flex`/`width` dual-parameter signatures) changed.

### Blockers Encountered
None.

### Ready For QA
Yes, with the same on-device confirmation caveat as Addendum 7's Task X (confirm the five columns visually render at the intended proportions and that BPM/Tuning/Key header text doesn't wrap at their new, narrower-in-some-cases flex-based widths on the smallest supported screen).

## Investigation — 2026-07-28 — "Columns Do Not Reach Full Width" Report, Resolved as Not a Bug

### Context
After the percentage-based flex correction (5:5:3:4:3 → 25/25/15/20/15), Tony reported the loaded-songs table's columns still did not reach the full width of the table — specifically, a visible blank gap after the "Key" column. Code review (Row with `mainAxisSize.max`, five `Expanded` columns absorbing 100% of leftover space after one fixed-width `SizedBox`) gave no structural explanation for a gap, and a full app quit/relaunch on a real device (ruling out stale build/hot-reload staleness) did not change the symptom — consistent with this ticket's repeated lesson (Addenda 1–3) that code-path reasoning alone is not sufficient here.

### Diagnostic Approach
Rather than guess another fix, temporary `// TEMP-DEBUG` instrumentation was added (matching the pattern already established in this ticket's Addendum 2 Task B): each of the five data columns and the trailing delete-icon column were wrapped in a `ColoredBox` with a distinct, high-visibility debug color (Artist=red, Song=green, BPM=blue, Tuning=yellow, Key=purple, delete-column=orange), and the row's background was forced to a constant visible gray (superseding the existing isEven-based transparent/faint-white alternation, which was hiding the row's true bounding box on the single test row, index 0, which is `isEven`). Tony rebuilt (full stop/relaunch) and provided a screenshot.

### Finding
The screenshot conclusively showed all six colored blocks tiling edge-to-edge across the full width of the table, with **no unaccounted blank space anywhere in the row**. Measuring the colored blocks against the screenshot confirmed the five data columns split the available width at almost exactly 25% / 25% / 15% / 20% / 15% (Artist/Song/BPM/Tuning/Key) — matching the intended design precisely. The visible "gap" Tony had been seeing was the orange block itself: the **reserved 36pt delete-icon column** (`_kDeleteWidth`), which hosts the "✕" remove-row icon on rows 2 and later but renders as `SizedBox.shrink()` (i.e., no visible icon) when there is only one row in the table (`_rows.length > 1` is false). With no visual marker and no adjacent contrast (previously fully transparent for an even-indexed row), this reserved-but-empty 36pt gutter was being perceived as a much larger unaccounted gap than it actually is.

**Conclusion: not a bug.** The table already spans its full available width, and the five data columns already split it at the requested 25/25/15/20/15 ratio. No code change was made as a result of this investigation — Tony was asked whether the delete-icon gutter should collapse to zero width specifically when only one row exists (letting the five columns expand to consume that space too), as a follow-up design question distinct from this bug report.

### Files Modified
None net — the file's committed state (percentage-based flex from the prior "Correction" entry) is unchanged. Temporary `TEMP-DEBUG` `ColoredBox`/debug-color instrumentation was added and then fully stripped in this same session; confirmed via `grep -n "TEMP-DEBUG\|debugColor\|ColoredBox"` returning no matches.

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (both with instrumentation in place and after it was stripped)

### Verification
- Added temporary debug coloring, confirmed `flutter analyze` clean and `dart format` no-op with it in place.
- Tony rebuilt (full stop/relaunch) on a real device and provided a screenshot showing all six columns tiling with no gap, at the expected proportions.
- Stripped all temporary instrumentation; re-ran `flutter analyze` (0 errors/warnings) and `dart format` (no changes) to confirm the file is back to its clean, percentage-based-flex state.

### Deviations From Architect Plan
None — no functional code change resulted from this investigation.

### Blockers Encountered
None.

### Ready For QA
Yes — the percentage-based column widths (25/25/15/20/15) implemented in the prior "Correction" entry are confirmed correct on a real device via this investigation.

## Correction 2 — 2026-07-28 — Delete-Icon Gutter Narrowed, Table Extends Edge-to-Edge

### Context
Following the "not a bug" investigation above (which confirmed the table already fills its available width, and the perceived gap was the reserved-but-invisible 36pt delete-icon gutter), Tony gave a direct follow-up instruction: narrow that gutter from 36pt to 16px, and additionally remove the loaded-songs table's own horizontal padding entirely so the header row and data rows extend all the way to the left and right edges of the Bulk Entry overlay/modal card itself (previously inset by `Spacing.space16` on each side). The delete "✕" icon is kept, now sitting flush against the right edge of the overlay as a result of the padding removal.

### Implementation
- `_kDeleteWidth` changed from `36` to `16` (module-level constant, lines 99–105) — used identically by both `_buildColumnHeaders()`'s trailing `SizedBox` and `_buildRow()`'s trailing `SizedBox`/delete-icon column, so header and row gutters stay in lockstep exactly as before.
- Removed the `padding: const EdgeInsets.symmetric(horizontal: Spacing.space16)` line from both `_buildColumnHeaders()`'s and `_buildRow()`'s outer `Container`s. No ancestor between `BulkEntryScreen`'s outer `Column` and the Bulk Entry overlay's card (`add_to_setlist_overlay.dart`) applies any horizontal padding of its own around this section (confirmed by re-reading `_buildContent()` in that file — `BulkEntryScreen` is placed directly, no wrapping `Padding`), so removing this Container-level padding makes the header row and every data row span the full width of the overlay card, left edge to right edge, with no gap on either side.
- The delete icon itself (`Icon(AppIcons.close, size: 16, ...)`) and its `GestureDetector`/`Center` wrapping were not touched — with the gutter now exactly `16` wide (matching the icon's own `size: 16`) and no more surrounding row padding, the icon renders flush against the table's right edge, which is now also the overlay's right edge.
- Per-cell internal padding (`_headerCell`'s `Padding(EdgeInsets.symmetric(horizontal: 6, vertical: 10))` and `_TableTextField`'s `contentPadding`) was left untouched — Tony's instruction was about the table's outer inset relative to the overlay, not the small breathing room between adjacent column labels/values.
- The paste-UI block above the table (intro text, column-order info box, paste `TextField`, "Load Songs" button) still uses its own separate `Spacing.space16` horizontal padding and was not touched — this request was specifically about the loaded-songs table.

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (project-wide)

### Test Results
Not run — no automated test covers this table-layout code.

### Verification
- Confirmed via `flutter analyze` (project-wide) that removing the two `padding:` properties and changing `_kDeleteWidth` type-checks with 0 errors/warnings.
- Ran `dart format` — no changes needed.
- Did not perform on-device verification of the edge-to-edge table and narrowed/repositioned delete icon in this session — left for Tony to confirm on a real device, consistent with this ticket's established practice of real-device confirmation before considering a cosmetic change closed.

### Deviations From Architect Plan
None beyond what was already logged in the prior "Correction" entry (percentage-based column widths superseding Addendum 7's fixed-`_kNarrowColumnWidth` design) — this entry is a further direct-instruction refinement of that same table, not a new deviation category.

### Blockers Encountered
None.

### Ready For QA
Yes, pending Tony's on-device confirmation that the table now spans edge-to-edge and the delete icon sits correctly flush against the right edge without being clipped or too small a tap target.

## Addendum 8 — 2026-07-28 — On-Screen Keyboard Renders in Light Mode on Android (App-Wide, Not Bulk-Entry-Scoped)

### Context
Per Architect Addendum 8, this is a distinct, app-wide theming concern, not a `bulk_entry_screen.dart`-scoped bug like Addenda 1–7. Task Y only: force Android's native `Configuration.uiMode` night flag on unconditionally in `MainActivity.kt` so the on-screen keyboard (IME) renders dark regardless of the device's system-wide dark/light setting. iOS requires no change (already resolves dark via `Theme.of(context).brightness`, confirmed by the Architect via direct Flutter SDK source read).

### Architect Tasks Completed
- [x] Task Y — Force Android's native `uiMode` to dark, unconditionally, via `attachBaseContext()` override in `MainActivity.kt`.
- [ ] Task Z — real-device verification (both platforms, all theme-state combinations) — not performed in this session; no device/emulator available. Left for Tony/QA per the plan's established practice.

### Files Modified
- `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`

### Implementation
Added imports `android.content.Context` and `android.content.res.Configuration`, and overrode `attachBaseContext(Context)` exactly as specified in the Architect plan: build a new `Configuration` copying `newBase.resources.configuration`, clear the existing night-mode bits via `UI_MODE_NIGHT_MASK.inv()` and OR in `UI_MODE_NIGHT_YES`, then call `super.attachBaseContext(newBase.createConfigurationContext(configuration))`. No `MethodChannel` added. `AndroidManifest.xml`, `styles.xml` (either variant), and all Dart files left untouched. `ios/Runner/Info.plist` and `ios/Runner/AppDelegate.swift` left untouched.

### Git Diff
```diff
diff --git a/android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt b/android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt
index 4d1cc2c..b68315a 100644
--- a/android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt
+++ b/android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt
@@ -1,5 +1,14 @@
 package com.bandroadie.app
 
+import android.content.Context
+import android.content.res.Configuration
 import io.flutter.embedding.android.FlutterActivity
 
-class MainActivity : FlutterActivity()
+class MainActivity : FlutterActivity() {
+    override fun attachBaseContext(newBase: Context) {
+        val configuration = Configuration(newBase.resources.configuration)
+        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
+            Configuration.UI_MODE_NIGHT_YES
+        super.attachBaseContext(newBase.createConfigurationContext(configuration))
+    }
+}
```

### Android Build Result
Command: `flutter build apk --debug`
Result: **Success** — `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (Gradle `assembleDebug` completed in 19.5s). One pre-existing, unrelated warning emitted (Flutter's Kotlin-version-support notice for KGP 2.1.0 — present before this change, unrelated to this file).

### Analyzer Results
Command: `flutter analyze` (project-wide)
Result: 0 errors, 0 warnings — "No issues found!" (this Kotlin-only change is not itself analyzable by `flutter analyze`; run to confirm no Dart regression, per plan instructions).

### Test Results
Not run — no automated test covers native Android `Configuration`/IME behavior; this is real-device-only per the Architect plan's Task Z / Verification Plan Addendum.

### Verification
Manual steps performed:
- Confirmed current branch is `bug/bulk-entry-instructions-cutoff-ios` before starting.
- Read `MainActivity.kt` before editing; confirmed it was the bare, unmodified `flutter create` template (`class MainActivity : FlutterActivity()`, no overrides) as the plan's Investigation section described.
- Applied the exact override specified in the Architect plan's Proposed Solution, verbatim.
- Ran `flutter build apk --debug` — compiled and linked cleanly, APK produced.
- Ran `flutter analyze` project-wide — 0 issues.
- Did not perform on-device IME verification (Task Z, PRE-DEPLOY TESTS 40–45) — no physical Android/iOS device available in this session. Left for Tony/QA, consistent with this ticket's established practice of real-device confirmation before closing.

### Deviations From Architect Plan
None. Implementation matches the Proposed Solution code block verbatim; no unlisted file touched.

### Blockers Encountered
None.

### Ready For QA
Yes for Task Y (code change, build, and analyzer verification complete). Task Z (real-device confirmation across both platforms and all theme-state combinations, per Architect Addendum 8) is outstanding and must be completed before this addendum is considered fully closed.

## Addendum 9 Engineer Report — 2026-07-28 — Tasks R–S (Re-Focusing the Paste Field After Songs Are Loaded Should Re-Expand the View)

### Feature Slug
`bug/bulk-entry-instructions-cutoff-ios`

### Goal
Track whether the CSV paste field has focus, and widen `showExpandedPasteField` (plus the table- and footer-visibility conditions that key off it) so that re-focusing the paste field after songs are already loaded re-expands the field to full height and hides the table/footer, matching the pre-load "first tap" treatment — per Addendum 9 of `ARCHITECT_PLAN.md`.

### Architect Tasks Completed
- [x] Task R — Added `_csvFocusNode` (`FocusNode`) and `_isPasteFieldFocused` (`bool`) fields to `_BulkEntryScreenState`; registered `_handleCsvFocusChange` via `_csvFocusNode.addListener(...)` in `initState()`; added the `_handleCsvFocusChange()` method with a `mounted` guard; disposed `_csvFocusNode` in `dispose()`; wired `focusNode: _csvFocusNode` onto the existing CSV `TextField` as an additional named argument, with `key`, `controller`, `maxLines`, `minLines`, `style`, and `decoration` all left unchanged and no wrapping widget introduced.
- [x] Task S — Widened `showExpandedPasteField` to `!_hasLoadedSongs || _isPasteFieldFocused`; changed the table-visibility condition to `_hasLoadedSongs && !showExpandedPasteField`; changed the footer-visibility condition to `(_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0`; left `showFullPasteUi`, its two use sites, `_buildKeyboardToolbar()`'s own condition, and Task N's `Flexible`/`SingleChildScrollView` wrapper untouched.
- [x] Task T — `flutter analyze` run (both scoped to the file and project-wide), 0 errors, 0 warnings.
- [ ] Task U — Verification-only, real-device tap-cycle confirmation (repeated focus/blur on the paste field with songs already loaded). Not performed in this session (no running device/simulator available to this Engineer); left for Tony per the plan's own framing of Task U as verification-only.

### Files Created
none

### Files Modified
- `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`

### Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings (project-wide, not just the changed file)

### Test Results
Not run — not required by the Architect plan for this addendum, and no automated test covers the changed focus/layout-visibility code.

### Verification
Manual steps performed:
- Confirmed current branch is `bug/bulk-entry-instructions-cutoff-ios` before starting (no new branch created).
- Read the current file state before editing to confirm line numbers/content matched the plan's description of the post-Addendum-8 file.
- Applied Task R and Task S exactly as specified, touching only the listed lines.
- Ran `flutter analyze` scoped to the file, then project-wide — 0 issues both times.
- Ran `dart format` on the changed file — no changes needed (already correctly formatted).
- Did not perform on-device verification (Task U, PRE-DEPLOY TESTS 46–52) — no running device available in this session. Left for Tony, consistent with this ticket's established practice of real-device confirmation before closing.

### Deviations From Architect Plan
None. `showFullPasteUi`, its two use sites, `_buildKeyboardToolbar()`'s condition, and Task N's wrapper were left untouched as specified; no unlisted file touched.

### Blockers Encountered
None.

### Ready For QA
Yes for Tasks R–T (code change and analyzer verification complete). Task U (real, interactive, repeated tap-cycle confirmation on a device with songs already loaded, per Architect Addendum 9) is outstanding and must be completed before this addendum is considered fully closed.

### Git Diff (Tasks R–S)
```diff
diff --git a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
--- a/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
+++ b/lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart
@@ -129,11 +129,13 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   bool _isSubmitting = false;
   final ScrollController _scrollController = ScrollController();
   final TextEditingController _csvController = TextEditingController();
+  final FocusNode _csvFocusNode = FocusNode();
 
   int _focusedRowIndex = 0;
   bool _isLoadingSongs = false;
   String? _ingestionSummary;
   bool _hasLoadedSongs = false;
+  bool _isPasteFieldFocused = false;
 
   // -------------------------------------------------------
   // Lifecycle
@@ -145,6 +147,14 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     for (var i = 0; i < _kInitialRows; i++) {
       _rows.add(_createRow());
     }
+    _csvFocusNode.addListener(_handleCsvFocusChange);
+  }
+
+  void _handleCsvFocusChange() {
+    if (!mounted) return;
+    setState(() {
+      _isPasteFieldFocused = _csvFocusNode.hasFocus;
+    });
   }
 
   @override
@@ -154,6 +164,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
     }
     _scrollController.dispose();
     _csvController.dispose();
+    _csvFocusNode.dispose();
     super.dispose();
   }
 
@@ -350,7 +361,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
   Widget build(BuildContext context) {
     final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
     final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
-    final showExpandedPasteField = !_hasLoadedSongs;
+    final showExpandedPasteField = !_hasLoadedSongs || _isPasteFieldFocused;
     final validCount = _validRowCount;
     final hasValid = validCount > 0;
 
@@ -425,6 +436,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
           TextField(
             key: const ValueKey('bulk-entry-csv-field'),
             controller: _csvController,
+            focusNode: _csvFocusNode,
             maxLines: 5,
             minLines: showExpandedPasteField ? 3 : 1,
             style: TextStyle(
@@ -525,7 +537,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
             child: pasteUiBlock,
           ),
         ),
-        if (_hasLoadedSongs) ...[
+        if (_hasLoadedSongs && !showExpandedPasteField) ...[
           const SizedBox(height: Spacing.space12),
           _buildColumnHeaders(),
           Expanded(
@@ -545,7 +557,7 @@ class _BulkEntryScreenState extends State<BulkEntryScreen> {
         ] else
           const Expanded(child: SizedBox.shrink()),
         if (keyboardHeight > 0) _buildKeyboardToolbar(),
-        if (_hasLoadedSongs || keyboardHeight == 0)
+        if ((_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0)
           _buildFooter(hasValid, validCount),
       ],
     );
```
