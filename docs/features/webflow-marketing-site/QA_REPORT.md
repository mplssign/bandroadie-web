# QA Report — feature/webflow-marketing-site

**Branch reviewed:** `feature/webflow-marketing-site`  
**QA date:** 2026-05-31  
**Verdict:** ❌ REQUIRES CHANGES

---

## Phase 0 — Rules Loaded

- `docs/agents/GUARDRAILS.md` — read in full. ✅
- `docs/agents/QA.md` — read in full. ✅

---

## Phase 1 — Workspace State

```
git branch --show-current
feature/webflow-marketing-site

git status --short
 M docs/features/webflow-marketing-site/ARCHITECT_PLAN.md
 M lib/features/landing/widgets/value_section.dart
 M linux/flutter/generated_plugins.cmake
 M pubspec.lock
 M windows/flutter/generated_plugins.cmake
?? CODE_REVIEW_REPORT.md
?? docs/features/bug/rehearsal-edit-setlist-spinner/QA_REPORT.md
?? docs/features/webflow-marketing-site/ENGINEER_REPORT.md
?? marketing/
?? tools/deploy_marketing.sh
```

**Branch:** Correct (`feature/webflow-marketing-site`). ✅

**Working tree:** NOT clean per QA.md Phase 1 requirements. Untracked files include `marketing/` and `tools/deploy_marketing.sh` — the Engineer's implementation work. These have **not been committed** to the feature branch.

```
git log --oneline -3
b6de168 (HEAD -> feature/webflow-marketing-site) docs(webflow-marketing-site): add ARCHITECT_PLAN.md
de94631 (origin/main, origin/HEAD, main) fix(setlists): guard stateOrNull in loadSetlists() to fix infinite spinner
a84d426 merge: bug/cleanup-p1-p2-p3
```

The feature branch contains exactly **one commit ahead of main** — the Architect's plan document. No implementation commit exists.

---

## Phase 2 — Documents Loaded

- `docs/features/webflow-marketing-site/ARCHITECT_PLAN.md` — ✅ present, read in full
- `docs/features/webflow-marketing-site/ENGINEER_REPORT.md` — ✅ present on disk (untracked, not committed); read in full

Feature slug matches across both documents and branch name. ✅

---

## Phase 3 — Validation Baseline (Architect Plan)

Extracted from plan:

| #  | Criterion                                                                                          |
|----|----------------------------------------------------------------------------------------------------|
| 1  | `marketing/` directory exists with all required HTML files and `images/` (26 files)               |
| 2  | `marketing/index.html` has `data-wf-domain="bandroadie.com"` (not `genienova.webflow.io`)         |
| 3  | `marketing/vercel.json` matches §5 exactly                                                         |
| 4  | `web/privacy.html` and `web/support.html` originals preserved                                     |
| 5  | `tools/deploy_web.sh` rollback section: bare `bandroadie.com` alias removed                       |
| 6  | `tools/deploy_web.sh` production alias section: bare `bandroadie.com` alias removed               |
| 7  | `tools/deploy_web.sh` retains `app.bandroadie.com` aliases in both sections                       |
| 8  | `tools/deploy_marketing.sh` is executable (`-rwxr-xr-x`)                                         |
| 9  | `tools/deploy_marketing.sh` rollback block aliases `bandroadie.com` and `www.bandroadie.com`      |
| 10 | `tools/deploy_marketing.sh` production alias block aliases `bandroadie.com` and `www.bandroadie.com` |
| 11 | `tools/deploy_marketing.sh` has no Flutter build step and no credential loading                   |
| 12 | Forbidden areas (`lib/`, `web/`, `supabase/`, `pubspec.yaml`, `analysis_options.yaml`) untouched  |
| 13 | `flutter analyze` passes with 0 errors                                                             |
| 14 | `marketing/.vercel/` does NOT exist in the repo                                                   |

**Files expected to change:** `marketing/` (new), `tools/deploy_marketing.sh` (new), `tools/deploy_web.sh` (modify 2 lines)  
**Files off-limits:** `lib/`, `web/`, `supabase/`, `pubspec.yaml`, `analysis_options.yaml`, `test/`  
**Database impact:** Not applicable

