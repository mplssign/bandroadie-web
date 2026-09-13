## Summary

Adds the missing optional setlist picker to the rehearsal Add/Edit Event drawer. Rehearsals can now select an existing setlist or clear the association with `None`, matching the established gig picker behavior.

The rehearsal model, database column, save paths, edit prefill, and display surfaces already supported `setlist_id`; this change exposes the existing selector inside the rehearsal `Details` card, above the Notes field, so that support is reachable in the UI.

## Changes

- Renames the rehearsal `Notes` card to `Details` and places the existing setlist selector above Notes.
- Shows a muted `No Setlist Selected` badge on confirmed rehearsal and confirmed gig dashboard cards when their setlist association is empty.
- Keeps potential rehearsal and potential gig cards badge-free regardless of setlist state.
- Preserves the confirmed rehearsal's existing selected-setlist badge and suppresses false empty badges while its setlist name loads.
- Preserves the gig and block-out layouts unchanged.
- Adds widget coverage for the `Details` layout, selector-before-Notes order, required Location gate, selecting a setlist through the public create path, and clearing it with `None`.
- Captures framework errors during first-character Location entry and verifies no error banner, validation message, or exception appears as `Add Rehearsal` enables.
- Adds 10 widget cases covering confirmed-card badges and potential-card badge absence across selected, unselected, loading-name, and stale-name states.
- Adds no migration, RPC, dependency, route, provider, or public API.

## Verification

- Changed-file `flutter analyze`: no issues.
- Focused dashboard widget tests: 10/10 passed.
- Event regression tests: 7/7 passed.
- Full Flutter suite: 321/321 passed.
- QA verdict: **APPROVED**, LOW regression risk.

QA recorded no Cycle 6 findings. Create-mode coverage confirms that Location is required: selecting a setlist alone intentionally leaves `Add Rehearsal` disabled, while entering Location enables it and setlist changes preserve that enabled state. Confirmed dashboard badges key off the authoritative setlist ID; potential cards never render the badge.

Accepted limitation: a brief error flash observed once during native Location entry could not be reproduced in the widget harness, and its exact message was not captured. No speculative production change was made. If it recurs, capture the exact text or a screen recording, platform/OS, app build, timing relative to the first character, and whether Save or another validation action was attempted first.

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
10. On Home, confirm a confirmed rehearsal without a setlist shows `No Setlist Selected`; selecting a setlist replaces it with the existing selected-setlist badge.
11. On Home, confirm a confirmed gig without a setlist shows `No Setlist Selected`; selecting a setlist removes the empty badge.
12. Confirm potential rehearsal and potential gig cards never show `No Setlist Selected`, whether a setlist is selected or not.
13. Cold-start with a confirmed rehearsal that has a selected setlist. Confirm no transient `No Setlist Selected` badge appears while its setlist name loads.
14. Repeat the confirmed and potential dashboard checks on Web and confirm matching behavior.
15. On the native platform where the brief Location error was observed, start a screen recording and open a fresh Add Rehearsal drawer. Without attempting Save, type `T`, pause, then complete `Test Studio`. Confirm no error banner, inline message, snackbar, system message, or framework overlay flashes and that `Add Rehearsal` enables after the first character.
16. Repeat step 15 with the original interaction history, including any focus, clear, re-entry, or attempted validation. If anything flashes, preserve its exact text, UI location, first video frame, platform/OS, and app build.
17. Repeat step 15 on Web and record any platform difference.
