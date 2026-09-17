# ENGINEER_REPORT — bug/web-main-dart-js-immutable-cache

## Feature Slug

`bug/web-main-dart-js-immutable-cache`

## Feature Title

Web app serves stale `main.dart.js` indefinitely due to overly broad immutable cache header

## Cycle Number

1

## Goal

Add a single new Vercel header rule pinning `/main.dart.js` to `Cache-Control: no-cache, no-store, must-revalidate`, placed after the existing `/:path*.js` immutable glob rule so it wins under Vercel's last-rule-wins precedence, without touching any other rule or file.

## Architect Tasks Completed

1. Located the existing `"source": "/:path*.js"` rule in [web/vercel.json](../../../web/vercel.json).
2. Inserted exactly one new rule object immediately after it and immediately before the `"source": "/flutter_bootstrap.js"` rule:
   ```json
   {
     "source": "/main.dart.js",
     "headers": [
       { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
     ]
   },
   ```
3. Matched existing 4-space base / 6-space / 8-space nested indentation and trailing-comma style used by sibling rule objects.
4. No other rule object, the `rewrites` array, or any other file was modified.

## Files Created

None.

## Files Modified

- [web/vercel.json](../../../web/vercel.json) — added the single `/main.dart.js` header rule as specified (+6 lines, no other changes).

## Analyzer Results

`flutter analyze` — **No issues found!** (ran in 3.9s)

## Test Results

`flutter test` — **All tests passed!** (346 tests, no-op as expected since no Dart source was changed)

## Code Efficiency/Bloat Check

Not applicable — config-only, single-object JSON insertion, no Dart code added. No helper/util/widget candidates to search for.

## Verification (manual steps performed)

1. `python3 -c "import json; json.load(open('web/vercel.json'))"` — exited 0, JSON valid.
2. `git diff -- web/vercel.json` — confirmed exactly one added rule object (+6 lines), placed after `/:path*.js` and before `/flutter_bootstrap.js`, no other lines changed.
3. `git diff main --name-only` — confirmed `web/vercel.json` is the only modified file relative to `main`.
4. `flutter analyze` — clean.
5. `flutter test` — all 346 tests passed.

## Deviations From Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes.
