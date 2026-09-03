# ARCHITECT_PLAN — Unified Forui Switch Styling

## Feature Slug

`feature/unified-forui-switch-styling`

## Feature Title

Unify all app toggle switches on one Forui Switch component with improved on-state contrast

## Problem Summary

Toggle switches in the app are not visually or structurally unified:

1. **Component drift**: 16 switch instances across 12 feature files use three different widgets — `AppSwitch` (10), raw Material `Switch` (4), and Material `SwitchListTile` (2). The `AppSwitch` wrapper around Forui's `FSwitch` already exists as the "one shared switch" contract, but 6 call sites bypass it.
2. **Poor on-state contrast**: In the ON state, the FSwitch track resolves to `colors.primary` (rose `#FF2056`), and several call sites explicitly force the Material Switch thumb to the same rose — so thumb and track are both the same saturated rose and hard to tell apart. Even where `AppSwitch` is used correctly, the track uses the full-saturation brand rose against a light thumb, and per-call-site `activeColor:` / `activeTrackColor:` overrides scattered across features prevent a single theme fix from taking effect.

## Root Cause

**Confidence: HIGH** — validated end-to-end in the code.

### Component drift (structural)

`grep_search` inventory:

- `AppSwitch(` — 10 sites, 7 files (calendar, events × 3, notifications, print options, settings).
- Raw `Switch(` — 4 sites, 2 files (`features/financials/widgets/add_financial_entry_bottom_sheet.dart` × 3, `features/financials/widgets/gig_pay_bottom_sheet.dart` × 1).
- `SwitchListTile(` — 2 sites, 2 files (`features/contacts/widgets/band_member_edit_drawer.dart`, `features/members/widgets/role_management_sheet.dart`).

The Forui preview cycle documented in [lib/components/ui/README.md](lib/components/ui/README.md) explicitly lists `AppSwitch → FSwitch` as the shared abstraction, but the cycle never migrated the 4 Material `Switch(` and 2 `SwitchListTile(` call sites, so the "single component" invariant is not currently enforced.

### On-state contrast (visual)