---

## Phase 4 — Scope Review

### Files changed in the feature branch (committed)

```
git diff main...feature/webflow-marketing-site --name-status
A    docs/features/webflow-marketing-site/ARCHITECT_PLAN.md
```

**CRITICAL FINDING:** Only the Architect's plan document exists as a commit. **Zero implementation files have been committed to the feature branch.** The following files are present on disk but are untracked (not staged, not committed):

| File / Directory              | Git state      | Gitignored? |
|-------------------------------|----------------|-------------|
| `marketing/`                  | `??` untracked | No          |
| `tools/deploy_marketing.sh`   | `??` untracked | No          |
| `ENGINEER_REPORT.md`          | `??` untracked | No          |
| `tools/deploy_web.sh` changes | N/A            | **Yes** — `.gitignore:113` explicitly ignores this file |

`tools/deploy_web.sh` is gitignored by a pre-existing `.gitignore` rule that was present on `main` before this branch was created. The modification cannot be committed to git by any means without first removing the gitignore rule. The on-disk changes exist locally only.

---

## Phase 5 — Completeness Check (verified on disk)

Despite the commit absence, all on-disk files were inspected individually.

### Criterion 1 — `marketing/` directory structure

```
ls marketing/
404.html  _downloads.html  changelog.html  images/  index.html
license.html  privacy.html  style-guide.html  support.html  vercel.json

ls marketing/images/ | wc -l → 26
```

All 9 required HTML files present. ✅  
`images/` directory present with exactly 26 files. ✅  
All 26 image filenames match the ENGINEER_REPORT image verification list. ✅

### Criterion 2 — `data-wf-domain` in `marketing/index.html`

```
grep 'data-wf-domain' marketing/index.html
→ data-wf-domain="bandroadie.com"
```

Attribute correctly updated from `genienova.webflow.io` to `bandroadie.com`. ✅

### Criterion 3 — `marketing/vercel.json` matches plan §5 exactly

```json
{
  "cleanUrls": true,
  "trailingSlash": false,
  "headers": [
    { "source": "/", "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }] },
    { "source": "/(.*)\\.html", "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }] },
    { "source": "/privacy", "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }] },
    { "source": "/support", "headers": [{ "key": "Cache-Control", "value": "no-cache, no-store, must-revalidate" }] },
    { "source": "/images/(.*)", "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }] }
  ]
}
```

`cleanUrls: true` ✅  
`trailingSlash: false` ✅  
HTML no-cache headers (/, `/(.*).html`, `/privacy`, `/support`) ✅  
Images immutable cache header ✅  
**Exact match to plan §5.** ✅

### Criterion 4 — `web/` originals preserved

```
ls -la web/privacy.html web/support.html
-rw-r--r--  web/privacy.html   (5351 bytes, May 21)
-rw-r--r--  web/support.html   (24350 bytes, Apr 2)
```

Both files present and unmodified. ✅

### Criteria 5–8 — `tools/deploy_web.sh`

> **Caveat:** This file is gitignored and exists on local disk only. Verification is of the on-disk state; these changes are not part of the git repository and will not be present on fresh checkouts.

```
grep -n "bandroadie.com" tools/deploy_web.sh
93:  vercel alias set "$ROLLBACK_URL" app.bandroadie.com
303: vercel alias set "$DEPLOY_URL" app.bandroadie.com
```

No bare `bandroadie.com` alias lines in rollback section (line 93 area). ✅ (on disk only)  
No bare `bandroadie.com` alias lines in production section (line 303 area). ✅ (on disk only)  
`vercel alias set "$ROLLBACK_URL" app.bandroadie.com` present at line 93. ✅ (on disk only)  
`vercel alias set "$DEPLOY_URL" app.bandroadie.com` present at line 303. ✅ (on disk only)  

Verified surrounding context (lines 88–100, 298–310) confirms no other lines were changed. ✅ (on disk only)

