# ARCHITECT_PLAN.md — Setlist Print Layout Options with Saved Templates

---

## 1. Feature Slug

`feature/setlist-print-layout-options`

**Branch:** `feature/setlist-print-layout-options`
**Docs path:** `docs/features/setlist-print-layout-options/`

---

## 2. Problem Summary

Users currently have no control over how a setlist is formatted when printed. The existing print system (`SetlistPrintHandler` → `SetlistPrintService` / `SetlistPrintWeb`) produces a fixed layout: song titles + BPM grouped by tuning, with hardcoded font sizes, no set grouping by Set Break markers, no Pause rendering, no metadata toggles, no paper size options, and no ability to save or reuse formatting preferences.

Users need:

- Configurable print layout options (tuning display, metadata, font size, columns, paper size, etc.)
- Named print templates that persist and can be reused
- Set grouping driven by Set Break markers with per-set page fitting
- Inline Pause rendering
- Header content options (title, band, date, venue)

---

## 3. Root Cause

**Root Cause:** The print system was designed as a minimal stage-readable output with hardcoded formatting constants. It accepts only `setlistName` + `List<SetlistSong>` — it has no awareness of Set Breaks, Pauses, or any configurable options. No template model, persistence layer, or configuration UI exists.

**Confidence:** HIGH — confirmed by direct inspection of:

- `setlist_print_handler.dart` — `print()` signature takes only `setlistName` and `songs`
- `setlist_print_service.dart` — all formatting constants are private static `const`
- `setlist_detail_screen.dart:1118` — `_handlePrint()` passes `state.songs` (strips out special items)
- No `print_template` table in database
- No print configuration UI anywhere in the codebase

---

## 4. Existing System Analysis

### Current Print Data Flow

```
SetlistDetailScreen._handlePrint()
  → reads state.songs (List<SetlistSong> — songs only, no breaks/pauses)
  → SetlistPrintHandler.print(setlistName, songs)
    → kIsWeb?
      → YES: SetlistPrintWeb.printSetlist() → generates HTML → window.print()
      → NO:  SetlistPrintService.printSetlist() → generates PDF → Printing.layoutPdf()
```

### Current Print Formatting (hardcoded)

| Setting           | Current Value             | Configurable? |
| ----------------- | ------------------------- | ------------- |
| Title font        | 28pt                      | No            |
| Song font         | 18pt                      | No            |
| BPM font          | 16pt                      | No            |
| Tuning label font | 14pt                      | No            |
| Min font scale    | 0.75x                     | No            |
| Page size         | Letter only               | No            |
| Columns           | Single only               | No            |
| Grouping          | By tuning                 | No            |
| Set breaks        | **Ignored** (not in data) | No            |
| Pauses            | **Ignored** (not in data) | No            |
| Song numbering    | Always shown              | No            |
| Header            | Title only                | No            |
| Page numbers      | None                      | No            |
| Key/Capo display  | None                      | No            |
| Notes/Cues        | None                      | No            |

### Current Setlist Data Model

The `SetlistDetailState` already maintains:

- `items: List<SetlistItem>` — ordered list of songs, set breaks, and pauses
- `songs: List<SetlistSong>` — songs only (for backward compat)

Each `SetlistItem` has:

- `type`: `song | set_break | pause`
- `song`: `SetlistSong?` (for songs — includes title, artist, bpm, tuning, notes)
- `specialItem`: `SpecialItem?` (for breaks/pauses — includes type, duration, purposes)

Tuning string encodes capo as `tuningId|capo:N`. There is no separate `key` column on songs — the feature input mentions "Key / Capo" but only capo exists. The plan will surface **capo only** (extracted from tuning string) since there is no key data in the database.

### Platform Print Support

| Platform | Method                  | Package             |
| -------- | ----------------------- | ------------------- |
| Web      | HTML + `window.print()` | `package:web`       |
| iOS      | PDF + system dialog     | `printing: ^5.13.4` |
| macOS    | PDF + system dialog     | `printing: ^5.13.4` |
| Android  | PDF + system dialog     | `printing: ^5.13.4` |

All four platforms are supported by the existing `printing` package.

---

## 5. Proposed Solution

### Overview

1. **Print Template Model** — new Dart model `PrintTemplate` with all configurable options
2. **Print Template Persistence** — new Supabase table `print_templates` scoped to band
3. **Print Template Repository** — new repository for CRUD on templates
4. **Print Options Bottom Sheet** — new UI widget for template selection and option configuration before printing
5. **Refactored Print Services** — `SetlistPrintService` and `SetlistPrintWeb` accept `List<SetlistItem>` + `PrintTemplate` instead of just `List<SetlistSong>`
6. **Set Grouping Logic** — new service method to split items by Set Break markers into set groups
7. **Updated Print Handler** — new signature accepting items + template

