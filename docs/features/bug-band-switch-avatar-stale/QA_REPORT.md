# QA Report

## Feature Slug
bug/band-switch-avatar-stale

## Feature Title
Band switch nav bar avatar intermittently shows stale (previous band's) image

## Final Verdict
**APPROVED**

## Validation Summary
Confirmed via `git diff` that the only change in `lib/features/bands/active_band_controller.dart` is the relocation of `await _persistBandId(band.id);` from the first statement to the last statement of `selectBand()` — verbatim match to Architect Plan §6/§14 and Engineer Report's description, with zero other lines touched. `flutter analyze` passes with 0 errors/warnings. Regression areas from Architect Plan §16 were validated via code-path analysis (re-reading the full modified method and its call sites) — this is **code-path analysis, not runtime-tested**; see Behavior Verification and the Tier 2 section below for an explicit statement of what could not be executed in this session.

## Architect Scope Review
- Scope adherence: compliant
- Files modified: as expected — only `lib/features/bands/active_band_controller.dart`
- Files off-limits: not touched — confirmed no changes to `band_avatar.dart`, `home_app_bar.dart`, `calendar_app_bar.dart`, `setlists_app_bar.dart`, `band_form_screen.dart`, `displayBandProvider`, or `ActiveBandState.==`/`hashCode`

## Completeness Check
- All Architect tasks implemented: yes
  - Task 1 (reorder `_persistBandId` call): confirmed exact match via diff inspection
  - Task 2 (`flutter analyze` clean): confirmed independently by QA (0 errors, 0 warnings)
  - Task 3 (no other file touched): confirmed via `git status`/`git diff` — only the one file modified
- Missing tasks: none

## Behavior Verification
- Validation method: **code-path analysis only** (see Tier 2 gap below)
- Result: matches expected. Re-read the full `selectBand()` body post-change (`active_band_controller.dart:320-335`) and confirmed:
  - `state = state.copyWith(activeBand: band)` and `ref.invalidate(displayBandProvider)` now execute synchronously, before any `await`, closing the identified async gap.
  - `_persistBandId`'s internal try/catch (including the private-browsing/web fallback debug logging at lines 239–244) is byte-for-byte unchanged — only its call site moved.
  - All downstream call sites of `selectBand()` (`home_screen.dart:173`, `calendar_screen.dart:166`, `app_shell.dart:318`, `no_band_shell.dart:712`, `setlists_screen.dart:419`, `notification_navigation_handler.dart:48`) are unmodified and still call it fire-and-forget (except `notification_navigation_handler.dart`, which awaits it — unaffected since `selectBand()`'s own `Future` still completes only after `_persistBandId` finishes).

## Regression Check
- Risk level: **LOW** (matches Architect Plan §13 assessment)
- Systems reviewed (code-path analysis): permissions re-fetch (`currentUserPermissionsProvider` invalidation — unchanged, same relative position), setlist-selection clearing (`selectedSetlistProvider.clear()` — unchanged), dashboard-tab navigation (`currentTabProvider.setTab()` — unchanged), gig/rehearsal reset-on-band-change (call-site logic untouched, not in this file), private-browsing/web `SharedPreferences`-unavailable fallback path (try/catch in `_persistBandId` unchanged, now simply invoked later)
- Regressions found: none identified via code-path analysis

## Database Safety
Not applicable — client-side Riverpod state ordering only, no RLS/RPC/migration involvement (confirmed, matches Architect Plan §7).

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings

## Test Results
Not run — no existing automated test covers `selectBand()` statement ordering, and the Architect plan did not require adding one (§18, out of scope).

## Diff Safety Review
- Secrets: none found
- Debug artifacts: none found — no new print statements, TODOs, or temporary flags; `dart format` drift not introduced
- Unrelated changes: none found — diff is exactly one line removed + one line added (the same statement, relocated)

## Tier 2 — Manual/Runtime Verification (Explicit Gap)

**Not performed**, disclosed explicitly per QA.md's precision-of-language requirement rather than claimed:

This session has shell (Bash) and file read/write access only. There is no UI-automation, device-interaction (tap/gesture), or frame-capture tooling available to drive a running build through the Tier 2 test steps or to visually observe per-frame rendering. Specifically **not executed**:
- POST-DEPLOY TEST 1 (baseline regression — visual header update on switch)
- POST-DEPLOY TEST 2 (15–20 rapid consecutive switches, stale-frame check)
- POST-DEPLOY TEST 3 (rapid double-tap race, settles on last-tapped band)
- POST-DEPLOY TEST 4 (cold-start restoration check)

`flutter devices` confirms build targets are available (macOS desktop, Chrome, a physical iOS device), but no tool in this session can perform the tap interactions or visual/frame-level observation these tests require — that requires a human tester on a running build.

This gap is weighed against: (a) the Architect Plan's own rollout strategy (§17) explicitly treats non-reproduction of this timing-dependent symptom in QA's environment as an acceptable condition for merge, given the bug's inherent timing-dependence; (b) Tier 1 fully passes; (c) the change is a single, minimal, low-risk statement reorder with no logic changes; (d) code-path analysis found no break in any regression area. On that basis this is not treated as a blocking gap, but it **is** a residual, undischarged verification item — a human should perform a quick manual smoke test (at minimum POST-DEPLOY TEST 1 and TEST 4) on a real device before or shortly after this merges to `main`.

## Issues Found
None

### Suggestions (optional)
1. Before or shortly after merging, have a human perform a quick manual smoke test on a device (at least baseline band-switch header update + cold-start restore) since Tier 2 could not be executed in this session — see Tier 2 gap above.