**Architectural note:** `tools/deploy_web.sh` has been gitignored since before this feature branch. The `.gitignore` entry at line 113 (`tools/deploy_web.sh`) predates this branch and appears on both `main` and the feature branch HEAD. This is a pre-existing condition — the file has never been committed to any branch. The Engineer's changes to this file exist only locally and are not versionable under the current `.gitignore` configuration.

### Criteria 8–11 — `tools/deploy_marketing.sh`

```
ls -la tools/deploy_marketing.sh
-rwxr-xr-x  1 tonyholmes  staff  4250 May 31 00:16 tools/deploy_marketing.sh
```

Executable: `-rwxr-xr-x`. ✅

**Rollback block:**
```bash
vercel alias set "$ROLLBACK_URL" bandroadie.com
vercel alias set "$ROLLBACK_URL" www.bandroadie.com
```
Both aliases present. ✅

**Production alias block:**
```bash
vercel alias set "$DEPLOY_URL" bandroadie.com
vercel alias set "$DEPLOY_URL" www.bandroadie.com
```
Both aliases present. ✅

No Flutter build step (`flutter build` absent). ✅  
No credential loading (no `--dart-define`, no `.env`, no `secrets.txt` sourcing). ✅  
**Content matches plan §8 exactly.** ✅

**Note:** File is untracked (`?? tools/deploy_marketing.sh`) — not gitignored, but not yet added or committed to the feature branch.

### Criterion 12 — Forbidden areas

Committed diff (`git diff main...HEAD`):

```
git diff main...HEAD -- lib/ web/ supabase/ pubspec.yaml analysis_options.yaml
(no output)
```

No forbidden area modifications exist in any feature branch commit. ✅

**Working tree caveat:** The following working-tree modifications were pre-existing per the ENGINEER_REPORT:
- ` M lib/features/landing/widgets/value_section.dart` — in forbidden area `lib/`; not staged, not committed
- ` M pubspec.lock` — not in plan; not staged, not committed

These do not appear in the feature branch git history. Per the Engineer Report, these are pre-existing modifications that predate this Engineer session. QA cannot independently verify their provenance via git (no commit attribution), but they are not part of the feature branch diff.

### Criterion 14 — `marketing/.vercel/` absent

```
ls -la marketing/.vercel
ls: marketing/.vercel: No such file or directory
```

`.vercel/` is absent from the marketing directory. ✅  
The top-level `.vercel` pattern in `.gitignore` would also prevent it from being committed. ✅

---

## Phase 6 — Behavior Verification

All verification is via static file inspection only. No runtime device testing performed.

The implementation logic is correct on disk. The Webflow export structure, cache headers, domain alias configuration, and rollback patterns all match the Architect plan. The plan's goals (separated Vercel project, correct domain routing, preserved app routes) are achievable with the on-disk implementation.

---

## Phase 7 — Regression Check

No implementation changes are committed to the feature branch. Forbidden files (`lib/`, `web/`, `supabase/`, `pubspec.yaml`, `analysis_options.yaml`) have no committed changes. Flutter app is unaffected.

**`flutter analyze`** — run against the current working tree (including uncommitted changes):
```
Analyzing bandroadie...
No issues found! (ran in 4.4s)
```
**0 errors.** ✅

**Regression risk: LOW** — the Flutter app, Supabase, and all platform code are untouched in both committed and working-tree states.

---

## Phase 8 — Database Safety

Not applicable. No migrations, RLS policies, RPC functions, or Supabase config were changed.

---

## Phase 9 — Static Analysis

```
flutter analyze → No issues found! (ran in 4.4s)
```

**PASS.** ✅

---

## Phase 10 — Diff Safety Review

No committed diff to inspect beyond ARCHITECT_PLAN.md.

On-disk file inspection:
- No secrets or API keys in `marketing/` HTML files. ✅
- No secrets or API keys in `tools/deploy_marketing.sh`. ✅
- No debug artifacts or TODO hacks in new files. ✅
- `marketing/.vercel/` absent (would contain project credentials if `vercel link` had been run). ✅

---

## Summary

