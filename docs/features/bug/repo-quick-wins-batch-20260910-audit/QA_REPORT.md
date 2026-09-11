# QA Report

## Feature Slug

`bug/repo-quick-wins-batch-20260910-audit`

## Feature Title

Quick-win cleanup batch: redundant `_isMarketingHost()` calls, non-const tuning color map, duplicated Edge Function CORS headers

## Cycle Number

2

## Final Verdict

APPROVED

## Validation Summary

The uncommitted implementation matches the Architect scope for all three independently reviewed mini-scopes. Validation consisted of working-tree diff review, code-path analysis, scoped Flutter analysis, the full Flutter test suite, static invariant searches, change-budget checks, and diff-safety checks. QA did not launch or drive the app, deploy Edge Functions, or test a live endpoint; those correctly classified owner-run checks are captured in the Manual Verification Punch List.

## Architect Scope Review

- Plan, Engineer report, and branch all use slug `bug/repo-quick-wins-batch-20260910-audit`; the Engineer report is Cycle 2.
- Implementation files are limited to the two approved Dart files, the nine approved Edge Function entry points, and the approved new `_shared/cors.ts` module. The untracked Architect and Engineer reports are expected pipeline artifacts.
- No migrations, Edge Function configuration, dependencies, tests, RPCs, RLS, provider/controller architecture, initialization order, or unrelated files changed.
- The implementation remains uncommitted as expected and was reviewed directly against `HEAD`.

## Completeness Check

### Item 1: Routing

PASS. `onGenerateRoute` assigns `final isMarketingHost = _isMarketingHost();` once and both formerly repeated branches use the local. `_isMarketingHost()` itself and the `onUnknownRoute` call are unchanged. Per the clarified check, `_isMarketingHost` has exactly three textual matches: definition, cached assignment, and untouched `onUnknownRoute` call.

### Item 2: Tuning Color Map

PASS. The 47-entry map was hoisted to file-private top-level const `_tuningBadgeColorMap`. Diff comparison confirms the same keys, color values, ordering, and family comments. The function's guards, normalization, custom-tuning behavior, and slate fallback remain unchanged. `final colorMap` has zero matches and `_tuningBadgeColorMap` has exactly two.

### Item 3: Shared Edge Function CORS

PASS. `_shared/cors.ts` exports exactly the planned typed base object and override helper. All nine functions have one shared import and one planned assignment. Declaration locations remain unchanged, and no handler/business-logic or OPTIONS response hunk changed.

The deliberate behavior change is present and correct: `accept-invite`, `getsongbpm_lookup`, `itunes_search`, and `musicbrainz_search` now receive `Access-Control-Allow-Methods: POST, OPTIONS` through `baseCorsHeaders`.

The required exceptions are preserved:

- `calendar-feed`: `GET, OPTIONS` and `Content-Type` only.
- `send-push`: `POST, OPTIONS`; headers include `X-Internal-Secret` and exclude `Authorization`.

## Behavior Verification

Code-path analysis confirms behavior preservation for Items 1 and 2 and the planned CORS semantics for Item 3. This was not runtime-exercised by QA.

- Item 1 computes the same pure host predicate once per `onGenerateRoute` invocation instead of twice.
- Item 2 performs the same normalized lookup against identical entries without per-call map allocation.
- Item 3 preserves effective headers for five functions and intentionally adds the methods header to the four approved POST-only functions. Existing OPTIONS response bodies/statuses remain four `"ok"`/200 responses and five `null`/204 responses.

## Regression Check

Overall regression risk: **LOW**.

- Routing: LOW. Both web routing branches retain their prior conditions; `onUnknownRoute` and native behavior are untouched.
- Setlists: LOW. The tuning lookup data and fallback behavior are unchanged; covered Open E behavior passes.
- Auth: LOW. `accept-invite` and `send-band-invite` change only CORS declaration sourcing; auth logic is untouched.
- Notifications: LOW. `send-push` retains `X-Internal-Secret` and does not acquire `Authorization`.
- Calendar subscription: LOW. `calendar-feed` remains GET-only with `Content-Type` only.
- Song enrichment: LOW. All three lookup functions gain the explicitly approved `POST, OPTIONS` methods header and retain their handlers.
- Demo session and bug report: LOW. Only shared CORS sourcing changed.
- Platform parity/init order: LOW. Shared Dart behavior remains equivalent; no initialization or platform-specific files changed.

## Database Safety

Not applicable. No SQL migrations, schema, RLS, RPC, grants, or `SECURITY DEFINER` functions changed. The migration and Edge Function `config.toml` diffs are empty.

## Analyzer Results

PASS. `flutter analyze lib/main.dart lib/features/setlists/tuning/tuning_helpers.dart` reported exactly 0 errors, 0 warnings, and 47 info-level `unnecessary_const` diagnostics. The 47 infos arise from preserving the map's explicit `const Color(...)` entries as required; the gate is 0 errors and zero new warnings/errors, so this passes.

