## Summary

- Purge a persisted anonymous demo session before Supabase initialization can restore it.
- Preserve cached sessions for normal, non-anonymous users.
- Keep fresh demo entry during the current app run unchanged.
- Leave the existing demo capacity, TTL, cleanup, and database behavior untouched.

## Verification

- `flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart test/features/auth/demo_lifecycle_predicate_test.dart`
- Focused lifecycle, storage-purge, and anonymous-recovery tests: 18/18 passing.
- Full Flutter test suite: 298/298 passing.
- Independent QA verdict: APPROVED.
- Source review confirmed Supabase Flutter 2.17.2 starts a non-awaited background session recovery after initialization. The repair removes only positively identified anonymous session data from the SDK's exact native storage key before initialization begins.

## Manual Verification

1. On macOS, enter the demo from login. Expected: the Demo Band loads normally.
2. Reproduce the previously failing path: while in Demo Band, quit with `Cmd-Q` within eight minutes, then run `./run.sh macos`. Expected: the login screen appears instead of the Demo Band.
3. Repeat the quit/reopen test without network connectivity. Expected: the login screen still appears because the purge is local.
4. Sign in as a normal user, quit, and reopen. Expected: the account resumes without requiring login.
5. Repeat steps 1–4 on at least one of iOS or Android, using swipe-kill for the demo relaunch test. Then smoke-test Web: no demo button, and normal-user page-reload persistence remains unchanged.

## Release State

- No database migration is included or was applied by this pipeline.
- No application build was produced or shipped by this pipeline.
