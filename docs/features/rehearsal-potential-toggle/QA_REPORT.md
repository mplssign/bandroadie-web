# QA Report

## Feature Slug

`rehearsal-potential-toggle`

## Feature Title

Rehearsal Potential Toggle

## Final Verdict

**REQUIRES CHANGES**

## Validation Summary

All Architect tasks are implemented and the migration, model, form, controller, and repository layers are correct. The static analyzer passes with 0 errors and all 5 unit tests pass. One critical runtime layout bug was identified in `home_tab_content.dart`: `RehearsalCard` is rendered inside a horizontal `ListView` without a width constraint, which will cause a Flutter `RenderFlex` crash at runtime when any potential rehearsal exists. This must be resolved before commit.

All validation was performed via code-path analysis and static tooling only. Tier 2 (post-`supabase db push`) runtime testing was not performed and is a prerequisite before release.

## Architect Scope Review

- Scope adherence: **compliant** — no out-of-scope changes found
- Files modified: **as expected** — all 8 Dart files match the approved list; migration and test file created as required
- Files off-limits: **not touched** — `lib/main.dart`, notification files, `gig_response_repository.dart`, `potential_gig_prompt_service.dart` are all untouched; gig potential RSVP logic unchanged
- `gig_form_fields.dart`: correctly not modified (shared widget extraction was optional; Engineer chose inline approach)
- `data_backup_service.dart`: correctly not modified; confirmed uses `.select()` full-row query (line 220) and `_upsertRows` (line 330) — `is_potential` is automatically included in export/import post-migration
- No `_lastLoadedBandId` + `Future.microtask` pattern introduced; no silent `catch (e) { return []; }` introduced

## Completeness Check

- All Architect tasks implemented: **yes**
- Missing tasks: none
  - Task 1 (migration): SQL file created, correct syntax, `BOOLEAN NOT NULL DEFAULT FALSE`
  - Task 2 (model): `isPotential` field added to `Rehearsal` with `fromJson`/`toJson` mapping
  - Task 3 (form data): `EventFormData.fromRehearsal()` now reads `rehearsal.isPotential` (was hardcoded `false`)
  - Task 4 (toggle UI): `_buildPotentialToggle()` added to `RehearsalFormFields`
  - Task 5 (drawer wiring): `isPotential`/`onPotentialToggled` passed to `RehearsalFormFields`; `_buildFormData()` guard removed
  - Task 6 (repository): All 4 rehearsal DB paths include `'is_potential': formData.isPotentialGig`
  - Task 7 (controller): `upcomingPotentialRehearsals`, `upcomingConfirmedRehearsals` partitioned; `nextRehearsal` is now confirmed-only
  - Task 8 (home_tab_content): Potential area extended to include rehearsals — **has critical layout bug**
  - Task 9 (home_screen): Potential rehearsals surfaced in top area
  - Task 10 (backup): Verified no changes required
  - Task 11 (tests): 5 unit tests for `Rehearsal.fromJson`/`toJson`; all pass

## Behavior Verification

- Validation method: **code-path analysis only** (no runtime device testing performed)

### Deviation 1 — Shared Toggle Widget Not Extracted

**Assessment: ACCEPTABLE.**
The rehearsal toggle (`_buildPotentialToggle` in `rehearsal_form_fields.dart`) uses identical design tokens to the gig toggle: `AnimatedContainer` with `duration: 200ms`, `Curves.easeOut`, `Spacing.space12` padding, `BorderRadius.circular(12)`, `Border.all(color: AppColors.primary, width: 2)` when active. Text uses `AppTextStyles.callout` / `AppTextStyles.footnote` with `context.colors.textPrimary` / `context.colors.textSecondary`. Switch uses `Switch.adaptive`, `activeTrackColor: AppColors.primary`, white thumb when selected. The visual pattern is consistent enough to satisfy the Architect's requirement. Label copy differs appropriately: "Potential Rehearsal" / "Mark as tentative until confirmed." vs "Potential Gig" / "Requires member confirmation before gig is official."

### Deviation 2 — `isPotentialGig` Reused for Both Event Types

