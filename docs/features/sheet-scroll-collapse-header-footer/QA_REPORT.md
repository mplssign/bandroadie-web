# QA REPORT — sheet-scroll-collapse-header-footer

## Feature Slug
`sheet-scroll-collapse-header-footer`

## Feature Title
Collapse sheet header on scroll-down and hide footer during scroll for maximum vertical space

## Cycle Number
1

## Final Verdict
**APPROVED**

---

## Validation Summary

| Check | Result |
|---|---|
| Branch | `feature/sheet-scroll-collapse-header-footer` ✅ |
| Git tree | Uncommitted working-tree changes, clean otherwise ✅ |
| Slugs match (Plan / Report / Branch) | ✅ |
| Scope (22 files) | ✅ exactly 22 — 2 created + 20 modified |
| Off-limits files untouched | ✅ 7/7 confirmed |
| `flutter analyze` (changed files) | ✅ 0 errors · 0 warnings · 0 infos |
| `flutter test` (full suite) | ✅ 206/206 pass |
| Scaffold test cases (11) | ✅ 11/11 present and passing |
| Wrapper preservation (PopScope) | ✅ 3/3 |
| Wrapper preservation (entrance AnimatedBuilder) | ✅ 4/4 |
| Wrapper preservation (keyboard viewInsets outer) | ✅ 8/8 |
| High-risk spot-checks (5) | ✅ all pass |
| Deviations acceptable | ✅ 5/5 |
| Debug artifacts (debugPrint / TODO / FIXME) | ✅ none |
| Database impact | N/A |

---

## Architect Scope Review

### Files Off-Limits — confirmed no diff:
- `lib/components/ui/sheet_footer.dart` ✅
- `lib/components/ui/app_bottom_sheet.dart` ✅
- `lib/features/setlists/widgets/key_picker_bottom_sheet.dart` ✅
- `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart` ✅
- `lib/features/setlists/widgets/print_options_bottom_sheet.dart` ✅
- `lib/main.dart` ✅
- `pubspec.yaml` ✅
- `supabase/` (unmodified) ✅

`calendar_subscription_dialog`, `set_break_creator`, `custom_tuning_modal`, `role_management_sheet` also confirmed untouched.

### File counts:
`git status --short` shows exactly 20 modified source files + 2 untracked new files = **22 total**. All 20 modified files match the plan's Files to Modify list exactly. `grep -rn CollapsingSheetScaffold lib/features | wc -l` → 20. ✓

---

## Completeness Check

All 24 Engineer Tasks from the plan completed:
- **Batch 1** — `collapsing_sheet_scaffold.dart` + test file created ✅
- **Batch 2** — 10 Pattern A files adopted ✅
- **Batch 3** — 10 Pattern B files adopted ✅
- **Batch 4** — `flutter analyze` + `flutter test` both green ✅

No partial implementations or missing edge cases.

---

## Behavior Verification

**Method: code-path analysis for scaffold logic; code review for adoption correctness; automated tests for behavioral cases. No runtime UI exercise was performed — see note at end of section.**

### Scaffold (`collapsing_sheet_scaffold.dart`) — code review:

**Slot rendering** (line 172–196):
- `dragHandle` — always visible, rendered first ✅
- `header` — wrapped in `SizeTransition(alignment: Alignment.bottomCenter, ...)` when non-null; absent when null ✅
- `body` — inside `Expanded(child: NotificationListener<Notification>(...))` ✅
- `footer` — wrapped in `SizeTransition(alignment: Alignment.topCenter, ...)` when non-null ✅

**Animation direction**:
- `alignment: Alignment.bottomCenter` on header → bottom edge anchored, top shrinks upward → **collapses up** ✅
- `alignment: Alignment.topCenter` on footer → top edge anchored, bottom shrinks downward → **collapses down** ✅
- Both transitions share the same `AnimationController` → freed space reclaimed by `Expanded` body with no dead gap ✅

