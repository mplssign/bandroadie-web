# ENGINEER_REPORT.md — Setlist Print Layout Options with Saved Templates

**Feature Slug:** `feature/setlist-print-layout-options`
**Branch:** `feature/setlist-print-layout-options`
**Architect Plan:** `docs/features/setlist-print-layout-options/ARCHITECT_PLAN.md`
**Date:** 2026-03-22

---

## 1. Summary of Changes

Implemented configurable print layout options for setlists, replacing the previous hardcoded print system. Users can now control tuning display mode, metadata visibility, font size, paper size, column count, header content, and song numbering. Print templates persist per-band in Supabase and can be saved, named, reused, and deleted.

The print pipeline was rewritten to accept `List<SetlistItem>` (instead of `List<SetlistSong>`), enabling proper rendering of Set Breaks and Pauses. Songs are now grouped by Set Break markers into numbered sets, with Pauses rendered inline.

---

## 2. Files Changed

### New Files (4)

| File                                                            | Lines | Purpose                                                                                                               |
| --------------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260322100000_print_templates.sql`        | 71    | Database migration: `print_templates` table with RLS, `bands.last_used_print_template_id` column, auto-update trigger |
| `lib/features/setlists/models/print_template.dart`              | 180   | `PrintTemplate` model with `fromSupabase()`, `toInsertJson()`, `toUpdateJson()`, `copyWith()`, `defaultTemplate()`    |
| `lib/features/setlists/print_template_repository.dart`          | 100   | Supabase CRUD repository: fetch, create, update, delete templates; set/get last-used template ID via `bands` table    |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart` | 536   | Bottom sheet UI: template picker dropdown, CRUD actions, toggle sections for all options, save/print actions          |

### Modified Files (5)

