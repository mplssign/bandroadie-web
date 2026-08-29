# Feature Slug

bug/deploy-script-blocked-by-branch-protection

# Problem Summary

The build/deploy automation in `tools/deploy_web.sh` and `tools/build_web.sh` bumps the app version in `pubspec.yaml` and `web/version.json`, commits that change, and then pushes directly to `main`. GitHub branch protection on `bandroadie-web` now requires all changes to `main` to go through a pull request. The direct push is rejected with `GH013`, which aborts the script after the local version bump is committed but before the build/test/deploy pipeline can continue. The repo ruleset blocks the bypass pattern the current scripts rely on. The fix must preserve the pending local version-bump commit already sitting on `main`, while moving future version bumps through a short-lived branch + PR + auto-merge flow instead of pushing directly to `main`.

# Root Cause

The root cause is a direct, non-PR push to `main` in both deploy scripts. The scripts follow this sequence: version bump -> `git commit` -> `git push origin main`. That sequence violates the repo ruleset and fails with branch-protection enforcement. The local main branch is already ahead of `origin/main` because of the failed version-bump commit, so the fix must account for that existing divergence without silently discarding or duplicating it.

Root cause confidence: HIGH.

# Reference Docs Consulted

This issue is not in the notifications domain; no notification reference docs were relevant to the root cause. The relevant evidence came from the actual build/deploy tooling in the repo, specifically:

- `tools/deploy_web.sh`
- `tools/build_web.sh`

No files under `docs/reference/notifications/` were consulted because this is not a notification bug and the scope is explicitly limited to release automation.

# Existing System Analysis

The current behavior is consistent across both scripts:

1. The script validates the local branch is `main` and that it is synced with `origin/main`.
2. It updates the semantic/build version in `pubspec.yaml` and `web/version.json`.
3. It stages those files and makes a commit with message `chore: bump build version`.
4. It immediately runs `git push origin main`.
5. GitHub rules reject the push with a branch-protection violation.
6. The script exits before the build, test, and deploy work runs.

This means the failure is not in Flutter or the web build itself. The failure is in the release workflow’s git strategy: it tries to push a version-bump commit directly to a protected branch. The pending local commit already on `main` also proves the scripts do not handle the case where `main` is locally ahead of `origin/main` from a previous failed attempt.

# Proposed Solution

Implement a minimal branch-and-PR release workflow instead of a direct push to `main`.

Preferred approach:

- Add a tiny shared helper script (example: `tools/git_version_pr.sh`) that encapsulates the version-bump + branch + PR + auto-merge logic.
- Have both `tools/deploy_web.sh` and `tools/build_web.sh` call the helper after the version bump is generated.
- The helper must:
  - verify the `gh` CLI is installed and authenticated (`gh auth status`)
  - check whether the repo has auto-merge enabled for PRs; if not, fail with a clear error instead of silently continuing or falling back to direct push
  - preserve any local commit(s) already ahead of `origin/main` by creating the PR branch from the current `main` HEAD, not from a freshly reset `origin/main`
  - create a short-lived branch (for example `chore/version-bump-<timestamp>`)
  - push the branch to origin
  - open a PR with `gh pr create --base main --head <branch> --title "chore: bump build version" --body "Automated version bump"`
  - enable auto-merge with `gh pr merge --auto --squash --delete-branch` (or equivalent supported syntax)
  - wait for the PR to merge and then update local `main` with `git fetch origin` and `git pull --ff-only origin main`
  - continue the build/test/deploy pipeline only after the merge succeeds

This keeps the same build and deploy behavior, but replaces the forbidden push to `main` with a compliant GitHub PR flow. It also preserves the existing unpushed version bump already committed on `main` rather than silently dropping it.

What must not change:

- no app source changes
- no Supabase changes
- no CI workflow changes
- no ruleset bypass or direct push to `main`
- no changes to the Flutter build/test/deploy logic beyond the repo gating step

# Database Impact

Database: not applicable.

This fix does not modify database schema, migrations, RLS, SQL functions, or any application runtime. There are no database writes from the script beyond pushing git metadata to GitHub. No migration is required.

# Flutter Architecture Changes

Flutter architecture changes: none.

This is build automation only. No app state, widget tree, repository, provider, auth, or database layer is modified. The fix is isolated to shell tooling and GitHub PR flow.

# Files to Create

- `tools/git_version_pr.sh` — optional shared helper to centralize branch/PR/auto-merge logic and keep the two scripts minimal and consistent.

If the team prefers to avoid a new helper, the same logic can be embedded in both scripts, but the helper is cleaner and avoids duplicated PR logic.

# Files to Modify

| File                  | What changes                                                                                                                                                      |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools/deploy_web.sh` | Replace the direct `git push origin main` after version bump with a PR-based branch flow, including explicit preflight checks for `gh` and auto-merge capability. |
| `tools/build_web.sh`  | Apply the same PR-based flow at the identical version-bump step so the same root cause is fixed in both scripts.                                                  |

# Files Off-Limits

| File                   | Reason                                                                                                                                                   |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/**`               | Application runtime is not in scope; this is a deployment-tooling bug.                                                                                   |
| `supabase/**`          | No database or backend change is needed; the issue is GitHub branch protection, not app or DB logic.                                                     |
| `android/**`           | Not relevant to the root cause and outside the release script scope.                                                                                     |
| `ios/**`               | Not relevant to the root cause and outside the release script scope.                                                                                     |
| `macos/**`             | Not relevant to the root cause and outside the release script scope.                                                                                     |
| `web/**`               | Version file is already intentionally updated by the script; no direct app source edits needed.                                                          |
| `.github/workflows/**` | User explicitly stated CI files should not be touched unless investigation shows they are required; this issue is fixed in the shell scripts themselves. |

