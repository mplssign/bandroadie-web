# ARCHITECT_PLAN — bug/mobile-keyboard-covers-event-actions

## 1. Problem Summary

On mobile devices, the on-screen keyboard covers the primary action buttons (Save, Cancel, Delete, Add Rehearsal, Add Gig) in event creation and editing drawers. This affects block out events, gigs, and rehearsals. Users cannot complete event flows without first blindly dismissing the keyboard.

## 2. Existing System Analysis

Two drawer widgets handle event forms on mobile:

### EventEditorDrawer (`lib/features/events/widgets/event_editor_drawer.dart`, 2301 lines)

- Used for gig, rehearsal, and block-out-within-event-editor flows.
- Opened via `AddEditEventBottomSheet.show()` which calls `showModalBottomSheet(isScrollControlled: true, backgroundColor: transparent)`.
- Layout structure: `Container(maxHeight: screenHeight * 0.9) > Column > [drag handle, header, Flexible(SingleChildScrollView), EventEditorBottomActions]`.
- The `maxHeight` constraint (line 1704) uses `MediaQuery.of(context).size.height * 0.9` — the full screen height, not accounting for keyboard.
- `EventEditorBottomActions` (lines 1901–1924) is placed bare in the Column with no `Container` wrapper — no horizontal padding, no safe area bottom padding, no top border separator.
- The `SingleChildScrollView` (line 1783) adds `bottomPadding + safeBottom + 100` to its bottom padding, where `bottomPadding = viewInsets.bottom`. This helps scroll content clear the bottom, but does nothing for the sticky bottom actions outside the scroll.

### BlockOutDrawer (`lib/features/calendar/widgets/add_block_out_drawer.dart`, 907 lines)

- Standalone drawer for block out creation/editing.
- Same `maxHeight: screenHeight * 0.9` pattern (line 415).
- Has `_buildBottomButtons()` with keyboard-aware padding: `keyboardHeight > 0 ? keyboardHeight : safeBottom` (line 757).
- This keyboard padding partially compensates but creates a double-offset scenario when the modal bottom sheet already positions itself.

### EventEditorBottomActions (`lib/features/events/widgets/event_editor_actions.dart`)

- Stateless widget rendering a `Row` with Cancel (`OutlinedButton`) and primary Save (`BrandActionButton`).
- No internal padding, background, or separator — the widget is a raw Row.
- `EventEditorViewOnlyClose` has the same pattern — bare `SizedBox` with no padding.

## 3. Root Cause

The `maxHeight` constraint in both drawer widgets uses `MediaQuery.of(context).size.height` (full screen height) without subtracting `MediaQuery.of(context).viewInsets.bottom` (keyboard height). When the keyboard opens:

1. The `Container` tries to be `0.9 * fullScreenHeight` tall (e.g., ~760px on iPhone 14).
2. The `showModalBottomSheet` positions the content above the keyboard, but the available viewport is only `fullScreenHeight - keyboardHeight` (e.g., ~506px with a ~346px keyboard).
3. The Container exceeds the available viewport — the bottom portion (including `EventEditorBottomActions`) renders behind/below the keyboard.
4. Users cannot see or tap the Save/Cancel/Delete buttons.

Secondary contributing factor: `EventEditorBottomActions` has no padding wrapper at the parent site, so even in edge cases where the layout partially works, the buttons lack horizontal page padding, safe area bottom padding, and a visual separator from the scroll content.

## 4. Proposed Solution

Make the `maxHeight` constraint keyboard-aware by subtracting `viewInsets.bottom` from the screen height before applying the 0.9 multiplier. Add a proper padding wrapper around the bottom action buttons in the event editor drawer, matching the established pattern in the block out drawer. Simplify the block out drawer's bottom button padding to remove redundant keyboard compensation.

Three localized change areas across two files:

1. **Event editor drawer**: Adjust `maxHeight` to `(screenHeight - viewInsets.bottom) * 0.9`. Wrap `EventEditorBottomActions` and `EventEditorViewOnlyClose` in a `Container` with horizontal page padding, top border separator, and bottom safe area padding.

2. **Block out drawer**: Adjust `maxHeight` to `(screenHeight - keyboardHeight) * 0.9`. Simplify `_buildBottomButtons` bottom padding to use `safeBottom` instead of the `keyboardHeight` ternary (since the maxHeight fix removes the need for keyboard compensation inside the widget).

No new widgets. No state changes. No architecture changes.

## 5. Database Impact

None.

## 6. RLS / RPC Changes

None.

## 7. Flutter Architecture Changes

Layout-only changes in two existing drawer widgets. No new widgets, controllers, providers, or repositories. No state flow changes. The `EventEditorBottomActions` widget API remains unchanged — padding is added by the parent, not the widget itself.

## 8. Exact Files to Create

None.

## 9. Exact Files to Modify

