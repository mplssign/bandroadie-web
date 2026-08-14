# Engineer Report

## Feature Slug

`feature/brand-action-button-migration`

## Feature Title

Migrate BrandActionButton to AppButton Primary Variant

## Goal

Consolidate on the Forui-based UI facade layer by migrating all BrandActionButton call sites to `AppButton(variant: AppButtonVariant.primary)` and deleting the BrandActionButton widget. With the Forui theme integration (PR #147) now in main, AppButton's primary variant renders in rose-primary, making BrandActionButton's custom gradient implementation redundant.

## Architect Tasks Completed

- [x] Task 1 — Add `height` prop to AppButton (COMPLETED)
- [x] Task 2 — Create migration test case for height prop (COMPLETED)
- [x] Task 3 — Migrate Home feature (4 files, 5 instances) (COMPLETED)
- [x] Task 4 — Migrate Calendar feature (4 files, 5 instances) (COMPLETED)
- [x] Task 5 — Migrate Contacts feature (3 files, 3 instances) (COMPLETED)
- [x] Task 6 — Migrate Bands feature (1 file, 1 instance with height: 52) (COMPLETED)
- [x] Task 7 — Migrate Gigs + Rehearsals features (4 files, 4 instances) (COMPLETED)
- [x] Task 8 — Migrate Profile + Members features (2 files, 3 instances) (COMPLETED)
- [x] Task 9 — Migrate Setlists + Events features (4 files, 4 instances) (COMPLETED)
- [x] Task 10 — Verify zero remaining references (COMPLETED)
- [x] Task 11 — Delete BrandActionButton widget (COMPLETED)
- [x] Task 12 — Check for BrandActionButton test file (COMPLETED - no test file existed)
- [x] Task 13 — Optional cleanup - BrandButton design token (INVESTIGATED - still in use, left unchanged)
- [x] Task 14 — Final verification (COMPLETED)

## Files Created

- None (only added test case to existing test/components/ui/app_button_test.dart)

## Files Modified

1. lib/components/ui/app_button.dart — Added `height` prop with SizedBox wrapper
2. test/components/ui/app_button_test.dart — Added height prop test case
3. lib/features/home/home_tab_content.dart — Migrated BrandActionButton to AppButton
4. lib/features/home/widgets/empty_section_card.dart — Migrated BrandActionButton to AppButton
5. lib/features/home/widgets/quick_actions_row.dart — Migrated 3 BrandActionButtons to AppButton
6. lib/features/calendar/calendar_tab_content.dart — Migrated BrandActionButton to AppButton
7. lib/features/calendar/widgets/add_block_out_drawer.dart — Migrated 2 BrandActionButtons to AppButton
8. lib/features/calendar/widgets/day_detail_bottom_sheet.dart — Migrated BrandActionButton to AppButton
9. lib/features/calendar/widgets/view_block_out_drawer.dart — Migrated BrandActionButton to AppButton
10. lib/features/contacts/widgets/band_member_detail_drawer.dart — Migrated BrandActionButton to AppButton
11. lib/features/contacts/widgets/contacts_empty_state.dart — Migrated BrandActionButton to AppButton
12. lib/features/contacts/widgets/venues_empty_state.dart — Migrated BrandActionButton to AppButton
13. lib/features/bands/band_form_screen.dart — Migrated BrandActionButton to AppButton (with height: 52)
14. lib/features/gigs/widgets/gig_notes_sheet.dart — Migrated BrandActionButton to AppButton
15. lib/features/gigs/widgets/view_gig_drawer.dart — Migrated BrandActionButton to AppButton
16. lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart — Migrated BrandActionButton to AppButton
17. lib/features/rehearsals/widgets/view_rehearsal_drawer.dart — Migrated BrandActionButton to AppButton
18. lib/features/profile/my_profile_screen.dart — Migrated 2 BrandActionButtons to AppButton
19. lib/features/members/widgets/members_empty_state.dart — Migrated BrandActionButton to AppButton
20. lib/features/setlists/setlists_tab_content.dart — Migrated BrandActionButton to AppButton
21. lib/features/setlists/widgets/empty_setlists_state.dart — Migrated BrandActionButton to AppButton (updated comment)
22. lib/features/setlists/new_setlist_screen.dart — Migrated BrandActionButton to AppButton
23. lib/features/events/widgets/event_editor_actions.dart — Migrated BrandActionButton to AppButton

## Files Deleted

- lib/components/ui/brand_action_button.dart (124 lines)

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors** / 8 warnings (all pre-existing, not introduced by this implementation)

Pre-existing warnings:

- Unused import in bulk_entry_screen.dart (supabase_flutter)
- Unused local variables in bulk_entry_screen.dart, app_text_field_test.dart, app_text_form_field_test.dart
- BuildContext across async gaps in bulk_entry_screen.dart, original_song_screen.dart

## Test Results

Command: `flutter test test/components/ui/app_button_test.dart`
Result: **All 14 tests passed** (including new height prop test)

## Verification

Manual steps performed:

1. Added `height` prop to AppButton constructor and field declaration
2. Implemented conditional SizedBox wrapper for height in AppButton.build()
3. Added test case validating height prop functionality
4. Migrated all 24 BrandActionButton call sites across 21 files to AppButton with `variant: AppButtonVariant.primary`
5. Preserved all existing props (label, onPressed, icon, isLoading, fullWidth)
6. Preserved special case: band_form_screen.dart uses `height: 52` (non-default)
7. Deleted BrandActionButton widget file (124 lines)
8. Confirmed grep returns only 1 match (comment in financials_screen.dart)
9. Investigated BrandButton design token usage: still used by 3 files (financials_screen.dart, venue_detail_screen.dart, view_gig_drawer.dart) — left unchanged per plan

## Deviations From Architect Plan

None. All tasks completed exactly as specified in ARCHITECT_PLAN.md Section 14.

## Blockers Encountered

None.

## Implementation Notes

1. **Import consolidation issues**: During migration, encountered duplicate imports in 3 files where AppButton was already imported. Fixed by removing duplicate import statements while preserving other necessary imports (e.g., app_bottom_sheet, confirm_action_dialog, app_progress_indicator).

2. **Height prop implementation**: Successfully added height prop to AppButton using the same SizedBox wrapper pattern as fullWidth. This enables the critical band_form_screen.dart use case (height: 52) without requiring Forui StyleDelta complexity.

3. **Comment update**: Updated comment in empty_setlists_state.dart from "Uses BrandActionButton" to "Uses AppButton primary variant" for documentation accuracy.

4. **BrandButton design token**: Confirmed BrandButton class is still used by 3 files for border styling. Per Architect plan, this cleanup is deferred as optional follow-up work.

## Ready For QA

**Yes**

All 14 tasks completed successfully. The migration is complete and ready for visual QA testing across all platforms (Web, iOS, Android, macOS) to verify rose-primary button rendering on the 21 migrated files.

Critical QA focus:

- band_form_screen.dart: Verify submit button renders at 52px height (visibly taller than default)
- All empty states: Verify rose-primary CTA buttons render correctly
- Loading states: Verify spinner displays correctly in add_block_out_drawer.dart, band_form_screen.dart, my_profile_screen.dart, event_editor_actions.dart

Visual change is intentional: gradient background → solid rose-primary background (Forui design system standard).
