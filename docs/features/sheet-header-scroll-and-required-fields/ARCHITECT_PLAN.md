# ARCHITECT PLAN

## Feature Slug
`sheet-header-scroll-and-required-fields`

## Feature Title
Sheet Header Scroll + Required-Fields Button Gate

## Problem Summary
Two independent UX improvements to modal sheets/drawers:

1. **Scrollable header (Change 2)**: Several sheets pin a visible title/header widget outside (above) the `SingleChildScrollView`, so when the form body scrolls, the header stays stuck to the top. The header content should scroll with the body so the full sheet height is available for form fields.

2. **Required-fields gate (Change 1)**: Most editor sheets enable the primary Save/Create button immediately on open, allowing a no-op save before any required fields are filled. The button should be disabled until the semantically required fields contain a value.

---

## Root Cause

### Change 2
Root cause: **Author choice, no single convention.**  
The codebase has two inconsistent patterns:
- **Already-scrolling pattern** (correct): header placed as first child *inside* the `SingleChildScrollView`.  
- **Fixed-header pattern** (to fix): header placed *outside* the `Flexible/Expanded → SingleChildScrollView` column, making it sticky.

Confidence: HIGH (confirmed by reading all 18 files).

### Change 1
Root cause: **Missing gate condition.**  
`_buildStickyFooter` in `event_editor_drawer.dart` derives `canSave` as `!_isSaving && !_isDeleting && (create || _isDirty)`. In create mode this is immediately `true`, regardless of required field state. The state fields that back the required fields (`_gigNameText`, `_gigCityText`, `_rehearsalLocationText`) are already updated via `setState` on every keystroke, so a simple getter can read them with no new listeners.

Confidence: HIGH.

---

## Existing System Analysis

### Files investigated and scrollability verdict

| File | Header status | Notes |
|---|---|---|
| `event_editor_drawer.dart` | **FIXED** – `_buildStickyHeader` above scroll | No drag-handle pill (full-screen-style editor) |
| `add_block_out_drawer.dart` | **FIXED** – title row above `Flexible → SingleChildScrollView` | Has drag handle + header + scroll |
| `band_member_edit_drawer.dart` | **FIXED** – 'Edit' label + name + role above `Flexible → SingleChildScrollView` | Has drag handle + header + scroll |
| `song_details_bottom_sheet.dart` | **FIXED** – `_buildHeader()` above `Expanded → SingleChildScrollView` | Drag handle outside, header outside |
| `song_enrichment_review_sheet.dart` | **FIXED** – `_buildHeader()` above `Flexible → SingleChildScrollView` | Drag handle outside, header outside |
| `song_notes_drawer.dart` | **FIXED** – `_buildHeader()` above `Flexible → SingleChildScrollView` | Drag handle outside, header outside |
| `gig_notes_sheet.dart` | **FIXED** – gigName text + divider above `Flexible → SingleChildScrollView` | Drag handle outside, header outside |
| `rehearsal_notes_sheet.dart` | **FIXED** – 'Rehearsal Notes' text + divider above `Flexible → SingleChildScrollView` | Drag handle outside, header outside |
| `day_detail_bottom_sheet.dart` | **FIXED** – date row + events-count above `ConstrainedBox(ListView)` | No `SingleChildScrollView`; uses ListView |
| `view_gig_drawer.dart` | ALREADY SCROLLS – header inside `SingleChildScrollView` | No change |
| `view_rehearsal_drawer.dart` | ALREADY SCROLLS – header inside `SingleChildScrollView` | No change |
| `view_block_out_drawer.dart` | ALREADY SCROLLS – header inside `SingleChildScrollView` | No change |
| `band_member_detail_drawer.dart` | ALREADY SCROLLS – header inside `SingleChildScrollView` | No change |
| `contact_detail_drawer.dart` | ALREADY SCROLLS – header inside `SingleChildScrollView` | No change |
| `add_financial_entry_bottom_sheet.dart` | ALREADY SCROLLS – drag handle + title inside `SingleChildScrollView` | No Change 2 needed |
| `gig_pay_bottom_sheet.dart` | ALREADY SCROLLS – drag handle + title inside `SingleChildScrollView` | No Change 2 needed |
| `setlist_picker_bottom_sheet.dart` | **N/A – skip** | Header contains Move/Copy interactive toggle that must remain visible while scrolling the setlist. Moving it into the scroll body would make the toggle inaccessible after minimal scroll. Fixed header is correct UX here. |

