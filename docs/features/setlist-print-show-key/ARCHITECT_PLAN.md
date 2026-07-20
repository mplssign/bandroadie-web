# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/setlist-print-show-key`

Branch name: `feature/setlist-print-show-key`
Docs path: `docs/features/setlist-print-show-key/ARCHITECT_PLAN.md`

## 2. Problem Summary

The setlist print settings flow already persists multiple per-template visibility toggles on `print_templates` (`show_capo`, `show_bpm`, `show_notes`, `show_tuning`, `show_pauses`) and uses those settings to decide what metadata appears in printed/exported setlists. Songs already carry a nullable musical key in `songs.musical_key`, exposed to the setlist print flow as `SetlistSong.musicalKey`, but the print-template model and renderers have no `show_key` setting and no key-specific output branch.

Result: bands can store and edit song keys in the app, but they cannot choose to include or suppress keys in printed/exported setlists.

## 3. Root Cause

Confirmed root cause: the print-template system predates song-key support and was never extended in three places that must agree:

1. Database schema: `print_templates` has no `show_key` column.
2. Flutter template model/UI: `PrintTemplate` and `PrintOptionsBottomSheet` have no key toggle state.
3. Print renderers: `SetlistPrintService` renders tuning, BPM, capo, notes, and pauses, but never renders `song.musicalKey`.

Confidence: `HIGH`

## 4. Reference Docs Consulted

- `docs/reference/architecture/database_schema.md`

Additional note: no dedicated print/export reference docs were found under `docs/reference/` beyond the schema snapshot above.

## 5. Existing System Analysis

### Current data flow

Active setlist print/export flow:

`SetlistDetailScreen._handlePrint()`
→ `PrintOptionsBottomSheet.show(...)`
→ `PrintTemplateRepository.fetchTemplates()` / `getLastUsedTemplateId()`
→ user edits a `PrintTemplate`
→ `SetlistPdfPreviewScreen`
→ `SetlistPrintService.generatePdfBytes()`
→ `Printing.layoutPdf()` or `Printing.sharePdf()`

### Platform confirmation

- Print settings UI is shared Flutter UI across Web, iOS, Android, and macOS.
- The currently active setlist preview/export path is also shared across all four platforms through `SetlistPdfPreviewScreen` + `SetlistPrintService.generatePdfBytes()`.
- A separate platform-specific path still exists in `lib/features/setlists/services/setlist_print_handler.dart` (`HTML/window.print()` on web, PDF on native), but no current setlist call site references it. It appears to be legacy/unused for this feature entry point.

### Relevant current behavior

- `SetlistSong` already exposes `musicalKey` from `songs.musical_key`; no repository or controller work is needed to fetch the value for printing.
- `PrintTemplate` currently persists `showTuning`, `showCapo`, `showBpm`, `showNotes`, and `showPauses`, plus per-section font sizes.
- `PrintOptionsBottomSheet._buildSection(...)` requires both a toggle and a font-size slider for each visible metadata section. A new first-class Key section cannot match the existing UI pattern cleanly without its own font-size field.
- `SetlistPrintService.generatePrintHtml(...)` and `_buildSongRow(...)` currently render inline metadata on the right side for tuning/BPM, render capo inline with the title, and omit notes/tuning/BPM when source data is empty.
- `bands.last_used_print_template_id` is already wired through `PrintTemplateRepository` and should continue to work unchanged as long as the template row shape remains compatible.

### Defaults confirmed from existing migrations

Existing display-toggle defaults on `print_templates`:

- `show_capo`: `true`
- `show_bpm`: `true`
- `show_notes`: `false`
- `show_tuning`: `true`
- `show_pauses`: `true`

The new `show_key` column must match the existing metadata-toggle pattern and default to `true`.

## 6. Proposed Solution

Implement the feature as an additive extension of the existing print-template system.

### Required changes

