## Summary

On the "My Profile" screen, the "Role in Band" chips row was inset by the same 24px horizontal padding as the rest of the form. This PR makes the chip row extend edge to edge, while every other section (name, phone, address, birthday, band selector) keeps its existing padding.

## Changes

- Split `_buildRoleSection()` into `_buildRoleSectionHeader()` (label + band selector, still inset) and `_buildRolePillRow()` (the pill row itself, no horizontal inset).
- Moved the outer scroll view's horizontal padding into a single wrapper around the padded sections, leaving the pill row as an unpadded sibling.
- No changes to role pill behavior, data, or state — pure layout restructure.

## Verification

- `flutter analyze` — clean
- `flutter test` (full suite, 277 tests) — all pass
- No existing test coverage on this screen; none added (pure layout change).

## Manual Verification Punch List (for reviewer/tester)

1. Open My Profile. Confirm the "Role in Band" label is inset ~24px like the fields above it.
2. Confirm the pill row (starting with "+ Add") sits flush against the left screen edge and extends past the right edge into a horizontal scroll.
3. Confirm scrolling, tapping to toggle roles, add/remove custom roles, and delete mode all still work as before.
4. If in multi-band mode, confirm the band selector row above the pills is still inset (unchanged).
5. Confirm Save/Cancel footer still works normally.
6. Check on a second platform (iOS or Web) for parity.

## Note

If you'd prefer the first pill aligned with the label above (24px inset) instead of flush against the screen edge, that's a one-line follow-up change.