# System Impact Map

| System                                  | Impact     |
| --------------------------------------- | ---------- |
| Gigs                                    | unaffected |
| Rehearsals                              | unaffected |
| Setlists / Catalog                      | unaffected |
| Members / RBAC                          | unaffected |
| Auth / Session                          | unaffected |
| Routing                                 | unaffected |
| Notifications                           | unaffected |
| Platform (iOS / Android / Web / macOS)  | unaffected |
| GitHub branch protection / repo ruleset | affected   |
| Release automation / deploy scripts     | affected   |

# Regression Risk

Regression risk: MEDIUM.

Rationale:

- The change affects the release automation path only; app logic is untouched.
- The repo policy and GitHub CLI behavior are external dependencies, so operational failures are possible if `gh` is missing, unauthenticated, or auto-merge is disabled.
- The risk is limited to deployment scripts and branch flow, but an incorrect implementation would block releases. The fix is still small and localized.

# Engineer Task Breakdown

1. Confirm the current branch state and whether there is a local version-bump commit ahead of `origin/main`.
2. Create or reuse a minimal helper function/script to perform version-bump PR creation and auto-merge.
3. Update `tools/deploy_web.sh` to replace the direct `git push origin main` with the PR-based flow and clear failure messages.
4. Update `tools/build_web.sh` in the same way, using the same helper logic.
5. Ensure the scripts preserve the existing local bumped commit rather than resetting or duplicating it.
6. Validate the helper handles the `gh` dependency and repo auto-merge requirement explicitly.
7. Prepare the final verification notes for QA and Tony.

# Verification Plan

Tier 1 — Pre-deployment (must pass before build or deploy proceeds):

- `-- PRE-DEPLOY TEST 1:` verify `gh` is installed: `gh --version`
- `-- PRE-DEPLOY TEST 2:` verify the user is authenticated to the repo: `gh auth status`
- `-- PRE-DEPLOY TEST 3:` verify the repo is reachable and the target repo is configured: `gh repo view --json nameWithOwner`
- `-- PRE-DEPLOY TEST 4:` verify the PR auto-merge setting is enabled in the GitHub repo settings; if not, fail early with a clear message because `gh pr merge --auto` will not succeed without it
- `-- PRE-DEPLOY TEST 5:` check for an existing local version-bump commit ahead of `origin/main` and confirm the flow preserves it: `git rev-list --count origin/main..main` and `git log --oneline --decorate -n 5`
- `-- PRE-DEPLOY TEST 6:` confirm no direct push to `main` is attempted by the script after the bump; this is a code review/grep validation, not a runtime deploy step: `grep -n "git push origin main" tools/deploy_web.sh tools/build_web.sh`

Tier 2 — Post-deployment (run after the script has reached the PR/open-merge stage):

- `-- POST-DEPLOY TEST 1:` verify a PR was opened for the version-bump branch: `gh pr list --state open --limit 10`
- `-- POST-DEPLOY TEST 2:` verify the PR merges automatically: `gh pr view <pr-number> --json state,mergeStateStatus,autoMergeRequest`
- `-- POST-DEPLOY TEST 3:` verify `main` is updated after merge: `git fetch origin && git rev-parse main && git rev-parse origin/main` and ensure they match
- `-- POST-DEPLOY TEST 4:` verify the version-bump commit is present on `main` exactly once and is not duplicated: `git log --oneline --decorate -n 5 main`
- `-- POST-DEPLOY TEST 5:` confirm the script proceeds past the PR merge and continues with the normal build/test/deploy actions, rather than exiting early on a push rejection

Important note: no database migration or SQL validation is relevant here. The automation fix does not write app data or alter database objects, so the SQL-specific pre/post-deploy validation pattern is not applicable. There is no production data integrity query to run for this ticket because the fix is entirely in shell tooling and GitHub PR flow.

# QA Regression Areas

QA should specifically verify:

- the direct `git push origin main` path is no longer used in both scripts
- the version bump still updates both `pubspec.yaml` and `web/version.json` correctly
- the pending local version-bump commit is preserved rather than dropped or duplicated
- a short-lived branch is created, PR is opened, and the PR auto-merges without manual approval
- a clear failure appears if `gh` is missing, not authenticated, or if repo auto-merge is disabled
- the build/test/deploy sequence resumes after the PR merge and does not exit early
- both `tools/deploy_web.sh` and `tools/build_web.sh` are fixed in the same pass without regression to the other script

# Rollout / Migration Strategy

No database migration is required. The rollout is operational only:

1. update the two scripts in place
2. ensure `gh` is installed and authenticated on Tony’s machine
3. confirm the repo has “Allow auto-merge” enabled in the GitHub settings
4. run the scripts from `main` after the patch and verify the PR-based flow works end-to-end
5. if the repo still rejects auto-merge, the script should fail clearly with actionable guidance instead of falling back to a forbidden push

# Out of Scope

- all app runtime code and UI changes
- any Supabase database changes or migrations
- CI workflow edits or GitHub Actions changes
- disabling branch protection or creating a bypass user/service account
- any unrelated cleanup or refactoring beyond the minimal script changes required for the PR-based fix
