# Architect Plan — Detail Sheet Sizing & Venue Back Button

## Feature Slug

`feature/detail-sheet-sizing-venue-back`

## Problem Summary

Read-only "view" sheets (View Gig, View Rehearsal, View Band Member, View Block Out) cap height at 90% screen height, causing fully-populated content to require in-sheet scrolling. Edit sheets (Event Editor, Block Out Editor) also use 90% cap and need full-height treatment. No "View Contact" sheet exists—tapping a contact opens the edit form directly. VenueDetailScreen lacks an explicit back button in its AppBar.

## Root Cause

**Confidence: HIGH (direct observation in code)**

**Primary constraint: Forui's `showFSheet` default `mainAxisMaxRatio: 9/16` (0.5625)**

The binding constraint is **not** the local `Container(maxHeight: ...)` multipliers in each drawer. It is the ancestor constraint applied by Forui's sheet system, which every downstream `Container` is subject to.

`lib/components/ui/app_bottom_sheet.dart` wraps Forui's `showFSheet()` but never passes a `mainAxisMaxRatio` argument:

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(type: MaterialType.transparency, child: builder(context)),
  side: FLayout.btt,
  barrierDismissible: isDismissible,
  useRootNavigator: useRootNavigator,
);
```

Per Forui's API signature (confirmed in `docs/features/forui-design-system-swap/API_CORRECTIONS.md` line 496):

```dart
Future<T?> showFSheet<T>({
  ...
  double? mainAxisMaxRatio = 9 / 16,  // defaults to 0.5625
  ...
})
```

Forui's `ShiftedSheet` render object applies this ratio as a hard `BoxConstraints.maxHeight` ancestor constraint on the sheet's child. Since Flutter constraints only tighten descending the widget tree, every downstream `Container(maxHeight: MediaQuery.of(context).size.height * 0.9)` set inside individual drawers is **looser** than 0.5625 and therefore **never the binding constraint**.

**Result:** Every sheet in the app going through `showAppBottomSheet` is capped at ~56% of screen height, regardless of what local maxHeight multipliers individual drawers specify. The previous Engineer changes (0.9 → 0.95 for view sheets, removing 0.9 for edit sheets) had **no visible effect** because they never tightened beyond the ancestor 9/16 cap.

### Secondary Analysis: `showModalBottomSheet` Path (view_rehearsal_drawer.dart, view_block_out_drawer.dart)

Two view sheets bypass `showAppBottomSheet` and call Flutter's native `showModalBottomSheet` directly with `isScrollControlled: true`:

- `view_rehearsal_drawer.dart` line 35
- `view_block_out_drawer.dart` line 26

Flutter's default `showModalBottomSheet` behavior:

- **Without** `isScrollControlled: true`: caps at 9/16 of screen height (same as Forui's default)
- **With** `isScrollControlled: true`: allows full screen height (no artificial cap)

These two files **already pass `isScrollControlled: true`**, so they are not affected by a 9/16 constraint—they can grow to full height if their internal `Container(maxHeight: 0.9)` allows. The previous Engineer change (0.9 → 0.95) on these two files **may have had a visible effect** depending on whether their content height exceeds the cap.

However, this is a **pre-existing inconsistency** explicitly excluded from scope per the original Feature Input (no migration between `showModalBottomSheet` and `showAppBottomSheet` wrappers).

### Contact and Venue Issues (Unaffected by Height Constraint)

3. **Contact tap wiring**:
   - `contacts_view.dart`: Contact card tap calls `_openContactForm`, navigating directly to `ContactFormScreen` (edit mode)
   - No read-only View Contact drawer exists (separate UX issue, unrelated to height caps)

4. **VenueDetailScreen**:
   - Line 30: `AppAppBar` has title but no `leading` parameter (separate navigation issue, unrelated to height caps)
   - AppAppBar does not auto-render back buttons from `Navigator.canPop()`

## Reference Docs Consulted

No UI/sheet reference documentation exists in `docs/reference/`.

## Existing System Analysis

### View Sheets Pattern

All view sheets share this structure:

```dart
Container(
  constraints: BoxConstraints(
    maxHeight: MediaQuery.of(context).size.height * 0.9,
  ),
  child: Column(
    children: [
      // Drag handle
      // Flexible + SingleChildScrollView for scrollable body
      // Fixed footer with Done/Edit buttons
    ],
  ),
)
```

When content exceeds ~85% screen height (accounting for drag handle + footer + safe areas), users must scroll within the sheet. Typical fully-populated content (e.g., View Gig with all optional fields filled) triggers this scrolling.

### Edit Sheets Pattern

- **EventEditorDrawer**: 90% cap at line 2499, no keyboard-aware offset subtraction
- **BlockOutDrawer**: 90% cap with keyboard offset subtraction at line 567

### Contact Tap Flow

`ContactCard` tap → `_openContactForm` → `Navigator.push(ContactFormScreen)` (edit mode)

No intermediate read-only view step exists. Users expect a "view" sheet with edit affordance, matching the Gig/Rehearsal/BandMember pattern.

### VenueDetailScreen

Full-screen route with `AppAppBar`, no `leading` parameter passed. Per codebase convention (see `ContactFormScreen` line 206, `VenueFormScreen`), explicit back/close button is required—AppAppBar does not infer from Navigator.

## Proposed Solution

### 1. Fix the Shared Constraint: Add `mainAxisMaxRatio` Parameter to `showAppBottomSheet`

**File:** `lib/components/ui/app_bottom_sheet.dart`

Add new optional parameter `mainAxisMaxRatio` to `showAppBottomSheet()` and forward it to `showFSheet()` with explicit fallback:

```dart
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool useRootNavigator = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? barrierColor,
  double? mainAxisMaxRatio,  // NEW: defaults to null
}) {
  return showFSheet<T>(
    context: context,
    builder: (context) => Material(type: MaterialType.transparency, child: builder(context)),
    side: FLayout.btt,
    barrierDismissible: isDismissible,
    useRootNavigator: useRootNavigator,
    mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16),  // NEW: explicit fallback to Forui's default
  );
}
```

**Critical Detail: Why the `?? (9 / 16)` Fallback Is Mandatory**

In Dart, a default parameter value (e.g., Forui's `showFSheet`'s `mainAxisMaxRatio = 9/16`) only applies when the caller **omits** the argument—not when it's explicitly passed as `null`. If we forwarded `mainAxisMaxRatio: mainAxisMaxRatio` without the fallback, every `showAppBottomSheet` call site that doesn't pass this new parameter would send `null` explicitly through to `showFSheet`. Per Forui's render-object logic (`_mainAxisMaxRatio == null ? constraints.maxHeight : ...`), `null` means **uncapped height**, not "use the 9/16 default." This would silently break all ~136 other `showAppBottomSheet` call sites in the app that don't opt in to this feature—a catastrophic regression far outside scope.

The `?? (9 / 16)` fallback ensures that when a call site omits `mainAxisMaxRatio` (defaults to `null`), we pass `9 / 16` explicitly to `showFSheet`, preserving the current behavior for all existing sheets.

**Design Decision: Safe Default, Opt-In Per Call Site**

- **Default:** `mainAxisMaxRatio: null` → Forui's default (9/16) applies
- **Rationale:** `showAppBottomSheet` is used by 40+ sheets across the app (145 call sites in 43 files per grep). Changing the global default would affect **every sheet** with unknown visual impact—high blast radius. Instead, add the parameter and let individual call sites opt-in to taller sheets.
- **Alternative considered:** Change global default to `0.95` or `1.0` (full height) to match `showModalBottomSheet(isScrollControlled: true)` behavior. **Rejected** due to regression risk—would resize all existing sheets simultaneously, including pickers, menus, and simple dialogs that may be designed for compact presentation.

### 2. Update View Sheets: Pass `mainAxisMaxRatio: 0.95` to `showAppBottomSheet`

Files using `showAppBottomSheet` (modify call sites, not internal Container constraints):

- `view_gig_drawer.dart` line 41
- `band_member_detail_drawer.dart` line 38
- New `contact_detail_drawer.dart` (to be created) line ~34

**Changes:**

- Add `mainAxisMaxRatio: 0.95` parameter to `showAppBottomSheet()` call
- **Keep** existing internal `Container(maxHeight: 0.9)` unchanged—now that Forui's ancestor constraint is loosened to 0.95, the internal 0.9 will bind correctly (90% of screen after the 95% Forui cap no longer restricts)

Rationale: 95% Forui cap + 90% internal container = ~85% usable content area (accounting for drag handle + footer + safe areas), sufficient for typical fully-populated records without in-sheet scrolling.

### 3. Update Edit Sheets: Pass `mainAxisMaxRatio: 1.0` to `showAppBottomSheet`

Files using `showAppBottomSheet` (modify call sites):

- `event_editor_drawer.dart` — `showAppBottomSheet()` call site (locate via grep, not line number)
- `add_block_out_drawer.dart` line 88

**Changes:**

- Add `mainAxisMaxRatio: 1.0` (full height) parameter to `showAppBottomSheet()` call
- **Keep** existing internal `Container(maxHeight: ...)` with keyboard offset handling unchanged

Rationale: Edit forms need full vertical real estate. The internal containers already handle keyboard offset subtraction (`MediaQuery.of(context).size.height - keyboardHeight`) — removing the Forui 9/16 cap allows them to grow properly.

### 4. Handle `showModalBottomSheet` Path (view_rehearsal_drawer.dart, view_block_out_drawer.dart)

**Decision: Fix on Their Own Terms, Do Not Migrate**

These two files use Flutter's native `showModalBottomSheet(isScrollControlled: true)` directly (not `showAppBottomSheet`). Per original Feature Input scope, **do not migrate them** to `showAppBottomSheet` wrapper. However, they still have the 0.9 internal container cap that should be adjusted for consistency.

**Changes:**

- `view_rehearsal_drawer.dart` line 147: Change internal `Container(maxHeight: 0.9)` to `0.95`
- `view_block_out_drawer.dart` line 74: Change internal `Container(maxHeight: 0.9)` to `0.95`

**Rationale:** Since `isScrollControlled: true` removes Flutter's default 9/16 cap, these sheets are already free to grow. Changing internal container from 0.9 to 0.95 provides the same user-visible improvement as the `showAppBottomSheet` sheets without touching the wrapper inconsistency itself.

### 5. New View Contact Drawer (Unchanged from Original Plan)

Create `lib/features/contacts/widgets/contact_detail_drawer.dart`:

**Pattern source:** `BandMemberDetailDrawer` (read-only, 95% height, Done/Edit buttons)

**Display fields** (conditional on presence):

- Header: name (title style, no icon badge)
- Divider + Detail rows:
  - Title (if present)
  - Company (if present)
  - Phone (tappable → `tel:` URI)
  - Email (tappable → `mailto:` URI)
  - Notes (if present)

**Actions:**

- Done button (pop sheet)
- Edit button (pop sheet, navigate to `ContactFormScreen(contact: contact)`)

**Height configuration:**

- Use `showAppBottomSheet(mainAxisMaxRatio: 0.95, ...)` at call site
- Internal container: `maxHeight: MediaQuery.of(context).size.height * 0.9` (matches other view sheets)

**Wiring in `contacts_view.dart`:**

- Line 111 (or thereabouts—search for `_buildItem` with `onTap`): Replace `_openContactForm(context: context, contact: contact)` with:
  ```dart
  ContactDetailDrawer.show(
    context,
    contact: contact,
    onEdit: () => _openContactForm(context: context, contact: contact),
  )
  ```

### 6. VenueDetailScreen Back Button (Unchanged from Original Plan)

Line 30 (or thereabouts—search for `AppAppBar` in `venue_detail_screen.dart`), add `leading` parameter:

```dart
AppAppBar(
  leading: AppIconButton(
    icon: AppIcons.back,
    color: context.colors.textPrimary,
    onPressed: () => Navigator.of(context).pop(),
  ),
  title: Text('Venue Details', style: AppTextStyles.title3),
  backgroundColor: context.colors.surface,
)
```

Follows `ContactFormScreen` pattern.

## Database Impact

**Not applicable** — UI-only changes.

## Flutter Architecture Changes

**State:**

- No new providers
- No controller changes

**Widgets:**

- **Modified (shared component):** `app_bottom_sheet.dart` — added optional `mainAxisMaxRatio` parameter (backward compatible)
- **New:** `ContactDetailDrawer` (follows existing drawer pattern)
- **Modified:** 8 existing drawers (5 via `showAppBottomSheet` call-site parameter changes, 2 via internal `Container` constraints, 1 new Contact drawer)
- **Modified:** `contacts_view.dart` (tap handler)
- **Modified:** `venue_detail_screen.dart` (AppBar leading)

**Repositories:**

- No changes

**Critical Architecture Note:**

The shared component `app_bottom_sheet.dart` is modified for the first time to expose height control. This component is used by 40+ sheets across the app (145 call sites in 43 files). The change is additive (new optional parameter with safe default), but the blast radius requires elevated regression risk rating and mandatory cross-app smoke testing.

## Files to Create

| File                                                       | Justification                                                                                                                                                                                               |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/contact_detail_drawer.dart` | New read-only drawer for contacts, completing the view/edit separation pattern used for Gigs, Rehearsals, and Band Members. No shared component exists; must be feature-specific per existing architecture. |

