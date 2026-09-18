# ARCHITECT_PLAN.md

## Feature Slug

setlist-pause-label-overflow

## Feature Title

RenderFlex overflow when adding a Pause to a setlist

## Problem Summary

Opening the "Add Pause" screen (`PauseScreen`, reached via the Add-to-Setlist
overlay's Pause category) throws a `RenderFlex overflowed by 2.0 pixels on the
bottom` exception the moment the screen builds, because it always renders at
least one custom-purpose input row.

## Root Cause (Confidence: HIGH — confirmed in code)

`lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`'s custom
purpose field row wraps `AppTextField` in a `Container` with a **fixed
`height: 44`** and a **1px border on all sides**
(`Border.all(color: context.colors.border)`, no explicit width → defaults to
1.0):

```dart
Container(
  height: 44,
  decoration: BoxDecoration(
    color: context.colors.surface,
    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    border: Border.all(color: context.colors.border),
  ),
  child: AppTextField(
    controller: _customFields[i].$1,
    focusNode: _customFields[i].$2,
    hintText: 'Custom purpose...',
    textInputAction: TextInputAction.done,
    onSubmitted: ...,
  ),
),
```

`Container` derives its effective child padding from `BoxDecoration.padding`,
which for a `Border` equals `border.dimensions` — `EdgeInsets.all(1)` here.
Flutter's `Container.build()` adds that as real padding around the child (see
`_paddingIncludingDecoration` in the Flutter framework), so the actual space
handed to `AppTextField` is **44 − 1 − 1 = 42px**, exactly matching the
crash's reported constraint (`BoxConstraints(w=334.0, h=42.0)`).

`AppTextField` wraps Forui's `FTextField`
(`lib/components/ui/app_text_field.dart`), which — with no `labelText` passed
here — renders a `_VerticalLabel` (`Column`, `mainAxisSize: min`) containing
just `Padding(childPadding, child: <editable text>)`. That content's natural
minimum height is 44px (the overflow amount, 2.0px, plus the 42px it was
given), one pixel each side more than the 42px left after the border eats
into the fixed 44px box.

This overflow is **unconditional**: `PauseScreen.initState()` always ensures
at least one custom-purpose field exists via `_addCustomField()` (both for
new pauses and pre-populated edits with no existing custom purposes), so the
offending row renders on first build every time the Pause screen opens —
matching the reported timing (the exception fires immediately, before any
duration/purpose data is even entered).

The second `AppTextField` usage in the same file (the duration input, ~line
545) sits in a `Container(width: 120, height: 52, ...)` with the same 1px
border. 52 − 2 = 50px, comfortably above the 44px minimum, so it does not
overflow — consistent with the crash log showing only one overflow instance.

### Related/unrelated to PR #319

**Confirmed unrelated.** `git diff main...feature/animation-interaction-consistency-pass
--stat` shows that branch touches `lib/features/setlists/widgets/special_item_card.dart`
only (wrapping `_buildSetBreakCard`/`_buildPauseCard` in `AnimatedCardPressable`,
+5/−1 lines) — it does not touch `pause_screen.dart`, `app_text_field.dart`, or any
Forui theme file. `special_item_card.dart` renders *existing* setlist items in the
list (and the crash log shows `0 pauses` loaded at the time of the exception — there
is no existing Pause card to render yet). `AnimatedCardPressable` also only wraps a
`child` with `GestureDetector` + `AnimatedScale`; it does not constrain or alter the
child's layout box in any way that could produce a fixed 42px height elsewhere.

This is a **pre-existing bug in `pause_screen.dart`**, unrelated to PR #319, that
Tony happened to trigger while manually testing that PR. There is also prior art in
this exact repo for the identical failure mode: `docs/features/song-lookup-field-overflow/ARCHITECT_PLAN.md`
diagnosed the same "fixed-height `Container` + `AppTextField`/`FTextField`
minimum-height conflict" pattern in a different file, and its accepted fix was to
stop fighting `FTextField`'s intrinsic sizing with a fixed-height parent.

## Existing System Analysis

- Live "Add Pause" path: `setlist_detail_screen.dart` / `new_setlist_screen.dart`
  → `showAddToSetlistOverlay()` (`add_to_setlist_overlay.dart`) → `PauseScreen`
  (`pause_screen.dart`). Confirmed via `PauseScreen(` call sites.
- `lib/features/setlists/widgets/pause_creator.dart` defines a separate,
  older `showPauseCreator()`/`PauseConfig` pair that is not wired into any
  current call site found in the app — out of scope, not touched.
- The custom-purpose-field row's outer 44px height was clearly sized to
  visually match the adjacent 44×44 "remove" button (`Container(width: 44,
  height: 44, ...)`, rendered when more than one custom field exists) — the
  content's true natural height (44px) already matches that target once the
  border stops subtracting from it.

## Proposed Solution

Remove the fixed `height: 44` from the custom-purpose-field `Container` in
`pause_screen.dart` and let it size to `AppTextField`'s natural intrinsic
height instead of fighting it. All other properties (`decoration`, `color`,
`borderRadius`, `border`) are unchanged. Since the field's natural content
height is 44px (as shown by the overflow arithmetic above), the row will
still visually align with the adjacent 44×44 remove button — no visual
regression, and this is the same fix pattern already accepted in this repo
for the equivalent `song-lookup-field-overflow` bug.

No change to `AppTextField`, `app_text_field.dart`, Forui theme, or any
animation-pass file.

## Database Impact

Not applicable — pure Flutter UI layout fix, no Supabase interaction.

## Flutter Architecture Changes

None. No new widgets, controllers, providers, or repositories. Single
`Container` property removal in an existing `StatefulWidget`'s `build()`
method.

## Files to Create

None.

## Files to Modify

| File | What changes |
| --- | --- |
| `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart` | Remove the `height: 44,` line from the `Container` wrapping the custom-purpose-field `AppTextField` (inside the `for (var i = 0; i < _customFields.length; i++)` loop, currently ~line 403). No other lines in this file change. |

## Files Off-Limits

| File | Reason |
| --- | --- |
| `lib/features/setlists/widgets/special_item_card.dart` | Not implicated — renders existing items only, unaffected by this bug and part of the separate, already-approved animation-pass PR. |
| `lib/app/theme/app_animations.dart` (`AnimatedCardPressable`) | Not implicated — confirmed unrelated to this layout conflict. |
| `lib/components/ui/app_text_field.dart` | Already correctly delegates to `FTextField`; the conflict is entirely in the fixed-height parent `Container` in `pause_screen.dart`, not in this wrapper. |
| `lib/features/setlists/widgets/pause_creator.dart` | Legacy/unwired duplicate, not part of the live Pause flow; not implicated. |
| The duration-input `Container` (~line 545) in `pause_screen.dart` | Its 52px height already leaves enough room (50px after border) — not overflowing, no change needed. |

**Migration policy:** not required (no database changes).
**Edge function deploy:** not required (no backend changes).
**New dependencies:** none.

## Change Budget

- Expected net line delta: −1 line (`lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`)
- Expected new files: 0
- Expected new public classes/methods: 0
- Expected new dependencies: 0

## System Impact Map

- Setlists: affected (fix location) — Pause creation/edit UI only.
- Gigs / Rehearsals / Members / Auth / Routing / Notifications: unaffected.
- Platforms: fix is pure layout, applies identically to all platforms
  (iOS/Android/macOS/Web); the overflow itself is a debug-mode Flutter
  rendering assertion, but the underlying overconstrained layout would
  produce clipped/squashed content in release mode on any platform too.

## Regression Risk

**LOW.** Single-property removal (`height: 44`) on one `Container` in one
file; no logic, state, controller, or data-flow changes; the row's resulting
height matches the existing adjacent 44px remove-button for visual
consistency.

## Engineer Task Breakdown

1. In `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`,
   remove the `height: 44,` property from the `Container` that wraps the
   custom-purpose-field `AppTextField` (inside the `for` loop building
   `_customFields`). Leave `decoration` (`color`, `borderRadius`, `border`)
   unchanged.

## Verification Plan

**Tier 1 (pre-deploy, no running app required):**
- `flutter analyze` on the changed file — 0 errors/warnings expected (pure
  property removal, no signature/type changes).
- Code review: confirm no other reference to this `Container`'s `height`
  exists elsewhere (e.g. no sibling code assumes a fixed 44px height for
  layout math) — grep for the surrounding method confirms the row's `Row`/
  `Padding` don't depend on a fixed child height.

**Tier 2 (owner-run, requires a running app — Tony, at PR-test time):**
1. Open any setlist (e.g. "Jonny Cabs").
2. Tap "+" → choose "Pause" (or the Breaks & Pauses category).
3. Expected: the Pause screen renders with no red/yellow overflow banner in
   the console or on screen, and the custom-purpose input row visually
   aligns with the (44×44) remove button when a second custom field is
   added.
4. Add a Pause with a custom purpose and confirm it saves and appears in the
   setlist as before (behavior unchanged, layout-only fix).

## QA Regression Areas

- Setlists → Add to Setlist overlay → Pause screen (create and edit modes).
- No other systems touched.

## Rollout Strategy

Standard PR merge; no migration or edge-function deploy required; no
feature flag needed (pure bugfix, no behavior change beyond removing the
layout error).

## Out of Scope

- `special_item_card.dart` / `AnimatedCardPressable` (PR #319) — confirmed
  unrelated, not touched.
- `pause_creator.dart` — legacy, unwired duplicate; not touched.
- The duration-input field's `Container` — not overflowing, not touched.
