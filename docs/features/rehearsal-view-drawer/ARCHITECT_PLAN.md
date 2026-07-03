# Architect Plan — Rehearsal View Drawer

## Feature Slug

`feature/rehearsal-view-drawer`

## Problem Summary

Confirmed gigs have a view drawer that opens when the user taps a confirmed gig card (from dashboard, calendar, or elsewhere). This drawer shows gig details in a read-oriented layout: venue/name, date, time, setlist, notes, and an Edit button to reach the edit flow.

Confirmed rehearsals have no equivalent view drawer. Tapping a confirmed rehearsal card currently opens the edit drawer directly, bypassing the view step. The user requested rehearsals behave identically to gigs — tapping a rehearsal card should open a view drawer matching the confirmed gig view drawer's structure and interaction.

**Type:** Feature addition (not a bug — this is new functionality)

## Root Cause

Not applicable — this is an intentional feature addition, not a diagnosis of a defect. The current behavior is working as designed; the edit flow is directly accessible from rehearsal cards. The feature request asks for a new view drawer layer to be inserted before the edit step, matching the confirmed gig interaction model.

**Root cause confidence:** `HIGH` — Confirmed by code inspection. The pattern exists for gigs (`ViewGigDrawer`) but was never implemented for rehearsals.

## Reference Docs Consulted

- `docs/reference/architecture/database_schema.md` — confirmed `rehearsals` table schema includes all required fields (date, start/end time, location, notes, setlist_id, recurrence fields)
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — understood app architecture, feature-first structure, and repository pattern

No reference docs exist for the gig/rehearsal drawer domain. The reference implementation is the existing `ViewGigDrawer` code (`lib/features/gigs/widgets/view_gig_drawer.dart`).

## Existing System Analysis

### Current Behavior — Confirmed Gigs

1. User taps `ConfirmedGigCard` (dashboard/home)
2. `onTap` → `_openViewGigSheet(gig)` in `home_tab_content.dart`
3. `ViewGigDrawer.show()` is called
4. Drawer displays: gig/venue name (large bold), location, Navigate button, date/time, load-in time (if present), setlist (tappable), gig pay (if present), notes (tappable)
5. Footer: "Done" button + "Edit" text button (if `canEdit`)
6. "Edit" button → pops drawer → calls `onEdit()` callback → `AddEditEventBottomSheet.show()` in edit mode

**Calendar behavior for confirmed gigs:**

- `CalendarEventCard` tap → `_openEditEventSheet()` in `calendar_screen.dart`
- Confirmed gigs (lines 244-265): check `event.isConfirmedGig` → call `ViewGigDrawer.show()` first → Edit button callback → `AddEditEventBottomSheet.show()`

### Current Behavior — Confirmed Rehearsals

**Dashboard surfaces (3 call sites):**

1. **`home_screen.dart` line ~814** (next rehearsal card):
   - User taps `RehearsalCard` for next upcoming rehearsal
   - `onTap` → `_openEditRehearsalSheet(nextRehearsal)`
   - **Skips view step** → directly calls `AddEditEventBottomSheet.show()` in edit mode

2. **`home_tab_content.dart` line ~1233** (confirmed rehearsals horizontal list):
   - User taps `RehearsalCard` in confirmed rehearsals section
   - Source: `confirmedRehearsals` filtered/grouped by `RehearsalDisplayHelper` (lines 1201-1209)
   - `onTap` → `_openEditRehearsalSheet(rehearsal)`
   - **Skips view step** → directly calls `AddEditEventBottomSheet.show()` in edit mode

3. **`home_tab_content.dart` line ~1119** (potential rehearsals — **NO CHANGE REQUIRED**):
   - User taps potential `RehearsalCard` in upcoming events section (line 1109: `event['rehearsal']`)
   - Card has `additionalDates`, `perDateUserResponses`, `onRespondForDate` callbacks
   - Shows availability buttons inline (not affected by this feature)
   - **Feature input constraint:** "confirmed rehearsals" only — potential rehearsals keep existing behavior

**Calendar behavior for rehearsals:**

