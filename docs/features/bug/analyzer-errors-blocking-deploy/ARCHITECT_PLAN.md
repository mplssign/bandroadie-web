# ARCHITECT_PLAN

**Feature:** `bug/analyzer-errors-blocking-deploy`  
**Type:** Bug  
**Branch:** `bug/analyzer-errors-blocking-deploy`  
**Architect:** Claude Sonnet 4.6  
**Date:** 2026-05-22

---

## 1. Feature Slug

`bug/analyzer-errors-blocking-deploy`

---

## 2. Problem Summary

`flutter analyze` fails with 35 errors across 11 files, aborting `./tools/deploy_web.sh` at the analyze gate. Two independent root causes:

1. **26 `duplicate_definition` errors** in 10 files — every lambda written as `(_, _)` (two parameters both named `_`) is a compile error under Dart 3, which promotes `_` to a reserved wildcard identifier. Duplicate parameter names in the same function signature are rejected.

2. **7 type errors** in `calendar_controller.dart` — `Future.wait([f1, f2, f3])` with three futures of different generic types (`Future<List<Gig>>`, `Future<List<Rehearsal>>`, `Future<List<BlockOut>>`) forces Dart's type inference to widen to `Future<List<Object>>`. All downstream operations on `results[0..2]` then fail because `Object` has no `.map()`, no typed `List` operations, and no `.date` accessor. The `gig.dart` / `rehearsal.dart` imports are flagged unused as a symptom of the same problem (the types never appear in a typed context).

Both categories were introduced by the `bug/potential-rehearsal-availability-nav` branch and landed on `main`.

---

## 3. Root Cause

### Root Cause A — Dart 3 wildcard `_` restriction (26 errors, 10 files)

**Confidence: HIGH** — confirmed by direct code inspection.

In Dart 3, `_` is a reserved wildcard. A function parameter named `_` is legal once per signature; naming two parameters `_` in the same signature (`(_, _)`) is `duplicate_definition`. Every affected site is a two-argument callback (Riverpod `.when(error:)` or `ListView.separated(separatorBuilder:)`) where both parameters are discarded.

### Root Cause B — `Future.wait` type inference widening (7 errors, 1 file)

**Confidence: HIGH** — confirmed by direct code inspection.

`Future.wait<T>(Iterable<Future<T>> futures)` is a homogeneous API. Passing three futures with three distinct element types causes Dart to infer `T = Object`, yielding `Future<List<Object>>`. The three indexed extractions (`results[0]`, `results[1]`, `results[2]`) are therefore typed `Object`, not their intended `List<Gig>`, `List<Rehearsal>`, `List<BlockOut>`. All subsequent operations on those variables fail the analyzer.

---

## 4. Reference Docs Consulted

No domain reference docs apply to this bug. The fix is purely a Dart type system correction. Checked `docs/reference/` — no Dart/analyzer reference folder exists. No domain reference docs applicable.

---

## 5. Existing System Analysis

### `(_, _)` pattern — Riverpod `.when()` callbacks

All 26 occurrences follow the same shape:

```dart
someProvider.when(
  data: (value) => ...,
  loading: () => ...,
  error: (_, _) => someDefault,
);
```

The `error:` callback signature is `T Function(Object error, StackTrace stackTrace)`. Both parameters are intentionally ignored. Renaming the second `_` to `__` makes the two identifiers distinct without changing behavior. The `separatorBuilder: (_, _)` occurrence in `pause_screen.dart` is the same pattern: `(BuildContext, int)` callback where both are unused.

### `Future.wait` type widening — `calendar_controller.dart`

`_loadEventsForBand()` fires three concurrent fetches:

```dart
final results = await Future.wait([
  _gigRepository.fetchGigsForBand(bandId),       // Future<List<Gig>>
  _rehearsalRepository.fetchRehearsalsForBand(bandId), // Future<List<Rehearsal>>
  _blockOutRepository.fetchBlockOutsForBand(bandId),   // Future<List<BlockOut>>
]);
// results: List<Object>

final gigs = results[0];      // Object — should be List<Gig>
final rehearsals = results[1]; // Object — should be List<Rehearsal>
final blockOuts = results[2];  // Object — should be List<BlockOut>
```

The fan-out/fan-in pattern — assigning each future to a typed variable and then awaiting them in sequence — preserves concurrent I/O while restoring type inference. All three HTTP requests are in-flight simultaneously because futures start executing at creation time (not at `await`). Only the join point is sequential, which is functionally identical to `Future.wait`.

---

## 6. Proposed Solution

### Fix A: Replace all `(_, _)` with `(_, __)` (10 files)

Rename the second parameter from `_` to `__` (double underscore). `__` is a valid Dart identifier, is conventionally understood as "also ignored", and makes the two parameters syntactically distinct. This is the minimal change — one character per occurrence.

