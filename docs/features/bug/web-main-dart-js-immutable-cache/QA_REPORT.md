# QA_REPORT — bug/web-main-dart-js-immutable-cache

## Feature Slug

`bug/web-main-dart-js-immutable-cache`

## Feature Title

Web app serves stale `main.dart.js` indefinitely due to overly broad immutable cache header

## Cycle Number

1

## Final Verdict

**APPROVED**

## Validation Summary

Config-only fix (single new Vercel header rule in [web/vercel.json](../../../web/vercel.json)). All Tier 1 mechanically-verifiable checks specified by the Architect plan pass: JSON is valid, the diff is scoped to exactly one file with exactly the planned +6/-0 lines, the new `/main.dart.js` rule sits at a strictly later array index than `/:path*.js` so it wins under Vercel's documented last-rule-wins precedence, its `Cache-Control` value string matches `/index.html` and `/version.json` byte-for-byte, and the `rewrites` block is untouched. `flutter analyze` and `flutter test` were run as baseline gates and are no-ops as expected (no Dart source changed). This is code-path/static-config analysis only — no runtime or on-device verification was performed or attempted, per QA scope. Tier 2 (live-deploy curl checks) is owner-run and included below as a punch list for Tony.

## Architect Scope Review

- Branch `bug/web-main-dart-js-immutable-cache` matches the slug in both `ARCHITECT_PLAN.md` and `ENGINEER_REPORT.md`.
- Working tree: `web/vercel.json` modified (uncommitted, expected), plus untracked `docs/features/bug/web-main-dart-js-immutable-cache/` — no unexpected changes present.
- No `QA_REPORT.md` existed for this slug prior to this run.

## Completeness Check

All 5 Engineer Task Breakdown steps from the plan were completed:
1. Located `"source": "/:path*.js"` rule — confirmed.
2. Inserted exactly one new rule object for `/main.dart.js` immediately after it and before `/flutter_bootstrap.js` — confirmed via diff.
3. Indentation and trailing-comma style match surrounding sibling rules — confirmed.
4. No other rule object or the `rewrites` array modified — confirmed.
5. File saved, JSON remains valid — confirmed.

No partial implementation, no missing edge cases relative to plan scope (deliberately excluded items — `.map` rule, `.part.js` rule, `flutter_service_worker.js` reorder — correctly left untouched).

## Behavior Verification

Code-path/static-config analysis only (no runtime exercised, no deploy performed — none is in scope for this fix or for QA).

- Root cause (glob `/:path*.js` applying `immutable` to non-hashed `main.dart.js` URL) is addressed by adding a more-specific, later rule that overrides it under Vercel's last-rule-wins precedence — matches plan's proposed solution exactly.
- No extra behavior added: exactly one rule object added, nothing else in scope touched.

## Regression Check