### Required-fields inventory (Change 1)

| File | Action | Required fields | Current gate | Needed? |
|---|---|---|---|---|
| `event_editor_drawer.dart` | Save/Create | Gig: name + city; Rehearsal: location; Block-out: none | `!_isSaving && !_isDeleting && (create\|\|dirty)` — no field check in create mode | **YES** |
| `add_block_out_drawer.dart` | Save | `_startDate` always initialized; reason optional | Already always enabled (date pre-set) | No — always valid |
| `band_member_edit_drawer.dart` | Save Role | Must have changed role/permissions | Already gated: `_hasChanges && !_isSaving` | No — already correct |
| `add_financial_entry_bottom_sheet.dart` | Save | amount > 0 | `_amountController.cents > 0` | No — already correct |
| `gig_pay_bottom_sheet.dart` | Save | amount > 0 | `_amountController.cents > 0` | No — already correct |
| `song_details_bottom_sheet.dart` | Save | No empty-able required field (song already exists) | `_hasChanges` | No — already correct |
| `song_notes_drawer.dart` | Save (edit mode) | Notes changed from original | `_isEditing ? (_hasChanges ? _handleSave : null)` | No — already correct |
| `song_enrichment_review_sheet.dart` | Save | All fields optional by spec: "Save is never gated" | Always enabled | No — by design |

**Net result for Change 1: one file requires modification** — `event_editor_drawer.dart`.

### Ambiguity notes (Change 1 — for Tony's awareness)
`event_editor_drawer.dart` existing `validate()` already treats **gig city** and **rehearsal location** as required. The plan uses the same criteria for the button gate (mirrors existing submit-time validation). However, if online-only gigs (no city) are a real use case, the city gate would block those users. This is flagged for Tony to confirm but is **not a stop-condition** — the plan uses the existing validation logic.

---

## Proposed Solution

### Change 2 — Scrollable header (9 files)
For each FIXED-header file, the structural change is identical in intent:

**General pattern (files with a `SingleChildScrollView`):**
1. Remove the header widget(s) and the divider that follows from the outer `Column`.
2. Make them the first child(ren) inside the `SingleChildScrollView`'s child `Column`.
3. Keep the drag-handle pill widget in its current position *outside* the scroll.
4. `SheetFooter` stays fixed outside the scroll — no change.

**Special case — `day_detail_bottom_sheet.dart`:**
No `SingleChildScrollView` exists. Replace `ConstrainedBox(ListView.separated)` with `Flexible → SingleChildScrollView → Column(children: [header, eventsCount, …event cards…])`. The date header and events-count move from the outer Column into this new scroll Column. Drag handle stays outside.

### Change 1 — Required-fields gate (`event_editor_drawer.dart` only)
Extract a `bool get _canSave` getter from the inline expression in `_buildStickyFooter`, and add type-specific field checks:

```dart
bool get _canSave {
  if (_isEditingExpense || _isSaving || _isDeleting || widget.viewOnly) {
    return false;
  }
  if (widget.mode == EventEditorMode.edit) return _isDirty;
  // Create mode: gate on type-specific required fields
  return switch (_eventType) {
    EventType.gig =>
        (_gigNameText?.trim().isNotEmpty ?? false) &&
        (_gigCityText?.trim().isNotEmpty ?? false),
    EventType.rehearsal =>
        (_rehearsalLocationText?.trim().isNotEmpty ?? false),
    EventType.blockOut => true,
    _ => true,
  };
}
```

Replace the local `canSave` variable in `_buildStickyFooter` with `_canSave`.

---

## Database Impact
Not applicable.

---

## Flutter Architecture Changes
Widget tree restructuring only. No new providers, controllers, repositories, or models. No new dependencies.

---

## Files to Create
None.

---

## Files to Modify

### Change 2 — Scrollable header

1. **`lib/features/events/widgets/event_editor_drawer.dart`**  
   In `build`: remove `_buildStickyHeader(context)` and `Container(height: 1, color: kEdCardBorder)` from the outer `Column`. In `_buildScrollableBody`: add `_buildStickyHeader(context)` and `Container(height: 1, color: kEdCardBorder)` as the first two items in the returned body `Column`.  
   Rename method from `_buildStickyHeader` → `_buildHeader` is optional and out of scope; rename only if zero-cost. Prefer not renaming.

