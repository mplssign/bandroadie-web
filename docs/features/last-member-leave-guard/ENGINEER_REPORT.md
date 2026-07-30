# Engineer Report

## Feature Slug
feature/last-member-leave-guard

## Feature Title
Last-member-leave guard (re-diagnosis / corrected implementation)

## Goal
Show a fixed explanatory message in place of the "Remove from band" action when the viewer is the sole active member of their own band, in the live editor screen (`BandMemberEditDrawer`) rather than the previously-targeted dead-code screen (`RoleManagementSheet`).

## Architect Tasks Completed
- [x] Task 1 — Revert `lib/features/members/members_tab_content.dart` to `origin/main` state
- [x] Task 2 — Revert `lib/features/members/widgets/role_management_sheet.dart` to `origin/main` state
- [x] Task 3 — Compute `activeMemberCount` in `ContactsTabContent._openRoleManagement`
- [x] Task 4 — Pass `activeMemberCount` into `BandMemberEditDrawer.show(...)`
- [x] Task 5 — Add `activeMemberCount` field to `BandMemberEditDrawer` constructor and `show(...)` factory
- [x] Task 6 — Add `_isSoleActiveMember` getter to `_BandMemberEditDrawerState`
- [x] Task 7 — Replace `if (!_isLastAdmin)` block with `if (_isSoleActiveMember) [...] else if (!_isLastAdmin) [...]`
- [x] Task 8 — Confirmed `_removeMember()`, `_saveRole()`, `_isLastAdmin`, `_isSelfAndLastAdmin`, `BandMemberDetailDrawer`, `BandMemberCard`, and all RPC calls left unmodified

## Files Created
none

## Files Modified
- `lib/features/members/members_tab_content.dart` — reverted to `origin/main` (zero diff confirmed)
- `lib/features/members/widgets/role_management_sheet.dart` — reverted to `origin/main` (zero diff confirmed)
- `lib/features/contacts/contacts_tab_content.dart` — `_openRoleManagement` now computes `activeMemberCount` and passes it to `BandMemberEditDrawer.show(...)`
- `lib/features/contacts/widgets/band_member_edit_drawer.dart` — added `activeMemberCount` param (constructor + `show` factory), added `_isSoleActiveMember` getter, replaced the "Remove from band" block with the `if (_isSoleActiveMember) [...] else if (!_isLastAdmin) [...]` branch

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results
Not run — no test files reference `role_management_sheet`, `members_tab_content`, or `band_member_edit_drawer` (per Architect Plan §5), and the Architect plan does not require tests for this change.

## Verification
Manual steps performed:
- Confirmed pre-flight `git status` matched the plan's expected dirty-tree state before starting.
- After revert: `git diff origin/main -- lib/features/members/members_tab_content.dart lib/features/members/widgets/role_management_sheet.dart` produced zero output (Architect Plan §16 verification step 7, dead-code confirmation).
- `flutter analyze` run twice (after implementation, and again after formatting) — 0 errors, 0 warnings both times.
- `dart format` run on the two changed live files — 0 files changed (already correctly formatted).
- Confirmed via `git status --short` that only the two live files are modified beyond the two pre-existing, out-of-scope dirty entries (`docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`, `docs/features/gig-sheet-full-address/`), which were left untouched.
- Confirmed the new `_isSoleActiveMember` getter mirrors the existing `_isLastAdmin`/`_isSelfAndLastAdmin` pattern (same `supabase.auth.currentUser?.id` comparison style).
- Confirmed the new conditional branch is scoped by `widget.member.userId == currentUserId` combined with `widget.activeMemberCount <= 1`, so it cannot fire for any card other than the viewer's own.
- Confirmed the `else if (!_isLastAdmin)` branch preserves the original button code byte-for-byte (icon, label, styling, `onPressed: _isRemoving ? null : _removeMember`).
- Confirmed the implicit else (sole admin of a multi-member band) renders nothing, unchanged from prior behavior.
- Confirmed the rendered text matches the required copy verbatim, including the "→" arrow characters.
- Confirmed no new color constants were introduced — reused `context.colors.warning` and `AppIcons.warning`, consistent with the existing `_isSelfAndLastAdmin` warning container.
- Did not perform device/simulator testing — no device/simulator was available in this session. Per Architect Plan §16, the mandatory device re-test of the exact repro steps (tap own card → info drawer → Edit → confirm exact text renders) remains outstanding and must be performed by Tony (or QA with device access) before this bug is considered resolved. QA must not mark this APPROVED on code-path analysis alone.

## Deviations From Architect Plan
None.

## Blockers Encountered
None. Device/simulator testing was not available in this session — flagged above and in the Architect Plan §16 as a mandatory gate prior to sign-off, not treated as a blocker to implementation completion.

## Corrective Notes (this session)

1. **Revert of the wrong-file diff:** The working tree at session start contained the prior Engineer's uncommitted diff in `lib/features/members/members_tab_content.dart` and `lib/features/members/widgets/role_management_sheet.dart`. Both files were reverted with `git checkout origin/main -- <file>`, and `git diff origin/main -- <file> <file>` was confirmed to produce zero output for both — the revert is complete and clean, not partial.
2. **New implementation location:** The guard is now implemented on the live navigation path: `AppShell` → `ContactsTabContent` → `BandMembersView` → `BandMemberCard` → `BandMemberDetailDrawer` (Edit button) → `BandMemberEditDrawer`. Specifically, `ContactsTabContent._openRoleManagement` (`contacts_tab_content.dart`) and `BandMemberEditDrawer` (`band_member_edit_drawer.dart`) — not `MembersTabContent` / `RoleManagementSheet`, which are unreachable dead code (Architect Plan §3).
3. **This is a correction of a prior wrong-screen defect:** The original implementation was functionally correct and analyzer-clean but was wired into `RoleManagementSheet`/`MembersTabContent`, files that are never mounted by the running app (confirmed by repo-wide grep in the Architect Plan §3 — the only other reference to `MembersTabContent` sits inside a commented-out documentation block). That defect is why the guard did not appear on a real device despite passing prior code-path-only QA. This session reverted that dead-code diff and re-implemented the identical guard logic (same predicate semantics, same exact required text) in the actual live screen, `BandMemberEditDrawer`.

## Ready For QA
Yes — with the caveat above: QA must have (or obtain) device/simulator access to perform the mandatory repro re-test per Architect Plan §16, and must not approve on code-path analysis alone given this exact "code-path-correct, screen-wrong" failure class already passed QA once before.

## Follow-Up: Text Correction (this session)

Tony flagged that the rendered guard text in `lib/features/contacts/widgets/band_member_edit_drawer.dart` (line ~486) contained the literal parenthetical words "(arrow right icon)" twice — these were only ever meant as an authoring note describing the UI affordance, not text intended for display to users.

**Change made:** the string literal was corrected from:
> "Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right (arrow right icon) → Edit band (arrow right icon) → Delete)"

to:
> "Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right → Edit band → Delete)"

This is a copy-only fix — no logic, styling, predicate, or other line in the file was touched. `flutter analyze` re-run after this change: 0 errors, 0 warnings. `dart format` re-run on the file: 0 changes (already correctly formatted).
