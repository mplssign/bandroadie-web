# ARCHITECT_PLAN — bug/subscribe-calendar-full-height-forui

## Feature Slug
`bug/subscribe-calendar-full-height-forui`

## Feature Title
Make Subscribe to Calendar bottom sheet full height and use Forui components

## Problem Summary
The Subscribe to Calendar bottom sheet (opened from the Calendar screen and the Calendar tab via the `+ Subscribe to Calendar` link) presents at roughly 56% of the screen height, cutting off content that should be visible without scrolling and leaving conspicuous empty space under the modal barrier. Independent of the height issue, part of the sheet's rendered widget tree bypasses the app's Forui wrappers: the "Copy" button is a hand-built `Material` + `InkWell` and the feed-content toggles ultimately render `Switch.adaptive` rather than the Forui `FSwitch`-backed `AppSwitch`. The sheet should present at full available height and every component inside it should route through the established Forui wrappers.

## Root Cause — HIGH confidence (confirmed in code)

Two independent causes, both directly observable in the source.

### 1. Sheet height cap comes from the outer Forui envelope, not the inner container

`showCalendarSubscriptionDialog()` at [lib/features/calendar/widgets/calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L22-L37) calls `showAppBottomSheet(...)` without passing `mainAxisMaxRatio` or `useSafeArea`:

```dart
showAppBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => CalendarSubscriptionDialog(...),
);
```