No logic change. Lambda bodies are untouched.

### Fix B: Replace `Future.wait` block with typed fan-out in `calendar_controller.dart`

Replace:

```dart
final results = await Future.wait([
  _gigRepository.fetchGigsForBand(bandId),
  _rehearsalRepository.fetchRehearsalsForBand(bandId),
  _blockOutRepository.fetchBlockOutsForBand(bandId),
]);

if (ref.read(activeBandIdProvider) != bandId) return;

final gigs = results[0];
final rehearsals = results[1];
final blockOuts = results[2];
```

With:

```dart
final gigsFuture = _gigRepository.fetchGigsForBand(bandId);
final rehearsalsFuture = _rehearsalRepository.fetchRehearsalsForBand(bandId);
final blockOutsFuture = _blockOutRepository.fetchBlockOutsForBand(bandId);

final gigs = await gigsFuture;
final rehearsals = await rehearsalsFuture;
final blockOuts = await blockOutsFuture;

if (ref.read(activeBandIdProvider) != bandId) return;
```

Key points:

- All three futures are created (and therefore started) before the first `await` — parallel I/O is preserved.
- The race guard moves to after all three awaits complete (unchanged semantics — the original guard was after `Future.wait` returned, which is also after all three complete).
- `gigs`, `rehearsals`, `blockOuts` are now inferred as `List<Gig>`, `List<Rehearsal>`, `List<BlockOut>` respectively.
- The `gig.dart` and `rehearsal.dart` imports are retained — they are needed by `CalendarEvent.fromGig`, `CalendarEvent.fromRehearsal`, and the now-typed variables.

---

## 7. Database Impact

**Not applicable.** This is a pure Dart/Flutter source change. No migrations, RPC functions, RLS policies, or triggers are touched.

---

## 8. Flutter Architecture Changes

- No providers added or removed.
- No repositories modified.
- No state shape changed.
- No widget tree changed.
- `calendar_controller.dart` internal fetch implementation only — public API (`loadEvents`, `invalidateAndRefresh`, `CalendarState`) is unchanged.

---

## 9. Files to Create

**None.**

---

## 10. Files to Modify

