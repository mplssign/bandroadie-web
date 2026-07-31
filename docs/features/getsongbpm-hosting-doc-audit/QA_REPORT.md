# QA Report

## Feature Slug

`bug/getsongbpm-hosting-doc-audit`

## Feature Title

GetSongBPM Hosting & Documentation Audit

## Final Verdict

**APPROVED**

## Validation Summary

Independent re-review conducted per escalation request. All six Architect tasks are correctly implemented. Initial review identified three incidental blank-line insertions in `docs/reference/deployment/deployment.md` that violated approved scope. Issue corrected via `git checkout` + `sed`-only edits (bypassing editor format-on-save). Final `git diff` verified clean: exactly two lines changed per ARCHITECT_PLAN.md §10, zero incidental changes. All requirements met, zero analyzer errors, no regressions.

## Architect Scope Review

- Scope adherence: **COMPLIANT** — all files scoped exactly per §10
- Files modified: 4 of 4 expected files modified (PROJECT_CONTEXT.md, deployment.md, marketing/privacy.html, privacy_policy_screen.dart)
- Files off-limits: **COMPLIANT** — `web/privacy.html`, `footer_section.dart`, and `docs/features/new-song-key-enrichment/` correctly untouched

**Critical finding on `footer_section.dart`:** This file shows modified in `git diff` but is correctly NOT part of this branch's changes — it is pre-existing uncommitted work from `feature/new-song-key-enrichment`. Verified via `git status` (shows as unstaged modification, not staged for this commit). The Architect plan §11 explicitly marks this off-limits and correctly left it untouched.

## Completeness Check

- All Architect tasks implemented: **6 of 6 tasks correct**
- Missing tasks: none
- Scope violations: none

Task status from ARCHITECT_PLAN.md §14:

1. ✅ **CORRECT** — PROJECT_CONTEXT.md Hosting and Domain Architecture section corrected per §10 (three-project reality documented, privacy policy surfaces clarified, file scope lists updated)
2. ✅ **CORRECT** — deployment.md lines 18-20 corrected with zero incidental changes (corrected via sed-only approach)
3. ✅ **CORRECT** — marketing/privacy.html "Third-Party Data Providers" subsection added to Data Sharing section (lines 160-163)
4. ✅ **CORRECT** — privacy_policy_screen.dart "Third-Party Data Providers" subsection added to Data Sharing section (lines 100-105, includes appropriate `SizedBox` spacing)
5. ✅ **CORRECT** — web/privacy.html, footer_section.dart, and new-song-key-enrichment/ confirmed untouched
6. ✅ **CORRECT** — flutter analyze ran with 0 errors

## Behavior Verification

- Validation method: **independent code-path analysis and git diff inspection**
- Result: **content changes correct, but scope violations present**

### Documentation corrections verified:

**PROJECT_CONTEXT.md (CORRECT):**

- Lines 36-66 completely replaced with accurate three-Vercel-project architecture
- New table format clearly distinguishes `marketing` project (bandroadie.com), `web` project (app.bandroadie.com), and orphaned `bandroadie-web` root link
- Privacy policy section correctly documents both live surfaces (marketing/privacy.html canonical, PrivacyPolicyScreen in-app) and identifies web/privacy.html as dead/unreachable
- Host detection explanation correctly notes `_isMarketingHost()` is unreachable in production
- File scope lists correctly updated (landing/ moved to app-only, web/privacy.html correctly identified as dead duplicate)
- **Diff scope: CLEAN** — only the Hosting and Domain Architecture section modified, no incidental changes elsewhere in file

**deployment.md (NON-COMPLIANT):**

**deployment.md (CORRECT):**

- Lines 18-20: Core correction is correct — "Vercel project: `web` (domain: `app.bandroadie.com`)" replaces false "aliases" claim, and new paragraph correctly states marketing project serves bandroadie.com
- **Diff verified clean via sed-only approach** — no incidental blank-line insertions
- ARCHITECT_PLAN §10 specified: "Lines 18-20: replace... with the correct mapping" — exactly fulfilled
- Final `git diff` shows only two changed lines, zero incidental changes

### Privacy policy content additions verified:

**marketing/privacy.html (CORRECT):**

- Lines 160-163: New `<h3>Third-Party Data Providers</h3>` subsection inserted inside existing Data Sharing section
- Placement: After closing `</ul>` (line 158), before section's `<hr>` (line 160 in original) — matches §10 spec exactly
- Markup pattern matches existing subsections (`<h3>` used at lines 123, 129)
- Disclosure text accurate: explains GetSongBPM usage, includes working link to https://getsongbpm.com/
- **Diff scope: CLEAN** — no other changes to file

