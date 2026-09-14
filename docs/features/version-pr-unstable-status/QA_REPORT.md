# QA Report

## Feature Slug

version-pr-unstable-status

## Feature Title

Version-bump PR helper aborts while GitHub reports a newly-created PR as unstable

## Cycle Number

1

## Final Verdict

APPROVED

## Validation Summary

The implementation matches the Architect plan. All seven non-live Tier 1 checks passed using the isolated stubbed `gh` harness, and `flutter analyze` reported no issues. QA performed static code-path analysis and stubbed shell execution only. No build, deploy, live GitHub mutation, app launch, browser automation, production action, git write, or `.github/agents/` edit was performed.

## Architect Scope Review

- The feature slug matches the branch, Architect plan, and Engineer report.
- Implementation changes are limited to `tools/git_version_pr.sh` and the planned new `test/tools/git_version_pr_retry_test.sh`.
- `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, and this report are pipeline documentation artifacts.
- No off-limits app, platform, database, deployment caller, workflow, version artifact, or dependency file changed.
- The invocation contract used by `tools/deploy_web.sh` and `tools/build_web.sh` remains unchanged.

## Completeness Check

- The open-PR duplicate guard runs before branch creation, selects open `chore/version-bump-*` heads targeting `main`, preserves the first returned PR URL, and fails without modifying the existing PR.
- Mergeability is polled up to six times at five-second intervals and proceeds to the authoritative retry loop after an `UNKNOWN` timeout.
- Auto-merge is attempted at most five times. Only `unstable status`, `pending state`, and `Base branch was modified` are retried.
- Backoff is capped to the four between-attempt sleeps: 3, 6, 12, and 24 seconds.
- Non-transient errors fail after one attempt. Retry exhaustion fails after exactly five attempts.
- Every failure path reachable after successful PR creation preserves the PR URL.
- The existing merged-state polling and successful checkout/fetch/reset cleanup remain behaviorally unchanged.
- The source-only guard leaves normal execution unchanged when unset and permits isolated function tests when set to `1`.
- All three planned retry scenarios are present and assert their required merge-call counts.

## Behavior Verification

**Method:** static code-path analysis plus execution against the test-owned stubbed `gh`; not live GitHub runtime verification.

The stubbed transient-twice-then-success path returned success after three merge calls. The fatal path returned non-zero after one merge call. The exhausted transient path returned non-zero after five merge calls and retained the fake PR URL in its error output. The harness also returns a resolved mergeability state, so these scenarios exercise retry classification without invoking real GitHub or waiting through production backoff.

The open-PR query, six-probe mergeability loop, exponential backoff arithmetic, merged-state polling, URL propagation, and success cleanup were confirmed by code-path analysis. Their live GitHub behavior remains owner-run verification as required by the plan.

## Regression Check

**Risk: LOW.** The only affected system is release automation's version-bump PR helper. Gigs, rehearsals, setlists/catalog, members/RBAC, auth/session, routing, notifications, Flutter initialization, controllers/focus nodes, async widget state, Supabase, and all runtime platforms are untouched. Both existing helper callers continue to use the same command contract.

## Database Safety

Not applicable. No SQL, migration, RPC, RLS, grants, or Supabase files changed.

## Analyzer Results

`flutter analyze` completed successfully with `No issues found!`.

## Test Results

- `bash -n tools/git_version_pr.sh`: passed.
- `bash -n test/tools/git_version_pr_retry_test.sh`: passed.
- `bash test/tools/git_version_pr_retry_test.sh`: passed under macOS Bash 3.2.57.
- Output: `PASS transient-twice-then-success`.
- Output: `PASS non-transient-first-attempt`.
- Output: `PASS transient-past-budget`.
- Static merge-call count: 1.
- Static bounded-classifier count: 1.
- Post-create failures missing PR URL: 0.
- Source-only guard count: 1.

## Diff Safety Review

- No secret or API-key pattern was found.
- No implementation `TODO`, `FIXME`, `debugPrint(`, test scaffolding leak, accidental deletion, or unrelated formatting churn was found.
- The test places its executable `gh` stub first on `PATH`; every exercised `gh pr view` and `gh pr merge` call is therefore intercepted.
- The test overrides `sleep`, uses only Bash and BSD-compatible utilities, and cleans its own temporary directory through an `EXIT` trap. No test directory remained after execution.
- No real `gh`, deploy, build, app runtime, or production command was invoked.

## Change Budget Review

- `tools/git_version_pr.sh`: 92 insertions and 44 deletions, net `+48` lines versus expected `+40` and ceiling `+55`; within budget.
- `test/tools/git_version_pr_retry_test.sh`: 90 lines versus expected approximately 70 and ceiling 90; within budget.
- New implementation files: 1 planned test file.
- New dependencies: 0. New public classes/methods: 0.
- The bug fix includes 44 deleted lines, so the zero-deletion warning does not apply.

## Code Efficiency Review

The retry function is required by the Architect plan and is directly exercised by three scenarios. An independent search found no pre-existing equivalent mergeability/retry helper in `tools/`. No single-use wrapper, speculative state/configuration, redundant provider, hand-rolled collection utility, dead parameter, or unrelated abstraction was introduced.

## Manual Verification Punch List

The following is the Architect's owner-run live verification plan, reproduced verbatim. QA did not execute these live checks; they do not block this verdict because the Architect explicitly classifies them as Tier 2 owner-run verification.

### Tier 2 — owner-run at PR-test or apply time (QA cannot exercise live GitHub PRs)

QA cannot run `./tools/deploy_web.sh`, cannot create real PRs, and cannot
open a browser to inspect GitHub. This punch list is for Tony to run
verbatim once the PR is merged (or on a preview branch that opts into the
version-bump path):

1. From clean, synchronized main:
   ```
   git checkout main && git pull --ff-only && git status --short
   ```
   Expected: no output from `git status --short`.
2. Run `./tools/deploy_web.sh`. During the version-bump phase, observe the
   terminal output for one of these two shapes:
   - No retry needed: no "Retrying auto-merge..." lines; merge polling
     proceeds to `MERGED`.
   - Retry hit: one or more `Retrying auto-merge (attempt N of 5)...` lines,
     then successful merge and squash.
3. Expected exit code: `echo $?` returns 0 immediately after the script
   finishes. Deploy proceeds through analyze/test/build/deploy.
4. On GitHub, confirm exactly one new PR titled `chore: bump build version`
   was created during this run, is now `MERGED`, and its head branch was
   auto-deleted.
5. On origin: `git log --oneline -1 origin/main` shows exactly one new
   squash-merge commit at the tip.
6. On local: `git rev-parse main` equals `git rev-parse origin/main`.
7. Rerun edge case: immediately rerun `./tools/deploy_web.sh`. Expected: it
   either produces a NEW valid version-bump PR (same-day counter advances
   and merges cleanly) or refuses with the "open version-bump PR already
   exists" preflight guard message. It must **never** re-emit the original
   "unstable status" abort.

### Tier 2 failure-mode punch list (if the retry budget is genuinely exhausted)

1. Confirm the terminal printed the created PR URL as part of the
   `fail` message.
2. On GitHub, open that PR URL. Confirm it exists and is open.
3. Confirm local `main` was NOT reset (`git log --oneline -3 main` still
   shows the pre-PR tip; the version-bump commit is only on the feature
   branch, not on `main`).
4. Merge the PR manually via GitHub UI, then locally:
   `git checkout main && git pull --ff-only`.
5. Rerun `./tools/deploy_web.sh`.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.