1. Add `show_key BOOLEAN NOT NULL DEFAULT true` to `public.print_templates` in a new timestamp-named migration.
2. Add `key_font_size DOUBLE PRECISION NOT NULL DEFAULT 14.0 CHECK (key_font_size >= 14.0 AND key_font_size <= 36.0)` in the same migration.
3. Extend `PrintTemplate` to parse, store, serialize, compare, and copy both `showKey` and `keyFontSize`.
4. Add a new `Key` section to `PrintOptionsBottomSheet`, styled with the same `_buildSection(...)` pattern as the existing metadata toggles.
5. Render musical key in `SetlistPrintService` when `template.showKey` is enabled and `song.musicalKey` is non-null/non-empty.
6. Keep key rendering inline in the song metadata lane rather than introducing any new grouping mode. Grouped/inline tuning behavior remains tuning-only.
7. Ensure separators are emitted only between visible metadata tokens so songs without a key do not produce dangling separators.
8. Update `docs/reference/architecture/database_schema.md` to document the new `print_templates` columns.

### Rendering rules

- When `showKey == false`: omit key entirely.
- When `showKey == true` and `song.musicalKey` is null or empty: omit key entirely.
- When `showKey == true` and `song.musicalKey` has a value: render it in the same right-side metadata lane used for inline tuning/BPM today.
- Key rendering must not change grouped tuning dividers, capo rendering, note rendering, song numbering, or pause rendering.

### Why `key_font_size` is included

Although the user explicitly called out the new boolean column, the current print settings UI architecture treats each printable metadata section as a toggle plus its own font-size control. Reusing `tuning_font_size` for key would couple two independent settings, and creating a toggle-only exception would break the existing section pattern. Adding `key_font_size` is the smallest way to preserve the current UI contract without refactoring the sheet.

## 7. Database Impact

Migration: `required`

### Migrations

- `print_templates`: `affected`.
- New migration required to add `show_key` and `key_font_size`.
- Existing rows will receive additive defaults through the migration; no manual backfill table sweep is required.

### RLS

- `unaffected`.
- Existing table policies already authorize row access by band membership and do not need to change for additive columns.

### RPCs

- `unaffected`.
- No RPC signatures or behaviors are involved in this feature.

### Triggers

- `unaffected`.
- Existing `updated_at` trigger on `print_templates` remains sufficient.

### `bands.last_used_print_template_id`

- `unaffected`.
- The last-used template pointer continues to work as-is because the template primary key and repository save/load flow do not change.

## 8. Flutter Architecture Changes

- `PrintTemplate` model: add `showKey` and `keyFontSize` fields, defaults, Supabase mapping, `copyWith`, equality, and hash support.
- `PrintOptionsBottomSheet`: add a `Key` configuration section using the existing section builder.
- `SetlistPrintService`: extend both HTML and PDF render branches inside the shared service file so exported output stays aligned anywhere that file is used.
- No provider, controller, repository query, or navigation changes are required.

## 9. Files to Create

| File                                                                     | Justification                                                                                    |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| `supabase/migrations/20260719000000_add_show_key_to_print_templates.sql` | Additive schema change for `show_key` and `key_font_size`. Use a timestamp-named migration file. |

## 10. Files to Modify

| File                                                            | What changes                                                                                                                                           |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/models/print_template.dart`              | Add `showKey` / `keyFontSize` defaults, Supabase parsing, insert/update JSON, `copyWith`, equality, and hash coverage.                                 |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart` | Add a new Key section using `_buildSection(...)`, persist `showKey` / `keyFontSize`, and place it adjacent to the other song-metadata display toggles. |
| `lib/features/setlists/services/setlist_print_service.dart`     | Add key rendering to both HTML and PDF output branches, using null/empty guards and separator-safe inline metadata assembly.                           |
| `docs/reference/architecture/database_schema.md`                | Update the `print_templates` section to document `show_key` and `key_font_size`.                                                                       |

## 11. Files Off-Limits