**Scroll detection** (`_onNotification`, lines 103–155):
- `ScrollMetricsNotification` at depth==0 → sets `_hasOverflow`; depth!=0 → ignored ✅
- `UserScrollNotification(reverse)` → `_collapse()` via `Curves.easeIn` ✅
- `UserScrollNotification(forward)` → `_reveal()` via `Curves.easeOut` ✅
- `ScrollEndNotification` → `_reveal()` unconditionally (bypasses debounce, resets accumulated delta) ✅
- `ScrollUpdateNotification` → accumulates `delta.abs()`; collapses/reveals only when `> 6.0` (strict, avoids exactly-6 trackpad events) ✅
- `depth != 0` check applied to all `ScrollNotification` subtypes ✅

**Debounce** (`_acceptDirectionChange`):
- Rejects rapid direction flips inside 50 ms window ✅
- Timer cancelled in `dispose()` ✅

**UX guards** (checked in `_onNotification` and `didChangeDependencies`):
- `viewInsetsOf(context).bottom > 0` → forces `_controller.value = 1.0`, short-circuits listener ✅
- `disableAnimationsOf(context)` → returns early from `_onNotification`; `didChangeDependencies` pins controller to 1.0 ✅
- `!_hasOverflow` → returns early ✅

**Controller lifecycle**:
- `initState`: `_controller` created at `value: 1.0` ✅
- `dispose`: `_debounceTimer?.cancel()` then `_controller.dispose()` ✅
- `unawaited()` applied to both `animateTo` calls (no fire-and-forget unhandled future) ✅

**Note on `alignment` vs `axisAlignment`**: The Flutter SDK at this version deprecates `axisAlignment` ("Use alignment instead — deprecated after v3.41.0-1.0.pre"). Using `alignment` is the correct modern API. `Alignment.bottomCenter` ≡ `axisAlignment: 1.0`; `Alignment.topCenter` ≡ `axisAlignment: -1.0`. Behavior is identical. ✅

**Note on `NotificationListener<Notification>`**: `ScrollMetricsNotification` is NOT a subtype of `ScrollNotification` — it cannot pass through a `ScrollNotification`-typed listener. Using the broader `Notification` base type with `is` checks is the correct workaround. ✅

### Runtime smoke:
Not performed at the macOS/iOS simulator level. All 11 behavioral cases are covered by the widget test suite which passes 206/206. The collapse/reveal motion, keyboard suppression, and reduced-motion disable were verified by automated test, not by physical device exercise. This is noted explicitly for transparency.

---

## Regression Check

### Wrapper preservation (code review):

**PopScope (unsaved-changes guard)** — 3 files required:
- `song_notes_drawer.dart`: `PopScope` at line 90, wrapping scaffold ✅
- `song_details_bottom_sheet.dart`: `PopScope` at line 858, wrapping scaffold ✅
- `song_enrichment_review_sheet.dart`: `PopScope` at line 244, wrapping scaffold ✅

**Entrance `AnimatedBuilder`** — 4 files:
- `pause_creator.dart`: `AnimatedBuilder` at line 156, scaffold inside ✅
- `song_details_bottom_sheet.dart`: `AnimatedBuilder` at line 850, scaffold inside ✅
- `setlist_picker_bottom_sheet.dart`: `AnimatedBuilder` at line 238, scaffold inside ✅
- `song_enrichment_review_sheet.dart`: entrance animation confirmed (code reviewed) ✅

**Keyboard `viewInsets.bottom` outer wrappers**:
- `add_financial_entry_bottom_sheet.dart`: `Container(padding: EdgeInsets.only(bottom: keyboardHeight))` at line 486, outside scaffold ✅
- `song_notes_drawer.dart`: `keyboardHeight` at line 88, used as outer wrapper ✅
- `song_details_bottom_sheet.dart`: `Container(margin: EdgeInsets.only(bottom: bottomPadding))` at line 875, outside scaffold ✅
- `pause_creator.dart`: `bottomInset` at line 154, used outside scaffold ✅
- `add_block_out_drawer.dart`: `constraints: BoxConstraints(maxHeight: height - keyboardHeight)` at line 521, outside scaffold ✅
- `enrichment_selector_bottom_sheet.dart`: `EdgeInsets.only(bottom: viewInsets.bottom)` at line 94, outside scaffold ✅
- `song_enrichment_review_sheet.dart`: `margin: EdgeInsets.only(bottom: bottomPadding)` outside scaffold ✅
- `event_editor_drawer.dart`: no `viewInsets` wrapper — **confirmed the original file also had no such wrapper** (diff shows 0 viewInsets lines added or removed); the outer Container/FTheme is preserved ✅

