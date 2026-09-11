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

---

# QA Report — Cycle 6

## Feature Slug

`bug/subscribe-calendar-full-height-forui`

## Feature Title

Make Subscribe to Calendar bottom sheet full height and use Forui components

## Cycle Number

6

## Final Verdict

REQUIRES CHANGES

## Validation Summary

The Cycle 6 source implementation matches the finalized Architect behavior and preserves the approved prior-cycle behavior. Focused analysis is clean, formatting is stable, all 277 Flutter tests pass, and code-path inspection confirms the exact title, Add Event header parity, body order, hidden URL, copy feedback path, `bandId` flow, full-height shell, Forui controls, and typography.

The verdict is blocked solely by a mandatory diff-safety failure: the newly edited `ENGINEER_REPORT.md` adds all three prohibited task/debug marker names enumerated by the QA policy. QA rules classify any such addition anywhere in the diff as an automatic Critical. Runtime UI checks were not attempted because the plan correctly classifies them as Tony-owned.

Regression risk: **LOW** for the source implementation.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all identify `bug/subscribe-calendar-full-height-forui`; the Engineer report is Cycle 6.
- Source changes are confined to the three Cycle 6-approved files: `calendar_subscription_dialog.dart`, `calendar_screen.dart`, and `calendar_tab_content.dart`.
- Each caller contains only the planned two-line `bandName` deletion. No off-limits source, migration, configuration, dependency, or test file changed.
- The Cycle 4 APPROVED report above is preserved verbatim. Unrelated untracked `docs/features` artifacts were ignored.
- The intentionally uncommitted source is expected pipeline state and was not treated as a defect.

## Completeness Check

- Header title is exactly `Subscribe to Band Calendar`, with no dynamic band name.
- Header title style, alignment, padding, and close control match the Add Event reference; the Subscribe drag handle remains.
- The raw URL widget, URL label/container, monospace style, and ellipsis are absent.
- All five feed toggles precede the full-width `Copy subscription link` button; `How to subscribe` follows it.
- Clipboard payload, `Copied` label, icon/success-color transition, success snackbar, mounted guard, and two-second reset remain.
- `bandName` is absent from the dialog and both Subscribe call paths. Both callers still derive, null-check, and pass `bandId`.
- Full-height `mainAxisMaxRatio: 1.0`, safe-area opt-in, `DecoratedBox` shell, Forui `AppButton`, Forui `AppSwitch`, and 16px/14px typography remain.

## Behavior Verification

**Code-path analysis only; not runtime-exercised.**

The dialog receives only `bandId`, watches `calendarBandSubscriptionUrlProvider(widget.bandId)`, and passes that same ID to preference reads and writes. The copy button still calls `Clipboard.setData(ClipboardData(text: url))`, then invokes the unchanged callback that updates `_copied`, shows `Link copied to clipboard`, and resets after two seconds when mounted.

The body sequence is description, feed label, five toggles, copy button, instructions, and notes. Header inspection confirms the exact literal and Add Event's 20px/w600/near-white title plus 32x32 rounded-square close button. Live dimensions, clipboard integration, accessibility announcements, and platform rendering remain owner-run checks.

## Regression Check

- **Calendar entry points and band isolation: LOW.** Both callers preserve their `bandId != null` gates and pass only `bandId`.
- **Full-height and shell behavior: LOW.** Ratio, safe area, drag handle, scroll boundary, footer, and bottom inset handling remain.
- **Copy flow: LOW.** Data source, clipboard payload, state transition, snackbar, and delayed mounted reset remain.
- **Forui and typography: LOW.** `AppButton`, `AppSwitch`, `AppProgressIndicator`, and the approved 16px/14px hierarchy remain; shared wrappers and tokens are untouched.
- **Auth, session, routing, notifications, ICS generation, RLS/RPC, and init order: LOW.** No controlling code changed.
- **Platform parity: LOW by code-path analysis.** The common Flutter path has no platform conditionals; runtime platform checks are in the punch list.
- **Lifecycle/rebuild behavior: LOW.** No controller, focus node, stream, provider, or rebuild trigger was added; mounted guards remain.

## Database Safety

Not applicable. No SQL, migration, RLS, RPC, grant, edge-function, or database-client change exists.

## Analyzer Results

Passed:

`flutter analyze --no-fatal-infos lib/features/calendar/widgets/calendar_subscription_dialog.dart lib/features/calendar/calendar_screen.dart lib/features/calendar/calendar_tab_content.dart lib/shared/widgets/toggle_tile.dart`

Result: `No issues found!`

## Test Results

Passed:

`flutter test`

Result: 277 tests passed, 0 failed.

Formatting check passed for all three Cycle 6 source files: 0 files changed.

## Diff Safety Review

- `git diff --check` passed.
- No likely credential token or secret was added.
- No migration, dependency, test scaffolding, accidental source deletion, or unrelated source churn was found.
- **Failed:** the added Engineer report text contains all three prohibited task/debug marker names enumerated by QA policy. This is an automatic Critical even though the sentence claims those markers are absent.

## Change Budget Review

- Cycle 6 source files modified: 3, exactly as budgeted. Source files created: 0.
- Source diff against `HEAD`: `calendar_subscription_dialog.dart` +48/-72; each caller +0/-2; `toggle_tile.dart` has no uncommitted Cycle 6 delta.
- The net deletion reflects the planned URL-surface removal, header replacement, button relocation, and dead-parameter cleanup. There is no unplanned file, public API, dependency, provider, or migration expansion.
- The plan's whole-file expectation of exactly one `Expanded(` is inaccurate: the file has three, comprising the new header plus the pre-existing `_InstructionTile` and `_NoteBullet` layout widgets. The URL-row `Expanded(Text(url))` is removed as required. This is a verification-text defect, not an implementation defect.

## Code Efficiency Review

No new helper, utility, provider, notifier, private widget, dependency, field, or parameter was introduced. Cycle 6 removes dead API plumbing and reuses the existing copy widget. Existing private symbols remain file-local, and no equivalent new symbol search was necessary because no symbol was added.

## Manual Verification Punch List

QA does not launch or drive a running app. Tony must execute these owner-run checks:

1. On iOS, open Calendar and tap `+ Subscribe to Calendar`. **Expected:** the sheet reaches full available height, respects system insets, scrolls normally, and keeps `Done` visible.
2. Inspect the header beside Add Event. **Expected:** title is exactly `Subscribe to Band Calendar` with no band name; title styling/position and the 32x32 close control match Add Event; the Subscribe drag handle remains visible.
3. Switch bands and reopen from each band. **Expected:** the title remains exactly `Subscribe to Band Calendar` in both.
4. Read the body top to bottom. **Expected:** description, `Include in feed`, all five toggles, full-width `Copy subscription link`, `How to subscribe`, three instruction tiles, then notes.
5. Inspect the copy area. **Expected:** no URL, URL container, monospace text, or ellipsis is visible; the copy button spans the same content width as `Done`.
6. Tap `Copy subscription link`, then paste into a text field. **Expected:** the correct active-band ICS URL is pasted; button changes to `Copied` with check icon and success color; snackbar says `Link copied to clipboard`; button resets after about two seconds.
7. Toggle each of Gigs, Potential gigs, Rehearsals, Potential rehearsals, and Member block-out days, then reopen the sheet. **Expected:** each Forui switch responds immediately and its saved state persists.
8. Inspect `How to subscribe`. **Expected:** calendar labels render at 16px; instruction subtext and all note bullets render at 14px with no clipping or overlap.
9. Tap `Done`, then separately tap the header close button. **Expected:** each dismisses cleanly with no error snackbar or visual glitch.
10. With a screen reader and hardware keyboard, focus and activate the copy and close buttons. **Expected:** button roles and current labels are announced; Tab reaches close; Enter/Space dismisses; the URL is not announced as body text.
11. Repeat the open/layout/copy checks on Android. **Expected:** full height respects Android navigation insets and `Copy subscription link` does not wrap at typical widths.
12. Repeat on macOS. **Expected:** full-height layout, header parity, scrolling, and clipboard behavior match iOS.
13. Repeat in Chrome web. **Expected:** full viewport height, header parity, scrolling, and browser clipboard behavior work.
14. Open from both Calendar screen entry points. **Expected:** both produce identical band-scoped content and behavior.

## Issues Found

### Critical

1. **[code-quality] Forbidden diff markers were added to `ENGINEER_REPORT.md`.** Its new Code Efficiency/Bloat Check sentence spells out all three prohibited marker names enumerated by QA policy. Remove or rephrase that sentence, then rerun QA. No source-code change is requested.

