## Change

The Add/Edit Event drawer groups its form into named section cards. Two titles were sentence case; they now use Title Case to match the rest:

- `The gig` → `The Gig`
- `Show prep` → `Show Prep`

The other section titles (`Schedule`, `Location`, `Money`, `Notes`) were already Title Case and are unchanged. Home-screen section headers were already Title Case — no changes there.

## Scope

Text-only. Two string literals in `lib/features/events/widgets/event_editor_drawer.dart`. No logic, layout, state, database, or RPC impact.

## Testing

- `flutter analyze --no-pub` → 0 errors.
- No database migrations. No app build shipped by this PR.