**Regression rating: LOW** — Wrappers confirmed in every required file by direct code inspection. No auth, routing, Supabase, init-order, or deep-link changes.

---

## Database Safety
N/A — no migrations, no RPC changes, no schema changes.

---

## Analyzer Results

```
flutter analyze (full workspace):
  0 errors
  0 warnings
  0 infos in all 22 changed files
  572 pre-existing info lints in unchanged files (confirmed pre-existing)

Changed files analyzed individually:
  lib/components/ui/collapsing_sheet_scaffold.dart → 0 issues
  All 20 modified feature files → 0 issues each
  test/components/ui/collapsing_sheet_scaffold_test.dart → 0 issues
```

---

## Test Results

```
flutter test (full suite):
  206/206 pass
  0 failures
  0 errors

New scaffold tests (test/components/ui/collapsing_sheet_scaffold_test.dart):
  collapses footer on reverse scroll ✅
  reveals footer on forward scroll ✅
  reveals footer on scroll-end notification ✅
  collapses header+footer when header slot present ✅
  no header SizeTransition when header is null ✅
  respects 6-pixel anti-flicker threshold ✅
  ignores nested scroll notifications (depth != 0) ✅
  is a no-op when body has no overflow ✅
  suppresses collapse when keyboard is open ✅
  disables collapse under reduced motion ✅
  footer child is untouched SheetFooter without extra SafeArea ✅

All 11 plan-required test cases present and passing.
```

---

## Diff Safety Review

- `debugPrint` in diff: **none** (grepped all `+` lines) ✅
- `TODO` / `FIXME` in diff: **none** ✅
- Leftover test scaffolding: **none** ✅
- Accidental deletions: **none detected** ✅
- Secrets / API keys: **none** ✅
- Unrelated formatting churn: **none detected** — `git diff --numstat` shows only the 20 target files with net-negative deltas (structural simplification) ✅

---

## Change Budget Review

### Per-file net line deltas (`git diff --numstat`, additions − deletions):

| File | +Added | −Deleted | Net | Plan range | Status |
|---|---|---|---|---|---|
| `add_financial_entry_bottom_sheet.dart` | 305 | 333 | −28 | −5 to +25 | ✅ |
| `band_member_edit_drawer.dart` | 216 | 222 | −6 | −10 to +30 | ✅ |
| `pause_creator.dart` | 198 | 207 | −9 | −5 to +25 | ✅ |
| `gig_pay_bottom_sheet.dart` | 144 | 162 | −18 | −5 to +25 | ✅ |
| `view_gig_drawer.dart` | 136 | 149 | −13 | −5 to +25 | ✅ |
| `financial_entry_details_bottom_sheet.dart` | 135 | 146 | −11 | −5 to +25 | ✅ |
| `view_rehearsal_drawer.dart` | 93 | 105 | −12 | −5 to +25 | ✅ |
| `day_detail_bottom_sheet.dart` | 91 | 105 | −14 | −10 to +30 | ✅ |
| `band_member_detail_drawer.dart` | 87 | 97 | −10 | −5 to +25 | ✅ |
| `enrichment_selector_bottom_sheet.dart` | 79 | 87 | −8 | −5 to +25 | ✅ |
| `add_block_out_drawer.dart` | 74 | 89 | −15 | −10 to +30 | ✅ |
| `contact_detail_drawer.dart` | 73 | 84 | −11 | −5 to +25 | ✅ |
| `view_block_out_drawer.dart` | 59 | 71 | −12 | −5 to +25 | ✅ |
| `setlist_picker_bottom_sheet.dart` | 50 | 63 | −13 | −10 to +30 | ✅ |
| `rehearsal_notes_sheet.dart` | 36 | 46 | −10 | −10 to +30 | ✅ |
| `gig_notes_sheet.dart` | 36 | 46 | −10 | −10 to +30 | ✅ |
| `song_enrichment_review_sheet.dart` | 20 | 20 | 0 | −10 to +30 | ✅ |
| `song_details_bottom_sheet.dart` | 19 | 19 | 0 | −10 to +30 | ✅ |
| `song_notes_drawer.dart` | 14 | 14 | 0 | −10 to +30 | ✅ |
| `event_editor_drawer.dart` | 13 | 13 | 0 | ~two-line swap | ✅ |

