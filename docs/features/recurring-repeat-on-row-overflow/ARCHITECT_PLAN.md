# ARCHITECT_PLAN — recurring-repeat-on-row-overflow

## Feature Slug
`recurring-repeat-on-row-overflow`

## Feature Title
RenderFlex overflow in "Repeat on" row when enabling recurring rehearsal

## Problem Summary
In the Add Event flow, choosing **Rehearsal** and toggling **Make this recurring** ON causes Flutter to emit `A RenderFlex overflowed by 4.0 pixels on the right.` The overflowing widget is the "Repeat on" day-of-week selector Row at [lib/features/events/widgets/rehearsal_form_fields.dart:625](lib/features/events/widgets/rehearsal_form_fields.dart#L625). Observed on Android; the fix must also be robust on iOS across all supported screen widths.

## Root Cause (confidence: HIGH — confirmed from code + arithmetic)
The Row at [lib/features/events/widgets/rehearsal_form_fields.dart:625](lib/features/events/widgets/rehearsal_form_fields.dart#L625) maps every value of the `Weekday` enum ([lib/features/events/models/event_form_data.dart:146-152](lib/features/events/models/event_form_data.dart#L146-L152) — 7 values: sunday…saturday) into a chip whose `AnimatedContainer` has a hard-coded `width: 40, height: 40` and `BoxDecoration(shape: BoxShape.circle)`.

Natural children width = 7 × 40 px = **280 px**.

Per the error's constraints, the Row's available width on the reproducing device is **0 ≤ w ≤ 276 px**. The overflow is exactly **280 − 276 = 4.0 px**, matching the reported figure to the pixel.

`mainAxisAlignment: MainAxisAlignment.spaceBetween` only distributes the *remaining* space between children after they are laid out at their natural sizes; when the children's combined natural width already exceeds the available width, `spaceBetween` cannot shrink them and the Row overflows. The default `mainAxisSize: MainAxisSize.max` makes the Row take the full 276 px of the parent, but the children still demand 280 px, so the flex constraint fails.

This is device-width sensitive: any parent width < 280 px will overflow. The reproducing device sits just 4 px short. Narrower Android/iOS devices, split-screen layouts, or added parent padding would overflow by more.

## Existing System Analysis
- `RehearsalFormFields` ([lib/features/events/widgets/rehearsal_form_fields.dart:133-163](lib/features/events/widgets/rehearsal_form_fields.dart#L133-L163)) is a `ConsumerWidget` that lays out its content in a single `Column` with no horizontal padding of its own. Its actual width is inherited from wherever it is hosted (the event editor bottom sheet / drawer).
- `_buildRecurringToggle` ([lib/features/events/widgets/rehearsal_form_fields.dart:582-602](lib/features/events/widgets/rehearsal_form_fields.dart#L582-L602)) wraps itself in `Padding(horizontal: Spacing.space12)`, but `_buildRecurringSection` ([lib/features/events/widgets/rehearsal_form_fields.dart:607-660](lib/features/events/widgets/rehearsal_form_fields.dart#L607-L660)) does not, so the "Repeat on" chip Row is flush to whatever width the parent gives it.
- The sibling **Frequency** Row two blocks below ([lib/features/events/widgets/rehearsal_form_fields.dart:672-711](lib/features/events/widgets/rehearsal_form_fields.dart#L672-L711)) already uses `Expanded` around each mapped item, which is why it does **not** overflow. That is the precedent to follow for a consistent, width-robust layout inside the same section.
- No provider, controller, repository, RPC, or router touches this Row. It reads `selectedDays`, calls `onDayToggled`, and triggers `HapticFeedback.selectionClick()`. Fixing the layout does not change any of that.

## Proposed Solution
Match the working pattern already used by the Frequency row directly below: give each day chip an equal 1/7 flex slot with `Expanded`, and centre the 40 × 40 chip inside that slot with `Center` so the chip keeps its fixed size on wide screens and gracefully compresses to fit on narrow screens.

**Concretely**, the current Row:
- has `mainAxisAlignment: MainAxisAlignment.spaceBetween` — becomes a no-op once children fill the row, so it is removed for clarity.
- returns each `GestureDetector` directly — is wrapped in `Expanded(child: Center(child: <GestureDetector>))`.

The tap handler, `AnimatedContainer` dimensions (`width: 40, height: 40`), decoration (`BoxShape.circle`), border, colour logic, and text style are all preserved verbatim.

### Width-robustness across devices (Android + iOS, small + large)
Let `W` = available Row width, `S` = W / 7 = per-chip slot width.

| Scenario | W | S | Chip render | Notes |
|---|---|---|---|---|
| Reproducing device | 276 | 39.43 | 39.43 × 40 | `Center` passes *loose* constraints to child, so the 40-wide container is clamped to 39.43 by the slot; height is unbounded and stays 40. Result: a 1.4 % horizontal squish — visually indistinguishable from a circle. No overflow. |
| iPhone SE (smallest common iOS, ~320 pt sheet content) | ~296 | 42.3 | 40 × 40 | Chip fits its slot exactly; centred with ~1.1 px slack per side. Perfect circle. |
| iPhone 15 Pro Max (~410 pt sheet content) | ~386 | 55.1 | 40 × 40 | Chip 40 × 40 centred in 55 px slot; ~7.5 px inset from each edge. Same visual weight as the Frequency row below it. |
| Split-screen / very narrow Android | e.g. 240 | 34.3 | 34.3 × 40 | Still no overflow. Chip becomes a slightly compressed circle (~14 %); still legible. This is a graceful degradation, not a failure mode. |

Key property: because `Center` gives the child *loose* horizontal constraints, the container reads its own `width: 40` and clamps against the parent max — it can never overflow.

### Alternatives rejected
- **Shrink the chip to `width: 36`** — a hard-coded tweak that only fixes today's reproducing device; still fragile at even narrower widths and looks cramped on wide screens. Rejected.
- **Wrap the whole Row in `FittedBox(fit: BoxFit.scaleDown)`** — `FittedBox` gives its child unbounded constraints, which forces the Row to `mainAxisSize.min`; `spaceBetween` becomes meaningless and the chip spacing model has to be rebuilt. Not minimal. Rejected.
- **Switch to `Wrap`** — day chips would break onto a second row on narrow screens, which is worse UX than a barely-visible size adjustment. Rejected.
- **Add `AspectRatio(1.0)` to preserve perfect circularity at narrow widths** — the residual ~1.4 % squish at 276 px is imperceptible; adding another widget just to eliminate it is not justified. Rejected.

## Database Impact
Not applicable — pure client-side Flutter layout change. No migration, no RLS policy, no RPC, no trigger, no schema touched.

## Flutter Architecture Changes
None. No new provider, controller, repository, model, or widget class. Only the internal structure of a Row inside one existing widget's build method changes.

## Files to Create
None.

## Files to Modify
- **[lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)** — inside `_buildRecurringSection`, modify the Row at line 625:
  - Remove `mainAxisAlignment: MainAxisAlignment.spaceBetween,`.
  - Wrap the returned `GestureDetector` in `Expanded(child: Center(child: <GestureDetector>))`.
  - Do **not** alter the chip's dimensions, decoration, tap handler, haptic call, or text.

## Files Off-Limits
- **[lib/features/events/models/event_form_data.dart](lib/features/events/models/event_form_data.dart)** — the `Weekday` enum and its `shortLabel` strings are correct; changing labels would be a data model change, not a layout fix.
- **[lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart)** — outside the single Row at line 625: the Location autocomplete section, the potential-rehearsal toggle, the recurring toggle Row, the Frequency Row (already correct), and the Until-date input are all **off-limits**. This is a one-Row fix.
- All other event editor files (`add_edit_event_bottom_sheet.dart`, `event_editor_drawer.dart`, `event_editor_helpers.dart`, `event_editor_actions.dart`, `gig_form_fields.dart`, `event_form_fields.dart`, `event_type_selector.dart`, `button_group_grid.dart`) — unrelated.
- Any repository, provider, controller, migration, edge function, or platform config.

## Change Budget
- Expected net line delta in `lib/features/events/widgets/rehearsal_form_fields.dart`: **+3 to +5** lines (remove one line for `mainAxisAlignment`, add `Expanded(child: Center(child:` opener plus matching closers, preserving indentation).
- Expected new files: **0**.
- Expected new public classes/methods: **0**.
- Expected new dependencies: **0**.

If the actual diff is materially larger than this, the Engineer has expanded scope beyond what is needed.

## System Impact Map
| Area | Status |
|---|---|
| Gigs | unaffected |
| Rehearsals | affected — layout only, in Add/Edit Rehearsal recurring section |
| Setlists | unaffected |
| Members | unaffected |
| Auth | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platforms (Android / iOS / macOS / web) | all affected identically — Flutter framework layout, no platform-conditional code |
| Init order / config / DB / RLS / RPC | unaffected |

## Regression Risk: LOW
- Localized to the internal structure of a single Row inside one build method.
- No state, side effect, callback signature, or public API changes.
- No provider, repository, or auth flow touched.
- No platform-conditional code — behaviour is identical on Android, iOS, macOS, and web.
- Layout math verified across the full plausible width range (240 px → 500+ px).
- The chosen pattern already exists and works in the Frequency Row immediately below the changed Row, so this brings the two rows into consistency rather than introducing a novel pattern.

## Engineer Task Breakdown
1. In [lib/features/events/widgets/rehearsal_form_fields.dart](lib/features/events/widgets/rehearsal_form_fields.dart), locate the Row inside `_buildRecurringSection` at line ~625 (the one whose `children` are `Weekday.values.map((day) { … })`).
2. Delete the line `mainAxisAlignment: MainAxisAlignment.spaceBetween,` from that Row.
3. In that Row's mapped builder, wrap the returned `GestureDetector(...)` in `Expanded(child: Center(child: <GestureDetector>))` — matching the surrounding indentation and closing brackets.
4. Do not modify any other line in this file. Do not modify chip dimensions, decoration, colour logic, tap handler, haptic call, or text style.
5. Run `flutter analyze` and confirm zero new warnings or errors introduced by the change.

## Verification Plan

### Tier 1 — pre-deploy (client-side only)
1. `flutter analyze` — no new warnings or errors.
2. Reproduce the original bug on Android (Pixel 4a or similar, or an emulator sized to reproduce the 276 px available width, e.g. Small Phone profile). Steps: launch app → Add Event → Rehearsal → toggle **Make this recurring** ON. **Expected**: the "Repeat on" row renders 7 day chips with no `A RenderFlex overflowed by …` message in the debug console.
3. Repeat step 2 on **iOS Simulator — iPhone SE (3rd gen)** (smallest common iOS width). **Expected**: no overflow; chips remain 40 × 40 perfect circles; row is visually consistent with the Frequency row below.
4. Repeat step 2 on **iOS Simulator — iPhone 15 Pro Max** (largest common iOS width). **Expected**: no overflow; chips 40 × 40 centred in their equal slots; slight inset from row edges (comparable to how the Frequency row already renders) is acceptable and expected.
5. Repeat step 2 on **macOS** (window resized narrow, ≤ 400 px content area) and **Chrome** (dev-tools width set to 320 px). **Expected**: no overflow; on very narrow widths chips may compress by ≤ 15 % but remain legible circular targets.
6. Tap each of the 7 day chips in turn on at least one platform to confirm selection state, colour swap (rose accent → white text), and haptic feedback still fire — the change is layout-only and must not disturb interaction.

No new automated widget test is required for a 3-to-5-line minimal layout fix that has no logic change; adding one would exceed the change budget. If Engineer sees existing tests for this widget, they are welcome to leave them alone and rely on manual verification above.

### Tier 2 — post-deploy
Not applicable. There is no server-side change, no RPC, no migration, no edge function, and no shared infrastructure touched. Nothing to verify against production.

## QA Regression Areas
- **Add Event → Rehearsal → recurring ON**: no console overflow error; "Repeat on" row lays out cleanly on smallest and largest available devices.
- **Add Event → Rehearsal → recurring ON → tap each day chip**: selection state toggles correctly; visual state (rose fill, white text) unchanged; haptic still fires.
- **Add Event → Rehearsal → recurring ON → Frequency row**: unchanged, still lays out weekly/bi-weekly/monthly correctly.
- **Add Event → Rehearsal → recurring ON → Until (optional) input**: unchanged.
- **Add Event → Rehearsal → recurring toggle OFF then ON again**: the `AnimatedSize` + `SlideTransition` + `FadeTransition` reveal still animates cleanly (no overflow during animation frames when the parent width is transiently narrower).
- **Edit existing recurring rehearsal**: recurring section renders pre-populated day selections without overflow.
- **Add Event → Gig flow**: unaffected — different widget file.
- **Add Event → Potential Rehearsal ON**: recurring section is hidden ([rehearsal_form_fields.dart:138](lib/features/events/widgets/rehearsal_form_fields.dart#L138)), so unaffected.

## Rollout Strategy
Standard PR against `main`. No feature flag, no coordinated deploy, no migration. Ship with the next mobile release train; web can go out immediately via the normal Vercel deploy.

## Out of Scope
- Any change to the Frequency Row, Until-date input, potential-rehearsal toggle, location autocomplete, or member availability section.
- Any change to `Weekday` enum labels or the recurring data model.
- Any restyling of day chips (size, colour, border, typography).
- Any refactor of `RehearsalFormFields` into smaller components.
- Adding widget/golden tests for this file — outside the change budget for a 3-to-5-line fix.
- Fixing overflow bugs in any other Row anywhere else in the app.