**Risk: LOW** (matches Architect's assessment).

- Diff touches only `web/vercel.json`; no Dart/Flutter code, no init order, no auth/session, no RPC signatures, no platform-specific code affected.
- `rewrites` block (governs `/api/calendar-feed` proxy and SPA fallback) confirmed byte-identical — grepped diff for `rewrites`, no match.
- All off-limits rules (`/:path*.js`, `/flutter_bootstrap.js`, `/icons/:path*`, `/assets/:path*`, `/canvaskit/:path*`, `/version.json`, `/index.html`, `.well-known/*`, `/flutter_service_worker.js`) confirmed byte-identical in the diff — none appear as changed lines.
- Platform parity: web-only change by design; no iOS/Android/macOS files touched (confirmed via `git diff --name-only`).

## Database Safety

Not applicable — no migrations, RLS, RPCs, or schema changes in this diff. Confirmed via diff scope (single non-SQL file).

## Analyzer Results

`flutter analyze` — **No issues found!** (ran in 3.6s). Zero delta as expected, no Dart source changed.

## Test Results

`flutter test` — **All tests passed!** (346 tests). Zero delta as expected, no Dart source changed.

## Diff Safety Review

- Grepped the diff for `TODO|FIXME|debugPrint(|api_key|secret|password|token` — no matches.
- No leftover test scaffolding, no accidental deletions, no unrelated formatting churn — diff is exactly the planned 6-line insertion.

## Change Budget Review

- Plan budget: `web/vercel.json` +6 lines, 0 new files, 0 new public classes, 0 new dependencies, 0 new tests.
- Actual (`git diff --numstat` vs HEAD): `web/vercel.json` +6/-0. Exact match, no variance.
- 0 new files, 0 new dependencies — confirmed via `git diff --name-only` (single file) and no `pubspec.yaml` change.

## Code Efficiency Review

Not applicable — single static JSON object insertion, no Dart code, no new symbols to check against existing helpers.

## Tier 1 Mechanical Verification (executed)

| # | Check | Result |
|---|---|---|
| 1 | JSON validity (`python3 -c "import json; json.load(open('web/vercel.json'))"`) | PASS — exits 0 |
| 2 | Diff scope + line count (`git diff --stat` / `--numstat` vs HEAD) | PASS — `web/vercel.json` only, +6/-0, matches budget exactly |
| 3 | Rule ordering (`/main.dart.js` array index vs `/:path*.js` index) | PASS — `/main.dart.js` is object index 6 (0-based), `/:path*.js` is index 5; strictly later |
| 4 | Value-string exact match vs `/index.html` and `/version.json` | PASS — all three are literal `no-cache, no-store, must-revalidate` |
| 5 | Off-limits files untouched (`git diff --name-only` vs HEAD) | PASS — returns exactly `web/vercel.json` |
| 6 | `rewrites` block untouched | PASS — not present in diff; full-file read confirms both `rewrites` entries (`/api/calendar-feed`, SPA fallback) unchanged |
| 7 | `flutter analyze` | PASS — no issues |
| 8 | `flutter test` | PASS — 346/346 |

Note: Tier 1 check #2 in the plan referenced `git diff main` — this environment compared against `HEAD` per QA mode instructions (uncommitted working-tree diff), which is the correct form here since nothing is committed yet; results are equivalent for this single-commit-behind-main branch state (confirmed no other divergence from `main` beyond this working-tree change, via the untracked-only + single-modified-file status).

## Manual Verification Punch List (Tier 2 — Tony, owner-run, after next deploy)

QA cannot execute these (no deploy triggered by this pipeline, no live-app driving permitted). Run after the next `./tools/deploy_web.sh` deploy completes and the alias points at `app.bandroadie.com`:

1. Deploy web as usual (`./tools/deploy_web.sh` or existing deploy path). Wait for the deploy to complete and the alias to point at `app.bandroadie.com`.
2. Run `curl -sI https://app.bandroadie.com/main.dart.js | grep -i cache-control` — **expected:** `cache-control: no-cache, no-store, must-revalidate`.
3. Run `curl -sI https://app.bandroadie.com/main.dart.js | grep -iE '^(age|x-vercel-cache):'` — **expected:** `x-vercel-cache: HIT` may appear on a second identical curl, but the `cache-control` value from step 2 must still read no-cache.
4. Run `curl -sI https://app.bandroadie.com/flutter_bootstrap.js | grep -i cache-control` — **expected:** `cache-control: public, max-age=31536000, immutable` (unchanged).
5. Run `curl -sI https://app.bandroadie.com/canvaskit/canvaskit.js | grep -i cache-control` — **expected:** `cache-control: public, max-age=31536000, immutable` (unchanged).
6. Run `curl -sI https://app.bandroadie.com/index.html | grep -i cache-control` — **expected:** `cache-control: no-cache, no-store, must-revalidate` (unchanged).
7. Run `curl -sI https://app.bandroadie.com/version.json | grep -i cache-control` — **expected:** `cache-control: no-cache, no-store, must-revalidate` (unchanged); body's build number should match today's build.

If any step 2–7 fails, roll back via `./tools/deploy_web.sh --rollback <prev-deployment-url>`.

## Issues Found

None.

### Critical

None.

### Warnings

None.

### Suggestions

None.
