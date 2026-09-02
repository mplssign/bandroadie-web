#!/usr/bin/env bash
# Clears stale git lock files left behind by an interrupted git write
# (killed process, tool timeout, crashed session) before they block the
# next git command. This repo has hit this 12+ times historically —
# always self-inflicted by an automated agent's git write getting cut
# off mid-operation, never a genuine concurrent-editor conflict — so
# rather than relying on every agent's prompt to notice and reason about
# it correctly each time, this runs unconditionally as the first step of
# every agent's turn. It is a safe no-op when nothing is stale.
#
# Usage: bash scripts/clear_stale_git_lock.sh
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

STALE_AGE_SECONDS=30
LOCKS=(.git/index.lock .git/HEAD.lock .git/packed-refs.lock)
shopt -s nullglob 2>/dev/null || true
LOCKS+=(.git/refs/heads/*.lock .git/refs/remotes/*/*.lock)

file_mtime() {
  # GNU stat (-c) and BSD stat (-f) disagree on what "-f" even means, and
  # GNU's -f mode exits 0 while printing unrelated filesystem info instead
  # of failing — so validate the output is a plain integer rather than
  # trusting the exit code, and try GNU syntax first since that's this
  # environment; BSD syntax (macOS, where this actually runs in
  # production via Copilot) is the fallback.
  local out
  out=$(stat -c %Y "$1" 2>/dev/null) && [[ "$out" =~ ^[0-9]+$ ]] && { echo "$out"; return 0; }
  out=$(stat -f %m "$1" 2>/dev/null) && [[ "$out" =~ ^[0-9]+$ ]] && { echo "$out"; return 0; }
  return 1
}

found_any=false
for lock in "${LOCKS[@]}"; do
  [ -e "$lock" ] || continue
  found_any=true

  if pgrep -x git >/dev/null 2>&1; then
    echo "clear_stale_git_lock: a git process is currently running — leaving $lock alone" >&2
    continue
  fi

  now=$(date +%s)
  mtime=$(file_mtime "$lock")
  age=$(( now - mtime ))

  if [ "$age" -ge "$STALE_AGE_SECONDS" ]; then
    rm -f "$lock"
    echo "clear_stale_git_lock: removed stale $lock (age ${age}s, no live git process)"
  else
    echo "clear_stale_git_lock: $lock is only ${age}s old — leaving it in case a process is still finishing" >&2
  fi
done

if [ "$found_any" = false ]; then
  echo "clear_stale_git_lock: no lock files present, nothing to do"
fi
