# QA_REPORT.md — Setlist Print Layout Options with Saved Templates

---

## Feature Slug

`feature/setlist-print-layout-options`

## Feature Title

Setlist Print Layout Options with Saved Templates

---

## Validation Summary

QA validation performed via code-path analysis on branch `feature/setlist-print-layout-options`. All implementation artifacts were inspected against the Architect plan. Two specific deviations from the Architect plan were identified that require correction before approval.

**Validation method:** Code-path analysis only. No runtime, simulator, or device testing was performed.

---

## Architect Scope Review

The Architect plan specifies 10 tasks covering:

- Database migration for `print_templates` table + `bands` column
- `PrintTemplate` model with validation
- `PrintTemplateRepository` with 6 CRUD methods
- Set grouping logic (`SetGroup` + `groupItemsBySets()`)
- Print handler signature update
- PDF print service rewrite (template-driven)
- HTML print service rewrite (template-driven)
- Print options bottom sheet UI
- `SetlistDetailScreen._handlePrint()` update
- Catalog print compatibility

---

## Implementation Review (All 10 Tasks)

### Task 1: Database Migration — PASS ✅

- File: `supabase/migrations/20260322100000_print_templates.sql` (71 lines)
- `print_templates` table with all required columns
- CHECK constraints: `tuning_display`, `paper_size`, `column_count`, `base_font_size` — all present and correct
- `updated_at` trigger function and trigger (BEFORE UPDATE FOR EACH ROW) — matches 20260109_notifications.sql convention
- INDEX on `print_templates(band_id)` — present
- `bands.last_used_print_template_id UUID REFERENCES print_templates(id) ON DELETE SET NULL` — present
- RLS enabled with band_members join policy (not self-referencing) — correct
- No `is_last_used` boolean column — confirmed absent

### Task 2: PrintTemplate Model — PASS ✅

- File: `lib/features/setlists/models/print_template.dart` (180 lines)
- All fields match plan: id, bandId, name, tuningDisplay, showCapo, showBpm, showNotes, showSongNumbers, showHeader, showPageNumbers, baseFontSize, paperSize, columnCount, createdAt, updatedAt
- No `isLastUsed` field — confirmed absent
- `defaultTemplate(bandId)` returns: grouped tuning, show_bpm=true, show_capo=true, show_notes=false, 18pt font, letter paper, column_count=1 — correct
- `baseFontSize` clamped to [14.0, 24.0] in `fromSupabase()`, `copyWith()`, `toInsertJson()`, `toUpdateJson()` — confirmed in all four methods
- `fromSupabase()`, `toInsertJson()`, `toUpdateJson()`, `copyWith()` all present

### Task 3: PrintTemplateRepository — PASS ✅

- File: `lib/features/setlists/print_template_repository.dart` (100 lines)
- All 6 required methods present: `fetchTemplates`, `createTemplate`, `updateTemplate`, `deleteTemplate`, `setLastUsed`, `getLastUsedTemplateId`
- `setLastUsed()` performs single atomic UPDATE on bands row only — confirmed
- `getLastUsedTemplateId()` returns null when unset or deleted — confirmed

### Task 4: Set Grouping Logic — PASS ✅

- `SetGroup` class defined in `setlist_print_service.dart` with `setNumber` and `items` fields
- `groupItemsBySets()` splits on Set Break markers, assigns sequential set numbers
- Set Break markers are not included in output groups — confirmed
- Single group with no breaks returns setNumber=1, no "Set N" label printed — confirmed

### Task 5: Print Handler Signature — PASS ✅

- `SetlistPrintHandler.print()` accepts: `setlistName`, `items` (List<SetlistItem>), `template` (PrintTemplate), optional `bandName`, `gigDate`, `venue`
- Platform dispatch passes all parameters through
- `SetlistPrintWeb` and stub signatures match

### Task 6: PDF Print Service Rewrite — FAIL ❌ (2 issues)

