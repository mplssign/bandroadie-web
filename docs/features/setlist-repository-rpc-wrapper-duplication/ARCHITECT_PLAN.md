# ARCHITECT_PLAN — bug/setlist-repository-rpc-wrapper-duplication

## Feature Slug

`setlist-repository-rpc-wrapper-duplication`

## Feature Title

Consolidate duplicated updateSong*Override/clearSong*Override RPC wrappers in setlist_repository.dart

## Problem Summary

`lib/features/setlists/setlist_repository.dart` (currently 4,454 lines) contains 11 public metadata-mutation methods whose bodies are structurally near-identical, ~85 lines each. The Feature Input frames this as tech-debt cleanup rather than a user-visible bug: there is no reproduction path a user can walk through, and QA's job is to confirm byte-for-byte identical runtime behavior at every call site, not to test new behavior.

In addition, this file carries a debug-only smoke-test method `debugFetchSongsRaw()` (~line 764) whose only caller is `SetlistDetailNotifier.debugSmokeTest()` in `setlist_detail_controller.dart` (~line 858), which itself has zero callers anywhere in `lib/` or `test/`. Both are fully unreachable production code and safe to remove together.

Combined, this is ~700–900 lines of duplicated and dead code sitting on top of a Supabase RPC (`update_song_metadata`) that has already been redefined by 13 separate migrations, two of them explicit rollbacks. Consolidating the Dart side doesn't fix the RPC's churn history, but it removes the maintenance-cost half of the problem so a future RPC-contract change becomes a one-place edit instead of an eight-place hunt.

## Root Cause

**Confidence: HIGH.** Directly verified by reading the method bodies:

- **Pattern A — RPC-first, direct-fallback** (6 methods, ~90 lines each): `updateSongBpmOverride` (line 1527), `updateSongDurationOverride` (line 1845), `updateSongTuningOverride` (line 1940), `updateSongNotes` (line 2059), `updateSongTitleArtist` (line 2296), `updateSongMusicalKey` (line 2378). Each calls `supabase.rpc('update_song_metadata', params: {…10 named params, 9 of them `null`…})`, then on `PGRST203` throws a generic "Server configuration error" exception, on `PGRST202`/`42883` falls back to `supabase.from('songs').update({<field>: <value>}).eq('id', songId)`.
- **Pattern B — clear-RPC-first, direct-fallback** (3 methods, ~75 lines each): `clearSongBpmOverride` (line 1618), `clearSongTuningOverride` (line 1693), `clearSongMusicalKeyOverride` (line 1768). Each calls `supabase.rpc('clear_song_metadata', params: {'p_song_id': …, 'p_band_id': …, 'p_clear_<field>': true})`, then on `PGRST203` throws the same generic exception, on `PGRST202`/`42883` falls back to `supabase.from('songs').update({<field>: null}).eq('id', songId)`.
- **Pattern C — direct-first, RPC-RLS-fallback** (2 methods, ~65 lines each): `updateSongYoutubeLinks` (line 2151), `updateSongLyrics` (line 2222). Each calls `supabase.from('songs').update({<field>: <value>}).eq('id', songId)` DIRECTLY FIRST; only on `PostgrestException` with code `42501` or message containing `'policy'` does it fall back to `supabase.rpc('update_song_metadata', …)`. This is the INVERTED control flow from Patterns A/B.

The debug method: `SetlistRepository.debugFetchSongsRaw` (lines 764–836) is called only by `SetlistDetailNotifier.debugSmokeTest` in `setlist_detail_controller.dart` (lines 858–869). A workspace grep confirms `debugSmokeTest` has no callers in `lib/` or `test/`.

## Existing System Analysis

### Deltas between the Feature Input and the actual code

Per the Architect guardrail "trust the code and note the discrepancy," recording these:

1. **Method naming.** The Feature Input lists `updateSongMusicalKeyOverride` among the 8 update methods. The actual method is named `updateSongMusicalKey` (no "Override" suffix). Its clear counterpart is correctly named `clearSongMusicalKeyOverride`. The plan uses the real name throughout.
2. **Control-flow pattern for two of the eight update methods.** The Feature Input's Summary asserts every one of the 8 update methods "calls `supabase.rpc('update_song_metadata', ...)`" as its primary path. That is TRUE for 6 of them (BPM, Duration, Tuning, Notes, TitleArtist, MusicalKey) and INVERTED for the other 2 (YoutubeLinks, Lyrics). Ignoring this would silently swap the RLS-fallback semantics for those two paths.
3. **`debugFetchSongsRaw` call-site count.** The Feature Input's Summary says "no call sites anywhere in the app." Grep shows one call from `setlist_detail_controller.dart:865` (inside `debugSmokeTest`). The Feature Input's Additional Context §(3) already asks QA to "confirm no remaining reference to `debugFetchSongsRaw` anywhere in `lib/` or `test/` before deleting it" — this plan honors that by deleting `debugSmokeTest` as part of the same pass so no reference is left dangling.
4. **Referenced audit doc missing.** The Feature Input cites `docs/reference/audits/OPTIMIZATION_AUDIT_2026-09-10.md`. That file does not exist in the repo; `docs/reference/audits/` contains only `ICON_AUDIT_AND_LUCIDE_MIGRATION.md` and `CODEBASE_AUDIT.md`. Diagnosis was validated directly against the code, so the missing doc does not block this work — but Manager may want to know a source citation is broken.