### Design Decisions

**Why extend architecture (new model + repository + table)?**
Print templates are per-band persistent data requiring CRUD. This cannot be solved with a localized change — it requires a model, persistence, and UI. This is the minimum architecture to deliver the feature.

**Why not use local storage?**
Templates must sync across devices for band members. Supabase is the system of record (per guardrails). Band isolation requires `band_id` scoping.

**Why a bottom sheet for print options?**
Consistent with existing app patterns (set break creator, pause creator, song details). Quick to invoke, non-blocking, and can display template selection + live preview of options.

---

## 6. Database Impact

### New Table: `print_templates`

```sql
-- ============================================================================
-- MIGRATION: 20260322100000_print_templates.sql
-- ============================================================================

-- 1. CREATE print_templates TABLE
CREATE TABLE IF NOT EXISTS public.print_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  tuning_display TEXT NOT NULL DEFAULT 'grouped'
    CHECK (tuning_display IN ('grouped', 'inline')),
  show_capo BOOLEAN NOT NULL DEFAULT true,
  show_bpm BOOLEAN NOT NULL DEFAULT true,
  show_notes BOOLEAN NOT NULL DEFAULT false,
  show_song_numbers BOOLEAN NOT NULL DEFAULT true,
  show_header BOOLEAN NOT NULL DEFAULT true,
  show_page_numbers BOOLEAN NOT NULL DEFAULT true,
  base_font_size DOUBLE PRECISION NOT NULL DEFAULT 18.0
    CHECK (base_font_size >= 14.0 AND base_font_size <= 24.0),
  paper_size TEXT NOT NULL DEFAULT 'letter'
    CHECK (paper_size IN ('letter', 'a4')),
  column_count INT NOT NULL DEFAULT 1
    CHECK (column_count IN (1, 2)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. INDEX for band isolation and fast lookup
CREATE INDEX idx_print_templates_band_id ON public.print_templates(band_id);

-- 3. TRIGGER: auto-update updated_at on every UPDATE
CREATE OR REPLACE FUNCTION update_print_templates_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER print_templates_updated_at
  BEFORE UPDATE ON public.print_templates
  FOR EACH ROW
  EXECUTE FUNCTION update_print_templates_updated_at();

-- 4. ADD last_used_print_template_id to bands table
ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS last_used_print_template_id UUID
  REFERENCES public.print_templates(id) ON DELETE SET NULL;

-- 5. RLS POLICY
ALTER TABLE public.print_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage print templates for their bands"
  ON public.print_templates
  FOR ALL
  USING (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  )
  WITH CHECK (
    band_id IN (
      SELECT bm.band_id FROM public.band_members bm
      WHERE bm.user_id = auth.uid()
    )
  );
```

**RLS Safety:** Policy queries `band_members` (different table), not `print_templates` itself. No self-referencing risk.

**CHECK constraints:** `tuning_display`, `paper_size`, `column_count`, and `base_font_size` are all constrained at the database level to prevent invalid values.

**updated_at trigger:** Uses the same per-table trigger function pattern as `notification_preferences_updated_at` in `20260109_notifications.sql`.

**last_used_print_template_id on bands:** Replaces the `is_last_used` boolean on `print_templates`. A single column on `bands` avoids the race condition of clearing/setting booleans across multiple rows. `ON DELETE SET NULL` ensures graceful fallback when a template is deleted.

### Schema Impact Summary

| Area            | Impact                                                            |
| --------------- | ----------------------------------------------------------------- |
| New table       | `print_templates` — band-scoped template storage                  |
| Existing tables | `bands` — new nullable column `last_used_print_template_id` added |
| RLS             | New policy on `print_templates` only                              |
| RPCs            | Not required                                                      |
| Triggers        | New `print_templates_updated_at` trigger on `print_templates`     |

---

## 7. RLS / RPC Changes

- **New RLS:** One policy on `print_templates` — standard band membership check via `band_members` join
- **No new RPCs required** — standard CRUD via PostgREST is sufficient
- **No RPC modifications**
- **New trigger:** `print_templates_updated_at` — auto-sets `updated_at = now()` on every UPDATE to `print_templates`
- **Bands table alteration:** New nullable column `last_used_print_template_id UUID REFERENCES print_templates(id) ON DELETE SET NULL`