- **Issue 1 — Font reduction loop missing:** The Architect plan requires: "If set overflows, reduce font incrementally (step 0.5pt) until fit or floor reached, then overflow naturally." No font reduction loop exists in `_buildPdfDocument()`. All content is rendered at the base font size and passed to `pw.MultiPage` without per-set page-fitting logic.
- **Issue 2 — Song numbering is global, not per-set:** `songNumber` counter (line 462) increments continuously across all sets. The Architect plan specifies "per-set sequential numbers." The counter should reset to 0 at the start of each set group.
- Template-driven font sizes, paper size, columns, header, page numbers — all correct
- Two-column layout with `_FullWidthMarker` pattern — correct (see deviation assessment below)
- Tuning display modes (grouped/inline) — correct
- Pause rendering (bold, smaller font, outlined border) — correct
- `generatePdfBytes()` preserved — confirmed at line 63

### Task 7: HTML Print Service Rewrite — FAIL ❌ (1 issue)

- **Issue — Song numbering is global, not per-set:** Same issue as PDF path. `songNumber` counter (line 129) is never reset per set.
- CSS `@page` size from template — correct
- `column-count` CSS — correct
- `column-span: all` for set labels, pause rows, headers — confirmed
- All user content escaped via `_escapeHtml()` — confirmed (10 call sites)
- Header null handling: null fields omitted entirely — correct
- Page numbers via `@bottom-center { content: counter(page); }` — correct

### Task 8: Print Options Bottom Sheet — PASS ✅

- File: `lib/features/setlists/widgets/print_options_bottom_sheet.dart` (536 lines)
- `PrintOptionsBottomSheet.show()` static method returns `PrintTemplate?` — correct
- Template picker with DropdownButton ("Default" + saved templates) — correct
- New Template / Delete Template actions — correct
- Toggle sections: Tuning Display, Capo, BPM, Notes, Song Numbers, Header, Page Numbers — all present
- Font size slider bounded [14.0, 24.0] with `pt` label — confirmed
- Paper Size segmented control (Letter/A4) — correct
- Columns segmented control (1/2) — correct
- Print button (FilledButton, rose accent `AppColors.primary`) — correct
- Save Template button — correct
- Loads templates and reads `getLastUsedTemplateId` on open — confirmed
- Falls back to `defaultTemplate` when last-used ID is null — confirmed
- Falls back to `defaultTemplate` when deleted template was active — confirmed
- Dark theme tokens: `AppColors.surface`, `AppColors.surfaceElevated`, 48px touch targets, `Spacing.buttonRadius` — confirmed
- `_nameController` disposed in `dispose()` — confirmed

### Task 9: SetlistDetailScreen.\_handlePrint() — PASS ✅

- `_handlePrint()` is now `async`
- Reads active band via `activeBandProvider` — correct
- Shows `PrintOptionsBottomSheet.show(context, bandId: band.id)` — correct
- `mounted` guard after async gap — confirmed
- Passes `state.items`, template, `bandName: band.name` to handler — correct
- `gigDate` and `venue` not passed (default to null) — correct per plan

### Task 10: Catalog Print Compatibility — PASS ✅

- When `state.isCatalog`, converts `state.songs` to `List<SetlistItem>` wrappers (type: song, no breaks) — confirmed
- `state.isCatalog` exists as computed property on `SetlistDetailState` — confirmed (`bool get isCatalog => setlistName == kCatalogSetlistName`)
- No set grouping occurs (no Set Break items in converted list) — correct

---

## Files Verified

### Created Files (4)

