# QA Report

## Feature Slug

`setlist-repository-rpc-wrapper-duplication`

## Feature Title

Consolidate duplicated updateSong*Override/clearSong*Override RPC wrappers in setlist_repository.dart

## Cycle Number

3

## Final Verdict

APPROVED

## Validation Summary

Independent cycle-3 QA confirmed the uncommitted implementation matches the Architect plan. Review covered the full working-tree diff against `HEAD`, all 11 rewritten wrappers, both new private helpers, both dead-method deletions, scope and budget constraints, analyzer output, and the full test suite. Verification of wrapper behavior was static code-path analysis; no app instance, simulator, device, browser, or production service was launched.

Regression risk: **MEDIUM**, matching the plan. The refactor changes 11 metadata mutation bodies simultaneously and lacks direct repository unit coverage, but preserves public signatures and confines shared behavior to two private helpers.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all use slug `setlist-repository-rpc-wrapper-duplication`; Engineer report is cycle 3.
- Tracked implementation changes are limited to `lib/features/setlists/setlist_repository.dart` and `lib/features/setlists/setlist_detail_controller.dart`.
- No imports, dependencies, public APIs, providers, platform code, configuration, tests, Supabase migrations, or Edge Functions changed.
- Exactly two planned private helpers were added. No unapproved architecture or unrelated formatting churn was found.

## Completeness Check

All 15 Architect tasks are complete. Both helpers exist in the specified location, all 11 methods are thin wrappers, `debugFetchSongsRaw` and `debugSmokeTest` were deleted, and neither dead symbol remains in `lib/` or `test/`.

## Behavior Verification

Static side-by-side diff and code-path analysis confirmed:

- All six RPC-first update wrappers use `update_song_metadata` with the complete 11-key parameter map and the correct single non-null value or title/artist pair.
- All three clear wrappers use `clear_song_metadata` with only `p_song_id`, `p_band_id`, and their correct `p_clear_*: true` parameter. Their direct fallback maps set the matching column to `null`.
- All direct fallback updates retain `.eq('id', songId)` and the pre-refactor column/value expression.
- All public signatures, requiredness, early returns, validation conditions, and `ArgumentError` messages are unchanged.
- Helper 1 checks `{success: false}`, maps PGRST203 to `Exception('Server configuration error. Please contact support.')` for the eight historical handlers, falls back only for PGRST202/42883, and rethrows other RPC exceptions.
- `updateSongTitleArtist` retains its null/null early return, conditional direct fallback map, explicit `handlePgrst203: false`, and raw PGRST203 passthrough. It does not provide an exception mapper.
- `updateSongTuningOverride` computes `tuningToDbEnum(tuning) ?? tuning` and `isLegacyEnumSupported(tuning)` before delegation, uses `dbTuning` on both paths, and maps only unhandled RPC-path enum exceptions. It has no wrapper-level catch, so fallback exceptions remain unclassified.
- YouTube and Lyrics remain direct-first and fall back only for code 42501 or a message containing `policy`.
- YouTube explicitly uses `checkRpcResultPayload: false` and does not capture or inspect the fallback RPC payload. Lyrics explicitly uses `true` and preserves `Exception(result['error'] ?? 'Unknown error')` on a failed payload.
- The only diagnostic change is the plan-authorized consolidation into `kDebugMode`-gated helper logging. Persisted state and surfaced exception types/messages are unchanged.

## Regression Check

- Setlists: **MEDIUM**. All affected metadata paths were statically checked; existing automated tests pass. Runtime UI persistence remains owner-run.
- Legacy `NULL band_id` songs/RLS bypass: **MEDIUM**. RPC-first and direct-first fallback ordering, RPC names, parameter maps, and fallback conditions are preserved in code.
- Gigs, rehearsals, Catalog logic, members, auth/session, routing, notifications, deep links, Firebase/init order, and platform parity: **LOW**. No controlling code or call sites changed.
- Controller lifecycle, FocusNode disposal, async `setState`, and rebuild frequency: **LOW**. The only controller change is deletion of an unreachable zero-caller debug method.

