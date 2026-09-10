# ENGINEER_REPORT — bug/demo-band-link-spacing

## Feature Slug

`bug/demo-band-link-spacing`

## Feature Title

"Check out the demo band" link sits too close to the logo on the login screen; should be positioned lower, closer to the Email field

## Cycle Number

3

## Goal

Owner-instruction-driven repositioning, not a new root-cause finding (no Architect re-pass needed per Tony). After visually testing the QA-approved Cycle 2 state, Tony gave this direct, explicit, numeric instruction:

> 1. Move the logo up 50px.
> 2. Move the "Check out the demo band" link up 65px.
> 3. Move the email field and email domain shortcuts up 50px.

Each element moves by its own distinct amount relative to its Cycle 2 rendered position (not relative to each other). Tony's instruction explicitly overrides the original Cycle 1 plan's "Files Off-Limits" restriction on `_buildEmailField()` / `_buildDomainPills()` / the `availableHeight / 2` split, but **only** for repositioning — no restyling, restructuring, renaming, or other changes to those widgets or the rest of `login_screen.dart`.

## Architect Tasks Completed (Cycle 3, owner-instruction scope)

Implemented as `Transform.translate` wraps at the call sites inside `_buildContentCluster()` — the cleanest, least invasive mechanism available, since it moves each element by paint offset only and does not touch any layout box size, `Flexible`/`Align` bound, or the `availableHeight / 2` split (all of which PR #278's overflow-safety mechanism and Test C depend on):

1. `_buildLogo(logoWidth: logoWidth)` (already wrapped in `Align(alignment: const Alignment(0, 0.5), ...)` from Cycle 2) is now also wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`.
2. `_buildDemoButton()` (in the outer `Column`'s `if (_kDemoBandVisible)` block, unchanged position from Cycle 1) is now wrapped in `Transform.translate(offset: const Offset(0, -65), ...)`.
3. `_buildEmailField()` is now wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`.
4. `_buildDomainPills(maxWidth: maxWidth)` is now wrapped in `Transform.translate(offset: const Offset(0, -50), ...)`.
5. Updated the `Layout contract:` doc comment with a new bullet documenting the Cycle 3 paint-only offsets. No other doc/section-comment wording from Cycle 1/2 was altered.
6. All existing spacers (`SizedBox(height: 12)` between the demo button/email field and between email field/domain pills, the outer `SizedBox(height: availableHeight / 2)`, the trailing 24px/40px spacers) are untouched — the owner instruction only calls for element repositioning, not spacer resizing.

Why `Transform.translate` and not adjusting spacers/`Align` offsets directly: each of the three moves is independent and by a different amount (50/65/50), and the email field + domain pills need to move together by the same amount while staying visually adjacent to each other (their existing 12px spacer between them is preserved). Adjusting the `SizedBox`/`Align` structural values instead would require re-deriving three different flex/alignment fractions against a variable `availableHeight`, which is fragile and harder to reason about than a fixed, explicit pixel offset per element — and it would risk perturbing the Cycle 2 `Alignment(0, 0.5)` logo-bias math that Test C's headless harness already validates. `Transform.translate` is paint-only (the same primitive already used elsewhere in this file for the keyboard-shrink `Transform.scale`), so it cannot change any `RenderFlex` size and cannot regress PR #278's overflow-safety mechanism.

## Files Created

None.

## Files Modified

- `lib/features/auth/login_screen.dart` — four `Transform.translate` wraps added inside `_buildContentCluster()` (logo, demo button, email field, domain pills), plus one doc-comment bullet. No other lines changed.

## Analyzer Results

```
flutter analyze lib/features/auth/login_screen.dart
Analyzing login_screen.dart...
No issues found! (ran in 2.7s)
```

## Test Results

```
flutter test test/features/auth/login_screen_demo_button_test.dart
00:03 +3: All tests passed!
```

All three tests (A, B, C) pass.

Re-ran the 20-iteration Test C loop-stability check per the owner's explicit request for this cycle:

```
for i in $(seq 1 20); do flutter test test/features/auth/login_screen_demo_button_test.dart --plain-name "Test C" || echo "FAILED run $i"; done
```

Result: 20/20 passed, zero `FAILED` lines emitted.

**Why this result is expected and not sufficient on its own:** Test C asserts no `RenderFlex` overflow at 800×600 with the demo button visible. `Transform.translate` never changes any widget's layout size or constraints — it repositions the already-laid-out render object at paint time only — so it is structurally impossible for this change to introduce a `RenderFlex` overflow. The 20/20 pass confirms that invariant held, exactly as expected. It does **not** by itself confirm the four moved elements don't visually overlap each other, because overlap-from-paint-offset is a different failure mode than layout overflow and `flutter_test`'s widget tests in this file do not assert on painted bounding boxes. See "Overflow/Overlap Risk Assessment" below — flagged per the owner's explicit request to not silently paper over this.

## Overflow/Overlap Risk Assessment (flagged per owner request — please review)

Because `Transform.translate` shifts paint position without changing the reserved layout space, moving each element up by a different amount changes the *visual* gap between adjacent elements without changing their *layout* gap. Working through the adjacent pairs where the move amounts differ:

- **Logo → demo button:** Cycle 2 biases the logo toward the bottom of its upper-half box (`Alignment(0, 0.5)`), leaving some slack between the logo's visual bottom and the demo button's original top. The logo moves up 50px and the demo button moves up 65px — since the demo button moves up *15px more* than the logo, the visual gap between them **shrinks by 15px** relative to Cycle 2. On a typical mobile-portrait or default-desktop-window viewport this slack was estimated at roughly 35–50px in the original Architect Plan's math, so a 15px reduction is unlikely to cause overlap there. **At compact viewports (e.g. the ~800×600 macOS window used in Test C / PR #278's overflow scenario), that slack shrinks toward zero as `BoxFit.contain` compresses the logo** — at the limit, the 15px shrinkage could cause the demo button to visually overlap the bottom of the logo image. This will not fail any automated test (it's a paint-level overlap, not a layout overflow) and needs a visual check.
- **Demo button → email field:** the demo button moves up 65px and the email field moves up 50px — since the demo button moves up *15px more* than the email field, the visual gap between them **grows by 15px** (from the existing 12px spacer to ~27px). No overlap risk here; if anything the gap widens.
- **Email field → domain pills:** both move up by the same 50px, so their existing 12px visual gap is unchanged.
- **Domain pills → login button:** only the pills moved (50px up); the login button did not move, so the visual gap **grows by 50px**. No overlap risk, but the pills now sit visually farther from the login button than in Cycle 2.

**Bottom line:** no automated test can fail from this change (layout sizes are untouched), but there is a genuine, non-zero visual-overlap risk between the logo and the demo link specifically at compact/small viewports, where Cycle 2's existing logo-to-button slack was already the tightest margin in the layout. This was not part of the original plan's verification surface (moving the email field/pills is new territory per the owner's note). **Recommend Tony specifically check the logo/demo-link relationship on the smallest viewport he tests** (e.g. resizing the macOS window down to ~800×600, and/or the smallest phone in his device matrix) in addition to the standard punch list, since this is the one place these three independent moves could plausibly touch.

## Code Efficiency/Bloat Check

- No new helpers, widgets, providers, methods, or fields introduced. `Transform.translate` is a standard Flutter primitive already used elsewhere in this same file (`Transform.scale` for the keyboard-shrink logo animation) — no new abstraction needed, and none was created.
- Searched for an existing "shift element by N px" helper/extension in `lib/` before writing this — none exists; `Transform.translate` is the correct built-in primitive for a paint-only offset and needed no wrapper.
- Four wrap sites for three distinct pixel amounts (logo 50, demo 65, email+pills 50 each) is the minimum number of `Transform.translate` calls that satisfies three independently-specified, differently-sized moves without introducing a shared "move everything below X by Y" abstraction that nothing else calls for.
- File size unaffected relative to the 500-line Dart target; `_buildContentCluster` remains a single-purpose layout method.

## Verification (manual steps performed)

- Re-read `_buildContentCluster` before and after the edit; confirmed each `Transform.translate` wraps only the existing widget call (`_buildLogo(...)`, `_buildDemoButton()`, `_buildEmailField()`, `_buildDomainPills(...)`) with no change to their internals, and confirmed the Cycle 2 `Align(alignment: const Alignment(0, 0.5), ...)` wrapper around the logo and all existing spacers/section structure are otherwise untouched.
- Confirmed via the diff that no `SizedBox`/`Align`/`mainAxisAlignment` value from Cycle 1/2 was altered — only new `Transform.translate` wraps and one doc-comment bullet were added.
- Ran `dart format` on the modified file — 0 changes (already formatted).
- Ran `flutter analyze` and `flutter test` (both above) plus the 20-iteration Test C loop — all green.
- Did not launch the app on any platform — per the original plan and prior cycles, visual confirmation across macOS/iOS/web remains an owner-run (Tony) punch-list item. Given the overlap risk flagged above, this cycle's punch-list verification is more load-bearing than prior cycles — recommend Tony specifically eyeball the logo/demo-link boundary at a compact viewport before merging.

## Deviations From Plan

Tony's Cycle 3 instruction explicitly authorizes touching `_buildEmailField()`/`_buildDomainPills()` call sites and moving elements that the original Cycle 1 `ARCHITECT_PLAN.md` marked off-limits — a deliberate, explicit override for this cycle only (repositioning via wrap, not restructuring the widgets themselves), as stated in the owner instruction. No other deviation.

## Blockers Encountered

None. See "Overflow/Overlap Risk Assessment" above for a flagged (non-blocking) visual risk that needs owner eyes at PR-test time, not an implementation blocker.

## Ready For QA

yes