| File                                                        | Reason                                                                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_repository.dart`             | Already fetches `musical_key`; oversized file and unrelated to print-template persistence.                   |
| `lib/features/setlists/setlist_detail_screen.dart`          | Existing print entry point already routes into `PrintOptionsBottomSheet`; no new wiring is needed.           |
| `lib/features/setlists/print_template_repository.dart`      | Uses `select()` plus model serialization; additive field support belongs in the model, not repository logic. |
| `lib/features/setlists/services/setlist_print_handler.dart` | Legacy unused path for the current setlist print entry point; do not expand scope into handler wiring.       |
| `lib/features/setlists/services/setlist_print_web.dart`     | Legacy wrapper over `generatePrintHtml(...)`; behavior stays aligned via shared service changes only.        |
| `lib/features/setlists/services/setlist_print_stub.dart`    | No interface change is required for this feature.                                                            |

## 12. System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | unaffected |
| Setlists / Catalog                     | affected   |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | affected   |

## 13. Regression Risk

`MEDIUM`

Rationale: the schema change is additive and localized, but the renderer change affects shared print/export output across all supported platforms. Risk is concentrated in metadata layout/separator behavior and template persistence rather than auth, routing, or business logic.

## 14. Engineer Task Breakdown

1. Create a timestamp-named Supabase migration that adds `show_key` and `key_font_size` to `public.print_templates`, matching the established defaults and font-size constraint range.
2. Extend `PrintTemplate` so the new fields round-trip cleanly for defaults, fetched templates, inserts, updates, and `copyWith` usage.
3. Add a `Key` section to `PrintOptionsBottomSheet` using the existing `_buildSection(...)` pattern and persist user edits into `_current`.
4. Update `SetlistPrintService.generatePrintHtml(...)` so key appears only when enabled and present, using separator-safe metadata assembly.
5. Update `SetlistPrintService` PDF song-row rendering with the same enable/presence rules and independent `keyFontSize` styling.
6. Update `docs/reference/architecture/database_schema.md` to note the new `print_templates` columns.
7. Validate that existing saved-template selection and `bands.last_used_print_template_id` behavior still work without additional repository changes.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

Run these against the current database before applying the new migration.

```sql
-- PRE-DEPLOY TEST 1:
-- Confirm the current show_* defaults so the new show_key default matches the existing pattern.
SELECT
  column_name,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'print_templates'
  AND column_name IN (
    'show_capo',
    'show_bpm',
    'show_notes',
    'show_tuning',
    'show_pauses'
  )
ORDER BY ordinal_position;
```

```sql
-- PRE-DEPLOY TEST 2:
-- Confirm the new columns do not already exist.
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'print_templates'
  AND column_name IN ('show_key', 'key_font_size');
```

```sql
-- PRE-DEPLOY TEST 3:
-- Confirm song key data already exists at the schema level and can be used by the renderer.
SELECT
  EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'songs'
      AND column_name = 'musical_key'
  ) AS songs_has_musical_key,
  COUNT(*) FILTER (WHERE musical_key IS NOT NULL AND musical_key <> '') AS songs_with_keys
FROM public.songs;
```

Flutter-side pre-deploy verification:

- Confirm `PrintOptionsBottomSheet` currently loads/saves templates through `PrintTemplate` only, so model-field additions are sufficient.
- Confirm no current setlist call site uses `SetlistPrintHandler`, to avoid unnecessary implementation spread.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

Function verification: not applicable. This migration adds columns only and does not create or replace any SQL functions.

```sql
-- POST-DEPLOY TEST 1:
-- Verify the new columns exist with the expected type/default/nullability.
SELECT
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'print_templates'
  AND column_name IN ('show_key', 'key_font_size')
ORDER BY ordinal_position;
```

```sql
-- POST-DEPLOY TEST 2:
-- Integration test using a real band FK. Wrap in a transaction and roll back.
BEGIN;

WITH target_band AS (
  SELECT id
  FROM public.bands
  ORDER BY created_at
  LIMIT 1
), inserted_template AS (
  INSERT INTO public.print_templates (
    band_id,
    name,
    tuning_display,
    show_capo,
    show_bpm,
    show_notes,
    show_tuning,
    show_pauses,
    show_song_numbers,
    show_header,
    show_band_name,
    show_page_numbers,
    base_font_size,
    number_font_size,
    header_font_size,
    band_name_font_size,
    bpm_font_size,
    tuning_font_size,
    capo_font_size,
    notes_font_size,
    pause_font_size,
    line_spacing,
    paper_size,
    column_count
  )
  SELECT
    id,
    'architect-show-key-verification',
    'grouped',
    true,
    true,
    false,
    true,
    true,
    true,
    true,
    true,
    true,
    18.0,
    18.0,
    28.0,
    16.0,
    16.0,
    14.0,
    14.0,
    14.0,
    16.0,
    1.0,
    'letter',
    1
  FROM target_band
  RETURNING id, show_key, key_font_size
)
SELECT * FROM inserted_template;

