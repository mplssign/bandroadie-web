# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/getsongbpm-hosting-doc-audit`

**Note on process:** `docs/agents/ARCHITECT.md` Phase 4 is written around a notification-delivery worked example ("read `docs/reference/notifications/`"). That domain has no bearing here. Per the outer task instructions, Phase 4 is adapted to the actual domain: hosting/deployment reference docs. `docs/reference/deployment/deployment.md` was read in full (the only file in that directory) — see §4. `docs/reference/notifications/` was not read; this bug does not touch notifications. All other phases (0–13) were followed as written.

---

## 2. Problem Summary

`docs/agents/PROJECT_CONTEXT.md`'s "Hosting and Domain Architecture" section claims BandRoadie is "a single Vercel deployment serving both the marketing site and the web app from the same Flutter build," with `/privacy` served by the Flutter `PrivacyPolicyScreen`. This claim is **confirmed false** — verified against `vercel.json` files, `.vercel/project.json` linkage, the live Vercel API (actual domain-to-project assignments), and the deploy scripts. The doc also contains an internal contradiction (table says `/privacy` → `PrivacyPolicyScreen`; the "marketing only" file list separately names `web/privacy.html`) — resolved below: neither is what the public actually sees.

Separately, an uncommitted change already exists on this working tree (`lib/features/landing/widgets/footer_section.dart`, part of `feature/new-song-key-enrichment`, currently checked out) that adds a GetSongBPM attribution link to the Flutter landing page footer. Given the corrected hosting picture, that footer widget **cannot be reached by any real visitor to `bandroadie.com`** — it is diagnosed below, but is explicitly **not** fixed by this plan (§11, §18) since it is uncommitted work-in-progress belonging to a different feature branch's own Architect/Engineer/QA cycle, not this slug's scope.

Finally, a privacy-policy disclosure for the GetSongBPM third-party data flow (introduced by `feature/new-song-key-enrichment`) does not yet exist anywhere. This plan identifies the exact authoritative file(s) and insertion point(s) for it.

---

## 3. Root Cause — Confidence: HIGH (confirmed live via Vercel API + code, not speculation)

**This repo is NOT a single Vercel deployment.** It contains three independently deployed surfaces, each with its own `.vercel` project link, deployed by different scripts:

