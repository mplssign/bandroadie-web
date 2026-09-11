## Summary

- Make the Subscribe to Calendar bottom sheet use the full available height.
- Replace the custom copy control with the Forui-backed `AppButton`.
- Replace legacy adaptive toggles with the Forui-backed `AppSwitch`.
- Increase the "How to subscribe" calendar labels to 16px and supporting text and notes to 14px.

## Verification

- `flutter analyze --no-fatal-infos lib/features/calendar/widgets/calendar_subscription_dialog.dart lib/shared/widgets/toggle_tile.dart`
- `flutter test` (289 tests passed in independent QA)
- Independent code review confirmed the full-height Forui sheet path, wrapper usage, and requested typography tokens.

## Manual Testing

Runtime UI verification is required before merge. Confirm the sheet height, copy-button state and clipboard behavior, toggle persistence, dismissal, both calendar entry points, platform layout, and the 16px/14px "How to subscribe" hierarchy on the supported targets.

## Database Impact

None. No migrations, RLS policies, RPC functions, or edge functions changed.