## Test Results

PASS. Full `flutter test`: 297 passed, 0 failed. This includes the existing Open E tuning-color regression test.

## Diff Safety Review

PASS. `git diff --check` is clean. Added-line scans found no `TODO`, `FIXME`, `debugPrint(`, credential literals, private keys, or test scaffolding. The existing PEM-delimiter regex in `send-push` is unchanged and is not a credential. No accidental deletion or unrelated formatting churn was found.

## Change Budget Review

PASS. Actual implementation net delta is -5 lines, within the planned total range of -17 to 0.

| File | Actual net | Planned net |
| --- | ---: | ---: |
| `lib/main.dart` | +1 | +1 |
| `lib/features/setlists/tuning/tuning_helpers.dart` | 0 | -1 to +1 |
| `supabase/functions/_shared/cors.ts` | +20 | +15 to +25 |
| `accept-invite/index.ts` | -3 | -2 to -4 |
| `calendar-feed/index.ts` | -3 | -2 to -4 |
| `exit-demo-session/index.ts` | -3 | -2 to -4 |
| `getsongbpm_lookup/index.ts` | -2 | -1 to -3 |
| `itunes_search/index.ts` | -2 | -1 to -3 |
| `musicbrainz_search/index.ts` | -2 | -1 to -3 |
| `send-band-invite/index.ts` | -4 | -2 to -4 |
| `send-bug-report/index.ts` | -4 | -2 to -4 |
| `send-push/index.ts` | -3 | -2 to -4 |

No unplanned implementation file, dependency, or public symbol was added.

## Code Efficiency Review

PASS. Item 1 removes a repeated pure-function call. Item 2 removes repeated map allocation without changing its API. Item 3 replaces nine duplicate literals with the planned shared const/helper, used by seven and two functions respectively. Independent searches found no pre-existing equivalent in `lib/`; repository-wide CORS searches identify the new shared module as the sole origin literal. No single-use wrapper, unused state, speculative configuration, or other AI-shaped bloat was introduced.

## Manual Verification Punch List

QA did not execute these owner-run runtime checks. Tony should run them against a non-production preview/build where applicable.

### Item 1: Routing

1. Open the preview root on the marketing host. Expected: `LandingPage` loads.
2. Open an unknown path on the marketing host. Expected: `onUnknownRoute` resolves to `LandingPage`.
3. Open the root on the app host. Expected: `AuthGate` loads.
4. Open an unknown path on the app host. Expected: `onUnknownRoute` resolves to `AuthGate`.
5. Launch the branch on iOS, Android, or macOS. Expected: it opens to `AuthGate` as before because `kIsWeb` is false.

### Item 2: Tuning Badges

1. Open a song using `standard_e`. Expected: blue badge fill `#2563EB`.
2. Open or assign `drop_d`. Expected: olive-green badge fill `#65A30D`.
3. Open or assign `half_step_down`. Expected: magenta badge fill `#C026D3`.
4. Open or assign any `custom_<uuid>` tuning. Expected: slate badge fill `#64748B`.
5. Open a `nashville` tuning. Expected: amber fill `#F59E0B` and dark text `#09090B`.
6. Compare the same setlist with `main` while scrolling. Expected: no color difference, flicker, or rendering glitch.

### Item 3: Deployed Edge Functions

1. Send an OPTIONS request to preview `send-band-invite` requesting POST with `content-type,authorization`. Expected: HTTP 204; origin `*`; methods `POST, OPTIONS`; headers `Content-Type, Authorization, x-client-info, apikey`.
2. Send the same POST preflight to preview `itunes_search`. Expected: HTTP 200 with body `ok`; the same three CORS headers, including the deliberately added `POST, OPTIONS` methods header. Confirm browser preflight succeeds.
3. Send an OPTIONS request to preview `calendar-feed` requesting GET with `content-type`. Expected: HTTP 204; methods exactly `GET, OPTIONS`; allowed headers exactly `Content-Type`, without `Authorization` or `apikey`. With a valid token, a real GET still returns a parseable iCal feed.
4. Send an OPTIONS request to preview `send-push` requesting POST with `content-type,x-internal-secret`. Expected: HTTP 204; allowed headers include `X-Internal-Secret` and exclude `Authorization`. Trigger the normal internal-secret flow and confirm push delivery.
5. From the deployed preview, send and accept a band invite. Expected: email delivery and app redirect behave as before.
6. Run song enrichment through iTunes, MusicBrainz, and GetSongBPM. Expected: all three return results normally in a browser context.
7. Subscribe to the band calendar in an iCal client. Expected: the feed parses and returns band events.
8. Exit a demo session. Expected: the user returns to the anonymous/logged-out state.
9. Submit a bug report. Expected: delivery succeeds as before.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.