- `CalendarEventCard` tap → `_openEditEventSheet()` in `calendar_tab_content.dart` (live surface mounted at `app_shell.dart:158`)
- Confirmed gigs (lines 224-243): check `event.isConfirmedGig` → call `ViewGigDrawer.show()` first
- Rehearsals (lines 252-260): **NO view drawer check** → directly to `AddEditEventBottomSheet.show()` in edit mode
- **No view drawer step for rehearsals**

**Note:** `calendar_screen.dart` exists but is not imported anywhere in the codebase (grep confirms no imports). It appears to be legacy/dead code. The live calendar surface is `calendar_tab_content.dart`.

### Data Flow for Rehearsals

- `Rehearsal` model (`lib/app/models/rehearsal.dart`): includes date, startTime, endTime, location, notes, setlistId, isRecurring, recurrenceFrequency, recurrenceDays[], recurrenceUntil, parentRehearsalId
- Rehearsal cards render on dashboard:
  - `home_screen.dart` line ~814: next rehearsal card
  - `home_tab_content.dart` line ~1233: confirmed rehearsals horizontal list (lines 1201-1209: grouped by `RehearsalDisplayHelper`)
  - `home_tab_content.dart` line ~1119: potential rehearsals (availability buttons, not affected by this feature)
- Rehearsal events render on calendar: `calendar_event_card.dart` used in calendar month view
- Setlist name resolved via `setlistsProvider` lookup

## Proposed Solution

Add a `ViewRehearsalDrawer` widget that mirrors the structure, styling, and interaction of `ViewGigDrawer`. Insert this drawer as an intermediate step between card tap and edit flow, matching the confirmed gig interaction pattern.

### What Changes

1. **Create `ViewRehearsalDrawer` widget** (`lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`):
   - Static `show()` method using `showModalBottomSheet` (same signature as `ViewGigDrawer.show`)
   - Header section: rehearsal day/date (large bold, `headlineMedium` + `textPrimary` color), time range (callout style, `textPrimary` color)
   - Recurrence indicator (if `isRecurring`): below date line, shows frequency (Weekly/Biweekly/Monthly) + days (Tue/Thu) + until date. Example: "Weekly · Tue/Thu until Aug 30"
   - Divider (matches `ViewGigDrawer` divider)
   - Detail rows (using `_DetailRow` pattern from `ViewGigDrawer`):
     - Setlist row (if `setlistId != null`): label "Setlist", value = setlist name, `showChevron: true`, tappable → opens `SetlistDetailScreen`
     - Notes row (if notes exist and non-empty): label "Notes", value = empty, `showChevron: true`, tappable → opens `RehearsalNotesSheet`
   - Footer: "Done" button (BrandActionButton, full width) + "Edit" text button (if `canEdit`)
   - "Edit" button → pops drawer → calls `onEdit` callback → parent calls `AddEditEventBottomSheet.show()`

2. **Create `RehearsalNotesSheet` widget** (`lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`):
   - Simple bottom sheet showing notes text (read-only)
   - Mirror `GigNotesSheet` structure: drag handle, title ("Rehearsal Notes"), scrollable text content, "Done" button

3. **Update `home_screen.dart`**:
   - Line ~818: Change rehearsal card `onTap` from `() => _openEditRehearsalSheet(nextRehearsal)` to `() => _openViewRehearsalSheet(nextRehearsal)`
   - Add new `_openViewRehearsalSheet(Rehearsal rehearsal)` method:
     - Check permissions via `currentUserPermissionsProvider` (same pattern as `_openViewGigSheet` in home_tab_content)
     - Get band timezone from `activeBandProvider`
     - Call `ViewRehearsalDrawer.show()` with `canEdit`, `onEdit` callback → `_openEditRehearsalSheet(rehearsal)`

4. **Update `home_tab_content.dart`**:
   - Line ~1239: Change rehearsal card `onTap` from `() => _openEditRehearsalSheet(rehearsal)` to `() => _openViewRehearsalSheet(rehearsal)`
   - Add new `_openViewRehearsalSheet(Rehearsal rehearsal)` method:
     - Check permissions via `currentUserPermissionsProvider` (same pattern as `_openViewGigSheet` lines 437-454)
     - Get band timezone from `activeBandProvider`
     - Call `ViewRehearsalDrawer.show()` with `canEdit`, `onEdit` callback → `_openEditRehearsalSheet(rehearsal)`
   - **Line ~1119: NO CHANGE** — this renders potential rehearsals with availability buttons; feature input specifies "confirmed rehearsals" only

