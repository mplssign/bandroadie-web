#!/usr/bin/env bash
#
# git_version_pr.sh — Create a short-lived PR for version-bump commits
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PR_TITLE="${PR_TITLE:-chore: bump build version}"
PR_BODY="${PR_BODY:-Automated version bump}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  fail "GitHub CLI (gh) is required for the version-bump PR flow. Install gh and retry."
fi

gh --version >/dev/null 2>&1 || fail "gh CLI is installed but failed to execute."
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated for this repository. Run 'gh auth login' and retry."
gh repo view --json nameWithOwner >/dev/null 2>&1 || fail "GitHub repo is not reachable from this machine. Check the remote and gh authentication."

CURRENT_BRANCH="$(git branch --show-current)"
[[ "$CURRENT_BRANCH" == "main" ]] || fail "Version-bump PR flow must start from main."

git fetch origin >/dev/null 2>&1 || fail "Unable to fetch origin."

REPO_SLUG="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
AUTO_MERGE_ENABLED="$(gh api "repos/$REPO_SLUG" --jq '.allow_auto_merge' 2>/dev/null || echo "false")"
if [[ "$AUTO_MERGE_ENABLED" != "true" ]]; then
  fail "Repository auto-merge is disabled. Enable 'Allow auto-merge' in GitHub and retry."
fi

AHEAD_COUNT="$(git rev-list --count origin/main..main || echo 0)"
if [[ "$AHEAD_COUNT" -gt 0 ]]; then
  echo "Preserving $AHEAD_COUNT local commit(s) already ahead of origin/main."
fi

BRANCH_NAME="chore/version-bump-$(date +%Y%m%d-%H%M%S)"

git checkout -b "$BRANCH_NAME" >/dev/null 2>&1 || fail "Unable to create version-bump branch '$BRANCH_NAME'."
git push -u origin "$BRANCH_NAME" >/dev/null 2>&1 || fail "Unable to push version-bump branch '$BRANCH_NAME' to origin."

PR_NUMBER=$(gh pr create \
  --base main \
  --head "$BRANCH_NAME" \
  --title "$PR_TITLE" \
  --body "$PR_BODY" \
  --json number \
  --jq '.number' 2>/dev/null) || fail "Unable to create a pull request for the version bump. Check repo permissions and GitHub PR settings."

gh pr merge --auto --squash --delete-branch "$PR_NUMBER" >/dev/null 2>&1 || fail "Unable to enable PR auto-merge. Check repository settings and PR permissions."

STATE="OPEN"
for _ in $(seq 1 40); do
  STATE="$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "OPEN")"
  if [[ "$STATE" == "MERGED" ]]; then
    break
  fi
  sleep 5
done

if [[ "$STATE" != "MERGED" ]]; then
  fail "Version-bump PR did not merge automatically within the timeout. Check required status checks or repo auto-merge settings."
fi

git checkout main >/dev/null 2>&1

git fetch origin >/dev/null 2>&1 || fail "Unable to fetch origin after merge."
git reset --hard origin/main >/dev/null 2>&1 || fail "Unable to reset local main to the merged upstream version-bump commit."

echo "Version bump PR merged and local main updated."
