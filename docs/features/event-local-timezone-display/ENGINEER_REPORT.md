# ENGINEER_REPORT.md

## Feature Slug

`bug/event-local-timezone-display`

## Branch

`bug/event-local-timezone-display`

---

## Summary

Implemented display-layer timezone conversion so event times (gigs, rehearsals) render in the viewer's local timezone rather than the band's stored timezone. Also fixed timezone-aware future/past filtering in controllers and repositories.

---

## Architect Plan Compliance

| Task | Description                                           | Status | Notes                                                                                     |
| ---- | ----------------------------------------------------- | ------ | ----------------------------------------------------------------------------------------- |
| 1    | Add `timezone: ^0.10.0` to `pubspec.yaml`             | Done   |                                                                                           |
| 2    | Create `lib/app/utils/timezone_helper.dart`           | Done   | `initialize()`, `toLocal()`, `toUtc()` implemented with `'America/Chicago'` fallback      |
| 3    | Add `formatRangeLocal()` to `TimeFormatter`           | Done   | Falls back to `formatRange()` on conversion error                                         |
| 4    | Initialize timezone data at startup (`main.dart`)     | Done   | Inserted after `WidgetsFlutterBinding.ensureInitialized()`, before `usePathUrlStrategy()` |
| 5    | Update `ConfirmedGigCard` with `bandTimezone`         | Done   |                                                                                           |
| 6    | Update `PotentialGigCard` with `bandTimezone`         | Done   | Non-multidate time path uses `formatRangeLocal`                                           |
| 7    | Update `RehearsalCard` with `bandTimezone`            | Done   | `_formatTimeLine()` updated                                                               |
| 8    | Update `CalendarEventCard` with `bandTimezone`        | Done   | Replaced `widget.event.timeRange` with `formatRangeLocal`                                 |
| 9    | Update `HomeScreen` parent to pass `bandTimezone`     | Done   |                                                                                           |
| 10   | Update `CalendarScreen` parent to pass `bandTimezone` | Done   |                                                                                           |
| 11   | Update `AvailabilityPromptModal` + callers            | Done   | `show()` static method and constructor both accept `bandTimezone`                         |
| 12   | Update `gig_controller.dart` filtering                | Done   | `_isEndTimeInFuture` uses `TimezoneHelper.toUtc()`                                        |
| 13   | Update `rehearsal_controller.dart` filtering          | Done   | Same pattern as gig controller                                                            |
| 14   | Update `gig_repository.dart` filtering                | Done   | Optional `bandTimezone` param on 3 fetch methods                                          |
| 15   | Update `rehearsal_repository.dart` filtering          | Done   | Optional `bandTimezone` param on 2 fetch methods                                          |

---

## Deviations from Architect Plan

### Additional files modified (not in Architect's "Files to Modify" table)

The Architect plan listed 14 files to modify. Six additional caller sites required updates because `bandTimezone` was added as a `required` constructor parameter on the card widgets, breaking existing callers that weren't listed:

| File                                                         | Change                                                                           | Justification                                                                 |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `lib/features/gigs/potential_gig_prompt_service.dart`        | Pass `bandTimezone` to `AvailabilityPromptModal.show()`                          | Required by Task 11 ("Update callers of AvailabilityPromptModal")             |
| `lib/features/home/home_tab_content.dart`                    | Pass `bandTimezone` to `RehearsalCard`, `PotentialGigCard`, `ConfirmedGigCard`   | Additional caller of all 3 card widgets (parallel to `home_screen.dart`)      |
| `lib/features/calendar/calendar_tab_content.dart`            | Add `bandTimezone` to `_EventsSection`, pass to `CalendarEventCard`              | Additional caller of `CalendarEventCard` (parallel to `calendar_screen.dart`) |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` | Add `bandTimezone` field/constructor/`show()` param, pass to `CalendarEventCard` | Contains `CalendarEventCard` instances; threads timezone from callers         |

These are mechanical fixes — pass `bandTimezone` from `ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'` at each call site. No architectural deviation.

### Scope note on `calendar_screen.dart`

The `_EventsSection` widget in `calendar_screen.dart` is instantiated inside `_buildContent()`, a helper method that doesn't have direct access to the `bandState` local variable from `build()`. Used `ref.watch(activeBandProvider)` directly instead of threading the variable through. Same pattern applied to `calendar_tab_content.dart`.

---

## Files Changed

### New Files (1)