| File                                                        | Lines | Changes                                                                                                                                                                                             |
| ----------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/services/setlist_print_service.dart` | 898   | Full rewrite: `TuningBlock` → `SetGroup`, template-driven PDF + HTML generation, set grouping by Set Break markers, Pause rendering, two-column layout, configurable metadata/header/font/paper     |
| `lib/features/setlists/services/setlist_print_handler.dart` | 58    | Signature updated: `List<SetlistSong>` → `List<SetlistItem>` + `PrintTemplate` + optional `bandName`/`gigDate`/`venue`                                                                              |
| `lib/features/setlists/services/setlist_print_web.dart`     | 53    | Signature updated to match handler; passes all params to `SetlistPrintService.generatePrintHtml()`                                                                                                  |
| `lib/features/setlists/services/setlist_print_stub.dart`    | 27    | Signature updated to match handler                                                                                                                                                                  |
| `lib/features/setlists/setlist_detail_screen.dart`          | 2816  | `_handlePrint()` now shows `PrintOptionsBottomSheet`, passes `state.items` + template. Catalog compatibility: converts `songs` to `SetlistItem` wrappers when `state.isCatalog`. New imports added. |

---

## 3. Task-by-Task Implementation Notes

### Task 1: Database Migration

Created `supabase/migrations/20260322100000_print_templates.sql`:

- `print_templates` table with all columns per plan (tuning_display, show_capo, show_bpm, show_notes, show_song_numbers, show_header, show_page_numbers, base_font_size with CHECK 14–24, paper_size with CHECK letter/a4, column_count with CHECK 1/2)
- `updated_at` auto-update trigger following notification_preferences pattern
- `bands.last_used_print_template_id` FK with ON DELETE SET NULL
- RLS policy: band members only (via `band_members` join)
- Index on `band_id` for query performance

### Task 2: PrintTemplate Model

- All fields match migration schema; `baseFontSize` clamped to `[14.0, 24.0]` in `fromSupabase()`, `toInsertJson()`, `toUpdateJson()`, and `copyWith()`
- `defaultTemplate(bandId)` factory returns sensible defaults (grouped tuning, all metadata on, 18pt font, letter paper, 1 column)
- No `isLastUsed` field — tracking is on `bands.last_used_print_template_id`

### Task 3: PrintTemplateRepository

- `fetchTemplates(bandId)` — SELECT with band_id filter, ordered by created_at
- `createTemplate(bandId, template)` — INSERT with upsert:false
- `updateTemplate(template)` — UPDATE by id, returns updated row
- `deleteTemplate(templateId)` — DELETE by id
- `setLastUsed(bandId, templateId)` — single atomic UPDATE on bands row
- `getLastUsedTemplateId(bandId)` — reads `bands.last_used_print_template_id`

### Task 4: Set Grouping Logic

- `SetGroup` class: `setNumber` + `List<SetlistItem> items`
- `groupItemsBySets(List<SetlistItem>)`: iterates items, splits on Set Break markers, assigns sequential set numbers. If no set breaks → single group with setNumber=1.

### Task 5: Refactor Print Handler Signature

- `SetlistPrintHandler.print()` now accepts: `setlistName`, `items` (List<SetlistItem>), `template` (PrintTemplate), optional `bandName`, `gigDate`, `venue`
- Platform dispatch (conditional import) passes all parameters through

### Task 6: Rewrite PDF + HTML Print Service

- **PDF path** (`generatePrintDocument`): Template-driven font sizes (base × scale factors), optional header, set labels when multiple sets, song numbering, tuning display (grouped headers vs inline), BPM/capo/notes conditionals, Pause rows with duration, page numbers, paper size, two-column layout via `_FullWidthMarker` pattern
- **HTML path** (`generatePrintHtml`): CSS `@page` size from template, `column-count` CSS, `column-span: all` for set labels/pauses/headers, all user content escaped via `_escapeHtml()`, responsive print media query

### Task 7: Web + Stub Updates

- `setlist_print_web.dart` and `setlist_print_stub.dart` updated to new signature
- Web implementation passes all params to `SetlistPrintService.generatePrintHtml()`

### Task 8: Print Options Bottom Sheet

- `PrintOptionsBottomSheet.show()` static method returns `PrintTemplate?` via `showModalBottomSheet`
- On open: loads templates + reads `getLastUsedTemplateId` + pre-selects matching template (or default)
- Template picker: `DropdownButton` with "Default" + saved templates
- New/Delete template actions with inline name field
- Toggle sections: Tuning Display (Grouped/Inline segmented control), Capo/BPM/Notes switches, Song Numbers/Header/Page Numbers switches
- Font size: Slider bounded [14.0, 24.0] with live `pt` label
- Paper size: Letter/A4 segmented control
- Columns: 1/2 segmented control
- Print button (filled, rose accent) + optional Save Template button
- Dark theme: `AppColors.surface` background, 48px min touch targets, `Spacing.buttonRadius`

### Task 9: Update SetlistDetailScreen

- `_handlePrint()` now async: reads active band → shows `PrintOptionsBottomSheet` → on confirmed, calls `SetlistPrintHandler.print()` with `state.items`, template, and `bandName`
- Added imports for `PrintOptionsBottomSheet`

### Task 10: Catalog Print Compatibility

- When `state.isCatalog`, converts `state.songs` to `List<SetlistItem>` wrappers (type: song, no set breaks/pauses) before passing to handler
- Uses whatever template the user selects (default or saved) — no set grouping occurs since no Set Break items exist

---

## 4. Architecture Decisions

1. **Last-used tracking on `bands` table** (not `print_templates`): Avoids N-way flag updates. Single column `bands.last_used_print_template_id` with FK ON DELETE SET NULL provides atomic last-used tracking.

2. **`SetGroup` class in print service** (not a separate model file): The grouping is purely a print-time concern — not persisted, not used elsewhere. Keeping it in the service avoids file bloat.

3. **`_FullWidthMarker` pattern for two-column PDF**: Custom `Widget` that Paint ignores but layout recognizes, enabling set labels and pause rows to span both columns in the PDF grid layout.

4. **Template picker as DropdownButton** (not separate screen): The template list is small per-band; a dropdown in the bottom sheet keeps the flow to a single interaction surface.

5. **Catalog compatibility via item conversion** (not separate code path): Converting `songs` → `SetlistItem` wrappers at the call site means the entire print pipeline is unified. No branching inside the service.

---

## 5. Deviations from Architect Plan

1. **`_FullWidthMarker` private widget pattern (minor implementation detail):** The Architect plan specified "use full-width container outside column context" for two-column PDF layout. The implementation introduces `_FullWidthMarker`, a private `pw.StatelessWidget` subclass not named in the plan. It acts as a marker: when `_layoutTwoColumns()` encounters a `_FullWidthMarker` in the widget list, it flushes the current column buffer and emits the marker's child at full page width. Set labels and Pause rows are wrapped via `_fullWidth()` → `_FullWidthMarker`, producing the specified behavior (these elements span both columns). This is a private implementation detail that achieves the plan's stated outcome, not a structural deviation.

All other aspects — file locations, model shapes, API signatures, and UI patterns — match the plan.

---

## 6. Validation

| Check             | Result                                               |
| ----------------- | ---------------------------------------------------- |
| `flutter analyze` | 0 issues                                             |
| `dart format`     | 8 Dart files formatted (4 changed)                   |
| New files created | 4 (migration, model, repository, bottom sheet)       |
| Files modified    | 5 (print service, handler, web, stub, detail screen) |
| No files deleted  | ✓                                                    |
| Feature branch    | `feature/setlist-print-layout-options`               |

### File Size Notes

The following files exceed the Architect's stated size guidelines. These are informational notes for QA, not blockers.

- **`setlist_print_service.dart` — 898 lines** (guideline: 500-line max for Dart files): File was already 596 lines before the rewrite. The Architect plan acknowledged this as a "major rewrite" covering lines 1–600. The rewrite replaced both PDF and HTML generation paths with a single template-driven service, including set grouping, pause rendering, two-column layout logic, and all widget builder methods.

- **`print_options_bottom_sheet.dart` — 536 lines** (guideline: 350-line max for container widgets): New file creation, not a modification. Size is driven by template CRUD UI (dropdown picker, name field, new/delete actions), six toggle sections (tuning display, capo, BPM, notes, song numbers, header, page numbers), font size slider, paper size and column count segmented controls, and save/print action buttons.

### Verification

- **`state.isCatalog`**: Confirmed — exists as a computed property on `SetlistDetailState` (defined in `setlist_detail_controller.dart` as `bool get isCatalog => setlistName == kCatalogSetlistName`). Used extensively throughout `setlist_detail_screen.dart` for Catalog-specific branching.
- **`generatePdfBytes()`**: Preserved per plan — exists at line 63 of `setlist_print_service.dart` after the rewrite. Accepts `setlistName`, `List<SetlistItem>`, `PrintTemplate`, and optional header fields.

---

## 7. Remaining Work / Known Issues

- **Tests:** No tests added in this implementation (consistent with project convention of minimal test coverage). The `SetlistPrintService`, `PrintTemplate` model, and `PrintTemplateRepository` are good candidates for unit tests.
- **Migration deployment:** The SQL migration must be applied to Supabase (production + any staging environments) before the Flutter code is deployed.
- **Gig integration:** `gigDate` and `venue` are accepted by the handler but not yet populated from gig context — the `_handlePrint` call in `SetlistDetailScreen` passes `null` for both. A future task could auto-populate these when printing from a gig-linked setlist.

---

## 8. Amendment — QA Round 1

Two fixes applied to `lib/features/setlists/services/setlist_print_service.dart` only.

### Fix 1: Per-set song number reset (PDF + HTML)

**Problem:** `int songNumber = 0;` was initialized once before the outer set-group loop in both the PDF and HTML generation paths. Songs in Set 2 continued numbering from where Set 1 left off (e.g., 8, 9, 10…) instead of restarting at 1.

**Change — HTML path:** Moved `int songNumber = 0;` and `String? lastTuning;` from before the `for (final group in setGroups)` loop to inside it, at the top of each iteration. Removed the now-unnecessary `lastTuning = null` reset inside the `if (hasMultipleSets)` block (the variable is freshly initialized each iteration).

**Change — PDF path:** Same relocation — `int songNumber = 0;` and `String? lastTuning;` moved inside the set-group loop. Each set now numbers songs starting from 1.

### Fix 2: Per-set font reduction loop (PDF path only)

**Problem:** No font reduction logic existed. The Architect plan required attempting to fit each set on one page by reducing song-level font size in 0.5pt steps down to a 14pt floor.

**Implementation:** Added a per-set font reduction loop in `_buildPdfDocument()` and a new `_estimateSetHeight()` helper method.

- **Available page height** is calculated as page format height minus margins (36pt × 2), minus footer estimate if `showPageNumbers` is enabled.
- **For each set group**, the loop calls `_estimateSetHeight()` at the current `setFontSize`. If the estimate exceeds one page height and `setFontSize - 0.5 >= 14.0`, it reduces by 0.5pt and re-estimates. This repeats until the set fits or the 14pt floor is reached.
- **Below floor**, `pw.MultiPage` handles overflow naturally (no special behavior).
- **Scope of reduction:** Only song rows, tuning dividers, and notes rows use the reduced `setFontSize`. Set labels, pause rows, header, and page numbers remain at `baseFontSize`.

**Measurement approach:** Best-effort estimation using line count × line height. `_estimateSetHeight()` sums per-item height estimates based on font scale factors matching the actual widget margins/padding (song row: `setFontSize × 1.55`, tuning divider: `setFontSize × 2.55`, notes row: `setFontSize × 1.12`, pause row: `baseFontSize × 2.05`). This is an approximation — the pdf package does not expose a pre-render layout measurement API. The estimation is conservative enough to trigger reduction for visually large sets.

### Validation

- `flutter analyze`: **0 issues**
- `dart format`: 1 file formatted, 0 changed (already formatted)
- No deviation from the QA-specified approach was required

---

## 9. Amendment — Code Review Round 1

Two fixes applied to `lib/features/setlists/services/setlist_print_service.dart` only.

### Fix 1: CSS two-column `.song-list` flex conflict

**Bug:** `.song-list` had `display: flex; flex-direction: column`, which creates a new block formatting context that prevents the parent `body`'s `column-count: 2` from flowing content into columns. It also prevented `column-span: all` on `.set-label` and `.pause-row` from working.

**Change:** Removed `display: flex; flex-direction: column;` from the `.song-list` CSS rule in `_generatePrintCss()`. The rule body is now empty (the selector is retained for potential future styling). All child elements are block-level `<div>`s and stack vertically without flexbox. Single-column layout is unaffected.

### Fix 2: PDF two-column height estimation

**Bug:** `_estimateSetHeight()` returns the total stacked height of all songs in a set. In two-column mode, `_buildTwoColumnLayout()` splits songs across two columns, so the actual rendered height is roughly half the estimate. The font reduction loop compared against full `availableHeight`, meaning it almost never triggered for two-column layouts.

**Change:** Added `effectiveHeight` variable in `_buildPdfDocument()` after `availableHeight` is calculated. When `template.columnCount == 2`, `effectiveHeight` is `availableHeight / 2`; otherwise it equals `availableHeight`. The font reduction `while` loop now compares `estimatedHeight > effectiveHeight` instead of `estimatedHeight > availableHeight`. No changes to `_estimateSetHeight()` itself.

### Validation

- `flutter analyze`: **0 issues**
- `dart format`: 1 file formatted, 1 changed

---

## 10. Amendment — macOS Print Entitlement

### Files Modified

- `macos/Runner/DebugProfile.entitlements`
- `macos/Runner/Release.entitlements`

### Change

Added `com.apple.security.print` entitlement (`<true/>`) to both files inside the root `<dict>` block.

### Reason

The `printing` package requires the macOS print entitlement to open the system print dialog. Without it, macOS sandbox blocks printing at the OS level with: "This application does not support printing." This is a platform configuration requirement, not a code bug.

### Deviation Note

These files are outside the Architect plan's defined file scope (`lib/features/setlists/` and `supabase/migrations/` only). The change is required for macOS platform compatibility and does not affect iOS, Android, or web.

### Validation

- `flutter analyze`: **0 issues**