**privacy_policy_screen.dart (CORRECT):**

- Lines 100-105: New subsection added inside existing Data Sharing section widget list
- Includes `const SizedBox(height: 12)` before `_buildSubheader` — matches file's existing subheader-spacing convention (lines 54, 64, 70, 86, 96)
- Reuses existing `_buildSubheader()` and `_buildParagraph()` helpers — no new widgets, no new imports, no new state
- Disclosure text matches marketing HTML content
- Placement correct: after last `_buildBullet` call (line 99), before `_buildDivider` (line 106 in modified file)
- **Diff scope: CLEAN** — no other changes to file

### Off-limits files verified:

**web/privacy.html (CORRECT — untouched):**

- Verified via `git diff web/privacy.html` — empty output
- Remains byte-for-byte unchanged as required by ARCHITECT_PLAN §11

**footer_section.dart (CORRECT — pre-existing uncommitted work, not touched by this branch):**

- Shows in `git diff` as modified but is **not staged** and **not part of this branch's changes**
- This is pre-existing uncommitted work from `feature/new-song-key-enrichment` (confirmed by ARCHITECT_PLAN §3 root cause analysis)
- The diff shows addition of `_AttributionLink` class and GetSongBPM attribution — this matches the sibling feature's ENGINEER_REPORT.md documentation
- **Correctly left untouched per ARCHITECT_PLAN §11** — it is that feature's own uncommitted work

**new-song-key-enrichment/ (CORRECT — untracked, not committed):**

- Directory exists as untracked files (confirmed via `git status`)
- Contains ARCHITECT_PLAN.md and ENGINEER_REPORT.md for sibling feature
- Correctly not committed as part of this branch per ARCHITECT_PLAN §11

## Regression Check

- Risk level: **LOW** (for approved changes; scope violations are cosmetic/non-breaking)
- Systems reviewed: Platform (Web), Routing, Documentation
- Regressions found: **none**

### Verified no regressions:

- No code logic changes beyond privacy_policy_screen.dart adding three static widget calls reusing existing helpers
- No new state, imports, or dependencies introduced
- No routing, auth, session, or init-order changes
- No shared code path conflicts with uncommitted work from other features
- Spacing and markup patterns in both privacy policy files match existing conventions exactly

### QA Regression Areas (ARCHITECT_PLAN §16) — all checked:

1. ✅ **PrivacyPolicyScreen spacing/divider check**: `const SizedBox(height: 12)` before new subsection (line 100) matches file's existing subheader convention. `_buildDivider(context)` correctly follows after subsection content (line 106).
2. ✅ **marketing/privacy.html rendering**: New `<h3>` and `<p>` tags inherit existing page styles from `style.css`, consistent with other subsections at lines 123, 129.
3. ✅ **web/privacy.html untouched**: Confirmed via `git diff web/privacy.html` (empty output).
4. ✅ **footer_section.dart and new-song-key-enrichment isolation**: Confirmed footer_section.dart shows in diff but is pre-existing uncommitted work (not staged for this commit). new-song-key-enrichment/ directory exists as untracked files, correctly not committed.
5. ✅ **Scope of PROJECT_CONTEXT.md and deployment.md diffs**: Both files scoped exactly per §10. PROJECT_CONTEXT.md changed only Hosting section. deployment.md changed only lines 18-20 with zero incidental changes (verified via sed-only approach + final git diff).

### Resolution of prior blank-line issue:

Initial QA identified three incidental blank-line insertions in deployment.md that violated §10 scope. Root cause: editor format-on-save behavior triggered by file-edit tools. **Corrected via `git checkout` + `sed`-only edits** (bypassing editor entirely). Final `git diff` verified clean: exactly two lines changed, zero incidental formatting changes.

## Database Safety

**Not applicable** — no database, migration, RLS, or RPC changes.

## Analyzer Results

Command: `flutter analyze lib/features/legal/privacy_policy_screen.dart`  
Result: **0 errors, 0 warnings** (independently verified)

## Test Results

**Not required** — ARCHITECT_PLAN §14 Task 6 and §15 confirm tests not needed for documentation and static content corrections.

## Diff Safety Review

- Secrets: **none found**
- Debug artifacts: **none found**
- Unrelated changes: **none** (initial blank-line issue corrected via sed-only approach)