---

## 8. Flutter Architecture Changes

### New State / Models

| Component                 | Type         | Purpose                                        |
| ------------------------- | ------------ | ---------------------------------------------- |
| `PrintTemplate`           | Model        | Dart representation of `print_templates` row   |
| `PrintTemplateRepository` | Repository   | Supabase CRUD for templates                    |
| `SetGroup`                | Helper class | Represents a group of items between Set Breaks |

### Modified Components

| Component             | Change                                                                                  |
| --------------------- | --------------------------------------------------------------------------------------- |
| `SetlistPrintHandler` | New signature: accepts `List<SetlistItem>` + `PrintTemplate`                            |
| `SetlistPrintService` | Rewritten PDF generation driven by `PrintTemplate` options, accepts `SetlistItem` list  |
| `SetlistPrintWeb`     | Rewritten HTML generation driven by `PrintTemplate` options, accepts `SetlistItem` list |
| `SetlistPrintStub`    | Updated signature to match handler                                                      |
| `SetlistDetailScreen` | `_handlePrint()` shows print options bottom sheet instead of printing directly          |

### New Widgets

| Widget                    | Purpose                                                  |
| ------------------------- | -------------------------------------------------------- |
| `PrintOptionsBottomSheet` | Template selection + live option toggles before printing |

### Provider Analysis

No new providers are required. The print flow is action-based (user taps Print → bottom sheet → confirm → print). Template data is loaded imperatively in the bottom sheet via repository calls. This follows the callback communication pattern within the feature subtree.

### Data Flow (New)

```
User taps Print icon
  → SetlistDetailScreen shows PrintOptionsBottomSheet(bandId: bandId)
    → Bottom sheet loads templates via PrintTemplateRepository.fetchTemplates(bandId)
    → Bottom sheet reads band.last_used_print_template_id to pre-select template
       (if null or references deleted template → falls back to PrintTemplate.defaultTemplate)
    → User selects/edits template
    → User taps "Print"
    → Bottom sheet calls PrintTemplateRepository.setLastUsed(bandId, templateId)
       (single atomic UPDATE on bands row)
    → Bottom sheet returns PrintTemplate to SetlistDetailScreen
  → SetlistDetailScreen calls SetlistPrintHandler.print(
      setlistName: name,
      items: state.items,        // Full mixed list
      template: selectedTemplate,
      bandName: bandName,        // For header
      gigDate: gigDate,          // Optional, for header
      venue: venue,              // Optional, for header
    )
    → Platform dispatch → PDF or HTML generation using template options
```

---

## 9. Files to Create

| File                                                            | Justification                                                                               |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `lib/features/setlists/models/print_template.dart`              | New model for print configuration — no existing model can represent this                    |
| `lib/features/setlists/print_template_repository.dart`          | Supabase CRUD for `print_templates` — follows existing repository pattern                   |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart` | UI for template selection and print options — consistent with existing bottom sheet pattern |
| `supabase/migrations/20260322100000_print_templates.sql`        | Database migration for new table, trigger, bands column, and RLS                            |

---

## 10. Files to Modify

| File                                                        | Changes                                                                                                                                                                                                                                                          |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/services/setlist_print_handler.dart` | Update `print()` signature to accept `List<SetlistItem>`, `PrintTemplate`, optional header fields. Update platform dispatch.                                                                                                                                     |
| `lib/features/setlists/services/setlist_print_service.dart` | Rewrite `_buildPdfDocument()` and helpers to: accept items + template, group by Set Breaks, render Pauses inline, apply template options (tuning mode, metadata, font size, paper size, columns, headers, page numbers). Update `generatePrintHtml()` similarly. |
| `lib/features/setlists/services/setlist_print_web.dart`     | Update `printSetlist()` signature to match handler. Pass through items + template.                                                                                                                                                                               |
| `lib/features/setlists/services/setlist_print_stub.dart`    | Update stub signature to match handler.                                                                                                                                                                                                                          |
| `lib/features/setlists/setlist_detail_screen.dart`          | Change `_handlePrint()` to show `PrintOptionsBottomSheet` and pass `state.items` + template to handler. Add imports.                                                                                                                                             |

---

## 11. Files Off-Limits

