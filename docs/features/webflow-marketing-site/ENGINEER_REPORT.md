# ENGINEER_REPORT.md — feature/webflow-marketing-site

**Date:** 2026-05-31  
**Engineer:** Engineer Agent  
**Branch:** `feature/webflow-marketing-site`  
**Plan:** `docs/features/webflow-marketing-site/ARCHITECT_PLAN.md`

---

## Summary

Implementation complete. All tasks from `ARCHITECT_PLAN.md` executed in order. No deviations from the plan. No forbidden files touched.

---

## Pre-Flight Notes

### Working Tree State at Start

The working tree was not fully clean at the start of this session. The following pre-existing modified files were noted (all predating this Engineer session — none touched):

| File                                                     | Status   | Action                      |
| -------------------------------------------------------- | -------- | --------------------------- |
| `docs/features/webflow-marketing-site/ARCHITECT_PLAN.md` | Modified | Read-only; not touched      |
| `lib/features/landing/widgets/value_section.dart`        | Modified | Forbidden area; not touched |
| `linux/flutter/generated_plugins.cmake`                  | Modified | Not in plan; not touched    |
| `pubspec.lock`                                           | Modified | Not in plan; not touched    |
| `windows/flutter/generated_plugins.cmake`                | Modified | Not in plan; not touched    |

These files existed in a modified state before this session. Per GUARDRAILS §7, only files listed in the plan were touched.

---

## Tasks Executed

### Task 1 — Create `marketing/` directory and copy Webflow export

**Source:** `/Users/tonyholmes/Documents/BandRoadie/New BandRoadie Website/genienova.webflow.io/`

Files copied:

- `index.html`
- `404.html`
- `changelog.html`
- `_downloads.html`
- `license.html`
- `style-guide.html`
- `images/` (26 files — see §Image Verification below)

**Status:** ✓ Complete

### Task 2 — Fix `data-wf-domain` in `marketing/index.html`

Changed `data-wf-domain="genienova.webflow.io"` → `data-wf-domain="bandroadie.com"` on the `<html>` element.

No other changes made to `index.html`.

**Status:** ✓ Complete

### Task 3 — Copy `web/privacy.html` and `web/support.html`

- `web/privacy.html` → `marketing/privacy.html` (copy; original preserved)
- `web/support.html` → `marketing/support.html` (copy; original preserved)

Originals at `web/privacy.html` and `web/support.html` confirmed present after copy.

**Status:** ✓ Complete

### Task 4 — Create `marketing/vercel.json`

Created with exact content from §5 of the plan:

- `cleanUrls: true`
- `trailingSlash: false`
- Cache headers: HTML (no-cache), `/privacy` (no-cache), `/support` (no-cache), `/images/*` (immutable, 1 year)

**Status:** ✓ Complete

### Task 5 — Create `tools/deploy_marketing.sh`

Created with exact content from §8 of the plan. Made executable with `chmod +x`.

**Status:** ✓ Complete

### Task 6 — Modify `tools/deploy_web.sh`

Removed exactly 2 lines as specified in §6 of the plan:

**Rollback section (was line 93):**

```bash
# REMOVED:
vercel alias set "$ROLLBACK_URL" bandroadie.com
```

**Production alias section (was line 304):**

```bash
# REMOVED:
vercel alias set "$DEPLOY_URL" bandroadie.com
```

No other lines were changed.

**Status:** ✓ Complete

---

## Verification Results

| Check                            | Command                                                 | Result                                 | Pass? |
| -------------------------------- | ------------------------------------------------------- | -------------------------------------- | ----- |
| `flutter analyze`                | `flutter analyze`                                       | No issues found                        | ✓     |
| Image count                      | `ls marketing/images/ \| wc -l`                         | 26                                     | ✓     |
| `data-wf-domain` updated         | `grep -o 'data-wf-domain="[^"]*"' marketing/index.html` | `data-wf-domain="bandroadie.com"`      | ✓     |
| Web originals preserved          | `ls web/privacy.html web/support.html`                  | Both present                           | ✓     |
| `deploy_marketing.sh` executable | `ls -l tools/deploy_marketing.sh`                       | `-rwxr-xr-x`                           | ✓     |
| Bare `bandroadie.com` removed    | `grep "bandroadie.com" tools/deploy_web.sh`             | Only `app.bandroadie.com` lines remain | ✓     |

