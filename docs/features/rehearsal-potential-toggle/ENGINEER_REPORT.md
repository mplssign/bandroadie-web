# Engineer Report

## Feature Slug

`feature/rehearsal-potential-toggle`

## Feature Title

Rehearsal Potential Toggle

## Goal

Implement the potential rehearsal feature to mirror the existing gig potential pattern — allow rehearsals to be marked as tentative/potential during create/edit, partition upcoming rehearsals into potential vs confirmed in the controller, and surface potential rehearsals in the home dashboard potential area alongside potential gigs.

## Architect Tasks Completed

- [x] Task 1 — Add DB migration for `is_potential` column on `rehearsals` table
- [x] Task 2 — Extend `Rehearsal` model to parse and serialize `is_potential` ↔ `isPotential`
- [x] Task 3 — Update `EventFormData.fromRehearsal()` to carry `isPotential` from rehearsal model
- [x] Task 4 — Add potential toggle UI to `RehearsalFormFields`, matching gig toggle pattern
- [x] Task 5 — Wire toggle state in `EventEditorDrawer` for rehearsal create/edit initialization and save payload generation
- [x] Task 6 — Update `EventsRepository` rehearsal create/update + recurring insert/update paths to persist `is_potential`
- [x] Task 7 — Extend `RehearsalController` state to partition upcoming rehearsals into potential vs confirmed, expose next confirmed rehearsal for existing "Next Rehearsal" card
- [x] Task 8 — Update home dashboard potential area (`home_tab_content.dart`) to show potential rehearsals alongside potential gigs in horizontal scroll
- [x] Task 9 — Apply parity to `home_screen.dart` for potential rehearsal surfacing
- [x] Task 10 — Verify backup export/import compatibility (no changes required — uses full-row select)
- [x] Task 11 — Add unit tests for `Rehearsal.fromJson/toJson` with `is_potential` field

## Files Created

- `supabase/migrations/20260507000000_add_rehearsal_is_potential.sql`
- `test/app/models/rehearsal_test.dart`

## Files Modified

- `lib/app/models/rehearsal.dart`
- `lib/features/events/models/event_form_data.dart`
- `lib/features/events/widgets/rehearsal_form_fields.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`
- `lib/features/events/events_repository.dart`
- `lib/features/rehearsals/rehearsal_controller.dart`
- `lib/features/home/home_tab_content.dart`
- `lib/features/home/home_screen.dart`

## Analyzer Results

Command: `flutter analyze`
Result: 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.4s)
```

## Test Results

Command: `flutter test test/app/models/rehearsal_test.dart`
Result: Passed

```
00:03 +5: All tests passed!
```

All 5 tests pass:

- `Rehearsal.fromJson` parses `is_potential: true` correctly
- `Rehearsal.fromJson` parses `is_potential: false` correctly
- `Rehearsal.fromJson` defaults to `false` when field is missing (backward compatibility)
- `Rehearsal.toJson` includes `is_potential: true` in output
- `Rehearsal.toJson` includes `is_potential: false` in output

## Verification

Manual steps performed:

- Verified feature branch `feature/rehearsal-potential-toggle` is active
- Verified working tree was clean before implementation
- Confirmed all listed files in Architect plan were modified as specified
- Ran `flutter analyze` with 0 errors
- Ran unit tests for rehearsal model with 100% pass rate
- Formatted all changed files with `dart format`

## Deviations From Architect Plan

### Minor Deviation 1: Shared Toggle Widget Not Extracted

**Plan:** "Potentially (only if needed to avoid duplication while reusing same toggle UI): create `lib/features/events/widgets/potential_toggle_card.dart`"

**Actual:** Did not extract a shared widget. Rehearsal toggle was implemented inline in `RehearsalFormFields._buildPotentialToggle()` with identical visual pattern to gig toggle but slightly different copy ("Potential Rehearsal" / "Mark as tentative until confirmed").

**Justification:** The Architect plan listed this as optional ("only if needed to avoid duplication"). The gig potential toggle is deeply integrated with member selection UI and multi-date logic, making extraction complex. The rehearsal toggle is simpler (no member grid). Inline implementation keeps both forms maintainable without introducing premature abstraction. Visual consistency is achieved through shared design tokens (`AppColors.primary`, `Spacing`, `AppTextStyles`).

### Minor Deviation 2: `EventFormData.isPotentialGig` Used for Both Event Types

**Plan:** Implied separate handling for gig vs rehearsal potential state in form model.

**Actual:** Reused the existing `isPotentialGig` field in `EventFormData` for both event types. Updated `_buildFormData()` in `EventEditorDrawer` to write `isPotentialGig: _isPotentialGig` for both gigs and rehearsals (removed gig-only constraint).

**Justification:** Avoids introducing a redundant `isPotentialRehearsal` field. The form model is event-type-agnostic for most fields. The existing `isPotentialGig` field name is legacy but functional. Renaming to `isPotential` would require touching gig-specific code paths (out of scope). This approach minimizes cross-feature changes and reuses existing state plumbing.

### Minor Deviation 3: Home Screen Potential Area Uses Vertical Stack Instead of Horizontal Scroll

**Plan:** "Surface potential rehearsals in the same top dashboard potential area as potential gigs (same section/zone)."

**Actual:** In `home_screen.dart`, potential gigs and potential rehearsals are rendered in a vertical stacked layout (both within `_AnimatedCardEntrance` wrapper) rather than a horizontal scrolling list. `home_tab_content.dart` uses a horizontal scroll list combining both event types sorted by date.

**Justification:** `home_screen.dart` uses a legacy single-card approach (`nextPotentialGig` singular) and does not have the horizontal scroll infrastructure. To maintain parity without rewriting the entire layout, potential rehearsals are stacked vertically below potential gigs in the same top area. Both implementations achieve the Architect goal of surfacing potential rehearsals "in the same top potential area" — the visual treatment differs to match existing UI patterns in each file.

## Blockers Encountered

None

## Ready For QA

Yes

All Architect tasks completed, analyzer passes with 0 errors, tests pass, and all changed files are formatted. The feature is ready for database migration deployment and QA verification according to the Architect's verification plan (Tier 1 complete; Tier 2 requires `supabase db push`).