2. **`lib/features/calendar/widgets/add_block_out_drawer.dart`**  
   In `build`: remove the title-row `Padding` block and `const SizedBox(height: Spacing.space16)` that precede the `Flexible`. Move them to be the first children inside `SingleChildScrollView`'s `Column`.

3. **`lib/features/contacts/widgets/band_member_edit_drawer.dart`**  
   In `build`: remove the header `Padding` block (containing 'Edit', member name, role text), `const SizedBox(height: Spacing.space16)`, and `const Divider(height: 1)` from the outer `Column`. Move them to be the first children inside `SingleChildScrollView`'s `Column`.

4. **`lib/features/setlists/widgets/song_details_bottom_sheet.dart`**  
   In `build`: remove `_buildHeader()` call and the `Divider` from the outer `Column`. Add `_buildHeader()` and `Divider(color: context.colors.border, height: 1)` as the first two children inside `SingleChildScrollView`.

5. **`lib/features/setlists/widgets/song_enrichment_review_sheet.dart`**  
   In `build`: remove `_buildHeader()` call and `Divider(color: context.colors.border, height: 1)` from the outer `Column`. Add them as first two children inside `SingleChildScrollView`.

6. **`lib/features/setlists/widgets/song_notes_drawer.dart`**  
   In `build`: remove `_buildHeader()` and `Divider(color: context.colors.border, height: 1)` from the outer `Column`. Add them as first two children inside `SingleChildScrollView`. Adjust `SingleChildScrollView` padding as needed so header has correct top padding.

7. **`lib/features/gigs/widgets/gig_notes_sheet.dart`**  
   In `build`: remove the `const SizedBox(height: Spacing.space16)`, gigName `Padding`, `const SizedBox(height: Spacing.space16)`, and `const Divider(height: 1)` from the outer `Column`. Add them as first children inside `SingleChildScrollView`.

8. **`lib/features/rehearsals/widgets/rehearsal_notes_sheet.dart`**  
   In `build`: same pattern as `gig_notes_sheet.dart` — remove `SizedBox`, 'Rehearsal Notes' `Padding`, `SizedBox`, `Divider` from outer `Column`; move them inside `SingleChildScrollView`.

9. **`lib/features/calendar/widgets/day_detail_bottom_sheet.dart`**  
   In `build`: remove `SizedBox(height: Spacing.space16)`, date header `Padding`, `SizedBox(height: Spacing.space8)`, events-count `Padding`, and `SizedBox(height: Spacing.space16)` from the outer `Column`. Remove `ConstrainedBox`. Replace with `Flexible → SingleChildScrollView → Column(children: [SizedBox(16), date header Padding, SizedBox(8), events count Padding, SizedBox(16), …event card items or empty state…])`.

### Change 1 — Required-fields gate

10. **`lib/features/events/widgets/event_editor_drawer.dart`** *(same file as Change 2 item 1 — single edit)*  
    In `_EventEditorDrawerState`: add `bool get _canSave` getter (as described in Proposed Solution). In `_buildStickyFooter`: replace `final canSave = !_isSaving && ...` (3 lines) with `onPrimary: _canSave ? _handleSave : null`.

---

## Files Off-Limits
All other files. Specifically:
- `lib/components/ui/sheet_footer.dart` — `SheetFooter` already supports `onPrimary: null` for disabled state; no changes needed.
- `lib/features/events/models/event_form_data.dart` — validation logic unchanged.
- Any repository, controller, provider, or migration file — not touched.
- `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart` — N/A (header intentionally fixed).

---

## Change Budget
| | Value |
|---|---|
| Expected net line delta per file | ±5–15 lines each across 9 files; ~+10 lines in event_editor_drawer.dart for getter |
| Expected new files | 0 |
| Expected new public classes/methods | 0 |
| Expected new dependencies | 0 |

If Engineer's diff shows >40 net lines changed in any single file for Change 2, QA should flag for review.

---