| File                                                       | Reason                                              |
| ---------------------------------------------------------- | --------------------------------------------------- |
| `lib/main.dart`                                            | Init order must not change                          |
| `lib/features/setlists/setlist_detail_controller.dart`     | State shape already has `items` — no changes needed |
| `lib/features/setlists/setlist_repository.dart`            | Song queries are unrelated to print                 |
| `lib/features/setlists/special_item_repository.dart`       | Special item loading is already correct             |
| `lib/features/setlists/models/setlist_song.dart`           | Model is stable — no new fields                     |
| `lib/features/setlists/models/setlist_item.dart`           | Model is sufficient as-is                           |
| `lib/features/setlists/models/special_item.dart`           | Model is sufficient as-is                           |
| `lib/features/setlists/tuning/tuning_helpers.dart`         | Tuning parsing is already available                 |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Display-only — not related to print                 |
| `lib/features/setlists/widgets/special_item_card.dart`     | Display-only — not related to print                 |
| `lib/app/theme/design_tokens.dart`                         | Theme tokens are unchanged                          |
| Any file outside `lib/features/setlists/`                  | Feature-scoped change only                          |

---

## 12. System Impact Map

| System             | Impact                                                                                                                                                                                 |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setlists / Catalog | **Affected** — print flow changes, new bottom sheet, new template persistence                                                                                                          |
| Gigs               | **Unaffected** — print may optionally display gig info in header, but gig data is passed as parameters, not queried from print layer                                                   |
| Rehearsals         | Unaffected                                                                                                                                                                             |
| Members / RBAC     | Unaffected — RLS on print_templates uses existing band_members check                                                                                                                   |
| Auth / Session     | Unaffected                                                                                                                                                                             |
| Routing            | Unaffected — bottom sheet is modal, no new routes                                                                                                                                      |
| Notifications      | Unaffected                                                                                                                                                                             |
| Platform: iOS      | Affected — PDF print service changes                                                                                                                                                   |
| Platform: Android  | Affected — PDF print service changes                                                                                                                                                   |
| Platform: macOS    | Affected — PDF print service changes                                                                                                                                                   |
| Platform: Web      | Affected — HTML print service changes                                                                                                                                                  |
| Catalog            | Unaffected — Catalog uses `songs` list not `items`, and Catalog does not have set breaks/pauses. Print from Catalog should continue to work with a default template (no set grouping). |

---

## 13. Regression Risk

**Level: MEDIUM**

**Rationale:**

- Print services are being rewritten (not just extended) to support the new template-driven model — existing print output will change
- New database table + RLS policy — migration required
- All four platforms are affected (PDF + HTML paths)
- No auth, session, routing, or init order changes reduce risk
- No mutations to existing data — print is read-only
- Existing `state.items` data flow is not modified
- Template persistence is additive (new table, one nullable column added to `bands`)

**Mitigation:** Engineer must verify that printing without a saved template (first-time use, default options) produces output equivalent to or better than the current hardcoded output.

### Risks / Edge Cases

1. **Two-column layout + set headers / pauses:** When `column_count = 2`, "Set N" label rows and Pause rows must span both columns at full page width. If these elements are rendered inside the column flow, they will be visually broken. The Engineer must ensure these elements break out of the column layout (PDF: use full-width container outside column context; HTML: use `column-span: all`).

2. **Template deletion while selected:** If a user deletes the template that `bands.last_used_print_template_id` references, the FK `ON DELETE SET NULL` clears the reference. On next print open, the bottom sheet reads null and falls back to `PrintTemplate.defaultTemplate(bandId: bandId)`. Engineer must test this path explicitly.

3. **show_header with null gig data:** When `show_header = true` but `gigDate` and `venue` are null, the header must render only setlist name and band name. No blank lines, no placeholder text. Engineer must verify this renders cleanly on both PDF and HTML paths.

4. **Font size floor enforcement:** The database CHECK constraint enforces `base_font_size >= 14.0 AND <= 24.0`. The Dart model `defaultTemplate()` must also enforce this range. The UI slider/stepper must be bounded to this range.

---

## 14. Engineer Task Breakdown

Execute in order:

### Task 1: Database Migration

- Create migration file `supabase/migrations/20260322100000_print_templates.sql`
- Define `print_templates` table with all columns per schema in Section 6, including CHECK constraints on `tuning_display`, `paper_size`, `column_count`, and `base_font_size`
- Add `updated_at` trigger function `update_print_templates_updated_at()` and trigger `print_templates_updated_at` (same pattern as `20260109_notifications.sql`)
- ALTER TABLE `bands` to add `last_used_print_template_id UUID REFERENCES print_templates(id) ON DELETE SET NULL`
- Add RLS policy using `band_members` join
- Add index on `band_id`

### Task 2: PrintTemplate Model