## Files to Modify

| File                                                           | What changes                                                                                                                                                                                                                                                                                                                                          |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_bottom_sheet.dart`                      | **CRITICAL SHARED COMPONENT:** Add new optional parameter `mainAxisMaxRatio` (defaults to `null`) and forward to `showFSheet()` **with explicit `?? (9 / 16)` fallback**. Without the fallback, passing `null` explicitly means uncapped height (Forui behavior), breaking all ~136 existing call sites. Blast radius: used by 40+ sheets in the app. |
| `lib/features/gigs/widgets/view_gig_drawer.dart`               | Modify `showAppBottomSheet()` call site (line 41 or thereabouts) to pass `mainAxisMaxRatio: 0.95`. Internal `Container(maxHeight: 0.9)` unchanged.                                                                                                                                                                                                    |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`   | Line 147: Change internal `Container(maxHeight)` from `* 0.9` to `* 0.95`. Uses `showModalBottomSheet(isScrollControlled: true)` directly—not migrating to `showAppBottomSheet` per scope exclusion.                                                                                                                                                  |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | Modify `showAppBottomSheet()` call site (line 38 or thereabouts) to pass `mainAxisMaxRatio: 0.95`. Internal `Container(maxHeight: 0.9)` unchanged.                                                                                                                                                                                                    |
| `lib/features/calendar/widgets/view_block_out_drawer.dart`     | Line 74: Change internal `Container(maxHeight)` from `* 0.9` to `* 0.95`. Uses `showModalBottomSheet(isScrollControlled: true)` directly—not migrating to `showAppBottomSheet` per scope exclusion.                                                                                                                                                   |
| `lib/features/events/widgets/event_editor_drawer.dart`         | Modify `showAppBottomSheet()` call site (locate via grep—drawer contains both call site and implementation) to pass `mainAxisMaxRatio: 1.0`. Internal `Container(maxHeight: ...)` unchanged (keyboard handling preserved).                                                                                                                            |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`      | Line 88: Modify `showAppBottomSheet()` call to pass `mainAxisMaxRatio: 1.0`. Internal `Container(maxHeight: MediaQuery.of(context).size.height - keyboardHeight)` unchanged.                                                                                                                                                                          |
| `lib/features/contacts/widgets/contacts_view.dart`             | Modify `_buildItem()` onTap handler (search for contact card tap logic) to call `ContactDetailDrawer.show()` instead of `_openContactForm()` directly. Pass `onEdit` callback that navigates to `ContactFormScreen`.                                                                                                                                  |
| `lib/features/contacts/widgets/venue_detail_screen.dart`       | Line 30 (or thereabouts—search for `AppAppBar`): Add `leading: AppIconButton(icon: AppIcons.back, ...)` parameter.                                                                                                                                                                                                                                    |

**Note on File Count Change:** Original plan listed 8 files to modify + 1 to create. Corrected plan lists 9 files to modify + 1 to create (added `app_bottom_sheet.dart` as the root fix, all other changes flow from it).

## Files Off-Limits

| File                                                                                              | Reason                                                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart`                                      | Explicitly out of scope per Feature Input                                                                                                                                                           |
| `lib/components/ui/app_app_bar.dart`                                                              | Reference only — no modification needed; `leading` parameter already exists                                                                                                                         |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` (showModalBottomSheet inconsistency) | Feature Input explicitly excludes fixing the `showModalBottomSheet` vs `showAppBottomSheet` inconsistency. **However**, we are modifying the internal height constraint, not migrating the wrapper. |
| `lib/features/calendar/widgets/view_block_out_drawer.dart` (showModalBottomSheet inconsistency)   | Feature Input explicitly excludes fixing the `showModalBottomSheet` vs `showAppBottomSheet` inconsistency. **However**, we are modifying the internal height constraint, not migrating the wrapper. |

## System Impact Map

| System                                 | Impact                                                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | affected (view/edit drawer height via showAppBottomSheet + internal constraints)                                                   |
| Rehearsals                             | affected (view/edit drawer height via showModalBottomSheet internal constraints)                                                   |
| Setlists / Catalog                     | **POTENTIAL** (uses showAppBottomSheet for pickers/song notes—no height change per call site, but shared component modified)       |
| Members / RBAC                         | affected (view drawer height via showAppBottomSheet)                                                                               |
| Auth / Session                         | unaffected                                                                                                                         |
| Routing                                | unaffected                                                                                                                         |
| Notifications                          | unaffected                                                                                                                         |
| Platform (iOS / Android / Web / macOS) | affected (all platforms, UI-only)                                                                                                  |
| Contacts                               | affected (new view drawer, venue back button)                                                                                      |
| Calendar                               | affected (block out view/edit drawer height via showAppBottomSheet + showModalBottomSheet)                                         |
| **Shared UI Components**               | **CRITICAL:** app_bottom_sheet.dart modified (40+ sheets, 145 call sites). Additive change only, but must be validated across app. |

## Regression Risk

**Level: HIGH**

**Rationale:**

**Why HIGH (elevated from original LOW):**

1. **Shared component modification**: `app_bottom_sheet.dart` is used by 40+ sheets across the entire app (145 call sites in 43 files). While the change is additive (new optional parameter with safe default), any shared utility that touches this many surfaces carries elevated risk.

2. **Parameter forwarding chain**: The new `mainAxisMaxRatio` parameter passes through `showAppBottomSheet` → Forui's `showFSheet` → internal render object constraints. If parameter forwarding has issues (e.g., null handling, type mismatch), 145 call sites could be affected.

3. **Constraint precedence complexity**: The fix relies on understanding Flutter's constraint tightening rules (ancestor constraints bind over descendant constraints). If the understanding is wrong or Forui's implementation differs from documented behavior, the fix may not work as expected.

4. **Blast radius of failure**: If the shared component change causes issues (e.g., runtime error, unexpected layout behavior), every sheet in the app is at risk—not just the 9 explicit call sites we're modifying.

**Mitigations:**

- **Safe default preserved**: `mainAxisMaxRatio` defaults to `null`, which preserves Forui's existing 9/16 behavior for all sheets that don't explicitly pass the parameter. Only 9 call sites opt-in to new behavior.
- **Additive-only change**: No existing behavior is altered unless a call site explicitly passes the new parameter.
- **No database/auth/session risk**: UI-only changes, no backend interaction.
- **Contact view drawer is new**: No existing behavior to break.
- **VenueDetailScreen back button is additive**: Adds missing navigation, doesn't change existing paths.

**Required validation:**

- **Visual verification mandatory**: Previous QA round approved based on code review only, which failed to catch that the changes had no effect. This round requires actual device testing to confirm height changes are visible.
- **Cross-app smoke test**: Verify representative sheets from other features (setlist picker, song notes, calendar dialogs) still render correctly after `app_bottom_sheet.dart` modification.
- **Test all platforms**: iOS, Android, macOS, Web—constraint behavior may differ per platform.

## Engineer Task Breakdown

1. **Create ContactDetailDrawer** (new file)
   - Copy structure from `BandMemberDetailDrawer`
   - Replace MemberVM with Contact model
   - Update field display logic (title, company, phone, email, notes)
   - Implement phone/email tap handlers (URL launcher)
   - Add 95% height constraint

## Engineer Task Breakdown

**CRITICAL NOTE:** The previous implementation modified internal `Container(maxHeight: ...)` constraints but did not fix the actual binding constraint in `app_bottom_sheet.dart`. All previous height changes had **no visible effect**. This corrected plan fixes the root cause first, then adjusts call sites.

1. **Fix Shared Component: Add `mainAxisMaxRatio` to `app_bottom_sheet.dart`**
   - Add new optional parameter `mainAxisMaxRatio` (type: `double?`, default: `null`)
   - Forward parameter to `showFSheet()` call **with explicit fallback:** `mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16)`
   - **Critical:** Do NOT use bare `mainAxisMaxRatio: mainAxisMaxRatio` forwarding. Without the `?? (9 / 16)` fallback, passing `null` explicitly to Forui means uncapped height (per render-object logic: `_mainAxisMaxRatio == null ? constraints.maxHeight : ...`), which would silently break all ~136 existing call sites that don't opt in to this feature.
   - Verify parameter is properly typed and fallback is correct
   - **Sanity check (manual QA or unit test):** After implementing, confirm that a sheet which does NOT pass `mainAxisMaxRatio` (e.g., an existing setlist picker) still renders at the same ~56% height as before this feature. This validates that the fallback preserves backward compatibility.
   - **Critical:** This change affects 40+ sheets—test behavior with and without the parameter

2. **Create ContactDetailDrawer** (new file)
   - Copy structure from `BandMemberDetailDrawer`
   - Replace MemberVM with Contact model
   - Update field display logic (title, company, phone, email, notes)
   - Implement phone/email tap handlers (URL launcher)
   - Static `show()` method calls `showAppBottomSheet(mainAxisMaxRatio: 0.95, ...)`
   - Internal container: `maxHeight: MediaQuery.of(context).size.height * 0.9` (unchanged pattern)
   - Implement `onEdit` callback

3. **Wire ContactDetailDrawer into ContactsView**
   - Locate contact card `onTap` handlers (search for `_buildItem` with tap logic)
   - Replace `_openContactForm(context: context, contact: contact)` with:
     ```dart
     ContactDetailDrawer.show(context, contact: contact, onEdit: () => _openContactForm(...))
     ```

4. **Update View Sheet Heights via `showAppBottomSheet` Call Sites** (3 files)
   - `view_gig_drawer.dart`: Locate `showAppBottomSheet()` call, add `mainAxisMaxRatio: 0.95`
   - `band_member_detail_drawer.dart`: Locate `showAppBottomSheet()` call, add `mainAxisMaxRatio: 0.95`
   - Do **not** modify internal `Container(maxHeight: 0.9)` in these files—leave unchanged

5. **Update View Sheets via Internal Constraints** (2 files using `showModalBottomSheet`)
   - `view_rehearsal_drawer.dart` line 147: Change internal `Container(maxHeight: 0.9)` to `0.95`
   - `view_block_out_drawer.dart` line 74: Change internal `Container(maxHeight: 0.9)` to `0.95`
   - Do **not** change their `showModalBottomSheet` wrappers

6. **Update Edit Sheet Heights via `showAppBottomSheet` Call Sites** (2 files)
   - `event_editor_drawer.dart`: Locate `showAppBottomSheet()` call (grep for it—file contains both call and implementation), add `mainAxisMaxRatio: 1.0`
   - `add_block_out_drawer.dart` line 88: Modify `showAppBottomSheet()` call, add `mainAxisMaxRatio: 1.0`
   - Do **not** modify internal `Container(maxHeight: ...)` constraints—keyboard handling is already correct

7. **Add VenueDetailScreen Back Button**
   - Locate `AppAppBar` in `venue_detail_screen.dart`
   - Add `leading` parameter: `AppIconButton(icon: AppIcons.back, onPressed: () => Navigator.of(context).pop())`

8. **Verification Testing** (MANDATORY—visual confirmation required)
   - **Shared component smoke test:** Open 3-5 sheets from different features (e.g., setlist picker, song notes, gig notes) and verify they still render correctly (no regression from `app_bottom_sheet.dart` change)
   - **Target sheets:** For each modified sheet, measure actual height on device—confirm it visibly changed from previous 56% cap
   - **All platforms:** iOS, Android, macOS, Web
   - Verify keyboard doesn't obscure inputs in edit sheets
   - Verify Contact → View drawer → Edit flow
   - Verify Venue back button navigation

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — no database changes.

### Tier 2 — Post-deployment

**Not applicable** — no database changes.

### Manual UI Verification (MANDATORY—Visual Confirmation Required)

**CRITICAL:** The previous implementation was approved by QA based on code review only, which failed to detect that the changes had **no visible effect**. This round requires **actual device testing on all platforms** to confirm height changes are visible and the shared component modification did not break other sheets.

#### Part 1: Regression Testing (Shared Component Safety)

**Purpose:** Verify `app_bottom_sheet.dart` modification did not break existing sheets that are not explicitly in scope.

Test 3-5 representative sheets from different features (confirm they still render correctly):

1. **Setlist Picker** (from setlists feature) — open via "Add to Setlist" action
   - Verify sheet renders at expected compact height
   - Verify list scrolls, buttons are accessible
2. **Song Notes Drawer** (from setlists feature) — open via song context menu
   - Verify sheet renders, text field is accessible
   - Verify Save/Cancel buttons work
3. **Gig Notes Sheet** (from gigs feature) — open via "Notes" button on a gig
   - Verify sheet renders, notes display correctly
4. **Key Picker** (from setlists feature) — open via song key selection
   - Verify list of keys renders, selection works
5. **Calendar Subscription Dialog** (from calendar feature) — open via calendar settings
   - Verify dialog renders, switches work

If any of these fail to render or behave incorrectly, the `app_bottom_sheet.dart` change broke backward compatibility—STOP and investigate before proceeding.

#### Part 2: Target Feature Verification

For each platform (iOS, Android, macOS, Web):

**View Sheets (verify visible height increase from previous ~56% cap):**

1. Open View Gig drawer with all optional fields filled (load-in, setlist, pay, notes)
   - **Measure actual sheet height** (use screenshot or visual ruler app)—should be ~85-90% of screen height (up from ~56%)
   - Verify no scrolling required to see footer buttons for typical fully-populated content
   - Verify drag handle + footer visible simultaneously
2. Open View Rehearsal drawer with setlist and notes filled
   - **Measure actual sheet height**—should be ~85-90% (up from ~56%)
   - Verify no scrolling required to see footer buttons
3. Open View Band Member drawer with all fields filled (roles, phone, email, address, birthday)
   - **Measure actual sheet height**—should be ~85-90% (up from ~56%)
   - Verify no scrolling required to see footer buttons
4. Open View Block Out drawer (multi-day with reason)
   - **Measure actual sheet height**—should be ~85-90% (up from ~56%)
   - Verify no scrolling required to see footer buttons

**Edit Sheets (verify full height usage):**

5. Open Edit Gig drawer
   - **Measure actual sheet height**—should be full screen minus safe areas and keyboard (up from ~56% cap)
   - Focus on each text field (venue, city, address, notes)
   - Verify keyboard appears without obscuring focused field
   - Verify scroll works to access all fields with keyboard visible
6. Open Edit Rehearsal drawer
   - Focus on location and notes fields
   - Verify keyboard doesn't obscure inputs
7. Open Edit Block Out drawer
   - Focus on reason field
   - Verify keyboard doesn't obscure input
   - Verify "until date" picker is accessible with keyboard visible

**Contact View Drawer (new):**

8. Tap a contact card with all fields filled (title, company, phone, email, notes)
   - Verify View Contact drawer appears (not edit form)
   - Verify all filled fields are displayed
   - Tap phone → verify dialer opens
   - Tap email → verify mail client opens
   - Tap Edit button → verify ContactFormScreen opens
   - Save edit → verify drawer refreshes on return
9. Tap Done → verify drawer closes

**Venue Back Button:**

10. Navigate to Venue Detail screen
    - Verify back arrow appears in AppBar leading position
    - Tap back arrow → verify returns to Venues list

**Edge Cases:**

11. View Gig with minimal fields (name, location, time only)
    - Verify no scrolling required (content shouldn't be artificially tall)
12. Edit Gig with recurring settings, multi-date, expenses expanded
    - Verify all sections accessible with full height
    - Verify no content cut off at bottom

## QA Regression Areas

**Primary Focus: Visual Verification (MANDATORY)**

- **Height changes are actually visible**: Previous round failed to catch that code changes had no effect. QA must visually measure sheet heights on device—not just review code.
- **Shared component safety**: `app_bottom_sheet.dart` modification must not break existing sheets outside this feature's scope (test representative samples)

**Target Sheets:**

- **View sheets**: Verify typical fully-populated content is visible without in-sheet scrolling, sheet height visibly increased from ~56% to ~85-90%
- **Edit sheets**: Verify full height usage (not capped at 56%), keyboard doesn't obscure inputs
- **Contact workflow**: Verify view drawer appears on tap, edit routing works
- **Venue navigation**: Verify back button returns to Venues list

**Cross-Feature Regression:**

- **Setlists**: Song notes drawer, key picker, setlist picker still render correctly
- **Calendar**: Calendar subscription dialog still renders correctly
- **Gigs**: Gig notes sheet still renders correctly

**Cross-Platform:**

- Test on iOS, Android, macOS, Web (constraint behavior may differ)

**Platform-Specific Concerns:**

- **Safe areas**: Verify no content clipped on devices with notches/rounded corners
- **Keyboard interaction**: Verify no input fields obscured on all platforms
- **Drag-to-dismiss**: Verify all drawers still dismiss via drag gesture
- **Done/Edit buttons**: Verify footer buttons remain accessible in all sheets

## Rollout / Migration Strategy

**Not applicable** — UI-only changes, no migration required.

## Out of Scope

Explicitly excluded from this feature:

1. **Migrating `showModalBottomSheet` to `showAppBottomSheet`** in:
   - `view_rehearsal_drawer.dart`
   - `view_block_out_drawer.dart`

   **Clarification:** We ARE modifying these two files' internal `Container(maxHeight: 0.9 → 0.95)` constraints to fix the visible height issue, but we are NOT migrating them from `showModalBottomSheet` to `showAppBottomSheet` wrapper. The wrapper inconsistency remains untouched.

2. **Modifying `band_member_edit_drawer.dart`** for any reason

3. **Changing the global default for `mainAxisMaxRatio`** in `app_bottom_sheet.dart`—the parameter defaults to `null` (preserving Forui's 9/16 default), requiring explicit opt-in per call site to avoid blast radius across 40+ sheets

4. **Creating a shared height-control component** (no shared component pattern exists in the codebase; each drawer manages its own constraints)

5. **Changing AppAppBar auto-back-button behavior** (existing convention is explicit `leading` parameter; changing this would affect all screens)

6. **Handling block-out edit routing inconsistencies** (Feature Input notes dead code in `event_editor_drawer.dart` but states verification is needed before touching—this is Engineer's responsibility during implementation, not Architect's)

---

## Architect Plan Correction (2026-08-14)

**This document has been corrected from the original version approved on 2026-08-14.**

**What went wrong:**

The original plan diagnosed the sheet-height problem as each drawer's local `Container(maxHeight: MediaQuery.of(context).size.height * 0.9)` constraint and directed the Engineer to change that multiplier (0.9 → 0.95 for view sheets, remove entirely for edit sheets). QA approved based on code review. Tony then manually tested and found the edit sheets showed **no visible height change at all**.

**Actual root cause:**

`lib/components/ui/app_bottom_sheet.dart`'s `showAppBottomSheet()` wraps Forui's `showFSheet()` but never passes a `mainAxisMaxRatio` argument. Forui's `showFSheet` defaults `mainAxisMaxRatio` to `9/16` (0.5625), which its `ShiftedSheet` render object applies as a hard ancestor `BoxConstraints.maxHeight` on the sheet's child. Since Flutter constraints only tighten descending the tree, every downstream `Container(maxHeight: ...)` set inside individual drawers—regardless of whether it says 0.9, 0.95, or the full screen height—is looser than 0.5625 and therefore never the binding constraint. **Every sheet in the app going through `showAppBottomSheet` is capped at ~56% of screen height**, and none of the local edits made in the previous Engineer round had any effect.

**Corrected approach:**

1. Add optional `mainAxisMaxRatio` parameter to `showAppBottomSheet()` and forward to `showFSheet()`
2. Default to `null` (preserves existing 9/16 behavior for backward compatibility)
3. Modify 5 call sites to explicitly pass `mainAxisMaxRatio: 0.95` (view sheets) or `1.0` (edit sheets)
4. Keep internal `Container(maxHeight: ...)` constraints unchanged—they will bind correctly once the ancestor Forui cap is loosened
5. Modify 2 files using `showModalBottomSheet` directly (`view_rehearsal_drawer.dart`, `view_block_out_drawer.dart`) by changing their internal constraints only (no wrapper migration)

**Impact on scope:**

- **Files to modify:** Increased from 8 to 9 (added `app_bottom_sheet.dart`)
- **Regression risk:** Elevated from LOW to HIGH (shared component used by 40+ sheets)
- **Verification requirement:** Visual confirmation now mandatory (code review alone failed to catch the issue)

---

## Architect Plan Correction #2 (2026-08-14) — Safe Area Handling

**This is the second correction to this feature. Both corrections affect `app_bottom_sheet.dart` and should be reviewed together for the Engineer's next implementation pass.**

**What Tony found on device:**

Visual testing of Edit Gig on an iPhone with Dynamic Island revealed that the sheet's "Edit Gig" title and close button overlap the status bar (time/signal/battery icons drawn through the header row). This was confirmed via screenshot.

**Root cause (already diagnosed — verified here):**

`lib/components/ui/app_bottom_sheet.dart` declares `bool useSafeArea = false` as a parameter (line 24) but never forwards it to `showFSheet()` (line 28). This is dead code—the parameter is accepted but dropped.

**Forui's safe area handling (confirmed from source):**

Forui's `Sheet` widget explicitly handles `useSafeArea` per-side:

```dart
sheet = switch ((widget.side, widget.useSafeArea)) {
  (.btt, true)  => SafeArea(bottom: false, child: sheet),
  (.btt, false) => MediaQuery.removePadding(context: context, removeTop: true, child: sheet),
  ...
};
```

For `FLayout.btt` (bottom-to-top, what every `showAppBottomSheet` caller uses):

- **With `useSafeArea: true`:** Wraps content in `SafeArea(bottom: false)`, which adds top padding equal to the status bar height (preserves top safe area, removes bottom)
- **With `useSafeArea: false` (current state):** Actively **strips** the top `MediaQuery` padding via `MediaQuery.removePadding(removeTop: true)`

This means nothing downstream can compensate by reading `MediaQuery.of(context).padding.top` either—Forui explicitly removes it from the context.

**Why this wasn't visible until now:**

At `mainAxisMaxRatio: 0.95`, the sheet uses 95% of screen height, leaving ~5% (~42 points on iPhone 14 Pro) blank at the top by coincidence. This margin exceeds the status bar height, so the header doesn't collide. At `mainAxisMaxRatio: 1.0` (full height, as implemented for edit sheets in Correction #1), there's no blank margin left, so the header collides with the status bar.

**This is a latent defect in every sheet using `showAppBottomSheet`**, not just the two at `1.0`—it's just only visually triggered at full height on devices with status bars.

---

### Corrected Approach: Forward useSafeArea + Enable for Target Sheets

#### 1. Forward the Dead Parameter in app_bottom_sheet.dart

**File:** `lib/components/ui/app_bottom_sheet.dart`

The `useSafeArea` parameter is already declared (line 24) but never passed to `showFSheet()`. Add it to the call:

```dart
return showFSheet<T>(
  context: context,
  builder: (context) => Material(type: MaterialType.transparency, child: builder(context)),
  side: FLayout.btt,
  barrierDismissible: isDismissible,
  useRootNavigator: useRootNavigator,
  mainAxisMaxRatio: mainAxisMaxRatio ?? (9 / 16),
  useSafeArea: useSafeArea,  // NEW: forward the already-declared parameter
);
```

**Critical detail:** The parameter defaults to `false` in the function signature (line 24), preserving backward compatibility for all existing call sites that don't pass it. This is an additive change—no existing behavior changes unless a call site explicitly passes `useSafeArea: true`.

#### 2. Scope: Which Call Sites Should Pass useSafeArea: true?

**Mandatory (bug is visible):**

The two edit sheets at `mainAxisMaxRatio: 1.0` where header collision is confirmed:

1. `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` line 63
2. `lib/features/calendar/widgets/add_block_out_drawer.dart` line 88

**Strongly recommended (defense-in-depth):**

The three view sheets at `mainAxisMaxRatio: 0.95`:

1. `lib/features/gigs/widgets/view_gig_drawer.dart` line 41
2. `lib/features/contacts/widgets/band_member_detail_drawer.dart` line 38
3. `lib/features/contacts/widgets/contact_detail_drawer.dart` line 34

**Rationale for including view sheets:**

- The current 5% margin (0.95) provides ~42 points of blank space on an iPhone 14 Pro (844pt tall × 0.05), which exceeds the typical status bar height (~47pt including Dynamic Island base state)
- However, this margin is **coincidental**, not an intentional safe area design
- Dynamic Island can expand in active states (taller than base state)
- Larger notch devices or future devices might have different safe area insets
- The fix is already being made to the shared component—extending it to all sheets that could potentially collide is consistent and safe
- If a device's safe area inset exceeds the 5% margin, the view sheets would exhibit the same collision bug as the edit sheets

**Defense-in-depth recommendation: Apply `useSafeArea: true` to all 5 call sites** (2 edit + 3 view) to ensure no sheet headers collide with the status bar, regardless of device notch size or Dynamic Island state.

#### 3. Interaction with Internal Container(maxHeight: ...) Values

**Question:** Does passing `useSafeArea: true` interact with or conflict with the internal `Container(maxHeight: MediaQuery.of(context).size.height * 0.95)` values already present in each drawer?

**Analysis:**

When `useSafeArea: true` is passed to Forui's `showFSheet()` for `FLayout.btt` (bottom-to-top), Forui wraps the content in:

```dart
SafeArea(bottom: false, child: sheet)
```

This adds **padding** at the top equal to `MediaQuery.of(context).viewPadding.top` (which includes the status bar height + notch/Dynamic Island height). This padding is **inside** the sheet's allocated space, not outside it.

**How constraints compose:**

1. **Forui's sheet render object:** Applies `mainAxisMaxRatio` as a hard `BoxConstraints.maxHeight` on the sheet's root (e.g., 1.0 means full screen height, 0.95 means 95% of screen)
2. **SafeArea widget (when useSafeArea: true):** Adds top padding inside the sheet's allocated space, equal to the safe area inset (~47-59pt on notched iPhones)
3. **Internal Container(maxHeight: ...):** Evaluated downstream, inside the SafeArea padding

**Result:**

- `MediaQuery.of(context).size.height` inside the drawer is still the **full screen height** (SafeArea doesn't modify MediaQuery size, only adds padding to its child)
- The internal `Container(maxHeight: MediaQuery.of(context).size.height * 0.95)` will still try to be 95% of the full screen height
- However, the SafeArea's top padding **pushes the content down**, so the actual usable content area is reduced by the safe area inset
- This is **correct behavior**—the safe area inset is inside the sheet's allocated space, preventing collision with the status bar, and the content naturally flows within the remaining space

**Example for edit sheets (mainAxisMaxRatio: 1.0):**

- iPhone 14 Pro: 844pt tall screen, 59pt top safe area inset (with Dynamic Island)
- Sheet total height: 844pt (full screen)
- SafeArea top padding: 59pt
- Usable content area: 844pt - 59pt = 785pt
- Internal container tries to be full height, but SafeArea padding ensures the header starts 59pt from the top, avoiding collision

**Example for view sheets (mainAxisMaxRatio: 0.95):**

- Sheet total height: 844pt × 0.95 = 801.8pt
- SafeArea top padding: 59pt
- Usable content area: 801.8pt - 59pt = 742.8pt
- Internal container is already constrained to 0.95 (or similar), so no conflict

**Conclusion:**

No changes to internal `Container(maxHeight: ...)` values are needed. The SafeArea padding is applied **upstream** of the container, so the two constraints compose correctly. The container's maxHeight is relative to the full screen, while SafeArea's padding reduces the **usable** content area within that allocated space.

#### 4. Summary of Required Changes

**1 shared file + 5 call sites (small, targeted change):**

| File                                                           | Change                                                                                                      |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_bottom_sheet.dart`                      | Line 28-36: Add `useSafeArea: useSafeArea,` to `showFSheet()` call (forward the already-declared parameter) |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Line 63: Add `useSafeArea: true,` to `showAppBottomSheet()` call                                            |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`      | Line 88: Add `useSafeArea: true,` to `showAppBottomSheet()` call                                            |
| `lib/features/gigs/widgets/view_gig_drawer.dart`               | Line 41: Add `useSafeArea: true,` to `showAppBottomSheet()` call                                            |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | Line 38: Add `useSafeArea: true,` to `showAppBottomSheet()` call                                            |
| `lib/features/contacts/widgets/contact_detail_drawer.dart`     | Line 34: Add `useSafeArea: true,` to `showAppBottomSheet()` call                                            |

**Internal drawer constraints:** No changes required (SafeArea padding composes correctly with existing maxHeight values).

---

### Impact Assessment: Second Correction

**Files modified:** 1 shared + 5 call sites = **6 files total** (small scope)

**Regression risk:** **LOW** (additive-only change to shared component)

- The `useSafeArea` parameter defaults to `false`, preserving existing behavior for all ~12 call sites that don't explicitly pass it
- Only 5 call sites opt-in to `useSafeArea: true`
- No change to any other sheet's layout or behavior
- No database, routing, or state management impact

**Verification requirements:**

- **Visual confirmation on notched devices:** iPhone with Dynamic Island (or similar notch/island device)
  - Edit Gig: Confirm title/close button no longer overlap status bar
  - Edit Block Out: Confirm title/close button no longer overlap status bar
  - View Gig, View Band Member, View Contact: Confirm headers respect safe area
- **Regression check:** Test 2-3 unchanged sheets (e.g., song notes drawer, key picker) to confirm they still render at expected height without safe area padding (should still use full available height since they don't pass `useSafeArea: true`)
- **Test on devices without notches:** Verify no unintended padding added on devices with standard status bars (safe area inset should be smaller but still correct)

---

### Out of Scope (Correction #2)

- Changing the default value of `useSafeArea` in `app_bottom_sheet.dart` (keep `false` for backward compatibility)
- Adding `useSafeArea: true` to other sheets beyond the 5 identified call sites (can be addressed separately if needed)
- Modifying internal drawer constraints (no interaction with SafeArea padding)

---

### Engineer Notes: Both Corrections Apply

**This feature now has TWO corrections to `app_bottom_sheet.dart`:**

1. **Correction #1:** Add `mainAxisMaxRatio` parameter with `?? (9 / 16)` fallback, forward to `showFSheet()`
2. **Correction #2:** Forward existing `useSafeArea` parameter to `showFSheet()`

**Both changes should be implemented in a single pass.** The Engineer should:

1. Read both correction sections in full before starting
2. Apply both parameter forwards to `app_bottom_sheet.dart` simultaneously
3. Update all affected call sites (5 for `mainAxisMaxRatio`, 5 for `useSafeArea`, with overlap: 2 edit sheets get both, 3 view sheets get both)
4. Verify both fixes together on device (height increase + safe area respect)

**Combined call site updates:**

| Call Site                                  | mainAxisMaxRatio | useSafeArea |
| ------------------------------------------ | ---------------- | ----------- |
| `add_edit_event_bottom_sheet.dart` line 63 | `1.0`            | `true`      |
| `add_block_out_drawer.dart` line 88        | `1.0`            | `true`      |
| `view_gig_drawer.dart` line 41             | `0.95`           | `true`      |
| `band_member_detail_drawer.dart` line 38   | `0.95`           | `true`      |
| `contact_detail_drawer.dart` line 34       | `0.95`           | `true`      |

All 5 call sites get both parameters in the same edit.
