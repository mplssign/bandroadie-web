# ARCHITECT_PLAN — bug/repo-quick-wins-batch-20260910-audit

## Feature Slug

`bug/repo-quick-wins-batch-20260910-audit`

## Feature Title

Quick-win cleanup batch: redundant _isMarketingHost() calls, non-const tuning color map, duplicated Edge Function CORS headers

## Problem Summary

Three small, independently-verified findings from the 2026-09-10 optimization audit, re-confirmed against current code on 2026-09-11. None has a user-facing symptom or a behavior-change contract — this is internal-quality maintenance bundled into one pass (same pattern as PR #183's `project_ui_small_fixes_batch`) because each item is trivially small on its own. Each item touches a completely unrelated part of the codebase and a disjoint file set, so QA verifies them independently, not as a single blob. Engineer does not commit at any point; all three items land as uncommitted changes in a single working tree that Manager commits as the pipeline's one commit after literal `QA: APPROVED`.

- **Item 1 (`lib/main.dart`)**: `_isMarketingHost()` is a pure function called redundantly from `onGenerateRoute`. Harmless duplication, but three places to keep in sync if the check ever changes.
- **Item 2 (`lib/features/setlists/tuning/tuning_helpers.dart`)**: `tuningBadgeColor()` allocates a new ~47-entry `Map<String, Color>` on every call because the map literal is `final` inside the function body rather than a file-level `const`. Called per-song-card render wherever a tuning badge is shown.
- **Item 3 (`supabase/functions/*/index.ts`)**: Nine independent, drifted copies of `corsHeaders` — four are silently missing `Access-Control-Allow-Methods`, one restricts to `GET, OPTIONS` (`calendar-feed`), one carries `X-Internal-Secret` and drops `Authorization` (`send-push`). No `_shared/` directory exists.

## Root Cause

### Item 1 — `_isMarketingHost()` redundancy

**Confidence: HIGH.** Directly verified.

- `bool _isMarketingHost()` defined at [lib/main.dart#L132-L137](lib/main.dart#L132-L137).
- Call sites confirmed by grep: lines 132 (definition), **181**, **214**, **223**.
- Lines 181 and 214 are both inside the `onGenerateRoute` closure (first inside the `if (uri.path == '/' || uri.path == '/app')` block, second in the final fallback). Line 223 is inside a **sibling** closure `onUnknownRoute` — not `onGenerateRoute`, contrary to the Feature Input's phrasing (see §Existing System Analysis → Item 1 discrepancy).
- The two `onGenerateRoute` call sites are the actual redundancy: both fire on the same closure invocation, computing the same string comparison twice. `onUnknownRoute`'s single call is not redundant on a per-invocation basis.

### Item 2 — `tuningBadgeColor()` non-const map

**Confidence: HIGH.** Directly verified.

- `Color tuningBadgeColor(String? tuningKey)` at [lib/features/setlists/tuning/tuning_helpers.dart#L205-L307](lib/features/setlists/tuning/tuning_helpers.dart#L205-L307).
- The `final colorMap = <String, Color>{...}` literal starts at [lib/features/setlists/tuning/tuning_helpers.dart#L224](lib/features/setlists/tuning/tuning_helpers.dart#L224) and closes at [lib/features/setlists/tuning/tuning_helpers.dart#L304](lib/features/setlists/tuning/tuning_helpers.dart#L304) — 47 entries (counted, not "~50" per the Feature Input, but immaterial).
- Every key is a string literal, every value is a `const Color(0xFF…)` — the entire map is `const`-eligible. `final` (not `const`) forces a new `LinkedHashMap` allocation on each call.
- Function is called from every tuning-badge render site (song cards, badges, filter chips). Not hot-loop CPU, but a strict-no-op-cost fix.

### Item 3 — Drifted Edge Function CORS headers

**Confidence: HIGH.** Verified across all 9 Edge Function `index.ts` files. `supabase/functions/_shared/` does not exist.

The nine functions cluster into four groups:

| Group | Functions | `Allow-Methods` | `Allow-Headers` value string |
| --- | --- | --- | --- |
| A | `calendar-feed` (L471) | `GET, OPTIONS` | `Content-Type` |
| B | `exit-demo-session` (L46), `send-band-invite` (L40), `send-bug-report` (L56) | `POST, OPTIONS` | `Content-Type, Authorization, x-client-info, apikey` |
| C | `send-push` (L126) | `POST, OPTIONS` | `Content-Type, X-Internal-Secret, x-client-info, apikey` (drops `Authorization`, adds `X-Internal-Secret`) |
| D | `accept-invite` (L11), `getsongbpm_lookup` (L46), `itunes_search` (L8), `musicbrainz_search` (L8) | *(absent)* | `authorization, x-client-info, apikey, content-type` (lowercase, different ordering) |

All 9 also declare `Access-Control-Allow-Origin: *`. OPTIONS-handler response bodies also drift (`"ok"` 200 vs. `null` 204) but that is **not** in scope for this fix — only the `corsHeaders` object itself is being consolidated.

## Existing System Analysis

### Item 1 — Feature Input vs. code discrepancies

Per the "trust the code and note the discrepancy" guardrail:

1. **Call-site location.** Feature Input asserts all 3 sites are "inside the same `onGenerateRoute` routing logic". Actually 2 are in `onGenerateRoute` and 1 is in the **sibling** `onUnknownRoute` closure. `onGenerateRoute` and `onUnknownRoute` are mutually-exclusive per route resolution (Flutter calls one or the other), so the true redundancy is 2 calls per `onGenerateRoute` invocation. The `onUnknownRoute` call is exactly-once-per-invocation already.
2. **"Compute once ... reference at all 3 use sites".** With the discrepancy above, the minimum-change fix that eliminates all per-invocation redundancy is a single local `final isMarketingHost = _isMarketingHost();` at the top of `onGenerateRoute`, replacing the two call sites there. Adding a second local to `onUnknownRoute` would require rewriting its arrow closure `(settings) => fadeSlideRoute(...)` into a block closure `(settings) { ... return ...; }` for zero dedup gain — pure churn. This plan therefore modifies **only** the two `onGenerateRoute` call sites and explicitly leaves `onUnknownRoute` untouched. This is a deliberate deviation from the Feature Input's "all 3 use sites" phrasing, called out here so review understands the count.
3. **`_isMarketingHost()` definition is unchanged.** Its body reads `Uri.base.host` once and returns a `bool`. No caching, no hoisting to a `late final` field, no rename — the function stays exactly as it is. Only its call-site count changes.

### Item 2 — hoist target details

- The current declaration is `final colorMap = <String, Color>{ … };`. To hoist, every value must be a compile-time constant. All 47 values are `const Color(0xFF…)` — verified — so the map literal is `const`-eligible without any other change.
- Comment blocks inside the map (`// Standard`, `// Half-Step`, …) group entries by tuning family. These will be preserved verbatim in the hoisted top-level const so the file's structure/searchability is unchanged.
- The hoisted map will be file-private (`_tuningBadgeColorMap`) to keep it out of `tuning_helpers.dart`'s public API surface. `tuningBadgeColor()` remains the only public interface.
- The fallback `return colorMap[normalized] ?? const Color(0xFF64748B);` becomes `return _tuningBadgeColorMap[normalized] ?? const Color(0xFF64748B);`. Fallback color unchanged.
- Existing test `test/app/theme/rose_primary_color_test.dart` (line 23) already asserts `tuningBadgeColor('open_e') == Color(0xFFBE123C)`; this test must remain passing after the hoist.

### Item 3 — shared `_shared/cors.ts` module design

**Discrepancies with the Feature Input worth calling out:**

1. **`send-push` also drops `Authorization`.** Feature Input says `send-push` "uniquely adds `X-Internal-Secret` to `Access-Control-Allow-Headers`". True — but it also drops `Authorization` from its `Allow-Headers` list (its auth is `X-Internal-Secret`, not a JWT). The preserved effective headers for `send-push` post-refactor must therefore be `"Content-Type, X-Internal-Secret, x-client-info, apikey"` — WITHOUT `Authorization`. Any refactor that merges the base default into `send-push` and picks up `Authorization` silently is a behavior change and is a Blocker.
2. **Group D header-value string casing/ordering will change.** The 4 Group-D functions today emit `Access-Control-Allow-Headers: authorization, x-client-info, apikey, content-type`. Post-refactor they will emit the base default `Content-Type, Authorization, x-client-info, apikey`. **This is CORS-spec-equivalent** — RFC 7230 header names are case-insensitive and RFC 6454's `Access-Control-Allow-Headers` list is unordered. But the raw response header STRING value at the network layer will differ. Per the Feature Input's "effective CORS response headers must be unchanged" wording, "effective" is interpreted as semantic equivalence (any browser preflight that passed before still passes after); the string-value diff is acceptable and expected. This is noted so QA does not misclassify the string diff as a regression.
3. **Deliberate change: Group D gains `Access-Control-Allow-Methods: POST, OPTIONS`.** Feature Input already flags this as the one intentional non-no-op. All four Group-D functions are POST-only handlers, so `POST, OPTIONS` is the correct value and its current absence is itself part of the drift being fixed.

**Design of `_shared/cors.ts`:**

- Export a `baseCorsHeaders: Record<string, string>` const carrying `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: POST, OPTIONS`, `Access-Control-Allow-Headers: Content-Type, Authorization, x-client-info, apikey`. This matches Group B verbatim — the majority.
- Export a `buildCorsHeaders(overrides?: { methods?: string; headers?: string }): Record<string, string>` helper. When called with an `overrides.methods` string, it **replaces** the base `Allow-Methods` (not merges). Same for `overrides.headers`. Missing/`undefined` fields fall through to the base value. `Access-Control-Allow-Origin` is not overridable — every function needs `*` and nothing in scope needs to change that.
- The 3 Group-B functions and the 4 Group-D functions can therefore say `const corsHeaders = baseCorsHeaders;` — a single-line replacement of the entire local object literal.
- `calendar-feed` says `const corsHeaders = buildCorsHeaders({ methods: "GET, OPTIONS", headers: "Content-Type" });`.
- `send-push` says `const corsHeaders = buildCorsHeaders({ headers: "Content-Type, X-Internal-Secret, x-client-info, apikey" });`.

**Preservation invariants that must hold after the refactor:**

- `calendar-feed` emits `Allow-Methods: GET, OPTIONS` (NOT `POST`) and `Allow-Headers: Content-Type` (NOT `Authorization`, NOT `apikey`). This is a public token-based iCal feed; adding POST would loosen its surface.
- `send-push` emits `Allow-Headers: Content-Type, X-Internal-Secret, x-client-info, apikey` (with `X-Internal-Secret`, WITHOUT `Authorization`). Its handler auth check reads `X-Internal-Secret`; browser preflight must be able to send it.
- Every function keeps its **existing** OPTIONS response body and status code (`"ok"` 200 for `accept-invite`/`getsongbpm_lookup`/`itunes_search`/`musicbrainz_search`, `null` 204 for `calendar-feed`/`exit-demo-session`/`send-band-invite`/`send-bug-report`/`send-push`). Do not normalize these — out of scope.
- Every function keeps its **existing declaration site** for `const corsHeaders = ...` (module-top-level for functions that have it there today, `Deno.serve` closure-local for functions that have it there today). Moving declaration sites is unrelated churn and not in scope.

### Referenced audit doc missing

The Feature Input cites `docs/reference/audits/OPTIMIZATION_AUDIT_2026-09-10.md`. That file does not exist in the repo (`docs/reference/audits/` contains only `CODEBASE_AUDIT.md` and `ICON_AUDIT_AND_LUCIDE_MIGRATION.md`). Same broken citation flagged in `docs/features/setlist-repository-rpc-wrapper-duplication/ARCHITECT_PLAN.md`. Diagnosis was validated directly against the code; the missing doc does not block this work, but Manager may want to know.

## Proposed Solution

### Item 1 — `main.dart`

Inside `onGenerateRoute` (closure begins at line 176), add `final isMarketingHost = _isMarketingHost();` as a new line **immediately after** `final uri = Uri.parse(settings.name ?? '');` (line 177). Replace `_isMarketingHost()` at lines 181 and 214 with `isMarketingHost`. `onUnknownRoute` (lines 222-227) is not modified. `_isMarketingHost()`'s definition (lines 132-137) is not modified.

### Item 2 — `tuning_helpers.dart`

Hoist the `final colorMap = <String, Color>{ … }` literal (lines 224-304) to a **file-private top-level `const _tuningBadgeColorMap = <String, Color>{ … };`** placed immediately before `Color tuningBadgeColor(String? tuningKey) {` (currently line 205), inside the existing `// BADGE COLOR MAPPING` region (lines 200-204). The map's keys, values, comments, and entry ordering must be preserved byte-identically — this is a hoist, not a re-authoring. Inside `tuningBadgeColor()`, delete the local `final colorMap = …` block (lines 224-304) and change the fallback return from `colorMap[normalized]` to `_tuningBadgeColorMap[normalized]`. Every other line of `tuningBadgeColor()` (null/empty check, capo-stripping, custom_ prefix short-circuit, normalization, fallback color) is unchanged.

### Item 3 — Edge Functions

**Create `supabase/functions/_shared/cors.ts`:**

```typescript
// Shared CORS headers for BandRoadie Supabase Edge Functions.
// Base = Group B (Content-Type, Authorization, x-client-info, apikey) — the
// majority default. Callers override Access-Control-Allow-Methods or
// Access-Control-Allow-Headers via buildCorsHeaders() only when they need
// non-default values (calendar-feed: GET-only; send-push: X-Internal-Secret).

export const baseCorsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
};

export function buildCorsHeaders(
  overrides?: { methods?: string; headers?: string },
): Record<string, string> {
  return {
    ...baseCorsHeaders,
    ...(overrides?.methods !== undefined && { "Access-Control-Allow-Methods": overrides.methods }),
    ...(overrides?.headers !== undefined && { "Access-Control-Allow-Headers": overrides.headers }),
  };
}
```

**Update each of the 9 Edge Functions**:

- Add `import { baseCorsHeaders } from "../_shared/cors.ts";` (or `import { buildCorsHeaders } from "../_shared/cors.ts";` for the 2 functions that need overrides) at the top of each `index.ts`, in the existing import block.
- Replace the existing local `const corsHeaders = { … };` object literal with:
  - **`accept-invite`, `getsongbpm_lookup`, `itunes_search`, `musicbrainz_search`, `exit-demo-session`, `send-band-invite`, `send-bug-report`** (7 functions): `const corsHeaders = baseCorsHeaders;`
  - **`calendar-feed`**: `const corsHeaders = buildCorsHeaders({ methods: "GET, OPTIONS", headers: "Content-Type" });`
  - **`send-push`**: `const corsHeaders = buildCorsHeaders({ headers: "Content-Type, X-Internal-Secret, x-client-info, apikey" });`
- Keep the declaration site exactly where it is today. Do not move `calendar-feed`'s in-closure declaration to module scope, do not move any of the module-scope declarations into the closure. Do not touch the OPTIONS response body or status. Do not touch handler logic.

## Database Impact

n/a

## Flutter Architecture Changes

- Item 1: none — one local variable added inside an existing closure.
- Item 2: one new file-private top-level `const`. No public API change; no new controllers/providers/repositories.
- Item 3: not applicable — Deno/TypeScript Edge Functions, not Flutter.

## Files to Create

- **`supabase/functions/_shared/cors.ts`** — new shared module for Item 3. Exports `baseCorsHeaders` const and `buildCorsHeaders()` function per §Proposed Solution → Item 3. ~20 lines.

## Files to Modify

- **`lib/main.dart`** (Item 1) — add one `final isMarketingHost = _isMarketingHost();` line inside `onGenerateRoute`; change 2 call sites (lines 181, 214) from `_isMarketingHost()` to `isMarketingHost`. Net +1 line.
- **`lib/features/setlists/tuning/tuning_helpers.dart`** (Item 2) — hoist the ~80-line `final colorMap` map literal to a top-level `const _tuningBadgeColorMap`; replace the local reference inside `tuningBadgeColor()`. Net 0 lines.
- **`supabase/functions/accept-invite/index.ts`** (Item 3) — add `_shared/cors.ts` import; replace local `corsHeaders` object with `baseCorsHeaders`. Net ~-3 lines.
- **`supabase/functions/calendar-feed/index.ts`** (Item 3) — same, using `buildCorsHeaders({ methods: "GET, OPTIONS", headers: "Content-Type" })`. Net ~-3 lines.
- **`supabase/functions/exit-demo-session/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-3 lines.
- **`supabase/functions/getsongbpm_lookup/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-2 lines.
- **`supabase/functions/itunes_search/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-2 lines.
- **`supabase/functions/musicbrainz_search/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-2 lines.
- **`supabase/functions/send-band-invite/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-4 lines.
- **`supabase/functions/send-bug-report/index.ts`** (Item 3) — same, using `baseCorsHeaders`. Net ~-4 lines.
- **`supabase/functions/send-push/index.ts`** (Item 3) — same, using `buildCorsHeaders({ headers: "Content-Type, X-Internal-Secret, x-client-info, apikey" })`. Net ~-4 lines.

## Files Off-Limits

- **`onUnknownRoute` in `lib/main.dart`** (Item 1) — single call site, no dedup opportunity; converting its arrow closure to a block closure adds churn for zero gain. Do not touch.
- **`_isMarketingHost()` function body itself** (Item 1) — pure and unchanged; do not rename, cache, promote to a `late final`, or alter its logic.
- **The rest of `lib/main.dart`** outside the two modified call sites and the single added `final` declaration.
- **The rest of `tuning_helpers.dart`** (Item 2) — `parseCapoTuning`, `composeCapoTuning`, `tuningShortLabel`, `tuningShortLabelAsync`, `tuningBadgeTextColor`, `tuningToDbEnum`, `isLegacyEnumSupported`, custom-tuning helpers, and every other function in the file. Do not opportunistically refactor.
- **OPTIONS response body/status in every Edge Function** (Item 3) — `"ok"` 200 vs. `null` 204 drift is real but out of scope. Leave every OPTIONS handler's `new Response(...)` call byte-identical.
- **`Deno.serve` handler bodies** (Item 3) — no changes to method-dispatch, auth, business logic. Only the `corsHeaders` declaration line and its import.
- **`supabase/functions/*/config.toml`** (Item 3) — no `verify_jwt` or other config changes.
- **`supabase/migrations/**`** (Item 3) — SQL layer untouched.
- **Every other file in `lib/`, `test/`, `supabase/`, `web/`, `android/`, `ios/`, `macos/`, `windows/`, `linux/`, and root-level configs** — no in-scope reason to touch.

## Change Budget

QA compares the actual PR diff to these numbers; if actuals fall outside the ranges, escalate to Architect before proceeding.

| File | Expected net line delta | New files | New public exports | New deps |
| --- | --- | --- | --- | --- |
| `lib/main.dart` | +1 | 0 | 0 | 0 |
| `lib/features/setlists/tuning/tuning_helpers.dart` | −1 to +1 | 0 | 0 (new symbol is file-private) | 0 |
| `supabase/functions/_shared/cors.ts` | +15 to +25 | 1 | 2 (`baseCorsHeaders`, `buildCorsHeaders`) | 0 |
| `supabase/functions/accept-invite/index.ts` | −2 to −4 | 0 | 0 | 0 |
| `supabase/functions/calendar-feed/index.ts` | −2 to −4 | 0 | 0 | 0 |
| `supabase/functions/exit-demo-session/index.ts` | −2 to −4 | 0 | 0 | 0 |
| `supabase/functions/getsongbpm_lookup/index.ts` | −1 to −3 | 0 | 0 | 0 |
| `supabase/functions/itunes_search/index.ts` | −1 to −3 | 0 | 0 | 0 |
| `supabase/functions/musicbrainz_search/index.ts` | −1 to −3 | 0 | 0 | 0 |
| `supabase/functions/send-band-invite/index.ts` | −2 to −4 | 0 | 0 | 0 |
| `supabase/functions/send-bug-report/index.ts` | −2 to −4 | 0 | 0 | 0 |
| `supabase/functions/send-push/index.ts` | −2 to −4 | 0 | 0 | 0 |
| **Totals** | **−17 to +0** | **1** | **2** | **0** |

The 2 new public exports are both in `_shared/cors.ts` — they are the module's raison d'être. No new public exports in any other file.

## System Impact Map

| System | Status |
| --- | --- |
| Setlists | affected — Item 2 (`tuningBadgeColor()` reads a hoisted `const` instead of allocating a local `final` map; return value identical) |
| Routing | affected — Item 1 (`onGenerateRoute` calls `_isMarketingHost()` once instead of twice; route resolution output identical) |
| Gigs | unaffected |
| Rehearsals | unaffected |
| Members | unaffected |
| Auth | affected — Item 3 touches `accept-invite`, `send-band-invite` CORS headers only; effective behavior unchanged for both. Handler logic and JWT verification unchanged. |
| Notifications | affected — Item 3 touches `send-push` CORS headers only; effective behavior unchanged (retains `X-Internal-Secret`, still no `Authorization`). |
| Calendar subscription (iCal) | affected — Item 3 touches `calendar-feed` CORS headers only; effective behavior unchanged (still `GET, OPTIONS` only, `Content-Type` only). |
| Bug report | affected — Item 3 touches `send-bug-report` CORS headers only; effective behavior unchanged. |
| Song enrichment (iTunes / MusicBrainz / GetSongBPM) | affected — Item 3 touches those functions' CORS headers only. Group D functions gain `Access-Control-Allow-Methods: POST, OPTIONS` (deliberate; addresses drift). |
| Demo session | affected — Item 3 touches `exit-demo-session` CORS headers only; effective behavior unchanged. |
| Deep links | unaffected |
| Init order | unaffected |
| Firebase initialization | unaffected |
| RLS / RPC / migrations | unaffected — no SQL touched |
| Platforms — iOS / Android / macOS | affected by Items 1 & 2 (shared Dart); Item 3 is server-side, no client platform impact |
| Platforms — Web | affected by all 3 items — Item 1 exercises the `_isMarketingHost()` branch, Item 2 exercises the tuning color map, Item 3 CORS headers are consumed by browser preflight |

## Regression Risk

**LOW.**

- Item 1: single-file, single-closure, no exception paths, no state — a local variable substitution for a pure function call.
- Item 2: single-file, single-function, purely a hoist — same values, same lookup, same fallback. `const` vs. `final` is the ONLY semantic difference (compile-time vs. runtime allocation). Return value byte-identical for every input.
- Item 3: multi-file but each file's diff is the same 3-line pattern — remove local literal, add import, assign shared const/helper result. Effective CORS behavior byte-identical for 5 of 9 functions; 4 gain a `POST, OPTIONS` methods header (deliberate, corrects prior drift); `send-push` and `calendar-feed` retain their overrides via the helper.
- No auth flow logic touched. No RLS touched. No migrations. No `SECURITY DEFINER` functions. No `--dart-define` config. No init-order. No new dependencies.
- All three items are fully reversible by reverting the single Manager pipeline commit post-merge. Pre-merge, because each item's changes are scoped to a disjoint set of files, a specific item can still be pulled out at review time via a working-tree reset on that item's file group without disturbing the other two.

Reasons it is not TRIVIAL:

- Item 3 changes CORS headers on 9 production Edge Functions simultaneously. A slip in `_shared/cors.ts` (e.g. wrong base header string) would silently affect every consumer's preflight response. Static diff review at QA time catches this.
- Item 2's hoist could accidentally drop or duplicate a map entry during editor manipulation. Static line-by-line comparison at QA time catches this.

## Engineer Task Breakdown

Ordered by item so each mini-scope stays visually distinct in the working-tree diff and can be reviewed and verified by QA independently. Engineer performs no `git commit`, `git add`, or `git push` at any point — every change remains uncommitted in the working tree until Manager stages and creates the pipeline's single commit after literal `QA: APPROVED`. Each task is atomic and independently revertable at the working-tree level (a `git checkout main -- <path>` on one item's file group does not disturb the other two).

### Item 1 — `lib/main.dart`

1. In `lib/main.dart`, inside the `onGenerateRoute:` closure (opens at line 176), add `final isMarketingHost = _isMarketingHost();` as a new line immediately after the existing `final uri = Uri.parse(settings.name ?? '');` (line 177). Do not add or remove any other line above or below.
2. In the same file, at the existing `if (kIsWeb && _isMarketingHost())` on line 181 (inside the `if (uri.path == '/' || uri.path == '/app')` block) and on line 214 (in the fallback), replace `_isMarketingHost()` with `isMarketingHost` — 2 occurrences, both inside `onGenerateRoute`.
3. Do NOT modify `_isMarketingHost()`'s definition (lines 132-137). Do NOT modify the `_isMarketingHost()` call inside `onUnknownRoute` at line 223 — see §Existing System Analysis → Item 1 discrepancy for why. Do NOT touch any other line.

### Item 2 — `lib/features/setlists/tuning/tuning_helpers.dart`

4. In `lib/features/setlists/tuning/tuning_helpers.dart`, add a file-private top-level `const _tuningBadgeColorMap = <String, Color>{ … };` immediately before `Color tuningBadgeColor(String? tuningKey) {` (currently line 205), placed inside the existing `// BADGE COLOR MAPPING` region banner (lines 200-204). Copy the entire body of the current in-function `final colorMap = <String, Color>{ … };` (lines 224-304) — every key, every value, every comment block, in the same order — into the hoisted `const`. Keys, values, and comments must be byte-identical.
5. In the same file, delete the local `final colorMap = <String, Color>{ … };` block that starts at line 224 and ends at line 304. Change the fallback return statement at what is currently line 306 from `return colorMap[normalized] ?? const Color(0xFF64748B);` to `return _tuningBadgeColorMap[normalized] ?? const Color(0xFF64748B);`. Do NOT modify any other line of `tuningBadgeColor()` (null/empty check on lines 206-208, capo-stripping on lines 210-212, normalization on line 213, `custom_` short-circuit on lines 216-219). Do NOT touch any other function in the file.

### Item 3 — Edge Functions

6. Create `supabase/functions/_shared/cors.ts` with the exact contents shown in §Proposed Solution → Item 3.
7. Modify `supabase/functions/accept-invite/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";` in the existing import block (below the existing `import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";`). Replace the local `const corsHeaders = { … };` object literal (currently lines 11-15) with `const corsHeaders = baseCorsHeaders;`. Do NOT touch any handler body, OPTIONS response, or other line.
8. Modify `supabase/functions/calendar-feed/index.ts`: add `import { buildCorsHeaders } from "../_shared/cors.ts";` in the existing import block at the top of the file. Replace the local in-closure `const corsHeaders = { … };` (currently lines 471-475) with `const corsHeaders = buildCorsHeaders({ methods: "GET, OPTIONS", headers: "Content-Type" });` — keep this declaration inside the `Deno.serve` closure where it is today. Do NOT move it to module scope. Do NOT touch anything else.
9. Modify `supabase/functions/exit-demo-session/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";`. Replace the local in-closure `const corsHeaders = { … };` (currently lines 46-50) with `const corsHeaders = baseCorsHeaders;`. Keep the declaration inside the closure.
10. Modify `supabase/functions/getsongbpm_lookup/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";` in the existing import block. Replace the module-top-level `const corsHeaders = { … };` (currently lines 46-49) with `const corsHeaders = baseCorsHeaders;`. Keep at module scope.
11. Modify `supabase/functions/itunes_search/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";` in the existing import block. Replace the module-top-level `const corsHeaders = { … };` (currently lines 8-11) with `const corsHeaders = baseCorsHeaders;`. Keep at module scope.
12. Modify `supabase/functions/musicbrainz_search/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";`. Replace the module-top-level `const corsHeaders = { … };` (currently lines 8-11) with `const corsHeaders = baseCorsHeaders;`. Keep at module scope.
13. Modify `supabase/functions/send-band-invite/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";`. Replace the in-closure `const corsHeaders = { … };` (currently lines 40-45) with `const corsHeaders = baseCorsHeaders;`. Keep inside the closure.
14. Modify `supabase/functions/send-bug-report/index.ts`: add `import { baseCorsHeaders } from "../_shared/cors.ts";`. Replace the in-closure `const corsHeaders = { … };` (currently lines 56-60) with `const corsHeaders = baseCorsHeaders;`. Keep inside the closure. Preserve the existing `// CORS headers - ...` comment if it directly annotates this declaration — or drop it if it now duplicates the shared module's doc comment; Engineer's judgment.
15. Modify `supabase/functions/send-push/index.ts`: add `import { buildCorsHeaders } from "../_shared/cors.ts";`. Replace the in-closure `const corsHeaders = { … };` (currently lines 126-131) with `const corsHeaders = buildCorsHeaders({ headers: "Content-Type, X-Internal-Secret, x-client-info, apikey" });`. Keep inside the closure. The absence of `Authorization` in this Allow-Headers value is intentional and must not be changed to include it.

Engineer creates no commits at any point across Items 1, 2, or 3. The item-grouping above exists so the working-tree diff naturally partitions into three reviewable groups (`lib/main.dart`; `lib/features/setlists/tuning/tuning_helpers.dart`; `supabase/functions/_shared/cors.ts` plus the 9 modified `supabase/functions/*/index.ts` files), not because the items land as separate commits — they land together in the one commit Manager creates after QA APPROVED. Do not modify any file outside those explicitly named in the tasks above.

## Verification Plan

Each item verifies independently. QA runs all 3 sub-sections and reports each item's pass/fail separately. A single item failing does not block the other two.

### Item 1 — main.dart (Tier 1, QA gate)

1.1. `flutter analyze` returns zero new warnings or errors compared to `main`.
1.2. `flutter test` passes (no new tests required; the change is a mechanical dedup).
1.3. Static diff review: exactly one new `final isMarketingHost = _isMarketingHost();` line is added inside the `onGenerateRoute` closure. Exactly 2 call sites (previously lines 181 and 214) now read `isMarketingHost` (bare local) instead of `_isMarketingHost()` (function call). The definition at lines 132-137 is byte-identical to pre-refactor. The `_isMarketingHost()` call inside `onUnknownRoute` (previously line 223) is unchanged.
1.4. `grep_search '_isMarketingHost' lib/main.dart` returns exactly 2 matches: the definition (`bool _isMarketingHost() {`) and the `onUnknownRoute` call site. The 2 former `onGenerateRoute` call sites no longer match.
1.5. Change budget: net line delta on `lib/main.dart` = +1. Any other value → escalate.

### Item 1 — main.dart (Tier 2, Tony's PR-test punch list — not a QA gate)

QA copies this exact numbered list into the QA report so Tony can run it verbatim on the PR preview / a manual build. QA cannot execute these steps.

Setup: build the branch to a web target and run locally (`flutter run -d chrome`) OR load the deployed preview URL.

1. In the browser address bar, navigate to `http://localhost:<port>/` (or the preview root URL served from `bandroadie.com`). **Expected:** the marketing landing page loads (LandingPage widget).
2. Navigate to `http://localhost:<port>/#/some/unknown/path` (or a random path under `bandroadie.com`). **Expected:** the marketing landing page loads (`onUnknownRoute` branch — falls to LandingPage because host matches marketing).
3. Navigate to `http://app.<local-preview-host>/` (or `app.bandroadie.com`). **Expected:** the AuthGate loads (login flow).
4. Navigate to `http://app.<local-preview-host>/some/unknown/path`. **Expected:** the AuthGate loads (`onUnknownRoute` branch — falls to AuthGate because host does not match marketing).
5. On native (iOS Simulator, macOS, Android emulator), launch the app. **Expected:** app opens to AuthGate as it does today (kIsWeb is false, so `_isMarketingHost()` returns false — behavior unchanged).

If any step differs from today's behavior on the same build, reset the working tree for Item 1's file group (`git checkout main -- lib/main.dart`) if the pipeline commit has not been created yet, or revert the pipeline commit if it has. Refile the failing step's expected-vs-actual to Architect.

### Item 2 — tuning_helpers.dart (Tier 1, QA gate)

2.1. `flutter analyze` returns zero new warnings or errors compared to `main`.
2.2. `flutter test` passes. The existing `test/app/theme/rose_primary_color_test.dart` `Open E tuning color is unchanged` test (`tuningBadgeColor('open_e') == const Color(0xFFBE123C)`) MUST still pass — this is the mechanical proof the hoisted const carries the same values.
2.3. Static diff review: the file gains a new top-level `const _tuningBadgeColorMap = <String, Color>{ … };` and loses the local `final colorMap = <String, Color>{ … };` inside `tuningBadgeColor()`. **Byte-identical entries required**: QA opens the pre-refactor `final colorMap` block (currently lines 224-304) side-by-side with the post-refactor top-level `const _tuningBadgeColorMap` and confirms every one of the 47 key-value pairs is identical (same key string, same `const Color(0xFF……)` value, same order, same interleaved `// Standard` / `// Half-Step` / etc. comments). Missing entry, duplicated entry, or altered hex value → Blocker.
2.4. Static diff review: `tuningBadgeColor()`'s function body — null/empty check, capo-stripping, `normalized` computation, `custom_` short-circuit, fallback color `const Color(0xFF64748B)` — is unchanged. Only the map-literal-and-lookup line changes. No new imports required.
2.5. `grep_search 'final colorMap' lib/features/setlists/tuning/tuning_helpers.dart` returns zero matches. `grep_search '_tuningBadgeColorMap' lib/features/setlists/tuning/tuning_helpers.dart` returns exactly 2 matches (the declaration and the one reference inside `tuningBadgeColor()`).
2.6. Change budget: net line delta on `tuning_helpers.dart` in [-1, +1]. Any other value → escalate.

### Item 2 — tuning_helpers.dart (Tier 2, Tony's PR-test punch list — not a QA gate)

Setup: build the branch to any platform (`./run.sh <device-id>`). Log in as a real user. Open a setlist with songs assigned various tunings, or use the setlist detail screen to assign tunings for spot-check.

1. Open a song with tuning `standard_e`. **Expected:** tuning badge fill is blue (`#2563EB`) — same as today.
2. Open (or assign) tuning `drop_d`. **Expected:** badge fill is olive-green (`#65A30D`).
3. Open (or assign) tuning `half_step_down`. **Expected:** badge fill is magenta (`#C026D3`).
4. Open (or assign) any `custom_<uuid>` tuning. **Expected:** badge fill is slate (`#64748B`) — the pre-normalization `custom_` short-circuit.
5. If any song exists whose tuning is a `nashville` value, confirm badge fill is amber (`#F59E0B`) and badge text is dark (`#09090B` per `tuningBadgeTextColor`'s Nashville special-case).
6. Confirm no visual difference in badge colors compared to a screenshot of the same setlist on `main`. No visible flicker, no color glitch on scroll.

### Item 3 — Edge Functions (Tier 1, QA gate)

3.1. `flutter analyze` and `flutter test` continue to pass — Edge Functions are TypeScript, so these are not directly relevant to Item 3 but must not regress from Items 1 & 2's changes.
3.2. Static SQL/migration review: `git diff main -- supabase/migrations/` returns empty output.
3.3. Static Deno file review, `_shared/cors.ts`:
    - Exports exactly `baseCorsHeaders` (const, `Record<string, string>`) and `buildCorsHeaders` (function).
    - `baseCorsHeaders` has exactly 3 keys: `Access-Control-Allow-Origin: "*"`, `Access-Control-Allow-Methods: "POST, OPTIONS"`, `Access-Control-Allow-Headers: "Content-Type, Authorization, x-client-info, apikey"`. No fourth key, no drift.
    - `buildCorsHeaders`'s `overrides.methods`, when set, replaces (not concatenates or merges) the base `Allow-Methods` string. Same for `overrides.headers`. `Allow-Origin` is not overridable.
3.4. Static review of each of the 9 modified functions: each has exactly one `import { baseCorsHeaders … }` or `import { buildCorsHeaders … }` from `../_shared/cors.ts`. Each has exactly one `const corsHeaders = …;` assignment on the RHS matching one of these patterns:
    - `accept-invite`, `exit-demo-session`, `getsongbpm_lookup`, `itunes_search`, `musicbrainz_search`, `send-band-invite`, `send-bug-report` → `const corsHeaders = baseCorsHeaders;`
    - `calendar-feed` → `const corsHeaders = buildCorsHeaders({ methods: "GET, OPTIONS", headers: "Content-Type" });`
    - `send-push` → `const corsHeaders = buildCorsHeaders({ headers: "Content-Type, X-Internal-Secret, x-client-info, apikey" });`
    Any deviation → Blocker.
3.5. Static review: `grep_search 'Access-Control-Allow-Origin' supabase/functions/` returns exactly 1 match — in `_shared/cors.ts`. No function still declares its own `Access-Control-Allow-Origin` string literal.
3.6. Static review: `grep_search 'Authorization' supabase/functions/send-push/index.ts` — the `send-push` Allow-Headers override string DOES NOT contain the word `Authorization`. This preserves the pre-refactor behavior. Presence of `Authorization` in that string → Blocker.
3.7. Static review: `grep_search 'POST' supabase/functions/calendar-feed/index.ts` — the `calendar-feed` Allow-Methods override string DOES NOT contain `POST` (still `GET, OPTIONS` only). Presence of `POST` in that string → Blocker.
3.8. Static review: OPTIONS response bodies unchanged. In each of the 9 files, the `if (req.method === "OPTIONS") { return new Response(...); }` block is byte-identical to pre-refactor (same status code, same body string or `null`). Any change to the response call site → escalate (out of scope).
3.9. Static review: handler bodies, business logic, auth checks, config.toml files — all unchanged. `git diff main -- supabase/functions/` shows only the `corsHeaders` declaration line, the import line, and (for the new file) the entire `_shared/cors.ts`. No other lines modified.
3.10. Change budget: net line delta per file within the ranges in §Change Budget. Any deviation → escalate.
3.11. `git diff main -- lib/` shows changes ONLY in `lib/main.dart` and `lib/features/setlists/tuning/tuning_helpers.dart`. `git diff main -- test/` empty. `git diff main -- supabase/` shows changes ONLY in `supabase/functions/_shared/cors.ts` (new) and the 9 modified `index.ts` files. No other files in the diff.

### Item 3 — Edge Functions (Tier 2, Tony's PR-test punch list — not a QA gate)

QA cannot deploy Edge Functions or drive an OPTIONS preflight from a browser. Tony runs these at apply / deploy time. Depending on Tony's usual workflow, this is either a preview-branch supabase deploy or a production deploy immediately post-merge; the checks are the same either way and must be done against the deployed function URL.

Setup: after the branch is deployed to whatever Supabase environment Tony uses for PR-testing, note the base URL (e.g. `https://<project-ref>.supabase.co/functions/v1`).

1. `curl -si -X OPTIONS -H "Origin: https://bandroadie.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization" '<base>/send-band-invite'`. **Expected**: HTTP 204. Response headers include `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: POST, OPTIONS`, `Access-Control-Allow-Headers: Content-Type, Authorization, x-client-info, apikey`. (This exercises a Group-B function that had these headers pre-refactor — must be byte-identical semantically.)
2. `curl -si -X OPTIONS -H "Origin: https://bandroadie.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,authorization" '<base>/itunes_search'`. **Expected**: HTTP 200 with body `ok`. Response headers include `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Methods: POST, OPTIONS` (this is the DELIBERATE change — pre-refactor this function had no Allow-Methods header), `Access-Control-Allow-Headers: Content-Type, Authorization, x-client-info, apikey`. Confirm the browser would successfully complete a preflight for a POST.
3. `curl -si -X OPTIONS -H "Origin: https://bandroadie.com" -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: content-type" '<base>/calendar-feed?token=<any>'`. **Expected**: HTTP 204. Response headers include `Access-Control-Allow-Methods: GET, OPTIONS` (NOT `POST`), `Access-Control-Allow-Headers: Content-Type` (NOT `Authorization`, NOT `apikey`). Then confirm a real GET against the same URL (with a valid calendar token) still returns the iCal feed body as it did before.
4. `curl -si -X OPTIONS -H "Origin: https://bandroadie.com" -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: content-type,x-internal-secret" '<base>/send-push'`. **Expected**: HTTP 204. Response `Access-Control-Allow-Headers` includes `X-Internal-Secret` and does NOT include `Authorization`. Then trigger a real internal-secret-authenticated push from whatever cron / edge that normally calls `send-push` and confirm it still delivers.
5. Real end-to-end on the deployed branch:
    - Send a band invite from a real user → receiver gets the email as before.
    - Look up a song by title using the enrichment flow (which calls `itunes_search` / `musicbrainz_search` / `getsongbpm_lookup`) → results still return normally.
    - Subscribe to a band calendar in a system iCal client → feed still parses.
    - Accept an invite link on web → still redirects to the app correctly.
    - Exit demo session → still returns to the anonymous / logged-out state.
    - Submit a bug report → still delivers.

If any step fails, revert the pipeline commit (the single Manager-created commit for this PR). Items 1 and 2 revert with it, but they are behavior-equivalent no-ops so nothing user-facing is lost by rolling all three back together. Refile the failing step's expected-vs-actual to Architect. If the failure surfaces pre-merge (during Tony's PR-test on the preview / preview-deploy of the branch), the working tree can instead be reset for just Item 3's file group (`git checkout main -- supabase/functions/`), Items 1 and 2 kept, and Manager creates the single commit from what remains.

### Tier 2 addendum — coverage limitation

QA gates are limited to static analysis, `flutter test`, and static diff review. QA cannot run `flutter analyze` against Deno/TypeScript files, cannot execute Deno type-checking (no Deno toolchain in the QA harness), cannot deploy Edge Functions, and cannot drive OPTIONS preflight requests. Item 3's runtime verification is therefore entirely a Tony-run activity at deploy time; QA's Tier 1 checks 3.1-3.11 are the ceiling of what QA can gate on.

## QA Regression Areas

- **Web routing** for both `bandroadie.com` and `app.bandroadie.com` (Item 1) — landing vs. auth-gate resolution paths.
- **Setlist song cards** displaying tuning badges (Item 2) — color fill for each tuning family, custom tuning slate fallback, unknown-tuning fallback.
- **All 9 Edge Functions' CORS preflight surface** (Item 3) — especially `calendar-feed` (public iCal, restricted methods), `send-push` (internal-secret auth), and the 4 Group-D functions that gain a new `Allow-Methods` header.
- **Auth flow** (Item 3) — magic-link email delivery via `send-band-invite`, accept-invite deep-link handling via `accept-invite`.
- **Song enrichment** on Web (Item 3) — iTunes / MusicBrainz / GetSongBPM lookups from browser preflight-sensitive contexts.
- **Calendar subscription** in system calendar clients (Item 3) — iCal feed still parses, still delivers per-band events.

## Rollout Strategy

Ship as **one PR against `main` containing one Manager-created commit**. Engineer performs no `git commit`, `git add`, or `git push` during implementation; every change from all three items stays uncommitted in the working tree of `bug/repo-quick-wins-batch-20260910-audit` until QA returns literal `QA: APPROVED`, at which point Manager stages the full working tree and creates the pipeline's single commit. Manager writes that commit's message covering all three items.

This does not collapse the three-item structure the plan is built around — the item groups exist in the file layout, not in the commit graph:

- Item 1's diff is confined to `lib/main.dart`.
- Item 2's diff is confined to `lib/features/setlists/tuning/tuning_helpers.dart`.
- Item 3's diff is confined to `supabase/functions/_shared/cors.ts` (new) plus the 9 `supabase/functions/*/index.ts` files.

Because the three groups are file-disjoint, PR reviewers still see and evaluate each item on its own by filtering the diff to that group's paths, and QA has already verified each item independently (§Verification Plan Items 1 / 2 / 3 Tier 1). The single-commit shape only changes how the changes are packaged for merge — not how they are reviewed or verified.

No feature flag. No coordinated deploy (Items 1 & 2 land with the standard Flutter build; Item 3 requires `supabase functions deploy` for all 9 functions and the new `_shared/cors.ts` — Tony's usual Edge Function deploy path). No `--dart-define` or environment-config change.

Rollback surface:

- Post-merge, the single Manager commit is reverted as one unit if any item regresses. Reverting takes Items 1 and 2 back with Item 3 (and vice versa), but Items 1 and 2 are pure behavior-equivalent no-ops (deduping a function call; hoisting a `const`), so there is zero user-facing loss from reverting all three even when only one item is at fault.
- Post-deploy rollback of Item 3 additionally requires `supabase functions deploy` for all 9 functions to bring production Edge Functions' CORS headers back to their pre-refactor state.
- Pre-merge, if a specific item's regression is caught during Tony's PR-test before Manager has created the pipeline commit, the working tree can be selectively reset for only that item's file group (per the paths listed above) and Manager then creates the single commit from what remains. This preserves the pipeline's one-commit-per-PR shape.

## Out of Scope

- **RPC-wrapper consolidation in `setlist_repository.dart`** — separate Feature Input `bug/setlist-repository-rpc-wrapper-duplication`, already has its own architect plan.
- Any other item in the audit's P1/P2/P3 backlog.
- `_isMarketingHost()` memoization / promotion to a `late final` field / rename.
- Rewriting `onUnknownRoute` in `lib/main.dart` to a block closure just to add a local (see §Existing System Analysis → Item 1).
- Hoisting any other map / list / literal inside `tuning_helpers.dart` (e.g. the `newToLegacy` map in `tuningToDbEnum`, which is already `const`, or any label maps in `tuningShortLabel`).
- Normalizing Edge Function OPTIONS response bodies (the `"ok"` 200 vs. `null` 204 drift is a real drift, but was explicitly excluded from the Feature Input's scope).
- Moving Edge Function `corsHeaders` declarations from in-closure to module-scope (or vice versa) — declaration site is preserved as-is per §Files Off-Limits.
- Changing `verify_jwt` config or any `config.toml` on any Edge Function.
- Changing `Access-Control-Allow-Origin: *` to a more restrictive origin — worth a separate audit item, not this batch.
- Adding Deno type-check or Edge Function CI gates — separate infrastructure work.
