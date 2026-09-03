# ARCHITECT_PLAN — Switch OFF-state Surface Contrast

## Feature Slug

`bug/switch-off-state-surface-contrast`

## Feature Title

OFF-state toggle switch track blends into the surrounding surface — nearly invisible when off

## Problem Summary

After PR #239 shipped the unified Forui switch styling, a toggle switch in its OFF (default) state reads as an isolated white dot floating on a dark surface, not as a control. The OFF-track fill (`AppColors.switchTrackOff` = `#52525B`, Tailwind Zinc 600) is only 2.13:1 – 2.63:1 relative to the actual surfaces switches render on in the app — below WCAG 2.1 SC 1.4.11's 3:1 threshold for non-text UI components. Tony's perceptual report ("almost impossible to see") matches the math.

A second, structurally-linked problem was surfaced during diagnosis: the Event Editor drawer wraps its content in a nested `FTheme` (`buildEventEditorTheme()`) that does not chain `switchStyle` at all, so switches inside gig/rehearsal form fields and gig expense subview never receive the app-level OFF-track override in the first place — they render Forui's default `colors.secondary` (`#141417`, roughly 1.16:1 against the drawer's `kEdSurface` = `#0C0C0E`). This is a hidden gap in PR #239's "unified switch styling" invariant; it must be closed in the same cycle or the fix ships as a half-fix that leaves a high-traffic path (event editing) still broken.

## Root Cause

**Confidence: HIGH** — validated end-to-end in the code and against the WCAG luminance formula on the exact hex values.

### Which surface each reproduction screen actually puts a switch on

Traced by reading the widget tree from switch call site upward until the first ancestor that sets a `color`/`backgroundColor`. Result (dark mode only; the app is dark-only):

