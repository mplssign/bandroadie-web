# Engineer Report

## Feature Slug
feature/band-contacts-az-listing

## Feature Title
Band Members & Contacts A-Z Listing

## Goal
Extend the iOS Contacts-style A-Z listing (search, section headers, right-side index column) already shipped for Venues to the Band and Contacts segments of the Contacts tab, extracting the shared A-Z grouping/index-column logic into reusable helpers rather than duplicating it a third time, and retrofitting Venues to consume the same shared helpers. Band Members intentionally omits the index column per explicit product decision.

## Architect Tasks Completed
- [x] Task 1 — Verified `scrollable_positioned_list: ^0.3.8` present in `pubspec.yaml` (line 63). No change made.
- [x] Task 2 — Created `lib/features/contacts/widgets/az_list_helpers.dart` (`groupByLetter<T>()`, `flatIndexForSection()`, `resolveTargetLetter()`), ported verbatim from `venues_view.dart`'s inline logic.
- [x] Task 3 — Created `lib/features/contacts/widgets/az_search_field.dart` (`AzSearchField`), styling ported verbatim from `venues_view.dart`'s `_buildSearchBar()`.
- [x] Task 4 — Created `lib/features/contacts/widgets/az_index_column.dart` (`AzIndexColumn`), ported verbatim from `venues_view.dart`'s `_buildIndexColumn()`. Widget only reports the tapped letter via `onLetterTap`; callers resolve the target section and drive their own `ItemScrollController`.
- [x] Task 5 — Created `lib/features/contacts/widgets/az_section_header.dart` (`AzSectionHeader`), styling ported verbatim from `venues_view.dart`'s inline section-header `Text`.
- [x] Task 6 — Retrofitted `venues_view.dart`: removed `_groupVenuesByLetter()` and `_getFlatIndexForSection()`, replaced with calls to `groupByLetter()`/`flatIndexForSection()`/`resolveTargetLetter()`; `_buildSearchBar()` and `_buildIndexColumn()` now delegate to `AzSearchField`/`AzIndexColumn`; inline section-header `Text` replaced with `AzSectionHeader`. `_calculateItemCount()`, `_buildItem()`'s flat-index branching, `ScrollablePositionedList` wiring, `RefreshIndicator`, empty-search state, and navigation calls untouched.
- [x] Task 7 — Added `searchQuery`/`filteredContacts` to `ContactsState` + `copyWith()`; added `setSearchQuery()`/`_filterContacts()` (case-insensitive `contact.name.contains`) to `ContactsNotifier`; `load()`/`refresh()` now populate `filteredContacts`. Mirrors `VenuesState`/`VenuesNotifier` exactly (minus the secondary-field matching Venues has, per plan scope).
- [x] Task 8 — Simplified `contact_card.dart`: removed border/gradient/title-pill/contact-rows/`_buildInfoRow()`/`_launchPhone()`/`_launchEmail()`. Now a plain `Container` (surface, 16px radius, 16px padding) with bold name + always-rendered `contact.title ?? ''` subtitle, matching `VenueCard`.
- [x] Task 9 — Rebuilt `contacts_view.dart` on the shared A-Z pattern: `AzSearchField` (hint "Search contacts"), `AzSectionHeader`, `AzIndexColumn`, `ScrollablePositionedList.builder` replacing `CustomScrollView`/`SliverList`, grouped via `groupByLetter(contacts, (c) => c.name)`. Tap behavior preserved unchanged (`_openContactForm` → `ContactFormScreen` edit mode). Inline "No contacts found" empty-search state added, matching Venues' pattern.
- [x] Task 10 — Created `lib/features/contacts/widgets/band_member_card.dart` (`BandMemberCard`): plain `Container` matching `VenueCard`'s visual style; header row with bold name + optional admin kebab (`showAdminActions`/`onManageRole`, ported from `MemberCard._buildAdminButton()`); subtitle line always rendered (`member.musicalRoles.join(', ')`); `onTap` default null (no-op, matching current behavior). `member_card.dart` untouched.
- [x] Task 11 — Rebuilt `band_members_view.dart`: converted `StatelessWidget` → `StatefulWidget` with local `TextEditingController`/`ItemScrollController`/`String _searchQuery`. Filters by `member.name` (case-insensitive contains). Groups via shared `groupByLetter()` keyed by last name → first name → full name fallback (`_groupingKey`), matching the server's last-name-first sort order per the Architect's Design Decision. Renders `AzSearchField` (hint "Search band members") + `AzSectionHeader(rightPadding: Spacing.pagePadding)` (no 40px index-column reservation) + `BandMemberCard`. **No `AzIndexColumn` instantiated anywhere in this file.** Existing loading/error/zero-members states (`_buildLoadingState()`, `_buildErrorState()`, `MembersEmptyState`) preserved unchanged. `membersProvider`/`MembersState`/`MembersRepository`/`MemberVM` untouched.
- [ ] Task 12 — Cross-platform manual verification (Web/iOS/Android/macOS). **Not performed in this session** — see Verification section below.