### Special per-method behaviors that must be preserved

- **`updateSongTuningOverride`**: applies `tuningToDbEnum(tuning) ?? tuning` normalization BEFORE calling the RPC (uses `tuning_helpers.dart`), and passes `dbTuning` to both the RPC and the direct fallback. Has an extra classification branch that inspects a caught PostgrestException with `isEnumError && !isLegacySupported` and throws a tuning-specific exception (`Exception('This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.')`).
- **`updateSongTuningOverride` isEnumError scoping (verified at lines 2019–2035)**: pre-refactor, the isEnumError classification is inside the `on PostgrestException catch (e)` block, AFTER the `PGRST203` and `PGRST202`/`42883` branches (each of which throws or `return;`s before falling through). Consequently the classification fires ONLY on RPC-path PostgrestExceptions with codes not in `{PGRST203, PGRST202, 42883}`. It NEVER fires on PostgrestExceptions thrown by the fallback `supabase.from('songs').update(...)` call inside the `PGRST202`/`42883` branch: a `throw` from inside a catch handler propagates out of the try/catch entirely, and Dart's sibling-catch semantics forbid the outer `catch (e)` from re-catching. Any refactor that puts the isEnumError classification in a wrapper-level outer catch around the helper call would incorrectly classify fallback-path exceptions too, silently changing observable behavior. Helper 1 must expose an RPC-path-only classification hook; see §Proposed Solution.
- **`updateSongTitleArtist`**: has an early-return `if (title == null && artist == null) return;`. Its direct-fallback map is conditionally built with `if (title != null) updates['title'] = title;` and `if (artist != null) updates['artist'] = artist;`.
- **`updateSongTitleArtist` PGRST203 passthrough (verified in code lines 2296–2385)**: this is the ONLY one of the 9 Pattern-A/B methods that has NO `if (e.code == 'PGRST203')` branch. When `update_song_metadata` returns PGRST203 today, the raw `PostgrestException` is `rethrow`-n unmodified to the caller (via the generic `PostgrestException` else-branch). The other 8 methods (`updateSongBpmOverride`, `updateSongDurationOverride`, `updateSongTuningOverride`, `updateSongNotes`, `updateSongMusicalKey`, `clearSongBpmOverride`, `clearSongTuningOverride`, `clearSongMusicalKeyOverride`) DO intercept PGRST203 and throw `Exception('Server configuration error. Please contact support.')`. Both behaviors — the 8-method conversion AND the 1-method raw rethrow — are required to be preserved byte-for-byte per the Feature Input's pure-refactor contract. Helper 1 must be designed to serve both with a per-call switch; see §Proposed Solution.
- **Pattern C RPC-result-payload asymmetry (verified at lines 2151–2220 and 2222–2293)**: the two Pattern C methods disagree on whether the RPC fallback's return value is inspected.
  - `updateSongYoutubeLinks` calls `await supabase.rpc('update_song_metadata', params: {…})` in its fallback WITHOUT capturing the result. If the RPC returns `{success: false, error: '…'}`, no exception is thrown and the caller believes the update succeeded.
  - `updateSongLyrics` captures `final result = await supabase.rpc('update_song_metadata', params: {…})` and, when `result is Map && result['success'] == false`, throws `Exception(result['error'] ?? 'Unknown error')`.
  A uniform helper that always performs the result-payload check would introduce a NEW exception path into `updateSongYoutubeLinks` (which pre-refactor swallows the failure). Helper 2 must therefore expose a per-call switch that controls whether the result payload is inspected; see §Proposed Solution. Engineer's Cycle 2 stop-report correctly flagged this contradiction against the earlier plan.
