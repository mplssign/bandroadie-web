# QA Report

## Feature Slug

`bug/subscribe-calendar-full-height-forui`

## Feature Title

Make Subscribe to Calendar bottom sheet full height and use Forui components

## Cycle Number

4

## Final Verdict

APPROVED

## Validation Summary

The uncommitted implementation matches the amended Architect plan and Tony's tester feedback. The four Cycle 4 source changes use the required existing 16px and 14px tokens, preserve the 13px URL caption, and leave the approved full-height and Forui code paths intact. All mechanically executable checks pass. Runtime UI behavior was not exercised because the plan correctly classifies it as owner-run verification.

Regression risk: **LOW**.

## Architect Scope Review

- Branch, plan, and Engineer report all use `bug/subscribe-calendar-full-height-forui`.
- Cycle number is 4 in the Engineer report and this report.
- Cycle 4 source edits are confined to `lib/features/calendar/widgets/calendar_subscription_dialog.dart`; the approved Cycle 3 `lib/shared/widgets/toggle_tile.dart` implementation remains intact.
- No off-limits source, migration, configuration, dependency, test, or shared wrapper file changed.
- Manager-approved unrelated untracked `docs/features` artifacts were ignored and left untouched.
- Tony-approved formatting-only source hunks and autoformatted feature documentation were preserved and are not defects.
- The intentionally uncommitted working tree is the expected pipeline state and is not a defect.

## Completeness Check

- Apple Calendar, Google Calendar, and Outlook labels use `AppFontSizes.body`, whose existing value is 16px.
- All three platform instruction lines use `AppFontSizes.subhead`, whose existing value is 14px.
- The bullet glyph and text for all three notes use `AppFontSizes.subhead` (14px).
- The subscription URL remains the file's sole `AppFontSizes.caption` use (13px); no hardcoded 14px or 16px font size was added.
- `mainAxisMaxRatio: 1.0` and `useSafeArea: true` are passed at the subscription sheet call site.
- The redundant inner `BoxConstraints` height cap and `keyboardHeight` local are removed.
- The decoration-only shell is a `DecoratedBox`; its decoration and child structure are preserved.
- `_CopyButton` delegates to `AppButton` without a redundant `variant` argument and preserves clipboard, callback, snackbar, and delayed-reset behavior.
- `AppToggleTile` delegates to `AppSwitch` and preserves its constructor, fields, compact layout, subtitle layout, and disabled callback behavior.
- `brand_colors.dart` correctly remains because `context.colors` is still used in `AppToggleTile`.
- Both prior presentation call sites remain, with no new or removed call site.

## Behavior Verification

**Code-path analysis only; not runtime-exercised.**

The three `_InstructionTile` instances all render their labels through one file-local title style using `AppFontSizes.body` and their instruction text through `AppFontSizes.subhead`. All three `_NoteBullet` instances share styles that apply `AppFontSizes.subhead` to both the bullet glyph and note text. `design_tokens.dart` confirms body = 16px, subhead = 14px, and caption = 13px. The URL style remains unchanged at caption size.

`showCalendarSubscriptionDialog` passes a ratio of `1.0` and safe-area handling to `showAppBottomSheet`, which forwards both values to Forui `showFSheet`. With the inner 90% cap removed, that outer Forui envelope is the single authoritative height limit. The existing `Flexible` plus `SingleChildScrollView` body and `SheetFooter` remain unchanged, preserving scrolling and footer layout.

`_CopyButton` now reaches Forui `FButton` through `AppButton`. Its displayed label/icon, success background, clipboard payload, success snackbar, and mounted delayed reset remain on the same state path. `AppToggleTile` now reaches Forui `FSwitch` through `AppSwitch`; `enabled ? onChanged : null` continues to propagate disabled state correctly.

## Regression Check

- **How-to typography and URL caption: LOW.** Only four token references changed. Text, colors, weights, spacing, constructors, and layout remain unchanged; the URL retains its 13px caption token.
- **Calendar entry points: LOW.** Both existing callers remain unchanged and invoke the same dialog function.
- **Sibling calendar sheets: LOW.** No sibling or shared bottom-sheet wrapper changed; close control, drag handle, and shell decoration remain on the established house pattern.
- **AppButton consumers: LOW.** The wrapper itself is unchanged; only this private copy button now consumes it.
- **AppSwitch consumers: LOW.** The wrapper and theme are unchanged; only `AppToggleTile` now consumes it.
- **Preferences and ICS feed: LOW.** Providers, service calls, preference model, and update callbacks are unchanged.
- **Auth, session, routing, band isolation, notifications, RLS/RPC, and init order: LOW.** No controlling code for these systems changed.
- **Platform parity: LOW.** The common Flutter/Forui path applies to iOS, Android, macOS, and web with no platform-conditional edits.
- **Async lifecycle: LOW.** Existing mounted guards remain; no controller, focus node, stream, provider, or rebuild trigger was added or altered.

## Database Safety

Not applicable. There are no SQL, migration, RLS, RPC, grant, edge-function, or database-client changes.