### Warnings

1. **[implementation-gap] Architect verification text has an impossible whole-file `Expanded(` count.** It expects exactly one after Cycle 6, but two approved pre-existing layout uses remain in `_InstructionTile` and `_NoteBullet`; actual whole-file count is three. The URL-specific `Expanded(Text(url))` removal is confirmed. Architect should scope this check to the removed URL block or update the expected count to three.

### Suggestions

None.

---

# QA Report — Cycle 7

## Feature Slug

`bug/subscribe-calendar-full-height-forui`

## Feature Title

Make Subscribe to Calendar bottom sheet full height and use Forui components

## Cycle Number

7

## Final Verdict

APPROVED

## Validation Summary

Both Cycle 6 findings are resolved. The Engineer report no longer introduces the prohibited task/debug marker literals, and the Architect verification now requires exactly three whole-file `Expanded(` occurrences, explicitly identifying the header, `_InstructionTile`, and `_NoteBullet`. The URL-specific `Expanded(Text(url))` and its visible/hidden substitutes remain absent.

The source implementation remains identical to the Cycle 6 implementation by complete diff review and matching source diff arithmetic. Focused analysis is clean, `git diff --check` passes, and all 277 Flutter tests pass. Behavior was confirmed by code-path analysis only; runtime UI verification remains Tony-owned under the Architect plan.

Regression risk: **LOW**.

## Architect Scope Review

- Branch, Architect plan, and Engineer report all identify `bug/subscribe-calendar-full-height-forui`; the Engineer report is Cycle 7.
- Cycle 7 changes are report/verification corrections only. The cumulative source diff remains confined to the three Cycle 6-approved files, with the approved `AppToggleTile` implementation unchanged.
- The source diff remains `calendar_subscription_dialog.dart` +48/-72 and each caller +0/-2, exactly matching Cycle 6.
- Cycle 4 and Cycle 6 QA reports above are preserved verbatim. Unrelated untracked `docs/features` artifacts were ignored.
- The intentionally uncommitted working tree is expected pipeline state and was not treated as a defect.

## Completeness Check

- The title is exactly `Subscribe to Band Calendar`; `bandName` is absent from the dialog API and both Subscribe call paths.
- Header style, padding, alignment, and close control match Add Event; the Subscribe drag handle remains.
- Body order is description, feed label, five toggles, full-width copy button, instructions, then notes.
- The URL text/container, monospace style, ellipsis, and hidden URL substitutes are absent.
- Clipboard payload, copied state, icon/success-color transition, snackbar, mounted guard, and two-second reset remain.
- Full-height ratio, safe-area opt-in, `DecoratedBox` shell, Forui button/switch/progress paths, and 16px/14px instruction typography remain.
- The corrected whole-file `Expanded(` count is exactly three at the three Architect-enumerated locations.

## Behavior Verification

**Code-path analysis only; not runtime-exercised.**

Both entry points preserve their non-null `bandId` gates and pass only `bandId`. The dialog uses that ID for URL generation and preference reads/writes. `_CopyButton` remains after all five toggles and before `How to subscribe`, displays `Copy subscription link` at full width, and copies `url` without rendering it in the widget tree.

The shell still opts into the full Forui sheet height and safe area, the title/close widget tree matches Add Event, `AppToggleTile` delegates to `AppSwitch`, and the instruction/note helpers retain the required 16px/14px token hierarchy.

## Regression Check

- **Calendar entry points and band isolation: LOW.** Both `bandId` gates and band-scoped service/provider calls remain intact.
- **Full-height shell and platform parity: LOW.** Common Flutter/Forui layout, safe area, scrolling, footer, and inset paths are unchanged; no platform conditional changed.
- **Header and dismissal: LOW.** Add Event parity and `Navigator.of(context).pop()` remain in code.
- **Copy flow and hidden URL: LOW.** Clipboard data flow and feedback state remain; no URL-rendering substitute exists.
- **Forui and typography: LOW.** Existing wrappers and tokens are consumed without shared-wrapper or theme changes.
- **Lifecycle/rebuild behavior: LOW.** No controller, focus node, stream, provider, or rebuild trigger changed; mounted guards remain.
- **Auth, session, routing, notifications, ICS generation, RLS/RPC, and init order: LOW.** No controlling code changed.