| Directory / build output | Deploy script | Linked Vercel project (verified via `list_projects`/`get_project`) | Live domain(s) on that project |
|---|---|---|---|
| `build/web` (this Flutter repo's web build) | `tools/deploy_web.sh` (`PROJECT_NAME="web"`, links inside `build/web`) | **`web`** — `prj_Aq7Q0pRo2oezPMOy01E0gMKO0Sk9` | `app.bandroadie.com` (+ preview `*.vercel.app` URLs only) |
| `marketing/` (static Webflow export — `index.html`, `privacy.html`, `style.css`, no Flutter/Dart) | `tools/deploy_marketing.sh` (`MARKETING_PROJECT="marketing"`, links inside `marketing/`) | **`marketing`** — `prj_6XAVv0lp4ySiYWAoBTPaWgT52DzW` | **`bandroadie.com`, `www.bandroadie.com`** (+ preview URLs) |
| repo root (`.vercel/project.json` at repo root, `vercelignore`s everything except `build/web`) | *(none — not referenced by any deploy script)* | `bandroadie-web` — `prj_EF0jMD0m2SEBdytZxCp7XnZVknzT` | **No production domain** — only preview `*.vercel.app` URLs. Orphaned/unused link, superseded by the `web` project that `deploy_web.sh` actually targets. |

**Consequence — `lib/features/landing/` (the Flutter `LandingPage`, `FooterSection`, and `_isMarketingHost()` routing in `lib/main.dart`) is dead code in production.** `bandroadie.com` and `www.bandroadie.com` are DNS-aliased directly to the separate `marketing` Vercel project (a static Webflow export, confirmed via `marketing/vercel.json`'s redirect/header rules and the Webflow CDN script tags in `marketing/index.html`). The Flutter app (the `web` project) only ever answers on `app.bandroadie.com`. There is no runtime path by which a real visitor to `bandroadie.com` ever executes `lib/main.dart`'s `_isMarketingHost()` check or renders `FooterSection` — that logic would only fire if someone hit the `web` project's own URLs with a spoofed `Host: bandroadie.com` header, which never happens in production.

**`/privacy` contradiction resolved — there are two real, separate, live `/privacy` pages, and both existing doc claims were wrong about which one is canonical:**

| URL | What actually serves it | Status |
|---|---|---|
| `bandroadie.com/privacy` / `www.bandroadie.com/privacy` | `marketing/privacy.html` — static HTML, `marketing` Vercel project. Confirmed canonical: its own `<link rel="canonical" href="https://www.bandroadie.com/privacy"/>` tag. This is the SEO-indexed, publicly linked policy. | **Live — public/canonical** |
| `app.bandroadie.com/privacy` | Flutter `PrivacyPolicyScreen` (`lib/features/legal/privacy_policy_screen.dart`), routed unconditionally on path match in `lib/main.dart` (not gated by `_isMarketingHost()`) | **Live — reachable inside the app SPA** |
| `web/privacy.html` (built into `build/web`, deployed to the `web` project) | **Nothing.** `web/vercel.json`'s catch-all rewrite (`"/((?!api/|.well-known/).*)" → "/index.html"`) intercepts any request for `/privacy.html` before it reaches the static file. Confirmed byte-identical body to `marketing/privacy.html` (only `<title>`/meta tags differ) — an orphaned duplicate, not a second live surface. | **Dead — unreachable** |

**A third stale document was found during Phase 4 (deployment reference read):** `docs/reference/deployment/deployment.md:18-20` states *"Vercel project: `web` (aliases: `bandroadie.com`, `app.bandroadie.com`). Both `bandroadie.com` and `app.bandroadie.com` are aliases for the same deployment."* This is the same false claim as `PROJECT_CONTEXT.md`, in a different file, and is corrected in this plan (§10).

**Escalation check:** Per the outer task instructions, a hard escalation is required only if this repo does **not** serve the live marketing site. That is not the case — `marketing/` (deployed by `tools/deploy_marketing.sh`, present and tracked in this same repo/remote, `git log -- marketing/` shows ongoing commits) **is** the live marketing site's source, just a separate static-site subtree with its own Vercel project rather than the Flutter build. This plan proceeds normally; no hard escalation to a different repo is warranted.

**Footer placement assessment (uncommitted `footer_section.dart` change):** Per its own `ENGINEER_REPORT.md` (`docs/features/new-song-key-enrichment/ENGINEER_REPORT.md`), this edit was a Tony-directed amendment to add a second, "crawlable" GetSongBPM backlink beyond the Settings-screen line in that feature's `ARCHITECT_PLAN.md` §6.6 — specifically because Settings sits behind auth and GetSongBPM requires a live, crawlable public backlink. The stated goal was correct; the target file was not. `lib/features/landing/widgets/footer_section.dart` is never served at `bandroadie.com` (see above), so this edit does not achieve a crawlable backlink at all — a crawler hitting `bandroadie.com` gets `marketing/index.html`'s Webflow-rendered footer (confirmed: no such attribution link exists there today), never this Flutter widget tree. **This is misplaced, not merely undesirable** — it is inert code with respect to its stated purpose.

---

## 4. Reference Docs Consulted

- `docs/reference/deployment/deployment.md` (only file in `docs/reference/deployment/`) — contains the same stale single-deployment/alias claim as `PROJECT_CONTEXT.md`; corrected in this plan (§10).
- `docs/agents/PROJECT_CONTEXT.md` — the primary doc under audit (§2, §10).
- `docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md` §6.6, §9–11 and `ENGINEER_REPORT.md` — establishes that the footer edit is a directed, documented amendment to a sibling feature, not stray/accidental work, and that Settings-screen attribution (§6.6 Task 11) is still outstanding there. Read for context only; not modified by this plan (§11).
- `docs/reference/general/AI_DECISIONS.md`, `docs/reference/general/RUNTIME_CONFIG.md` — checked for any prior logged decision about the marketing/app deployment split; none found. No new decision entry is required by this plan (it documents existing, already-live infrastructure — it does not change deployment architecture).

---

## 5. Existing System Analysis

Current (as of this session, verified against live Vercel API):

```
bandroadie.com, www.bandroadie.com
  └─ Vercel project "marketing" (prj_6XAVv0lp4ySiYWAoBTPaWgT52DzW)
       └─ marketing/  (static Webflow export — index.html, privacy.html, support.html, style.css)
       └─ deployed by tools/deploy_marketing.sh
       └─ /privacy → marketing/privacy.html (static, canonical, SEO-indexed)

app.bandroadie.com
  └─ Vercel project "web" (prj_Aq7Q0pRo2oezPMOy01E0gMKO0Sk9)
       └─ build/web  (flutter build web output, using web/vercel.json's rewrites/headers)
       └─ deployed by tools/deploy_web.sh
       └─ /privacy → Flutter PrivacyPolicyScreen (routed in lib/main.dart, path-based, host-independent)
       └─ lib/features/landing/ (LandingPage, FooterSection, _isMarketingHost()) → unreachable in production;
          _isMarketingHost() can never return true on this project's own domain

repo root .vercel link → project "bandroadie-web" (prj_EF0jMD0m2SEBdytZxCp7XnZVknzT)
  └─ no production domain attached; not referenced by any deploy script; orphaned
```

Documentation currently describes a single unified deployment with host-based routing deciding marketing vs. app vs. `/privacy` — this does not match the live infrastructure.

---

## 6. Proposed Solution

Three independent, minimal corrections — no architecture changes, no deployment changes, no code-behavior changes:

1. **Correct `docs/agents/PROJECT_CONTEXT.md`'s "Hosting and Domain Architecture" section** to state the verified three-project reality (§3 table), replace the `/privacy` row to reflect both live surfaces, and correct the "Files scoped to marketing only" list (remove `web/privacy.html`, which is not marketing-scoped and is not live; note `lib/features/landing/` is Flutter code that ships inside the `web` project's build but is unreachable at `bandroadie.com` in production). This is a targeted correction of the specific false claims, not a rewrite of the whole document.
2. **Correct `docs/reference/deployment/deployment.md:18-20`** — remove the "both are aliases for the same deployment" claim and the incorrect domain list; state the correct project/domain mapping for `web` vs. `marketing`.
3. **Add the GetSongBPM third-party-data disclosure** to both live, authoritative `/privacy` surfaces — `marketing/privacy.html` (public/canonical) and `lib/features/legal/privacy_policy_screen.dart` (in-app) — each already has an existing **"Data Sharing"** section (confirmed by direct read of both files), so the new content is inserted as a subsection there per the outer task's instruction, not as a new top-level section.

The uncommitted `footer_section.dart` change and the `web/privacy.html` dead duplicate are **diagnosed, not fixed** — see §11 and §18 for why, and what should happen to them instead.

---

## 7. Database Impact

Not applicable. No database, migration, RLS, or RPC changes.

---

## 8. Flutter Architecture Changes

One widget-tree content addition only: `PrivacyPolicyScreen._build...` calls in the existing `build()` method gain three new lines inside the existing `Data Sharing` section (a new `_buildSubheader` + two `_buildParagraph` calls, reusing existing private helper methods already defined in the same file — no new widgets, no new state, no new dependencies).

---

## 9. Files to Create

`none`

---

## 10. Files to Modify

| File | Change |
|---|---|
| `docs/agents/PROJECT_CONTEXT.md` | In the "Hosting and Domain Architecture" section (lines 32–61): replace the single-deployment claim and the surface/hostname table with the verified three-Vercel-project reality (§3 table — `web` project → `app.bandroadie.com`; `marketing` project → `bandroadie.com`/`www.bandroadie.com`; orphaned `bandroadie-web` root link with no production domain). Update the `/privacy` row to show both live surfaces (`marketing/privacy.html` public/canonical, and `PrivacyPolicyScreen` in-app). Remove `web/privacy.html` from "Files scoped to marketing only" (it is not marketing-scoped and is not reachable in production — note it as a dead/orphaned duplicate instead). Note that `lib/features/landing/` is Flutter code bundled into the `web` project's build but is unreachable at the live marketing domain. Do not otherwise rewrite the document. |
| `docs/reference/deployment/deployment.md` | Lines 18–20: replace "Vercel project: `web` (aliases: `bandroadie.com`, `app.bandroadie.com`). Both ... are aliases for the same deployment." with the correct mapping — `web` project serves only `app.bandroadie.com`; `bandroadie.com`/`www.bandroadie.com` are served by the separate `marketing` project deploying `marketing/` via `tools/deploy_marketing.sh`. |
| `marketing/privacy.html` | Inside the existing `<h2>Data Sharing</h2>` section, after the closing `</ul>` (line 158) and before the section's closing `<hr>` (line 160), insert:<br>`<h3>Third-Party Data Providers</h3>`<br>`<p>BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song.</p>`<br>`<p>Data from GetSongBPM: <a href="https://getsongbpm.com/">https://getsongbpm.com/</a>.</p>`<br>Matches the existing `<h3>` sub-heading pattern already used under "Information We Collect" (lines 123, 129). No other section touched. |
| `lib/features/legal/privacy_policy_screen.dart` | Inside the existing `Data Sharing` section's widget list, after the last `_buildBullet(context, 'Required by law or legal process')` call (line 99) and before `_buildDivider(context)` (line 100), insert:<br>`_buildSubheader(context, 'Third-Party Data Providers'),`<br>`_buildParagraph(context, "BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song."),`<br>`_buildParagraph(context, 'Data from GetSongBPM: https://getsongbpm.com/.'),`<br>Reuses existing `_buildSubheader`/`_buildParagraph` helpers already defined in this file (same pattern as the "Information You Provide" subheader at line 55). No new widgets, no other section touched. |

---

## 11. Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/landing/widgets/footer_section.dart` | **Currently uncommitted, dirty-tree work belonging to `feature/new-song-key-enrichment`**, per explicit Feature Input instruction: do not stash, discard, or commit it. It is diagnosed as misplaced in §3, but fixing it is out of scope for this slug — it is that feature's own Architect/Engineer/QA cycle's responsibility (its `ARCHITECT_PLAN.md` §6.6/§10 already specifies `settings_screen.dart`, not this file, as the attribution surface). Recommend to Manager/Tony: revert or relocate this edit under the `new-song-key-enrichment` pipeline — if a crawlable public backlink is still required, the correct live target is `marketing/index.html`'s footer markup (static Webflow export), not this Flutter widget. |
| `web/privacy.html` | Confirmed dead/unreachable in production (§3) — intercepted by `web/vercel.json`'s catch-all rewrite before ever being served. An orphaned, byte-identical duplicate of the pre-GetSongBPM-disclosure `marketing/privacy.html`. Editing it would create a second, silently-diverging copy of dead content. Left untouched; flagged in §18 for Tony to decide whether to delete it outright (separate, tiny cleanup task, not bundled here). |
| `docs/features/new-song-key-enrichment/*` | Sibling feature's own plan/report docs. Read for context (§4) only; not this slug's to modify. |
| Any `.vercel/project.json`, `vercel.json` (root, `web/`, `marketing/`) | No deployment/routing behavior is changing in this plan — these are documentation and content corrections only. Touching real deploy config is out of scope and would risk the live sites. |
| `lib/main.dart` | Routing/init order — unrelated to this bug; not touched. |
| Any privacy-policy content beyond the one new "Third-Party Data Providers" subsection in each of the two live `/privacy` surfaces | Explicit constraint from the outer task: do not touch any other privacy-policy content. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed
**New files:** none

---

## 12. System Impact Map

| System | Impact |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected — no route/host-detection logic changes, documentation-only correction of what's already true |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected (content only)** — `PrivacyPolicyScreen` renders identically on all platforms since it's a shared Flutter screen; the added subsection appears wherever the app is run. `marketing/privacy.html` affects Web (public site) only. |

---

## 13. Regression Risk

**Level: LOW**

- No code logic changes — one Flutter screen gains three additional static widget calls reusing existing helper methods; no new state, no new imports, no new dependencies.
- One static HTML file gains a heading + two paragraphs inside an existing section, matching existing markup patterns exactly.
- Two markdown reference docs get factual corrections with no behavioral consequence.
- No routing, auth, session, or init-order changes.
- No shared code path with any other feature's active work (the `feature/new-song-key-enrichment` dirty-tree changes are explicitly untouched, §11).

---

## 14. Engineer Task Breakdown

1. In `docs/agents/PROJECT_CONTEXT.md`, replace the "Hosting and Domain Architecture" section's deployment claim and table per §10 — three verified Vercel projects, corrected `/privacy` row, corrected marketing-scoped file list.
2. In `docs/reference/deployment/deployment.md`, replace lines 18–20 per §10 with the corrected project/domain mapping.
3. In `marketing/privacy.html`, insert the "Third-Party Data Providers" subsection inside the existing `Data Sharing` section per the exact markup in §10.
4. In `lib/features/legal/privacy_policy_screen.dart`, insert the "Third-Party Data Providers" subsection inside the existing `Data Sharing` section per the exact widget calls in §10.
5. Do not touch `web/privacy.html`, `lib/features/landing/widgets/footer_section.dart`, or anything under `docs/features/new-song-key-enrichment/`.
6. Run `flutter analyze lib/features/legal/privacy_policy_screen.dart` — 0 errors expected (content-only change, no new imports/types).

---

## 15. Verification Plan

### Tier 1 — Pre-deployment
No database or backend objects are touched by this plan — Tier 1/Tier 2 SQL test tiering from `docs/agents/ARCHITECT.md` §15 does not apply. Pre-deployment checks are:
- **PRE-DEPLOY CHECK 1:** `git diff docs/agents/PROJECT_CONTEXT.md` — confirm only the Hosting and Domain Architecture section changed, nothing else in the file.
- **PRE-DEPLOY CHECK 2:** `git diff docs/reference/deployment/deployment.md` — confirm only lines 18–20 changed.
- **PRE-DEPLOY CHECK 3:** `git diff marketing/privacy.html` — confirm the diff is exactly one `<h3>` + two `<p>` lines inside the `Data Sharing` section, nothing else in the file reflowed or altered.
- **PRE-DEPLOY CHECK 4:** `git diff lib/features/legal/privacy_policy_screen.dart` — confirm the diff is exactly one `_buildSubheader` + two `_buildParagraph` calls inside the `Data Sharing` section, nothing else changed.
- **PRE-DEPLOY CHECK 5:** `flutter analyze lib/features/legal/privacy_policy_screen.dart` — 0 errors.

### Tier 2 — Post-deployment
This content ships with the normal `tools/deploy_web.sh` (Flutter/app privacy screen) and `tools/deploy_marketing.sh` (static marketing privacy page) cycles — not a special/isolated deploy. Post-deploy checks, once each script is next run in the ordinary course of business:
- **POST-DEPLOY CHECK 1:** Load `https://www.bandroadie.com/privacy` — confirm the "Data Sharing" section shows the new "Third-Party Data Providers" subsection with a working link to `https://getsongbpm.com/`.
- **POST-DEPLOY CHECK 2:** Load `https://app.bandroadie.com/privacy` (or the in-app Settings → Privacy Policy link) — confirm the same subsection appears identically inside the app's `PrivacyPolicyScreen`.

---

## 16. QA Regression Areas

1. **`PrivacyPolicyScreen` renders correctly end-to-end** (not just the new subsection) — confirm no divider/spacing regression above or below the insertion point, on at least one native platform and Web.
2. **`marketing/privacy.html` renders correctly** at both mobile and desktop widths — confirm the new `<h3>`/`<p>` inherits the page's existing `style.css` typography with no visual break.
3. **Confirm `web/privacy.html` was not touched** (`git diff web/privacy.html` should be empty) — it must remain byte-for-byte the same dead duplicate, not silently diverge further.
4. **Confirm `lib/features/landing/widgets/footer_section.dart` and `docs/features/new-song-key-enrichment/` are untouched by this branch's diff** — these belong to the sibling feature and must not be swept up here.
5. **Confirm `docs/agents/PROJECT_CONTEXT.md` and `docs/reference/deployment/deployment.md` diffs are scoped exactly as described in §10** — no incidental rewriting of unrelated sections.

---

## 17. Rollout / Migration Strategy

No special rollout. Documentation corrections take effect immediately on merge (no deploy needed). The two privacy-policy content additions ship on the next ordinary run of `tools/deploy_marketing.sh` (marketing site) and `tools/deploy_web.sh` (app) respectively — no need to force an out-of-band deploy for this change alone; it can ride along with the next regular deploy of each. **Rollback:** plain `git revert` — no data, schema, or Edge Function involved.

---

## 18. Out of Scope

1. **Fixing/reverting the uncommitted `lib/features/landing/widgets/footer_section.dart` edit.** Diagnosed in §3 as misplaced (unreachable at `bandroadie.com` in production), but it is `feature/new-song-key-enrichment`'s own uncommitted work — recommend Manager/Tony route the fix (likely: revert this edit, and if a crawlable public backlink is still required for GetSongBPM API compliance, add it to `marketing/index.html`'s static footer instead) back through that feature's own pipeline, not this one.
2. **Deleting `web/privacy.html`.** Confirmed dead/unreachable (§3). A one-line-diff cleanup, but it's a separate, distinct decision (deleting a file vs. correcting docs/content) that the outer task did not ask for and that risks looking like opportunistic cleanup bundled into an unrelated PR. Flagged for a future, separate bug/chore ticket.
3. **Cleaning up the orphaned root `.vercel`/`vercel.json` link (`bandroadie-web` project, no production domain, unused by any deploy script).** Purely cosmetic/hygiene; not touched — deleting or relinking Vercel project config is a deploy-infrastructure change outside a docs/content-audit bug's blast radius.
4. **Any rewrite of `PROJECT_CONTEXT.md` or `deployment.md` beyond the specific false claims identified in §3.** Per the outer task's explicit instruction.
5. **The Settings-screen GetSongBPM attribution line** (`feature/new-song-key-enrichment` ARCHITECT_PLAN.md §6.6 Task 11) — that feature's own outstanding task, unrelated to this plan.
6. **Adding a GetSongBPM disclosure to `web/privacy.html`** — it's dead code (§3); keeping it in sync would only entrench a duplicate that should eventually be deleted (§18.2), not maintained.