**Assessment: ACCEPTABLE. Isolation confirmed.**
Traced through code:

- For **rehearsal create/edit**: `EventFormData.fromRehearsal()` sets `isPotentialGig: rehearsal.isPotential` (line 551 of `event_form_data.dart`). `_buildFormData()` passes `_isPotentialGig` (line 837 of `event_editor_drawer.dart`). Save path calls `createRehearsal` or `updateRehearsal`, both of which write `is_potential` to the `rehearsals` table only.
- For **gig create/edit**: `EventFormData.fromGig()` sets `isPotentialGig: gig.isPotential` (line 507). Same `_buildFormData()` path. Save path calls `createGig` or `updateGig`, which write `is_potential` to the `gigs` table only.
- The former guard `_eventType == EventType.gig && _isPotentialGig` has been removed from `_buildFormData()`, but this is correct — the guard was unnecessary once rehearsal form data carries the flag. Repository isolation ensures no cross-table contamination.
- Conclusion: creating/saving a gig with potential ON does **not** write `is_potential` to rehearsals table; creating/saving a rehearsal with potential ON does **not** write `is_potential` to gigs table. ✓

### Deviation 3 — `home_screen.dart` Uses Vertical Stack

**Assessment: ACCEPTABLE for `home_screen.dart`; CRITICAL BUG in `home_tab_content.dart` horizontal scroll.**

- `home_screen.dart`: Potential rehearsals render in a `Column` inside `_AnimatedCardEntrance` in the top potential area alongside the potential gig. `nextRehearsal = rehearsalState.nextRehearsal` is confirmed-only (post-controller change). Potential rehearsals do NOT appear in the confirmed-rehearsal lane. No duplication. The vertical stack matches `home_screen.dart`'s legacy single-card pattern. ✓
- `home_tab_content.dart`: Potential rehearsals appear in the horizontal scroll as intended. However, `RehearsalCard` is rendered without a width constraint — see Critical issue #1 below.

### Other Verified Behaviors

- **`nextRehearsal` regression**: `rehearsal_controller.dart` now sets `nextRehearsal = upcomingConfirmedRehearsals.first`. All pre-existing rehearsals have `is_potential = false` (migration default), so the `nextRehearsal` behavior is backward-compatible for all existing data. ✓
- **No duplicates in confirmed area**: `upcomingConfirmedRehearsals` excludes `isPotential = true` records. `nextRehearsal` card cannot show a potential rehearsal. ✓
- **Notification files**: Zero diff on any notification file or SQL trigger. CREATE-only notification behavior preserved. ✓
- **Backup export/import**: `data_backup_service.dart` uses `supabase.from('rehearsals').select()` (full-row select, no column filter), so `is_potential` is automatically included in export. `_upsertRows` upserts full row data. Import will restore `is_potential` correctly. ✓

## Regression Check

- **Risk level: MEDIUM** (as Architect assessed — cross-layer change on frequently-used home surface and event editor)
- Systems reviewed: Rehearsals, Gigs, Home dashboard, Notifications, Backup, Auth/Session, Routing
- Regressions found:
  - **Gig potential flow**: Unchanged — `gig_form_fields.dart`, `createGig`, `updateGig` unmodified except pre-existing `is_potential` fields. ✓
  - **Rehearsal controller**: Backward-compatible; existing rehearsals all have `isPotential = false` (migration default). ✓
  - **Auth/Session**: Unaffected. ✓
  - **Routing**: Unaffected. ✓
  - **Notifications**: Unaffected. ✓
  - **`mounted` guards**: No new `async` gaps introduced in widget lifecycle methods. Existing `setState` call in `onPotentialToggled` is synchronous (no async gap). ✓
  - **Controller/FocusNode disposal**: No new controllers or focus nodes introduced. ✓

## Database Safety

**Verified.**