- Create `lib/features/setlists/models/print_template.dart`
- Fields: id, bandId, name, tuningDisplay (`grouped` | `inline`), showCapo, showBpm, showNotes, showSongNumbers, showHeader, showPageNumbers, baseFontSize, paperSize (`letter` | `a4`), columnCount (1 | 2), createdAt, updatedAt
- **No `isLastUsed` field** — last-used tracking is on the `bands` table (`last_used_print_template_id`)
- Include `fromSupabase()`, `toInsertJson()`, `toUpdateJson()`, `copyWith()`
- Include a `static PrintTemplate defaultTemplate({required String bandId})` factory that returns sensible defaults matching current behavior (grouped tuning, show BPM, 18pt font, letter, single column)

### Task 3: PrintTemplateRepository

- Create `lib/features/setlists/print_template_repository.dart`
- Methods: `fetchTemplates(bandId)`, `createTemplate(bandId, template)`, `updateTemplate(template)`, `deleteTemplate(templateId)`, `setLastUsed(bandId, templateId)`, `getLastUsedTemplateId(bandId)`
- `setLastUsed` performs a single atomic UPDATE on the `bands` row: `UPDATE bands SET last_used_print_template_id = templateId WHERE id = bandId`. No multi-row boolean flip.
- `getLastUsedTemplateId` reads `bands.last_used_print_template_id` for the given band. Returns `null` if no template has been used or if the referenced template was deleted (ON DELETE SET NULL).
- Standard Supabase CRUD via PostgREST

### Task 4: Set Grouping Logic

- Add a static method in `SetlistPrintService` (or a private helper): `groupItemsBySets(List<SetlistItem>) → List<SetGroup>`
- `SetGroup` contains: `int setNumber`, `List<SetlistItem> items` (songs + pauses only — breaks are delimiters)
- Logic: iterate items, split on `isSetBreak`, assign incrementing set numbers
- If no set breaks exist, all items form a single group (no set label printed)
- Define `SetGroup` class in `setlist_print_service.dart` (small helper, analogous to existing `TuningBlock`)

### Task 5: Refactor Print Handler Signature

- Update `SetlistPrintHandler.print()` to accept:
  - `setlistName: String`
  - `items: List<SetlistItem>`
  - `template: PrintTemplate`
  - `bandName: String?` (optional, for header)
  - `gigDate: String?` (optional, for header)
  - `venue: String?` (optional, for header)
- Update platform dispatch to pass all parameters through
- Update `SetlistPrintWeb.printSetlist()` and stub signatures to match

### Task 6: Rewrite PDF Print Service

- Rewrite `_buildPdfDocument()` to accept `List<SetlistItem>`, `PrintTemplate`, and optional header fields
- Apply template options:
  - Paper size: `PdfPageFormat.letter` or `PdfPageFormat.a4`
  - Base font size: from `template.baseFontSize` with minimum floor of 14pt
  - Column layout: single or two-column (`pw.MultiPage` with `crossAxisCount`)
  - **Two-column rule:** When `column_count = 2`, "Set N" label rows and Pause rows must always render at full page width spanning both columns. Only individual song rows participate in the two-column flow.
  - Header: conditionally render setlist name, band name, date, venue
  - **Header null handling:** When `show_header = true` but `gigDate` and `venue` are null, render setlist name and band name only. Empty fields are omitted entirely — no blank lines or placeholder text.
  - Page numbers: conditionally render via `pw.MultiPage.footer`
- Implement set grouping:
  - Call `groupItemsBySets(items)` to get set groups
  - For each set group, render "Set N" label
  - Attempt to keep entire set on one page using `pw.Wrap` / `pw.Partition`
  - If set overflows, reduce font incrementally (step 0.5pt) until fit or floor reached, then overflow naturally
- Render pauses: full-width row, bold text, smaller font, outlined rectangle border
- Tuning display per template:
  - `grouped`: current behavior — tuning header above first song in that tuning group, not repeated until change
  - `inline`: tuning short label displayed right-aligned on each song row
- Metadata per template toggles:
  - Capo: extract from tuning string via `parseCapoTuning()`, display "Capo N" adjacent to title
  - BPM: display "(N BPM)" right-aligned (current behavior, now toggleable)
  - Notes: display below song title as secondary line, smaller font
- Song numbering: per-set sequential numbers, toggleable
- Remove old `groupSongsByTuning()` / `TuningBlock` — replaced by set grouping + tuning display mode
- Keep `generatePrintHtml()` updated in parallel (shared logic where possible)

### Task 7: Rewrite HTML Print Service (Web)