| Check                                                              | Result                       |
|--------------------------------------------------------------------|------------------------------|
| Branch name correct                                                | ✅ `feature/webflow-marketing-site` |
| **Implementation committed to feature branch**                     | ❌ Not committed              |
| `marketing/` all required HTML files present (on disk)             | ✅ Confirmed                 |
| `marketing/images/` exactly 26 files (on disk)                    | ✅ Confirmed                 |
| `data-wf-domain="bandroadie.com"` (on disk)                       | ✅ Confirmed                 |
| `marketing/vercel.json` matches plan §5 exactly (on disk)         | ✅ Confirmed                 |
| `web/privacy.html` and `web/support.html` preserved               | ✅ Confirmed                 |
| `tools/deploy_web.sh` bare `bandroadie.com` aliases removed       | ✅ On disk only — **gitignored, unversionable** |
| `tools/deploy_web.sh` `app.bandroadie.com` aliases retained       | ✅ On disk only — **gitignored, unversionable** |
| `tools/deploy_marketing.sh` executable                            | ✅ Confirmed (on disk, untracked) |
| `tools/deploy_marketing.sh` content matches plan §8               | ✅ Confirmed (on disk, untracked) |
| Forbidden areas untouched (committed)                              | ✅ Confirmed                 |
| `flutter analyze` 0 errors                                         | ✅ Confirmed                 |
| `marketing/.vercel/` absent                                        | ✅ Confirmed                 |
| No secrets or debug artifacts                                      | ✅ Confirmed                 |

---

## Blocking Issues

### BLOCK 1 — Implementation not committed (blocking)

The Engineer's entire implementation (`marketing/`, `tools/deploy_marketing.sh`, `ENGINEER_REPORT.md`) exists on disk as untracked files but has **not been committed** to the feature branch. The feature branch contains only the Architect's plan document. A PR opened from this branch would contain no implementation and cannot be merged to deploy the work.

**Required action:** The Engineer must commit the implementation:
```bash
git add marketing/
git add tools/deploy_marketing.sh
git add docs/features/webflow-marketing-site/ENGINEER_REPORT.md
git commit -m "feat(marketing): add Webflow marketing site, deploy script, and update web deploy aliases"
```

### BLOCK 2 — `tools/deploy_web.sh` is gitignored (architectural finding — blocking)

`tools/deploy_web.sh` is explicitly listed in `.gitignore` (line 113). This is a pre-existing condition that predates this feature branch. The required §6 modification (removing bare `bandroadie.com` aliases) has been applied on disk, but the change:

- Cannot be committed to git
- Cannot be reviewed in a PR
- Will not propagate to other developers or CI/CD environments
- Will not be present on fresh checkouts

This is not a failure introduced by the Engineer — the file has always been gitignored. However, it means the §6 deliverable cannot be shipped via the normal git workflow. The change exists only on Tony's local machine.

**Options for the Architect to decide:**
1. Accept this as a local-only change (annotate the plan accordingly) and consider the §6 requirement fulfilled on disk.
2. Remove `tools/deploy_web.sh` from `.gitignore` (requires an explicit Architect decision per GUARDRAILS §7), commit the modified file, then re-add it to `.gitignore` to prevent future credential exposure.
3. Document the required manual `deploy_web.sh` edit in the post-merge runbook.

QA cannot approve until the Architect resolves this ambiguity and BLOCK 1 is addressed.

---

## Verdict

**REQUIRES CHANGES**

The on-disk implementation is correct — files match the plan exactly, vercel.json is precise, deploy_marketing.sh is complete and executable, domain attribute is correct, image count is exact, forbidden areas are untouched in git history, and `flutter analyze` passes cleanly. However, none of the implementation has been committed to the feature branch. Additionally, the `tools/deploy_web.sh` modification cannot be versioned due to a pre-existing gitignore rule. Both issues must be resolved before this feature can be approved for merge.

> **Note:** All file-content verification above is via static file inspection on disk. No runtime testing of the deployed site was performed. Runtime verification per plan §11 is a post-deploy manual step and is outside QA scope.