---

## 19. Branch Handling (per outer task instruction)

**Current state at Architect session start:** `feature/new-song-key-enrichment` checked out, `git rev-parse main` and `git rev-parse HEAD` are **identical** (`ba907ab...`) — i.e., this branch has **zero committed divergence** from `main`; the only differences are the uncommitted working-tree changes (`lib/features/landing/widgets/footer_section.dart` modified, `docs/features/new-song-key-enrichment/` untracked).

**Decision: create the new branch `bug/getsongbpm-hosting-doc-audit` from the current position (`git checkout -b`), not by first switching to `main`.**

**Why this is safe and equivalent to branching from `main`:** since `HEAD == main` exactly (no commits ahead), `git checkout -b bug/getsongbpm-hosting-doc-audit` from here produces a branch pointing at the identical commit `main` does — there is no risk of carrying any of `feature/new-song-key-enrichment`'s (nonexistent) committed work onto this branch. `git checkout -b` does not touch the working tree's uncommitted contents at all, so the existing dirty files remain exactly as they are, un-stashed, un-discarded, un-committed, per the outer task's explicit instruction — they will simply also show as pending changes under the new branch name until whoever owns `feature/new-song-key-enrichment` returns to it. This plan's own Engineer work (§14) touches none of those dirty files, so there is no merge/conflict risk between the two efforts.