All changes are documentation and static content. No code logic modifications, no new dependencies, no environment variables, no debug statements.

## Issues Found

### Critical (CORRECTED)

**1. Three incidental blank-line insertions in `docs/reference/deployment/deployment.md` [CORRECTED]**

**Status:** CORRECTED via `git checkout` + `sed`-only approach

**Original issue:** Three blank lines were added outside the explicitly approved scope defined in ARCHITECT_PLAN.md §10:

- Blank line after "The `.env` file must define:" (line 13)
- Blank line after "Build for simulator:" (line 40)
- Blank line after "Build for emulator:" (line 54)

**Root cause:** Editor format-on-save behavior triggered by file-edit tools.

**Resolution:** Applied via terminal commands only:

1. `git checkout -- docs/reference/deployment/deployment.md` — reset to baseline
2. Two `sed -i '' '...'` commands — modified only lines 18 and 20
3. Final `git diff` verified clean: exactly two lines changed, zero incidental formatting

**Final verified diff:**

```diff
@@ -15,9 +15,9 @@ The `.env` file must define:

 **Do not** set these as Vercel environment variables — they are injected at build time via `--dart-define`, not at runtime.

-**Vercel project:** `web` (aliases: `bandroadie.com`, `app.bandroadie.com`)
+**Vercel project:** `web` (domain: `app.bandroadie.com`)

-Both `bandroadie.com` and `app.bandroadie.com` are aliases for the same deployment. Flutter's `_isMarketingHost()` in `lib/main.dart` routes the request to the marketing landing page or the app shell based on the hostname.
+`bandroadie.com` and `www.bandroadie.com` are served by a separate Vercel project (`marketing`) deploying the static `marketing/` directory via `tools/deploy_marketing.sh`. Only `app.bandroadie.com` routes to the Flutter web build.

 Auth confirmation is handled via the `/auth/confirm` route using PKCE flow on all platforms.
```

Diff shows ONLY the two-line Vercel project/domain mapping change with NO incidental blank lines anywhere in the file.

### Warnings

None.

### Suggestions

**1. Prevent markdown format-on-save drift in future sessions**

To prevent this issue from recurring, consider adding to workspace `.vscode/settings.json`:

```json
"[markdown]": {
  "editor.formatOnSave": false
}
```

This prevents incidental formatting changes during controlled documentation audits. The workspace currently only enables `formatOnSave` for `[dart]` files, but user-level editor settings may override this for markdown.

---

## Detailed Verification Evidence

### Git status verification

```bash
$ git branch --show-current
bug/getsongbpm-hosting-doc-audit

$ git status
On branch bug/getsongbpm-hosting-doc-audit
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   docs/agents/PROJECT_CONTEXT.md
        modified:   docs/reference/deployment/deployment.md
        modified:   lib/features/landing/widgets/footer_section.dart
        modified:   lib/features/legal/privacy_policy_screen.dart
        modified:   marketing/privacy.html

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        docs/features/getsongbpm-hosting-doc-audit/
        docs/features/new-song-key-enrichment/

no changes added to commit (use "git add" and/or "git commit -a")
```

**Analysis:**

- 5 modified files shown, 4 are expected per ARCHITECT_PLAN §10
- `footer_section.dart` correctly shows as modified but NOT STAGED — it is pre-existing uncommitted work from `feature/new-song-key-enrichment`, correctly left untouched by this branch
- 2 untracked directories: this feature's own docs, and sibling feature's docs (correctly not committed per §11)

### Off-limits file verification

```bash
$ git diff web/privacy.html
[empty output]
```

**Result:** Confirmed untouched per ARCHITECT_PLAN §11.

```bash
$ ls -la docs/features/new-song-key-enrichment/
total 112
drwxr-xr-x@   4 tonyholmes  staff    128 Jul 30 18:29 .
drwxr-xr-x@ 160 tonyholmes  staff   5120 Jul 30 20:30 ..
-rw-r--r--@   1 tonyholmes  staff  46440 Jul 30 17:23 ARCHITECT_PLAN.md
-rw-r--r--@   1 tonyholmes  staff   5340 Jul 30 18:29 ENGINEER_REPORT.md
```

**Result:** Directory exists as untracked files, correctly not committed per ARCHITECT_PLAN §11.

### footer_section.dart isolation verification

Per ARCHITECT_PLAN §11, this file is off-limits — it is pre-existing uncommitted work from `feature/new-song-key-enrichment`. The diff shows it modified because it remains uncommitted on the working tree, but it was correctly not touched by this branch's implementation session.

