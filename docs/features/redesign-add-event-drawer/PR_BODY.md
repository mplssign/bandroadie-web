## Redesign Add/Edit Event Drawer — Forui Dark Theme

Replaces the flat-scroll event editor with a structured, dark-mode drawer matching the spec mockup. All existing save/delete/RBAC logic is preserved unchanged.

### What changed

**Visual structure**
- Sticky header: title + subtitle + close button + 3-way event-type segmented control (Rehearsal / Gig / Block Out)
- Scrollable body: six section cards for the gig form (The gig / Schedule / Location / Show prep / Money / Notes); three for rehearsal (Schedule / Location / Notes); block-out form unchanged
- Sticky footer: live event summary (`Potential gig · Sep 2 · 7:00 PM · 1h`) + Cancel + primary submit button

**Theme**
- New `lib/app/theme/event_editor_theme.dart` with `buildEventEditorTheme()` and all extra colour tokens (`kEdSurface`, `kEdCardBg`, `kEdCardBorder`, `kEdInputFill`, etc.)
- `FTheme` scope is confined to the drawer — nothing outside it is affected

**Controls**
- `EventTextField` restyled: `kEdInputFill` fill, 8px radius, primary-colour focus ring
- `EventTypeSelector` restyled: dark segmented track, rose filled indicator
- `AvailabilityButton` and availability grid chips updated to success/danger token colours
- `EventEditorBottomActions` gains an optional `summary` text slot

**Soundcheck**
- New collapsible Soundcheck row in the Schedule section (mirrors Load-in pattern)
- UI-only state (`_soundcheckHour/Minutes/IsPM`) — not persisted to the database in this PR

### Files changed
- `lib/app/theme/event_editor_theme.dart` (new)
- `lib/features/events/widgets/event_editor_drawer.dart`
- `lib/features/events/widgets/event_editor_actions.dart`
- `lib/features/events/widgets/event_editor_helpers.dart`
- `lib/features/events/widgets/event_type_selector.dart`
- `lib/features/events/widgets/gig_form_fields.dart`
- `lib/features/events/widgets/event_form_fields.dart`
- `lib/features/events/widgets/rehearsal_form_fields.dart`
- `lib/features/events/widgets/button_group_grid.dart` (availability chip colours only — within approved scope)

### Off-limits unchanged
`add_edit_event_bottom_sheet.dart`, `event_form_data.dart`, `events_repository.dart` — untouched.

### Known limitation
`event_form_fields.dart` and `rehearsal_form_fields.dart` received targeted restylings but are not fully spec-compliant on every control (date button, time selects, duration stepper on rehearsal view). Visual polish deferred; no functional regression.

### No database changes
Pure UI redesign. No migrations, RLS policies, RPCs, or edge functions changed.
