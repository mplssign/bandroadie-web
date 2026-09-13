## Change

Potential Gig and Potential Rehearsal cards now use a brighter orange background tint. Confirmed Gig and Confirmed Rehearsal cards use slightly more opaque green and sky-blue background tints.

Borders, animation, layout, typography, and interactions are unchanged.

## Scope

Four color-literal updates across the three Home dashboard event-card widgets. No state, navigation, database, RLS, RPC, or dependency changes.

## Testing

- Focused `flutter analyze` passed with no issues.
- Full `flutter test` passed: 322 tests, 0 failures.
- Independent QA approved the exact four-line application change.
- No database migrations. No app build shipped by this PR.