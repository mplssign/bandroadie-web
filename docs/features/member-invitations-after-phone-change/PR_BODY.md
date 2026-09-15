## Summary

The Members tab sent users to Edit Band when they tried to invite someone, but Edit Band intentionally has no invitation controls. Existing bands also had no invite action once they contained members. This left both existing and newly created bands unable to add people from the natural Members workflow.

## Changes

- Route the Members empty-state invite action to the existing Invite Members screen.
- Add an "Add" action to the Members header when a band already has members.
- Add widget coverage for both entry points and guard against routing back to Edit Band.

Group chat is explicitly out of scope and was not added. There are no database, RLS, RPC, auth, dependency, or platform-specific changes.

## Verification

- `flutter analyze lib/features/members/members_tab_content.dart test/features/members/members_tab_content_test.dart` - no issues.
- `flutter test test/features/members/members_tab_content_test.dart` - 2 tests passed.
- `flutter test` - 312 tests passed.
- Independent QA reviewed the implementation and reran all checks with an `APPROVED` verdict.

## Manual Verification Punch List

1. Open BandRoadie; select a band with 2+ active members; open the Members tab. **Expected:** an "Add" button is visible in the Members header; tapping it opens the Invite Members screen (email field + role selector) - **not** the Edit Band screen.
2. From that Invite Members screen, invite a test email you control. **Expected:** success snackbar "Invite sent to `<email>`"; no "Only band admins can invite members" error.
3. Create a brand-new band (no members yet); open its Members tab. **Expected:** the empty-state CTA also opens the Invite Members screen (not Edit Band).
4. Send a test invite from the new band. **Expected:** the invited email receives the invite, and the pending invite appears in the Contacts tab's Band Members section.
5. Regression: open Edit Band (tap band name/avatar) for an existing band. **Expected:** rename/avatar/timezone still work, and no invite section appears there (unchanged, intentional).