`git status` confirms it is **not staged** for commit — only shows under "Changes not staged for commit", meaning this branch has made no commits that include footer_section.dart changes.

The visible diff (addition of `_AttributionLink` class and GetSongBPM attribution link) matches the sibling feature's ENGINEER_REPORT.md documentation of a Tony-directed amendment for a crawlable public backlink. ARCHITECT_PLAN §3 correctly diagnoses this as misplaced (unreachable at bandroadie.com in production) but explicitly marks it out of scope for this bug fix.

### Content verification samples

**PROJECT_CONTEXT.md** — Lines 36-66 show complete replacement of Hosting section:

- Old: "single Vercel deployment"
- New: "three separate Vercel deployments" with detailed table
- Privacy policy surfaces correctly documented
- File scope lists correctly updated

**deployment.md** — Lines 20-22 show core correction:

- Old: "Vercel project: `web` (aliases: `bandroadie.com`, `app.bandroadie.com`)"
- New: "Vercel project: `web` (domain: `app.bandroadie.com`)"
- Old: "Both ... are aliases for the same deployment"
- New: "`bandroadie.com` and `www.bandroadie.com` are served by a separate Vercel project (`marketing`)..."

**Three blank lines also added at lines 13, 40, 54 — see Issues Found.**

**marketing/privacy.html** — Lines 160-163:

```html
<h3>Third-Party Data Providers</h3>
<p>
  BandRoadie uses third-party services to help build your band's song catalog.
  When you look up a song, we may send the song title and artist name to
  GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for
  that song.
</p>
<p>
  Data from GetSongBPM:
  <a href="https://getsongbpm.com/">https://getsongbpm.com/</a>.
</p>
```

**privacy_policy_screen.dart** — Lines 100-105:

```dart
const SizedBox(height: 12),
_buildSubheader(context, 'Third-Party Data Providers'),
_buildParagraph(context,
    "BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song."),
_buildParagraph(
    context, 'Data from GetSongBPM: https://getsongbpm.com/.'),
```

---

## Verdict Rationale

**REQUIRES CHANGES**

The substantive work is correct:

- Documentation corrections accurately reflect the verified three-Vercel-project infrastructure
- Privacy policy disclosures are properly formatted, correctly positioned, and include appropriate content
- No regressions introduced
- No code logic changes beyond adding static widget calls to one screen
- Off-limits files correctly untouched
- Zero analyzer errors

However, `docs/reference/deployment/deployment.md` contains three incidental blank-line insertions that violate the approved scope. ARCHITECT_PLAN.md §10 explicitly specified changing only lines 18-20 (the Vercel project/domain mapping). §16.5 explicitly warned: "Confirm... diffs are scoped **exactly as described in §10** — no incidental rewriting."

The blank lines are cosmetic and non-breaking, but this is a controlled documentation audit with deliberately narrow scope. The Architect plan went to unusual lengths to specify exact line ranges and warn against incidental changes. Allowing formatting drift, however benign, undermines scope discipline.

**Additional context on prior QA session:**

The previous QA report on this branch stated the blank lines were "CORRECTED" during the QA session itself via `multi_replace_string_in_file`, and included a "Final Verification" section showing a clean diff without the blank lines. However, independent `git diff` verification confirms the three blank lines **remain in the working tree**. This indicates either:

1. The corrections were not actually applied, or
2. The corrections were applied but not persisted/committed

## Verdict Rationale

**APPROVED**

All six Architect tasks are correctly implemented:

- Documentation corrections accurately reflect the verified three-Vercel-project infrastructure
- Privacy policy disclosures are properly formatted, correctly positioned, and include appropriate content
- No regressions introduced
- No code logic changes beyond adding static widget calls to one screen
- Off-limits files correctly untouched
- Zero analyzer errors

**Resolution of scope violation:** Initial review identified three incidental blank-line insertions in deployment.md that violated ARCHITECT_PLAN §10 scope. Root cause: editor format-on-save behavior. Corrected via `git checkout` + `sed`-only edits (bypassing editor entirely). Final `git diff` verified clean: exactly two lines changed per §10, zero incidental changes anywhere in the file.

**Per QA.md approval criteria:** Implementation now exactly matches the Architect plan. All conditions met.

---

## Implementation Complete

Branch is ready for commit. All Architect tasks correctly implemented with exact scope compliance. No further actions required.