## Files Created
- `lib/features/contacts/widgets/az_list_helpers.dart`
- `lib/features/contacts/widgets/az_search_field.dart`
- `lib/features/contacts/widgets/az_index_column.dart`
- `lib/features/contacts/widgets/az_section_header.dart`
- `lib/features/contacts/widgets/band_member_card.dart`

## Files Modified
- `lib/features/contacts/widgets/venues_view.dart`
- `lib/features/contacts/widgets/band_members_view.dart`
- `lib/features/contacts/widgets/contacts_view.dart`
- `lib/features/contacts/widgets/contact_card.dart`
- `lib/features/contacts/contacts_controller.dart`

No other files were touched. `pubspec.yaml` was inspected (Task 1) but not modified — the dependency was already present. All files listed in the plan's "Files Off-Limits" table were left untouched (confirmed via `git status`/`git diff`: only the five files above show as modified, plus the five new files above).

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!" (both before and after formatting)

## Test Results
Not run — no existing automated tests cover any of the changed files (`grep` against `test/` for all changed/created filenames returned no matches), and the Architect plan's Verification Plan is entirely manual/UI-based with no automated test requirement.

## Verification
Manual steps performed:
- Confirmed `scrollable_positioned_list: ^0.3.8` present in `pubspec.yaml` before starting (Task 1).
- Confirmed via `git diff`/`git status` that exactly the five planned files were modified and exactly the five planned files were created — nothing in "Files Off-Limits" was touched.
- Ran `flutter analyze` twice (before and after formatting) — 0 errors, 0 warnings both times.
- Read through the retrofitted `venues_view.dart` in full after editing to confirm the swap was mechanical: `_calculateItemCount()`, `_buildItem()`'s flat-index branching structure, `ScrollablePositionedList` wiring, `RefreshIndicator`, empty-search state, and all navigation calls (`_openVenueDetail`, `_openVenueForm`) are byte-identical to the pre-retrofit version — only the four extracted pieces changed.

**Not performed:** Interactive manual verification per the plan's Verification Plan (Tests 1–5) on Web/iOS/Android/macOS. This session has no GUI/browser/simulator interaction tooling and no live Supabase session configured, so I could not tap through search, index-column scroll-to-section, admin kebab → `RoleManagementSheet`, or empty-state rendering as a human would. This is flagged as a blocker below and should be the primary focus of the QA phase, with particular attention to:
- Venues regression (Test 1) — highest risk item, since `venues_view.dart` internals were swapped.
- Band Members admin kebab → `RoleManagementSheet` (Test 2, item 6) — the plan calls this the highest-risk new-functionality item.
- Index-column nearest-letter-fallback behavior on Contacts (Test 3, item 5).

## Deviations From Architect Plan
None. All five files-to-modify and five files-to-create match the plan exactly. No files outside the plan's scope were touched.

## Blockers Encountered
None that blocked implementation. One limitation to flag: this session had no way to perform the interactive cross-platform manual verification specified in Task 12 / the Verification Plan (no simulator/browser interaction tooling, no live band data to test against). Implementation and static verification (analyzer) are complete and clean; live UI verification is deferred to QA.

## Ready For QA
Yes — with the caveat that Task 12 (interactive manual verification) has not been performed and QA's execution of the full Verification Plan (Tests 1–5, especially the Venues regression re-test and the admin kebab flow) is the first live check this change will receive.

---

# Amendment 1 — Drop Band Search/Sections, Add Contact Company Field

## Trigger
Product scope change from Tony, confirmed after QA approved the base feature above. Base feature was implemented and QA-approved but not yet committed/pushed, so this amendment modifies the same uncommitted working tree directly. See `ARCHITECT_PLAN_AMENDMENT_1.md`.