| File                                                      | Reason                                                                                                                                       |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`    | Fix `maxHeight` constraint to subtract keyboard height; wrap bottom actions in padded Container with top border and safe area bottom padding |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Fix `maxHeight` constraint to subtract keyboard height; simplify `_buildBottomButtons` to remove redundant keyboard padding                  |

## 10. Risks / Edge Cases

1. **Keyboard not open**: When no keyboard is visible, `viewInsets.bottom` is 0, so `maxHeight = screenHeight * 0.9` — identical to current behavior. No regression.

2. **Large keyboards / accessibility keyboards**: Taller keyboards produce a larger `viewInsets.bottom`. The formula `(screenHeight - viewInsets.bottom) * 0.9` naturally handles this.

3. **Desktop / web**: No on-screen keyboard, so `viewInsets.bottom` is typically 0. No behavioral change.

4. **iPad / tablet split keyboard**: Split keyboards may report 0 for `viewInsets.bottom`. The fix does not worsen this case since maxHeight remains unchanged (same as current behavior).

5. **Block out drawer bottom padding removal**: Replacing `keyboardHeight > 0 ? keyboardHeight : safeBottom` with `safeBottom` means the bottom buttons rely on `MediaQuery.of(context).padding.bottom` for safe area insets. This is the standard Flutter pattern for home indicator / bottom bar clearance.

6. **Drawer height shrinks with keyboard**: Scrollable form content area shrinks when keyboard is open, but the `Flexible` child absorbs this. All form fields remain scrollable. Delete buttons inside the scroll area remain accessible via scrolling.

## 11. Verification Plan

### Engineer must verify

1. `flutter analyze` passes with no new warnings or errors.
2. On a mobile device or simulator (iOS or Android) with keyboard open:
   - Open gig creation → tap notes field → keyboard appears → Save and Cancel buttons remain visible and tappable.
   - Open rehearsal creation → tap any text field → keyboard appears → Add Rehearsal and Cancel buttons remain visible and tappable.
   - Open block out creation (standalone drawer) → tap reason field → keyboard appears → Add Block Out and Cancel buttons remain visible and tappable.
   - Open block out creation (via event editor) → tap reason field → keyboard appears → Save and Cancel buttons remain visible and tappable.
   - In edit mode for any event type → tap text field → Delete button (in scroll area) reachable by scrolling; Save/Cancel buttons visible below scroll.
3. Without keyboard open:
   - All event drawers render at expected maximum height.
   - Bottom action buttons have proper horizontal padding and safe area spacing.
   - Visual separator (top border) visible above action buttons.

### QA must verify

- No regression in drawer sizing on mobile without keyboard.
- No regression on desktop/web drawer behavior.
- Action buttons accessible for all three event types (gig, rehearsal, block out) with keyboard open.
- Block out standalone drawer buttons accessible with keyboard open.
- Edit mode delete button reachable via scroll with keyboard open.

## 12. Engineer Task Breakdown

1. In `event_editor_drawer.dart` `build()` method (line 1704): change `maxHeight` from `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - bottomPadding) * 0.9` where `bottomPadding` is the existing `viewInsets.bottom` variable declared at line 1696.

2. In `event_editor_drawer.dart` `build()` method (lines 1901–1924): wrap the `EventEditorBottomActions` widget and the `EventEditorViewOnlyClose` widget in a `Container` with:
   - `padding: EdgeInsets.only(left: Spacing.pagePadding, right: Spacing.pagePadding, top: Spacing.space12, bottom: safeBottom + Spacing.space12)`
   - `decoration: BoxDecoration(color: AppColors.cardBg, border: Border(top: BorderSide(color: AppColors.borderMuted.withValues(alpha: 0.5))))`

3. In `add_block_out_drawer.dart` `build()` method (line 415): change `maxHeight` from `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - keyboardHeight) * 0.9` where `keyboardHeight` is the existing variable declared at line 405.

4. In `add_block_out_drawer.dart` `_buildBottomButtons()` method (line 757): change the `bottomPadding` calculation from `keyboardHeight > 0 ? keyboardHeight : safeBottom` to `safeBottom`.

5. Run `flutter analyze` and confirm no new issues.

## 13. Rollout / Migration Strategy

None. This is a client-side UI fix with no database, configuration, or deployment dependencies. Ships with the next app release.

## 14. Out of Scope

- Refactoring `event_editor_drawer.dart` (2301 lines exceeds 500-line guideline, but decomposition is not required for this bug fix — changes are minimal and localized).
- Adding padding to `EventEditorBottomActions` widget internals — padding belongs in the parent.
- Changing form field layout, validation logic, or save/delete handlers.
- Adding keyboard-dismiss gestures (tap-to-dismiss exists in block out drawer but not in event editor drawer; adding it is a separate enhancement).
- Desktop/web layout changes.
- Any database, auth, or migration changes.

## 15. Widget Contracts (Public API)

None. No new widgets are introduced. Existing widget APIs remain unchanged.

## 16. Data Flow Architecture

No data flow changes. This bug fix modifies only layout constraints and padding in the view layer. State ownership, callback flow, repository calls, provider invalidations, and UI rebuild triggers are all unchanged.

The only reactive element involved is `MediaQuery.of(context).viewInsets.bottom`, which is already read in both drawer `build()` methods. The fix uses this existing value in the `maxHeight` calculation.

## 17. Exact Code Locations

### File: `lib/features/events/widgets/event_editor_drawer.dart`

| Class / Method                                             | Approx. Line | Change                                                                                                                 |
| ---------------------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `_EventEditorDrawerState.build()` — `maxHeight` constraint | 1704         | Change `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - bottomPadding) * 0.9`      |
| `_EventEditorDrawerState.build()` — bottom action buttons  | 1901–1924    | Wrap `EventEditorBottomActions` and `EventEditorViewOnlyClose` in a `Container` with padding and top border decoration |

### File: `lib/features/calendar/widgets/add_block_out_drawer.dart`

| Class / Method                                                      | Approx. Line | Change                                                                                                             |
| ------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------ |
| `_BlockOutDrawerState.build()` — `maxHeight` constraint             | 415          | Change `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - keyboardHeight) * 0.9` |
| `_BlockOutDrawerState._buildBottomButtons()` — `bottomPadding` calc | 757          | Change `keyboardHeight > 0 ? keyboardHeight : safeBottom` to `safeBottom`                                          |
