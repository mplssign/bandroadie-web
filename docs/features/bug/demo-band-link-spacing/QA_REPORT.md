# QA_REPORT — bug/demo-band-link-spacing

## Feature Slug

`bug/demo-band-link-spacing`

## Feature Title

"Check out the demo band" link sits too close to the logo on the login screen; should be positioned lower, closer to the Email field

## Cycle Number

4

## Final Verdict

**APPROVED**

## Validation Summary

Cycle 4 is an owner-reported issue found while testing the QA-approved Cycle 3 state (merged into open PR #279, not yet merged to `main`): the email domain shortcut pill row was cut off horizontally by the same 32px `Padding(hz: 32)` inset shared by the rest of the login form. `ENGINEER_REPORT.md` (Cycle Number 4) diagnoses this correctly — the single ambient `Padding` wrap around the entire `_buildContentCluster()` output inset every child, including the pill row, to `screenWidth − 64`, identical to the email field. There was no bug inside `_buildDomainPills()` itself.

The fix removes that single ambient `Padding` and instead applies two separate `Padding(hz: 32)` wraps — one around a new sub-`Column` holding the logo/demo/email group, one around a second sub-`Column` holding the login-button/message group — leaving the domain pill row as a plain, unpadded sibling `Column` item between them. The pill row's `_buildDomainPills` call now receives `maxWidth: maxWidth + 64` (i.e. the full `constraints.maxWidth`, not the email-field width), and its inner `SizedBox(width: maxWidth)` therefore spans the full screen width edge-to-edge.

QA independently reviewed the full diff (`git diff HEAD -- lib/features/auth/login_screen.dart`, 91 insertions / 54 deletions, matching the report's stated numstat exactly) and confirms:

- The `maxWidth` value passed into `_buildContentCluster` is unchanged in substance (`constraints.maxWidth - (_kHorizontalPadding * 2)` = the same `constraints.maxWidth - 64` as before) — `logoWidth = (maxWidth * 0.9).clamp(0.0, 600.0)` is therefore numerically identical to Cycle 3, so the logo's rendered width is unaffected.
- All four Cycle 3 `Transform.translate` offsets (logo `-50`, demo `-65`, email `-50`, pills `-50`) are present verbatim at the same relative call sites, just re-nested one level deeper inside the new `Padding`/`Column` sub-groups (logo/demo/email) or left in place as a direct child (pills). `Transform.translate` is a paint-only primitive independent of tree depth, so re-nesting cannot change any of these four offsets' visual effect — confirmed by direct reading of the diff, not just taken on the Engineer's word.
- No `SizedBox` height, `mainAxisAlignment`, or `Align` value changed anywhere in the diff — only the `Padding`/`Column` re-nesting and the pill row's `maxWidth` math changed.
- The domain pill row's `SizedBox(width: maxWidth)` in `_buildDomainPills` now receives `maxWidth + 64` from the caller, which equals the original, un-inset `constraints.maxWidth` — the row genuinely spans full screen width, confirmed by tracing the value end-to-end rather than trusting the report's arithmetic claim alone.
- `test/features/auth/login_screen_demo_button_test.dart` (off-limits) is untouched; no other file besides `lib/features/auth/login_screen.dart` and `ENGINEER_REPORT.md` is part of the tracked diff.

Analyzer is clean, all three tests pass, and the 20-iteration Test C loop-stability re-check independently passed 20/20 with zero failures. No secrets or debug artifacts were introduced by the diff (pre-existing `debugPrint` calls elsewhere in the file are outside the diff's hunks). This is **code-path analysis plus independent trace-through of the `maxWidth` arithmetic**, not manual/runtime verification — QA did not launch the app on any platform, consistent with mode rules. Visual confirmation that the pill row now reaches both screen edges, and that the logo/demo link/email field/login button remain at their exact Cycle 3 positions, is an owner-run (Tony) punch-list item — see below.

## Architect Scope Review

No new `ARCHITECT_PLAN.md` exists for Cycle 4 — per `ENGINEER_REPORT.md`, this is a direct owner-reported issue found during PR #279 testing, handled the same way Cycle 3 was (owner instruction → Engineer implements directly, no Architect re-pass), and the user request explicitly authorized engineering judgment on the exact mechanism. QA held the diff to that stated scope:

- Diff touches exactly one source file: `lib/features/auth/login_screen.dart`. Matches report.
- The entire Cycle 4 change is confined to the top-of-file constant addition and `_buildContentCluster()`'s internal structure, plus two doc-comment updates (`Layout contract:` bullet and the `_buildDomainPills` doc/inline comment) — no other method in the file is touched. Confirmed by diff.
- `test/features/auth/login_screen_demo_button_test.dart` (Files Off-Limits from the original Cycle 1 plan, never overridden for this cycle) — confirmed untouched via `git diff HEAD --numstat` scoped to `test/`, which returns nothing for this file.
- No changes to `lib/main.dart`, `lib/app/**`, `demo_session_service.dart`, `auth_gate.dart`, `auth_confirm_screen.dart`, `pubspec.yaml`/`.lock`, `analysis_options.yaml`, `supabase/**`, `database/**`, `assets/images/**`, `lib/components/ui/email_domain_shortcut_bar.dart`, or any other `lib/features/**` file — independently confirmed via `git diff HEAD --numstat` scoped to those paths, which returns only `docs/features/bug/demo-band-link-spacing/ENGINEER_REPORT.md` and `lib/features/auth/login_screen.dart`.
- Untracked pre-existing artifacts (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/PR_BODY.md`, `docs/features/feature/financials-transaction-cards-reconciliation/PR_BODY.md`, `docs/features/feature/financials-transaction-cards/`, `docs/features/transaction-drawer-redesign/PR_BODY.md`) remain leftovers from unrelated prior slugs, not created by this Engineer's Cycle 4 work — correctly out of scope for this review.

## Completeness Check

`ENGINEER_REPORT.md`'s Cycle 4 "Fix Implemented" task list (4 items) verified directly against the diff:

1. `_kHorizontalPadding = 32.0` top-level constant added, replacing the previously duplicated `32`/`64` magic numbers. Confirmed in diff.
2. The single `Padding(hz: 32)` wrap around the whole `_buildContentCluster()` output in `LoginScreen.build()` is removed; `maxWidth` passed into `_buildContentCluster` is now `constraints.maxWidth - (_kHorizontalPadding * 2)` — numerically identical to the prior `constraints.maxWidth - 64`. Confirmed in diff — no behavior change for that computation, as claimed.
3. Inside `_buildContentCluster()`, the single flat `Column` is split into three siblings: a `Padding(hz: 32)`-wrapped `Column` (logo, demo button, email field — same content/order/spacers as Cycle 3, re-nested one level deeper); the domain pill row as a plain unpadded sibling receiving `maxWidth: maxWidth + 64`; a second `Padding(hz: 32)`-wrapped `Column` (trailing spacer, login button, message, final spacer — same content/order as Cycle 3, re-nested). Confirmed in diff, matches exactly.
4. The `Layout contract:` doc comment and the `_buildDomainPills` doc/inline "PILL SNAP-ALIGNMENT" comment are updated to describe the new full-width contract. Confirmed — no other bullet/comment in either doc block was altered; the Cycle 3 bullet describing the four `Transform.translate` offsets is preserved verbatim.

No partial implementation. No missing edge case relative to the owner's "extend edge to edge" request — the pill row's effective width is traced end-to-end (see Validation Summary) and confirmed to equal the full, un-inset screen width.

## Behavior Verification

Independently traced the `maxWidth` value through the call chain rather than taking the report's math on faith:

- `LoginScreen.build()`: `maxWidth` param to `_buildContentCluster` = `constraints.maxWidth - 64` (unchanged in value from Cycle 3, just expressed via the named constant).
- `_buildContentCluster()`: `logoWidth = (maxWidth * 0.9).clamp(...)` — uses the same `maxWidth` as before, so the logo's rendered width is byte-identical to Cycle 3. The email field (`_buildEmailField()`) has no explicit width constraint of its own beyond whatever its parent `Padding`-wrapped `Column` gives it — since that `Column` is inside a `Padding(hz: 32)` identical in extent to Cycle 3's ambient padding, the email field's effective width is unchanged.
- The domain pills call site now passes `maxWidth + 64` = `(constraints.maxWidth - 64) + 64` = `constraints.maxWidth` — the original, full, un-inset screen width. `_buildDomainPills`'s own body applies this value directly as `SizedBox(width: maxWidth)`, with no further inset inside the method — so the row's rendered width is genuinely the full screen width, confirmed by tracing the value rather than trusting the claim.
- All four `Transform.translate` wraps (`-50` logo, `-65` demo, `-50` email, `-50` pills) remain at their Cycle 3 call sites, only re-nested one `Column`/`Padding` level deeper (logo/demo/email) or left as a direct child (pills). `Transform.translate` repositions only the painted output of its child and is independent of ancestor nesting depth or ancestor padding — re-nesting a `Transform.translate`-wrapped widget inside an additional `Padding`/`Column` does not change the offset it applies to its own child. This is a sound, independently-verified basis for the "positions preserved verbatim" claim, not merely restated from the report.
- No `SizedBox` height, `mainAxisAlignment`, or `Align` value changed anywhere in the diff — confirmed directly by reading every hunk; the only new value introduced is the pill row's `maxWidth + 64` width computation and the `_kHorizontalPadding` constant itself.
- Web (`_kDemoBandVisible == false`): the demo button's `if (_kDemoBandVisible)` gate is preserved verbatim inside the (now re-nested) logo/demo/email `Padding` group — no change to web/native parity introduced by this cycle beyond what Cycle 3 already established (all four wraps, including the platform-parity note from the Cycle 3 record, are otherwise unaffected by this cycle's restructuring).

This is **code-path analysis plus independent trace-through of the `maxWidth`/offset arithmetic**, not manual/runtime verification. QA did not launch the app on any platform.

## Regression Check

| Area | Risk | Notes |
| --- | --- | --- |
| Auth / session / magic-link / PKCE | LOW | Not touched by diff. |
| Init order | LOW | Not touched by diff. |
| Platform parity (native vs. web) | LOW | This cycle's restructuring does not touch the `_kDemoBandVisible`/`kIsWeb` gating logic at all — the demo button's conditional block is preserved unchanged, just re-nested inside the new `Padding` sub-group. The Cycle 3 platform-parity note (web also receiving the logo/email/pills `Transform.translate` shifts) is unaffected by this cycle either way. |
| PR #278 overflow safety (Flexible wrap on logo) | LOW | Structurally unaffected — no `SizedBox`/`Flexible`/`Align` bound around the logo changed; the re-nesting only adds an outer `Padding`/`Column` around the logo/demo/email group, which does not alter the logo's own `availableHeight / 2` budget. Independently re-run 20/20 passing on Test C. |
| Domain pill row width / overflow | LOW | Traced end-to-end: the row's `SizedBox(width: maxWidth)` now receives the full, un-inset `constraints.maxWidth`, confirmed by arithmetic trace, not just claim. `EmailDomainShortcutBar` itself (the pill row's child widget) is untouched by this diff — its internal scroll/pill-rendering logic is unaffected, only the width budget its parent hands it changed. |
| Negative-`Padding`/`OverflowBox` dead-end approaches | N/A | Report states both were tried and discarded during implementation (framework assertion failures) before landing on the final full-width-sibling restructure. Neither dead-end approach is present in the final diff — confirmed, the diff contains only `Padding`/`Column` re-nesting and the `maxWidth` arithmetic change, no `OverflowBox` or negative `Padding` anywhere. |
| Paint-level overlap (logo ↔ demo link) flagged in Cycle 3 | LOW (unchanged from Cycle 3) | This cycle does not touch any of the four `Transform.translate` offset values — the Cycle 3-flagged compact-viewport overlap risk is neither improved nor worsened by this restructuring. Still an open, non-blocking punch-list item carried forward from Cycle 3 (not re-litigated here since nothing about it changed). |
| Animation timing / intervals | LOW | Not touched — `Transform.translate`/`FadeTransition`/`SlideTransition` wraps and their controllers are unchanged; only the surrounding `Padding`/`Column` structure changed. |
| Hit-testing / tap targets | LOW | No element's screen position changed relative to Cycle 3 (see Behavior Verification) — hit-testing is unaffected by construction. Not independently verified at runtime; flagged as a secondary punch-list check. |
| Controller/FocusNode disposal, `setState` after async gaps | LOW | Not touched — diff is confined to widget-tree structure inside a single build method. |

Overall regression risk: **LOW**. No new regressions introduced by this cycle; the one previously-flagged Cycle 3 paint-overlap risk (logo/demo link at compact viewports) is carried forward unchanged and remains on the punch list below since this cycle did not touch those offsets.

## Database Safety

N/A — no DB/RLS/RPC/migration impact. Diff confirmed to touch no `supabase/**` or `database/**` files.

## Analyzer Results

```
flutter analyze lib/features/auth/login_screen.dart
Analyzing login_screen.dart...
No issues found! (ran in 3.0s)
```

Independently re-run by QA; matches Engineer's reported Cycle 4 result.

## Test Results

```
flutter test test/features/auth/login_screen_demo_button_test.dart
00:03 +3: All tests passed!
```

Independently re-run by QA (Tests A, B, C all pass).

Loop-stability check for Test C, independently re-executed by QA against the Cycle 4 code (20 iterations, each individually checked for "All tests passed"):

```
for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" || echo "FAILED run $i"; done
```

Result: 20/20 passed, zero `FAILED` lines emitted — matches the Engineer's reported result exactly.

`dart format --output=none --set-exit-if-changed lib/features/auth/login_screen.dart` independently re-run by QA: `Formatted 1 file (0 changed)` — confirms the file is already correctly formatted, matching the report's claim of one reformat already applied prior to hand-off.

## Diff Safety Review

- No secrets, API keys, or credentials found in the diff.
- No `TODO`/`FIXME`/`debugPrint(` within the diff hunks — `git diff HEAD -- lib/features/auth/login_screen.dart | grep -iE "TODO|FIXME|debugPrint\("` returned no matches. The file contains pre-existing `debugPrint(...)` calls elsewhere (session-check/error-handling logging, lines ~129/393/400/407/415) — outside this diff's hunks, untouched by this change, correctly not flagged.
- No leftover test scaffolding (the two discarded implementation attempts — negative `Padding`, `OverflowBox` — are confirmed absent from the final diff), no accidental deletions, no unrelated formatting churn — diff is confined to the constant addition, the `Padding`/`Column` re-nesting, the pill-row `maxWidth` change, and the two doc-comment updates described in `ENGINEER_REPORT.md`.

## Change Budget Review

- No Cycle 4 Architect Plan/Change Budget exists — this is a direct owner-reported-issue cycle, not a new planning pass, per `ENGINEER_REPORT.md`.
- `git diff --numstat` for `lib/features/auth/login_screen.dart`: 91 insertions, 54 deletions — matches the report's stated numstat exactly. The Engineer's characterization ("mostly re-indentation from the added nesting level, not new logic") is corroborated by direct reading of the diff: the vast majority of the insertion/deletion pairs are the same lines re-indented one level deeper inside the new `Padding`/`Column` wraps, not new logic. The only genuinely new logic is the `_kHorizontalPadding` constant declaration and the pill row's `maxWidth + (_kHorizontalPadding * 2)` expression.
- This bug fix has substantial deletions (54) alongside insertions (91), so the "bug fix with zero deleted lines" Warning trigger does not apply here.
- Expected new files: 0 — actual: 0.
- Expected new public classes/methods: 0 — actual: 0 (one new private top-level `const double`, not a class or method).
- Expected new dependencies: 0 — actual: 0.
- Expected new tests: 0 — actual: 0 (test file untouched; report states existing Tests A/B/C already cover the invariants this change can affect, and the visual edge-to-edge outcome is correctly deferred to Tony's punch list).

## Code Efficiency Review

- No new widgets, helpers, providers, notifiers, or public methods introduced — the change re-nests existing `Padding`/`Column` primitives already used throughout this file, plus one new `const double` that replaces a previously duplicated magic number (`32`/`64` appeared in two places before this change; now a single named constant). This is a genuine, minor de-duplication improvement, not bloat.
- Report states a search of `lib/` for an existing "full-bleed"/"edge-to-edge"/"break out of padding" helper was performed and found none — independently spot-checked via a search of `lib/` for similar full-bleed/edge-to-edge patterns; none found, corroborating the claim. This is a one-off structural adjustment scoped to a single screen, not a pattern repeated elsewhere, so no shared abstraction is warranted.
- No single-use `_buildX()` method added beyond what already existed; no new `copyWith` entries, hand-rolled loops/try-catch, or barrel files.
- File size/method size unaffected relative to the 500-line Dart target per the report's claim; the restructuring adds nesting depth but no new methods.

No bloat findings.

## Manual Verification Punch List

QA did not attempt any of these — cannot launch the app in this pipeline.

1. **[Primary check for this cycle]** `flutter run -d macos` (or `-d chrome`/`-d ios`), open the login screen, and confirm the email domain shortcut pill row now visually extends to both screen edges (no visible gap matching the 32px inset still present above/below it around the email field and login button). **Expected:** the pill row's background/content reaches flush to the left and right edges of the screen/window, while the logo, "Check out the demo band" link, email field label/input, and login button all remain visually inset from the edges exactly as they were in the already-approved Cycle 3 state.
2. At the same time, confirm the logo, "Check out the demo band" link, email field, and login button have **not** moved from their Cycle 3 positions — this is a restructuring-only cycle, so nothing about their vertical position or horizontal inset should look different from what you already approved testing PR #279.
3. Scroll the pill row (if it has more shortcuts than fit on screen) and confirm horizontal scrolling still works correctly now that it has more width to work with — confirm no visual clipping or stray padding remains at either edge during a scroll.
4. Resize the macOS window down to a compact size (~800×600 client area) and confirm no `RenderFlex` overflow banner appears — this exercises PR #278's overflow-safety mechanism, unaffected by this cycle's `Padding` restructuring per the analysis above, but worth a quick visual confirmation.
5. Repeat step 1 on `flutter run -d chrome` and (if available) `flutter run -d ios`, to confirm the edge-to-edge pill row renders correctly across platforms — this cycle's change is not platform-conditioned, so all platforms should show the same full-width pill row.
6. This cycle carries forward the still-open Cycle 3 punch-list item (not re-tested here since this cycle didn't touch those offsets): on a compact viewport (~800×600), confirm the logo and the "Check out the demo band" link still do not visually overlap. If you already confirmed this while testing PR #279 before this cycle's fix, no need to repeat it — flagging only because it remains open in the audit trail.

## Issues Found

**Critical:** none.

**Warnings:** none.

**Suggestions:**

- **`code-quality`** — As in Cycles 2–3, no formal Cycle 4 Architect Plan/Change Budget exists since this is a direct owner-reported issue rather than a new planning pass. Not a blocker (the diff is single-file, well-explained, and the restructuring rationale — including two discarded dead-end approaches — is documented in detail in `ENGINEER_REPORT.md`), but if further layout-restructuring cycles are anticipated for this file, a short Architect addendum per cycle would let future QA verify against an explicit budget rather than reconstructing rationale from the Engineer's report alone.

---

## Cycle 3 Record (preserved for history)

### Cycle 3 Final Verdict

**APPROVED**

### Cycle 3 Validation Summary

Cycle 3 is a direct, explicit, numeric owner (Tony) instruction layered on top of the already-QA-approved Cycle 2 state (see Cycle 2 and Cycle 1 records preserved verbatim below): move the logo up 50px, the demo link up 65px, and the email field + domain pills up 50px each, each relative to its own Cycle 2 rendered position. `ENGINEER_REPORT.md` (Cycle Number 3) implements this as four `Transform.translate` paint-only wraps at the existing call sites inside `_buildContentCluster()`, plus one doc-comment bullet. No layout box size, `Flexible`/`Align` bound, or the `availableHeight / 2` split is touched, so PR #278's overflow-safety mechanism and Test C are structurally unaffected by construction (paint-time transforms cannot change `RenderFlex` sizing).

The working tree contains exactly one uncommitted tracked change (`lib/features/auth/login_screen.dart`). QA independently confirmed: the diff is confined to four `Transform.translate` wraps (offsets `-50`, `-65`, `-50`, `-50` respectively for logo/demo/email/pills) and one doc-comment bullet, with no internals of `_buildEmailField()` or `_buildDomainPills()` touched (only their call sites, which the doc-comment override explicitly authorizes for this cycle); analyzer is clean on the modified file; all three tests in `login_screen_demo_button_test.dart` pass; the 20-iteration Test C loop-stability check passes 20/20; no secrets or debug artifacts were introduced by the diff; and no off-limits files were touched. This is **code-path analysis plus independent Flutter-semantics reasoning about `Transform.translate`**, not manual/runtime verification — QA did not launch the app on any platform, consistent with mode rules.

**Tony's explicit instruction to override the original Cycle 1 plan's off-limits restriction on `_buildEmailField()`/`_buildDomainPills()` is honored as documented** — the override is narrowly scoped to repositioning via wrap at the call site, not restructuring those widgets' internals, and the diff confirms that narrow scope was respected.

**The Engineer's flagged non-blocking risk is validated as sound and is called out below as the top item on the Manual Verification Punch List**: because the demo link moves up 15px more than the logo, their Cycle-2 visual gap shrinks by 15px. This cannot regress any automated test (layout sizes are unchanged; it is a paint-level overlap risk, not a `RenderFlex` overflow), so it does not block this verdict, but it is a genuine visual risk at compact viewports that only a running app can confirm — see punch list item 1 below.

### Cycle 3 Architect Scope Review

There is no new `ARCHITECT_PLAN.md` for Cycle 3 — per `ENGINEER_REPORT.md`, this is a direct owner-instruction cycle, not a new architect-planned task, and Tony's instruction explicitly authorizes deviating from the original Cycle 1 plan's off-limits list for this cycle only. QA held the diff to that explicit authorization plus the plan's still-governing constraints for everything not covered by the override:

- Diff touches exactly one file: `lib/features/auth/login_screen.dart`. Matches plan/report.
- The entire Cycle 3 change is confined to `_buildContentCluster()` — no other method in the file is touched. Confirmed by diff.
- The four `Transform.translate` wraps touch only the **call sites** of `_buildLogo(...)`, `_buildDemoButton()`, `_buildEmailField()`, `_buildDomainPills(...)` inside `_buildContentCluster()` — none of those four methods' own bodies/internals are modified. This matches the narrow scope of Tony's override as described in `ENGINEER_REPORT.md` ("repositioning via wrap, not restructuring the widgets themselves").
- `test/features/auth/login_screen_demo_button_test.dart` (Files Off-Limits, never overridden by Tony's instruction) — confirmed untouched (`git diff HEAD --stat -- test/` returns empty).
- No changes to `lib/main.dart`, `lib/app/**`, `demo_session_service.dart`, `auth_gate.dart`, `auth_confirm_screen.dart`, `pubspec.yaml`/`.lock`, `analysis_options.yaml`, `supabase/**`, `database/**`, `assets/images/**`, or any other `lib/features/**` file — independently confirmed empty via `git diff HEAD --stat` scoped to those paths.
- Untracked pre-existing artifacts (`docs/features/bug/demo-session-cleanup-orphaned-anonymous-users/PR_BODY.md`, `docs/features/feature/financials-transaction-cards-reconciliation/PR_BODY.md`, `docs/features/feature/financials-transaction-cards/`, `docs/features/transaction-drawer-redesign/PR_BODY.md`) remain leftovers from unrelated prior slugs, not created by this Engineer's work — correctly out of scope for this review.

### Cycle 3 Completeness Check

`ENGINEER_REPORT.md`'s Cycle 3 task list (6 items) verified directly against the diff:

1. `_buildLogo(logoWidth: logoWidth)` — already wrapped in `Align(alignment: const Alignment(0, 0.5), ...)` from Cycle 2 — now additionally wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`. Confirmed in diff.
2. `_buildDemoButton()` — now wrapped in `Transform.translate(offset: const Offset(0, -65), ...)`. Confirmed in diff; the surrounding `if (_kDemoBandVisible) ...[...]` block and trailing `SizedBox(height: 12)` from Cycle 1 are otherwise unchanged.
3. `_buildEmailField()` — now wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`. Confirmed in diff.
4. `_buildDomainPills(maxWidth: maxWidth)` — now wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`. Confirmed in diff.
5. `Layout contract:` doc comment updated with a new "Cycle 3 (owner-directed, paint-only)" bullet documenting all three offsets and stating layout sizes are unchanged. Confirmed — no other bullet in that doc comment was altered (the two Cycle-2-era bullets and the "Logo width is 90%..." / "Form elements start at the midpoint..." bullets are verbatim).
6. All existing spacers (`SizedBox(height: 12)` between demo/email and email/pills, the outer `SizedBox(height: availableHeight / 2)`, the trailing 24px/40px spacers) are untouched. Confirmed — diff shows no `SizedBox` height values changed anywhere.

No partial implementation. No missing edge case relative to Tony's three-part numeric instruction — all three moves (50px, 65px, 50px) are present at the correct call sites with the correct signs (negative = up, per `Transform.translate`/`Offset` semantics).

### Cycle 3 Behavior Verification

Independently reasoned through Flutter's `Transform.translate` semantics rather than taken on the Engineer's word:

- `Transform.translate` repositions its child's **painted** output (and, by default, its hit-test region — `transformHitTests` defaults to `true`) without altering the size or constraints the child reports to its parent during layout. The parent `Column`/`Flexible`/`SizedBox`/`Align` structure therefore lays out exactly as it did in Cycle 2; only paint position (and consequently interactive hit-test position) shifts. This means: (a) tapping the demo button or the email field still hits the correct widget at its new visual location — no dead-tap-zone regression; (b) `RenderFlex` sizing, and therefore PR #278's overflow-safety invariant, cannot be affected by this change, independent of any test run.
- The claimed per-pair gap deltas in `ENGINEER_REPORT.md`'s risk assessment were independently re-derived and confirmed arithmetically sound: logo −50 vs. demo −65 ⇒ demo moves 15px more ⇒ their visual gap **shrinks 15px**; demo −65 vs. email −50 ⇒ demo moves 15px more ⇒ their gap **grows 15px**; email −50 vs. pills −50 ⇒ equal move ⇒ gap **unchanged**; pills −50 vs. login button (unmoved) ⇒ gap **grows 50px**. All four match the Engineer's stated deltas.
- `_kDemoBandVisible` gating, `_buildDemoButton()`/`_enterDemo`/`_buildEmailField()`/`_buildDomainPills()` internals, and all animation controllers (`_buttonOpacity`, `_logoShrinkController`, `_titleOpacity`, `_titleScale`) are untouched — confirmed by diff (no hunks outside the four wrap sites and the doc comment).
- Web (`_kDemoBandVisible == false`): the moved demo-button block remains a no-op on web in either tree location; the three always-rendered elements (logo, email field, domain pills) each still receive their respective `Transform.translate`, so **web layout is not byte-identical to Cycle 2 for this cycle** — logo/email/pills all shift up 50px on web too, since none of these four wraps are conditioned on `_kDemoBandVisible`. This is consistent with Tony's instruction (which does not exempt web) and is not a defect, but note this is a change in status from Cycle 1/2's "web is byte-identical" invariant — Tony's punch list should include a web check (added below) since the original plan's "web unaffected" claim no longer holds for this cycle by design.

This is **code-path analysis plus independent semantic/arithmetic verification**, not manual/runtime verification. QA did not launch the app on any platform.

### Cycle 3 Regression Check

| Area | Risk | Notes |
| --- | --- | --- |
| Auth / session / magic-link / PKCE | LOW | Not touched by diff. |
| Init order | LOW | Not touched by diff. |
| Platform parity (native vs. web) | LOW–MEDIUM | Unlike Cycles 1–2, this cycle's four `Transform.translate` wraps are **not** gated by `_kDemoBandVisible`/`kIsWeb`, so web now also shifts logo/email/pills up 50px each (the demo-button wrap remains native-only since the whole block is still `if (_kDemoBandVisible)`-gated). This is the intended, literal reading of Tony's instruction (no platform exemption was stated) but is a behavior change from the "web is byte-identical" invariant both prior cycles' plans relied on. Flagged for the punch list (web visual check added below); not a code defect. |
| PR #278 overflow safety (Flexible wrap on logo) | LOW | Structurally unaffected — `Transform.translate` is paint-only and cannot change the `SizedBox(height: availableHeight / 2)` / `Flexible` / `Align` bounds the logo lays out within. Independently re-run 20/20 passing on Test C. |
| Paint-level overlap (logo ↔ demo link) at compact viewports | **MEDIUM (flagged, non-blocking)** | Genuine, correctly-identified risk: demo link moves up 15px more than the logo, shrinking their Cycle-2 visual gap by 15px. At compact viewports (~800×600) where `BoxFit.contain` has already compressed the logo's slack toward zero, this could produce visual overlap. Cannot be caught by `RenderFlex`-overflow-based automated tests (Test C only asserts absence of overflow, not absence of paint overlap). This is the single most important item for Tony's manual punch list — see below. |
| Animation timing / intervals | LOW | Not touched — `Transform.translate` wraps the already-animated widget subtrees without altering controller/interval code. |
| Hit-testing / tap targets | LOW | `Transform` defaults to `transformHitTests: true`, so tap targets move with the visual position — no dead-zone regression expected. Not independently verified at runtime (requires a running app); flagged as a secondary punch-list check. |
| Controller/FocusNode disposal, `setState` after async gaps | LOW | Not touched — diff is confined to widget-tree wraps inside a single build method. |

Overall regression risk: **LOW**, with one **MEDIUM, explicitly flagged, non-blocking** paint-overlap risk that requires Tony's runtime confirmation before merge (see punch list item 1) and one **LOW–MEDIUM** platform-parity note (web is no longer byte-identical to prior cycles, by design of the literal instruction).

### Cycle 3 Database Safety

N/A — no DB/RLS/RPC/migration impact. Diff confirmed to touch no `supabase/**` or `database/**` files.

### Cycle 3 Analyzer Results

```
flutter analyze lib/features/auth/login_screen.dart
Analyzing login_screen.dart...
No issues found! (ran in 1.9s)
```

Independently re-run by QA; matches Engineer's reported Cycle 3 result.

### Cycle 3 Test Results

```
flutter test test/features/auth/login_screen_demo_button_test.dart
00:03 +3: All tests passed!
```

Independently re-run by QA (Tests A, B, C all pass).

Loop-stability check for Test C, independently re-executed by QA against the Cycle 3 code (20 iterations, each checked individually for "All tests passed"):

```
for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" ...; done
```

Result: 20/20 PASS, zero failures.

### Cycle 3 Diff Safety Review

- No secrets, API keys, or credentials found in the diff.
- No `TODO`/`FIXME`/`debugPrint(` within the diff hunks — `git diff HEAD -- lib/features/auth/login_screen.dart | grep -iE "TODO|FIXME|debugPrint\("` returned no matches. Note: the file contains pre-existing `debugPrint(...)` calls elsewhere (session-check/error-handling logging, unrelated lines) — outside the diff's hunks, untouched by this change, correctly not flagged.
- No leftover test scaffolding, no accidental deletions, no unrelated formatting churn — diff is confined to the four `Transform.translate` wraps and the doc-comment bullet described in `ENGINEER_REPORT.md`.

### Cycle 3 Change Budget Review

- No Cycle 3 Architect Plan/Change Budget exists — this is a direct owner-instruction cycle, not a new planning pass, per `ENGINEER_REPORT.md`.
- Cumulative diff vs. `HEAD` (`git diff --numstat`): 46 insertions, 12 deletions, net +34, spanning Cycles 1–3 in one uncommitted working tree (no intermediate commits exist to isolate Cycle 3 alone, same process limitation noted in the Cycle 2 record below). Reading the diff directly, the Cycle-3-attributable portion is exactly the four `Transform.translate` wrap blocks (~4-5 lines each with the explanatory comment) plus one 4-line doc-comment bullet — roughly +26 to +30 lines, 0 deletions, consistent with "wrap four existing call sites, do not remove anything."
- The zero-deletion pattern here is expected and does not trigger the "bug fix with zero deletions" Warning: this is not a root-cause bug fix (Cycle 1 already fixed the root cause and had real deletions); it is an additive, owner-directed paint-offset repositioning where nothing needed to be removed. `ENGINEER_REPORT.md` states this explicitly ("the owner instruction only calls for element repositioning, not spacer resizing").
- Expected new files: 0 — actual: 0.
- Expected new public classes/methods: 0 — actual: 0.
- Expected new dependencies: 0 — actual: 0.
- Expected new tests: 0 — actual: 0 (test file untouched, consistent with the original plan's off-limits list, which Tony's override does not touch).

### Cycle 3 Code Efficiency Review

- No new helpers, widgets, providers, notifiers, fields, or abstractions introduced. `Transform.translate` is a standard Flutter primitive already used in six other places across the codebase (`potential_gig_card.dart`, `hero_section.dart`, `original_song_screen.dart`, `setlist_picker_bottom_sheet.dart`, `scroll_animated_widget.dart`) — independently grepped by QA, confirming no pre-existing "shift by N px" helper/extension exists that this change should have reused instead. `ENGINEER_REPORT.md`'s claim of having searched and found none is corroborated.
- Four separate wrap sites for three distinct pixel amounts (50/65/50) is the minimum needed to satisfy three independently-specified move amounts without inventing an unrequested "shift everything below X" abstraction — reasonable, not over-engineered.
- No single-use `_buildX()` method added, no new `copyWith` entries, no hand-rolled loops/try-catch, no barrel file.
- File size/method size unaffected relative to prior cycles; no size-target crossing newly introduced.

No bloat findings.

### Cycle 3 Manual Verification Punch List (historical — superseded by Cycle 4 punch list above)

QA did not attempt any of these — cannot launch the app in this pipeline. Preserved for audit history only; Cycle 4's punch list above supersedes it for current merge decisions.

1. **[Priority — logo/demo-link overlap risk, flagged by Engineer, validated by QA]** `flutter run -d macos`, then resize the window down to a compact size (~800×600 client area) — the same viewport PR #278's overflow-safety mechanism and Test C target. **Expected:** the logo and the "Check out the demo band" link do **not** visually overlap or touch — there should still be a visible gap between the bottom of the logo image and the top of the demo-link text at this compact size. **If they visually touch or overlap:** this is the specific risk flagged in `ENGINEER_REPORT.md` — the 15px-tighter gap (demo link moves up 15px more than the logo) combined with `BoxFit.contain`'s logo-shrink at compact viewports. Do not merge if overlap is observed; report back for a follow-up cycle (e.g. reducing the demo link's offset, or reducing to 50px to match the logo).
2. Repeat step 1 on the smallest physical/simulated phone in your device matrix (e.g. `flutter run -d ios` on the smallest iPhone simulator available, in portrait). Same expected result: no visual overlap between logo and demo link.
3. At the default macOS window size (~1200×900) and on a typical mobile portrait viewport, confirm the overall vertical rebalancing reads correctly: logo, demo link, email field, and domain pills should all appear shifted upward relative to Cycle 2's positions, with the demo-link-to-email-field gap now visibly a bit larger than before (~27px vs. ~12px) and the domain-pills-to-login-button gap visibly larger (grew by 50px). Confirm this matches the intended visual outcome you asked for — if any relationship looks wrong, note which one for a fast follow-up.
4. `flutter run -d chrome` at any window size. **Expected:** the "Check out the demo band" link is still not visible (`_kDemoBandVisible == false` on web), but — **new for this cycle** — the logo, email field, and domain pills should now also appear shifted up ~50px on web relative to their Cycle 2 position, since none of those three wraps are conditioned on the web/native platform check. Confirm this is the outcome you want on web too; if you expected web to be unaffected, that needs a follow-up cycle to gate these wraps behind `!kIsWeb` or similar.
5. On macOS, tap into the email field to raise the keyboard/focus indicator. **Expected:** the logo still shrinks to 75% smoothly (existing behavior, unaffected by the new `Transform.translate` wrap); tapping/typing in the email field and tapping the domain pills still works correctly at their new (shifted-up) visual positions — confirms hit-testing follows the paint offset as expected.
6. Confirm the demo link and email field are still tappable at their new visual locations (not just visually present) — tap the demo link to confirm it still navigates into the demo flow, and tap/focus the email field to confirm the cursor lands in the field at its new position.
7. Optional but recommended: `flutter run -d android` on a physical device or emulator (Pixel 6 or similar) to confirm parity with the iOS/macOS observations above.

### Cycle 3 Issues Found

**Critical:** none.

**Warnings:**

- **`regression`** — This cycle's four `Transform.translate` wraps are not conditioned on `_kDemoBandVisible`/`kIsWeb`, so web layout is no longer byte-identical to Cycle 1/2 (logo/email/pills all shift up 50px on web now too). This is a literal, correct implementation of Tony's instruction as stated (no platform exemption was given), and is not a code defect — but it silently overturns an invariant both prior Architect/QA cycles explicitly relied on ("web is byte-identical"/"unaffected"). Flagged as a Warning rather than Critical because it is very likely the intended outcome of a direct, explicit owner instruction rather than an accident — but it must be confirmed via punch-list item 4 before merge, since if Tony actually only meant the native login screen, this needs a follow-up cycle to gate the wraps.

**Suggestions:**

- **`code-quality`** — As in Cycle 2, no formal Cycle 3 Architect Plan/Change Budget exists since this is direct owner instruction rather than a new planning pass. Not a blocker (the diff is small, single-file, single-method, and fully explained by `ENGINEER_REPORT.md`), but if further numeric-nudge cycles are anticipated, a one-paragraph Architect addendum per cycle would let future QA verify against an explicit budget rather than reconstructing rationale from the Engineer's report alone.
- **`code-quality`** — The Engineer's own flagged overlap risk (logo/demo-link at compact viewports) is exactly the kind of risk that would benefit from a fast, cheap, code-only guard if it turns out to be a real problem after Tony's punch-list check (e.g. clamping the demo link's upward offset so the gap never goes below a minimum, computed from the logo's rendered height) — not requested by Tony for this cycle, so not implemented, but worth keeping in mind if punch-list item 1 comes back positive for overlap.

---

## Cycle 2 Record (preserved for history)

### Cycle 2 Final Verdict

**APPROVED**

### Cycle 2 Validation Summary

Cycle 2 is an owner-feedback-driven refinement of the already-QA-approved Cycle 1 (see Cycle 1 record below, preserved verbatim in this same file). There is no new `ARCHITECT_PLAN.md` for Cycle 2 — Tony visually tested Cycle 1 on the running app and asked to move the demo button back up roughly halfway between its pre-fix and Cycle-1 positions; `ENGINEER_REPORT.md` (Cycle Number 2) documents this as the goal. QA validated the Cycle 2 diff against the original Architect Plan's scope constraints (single file, single method, Files Off-Limits, Change Budget rationale, DB/system-impact map) since those remain the governing constraints for what may change, and validated the Cycle 2 behavioral goal against Tony's own stated request as relayed in `ENGINEER_REPORT.md`.

The working tree contained exactly one uncommitted tracked change (`lib/features/auth/login_screen.dart`), confined entirely to `_buildContentCluster()` — the only method the original plan permits touching. Cycle 1's structural move (demo button re-parented into the outer `Column`, directly above `_buildEmailField()`) was preserved verbatim. Cycle 2's sole change was wrapping the logo's existing `Flexible` child in an `Align(alignment: const Alignment(0, 0.5), ...)` plus two doc/section-comment updates. Analyzer was clean on the modified file (independently re-run by QA), all three tests in `login_screen_demo_button_test.dart` passed (independently re-run by QA), and the Tier 1 loop-stability check (20 runs of Test C) was independently re-executed by QA with 20/20 passes. No secrets, debug artifacts, or out-of-scope changes were found. This was code-path/static analysis + headless `flutter_test` verification only — no runtime/device verification was performed, per QA's mandate; that was Tony's punch list.

### Cycle 2 Architect Scope Review

No new `ARCHITECT_PLAN.md` existed for Cycle 2 — this was an owner-feedback refinement, not a new architect-planned task. QA held the Cycle 2 diff to the original plan's governing constraints, which remained unchanged and unexpired:

- Diff touched exactly one file: `lib/features/auth/login_screen.dart`. Matched plan.
- The entire Cycle 2 change was confined to `_buildContentCluster()` — the plan's explicit Files-to-Modify scope ("do not reformat, retheme, restructure, or 'improve'" anything else in this file). Confirmed by diff: only the doc comment, one section-comment line, and the `Flexible(child: ...)` → `Flexible(child: Align(...))` wrap changed.
- `test/features/auth/login_screen_demo_button_test.dart` (Files Off-Limits) — confirmed untouched.
- No changes to `lib/main.dart`, `lib/app/**`, `demo_session_service.dart`, `auth_gate.dart`, `auth_confirm_screen.dart`, `pubspec.yaml`/`.lock`, `analysis_options.yaml`, `supabase/**`, `database/**`, `assets/images/**`, or any other `lib/features/**` file. All Files Off-Limits respected.
- Untracked pre-existing artifacts were leftovers from unrelated prior slugs, not created by this Engineer's work, and not part of the tracked diff — correctly out of scope for this review.

### Cycle 2 Completeness Check

`ENGINEER_REPORT.md`'s Cycle 2 task list (4 items) verified directly against the diff:

1. Cycle 1's structural move (demo button + trailing spacer relocated to the outer `Column`, directly above `_buildEmailField()`) preserved verbatim — confirmed, that block is unchanged from Cycle 1.
2. Inner `Column`'s sole child changed from `Flexible(child: _buildLogo(logoWidth: logoWidth))` to `Flexible(child: Align(alignment: const Alignment(0, 0.5), child: _buildLogo(logoWidth: logoWidth)))` — confirmed in diff.
3. `Layout contract:` doc comment and the `// === LOGO ===` section marker updated to describe the anchor-toward-bottom behavior instead of "centered" — confirmed, wording matches the described intent.
4. No other lines changed — confirmed; diff hunks are limited to the doc comment, the section marker, and the `Flexible`/`Align` wrap.

No partial implementation. No missing edge case relative to the Cycle 2 ask.

### Cycle 2 Behavior Verification

Cycle 2's mechanism was independently derived and checked against Flutter's `Align` layout semantics, not just taken on the Engineer's word:

- `Align`'s vertical offset for a bounded parent is `offset = (alignment.y + 1) / 2 * slack`, where `slack = parentHeight − childHeight`. At `Alignment(0, 0.5)`, `offset = 0.75 × slack` — i.e. 75% of the slack lands **above** the logo and 25% **below** it (between the logo and the demo button), versus a 50/50 split under Cycle 1's implicit centering.
- This halves the visible logo-to-button gap relative to Cycle 1 (25% of slack vs. 50%), which is a faithful, sound implementation of "move it up roughly halfway" — halfway back toward the pre-Cycle-1 (tightly-grouped) state without reverting Cycle 1's structural fix (button still grouped with the email field, not the branding cluster).
- `Align` does not alter the `maxHeight` bound handed down to `_buildLogo`'s `Image.asset(..., fit: BoxFit.contain)` — it fills the same bounded slot the bare `Flexible` previously gave the logo and only repositions the child within that slot. PR #278's overflow-safety mechanism (shrink-on-pressure via `BoxFit.contain`) is structurally unaffected. This was independently verified empirically as well: Test C (the 800×600 overflow invariant) passes on a fresh, independent 20-iteration run (below).
- `_kDemoBandVisible` gating, `_buildDemoButton()`/`_enterDemo` internals, `_buildLogo` internals (aside from being wrapped, not modified), and animation controllers (`_buttonOpacity`, `_logoShrinkController`, `_titleOpacity`, `_titleScale`) are untouched — confirmed by diff (no hunks outside the described lines).

This is **code-path analysis plus independent layout-math verification**, not manual/runtime verification. QA did not launch the app on any platform, consistent with mode rules.

### Cycle 2 Regression Check

| Area | Risk | Notes |
| --- | --- | --- |
| Auth / session / magic-link / PKCE | LOW | Not touched by diff. |
| Init order | LOW | Not touched by diff. |
| Platform parity (web vs native) | LOW | `_kDemoBandVisible` expression unchanged; web branch (`_kDemoBandVisible == false`) never renders the `Align`-wrapped block differently — the wrap is inside the always-rendered logo path, and its only effect is the logo's position within the upper-half box, not visibility. No web-specific diff. |
| PR #278 overflow safety (Flexible wrap on logo) | LOW | Preserved; `Align` receives the same bounded `maxHeight` the bare `Flexible` did and does not loosen or remove that bound. Test C (800×600 overflow check) re-run 20/20 passing by QA independently, confirming determinism under the new wrap. |
| Animation timing / intervals | LOW | Animation controller code not in diff; only the logo's static position within its already-bounded box changed. `Transform.scale`/`FadeTransition`/`ScaleTransition` continue to operate on the same child. |
| Controller/FocusNode disposal, `setState` after async gaps | LOW | Not touched — diff is confined to widget-tree structure inside a single build method. |

Overall regression risk: **LOW**.

### Cycle 2 Database Safety

N/A — plan states no DB/RLS/RPC/migration impact, and the diff confirms no `supabase/**` or `database/**` files touched.

### Cycle 2 Analyzer Results

```
flutter analyze lib/features/auth/login_screen.dart
Analyzing login_screen.dart...
No issues found! (ran in 2.8s)
```

Independently re-run by QA; matches Engineer's reported Cycle 2 result.

### Cycle 2 Test Results

```
flutter test test/features/auth/login_screen_demo_button_test.dart
00:03 +3: All tests passed!
```

Independently re-run by QA (Tests A, B, C all pass).

Loop-stability check for Test C (plan's Tier 1 item 5), independently re-executed by QA against the Cycle 2 code:

```
for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" > /tmp/qa_testc_$i.log 2>&1 || echo "FAILED run $i"; done
grep -L "All tests passed" /tmp/qa_testc_*.log
```

Result: 20/20 passed — no `FAILED` lines emitted, and `grep -L` (files *not* containing "All tests passed") returned zero files. Temp logs deleted after the check.

### Cycle 2 Diff Safety Review

- No secrets, API keys, or credentials found in the diff.
- No `TODO`/`FIXME`/`debugPrint(` within the diff hunks (`git diff -- lib/features/auth/login_screen.dart | grep -iE "TODO|FIXME|debugPrint\("` returned no matches). Note: the file itself contains pre-existing `debugPrint(...)` calls elsewhere (session-check and error-handling logging, lines ~123/387/394/401/409) — these are outside the diff's hunks, untouched by this change, and correctly not flagged.
- No leftover test scaffolding, no accidental deletions, no unrelated formatting churn — diff is confined to the exact hunks described in `ENGINEER_REPORT.md`.

### Cycle 2 Change Budget Review

- Original plan budget (`lib/features/auth/login_screen.dart`, −1 to +2 net) was written for Cycle 1 only; no Cycle 2 budget exists because there is no new Architect Plan for this owner-feedback cycle.
- Cumulative diff vs. `HEAD` (`git diff --numstat`): 24 insertions, 10 deletions, net **+14**. This is well outside the original Cycle-1-only budget in absolute terms, but the excess is fully attributable to Cycle 2's disclosed, narrow, owner-requested scope (one `Align` wrapper + `Alignment` constant + two doc/comment blocks) layered on top of the already-approved Cycle 1 diff — not undisclosed scope creep. `ENGINEER_REPORT.md` explicitly flags this attribution itself.
- QA could not independently re-derive the Engineer's claimed Cycle-1-vs-Cycle-2 line split (+10/−4 for Cycle 2 alone) because no commit checkpoint exists between the two cycles — everything is uncommitted in the same working tree, so `numstat` only ever compares current-file-vs-`HEAD`, not cycle-vs-cycle. This is a process limitation of the no-intermediate-commit workflow, not a discrepancy in the reviewed code; the full cumulative diff was read in its entirety and matches the described end state exactly.
- Expected new files: 0 — actual: 0.
- Expected new public classes/methods: 0 — actual: 0.
- Expected new dependencies: 0 — actual: 0.
- Expected new tests: 0 — actual: 0 (test file untouched, consistent with plan's stated rationale).

### Cycle 2 Code Efficiency Review

- No new helpers, widgets, providers, notifiers, fields, or abstractions introduced — the Cycle 2 change is a single stock `Align` widget wrap plus an `Alignment` constant; `Align` is Flutter's standard primitive for biasing a child within a bounded box, and `ENGINEER_REPORT.md` notes a search for an existing equivalent helper in `lib/` found none, which is plausible given the small surface area of this pattern.
- Rejected alternative (`Expanded`/`Spacer` siblings for flex-ratio control) is reasoned and correctly avoided — it would compete with the logo's `Flexible` for allocation and risk forcing it smaller at ordinary viewport sizes.
- No single-use `_buildX()` method added; no new `copyWith` entries; no hand-rolled loops, `try/catch`, or barrel files.
- File size / method size unaffected; no size-target crossing.

No bloat findings beyond the Change Budget note above.

### Cycle 2 Manual Verification Punch List (historical — superseded by Cycle 3 punch list above)

The following was Tony's punch list for Cycle 2, from the plan's owner-run Verification Plan reflecting the halfway-adjusted gap. QA did not attempt any of these steps. Preserved for audit history only; Cycle 3's punch list above supersedes it for current merge decisions.

1. Run `flutter run -d macos` (sign out first if you land on the app shell after Cycle 1's or Cycle 2's changes were previously tested).
2. Observe the login screen at the default window size (~1200 × 900). **Expected:** the gap between the logo and the "Check out the demo band" button is noticeably smaller than it was after Cycle 1 — roughly half of Cycle 1's gap — while still clearly larger than the original pre-fix gap (button was flush against the logo). The gap between the button and the "Email address" label should remain small (~12px), unchanged from Cycle 1.
3. Run `flutter run -d ios` (or an iOS simulator such as iPhone 15). **Expected:** same relative positioning as macOS — logo-to-button gap roughly halved vs. Cycle 1, button still adjacent to the email field.
4. Run `flutter run -d chrome` at any window size. **Expected:** the "Check out the demo band" link is still **not** visible (`_kDemoBandVisible == false` on web) — unaffected by this cycle.
5. On macOS, tap into the email field to raise the keyboard/focus indicator. **Expected:** the logo shrinks to 75% smoothly (existing behavior, unaffected by the `Align` wrap); the demo link stays anchored to the email field. Blur the field — logo returns to full size smoothly.
6. Resize the macOS window to a compact size (~800 × 600 client area). **Expected:** no "BOTTOM OVERFLOWED BY N PIXELS" banner appears at any point during the resize — this is the PR #278 overflow-safety check, now exercised through the added `Align` wrap.
7. Confirm the new gap "feels right" per your original halfway request — if it needs further nudging, the tunable value is a single `Alignment(0, y)` constant (`y` between 0 = Cycle 1's centered/large-gap look and 1 = fully bottom-anchored/near-zero-gap look); report a preferred `y` or a qualitative direction (tighter/looser) for a fast follow-up if not exactly right.
8. Optional but recommended: `flutter run -d android` on a physical device or emulator (Pixel 6 or similar). **Expected:** demo link position matches the iOS/macOS observation from step 2.

### Cycle 2 Issues Found

None Critical, none Warning.

- **Suggestion** (`code-quality`): No formal Cycle 2 Architect Plan / Change Budget exists for this refinement since it was driven directly by owner feedback rather than a new planning pass. The cumulative diff is small (net +14 lines, one file, one method) and fully explained by `ENGINEER_REPORT.md`, so this is not a blocker — but if further halfway-style visual nudges are anticipated, a lightweight Architect addendum (even a one-paragraph note) would let future QA cycles verify against an explicit budget instead of reconstructing rationale from the Engineer's report alone.

---

## Cycle 1 Record (preserved for history)

### Cycle 1 Final Verdict

**APPROVED**

### Cycle 1 Validation Summary

Branch `bug/demo-band-link-spacing` was checked out at `07ff1aab` (= `origin/main`, PR #278) at the time of Cycle 1 review, so `git diff HEAD` was equivalent to the plan's `git diff origin/main` check. The working tree contained exactly one uncommitted tracked change (`lib/features/auth/login_screen.dart`), matching the plan's Files to Modify list exactly. Analyzer was clean on the modified file, all three tests in `login_screen_demo_button_test.dart` passed, and the Tier 1 loop-stability check (20 runs of Test C) was independently re-executed by QA with 20/20 passes. No secrets, debug artifacts, or out-of-scope changes were found. This was code-path/static analysis + headless `flutter_test` verification only — no runtime/device verification was performed, per QA's mandate; that was Tony's punch list (also per the plan's Verification Plan, which explicitly classifies it as owner-run).

### Cycle 1 Outcome

All six Engineer Task Breakdown steps were completed and verified in the diff (inner Column reduced to single `Flexible(child: _buildLogo(...))` child; demo button + spacer re-parented into the outer Column immediately above `_buildEmailField()`; section comment and doc comment updated per plan wording). Change budget: 14 insertions / 12 deletions, net +2 (at the upper edge of the −1 to +2 budget but within it). No bloat findings. Full detail superseded by the Cycle 2 sections above; this record is retained only for audit history.