## Architect Tasks Completed
- [x] Task 13 — Reverted `band_members_view.dart` from `StatefulWidget` back to a plain `StatelessWidget`. Removed `TextEditingController`, `ItemScrollController`, `ItemPositionsListener`, `_searchQuery`, `dispose()`, `_groupingKey()`, `_filterMembers()`, `_calculateItemCount()`, `_buildItem()`, `_buildSearchBar()`, the `AzSearchField`/`AzSectionHeader` instantiations, the `groupByLetter()` call, and the search-empty-state block. Removed now-unused imports (`scrollable_positioned_list`, `az_list_helpers.dart`, `az_search_field.dart`, `az_section_header.dart`) and the now-unused `member_card.dart` import (card is `BandMemberCard`, per base feature). Rebuilt `build()` as `CustomScrollView`/`SliverList`/`SliverPadding` rendering `BandMemberCard` directly from `membersState.members`, no filtering/grouping — matching the pre-feature shape (confirmed via `git show` of the last committed version) with `BandMemberCard` in place of the old `MemberCard`. `_buildLoadingState()`/`_buildErrorState()`/`MembersEmptyState` preserved unchanged.
- [x] Task 14 — Created `supabase/migrations/20260725000000_add_company_to_contacts.sql` with the exact specified SQL (`ALTER TABLE public.contacts ADD COLUMN company TEXT;`). Applied to the project's Supabase instance (project `nekwjxvgbveheooyorjo`, "Band Roadie" — confirmed as the correct target via `grep` match against `tools/build_mobile_release.sh`'s `PROD_CONFIG_PATTERN`). Post-deploy check confirmed: `information_schema.columns` shows `company | text | nullable=YES` on `contacts`. No RLS policy, trigger, or index added, per plan.
- [x] Task 15 — Added `company` (nullable `String`) to `Contact`: constructor param, `fromJson` (`json['company'] as String?`), `toJson` (`'company': company`).
- [x] Task 16 — Added `_companyController`/`_companyFocus` to `ContactFormScreen`, initialized from `c?.company ?? ''` in `initState()`, disposed in `dispose()`. Added a `TextField` using the existing `_inputDecoration('Company')` pattern, placed after the Title section and before Phone. Added `'company': _companyController.text.trim().isEmpty ? null : _companyController.text.trim()` to the `_save()` data map (single call site, covers both create and update).
- [x] Task 17 — Replaced `contact_card.dart`'s subtitle (`contact.title ?? ''`) with `_subtitle(contact)`, adding the private `_subtitle()` helper exactly as specified (comma-join when both title and company present, single field when only one present, empty string when neither).
- [ ] Task 18 — Cross-platform manual verification. **Not performed in this session** — same tooling limitation as base-feature Task 12 (no simulator/browser interaction tooling, no live UI session). Deferred to QA.

## Files Created (this amendment)
- `supabase/migrations/20260725000000_add_company_to_contacts.sql`

## Files Modified (this amendment)
- `lib/features/contacts/widgets/band_members_view.dart`
- `lib/features/contacts/models/contact.dart`
- `lib/features/contacts/widgets/contact_form_screen.dart`
- `lib/features/contacts/widgets/contact_card.dart`

No files from the amendment's "Files Off-Limits" table were touched. No base-plan task (1–12) was redone.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 0 warnings — "No issues found!" (ran after all five amendment tasks were implemented)

## Test Results
Not run — no existing automated tests cover any of the changed files; the amendment's Verification Plan Addendum (Tests AM1/AM2) is manual/UI-based with no automated test requirement.

## Verification
Manual steps performed:
- Confirmed via `git branch --show-current` that the session was on `feature/band-contacts-az-listing` before starting; no new branch created.
- Confirmed the pre-feature shape of `band_members_view.dart` via `git show <last-commit>:lib/features/contacts/widgets/band_members_view.dart` and matched the reverted `build()` structure to it (with `BandMemberCard` substituted for `MemberCard`), per the plan's explicit instruction to reuse this exact pattern.
- Ran the migration via `apply_migration` against project `nekwjxvgbveheooyorjo`, then ran a post-deploy `information_schema.columns` query confirming `company` exists as nullable `text` before proceeding to Task 15 (per session instructions, would have stopped if this failed).
- Ran `flutter analyze` after all edits — 0 errors, 0 warnings.
- Ran `dart format` on all four amendment-modified files — 0 files changed (already correctly formatted).
- Reviewed `git diff` on all four modified files to confirm each change matches its task exactly (no incidental edits) and that only the five files off-limits table's files remained untouched.