## System Impact Map
| System | Impact |
|---|---|
| Gigs | Affected — `event_editor_drawer.dart`, `view_gig_drawer.dart` (skip), `gig_notes_sheet.dart` |
| Rehearsals | Affected — `view_rehearsal_drawer.dart` (skip), `rehearsal_notes_sheet.dart` |
| Setlists | Affected — `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`, `song_notes_drawer.dart` |
| Calendar | Affected — `add_block_out_drawer.dart`, `day_detail_bottom_sheet.dart` |
| Members/Contacts | Affected — `band_member_edit_drawer.dart` |
| Auth | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| DB / RLS / RPCs | Unaffected |
| Platforms (iOS/Android/macOS/Web) | All platforms affected equally (UI change only, no platform-conditional code) |

---

## Regression Risk
**MEDIUM**

- All changes are widget tree restructuring and one getter addition — no data layer, no auth, no routing, no DB.
- The 9 scrollable-header files have low complexity; risk is purely visual (header not rendering in expected position, unexpected scroll physics).
- The 1 required-fields change in `event_editor_drawer.dart` carries slightly higher risk because it changes button behavior: in create mode the Save/Add button will now start disabled. Any path that opens the drawer with pre-filled data (e.g., edit mode populated from calendar tap, block-out edit) must ensure `_canSave` returns `true` immediately. For edit mode the existing `_isDirty` path is unchanged. For block-out create, `_canSave` returns `true` by the `EventType.blockOut` branch, which is correct. Pre-filled gig/rehearsal creates (from calendar day tap) open with no name/city populated, so the button correctly starts disabled.
- Risk factor elevated by `event_editor_drawer.dart` being the most complex file in the codebase (3 500+ lines).

---

## Engineer Task Breakdown

### Change 2 — Scrollable header (do these first)

**Task 1 — Notes-only sheets (identical structure)**  
Files: `gig_notes_sheet.dart`, `rehearsal_notes_sheet.dart`, `song_notes_drawer.dart`  
Action: In each `build` method, move the SizedBox spacer(s), header `Padding`, second spacer (if any), and `Divider` out of the outer `Column` and into the `SingleChildScrollView` child as its first children. Drag handle stays outside in all three.  
Constraint: `song_notes_drawer.dart` uses `_buildDragHandle()` and `_buildHeader()` helper methods — move only the `_buildHeader()` call (not `_buildDragHandle()`).

**Task 2 — Song sheets**  
Files: `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`  
Action: Both share the pattern: `_buildDragHandle()` + `_buildHeader()` + `Divider` in outer `Column` above scroll. Move `_buildHeader()` and `Divider` inside `SingleChildScrollView`. Keep `_buildDragHandle()` outside.

**Task 3 — Form drawers**  
Files: `add_block_out_drawer.dart`, `band_member_edit_drawer.dart`  
Action per file:
- `add_block_out_drawer.dart`: move title `Row` + `SizedBox(space16)` before `Flexible` into `SingleChildScrollView` as first children.
- `band_member_edit_drawer.dart`: move header `Padding` (Edit/name/role), `SizedBox(space16)`, and `Divider(height: 1)` from the outer Column into `SingleChildScrollView` as first children.

**Task 4 — Event editor drawer (Change 2 portion)**  
File: `event_editor_drawer.dart`  
Action: In `build`, remove `_buildStickyHeader(context)` and `Container(height: 1, color: kEdCardBorder)` from the outer `Column`. In `_buildScrollableBody`, add them as the first two items in the returned body content. No rename.

**Task 5 — Day detail bottom sheet**  
File: `day_detail_bottom_sheet.dart`  
Action: Remove `SizedBox(space16)`, date-header `Padding`, `SizedBox(space8)`, events-count `Padding`, `SizedBox(space16)`, and the `ConstrainedBox(ListView)` from the outer Column. Replace with `Flexible → SingleChildScrollView → Column` that starts with those header items followed by either the event-card list or the empty-state widget. `shrinkWrap: false` on the inner `ListView` is no longer needed since it is inside a `SingleChildScrollView`; use `shrinkWrap: true` or convert to a `Column` of items (preferred for small item counts). Drag handle stays outside.

### Change 1 — Required-fields gate