5. **Update `calendar_tab_content.dart`**:
   - In `_openEditEventSheet()` method (lines 189-261), insert new check after confirmed gig check (line 244) and before existing fallthrough (lines 252-260)
   - Pattern: Match confirmed gig check (lines 224-243)
   - New check: `if (!event.isPotentialRehearsal && event.rehearsal != null && event.isRehearsal)`
   - Call `ViewRehearsalDrawer.show()` with `canEdit`, `onEdit` callback → `AddEditEventBottomSheet.show()` (copy callback from gig pattern lines 233-241)
   - Insert `return;` after `ViewRehearsalDrawer.show()` to prevent fallthrough to existing edit logic

### What Must Not Change

- No changes to `RehearsalCard` widget (only the `onTap` prop value changes in the parent)
- No changes to `AddEditEventBottomSheet` (edit drawer is unchanged)
- No changes to potential rehearsals (they keep their inline availability buttons)
- No changes to the `Rehearsal` model or database schema
- No changes to rehearsal repository or controller
- No changes to `main.dart` routing logic (constraint specified in feature input)
- No copy of `_lastLoadedBandId` + `Future.microtask` pattern (constraint specified in feature input)

## Database Impact

**Database: not applicable**

This is a read-only UI feature. All data required already exists in the `rehearsals` table:

- date, start_time, end_time, location, notes, setlist_id (confirmed in `docs/reference/architecture/database_schema.md`)
- is_recurring, recurrence_frequency, recurrence_days[], recurrence_until (for recurrence indicator)

No schema changes. No RLS policy changes. No RPC functions required. No migrations required.

## Flutter Architecture Changes

### State

- No new state required
- Existing providers used: `activeBandProvider` (timezone), `currentUserPermissionsProvider` (Edit button visibility), `setlistsProvider` (setlist name lookup)

### Widgets

- **New:** `ViewRehearsalDrawer` (stateless, mirrors `ViewGigDrawer`)
- **New:** `RehearsalNotesSheet` (stateless, mirrors `GigNotesSheet`)
- **Modified:** Rehearsal card `onTap` handlers in `home_tab_content.dart` and `calendar_screen.dart`

### Repositories

- No repository changes
- Existing `RehearsalRepository` provides all required data via `Rehearsal` model

## Files to Create

| File                                                         | Justification                                                                                                                   |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` | New view drawer mirroring `ViewGigDrawer` structure. Required to display rehearsal details in read-oriented layout before edit. |
| `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart` | Notes viewer bottom sheet matching `GigNotesSheet` pattern. Required to display notes in tappable detail row.                   |

## Files to Modify

| File                                              | What Changes                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_screen.dart`              | (1) Change rehearsal card `onTap` prop from `_openEditRehearsalSheet` to `_openViewRehearsalSheet` (line ~818). (2) Add new `_openViewRehearsalSheet(Rehearsal rehearsal)` method that checks permissions, gets timezone, and calls `ViewRehearsalDrawer.show()` with `onEdit` callback.                                                                        |
| `lib/features/home/home_tab_content.dart`         | (1) Change rehearsal card `onTap` prop from `_openEditRehearsalSheet` to `_openViewRehearsalSheet` (line ~1239 — confirmed rehearsals list). (2) Add new `_openViewRehearsalSheet(Rehearsal rehearsal)` method. **Line ~1119 unchanged** — renders potential rehearsals with availability buttons (not affected by this feature).                               |
| `lib/features/calendar/calendar_tab_content.dart` | In `_openEditEventSheet()` method, insert check after line 244 (confirmed gig check): if confirmed rehearsal (`!event.isPotentialRehearsal && event.rehearsal != null && event.isRehearsal`), call `ViewRehearsalDrawer.show()` first (matching gig pattern lines 224-243), then Edit button callback opens `AddEditEventBottomSheet.show()`. Insert `return;`. |

## Files Off-Limits