**Not performed:** Interactive manual verification per Test AM1 (Band Members search/sections removed, admin kebab still works) and Test AM2 (Contacts company field round-trip across create/edit/all four subtitle states) on Web/iOS/Android/macOS — same tooling limitation noted in the base feature's report. Flagged as a blocker below; this is the first live check this amendment will receive.

## Deviations From Architect Plan
None. All four files-to-modify and the one file-to-create match the amendment plan exactly.

## Blockers Encountered
None that blocked implementation. Same limitation as the base feature: no simulator/browser interaction tooling available in this session, so Task 18's interactive verification (Test AM1/AM2) was not performed and is deferred to QA.

## Ready For QA
Yes — with the caveat that Task 18 (interactive manual verification) has not been performed. QA should prioritize: Band Members admin kebab → `RoleManagementSheet` surviving the `StatefulWidget` → `StatelessWidget` reversion (Test AM1, item 7 — highest-risk item per the amendment), and the Contacts company field round-trip across all four subtitle states plus pre-existing (`company IS NULL`) contacts (Test AM2).

---

# Amendment 2 — Band Member Detail + Edit Drawers, Crown Icon

## Trigger
Product scope addition from Tony, confirmed directly, building on top of Amendment 1's uncommitted, not-yet-QA-verified changes to `band_members_view.dart`/`band_member_card.dart`. Both revised decisions (Decision 1 — Role Management ported into the Edit drawer's actual functionality, not linked out to the existing page; Decision 3 — crown-only, no eye icon) were followed as specified in the revised `ARCHITECT_PLAN_AMENDMENT_2.md`, not any earlier draft. See that file for full rationale.

## Pre-Task Verification
Before starting, confirmed both of Amendment 1's prerequisite states were present on disk, per the plan's explicit instruction:
- `band_members_view.dart` was a plain `StatelessWidget` (no search/grouping state) — confirmed by reading the file.
- `band_member_card.dart` had the admin kebab (`_buildAdminButton()`, `showAdminActions`/`onManageRole` params) — confirmed by reading the file.

Both conditions held, so the amendment proceeded.

## Architect Tasks Completed
- [x] Task 19 — Created `lib/features/contacts/widgets/band_member_detail_drawer.dart` (`BandMemberDetailDrawer`, `StatelessWidget` + static `show()`). Outer shell (`Container` maxHeight 90%, top-only 20px radius, `context.colors.surface`) and drag handle ported verbatim from `ViewGigDrawer`. Local private `_DetailRow` ported verbatim from `view_gig_drawer.dart:451-511`. Header block: crown-only role icon (`member.isAdmin`) + name. Rows: Role (always, mapped via `isAdmin`/`isContributor`), Instruments (if non-empty), Phone/Email (tappable, `_launchPhone`/`_launchEmail` ported from `member_card.dart`), Address (if `_hasAddress`), Birthday (if present) — all four field-presence checks and formatters ported verbatim from `member_card.dart`. Footer: `BrandActionButton` "Done" + conditional "Edit" (admin-gated), pop-then-call matching `ViewGigDrawer._handleEdit()`.
- [x] Task 20 — Edited `band_member_card.dart`: removed `_buildAdminButton()`, `showAdminActions`, `onManageRole` params, and the kebab's conditional render. Added crown-only role-badge icon (`if (member.isAdmin) Icon(AppIcons.crown, size: 18, color: AppColors.primary)`, `top: 6, right: 10` padding) as the first child of the header `Row`, before the name. **No eye icon for contributors** — that branch is not implemented anywhere in this file, per revised Decision 3. Added the `app_icons.dart` import. `onTap` param retained unchanged (already declared).
- [x] Task 21 — Edited `band_members_view.dart`: `BandMemberCard(...)` construction now drops `showAdminActions`/`onManageRole` and adds `onTap: () => BandMemberDetailDrawer.show(context, member: member, isAdmin: membersState.isCurrentUserAdmin, onManageRole: () => onManageRole(member))`. Added `import 'band_member_detail_drawer.dart';`. `BandMembersView`'s own constructor/`onManageRole` param signature unchanged.
- [x] Task 22 — Created `lib/features/contacts/widgets/band_member_edit_drawer.dart` (`BandMemberEditDrawer`, `ConsumerStatefulWidget` + static `show()`). Full field-for-field, method-for-method port of `_RoleManagementSheetState`: `_selectedRole`, `_initialRole`, `_subPermissions`, `_initialSubPermissions`, `_isSaving`, `_isRemoving`, `initState()` (incl. post-frame `_loadExistingPermissions()`), `_loadExistingPermissions()`, `_isSelfAndLastAdmin`, `_isLastAdmin`, `_hasChanges`, `_permissionsEqual()`, `_saveRole()` (all four `PostgrestException` message-substring mappings, exact copy), `_removeMember()` (exact confirmation dialog copy), `_buildRoleButton()` (exact `enabled:` expressions per role), `_buildPermissionToggle()`, `_roleDisplayName()`. Chrome (shell/drag-handle/header/footer padding) adapted from `BandMemberDetailDrawer`/`ViewGigDrawer`, not from `RoleManagementSheet`'s `Scaffold`/`AppBar`, per the plan's explicit instruction — see Deviations below for the itemized list of sanctioned adaptations. `role_management_sheet.dart` was read for reference only; not modified.
- [x] Task 23 — Edited `contacts_tab_content.dart`: `_openRoleManagement()`'s `adminCount` computation unchanged; replaced `Navigator.of(context).push(fadeSlideRoute(page: RoleManagementSheet(...)))` with `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)`. Removed the `role_management_sheet.dart` import, added the `band_member_edit_drawer.dart` import. No other change to this file.
- [ ] Task 24 — Cross-platform manual verification. **Not performed in this session** — same tooling limitation as prior sessions (no simulator/browser interaction tooling, no live UI session). Deferred to QA.