## Analyzer Results

Passed:

`flutter analyze --no-fatal-infos lib/features/calendar/widgets/calendar_subscription_dialog.dart lib/shared/widgets/toggle_tile.dart`

Result: `No issues found!`

## Test Results

Passed:

`flutter test`

Result: 289 tests passed, 0 failed.

## Diff Safety Review

- `git diff --check` passed.
- No `TODO`, `FIXME`, or `debugPrint(` was introduced.
- No likely API key, client secret, or password assignment was introduced.
- No accidental deletion, test scaffolding, migration, dependency, or unrelated source churn is present.
- The exact Cycle 4 source diff contains four typography token substitutions plus the two Tony-approved formatting-only hunks; no new formatting-only source hunk was introduced.
- Static checks found exactly one `AppFontSizes.body` and one `AppFontSizes.subhead` in `_InstructionTile`, exactly two `AppFontSizes.subhead` uses in `_NoteBullet`, and exactly one remaining file-wide `AppFontSizes.caption` at the URL row.
- All plan-specified static occurrence checks passed exactly: one full-height ratio, one safe-area opt-in, one shell `DecoratedBox`, one `AppButton`, one `AppSwitch`, zero inner `BoxConstraints`, zero `keyboardHeight`, zero `_CopyButton` `InkWell`, zero `Switch.adaptive`, and zero redundant `AppButtonVariant.primary`.

## Change Budget Review

- Files created in Cycle 4: 0, as budgeted.
- Source files modified in Cycle 4: 1, as budgeted.
- Cycle 4 typography changes are four in-place substitutions with net 0 lines, as budgeted.
- The complete current source diff is +7/-8 because it also preserves the two Tony-approved formatting-only hunks. No Cycle 4 delta was added to `toggle_tile.dart`.
- New public classes/methods: 0.
- New dependencies, migrations, and edge functions: 0.
- No unplanned file or public API expansion occurred.

## Code Efficiency Review

No new symbols, wrappers, helpers, providers, abstractions, fields, parameters, or dependencies were added. The Cycle 4 change reuses the existing canonical tokens and introduces no analyzer-invisible maintenance burden. Existing private `_CopyButton` and shared `AppToggleTile` continue delegating to established Forui wrappers.

## Manual Verification Punch List

QA does not launch or drive a running app. Tony must execute these owner-run checks:

1. Launch the app on iOS device or simulator. Sign in to a band. Open the Calendar tab. Scroll to the `+ Subscribe to Calendar` link and tap it. **Expected:** The bottom sheet opens and extends to full available height (top edge sits just under the status bar / Dynamic Island; bottom edge sits at the home-indicator inset). The subscription URL row, all five feed-content toggles, all three "How to subscribe" instruction tiles, and the notes block are all visible with normal scrolling behavior; the sheet is not clipped to ~56% of screen height.
2. In the same open sheet, tap the "Copy" button next to the URL. **Expected:** The button label swaps to "Copied", the icon swaps to a check, the background color shifts to the app's success green, and a success snackbar reads "Link copied to clipboard". After ~2 seconds the button reverts to "Copy" / copy icon / rose background. Paste from the system clipboard into any text field; the pasted URL matches the URL displayed in the sheet.
3. In the same open sheet, toggle each of the five switches (`Gigs`, `Potential gigs`, `Rehearsals`, `Potential rehearsals`, `Member block-out days`) once on, then once off. **Expected:** Every toggle responds immediately (no lag), renders as `FSwitch` (soft-rose selected track, `AppColors.switchTrackOff` off track, white thumb, visually identical to `FSwitch` in other sheets like `notification_settings_screen.dart` or `settings_screen.dart`), and each change persists across a sheet close-and-reopen cycle.
4. Tap "Done". **Expected:** Sheet dismisses, with no error snackbar or visual glitch.
5. Repeat step 1 on Android (physical device or emulator). **Expected:** The sheet reaches full available height above the Android navigation bar or gesture handle; the "Done" button is visible and not clipped by the navigation bar.
6. Repeat step 1 on macOS. **Expected:** The sheet reaches full available height in the desktop window.
7. Repeat step 1 in the Chrome web build. **Expected:** The sheet reaches full available height in the browser viewport.
8. Open the sheet from the Calendar tab and from the Calendar screen. **Expected:** Behavior is identical from both entry points.
9. Compare visually with a sibling calendar sheet (`Add Block Out` or `Day Detail`) opened in the same session. **Expected:** The close-X, drag handle, rounded-top shell, and outer sheet chrome are visually identical.
10. Scroll to "How to subscribe" and compare the text tiers. **Expected:** Apple Calendar, Google Calendar, and Outlook labels render at 16px; each platform instruction line renders at 14px; the bullet glyph and text in all three notes render at 14px. The labels are one tier larger than the 14px instruction and note text, while the monospace subscription URL remains unchanged at 13px. No text is clipped or overlaps at narrow widths or with larger accessibility text settings.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.
