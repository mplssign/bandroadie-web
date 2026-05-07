# ARCHITECT_PLAN

## 1) Feature Slug

`bug/potential-rehearsal-member-names-missing`

## 2) Problem Summary

When a rehearsal is marked as potential in the create/edit form, no band member names are displayed. The gig form shows all band member names when the "Potential Gig" toggle is ON, but the rehearsal form does not show equivalent member names when the "Potential Rehearsal" toggle is ON. This creates inconsistent UX between the two event types and reduces transparency about who will be notified about a potential rehearsal.

## 3) Root Cause

The `_buildPotentialToggle()` method in `rehearsal_form_fields.dart` displays only the toggle switch and descriptive text. It does not include the member name display logic that exists in `gig_form_fields.dart`'s `_buildPotentialGigContainer()`.

**Comparison:**

- **Gig form**: Uses `ConsumerWidget`, accesses `ref.watch(membersProvider)`, wraps toggle in `AnimatedSize` that reveals `ButtonGroupGrid<MemberVM>` showing all band members when `isPotentialGig` is true
- **Rehearsal form**: Uses `StatelessWidget`, has no member provider access, shows only the toggle itself when `isPotential` is true

**Confidence: HIGH** — Direct code observation confirms the gap.

## 4) Reference Docs Consulted

No domain-specific reference docs exist for events/gigs/rehearsals. Diagnosis was based on:

- Direct code inspection of `lib/features/events/widgets/gig_form_fields.dart`
- Direct code inspection of `lib/features/events/widgets/rehearsal_form_fields.dart`
- `docs/features/rehearsal-potential-toggle/ARCHITECT_PLAN.md` (previous feature)
- `docs/features/rehearsal-potential-toggle/QA_REPORT.md` (confirmed implementation gaps)

## 5) Existing System Analysis

### Current data flow (gigs — reference pattern)

1. `GigFormFields` extends `ConsumerWidget` (has `WidgetRef ref` access)
2. In `build()`: reads `final members = ref.watch(membersProvider).members`
3. `_buildPotentialGigContainer()` wraps toggle + member grid in `AnimatedContainer`
4. When `isPotentialGig` is true: `AnimatedSize` reveals `_buildMemberSelectionGrid()`
5. `_buildMemberSelectionGrid()` renders `ButtonGroupGrid<MemberVM>`:
   - `items: members` (all band members)
   - `labelBuilder: (member) => _getMemberLabel(member, members)` (text label)
   - `labelWidgetBuilder: (member) => _buildMemberLabelWidget(...)` (multi-line for disambiguation)
   - `availabilityMode: true` (shows availability states in edit mode)
   - `availabilityState: (member) => { yes/no/notResponded }` (based on `memberAvailability` map)
   - `onTap: null` (display-only, not interactive)
   - `columns: 4`
6. Helper methods handle name disambiguation when multiple members share first names

### Current data flow (rehearsals — target)

1. `RehearsalFormFields` extends `StatelessWidget` (no `WidgetRef` access)
2. Has no member provider access
3. `_buildPotentialToggle()` renders only:
   - `AnimatedContainer` with border when `isPotential` is true
   - Row: title/description + Switch
   - No member display logic
4. Does not use `AnimatedSize` or `ButtonGroupGrid`

## 6) Proposed Solution

Add band member name display to rehearsal form when `isPotential` is true, mirroring the gig pattern with simplifications appropriate for rehearsals:

1. **Convert `RehearsalFormFields` from `StatelessWidget` to `ConsumerWidget`** to access `membersProvider`
2. **Wrap potential toggle in `AnimatedContainer`** with `AnimatedSize` child (matching gig pattern)
3. **When `isPotential` is true**, display `ButtonGroupGrid<MemberVM>` showing all band members
4. **Extract shared member label logic** to `event_editor_helpers.dart` or a new `member_display_helpers.dart` file to avoid duplication between gig and rehearsal forms
5. **Use display-only mode** for rehearsal member grid:
   - Show all members with `AvailabilityState.notResponded` style (outlined)
   - No actual availability states (rehearsals don't have the RSVP concept)
   - `onTap: null` (not interactive)
   - Same 4-column grid layout as gigs for visual consistency

### Must not change

- Database schema (already has `rehearsals.is_potential`)
- Gig form behavior or layout
- Member RSVP/availability model (rehearsals remain display-only)
- Notification behavior
- Routing or initialization

## 7) Database Impact

Database: **not applicable**

The `rehearsals.is_potential` column already exists (added in `feature/rehearsal-potential-toggle`). This is a UI-only change.

## 8) Flutter Architecture Changes

No new architecture layers. Existing patterns remain:

**State:**

- `RehearsalFormFields` changes from `StatelessWidget` to `ConsumerWidget`
- Accesses existing `membersProvider` (already used by gig form)

**Widgets:**

- Reuses existing `ButtonGroupGrid` (already shared)
- New shared helper functions for member label generation (extract from gig form)

**Repositories:**

- No changes

## 9) Files to Create

**Option A: Extract to new shared file**

- `lib/features/events/widgets/member_display_helpers.dart`
  - Contains `getMemberLabel()`, `buildMemberLabelWidget()`, and `getMemberDisambiguation()` functions extracted from `gig_form_fields.dart`
  - Shared by both gig and rehearsal forms

**Option B: Extract to existing shared file**

- Update `lib/features/events/widgets/event_editor_helpers.dart`
  - Add the three member label functions to the existing shared helpers file

**Recommendation:** Option B (update existing file) to avoid creating a new file for just three functions.

## 10) Files to Modify

| File                                                     | What changes                                                                                                                                                                                        |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_helpers.dart`  | Add shared member label functions: `getMemberLabel()`, `buildMemberLabelWidget()`, `getMemberDisambiguation()`, and supporting `MemberDisambiguation` class (extracted from `gig_form_fields.dart`) |
| `lib/features/events/widgets/gig_form_fields.dart`       | Replace inline member label methods with calls to shared functions from `event_editor_helpers.dart`                                                                                                 |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Change from `StatelessWidget` to `ConsumerWidget`; wrap potential toggle in `AnimatedSize`; add `_buildMemberGrid()` that displays when `isPotential` is true; use shared member label functions    |

## 11) Files Off-Limits

| File                                                   | Reason                                                        |
| ------------------------------------------------------ | ------------------------------------------------------------- |
| `lib/main.dart`                                        | Init order must not change                                    |
| `lib/app/models/rehearsal.dart`                        | Model already has `isPotential`; no changes needed            |
| `lib/features/events/events_repository.dart`           | Persistence already handles `is_potential`; no changes needed |
| `lib/features/events/widgets/event_editor_drawer.dart` | Drawer already passes `isPotential` state; no changes needed  |
| `lib/features/events/widgets/button_group_grid.dart`   | Existing shared widget; no modifications needed               |
| `lib/features/members/members_controller.dart`         | Member provider unchanged                                     |
| Any notification files                                 | Out of scope                                                  |
| Any database migration files                           | Schema already complete                                       |

## 12) System Impact Map

| System                                 | Impact                                                 |
| -------------------------------------- | ------------------------------------------------------ |
| Gigs                                   | unaffected (refactor to shared helpers is transparent) |
| Rehearsals                             | affected (adds member name display)                    |
| Setlists / Catalog                     | unaffected                                             |
| Members / RBAC                         | unaffected (read-only access to members)               |
| Auth / Session                         | unaffected                                             |
| Routing                                | unaffected                                             |
| Notifications                          | unaffected                                             |
| Platform (iOS / Android / Web / macOS) | affected (UI change visible on all platforms)          |

## 13) Regression Risk

**LOW**

Rationale:

- UI-only change, no database or state mutations
- No new data flow or async operations
- No new widget lifecycle concerns (no controllers to dispose, no new async gaps)
- Gig form change is a pure refactor to shared functions with identical behavior
- Rehearsal form adds read-only display using existing proven widgets
- No touch to auth, routing, init, or notification systems
- Member provider is already widely used and stable
- `ButtonGroupGrid` is existing, tested, reusable component

## 14) Engineer Task Breakdown

1. **Extract shared member label helpers** to `event_editor_helpers.dart`:
   - Copy `_getMemberLabel()`, `_buildMemberLabelWidget()`, and `_getMemberDisambiguation()` from `gig_form_fields.dart`
   - Copy `MemberDisambiguation` class
   - Make them top-level functions (remove `_` prefix) or static methods in a helper class
   - Add required imports (`MemberVM`, `BuildContext`, design tokens)

2. **Refactor `gig_form_fields.dart`** to use shared helpers:
   - Import `event_editor_helpers.dart`
   - Replace calls to `_getMemberLabel()` with `getMemberLabel()`
   - Replace calls to `_buildMemberLabelWidget()` with `buildMemberLabelWidget()`
   - Remove the now-redundant inline helper methods
   - Verify `flutter analyze` passes with 0 errors

3. **Convert `rehearsal_form_fields.dart`** to `ConsumerWidget`:
   - Change class signature from `extends StatelessWidget` to `extends ConsumerWidget`
   - Update `build()` signature from `build(BuildContext context)` to `build(BuildContext context, WidgetRef ref)`
   - Add `import 'package:flutter_riverpod/flutter_riverpod.dart'`

4. **Refactor `_buildPotentialToggle()`** in `rehearsal_form_fields.dart`:
   - Change return type from `Widget` to return an `AnimatedContainer` wrapping `Column`
   - Inside the `Column`, place the existing toggle UI as the first child
   - Add `AnimatedSize` as second child that reveals member grid when `isPotential` is true

5. **Add `_buildMemberGrid()`** to `rehearsal_form_fields.dart`:
   - Accept `BuildContext context`, `WidgetRef ref` as parameters
   - Read `final membersState = ref.watch(membersProvider)`
   - Read `final members = membersState.members`
   - If loading: show `CircularProgressIndicator`
   - If empty: show "No members to notify" message
   - Otherwise: return `ButtonGroupGrid<MemberVM>` with:
     - `items: members`
     - `labelBuilder: (member) => getMemberLabel(member, members)` (shared helper)
     - `labelWidgetBuilder: (member) => buildMemberLabelWidget(context, member, members)` (shared helper, no availability map)
     - `isSelected: (member) => false`
     - `availabilityMode: true`
     - `availabilityState: (member) => AvailabilityState.notResponded` (always outlined)
     - `onTap: null`
     - `columns: 4`
     - `buttonHeight: 48`

6. **Update imports** in `rehearsal_form_fields.dart`:
   - Add `import 'package:flutter_riverpod/flutter_riverpod.dart'`
   - Add `import '../../members/member_vm.dart'`
   - Add `import '../../members/members_controller.dart'`
   - Add `import 'button_group_grid.dart'`
   - Add `import 'event_editor_helpers.dart'`

7. **Verify static analysis**: Run `flutter analyze` and confirm 0 errors

8. **Manual visual verification** (Tier 2):
   - Create rehearsal, toggle potential ON → member names appear in 4-column grid
   - Edit existing rehearsal, toggle potential ON → member names appear
   - Compare side-by-side with potential gig form → visual parity confirmed
   - Test on Web, iOS, Android, macOS

## 15) Verification Plan

### Tier 1 — Pre-deployment (must pass before any device testing)

**Note:** No database changes in this feature; Tier 1 is static analysis + build verification only.

- **PRE-DEPLOY TEST 1:** Run `flutter analyze` on the workspace root; expect 0 errors, 0 warnings.
- **PRE-DEPLOY TEST 2:** Run `flutter build web --release` to confirm no build errors introduced.
- **PRE-DEPLOY TEST 3:** Code review for `event_editor_helpers.dart`: verify shared functions are pure (no side effects, no state mutations).
- **PRE-DEPLOY TEST 4:** Code review for `gig_form_fields.dart`: verify refactor is call-site only (behavior unchanged, no new logic).
- **PRE-DEPLOY TEST 5:** Code review for `rehearsal_form_fields.dart`: verify `ConsumerWidget` conversion follows standard Riverpod patterns (no missing `mounted` checks, no controller leaks).

### Tier 2 — Post-deployment (runtime testing on actual device/web)

- **POST-DEPLOY TEST 1:** Open rehearsal create drawer on Web, toggle "Potential Rehearsal" ON → verify band member names appear in a 4-column grid below toggle.
- **POST-DEPLOY TEST 2:** Verify member names use first name only when no disambiguation needed; show "FirstName\nL." when multiple members share first name.
- **POST-DEPLOY TEST 3:** Edit existing rehearsal, toggle potential ON → member names appear; toggle OFF → member names disappear with smooth animation.
- **POST-DEPLOY TEST 4:** Open gig create drawer, toggle "Potential Gig" ON → verify member names still appear correctly (refactor did not break gig form).
- **POST-DEPLOY TEST 5:** Compare potential rehearsal form side-by-side with potential gig form → verify visual consistency (same grid layout, same card styling, same animation timing).
- **POST-DEPLOY TEST 6:** Cross-platform smoke test: repeat tests 1-3 on iOS, Android, macOS → confirm parity.
- **POST-DEPLOY TEST 7:** Edge case: band with 0 members → verify "No members to notify" message appears when potential toggle is ON for both gigs and rehearsals.
- **POST-DEPLOY TEST 8:** Edge case: band with 10+ members → verify grid wraps correctly to multiple rows (columns: 4).

**SQL test authoring rules:** Not applicable (no database changes).

## 16) QA Regression Areas

QA must specifically test:

1. **Rehearsal create flow:**
   - Toggle "Potential Rehearsal" ON → member names appear in 4-column grid
   - Toggle OFF → member names disappear
   - Animation is smooth (250ms AnimatedSize)
   - Save potential rehearsal → confirmation modal or success indicator

2. **Rehearsal edit flow:**
   - Open existing non-potential rehearsal → toggle OFF (default)
   - Toggle ON → member names appear
   - Save → persists `is_potential = true` (already tested in prior feature; sanity check only)

3. **Gig form unchanged:**
   - Create potential gig → member names still appear (refactor did not break behavior)
   - Edit potential gig → member availability states still display correctly
   - Multi-date gig → per-date availability sections still render

4. **Member name disambiguation:**
   - Band with multiple members named "John" → verify last initials appear ("John D.", "John K.")
   - Band with unique first names → verify only first names shown ("Sarah", "Mike")

5. **Visual consistency:**
   - Potential rehearsal grid matches potential gig grid styling (card border, padding, animation timing)
   - 4-column layout consistent across both event types

6. **Cross-platform parity:**
   - Web, iOS, Android, macOS all show member names when potential rehearsal toggle is ON
   - Switch.adaptive renders correctly on each platform

7. **Existing rehearsal features unchanged:**
   - Recurring rehearsal toggle still works
   - Location autocomplete still works
   - Setlist selection still works

## 17) Rollout / Migration Strategy

Not applicable — UI-only change, no database migration required.

**Deployment:**

1. Merge PR into main
2. Deploy web via `./tools/deploy_web.sh`
3. Increment iOS/Android build number for next release
4. No rollback concerns (backward-compatible UI change)

## 18) Out of Scope

- Rehearsal member availability/RSVP (rehearsals remain notification-only, no member responses)
- Multi-date rehearsal support (not a feature rehearsals have)
- Any changes to notification copy or trigger logic
- Any changes to gig RSVP/availability model
- Database schema changes (already complete from prior feature)
- New member selection UI for rehearsals (display-only, not interactive)
- Any changes to member roles or permissions
- Any changes to recurring rehearsal logic
