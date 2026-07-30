# QA Report

## Feature Slug
feature/last-member-leave-guard

## Feature Title
Last-member-leave guard (re-diagnosis / corrected implementation)

## Final Verdict
**APPROVED**

## Validation Summary
This is a re-diagnosis QA pass following a prior session where a code-path-correct guard was wired into dead code (`RoleManagementSheet`/`MembersTabContent`) and never appeared on a real device — that prior pass had been marked APPROVED on code-path analysis alone. This session independently re-derived the reachability claims from scratch rather than trusting the Architect plan's text: re-ran the repo-wide grep for `MembersTabContent`/`RoleManagementSheet`/`ContactsTabContent`/`BandMemberEditDrawer`, read `app_shell.dart` directly to confirm it mounts `ContactsTabContent` (not `MembersTabContent`), and read the full `native_app_banner_integration.dart` file to confirm the one other `MembersTabContent` reference sits inside a `/* ... */` block comment in a non-compiled example file. Also validated via `git diff` (every hunk read in full across both changed files), `flutter analyze`, and confirmed zero-diff on both the reverted dead-code files and every off-limits file against `origin/main`. **Runtime/device behavior was not exercised this session** — see Behavior Verification below.

## Architect Scope Review
- Scope adherence: compliant
- Files modified: as expected — `lib/features/contacts/contacts_tab_content.dart`, `lib/features/contacts/widgets/band_member_edit_drawer.dart` (both Architect-approved live files). `lib/features/members/members_tab_content.dart` and `lib/features/members/widgets/role_management_sheet.dart` were reverted to `origin/main`, confirmed by `git diff origin/main -- <both files>` producing zero output.
- Files off-limits: not touched — verified via `git diff origin/main -- <path>` producing zero output for each of: `band_member_card.dart`, `band_member_detail_drawer.dart`, `members/widgets/member_card.dart`, `members_repository.dart`, `members_controller.dart`, `main.dart`, `band_form_screen.dart`, `edit_band_screen.dart`, `supabase/migrations/*`.

## Reachability Verification (re-diagnosis-specific)
Independently re-confirmed, not taken on the Architect plan's word:
- `grep -rn "BandMemberEditDrawer\|ContactsTabContent" lib/ --include="*.dart"` — every result resolves inside `lib/features/contacts/` (the live tree); no dead-code cross-references found.
- `grep -n "MembersTabContent\|ContactsTabContent" lib/features/shell/app_shell.dart` — only `ContactsTabContent()` (line 166) is instantiated; `MembersTabContent` does not appear in `app_shell.dart` at all.
- Read `lib/shared/widgets/native_app_banner_integration.dart` in full — confirmed the single other `MembersTabContent` reference (line 45) sits inside a `/* ... */`-fenced "INTEGRATION EXAMPLE 1" documentation block (opens at line 20), not live/compiled code.
- Conclusion: `BandMemberEditDrawer` (edited this session) is reachable from `AppShell`; `RoleManagementSheet`/`MembersTabContent` (reverted this session) are not reachable from any mounted screen. The fix is wired into the correct, live widget tree — this is the specific failure mode the re-diagnosis exists to catch, and it does not recur here.

## Completeness Check
- All Architect tasks implemented: yes — all 8 tasks from Architect Plan §15 confirmed directly against the diff:
  1. `members_tab_content.dart` reverted — zero diff vs. `origin/main`, confirmed independently.
  2. `role_management_sheet.dart` reverted — zero diff vs. `origin/main`, confirmed independently.
  3. `activeMemberCount` computed in `_openRoleManagement` (`contacts_tab_content.dart:114-115`) via `membersState.members.where((m) => m.isActive).length`.
  4. Passed into `BandMemberEditDrawer.show(...)` (`contacts_tab_content.dart:121`).
  5. `activeMemberCount` added to the constructor (required param) and the `show(...)` factory, threaded through — `band_member_edit_drawer.dart:28-52`.
  6. `_isSoleActiveMember` getter added (`band_member_edit_drawer.dart:119-123`), matching the existing `_isLastAdmin`/`_isSelfAndLastAdmin` style.
  7. `if (!_isLastAdmin)` block replaced with `if (_isSoleActiveMember) [...] else if (!_isLastAdmin) [...]` at the exact target location (former lines 456-483, now 467-522 post-insertion).
  8. `_removeMember()`, `_saveRole()`, `_isLastAdmin`, `_isSelfAndLastAdmin`, `BandMemberDetailDrawer`, `BandMemberCard`, and all RPC calls confirmed unmodified via the off-limits diff check above.
- Missing tasks: none