## Database Safety

Not applicable. `git diff -- supabase/` is empty. No migration, RPC definition/signature, RLS policy, grant, or SECURITY DEFINER function changed, so branch migration application and privilege probes are not required.

## Analyzer Results

`flutter analyze`: **PASS**. No issues found at any severity.

## Test Results

`flutter test`: **PASS**. 284 tests passed with zero failures.

The Engineer report recorded 296 tests in its earlier run; the independent cycle-3 run discovered 284 and completed successfully. This count difference does not indicate a failing or skipped named plan test in the current suite output.

## Diff Safety Review

- `git diff --check`: clean.
- No likely secrets or credentials were added.
- No `TODO` or `FIXME` was added.
- Added `debugPrint` calls are confined to the two plan-required helpers and are all gated by `kDebugMode`; no smoke-test/debug-only symbols remain.
- No accidental deletion, test scaffolding, Supabase change, or out-of-scope tracked file was found.

## Change Budget Review

- `setlist_repository.dart`: 293 additions, 798 deletions, net **-505**; planned net range **-500 to -700**.
- `setlist_detail_controller.dart`: 0 additions, 13 deletions, net **-13**; planned net range **-11 to -13**.
- Tracked implementation total: 293 additions, 811 deletions, net **-518**; planned total net range **-511 to -713**.
- Exactly two private methods and no new public class, public method, dependency, import, or implementation file were added.

Actual changes are within budget. The repository remains over the general file-size target, with the Engineer report's required justification that splitting it is explicitly outside this refactor's scope.

## Code Efficiency Review

Independent searches across `lib/` found no pre-existing equivalent to either new helper. The helpers serve nine and two wrappers respectively; neither is a single-use abstraction. No new provider, notifier, fetch layer, unused field/parameter, hand-rolled collection substitute, barrel file, future-use flag, or single-call wrapper was introduced.

## Manual Verification Punch List

Setup: build the branch to a real iOS device or Simulator (`./run.sh <device-id>`). Log in as a real user. Open a setlist with at least one song.

1. Tap the song's BPM badge. Set BPM = 123. Save. Reload the setlist (pull to refresh or navigate away and back). **Expected:** BPM displays as 123.
2. Tap BPM badge again. Clear the value (empty input or explicit clear action). Save. Reload. **Expected:** BPM shows as unset.
3. Tap the tuning badge. Pick "Half-Step Down". Save. Reload. **Expected:** tuning shows as "Half-Step Down".
4. Tap tuning badge again. Pick "None" (clear). Save. Reload. **Expected:** tuning shows as unset.
5. Tap the musical-key badge. Pick "Em". Save. Reload. **Expected:** key shows as Em.
6. Tap key badge again. Clear. Save. Reload. **Expected:** key shows as unset.
7. Tap the duration display, if editable in this UI, set to 3:30 (210s). Save. Reload. **Expected:** duration shows 3:30.
8. Open the song details bottom sheet. Change title, artist, and notes in one save. **Expected:** all three persist after reload.
9. In song details, add a YouTube URL to links. Save. **Expected:** link persists after reload.
10. In song details, add lyrics text. Save. **Expected:** lyrics persists after reload.
11. Throughout the above, watch for any snackbar error, red overlay, or unexpected app reload. **Expected:** none.

If any step fails, Tony reverts the PR and re-files the failing step's expected-vs-actual back to Architect.

The PGRST202/42883 direct-fallback path is intentionally not exercised against production or the PR preview because doing so would require removing an RPC. Its verification is limited to the static equivalence review above.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.

No findings in categories `root-cause-diagnosis`, `implementation-gap`, `regression`, `database-safety`, `code-quality`, or `out-of-scope`.