- Migration file: `supabase/migrations/20260507000000_add_rehearsal_is_potential.sql`
- SQL content reviewed: `ALTER TABLE public.rehearsals ADD COLUMN is_potential BOOLEAN NOT NULL DEFAULT FALSE` — additive, non-destructive, correct type, correct default. Backward-compatible with all existing rows.
- Index added: `CREATE INDEX idx_rehearsals_is_potential ON public.rehearsals(is_potential)` — safe, appropriate for filtering.
- RLS policies: No changes. Existing rehearsal policies are unaffected.
- No RPC function signature changes.
- No SECURITY DEFINER functions introduced.
- No self-referencing RLS policies (infinite recursion risk: none).
- Tier 2 verification (schema confirm query, live row creation, dashboard integration) requires `supabase db push` — not performed in this session.

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 4.6s)
```

## Test Results

Command: `flutter test test/app/models/rehearsal_test.dart`
Result: **Passed — 5/5**

```
00:00 +5: All tests passed!
```

Tests cover: `fromJson` parses `true`, `fromJson` parses `false`, `fromJson` defaults to `false` when missing, `toJson` emits `true`, `toJson` emits `false`.

No widget tests were run for the form toggle or dashboard surface (none exist; Architect required unit tests only for Tier 1, which pass).

## Diff Safety Review

- Secrets: **none found**
- Debug artifacts: `debugPrint` calls in `events_repository.dart` are pre-existing (not introduced in this diff — confirmed by `git diff main` showing no `+debugPrint` lines)
- Unrelated changes: **none found**
- Untracked `BandRoadie/` directory in workspace: pre-existing artifact, not part of this diff, not a concern

---

## Issues Found

### Critical (must fix before commit)

**1. `RehearsalCard` rendered in horizontal `ListView` without width constraint — runtime layout crash**

Location: `lib/features/home/home_tab_content.dart`, `_buildHorizontalPotentialEvents()` method, `itemBuilder` for rehearsal branch.

Root cause: `RehearsalCard.build()` returns a `Container(height: Spacing.rehearsalCardHeight)` with **no explicit width**. The card's inner layout uses `Expanded` inside `Row` inside `Column`. When a `Container` without width is placed inside a horizontal `ListView` (which provides unconstrained horizontal space to children), the `Row` receives unbounded width constraints. Flutter will throw a `RenderFlex` error: _"RenderFlex children have non-zero flex but incoming width constraints are unbounded"_ at runtime when any potential rehearsal is rendered in `home_tab_content.dart`.

Note: `home_screen.dart` is **not affected** — there, potential rehearsal cards are inside a `Column` in a vertical scroll (bounded width). Only the horizontal scroll in `home_tab_content.dart` is affected.

Compare: `PotentialGigCard` accepts `width: Spacing.potentialGigCardWidth` (300px) and uses it to bound its Container. `RehearsalCard` has no such parameter.

**Required fix**: Wrap the `RehearsalCard` returned in `_buildHorizontalPotentialEvents`'s `itemBuilder` in a `SizedBox(width: Spacing.potentialGigCardWidth, child: RehearsalCard(...))`. This constrains the width to 300px, matching the visual footprint of `PotentialGigCard` in the horizontal scroll. No changes to `RehearsalCard` itself are required.

This fix is within the Architect-approved scope: Task 8 requires surfacing potential rehearsals in the horizontal scroll, and `lib/features/home/widgets/rehearsal_card.dart` is listed in the Architect plan as an approved optional modification.

---

### Warnings (should fix)

**1. `setlistName: null` hardcoded in `home_tab_content.dart` for potential rehearsal cards**

Location: `lib/features/home/home_tab_content.dart`, `_buildHorizontalPotentialEvents()`, rehearsal branch (line 863).

Issue: `setlistName: null` is always passed, even when the rehearsal has a non-null `setlistId`. In `home_screen.dart`, the corresponding code correctly performs a setlist lookup from `setlistsState.setlists`. `home_tab_content.dart` has access to `setlistsState` (passed as a parameter to `_buildContentSection`), so the lookup is feasible.

Impact: Potential rehearsal cards in `home_tab_content.dart` will never display a setlist name. This is a cosmetic inconsistency between the two screen paths, not a crash.

---

### Suggestions (optional)

None — staying within QA scope.
