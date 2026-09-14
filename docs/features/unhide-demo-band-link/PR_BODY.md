## Change

The existing "Check out the demo band" link is now visible on the login screen
on every Flutter platform, including web. Its interaction, placement, session
lifecycle, and backend behavior are unchanged.

The focused widget test wording and decision log now reflect the all-platform
visibility contract.

## Scope

One visibility constant, its existing test description, and supporting
documentation. No database, RPC, dependency, routing, or platform-runner changes.

## Testing

- `flutter analyze` passed with no issues.
- Focused login-screen tests passed: 5/5.
- Full Flutter test suite passed: 322/322.
- `git diff --check` passed.

## Known Behavior

Refreshing the web app during an active demo resumes that anonymous session while
its TTL remains valid. This matches the existing web session behavior and is not
changed by this visibility-only update.