## Problem

The version-bump helper requested auto-merge immediately after creating a pull
request. GitHub can still report a new pull request as unstable while computing
mergeability, causing the helper to abort and a rerun to create another version
bump.

## Change

- Wait briefly for mergeability to resolve before requesting auto-merge.
- Retry only GitHub's known transient merge-state failures, with a bounded
  backoff.
- Refuse to create another version-bump PR while one is already open.
- Preserve the created PR URL in every later failure message.
- Add an isolated shell harness that stubs `gh` and covers success, fatal error,
  and retry-exhaustion paths.

## Verification

- Both shell scripts pass `bash -n`.
- All three stubbed retry scenarios pass with the expected attempt counts.
- Tier 1 static checks pass.
- `flutter analyze` reports no issues.

No live pull request mutation, build, deployment, database change, or version
bump was performed while verifying this fix.