## Summary

Adds the missing optional setlist picker to the rehearsal Add/Edit Event drawer. Rehearsals can now select an existing setlist or clear the association with `None`, matching the established gig picker behavior.

The rehearsal model, database column, save paths, edit prefill, and display surfaces already supported `setlist_id`; this change exposes the existing selector inside the rehearsal `Details` card, above the Notes field, so that support is reachable in the UI.

## Changes

- Renames the rehearsal `Notes` card to `Details` and places the existing setlist selector above Notes.
- Preserves the gig and block-out layouts unchanged.
- Adds widget coverage for the `Details` layout and selector-before-Notes order, selecting a setlist through the public save path, and clearing it with `None`.
- Adds no migration, RPC, dependency, route, provider, or public API.

## Verification

- Changed-file `flutter analyze`: no issues.
- Focused widget tests: 7/7 passed.
- Full Flutter suite: 311/311 passed.
- QA verdict: **APPROVED**, LOW regression risk.

QA recorded no Cycle 2 findings. The earlier non-blocking test-harness size warning was not worsened by this revision.

## Manual Verification

1. Open Home -> Add -> Rehearsal. Confirm one `Details` card appears after Location, with the `Setlist` label and selectable `None` / band-setlist pills above `Notes (optional)` and no separate Setlist or Notes cards.
2. Complete the required rehearsal fields, select a non-catalog setlist, enter a note, and save. Confirm the Home rehearsal card shows the selected setlist.
3. Reopen the rehearsal through View Rehearsal -> Edit. Confirm the selected setlist remains highlighted, the selector remains above Notes, and the note is preserved.
4. Select `None` and save. Confirm the note remains, while the setlist association and Home card pill are removed.
5. In a band with no setlists, confirm `Details` shows `None` and `+ Create Setlist` above Notes.
6. Create or edit a recurring rehearsal with a setlist. Confirm generated instances retain it and `None` clears it.
7. Repeat steps 1-4 on Web and confirm matching layout, persistence, note preservation, and clearing behavior.
8. Open Add -> Gig and confirm Show Details still includes the setlist selector and contacts while the gig Notes card remains separate.