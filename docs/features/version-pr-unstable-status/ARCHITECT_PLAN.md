# Architect Plan

## Feature Slug

version-pr-unstable-status

## Feature Title

Version-bump PR helper aborts while GitHub reports a newly-created PR as unstable

## Problem Summary

`tools/git_version_pr.sh` creates a version-bump PR and then immediately runs
`gh pr merge --auto --squash --delete-branch "$PR_NUMBER"`. When GitHub has not
yet finished computing the PR's mergeability, that call fails with
`GraphQL: Pull request Pull request is in unstable status
(enablePullRequestAutoMerge)` and the script exits 1. The failed helper leaves
the PR/branch on origin for manual recovery, and any rerun of
`./tools/deploy_web.sh` regenerates a new version bump (the same-day counter in
the version-sync Python block advances every run), producing a duplicate PR.
This is the pattern that caused PR #299 (merged manually after the abort) and
PR #300 (merged from the rerun) to both land on main and advance the build
number twice within roughly fifteen minutes.

## Root Cause

**HIGH.** Confirmed against the code and against the actual GitHub metadata for
PR #299 / PR #300:

- `tools/git_version_pr.sh` line ~50 issues `gh pr merge --auto --squash
  --delete-branch "$PR_NUMBER"` a single time, with no wait for GitHub's
  mergeability computation and no retry classification. Any nonzero exit is
  routed straight to `fail "..."`.
- `gh pr view 299 --json mergeStateStatus,mergeable` returns `UNKNOWN` /
  `UNKNOWN` even now, post-merge — the field is populated asynchronously by
  GitHub after PR creation. Immediately after `gh pr create`, mergeability is
  `null` server-side, and the GraphQL `enablePullRequestAutoMerge` mutation
  rejects with the "unstable status" error whenever mergeability is not yet
  resolved (empirically also on the `UNSTABLE` state when required checks are
  pending, despite `UNSTABLE` normally being a valid input for auto-merge —
  GitHub's error message conflates the two).
- `gh api repos/mplssign/bandroadie-web/pulls/300` confirms auto-merge was
  successfully enabled on PR #300 (`auto_merge.merge_method: "squash"`), but
  PR #299 has `auto_merge: null` — i.e., PR #299's `gh pr merge --auto` call
  was the one that failed, matching the reported sequence.
- The subsequent poll loop (`STATE = gh pr view ... --jq '.state'`) only checks
  for `MERGED`, so it can never recover from a failed auto-merge enable call —
  it never re-attempts the mutation.

The root cause is the missing "wait for mergeability to settle" + "retry on
the specific transient GraphQL error class" pair around the
`enablePullRequestAutoMerge` call. Everything else in the flow is correct.

## Existing System Analysis

- `tools/git_version_pr.sh` is the sole controlling helper. Callers:
  `tools/deploy_web.sh` (line 225) and `tools/build_web.sh` (line 174).
  `docs/reference/deployment/deployment.md` explicitly notes `tools/build_web.sh`
  is not used by any deploy path; both invocations are structurally identical,
  and fixing the helper covers both.
- `tools/deploy_web.sh` recomputes the version every run through the embedded
  Python block (`same_day_counter += 1` for the same date), so `git diff
  --cached` after `git add pubspec.yaml web/version.json` will produce fresh
  staged content on every rerun. This means a rerun after any helper failure —
  including the transient one — will emit a new bump commit and call the
  helper again. **This is the mechanism that produced PR #300 after PR #299.**
  Fully addressing rerun-produces-duplicate-bump requires changes to
  `deploy_web.sh`'s version-sync step and is out of scope here (see Out of
  Scope); the helper can only narrow the window with an "open version-bump PR
  already exists" preflight guard.
