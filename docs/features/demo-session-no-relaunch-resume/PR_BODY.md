## Summary

- Purge a restored anonymous demo session during cold start, before auth routing reads it.
- Preserve cached sessions for normal, non-anonymous users.
- Keep fresh demo entry during the current app run unchanged.
- Leave the existing demo capacity, TTL, cleanup, and database behavior untouched.

## Verification

- `flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart test/features/auth/demo_lifecycle_predicate_test.dart`
- Focused lifecycle and anonymous-recovery tests: 12/12 passing.
- Full Flutter test suite: 292/292 passing.
- Independent QA verdict: APPROVED.
- Source review confirmed gotrue 2.27.2 clears the in-memory session before network work and defaults `signOut()` to local scope.

## Manual Verification

1. On macOS, enter the demo from login. Expected: the Demo Band loads normally.
2. Quit with `Cmd-Q` within eight minutes and reopen. Expected: the login screen appears instead of the Demo Band.
3. Repeat the quit/reopen test without network connectivity. Expected: the login screen still appears.
4. Sign in as a normal user, quit, and reopen. Expected: the account resumes without requiring login.
5. Repeat steps 1–4 on at least one of iOS or Android, using swipe-kill for the demo relaunch test. Then smoke-test Web: no demo button, and normal-user page-reload persistence remains unchanged.

## Release State

- No database migration is included or was applied by this pipeline.
- No application build was produced or shipped by this pipeline.