- Update `generatePrintHtml()` to accept `List<SetlistItem>`, `PrintTemplate`, and optional header fields
- Mirror all PDF formatting logic in HTML/CSS:
  - Set grouping with "Set N" headers
  - Pause rows with bordered styling
  - Tuning display modes (grouped vs inline)
  - Metadata toggles
  - Font size from template
  - Paper size via `@page { size: letter | A4 }`
  - Column layout via CSS `column-count`
  - **Two-column rule:** When `column_count = 2`, "Set N" label rows and Pause rows must use `column-span: all` to render at full page width. Only song rows participate in the column flow.
  - Header content
  - **Header null handling:** When `show_header = true` but `gigDate` and `venue` are null, render setlist name and band name only. Omit empty fields entirely — no blank lines or placeholder text.
  - Page numbers via CSS `@bottom-center { content: counter(page) }`
- Keep `_escapeHtml()` for all user-provided content

### Task 8: Print Options Bottom Sheet

- Create `lib/features/setlists/widgets/print_options_bottom_sheet.dart`
- UI structure:
  - Template picker dropdown (fetched from `PrintTemplateRepository`)
  - "New Template" / "Delete Template" actions
  - Template name text field (when creating/editing)
  - Toggle sections for each option group:
    - **Tuning Display**: segmented control (`Grouped` / `Inline`)
    - **Show Metadata**: toggle switches for Capo, BPM, Notes
    - **Layout**: toggle switches for Song Numbers, Header, Page Numbers
    - **Font Size**: slider or +/- stepper (14pt–24pt range)
    - **Paper Size**: segmented control (`Letter` / `A4`)
    - **Columns**: segmented control (`1` / `2`)
  - "Save Template" button (persists current options as named template)
  - "Print" action button (returns selected template to caller)
- On open: load templates via `PrintTemplateRepository.fetchTemplates(bandId)`, read `bands.last_used_print_template_id` via `PrintTemplateRepository.getLastUsedTemplateId(bandId)` to determine pre-selection. If the ID is null or not found in the loaded templates (deleted template), fall back to `PrintTemplate.defaultTemplate(bandId: bandId)`.
- On Print: call `PrintTemplateRepository.setLastUsed(bandId, templateId)` (single atomic UPDATE on bands row), then return template to caller
- **Template deletion edge case:** If the user deletes the currently selected template, the bottom sheet must fall back gracefully to `PrintTemplate.defaultTemplate(bandId: bandId)`. The `ON DELETE SET NULL` on `bands.last_used_print_template_id` ensures the FK reference is cleaned up automatically; the bottom sheet must handle the resulting null on next load.
- Follows existing bottom sheet patterns (dark theme, rose accent, 48px touch targets)
- Must respect `AppColors`, `AppTextStyles`, `Spacing` tokens

### Task 9: Update SetlistDetailScreen

- Change `_handlePrint()` to:
  1. Show `PrintOptionsBottomSheet`
  2. Receive returned `PrintTemplate`
  3. If user confirmed, call `SetlistPrintHandler.print()` with `state.items`, template, and optional header info
- Import `PrintOptionsBottomSheet` and `PrintTemplate`
- Obtain band name from `activeBandProvider` for header
- **Header null handling:** When `show_header = true`, pass `bandName` from `activeBandProvider`. Pass `gigDate` and `venue` as `null` for now. The print services must render only non-null header fields — no blank lines or placeholders for missing data.
- Gig date/venue: passed as `null` for now (setlist detail screen doesn't currently know which gig it's associated with — this is a known limitation, documented out of scope for this feature)

### Task 10: Catalog Print Compatibility

- When printing from Catalog (no `items`, only `songs`), convert `songs` to `List<SetlistItem>` of type `song` with no set breaks
- This produces a flat list with no set grouping — prints as a single block
- Default template options apply

---

## 15. Verification Plan

### Engineer Commands

```bash
flutter analyze     # Must pass with 0 errors
flutter test        # Must not break existing tests
```

### Manual Verification (Engineer)

