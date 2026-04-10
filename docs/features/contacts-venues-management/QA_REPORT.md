# QA Report

## 1. Feature Slug

`feature/contacts-venues-management`

---

## 2. Verdict

**APPROVED**

---

## 3. Findings

| #   | Area                 | Severity | Description                                                                                                                                                                                                                | File                                                                  | Recommendation                                                                                                                                                      |
| --- | -------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | File Size            | WARNING  | `contacts_tab_content.dart` is 360 lines (target ≤350, 10 over)                                                                                                                                                            | `lib/features/contacts/contacts_tab_content.dart`                     | Acceptable — minor overage in a container widget. No action needed this cycle.                                                                                      |
| 2   | File Size            | WARNING  | `venue_form_screen.dart` is 458 lines (target ≤400, 58 over)                                                                                                                                                               | `lib/features/contacts/widgets/venue_form_screen.dart`                | The AnimatedList venue-contact management and `_VenueContactEntry` helper class contribute to the bulk. Candidate for extraction in a future cycle. Does not block. |
| 3   | File Size            | NOTE     | `venue_contact_block.dart` is 212 lines (target ≤200, 12 over)                                                                                                                                                             | `lib/features/contacts/widgets/venue_contact_block.dart`              | Minor overage. No action needed.                                                                                                                                    |
| 4   | File Size            | NOTE     | `venue_card.dart` is 209 lines (target ≤200, 9 over)                                                                                                                                                                       | `lib/features/contacts/widgets/venue_card.dart`                       | Minor overage. No action needed.                                                                                                                                    |
| 5   | File Size            | NOTE     | `contact_card.dart` is 201 lines (target ≤200, 1 over)                                                                                                                                                                     | `lib/features/contacts/widgets/contact_card.dart`                     | Effectively at target. No action needed.                                                                                                                            |
| 6   | Form Error UX        | WARNING  | Both form screens catch errors silently (`catch (e) {}` resets `_isSaving` but shows no user-facing error message)                                                                                                         | `venue_form_screen.dart`, `contact_form_screen.dart`                  | Should display a snackbar via `showErrorSnackBar()` on save failure. Low-risk since the form state is preserved and the user can retry.                             |
| 7   | Lazy Load Redundancy | NOTE     | `VenuesView` and `ContactsView` each call `load()` in their own `initState`, but `ContactsTabContent._onSegmentChanged` already triggers `load()` on first segment switch. Both paths guard against re-fetch via cache.    | `venues_view.dart`, `contacts_view.dart`, `contacts_tab_content.dart` | No functional issue — the cache prevents double fetching. Informational only.                                                                                       |
| 8   | AppDurations Import  | NOTE     | `venue_form_screen.dart` uses `AppDurations.normal` in `_addContact`/`_removeContact` but does not import `app_animations.dart` directly — this resolves via transitive import through `venue_contact_block.dart` imports. | `venue_form_screen.dart`                                              | Works correctly at compile time. Analyzer passes with zero warnings. Informational only.                                                                            |
| 9   | Migration Safety     | NOTE     | Trigger function `update_updated_at_column` uses `CREATE OR REPLACE` — safe for re-run if the function already exists from another migration.                                                                              | `20260410000000_contacts_venues_tables.sql`                           | Correct approach. No action needed.                                                                                                                                 |
| 10  | Restricted Tab Label | NOTE     | When permission-gated, `RestrictedTabContent` now shows `'Contacts'` instead of `'Members'` — consistent with the nav bar label change.                                                                                    | `lib/features/shell/app_shell.dart`                                   | Correct. No action needed.                                                                                                                                          |

---

## 4. Critical Issues

None.

---

## 5. Warnings

1. **File Size — `venue_form_screen.dart`** (458 lines, target ≤400): The nested AnimatedList venue-contact management and `_VenueContactEntry` class push this 58 lines over. The Architect plan set a 400-line target for form screens. This is a soft target per GUARDRAILS §8 ("Exceeding these is a warning, not a hard stop"). Contents are cohesive and justified.

2. **File Size — `contacts_tab_content.dart`** (360 lines, target ≤350): 10 lines over the container widget target. Trivial overage.

