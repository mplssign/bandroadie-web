# QA_REPORT.md

## Feature Slug

setlist-pause-label-overflow

## Cycle Number

1

## Final Verdict

APPROVED

## Scope Verification

- Branch `bug/setlist-pause-label-overflow` forks cleanly from `main`
  (`ARCHITECT_PLAN.md` is the only committed change on top of `main`'s
  HEAD).
- Working tree diff contains exactly one modified file:
  `lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`, one
  line removed (`height: 44,`), matching the plan's Files to Modify table
  and the Engineer's reported diff verbatim.
- No other tracked file changed. Only untracked addition is
  `docs/features/setlist-pause-label-overflow/ENGINEER_REPORT.md`.
- All plan-designated off-limits files (`special_item_card.dart`,
  `app_animations.dart`, `app_text_field.dart`, `pause_creator.dart`, the
  duration-input `Container`) are untouched.
- No dependency, schema, RPC, routing, or auth changes — none were in
  scope and none are present in the diff.

## Root Cause Validation

Confirmed in code: the removed `Container` had `height: 44` plus an
all-sides `Border.all(...)` (defaulting to 1.0 width). `Container`'s
`_paddingIncludingDecoration` folds `border.dimensions` in as effective
padding, leaving `AppTextField`'s child exactly 42px of vertical space —
2px short of `FTextField`'s ~44px intrinsic minimum for an unlabeled
vertical layout. This matches the crash's reported
`BoxConstraints(w=334.0, h=42.0)` and the 2.0px overflow amount precisely.
Removing the fixed height lets the `Container` size to the child's natural
44px content height, which is the correct fix, not a workaround (no
`SizedBox`/`ConstrainedBox` reintroducing the same conflict elsewhere).

## Reviewed Row Structure (regression check)

Read the full `for` loop and surrounding `Row`/`Padding` in
[pause_screen.dart](lib/features/setlists/widgets/add_to_setlist/pause_screen.dart#L393-L451):

- The `Row` has no `crossAxisAlignment: CrossAxisAlignment.stretch` and no
  other sibling relies on the removed `Container`'s height for its own
  layout math.
- The adjacent remove-button `Container` (`width: 44, height: 44`,
  rendered only when `_customFields.length > 1`) keeps its own explicit
  fixed size, untouched — so visual alignment between the text field row
  and the remove button is preserved once the text field settles at its
  natural ~44px height, per the plan's reasoning.
- No other code path in the file references this `Container`'s `height`.

## Static Analysis

Ran `flutter analyze lib/features/setlists/widgets/add_to_setlist/pause_screen.dart`:

```
info • Use 'DecoratedBox' rather than a 'Container' with only a 'Decoration'.
       lib/features/setlists/widgets/add_to_setlist/pause_screen.dart:401:34
       • use_decorated_box
1 issue found.
```

0 errors, 0 warnings — matches Engineer's report exactly. Confirmed in
`analysis_options.yaml` that `use_decorated_box` is enabled as a lint
(`linter.rules`) but is **not** among the rules promoted to `errors:`
(only `unused_import`, `unused_local_variable`, `unused_element`,
`unused_field`, `dead_code`, `use_build_context_synchronously`,
`unawaited_futures`, `cancel_subscriptions`, `close_sinks` are) — so this
`info` finding correctly does not fail analysis and does not block this
gate. Converting to `DecoratedBox` is outside the plan's single-line
scope and correctly was not done.

## Deviations From Plan

None found. Diff is a strict subset of what the plan specified — exactly
the one line, one file.

## Risk Assessment

LOW, consistent with the plan. Single CSS-like property removal, no
logic/state/controller/data-flow change, no widget tree restructuring.
Same fix pattern as the prior `song-lookup-field-overflow` bug in this
repo.

## Manual Verification Punch List

1. Run the app (`flutter run -d macos` or any platform) in debug mode.
2. Open any setlist with existing songs (e.g. "Jonny Cabs").
3. Tap the "+" add button, then choose "Pause" (Breaks & Pauses category).
4. Confirm the Pause screen opens with **no red/yellow overflow banner**
   on screen and no `RenderFlex overflowed` exception in the debug
   console.
5. Tap "Add another custom purpose" to add a second custom-purpose field,
   confirming the (44×44) remove "×" button now appears next to each row.
6. Visually confirm the custom-purpose text field row aligns with the
   adjacent remove button (no visible height mismatch).
7. Type a custom purpose, set a duration, and save the Pause; confirm it
   appears correctly in the setlist afterward (behavior unchanged from
   before the fix).
8. Repeat steps 2–4 once more from a fresh app launch to confirm the
   overflow does not occur on first build (the originally reported
   trigger).