**Task 6 — Add `_canSave` getter and update footer**  
File: `event_editor_drawer.dart` (same file as Task 4 — apply together in one PR commit)  
Action:
1. Add `bool get _canSave` getter to `_EventEditorDrawerState` using the logic in Proposed Solution.
2. In `_buildStickyFooter`, replace:
   ```dart
   final canSave = !_isSaving &&
       !_isDeleting &&
       (widget.mode == EventEditorMode.create || _isDirty);
   return SheetFooter(
     ...
     onPrimary: canSave ? _handleSave : null,
   ```
   with:
   ```dart
   return SheetFooter(
     ...
     onPrimary: _canSave ? _handleSave : null,
   ```
   (remove the `canSave` local variable entirely).

---

## Verification Plan

### Tier 1 — Pre-deploy (static, no app launch)
1. `flutter analyze` — must report zero new errors/warnings in the 9 modified files.
2. Read each modified `build` method and confirm: drag handle appears before `SingleChildScrollView`, header appears as first child inside `SingleChildScrollView`, `SheetFooter` appears after the `Flexible/Expanded` in the outer `Column`.
3. For `event_editor_drawer.dart`: read `_canSave` getter and confirm each branch; confirm that `_buildStickyFooter` no longer contains a `canSave` local variable.

### Tier 2 — Post-deploy (device/simulator, visual check per sheet)
For each of the 9 scrollable-header sheets, open the sheet on a device and scroll the body:

| Sheet | Open path | Expected |
|---|---|---|
| `gig_notes_sheet.dart` | View gig → tap Notes detail row | Gig name scrolls with notes content |
| `rehearsal_notes_sheet.dart` | View rehearsal → tap Notes detail row | 'Rehearsal Notes' title scrolls with content |
| `song_notes_drawer.dart` | Open a song → Notes button | Header scrolls with notes text area |
| `song_details_bottom_sheet.dart` | Tap a song card | 'Song Details' header scrolls with form |
| `song_enrichment_review_sheet.dart` | Catalog search → tap external result | 'Review Song' header scrolls with metrics |
| `add_block_out_drawer.dart` | Calendar → Add Block Out | 'Add Block Out' title scrolls with date fields |
| `band_member_edit_drawer.dart` | Members → tap member → Edit | Edit + name + role header scrolls with role picker |
| `event_editor_drawer.dart` | Calendar → Add Event | Title scrolls with form fields; EventTypeSelector scrolls away on scroll |
| `day_detail_bottom_sheet.dart` | Calendar → tap a day with 2+ events | Date + events count scrolls with event cards |

For Change 1 (`event_editor_drawer.dart`):
- Open Add Event (Gig). Confirm Save button is disabled. Type a venue name → still disabled (city empty). Type a city → Save button enables. Clear venue name → Save button disables again.
- Open Add Event (Rehearsal). Confirm Save button is disabled. Type a location → Save button enables.
- Open Add Block Out (create). Confirm Save button is enabled immediately (date always pre-set).
- Open Edit Event. Confirm Save button starts disabled (not dirty). Change any field → enables. Revert → disables.

---

## QA Regression Areas
1. **All 9 scrollable-header sheets**: drag handle must stay pinned (not scroll away).
2. **`SheetFooter`** in all sheets: must remain fixed at the bottom (not scroll).
3. **`event_editor_drawer.dart` create mode**: button re-enables when required fields are filled; does not regress edit mode (button starts disabled, enables on first change).
4. **`day_detail_bottom_sheet.dart`**: sheet height should not change noticeably; event-card tap handlers must still fire.
5. **`band_member_edit_drawer.dart` / `song_notes_drawer.dart`**: divider position must appear between header and body content, not float.

---

## Rollout Strategy
Ship together (Change 2 + Change 1) in one PR — they touch overlapping files and both are UI-only, no feature flags needed. No DB migration. Deploy to web first; verify on iOS/Android simulator before release.

---

## Out of Scope
- `setlist_picker_bottom_sheet.dart` — fixed header is correct for this sheet's UX.
- `add_financial_entry_bottom_sheet.dart` / `gig_pay_bottom_sheet.dart` — header already scrolls; drag handle inside scroll is pre-existing and not part of this request.
- Renaming `_buildStickyHeader` in `event_editor_drawer.dart`.
- Adding required-field gating to any sheet beyond `event_editor_drawer.dart`.
- Any new tests for sheets that have no existing test file.