## Database Safety

Not applicable. No SQL, migration, RLS, RPC, grant, edge-function, or database-client change exists.

## Analyzer Results

Passed:

`flutter analyze --no-fatal-infos lib/features/calendar/widgets/calendar_subscription_dialog.dart lib/features/calendar/calendar_screen.dart lib/features/calendar/calendar_tab_content.dart lib/shared/widgets/toggle_tile.dart`

Result: `No issues found!`

## Test Results

Passed:

`flutter test`

Result: 277 tests passed, 0 failed.

## Diff Safety Review

- `git diff --check` passed.
- The Cycle 6 Critical is resolved: `ENGINEER_REPORT.md` no longer introduces the prohibited marker literals.
- No likely credential, migration, dependency, test scaffolding, accidental source deletion, or unrelated source churn was found.
- The only current marker-literal match is in the preserved Cycle 4 QA text before the Cycle 6 append; it is not newly introduced by Cycle 7.
- The corrected URL-removal checks pass: no URL-row `Expanded`, ellipsis, monospace style, selectable/hidden substitute, or caption token remains.

## Change Budget Review

- Cycle 7 source files modified: 0. Source files created: 0.
- Cumulative source diff remains `calendar_subscription_dialog.dart` +48/-72, `calendar_screen.dart` +0/-2, and `calendar_tab_content.dart` +0/-2; `toggle_tile.dart` has no current delta.
- The cumulative source change remains within the Architect budget and introduces no new public class, dependency, provider, migration, or edge function.
- Cycle 7 documentation corrections do not expand runtime scope.

## Code Efficiency Review

Cycle 7 adds no source symbol or abstraction. The cumulative implementation adds no helper, provider, notifier, field, parameter, dependency, or single-use wrapper; it removes dead `bandName` plumbing and reuses established `AppButton`, `AppSwitch`, and typography tokens. No new-symbol equivalence search is required because the source diff introduces no new symbol.

## Manual Verification Punch List

QA does not launch or drive a running app. Tony must execute these owner-run checks:

1. On iOS, open Calendar and tap `+ Subscribe to Calendar`. **Expected:** the sheet reaches full available height, respects system insets, scrolls normally, and keeps `Done` visible.
2. Inspect the body and copy area. **Expected:** no URL, URL container, monospace text, or ellipsis is visible; `Copy subscription link` follows all five feed toggles, precedes `How to subscribe`, and spans the same content width as `Done`.
3. Tap `Copy subscription link`, then paste into a text field. **Expected:** the active band's ICS URL is pasted; the button changes to `Copied` with check icon and success color; the snackbar says `Link copied to clipboard`; the button resets after about two seconds.
4. Toggle Gigs, Potential gigs, Rehearsals, Potential rehearsals, and Member block-out days, then reopen the sheet. **Expected:** each Forui switch responds immediately and its saved state persists.
5. Tap `Done`. **Expected:** the sheet dismisses with no error snackbar or visual glitch.
6. Repeat the open/layout/copy checks on Android. **Expected:** full height respects Android navigation insets, `Done` remains visible, and the copy label does not wrap at typical widths.
7. Repeat on macOS. **Expected:** full-height layout, scrolling, and clipboard behavior match iOS.
8. Repeat in Chrome web. **Expected:** full viewport height, scrolling, and browser clipboard behavior work.
9. Open from both Calendar entry points. **Expected:** both show identical band-scoped content and behavior.
10. Compare the shell with Add Block Out or Day Detail. **Expected:** drag handle, rounded-top shell, and outer chrome match; only the close control intentionally differs to match Add Event.
11. Inspect `How to subscribe`. **Expected:** calendar labels render at 16px; instruction subtext and all note bullets render at 14px without clipping or overlap.
12. Compare the header beside Add Event. **Expected:** title is exactly `Subscribe to Band Calendar`, with matching 20px/w600 near-white styling, left position, 20/16 spacing, and 32x32 rounded-square close control; the Subscribe drag handle remains.
13. Switch bands and reopen. **Expected:** the title remains exactly `Subscribe to Band Calendar`, while copied and saved data remains scoped to the active band.
14. With a screen reader and hardware keyboard, focus and activate the copy and close buttons. **Expected:** button roles and current labels are announced; the URL is not announced as body text; Tab reaches close and Enter/Space dismisses.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.