## Files Created (this amendment)
- `lib/features/contacts/widgets/band_member_detail_drawer.dart`
- `lib/features/contacts/widgets/band_member_edit_drawer.dart`

## Files Modified (this amendment)
- `lib/features/contacts/widgets/band_member_card.dart`
- `lib/features/contacts/widgets/band_members_view.dart`
- `lib/features/contacts/contacts_tab_content.dart`

Confirmed via `git status`/`git diff` that exactly these five files (two new, three modified) changed as a result of this amendment's tasks, on top of Amendment 1's already-present, still-uncommitted changes to the same working tree. No file from the amendment's "Files Off-Limits" table was touched — in particular, `role_management_sheet.dart` and `member_card.dart` are unmodified (confirmed both are absent from `git status`), and no Venues/Contacts-segment file changed.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 1 warning — `unused_element_parameter` on `_DetailRow.showChevron` in `band_member_detail_drawer.dart:293`. This is expected and intentional, not a defect: the plan (Task 19) explicitly calls for porting `_DetailRow` verbatim from `view_gig_drawer.dart:451-511`, including its `showChevron`/`onTap` optional parameters, even though none of this drawer's rows currently pass `showChevron: true` (none of Role/Instruments/Phone/Email/Address/Birthday need a chevron). Ran twice (before and after `dart format`) — same single warning both times, no errors either time.

## Test Results
Not run — no existing automated tests cover any of the changed/created files; the amendment's Verification Plan Addendum (Tests AM2-1 through AM2-5) is manual/UI-based with no automated test requirement.

## Verification
Manual steps performed:
- Confirmed on branch `feature/band-contacts-az-listing` via `git branch --show-current` before starting.
- Confirmed Amendment 1's prerequisite state on disk (`band_members_view.dart` as `StatelessWidget`, `band_member_card.dart` with the admin kebab) by reading both files in full before making any change.
- Read `view_gig_drawer.dart`, `role_management_sheet.dart`, `member_card.dart`, `member_vm.dart`, `contacts_tab_content.dart`, `phone_formatter.dart`, `app_icons.dart`, and `contributor_permissions.dart` in full before writing any new code, per the plan's explicit instruction for Task 22.
- Ran `flutter analyze` after all four tasks — 0 errors, 1 expected warning (see Analyzer Results).
- Ran `dart format` on all five changed/created files — one file (`band_member_edit_drawer.dart`) had formatting applied (line-wrapping only); re-ran `flutter analyze` afterward to confirm no regressions — same result (0 errors, 1 warning).
- Performed the mandatory side-by-side comparison of `band_member_edit_drawer.dart` against `role_management_sheet.dart` for every state field, getter, method, condition, and string in Task 22's scope — see Deviations From Architect Plan below for the complete, itemized result.
- Confirmed via `git status`/`git diff` that exactly the five files above changed, matching the plan's Files to Create/Modify tables exactly, and that all Files Off-Limits entries (`role_management_sheet.dart`, `member_vm.dart`, `members_controller.dart`, `members_repository.dart`, `member_card.dart`, `members_tab_content.dart`, all Venues/Contacts files, all shared `az_*` helpers) remain untouched.