ROLLBACK;
```

```sql
-- POST-DEPLOY TEST 3:
-- Integration test for persistence of explicit values. Uses a real band FK and rolls back.
BEGIN;

WITH target_band AS (
  SELECT id
  FROM public.bands
  ORDER BY created_at
  LIMIT 1
), inserted_template AS (
  INSERT INTO public.print_templates (
    band_id,
    name,
    tuning_display,
    show_key,
    key_font_size,
    show_capo,
    show_bpm,
    show_notes,
    show_tuning,
    show_pauses,
    show_song_numbers,
    show_header,
    show_band_name,
    show_page_numbers,
    base_font_size,
    number_font_size,
    header_font_size,
    band_name_font_size,
    bpm_font_size,
    tuning_font_size,
    capo_font_size,
    notes_font_size,
    pause_font_size,
    line_spacing,
    paper_size,
    column_count
  )
  SELECT
    id,
    'architect-show-key-explicit-values',
    'inline',
    false,
    22.0,
    true,
    true,
    false,
    true,
    true,
    true,
    true,
    true,
    true,
    18.0,
    18.0,
    28.0,
    16.0,
    16.0,
    14.0,
    14.0,
    14.0,
    16.0,
    1.0,
    'letter',
    1
  FROM target_band
  RETURNING id
)
SELECT show_key, key_font_size
FROM public.print_templates
WHERE id = (SELECT id FROM inserted_template);

ROLLBACK;
```

```sql
-- POST-DEPLOY TEST 4:
-- Production verification query: ensure no invalid data exists after deployment.
SELECT
  COUNT(*) FILTER (WHERE show_key IS NULL) AS null_show_key_rows,
  COUNT(*) FILTER (WHERE key_font_size IS NULL) AS null_key_font_size_rows,
  COUNT(*) FILTER (WHERE key_font_size < 14.0 OR key_font_size > 36.0) AS out_of_range_key_font_rows
FROM public.print_templates;
```

Flutter-side post-deploy verification:

- Open print options on Web, iOS, Android, and macOS and confirm the new Key section appears with the same section styling as the existing metadata toggles.
- Save a template with `Show Key` on, reload it, and confirm both the toggle state and key font size persist.
- Save a second template with `Show Key` off, mark it last-used, reopen print options, and confirm the correct template is restored through `bands.last_used_print_template_id`.
- Preview/share/print a setlist containing songs with mixed key presence and confirm keys appear only for songs that actually have a value.
- Confirm no extra separators appear when key is hidden or absent.

## 16. QA Regression Areas

- Primary: `Show Key` toggle appears in print settings, matches existing section styling, and persists per saved template.
- Printed/exported setlist output includes key only when enabled and only for songs with non-empty `musicalKey`.
- Tuning grouped mode still renders tuning dividers correctly while key remains an inline metadata token.
- Inline metadata separators remain correct for all combinations of key/tuning/BPM visibility.
- Existing toggles for capo, BPM, notes, tuning, and pauses retain prior behavior.
- `bands.last_used_print_template_id` still restores the expected saved template after reopening print options.
- Cross-platform coverage: Web, iOS, Android, and macOS preview/export paths.

## 17. Rollout / Migration Strategy

1. Apply the additive schema migration first.
2. Ship the Flutter changes that understand the new columns.
3. Existing templates should inherit `show_key = true` and `key_font_size = 14.0` automatically from the migration defaults.
4. No RPC deployment, edge-function deployment, or data backfill job is required.

## 18. Out of Scope

- Changing how musical keys are stored or edited on songs.
- Revisiting the prior `update_song_metadata` key-clearing fix.
- Refactoring the unused `SetlistPrintHandler` entry point or re-wiring the setlist UI to use it.
- Introducing grouped-by-key print behavior or any new print-layout abstraction beyond this additive toggle/size support.
- Opportunistic cleanup in oversized setlist files.