| File                                 | Purpose                                                |
| ------------------------------------ | ------------------------------------------------------ |
| `lib/app/utils/timezone_helper.dart` | Centralized TZ init, `toLocal()`, `toUtc()` conversion |

### Modified Files (18)

| File                                                         | Lines Changed                                                |
| ------------------------------------------------------------ | ------------------------------------------------------------ |
| `pubspec.yaml`                                               | +3 (timezone dependency)                                     |
| `lib/main.dart`                                              | +5 (import + initialize call)                                |
| `lib/app/utils/time_formatter.dart`                          | +34 (`formatRangeLocal` method)                              |
| `lib/features/home/widgets/confirmed_gig_card.dart`          | +4 (constructor param + formatRangeLocal)                    |
| `lib/features/home/widgets/potential_gig_card.dart`          | +4 (constructor param + formatRangeLocal)                    |
| `lib/features/home/widgets/rehearsal_card.dart`              | +4 (constructor param + formatRangeLocal)                    |
| `lib/features/calendar/widgets/calendar_event_card.dart`     | +10 (constructor param + import + formatRangeLocal)          |
| `lib/features/gigs/widgets/availability_prompt_modal.dart`   | +8 (constructor + show() param + formatRangeLocal)           |
| `lib/features/home/home_screen.dart`                         | +8 (bandTimezone derivation + pass to 3 cards)               |
| `lib/features/home/home_tab_content.dart`                    | +9 (bandTimezone pass to 3 cards)                            |
| `lib/features/calendar/calendar_screen.dart`                 | +10 (bandTimezone to \_EventsSection + DayDetailBottomSheet) |
| `lib/features/calendar/calendar_tab_content.dart`            | +8 (\_EventsSection bandTimezone + DayDetailBottomSheet)     |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` | +5 (bandTimezone field/constructor/show/pass)                |
| `lib/features/gigs/gig_controller.dart`                      | ~20 (TimezoneHelper.toUtc in filtering)                      |
| `lib/features/rehearsals/rehearsal_controller.dart`          | ~20 (TimezoneHelper.toUtc in filtering)                      |
| `lib/features/gigs/gig_repository.dart`                      | ~20 (optional bandTimezone param + toUtc)                    |
| `lib/features/rehearsals/rehearsal_repository.dart`          | ~20 (optional bandTimezone param + toUtc)                    |
| `lib/features/gigs/potential_gig_prompt_service.dart`        | +5 (read bandTimezone, pass to modal)                        |

**Total: 19 files changed, +268 / -164 lines**

---

## Off-Limits Files — Verified Untouched

- `lib/features/events/widgets/event_editor_drawer.dart` — not modified
- `lib/features/events/models/event_form_data.dart` — not modified
- `lib/features/events/events_repository.dart` — not modified
- `lib/app/models/gig.dart` — not modified
- `lib/app/models/rehearsal.dart` — not modified
- `lib/features/calendar/models/calendar_event.dart` — not modified
- `supabase/` — not modified
- `sql/` — not modified
- Platform configs (`.entitlements`, `AndroidManifest.xml`, `Info.plist`) — not modified

---

## Validation Results

| Check             | Result             |
| ----------------- | ------------------ |
| `flutter pub get` | Pass               |
| `flutter analyze` | 0 issues           |
| `flutter test`    | 6/6 tests pass     |
| `dart format`     | 18 files formatted |

---

## Manual Verification Required

The following manual tests from the Architect plan should be performed before merge:

1. **Same-timezone test**: Device and band both in `America/Chicago` → times display identically to previous behavior
2. **Cross-timezone test**: Change device to `America/New_York` → Chicago 7:30 PM displays as 8:30 PM
3. **Midnight-crossing test**: 11:00 PM Chicago → 12:00 AM New York with date adjustment
4. **Filtering test**: Just-ended event disappears regardless of device timezone
5. **Availability modal test**: Potential gig prompt shows local-converted time
6. **Fallback test**: Invalid band timezone falls back to `America/Chicago` without crash
7. **Event editor test**: Editor still shows/captures band-timezone times (unchanged)

---

## Risk Assessment

**LOW-MEDIUM**. All changes are display-layer only. Data integrity is preserved — no write paths were modified. The `timezone` package is mature (Dart team maintained). Same-timezone users experience a no-op conversion. Fallback to `'America/Chicago'` prevents crashes on invalid timezone data.
