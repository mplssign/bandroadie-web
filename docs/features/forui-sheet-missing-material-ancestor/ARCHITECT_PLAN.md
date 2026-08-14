# ARCHITECT_PLAN.md

## bug/forui-sheet-missing-material-ancestor

---

## Feature Slug

`bug/forui-sheet-missing-material-ancestor`

---

## Problem Summary

`showAppBottomSheet` (introduced in PR #129, migrating from Flutter's stock `showModalBottomSheet` to Forui's `showFSheet`) does not provide a Material ancestor to its content tree. Any widget inside a sheet presented via `showAppBottomSheet` that depends on an external Material ancestor for its ink/tap rendering layer (`InkWell`, `ListTile`, `SwitchListTile`) throws at build time:

```
No Material widget found. _InkResponseStateWidget widgets require a Material widget ancestor.
```

Flutter's stock `showModalBottomSheet` automatically wraps content in a Material widget. Forui's `showFSheet` does not. This causes immediate red error screens for any interactive row/tile widget that uses Material's ink effects.

Confirmed broken: gig detail drawer (Setlist/Notes rows), venue navigation picker, band member detail/edit drawers, calendar subscription dialog, setlist picker, key picker.

---

## Root Cause

**Confidence: HIGH (confirmed in code)**

`lib/components/ui/app_bottom_sheet.dart` directly wraps Forui's `showFSheet`, which does not provide a Material widget ancestor in its internal widget tree. Flutter's Material widgets that depend on external Material for ink effects (`InkWell`, `ListTile`, `SwitchListTile`) cannot locate the required ancestor and crash at build time.

### Data Flow

1. Call site invokes `showAppBottomSheet(context: context, builder: (ctx) => MyDrawer())`
2. `showAppBottomSheet` forwards to `showFSheet` with identical builder
3. Forui's `showFSheet` presents the sheet but does not wrap builder output in Material
4. `MyDrawer` builds a tree containing `ListTile` or `InkWell`
5. `ListTile`/`InkWell` walks up the widget tree looking for Material ancestor
6. No Material found → throws `No Material widget found` at build time → red error box replaces the widget

### Why This Wasn't Caught Earlier

- PR #129 (introducing `showAppBottomSheet`) passed QA because the initial affected widgets (e.g., gig notes sheet) used only non-Material widgets (TextField, FilledButton, TextButton)
- Material-dependent widgets (ListTile, InkWell) were added later in subsequent PRs (e.g., navigation picker in venue detail, gig detail drawer setlist row)
- No regression test coverage for Material dependency requirements in sheet content

### Why GestureDetector Is Unaffected

`GestureDetector` does not use Material's ink effects — it's a pure gesture recognizer. Widgets using only `GestureDetector` do not require a Material ancestor and work fine in Forui sheets.

### Why IconButton Appears Unaffected

`IconButton` internally provides its own Material handling when no ancestor is found (confirmed by screenshot evidence in `view_gig_drawer.dart`'s header navigation button rendering correctly). However, this is implementation-specific to `IconButton` and does not extend to `InkWell`, `ListTile`, or `SwitchListTile`.

---

## Reference Docs Consulted

None applicable. This is a UI widget layer bug, not a domain-specific feature. No reference docs exist for the UI facade layer beyond the feature docs themselves (which document the original facade migration but do not address this regression).

---

## Existing System Analysis

### Current Behavior

`showAppBottomSheet` is a thin wrapper over Forui's `showFSheet`:

```dart
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  // ... other params
}) {
  return showFSheet<T>(
    context: context,
    builder: builder,  // Direct passthrough
    side: FLayout.btt,
    barrierDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
  );
}
```

The builder output is presented by Forui's sheet implementation, which does not wrap it in a Material widget. Any Material-dependent widget in the builder tree crashes.

### Affected Files (Confirmed via Code Inspection)

All 7 files below use `showAppBottomSheet` and contain Material-dependent widgets that are reachable through sheet-presented content:

1. **`lib/features/gigs/widgets/view_gig_drawer.dart`**
   - **Material widgets:** 3 `ListTile` (navigation picker), 1 `InkWell` (\_DetailRow when onTap != null)
   - **Reachability:** Confirmed broken (screenshot evidence from user) — Setlist/Notes detail rows crash
   - **Context:** Setlist row (`_DetailRow(label: 'Setlist', ..., onTap: ...)`) wraps in InkWell, Notes row similar

2. **`lib/features/contacts/widgets/venue_detail_screen.dart`**
   - **Material widgets:** 3 `ListTile` (navigation picker: Apple Maps, Google Maps, Waze), 1 `IconButton` (navigation icon)
   - **Reachability:** Navigation picker (`_showNavigationAppPicker`) uses `showAppBottomSheet` directly, presents 3 `ListTile` widgets
   - **Context:** User taps navigation icon → picker opens → 3 ListTiles crash

3. **`lib/features/contacts/widgets/band_member_detail_drawer.dart`**
   - **Material widgets:** 1 `InkWell` (\_DetailRow when onTap != null, used for Phone/Email rows)
   - **Reachability:** Phone/Email rows use `_DetailRow(label: 'Phone', ..., onTap: _launchPhone)` which wraps in InkWell
   - **Context:** Member detail drawer with phone/email tappable rows

4. **`lib/features/contacts/widgets/band_member_edit_drawer.dart`**
   - **Material widgets:** 1 `SwitchListTile` (line 649, contributor permissions toggle)
   - **Reachability:** Role management drawer, contributor role selected → sub-permissions section renders SwitchListTile
   - **Context:** Admin editing member role → switches for permissions crash

5. **`lib/features/calendar/widgets/calendar_subscription_dialog.dart`**
   - **Material widgets:** 1 `InkWell` (line 455, close button or similar interactive element)
   - **Reachability:** Calendar subscription dialog presented via `showAppBottomSheet`
   - **Context:** User opens calendar subscription → InkWell crashes

6. **`lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`**
   - **Material widgets:** 1 `InkWell` (line 599, likely in setlist option tile)
   - **Reachability:** Setlist picker presented via `showAppBottomSheet`
   - **Context:** User adds songs to setlist → picker opens → option tiles crash

7. **`lib/features/setlists/widgets/key_picker_bottom_sheet.dart`**
   - **Material widgets:** 2 `ListTile` (key selection rows: major keys, minor keys)
   - **Reachability:** Key picker presented via `showAppBottomSheet` directly
   - **Context:** User edits song key → picker opens → all key tiles crash

### Unaffected Files (Confirmed via Code Inspection)

The following files use `showAppBottomSheet` but do **not** contain Material-dependent widgets (only GestureDetector, Container, AppButton, etc.):

- `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` — Uses only GestureDetector, no InkWell/ListTile
- `lib/features/calendar/widgets/add_block_out_drawer.dart` — Uses only AppButton, AppTextField
- `lib/features/setlists/widgets/pause_creator.dart` — Uses only AppButton, AppTextField
- `lib/features/setlists/widgets/set_break_creator.dart` — Uses only AppButton, AppTextField
- `lib/features/setlists/widgets/custom_tuning_modal.dart` — Uses only GestureDetector, AppButton, AppTextField

These files are explicitly out of scope and must not be modified.

---

## Proposed Solution

### Strategy: Root Fix in `app_bottom_sheet.dart`

Wrap the builder output in a transparent Material widget inside `showAppBottomSheet`, matching Flutter's stock `showModalBottomSheet` behavior. This fixes all current and future usages in a single location.

### Implementation

Modify `lib/components/ui/app_bottom_sheet.dart`:

**Before:**

```dart
return showFSheet<T>(
  context: context,
  builder: builder,  // Direct passthrough
  side: FLayout.btt,
  barrierDismissible: isDismissible,
  useRootNavigator: useRootNavigator,
);
```

**After:**

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(
    type: MaterialType.transparency,
    child: builder(context),
  ),
  side: FLayout.btt,
  barrierDismissible: isDismissible,
  useRootNavigator: useRootNavigator,
);
```

### Why This Works

- `Material(type: MaterialType.transparency)` provides a Material ancestor for ink effects without introducing visual artifacts (no background color, no elevation shadow)
- All Material-dependent widgets (`InkWell`, `ListTile`, `SwitchListTile`) can now locate the ancestor and render correctly
- Widgets that don't need Material (GestureDetector, Container, etc.) are unaffected — the Material wrapper is a no-op for them
- Matches the behavior of Flutter's stock `showModalBottomSheet` (which internally wraps content in Material)
- Zero visual regression risk — `MaterialType.transparency` is explicitly designed for this use case

### Why Root Fix Over Per-File Fix

**Root fix (chosen):**

- Single point of change
- Fixes all 7 affected files simultaneously
- Prevents this bug from recurring in future bottom sheet implementations
- Aligns with Flutter framework conventions (Material ancestor provided by sheet implementation, not by sheet content)
- No per-file code changes required → zero risk of introducing new bugs in feature files

**Per-file fix (rejected):**

- Requires modifying 7 files (high diff surface)
- Each file modification introduces risk (layout shifts, lost context, missed edge cases)
- Does not prevent recurrence — future sheets with Material widgets will hit the same bug
- Violates DRY principle — Material wrapper logic duplicated across 7 files
- Increases QA surface — must validate 7 files individually vs. 1 root fix

---

## Database Impact

**Not applicable.** This is a UI widget layer bug. No database tables, RLS policies, RPCs, or migrations are involved.

---

## Flutter Architecture Changes

### State Management

**Not affected.** No state controllers or Riverpod providers are modified.

### Repositories

**Not affected.** No data access layer changes.

### Widgets

**Modified:** `lib/components/ui/app_bottom_sheet.dart` — Wrap builder output in Material(type: MaterialType.transparency)

**Repaired (no code changes):** All 7 affected files listed in "Existing System Analysis" are automatically fixed by the root change.

---

## Files to Create

**None.** This is a single-line fix to an existing file.

---

## Files to Modify

| File                                      | What changes                                                                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_bottom_sheet.dart` | Wrap the builder output in `Material(type: MaterialType.transparency, child: builder(context))` inside the `showFSheet` call |

---

## Files Off-Limits

| File                                                              | Reason                                                        |
| ----------------------------------------------------------------- | ------------------------------------------------------------- |
| `lib/main.dart`                                                   | Init order must not change                                    |
| `lib/features/gigs/widgets/view_gig_drawer.dart`                  | Fixed by root change — no direct modification required        |
| `lib/features/contacts/widgets/venue_detail_screen.dart`          | Fixed by root change — no direct modification required        |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart`    | Fixed by root change — no direct modification required        |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart`      | Fixed by root change — no direct modification required        |
| `lib/features/calendar/widgets/calendar_subscription_dialog.dart` | Fixed by root change — no direct modification required        |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`  | Fixed by root change — no direct modification required        |
| `lib/features/setlists/widgets/key_picker_bottom_sheet.dart`      | Fixed by root change — no direct modification required        |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`      | Unaffected (uses only GestureDetector) — do not modify        |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`         | Unaffected (uses only AppButton/AppTextField) — do not modify |
| `lib/features/setlists/widgets/pause_creator.dart`                | Unaffected (uses only AppButton/AppTextField) — do not modify |
| `lib/features/setlists/widgets/set_break_creator.dart`            | Unaffected (uses only AppButton/AppTextField) — do not modify |
| `lib/features/setlists/widgets/custom_tuning_modal.dart`          | Unaffected (uses only GestureDetector) — do not modify        |
| `lib/components/ui/app_button.dart`                               | PR #148 complete, not a regression source — do not touch      |
| Any file containing `AppButton` call sites                        | Not related to this bug — do not touch                        |

---

## System Impact Map

| System                                 | Impact                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| Gigs                                   | **affected** — view_gig_drawer.dart fixed                                           |
| Rehearsals                             | unaffected                                                                          |
| Setlists / Catalog                     | **affected** — setlist_picker_bottom_sheet.dart, key_picker_bottom_sheet.dart fixed |
| Members / RBAC                         | **affected** — band_member_detail_drawer.dart, band_member_edit_drawer.dart fixed   |
| Auth / Session                         | unaffected                                                                          |
| Routing                                | unaffected                                                                          |
| Notifications                          | unaffected                                                                          |
| Contacts / Venues                      | **affected** — venue_detail_screen.dart fixed                                       |
| Calendar                               | **affected** — calendar_subscription_dialog.dart fixed                              |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms repaired (crash was cross-platform)                    |

---

## Regression Risk

**LOW**

### Rationale

1. **Single file modified:** Only `app_bottom_sheet.dart` changes (1 line added)
2. **Material.transparency is a no-op for visual rendering:** No background color, no elevation, no shadow — purely an ancestor provider
3. **Matches Flutter framework convention:** Flutter's stock `showModalBottomSheet` uses the same pattern
4. **All existing sheets unaffected by Material presence:** Sheets using only GestureDetector/Container/AppButton do not interact with the Material layer
5. **Zero layout changes:** Material(type: transparency) does not affect layout, spacing, or sizing
6. **No state management changes:** No controllers, providers, or repositories modified
7. **No database changes:** No RLS, migrations, or RPCs involved
8. **Blast radius:** Only bottom sheets presented via `showAppBottomSheet` are affected — scoped impact

### Why Not Higher Risk

- This is not a refactor or architectural change — it's a compatibility shim
- Material.transparency is explicitly designed for this use case (providing Material ancestor without visual artifacts)
- All affected files are automatically fixed without per-file changes → no risk of per-file implementation bugs
- Testing surface is small: verify Material-dependent widgets render correctly in sheets

---

## Engineer Task Breakdown

### Task 1: Verify current failure state

1. Launch app (web or iOS)
2. Navigate to Home → open any gig with a linked setlist
3. Tap the gig to open ViewGigDrawer
4. Observe: Setlist row renders red error box with "No Material widget found"
5. Document the exact error message and stack trace

### Task 2: Implement root fix in app_bottom_sheet.dart

1. Open `lib/components/ui/app_bottom_sheet.dart`
2. Locate the `showFSheet` call (line ~19)
3. Wrap the builder output in Material:
   ```dart
   builder: (context) => Material(
     type: MaterialType.transparency,
     child: builder(context),
   ),
   ```
4. Save file

### Task 3: Verify fix — ViewGigDrawer (confirmed broken)

1. Hot restart
2. Navigate to Home → open the same gig with linked setlist
3. Tap the gig to open ViewGigDrawer
4. Verify: Setlist row renders correctly (no red error box)
5. Verify: Notes row renders correctly (if gig has notes)
6. Tap Setlist row → verify navigation works
7. Tap Notes row → verify sheet opens

### Task 4: Verify fix — VenueDetailScreen navigation picker

1. Navigate to Contacts → Venues → tap any venue with address
2. Tap the navigation icon
3. Verify: Navigation picker sheet opens with 3 ListTile options (Apple Maps, Google Maps, Waze)
4. Tap each option → verify no crash, picker closes correctly

### Task 5: Verify fix — BandMemberDetailDrawer

1. Navigate to Members → tap any member with phone or email
2. Verify: Phone/Email rows render correctly (no red error box)
3. Tap Phone row → verify phone dialer launches (if device supports)
4. Tap Email row → verify email client launches (if device supports)

### Task 6: Verify fix — BandMemberEditDrawer

1. As admin: Navigate to Members → tap any member → tap "Edit"
2. Select "Contributor" role
3. Verify: Sub-permissions section renders with SwitchListTile toggles (no red error box)
4. Toggle each switch → verify state updates correctly

### Task 7: Verify fix — CalendarSubscriptionDialog

1. Navigate to Calendar → tap subscription icon (or trigger calendar subscription dialog)
2. Verify: Dialog opens, all interactive elements render correctly (no red error box)
3. Close dialog → verify no crash

### Task 8: Verify fix — SetlistPickerBottomSheet

1. Navigate to Setlists → Catalog → select 1+ songs → tap "Add To Setlist"
2. Verify: Picker sheet opens, setlist option tiles render correctly (no red error box)
3. Tap a setlist option → verify picker closes, songs added

### Task 9: Verify fix — KeyPickerBottomSheet

1. Navigate to Setlists → any setlist → tap a song → tap key field
2. Verify: Key picker opens, all key tiles render correctly (no red error box)
3. Tap a key (e.g., "C") → verify picker closes, key updates

### Task 10: Verify unaffected sheets (GestureDetector-only)

1. Navigate to Calendar → tap any date with events
2. Verify: DayDetailBottomSheet opens, renders correctly
3. Close sheet
4. Repeat for: AddBlockOutDrawer, PauseCreator, SetBreakCreator, CustomTuningModal
5. Confirm: All sheets open/close/interact correctly, no visual regression

### Task 11: Run flutter analyze

1. Run `flutter analyze` from project root
2. Confirm: 0 errors
3. Document any new warnings (there should be none)

### Task 12: Generate implementation report

1. Create `ENGINEER_REPORT.md` at `docs/features/forui-sheet-missing-material-ancestor/`
2. Document:
   - Tasks 1–11 completion status
   - flutter analyze output (0 errors)
   - Before/after screenshots for ViewGigDrawer Setlist row
   - Any deviations from plan

---

## Verification Plan

**No Tier 1/Tier 2 split required.** This is a UI widget fix with no database or backend component. All verification is post-implementation manual testing (documented in Engineer Task Breakdown above).

### Automated Test Coverage

Existing test file: `test/components/ui/app_bottom_sheet_test.dart`

**Verification:** Engineer must confirm all existing tests still pass after adding the Material wrapper. No new tests are required (Material.transparency is a no-op for rendering, existing tests implicitly verify the wrapper doesn't break functionality).

Run:

```bash
flutter test test/components/ui/app_bottom_sheet_test.dart
```

Expected: All tests pass, no failures.

### Manual Verification Checklist

Engineer must document in ENGINEER_REPORT.md:

**Primary fix verification (confirmed broken → fixed):**

- [ ] ViewGigDrawer Setlist row renders (screenshot before/after)
- [ ] ViewGigDrawer Notes row renders
- [ ] VenueDetailScreen navigation picker (3 ListTiles render)
- [ ] BandMemberDetailDrawer Phone/Email rows render
- [ ] BandMemberEditDrawer contributor permissions SwitchListTile renders
- [ ] CalendarSubscriptionDialog interactive elements render
- [ ] SetlistPickerBottomSheet option tiles render
- [ ] KeyPickerBottomSheet key tiles render

**Regression prevention (unaffected sheets still work):**

- [ ] DayDetailBottomSheet (GestureDetector-only) renders correctly
- [ ] AddBlockOutDrawer renders correctly
- [ ] PauseCreator renders correctly
- [ ] SetBreakCreator renders correctly
- [ ] CustomTuningModal renders correctly

**Cross-platform verification:**

- [ ] Web: ViewGigDrawer Setlist row + VenueDetailScreen navigation picker verified
- [ ] iOS: ViewGigDrawer Setlist row + BandMemberEditDrawer SwitchListTile verified
- [ ] Android: (if available) ViewGigDrawer Setlist row verified
- [ ] macOS: ViewGigDrawer Setlist row verified

---

## QA Regression Areas

QA must specifically test the following flows on at least 2 platforms (web + iOS minimum):

### Critical Path 1: Gig Details

1. Create/edit a gig with linked setlist and notes
2. From Home dashboard, tap the gig
3. Verify: ViewGigDrawer opens, all rows render correctly
4. Tap Setlist row → verify navigation to setlist detail
5. Tap Notes row → verify notes sheet opens
6. Tap navigation icon → verify navigation picker opens with 3 ListTile options

### Critical Path 2: Member Management

1. As admin: navigate to Members
2. Tap a member → verify detail drawer opens, Phone/Email rows render
3. Tap Phone/Email row → verify external app launches
4. Tap "Edit" → verify edit drawer opens
5. Select "Contributor" role → verify sub-permissions section renders with SwitchListTiles
6. Toggle each permission switch → verify state updates correctly
7. Save → verify role updates

### Critical Path 3: Setlist Operations

1. Navigate to Setlists → Catalog → select 2 songs
2. Tap "Add To Setlist" → verify picker opens, option tiles render
3. Select a setlist → verify songs added
4. Tap a song in the setlist → tap key field
5. Verify: Key picker opens, all key tiles render
6. Select a key → verify picker closes, key updates

### Critical Path 4: Venue Navigation

1. Navigate to Contacts → Venues → tap a venue with address
2. Tap navigation icon
3. Verify: Navigation picker opens, 3 ListTile options render
4. Tap an option (e.g., Google Maps) → verify external app launches

### Critical Path 5: Calendar Subscription

1. Navigate to Calendar → trigger subscription dialog
2. Verify: Dialog opens, all interactive elements render
3. Toggle feed preferences (if applicable with InkWell/switch)
4. Close dialog → verify no crash

### Regression Testing (Unaffected Sheets)

1. Open DayDetailBottomSheet → verify renders correctly, no visual change
2. Open AddBlockOutDrawer → verify renders correctly
3. Open PauseCreator, SetBreakCreator, CustomTuningModal → verify all render correctly

### Platform-Specific Testing

- **Web:** Verify all 5 critical paths
- **iOS:** Verify all 5 critical paths + phone/email tappability
- **Android:** (if available) Verify critical path 1 (gig details)
- **macOS:** Verify critical path 1 (gig details)

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-side UI fix. No server deployment, no migration, no data backfill required.

Rollout:

1. Engineer implements fix
2. QA approves
3. Merge to main
4. Deploy web build (next deployment cycle)
5. Native builds (iOS/Android) pick up fix on next app update

No user action required. Fix is transparent to users — sheets that previously crashed now render correctly.

---

## Out of Scope

The following are explicitly **out of scope** for this bug fix:

1. **Replacing Material widgets with Forui equivalents:** The goal is to fix the crash, not to refactor all Material usage. Material widgets (ListTile, InkWell, SwitchListTile) are still valid and supported — the fix ensures they work correctly in Forui sheets.

2. **Refactoring \_DetailRow across multiple files:** ViewGigDrawer and BandMemberDetailDrawer both have `_DetailRow` widgets with similar structure. These are intentionally file-local and not shared. No refactoring or consolidation in this cycle.

3. **Auditing all IconButton usage:** The user noted IconButton "appears empirically unaffected" but requested verification. Since IconButton has its own Material handling and is not crashing, a comprehensive audit is out of scope. If IconButton crashes are discovered later, they can be addressed in a separate bug fix.

4. **Migrating away from Forui sheets:** `showAppBottomSheet` using Forui's `showFSheet` is the current architectural decision (from PR #129, UI facade migration). This fix does not revert to Flutter's stock `showModalBottomSheet` — it repairs Forui sheet compatibility.

5. **Comprehensive Material audit across the codebase:** This fix addresses the specific crash in bottom sheets. Any Material dependency issues in other contexts (dialogs, overlays, etc.) are out of scope.

6. **Testing all 115 call sites of showAppBottomSheet:** The grep search returned 115 matches across 36 files. The 7 affected files identified in this plan are the only ones confirmed to contain Material-dependent widgets. QA must test these 7 specifically. Spot-checking other call sites is optional but not required.

---

## Additional Context

### Why This Bug Wasn't Caught in PR #129

PR #129 introduced `showAppBottomSheet` to replace `showModalBottomSheet` across ~20 files as part of the UI facade migration. At the time:

- Most sheets used only non-Material widgets (TextField, FilledButton, TextButton)
- QA verified visual rendering but did not test for Material dependency edge cases
- No test coverage for Material ancestor requirements

The bug surfaced later when Material-dependent widgets (ListTile, InkWell) were added to sheets in subsequent PRs (e.g., gig detail drawer setlist/notes rows, venue navigation picker).

### Why Material.transparency Is Safe

`Material(type: MaterialType.transparency)` is explicitly designed for this use case:

- No background color (transparent)
- No elevation shadow
- No clipping or shape
- Purely an ancestor provider for ink effects

It is used throughout Flutter's own framework (e.g., in `showModalBottomSheet`, Drawer, NavigationRail) for the exact same purpose: providing a Material ancestor without introducing visual artifacts.

### Why Root Fix Is Always Preferred Over Per-File Fix

This plan demonstrates the canonical BandRoadie approach to architectural bugs:

1. **Diagnose root cause** — Forui sheet missing Material ancestor
2. **Identify minimal fix point** — Single line in app_bottom_sheet.dart
3. **Fix once at the root** — All downstream usages repaired automatically
4. **Prevent recurrence** — Future sheets never hit this bug

Per-file fixes are only considered when:

- Root fix is impossible (no shared abstraction exists)
- Root fix would introduce unacceptable risk (changes core framework behavior)
- Files have fundamentally different requirements (not applicable here — all need Material ancestor)

This bug meets none of those conditions → root fix is the only acceptable solution.

---

**End of ARCHITECT_PLAN.md**
