## Summary

- Make the Subscribe to Calendar bottom sheet use the full available height.
- Replace the custom copy control with the Forui-backed `AppButton`.
- Replace legacy adaptive toggles with the Forui-backed `AppSwitch`.
- Increase the "How to subscribe" calendar labels to 16px and supporting text and notes to 14px.
- Hide the raw subscription URL while preserving clipboard behavior.
- Use a full-width `Copy subscription link` action below the feed toggles.
- Match the Add Event header and close control, with the fixed title `Subscribe to Band Calendar`.

## Verification

- `flutter analyze --no-fatal-infos lib/features/calendar/widgets/calendar_subscription_dialog.dart lib/features/calendar/calendar_screen.dart lib/features/calendar/calendar_tab_content.dart lib/shared/widgets/toggle_tile.dart`
- `flutter test` (277 tests passed in independent QA)
- Independent code review confirmed the full-height Forui sheet, fixed header, hidden URL, copy flow, wrapper usage, and typography tokens.

## Manual Testing

Runtime UI verification is required before merge. Confirm the sheet height, Add Event header parity, exact fixed title, hidden URL, full-width copy-button position and clipboard behavior, toggle persistence, dismissal, both calendar entry points, platform layout, and the 16px/14px "How to subscribe" hierarchy.

## Database Impact

None. No migrations, RLS policies, RPC functions, or edge functions changed.