| File                                                             | Change                                                                                         |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `lib/features/shell/app_shell.dart`                              | Replace `(_, _)` → `(_, __)` at lines 82, 127, 330 (3 occurrences)                             |
| `lib/features/calendar/calendar_screen.dart`                     | Replace `(_, _)` → `(_, __)` at lines 169, 237, 266, 271 (4 occurrences)                       |
| `lib/features/calendar/calendar_tab_content.dart`                | Replace `(_, _)` → `(_, __)` at lines 98, 219, 249 (3 occurrences)                             |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`        | Replace `(_, _)` → `(_, __)` at line 162 (1 occurrence)                                        |
| `lib/features/calendar/calendar_controller.dart`                 | Replace `Future.wait` block with typed fan-out; retain `gig.dart` and `rehearsal.dart` imports |
| `lib/features/home/home_screen.dart`                             | Replace `(_, _)` → `(_, __)` at lines 197, 212, 248, 289, 294, 301 (6 occurrences)             |
| `lib/features/setlists/new_setlist_screen.dart`                  | Replace `(_, _)` → `(_, __)` at line 800 (1 occurrence)                                        |
| `lib/features/setlists/setlists_screen.dart`                     | Replace `(_, _)` → `(_, __)` at lines 557, 728 (2 occurrences)                                 |
| `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart` | Replace `(_, _)` → `(_, __)` at line 377 (separatorBuilder, 1 occurrence)                      |
| `lib/features/shell/no_band_shell.dart`                          | Replace `(_, _)` → `(_, __)` at line 55 (1 occurrence)                                         |
| `lib/features/bands/band_form_screen.dart`                       | Replace `(_, _)` → `(_, __)` at lines 541, 1944, 2177, 2182 (4 occurrences)                    |

**Total: 11 files modified, 26 wildcard renames + 1 Future.wait refactor.**

---

## 11. Files Off-Limits

| File                                    | Reason                               |
| --------------------------------------- | ------------------------------------ |
| `lib/main.dart`                         | Initialization order must not change |
| `lib/app/services/supabase_client.dart` | Auth/config — untouched              |
| Any file not listed in §10              | No other files require modification  |

---

## 12. System Impact Map

| System                                 | Impact                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------- |
| Gigs                                   | Unaffected — logic unchanged                                                       |
| Rehearsals                             | Unaffected — logic unchanged                                                       |
| Setlists / Catalog                     | Unaffected — logic unchanged                                                       |
| Members / RBAC                         | Unaffected — logic unchanged                                                       |
| Auth / Session                         | Unaffected                                                                         |
| Routing                                | Unaffected                                                                         |
| Notifications                          | Unaffected                                                                         |
| Calendar                               | Unaffected — controller public API unchanged, internal fetch parallelism preserved |
| Platform (iOS / Android / Web / macOS) | All platforms benefit; web deploy is unblocked                                     |

---

## 13. Regression Risk

**LOW**

Rationale:

- Every `(_, _) → (_, __)` change is a mechanical identifier rename. Lambda bodies are byte-for-byte identical. The error callbacks return the same default values as before.
- The `Future.wait` → fan-out change preserves parallel I/O. All three futures start before the first `await`. The race guard semantics are identical (checked after all three complete). No data is lost or reordered.
- No auth, routing, state shape, provider graph, or database is touched.
- Zero cross-feature side effects.

---

## 14. Engineer Task Breakdown

Execute in order. Each task is independently verifiable.

| #   | Task                                                                                 | File(s)                                                          | Verification                                                                    |
| --- | ------------------------------------------------------------------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1   | Create branch `bug/analyzer-errors-blocking-deploy` from `main`                      | —                                                                | `git branch --show-current` → `bug/analyzer-errors-blocking-deploy`             |
| 2   | Replace all `(_, _)` → `(_, __)` in `app_shell.dart` (3 occurrences)                 | `lib/features/shell/app_shell.dart`                              | Search file for `(_, _)` — zero results                                         |
| 3   | Replace all `(_, _)` → `(_, __)` in `calendar_screen.dart` (4 occurrences)           | `lib/features/calendar/calendar_screen.dart`                     | Search file for `(_, _)` — zero results                                         |
| 4   | Replace all `(_, _)` → `(_, __)` in `calendar_tab_content.dart` (3 occurrences)      | `lib/features/calendar/calendar_tab_content.dart`                | Search file for `(_, _)` — zero results                                         |
| 5   | Replace all `(_, _)` → `(_, __)` in `add_block_out_drawer.dart` (1 occurrence)       | `lib/features/calendar/widgets/add_block_out_drawer.dart`        | Search file for `(_, _)` — zero results                                         |
| 6   | Replace `Future.wait` block with typed fan-out in `calendar_controller.dart`         | `lib/features/calendar/calendar_controller.dart`                 | `gigs`, `rehearsals`, `blockOuts` have correct inferred types; imports retained |
| 7   | Replace all `(_, _)` → `(_, __)` in `home_screen.dart` (6 occurrences)               | `lib/features/home/home_screen.dart`                             | Search file for `(_, _)` — zero results                                         |
| 8   | Replace all `(_, _)` → `(_, __)` in `new_setlist_screen.dart` (1 occurrence)         | `lib/features/setlists/new_setlist_screen.dart`                  | Search file for `(_, _)` — zero results                                         |
| 9   | Replace all `(_, _)` → `(_, __)` in `setlists_screen.dart` (2 occurrences)           | `lib/features/setlists/setlists_screen.dart`                     | Search file for `(_, _)` — zero results                                         |
| 10  | Replace `separatorBuilder: (_, _)` → `(_, __)` in `pause_screen.dart` (1 occurrence) | `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart` | Search file for `(_, _)` — zero results                                         |
| 11  | Replace all `(_, _)` → `(_, __)` in `no_band_shell.dart` (1 occurrence)              | `lib/features/shell/no_band_shell.dart`                          | Search file for `(_, _)` — zero results                                         |
| 12  | Replace all `(_, _)` → `(_, __)` in `band_form_screen.dart` (4 occurrences)          | `lib/features/bands/band_form_screen.dart`                       | Search file for `(_, _)` — zero results                                         |
| 13  | Run `flutter analyze`                                                                | All files                                                        | Output: `No issues found!` or 0 errors                                          |
| 14  | Commit                                                                               | All modified files                                               | `git log --oneline -1` shows `fix(analyzer): ...` commit                        |

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (no database changes required for this bug)

This bug has no database component. Tier 1 verification is therefore:

```bash
# Verify no (_, _) patterns remain in any lib/ Dart file
grep -r "(_, _)" lib/ --include="*.dart"
# Expected: no output (zero matches)

# Run analyzer
flutter analyze
# Expected: "No issues found." or exit code 0
```

These checks are runnable immediately after implementation with zero schema changes.

### Tier 2 — Post-deployment

No database changes. Post-deployment verification:

```bash
# Confirm web build proceeds past the analyze gate
./tools/deploy_web.sh
# Expected: analyze step passes; build proceeds to completion
```

Manual smoke test after deploy:

- Load app in browser — calendar tab renders without errors
- Switch band — calendar reloads correctly (fan-out race guard intact)
- Setlists, Home, Band settings screens render without runtime errors