All 20 modified files within the plan's stated net-line estimates. Overall net is negative (structural simplification). ✓

### New files:

| File | Actual lines | Plan estimate | Ratio |
|---|---|---|---|
| `collapsing_sheet_scaffold.dart` | 197 | 250–320 | 78% of min (compact) |
| `collapsing_sheet_scaffold_test.dart` | 539 | 180–260 | ~2.07× max |

- **Scaffold** is 197 lines — ~20% under the plan's lower estimate. More compact, no missing functionality confirmed by 0 analyzer issues and test pass. Note only; not a defect.
- **Test file** at 539 lines is over the plan's 180–260 estimate. See Issues Found below.

### No new helpers, extensions, or utility classes added outside the scaffold file. Confirmed by reviewing all 20 adoption diffs — no `_buildX()` helpers, no new providers, no new public classes. ✓

### Zero-deletion concern:
`song_enrichment_review`, `song_details`, `song_notes`, `event_editor` each show 0 net (equal adds/deletes) per numstat. This is structural equivalence, not a missing fix — the adoption swapped the Column scaffold for `CollapsingSheetScaffold` with matching line counts. Confirmed by diff review. No concern. ✓

---

## Code Efficiency Review

No AI-shaped code patterns found:
- No single-use `_buildX()` helper methods added in any migration file.
- No new providers, repositories, or services.
- No new `FutureBuilder`/`StreamBuilder` constructs.
- No hand-rolled first-match/grouping/dedupe loops.
- No catch blocks that log-and-rethrow unchanged.
- No comments restating the next line.
- No config/flag/enum cases added for future use.

The one design question — `drag-handle moved from scroll content to `dragHandle` slot in 4 Pattern A files` — is a legitimate UX improvement (handle always visible, not scrolled away) and is architecturally correct per the plan's slot design. ✓

---

## High-Risk Spot-Check Results

### (a) `event_editor_drawer.dart` — Pattern B, highest complexity

**Diff summary** (+13 −13, minimal call-site swap):
- `_buildStickyHeader(context)` + divider moved into `header:` slot ✅
- `_buildScrollableBody(context)` in `SingleChildScrollView` as `body:` ✅
- `_buildStickyFooter(context)` as `footer:` ✅
- `_buildStickyFooter` confirmed to respect `widget.viewOnly`, `_isSaving`, `_isDirty` gates (confirmed by grepping the function at line 3122) ✅
- `_isSaving` field (line 238), `_isDirty` field (line 247), `viewOnly` property (line 99) all preserved ✅
- Outer `FTheme(child: Container(...BoxDecoration...))` preserved outside scaffold ✅
- No `viewInsets` wrapper in original or modified — nothing dropped ✅

### (b) `song_details_bottom_sheet.dart` — temporarily broken then fixed

Final state confirmed complete and correct:
- `AnimatedBuilder` at line 850 → `PopScope` → `Container(margin: EdgeInsets.only(bottom: bottomPadding))` → `CollapsingSheetScaffold` with `header:`, `body:`, `footer:` ✅
- `_buildHeader()` extracted into `header:` slot ✅
- Title/close/subtitle content in header confirmed by reading lines 878–891 ✅
- No analyzer issues ✅

### (c) `setlist_picker_bottom_sheet.dart` — conditional footer

```dart
footer: _isCreatingNew
    ? SheetFooter(primaryLabel: 'Create & Add', ...)
    : null,
```
List mode passes `footer: null` → scaffold renders no footer `SizeTransition` → no crash, no dead gap ✅
Header still collapses when list scrolls ✅

### (d) `financial_entry_details_bottom_sheet.dart` — SingleChildScrollView deviation

Deviation: explicit `SingleChildScrollView` at call site as `body:` (plan noted scaffold was intended to auto-wrap, but the actual scaffold does NOT auto-wrap — `body` goes into `Expanded(child: NotificationListener(child: widget.body))`). The caller providing the scroll view is the correct approach given the scaffold's actual API. Equivalent UX result. No overflow/layout regression risk because:
1. `SingleChildScrollView` in `Expanded` is standard Flutter pattern
2. No-overflow guard means chrome stays visible when content fits
3. 0 analyzer issues ✅

