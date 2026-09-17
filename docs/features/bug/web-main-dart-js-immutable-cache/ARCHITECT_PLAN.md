# ARCHITECT_PLAN — bug/web-main-dart-js-immutable-cache

## Feature Slug

`bug/web-main-dart-js-immutable-cache`

## Feature Title

Web app serves stale `main.dart.js` indefinitely due to overly broad immutable cache header

## Problem Summary

Returning web users at `app.bandroadie.com` do not see UI changes from recent deploys (specifically noted: the band edit overlay redesign from PR #307) even though the deployment itself succeeded (`version.json` returns today's build number). The Flutter web loader (`flutter_bootstrap.js`) always requests the compiled app bundle at the fixed, non-content-hashed URL `main.dart.js`. That filename is currently served by Vercel with `Cache-Control: public, max-age=31536000, immutable`, so any browser or edge cache that fetched `main.dart.js` once will keep serving that stale copy for up to a year — silently hiding every subsequent deploy's UI/behavior changes from returning users until they hard-reload or the cache naturally expires.

## Root Cause

**Confidence: HIGH.** Confirmed by both static config inspection and live production HTTP headers.

`web/vercel.json` contains a generic header rule:

```json
{
  "source": "/:path*.js",
  "headers": [
    { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
  ]
}
```

The Vercel path-to-regexp source `/:path*.js` matches every path ending in `.js` at any depth, including the literal filename `main.dart.js` at the site root. `flutter_bootstrap.js` (fetched live) contains `entrypointUrl:s=m("main.dart.js")`, confirming the loader always requests that exact, non-hashed URL every build. So the URL is stable across deploys while the file's byte content changes every build — the exact combination that must not carry `immutable`.

Live production headers (captured during diagnosis, `curl -sI https://app.bandroadie.com/main.dart.js`) return:

```
cache-control: public, max-age=31536000, immutable
x-vercel-cache: HIT
age: 3668
content-type: application/javascript; charset=utf-8
```

confirming both that (a) the immutable directive is being applied to `main.dart.js` in production, and (b) Vercel's edge CDN is already serving a cached copy (`HIT` with an hour-plus age). Browser caches inherit the same directive.

**Vercel header precedence — validated observation (relevant to fix design).** Live curl also shows `/flutter_service_worker.js` currently returns `cache-control: public, max-age=31536000, immutable`, not `no-cache, no-store, must-revalidate` as the position-5 rule in `web/vercel.json` intends. This empirically confirms Vercel applies all matching header rules but resolves same-header-key conflicts with **last-rule-wins**: the position-6 `/:path*.js` immutable rule silently overrides the earlier position-5 no-cache rule for the service worker. This behavior determines where the fix rule must be placed (after the glob, not before). See "Additional Finding" below.

## Existing System Analysis

- [web/vercel.json](web/vercel.json) — the Vercel deployment config that lives alongside `web/index.html`. Flutter's `flutter build web` copies `web/vercel.json` verbatim into `build/web/vercel.json`, and [tools/deploy_web.sh](tools/deploy_web.sh) then runs `vercel --prod` from `build/web/`, so this file is exactly what governs production cache headers.
- [web/index.html](web/index.html) line 132: `<script src="flutter_bootstrap.js" async></script>` — confirms the site uses the modern Flutter bootstrap loader, which in turn fetches `main.dart.js`.
- [tools/build_web.sh](tools/build_web.sh) line 215 and [tools/deploy_web.sh](tools/deploy_web.sh) line 272 both invoke `flutter build web --release --pwa-strategy=none`. Two consequences relevant here:
  1. `--pwa-strategy=none` means the Flutter service worker is generated but not aggressively caching assets, so the (silently broken) `flutter_service_worker.js` cache header today has no user-visible effect. This is why the reported bug is `main.dart.js`-only in practice.
  2. No `--source-maps` flag → `main.dart.js.map` is not shipped in release, so no separate rule for it is needed.
- No `deferred as` / `loadLibrary()` in `lib/` (checked) — no `main.dart.js_*.part.js` deferred parts are produced. `main.dart.js` is the only stable-URL, per-build-changing bundle.
- Other `.js` files matched by the current `/:path*.js` glob:
  - `flutter_bootstrap.js` — stable content per Flutter SDK version, correctly kept immutable (explicit rule at position 7 restates immutable; redundant but harmless and matches Manager's intent).
  - `canvaskit/canvaskit.js` (and other canvaskit `.js`) — content-addressed and stable within a canvaskit release; both the glob and the position-10 `/canvaskit/:path*` rule set immutable, no conflict.
  - `flutter_service_worker.js` — see "Additional Finding" below.

## Additional Finding — Out of Scope, Documented

Manager's Feature Input states `flutter_service_worker.js` is "correctly configured with `no-cache, no-store, must-revalidate` in the same file and do[es] revalidate properly." Live curl during diagnosis contradicts this: the SW is served with `public, max-age=31536000, immutable` because the position-6 `/:path*.js` glob overrides the position-5 explicit `/flutter_service_worker.js` no-cache rule (same last-rule-wins precedence that causes the reported `main.dart.js` bug). Today this has no observable user impact because Flutter web is built with `--pwa-strategy=none`, so the SW isn't actively caching. This is called out here per the Architect discrepancy-reporting rule but is **explicitly not fixed by this plan** — it's a separate latent bug that Manager may want to file separately. Fixing it here would expand scope beyond the reported problem.

## Proposed Solution

Add **one** new rule to `web/vercel.json`'s `headers` array, placed **after** the existing `/:path*.js` immutable rule, that pins `/main.dart.js` to `Cache-Control: no-cache, no-store, must-revalidate` — the same directive already used for `/index.html` and `/version.json`. Because Vercel resolves same-header-key conflicts with last-rule-wins (empirically confirmed above), placing this rule after the glob makes the override deterministic without needing to remove, reorder, or regex-exclude anything else.

Explicit non-goals of this fix:
- Do not touch `/canvaskit/*`, `/icons/*`, `/assets/*`, or `/flutter_bootstrap.js` rules (Manager's explicit don't-touch list).
- Do not touch `/flutter_service_worker.js` (see Additional Finding).
- Do not remove or reorder the `/:path*.js` glob — genuinely stable JS assets (`flutter_bootstrap.js`, canvaskit `.js` if not already caught by later `/canvaskit/:path*` rule) still legitimately want long-lived immutable caching.
- Do not add a rule for `/main.dart.js.map` — release builds don't emit it (no `--source-maps` flag). A defensive rule would be dead code today.
- Do not add rules for `/main.dart.js_*.part.js` deferred parts — the app has no `deferred as` / `loadLibrary()` usage.
- No Dart/Flutter source code changes.
- No deploy triggered by this fix. Tony deploys on his own schedule.

## Database Impact

Not applicable — no migrations, RLS policies, RPCs, triggers, or schema changes. This is a Vercel edge-config-only fix.

## Flutter Architecture Changes

Not applicable — no changes to init order, providers, repositories, controllers, screens, or any Dart source. No changes to `main.dart`, no changes to app initialization sequence. Not touching `--dart-define` config or platform-conditional code paths. Init order (`WidgetsFlutterBinding` → URL strategy → orientation lock → `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp` [native only] → `DeepLinkService` → `runApp`) is completely untouched by this fix.

## Files to Create

None.

## Files to Modify

- [web/vercel.json](web/vercel.json) — add a single new header rule object for `/main.dart.js` immediately after the existing `/:path*.js` rule and immediately before the existing `/flutter_bootstrap.js` rule. Rule body:

  ```json
  {
    "source": "/main.dart.js",
    "headers": [
      { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
    ]
  }
  ```

  Preserve existing JSON formatting (4-space indent, trailing commas as JSON permits, order of all other rules unchanged). Ensure the trailing comma on the preceding `/:path*.js` closing `}` is retained and a trailing comma is added on the new rule's closing `}` so the following `/flutter_bootstrap.js` rule remains syntactically valid.

## Files Off-Limits

- [web/vercel.json](web/vercel.json) — the existing `/:path*.js`, `/flutter_bootstrap.js`, `/icons/:path*`, `/assets/:path*`, `/canvaskit/:path*`, `/version.json`, `/index.html`, `.well-known/*`, `rewrites`, and `/flutter_service_worker.js` rules must be left byte-identical. Only the single new `/main.dart.js` object is added.
- [vercel.json](vercel.json) (repo root) — this is the marketing/root project config, not the app; do not touch.
- [marketing/vercel.json](marketing/vercel.json) — separate marketing site project, out of scope.
- [web/index.html](web/index.html) — do not touch; the loader mechanics are correct.
- [tools/deploy_web.sh](tools/deploy_web.sh), [tools/build_web.sh](tools/build_web.sh) — do not touch; no deploy is being executed as part of this fix.
- All Dart source under `lib/`, all tests under `test/`, `pubspec.yaml`, `pubspec.lock`, any `*.entitlements`, `AndroidManifest.xml`, iOS Info.plist, `--dart-define` config — all off-limits. This is config-only.
- All Supabase migrations, RPCs, edge functions — off-limits.

## Change Budget

- Expected net line delta per file:
  - [web/vercel.json](web/vercel.json): **+6 lines** (one new rule object formatted per existing style: opening `{`, `"source"` line, `"headers": [` line, single header object line, closing `]`, closing `},`).
- Expected new files: **0**
- Expected new public classes/methods: **0** (config file, no code)
- Expected new dependencies: **0**
- Expected new tests: **0** (see Verification Plan for why a Dart unit/widget test isn't the right validation surface here)

## System Impact Map

- Gigs: unaffected
- Rehearsals: unaffected
- Setlists: unaffected
- Members: unaffected
- Auth: unaffected (auth flows through `/auth/confirm` and deep links; `main.dart.js` caching does not affect PKCE OTP verification)
- Routing: unaffected (Vercel `rewrites` block unchanged)
- Notifications: unaffected
- Platforms:
  - Web (app.bandroadie.com): **affected — this is the fix**
  - iOS: unaffected
  - Android: unaffected
  - macOS: unaffected

## Regression Risk

**LOW.**

Justification:
- Config-only change to a single file.
- No Dart/Flutter code changes; no init-order changes; no `--dart-define` changes; no auth/session/routing/DB touched.
- The only behavior change is that HTTP responses for exactly one URL path (`/main.dart.js`) change their `Cache-Control` header value from `public, max-age=31536000, immutable` to `no-cache, no-store, must-revalidate`. All other paths' headers are byte-identical.
- Worst-case failure modes:
  - If Vercel's precedence turns out to differ from empirically-confirmed last-rule-wins (already validated via live curl of `/flutter_service_worker.js` above): `main.dart.js` continues to be served with `immutable`, i.e., the current broken state persists. No new breakage — this is the same as pre-fix behavior.
  - If the JSON becomes invalid (malformed comma or brace from a careless edit): Vercel rejects the deploy at build time before it goes live, so production stays on the last-good deploy. No user impact.
- The fix does not affect long-cached genuinely-immutable assets (`canvaskit/*`, `icons/*`, `assets/*`, `flutter_bootstrap.js`), so page load performance for returning users is unchanged.

## Engineer Task Breakdown

1. Open [web/vercel.json](web/vercel.json).
2. Locate the existing rule object with `"source": "/:path*.js"` (currently around lines 40–45).
3. Immediately after that rule's closing `},`, and before the existing rule object with `"source": "/flutter_bootstrap.js"`, insert exactly one new rule object:

   ```json
       {
         "source": "/main.dart.js",
         "headers": [
           { "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }
         ]
       },
   ```

   matching the existing 4-space base indent of the `headers` array elements and the existing 6-space / 8-space nested indent already used in surrounding rules. Preserve the trailing comma pattern used by the surrounding sibling objects.
4. Do not modify any other rule object, the `rewrites` array, or any other file.
5. Save the file.

That is the complete implementation scope. Engineer must not add a `main.dart.js.map` rule, not add a `main.dart.js_*.part.js` rule, not reorder the `/flutter_service_worker.js` rule, not add explanatory JSON comments (JSON doesn't support them), and not touch anything outside `web/vercel.json`.

## Verification Plan

### Tier 1 — QA-mechanically-executable (no running app required)

These are all things QA can run without launching, building, or driving the app, and they must pass before this can be marked APPROVED:

1. **JSON validity** — `python3 -c "import json,sys; json.load(open('web/vercel.json'))"` exits 0 (or equivalent `node -e "JSON.parse(require('fs').readFileSync('web/vercel.json','utf8'))"`).
2. **Static diff scope check** — `git diff main -- web/vercel.json` shows exactly one added rule object with `"source": "/main.dart.js"` and `Cache-Control: no-cache, no-store, must-revalidate`, and no other lines removed or reordered. `git diff main --stat` shows `web/vercel.json` as the only modified file and net additions match the +6 line change budget (±1 for trailing-comma placement).
3. **Rule ordering check** — in the resulting `web/vercel.json`, the `/main.dart.js` rule appears at a strictly later array index than the `/:path*.js` rule. This is the mechanically-necessary condition for the fix to work under Vercel's last-rule-wins semantics; a rule placed before the glob would be silently overridden (that is exactly the pre-existing pattern with `/flutter_service_worker.js` this plan deliberately does not "fix").
4. **Value-string exact match check** — the new rule's `Cache-Control` value is byte-identical to the existing `/index.html` and `/version.json` rules' value: literal `no-cache, no-store, must-revalidate`. Grep both for uniformity.
5. **Off-limits files untouched** — `git diff main --name-only` returns exactly `web/vercel.json` and nothing else.
6. **`flutter analyze`** — passes (should be a no-op since no Dart changed, but part of standard QA gate).
7. **`flutter test`** — passes (should be a no-op since no Dart changed, but part of standard QA gate).

There is no meaningful new unit or widget test to add for this fix — the surface being changed is a static Vercel edge config, not Dart runtime behavior. Adding a Dart test that reads and parses `web/vercel.json` would test the test itself, not the fix. QA should not invent one.

### Tier 2 — Owner-run (Tony) after deploy — hand this punch list to Tony verbatim

QA cannot run these steps (no running app / no deploy is available in QA's environment). QA must include this exact numbered punch list in the PR/handoff so Tony runs them after his next production web deploy. Each step lists expected result immediately after the command; a failure at any step means the fix did not land correctly and Tony should rollback via `./tools/deploy_web.sh --rollback <prev-deployment-url>`.

1. Deploy web as usual (`./tools/deploy_web.sh` or existing deploy path). Wait for the deploy to complete and the alias to point at `app.bandroadie.com`.
2. Run `curl -sI https://app.bandroadie.com/main.dart.js | grep -i cache-control` — expected: `cache-control: no-cache, no-store, must-revalidate`. (This is the fix's success condition.)
3. Run `curl -sI https://app.bandroadie.com/main.dart.js | grep -iE '^(age|x-vercel-cache):'` — expected: after a second identical curl, `x-vercel-cache: HIT` may appear (Vercel edge may cache the response object even with no-cache), but the `cache-control` value from step 2 must still be no-cache; browsers and downstream caches will honor it.
4. Run `curl -sI https://app.bandroadie.com/flutter_bootstrap.js | grep -i cache-control` — expected: `cache-control: public, max-age=31536000, immutable` (unchanged — bootstrap is a stable shim per Manager's intent).
5. Run `curl -sI https://app.bandroadie.com/canvaskit/canvaskit.js | grep -i cache-control` — expected: `cache-control: public, max-age=31536000, immutable` (unchanged — canvaskit is content-addressed).
6. Run `curl -sI https://app.bandroadie.com/index.html | grep -i cache-control` — expected: `cache-control: no-cache, no-store, must-revalidate` (unchanged).
7. Run `curl -sI https://app.bandroadie.com/version.json | grep -i cache-control` — expected: `cache-control: no-cache, no-store, must-revalidate` (unchanged); the value string should also equal today's build number in the body.

Once steps 2–7 all pass, the fix is verified for **new visits after the deploy and for returning users on browsers that were not already caching `main.dart.js` under the old immutable directive**. See Rollout Strategy for the one-time transition cost for users already holding an immutable cache entry.

## QA Regression Areas

Scope QA regression to what's mechanically verifiable without a running app; do not attempt manual UI walkthroughs:

- **JSON parseability** and **diff-scope containment** as per Tier 1 above — these are the only mechanical regressions possible from this change.
- **`flutter analyze` + `flutter test`** as baseline standard gates — expect zero delta, because no Dart source is touched.
- **Off-limits enumeration** — QA must explicitly verify `git diff main --name-only` == `web/vercel.json`. Anything else in the diff means Engineer overstepped scope; QA blocks.
- **No changes to `rewrites` block** — QA should explicitly grep the diff for `rewrites` and confirm no changes; a modified `rewrites` block would silently break `/api/calendar-feed` proxying or the SPA fallback.

QA does not need to (and cannot) regression-test Gigs / Rehearsals / Setlists / Members / Auth / Routing / Notifications — this fix has no code path into any of them.

## Rollout Strategy

- **This plan does not deploy.** Tony deploys on his own cadence via `./tools/deploy_web.sh`.
- **Transition cost — one-time only.** After Tony deploys the fix:
  - New visitors, and returning users whose browser cache of `main.dart.js` has already been evicted, immediately pick up the new bundle on their next visit and thereafter always revalidate.
  - Returning users whose browsers still hold a `main.dart.js` cache entry from a *pre-fix* deploy will keep serving that stale copy until: (a) they do a hard reload / clear cache, (b) their browser evicts the entry, or (c) the entry's max-age naturally expires (up to a year, but browsers typically evict LRU well before that). This is inherent to the pre-fix `immutable` directive Manager cannot retroactively unset — those cache entries have already been committed by the browser.
  - Vercel's edge CDN typically purges its own cache for the affected path on each new deploy, so the edge itself will begin serving the corrected header immediately.
  - **From this deploy onward**, every subsequent deploy will reach every browser and edge on the next visit. This is the desired steady-state.
- **Rollback**: `./tools/deploy_web.sh --rollback <prior-deployment-url>` if a Tier 2 verification step fails.
- **No coordination with iOS/Android/macOS builds needed** — web-only change.

## Out of Scope

- Fixing the analogous silent bug affecting `/flutter_service_worker.js` (documented in Additional Finding). Currently harmless due to `--pwa-strategy=none`; deserves a separate ticket if Manager wants to address it. Not fixed here to keep this change genuinely minimal and to respect Manager's stated (though empirically inaccurate) belief that the SW rule already works.
- Refactoring `web/vercel.json` to reduce reliance on last-rule-wins precedence (e.g., replacing the `/:path*.js` glob with explicit per-file immutable rules). More maintainable in the long run, but larger diff and outside the reported bug's scope.
- Re-evaluating the `--pwa-strategy=none` build flag or reconsidering whether BandRoadie should use the Flutter web service worker at all.
- Adding a defensive rule for `/main.dart.js.map` (release builds don't emit source maps).
- Adding rules for deferred `.part.js` files (no `deferred as` / `loadLibrary()` in the app).
- Any changes to [vercel.json](vercel.json) (repo root) or [marketing/vercel.json](marketing/vercel.json).
- Purging existing users' stale browser caches — not technically achievable server-side once `immutable` has been committed to a client; users will naturally recover on hard-reload or eviction.
- Triggering a deploy as part of this change.
