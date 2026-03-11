# ENGINEER_REPORT — bug/mobile-keyboard-covers-event-actions

## Feature Slug

bug/mobile-keyboard-covers-event-actions

## Feature Title

Mobile Keyboard Covers Event Action Buttons

## Goal

Fix on-screen keyboard covering Save, Cancel, Delete, Add Rehearsal, and Add Gig action buttons in event creation/editing drawers on mobile devices.

## Architect Tasks Completed

All 4 tasks from the Architect plan were completed:

1. **Event editor drawer maxHeight fix** — Changed `maxHeight` from `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - bottomPadding) * 0.9` where `bottomPadding` is `viewInsets.bottom`.

2. **Event editor drawer bottom actions wrapper** — Wrapped `EventEditorBottomActions` and `EventEditorViewOnlyClose` in a `Container` with horizontal page padding (`Spacing.pagePadding`), top border separator (`AppColors.borderMuted` at 0.5 alpha), and bottom safe area padding (`safeBottom + Spacing.space12`).

3. **Block out drawer maxHeight fix** — Changed `maxHeight` from `MediaQuery.of(context).size.height * 0.9` to `(MediaQuery.of(context).size.height - keyboardHeight) * 0.9`.

4. **Block out drawer bottom padding simplification** — Replaced `keyboardHeight > 0 ? keyboardHeight : safeBottom` with `safeBottom` in `_buildBottomButtons()`, removing redundant keyboard compensation now handled by the maxHeight fix.

## Files Created

None.

## Files Modified

| File                                                      | Changes                                                                                                           |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`    | Fixed maxHeight constraint; wrapped bottom action buttons in Container with padding, border, and safe area insets |
| `lib/features/calendar/widgets/add_block_out_drawer.dart` | Fixed maxHeight constraint; simplified bottom button padding                                                      |

## File Size Changes

Minimal. Event editor drawer gained ~20 lines (Container wrapper). Block out drawer lost 1 line (simplified padding calculation).

## Analyzer Results

- Command: `flutter analyze`
- Result: **No issues found** (ran twice — after implementation and after formatting)

## Test Results

No tests were run. The Architect plan does not require tests, and no existing tests are relevant to these layout-only changes.

## Verification

### Manual test steps for QA

1. On mobile device/simulator with keyboard open:
   - Open gig creation → tap notes field → keyboard appears → Save and Cancel buttons must remain visible and tappable
   - Open rehearsal creation → tap any text field → keyboard appears → Add Rehearsal and Cancel buttons must remain visible and tappable
   - Open block out creation (standalone drawer) → tap reason field → keyboard appears → Add Block Out and Cancel buttons must remain visible and tappable
   - Open block out creation (via event editor) → tap reason field → keyboard appears → Save and Cancel buttons must remain visible and tappable
   - In edit mode for any event type → tap text field → Delete button reachable by scrolling; Save/Cancel buttons visible below scroll

2. Without keyboard open:
   - All event drawers render at expected maximum height (no regression)
   - Bottom action buttons have proper horizontal padding and safe area spacing
   - Visual separator (top border) visible above action buttons

3. Desktop/web:
   - No behavioral change (viewInsets.bottom is 0 when no on-screen keyboard)

## Deviations From Architect Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes. Implementation matches Architect plan exactly. Analyzer passes with zero issues. Changes are minimal and localized to layout constraints and padding.