- **`updateSongNotes` / `updateSongYoutubeLinks` / `updateSongLyrics` / `updateSongTitleArtist`**: no `setlistId` parameter (they're purely global-song mutations), while `updateSong{Bpm,Duration,Tuning}Override` and all three `clearSong*Override` methods DO accept `setlistId` even though they don't use it in the body. The plan preserves every method's exact public signature.
- **Outer `catch (e)` blocks in all 11 methods are unreachable in practice.** Every method has an `} catch (e) { debugPrint('…'); rethrow; }` clause sibling to the `on PostgrestException catch (e)` block. Dart's sibling-catch semantics prevent it from catching anything thrown by (or rethrown from) the on-PostgrestException handler; it only fires on non-PostgrestException throws from the initial try body. In Pattern A/B methods, the try body only calls `supabase.rpc(…)` (which throws `PostgrestException`) and may throw an `Exception` from the result-payload check — the latter IS caught by the outer catch, logged as `'❌ Error updating <X>: $e'`, and rethrown. In Pattern C methods, the try body only calls `supabase.from('songs').update(…)` (which throws `PostgrestException`). The outer catch's log-then-rethrow behavior is thus an observable side-effect for the Pattern A/B result-payload-check path (thrown Exception is logged before propagating) and effectively dead for Pattern C. Under the Feature Input's "consistent `kDebugMode`-gated logging" normalization, losing this specific per-method log line is acceptable because (a) it is debug-diagnostic only, never a user-visible outcome; (b) Helper 1 already logs the RPC error message at the point the Exception is constructed; (c) the thrown Exception type and message reaching the caller are byte-for-byte unchanged.
- **`kDebugMode` gating of `debugPrint`**: currently inconsistent (some methods gate, some don't). Feature Input's Expected Behavior explicitly asks for consistent `kDebugMode`-gated logging in the helper. This is the ONLY normalization this refactor performs on top of pure behavior-preservation. It affects developer-diagnostic log output only — never thrown exception types, exception messages, or persisted DB state. All thrown exceptions (type and message) at every one of the 11 wrappers remain byte-for-byte identical to the pre-refactor code.

### Where the methods are called from

Grep across `lib/` shows all 11 methods and `debugFetchSongsRaw` are called from exactly two files:

- `lib/features/setlists/setlist_detail_controller.dart` (all direct repository calls)
- `lib/features/setlists/setlist_repository.dart` (the definitions themselves)

`lib/features/setlists/setlist_detail_screen.dart` calls `notifier.updateSong*` (the controller's methods), never the repository directly. Since the plan preserves every repository method signature, the controller stays unmodified except for the deletion of `debugSmokeTest`.

Zero references in `test/` for any target method or for `debugFetchSongsRaw`/`debugSmokeTest`.

## Proposed Solution

Add TWO private helpers to `SetlistRepository`, then rewrite the 11 public methods as thin wrappers. Delete both dead-code methods. Every wrapper preserves its pre-refactor thrown-exception behavior byte-for-byte (type AND message) — including three singleton cases that pre-refactor code handled asymmetrically: (a) `updateSongTitleArtist`'s raw PGRST203 passthrough, (b) `updateSongTuningOverride`'s isEnumError classification scoped to RPC-path exceptions only, and (c) the Pattern C RPC-result-payload check that fires for `updateSongLyrics` but NOT for `updateSongYoutubeLinks`. The mechanisms for that byte-for-byte preservation are three per-call helper parameters — Helper 1's `handlePgrst203` defaulted flag (§Helper 1), Helper 1's `mapUnhandledRpcException` optional callback (§Helper 1), and Helper 2's `checkRpcResultPayload` required flag (§Helper 2) — NOT a normalization of the behaviors themselves. The only normalization performed on top of pure behavior-preservation is `kDebugMode`-gated logging inside the helpers, which affects developer-diagnostic output only (never thrown exception type, exception message, or DB state).

### Helper 1 — Patterns A + B

```
Future<void> _callSongMetadataRpc({
  required String bandId,
  required String songId,
  required String rpcName,
  required Map<String, dynamic> rpcParams,
  required Map<String, dynamic> directFallbackUpdate,
  required String logLabel,
  bool handlePgrst203 = true,
  Exception? Function(PostgrestException e)? mapUnhandledRpcException,
}) async
```

Body responsibilities:
1. Call `final result = await supabase.rpc(rpcName, params: rpcParams);`.
2. If `result is Map && result['success'] == false`, throw `Exception(result['error'] ?? 'Unknown error')`. This matches the observable behavior of all 9 Pattern-A/B methods pre-refactor — whether they wrote the check as nested `if (result is Map) { if (result['success'] == false) … }` or as a single-line `if (result is Map && result['success'] == false) …`, the surfaced exception type and message are identical.
3. Catch `PostgrestException e` and:
   - On `handlePgrst203 == true && e.code == 'PGRST203'`: log the migration hint (`kDebugMode`-gated) and throw `Exception('Server configuration error. Please contact support.')`. This is the pre-refactor behavior of 8 of the 9 Pattern-A/B methods.
   - On `e.code == 'PGRST202' || e.code == '42883'`: log a `kDebugMode`-gated fallback message and execute `await supabase.from('songs').update(directFallbackUpdate).eq('id', songId);` then return. If this direct-fallback `.update()` itself throws (whether `PostgrestException` or otherwise), the exception propagates out of the helper unmodified — matching pre-refactor sibling-catch semantics where a throw from inside the on-PostgrestException handler propagates up rather than falling through to any classification below.
   - Otherwise: if `mapUnhandledRpcException != null`, call it with `e`. If it returns a non-null `Exception`, throw that. If it returns `null`, or if the callback is not provided, `rethrow` `e` unmodified. This mirrors the pre-refactor location of `updateSongTuningOverride`'s `isEnumError` classification — it runs ONLY on RPC-path exceptions with codes NOT in `{PGRST203, PGRST202, 42883}`, and NEVER on fallback-path exceptions.
4. All `debugPrint` calls gated behind `kDebugMode`, prefixed with `[SetlistRepository]` and including `logLabel` for grep-ability. The helper does NOT add an outer `catch (e)` block — any non-PostgrestException from step 1 or from step 3's callback propagates directly out. This drops the pre-refactor outer-catch "❌ Error updating <X>" log line for the result-payload-check path; the RPC-error-message log emitted in step 2 preserves the diagnostic content at a different lifecycle point, and the thrown Exception's type + message are unchanged (§Existing System Analysis → outer-catch note).

Design rationale for the flags:
- `handlePgrst203` defaults to `true` because 8 of 9 wrappers need `true`, so 8 call sites omit it and `updateSongTitleArtist` explicitly passes `false` to preserve its raw `PostgrestException` passthrough on PGRST203.
- `mapUnhandledRpcException` is optional (default `null`) because 8 of 9 wrappers do not classify unhandled RPC exceptions. `updateSongTuningOverride` passes a callback that runs the `isEnumError && !isLegacySupported` check and returns the tuning-specific `Exception` or `null`. Placing this hook inside the helper's on-PostgrestException catch is the ONLY mechanism that preserves the pre-refactor scoping (RPC-path exceptions only, not fallback-path exceptions). A wrapper-level outer catch cannot distinguish RPC-path exceptions from fallback-path exceptions.
- The `kDebugMode`-gated logging normalization is the ONLY behavior change relative to pre-refactor code, and it affects developer-diagnostic output only — not thrown exception type, thrown exception message, or DB state at any of the 11 call sites.

Serves 9 wrappers: 6 Pattern-A update methods + 3 Pattern-B clear methods.

### Helper 2 — Pattern C

```
Future<void> _updateSongsDirectWithRpcRlsFallback({
  required String bandId,
  required String songId,
  required Map<String, dynamic> directUpdate,
  required Map<String, dynamic> rpcParams,
  required bool checkRpcResultPayload,
  required String logLabel,
}) async
```

Body responsibilities:
1. Call `await supabase.from('songs').update(directUpdate).eq('id', songId);`.
2. Catch `PostgrestException e` and:
   - If `e.code == '42501' || e.message.contains('policy')`:
     - Log the RLS-fallback message (`kDebugMode`-gated).
     - Call `final result = await supabase.rpc('update_song_metadata', params: rpcParams);`. If this RPC call itself throws, propagate unmodified — matching pre-refactor where a throw from inside the on-PostgrestException handler propagates out.
     - If `checkRpcResultPayload == true` AND `result is Map && result['success'] == false`, log the RPC error (`kDebugMode`-gated) and throw `Exception(result['error'] ?? 'Unknown error')`.
     - If `checkRpcResultPayload == false`, do NOT inspect `result` at all — pre-refactor `updateSongYoutubeLinks` never captured or checked the RPC return value and never surfaced an Exception for `{success: false}` payloads. Preserving this means the flag must be `false` for that wrapper.
   - Otherwise `rethrow`.
3. All `debugPrint` calls gated behind `kDebugMode`. The helper does NOT add an outer `catch (e)` block — the pre-refactor Pattern C outer `catch (e) { if (e is PostgrestException) rethrow; debugPrint('…'); rethrow; }` block is dead in practice under Dart sibling-catch semantics (a `PostgrestException` from the on-PostgrestException catch cannot re-enter a sibling `catch (e)`, and no non-PostgrestException is thrown from the direct `.update()` call in practice), so its debug log side-effect is dropped under the Feature Input's logging normalization.

Design rationale for the flag: `checkRpcResultPayload` is REQUIRED (no default) because the two Pattern C wrappers disagree pre-refactor (`updateSongYoutubeLinks` skips the check; `updateSongLyrics` performs it) with no natural majority default. Requiring both call sites to state their choice explicitly eliminates the risk of a future third caller silently getting the wrong behavior by omission and makes QA's static-diff review straightforward.

Serves 2 wrappers: `updateSongYoutubeLinks` (`checkRpcResultPayload: false`), `updateSongLyrics` (`checkRpcResultPayload: true`).

### The 11 thin wrappers

Each wrapper:
- Preserves its EXACT current public signature (parameter names, types, `required`ness, return type).
- Runs its EXISTING validations (`songId.isEmpty`, `bandId.isEmpty`, range checks, non-empty checks) with the SAME `ArgumentError` messages.
- Builds `rpcParams` inline with all 10 `update_song_metadata` keys (or the 3 `clear_song_metadata` keys) — the same shape used today.
- Builds `directFallbackUpdate` (Patterns A/B) or `directUpdate` (Pattern C) inline as a `{'<column>': <value>}` map — the same shape used today.
- Calls the appropriate helper with a descriptive `logLabel` (e.g. `'updateSongBpmOverride'`).

Two wrappers need extra local wrapping around the helper call to preserve special behavior:

- **`updateSongTuningOverride`**: computes `dbTuning = tuningToDbEnum(tuning) ?? tuning` and `isLegacySupported = isLegacyEnumSupported(tuning)` BEFORE the helper call, and passes `dbTuning` into both `rpcParams['p_tuning']` and `directFallbackUpdate['tuning']`. Delegates to Helper 1 with `handlePgrst203: true` (default, omitted from call site) AND `mapUnhandledRpcException` set to a callback that checks `isEnumError && !isLegacySupported` using the exact conditions currently on lines 2019–2023 (`e.message.contains('invalid input value for enum') || e.message.contains('tuning_type') || e.code == '22P02' || e.code == '400'`) and returns `Exception('This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.')` when the condition holds, else returns `null`. This mechanism preserves the pre-refactor scoping exactly: the callback fires only on RPC-path PostgrestExceptions with codes NOT in `{PGRST203, PGRST202, 42883}`, never on fallback-path exceptions. The wrapper does NOT add its own outer `try` / `on PostgrestException catch` block — doing so would incorrectly classify fallback-path exceptions and diverge from pre-refactor behavior.
- **`updateSongTitleArtist`**: preserves `if (title == null && artist == null) return;` early return. Builds `directFallbackUpdate` conditionally: `final directFallbackUpdate = <String, dynamic>{}; if (title != null) directFallbackUpdate['title'] = title; if (artist != null) directFallbackUpdate['artist'] = artist;`. This mirrors the current fallback exactly. Delegates to Helper 1 with `handlePgrst203: false` EXPLICITLY, so on PGRST203 the helper falls through to (no-callback →) `rethrow` and the raw `PostgrestException` surfaces to the caller unmodified — matching the pre-refactor behavior byte-for-byte. This wrapper does NOT gain any new PGRST203 conversion; the exception type and message on that path are identical to pre-refactor code. `mapUnhandledRpcException` is not passed (defaults to `null`).

### Deletions

- `SetlistRepository.debugFetchSongsRaw` at `setlist_repository.dart` lines 764–836 (73 lines).
- `SetlistDetailNotifier.debugSmokeTest` at `setlist_detail_controller.dart` lines 858–869 (12 lines). Deleted in the same PR because deleting the repository method without deleting this caller would break `flutter analyze`.

### Order of edits in the file

Add both helpers immediately above `updateSongBpmOverride` (currently line 1527), inside a new region marker or between existing markers as makes sense. Do NOT reorder any other methods or move any existing section markers.

## Database Impact

not applicable

## Flutter Architecture Changes

- No new controllers, providers, or repositories.
- No new public API on `SetlistRepository`.
- Two new PRIVATE helpers on the existing class.
- One controller method deleted (`debugSmokeTest`) — unreachable, zero callers.
- Init order, Riverpod graph, and band-scoping logic are all untouched.

## Files to Create

none

## Files to Modify

- **`lib/features/setlists/setlist_repository.dart`** — add two private helpers; rewrite the 11 named public methods as thin wrappers; delete `debugFetchSongsRaw`. Net line delta target: −500 to −700 (see Change Budget).
- **`lib/features/setlists/setlist_detail_controller.dart`** — delete `debugSmokeTest` method (currently lines 858–869). Net line delta: −11 to −13.

## Files Off-Limits

- **The other ~3,700 lines of `setlist_repository.dart`** (everything outside the 11 named methods, the two helpers being added, and `debugFetchSongsRaw`). No opportunistic cleanup, renaming, comment reflows, or region-marker edits.
- **`supabase/migrations/**`** — the `update_song_metadata` and `clear_song_metadata` RPCs and their `SECURITY DEFINER` role are unchanged. This is a Dart-side-only refactor.
- **`supabase/functions/**`** — no edge-function changes.
- **`lib/features/setlists/setlist_detail_screen.dart`** — screen-level callers are unaffected because every repository method signature is preserved. Do not modify.
- **`lib/features/setlists/tuning/tuning_helpers.dart`** — read-only dependency.
- **Every other file in `lib/` and `test/`** — no in-scope reason to touch.
- **Any of the "related but out of scope" audit items** — `.select()`/Riverpod rebuild-scope, edge function CORS duplication, `members_repository.dart` error swallowing.

## Change Budget

Measured against the pre-refactor file state. QA compares the actual PR diff to these numbers; if actuals fall outside the ranges, escalate to Architect before applying.

| File | Expected net line delta | Expected new files | New public classes/methods | New private methods | New deps |
| --- | --- | --- | --- | --- | --- |
| `lib/features/setlists/setlist_repository.dart` | −500 to −700 | 0 | 0 | 2 | 0 |
| `lib/features/setlists/setlist_detail_controller.dart` | −11 to −13 | 0 | 0 | 0 | 0 |
| **Totals** | **−511 to −713** | **0** | **0** | **2** | **0** |

If Engineer's actual diff is outside the −511/−713 window on the repository file, or introduces any new public method / class / dependency / file, QA flags Warning and asks Architect to review before proceeding.

## System Impact Map

| System | Status |
| --- | --- |
| Setlists | affected (repository refactor + one controller method removal; runtime behavior identical at every call site) |
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists (Catalog logic) | unaffected — no Catalog-specific method is in the 11-method scope |
| Members | unaffected |
| Auth | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Deep links | unaffected |
| Platforms (iOS / Android / macOS / Web) | unaffected — pure shared Dart, no platform-conditional code touched |
| Init order | unaffected |
| Firebase initialization | unaffected |
| RLS / SECURITY DEFINER contract | unaffected |

## Regression Risk

**MEDIUM.**

Reasons it is not LOW:
- 11 method bodies change simultaneously. A single copy-paste slip in any `rpcParams` map (wrong param name, wrong value assignment, e.g. `'p_bpm': durationSeconds`) silently corrupts a metadata path with no automated test coverage to catch it.
- The tuning normalization + enum-error branch is subtle. Losing the `tuningToDbEnum` normalization on either the RPC path or the fallback path would break tunings for pre-migration-052 databases.
- Pattern C's inverted control flow is easy to miss. Wiring `updateSongYoutubeLinks` or `updateSongLyrics` through Helper 1 instead of Helper 2 would invert their RLS-fallback semantics.
- No existing widget/unit tests for these methods; QA cannot mechanically verify runtime behavior.

Reasons it is not HIGH:
- Zero call-site changes required outside the two modified files.
- No RPC / migration / RLS / SQL touched.
- No auth / session / routing / init-order / Firebase / platform-conditional code touched.
- Every public method signature preserved, so downstream files compile unchanged.
- The change is fully reversible by reverting the PR.

## Engineer Task Breakdown

Ordered, atomic, one focused change per task. Engineer implements this list literally.

1. **Add `_callSongMetadataRpc` helper** to `SetlistRepository`, placed immediately above `updateSongBpmOverride` (currently line 1527). Body per §Proposed Solution → Helper 1, including:
   - `bool handlePgrst203 = true` parameter and its two-branch behavior (`true` → throw generic "Server configuration error" `Exception`; `false` → skip the PGRST203 branch entirely so PGRST203 falls through to the unhandled-code path).
   - `Exception? Function(PostgrestException e)? mapUnhandledRpcException` optional parameter (default `null`); when non-null, invoked ONLY in the on-PostgrestException catch's terminal "else" branch (after PGRST203-if-handled and PGRST202/42883 have been ruled out); if it returns a non-null `Exception`, throw that; otherwise `rethrow` the raw `PostgrestException`.
   - No outer `catch (e)` block — non-PostgrestException throws (including the `Exception` from the result-payload check on step 1 and any Exception returned by `mapUnhandledRpcException`) propagate directly out of the helper.
   Include a one-line class-internal doc comment stating its purpose and both flags' roles ("Shared RPC-first path for update_song_metadata and clear_song_metadata callers. Set handlePgrst203=false to preserve raw PostgrestException passthrough for callers that historically did not intercept PGRST203. Provide mapUnhandledRpcException to classify RPC-path PostgrestExceptions with codes not in {PGRST203, PGRST202, 42883} into a caller-specific Exception; the hook does NOT run on fallback-path exceptions, matching pre-refactor sibling-catch scoping."). Do not export it. All `debugPrint` calls `kDebugMode`-gated.
2. **Add `_updateSongsDirectWithRpcRlsFallback` helper** to `SetlistRepository`, placed immediately below Helper 1. Body per §Proposed Solution → Helper 2, including:
   - `required bool checkRpcResultPayload` parameter (NO default). When `true`, the helper captures the RPC fallback's return value and throws `Exception(result['error'] ?? 'Unknown error')` on `result is Map && result['success'] == false`. When `false`, the helper does NOT capture or inspect the RPC return value at all.
   - No outer `catch (e)` block.
   Include a one-line class-internal doc comment ("Shared direct-first path for songs.update() callers that fall back to update_song_metadata RPC on RLS block. checkRpcResultPayload is required and must exactly match the pre-refactor caller's behavior: false for callers that ignore the fallback RPC's return value (updateSongYoutubeLinks), true for callers that treat {success: false, error: '…'} as a thrown Exception (updateSongLyrics)."). Same style guidance as Task 1.
3. **Rewrite `updateSongBpmOverride`** as a thin wrapper: keep signature, keep the three `ArgumentError` validations verbatim, build `rpcParams` with all 10 keys (only `p_bpm` non-null), `directFallbackUpdate: {'bpm': bpm}`, delegate to Helper 1 with `rpcName: 'update_song_metadata'` and `logLabel: 'updateSongBpmOverride'`.
4. **Rewrite `clearSongBpmOverride`** as a thin wrapper: same shape as Task 3 but `rpcName: 'clear_song_metadata'`, `rpcParams: {'p_song_id': songId, 'p_band_id': bandId, 'p_clear_bpm': true}`, `directFallbackUpdate: {'bpm': null}`, `logLabel: 'clearSongBpmOverride'`.
5. **Rewrite `clearSongTuningOverride`** — same shape as Task 4 with `p_clear_tuning: true` and `directFallbackUpdate: {'tuning': null}`.
6. **Rewrite `clearSongMusicalKeyOverride`** — same shape as Task 4 with `p_clear_musical_key: true` and `directFallbackUpdate: {'musical_key': null}`.
7. **Rewrite `updateSongDurationOverride`** — Pattern A wrapper. Preserve the `0..1200` range check with its exact `ArgumentError` message.
8. **Rewrite `updateSongTuningOverride`** — Pattern A wrapper WITH the local tuning specialization: compute `dbTuning = tuningToDbEnum(tuning) ?? tuning` and `isLegacySupported = isLegacyEnumSupported(tuning)` BEFORE the helper call; pass `dbTuning` into both `rpcParams['p_tuning']` and `directFallbackUpdate['tuning']`. Delegate to Helper 1 with `handlePgrst203` omitted (default `true`) AND `mapUnhandledRpcException` set to a callback matching the exact pre-refactor conditions on lines 2019–2023: `final isEnumError = e.message.contains('invalid input value for enum') || e.message.contains('tuning_type') || e.code == '22P02' || e.code == '400'; if (isEnumError && !isLegacySupported) return Exception('This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.'); return null;`. Do NOT wrap the helper call in a wrapper-level `try` / `on PostgrestException catch` block — the callback is the mechanism that scopes the classification to RPC-path exceptions only. Wrapping externally would incorrectly classify fallback-path exceptions (i.e., PostgrestExceptions thrown by the `.update({'tuning': dbTuning})` call inside the PGRST202/42883 fallback) and diverge from pre-refactor behavior, which under Dart sibling-catch semantics never runs the enum-error check on those exceptions.
9. **Rewrite `updateSongNotes`** — Pattern A wrapper. Preserve the notes-substring `kDebugMode`-gated debug string.
10. **Rewrite `updateSongTitleArtist`** — Pattern A wrapper WITH two mandatory specializations: (a) preserve `if (title == null && artist == null) return;` early return; (b) build `directFallbackUpdate` conditionally per §Proposed Solution; (c) call Helper 1 with `handlePgrst203: false` EXPLICITLY. Do not omit the flag — the default (`true`) would change this method's PGRST203 exception behavior, which the Feature Input's pure-refactor contract forbids. All other 8 Pattern-A/B wrappers omit the flag (default `true`).
11. **Rewrite `updateSongMusicalKey`** — Pattern A wrapper.
12. **Rewrite `updateSongYoutubeLinks`** — Pattern C wrapper. `directUpdate: {'youtube_links': youtubeLinks}`, `rpcParams` with all 10 `update_song_metadata` keys and only `p_youtube_links` non-null. Call Helper 2 with `checkRpcResultPayload: false` EXPLICITLY. This preserves the pre-refactor behavior at lines 2151–2220 of NEVER inspecting the RPC fallback's return value — a `{success: false}` payload is silently swallowed exactly as it is today. Omitting this flag or setting it to `true` would introduce a NEW exception path that pre-refactor code does not have, violating the Feature Input's pure-refactor contract.
13. **Rewrite `updateSongLyrics`** — Pattern C wrapper. `directUpdate: {'lyrics': lyrics}`, `rpcParams` with all 10 `update_song_metadata` keys and only `p_lyrics` non-null. Call Helper 2 with `checkRpcResultPayload: true` EXPLICITLY. This preserves the pre-refactor behavior at lines 2222–2293 of throwing `Exception(result['error'] ?? 'Unknown error')` when the RPC fallback returns `{success: false, error: '…'}`. Omitting this flag would drop that exception path.
14. **Delete `SetlistRepository.debugFetchSongsRaw`** (currently lines 764–836) and its `// ==========================================================================` region-header comment block that immediately precedes it, if the header specifically annotates this method (leave adjacent unrelated region headers intact).
15. **Delete `SetlistDetailNotifier.debugSmokeTest`** in `setlist_detail_controller.dart` (currently lines 858–869) including its preceding `/// Debug: Run smoke test …` doc comment.

Do not reorder existing methods. Do not touch surrounding comments or region markers except as explicitly called out in Tasks 14 and 15. Do not add or modify any import.

## Verification Plan

### Tier 1 — pre-deploy, mechanically executable (QA gate for APPROVED)

QA runs each of these and gates approval on them:

1. `flutter analyze` returns zero new warnings or errors compared to `main`.
2. `flutter test` passes. No new tests are required for this refactor; existing suite must remain green.
3. **Static diff review — per-method equivalence.** For each of the 11 rewritten methods, QA opens the pre/post source side-by-side and confirms the wrapper produces identical:
   - RPC name string,
   - Complete `params` map (every key present with correct nullability, correct value assignment; for Pattern A/B, exactly 10 `update_song_metadata` keys or 3 `clear_song_metadata` keys),
   - Direct-fallback `songs.update(...)` map (column, value expression, `.eq('id', songId)` where clause),
   - Set of `PostgrestException` codes handled and the SIDE EFFECT of each branch (`PGRST203`, `PGRST202`/`42883`, other) — specifically: the type AND message of any exception thrown, or the fallback SQL executed. The internal ordering of the branch checks inside the helper does not need to match the pre-refactor method line-for-line, but the observable exception surfaced to the caller for each code must be identical.
   - RPC-result-payload check presence/absence per method: for the 9 Pattern-A/B methods, the wrapper must delegate to Helper 1 (which always performs the check) — matches pre-refactor. For the 2 Pattern-C methods, the wrapper must delegate to Helper 2 with the correct `checkRpcResultPayload` value — `updateSongYoutubeLinks: false`, `updateSongLyrics: true` — matching each method's pre-refactor behavior (YouTubeLinks NEVER inspects the RPC fallback return value; Lyrics ALWAYS does and throws on `{success: false}`).
   - `ArgumentError` validation messages,
   - Thrown `Exception` messages surfaced to callers (both `Exception` type and message string, byte-for-byte),
   as the pre-refactor method. This is a byte-level static diff review, not a runtime test. Any deviation is a Blocker.
4. **Special-case preservation for `updateSongTuningOverride`.** QA verifies:
   - The wrapper still calls `tuningToDbEnum` (for both the RPC path and the direct fallback) and computes `isLegacySupported = isLegacyEnumSupported(tuning)` before the helper call.
   - The wrapper passes `mapUnhandledRpcException` to Helper 1 as a callback whose body matches lines 2019–2023 exactly: `final isEnumError = e.message.contains('invalid input value for enum') || e.message.contains('tuning_type') || e.code == '22P02' || e.code == '400';` and returns `Exception('This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.')` when `isEnumError && !isLegacySupported`, else returns `null`.
   - The wrapper does NOT wrap the helper call in an outer `try` / `on PostgrestException catch` block. Presence of such a wrapper-level catch is a Blocker — it would incorrectly classify PostgrestExceptions thrown by the fallback `.update({'tuning': dbTuning})` call, diverging from pre-refactor sibling-catch semantics.
   - The enum-error `Exception` message ("This tuning is not yet available. Please try Standard, Drop D, Half-Step, or Full-Step.") is thrown byte-for-byte on the same trigger conditions.
5. **Special-case preservation for `updateSongTitleArtist`.** QA verifies: (a) the `if (title == null && artist == null) return;` early return remains; (b) the conditional `directFallbackUpdate` map builds match the pre-refactor pattern (`if (title != null) directFallbackUpdate['title'] = title;` and `if (artist != null) directFallbackUpdate['artist'] = artist;`); (c) the wrapper calls Helper 1 with `handlePgrst203: false` EXPLICITLY and does NOT pass `mapUnhandledRpcException`. This flag is required — its absence would change this method's PGRST203 behavior from raw `PostgrestException` passthrough to generic "Server configuration error" Exception, violating the Feature Input's pure-refactor contract.
6. **Special-case preservation for Pattern C RPC-result-payload asymmetry.** QA verifies:
   - `updateSongYoutubeLinks` calls Helper 2 with `checkRpcResultPayload: false` EXPLICITLY. Any other value — or omission with a defaulted `true` — introduces a new exception path on `{success: false}` payloads that pre-refactor code does not have. Blocker.
   - `updateSongLyrics` calls Helper 2 with `checkRpcResultPayload: true` EXPLICITLY. Any other value drops the pre-refactor `Exception(result['error'] ?? 'Unknown error')` throw on `{success: false}` payloads. Blocker.
   - Helper 2's parameter is defined as `required bool checkRpcResultPayload` (no default), so a wrapper that omits it fails to compile — Tier 1 §1 (`flutter analyze`) catches this automatically as a belt-and-braces check.
7. **PGRST203 exception behavior — byte-for-byte preservation at every one of the 9 Pattern-A/B wrappers.** For each of the 9 wrappers, QA statically confirms the pre/post exception behavior on PGRST203 is identical:
   - `updateSongBpmOverride`, `updateSongDurationOverride`, `updateSongTuningOverride`, `updateSongNotes`, `updateSongMusicalKey`, `clearSongBpmOverride`, `clearSongTuningOverride`, `clearSongMusicalKeyOverride` (8 wrappers): pre-refactor threw `Exception('Server configuration error. Please contact support.')`. Post-refactor MUST throw the same `Exception` type with the same message. Achieved by omitting `handlePgrst203` (defaults to `true`).
   - `updateSongTitleArtist` (1 wrapper): pre-refactor rethrew the raw `PostgrestException` unmodified. Post-refactor MUST rethrow the raw `PostgrestException` unmodified (same type, same fields, same message). Achieved by passing `handlePgrst203: false` explicitly.
   Any deviation — a wrapper missing an explicit `handlePgrst203: false` where it needs one, or vice versa — is a Blocker.
8. **Dead-code deletion audit.** `grep_search -r 'debugFetchSongsRaw' lib/ test/` returns zero matches. `grep_search -r 'debugSmokeTest' lib/ test/` returns zero matches.
9. **Call-site untouched audit.** `git diff main -- lib/ test/` shows changes ONLY in `lib/features/setlists/setlist_repository.dart` and `lib/features/setlists/setlist_detail_controller.dart`. No other file appears in the diff.
10. **Change budget check.** Actual net line delta on each modified file is within the range in the §Change Budget table. No new files, no new public methods, no new dependencies, no new imports.
11. **Migration/RPC/RLS untouched.** `git diff main -- supabase/` returns empty output.

### Tier 2 — Tony's manual PR-test punch list (owner-run at PR-test time; NOT a QA gate)

QA cannot launch, build, or drive a running instance of the app, so these are not a gate condition for APPROVED. QA copies this exact numbered list into the QA report so Tony can run it verbatim on the PR preview build.

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
10. In song details, add lyrics text. Save. **Expected:** lyrics persist after reload.
11. Throughout the above, watch for any snackbar error, red overlay, or unexpected app reload. **Expected:** none.

If any step fails, Tony reverts the PR and re-files the failing step's expected-vs-actual back to Architect.

### Tier 2 addendum — direct-fallback (PGRST202/42883) path

The direct-fallback path only fires if the RPC is missing from the deployed database. It cannot be exercised on production or the PR preview without dropping the RPC in a preview DB, which is out of scope. Static diff review (Tier 1 §3) is the only feasible verification for this branch. Recording this limitation explicitly.

## QA Regression Areas

- Setlist detail screen inline edits for BPM, Duration, Tuning, Musical Key (both set and clear paths).
- Song details bottom sheet: Title/Artist, Notes, YouTube Links, Lyrics save paths.
- Legacy songs with `NULL band_id`: the `SECURITY DEFINER` RPC path exists specifically to serve these; the refactor must not lose or reorder the RPC route.
- Any UI surface that displays these metadata fields after a save (should not re-render differently).

## Rollout Strategy

Ship as a single PR against `main`. No feature flag needed — behavior is byte-for-byte identical at every call site. No migration, no coordinated deploy, no environment-config change. Rollback = revert the PR (fully self-contained in two files).

## Out of Scope

- Any change to `update_song_metadata` or `clear_song_metadata` RPCs, their `SECURITY DEFINER` role, or their RLS-bypass semantics.
- The `.select()` / Riverpod rebuild-scope issue.
- The Edge Function CORS duplication.
- The `members_repository.dart` silent-error-swallowing fix.
- Any refactor of the remaining ~3,700 lines of `setlist_repository.dart` beyond the 11 named methods + `debugFetchSongsRaw`.
- Adding unit tests for the consolidated helpers. Would be valuable but requires Supabase mocking infra that does not currently exist in `test/`; would double the scope of this PR. Separate Feature Input if desired.
- Splitting `setlist_repository.dart` into `SetlistRepository` / `CatalogRepository` / `SetlistBulkRepository` per the `CODEBASE_AUDIT.md` recommendation. Out of scope; separate Feature Input.