- Prior fix (`bug-git-version-pr-json-flag-unsupported`, PR #200) already
  removed the unsupported `--json/--jq` flags on `gh pr create` and started
  capturing output for `fail` messages. The current control flow and error
  handling around `gh pr merge` are untouched by that change and remain the
  weak point.
- The helper is bash-only (`#!/usr/bin/env bash`, `set -euo pipefail`), uses
  `[[ ]]`, `$(...)`, `grep`, and portable shell primitives. No zsh idioms.
  This must be preserved.

## Proposed Solution

Modify `tools/git_version_pr.sh` only. Three narrow changes, in this order in
the file:

1. **Open-PR preflight guard.** Before creating the timestamped branch, query
   `gh pr list --state open --base main --json number,url,headRefName --jq
   '.[] | select(.headRefName | startswith("chore/version-bump-")) |
   .url'`. If any URL is returned, fail with a message that names the URL so
   Tony can resolve or close it before rerunning. This closes the "prior
   helper aborted, PR still open on origin" duplicate-PR variant.

2. **Wait for mergeability before enabling auto-merge.** After `PR_NUMBER` is
   captured and before the merge call, poll `gh pr view "$PR_NUMBER" --json
   mergeStateStatus --jq '.mergeStateStatus'` at 5 s intervals for up to
   ~30 s (6 iterations). Break as soon as the value is anything other than
   `UNKNOWN`. On timeout, proceed anyway — the retry loop below is
   authoritative and this poll is a best-effort optimization to avoid the
   first retry hit.

3. **Retry the auto-merge enable call on the transient error class only.**
   Replace the single `gh pr merge --auto --squash --delete-branch
   "$PR_NUMBER"` call with a capped retry loop (5 attempts, exponential
   backoff starting at 3 s and doubling). Capture the combined stdout/stderr
   into a variable. On failure, run `grep -qE 'unstable status|pending
   state|Base branch was modified'` on the captured output; retry only on a
   match, fail immediately otherwise. The retry-exhausted `fail` and every
   post-PR-creation `fail` must include the created `PR_URL` so Tony has a
   direct link to complete the merge manually.

The merged-state polling loop that already exists (`STATE == "MERGED"`) is
correct and stays as-is. The `git checkout main && git fetch origin && git
reset --hard origin/main` sequence at the tail is correct and stays as-is.

To keep the retry logic mechanically testable without a live PR, wrap it in a
shell function (e.g., `enable_auto_merge_with_retry <PR_NUMBER> <PR_URL>`) and
guard the top-level flow with `if [[ "${VERSION_PR_SOURCE_ONLY:-0}" != "1" ]];
then main; fi` so the test file can `source` the helper without triggering the
gh calls at the top level. This is a bounded four-line scaffolding change, not
a rewrite.

## Database Impact

Not applicable.

## Flutter Architecture Changes

Not applicable.

## Files to Create

- `test/tools/git_version_pr_retry_test.sh` — bash test that stubs `gh` on
  `PATH` via a scripted response file, sources `tools/git_version_pr.sh` with
  `VERSION_PR_SOURCE_ONLY=1` to skip the top-level flow, and invokes
  `enable_auto_merge_with_retry` against three scripted scenarios:
  transient-twice-then-success, non-transient-first-attempt, and
  transient-past-budget. Prints `PASS <scenario>` lines and exits 0 only when
  all three assertions hold. Uses `#!/usr/bin/env bash`, `set -euo pipefail`,
  and only POSIX/BSD-compatible utilities (no `grep -P`, no GNU-only `sed`
  flags). Never invokes the real `gh` binary — the stub intercepts every call
  by putting a temp directory ahead on `PATH`.

## Files to Modify

- `tools/git_version_pr.sh` — add open-PR preflight guard; wrap the auto-merge
  enable call in a `wait for mergeStateStatus` poll plus a
  `enable_auto_merge_with_retry` function with capped exponential retry and
  transient/fatal classification; include `PR_URL` in every post-creation
  `fail` message; add the `VERSION_PR_SOURCE_ONLY` guard so the file can be
  sourced by the test without triggering the live flow.

## Files Off-Limits

- `tools/deploy_web.sh` — invocation site is already correct; changing
  `deploy_web.sh`'s idempotency semantics exceeds this fix's scope and belongs
  in a separate ticket (see Out of Scope).
- `tools/build_web.sh` — documented in `docs/reference/deployment/deployment.md`
  as not used by any build or deploy path; identical invocation to
  `deploy_web.sh`. Touching it is either wasted diff or an accidental scope
  expansion. Fixing the helper transparently benefits any call site.
- `tools/generate_version.sh`, `tools/gen_dart_defines.sh`, `tools/build_*.sh`,
  `tools/deploy_marketing.sh` — unrelated tooling paths.
- `lib/**`, `test/**` (except the single new file at `test/tools/`),
  `supabase/**`, `android/**`, `ios/**`, `macos/**`, `web/**`,
  `pubspec.yaml`, `pubspec.lock`, `web/version.json` — no app runtime,
  platform, database, or version-artifact changes.
- `docs/reference/deployment/deployment.md` — the internal helper behavior
  change does not alter the documented deploy interface (`./tools/deploy_web.sh`
  is still the entry point). No documentation change required.
- `.github/workflows/**` — no CI changes.

## Change Budget

- `tools/git_version_pr.sh` — currently 55 lines. Expected net delta: **+40
  lines**, ceiling **+55 lines**. Breakdown: open-PR guard (~8), mergeability
  poll (~10), retry loop with classification (~18), `PR_URL` interpolation
  into existing fail strings (~2), `VERSION_PR_SOURCE_ONLY` guard + function
  wrap (~4). No lines removed apart from the single-call `MERGE_OUTPUT=...`
  block that the loop replaces.
- `test/tools/git_version_pr_retry_test.sh` — new file. Expected: **~70
  lines**, ceiling **90 lines**. Includes shebang, `set -euo pipefail`, temp
  dir setup/teardown, three scenario blocks, and result printing.
- Expected new files: **1** (the test file).
- Expected new public classes/methods: **0** (shell).
- Expected new dependencies: **0**.
- Off-limits files with expected delta: **0 lines** each.

## System Impact Map

- Gigs: unaffected.
- Rehearsals: unaffected.
- Setlists / Catalog: unaffected.
- Members / RBAC: unaffected.
- Auth / Session: unaffected.
- Routing: unaffected.
- Notifications: unaffected.
- Platforms (iOS/Android/macOS/Web at runtime): unaffected.
- Release automation / `deploy_web.sh` version-bump PR step: **fixed** — the
  helper now tolerates GitHub's transient post-creation `enablePullRequestAutoMerge`
  rejection and completes a single deploy invocation without operator
  intervention. `deploy_web.sh` line 225 invocation contract is unchanged.
- `tools/build_web.sh`: functionally benefits from the fixed helper it calls;
  file content unchanged.

## Regression Risk

**LOW.** The change is isolated to a single shell helper used only by
release tooling. No Flutter, Dart, Supabase, RLS, RPC, routing, auth,
platform, or init-order code is touched. The helper's public contract
(`./tools/git_version_pr.sh` from `main` with a staged version-bump commit,
returns 0 after merge, non-zero otherwise) is unchanged. Failure-path
behavior is strictly improved — the retry-exhausted path still exits non-zero
with the PR URL, matching the current post-creation failure semantics.

## Engineer Task Breakdown

1. In `tools/git_version_pr.sh`, before the `BRANCH_NAME=...` line, add an
   open-PR guard that runs `gh pr list --state open --base main --json
   number,url,headRefName --jq '.[] | select(.headRefName | startswith(...))
   | .url'`, captures the first URL if any, and calls `fail` with the URL
   embedded in the message. Do not close or modify the existing PR.

2. In `tools/git_version_pr.sh`, extract the current `gh pr merge --auto
   --squash --delete-branch "$PR_NUMBER"` line into a new bash function
   `enable_auto_merge_with_retry` that takes `PR_NUMBER` and `PR_URL`. Inside
   the function:
   - Poll `gh pr view "$PR_NUMBER" --json mergeStateStatus --jq
     '.mergeStateStatus'` up to 6 times at 5 s intervals; break as soon as
     the returned string is not `UNKNOWN`. On timeout, proceed to the retry
     loop without failing.
   - Run the `gh pr merge --auto --squash --delete-branch "$PR_NUMBER"` call
     inside a retry loop capped at 5 attempts. On success, return 0. On
     failure, capture combined stdout/stderr, then classify with `grep -qE
     'unstable status|pending state|Base branch was modified'`. Retry with
     exponential backoff (start 3 s, double each attempt) on a match; call
     `fail "Unable to enable PR auto-merge (PR: $PR_URL): $MERGE_OUTPUT"`
     immediately on any other error.
   - After the 5th failed attempt, call `fail "PR auto-merge remained in
     transient/unstable state after 5 attempts. Complete the merge manually,
     then rerun deploy. PR: $PR_URL"`.

3. In `tools/git_version_pr.sh`, replace the current single-shot merge call
   with `enable_auto_merge_with_retry "$PR_NUMBER" "$PR_URL"`.

4. In `tools/git_version_pr.sh`, update the existing merged-state polling
   loop's timeout `fail` (`Version-bump PR did not merge automatically within
   the timeout...`) to append `PR: $PR_URL` so operators always have the
   link. No behavioral change to the poll itself.

5. In `tools/git_version_pr.sh`, wrap the top-level flow (everything after
   the function definitions) in `if [[ "${VERSION_PR_SOURCE_ONLY:-0}" != "1"
   ]]; then ... fi`, or equivalently guard a `main` function and only call it
   under that condition. The guard is a testability seam only — it must not
   affect production execution when the env var is unset.

6. Create `test/tools/git_version_pr_retry_test.sh` per the "Files to Create"
   description. Run three scenarios against a stubbed `gh` on `PATH`:
   (a) transient-twice-then-success returns 0; (b) non-transient-first-attempt
   returns non-zero and does not retry (assert stub was called exactly once);
   (c) transient-past-budget returns non-zero with `PR_URL` present in the
   error output (assert stub was called exactly 5 times). Each scenario
   prints `PASS <name>` on success. Overall script exits 0 only when all
   three pass. Never invoke the real `gh` binary — the stub intercepts every
   call by prepending a temp directory to `PATH`.

7. Verify `bash -n tools/git_version_pr.sh` and `bash -n
   test/tools/git_version_pr_retry_test.sh` both return 0. Do not run
   `./tools/deploy_web.sh` or any deploy command.

## Verification Plan

### Tier 1 — pre-deploy, mechanically executable, never touches the real `gh`

1. `bash -n tools/git_version_pr.sh` — exit 0 (syntax).
2. `bash -n test/tools/git_version_pr_retry_test.sh` — exit 0 (syntax).
3. `bash test/tools/git_version_pr_retry_test.sh` — exit 0. All three
   scenarios print `PASS`. This is the primary correctness gate:
   - Transient error twice then success → `enable_auto_merge_with_retry`
     returns 0; stub `gh` was called 3 times.
   - Non-transient error on first attempt → function returns non-zero; stub
     was called exactly once (no retry on unclassified errors).
   - Transient error 5 times → function returns non-zero; error message
     contains the fake `PR_URL`; stub was called exactly 5 times.
4. Static grep: `grep -c "gh pr merge --auto" tools/git_version_pr.sh` — exact
   count **1** (the single source-level call inside the retry function).
5. Static grep: confirm the classification regex is bounded — `grep -E
   "grep -qE 'unstable status\|pending state\|Base branch was modified'"
   tools/git_version_pr.sh` returns exactly one line. Reject a broad catch-all
   like `grep -q .` or `2>/dev/null || true` on the merge call itself.
6. Static grep: confirm every `fail "..."` line that appears after the `gh
   pr create ...` block references `$PR_URL`. Command: `awk
   '/^PR_URL=/,0' tools/git_version_pr.sh | grep -E '^\s*fail ' | grep -v
   'PR_URL\|\$PR_URL'` — expected 0 lines (no post-creation `fail` without
   `PR_URL`).
7. Static grep: `grep -c "VERSION_PR_SOURCE_ONLY" tools/git_version_pr.sh`
   — exactly **1** (the guard).

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

## QA Regression Areas

- No app runtime code, no state management, no widgets, no providers, no
  routes, no auth, no notifications, no platform channels, no Supabase
  queries, no migrations, no RPCs, no RLS. Nothing to regression-test at
  runtime — QA's app-level checks would produce no signal.
- The only regression surface is the shell tooling itself. QA gates:
  - Tier 1 items 1–7 above must all pass.
  - Static diff review: confirm no changes outside
    `tools/git_version_pr.sh` and `test/tools/git_version_pr_retry_test.sh`.
    `git diff --name-only main...bug/version-pr-unstable-status` must list
    exactly those two files (plus this plan file).
  - `flutter analyze` is expected to pass unchanged (no Dart code touched).
    Run it once to confirm zero new issues attributable to this branch —
    this is a cheap sanity check, not a targeted signal.

## Rollout Strategy

- Merge the PR through the normal review path.
- No feature flag, no migration, no doc update, no coordinated deploy.
- The fix takes effect on the next `./tools/deploy_web.sh` invocation from
  `main`.
- No rollback plan needed beyond `git revert` — the helper is idempotent at
  the shell level and produces no persistent state.

## Out of Scope

- **`deploy_web.sh` idempotency.** A rerun after a successful helper still
  produces a new same-day version bump because the embedded Python block
  unconditionally increments the same-day counter. Fixing this properly
  requires the deploy script to detect whether the current pubspec version
  is already the latest same-day version on origin main and skip the bump
  if so, or to gate the bump on a `--force-bump` flag. This is a distinct
  behavior change worth its own diagnosis and is not required to close the
  reported abort.
- **Removing `tools/build_web.sh`.** Documented as unused but still present.
  Removing it is a hygiene task, not part of this fix.
- **Migrating the helper to a GitHub Actions workflow or Python script.**
  Larger architectural direction, not required by the reported symptom.
- **Any app-runtime, platform, or database change.** The reported failure is
  entirely in developer release tooling; app runtime is confirmed unaffected.