### (e) `band_member_edit_drawer.dart` — "Remove from band" stays in body

`CollapsingSheetScaffold` at line 266; `body: SingleChildScrollView(...)` starts at line 324; "Remove from band" button at line 490 is inside the `body` ✅. It scrolls with content — correct per the plan's note that it stays in the body.

---

## Deviation Assessment

| # | Deviation | Acceptable? |
|---|---|---|
| 1 | `NotificationListener<Notification>` instead of `<ScrollMetricsNotification>` | ✅ Required — `ScrollMetricsNotification` is not a `ScrollNotification` subtype |
| 2 | `alignment` instead of `axisAlignment` | ✅ Improvement — `axisAlignment` deprecated after Flutter v3.41.0-1.0.pre |
| 3 | Strict `> 6.0` px threshold (not `>= 6.0`) | ✅ Avoids toggle on exactly-6px trackpad events |
| 4 | `financial_entry_details`: `SingleChildScrollView` at call site | ✅ Correct given scaffold's actual API; UX identical |
| 5 | Drag handle moved from scroll content to `dragHandle:` slot (4 Pattern A files) | ✅ UX improvement; always-visible handle is the intended slot semantics |

---

## Issues Found

### Warnings

**[W-1] `code-quality` — Test file line overage**

`test/components/ui/collapsing_sheet_scaffold_test.dart` is 539 lines vs. the plan budget of 180–260 lines (2.07× maximum).

Content is entirely the 11 plan-specified widget test cases — no extra tests, no extra scenarios. The overage comes from Flutter widget test boilerplate inherent to this test style (one `await tester.pumpWidget(...)` + `_dispatch(...)` + `await tester.pumpAndSettle()` + assertions per case, plus the shared `_wrap()` and `_makeMetrics()` helpers). The plan's estimate was low for this style.

ENGINEER_REPORT does not justify the line count. Per the budget rules (>1.5× → Warning), flagged. Not a blocker — the content is correct, passes analysis, all 11 required cases present.

**Actionable if resolved in a later cycle:** Engineer adds a one-line budget note to `ENGINEER_REPORT.md` explaining the overage. No code change needed.

---

### Suggestions

**[S-1] `code-quality` — ENGINEER_REPORT.md path error for 3 files**

The report's "Files Modified" section lists:
- `lib/features/songs/widgets/song_notes_drawer.dart`
- `lib/features/songs/widgets/song_details_bottom_sheet.dart`
- `lib/features/songs/widgets/song_enrichment_review_sheet.dart`

Actual paths (matching both the plan and `git status`):
- `lib/features/setlists/widgets/song_notes_drawer.dart`
- `lib/features/setlists/widgets/song_details_bottom_sheet.dart`
- `lib/features/setlists/widgets/song_enrichment_review_sheet.dart`

Documentation error only. Code is in the correct locations. No code change needed.

**[S-2] `code-quality` — ENGINEER_REPORT.md cites wrong examples for PopScope files**

The report states: "PopScope confirmed present … in all Pattern B files that had it (e.g., `event_editor_drawer.dart`, `band_member_edit_drawer.dart`)." Neither of those files has PopScope. The files that actually have PopScope — and should — are `song_notes_drawer`, `song_details_bottom_sheet`, and `song_enrichment_review_sheet`. Code is correct; report examples are wrong. Documentation only.

---

## Final Verdict

**APPROVED**

All plan tasks completed. Scaffold behavioral requirements met (code-path analysis + 11/11 automated widget tests). All 22 files within scope. 0 off-limits files touched. 0 analyzer errors/warnings/infos in changed code. 206/206 tests passing. All high-risk wrappers (PopScope, entrance animations, keyboard viewInsets) preserved outside the scaffold in every required file. One Warning (test file line count overage — content correct, 11/11 cases present) and two Suggestions (report documentation errors). No Critical findings. No runtime UI exercise was performed; behavioral correctness was validated via automated tests and code-path analysis only — this is noted for transparency.