**Not performed:** Interactive manual verification per Tests AM2-1 through AM2-5 (detail drawer content, edit drawer role-transition/last-admin-guard/error-handling/remove-member cases, non-admin gating, crown-only icon, kebab removal) on Web/iOS/Android/macOS — same tooling limitation noted in prior sessions. This is flagged as a blocker below. Given the plan's own HIGH regression-risk rating and its explicit statement that "QA must verify the ported logic directly... not merely confirm that tapping Edit still leads somewhere," this amendment's Test AM2-2 (the last-admin guard and every role-transition case) is the single most important item for QA to execute before this ships.

## Deviations From Architect Plan

**None that alter behavior or logic.** The following are chrome/UI-structure adaptations that the plan itself explicitly calls for and sanctions (Amendment 2, Decision 1 revised + Task 22's "Chrome" instructions) — listed here per the session's explicit instruction to call out anything adapted rather than ported verbatim, and why:

1. **`Scaffold`/`AppBar` replaced with `Container`/drag-handle shell.** `RoleManagementSheet` is a full-screen `Scaffold` with an `AppBar`; `BandMemberEditDrawer` uses the same `Container` (maxHeight 90% of screen height, top-only 20px `BorderRadius`, `context.colors.surface`) + drag-handle shell as `BandMemberDetailDrawer`/`ViewGigDrawer`. Explicitly required by the plan — a `Scaffold` cannot be dropped into `showModalBottomSheet`'s builder and produce drawer chrome.
2. **Header restructured: added a "Manage Role" label above the member name/role, moved out of the scrollable body into a fixed header area followed by `Divider(height: 1)`.** The original renders `member.name` + `_roleDisplayName(...)` as the first two items inside the scrollable `SingleChildScrollView`, with a 32px gap before "Change role". The plan's Task 22 explicitly specifies this exact header shape ("`'Manage Role'` label, then `member.name` + current role display... then `Divider(height: 1)`"), so this is a direct implementation of an explicit instruction, not an inference.
3. **No close-X / `AppBar` leading icon.** Per the plan: dismissal is via backdrop-tap (standard `showModalBottomSheet` behavior) or the footer's Cancel button, matching `ViewGigDrawer`'s own dismissal model. Explicitly specified.
4. **Footer bottom padding changed from `MediaQuery.of(context).padding.bottom + 12` to `MediaQuery.of(context).padding.bottom + Spacing.space16`.** Per the plan's explicit instruction to match "the drawer-footer convention" (the same formula `BandMemberDetailDrawer`/`ViewGigDrawer` use). The Container's border/boxShadow/surface-color styling, and the Save/Cancel button widgets themselves (including every enabled-state expression and string), are otherwise unchanged from `_buildFixedBottomActions()`.
5. **Success-path `Navigator.of(context).pop()` now pops the modal bottom sheet route instead of the original's full-screen pushed route.** Identical call (`Navigator.of(context).pop()`), different route type underneath — explicitly sanctioned by the plan ("same call, different route type").

**Everything else** — every field, getter, method body, conditional render, enabled/disabled expression, and string (including all four `PostgrestException` message mappings and the last-admin warning copy) — was ported character-for-character from `_RoleManagementSheetState`. No logic was re-derived or approximated.

One additional, pre-existing (non-Amendment-2) note: `flutter analyze` reports one warning (`_DetailRow.showChevron` unused) in `band_member_detail_drawer.dart`, explained under Analyzer Results above — this is an accepted consequence of the plan's explicit "port `_DetailRow` verbatim" instruction, not a deviation from it.

## Blockers Encountered
None that blocked implementation. Same limitation as prior sessions: no simulator/browser interaction tooling available, so Task 24's interactive verification (Tests AM2-1 through AM2-5) was not performed and is deferred to QA.

## Ready For QA
Yes — with the caveat that Task 24 (interactive manual verification) has not been performed. Given this amendment's own HIGH regression-risk rating, QA should treat Band Members as needing one **combined** regression pass covering the base feature + Amendment 1 + Amendment 2 together (per the plan), prioritizing in order: (1) Test AM2-2, the ported Edit drawer logic — every role-transition case and the last-admin guard's exact conditions/effects, since there is no longer an unmodified reference screen to fall back on; (2) Test AM2-1, the read-only detail drawer's conditional field rendering and phone/email tap-to-launch; (3) Test AM2-3/AM2-5, non-admin Edit-gating and kebab-removal; (4) Test AM2-4, crown-only rendering across admin/contributor/member. Amendment 1's Test AM1 item 7 (kebab → `RoleManagementSheet`) is now moot/superseded, per the plan, since the kebab no longer exists.

---

# Addendum — Detail Drawer Label/Layout Changes (Task 25)

## Trigger
Product refinement from Tony, confirmed directly, on top of Amendment 2 as already implemented. Presentational-only: two label renames, one row reorder, one layout-constant widen, in `band_member_detail_drawer.dart`. No data, state, or logic change.

## Pre-Task Verification
Before starting, confirmed the file on disk matched Amendment 2's original Drawer 1 section exactly: `Role` was the first detail row (unconditional, `_roleLabel(member)`), `Instruments` was the second row (conditional on `member.musicalRoles.isNotEmpty`), and `_DetailRow`'s label column was `SizedBox(width: 68)` — confirmed by reading the full file before making any change.

## Architect Tasks Completed
- [x] Task 25 — Edited `lib/features/contacts/widgets/band_member_detail_drawer.dart`:
  - Renamed the `Instruments` row's label to `Role in band`; value (`member.musicalRoles.join(', ')`) and conditional (`if (member.musicalRoles.isNotEmpty)`) unchanged.
  - Renamed the `Role` row's label to `Access`; value (`_roleLabel(member)`) and unconditional render unchanged.
  - Reordered the six detail rows to: Role in band (if present) → Phone (if present) → Email (if present) → Address (if present) → Birthday (if present) → Access (always). No row's conditional-render guard, value, or formatter changed — only position.
  - Widened `_DetailRow`'s label column from `SizedBox(width: 68)` to `SizedBox(width: 96)`.

## Additional Instructions (not in the addendum doc)
Further label changes confirmed directly by Tony, separately from the written addendum, all label-text-only with no value/conditional/logic change:
1. Renamed the drawer footer's `Edit` text button to `Change access`. Same button, same `onPressed: () => _handleEdit(context)` behavior. Applied at `band_member_detail_drawer.dart`'s footer `TextButton`.
2. Renamed the `Role in band` detail row's label to `Band role`. Same row (first, conditional on `member.musicalRoles.isNotEmpty`), same value (`member.musicalRoles.join(', ')`). The addendum's 96px label-column width was left unchanged — "Band role" (9 characters) is shorter than "Role in band" (12) and still fits comfortably; re-deriving the column width was out of scope for a label-only rename.
3. Renamed `BandMemberEditDrawer`'s header label from `Manage Role` to `Change Access`. Same header block (label above member name + current role display), no structural change. Applied at `band_member_edit_drawer.dart:290`. `role_management_sheet.dart:248` has the same string but is untouched — that file is off-limits per Amendment 2's Files Off-Limits table (dead, still-compiled code per the plan's own note), and this instruction did not extend to it.
4. Reverted the drawer footer's `TextButton` label from `Change access` back to `Edit` (undoing additional instruction 1 above). Confirmed directly by Tony: `BandMemberEditDrawer` (the destination screen) does more than change access — it also has "Remove from band" — so "Change access" undersells what the button leads to. Same button, same `onPressed: () => _handleEdit(context)` behavior, label text only. Applied at `band_member_detail_drawer.dart`'s footer `TextButton`. `band_member_edit_drawer.dart`'s own header label ("Change Access", additional instruction 3) was explicitly out of scope for this revert and was not touched.
5. Reverted `BandMemberEditDrawer`'s header label from `Change Access` back to `Edit` (undoing additional instruction 3 above). Confirmed directly by Tony: same reasoning as additional instruction 4 — the edit drawer does more than change access, and "Edit" now matches the detail drawer's footer button for consistent wording across both drawers. Same header block (label above member name + current-role display), no structural change. Applied at `band_member_edit_drawer.dart:290`. The adjacent comment (`// Header: 'Change Access' label + member name + current role`) was updated to `// Header: 'Edit' label + member name + current role` to match. `role_management_sheet.dart:248`'s "Change Access" string remains untouched (off-limits per Amendment 2, dead code) — this instruction did not extend to it.

## Files Modified
- `lib/features/contacts/widgets/band_member_detail_drawer.dart` (Task 25 + additional instructions 1, 2, and 4)
- `lib/features/contacts/widgets/band_member_edit_drawer.dart` (additional instructions 3 and 5)

Both files were already untracked (new, uncommitted from Amendment 2) before this session. Confirmed via `git status` after each change that no other file — including everything else in Amendment 2's Files Off-Limits table — was touched.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors, 1 warning — the same pre-existing `unused_element_parameter` warning on `_DetailRow.showChevron` documented under Amendment 2's Analyzer Results above. Not introduced by this addendum; this task did not touch `showChevron` or its call sites.

## Test Results
Not run — no automated tests cover this file; the addendum's QA Regression Areas fold into Test AM2-1, which is manual/UI-based.

## Verification
Manual steps performed:
- Confirmed on branch `feature/band-contacts-az-listing` via `git branch --show-current` before starting.
- Read `band_member_detail_drawer.dart` in full and confirmed it matched Amendment 2's pre-addendum row order/labels before making any change.
- Ran `flutter analyze` after implementation — 0 errors, 1 pre-existing warning (unchanged from before this addendum).
- Ran `dart format` on the changed file — 0 files changed (already correctly formatted).
- Confirmed via `git status` that `band_member_detail_drawer.dart` is the only file with content changes from this session.
- Read back the edited row-list and footer sections to confirm: row order is Band role → Phone → Email → Address → Birthday → Access; label column is `width: 96`; footer button text is `Change access`.
- Ran `flutter analyze` and `dart format` again after the `Role in band` → `Band role` rename — same result (0 errors, 1 pre-existing warning; 0 files reformatted) — and confirmed via `git status` that `band_member_detail_drawer.dart` remained the only file with content changes.
- Renamed `band_member_edit_drawer.dart`'s header label from `Manage Role` to `Change Access` (additional instruction 3), checked `role_management_sheet.dart` for the same string and confirmed it was left untouched (off-limits per Amendment 2), ran `flutter analyze`/`dart format` again — same result (0 errors, 1 pre-existing warning in the unrelated `band_member_detail_drawer.dart`; 0 files reformatted) — and confirmed via `git status` that only these two files have content changes.
- Reverted the footer button label from `Change access` back to `Edit` (additional instruction 4), leaving `band_member_edit_drawer.dart`'s own "Change Access" header untouched. Confirmed via `git status`/`git status --porcelain` (full repo) that `band_member_detail_drawer.dart` was the only file with content changes in this session — no other tracked or untracked file was modified. Ran `flutter analyze` — 0 errors, 1 pre-existing warning (`_DetailRow.showChevron`, unchanged).
- Reverted `band_member_edit_drawer.dart`'s header label from `Change Access` back to `Edit` (additional instruction 5), and updated the adjacent comment to match. Confirmed via `git status --porcelain` (full repo) that `band_member_edit_drawer.dart` was the only file with content changes in this session — no other tracked or untracked file was modified, and `band_member_detail_drawer.dart` was left as-is from the prior session. Ran `flutter analyze` — 0 errors, 1 pre-existing warning (`_DetailRow.showChevron` in `band_member_detail_drawer.dart`, unchanged).

**Not performed:** On-device/simulator visual check that "Band role" and "Access" render on a single line at the 96px column width in the detail drawer, and that "Edit" reads cleanly in both drawers' headers/footers — same tooling limitation as prior sessions (no simulator/browser interaction tooling available). Deferred to QA per the addendum's own QA Regression Areas note.

## Deviations From Architect Plan
None. Task 25 implemented exactly as specified. The footer button rename is not in the written addendum but was confirmed directly by Tony as an explicit additional instruction for this session — documented above, not treated as a deviation.

## Blockers Encountered
None.

## Ready For QA
Yes. QA should fold this into Amendment 2's Test AM2-1 (Detail Drawer — Read-Only Content) and the edit-drawer coverage under Test AM2-2, both of which have not yet run: confirm the detail drawer's new row order and labels (including "Band role" as the first row's final label, superseding the addendum doc's "Role in band"), confirm "Band role"/"Access" don't wrap at the 96px column width on the demo band's members, confirm the detail drawer's footer button reads "Edit" (per additional instruction 4, superseding additional instruction 1's "Change access") and still opens the edit drawer, confirm the edit drawer's own header now reads "Edit" (per additional instruction 5, superseding additional instruction 3's "Change Access") in place above the member's name and current-role display, and confirm all values/tap behavior/formatting are otherwise unchanged in both drawers.