The wrapper at [lib/components/ui/app_bottom_sheet.dart](lib/components/ui/app_bottom_sheet.dart#L17-L41) forwards `mainAxisMaxRatio ?? (9 / 16)` to Forui's `showFSheet`, so when the caller omits the argument the outer envelope caps sheet height at `9/16 ≈ 56.25%` of screen height. The dialog's inner shell at [calendar_subscription_dialog.dart:98-104](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L98-L104) then adds a *second* height cap:

```dart
Container(
  constraints: BoxConstraints(
    maxHeight: (MediaQuery.of(context).size.height - keyboardHeight) * 0.9,
  ),
  ...
```

The inner `0.9` cap is masked by the outer `9/16` envelope — the sheet visibly clamps at `~56%`, never `~90%`. This is the same class of bug diagnosed in [docs/features/detail-sheet-sizing-venue-back/ARCHITECT_PLAN.md](docs/features/detail-sheet-sizing-venue-back/ARCHITECT_PLAN.md#L115-L149) and [docs/features/bug-setlist-picker-drawer-height/ARCHITECT_PLAN.md](docs/features/bug-setlist-picker-drawer-height/ARCHITECT_PLAN.md#L33-L60): the operative cap is the wrapper's default, not any per-sheet inner container. The fix is at the call site, with the inner double-cap removed to leave a single authoritative height ratio.

Sibling reference: [lib/features/calendar/widgets/add_block_out_drawer.dart:83-101](lib/features/calendar/widgets/add_block_out_drawer.dart#L83-L101) passes `mainAxisMaxRatio: 1.0` and `useSafeArea: true` and has no inner max-height container — the target pattern for a full-height calendar sheet.

### 2. Two components in the sheet render non-Forui underneath

The sheet already uses `showAppBottomSheet` (Forui `showFSheet`), `AppProgressIndicator` (Forui `FCircularProgress`), and `SheetFooter` (which delegates to `AppButton` → Forui `FButton`), consistent with the calendar-feature Forui audit at [docs/features/calendar-forui-consolidation/ARCHITECT_PLAN.md](docs/features/calendar-forui-consolidation/ARCHITECT_PLAN.md#L45-L55). Two sub-widgets do not:

**a. `_CopyButton`** at [calendar_subscription_dialog.dart:437-495](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L437-L495) hand-builds a button from `Material(color: ...)` + `InkWell(onTap:...)` + `Padding` + `Row(Icon, Text)`. This bypasses `AppButton` / `FButton` entirely and duplicates styling behaviour (background, radius, splash) that the Forui wrapper already provides.

**b. `AppToggleTile`** at [lib/shared/widgets/toggle_tile.dart:94-100](lib/shared/widgets/toggle_tile.dart#L94-L100) — used exclusively by this sheet for five toggles (`Gigs`, `Potential gigs`, `Rehearsals`, `Potential rehearsals`, `Member block-out days`) — renders `Switch.adaptive` directly rather than delegating to the app's Forui-backed `AppSwitch`. A grep of `lib/**` for `AppToggleTile(` confirms all five current call sites live in this dialog, so the widget is de facto single-use even though it is defined as a shared widget. This is the same class of legacy `Switch.adaptive` → `AppSwitch` migration that [docs/features/unified-forui-switch-styling/ARCHITECT_PLAN.md](docs/features/unified-forui-switch-styling/ARCHITECT_PLAN.md) established as the app-wide standard: `AppSwitch` without an explicit `activeTrackColor`, deferring to the app-theme `FSwitchStyleDelta` defined at [lib/app/theme/app_theme.dart:629-641](lib/app/theme/app_theme.dart#L629-L641).

The remaining hand-built elements in the sheet — the drag-handle stub, the rounded-top shell `Container`, the close-X `GestureDetector` + circle `Container` + `Icon`, and the plain `Text` / `Icon` / `Row` / `Column` atoms — are the documented "house pattern" for Forui-backed sheets in this codebase per [docs/features/calendar-forui-consolidation/ARCHITECT_PLAN.md](docs/features/calendar-forui-consolidation/ARCHITECT_PLAN.md#L51-L55) ("*The house pattern (17 files app-wide) is that each sheet hand-builds its own rounded-container + drag-handle shell because Forui preview's `backgroundColor`/`shape` params are no-ops. This is expected and not a defect.*"). They are shared verbatim with `day_detail_bottom_sheet.dart` and `add_block_out_drawer.dart`, so touching them here would break sheet-to-sheet consistency, not restore it.

## Existing System Analysis

- The sheet is opened from exactly two sites: [lib/features/calendar/calendar_screen.dart:507-535](lib/features/calendar/calendar_screen.dart#L507-L535) and [lib/features/calendar/calendar_tab_content.dart:483-511](lib/features/calendar/calendar_tab_content.dart#L483-L511). Both call `showCalendarSubscriptionDialog(context, ref, bandId: ..., bandName: ...)`. Neither site controls sheet chrome — the chrome is entirely owned by the dialog and its `showAppBottomSheet` wrapper call.
- `showAppBottomSheet` already supports the two params required for the height fix (`mainAxisMaxRatio`, `useSafeArea`) with backward-compatible defaults — the `?? (9 / 16)` fallback for `mainAxisMaxRatio` and the forwarded `useSafeArea` were both added and validated in the `detail-sheet-sizing-venue-back` cycle. No wrapper change is required here.
- `_CopyButton` in this file has one caller (its parent `_buildBody`). It is a private `StatelessWidget` — replacing its implementation in place preserves the public shape of the file and every state-management path unchanged: `_copied` still lives on `_CalendarSubscriptionDialogState`, the `onCopied` callback still runs `setState(() => _copied = true)` followed by a delayed reset, and the `Clipboard.setData` call still fires on tap.
- `AppButton` (Forui `FButton`) at [lib/components/ui/app_button.dart:100-206](lib/components/ui/app_button.dart#L100-L206) already accepts a leading `icon`, an optional `backgroundColor` override that is applied through a `FButtonStyleDelta.decoration` delta (the docstring's "ignored in Forui preview" comment is stale — the code applies it), and an `isLoading` spinner. It is a drop-in for the `_CopyButton`'s copy/copied dual state.
- `AppSwitch` at [lib/components/ui/app_switch.dart:47-76](lib/components/ui/app_switch.dart#L47-L76) accepts `value`, `onChanged`, and (optionally) `activeTrackColor` / `activeColor`. The current app-wide convention set by `unified-forui-switch-styling` is to *omit* the explicit `activeTrackColor` on `AppSwitch` call sites and let the theme delta handle the selected-track color (`AppColors.primarySoft`) and the off-track color (`AppColors.switchTrackOff`). `AppToggleTile` is the only widget in `lib/` still using `Switch.adaptive` after that convention was adopted, and its `inactiveTrackColor` / `inactiveThumbColor` overrides duplicate what the theme already sets.
- `AppToggleTile`'s public API (`title`, `subtitle`, `value`, `onChanged`, `enabled`, `compact`) is preserved by an internal `AppSwitch` swap. No caller-visible change; the shared-widget abstraction stays intact for any future caller.
- The sheet's keyboard-inset handling at [calendar_subscription_dialog.dart:92-93](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L92-L93) reads `MediaQuery.of(context).viewInsets.bottom` and `MediaQuery.of(context).padding.bottom` and forwards `safeBottom` into the scroll view's bottom padding at line 178. That handling remains correct once the outer envelope is `mainAxisMaxRatio: 1.0` and `useSafeArea: true` — Forui's `showFSheet` continues to expose `viewInsets` through the descendant `MediaQuery` per the same pattern proven in `add_block_out_drawer.dart`. The `MediaQuery.of` → `viewInsetsOf` / `viewPaddingOf` narrowing suggested in [docs/features/bulk-entry-instructions-cutoff-ios/ARCHITECT_PLAN.md](docs/features/bulk-entry-instructions-cutoff-ios/ARCHITECT_PLAN.md) is a separate systemic concern and is not in scope here.

## Proposed Solution

Three coordinated edits across two files. The Verification Plan section below states how each edit is validated.

### 1. Height — pass `mainAxisMaxRatio: 1.0` and `useSafeArea: true`, drop the redundant inner cap
- In `showCalendarSubscriptionDialog()`, add `mainAxisMaxRatio: 1.0` and `useSafeArea: true` to the existing `showAppBottomSheet(...)` call. The outer envelope now correctly expresses "full available height".
- In `_CalendarSubscriptionDialogState.build()`, replace the shell `Container` with a `DecoratedBox`, preserving its `decoration:` (rounded-top surface) and `child:` verbatim; the inner `constraints:` is dropped as part of the swap. Because the shell no longer holds any layout arguments (constraints/padding/margin/etc.), keeping it as a `Container` trips the `use_decorated_box` lint; `DecoratedBox` is the analyzer-clean replacement that preserves visual behaviour byte-for-byte. The outer envelope is now the single authoritative height cap — the same one-authoritative-cap pattern established for the setlist picker in `bug-setlist-picker-drawer-height` and applied consistently across `add_block_out_drawer.dart`, `event_editor_drawer.dart`, and other full-height sheets.
- Remove the now-unused `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` local at [calendar_subscription_dialog.dart:92](lib/features/calendar/widgets/calendar_subscription_dialog.dart#L92). It was consumed only by the inner cap; a re-read of `_buildBody` / the scroll view confirms that after the cap is removed, the sole remaining consumer of the keyboard-inset locals is the scroll view's bottom padding at line 178, which uses `safeBottom` alone. Keeping `keyboardHeight` around trips `unused_local_variable`. `safeBottom` stays as-is — the keyboard handling already works and is orthogonal to the outer envelope.

### 2. Forui — replace `_CopyButton` internals with `AppButton`
- Replace the `Material` + `InkWell` + `Padding` + `Row` tree in `_CopyButton.build()` with a single `AppButton` call:
  - `label` — `copied ? 'Copied' : 'Copy'`
  - `icon` — `copied ? AppIcons.check : AppIcons.copy`
  - `backgroundColor` — `copied ? context.colors.success : null` (preserves the rose → green state transition; when `null`, `AppButton` falls back to the theme's primary rose)
  - `onPressed` — the existing tap handler: `Clipboard.setData(ClipboardData(text: url)); onCopied();`
- Do *not* pass `variant:`. `AppButton`'s default is `AppButtonVariant.primary` ([app_button.dart:34](lib/components/ui/app_button.dart#L34)), so an explicit `variant: AppButtonVariant.primary` trips `avoid_redundant_argument_values`. Omitting the argument gives the same behaviour with a clean analyzer.
- The public shape of `_CopyButton` (private widget, three required fields: `url`, `copied`, `onCopied`) is preserved. The parent `_buildBody` continues to construct it identically.
- No change to the `_copied` state machine on `_CalendarSubscriptionDialogState`, the snackbar (`showSuccessSnackBar`), the 2-second delayed reset, or the `Clipboard.setData` payload.

### 3. Forui — migrate `AppToggleTile` internals from `Switch.adaptive` to `AppSwitch`
- In `AppToggleTile.build()`, replace `Switch.adaptive(value: ..., onChanged: ..., activeTrackColor: AppColors.primary, inactiveTrackColor: context.colors.surfaceOverlay, inactiveThumbColor: context.colors.textSecondary)` with `AppSwitch(value: value, onChanged: enabled ? onChanged : null)`.
- Drop the `activeTrackColor` / `inactiveTrackColor` / `inactiveThumbColor` explicit overrides — the app theme `FSwitchStyleDelta` at `app_theme.dart:629-641` provides `AppColors.switchTrackOff` (off), `AppColors.primarySoft` (selected), and `Colors.white` (thumb, all states). This aligns `AppToggleTile` with every other `AppSwitch` call site in the app after the `unified-forui-switch-styling` cycle.
- Public API of `AppToggleTile` is unchanged: `title`, `subtitle`, `value`, `onChanged`, `enabled`, `compact` stay in place. Every existing call site (all five in `calendar_subscription_dialog.dart`) continues to compile and render.
- Update the imports in `toggle_tile.dart` to add `AppSwitch` and drop `brand_colors.dart` / `AppColors` if no other reference remains after the swap (verify per-line before removing).

**Rejected alternatives:**

- **Swap `_CopyButton` for `SheetFooter`.** `SheetFooter` is a sticky bottom-of-sheet element with its own decoration and safe-area padding — it is not a fit for an inline row-anchored copy action. `AppButton` is the correct wrapper.
- **Replace `AppToggleTile` in this sheet with inline `AppSwitch` + `Text` rows and leave `toggle_tile.dart` alone.** This inflates the sheet body with duplicated container + padding + layout code for five rows and produces a surface-color / radius regression vs. the current tile appearance. Migrating the widget's internals is a smaller and lower-risk change than inlining five rows.
- **Change `showAppBottomSheet`'s default `mainAxisMaxRatio`.** Global default touches ~136 call sites; explicitly out of scope per every prior height-fix plan in this repo. The correct move is per-caller opt-in.
- **Swap the close-X `GestureDetector` for `FButton.icon` or an `AppIconButton`.** No `AppIconButton` wrapper exists that matches the circular-background house pattern used by `day_detail_bottom_sheet.dart`, `add_block_out_drawer.dart`, and this dialog. Changing only this sheet's close-X would produce three inconsistent close buttons in the calendar feature.
- **Migrate the drag-handle / rounded-top `Container` shell to Forui.** Documented house pattern — Forui preview's `backgroundColor` / `shape` are no-ops, so this is expected and not a defect (per calendar-forui-consolidation architect plan). Not changed.

## Database Impact
n/a — no SQL, migrations, RLS policies, RPC functions, edge functions, or grants change. Layout and widget-tree change only.

## Flutter Architecture Changes
None. No new Riverpod providers, notifiers, or controllers. No new repository. No new model. Init order (`WidgetsFlutterBinding` → URL strategy → orientation → `AppVersionService.init` → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp` [native] → `DeepLinkService` → `runApp`) unchanged. Auth / PKCE flow unchanged. Routing unchanged. Platform-conditional code unchanged (sheet renders uniformly across iOS, Android, macOS, and web).

## Files to Create
None.

## Files to Modify

| File | Change |
| --- | --- |
| [lib/features/calendar/widgets/calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart) | (a) In `showCalendarSubscriptionDialog()` (lines 22-37), add `mainAxisMaxRatio: 1.0` and `useSafeArea: true` to the `showAppBottomSheet` call. (b) In `_CalendarSubscriptionDialogState.build()` (lines 98-104), replace the shell `Container` with a `DecoratedBox`, preserving `decoration:` and `child:` verbatim; the inner `constraints:` is dropped in the process (a plain `Container` with only decoration + child trips `use_decorated_box`). Also remove the `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` local at line 92 — after removing the inner cap, `keyboardHeight` has no remaining reader (the scroll view padding at line 178 uses `safeBottom` alone, which stays). (c) In `_CopyButton.build()` (lines 447-495), replace the `Material` + `InkWell` + `Padding` + `Row` tree with a single `AppButton(label: copied ? 'Copied' : 'Copy', icon: copied ? AppIcons.check : AppIcons.copy, backgroundColor: copied ? context.colors.success : null, onPressed: () { Clipboard.setData(...); onCopied(); })`. Do *not* pass `variant:` — `AppButton`'s default is `AppButtonVariant.primary` ([app_button.dart:34](lib/components/ui/app_button.dart#L34)); passing it trips `avoid_redundant_argument_values`. Add the `app_button.dart` import. Drop the now-unused local `Material` / `InkWell` constructions. No other changes to this file. |
| [lib/shared/widgets/toggle_tile.dart](lib/shared/widgets/toggle_tile.dart) | In `AppToggleTile.build()` (line 94), replace `Switch.adaptive(value: value, onChanged: enabled ? onChanged : null, activeTrackColor: AppColors.primary, inactiveTrackColor: context.colors.surfaceOverlay, inactiveThumbColor: context.colors.textSecondary)` with `AppSwitch(value: value, onChanged: enabled ? onChanged : null)`. Add the `app_switch.dart` import. If no other reference to `AppColors` or `brand_colors.dart` remains after the swap (verify with grep on the file), drop those imports; otherwise leave them. No changes to the widget's constructor, fields, or public API. |

## Files Off-Limits

| File | Why off-limits |
| --- | --- |
| [lib/components/ui/app_bottom_sheet.dart](lib/components/ui/app_bottom_sheet.dart) | Shared wrapper. Its `mainAxisMaxRatio ?? (9 / 16)` fallback and `useSafeArea` forwarding are already correct — this fix opts in at the call site. Changing the default cascades to ~136 sheets. |
| [lib/components/ui/app_button.dart](lib/components/ui/app_button.dart) | Forui `FButton` wrapper. Consumed as-is; no API change required. |
| [lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart) | Forui `FSwitch` wrapper. Consumed as-is; no API change required. |
| [lib/components/ui/sheet_footer.dart](lib/components/ui/sheet_footer.dart) | Already Forui-backed via `AppButton`. Unchanged. |
| [lib/components/ui/app_progress_indicator.dart](lib/components/ui/app_progress_indicator.dart) | Already Forui-backed via `FCircularProgress`. Unchanged. |
| [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart) | App-wide `FSwitchStyleDelta`. Provides the switch styling the migrated `AppToggleTile` will inherit. Not modified. |
| [lib/features/calendar/calendar_screen.dart](lib/features/calendar/calendar_screen.dart), [lib/features/calendar/calendar_tab_content.dart](lib/features/calendar/calendar_tab_content.dart) | Call sites of `showCalendarSubscriptionDialog`. They already pass the required `bandId` / `bandName`. Sheet chrome is owned by the dialog, not the callers. |
| [lib/features/calendar/widgets/add_block_out_drawer.dart](lib/features/calendar/widgets/add_block_out_drawer.dart), [lib/features/calendar/widgets/day_detail_bottom_sheet.dart](lib/features/calendar/widgets/day_detail_bottom_sheet.dart), [lib/features/calendar/widgets/view_block_out_drawer.dart](lib/features/calendar/widgets/view_block_out_drawer.dart) | Sibling calendar sheets. Reference patterns for the fix; not the subject of this bug. Consistent close-X / drag-handle / shell pattern must remain visually identical to this sheet after the fix (the fix does not touch those elements). |
| [lib/features/calendar/calendar_subscription_service.dart](lib/features/calendar/calendar_subscription_service.dart), the `calendarBandSubscriptionUrlProvider`, `CalendarFeedPreferences` model, `getBandSubscriptionPreferences`, `updateBandSubscriptionPreferences` | Data layer for subscription URL and feed preferences. Bug is layout + widget-tree only. |
| `supabase/migrations/**`, `supabase/functions/**` | No DB or RPC change. |
| `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` | No dependency, package, or lint change. `forui`, `flutter_riverpod`, and every other dependency stay at their current versions. |
| Every non-listed file in `lib/` | Layout-plus-Forui-wrapper-swap only. |

## Change Budget

| Metric | Expected |
| --- | --- |
| Files created | 0 |
| Files modified | 2 |
| Net line delta in [calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart) | approximately **−31** (drop ~40-line `_CopyButton` tree, drop 3-line inner `BoxConstraints`, drop 1-line `keyboardHeight` local, swap shell `Container` → `DecoratedBox` (net zero), replace with ~10-line `AppButton` invocation without redundant `variant:`, add `mainAxisMaxRatio` + `useSafeArea` + import lines) |
| Net line delta in [toggle_tile.dart](lib/shared/widgets/toggle_tile.dart) | approximately **−3** (5-line `Switch.adaptive` block → 3-line `AppSwitch` block, one import swap) |
| New public classes / methods | 0 |
| New dependencies | 0 |
| New migrations / edge functions | 0 |
| Files touched outside `lib/` | 0 (aside from this plan document) |

## System Impact Map

| System | Impact |
| --- | --- |
| Gigs | Unaffected — no gig data path touched; the Subscribe to Calendar sheet only reads user preferences and displays the ICS URL. |
| Rehearsals | Unaffected — same as gigs. |
| Setlists | Unaffected. |
| Members | Unaffected. |
| Auth | Unaffected — sheet does not touch auth/session/PKCE. |
| Routing | Unaffected — no navigation change. Same two call sites, same widget instantiation. |
| Notifications | Unaffected. |
| Platforms (iOS / Android / macOS / Web) | Layout change applies uniformly; sheet chrome renders through Forui's `showFSheet` on every platform. Keyboard inset handling unchanged. Web deep-link (`/auth/confirm`) unaffected — subscription sheet is not in the auth flow. |
| Init order | Unaffected — no change to `main.dart` or startup sequence. |
| ICS feed generation (edge function) | Unaffected — the sheet reads the URL from `calendarBandSubscriptionUrlProvider` and toggles feed preferences via `updateBandSubscriptionPreferences`; neither path changes. |
| RLS / RPC | Unaffected — no policy or RPC change. |

## Regression Risk

**LOW.**

Scope is two files, one widget tree, two Forui-wrapper drop-in swaps, and one two-line addition at a single `showAppBottomSheet` call site. The change does not touch:

- Auth, session, PKCE, or deep-link flow.
- Supabase queries, RLS, RPC functions, edge functions, or any DB path.
- Any Riverpod provider or notifier (the sheet's use of `calendarBandSubscriptionUrlProvider` and `calendarSubscriptionServiceProvider` remains identical).
- Routing, navigation, or the `activeBandProvider` band-isolation contract.
- Init order or platform-conditional code.
- The keyboard-inset handling inside the sheet (`viewInsets.bottom` / `padding.bottom` reads at lines 92-93 are preserved and continue to feed the scroll view's bottom padding).
- Sibling calendar sheets (`add_block_out_drawer.dart`, `day_detail_bottom_sheet.dart`, `view_block_out_drawer.dart`) — their close-X / drag-handle / shell patterns must stay identical to this sheet after the fix, which the plan preserves.

Two soft risks worth naming:

1. **AppToggleTile switch appearance shifts from hard rose to soft rose in the selected state.** The theme delta uses `AppColors.primarySoft` for `FSwitchVariant.selected` and `AppColors.switchTrackOff` for off. This is the app-wide unified appearance established by `unified-forui-switch-styling` and is the *intended* target state for every switch in the app. Any earlier hard-rose visual on these five toggles was a legacy artifact of `AppToggleTile` not yet having been migrated. Non-regression against the app-wide standard; visible-but-desired against this sheet's prior rendering.
2. **`_CopyButton`'s copied-state background comes from `context.colors.success`, not a Forui variant.** Forui's `FButtonVariant` does not include a "success" variant. Using `AppButton.backgroundColor: context.colors.success` routes through the wrapper's `FButtonStyleDelta.decoration` override — the same code path already used by other `AppButton` call sites that need non-standard fills. The copied → uncopied transition is preserved.

## Engineer Task Breakdown

1. In [lib/features/calendar/widgets/calendar_subscription_dialog.dart](lib/features/calendar/widgets/calendar_subscription_dialog.dart), inside `showCalendarSubscriptionDialog()` (lines 22-37 as of `bug/subscribe-calendar-full-height-forui@HEAD`), add `mainAxisMaxRatio: 1.0,` and `useSafeArea: true,` to the `showAppBottomSheet(...)` argument list. Preserve `context`, `isScrollControlled`, `backgroundColor`, and `builder`. Make no other change in this function.
2. In the same file, inside `_CalendarSubscriptionDialogState.build()` (lines 96-105 as of `HEAD`), replace the shell `Container` with a `DecoratedBox`, preserving its `decoration:` and `child:` verbatim; the inner `constraints:` is dropped in the process. Then remove the now-unused `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` local at line 92 — after removing the inner cap, only `safeBottom` is still consumed (by the scroll view padding at line 178). Do *not* remove `safeBottom`. Do *not* refactor any other part of `build()` — outer `Material(color: Colors.transparent)`, the `Column`, drag handle, header, `Flexible` + `SingleChildScrollView`, and `SheetFooter` stay verbatim.
3. In the same file, replace the entire body of `_CopyButton.build()` (lines 452-495) with a single `AppButton(...)` invocation. Fields: `label: copied ? 'Copied' : 'Copy'`, `icon: copied ? AppIcons.check : AppIcons.copy`, `backgroundColor: copied ? context.colors.success : null`, `onPressed: () { Clipboard.setData(ClipboardData(text: url)); onCopied(); }`. Do *not* pass `variant:` — `AppButton`'s default is `AppButtonVariant.primary` ([app_button.dart:34](lib/components/ui/app_button.dart#L34)); passing it explicitly trips `avoid_redundant_argument_values`. Add `import '../../../components/ui/app_button.dart';` to the file's import block. Leave the `_CopyButton` constructor and fields (`url`, `copied`, `onCopied`) unchanged. Verify no residual `Material` / `InkWell` / `Padding` / `Row` remain inside `_CopyButton`.
4. In [lib/shared/widgets/toggle_tile.dart](lib/shared/widgets/toggle_tile.dart), inside `AppToggleTile.build()` (lines 94-100 as of `HEAD`), replace the entire `Switch.adaptive(...)` block with `AppSwitch(value: value, onChanged: enabled ? onChanged : null)`. Add `import '../../components/ui/app_switch.dart';` to the file's imports. Run a `grep AppColors` inside `toggle_tile.dart` after the swap — if zero references remain, remove the `brand_colors.dart` import; otherwise leave it. Do not change `AppToggleTile`'s constructor, fields, `Container` outer decoration, `compact` padding logic, or subtitle layout.
5. Run `flutter analyze --no-fatal-infos`. Confirm zero new warnings or errors introduced by this branch's diff (info-level lints on unrelated files are pre-existing baseline and not this branch's responsibility).
6. Run `flutter test`. Confirm the full suite passes, including any widget tests that instantiate `CalendarSubscriptionDialog`, `AppToggleTile`, or `AppSwitch`.

## Verification Plan

### Tier 1 — pre-deploy, mechanically executable without a running app

1. **`flutter analyze --no-fatal-infos`** — clean of new warnings and errors introduced by this branch's diff. QA compares against `main` baseline analyzer output; only new diagnostics attributable to the two modified files count against this gate.
2. **`flutter test`** — full suite passes. QA runs `flutter test` in the branch and confirms zero regressions vs. `main`. No new test file is required — this bug is presentation-and-widget-swap; there is no branching business logic to unit-test, and there is no existing golden coverage for this sheet to update.
3. **Static diff review — `calendar_subscription_dialog.dart`**:
   1. Grep `mainAxisMaxRatio: 1.0` in `showCalendarSubscriptionDialog` — exactly one occurrence.
   2. Grep `useSafeArea: true` in `showCalendarSubscriptionDialog` — exactly one occurrence.
   3. Grep `BoxConstraints(` inside `_CalendarSubscriptionDialogState.build` — zero occurrences (the inner cap is fully removed).
   4. Grep `DecoratedBox(` at the shell position inside `_CalendarSubscriptionDialogState.build` — exactly one occurrence. The shell wrapper is now `DecoratedBox`, not `Container`; `use_decorated_box` is clean.
   5. Grep `keyboardHeight` across `_CalendarSubscriptionDialogState` — zero occurrences. The unused local is removed alongside the inner cap. `safeBottom` still appears exactly twice (the local declaration at line 92 or 93 depending on how the diff lands, and the scroll view padding line).
   6. Grep `Material(` inside `_CopyButton` — zero occurrences (only the file-level outer `Material(color: Colors.transparent)` at the sheet root remains).
   7. Grep `InkWell(` inside `_CopyButton` — zero occurrences.
   8. Grep `AppButton(` inside `_CopyButton` — exactly one occurrence.
   9. Grep `AppButtonVariant.primary` inside `_CopyButton` — zero occurrences. `variant:` is `AppButton`'s default and must be omitted to satisfy `avoid_redundant_argument_values`.
   10. Grep `import '.*/app_button.dart';` in the import block — exactly one occurrence.
4. **Static diff review — `toggle_tile.dart`**:
   1. Grep `Switch.adaptive` — zero occurrences.
   2. Grep `AppSwitch(` — exactly one occurrence inside `AppToggleTile.build`.
   3. Grep `import '.*/app_switch.dart';` — exactly one occurrence.
   4. If `AppColors` no longer appears in the file, `brand_colors.dart` import is removed; otherwise it stays. Either outcome is acceptable.
5. **Change Budget check** — measured net line deltas match this plan's stated targets within ±5 lines per file, and no file outside the two listed in "Files to Modify" is touched.
6. **`show*` call-site parity** — grep `showCalendarSubscriptionDialog\(` under `lib/` returns exactly the two prior call sites (`calendar_screen.dart`, `calendar_tab_content.dart`); no new call site added, no existing call site removed.

### Owner-run punch list (Tony, at PR-test / apply time — QA hands this to Tony verbatim; QA does not attempt it)

QA cannot launch, build, or drive a running instance of the app. The following require a running instance and are Tony's to run:

1. Launch the app on iOS device or simulator. Sign in to a band. Open the Calendar tab. Scroll to the `+ Subscribe to Calendar` link and tap it. **Expected:** The bottom sheet opens and extends to full available height (top edge sits just under the status bar / Dynamic Island; bottom edge sits at the home-indicator inset). The subscription URL row, all five feed-content toggles, all three "How to subscribe" instruction tiles, and the notes block are all visible with normal scrolling behavior; the sheet is not clipped to ~56% of screen height.
2. In the same open sheet, tap the "Copy" button next to the URL. **Expected:** The button label swaps to "Copied", the icon swaps to a check, the background color shifts to the app's success green, and a success snackbar reads "Link copied to clipboard". After ~2 seconds the button reverts to "Copy" / copy icon / rose background. Paste from the system clipboard into any text field — the pasted URL matches the URL displayed in the sheet.
3. In the same open sheet, toggle each of the five switches (`Gigs`, `Potential gigs`, `Rehearsals`, `Potential rehearsals`, `Member block-out days`) once on, then once off. **Expected:** Every toggle responds immediately (no lag), renders as `FSwitch` (soft-rose selected track, `AppColors.switchTrackOff` off track, white thumb — visually identical to `FSwitch` in other sheets like `notification_settings_screen.dart` or `settings_screen.dart`), and each change persists across a sheet close-and-reopen cycle.
4. Tap "Done". **Expected:** Sheet dismisses, no error snackbar, no visual glitch.
5. Repeat step 1 on Android (physical device or emulator). Confirm sheet reaches full available height above the Android nav bar / gesture handle; the "Done" button is visible and not clipped by the nav bar.
6. Repeat step 1 on macOS. Confirm sheet reaches full available height in the desktop window.
7. Repeat step 1 in the Chrome web build (`flutter run -d chrome`). Confirm sheet reaches full available height in the browser viewport.
8. Open the sheet from the Calendar tab AND from the Calendar screen (both call sites exist). Confirm identical behavior from both entry points.
9. Compare visual side-by-side with a sibling calendar sheet (`Add Block Out` or `Day Detail`) opened from the same session. Confirm the close-X, drag handle, rounded-top shell, and outer sheet chrome are visually identical — the fix must not drift this sheet's shell away from its siblings.

### Tier 2 — post-deploy
n/a — no new SQL objects, no new RPC functions, no new grants, no new edge-function endpoints, no new migrations. There is nothing to run post-apply.

## QA Regression Areas

- Both call sites of `showCalendarSubscriptionDialog` (`calendar_screen.dart` and `calendar_tab_content.dart`) — sheet opens, all content visible, no navigation regression.
- Every other calendar sheet (`add_block_out_drawer.dart`, `day_detail_bottom_sheet.dart`, `view_block_out_drawer.dart`) — chrome (close-X / drag-handle / shell) still visually identical to the Subscribe sheet; no unintended drift from touching sibling shared components.
- Every `AppSwitch` call site listed in `unified-forui-switch-styling` (14 files across settings, contacts, events, financials, members, notifications, setlists, and one_calendar_settings_screen) — appearance unchanged (this branch does not touch `AppSwitch` itself, only makes `AppToggleTile` route through it).
- Every `AppButton` call site (~200+ across the app) — appearance unchanged (this branch does not touch `AppButton` itself, only makes `_CopyButton` route through it).
- Every remaining `Switch.adaptive` call site in the app — must remain unchanged. `AppToggleTile`'s migration to `AppSwitch` does not implicitly migrate any other `Switch.adaptive` call site.
- `AppToggleTile` API surface — `title`, `subtitle`, `value`, `onChanged`, `enabled`, `compact` behave identically for any future caller.
- Calendar tab and Calendar screen — unrelated tabs/screens unchanged.
- Auth (magic-link PKCE), band switching (`activeBandProvider`), ICS feed generation edge function, and RLS on `calendar_feed_preferences` / `band_calendar_tokens` — all unaffected.

## Rollout Strategy

Standard PR against `main` from `bug/subscribe-calendar-full-height-forui`. No feature flag, no database migration, no config change, no dependency change. Rollback is a two-file revert.

## Out of Scope

- Any change to `showAppBottomSheet` shared wrapper defaults.
- Any change to `AppButton`, `AppSwitch`, `AppProgressIndicator`, or `SheetFooter` shared wrappers.
- Any change to the sheet's shell decoration, drag handle, close-X button, or header row — these are the documented Forui-sheet house pattern and must remain visually identical to sibling calendar sheets.
- Any refactor of `AppToggleTile`'s outer `Container` styling, `compact` padding logic, subtitle rendering, or public API.
- Migration of any other `Switch.adaptive` call site elsewhere in the app.
- Migration of any other hand-built button elsewhere in the app.
- Migration of `MediaQuery.of(context)` to `MediaQuery.viewInsetsOf(context)` / `viewPaddingOf(context)` in this file (systemic concern tracked separately by `bulk-entry-instructions-cutoff-ios`).
- Any change to `_InstructionTile`, `_NoteBullet`, the "How to subscribe" section content, the notes bullets, the subscription URL container, or copy edits.
- Any change to `calendar_subscription_service.dart`, `CalendarFeedPreferences`, the URL provider, the preferences RPC, or the ICS feed edge function.
- Golden tests, screenshot tests, or new widget tests — presentation-only change with no branching business logic.