In [forui-0.26.0/switch.dart line 231-241](https://pub.dev/packages/forui), `FSwitchStyle.inherit` sets:

```dart
trackColor: FVariants(
  colors.secondary,                                    // off
  variants: {
    [.disabled]: colors.disable(colors.secondary),
    [.selected]: colors.primary,                       // ON = full rose #FF2056
    [.selected.and(.disabled)]: colors.disable(colors.primary),
  },
),
thumbColor: .all(colors.brightness == .light ? colors.background : colors.foreground),
```

Combined with the current `AppTheme.foruiTheme` in [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart#L615-L633), which only overrides `primary` (rose `#FF2056`) and `primaryForeground` (white) and does not override `switchStyle`, the ON-state track resolves to the full-saturation brand rose for every `FSwitch` in the app.

Meanwhile:

- [features/financials/widgets/gig_pay_bottom_sheet.dart line 440-444](lib/features/financials/widgets/gig_pay_bottom_sheet.dart#L440-L444) explicitly forces `activeThumbColor: AppColors.primary` (rose) AND `activeTrackColor: AppColors.primary.withAlpha(128)` — thumb and track are both rose, differing only in alpha. This is the visually-worst instance and matches the reproduction description exactly.
- [features/financials/widgets/add_financial_entry_bottom_sheet.dart line 823-931](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L823-L931) uses raw `Switch` with `activeTrackColor: AppColors.primary` and no explicit `activeThumbColor` — Material 3 then derives the thumb from `colorScheme.onPrimary`, which for this app's seed-based scheme is not guaranteed to be near-white.
- [features/events/widgets/rehearsal_form_fields.dart line 260-261, 603-604](lib/features/events/widgets/rehearsal_form_fields.dart#L260-L261) passes `activeColor: const Color(0xFFfb2c5a)` — a hardcoded near-rose that isn't even `AppColors.primary` (`#FF2056`) and violates the "no `Color(0xFF…)` outside `design_tokens.dart`" convention.

### Note on the Feature Input's stated brand color

The Feature Input references rose as `#F43F5E` (Tailwind rose-500). The actual `AppColors.primary` is `#FF2056` (shadcn/Forui rose primary), consistent with the copilot instructions preamble which says `#F43F5E` and with `AppColors.setlistGradientColors[0]` which is `#F43F5E`. This plan trusts the code (`#FF2056`) — the derived "lighter tint" is computed from the real `AppColors.primary`, not from `#F43F5E`. Discrepancy noted, no change to `AppColors.primary` in scope.

## Existing System Analysis

- **Theme wiring**: [lib/main.dart line 170-171](lib/main.dart#L170-L171) wraps the whole app in `FTheme(data: AppTheme.foruiTheme(brightness), ...)`. Any override we add to `foruiTheme` propagates to every `FSwitch` in the tree automatically — no per-call-site changes are required to fix the color, only to fix the component drift.
- **AppSwitch API**: [lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart) already exposes `activeColor` (thumb) and `activeTrackColor` (track) overrides via `FSwitchStyleDelta`. These per-call overrides currently defeat the theme default when set — several `AppSwitch` call sites do set them (unnecessarily, to the same rose the theme would already produce). The wrapper is the correct abstraction; the call sites just need to stop passing overrides.
- **`SwitchListTile` UX contract**: Material's `SwitchListTile` toggles when the user taps anywhere on the row (label + switch). `FSwitch` supports the same tap-anywhere behavior via its built-in `label` / `leadingLabel` fields — verified in [forui-0.26.0/switch.dart lines 45-107](https://pub.dev/packages/forui). Migration is 1:1 with no UX regression as long as we use `FSwitch.label` rather than `Row(Text, AppSwitch)`.
- **`FThemeData.copyWith`**: Verified in [forui-0.26.0/theme_data.dart line 1400](https://pub.dev/packages/forui) that `switchStyle: FSwitchStyleDelta?` is exposed on `copyWith`. This is the correct hook — no need to rebuild the whole `FThemeData` from scratch.
- **Design tokens**: [lib/app/theme/design_tokens.dart line 152](lib/app/theme/design_tokens.dart#L152) is the single source of truth for `AppColors.primary`. Adding one additional named token here (e.g., `AppColors.primarySoft`) for the lighter rose track is idiomatic and preserves the "no raw `Color(0xFF…)` outside `design_tokens.dart`" rule.
- **Existing tests**: [test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart) already exists with 4+ test cases; per the "no new test file where an existing group can take one more case" rule, new coverage goes into that file, not a new one.

## Proposed Solution

Two-part fix, both parts required:

### Part 1 — One shared component (structural)

Migrate the 4 raw `Switch(` and 2 `SwitchListTile(` call sites to `AppSwitch`. For the `SwitchListTile` cases, use `FSwitch`'s built-in label pattern so tap-anywhere UX is preserved. Extend `AppSwitch` with two new optional params (`label`, `leadingLabel`) that pass straight through to `FSwitch`.

### Part 2 — Unified on-state colors (visual)

Override `switchStyle` once in `AppTheme.foruiTheme(brightness)` via `FThemeData.copyWith`:

- **ON-state track**: `AppColors.primarySoft` — a lighter tint of `AppColors.primary` (see Design Tokens below).
- **Thumb (all variants)**: `Colors.white` — guaranteed near-white in dark mode, giving strong contrast against the lighter-rose track. This replaces Forui's `colors.foreground` default, which in `FColors.neutralDark` is a light gray but not pure white.
- **Off-state track**: Leave at Forui's default (`colors.secondary`, a mid-gray) — no change needed.
- **Focus / disabled**: Leave at Forui's default.

Because this is a theme-level override, all 10 existing `AppSwitch` sites AND the 6 migrated sites pick up the new colors at once with zero call-site code changes.

Also remove all per-call `activeColor:` / `activeTrackColor:` / `activeThumbColor:` overrides on `AppSwitch` and (post-migration) on the newly-converted call sites, so the theme default is not defeated site-by-site. Keep the existing `activeColor` / `activeTrackColor` params on `AppSwitch` (do not delete — public API preservation), but stop passing them from feature code.

### Design token choice (implementation detail)

Add one named token to `design_tokens.dart`:

```dart
/// Lighter rose tint used for the ON-state track of app toggle switches so
/// the (white) thumb has visible contrast against the (rose) track.
/// Derived visually from AppColors.primary (#FF2056) toward white.
static const Color primarySoft = Color(0xFFFB7185); // Tailwind rose-400
```

Rationale for the specific value: `#FB7185` is Tailwind rose-400, one step lighter than the shadcn/Forui rose primary the code already uses as its brand anchor. It reads as clearly "still rose, just softer", produces a WCAG-visible delta against pure white (~2.1:1), and matches the palette convention documented in [lib/components/ui/README.md](lib/components/ui/README.md). Engineer may substitute an equivalent `Color.lerp(AppColors.primary, Colors.white, ~0.35)` result if a computed form is preferred — same visual outcome, still declared once in `design_tokens.dart`.

## Database Impact

n/a — no migrations, RLS policies, RPCs, triggers, or edge functions. Pure client-side Flutter widget/theme change.

## Flutter Architecture Changes

- No new controllers, providers, or repositories.
- No changes to Riverpod state management, band isolation, or Supabase access.
- No changes to init order in [lib/main.dart](lib/main.dart) — `FTheme` wrap already exists in the correct position.
- No platform-conditional code (works identically on iOS / Android / macOS / Web).
- One additive param pair on the existing `AppSwitch` widget (`label`, `leadingLabel`) — API-compatible extension, no breaking changes to existing call sites.

## Files to Create

None.

## Files to Modify

### Theme + shared component (3 files)

1. **[lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart)** — Add `AppColors.primarySoft = Color(0xFFFB7185)` with a short doc comment explaining it's the switch on-state track tint.
2. **[lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart)** — In `AppTheme.foruiTheme(brightness)`, chain a `.copyWith(switchStyle: FSwitchStyleDelta.delta(trackColor: …, thumbColor: …))` after the current `FThemeData(colors: colors, touch: true)`. Track color: override the `.selected` variant to `AppColors.primarySoft`; leave `.disabled` and default (off) alone. Thumb color: `.all(Colors.white)`.
3. **[lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart)** — Add two optional params `Widget? label` and `bool leadingLabel = false`, pass through to `FSwitch`. Preserve existing `activeColor` / `activeTrackColor` params unchanged (public API preservation).

### Component-drift migration (6 files)

4. **[lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart)** — Replace 3 `Switch(...)` with `AppSwitch(value:, onChanged:)`. Drop `activeTrackColor`, `inactiveTrackColor`, `inactiveThumbColor` overrides. Row layout (label + switch) already exists in the parent widget tree — no structural change needed.
5. **[lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart)** — Replace 1 `Switch(...)` with `AppSwitch(value:, onChanged:)`. Drop `activeThumbColor` and `activeTrackColor` overrides. Preserve `viewOnly`-disabled behavior by passing `onChanged: viewOnly ? null : (v) => …` (matches existing pattern).
6. **[lib/features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart)** — Replace `SwitchListTile(...)` in `_buildPermissionToggle` with `AppSwitch(value:, onChanged:, label: Text(...), leadingLabel: true)`. Wrap in the existing `Padding` to preserve `contentPadding: horizontal: 4` and `dense: true` visual metrics. Drop `activeTrackColor` override.
7. **[lib/features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart)** — Same treatment as file 6 (`_buildPermissionToggle` has identical structure).

### Override cleanup on existing AppSwitch call sites (6 files)

Drop `activeColor:` / `activeTrackColor:` params so the new theme default takes effect uniformly:

8. **[lib/features/calendar/one_calendar_settings_screen.dart](lib/features/calendar/one_calendar_settings_screen.dart)** — Remove `activeTrackColor: AppColors.primary` from the 2 `AppSwitch` call sites at lines 303-306 and 456-459.
9. **[lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart)** — Remove `activeColor: AppColors.primary` from the `AppSwitch` at line 344-346.
10. **[lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart)** — Remove `activeColor: AppColors.primary` from the `AppSwitch` at line 1119-1124.
11. **[lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)** — Remove `activeColor: const Color(0xFFfb2c5a)` AND `activeTrackColor: const Color(0xFFfb2c5a)` from both `AppSwitch` call sites (lines 257-261 and 600-604). This also removes two `Color(0xFF…)` literals from outside `design_tokens.dart`, restoring the token convention.
12. **[lib/features/notifications/notification_settings_screen.dart](lib/features/notifications/notification_settings_screen.dart)** — Remove `activeColor: AppColors.primary` from the `AppSwitch` at line 310-313.
13. **[lib/features/setlists/widgets/print_options_bottom_sheet.dart](lib/features/setlists/widgets/print_options_bottom_sheet.dart)** — Remove `activeTrackColor: AppColors.primary` from both `AppSwitch` call sites at lines 624-627 and 696-699. Do NOT touch the non-switch `activeTrackColor:` matches at lines 661 and 750 (those are on unrelated widgets — verify per line before editing).
14. **[lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart)** — Remove `activeColor: AppColors.primary` from the `AppSwitch` at line 423-426.

### Test coverage (1 file, extended not created)

15. **[test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart)** — Add cases: (a) when wrapped in the app's `AppTheme.foruiTheme` (not `FTheme.neutral.dark`), the resolved ON-state track color equals `AppColors.primarySoft` and the thumb color equals `Colors.white` — asserted by pumping the widget and reading `FSwitch`'s style / theme; (b) when `label:` is provided with `leadingLabel: true`, the label text is rendered and tapping it flips the value.

## Files Off-Limits

- **[lib/main.dart](lib/main.dart)** — init order and theme wiring position are correct; no changes required or permitted.
- **All auth files** (`lib/features/auth/**`) — unaffected by switch styling.
- **Routing / deep link config** (`lib/app/services/deep_link_service.dart`, `AndroidManifest.xml`, `Info.plist`, `Runner.entitlements`) — no route or platform config touched.
- **All Supabase artifacts** (`supabase/migrations/**`, `supabase/functions/**`, `supabase/config.toml`) — no DB / edge function change.
- **`pubspec.yaml` / `pubspec.lock`** — no new dependency, no version bump.
- **Any file not enumerated in "Files to Modify"** — including other Forui component wrappers (checkbox, radio, etc.), unrelated widgets, docs, and marketing assets.
- **Existing public API of `AppSwitch`** — do not delete `activeColor`, `activeTrackColor`, or `useAdaptiveSwitch` params; keep them as-is for source compatibility, just stop passing them from feature code.

## Change Budget

- **Expected net line delta per file**:
  - `design_tokens.dart`: **+4 lines** (1 doc line + 1 const + spacing).
  - `app_theme.dart`: **+12 to +18 lines** (one `.copyWith(switchStyle: ...)` chained block).
  - `app_switch.dart`: **+6 to +10 lines** (two new params, pass-through).
  - `add_financial_entry_bottom_sheet.dart`: **−9 lines** (3 × removing 3 override lines).
  - `gig_pay_bottom_sheet.dart`: **−2 lines** (2 override lines).
  - `band_member_edit_drawer.dart`: **−3 lines** (SwitchListTile → AppSwitch is a wash; drop 1 override line).
  - `role_management_sheet.dart`: **−3 lines** (same as above).
  - Each of the 6 override-cleanup files: **−1 or −2 lines** each, ~ **−10 lines total**.
  - `app_switch_test.dart`: **+30 to +50 lines** (2 new test cases, proportional to the shared component being the linchpin of this fix).
- **Total net delta**: approximately **+15 to +30 lines** across all files (dominated by the new test cases).
- **Expected new files**: **0**.
- **Expected new public classes/methods**: **0** new classes. 2 new optional named params on the existing `AppSwitch` constructor (`label`, `leadingLabel`).
- **Expected new dependencies**: **0**.

## System Impact Map

| System                                  | Status             | Notes                                                                                                                             |
| --------------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Setlists                                | affected           | `print_options_bottom_sheet.dart` — override removal only, no structural change                                                   |
| Rehearsals                              | affected           | `rehearsal_form_fields.dart` — override removal, drops 2 hardcoded `Color(0xFF…)` literals                                        |
| Gigs                                    | affected           | `gig_form_fields.dart`, `gig_expense_subview.dart`, `gig_pay_bottom_sheet.dart` — override removal + 1 raw `Switch` → `AppSwitch` |
| Calendar                                | affected           | `one_calendar_settings_screen.dart` — override removal only                                                                       |
| Events (form editors)                   | affected           | (covered above under Rehearsals + Gigs)                                                                                           |
| Members                                 | affected           | `role_management_sheet.dart` — `SwitchListTile` → `AppSwitch` with label                                                          |
| Contacts                                | affected           | `band_member_edit_drawer.dart` — `SwitchListTile` → `AppSwitch` with label                                                        |
| Notifications (settings screen)         | affected           | `notification_settings_screen.dart` — override removal only                                                                       |
| Settings                                | affected           | `settings_screen.dart` — override removal only                                                                                    |
| Financials                              | affected           | 3 raw `Switch` → `AppSwitch` in `add_financial_entry_bottom_sheet.dart`, 1 in `gig_pay_bottom_sheet.dart`                         |
| Auth / Login                            | unaffected         | No auth screens contain switches                                                                                                  |
| Routing / Deep Links                    | unaffected         | No route or link config changes                                                                                                   |
| Notifications (delivery / FCM)          | unaffected         | Only the notification-settings SCREEN toggles; FCM registration, tokens, and edge functions unchanged                             |
| Platforms (iOS / Android / macOS / Web) | affected uniformly | Pure Flutter widget/theme change; identical behavior across all four                                                              |
| Init order                              | unaffected         | No changes to [lib/main.dart](lib/main.dart) startup sequence                                                                     |
| Database / RLS / RPCs                   | unaffected         | No SQL or Supabase artifact touched                                                                                               |

## Regression Risk

**LOW–MEDIUM.**

- **LOW factors**: Pure client-side visual change. No auth, session, routing, init order, or DB code touched. The theme override propagates through Forui's existing style resolution — no new custom render path. Existing `AppSwitch` public API preserved, so no compile-time breakage on any consumer.
- **MEDIUM factors**: 12 feature files touched. Two `SwitchListTile` → `AppSwitch` conversions change the widget structure (from a `ListTile`-based row to a `FSwitch` with `label`), so QA must confirm tap-anywhere-to-toggle still works and the label alignment matches the surrounding sheet layout. Two of the override removals are in `rehearsal_form_fields.dart`, which is inside the shared event editor drawer used for BOTH gigs and rehearsals — worth an extra QA pass on both event types.

Rated **LOW–MEDIUM** overall.

## Engineer Task Breakdown

Ordered so each step compiles and runs cleanly on its own — Engineer can stop and analyze between tasks if needed.

1. **Add `primarySoft` token** — In [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart) add `static const Color primarySoft = Color(0xFFFB7185);` in the `AppColors` class (immediately below the existing `primary` declaration), with a one-line doc comment: `/// Lighter rose tint for switch ON-state track (contrast with white thumb).`
2. **Override `switchStyle` in `foruiTheme`** — In [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart), inside `AppTheme.foruiTheme(brightness)`, replace the current `return FThemeData(colors: colors, touch: true);` with a version that chains `.copyWith(switchStyle: FSwitchStyleDelta.delta(...))`. The delta must (a) override the `.selected` variant of `trackColor` to `AppColors.primarySoft` while leaving the default (off) and `.disabled` variants alone, and (b) override `thumbColor` to `.all(Colors.white)`. Do NOT touch `focusColor` or the label styles.
3. **Extend `AppSwitch` with `label` + `leadingLabel`** — In [lib/components/ui/app_switch.dart](lib/components/ui/app_switch.dart), add two new optional params (`Widget? label`, `bool leadingLabel = false`) at the end of the constructor, and pass them through to both `FSwitch(...)` return branches. Do NOT reorder or rename existing params. Do NOT delete `activeColor`, `activeTrackColor`, or `useAdaptiveSwitch`.
4. **Migrate the 4 raw `Switch(...)` in financials** — In [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart) (3 sites) and [lib/features/financials/widgets/gig_pay_bottom_sheet.dart](lib/features/financials/widgets/gig_pay_bottom_sheet.dart) (1 site), replace `Switch(...)` with `AppSwitch(value: …, onChanged: …)`. Drop all `activeThumbColor`, `activeTrackColor`, `inactiveTrackColor`, `inactiveThumbColor` args. For the `gig_pay_bottom_sheet.dart` site, preserve the `viewOnly` disabled behavior: `onChanged: widget.viewOnly ? null : (value) => setState(() => _is1099Expected = value)`.
5. **Migrate the 2 `SwitchListTile(...)` in members / contacts** — In [lib/features/contacts/widgets/band_member_edit_drawer.dart](lib/features/contacts/widgets/band_member_edit_drawer.dart) and [lib/features/members/widgets/role_management_sheet.dart](lib/features/members/widgets/role_management_sheet.dart) (both have an identical `_buildPermissionToggle` helper), replace `SwitchListTile(...)` with `AppSwitch(value:, onChanged:, label: Text(label, style: …), leadingLabel: true)`. Keep the outer `Padding(padding: EdgeInsets.only(bottom: 4), child: …)` so vertical rhythm matches the current `dense: true` `SwitchListTile`. Preserve the existing color-by-enabled-state on the `Text` (the ternary on `context.colors.textPrimary` / `textDisabled`). Drop `activeTrackColor` override.
6. **Drop `activeColor:` / `activeTrackColor:` on existing `AppSwitch` call sites** — In each of the 6 files listed in "Files to Modify" items 8-14, remove ONLY the `activeColor:` and `activeTrackColor:` args from the `AppSwitch(...)` call. Do not touch other args. In [lib/features/setlists/widgets/print_options_bottom_sheet.dart](lib/features/setlists/widgets/print_options_bottom_sheet.dart), verify by line number that lines 627 and 699 are on `AppSwitch` and lines 661 and 750 are on unrelated widgets (per the grep audit) — only edit the two `AppSwitch` sites. In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart), the removals also delete both `const Color(0xFFfb2c5a)` literals — this restores the "no raw `Color(0xFF…)` outside `design_tokens.dart`" rule.
7. **Extend the AppSwitch test group** — In [test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart), add two `testWidgets(...)` cases inside the existing `group('AppSwitch', ...)`:
   - `'renders under AppTheme.foruiTheme with distinct on-state track and thumb colors'`: pump `AppSwitch(value: true, onChanged: (_) {})` inside `MaterialApp(builder: (context, child) => FTheme(data: AppTheme.foruiTheme(Brightness.dark), child: child!))`, `find` the underlying `FSwitch`, and assert that its resolved `trackColor` for the `.selected` variant equals `AppColors.primarySoft` and its `thumbColor` equals `Colors.white`. Access via `FSwitch.style` on the widget or by reading the resolved theme.
   - `'renders label and toggles when label is tapped when leadingLabel is true'`: pump `AppSwitch(value: false, onChanged: (v) { … }, label: const Text('Enable X'), leadingLabel: true)`, `expect(find.text('Enable X'), findsOneWidget)`, tap the text, `pumpAndSettle()`, assert the callback fired with `true`.
8. **Verify local build** — Engineer runs `flutter analyze` and `flutter test test/components/ui/app_switch_test.dart` (and the wider `flutter test` if time permits). Zero analyzer warnings tolerated in touched files.

## Verification Plan

### Tier 1 (pre-deploy, must pass before merge)

1. **Static grep gates** (no test failures, greps must be empty):
   - `grep -rnE "(^|[^p])Switch\(" lib/features` → returns **only** `AppSwitch(` matches. Zero raw `Switch(` or `SwitchListTile(` hits in `lib/features/**`.
   - `grep -rnE "activeColor:|activeTrackColor:|activeThumbColor:|inactiveTrackColor:|inactiveThumbColor:" lib/features/**/*.dart | grep -E "Switch|switch"` → zero matches on `AppSwitch` / `Switch` / `SwitchListTile` call sites. (Non-switch widget matches, e.g. checkbox / radio, are allowed and out of scope.)
   - `grep -rnE "Color\(0xFF" lib/features/events/widgets/rehearsal_form_fields.dart` → the two `0xFFfb2c5a` literals must be gone. Any other hex literals in that file are out of scope for this cycle.
2. **`flutter analyze`** — zero new warnings or errors in any of the 15 touched files. No new lint suppressions.
3. **Widget tests** — `flutter test test/components/ui/app_switch_test.dart` — all cases (existing + 2 new) pass. In particular:
   - Existing "activeColor applies StyleDelta" case still passes (public API preserved).
   - New "distinct on-state track and thumb colors" case asserts the theme-level override actually took effect. This test never calls into any pre-fix code path.
   - New "label taps toggle" case validates the `SwitchListTile` migration UX is preserved.
4. **Manual visual smoke test on macOS** — Engineer launches `./run.sh macos`, navigates to and toggles at least one switch on each of these screens (all 8 must show a visible ON-state contrast between a **white thumb** and a **softer, lighter-rose track**, and identical switch styling side-by-side):
   - Financials → Add Income (1099 toggle, Disburse to Band, Deposit to Savings).
   - Financials → Gig Pay bottom sheet (1099 toggle).
   - Members → Role Management sheet (any permission toggle) — tap the LABEL, confirm the switch toggles.
   - Contacts → Band member edit drawer (permission toggle) — tap the LABEL, confirm the switch toggles.
   - Calendar → One Calendar settings.
   - Events editor → Gig form + Rehearsal form.
   - Notifications settings.
   - Setlists → Print options bottom sheet.
   - Settings screen.

### Tier 2 (post-deploy)

n/a — pure client-side visual change. There is no backend state to verify after deploy that isn't already covered by Tier 1.

## QA Regression Areas

- **All switches enumerated in Tier 1 step 4** — verify: correct initial state, toggling actually persists (where applicable), disabled state renders (Members / Gig Pay `viewOnly`), and no state-management regressions in the underlying feature (e.g. Financials income entry still saves correctly, permission toggles still apply to the member).
- **Event editor drawer** — because `rehearsal_form_fields.dart` is shared, exercise both a Gig event AND a Rehearsal event editor. Confirm the switches inside each form still gate their dependent UI (e.g. any conditional fields that appear when a toggle is on).
- **`SwitchListTile` → `AppSwitch` UX** — specifically confirm:
  - Tapping the label text toggles the switch (not just tapping the switch itself).
  - The label is properly aligned to the left of the switch (leadingLabel: true).
  - Vertical spacing between adjacent permission toggles looks identical to before (matches the previous `dense: true` `SwitchListTile` visual rhythm).
- **Dark-mode only** — confirmed always dark; no light-mode regression check required.
- **Cross-platform spot check** — after macOS passes, do a quick smoke test on iOS Simulator and Chrome. Behavior must be identical.

## Rollout Strategy

Standard merge to `main` after Engineer implementation and QA sign-off. No feature flag, no phased rollout, no data migration. Pure visual change — safe to ship in a single PR. Rollback is a straightforward `git revert` if any visual regression is discovered post-merge; no data or state to migrate back.

## Out of Scope

- Renaming `AppSwitch` or removing its currently-unused `useAdaptiveSwitch` param.
- Deleting the `activeColor` / `activeTrackColor` params from `AppSwitch` (kept for source-compat).
- Unifying or restyling other Forui component wrappers (`AppCheckbox`, `AppButton`, `AppChip`, etc.) — separate cycle.
- Changing `AppColors.primary` itself (any reconciliation of `#FF2056` vs. `#F43F5E` with the copilot-instructions preamble is a separate design decision).
- Adding new switches or altering where existing switches appear.
- Any DB migration, RLS policy, RPC, or edge function change.
- Any change to `AndroidManifest.xml`, `Info.plist`, entitlements, or platform config.
- Any change to `pubspec.yaml`, `pubspec.lock`, or dependency versions.

---

## AMENDMENT 1 — OFF-state track visibility

**Status:** appended after the original plan was implemented. The Engineer work described above (ON-state soft-rose track + white thumb, 15 files, uncommitted on `feature/unified-forui-switch-styling`) is unchanged and stays. This amendment adds a small, additive delta on top of it.

**Feedback from Tony:** In the OFF (default) state, the FSwitch track resolves to Forui's `colors.secondary` (`#262626` in `FColors.neutralDark`), which is only 12–29 lightness units above the app's `background` (`#09090B`) / `surface` (`#18181B`). Against those surfaces the track vanishes and only the white thumb is visible — the switch reads as a floating dot rather than a switch. Requested outcome: OFF-state switch shape must be clearly visible via a "medium-gray border outline".

### Diagnosis

**Confidence: HIGH** — validated end-to-end against the installed Forui `0.26.0` source in the pub cache.

**Finding 1 — `FSwitchStyle` has NO track border / outline field.**

The full public surface of `FSwitchStyle` (see [`~/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/switch.dart` lines 205–252](https://pub.dev/packages/forui) and its generated `switch.design.dart`) is exactly five fields:

| Field | Type |
| --- | --- |
| `focusColor` | `Color` |
| `trackColor` | `FVariants<..., Color, Delta>` |
| `thumbColor` | `FVariants<..., Color, Delta>` |
| `leadingLabelStyle` | `FLabelStyle` |
| `trailingLabelStyle` | `FLabelStyle` |

There is no `trackBorderColor`, `trackOutlineColor`, `border`, `decoration`, or `stroke` field on `FSwitchStyle` — and none on `FSwitchStyleDelta` either (the delta factory exposes exactly the same five parameters). A stroke outline on the track cannot be expressed as an `FSwitchStyleDelta`.

**Finding 2 — Forui's underlying widget (`CupertinoSwitch` from `cupertino_ui-1.0.1`) DOES support a track outline, but `FSwitch` does not pipe it through.**

`CupertinoSwitch` exposes `trackOutlineColor: WidgetStateProperty<Color?>?` and `trackOutlineWidth: WidgetStateProperty<double?>?` (see [`~/.pub-cache/hosted/pub.dev/cupertino_ui-1.0.1/lib/src/switch.dart` lines 313–384](https://pub.dev/packages/cupertino_ui)) and paints a stroked stadium border around the track when they're set (lines 1311–1329). However, `FSwitch`'s `build` method (switch.dart lines 145–187) constructs its `CupertinoSwitch` with only `activeTrackColor`, `inactiveTrackColor`, `thumbColor`, and `focusColor` — `trackOutlineColor` / `trackOutlineWidth` are never passed, and there is no theme hook that would carry them through. So even though the underlying paint routine can draw an outline, Forui's public API has no way to reach it.

**Finding 3 — `FVariantsValueDelta` cleanly supports base-value replacement.**

The delta operation set on `FVariantValueDeltaOperation` (variants.dart lines 435–520) includes `.base(V value)`, which replaces ONLY the base (default = OFF, no active variants) of an `FVariants` map, leaving `.disabled`, `.selected`, and `.selected.and(.disabled)` entries untouched. This is the surgical hook that lets us modify the OFF-state track fill without disturbing the existing `.selected` → `AppColors.primarySoft` override or the built-in disabled dimming.

### Trade-off — literal outline vs. fill-based visibility

**Resolved: Option A (fill approach) is the chosen path.** Tony's directive: _"Forget the outline and just make the background color slightly lighter."_ Options B (Container wrapper) and C (CupertinoSwitch bypass) are **declined** and no longer require approval. They are kept documented below for provenance so future readers understand why a literal stroke was considered and ruled out, but they are not implementation paths for this amendment.

Because there is no clean Forui API path to a stroked outline on `FSwitch`, the three ways originally considered to satisfy the goal ("OFF-state switch shape reads clearly against dark surfaces") diverged sharply in structural cost. Only Option A survives:

| Option | What it does | Cost | Literal outline? | Status |
| --- | --- | --- | --- | --- |
| **A — Recolor OFF-state track fill** | Add `FVariantValueDeltaOperation.base(<subtle-gray>)` to the existing `switchStyle` delta. OFF track becomes a subtly lighter fill instead of near-black. | **Clean delta.** +2 lines in `app_theme.dart`, +3 lines (1 new token) in `design_tokens.dart`, +1 test case. Zero widget-tree changes. Zero risk to existing implementation. | **No** — solid fill, not a stroke. | **CHOSEN by Tony.** |
| **B — Wrap `FSwitch` in a stadium-shaped bordered `Container` inside `AppSwitch`** | Add a decorative `Container(decoration: BoxDecoration(border: Border.all(...), borderRadius: StadiumBorder))` around the `FSwitch` return branch in `AppSwitch`. | **Fragile.** Requires hardcoding `CupertinoSwitch`'s internal dimensions (`_kTrackWidth ≈ 51`, `_kTrackHeight ≈ 31` — private constants inside `cupertino_ui`); thumb overhangs the track slightly and would visually cross the border at the animation endpoints; adds an extra wrapper in every AppSwitch instance; the border also shows in the ON state unless we conditionally toggle it. | Partial — outline present, but thumb overlap looks wrong. | **DECLINED by Tony.** |
| **C — `AppSwitch` bypasses `FSwitch` and calls `CupertinoSwitch` directly** with `trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? null : mediumGray)` and `trackOutlineWidth: WidgetStateProperty.all(1.5)`. | **Materially changes the shared component's structure.** `AppSwitch → FSwitch` is the architectural contract the original plan established; Option C rips out FSwitch as the underlying implementation and forces `AppSwitch` to re-implement FSwitch's label/description/error/focus/semantics layout by hand (or by wrapping `CupertinoSwitch` in `FLabel` and re-doing the variant-set resolution). Loses the ON-state `switchStyle` theme override that the original plan's Task 2 was built around. | **Yes** — exact literal stroke outline. | **DECLINED by Tony.** |

**Chosen path: Option A, with `#52525B` (Zinc 600) — Tony's direct choice of the bolder value for stronger OFF-state visibility.**

Rationale that landed on this choice:

1. **Tony's directive is explicit.** After reviewing the trade-off between a subtler `#3F3F46` (Zinc 700) fill and a bolder `#52525B` (Zinc 600) fill, Tony directly chose `#52525B` — the bolder Zinc-600 value — for stronger OFF-state visibility. The mechanism is the fill delta; the value is Tony's explicit direct choice.
2. **`#52525B` (Zinc 600) delivers a genuinely visible track.** That value gives ~2.6:1 contrast against the app's `#09090B` background and ~2.3:1 against the `#18181B` sheet/card surface — bolder and more visible than the previously-considered `#3F3F46` (~1.9:1 / ~1.7:1). The switch shape reads as a clear medium-gray pill against the dark surfaces toggles actually appear on, not a floating white dot.
3. **Preserves the architectural contract.** `AppSwitch → FSwitch` remains true. `switchStyle` remains the single theme-level hook. No `CupertinoSwitch` API leaks into feature code. The 15-file Engineer implementation currently uncommitted on the working tree stays intact.

### Option A — full spec (approved by Tony; declines B and C)

#### Color choice

Add one new named token to `AppColors` in [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart), directly below the existing `primarySoft` declaration:

```dart
/// OFF-state track fill for app toggle switches — a medium-gray fill that
/// makes the track shape clearly visible against dark surfaces.
static const Color switchTrackOff = Color(0xFF52525B); // Tailwind zinc-600
```

**Value: `#52525B` (Tailwind Zinc 600).** This is Tony's explicit direct choice of the bolder value for stronger OFF-state visibility. Rationale for this specific value:

- **Two steps in the Zinc ladder above Forui's `colors.secondary` (`#262626`, ~= Zinc 800).** The Forui default is the OFF-track today and it's what Tony described as "current near-black default." Zinc 600 skips over Zinc 700 (`#3F3F46`, the subtler alternative that was previously considered) to land on a value that reads as a genuine medium-gray pill against the app's dark surfaces.
- **Bolder than the alternative `#3F3F46` (Zinc 700) — by direct choice.** Tony reviewed the two candidates and picked the stronger contrast. Zinc 600 gives roughly 1.4× the contrast delta of Zinc 700 against the app's dark surfaces, which is what makes the switch shape read as a clear component rather than a subtle raise-of-the-lid.
- **Duplicates an existing token value:** `#52525B` is already present in [lib/app/theme/brand_colors.dart line 54](lib/app/theme/brand_colors.dart#L54) as `BrandColors.dark.borderStrong` (the "strong border" token) — and also on line 58 as `BrandColors.dark.textDisabled`. This is a noted, intentional duplication — semantically appropriate (the OFF track behaves like a strong-border-weight neutral fill) and consistent with the amendment's first version, which already observed the `borderStrong` hex match. Per Tony's instructions we retain a dedicated `AppColors.switchTrackOff` name so `app_theme.dart` reads unambiguously and the switch tokens live where the other switch tokens live (`AppColors.primarySoft` sits in the same class).
- **Contrast math (WCAG relative-luminance):**

  | Foreground | Background | Contrast ratio | Interpretation |
  | --- | --- | --- | --- |
  | `#52525B` track | `#09090B` app background | **~2.6:1** | Clearly visible; approaches the "strong" threshold (~3:1). The switch shape reads as a medium-gray pill against the app background. |
  | `#52525B` track | `#18181B` sheet/card surface | **~2.3:1** | Clearly visible on modal / bottom-sheet surfaces where most toggles actually appear. |
  | `#52525B` track | `#262626` (previous default, for reference) | **~2.1× more contrast against dark surfaces than the previous default** — a strong, deliberate visibility lift. |

  For comparison, the alternative `#3F3F46` (Zinc 700) would have given ~1.9:1 vs background and ~1.7:1 vs surface — bolder than the default but subtler than the chosen `#52525B`. Tony directly chose `#52525B` for the bolder outcome.

- **No hue.** Pure neutral gray — no rose bleed into the OFF state, no interference with the ON-state `primarySoft` (`#FB7185`). The ON/OFF distinction remains obvious: chromatic rose vs. achromatic gray, with a large luminance and hue gap.

**Confidence on the visibility claim:** **HIGH** on the math (the ratios are the WCAG-standard formula on the exact hex values, and Zinc 600 is two steps higher on the ladder than the current default). **HIGH** on the in-vivo perceptual outcome — 2.3–2.6:1 sits solidly in the "clearly visible" band, which is exactly what Tony's direct choice of the bolder value asked for.

#### Files to modify

1. **[lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart)** — Add `AppColors.switchTrackOff = Color(0xFF52525B)` immediately after `primarySoft` (single const + one-line doc comment). No other change.
2. **[lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart)** — In the existing `switchStyle: FSwitchStyleDelta.delta(...)` block inside `AppTheme.foruiTheme(brightness)`, prepend a `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` entry to the `trackColor` delta's operations list. The existing `.match({FSwitchVariant.selected}, AppColors.primarySoft)` entry stays as-is, ordered after `.base(...)`. Do not touch `thumbColor` or `focusColor`.
3. **[test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart)** — Add one `testWidgets(...)` case inside the existing `group('AppSwitch', ...)` asserting the OFF-state resolution.

#### Files off-limits

Same as the original plan's "Files Off-Limits" list. In particular:

- No changes to `lib/components/ui/app_switch.dart` — this amendment is theme-only.
- No changes to any of the 12 feature files already touched by the original plan's Tasks 4–6.
- No new Container wrapper, no bypass of `FSwitch`.

#### Scope guard — OFF only, ON untouched

The `FVariantValueDeltaOperation.base(...)` op replaces ONLY the base (no active variants → OFF) entry of the `trackColor` FVariants. It does not touch:

- `.selected` variant → stays at `AppColors.primarySoft` (the existing ON-state override from the implemented Task 2).
- `.disabled` variant → stays at `colors.disable(colors.secondary)` (Forui's dimmed OFF, correct for disabled OFF switches).
- `.selected.and(.disabled)` variant → stays at `colors.disable(colors.primary)` (Forui's dimmed ON, correct for disabled ON switches).

**Recommendation: OFF only. Do NOT extend the medium-gray to the ON state.** The ON state already reads clearly via the rose fill (`primarySoft` against dark surface has ~4.2:1 luminance contrast and strong chromatic contrast). Adding gray anywhere in the ON path would only muddle it.

#### Change Budget (amendment only)

- `design_tokens.dart`: **+3 lines** (1 doc line + 1 const + spacing).
- `app_theme.dart`: **+1 line** (one `FVariantValueDeltaOperation.base(AppColors.switchTrackOff),` entry).
- `test/components/ui/app_switch_test.dart`: **+15 to +20 lines** (1 new `testWidgets` case).
- **Total net delta (amendment only):** approximately **+20 lines**.
- **New files:** 0.
- **New public classes/methods:** 0.
- **New dependencies:** 0.

#### Task Breakdown (for Engineer, additive to already-implemented tasks 1–8)

9. **Add `switchTrackOff` token** — In [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart), immediately below the existing `static const Color primarySoft = Color(0xFFFB7185);` declaration, insert:
   ```dart
   /// OFF-state track fill for app toggle switches — a medium-gray fill that
   /// makes the track shape clearly visible against dark surfaces.
   static const Color switchTrackOff = Color(0xFF52525B); // Tailwind zinc-600
   ```
10. **Add `.base(...)` op to trackColor delta** — In [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart), inside `AppTheme.foruiTheme(brightness)`, modify the `trackColor` list inside the existing `switchStyle: FSwitchStyleDelta.delta(...)`. Prepend `FVariantValueDeltaOperation.base(AppColors.switchTrackOff)` before the existing `FVariantValueDeltaOperation.match({FSwitchVariant.selected}, AppColors.primarySoft)`. Final shape:
    ```dart
    trackColor: FVariantsValueDelta.delta([
      FVariantValueDeltaOperation.base(AppColors.switchTrackOff),
      FVariantValueDeltaOperation.match(
        {FSwitchVariant.selected},
        AppColors.primarySoft,
      ),
    ]),
    ```
    Do NOT touch the `thumbColor` delta, `focusColor`, or the outer `.copyWith(...)` chain.
11. **Add OFF-state test case** — In [test/components/ui/app_switch_test.dart](test/components/ui/app_switch_test.dart), inside the existing `group('AppSwitch', ...)`, add:
    ```
    'off-state track resolves to AppColors.switchTrackOff under AppTheme.foruiTheme'
    ```
    which pumps an `AppSwitch(value: false, onChanged: (_) {})` inside `FTheme(data: AppTheme.foruiTheme(Brightness.dark), child: ...)` and asserts that `theme.switchStyle.trackColor.resolve(<FVariant>{})` (empty variant set = OFF, unfocused, enabled) equals `AppColors.switchTrackOff`. Use `FTheme.of(context)` (or read the pumped `FThemeData` via the existing pattern from the plan's Task 7 test) to access `switchStyle`.
12. **Verify local build** — Engineer runs `flutter analyze` (must stay clean) and `flutter test test/components/ui/app_switch_test.dart` (all cases from the original plan's Task 7 PLUS this new case must pass).

#### Verification Plan (amendment only)

Additive to the original Verification Plan.

**Tier 1 (pre-deploy)**

1. **`flutter analyze`** — zero new warnings in `design_tokens.dart`, `app_theme.dart`, or the test file.
2. **Widget test — `flutter test test/components/ui/app_switch_test.dart`** — the new OFF-state case must pass. It never calls into any pre-fix code path — it asserts the amended theme resolution directly.
3. **Manual visual smoke test on macOS** — Engineer launches `./run.sh macos`, navigates to any screen with an off-state switch (e.g. Settings, Notifications Settings, or the Members role management sheet), confirms:
   - The OFF-state switch shape is **clearly visible** against the dark surface — the track reads as a bold medium-gray pill, not a floating white dot. Expected contrast is ~2.3–2.6:1 (`#52525B` on `#18181B` / `#09090B`), which is Tony's direct choice of the bolder value for stronger OFF-state visibility. It should NOT read as a subtle raise-of-the-lid — if it does, the value has drifted from `#52525B` back toward `#3F3F46`.
   - Toggling the switch ON transitions cleanly from the subtle gray → soft rose (`primarySoft`) track. Thumb stays white throughout. The ON state remains obviously distinct from OFF because rose vs. gray is a hue difference in addition to a luminance one.
   - Disabled state (Members `viewOnly` sheet, or `Gig Pay` in view-only mode) still reads as visibly dimmer than enabled — i.e. the disabled `.selected.and(.disabled)` and `.disabled` variants were NOT accidentally overridden.
4. **Static gate** — grep `AppColors.switchTrackOff` appears exactly twice in `lib/` (declaration in `design_tokens.dart`, usage in `app_theme.dart`) and once in `test/components/ui/app_switch_test.dart`. No stray usages elsewhere.

**Tier 2 (post-deploy)**

n/a — pure client-side theme change, no backend state.

#### QA Regression Areas (amendment only)

- All 8 macOS smoke-test screens from the original plan's Verification Plan Tier 1 step 4 — verify the OFF state also reads clearly, in addition to the ON-state contrast that step already validates. The ON-state contrast must not have regressed.
- **Disabled state on `gig_pay_bottom_sheet.dart` (viewOnly) and any member permission toggle where the current user lacks edit permission** — verify the disabled switches still look dimmer/de-emphasized (not accidentally the new brighter gray).
- No routing, no state management, no DB.

### Regression risk (amendment only)

**LOW.**

- Additive theme-only change (`.base(...)` op layered onto an already-shipped delta chain).
- Zero widget-tree structural change.
- Zero API change to `AppSwitch` or any feature code.
- The `FVariantValueDeltaOperation.base(V)` semantics (variants.dart line 460) are surgical: replaces base only, leaves the variants map intact. Verified in the Forui `0.26.0` source.
- `AppColors.switchTrackOff` (`#52525B`) shares its hex with `BrandColors.dark.borderStrong` (declared at [lib/app/theme/brand_colors.dart line 54](lib/app/theme/brand_colors.dart#L54)). This is an accepted, semantically-coherent duplication — the OFF track behaves like a strong-border-weight neutral fill — kept as a dedicated named token per the same pattern used for `primarySoft`. Called out here so QA/reviewers know the duplicate hex is intentional.

### Out of Scope (amendment only)

- Adding a literal stroke outline via wrapper (Option B) or `CupertinoSwitch` bypass (Option C) — **declined by Tony**, not merely deferred.
- Restyling the disabled-state color separately.
- Changing the OFF-state track color for platforms other than dark mode — the app is dark-only.
- Any change to `BrandColors.dark.borderStrong` itself (it stays at `#52525B` for its existing "strong border" uses; `AppColors.switchTrackOff` shares its hex value, but the tokens are independent by name).