1. **Default print (no templates):** Open any setlist with set breaks and pauses → tap Print → bottom sheet appears with default options → tap Print → output shows set grouping, pauses inline, correct formatting
2. **Template CRUD:** Create a template "Stage Sheet" → save → close → reopen print → "Stage Sheet" is pre-selected → modify options → save as "Rehearsal Copy" → both templates persist → delete one → only one remains
3. **Tuning display modes:** Set template to Grouped → print → tuning headers appear above first song in group. Switch to Inline → print → tuning appears right-aligned on every song row
4. **Metadata toggles:** Toggle BPM off → no BPM in output. Toggle Capo on → "Capo N" appears for songs with capo. Toggle Notes on → notes appear below song title
5. **Paper size:** Switch to A4 → print → PDF uses A4 dimensions
6. **Two-column layout:** Enable → print → songs render in two columns
7. **Font size:** Adjust to 24pt → print → text is larger. Adjust to 14pt → text is smaller but readable
8. **Song numbering:** Toggle off → no numbers. Toggle on → per-set sequential numbers
9. **Header:** Toggle off → no header. Toggle on → setlist name, band name shown
10. **Page numbers:** Toggle off → no page numbers. Toggle on → page numbers visible
11. **Set fitting:** Create a set with many songs → set auto-reduces font to fit page → verify minimum font floor is respected
12. **Pause rendering:** Pauses appear inline with bold text, smaller font, outlined border
13. **Catalog print:** Print from Catalog → flat list, no set grouping, default template works
14. **Platform check:** Verify on Web (HTML), macOS (PDF), iOS (PDF) at minimum

---

## 16. QA Regression Areas

1. **Existing print functionality:** Verify a setlist with no set breaks/pauses prints correctly with default template (should match or improve on previous output)
2. **Set break / pause rendering in setlist detail screen:** Verify adding, editing, deleting, reordering set breaks and pauses still work (print changes must not affect the detail screen list)
3. **Song metadata editing:** Verify inline BPM, tuning, notes editing still works (print reads state, does not modify it)
4. **Setlist loading:** Verify `state.items` is still the same data as before
5. **Band switching:** Verify templates are band-scoped — switching bands shows different templates
6. **Catalog:** Verify Catalog print still works without set groups

---

## 17. Rollout / Migration Strategy

1. **Migration:** Apply `print_templates` migration to Supabase before deploying the Flutter update
2. **No breaking changes:** The migration adds a new table and one nullable column to `bands`. Existing band rows are unaffected (column defaults to NULL).
3. **Backward compatibility:** If no templates exist for a band (and `last_used_print_template_id` is null), the bottom sheet shows default options. Users are not blocked
4. **No feature flag required:** The print button simply opens the new bottom sheet instead of printing directly — this is safe to deploy to all users
5. **Deploy order:** Migration → Flutter build → Deploy

---

## 18. Out of Scope

| Item                                               | Reason                                                                                                                                                                                            |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Duration / running time display on print           | Explicitly excluded per feature input                                                                                                                                                             |
| Musical key display                                | No `key` column exists on `songs` table. Feature input says "Key / Capo" but only capo data exists (encoded in tuning string). Adding a key column is a separate schema change.                   |
| Gig-aware print headers (auto-populate date/venue) | Setlist detail screen doesn't know which gig it's linked to. Passing gig context requires routing changes out of scope. Header fields are available in the template for manual use in the future. |
| Print preview / live visual preview                | Not requested. Bottom sheet shows option toggles, not a rendered preview.                                                                                                                         |
| Export to file (save PDF to device)                | Not requested. Current `generatePdfBytes()` API remains available for future use.                                                                                                                 |
| Template sharing between bands                     | Templates are band-scoped per band isolation rules                                                                                                                                                |
| Landscape orientation                              | Not requested. Both Letter and A4 are portrait.                                                                                                                                                   |
| Custom fonts                                       | Not requested. System fonts are used per existing pattern.                                                                                                                                        |

---

## 19. Widget Contracts (Public API)

### PrintOptionsBottomSheet

```dart
class PrintOptionsBottomSheet extends StatefulWidget {
  /// Band ID for template loading/saving and last-used lookup
  final String bandId;

  /// Shows the bottom sheet. Returns the selected PrintTemplate, or null if cancelled.
  /// On open: loads templates + reads bands.last_used_print_template_id for pre-selection.
  /// On print: calls setLastUsed() on bands row, then returns template.
  /// On template deletion: falls back to PrintTemplate.defaultTemplate(bandId: bandId).
  static Future<PrintTemplate?> show(BuildContext context, {required String bandId});
}
```

### PrintTemplate

