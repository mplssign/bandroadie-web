## Summary

Adds the missing optional setlist picker to the rehearsal Add/Edit Event drawer. Rehearsals can now select an existing setlist or clear the association with `None`, matching the established gig picker behavior.

The rehearsal model, database column, save paths, edit prefill, and display surfaces already supported `setlist_id`; this change exposes the existing selector inside the rehearsal `Details` card, above the Notes field, so that support is reachable in the UI.

## Changes

- Renames the rehearsal `Notes` card to `Details` and places the existing setlist selector above Notes.
- Shows a muted `No Setlist Selected` badge on confirmed and potential rehearsal/gig dashboard cards when their setlist association is empty.
- Preserves the confirmed rehearsal's existing selected-setlist badge and suppresses false empty badges while its setlist name loads.
- Preserves the gig and block-out layouts unchanged.
- Adds widget coverage for the `Details` layout, selector-before-Notes order, required Location gate, selecting a setlist through the public create path, and clearing it with `None`.
- Adds 11 widget cases covering selected, unselected, loading-name, and stale-name dashboard states across all four card variants.
- Adds no migration, RPC, dependency, route, provider, or public API.

## Verification

- Changed-file `flutter analyze`: no issues.
- Focused dashboard widget tests: 11/11 passed.
- Dashboard plus event regression tests: 18/18 passed.
- Full Flutter suite: 322/322 passed.
- QA verdict: **APPROVED**, LOW regression risk.

QA recorded no Cycle 4 findings. Create-mode coverage confirms that Location is required: selecting a setlist alone intentionally leaves `Add Rehearsal` disabled, while entering Location enables it and setlist changes preserve that enabled state. Dashboard badges key off the authoritative setlist ID, avoiding false badges during name loading and handling stale gig names correctly.

## Manual Verification

1. Open Home -> Add -> Rehearsal and leave Location empty. Confirm one `Details` card appears after Location, with the `Setlist` label and selectable `None` / band-setlist pills above `Notes (optional)`. `Add Rehearsal` remains disabled because Location is required.
2. Select a setlist while Location is empty, then enter a non-whitespace Location such as `Test Studio`. Confirm `Add Rehearsal` is disabled before Location is entered, becomes enabled afterward, and remains enabled while changing setlists.
3. Save with `Test Studio`, a non-catalog setlist, and a note. Confirm the Home rehearsal card shows the selected setlist.
4. Reopen the rehearsal through View Rehearsal -> Edit. Confirm the selected setlist remains highlighted, the selector remains above Notes, and the note is preserved.
5. Select `None` and save. Confirm the note remains, while the setlist association and Home card pill are removed.
6. In a band with no setlists, enter Location and confirm `Details` shows `None` and `+ Create Setlist` above Notes while `Add Rehearsal` is enabled.
7. Create or edit a recurring rehearsal with a valid Location and setlist. Confirm generated instances retain it and `None` clears it.
8. Repeat steps 1-5 on Web and confirm matching Location gating, layout, persistence, note preservation, and clearing behavior.
9. Open Add -> Gig and confirm Show Details still includes the setlist selector and contacts while the gig Notes card remains separate.
10. On Home, confirm confirmed and potential rehearsal cards without setlists show `No Setlist Selected`; selecting a setlist removes the empty badge, and confirmed rehearsals show their existing selected-setlist badge.
11. On Home, confirm confirmed and potential gig cards without setlists show `No Setlist Selected`; selecting a setlist removes the empty badge.
12. Cold-start with confirmed and potential rehearsals that have selected setlists. Confirm no transient `No Setlist Selected` badge appears while setlist names load.
13. Repeat the four dashboard no-setlist badge checks on Web and confirm matching layout and styling.
