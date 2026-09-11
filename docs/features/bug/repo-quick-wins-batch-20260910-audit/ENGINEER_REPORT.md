# ENGINEER_REPORT

## Feature Slug

`bug/repo-quick-wins-batch-20260910-audit`

## Feature Title

Quick-win cleanup batch: redundant `_isMarketingHost()` calls, non-const tuning color map, duplicated Edge Function CORS headers

## Cycle Number

2

## Goal

Implement the three approved, independently verifiable cleanup mini-scopes without changing routing behavior, tuning colors, or existing effective CORS behavior except for the explicitly approved methods header addition.

## Architect Tasks Completed

- Item 1: cached `_isMarketingHost()` once inside `onGenerateRoute` and replaced its two repeated calls. The definition and `onUnknownRoute` call remain unchanged.
- Item 2: hoisted the 47-entry tuning color map to the file-private top-level const `_tuningBadgeColorMap` and retained the original entries, comments, ordering, lookup, and fallback.
- Item 3: created `_shared/cors.ts`, imported it from all nine listed Edge Functions, retained the `calendar-feed` and `send-push` overrides, and left OPTIONS handlers and business logic unchanged.
- Deliberate behavior change: `accept-invite`, `getsongbpm_lookup`, `itunes_search`, and `musicbrainz_search` gain `Access-Control-Allow-Methods: POST, OPTIONS`.

## Files Created

- `supabase/functions/_shared/cors.ts`
- `docs/features/bug/repo-quick-wins-batch-20260910-audit/ENGINEER_REPORT.md`

## Files Modified

- `lib/main.dart`
- `lib/features/setlists/tuning/tuning_helpers.dart`
- `supabase/functions/accept-invite/index.ts`
- `supabase/functions/calendar-feed/index.ts`
- `supabase/functions/exit-demo-session/index.ts`
- `supabase/functions/getsongbpm_lookup/index.ts`
- `supabase/functions/itunes_search/index.ts`
- `supabase/functions/musicbrainz_search/index.ts`
- `supabase/functions/send-band-invite/index.ts`
- `supabase/functions/send-bug-report/index.ts`
- `supabase/functions/send-push/index.ts`

## Analyzer Results

`flutter analyze lib/main.dart lib/features/setlists/tuning/tuning_helpers.dart` reported exactly 0 errors, 0 warnings, and 47 info-level `unnecessary_const` diagnostics. The Manager gate requires 0 errors, and the plan requires zero new warnings/errors, so the scoped analyzer passes both gates.

The 47 explicit `const Color(...)` entries remain unchanged because the plan requires the map contents to remain byte-identical. The info-level diagnostics were not treated as errors or warnings.

## Test Results

- Full `flutter test` passed: 297 tests passed and 0 failed.
- This includes `test/app/theme/rose_primary_color_test.dart` and its Open E tuning color regression coverage.

## Code Efficiency/Bloat Check

- Item 1 adds one local and removes two repeated calls; no abstraction added.
- Item 2 moves the existing map without adding entries, state, or public API.
- Item 3 adds the shared helper required by the plan and removes nine duplicate literals. Search of `lib/` for `corsHeaders`, `buildCorsHeaders`, and `Access-Control-Allow` found no existing helper equivalent.
- No new dependency, config, auth, routing, init-order, RPC, RLS, schema, migration, provider, notifier, or UI abstraction was added.
- `dart fix --dry-run` proposed only 47 `unnecessary_const` removals; they were not applied because the plan requires the explicit `const Color(...)` entries to remain byte-identical.
- File change budgets are within the plan's net-line ranges for tracked implementation files. The new untracked shared file contains 21 lines, within its +15 to +25 budget.

## Verification

- Item 1: static structure passes. The cached assignment appears once, both `onGenerateRoute` branches use the local, `onUnknownRoute` remains unchanged, and `lib/main.dart` has net +1 line. The plan's stated grep expectation of exactly two `_isMarketingHost` matches is internally inconsistent: the required new assignment itself is a third match, so the actual correct count is three (definition, cached assignment, unchanged `onUnknownRoute` call).
- Item 2: full tests pass; `final colorMap` has zero matches; `_tuningBadgeColorMap` has exactly two matches; net line delta is 0. Scoped analysis has 0 errors, 0 warnings, and 47 expected infos.
- Item 3: static verification passes. There is exactly one `Access-Control-Allow-Origin` literal, nine shared imports, and nine `corsHeaders` assignments. `calendar-feed` remains `GET, OPTIONS` with `Content-Type` only. `send-push` retains `X-Internal-Secret` and its CORS override does not include `Authorization`. `accept-invite`, `getsongbpm_lookup`, `itunes_search`, and `musicbrainz_search` deliberately gain `Access-Control-Allow-Methods: POST, OPTIONS`.
- No deployment or runtime Edge Function preflight testing was performed; that remains Tier 2 deploy-time verification.

## Deviations From Plan

- No implementation deviation was intentionally made.
- Verification step 1.4 has a mistaken static count: three `_isMarketingHost` textual matches are expected after implementation (definition, cached assignment, and untouched `onUnknownRoute` call), not two.

## Blockers Encountered

- None. The 47 `unnecessary_const` diagnostics are info-level lints and do not violate the 0-error Manager gate or the plan's zero-new-warning/error requirement.

## Ready For QA

Yes