```dart
class PrintTemplate {
  final String? id;                // null for unsaved/default
  final String bandId;
  final String name;
  final String tuningDisplay;      // 'grouped' | 'inline'
  final bool showCapo;
  final bool showBpm;
  final bool showNotes;
  final bool showSongNumbers;
  final bool showHeader;
  final bool showPageNumbers;
  final double baseFontSize;       // 14.0 – 24.0, floor 14.0
  final String paperSize;          // 'letter' | 'a4'
  final int columnCount;           // 1 | 2
  // NOTE: No isLastUsed field. Last-used tracking lives on bands.last_used_print_template_id.

  static PrintTemplate defaultTemplate({required String bandId});
  factory PrintTemplate.fromSupabase(Map<String, dynamic> json);
  Map<String, dynamic> toInsertJson();
  Map<String, dynamic> toUpdateJson();
  PrintTemplate copyWith({...});
}
```

### SetlistPrintHandler (updated)

```dart
class SetlistPrintHandler {
  static Future<void> print({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  });
}
```

### SetGroup (internal helper)

```dart
class SetGroup {
  final int setNumber;           // 1-based
  final List<SetlistItem> items; // Songs + pauses only (breaks are delimiters)
}
```

---

## 20. Data Flow Architecture

```
┌──────────────────────────────────────────────────────┐
│             SetlistDetailScreen                       │
│                                                       │
│  _handlePrint()                                       │
│    ├── shows PrintOptionsBottomSheet(bandId)           │
│    │     ├── loads templates via                      │
│    │     │   PrintTemplateRepository.fetchTemplates()  │
│    │     │     └── Supabase: print_templates           │
│    │     ├── reads bands.last_used_print_template_id   │
│    │     │   via PrintTemplateRepository               │
│    │     │     └── Supabase: bands                     │
│    │     │   (null or deleted → defaultTemplate)       │
│    │     ├── user selects/configures template          │
│    │     ├── on Print: UPDATE bands SET                │
│    │     │   last_used_print_template_id = templateId  │
│    │     └── returns PrintTemplate                     │
│    │                                                   │
│    └── calls SetlistPrintHandler.print(                │
│          setlistName,                                  │
│          state.items,    ← full mixed list             │
│          template,       ← user's config               │
│          bandName,       ← from activeBandProvider     │
│          gigDate?,       ← null (out of scope)         │
│          venue?,         ← null (out of scope)         │
│        )                                               │
│          ├── kIsWeb?                                   │
│          │   YES → SetlistPrintWeb                     │
│          │         → HTML with template options        │
│          │         → window.print()                    │
│          │   NO  → SetlistPrintService                 │
│          │         → PDF with template options         │
│          │         → Printing.layoutPdf()              │
│          │                                             │
│          └── Internal: groupItemsBySets(items)         │
│                → List<SetGroup>                        │
│                → each set rendered with:               │
│                   • "Set N" label (full-width in 2-col)│
│                   • songs with metadata per opts       │
│                   • pauses inline (full-width in 2-col)│
│                   • tuning per display mode            │
│                   • page-fit logic                     │
│                   • header: non-null fields only       │
└──────────────────────────────────────────────────────┘
```

---

## 21. Exact Code Locations

| What               | File                                                        | Line(s) | Action                                        |
| ------------------ | ----------------------------------------------------------- | ------- | --------------------------------------------- |
| Print trigger      | `lib/features/setlists/setlist_detail_screen.dart`          | ~1118   | Modify `_handlePrint()` to show bottom sheet  |
| Print handler      | `lib/features/setlists/services/setlist_print_handler.dart` | 1–50    | Update signature and dispatch                 |
| PDF print service  | `lib/features/setlists/services/setlist_print_service.dart` | 1–600   | Major rewrite: template-driven PDF generation |
| Web print service  | `lib/features/setlists/services/setlist_print_web.dart`     | 1–55    | Update signature, pass template               |
| Print stub         | `lib/features/setlists/services/setlist_print_stub.dart`    | 1–25    | Update stub signature                         |
| TuningBlock class  | `lib/features/setlists/services/setlist_print_service.dart` | 36–46   | Replace with SetGroup                         |
| groupSongsByTuning | `lib/features/setlists/services/setlist_print_service.dart` | 536–585 | Replace with groupItemsBySets                 |
| Print constants    | `lib/features/setlists/services/setlist_print_service.dart` | 49–77   | Replace with template-driven values           |
| Tuning parse       | `lib/features/setlists/tuning/tuning_helpers.dart`          | 17–48   | Read-only usage (no modification)             |
| SetlistItem model  | `lib/features/setlists/models/setlist_item.dart`            | 1–60    | Read-only usage (no modification)             |
| SpecialItem model  | `lib/features/setlists/models/special_item.dart`            | 1–115   | Read-only usage (no modification)             |
| Active band        | `lib/features/bands/active_band_controller.dart`            | —       | Read-only: get band name for header           |