| File                                                | Reason                                                                                                                                                    |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                     | Feature input constraint: "Do not add routing logic to `main.dart`"                                                                                       |
| `lib/app/models/rehearsal.dart`                     | No model changes required — all required fields already exist                                                                                             |
| `lib/features/rehearsals/rehearsal_repository.dart` | No repository changes required — existing queries provide all data                                                                                        |
| `lib/features/rehearsals/rehearsal_controller.dart` | No controller changes required — no new state management                                                                                                  |
| `lib/features/calendar/calendar_screen.dart`        | Dead code — not imported anywhere in codebase (grep confirms). The live calendar surface is `calendar_tab_content.dart` (mounted at `app_shell.dart:158`) |
| `supabase/migrations/*`                             | No schema changes required — all fields exist in `rehearsals` table                                                                                       |
| `lib/app/theme/*`                                   | Feature input constraint: "Use `AppColors` / design tokens; no new global colors"                                                                         |

## System Impact Map

| System                                 | Impact                                                                  |
| -------------------------------------- | ----------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                              |
| Rehearsals                             | affected — new view drawer, tap handlers redirect to drawer before edit |
| Setlists / Catalog                     | unaffected — setlist detail screen already opens from setlist rows      |
| Members / RBAC                         | affected — `canEdit` permission check gates Edit button visibility      |
| Auth / Session                         | unaffected                                                              |
| Routing                                | unaffected — no new routes, uses existing modal bottom sheet pattern    |
| Notifications                          | unaffected                                                              |
| Platform (iOS / Android / Web / macOS) | affected — all platforms (drawer uses Flutter's `showModalBottomSheet`) |

## Regression Risk

**Regression risk: LOW**

Rationale:

- Read-only UI feature addition, no database mutations
- Follows proven pattern (`ViewGigDrawer` already exists and works)
- Only 2 tap handler changes (home, calendar) — low blast radius
- Edit flow unchanged (just adds intermediate view step)
- No changes to potential rehearsals (only confirmed rehearsals affected)
- No auth, session, routing, or init order changes
- No new dependencies
- RBAC permission check already exists (`currentUserPermissionsProvider`) — reused pattern from gig drawer

## Engineer Task Breakdown

Execute in strict order. Do not skip. Do not reorder.

1. **Create `RehearsalNotesSheet` widget**
   - File: `lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`
   - Pattern: Copy `lib/features/gigs/widgets/gig_notes_sheet.dart` and adapt
   - Changes: Rename class, update title to "Rehearsal Notes", ensure drag handle + Done button present
   - Verify: Widget compiles, matches gig notes sheet structure

2. **Create `ViewRehearsalDrawer` widget**
   - File: `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`
   - Pattern: Mirror `lib/features/gigs/widgets/view_gig_drawer.dart` structure
   - Required sections:
     - Static `show()` method (same signature as `ViewGigDrawer.show`)
     - Drag handle (match gig drawer's drag handle widget)
     - Header: day/date (large bold, use gig drawer's `_formatFullDate()` pattern), time range (callout gray)
     - Recurrence indicator (if `isRecurring`): derive from `recurrenceFrequency` + `recurrenceDays[]` + `recurrenceUntil`, example: "Weekly · Tue/Thu until Aug 30"
     - Divider
     - Setlist detail row (if `setlistId != null`): label "Setlist", tappable, chevron, opens `SetlistDetailScreen`
     - Notes detail row (if notes exist): label "Notes", tappable, chevron, opens `RehearsalNotesSheet`
     - Footer: "Done" button + "Edit" text button (if `canEdit`)
   - No Navigate button (constraint: rehearsals don't have address field like gigs do)
   - Use `_DetailRow` pattern from `ViewGigDrawer` (reuse or copy)
   - Verify: Drawer compiles, matches gig drawer styling exactly

3. **Update `home_screen.dart` to add view drawer for rehearsals**
   - File: `lib/features/home/home_screen.dart`
   - Line ~818: Change rehearsal card `onTap` from `() => _openEditRehearsalSheet(nextRehearsal)` to `() => _openViewRehearsalSheet(nextRehearsal)`
   - Add new method `_openViewRehearsalSheet(Rehearsal rehearsal)`:
     - Pattern: Same as `_openViewRehearsalSheet` in home_tab_content (create that first, then copy pattern)
     - Check permissions via `currentUserPermissionsProvider` → `canEdit = perms.canEditGigs`
     - Get band timezone from `activeBandProvider`
     - Call `ViewRehearsalDrawer.show()` with rehearsal, timezone, `canEdit`, `onEdit: () => _openEditRehearsalSheet(rehearsal)`
   - Verify: Tapping next rehearsal card on dashboard opens view drawer, Edit button opens edit drawer

4. **Update `home_tab_content.dart` to add view drawer for rehearsals**
   - File: `lib/features/home/home_tab_content.dart`
   - Line ~1239: Change rehearsal card `onTap` from `() => _openEditRehearsalSheet(rehearsal)` to `() => _openViewRehearsalSheet(rehearsal)`
   - Add new method `_openViewRehearsalSheet(Rehearsal rehearsal)`:
     - Pattern: Copy `_openViewGigSheet()` method (lines 434-455) and adapt for rehearsal
     - Check permissions via `currentUserPermissionsProvider` → `canEdit = perms.canEditGigs`
     - Get band timezone from `activeBandProvider`
     - Call `ViewRehearsalDrawer.show()` with rehearsal, timezone, `canEdit`, `onEdit: () => _openEditRehearsalSheet(rehearsal)`
   - **Line ~1119: NO CHANGE** — potential rehearsals (has `additionalDates`, `onRespondForDate` callback) keep existing inline availability button behavior
   - Verify: Tapping a confirmed rehearsal card in horizontal list opens view drawer, Edit button opens edit drawer

5. **Update `calendar_tab_content.dart` to add view drawer for rehearsals**
   - File: `lib/features/calendar/calendar_tab_content.dart`
   - In `_openEditEventSheet()` method (lines 189-261), insert new check after line 244 (confirmed gig check ends) and before lines 252-260 (existing fallthrough)
   - Pattern: Match confirmed gig check (lines 224-243)
   - New check: `if (!event.isPotentialRehearsal && event.rehearsal != null && event.isRehearsal)`
   - Call `ViewRehearsalDrawer.show()` with:
     - `rehearsal: event.rehearsal!`
     - `bandTimezone: ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`
     - `canEdit: editPerms != null && editPerms.canEditGigs`
     - `onEdit: () => AddEditEventBottomSheet.show(...)` (copy callback from gig pattern lines 233-241)
   - Insert `return;` after `ViewRehearsalDrawer.show()` to prevent fallthrough
   - Verify: Tapping a rehearsal in calendar month view opens view drawer, Edit button opens edit drawer

6. **Manually test all rehearsal tap surfaces**
   - **Home screen** (next rehearsal card): tap card → view drawer opens → tap Done → drawer closes
   - **Home screen**: tap card → view drawer opens → tap Edit → edit drawer opens
   - **Dashboard** (confirmed rehearsals horizontal list): tap card → view drawer opens → tap Done → drawer closes
   - **Dashboard**: tap confirmed rehearsal card → view drawer opens → tap Edit → edit drawer opens
   - **Dashboard**: tap confirmed rehearsal card with setlist → tap Setlist row → setlist detail opens
   - **Dashboard**: tap confirmed rehearsal card with notes → tap Notes row → notes sheet opens
   - **Calendar**: tap rehearsal event → view drawer opens → same verifications as dashboard
   - **Potential rehearsals** (dashboard upcoming events): verify still open availability prompt inline (not affected by this feature — NO view drawer)
   - **Recurring rehearsal**: verify recurrence indicator displays correctly in view drawer

7. **Run `flutter analyze` and resolve any errors**
   - Ensure 0 errors before reporting complete
   - Resolve any import issues, missing parameters, or type mismatches

## Verification Plan

### Tier 1 — Pre-deployment (not applicable)

No database changes, no Supabase deployment required. Skip Tier 1.

### Tier 2 — Post-implementation (manual testing)

**Test 1: Home Screen — View Drawer Opens**

1. Navigate to home screen (`HomeScreen` widget via setlists screen)
2. Tap the next rehearsal card
3. Verify: `ViewRehearsalDrawer` opens with day/date header, time, setlist row (if present), notes row (if present), Done and Edit buttons
4. Tap Done → drawer closes

**Test 2: Dashboard — View Drawer Opens**

1. Navigate to dashboard/home tab content
2. Tap a confirmed rehearsal card in the horizontal list
3. Verify: `ViewRehearsalDrawer` opens with day/date header, time, setlist row (if present), notes row (if present), Done and Edit buttons
4. Tap Done → drawer closes

**Test 3: Edit Button Opens Edit Drawer (All Surfaces)**

1. Tap a confirmed rehearsal card → view drawer opens
2. Tap "Edit" text button
3. Verify: View drawer closes, `AddEditEventBottomSheet` opens in edit mode

**Test 3: Edit Button Opens Edit Drawer (All Surfaces)**

1. From home screen OR dashboard horizontal list: tap a confirmed rehearsal card → view drawer opens
2. Tap "Edit" text button
3. Verify: View drawer closes, `AddEditEventBottomSheet` opens in edit mode

**Test 4: Setlist Row Opens Setlist Detail (All Surfaces)**

1. Tap a confirmed rehearsal card that has a setlist assigned
2. In view drawer, tap the Setlist detail row
3. Verify: `SetlistDetailScreen` opens showing the linked setlist

**Test 5: Notes Row Opens Notes Sheet (All Surfaces)**

1. Tap a confirmed rehearsal card that has notes
2. In view drawer, tap the Notes detail row
3. Verify: `RehearsalNotesSheet` opens showing notes text

**Test 6: Calendar — View Drawer Opens**

1. Navigate to calendar tab
2. Tap a rehearsal event in the month view or event list
3. Verify: `ViewRehearsalDrawer` opens (same as home/dashboard tests)

**Test 7: Recurring Rehearsal — Recurrence Indicator**

1. Create or select a recurring rehearsal (e.g., Weekly on Tue/Thu until Aug 30)
2. Tap the rehearsal card (any surface)
3. Verify: View drawer shows recurrence indicator line below date (e.g., "Weekly · Tue/Thu until Aug 30")

**Test 8: Potential Rehearsal — No Change**

1. Tap a potential rehearsal card in dashboard upcoming events section (orange gradient with availability buttons, line ~1119 in home_tab_content)
2. Verify: Card behavior unchanged — availability prompt appears inline, NOT the view drawer

**Test 9: RBAC — Edit Button Visibility**

1. As admin or member: tap rehearsal card (any surface) → verify Edit button visible
2. As contributor with `canEditGigs = false`: tap rehearsal card → verify Edit button hidden

**Test 10: Missing Setlist / Missing Notes**

1. Tap a rehearsal card with no setlist assigned
2. Verify: No setlist row appears in view drawer
3. Tap a rehearsal card with no notes
4. Verify: No notes row appears in view drawer

**Test 11: All Platforms**

1. Test on web (Chrome)
2. Test on iOS (simulator or device)
3. Test on Android (emulator or device)
4. Test on macOS (desktop app)
5. Verify: Drawer opens and functions identically on all platforms

## QA Regression Areas

QA must specifically test:

1. **Confirmed Rehearsal View Drawer** (primary feature):
   - Home screen tap (next rehearsal card) → view drawer opens with correct data
   - Dashboard horizontal list tap → view drawer opens with correct data
   - Calendar tap → view drawer opens with correct data
   - Recurrence indicator displays for recurring rehearsals
   - Setlist row tappable → opens setlist detail
   - Notes row tappable → opens notes sheet
   - Edit button → opens edit drawer
   - Done button → closes view drawer

2. **Edit Flow Integrity** (regression check):
   - Edit drawer still opens from view drawer Edit button (all three surfaces)
   - Edit drawer still saves changes correctly
   - No loss of functionality in edit flow

3. **Potential Rehearsals Unchanged** (regression check):
   - Potential rehearsal cards (home_tab_content.dart line ~1119) still show availability buttons inline
   - Availability buttons still functional
   - NO view drawer opens for potential rehearsals
   - Confirmed vs potential rehearsals correctly distinguished on all surfaces

4. **Confirmed Gig View Drawer Unchanged** (regression check):
   - Confirmed gig cards still open view drawer
   - Gig view drawer functionality unchanged
   - No side effects from rehearsal drawer addition

5. **RBAC Permission Gating** (security check):
   - Contributors without `canEditGigs` do not see Edit button
   - Edit button visibility matches gig drawer behavior (all three surfaces)

6. **Cross-Platform Consistency**:
   - Web, iOS, Android, macOS all render drawer identically
   - No platform-specific rendering issues

7. **All Surfaces Covered** (completeness check):
   - `home_screen.dart` line ~814: next rehearsal card opens view drawer
   - `home_tab_content.dart` line ~1233: confirmed rehearsals open view drawer
   - `home_tab_content.dart` line ~1119: potential rehearsals do NOT open view drawer (unchanged)
   - `calendar_tab_content.dart`: calendar events open view drawer for confirmed rehearsals

## Rollout / Migration Strategy

Not applicable — this is a client-side UI feature with no database changes, no backend changes, and no data migration.

Deploy via standard web build:

```bash
./tools/deploy_web.sh
```

Native apps: Include in next app store release (iOS/Android/macOS).

## Out of Scope

Explicitly excluded from this feature:

1. **Navigate button for rehearsals** — Rehearsals do not have an `address` field like gigs do. The view drawer will not include a Navigate button. If the user later requests navigation to rehearsal locations, that would be a separate feature requiring schema changes.

2. **Load-in time for rehearsals** — Rehearsals do not have a load-in time field. The view drawer will not include a load-in row. If the user requests this, it would require a schema change.

3. **RSVP / Attendance tracking** — This feature is view-only. Rehearsal responses (similar to gig responses) are out of scope. If the user requests attendance tracking in the view drawer, that would be a separate feature.

4. **Deep linking to rehearsal view drawer** — This feature does not add deep link routes. If the user requests shareable rehearsal URLs that open the view drawer, that would require routing changes and is out of scope per the feature input constraint ("Do not add routing logic to `main.dart`").

5. **Edit recurring series from view drawer** — The Edit button opens the existing edit drawer, which already handles recurring series. No changes to series editing logic are in scope for this feature.

6. **Potential rehearsal view drawer** — The feature input specifies "confirmed rehearsals" only. Potential rehearsals keep their inline availability buttons and do not open a view drawer.

---

## Addendum — Location in Header (Manager-Approved, 2026-07-03)

**Requested by:** Tony (product owner)  
**Approved by:** Manager  
**Date:** 2026-07-03

### Requirement

Display the rehearsal's location directly in the view drawer header block, positioned between the time range and recurrence indicator.

### Specification

- **Position:** After the time range Text widget, before the recurrence indicator
- **Spacing:** Separated by `Spacing.space4` from adjacent elements
- **Styling:** Match gig drawer's location styling exactly (`view_gig_drawer.dart` ~line 302):
  - `AppTextStyles.callout`
  - `context.colors.textMuted`
- **Conditional rendering:** Display only if `rehearsal.location.isNotEmpty` (location is non-nullable String in Rehearsal model)
- **Recurrence indicator:** Moves below location when both location and recurrence are present

### Implementation

File: `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`

Add location Text widget in header block after time range (line ~206), before recurrence indicator (line ~208):

```dart
// Location (if present)
if (rehearsal.location.isNotEmpty) ...[
  const SizedBox(height: Spacing.space4),
  Text(
    rehearsal.location,
    style: AppTextStyles.callout.copyWith(
      color: context.colors.textMuted,
    ),
  ),
],
```

### Out of Scope

- **Navigate button:** Not included per the original plan — rehearsals do not have address field suitable for navigation
- **Other drawer sections:** No changes to setlist row, notes row, or footer

### QA Verification

QA must verify:

1. **Location displays correctly:**
   - Rehearsal with location → location appears in header below time range
   - Rehearsal with empty location → location does not appear
   - Location text uses correct style (callout, muted color)

2. **Recurrence indicator positioning:**
   - Rehearsal with location + recurrence → recurrence appears below location
   - Rehearsal with recurrence only → recurrence appears directly below time range (unchanged)

3. **Cross-reference gig drawer:**
   - Compare location text styling in rehearsal drawer vs. gig drawer
   - Verify visual consistency (font size, color, spacing)