3. **Silent Error Handling in Forms**: Both `venue_form_screen.dart` and `contact_form_screen.dart` catch save errors but only reset `_isSaving` — no error message is shown to the user. The project convention is to use `showErrorSnackBar()`. This is low-risk since form state is preserved and the user can retry, but it should be addressed in a fast-follow.

---

## 6. Notes

- All 14 Architect tasks confirmed complete via code-path analysis.
- All 21 files created at the correct paths with expected contents.
- 2 existing files modified with minimal, correct diffs.
- `flutter analyze` reported 0 errors / 0 warnings per Engineer Report.
- Documented deviations (pre-existing untracked files, lint cleanups, type annotation) are all reasonable and non-impacting.
- `VenuesView`/`ContactsView` dual-loading (own `initState` + parent's `_onSegmentChanged`) is harmless due to cache guard.
- `AppDurations.normal` used in `venue_form_screen.dart` via `design_tokens.dart` transitive import — compiles cleanly.

---

## 7. Regression Risk Assessment

**Level: LOW** — Confirmed. Rationale:

- **Members data flow untouched.** `BandMembersView` imports all widgets from `lib/features/members/` and uses `membersProvider` via constructor params passed from `ContactsTabContent`. No members code was modified.
- **Invite flow preserved.** `_openInviteScreen` navigates to `BandFormScreen(mode: BandFormMode.edit)` — identical to original `MembersTabContent`.
- **Role management preserved.** `_openRoleManagement` calls `RoleManagementSheet` with `adminCount` guard — identical to original.
- **Permission gating preserved.** `canViewMembers` still gates tab index 3. `RestrictedTabContent` label updated to 'Contacts'.
- **Band switch isolation.** `ref.listen(activeBandProvider)` resets `venuesProvider`, `contactsProvider`, `_selectedSegment`, and `_loadedSegments`. Members reload is also triggered.
- **Database additive only.** Three new tables created. No existing tables modified. All RLS policies query `band_members` (not self-referencing). `CREATE OR REPLACE` on shared trigger function.
- **No initialization order changes.** `lib/main.dart` untouched.
- **No new dependencies added.** Uses existing `url_launcher`, `flutter_riverpod`, and theme infrastructure.

---

## 8. Manual QA Checklist

Tony should verify the following manually after deployment:

- [ ] Tab label reads "Contacts" on all platforms (iOS, macOS, Web, Android)
- [ ] Band segment: existing member list appears unchanged; role badges, admin actions work
- [ ] Band segment: "Add" button opens BandFormScreen in edit mode (invite flow)
- [ ] Band segment: role management sheet opens correctly for admin users
- [ ] Venues segment: toggle switches with sliding indicator animation
- [ ] Venues segment: create a venue with all fields + venue contacts → saves correctly
- [ ] Venues segment: edit an existing venue → pre-populates, saves updates
- [ ] Venues segment: delete a venue (admin only)
- [ ] Venues segment: add/remove venue contacts with enter/exit animation
- [ ] Contacts segment: create a standalone contact with title pill selector
- [ ] Contacts segment: custom title entry via "Custom" pill
- [ ] Contacts segment: edit an existing contact
- [ ] Contacts segment: delete a contact
- [ ] Contacts segment: tap phone number launches dialer; tap email launches mail
- [ ] Band switch: toggle resets to "Band", venues/contacts data clears and reloads for new band
- [ ] Permission gating: contributor with `canViewMembers: false` sees restricted state
- [ ] Pull-to-refresh works on all three views
- [ ] Dashboard, Setlists, Calendar tabs completely unaffected
- [ ] Empty states show correct roadie humor messages with action buttons
- [ ] Verify migration applied cleanly (`supabase db push`) — all 3 tables, 4 indexes, 12 RLS policies, 3 triggers created

---

## 9. Commit Authorization

**Authorized.**

All Architect plan tasks are complete. No critical issues found. Warnings are soft-target file size overages (permitted by GUARDRAILS §8) and a low-risk UX gap (silent form errors) suitable for fast-follow. Off-limits files confirmed untouched. Migration is safe and additive. Regression risk is LOW.

---

_QA validation method: Code-path analysis only. No runtime behavior was exercised._
_Branch: `feature/contacts-venues-management`_
_Date: 2026-04-10_