| File                                                            | Lines | Status      |
| --------------------------------------------------------------- | ----- | ----------- |
| `supabase/migrations/20260322100000_print_templates.sql`        | 71    | ✅ Verified |
| `lib/features/setlists/models/print_template.dart`              | 180   | ✅ Verified |
| `lib/features/setlists/print_template_repository.dart`          | 100   | ✅ Verified |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart` | 536   | ✅ Verified |

### Modified Files (5)

| File                                                        | Status            |
| ----------------------------------------------------------- | ----------------- |
| `lib/features/setlists/services/setlist_print_handler.dart` | ✅ Verified       |
| `lib/features/setlists/services/setlist_print_service.dart` | ❌ 2 issues found |
| `lib/features/setlists/services/setlist_print_stub.dart`    | ✅ Verified       |
| `lib/features/setlists/services/setlist_print_web.dart`     | ✅ Verified       |
| `lib/features/setlists/setlist_detail_screen.dart`          | ✅ Verified       |

All files are within the Architect plan's Section 9 (create) and Section 10 (modify) lists. No off-limits files were modified.

---

## Feature Validation Result (Code-Path Analysis)

### PRINT TEMPLATES (Task 2 / Task 3 / Task 8)

- [x] PrintTemplate has no `isLastUsed` field
- [x] `PrintTemplate.defaultTemplate()` returns: grouped tuning, show_bpm=true, show_capo=true, show_notes=false, 18pt font, letter paper, column_count=1
- [x] `baseFontSize` clamped to [14.0, 24.0] in `fromSupabase()`, `copyWith()`, `toInsertJson()`, `toUpdateJson()`
- [x] `PrintTemplateRepository.setLastUsed()` performs single UPDATE on bands row only
- [x] `PrintTemplateRepository.getLastUsedTemplateId()` returns null when unset or deleted
- [x] Bottom sheet falls back to `defaultTemplate()` when last-used ID is null or not found
- [x] Bottom sheet falls back to `defaultTemplate()` when user deletes currently selected template
- [x] Font size slider bounded to [14.0, 24.0]

### SET GROUPING (Task 4 / Task 6)

- [x] `groupItemsBySets()` splits items on Set Break markers, assigns sequential setNumbers
- [x] No Set Breaks → single group, no "Set N" label printed
- [x] Set Break markers not rendered in print output
- [x] "Set N" labels printed when multiple sets exist

### PAUSE RENDERING (Task 6 / Task 7)

- [x] Pause rows render with bold text, smaller font (0.89× base), outlined rectangle border
- [x] Pause text uses `item.specialItem?.displayLabel` (not hardcoded)

### TUNING DISPLAY (Task 6 / Task 7)

- [x] Grouped mode: tuning header above first song in group, not repeated until change
- [x] Inline mode: tuning label right-aligned on every song row

### TWO-COLUMN LAYOUT (Task 6 / Task 7) — CRITICAL

- [x] PDF: "Set N" labels span both columns via `_FullWidthMarker` pattern
- [x] PDF: Pause rows span both columns via `_FullWidthMarker` pattern
- [x] PDF: Song rows participate in column flow via `_buildTwoColumnLayout` buffer
- [x] HTML: "Set N" labels use `column-span: all`
- [x] HTML: Pause rows use `column-span: all`
- [x] `_FullWidthMarker` produces correct two-column spanning behavior (verified in `_buildTwoColumnLayout`)

### HEADER NULL HANDLING (Task 6 / Task 7 / Task 9) — CRITICAL

- [x] PDF: null fields omitted via null/isEmpty checks — no blank lines or placeholders
- [x] HTML: null fields omitted via null/isEmpty checks — no blank lines or placeholders
- [x] `SetlistDetailScreen` passes `gigDate=null` and `venue=null` (not passed → default null)
- [x] Both paths handle null fields identically

### FONT SIZE AND PAGE FITTING (Task 6)

- [ ] **FAIL — Font reduction loop not implemented.** No code steps down in 0.5pt increments to fit sets on one page. All content renders at base font size and overflows to next page via `pw.MultiPage` default behavior.
- [x] `generatePdfBytes()` exists and was not removed

### METADATA TOGGLES (Task 6 / Task 7)

- [x] Capo: extracted via `parseCapoTuning()`, displayed only when `show_capo=true` and capo value exists
- [x] BPM: displayed only when `show_bpm=true`
- [x] Notes: displayed as secondary line below song title only when `show_notes=true`
- [ ] **FAIL — Song numbers: global sequential, not per-set sequential.** Counter increments across all sets without resetting.
- [x] Page numbers: rendered only when `show_page_numbers=true`

### CATALOG COMPATIBILITY (Task 10)

- [x] Catalog songs converted to `List<SetlistItem>` wrappers (type: song, no breaks)
- [x] `state.isCatalog` is a valid property on `SetlistDetailState`
- [x] No set grouping occurs in catalog path

---

## Completeness Check

| Task    | Description                         | Status                                                                       |
| ------- | ----------------------------------- | ---------------------------------------------------------------------------- |
| Task 1  | Database Migration                  | ✅ Complete                                                                  |
| Task 2  | PrintTemplate Model                 | ✅ Complete                                                                  |
| Task 3  | PrintTemplateRepository             | ✅ Complete                                                                  |
| Task 4  | SetGroup + groupItemsBySets         | ✅ Complete                                                                  |
| Task 5  | Print Handler Signature             | ✅ Complete                                                                  |
| Task 6  | PDF Print Service Rewrite           | ❌ Incomplete — missing font reduction loop; song numbers global not per-set |
| Task 7  | HTML Print Service Rewrite          | ❌ Incomplete — song numbers global not per-set                              |
| Task 8  | PrintOptionsBottomSheet             | ✅ Complete                                                                  |
| Task 9  | SetlistDetailScreen.\_handlePrint() | ✅ Complete                                                                  |
| Task 10 | Catalog Print Compatibility         | ✅ Complete                                                                  |

---

## Regression Check

### Affected Systems — Verified Correct

- [x] Setlists print flow — complete replacement of handler/service pipeline
- [x] All four platforms — PDF and HTML paths both changed with correct signatures

### Unaffected Systems — Verified Untouched

- [x] `SetlistDetailController` — state shape unchanged; items getter untouched
- [x] `SetlistRepository` — not modified
- [x] `SpecialItemRepository` — not modified
- [x] `SetlistSong` model — not modified
- [x] `SetlistItem` model — not modified
- [x] `SpecialItem` model — not modified
- [x] Gig feature — no changes
- [x] Rehearsals feature — no changes
- [x] Auth / session — no changes
- [x] Routing — no new routes, no navigation changes
- [x] `lib/main.dart` — not touched

---

## Regression Risk Level

**MEDIUM** — Confirmed. Matches Architect plan assessment.

Rationale:

- Print services are fully rewritten (not extended), changing all platform output
- New database table + RLS policy adds migration dependency
- No auth, session, routing, init order changes
- No mutations to existing data models or state shape
- Template persistence is additive (new table + one nullable column)
- All changes are within the setlist print feature boundary

---

## Database Safety Review

| Check                                                            | Result |
| ---------------------------------------------------------------- | ------ |
| `print_templates` table with all required columns                | ✅     |
| CHECK constraint: `tuning_display IN ('grouped', 'inline')`      | ✅     |
| CHECK constraint: `paper_size IN ('letter', 'a4')`               | ✅     |
| CHECK constraint: `column_count IN (1, 2)`                       | ✅     |
| CHECK constraint: `base_font_size >= 14.0 AND <= 24.0`           | ✅     |
| `updated_at` trigger function created                            | ✅     |
| Trigger fires BEFORE UPDATE FOR EACH ROW                         | ✅     |
| Trigger pattern matches 20260109_notifications.sql convention    | ✅     |
| INDEX on `print_templates(band_id)`                              | ✅     |
| `bands.last_used_print_template_id` UUID FK ON DELETE SET NULL   | ✅     |
| RLS enabled                                                      | ✅     |
| RLS policy uses `band_members` join (not self-referencing)       | ✅     |
| No privilege escalation                                          | ✅     |
| No unintended cascade (CASCADE on band_id, SET NULL on bands FK) | ✅     |
| No `is_last_used` boolean column on `print_templates`            | ✅     |

---

## Analyzer Results

```
flutter analyze → No issues found! (0 errors, 0 warnings)
```

---

## Test Results

Not run — no tests required per Architect plan. No tests were added (consistent with project convention).

---

## Diff Safety Review

- [x] No secrets, API keys, or credentials
- [x] No hardcoded environment values
- [x] No unrelated refactors (minor dart format line-wrap changes in modified file are acceptable)
- [x] No accidental deletions (`generatePdfBytes()` preserved)
- [x] No debug artifacts (no print(), debugPrint(), TODO, FIXME, commented-out blocks in new/modified print code)
- [x] No off-limits files modified
- [x] Old `TuningBlock` class and `groupSongsByTuning()` removed — confirmed absent
- [x] Old hardcoded formatting constants replaced by template-driven values
- [x] `_escapeHtml()` preserved in HTML service (11 call sites)

---

## Known Deviations Assessment

### 1. `_FullWidthMarker` Pattern — APPROVED ✅

The Engineer introduced a private `_FullWidthMarker` class extending `pw.StatelessWidget` in `setlist_print_service.dart` (line ~891). This was not named in the Architect plan but implements the plan's requirement for "full-width container outside column context."

**Behavior verified:** `_buildTwoColumnLayout()` iterates all widgets. When it encounters a `_FullWidthMarker`, it flushes the column buffer (emitting buffered song rows as a two-column `pw.Row`) and emits the marker's child at full page width. Set labels (via `_buildSetLabel` → `_fullWidth()`) and Pause rows (via `_buildPauseRow` → `_fullWidth()`) are both wrapped, producing the specified behavior: they span both columns while song rows participate in column flow.

**Verdict:** Private implementation detail that correctly produces the Architect-specified behavior. No structural deviation.

### 2. File Size Overruns — INFORMATIONAL (Not Blockers)

**`setlist_print_service.dart` — 898 lines** (guideline: 500):
The file was already ~596 lines before the rewrite. The Architect plan specified "Major rewrite: lines 1–600." The file now contains both PDF and HTML generation paths, set grouping logic, and all widget builder methods. While large, the file has a single clear responsibility (print formatting), and all methods are cohesive to that concern. The alternative — splitting PDF and HTML into separate files — would require duplicating shared types (`SetGroup`, `_FullWidthMarker`, tuning/HTML utilities) or creating an additional shared file, which adds complexity without improving maintainability at this scope. **Assessment: not a blocker.** The file is large but maintainable, with clear section markers and no cross-concern responsibilities.

**`print_options_bottom_sheet.dart` — 536 lines** (guideline: 350 for container widgets):
Size is driven by the number of distinct configuration sections required by the Architect plan (template picker, CRUD actions, 6 toggle groups, slider, 2 segmented controls, 2 action buttons). Extracting sub-widgets would split a cohesive interaction flow without meaningful reuse. **Assessment: not a blocker.** The size is a direct consequence of the feature's specification scope.

---

## Issues Found

### Issue 1: Font Reduction Loop Not Implemented (Task 6)

**Severity:** REQUIRES CHANGES

**Architect requirement (Task 6):** "Attempt to keep entire set on one page using `pw.Wrap` / `pw.Partition`. If set overflows, reduce font incrementally (step 0.5pt) until fit or floor reached, then overflow naturally."

**Architect verification checklist:** "Font reduction loop steps down in 0.5pt increments until set fits or 14pt floor. Below 14pt floor, set overflows naturally to next page."

**Observed:** No font reduction logic exists. `_buildPdfDocument()` builds all widgets at the base font size and passes them to `pw.MultiPage`, which handles overflow with default page-break behavior. There is no per-set measurement, no font stepping, and no 14pt floor enforcement in the page-fitting context.

**Location:** `lib/features/setlists/services/setlist_print_service.dart`, `_buildPdfDocument()` method (lines ~427–540).

### Issue 2: Song Numbers Are Global Sequential, Not Per-Set Sequential (Task 6 / Task 7)

**Severity:** REQUIRES CHANGES

**Architect requirement (Task 6):** "Song numbering: per-set sequential numbers, toggleable"

**Architect verification checklist:** "Song numbers: per-set sequential, displayed only when show_song_numbers=true"

**Observed:** In both PDF path (line 462: `int songNumber = 0;`) and HTML path (line 129: `int songNumber = 0;`), the `songNumber` counter is initialized once before the outer set-group loop and increments continuously across all sets. It is never reset when a new set group begins.

**Fix required:** Reset `songNumber = 0` at the beginning of each set group iteration in both the PDF and HTML generation paths.

**Location:**

- `lib/features/setlists/services/setlist_print_service.dart` line 462 (PDF path)
- `lib/features/setlists/services/setlist_print_service.dart` line 129 (HTML path)

---

## Final Verdict

### **APPROVED** ✅

All 10 Architect tasks implemented correctly. All original issues resolved in amendment rounds 1 and 2. Database safety verified. Analyzer clean. No regressions detected.

---

## Re-Validation — Amendment Rounds 1 and 2

**Date:** 2026-03-22
**Validation method:** Code-path analysis only.

This section validates only the four items changed in amendment rounds 1 and 2. All original PASS items from the initial validation are unchanged and remain passing.

### Item 1 — Per-set Song Number Reset (QA Round 1, Fix 2): PASS ✅

**PDF path:** `int songNumber = 0;` is declared **inside** the `for (final group in setGroups)` loop, at the top of each group iteration (line ~482). Resets to 0 at each set boundary.

**HTML path:** `int songNumber = 0;` is declared **inside** the `for (final group in setGroups)` loop, at the top of each group iteration (line ~132). Resets to 0 at each set boundary.

Both paths produce per-set sequential numbering (Set 1: 1,2,3… Set 2: 1,2,3…).

### Item 2 — Font Reduction Loop (QA Round 1, Fix 1): PASS ✅

**A. While loop exists in `_buildPdfDocument()`:** Confirmed. At line ~493:

```
while (estimatedHeight > effectiveHeight && setFontSize - 0.5 >= 14.0) {
  setFontSize -= 0.5;
  estimatedHeight = _estimateSetHeight(group, template, setFontSize, baseFontSize);
}
```

Reduces by 0.5pt per iteration, stops when fit or 14pt floor reached.

**B. `_estimateSetHeight()` exists:** Confirmed as static method (line ~920–958). Uses line count × line height approximation for songs, tuning dividers, pause rows, and notes.

**C. Song rows use `setFontSize` (reduced):** Confirmed. `_buildSongRow(baseFontSize: setFontSize)`, `_buildTuningDivider(tuning, setFontSize)`, `_buildNotesRow(song.notes!, setFontSize)` all receive the potentially-reduced font size.

**D. Set labels and pause rows use `baseFontSize` (not scaled):** Confirmed. `_buildSetLabel(group.setNumber, baseFontSize)` and `_buildPauseRow(item, baseFontSize)` use the original base font size.

### Item 3 — CSS Two-Column Flex Conflict (Code Review Round 1, Fix 1): PASS ✅

`.song-list` in `_generatePrintCss()` has **no** `display: flex` or `flex-direction` properties — it is an empty rule block (`{}`), making it a normal block container compatible with CSS multi-column layout.

When `columnCount == 2`:

- `body` has `column-count: 2; column-gap: 24px;` — confirmed
- `.set-label` has `column-span: all;` — confirmed
- `.pause-row` has `column-span: all;` — confirmed
- `.header`, `.setlist-title`, `.band-name`, `.gig-date`, `.venue`, `.title-divider` all have `column-span: all;` — confirmed

### Item 4 — PDF Two-Column Height Estimation (Code Review Round 1, Fix 2): PASS ✅

`effectiveHeight` variable computed at line ~467:

```
final effectiveHeight = template.columnCount == 2
    ? availableHeight / 2
    : availableHeight;
```

Halves `availableHeight` when `columnCount == 2` (since songs split across two columns, the stacked height per column is approximately half). The font reduction while loop compares `estimatedHeight > effectiveHeight` — confirmed it uses `effectiveHeight`, not `availableHeight`.

### flutter analyze

```
flutter analyze → No issues found! (0 errors, 0 warnings)
```

### Updated Verdict

All 4 re-validation items **PASS**. Combined with all original PASS items from initial validation, the implementation is complete and correct.

**Final Verdict: APPROVED**
