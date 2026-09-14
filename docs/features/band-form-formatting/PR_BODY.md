## Summary

Normalizes two formatter-selected line wraps in the shared band form screen.

## Changes

- Wrap the existing `StorageException` constructor argument.
- Collapse the existing `BorderSide` expression onto one line.
- Preserve the exact Dart token stream and runtime behavior.

## Verification

- Patch matches preserved rescue reference `a8e064a` exactly.
- `dart format --set-exit-if-changed`: passed with 0 changes.
- Focused and full `flutter analyze`: passed with no issues.
- Full `flutter test`: 322 passed, 0 failed.
- Independent QA approved the exact `+3/-3` formatting-only diff.

## Scope

- No runtime or user-visible behavior changes.
- No dependency, platform, database, RLS, RPC, or Edge Function changes.
- No database migration or app build is included.
