# QA Report

## Feature Slug

bug-git-version-pr-json-flag-unsupported

## Feature Title

Fix git_version_pr.sh unsupported gh pr create JSON flags and improve error visibility

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

Verified the core implementation against the Architect baseline via code inspection, bash parameter expansion testing, and git diff analysis. The fix to tools/git_version_pr.sh is correct and complete. However, an unrelated formatting change to pubspec.yaml (whitespace added before "- family: Noto Sans") violates the Architect scope and must be removed before commit.

## Architect Scope Review

- Scope adherence: **violated**
- Files modified: **deviations noted below**
- Files off-limits: **violations noted below**

### Deviation: pubspec.yaml Unrelated Formatting Churn

The file `pubspec.yaml` was modified with formatting changes unrelated to the bug fix:

- Line 95 in diff: Added ~40 spaces before `- family: Noto Sans`
- This is pure whitespace churn, not functional to the fix
- Violates GUARDRAILS §7: "Modify only files in the Architect plan"
- Violates GUARDRAILS §7a: "Never refactor opportunistically"

**Action required:** Remove this change from pubspec.yaml before commit.

### Approved Files: Confirmed ✓

- `tools/git_version_pr.sh` — only file intended to change
- `docs/features/bug-git-version-pr-json-flag-unsupported/ENGINEER_REPORT.md` — feature documentation, expected

## Completeness Check

- All Architect tasks implemented: **yes**
- Missing tasks: none

### Task Verification

1. **Replace gh pr create --json/--jq usage with URL capture and PR number extraction** — ✓ Confirmed
   - Old: `gh pr create ... --json number --jq '.number' 2>/dev/null`
   - New: `gh pr create ... 2>&1` captures full URL, then `PR_NUMBER="${PR_URL##*/}"` extracts the PR number
   - This approach is sound: `gh pr create` returns the PR URL as its only output on success

2. **Audit swallowed-error patterns and include captured output in fail paths** — ✓ Confirmed
   - All 10 prior `>/dev/null 2>&1` error suppressions in the file have been converted
   - Each now captures output into a variable and includes it in the fail message
   - Verified via grep: only one remaining `>/dev/null 2>&1` on line 19 (the `command -v gh` existence check, which is appropriate to leave as-is per Architect plan)

3. **Validate shell syntax and PR number extraction behavior** — ✓ Confirmed
   - `bash -n tools/git_version_pr.sh` passes with no syntax errors
   - PR number extraction test: `PR_URL="https://github.com/mplssign/bandroadie-web/pull/199"` → `PR_NUMBER="${PR_URL##*/}"` → `199` ✓ correct

## Behavior Verification

- Validation method: code-path analysis + bash parameter expansion testing
- Result: **matches expected**

The fix addresses the root cause identified by Manager:

- gh CLI removed support for `--json`/`--jq` flags on `gh pr create` (confirmed via live testing by Tony)
- Script now uses URL capture instead, which is the documented output format
- PR number extraction via bash parameter expansion `"${PR_URL##*/}"` is a standard, reliable shell idiom
- Error visibility is improved by capturing all command stderr/stdout and including it in fail messages

## Regression Check

- Risk level: **LOW**
- Systems reviewed: shell script build tooling (git, GitHub CLI)
- Regressions found: none

### Analysis

The changes are localized to a single build-time script that runs only during CI/CD version-bump workflows. No production Dart/Flutter code affected. No state management, no UI, no Supabase interactions. The fix introduces no new dependencies or architectural changes.

## Database Safety

Not applicable — this is a build script, no database access.

## Analyzer Results

Command: `bash -n tools/git_version_pr.sh`
Result: ✓ 0 syntax errors

## Test Results

Passed:

- PR number extraction local test: `"https://github.com/mplssign/bandroadie-web/pull/199"` → `"199"` ✓

## Diff Safety Review

- Secrets: none found ✓
- Debug artifacts: none found ✓
- Unrelated changes: **found** — pubspec.yaml formatting churn (see "Deviation" above)

## Code Efficiency Review

- Dead code / unused imports, vars, params: none found ✓
- Redundant restating comments: none found ✓
- Unnecessary abstraction for single call sites: none found ✓
- Unneeded defensive checks (impossible-case guards, try/catch): none found ✓
- Duplicated logic that should reuse existing code: none found ✓
- Overall assessment: lean ✓

The script changes are minimal and direct: capture command output, include it in error messages. No bloat introduced.

## Issues Found

### Critical (must fix before commit)

1. **pubspec.yaml formatting churn** — Lines 95–96 add ~40 spaces before `"- family: Noto Sans"`. This is unrelated to the bug fix and violates GUARDRAILS §7 (modify only approved files) and §10 (Git discipline / commit message discipline). Revert this file to its state on `main` before commit.

---

## Recommendation

**Implementation is correct and complete.** Revert `pubspec.yaml` to main, keep all changes to `tools/git_version_pr.sh` and feature docs. Then re-submit for QA approval.
