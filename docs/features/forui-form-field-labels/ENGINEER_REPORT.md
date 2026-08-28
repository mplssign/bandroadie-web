# Engineer Report

## Feature Slug

`bug/forui-form-field-labels`

## Feature Title

Forui-wrapped form fields render with no label/hint because callers pass Material `InputDecoration`/`style`, which the wrapper silently drops.

## Goal

Restore visible labels and placeholders in the app by migrating wrapper call sites to the Forui-native API (`labelText`, `hintText`, `prefixIcon`, `suffixIcon`) without changing the wrapper contract or touching off-limits files.

## QA Follow-Up Fixes (Round 2)

### 1. Removed remaining dead `style:` wrapper props

- [x] Removed all remaining no-op `style:` arguments from `AppTextField`/`AppTextFormField` call sites listed in QA follow-up (45 call sites total), excluding the lyrics editor field handled separately below.
- [x] Re-verified in code: no `style:` props remain on wrapper call sites in the requested cleanup files.

### 2. Lyrics editor regression decision and fix

- [x] Reviewed wrapper capability in [lib/components/ui/app_text_field.dart](lib/components/ui/app_text_field.dart): the wrapper does not pass through `style`, and does not support `expands`/`textAlignVertical` needed by this editor.
- [x] Applied the narrow exception path: reverted only [lib/features/lyrics/widgets/lyrics_editor_sheet.dart](lib/features/lyrics/widgets/lyrics_editor_sheet.dart) `_buildTextArea` back to raw Material `TextField`.
- [x] Restored prior behavior-critical properties:
  - dynamic font size (`_fontSize`)
  - bold text weight
  - `height: 1.6`
  - `expands: true`
  - `textAlignVertical: TextAlignVertical.top`
  - original hint/cursor styling

### 3. Restored add-type dialog validation feedback

- [x] In [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart) `_showAddTypeDialog`, wrapped dialog content in a `Column` and added conditional error text rendering beneath `AppTextField` when `errorText != null`.
- [x] Kept existing `setDialogState` flow so validation messages update live within the dialog.

## Architect Tasks Completed

### Root Cause Confirmation

- [x] Confirmed the wrapper contract in [lib/components/ui/app_text_field.dart](lib/components/ui/app_text_field.dart) and [lib/components/ui/app_text_form_field.dart](lib/components/ui/app_text_form_field.dart): label and hint render from wrapper props, not Material `InputDecoration`.
- [x] Verified the reported symptom pattern in the contact and venue UI flows.

### UI Fixes

- [x] Migrated the highest-priority app screens to wrapper-native props while preserving behavior.
- [x] Cleaned stale partial replacements and import gaps in affected fields.
- [x] Reverted unrelated iOS side-effect files from local tooling (`ios/Podfile.lock`, Xcode project/package resolutions) so the working tree remains limited to the approved feature scope.
- [x] Removed the remaining dead `style:` wrapper params across the QA follow-up list (including auth/profile/setlists/events/financials/bands/feedback call sites).
- [x] Avoided modifying off-limits files, including [lib/main.dart](lib/main.dart) and [lib/features/setlists/setlist_repository.dart](lib/features/setlists/setlist_repository.dart).

## Files Updated

The work touched the app’s form surfaces and wrapper call sites, including:

- [lib/features/contacts/widgets/venue_form_screen.dart](lib/features/contacts/widgets/venue_form_screen.dart)
- [lib/features/contacts/widgets/contact_form_screen.dart](lib/features/contacts/widgets/contact_form_screen.dart)
- [lib/features/contacts/widgets/venue_contact_block.dart](lib/features/contacts/widgets/venue_contact_block.dart)
- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
- [lib/features/feedback/bug_report_screen.dart](lib/features/feedback/bug_report_screen.dart)
- [lib/features/events/widgets/event_editor_helpers.dart](lib/features/events/widgets/event_editor_helpers.dart)
- [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart)
- [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)
- [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart)
- [lib/features/lyrics/widgets/lyrics_editor_sheet.dart](lib/features/lyrics/widgets/lyrics_editor_sheet.dart)
- [lib/features/setlists/widgets/bpm_input_dialog.dart](lib/features/setlists/widgets/bpm_input_dialog.dart)
- [lib/shared/widgets/currency_input_field.dart](lib/shared/widgets/currency_input_field.dart)

## Verification

### Static validation

Command run:

```bash
cd /Users/tonyholmes/apps/bandroadie && flutter analyze
```

Final result:

- 0 analyzer errors
- 13 warnings remain
- warnings are pre-existing/unrelated to the Forui fix, primarily unused locals/fields and app-wide deprecation/info notices

### Visual/legibility reasoning checks requested

- [x] [lib/features/feedback/bug_report_screen.dart](lib/features/feedback/bug_report_screen.dart) description field:
  - explicit wrapper `style:` override was removed as no-op; wrapper text rendering now comes from Forui/theme.
  - surrounding screen uses the same dark surface + tokenized text colors used by other wrapper fields in this flow; no code-path indicator of low-contrast text introduced by this change.
- [x] [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart) two migrated `AppTextFormField` helper call sites:
  - explicit wrapper `style:` overrides removed as no-op.
  - fields already rely on wrapper/themed defaults used by other inputs on this screen, so behavior should remain visually consistent.

Note: these are code-path/theming checks; not runtime device screenshots.

### Follow-up QA fixes

- [x] Reverted the unrelated iOS side-effect files to keep the patch limited to the approved feature files and the feature report directory.
- [x] Removed the remaining dead `style:` arguments from the final two Forui wrapper call sites so the patch is consistent with the rest of the bug fix.

### Notes on remaining warnings

These warnings are not caused by the field migration and did not block the label/hint fix:

- unused fields in auth, profile, and tuning widgets
- lint info warnings for whitespace and Supabase `anonKey` deprecation
- a small set of test-file unused locals

## Risk Assessment

Low to medium. Scope remains UI-only, with no backend or repository changes. The only behavior-sensitive area (lyrics editor) was intentionally reverted to Material `TextField` to preserve existing editing behavior.

## Ready For QA

Yes, for UI validation of visible label/hint rendering in the affected screens.