## Behavior Verification
- Validation method: **code-path analysis only.** No device or simulator interaction was performed this session.
- `flutter devices` shows three connected targets this session (a physical iPhone, macOS desktop, Chrome web) — hardware/runtime targets are technically present. However, this QA session has no visual/interactive UI-driving tool available (no screenshot capture, no UI automation/tap-simulation tool) to launch the app, tap through the five repro steps, and visually confirm the rendered text. Claiming visual confirmation without such a tool would be fabricated, so per QA.md's validation standard ("confirmed in code" ≠ "confirmed at runtime"), this is disclosed plainly rather than glossed over.
- Code-path result: matches expected. Traced the full call chain — `AppShell` → `ContactsTabContent` → `BandMembersView` → `BandMemberCard.onTap` → `BandMemberDetailDrawer.show` → Edit button (`_handleEdit`, visible `if (isAdmin)`) → `onManageRole` → `ContactsTabContent._openRoleManagement` → `BandMemberEditDrawer.show(..., activeMemberCount: activeMemberCount)` → `_isSoleActiveMember` evaluates `widget.member.userId == currentUserId && widget.activeMemberCount <= 1` → renders the warning `Container` with the exact required text when true, else falls through to the unmodified button/blank-state logic. No ambiguity found in the trace.
- Required text verified character-for-character against the diff at `band_member_edit_drawer.dart:486`: `"Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right (arrow right icon) → Edit band (arrow right icon) → Delete)"` — matches Architect Plan §6 verbatim, including both `→` arrow glyphs.
- **Runtime behavior was NOT exercised this session. Tony must independently confirm on a real device before this is committed**, per the mandatory device re-test gate in Architect Plan §16. This is a disclosed, accepted gap for this review (Tony has agreed to perform that confirmation himself after this review), not a blocking defect in the review's own rigor.

## Regression Check
- Risk level: **LOW** (matches Architect assessment)
- Systems reviewed: Members/RBAC (`BandMemberEditDrawer`, `ContactsTabContent`), and the reverted dead-code files (`members_tab_content.dart`, `role_management_sheet.dart`)
- Regressions found: none
  - Admin-removes-other-member flow: `_removeMember()`, the `TextButton.icon` block (label, icon, `onPressed: _isRemoving ? null : _removeMember`), and its styling are byte-for-byte unchanged — confirmed by reading the diff hunk directly; the only change to that block is its new placement inside the `else if (!_isLastAdmin)` branch, with no internal modification.
  - Sole-admin-of-multi-member-band blank state: the implicit `else` (neither `_isSoleActiveMember` nor `!_isLastAdmin`) renders nothing, unchanged from pre-diff behavior — no new branch was added for this case.
  - `_isSoleActiveMember` is additionally scoped by `widget.member.userId == currentUserId`, so it cannot fire when viewing another member's card, regardless of that band's active-member count — confirmed by reading the getter body directly.
  - `BandMemberDetailDrawer`, `BandMemberCard`: zero diff, confirmed above.
  - Revert of `members_tab_content.dart`/`role_management_sheet.dart` cannot regress anything observable, since both are unreachable from `AppShell` (Reachability Verification above, independently re-confirmed rather than taken from the plan).

## Database Safety
Not applicable — no migration, RLS, or RPC changes in the diff (confirmed: `git diff` against `supabase/migrations` shows zero output; the `remove_band_member`/`delete_band` RPC call sites in `band_member_edit_drawer.dart` are unmodified).

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings ("No issues found! (ran in 4.8s)")

## Test Results
Not run — confirmed via `grep -rl "role_management_sheet\|members_tab_content\|band_member_edit_drawer" test/` that no test file references any of the three touched files; the Architect plan does not require tests for this change.

## Diff Safety Review
- Secrets: none found
- Debug artifacts: none found (grepped the diff for `print(`, `debugPrint`, `TODO`, `FIXME`, API keys/secrets — no matches)
- Unrelated changes: none in the two live files. `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` remains modified as a pre-existing, out-of-scope entry (documented by every prior agent in this pipeline, including this Architect plan's Dirty-Tree Note); not part of this diff's scope and not touched by this change.

## Issues Found
None

---

**Note on device access:** three targets are connected (`flutter devices`: physical iPhone, macOS, Chrome), but this QA session has no interactive UI-driving or screenshot tool to perform the tap-through repro and visually confirm the rendered text. Per the re-diagnosis instructions, this is disclosed explicitly rather than defaulting to an unearned APPROVED-via-runtime claim. **Tony must independently confirm the exact repro steps on a real device before this is committed** (Architect Plan §16 mandatory gate). Tony has agreed to perform that confirmation himself following this review.