| Screen (call site) | Immediate ancestor that sets a color | Surface hex | Ref |
| --- | --- | --- | --- |
| Settings → Light mode toggle | `AppScaffold(backgroundColor: context.colors.background)` | `#09090B` | [settings_screen.dart#L288-L290](lib/features/settings/settings_screen.dart#L288-L290), [_LightModeToggle build](lib/features/settings/settings_screen.dart#L387-L432) |
| Notifications Settings → Master toggle | `_MasterToggleCard`'s `Container(color: context.colors.surface)` | `#18181B` | [notification_settings_screen.dart#L273-L283](lib/features/notifications/notification_settings_screen.dart#L273-L283) |
| Print Options bottom sheet toggles | `showModalBottomSheet(backgroundColor: Theme.of(context).colorScheme.surface)` (= `BrandColors.dark.surface`) | `#18181B` | [print_options_bottom_sheet.dart#L46-L52](lib/features/setlists/widgets/print_options_bottom_sheet.dart#L46-L52), [app_theme.dart#L21-L26](lib/app/theme/app_theme.dart#L21-L26) |
| Gig Pay bottom sheet → 1099 toggle | Sheet's outer `Container(color: context.colors.surface)` | `#18181B` | [gig_pay_bottom_sheet.dart#L268-L275](lib/features/financials/widgets/gig_pay_bottom_sheet.dart#L268-L275), [gig_pay_bottom_sheet.dart#L440-L450](lib/features/financials/widgets/gig_pay_bottom_sheet.dart#L440-L450) |
| Role Management sheet → contributor permission toggles | `AppScaffold(backgroundColor: context.colors.background)` | `#09090B` | [role_management_sheet.dart#L230-L232](lib/features/members/widgets/role_management_sheet.dart#L230-L232), [role_management_sheet.dart#L574-L595](lib/features/members/widgets/role_management_sheet.dart#L574-L595) |
| Band Member Edit Drawer → permission toggles | Drawer's outer `Container(color: context.colors.surface)` | `#18181B` | [band_member_edit_drawer.dart#L253-L260](lib/features/contacts/widgets/band_member_edit_drawer.dart#L253-L260), [band_member_edit_drawer.dart#L644-L666](lib/features/contacts/widgets/band_member_edit_drawer.dart#L644-L666) |
| Add Financial Entry bottom sheet → 3 toggles | Sheet's outer `Container(color: context.colors.surface)` | `#18181B` | [add_financial_entry_bottom_sheet.dart#L585-L597](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L585-L597) |
| One Calendar Settings → 2 toggles | `_MasterToggleCard` / `_AutoConflictToggleCard` `Container(color: context.colors.surface)` | `#18181B` | [one_calendar_settings_screen.dart#L268-L275](lib/features/calendar/one_calendar_settings_screen.dart#L268-L275), [one_calendar_settings_screen.dart#L422-L430](lib/features/calendar/one_calendar_settings_screen.dart#L422-L430) |
| Event Editor drawer → Potential Gig / Potential Rehearsal / expense toggle | `FTheme(data: buildEventEditorTheme(), child: Container(color: kEdSurface))` — nested Forui theme, **no `switchStyle` override** | `#0C0C0E` | [event_editor_drawer.dart#L2701-L2712](lib/features/events/widgets/event_editor_drawer.dart#L2701-L2712), [event_editor_theme.dart#L20-L41](lib/app/theme/event_editor_theme.dart#L20-L41) |

### Contrast math (WCAG 2.1 SC 1.4.11 threshold: 3:1 for non-text UI)

Current `AppColors.switchTrackOff = #52525B` (Zinc 600) vs each real surface:

| Surface | Contrast ratio | Passes 3:1? |
| --- | --- | --- |
| `#09090B` (`background`) | **2.63:1** | No |
| `#0C0C0E` (`kEdSurface`) | **2.53:1** | No |
| `#18181B` (`surface`) | **2.25:1** | No |

Every surface fails. Tony's "nearly invisible" is the correct perceptual read for a 2.25:1 solid pill against a dark neutral — the shape is present but doesn't cross the "clearly a UI component" threshold.

**Side-check on the same fill against Forui's own OFF default `colors.secondary = #262626` (which the amendment reported the fix was replacing):** `#52525B` vs `#262626` = ~1.94:1. So `#52525B` was already a lift over the raw Forui default, but not enough to clear the WCAG bar on the app's darker surfaces (`#09090B`, `#0C0C0E`, `#18181B` are all darker than the `#262626` the prior amendment was benchmarked against — the prior amendment's "~2.3–2.6:1" range was correct for the direction, but that band is below the 3:1 threshold, not above it).

### Event Editor drawer — separate root cause on the same symptom

`event_editor_drawer.dart` line 2701–2705 wraps the drawer body in a nested Forui theme:

```dart
return FTheme(
  data: buildEventEditorTheme(),   // <-- scoped, no switchStyle chain
  child: Container(
    ...
    color: kEdSurface,             // #0C0C0E
```

`buildEventEditorTheme()` ([event_editor_theme.dart#L20-L41](lib/app/theme/event_editor_theme.dart#L20-L41)) does `return FThemeData(colors: colors, touch: true);` — no `.copyWith(switchStyle: ...)`. So switches inside the event editor drawer resolve their OFF-track to Forui's own `colors.secondary` (`#141417` per the `secondary` override in that theme), not to `AppColors.switchTrackOff`. Contrast: `#141417` vs `#0C0C0E` ≈ **1.16:1** — essentially invisible.

Changing `AppColors.switchTrackOff` alone does not reach the event editor drawer. The token change fixes the seven other reproduction screens; the event editor drawer needs the same `switchStyle` delta merged into `buildEventEditorTheme()` for the fix to be complete.

## Existing System Analysis

- **App-level Forui theme wrap.** `main.dart` L170-171 wraps the whole app in `FTheme(data: AppTheme.foruiTheme(brightness), ...)`. `AppTheme.foruiTheme` ([app_theme.dart#L613-L644](lib/app/theme/app_theme.dart#L613-L644)) chains `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))` with `trackColor` doing `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` + `.match({FSwitchVariant.selected}, AppColors.primarySoft)`. Every reference to the OFF-track color goes through the `AppColors.switchTrackOff` symbol — so a value change in `design_tokens.dart` propagates automatically to all switches under the app-level FTheme, without touching `app_theme.dart`.
- **Nested drawer-scoped Forui theme.** `event_editor_drawer.dart#L2701-L2712` wraps the drawer body in a second `FTheme` with its own `FThemeData` (`kEdSurface`, primary `#fb2c5a`, secondary `#141417`, etc.). The app-level `switchStyle` override does not flow through — Forui's `switchStyle` is a field on `FThemeData`, not something that gets inherited from an outer `FTheme` when a nested `FTheme` supplies its own `FThemeData`. This is confirmed by reading how `FSwitchStyle.inherit(...)` resolves (via `FTheme.of(context).switchStyle`, which returns the closest `FThemeData`).
- **AppSwitch → FSwitch contract intact.** [app_switch.dart](lib/components/ui/app_switch.dart) still wraps `FSwitch` cleanly; no call-site override is currently competing with the OFF-state fill on any of the 15 app-level switch sites migrated by PR #239. The wrapper's `activeColor`/`activeTrackColor` params exist for backwards compat but no feature file passes them post-#239. The wrapper itself needs no change for this fix.
- **`AppColors.switchTrackOff` token is scoped, not overloaded.** Search confirms `#52525B` appears in `brand_colors.dart` (`borderStrong`, `textDisabled`) and `event_editor_theme.dart` (`kEdPlaceholder`), but those are named tokens with independent purposes — changing `switchTrackOff` in `design_tokens.dart` does not accidentally re-color a border or disabled text or a placeholder.
- **Prior-cycle history to respect.** Tony declined a literal stroked outline both via Container wrapper and via CupertinoSwitch bypass because both break the shared `AppSwitch → FSwitch` component contract. The existing theme-level fill via `FVariantValueDeltaOperation.base(...)` is the sanctioned mechanism; this plan keeps that mechanism and only revises the specific hex it emits.
- **Existing test coverage.** [app_switch_test.dart](test/components/ui/app_switch_test.dart) already includes: (a) OFF-track under `AppTheme.foruiTheme` resolves to `AppColors.switchTrackOff` (symbolic assertion — no hex hardcoded); (b) ON-track resolves to `AppColors.primarySoft`; (c) thumb resolves to `Colors.white`; (d) 4 other structural tests. The symbolic assertions in (a)–(c) survive the value change without edit. No test file currently exercises `buildEventEditorTheme()`'s `switchStyle` resolution — adding one is proportional to the second half of the fix.

## Proposed Solution

Two-token-level changes, no widget or call-site changes:

### Change 1 — Raise `AppColors.switchTrackOff` from Zinc 600 to Zinc 500

Update the single token declaration in [design_tokens.dart](lib/app/theme/design_tokens.dart):

```dart
// FROM
static const Color switchTrackOff = Color(0xFF52525B); // Tailwind zinc-600

// TO
static const Color switchTrackOff = Color(0xFF71717A); // Tailwind zinc-500
```

Post-change contrast against every switch surface in the app:

| Surface | Contrast vs `#71717A` | Passes 3:1? |
| --- | --- | --- |
| `#09090B` (`background`) | **~4.08:1** | Yes |
| `#0C0C0E` (`kEdSurface`) | **~3.98:1** | Yes |
| `#18181B` (`surface`) | **~3.59:1** | Yes |

**One value covers every switch surface in the app** — the darkest (`#18181B`) still clears WCAG 3:1 with margin (~0.6). The lighter surfaces (`#09090B`, `#0C0C0E`) get 4:1+. No trade-off between surfaces is required; this is a clean fix.

Why `#71717A` (Zinc 500) specifically, and not lighter:

- It's the next step up the Tailwind Zinc ladder from the current `#52525B` (Zinc 600). Preserves the "we build from the Zinc palette" convention documented at the top of `AppColors`.
- Zinc 400 (`#A1A1AA`) is already `BrandColors.dark.textSecondary`. Reusing it for a switch track would make the OFF switch as visually prominent as body-secondary text, which reads as too loud for the "unselected" state. Zinc 500 stays clearly quieter than body copy while clearly louder than surface neutrals.
- Zinc 500 preserves a distinct hue/luminance gap against the ON-state track (`AppColors.primarySoft` = `#FB7185`, Tailwind rose-400) — the ON→OFF transition remains obvious (chromatic rose vs. achromatic gray, with a large luminance and hue delta).
- No overlap with `borderStrong` (`#52525B`) or `textDisabled` (`#52525B`) — the OFF track becomes its own distinct value in the palette rather than duplicating existing tokens (a mild cleanup of the palette by side effect).

### Change 2 — Mirror the app-level `switchStyle` override into `buildEventEditorTheme()`

Update [event_editor_theme.dart](lib/app/theme/event_editor_theme.dart) so the drawer-scoped Forui theme applies the same OFF/ON track and thumb overrides that the app-level theme applies:

```dart
// FROM
return FThemeData(colors: colors, touch: true);

// TO
return FThemeData(colors: colors, touch: true).copyWith(
  switchStyle: FSwitchStyleDelta.delta(
    trackColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.base(AppColors.switchTrackOff),
      FVariantValueDeltaOperation.match(
        {FSwitchVariant.selected},
        AppColors.primarySoft,
      ),
    ]),
    thumbColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.all(Colors.white),
    ]),
  ),
);
```

Uses the exact same tokens (`AppColors.switchTrackOff`, `AppColors.primarySoft`, `Colors.white`) and delta shape as the app-level override — no new tokens, no divergent styling. This closes the event editor drawer gap discovered during diagnosis and completes PR #239's "unified switch styling app-wide" invariant.

The event editor drawer is included in this cycle rather than deferred because:

1. It was not in Tony's reproduction list but shares the exact same symptom on a high-traffic path (creating/editing gigs and rehearsals), and Tony's Feature Input explicitly requested that the plan "look at… how the switch-containing widgets are actually nested" — that nesting is the discovery.
2. The fix is a 5-line additive mirror of code already written and reviewed for PR #239. Zero architectural novelty.
3. Deferring it would ship a partial fix that leaves gig/rehearsal editors with an unfixed OFF switch, which contradicts the shipped design intent.
4. Cost/risk are proportional: the change is scoped to one function in one theme file that only the event editor drawer uses.

## Database Impact

n/a — no migrations, RLS policies, RPCs, triggers, edge functions, or Supabase artifacts touched. Pure client-side Flutter token/theme change.

## Flutter Architecture Changes

- No new controllers, providers, or repositories.
- No changes to Riverpod state, band isolation, or Supabase access.
- No changes to [main.dart](lib/main.dart) init order — theme wrap remains where it is.
- No platform-conditional code — pure Flutter widget/theme change, identical behavior across iOS / Android / macOS / Web.
- No public API change on `AppSwitch` (or any component). No new widgets. No new dependencies.
- One token value change (`AppColors.switchTrackOff` hex) and one theme function chain (`buildEventEditorTheme()` gains a `.copyWith(switchStyle: ...)`).

## Files to Create

None.

## Files to Modify

1. **[lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart)** — In the `AppColors` class, change `switchTrackOff` from `Color(0xFF52525B)` (Zinc 600) to `Color(0xFF71717A)` (Zinc 500). Update its inline hex comment (`// Tailwind zinc-600` → `// Tailwind zinc-500`) and update the doc comment above it to note the value clears WCAG 2.1 SC 1.4.11 (3:1) against every switch surface in the app.
2. **[lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart)** — In `buildEventEditorTheme()`, chain `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))` onto the `FThemeData(...)` return. The delta must mirror the app-level one in `AppTheme.foruiTheme`: `trackColor` uses `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` + `.match({FSwitchVariant.selected}, AppColors.primarySoft)`; `thumbColor` uses `.all(Colors.white)`. Add the `import 'design_tokens.dart';` line if not already present (the file already imports `forui/forui.dart`).
3. **[test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart)** — Add one `testWidgets(...)` case inside the existing `group('AppSwitch', ...)` that pumps `AppSwitch(value: false, onChanged: (_) {})` under `FTheme(data: buildEventEditorTheme())` and asserts the resolved OFF-state track color equals `AppColors.switchTrackOff` (not the drawer theme's `secondary`). This is the only new test — the existing two symbolic assertions (OFF resolves to `AppColors.switchTrackOff`, ON resolves to `AppColors.primarySoft`) already survive the value change without edit.

## Files Off-Limits

- **[lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart)** — the `switchStyle` override already references `AppColors.switchTrackOff` symbolically, so the token change flows through automatically. Do not touch this file.
- **[lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart)** — the wrapper's public API is unchanged; no new params, no removed params.
- **[lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart)** — `borderStrong` and `textDisabled` (both `#52525B`) are unrelated tokens; do not touch. This is not a palette-wide cleanup cycle.
- **All 12 switch-hosting feature files** already touched by PR #239 (settings, notification_settings, print_options_bottom_sheet, gig_pay_bottom_sheet, add_financial_entry_bottom_sheet, one_calendar_settings, gig_expense_subview, gig_form_fields, rehearsal_form_fields, role_management_sheet, band_member_edit_drawer, notifications) — no call-site changes required. Do not touch.
- **[lib/main.dart](lib/main.dart)** — init order and theme wiring correct as-is.
- **All Supabase artifacts** (`supabase/migrations/**`, `supabase/functions/**`, `supabase/config.toml`) — no DB / edge function change.
- **`pubspec.yaml` / `pubspec.lock`** — no new dependency, no version bump.
- **`AndroidManifest.xml`, `Info.plist`, entitlements** — no platform config change.
- **Any file not enumerated in "Files to Modify"** — including other Forui component wrappers, unrelated widgets, docs, and marketing assets.

## Change Budget

- **[design_tokens.dart](lib/app/theme/design_tokens.dart)**: **~0 net lines** (one hex swap + updated inline/doc comments; potentially +1 line if the doc comment grows by one line for the WCAG note).
- **[event_editor_theme.dart](lib/app/theme/event_editor_theme.dart)**: **+12 to +14 lines** (one `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))` block mirroring the app-level one, plus at most one new import line if `design_tokens.dart` isn't already imported).
- **[app_switch_test.dart](test/components/ui/app_switch_test.dart)**: **+15 to +22 lines** (one new `testWidgets` case; existing OFF-state assertion needs no edit because it's symbolic).
- **Total net delta**: approximately **+30 lines**.
- **Expected new files**: **0**.
- **Expected new public classes/methods/params**: **0**.
- **Expected new dependencies**: **0**.

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Settings | affected | `_LightModeToggle` OFF track now clears WCAG 3:1 against Scaffold `#09090B` |
| Notifications (settings screen) | affected | `_MasterToggleCard` OFF track now clears WCAG 3:1 against `#18181B` |
| Setlists → Print Options | affected | 4 toggles now clear WCAG 3:1 against sheet surface `#18181B` |
| Financials → Gig Pay bottom sheet | affected | 1099 toggle now clears WCAG 3:1 against sheet `#18181B` |
| Financials → Add Financial Entry | affected | 3 toggles now clear WCAG 3:1 against sheet `#18181B` |
| Calendar → One Calendar Settings | affected | 2 toggles now clear WCAG 3:1 against card `#18181B` |
| Members → Role Management sheet | affected | 6 contributor-permission toggles now clear WCAG 3:1 against Scaffold `#09090B` |
| Contacts → Band Member Edit Drawer | affected | 6 permission toggles now clear WCAG 3:1 against drawer `#18181B` |
| Events → Editor drawer (Gig / Rehearsal / Expense) | affected | 4 toggles gain the `switchStyle` override for the first time (drawer previously fell back to Forui default) — OFF now clears WCAG 3:1 against `kEdSurface` `#0C0C0E`; ON gains the softer rose + white thumb, matching the rest of the app |
| ON-state track / thumb visuals | unchanged | `AppColors.primarySoft` (`#FB7185`) and `Colors.white` unchanged; ON-state contrast unaffected |
| Disabled OFF / disabled ON | unchanged | `FVariantValueDeltaOperation.base(...)` and `.match({.selected}, ...)` do not touch the `.disabled` / `.selected.and(.disabled)` variants — Forui's default dimming survives intact |
| Auth / Login / Session | unaffected | No switches in auth flow; no theme touch |
| Routing / Deep Links | unaffected | No route or link config changed |
| Notifications (FCM delivery) | unaffected | Only the settings SCREEN toggle is affected; FCM registration, tokens, and edge functions untouched |
| Platforms (iOS / Android / macOS / Web) | affected uniformly | Pure Flutter widget/theme change |
| Init order | unaffected | `main.dart` untouched |
| Database / RLS / RPCs | unaffected | No SQL or Supabase artifact touched |

## Regression Risk

**LOW.**

- **LOW factors**: Pure client-side visual change. Two files touched, one line of runtime effect per file. No auth, session, routing, init order, or DB code touched. The `.copyWith(switchStyle: ...)` block added to `buildEventEditorTheme()` is a byte-for-byte structural copy of the app-level override that has already been reviewed and shipped in PR #239 — no new Forui API surface. Token value change is byte-for-byte symbolic-safe (no hardcoded `#52525B` outside `design_tokens.dart`, `brand_colors.dart`, and `event_editor_theme.dart`'s independent `kEdPlaceholder`, none of which we touch). Existing app_switch tests pass without edit because their assertions are symbolic.
- **Very small MEDIUM factor**: The Event Editor drawer gains a `switchStyle` override where previously it had none. This changes the ON-state track color inside the drawer from `#fb2c5a` (drawer theme's `primary`) to `AppColors.primarySoft` (`#FB7185`) — a small hue shift toward the softer app-wide rose. This is intentional (unifies the drawer with the rest of the app per PR #239's stated intent) and is called out in the QA regression list.

## Engineer Task Breakdown

Ordered so each step compiles and runs cleanly on its own.

1. **Update `AppColors.switchTrackOff` value.** In [design_tokens.dart](lib/app/theme/design_tokens.dart), change the hex literal on the `switchTrackOff` declaration from `Color(0xFF52525B)` to `Color(0xFF71717A)`. Update the inline hex comment from `// Tailwind zinc-600` to `// Tailwind zinc-500`. Update the doc comment above the declaration to read one line: `/// OFF-state track fill for app toggle switches — Tailwind Zinc 500, chosen to clear WCAG 2.1 SC 1.4.11 (3:1) against every dark surface the app renders switches on.` (Replace the current doc comment; do not stack a new one on top.) Do not touch any other declaration in this file, and do not touch `borderStrong` or `textDisabled` in `brand_colors.dart`.
2. **Add `switchStyle` override to `buildEventEditorTheme()`.** In [event_editor_theme.dart](lib/app/theme/event_editor_theme.dart), change the terminal `return FThemeData(colors: colors, touch: true);` to `return FThemeData(colors: colors, touch: true).copyWith(switchStyle: FSwitchStyleDelta.delta(...));` with the exact delta shape shown in "Proposed Solution → Change 2" above. Add `import 'design_tokens.dart';` at the top of the file if it isn't already imported (Engineer: check the current import list; do not add a duplicate). Do not touch any of the `kEd*` constants or the `FColors.neutralDark.copyWith(...)` block.
3. **Add one `testWidgets` case in `app_switch_test.dart`.** Inside the existing `group('AppSwitch', ...)`, immediately after the existing `'off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme'` case, add a new case titled `'off-state track resolves to AppColors.switchTrackOff under buildEventEditorTheme'`. It should pump `AppSwitch(value: false, onChanged: (_) {})` inside a `MaterialApp(builder: (context, child) => FTheme(data: buildEventEditorTheme(), child: child!))` (add the `buildEventEditorTheme` import at the top of the test file), locate the `FSwitch`, read `FTheme.of(element).switchStyle`, and assert `switchStyle.trackColor.resolve(<FVariant>{}) == AppColors.switchTrackOff`. Do not modify any existing test case.
4. **Verify locally.** Run `flutter analyze` — expect zero new warnings or errors in the touched files. Run `flutter test test/components/ui/app_switch_test.dart` — expect all cases (existing + 1 new) to pass. If time permits, run the full `flutter test` to confirm no unrelated widget test snapshots depend on the previous switch color.

## Verification Plan

### Tier 1 (pre-deploy — must all pass before merge; none of these call any pre-fix code path)

1. **Static grep gates** (each must return exactly what's stated):
   - `grep -n "switchTrackOff" lib/app/theme/design_tokens.dart` returns exactly one match, on a line containing `Color(0xFF71717A)`. `grep -n "0xFF52525B" lib/app/theme/design_tokens.dart` returns zero matches.
   - `grep -n "switchStyle" lib/app/theme/event_editor_theme.dart` returns at least one match on a line inside `buildEventEditorTheme()`. `grep -n "AppColors.switchTrackOff\|AppColors.primarySoft" lib/app/theme/event_editor_theme.dart` returns exactly two matches (or more if the doc comment mentions them).
   - `grep -rn "0xFF52525B\|0xFF71717A" lib/features` returns zero matches (no feature file hardcodes either value).
2. **`flutter analyze`** — zero new warnings or errors in either touched file. No new lint suppressions.
3. **`flutter test test/components/ui/app_switch_test.dart`** — every case passes, including:
   - Existing "off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme" case (proves the app-level path still resolves via the symbol).
   - New "off-state track resolves to AppColors.switchTrackOff under buildEventEditorTheme" case (proves the drawer-scoped path now inherits the same OFF-track).
   - Existing "on-state track/thumb" case (proves the ON path is unchanged).
4. **Manual visual smoke test on macOS.** Engineer runs `./run.sh macos` and confirms an OFF switch reads as a **clearly-visible medium-gray pill** with a white thumb on the left, on each of the following screens (each entry names the actual surface the switch renders on, so QA can visually confirm the contrast against that specific surface, not a guess):

   | Screen | Actual surface behind switch |
   | --- | --- |
   | Settings → Light mode toggle | Scaffold `context.colors.background` (`#09090B`) |
   | Notifications Settings → Master Toggle card | `Container(color: context.colors.surface)` (`#18181B`) |
   | Setlists → Print Options bottom sheet | Sheet `colorScheme.surface` (`#18181B`) |
   | Financials → Gig Pay bottom sheet → 1099 toggle | Sheet outer `Container(color: context.colors.surface)` (`#18181B`) |
   | Financials → Add Income (or Add Expense) → 1099 / Disburse to Band / Deposit to Savings | Sheet outer `Container(color: context.colors.surface)` (`#18181B`) |
   | Members → Role Management sheet → any contributor permission toggle | Scaffold `context.colors.background` (`#09090B`) |
   | Contacts → Band Member Edit Drawer → any permission toggle | Drawer outer `Container(color: context.colors.surface)` (`#18181B`) |
   | Calendar → One Calendar Settings → Master + Auto-conflict toggle | Card `Container(color: context.colors.surface)` (`#18181B`) |
   | Events → Add Gig drawer → Potential Gig toggle | Event editor drawer body `Container(color: kEdSurface)` (`#0C0C0E`) — validates Change 2 |
   | Events → Add Rehearsal drawer → Potential Rehearsal toggle | Same drawer body `kEdSurface` (`#0C0C0E`) — validates Change 2 |
   | Events → Gig expense subview toggle | Same drawer body `kEdSurface` (`#0C0C0E`) — validates Change 2 |

5. **Verify ON-state parity** on any one of the above screens: toggling the switch ON must produce the softer-rose (`#FB7185`) track + white thumb — the same ON visual PR #239 shipped. In the Event Editor drawer specifically, confirm the ON state now matches the rest of the app (softer rose, not the drawer's own `#fb2c5a` primary).

### Tier 2 (post-deploy)

n/a — pure client-side visual change. No backend state to verify after deploy that isn't already covered by Tier 1.

## QA Regression Areas

- **Every switch listed in Tier 1 step 4** — verify: correct initial state (bug is OFF-state visibility only; ON state must still look identical to PR #239), toggling still persists to underlying state (Financials still saves, permission toggles still apply to the member, Potential Gig toggle still gates the "Expected members" grid, etc.), disabled switches (e.g. Gig Pay in `viewOnly` mode) still visually dim per Forui's default `.disabled` handling.
- **Event Editor drawer ON-state color shift** — this is intentional (unification with the rest of the app) but the drawer's ON track will visually shift from `#fb2c5a` to `#FB7185`, a small softer-rose delta. QA must confirm this reads as intentional (matches other screens), not as a regression.
- **Sanity check on tokens with the same hex.** `borderStrong` (`#52525B`) and `textDisabled` (`#52525B`) still use `#52525B` after this fix. Confirm no visual regression on:
  - Any UI that uses `context.colors.borderStrong` (e.g. borders / dividers that use it).
  - Any UI that uses `context.colors.textDisabled` (e.g. disabled text labels / disabled Save button labels).
  This is a sanity check that the value change was strictly scoped to `switchTrackOff` and did not accidentally re-color other palette entries.
- **Dark-mode only** — confirmed always dark; no light-mode regression check required.
- **Cross-platform spot check.** After macOS passes, quick smoke on iOS Simulator (native) and Chrome (web). Behavior must be identical.

## Rollout Strategy

Standard merge to `main` after Engineer implementation and QA sign-off. No feature flag, no phased rollout, no data migration, no schema migration. Pure visual change — safe to ship in a single PR. Rollback is a straightforward `git revert` if any visual regression is discovered post-merge; no data or state to migrate back.

## Out of Scope

- Any change to `AppColors.primary`, `AppColors.primarySoft`, `Colors.white`, or the thumb color.
- Any change to `borderStrong`, `textDisabled`, or `kEdPlaceholder` (also `#52525B`, but semantically independent).
- Any reworking of the "unified switch component" contract itself (`AppSwitch → FSwitch`) — the wrapper is not touched.
- Any change to the disabled OFF / disabled ON handling (Forui default dimming is intentionally preserved).
- Any accessibility work outside of the OFF-track contrast fix (no label size changes, no touch-target changes, no keyboard-focus changes).
- Any DB migration, RLS policy, RPC, or edge function change.
- Any change to `AndroidManifest.xml`, `Info.plist`, entitlements, or platform config.
- Any change to `pubspec.yaml`, `pubspec.lock`, or dependency versions.
- Any refactor of the two `Container(color: context.colors.surface)` outer wrappers in the bottom sheets and drawer, or the Scaffold's `backgroundColor` on Settings / Role Management — the surfaces are the correct targets for switches to sit on; the fix is the switch, not the surface.
- Reconciling the `#F43F5E` vs `#FF2056` brand-color note from PR #239's plan (still a separate discussion, still not this cycle).
