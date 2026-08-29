# Engineer Report

## Feature Slug

bug/deploy-script-blocked-by-branch-protection

## Feature Title

Deploy scripts blocked by branch protection

## Goal

Replace the direct `git push origin main` flow in the web deploy/build scripts with a PR-based branch + auto-merge flow that preserves the existing local version-bump commit and keeps the release pipeline compliant with GitHub branch protection.

## Architect Tasks Completed

- [x] Task 1 — Confirmed the working branch is `bug/deploy-script-blocked-by-branch-protection` and the repo already has a local version-bump commit ahead of `origin/main`.
- [x] Task 2 — Added a minimal shared helper to create a short-lived version-bump branch, open a PR, and require auto-merge.
- [x] Task 3 — Updated `tools/deploy_web.sh` to replace the forbidden direct push path with the helper flow.
- [x] Task 4 — Updated `tools/build_web.sh` in the same way.
- [x] Task 5 — Preserved the local version-bump commit instead of resetting it or creating a duplicate.
- [x] Task 6 — Added preflight checks for `gh`, authentication, repository reachability, and repo auto-merge requirements.
- [x] Task 7 — Prepared the final verification notes for QA and Tony.

## Files Created

- `tools/git_version_pr.sh`

## Files Modified

- `tools/deploy_web.sh`
- `tools/build_web.sh`

## Analyzer Results

Command: `bash -n tools/git_version_pr.sh && bash -n tools/deploy_web.sh && bash -n tools/build_web.sh`
Result: pass (all three shell scripts parsed successfully).

`flutter analyze` was not run because this change is limited to shell tooling and the plan explicitly states it is not relevant for this bug.

## Test Results

Passed — shell validation succeeded and the forbidden `git push origin main` pattern was removed from both scripts.

## Code Efficiency / Bloat Check

Confirmed no dead code, unused imports/variables/parameters, redundant restating comments, single-use wrapper abstractions, or unnecessary defensive checks in the diff. The new helper is intentionally minimal and directly implements the required PR + auto-merge flow without extra speculative logic.

## Verification

Manual steps performed:

- Verified the branch is `bug/deploy-script-blocked-by-branch-protection`.
- Verified there is 1 local commit ahead of `origin/main` and preserved it.
- Ran `bash -n` on all changed script files.
- Ran `grep -n "git push origin main" tools/deploy_web.sh tools/build_web.sh` and confirmed there were no matches.
- Confirmed the environment used for this fix does not expose a working GitHub CLI: `gh` is not available here, so the live GitHub auth, PR merge, and repo auto-merge verification could not be observed in this execution context.
- Corrected the final local sync logic by code review of Git squash-merge mechanics: a squash merge creates a new commit on `origin/main` with a different parent/ancestor relationship, so `git pull --ff-only` is incompatible here and `git reset --hard origin/main` is the correct local sync after the PR has actually reached `MERGED` state.

Tier 2 live PR/merge verification remains a manual step for Tony on his machine because it requires a GitHub CLI installation, authenticated GitHub access, and repo settings that cannot be verified from this environment.

## Deviations From Architect Plan

None. The shared helper approach is the minimal implementation described in the plan and was used instead of duplicating the same logic in both scripts.

## Blockers Encountered

None in local validation. The only remaining live verification is the repo-side auto-merge/PR merge behavior, which must be confirmed manually by Tony on a machine with access to the protected repository settings.

## Ready For QA

Yes — the script logic and direct-push removal are in place, and the repo-protection fix is implemented in the deployment tooling. Final end-to-end PR/merge validation still needs Tony to run the script in the real GitHub environment with auto-merge enabled.
