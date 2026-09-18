## Summary

Fixes two related bugs in the gig editor's soundcheck time field:

1. Setting, adjusting, or clearing a soundcheck time never marked the edit form dirty, so **Update** stayed disabled.
2. Even with the form marked dirty, soundcheck time had no path to the database — no `gigs` column, no model field, and it was dropped from the `EventsRepository` write payload.

A fully-wired duplicate widget (`GigFormFields.buildSoundcheckRow`) already existed but was never called; the drawer instead rendered an ad-hoc, half-scaffolded duplicate that only mutated local, non-persisted state.

## Changes

- New migration: `gigs.soundcheck_time` (nullable `TEXT`), mirroring the existing `load_in_time` column.
- `Gig` model: add `soundcheckTime` field, threaded through `fromJson`/`toJson`.
- `EventFormData`: add `soundcheckHour`/`soundcheckMinutes`/`soundcheckIsPM` fields, a `soundcheckTimeDisplay` getter, and `fromGig` parsing — all mirroring the existing `loadIn*` pattern.
- `EventsRepository`: write `soundcheck_time` in both the create-gig and update-gig payloads.
- `event_editor_drawer.dart`: wire the drawer's soundcheck state into `_buildFormData()`, populate it on edit-open, and pass all 8 soundcheck args (3 state + 5 callbacks) into `_createGigFormFields()` — every callback now calls `_markDirty()`, matching the working `onLoadIn*` callbacks. The ad-hoc inline soundcheck UI block and the now-dead `_buildSoundcheckTimePicker` helper are deleted in favor of the existing `GigFormFields.buildSoundcheckRow`.
- `gig_form_fields.dart`: fixed a `RenderFlex` overflow bug found during manual testing, in `buildSoundcheckRow`'s unset-state branch — it rendered raw text in a `Row` with no width constraint. Replaced with the same `EventAddValueButton` component the working load-in row already uses.

Net effect: this PR deletes more lines than it adds. Every new line mirrors an existing, already-working load-in-time line.

## Testing

- `flutter analyze` — clean on all touched files.
- `flutter test` — 13/13 passing, including two new unit tests (`EventFormData.soundcheckTimeDisplay`, `Gig` JSON round-trip for `soundcheck_time`).
- New migration independently applied against an ephemeral Supabase branch and confirmed to apply cleanly (no RLS/trigger/RPC changes).
- Manual/device testing not performed by this pipeline — see the Manual Verification Punch List in `QA_REPORT.md` for the exact steps to run before merging.

## Known limitation / prerequisite

The "Failed to update event" save error seen during initial manual testing has no code-level cause — the code is a byte-for-byte mirror of the working `load_in_time` path. The most likely cause is that the new migration hasn't been applied yet to whatever database the running app instance is pointed at. **Apply the migration to your local/dev database before testing this PR** (see punch list step 1 in `QA_REPORT.md`).

## Out of scope

- `view_gig_drawer.dart` (read-only gig view) does not display soundcheck time.
- The ICS calendar feed does not emit soundcheck time.
- Demo-session seeding RPCs were not touched.

These are all called out as intentional follow-ups, not omissions, in `ARCHITECT_PLAN.md`.