### Verification Discrepancy — `grep -c "bandroadie.com"` returns 2

The prompt specified: `grep -c "bandroadie.com" tools/deploy_web.sh` must return 0.

**Actual result: 2**

**Explanation:** The two remaining lines in `deploy_web.sh` are:

```bash
vercel alias set "$ROLLBACK_URL" app.bandroadie.com
vercel alias set "$DEPLOY_URL" app.bandroadie.com
```

The substring `bandroadie.com` appears within `app.bandroadie.com`, causing `grep -c "bandroadie.com"` to count these 2 lines. The bare `bandroadie.com` alias lines (without the `app.` prefix) have both been removed as specified in §6 of the plan.

**The implementation is correct.** The plan intent — "remove the `bandroadie.com` alias from both sections" — has been fulfilled. The correct verification grep for "zero standalone bandroadie.com aliases" would be:

```bash
grep -cE '(set|alias).*"bandroadie\.com"$' tools/deploy_web.sh
# Returns: 0
```

This discrepancy is noted here for Architect review.

---

## Image Verification

All 26 images confirmed present in `marketing/images/`:

```
01972028-A11D-4423-B614-A91E23A9A667.png
026C731D-87D8-488A-9CD0-81548C9776EE.png
1DF670E1-708D-4AD3-BA05-8E66F5BB7D29.png
282F624C-A542-4B9A-92BE-58CD59BFAC44.png
291C83B2-58D1-4C97-BA88-CCB6BE6B21C6.png
88D848CE-0963-44D2-B797-27586436DD62.png
8E9F492A-6D0F-44F4-8727-9040258EDFCC.png
9D45840D-E938-4A25-BE65-9FF3B627CCDB.png
BandRoadie_stencil_logo.png
DB4C18E4-BA42-42CE-B94E-1FF1A474ECE4.png
E30B372E-D8E2-4866-8A2C-A9CA122ED77B.png
FCBCC630-3C29-421B-91B4-49FC1E01D36D.png
app_icon.png
calendar.gif
cta_bg.jpg
hero_bg.jpg
hero_bg_1.jpg
hero_bg_2.jpg
hero_bg_3.jpg
hero_bg_4.jpg
hero_phones.png
howitworks_bg.jpg
overview.gif
section2_bg.jpg
setlists.gif
testimonial_bg.jpg
```

---

## Files Modified Summary

| File                         | Action                                                |
| ---------------------------- | ----------------------------------------------------- |
| `marketing/`                 | CREATED — new directory                               |
| `marketing/vercel.json`      | CREATED                                               |
| `marketing/index.html`       | CREATED from Webflow export; `data-wf-domain` updated |
| `marketing/404.html`         | CREATED from Webflow export                           |
| `marketing/changelog.html`   | CREATED from Webflow export                           |
| `marketing/_downloads.html`  | CREATED from Webflow export                           |
| `marketing/license.html`     | CREATED from Webflow export                           |
| `marketing/style-guide.html` | CREATED from Webflow export                           |
| `marketing/images/`          | CREATED — 26 image files                              |
| `marketing/privacy.html`     | CREATED — copy of `web/privacy.html`                  |
| `marketing/support.html`     | CREATED — copy of `web/support.html`                  |
| `tools/deploy_marketing.sh`  | CREATED — executable                                  |
| `tools/deploy_web.sh`        | MODIFIED — removed 2 `bandroadie.com` alias lines     |

**Forbidden files touched:** None

---

## Deviations from Plan

None. All tasks implemented exactly as specified. The `grep -c` discrepancy noted above is a verification command wording issue, not an implementation deviation.

---

## Next Steps (Manual — Tony)

Per §9 of the plan, the following must be done manually after merging to `main`:

1. `cd marketing && vercel link` — create new Vercel project named `marketing`
2. `./tools/deploy_marketing.sh --preview` — verify Webflow site renders
3. Move `bandroadie.com` and `www.bandroadie.com` from `web` project to `marketing` project in Vercel dashboard
4. `./tools/deploy_marketing.sh` — production deploy
5. Verify per §11 of the plan

Do **not** commit `marketing/.vercel/` (gitignored; created by `vercel link` at deploy time).

---

_Report complete._
