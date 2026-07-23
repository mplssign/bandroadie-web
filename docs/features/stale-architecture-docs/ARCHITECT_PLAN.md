# ARCHITECT_PLAN.md

## 1. Feature Slug
`bug/stale-architecture-docs`

**Note on process:** This is a standard single-issue bug fix with a documentation-only scope override (per the Architect prompt). Phase 9 constraints are markdown edits, not Dart/SQL. `Database: not applicable`, `Migration policy: not required`, `Edge function deploy: not required`. Phase 4 (notification domain reference) applies normally since one of the three discrepancies concerns notification delivery architecture.

---

## 2. Problem Summary

The full-stack performance audit (`docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md`, finding DOC-1) identified three reference-doc discrepancies where documentation describes a system state that no longer matches the live project:

1. `docs/reference/architecture/architecture.md` and `docs/reference/architecture/supabase_functions.md` describe a `deliver-notifications` pg_cron-polled Edge Function as the current, deployed notification delivery mechanism. It does not exist in the live project.
2. `docs/agents/PROJECT_CONTEXT.md` lists the `_lastLoadedBandId` + `Future.microtask` pattern as open architecture debt in `GigNotifier`/`RehearsalNotifier`. Both controllers have already moved past this pattern.
3. `docs/reference/audits/CODEBASE_AUDIT.md` §4.5 lists missing static-asset cache headers as unresolved. `web/vercel.json` already has them.

This is a documentation-only correction. No app code, migrations, or edge functions change. Stale docs risk misleading future Architect sessions that treat these files as ground truth — the risk is process integrity, not runtime behavior.

---

## 3. Root Cause

Not a runtime root cause — this is a documentation-drift bug. For each of the three discrepancies, root cause is **the reference doc was never updated after the underlying system changed**, and confidence is `HIGH` for all three (each verified this session via live tool calls / direct code reads, not inherited from the audit uncritically):

| # | Discrepancy | Confidence | Verification this session |
|---|---|---|---|
| 1 | `deliver-notifications` documented as deployed/current; does not exist live | HIGH | `mcp_supabase_list_edge_functions` on live project `nekwjxvgbveheooyorjo` — re-run independently this session, confirms exactly 9 `ACTIVE` functions: `spotify_search`, `spotify_audio_features`, `musicbrainz_search`, `send-band-invite`, `send-bug-report`, `auth-confirm`, `accept-invite`, `send-push`, `calendar-feed`. Neither `deliver-notifications` nor `acousticbrainz_bpm` (also currently listed as deployed in `supabase_functions.md`) appear in the live list. |
| 2 | `_lastLoadedBandId` + `Future.microtask` listed as open debt in `GigNotifier`/`RehearsalNotifier` | HIGH | Direct code read this session: `lib/features/gigs/gig_controller.dart` and `lib/features/rehearsals/rehearsal_controller.dart` — grep for `_lastLoadedBandId` / `Future.microtask` returns no matches in either file. Both `build()` methods watch `bandFullStateProvider` and derive state via `AsyncValue.when(...)`, with no manual band-change tracking or microtask scheduling. `lib/features/calendar/calendar_controller.dart:183-186` contains an explicit code comment confirming the old pattern was replaced: *"Start async load directly — replaces the old `_lastLoadedBandId` + `Future.microtask()` pattern that caused race conditions under rapid band switching."* |
| 3 | `CODEBASE_AUDIT.md` §4.5 cache-header gap listed as unresolved | HIGH | Direct read of `web/vercel.json` this session — `headers` array includes `public, max-age=31536000, immutable` entries for `/:path*.js`, `flutter_bootstrap.js`, `/icons/:path*`, `/assets/:path*`, and `/canvaskit/:path*`. The file's own existing "Update (April 2026)" note under §4.5 is itself incomplete/stale — it says static build artifacts "remain uncached," which is no longer true. |

---

## 4. Reference Docs Consulted

Per Phase 4, all files in `docs/reference/notifications/` were read in full before any code inspection:

- `docs/reference/notifications/NOTIFICATION_SYSTEM.md` — accurately documents `send-push` as the current, webhook-triggered, synchronous delivery mechanism (Feb 2026 update). This file is **not** part of the fix — it is already correct and is the intended source of truth going forward.
- `docs/reference/notifications/notifications.md` — describes the `deliver-notifications` / pg_cron architecture in full detail as if current, with only a top-of-file banner acknowledging some internal references are outdated and pointing to `NOTIFICATION_SYSTEM.md` for "current implementation details." This file is significantly more stale than the two named in the bug report, but it is **out of scope** for this fix (see Section 18 — not one of the three discrepancies named in the Feature Input; flagging it is the extent of this plan's obligation).
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md` — describes the client-side permission flow (iOS/Android/Web), unrelated to the delivery-mechanism discrepancy. No changes needed.

Also consulted (per Phase 3/6, standard for diagnosing the reported discrepancies):
- `docs/reference/architecture/architecture.md`
- `docs/reference/architecture/supabase_functions.md`
- `docs/agents/PROJECT_CONTEXT.md`
- `docs/reference/audits/CODEBASE_AUDIT.md`
- `docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md` (finding DOC-1 — source of this bug ticket)

---

## 5. Existing System Analysis

**Edge Functions (discrepancy 1):** Live project `nekwjxvgbveheooyorjo` has 9 deployed, `ACTIVE` Edge Functions. `send-push` (`verify_jwt: false`) is triggered by a database webhook (`send_push_on_notification`) on `notifications` INSERT and delivers synchronously via FCM HTTP v1 API with OAuth2 — this matches `NOTIFICATION_SYSTEM.md` exactly. `architecture.md` and `supabase_functions.md` both additionally describe `deliver-notifications` (pg_cron, 5-minute poll, batch delivery) as deployed and "the current architecture" — this function is not in the live list. `supabase_functions.md` also lists `acousticbrainz_bpm` as deployed (`⚠️ DEAD — but deployed`); it is not in the live list either (confirmed absent from `list_edge_functions` output this session), though a local folder for it may still exist in `supabase/functions/` per the audit — that local-vs-deployed distinction is not itself part of this bug's scope beyond correcting the "deployed" claim.

**Controller pattern (discrepancy 2):** `gig_controller.dart` and `rehearsal_controller.dart` both build state by watching `bandFullStateProvider` and branching on `AsyncValue.when(data/loading/error)` — no `_lastLoadedBandId` field, no `Future.microtask()` call. `calendar_controller.dart` watches `activeBandIdProvider` directly and calls `_loadEventsForBand(bandId)`, with an inline comment explicitly documenting that this replaced the old debt pattern. Three current docs (`architecture.md`'s "Known pattern debt to avoid copying" and "Architecture Debt" table, `PROJECT_CONTEXT.md`'s "Architecture debt" and "Do not" lists) still describe this pattern as present in `GigNotifier`/`RehearsalNotifier`. Note: `architecture.md` itself is **not** named in the Feature Input for this discrepancy (only `PROJECT_CONTEXT.md` is) — see Section 10 for why `architecture.md`'s copies of this claim are being corrected anyway.

**Cache headers (discrepancy 3):** `web/vercel.json`'s `headers` array has five entries applying `public, max-age=31536000, immutable` to versioned static build artifacts (JS bundles, `flutter_bootstrap.js`, icons, assets, CanvasKit), in addition to the existing `no-cache` entries for `index.html`, `version.json`, and the service worker (correctly never cached, since those must always be fresh to avoid serving a stale app shell). `CODEBASE_AUDIT.md` §4.5's original finding text and its own "Update (April 2026)" addendum both predate this — the addendum specifically claims "Static build artifacts remain uncached," which the current `vercel.json` contradicts.

---

## 6. Proposed Solution

Correct each of the three reference docs (plus the closely-linked copies of discrepancy 2 found in `architecture.md` during Phase 5/6 inspection) to reflect the live system, with the smallest edit that removes the false claim and states the current, verified reality. No new sections, no speculative rewrites, no restructuring of unrelated content. Specifically:

1. **`architecture.md`**: Rewrite the "Push Notification Architecture" delivery-flow diagram and the "Two delivery mechanisms exist" paragraph to describe only `send-push` (synchronous webhook → FCM HTTP v1) as the current mechanism. Update the "Known pattern debt to avoid copying" note and the "Architecture Debt" table row to state the `_lastLoadedBandId`/`Future.microtask` pattern has been fixed (not present in current `GigNotifier`/`RehearsalNotifier`). Update the Cross-References table's "11 functions" count to 9. Update the "Last verified" date stamp.
2. **`supabase_functions.md`**: Remove the `deliver-notifications` and `acousticbrainz_bpm` rows from the "Deployed Edge Functions" table (neither is live) and their corresponding rows in the "Authentication Model" table. Rewrite the "Notes" section's `send-push` vs `deliver-notifications` comparison to state `send-push` is the sole, current push delivery path. Update the "Last verified" date stamp.
3. **`PROJECT_CONTEXT.md`**: Remove the `_lastLoadedBandId` bullet from "Architecture debt" and the corresponding bullet from "Do not" (both currently assert this pattern is present in `gig_controller.dart`/`rehearsal_controller.dart`, which is false).
4. **`CODEBASE_AUDIT.md`**: Update §4.5's "Update (April 2026)" note to state cache headers for static build artifacts are now present (citing the specific `vercel.json` header entries), mark the finding resolved, and remove the now-stale "add cache headers" line item from the Priority Matrix's P2 row.

No changes to `docs/reference/notifications/NOTIFICATION_SYSTEM.md` (already accurate) or `notifications.md` (stale but out of scope — flagged in Section 18).

---

## 7. Database Impact
`Database: not applicable` — no database objects, migrations, RLS policies, or RPCs are touched. This is a pure documentation correction.

---

## 8. Flutter Architecture Changes
None. No Dart files are created, modified, or otherwise touched.

---

## 9. Files to Create
None.

---

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `docs/reference/architecture/architecture.md` | Correct "Push Notification Architecture" section (delivery flow diagram + mechanism description) to describe only `send-push`, not `deliver-notifications`; correct "Known pattern debt to avoid copying" note and "Architecture Debt" table row for `_lastLoadedBandId`/`Future.microtask` to state it's fixed; update Cross-References edge-function count (11 → 9); update "Last verified" date. |
| `docs/reference/architecture/supabase_functions.md` | Remove `deliver-notifications` and `acousticbrainz_bpm` rows from "Deployed Edge Functions" and "Authentication Model" tables; rewrite "Notes" section to state `send-push` is the sole current push delivery path; update "Last verified" date. |
| `docs/agents/PROJECT_CONTEXT.md` | Remove the `_lastLoadedBandId` bullet from "Architecture debt" and the matching bullet from "Do not" under "Known Issues and Audit Findings." |
| `docs/reference/audits/CODEBASE_AUDIT.md` | Update §4.5's "Update" note to reflect cache headers now present for static build artifacts and mark resolved; remove the "add cache headers" item from the Priority Matrix P2 row. |

**Why `architecture.md` is touched even though the Feature Input only names `PROJECT_CONTEXT.md` for discrepancy 2:** Phase 5/6 inspection (reading the two named files plus cross-checking Phase 4/6 context) surfaced that `architecture.md` independently repeats the same false claim in two places (its "Known pattern debt" note and its "Architecture Debt" table). Leaving those uncorrected while fixing `PROJECT_CONTEXT.md` would still leave a reference doc asserting the same stale fact — contrary to the bug's stated goal ("Reference docs accurately reflect the live system"). This is the same discrepancy, not a new one, so it does not expand scope; it closes the gap the ticket already opened.

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| Any `.dart` file | Out of scope — documentation-only fix per Feature Input |
| Any file under `supabase/migrations/` or `supabase/functions/` | Out of scope — no schema or Edge Function code changes |
| `docs/reference/notifications/notifications.md` | Stale but not one of the three named discrepancies; flagged in Section 18, not corrected here, to keep this fix's diff scoped to what was asked |
| `docs/reference/notifications/NOTIFICATION_SYSTEM.md` | Already accurate — no change needed |
| `docs/reference/architecture/database_schema.md` | Not implicated by any of the three discrepancies |
| `docs/features/full-stack-performance-audit/ARCHITECT_PLAN.md` | Historical audit record — do not edit after the fact |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not applicable
**New files:** none

---

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected — doc reference only, no code change |
| Rehearsals | unaffected — doc reference only, no code change |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | affected (docs only) — corrects a reference doc that misdescribes the live delivery mechanism; no runtime behavior change |
| Platform (iOS / Android / Web / macOS) | unaffected |

---

## 13. Regression Risk

`LOW` (docs-only). No code path, build, or deploy is touched. The only "regression" surface is a future Architect session reading a doc — and this fix strictly removes false claims and states verified-current reality, so it can only reduce that risk, not introduce a new one. No QA/manual regression testing applies.

---

## 14. Engineer Task Breakdown

1. In `docs/reference/architecture/architecture.md`: replace the "Delivery flow" diagram and the paragraph following it in "Push Notification Architecture" to describe the synchronous `send-push` webhook path only; update the "Known pattern debt to avoid copying" bullet and the "Architecture Debt" table row for the `_lastLoadedBandId` pattern to state it is resolved; update the Cross-References table's function count from 11 to 9; update the "Last verified" date stamp at the top of the file.
2. In `docs/reference/architecture/supabase_functions.md`: remove the `deliver-notifications` and `acousticbrainz_bpm` rows from the "Deployed Edge Functions" table and their corresponding entries in "Authentication Model"; rewrite the "Notes" section bullet comparing `send-push`/`deliver-notifications` to state `send-push` is the sole current mechanism; update the "Last verified" date stamp.
3. In `docs/agents/PROJECT_CONTEXT.md`: remove the `_lastLoadedBandId` bullet from "Architecture debt" and the matching bullet from "Do not," both under "Known Issues and Audit Findings."
4. In `docs/reference/audits/CODEBASE_AUDIT.md`: update the §4.5 "Update" note to state cache headers for static build artifacts are now present (list the specific path patterns from `vercel.json`) and mark the finding resolved; remove the "add cache headers" phrase from the Priority Matrix's P2 row.

Each task is independent (different files, no shared state) and may be done in any order or in parallel.

---

## 15. Verification Plan

Per the documentation-only override, the standard Tier 1/Tier 2 pre/post-deploy SQL structure does not apply (nothing is deployed). Verification is read-based:

- **Edge functions claim:** Re-run `mcp_supabase_list_edge_functions` (or equivalent) against project `nekwjxvgbveheooyorjo` after the edit and confirm the corrected doc's function table/count matches the live list exactly (9 functions, no `deliver-notifications`, no `acousticbrainz_bpm`).
- **Controller pattern claim:** `grep -rn "_lastLoadedBandId\|Future.microtask" lib/features/gigs/gig_controller.dart lib/features/rehearsals/rehearsal_controller.dart` must return no matches (already confirmed this session) — the corrected docs must not contradict this.
- **Cache headers claim:** Re-read `web/vercel.json` and confirm the corrected `CODEBASE_AUDIT.md` §4.5 text accurately lists the path patterns that carry `immutable` cache headers.
- **General:** After edits, grep all four modified files for the literal strings `deliver-notifications` and `_lastLoadedBandId` to confirm no stale claim was missed in a section not explicitly listed above.

---

## 16. QA Regression Areas

Not applicable in the usual sense (no code path changed, nothing to manually regression-test in the running app). QA's role for this bug is to verify:
- Each of the four modified markdown files renders correctly (no broken tables/links introduced by the edit).
- No false claim (`deliver-notifications` as deployed/current, `_lastLoadedBandId` as open debt in gig/rehearsal controllers, cache headers as missing) remains anywhere in the four files.
- No unrelated content in these files was altered (diff should be limited to the sections named in Section 10/14).

---

## 17. Rollout / Migration Strategy
None required — documentation changes take effect immediately on merge, with no build, deploy, or migration step.

---

## 18. Out of Scope

- **`docs/reference/notifications/notifications.md`**: This file is more thoroughly stale than the two named in the bug report — it documents the entire `deliver-notifications`/pg_cron architecture as current, in detail (delivery lifecycle, troubleshooting, cost estimation, SQL debugging queries), with only a one-line banner at the top acknowledging some drift. It is **not** one of the three discrepancies named in this Feature Input's Summary, so it is not corrected in this pass. Recommend a follow-up `bug/` or `docs/` slug specifically to rewrite or retire this file, since fixing it properly is a larger edit than a few line corrections (the whole document's architecture section is wrong, not just a claim or two).
- **`acousticbrainz_bpm` local-folder-vs-deployed distinction**: Confirmed absent from the live deployed function list (corrected in this pass), but whether the local `supabase/functions/acousticbrainz_bpm/` folder should be deleted from the repo is a code-change decision, not a docs one — out of scope here.
- No app code, migration, or Edge Function changes of any kind (explicit Feature Input constraint).
- No other findings from `full-stack-performance-audit/ARCHITECT_PLAN.md` (DB-1 through DB-8, FE-1 through FE-5) are addressed here — each is explicitly scoped by that audit as its own future Architect plan.
