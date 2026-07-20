# Engineer Report

## Feature Slug

feature/setlist-print-show-key

## Feature Title

Setlist Print Show Key

## Goal

Add template-controlled key visibility and key font-size support to setlist print/export output. Keep behavior additive and aligned with existing print-template architecture for persistence, UI, and rendering.

## Architect Tasks Completed

- [x] Task 1 - Created timestamp migration adding show_key and key_font_size to public.print_templates with required defaults and range constraint.
- [x] Task 2 - Extended PrintTemplate defaults, parsing, insert/update serialization, copyWith, equality, and hash support for showKey and keyFontSize.
- [x] Task 3 - Added Key section to PrintOptionsBottomSheet using existing \_buildSection pattern and persisted edits to \_current.
- [x] Task 4 - Updated SetlistPrintService.generatePrintHtml to render key only when enabled and present, using separator-safe token assembly.
- [x] Task 5 - Updated SetlistPrintService PDF song-row metadata rendering for key with enable/presence rules and independent keyFontSize styling.
- [x] Task 6 - Updated database schema reference docs for new print_templates columns.
- [x] Task 7 - Validated saved-template selection and bands.last_used_print_template_id behavior remains in existing flow without repository changes.
- [x] Tony-requested addendum - Wrapped rendered key labels in parentheses in both HTML and PDF print output paths, reusing the existing showKey/non-empty guards so parentheses appear only when key text is shown.

## Files Created

- supabase/migrations/20260719000000_add_show_key_to_print_templates.sql
- docs/features/setlist-print-show-key/ENGINEER_REPORT.md

## Files Modified

- lib/features/setlists/models/print_template.dart
- lib/features/setlists/widgets/print_options_bottom_sheet.dart
- lib/features/setlists/services/setlist_print_service.dart
- docs/reference/architecture/database_schema.md

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

## Test Results

Not run (not explicitly required by Architect plan)

## Verification

Manual steps performed:

- Ran Tier 1 pre-deploy SQL check 1 against linked DB: confirmed show_capo/show_bpm/show_notes/show_tuning/show_pauses defaults and nullability pattern.
- Ran Tier 1 pre-deploy SQL check 2 against linked DB: confirmed show_key and key_font_size do not yet exist.
- Ran Tier 1 pre-deploy SQL check 3 against linked DB: confirmed songs.musical_key exists and key data is present.
- Confirmed no current setlist call site references SetlistPrintHandler.
- Confirmed PrintOptionsBottomSheet continues loading/saving templates through PrintTemplateRepository and last-used template calls.
- Ran flutter analyze with clean result.

## Deviations From Architect Plan

None

## Revision Notes

- QA identified unrelated markdown table reformatting in docs/reference/architecture/database_schema.md; that churn was reverted and only the architect-approved print-template key-field wording remains.
- Tony requested a follow-up renderer adjustment so printed song keys display in parentheses, for example `(E Minor)`, in both HTML and PDF output paths.

## Blockers Encountered

None

## Ready For QA

Yes

## Revision Notes
- 2026-07-20: Second occurrence of a full-document reformat regression in `docs/reference/architecture/database_schema.md` during this session. Repaired using terminal-only commands (`git checkout HEAD -- ...` + `sed -i '' ...`) to avoid editor format-on-save side effects. Verified resulting diff is exactly one line changed (`1 +-`) and only the Key fields sentence was modified to include `key`.
