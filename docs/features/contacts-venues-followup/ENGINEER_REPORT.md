# Engineer Report

## Feature Slug

contacts-venues-followup

## Feature Title

Contacts / Venues follow-up fixes and internationalization updates

## Goal

Fix the double-plus-sign button bug in empty states, add timezone-aware phone formatting for US bands, adapt venue address labels by region (US/Canada/UK), extract member invitations into a standalone screen, and expand the timezone picker with grouped Canadian/US/UK entries.

## Architect Tasks Completed

- [x] Task 0 — Fix double plus sign in VenuesEmptyState and ContactsEmptyState
- [x] Task 1 — Create USPhoneInputFormatter utility in lib/shared/utils/
- [x] Task 2 — Apply phone formatter to VenueFormScreen
- [x] Task 3 — Adapt VenueFormScreen address labels for timezone (State/Province/County)
- [x] Task 4 — Update VenueContactBlock to accept timezone parameter for phone formatting
- [x] Task 5 — Apply phone formatter to ContactFormScreen
- [x] Task 6 — Document ContactFormScreen address field design decision (comment only)
- [x] Task 7 — Create InviteMembersScreen (standalone invite screen)
- [x] Task 8 — Remove invite logic from BandFormScreen (edit mode only)
- [x] Task 9 — Update timezone picker list and label (grouped, expanded)
- [x] Task 10 — Update ContactsTabContent.\_openInviteScreen() to navigate to InviteMembersScreen

## Files Created

- `lib/shared/utils/phone_input_formatter.dart`
- `lib/features/contacts/widgets/invite_members_screen.dart`

## Files Modified

- `lib/features/contacts/widgets/venues_empty_state.dart` — Removed leading '+' from button label
- `lib/features/contacts/widgets/contacts_empty_state.dart` — Removed leading '+' from button label
- `lib/features/contacts/widgets/venue_form_screen.dart` — Added phone formatter, timezone-conditional State/Province/County label, timezone pass-through to VenueContactBlock
- `lib/features/contacts/widgets/venue_contact_block.dart` — Added timezone constructor parameter, phone input formatter
- `lib/features/contacts/widgets/contact_form_screen.dart` — Added phone formatter, address decision comment
- `lib/features/contacts/contacts_tab_content.dart` — Replaced BandFormScreen navigation with InviteMembersScreen, removed unused BandFormScreen import
- `lib/features/bands/band_form_screen.dart` — Removed edit-mode invite section (UI, state vars, methods, \_InvitePill widget), expanded timezone picker with grouped entries, updated label and helper text

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors / 0 warnings / 0 issues

## Test Results

Not run — no tests added per Architect plan scope

## Verification

- `flutter analyze` returns zero issues
- `dart format` applied to all new/modified Dart files (3 files reformatted)
- Confirmed both new files created at correct paths
- Confirmed 7 existing files modified as specified
- Verified import chains resolve correctly (no circular dependencies)
- Verified BandFormScreen create-mode invite section is completely untouched
- Verified onChanged null guard remains present in timezone dropdown
- Verified \_showErrorSnackBar still exists in BandFormScreen (used by non-invite code paths)

## Deviations From Architect Plan

None

## Blockers Encountered

None

## Ready For QA

Yes
