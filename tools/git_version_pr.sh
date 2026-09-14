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

enable_auto_merge_with_retry() {
  local pr_number="$1"
  local pr_url="$2"
  local merge_state="UNKNOWN"
  local merge_output
  local attempt=1
  local backoff_seconds=3

  for _ in $(seq 1 6); do
    merge_state="$(gh pr view "$pr_number" --json mergeStateStatus --jq '.mergeStateStatus' 2>/dev/null || echo "UNKNOWN")"
    if [[ "$merge_state" != "UNKNOWN" ]]; then
      break
    fi
    sleep 5
  done

  while [[ "$attempt" -le 5 ]]; do
    if merge_output="$(gh pr merge --auto --squash --delete-branch "$pr_number" 2>&1)"; then
      return 0
    fi

    if ! grep -qE 'unstable status|pending state|Base branch was modified' <<<"$merge_output"; then
      fail "Unable to enable PR auto-merge (PR: $pr_url): $merge_output"
    fi

    if [[ "$attempt" -eq 5 ]]; then
      fail "PR auto-merge remained in transient/unstable state after 5 attempts. Complete the merge manually, then rerun deploy. PR: $pr_url"
    fi

    echo "Retrying auto-merge (attempt $((attempt + 1)) of 5)..."
    sleep "$backoff_seconds"
    backoff_seconds=$((backoff_seconds * 2))
    attempt=$((attempt + 1))
  done
}

main() {
  cd "$ROOT_DIR"

  if ! command -v gh >/dev/null 2>&1; then
    fail "GitHub CLI (gh) is required for the version-bump PR flow. Install gh and retry."
  fi

  GH_VERSION_OUTPUT="$(gh --version 2>&1)" || fail "gh CLI is installed but failed to execute: $GH_VERSION_OUTPUT"
  GH_AUTH_OUTPUT="$(gh auth status 2>&1)" || fail "gh is not authenticated for this repository. Run 'gh auth login' and retry: $GH_AUTH_OUTPUT"
  GH_REPO_VIEW_OUTPUT="$(gh repo view --json nameWithOwner 2>&1)" || fail "GitHub repo is not reachable from this machine. Check the remote and gh authentication: $GH_REPO_VIEW_OUTPUT"

  CURRENT_BRANCH="$(git branch --show-current)"
  [[ "$CURRENT_BRANCH" == "main" ]] || fail "Version-bump PR flow must start from main."

  FETCH_OUTPUT="$(git fetch origin 2>&1)" || fail "Unable to fetch origin: $FETCH_OUTPUT"

  REPO_SLUG="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
  AUTO_MERGE_ENABLED="$(gh api "repos/$REPO_SLUG" --jq '.allow_auto_merge' 2>&1)" || fail "Unable to check repository auto-merge setting: $AUTO_MERGE_ENABLED"
  if [[ "$AUTO_MERGE_ENABLED" != "true" ]]; then
    fail "Repository auto-merge is disabled. Enable 'Allow auto-merge' in GitHub and retry."
  fi

  AHEAD_COUNT="$(git rev-list --count origin/main..main || echo 0)"
  if [[ "$AHEAD_COUNT" -gt 0 ]]; then
    echo "Preserving $AHEAD_COUNT local commit(s) already ahead of origin/main."
  fi

  OPEN_VERSION_PR_URL="$(gh pr list --state open --base main --json number,url,headRefName --jq '.[] | select(.headRefName | startswith("chore/version-bump-")) | .url' 2>&1)" || fail "Unable to check for an open version-bump PR: $OPEN_VERSION_PR_URL"
  OPEN_VERSION_PR_URL="${OPEN_VERSION_PR_URL%%$'\n'*}"
  if [[ -n "$OPEN_VERSION_PR_URL" ]]; then
    fail "An open version-bump PR already exists. Resolve or close it before rerunning. PR: $OPEN_VERSION_PR_URL"
  fi

  BRANCH_NAME="chore/version-bump-$(date +%Y%m%d-%H%M%S)"

  CHECKOUT_OUTPUT="$(git checkout -b "$BRANCH_NAME" 2>&1)" || fail "Unable to create version-bump branch '$BRANCH_NAME': $CHECKOUT_OUTPUT"
  PUSH_OUTPUT="$(git push -u origin "$BRANCH_NAME" 2>&1)" || fail "Unable to push version-bump branch '$BRANCH_NAME' to origin: $PUSH_OUTPUT"

  PR_URL=$(gh pr create \
    --base main \
    --head "$BRANCH_NAME" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    2>&1) || fail "Unable to create a pull request for the version bump: $PR_URL"
  PR_NUMBER="${PR_URL##*/}"

  enable_auto_merge_with_retry "$PR_NUMBER" "$PR_URL"

  STATE="OPEN"
  for _ in $(seq 1 40); do
    STATE="$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null || echo "OPEN")"
    if [[ "$STATE" == "MERGED" ]]; then
      break
    fi
    sleep 5
  done

  if [[ "$STATE" != "MERGED" ]]; then
    fail "Version-bump PR did not merge automatically within the timeout. Check required status checks or repo auto-merge settings. PR: $PR_URL"
  fi

  CHECKOUT_MAIN_OUTPUT="$(git checkout main 2>&1)" || fail "Unable to switch back to main after merge (PR: $PR_URL): $CHECKOUT_MAIN_OUTPUT"

  FETCH_AFTER_MERGE_OUTPUT="$(git fetch origin 2>&1)" || fail "Unable to fetch origin after merge (PR: $PR_URL): $FETCH_AFTER_MERGE_OUTPUT"
  RESET_OUTPUT="$(git reset --hard origin/main 2>&1)" || fail "Unable to reset local main to the merged upstream version-bump commit (PR: $PR_URL): $RESET_OUTPUT"

  echo "Version bump PR merged and local main updated."
}

if [[ "${VERSION_PR_SOURCE_ONLY:-0}" != "1" ]]; then
  main
fi
