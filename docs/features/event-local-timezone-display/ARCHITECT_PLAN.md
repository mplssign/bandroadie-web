# ARCHITECT_PLAN.md

## Feature Slug

`bug/event-local-timezone-display`

> **Revision 2 — 2026-03-18**: Updated Sections 9, 11, 12, 13, 15, 17, and Widget Contracts to reflect caller-site propagation discovered during Engineer pass. 4 additional files added to the approved file list. Task count: 15 → 19. No scope expansion — all additions are mechanical `bandTimezone` parameter threading required by the approved `required` constructor contract. See §9e for complete call-site audit.

---

## 1. Problem Summary

Event times for gigs and rehearsals do not display in the viewer's local time zone. All users see the same clock time regardless of their device's time zone. A band member in New York viewing a gig created in Chicago sees "7:30 PM" instead of "8:30 PM" (their local equivalent). This affects all display surfaces: home dashboard cards, calendar view, and availability modals.

---

## 2. Existing System Analysis

### Time Storage Architecture

Event times are stored as **timezone-unaware TEXT strings** in 24-hour format:

| Table        | Column         | Type            | Example             |
| ------------ | -------------- | --------------- | ------------------- |
| `gigs`       | `start_time`   | TEXT            | `"19:30"`           |
| `gigs`       | `end_time`     | TEXT            | `"22:00"`           |
| `gigs`       | `load_in_time` | TEXT (nullable) | `"18:00"`           |
| `gigs`       | `date`         | DATE            | `"2026-03-20"`      |
| `rehearsals` | `start_time`   | TEXT            | `"18:00"`           |
| `rehearsals` | `end_time`     | TEXT            | `"21:00"`           |
| `rehearsals` | `date`         | DATE            | `"2026-03-20"`      |
| `bands`      | `timezone`     | TEXT            | `"America/Chicago"` |

### Band Timezone Field

`bands.timezone` was added in migration `20260305000000_band_scoped_calendar.sql` with default `'America/Chicago'`. It is currently used **only** by the Supabase Edge Function `calendar-feed` for ICS export (`DTSTART;TZID=...`). It is **not used anywhere in the Flutter display layer**.

### Current Display Flow

```
DB TEXT "19:30" → Gig.startTime (String) → TimeFormatter.parse("19:30")
  → ParsedTime(hour: 7, minutes: 30, isPM: true)
  → ParsedTime.format() → "7:30 PM"
```

All display surfaces call `TimeFormatter.formatRange(startTime, endTime)` which performs pure string-to-string conversion with no timezone context:

- `Gig.timeRange` getter → `TimeFormatter.formatRange(startTime, endTime)`
- `Rehearsal.timeRange` getter → `TimeFormatter.formatRange(startTime, endTime)`
- `CalendarEvent.timeRange` getter → `TimeFormatter.formatRange(startTime, endTime)`
- Card widgets call these getters or `TimeFormatter.formatRange()` directly

### Current Filtering Flow

Client-side "is event in the future" filtering in controllers and repositories:

```dart
final endDateTime = DateTime(
  gig.date.year, gig.date.month, gig.date.day,
  int.parse(gig.endTime.split(':')[0]),
  int.parse(gig.endTime.split(':')[1]),
).toUtc();
return endDateTime.isAfter(nowUtc);
```

This constructs a `DateTime` in the **device's local timezone** (implicit `DateTime()` behavior), then converts to UTC. For cross-timezone users, this produces incorrect UTC times because the stored time is in the **band's** timezone, not the device's timezone.

### Display Surfaces (Exhaustive)

| Surface             | File                                                       | How Time Is Displayed                                               |
| ------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------- |
| Confirmed gig card  | `lib/features/home/widgets/confirmed_gig_card.dart`        | `TimeFormatter.formatRange(gig.startTime, gig.endTime)`             |
| Potential gig card  | `lib/features/home/widgets/potential_gig_card.dart`        | `TimeFormatter.formatRange(gig.startTime, gig.endTime)`             |
| Rehearsal card      | `lib/features/home/widgets/rehearsal_card.dart`            | `TimeFormatter.formatRange(rehearsal.startTime, rehearsal.endTime)` |
| Calendar event card | `lib/features/calendar/widgets/calendar_event_card.dart`   | `widget.event.timeRange` (→ `TimeFormatter.formatRange`)            |
| Availability modal  | `lib/features/gigs/widgets/availability_prompt_modal.dart` | `TimeFormatter.formatRange(gig.startTime, gig.endTime)`             |

### Filtering call sites (all timezone-unaware)

| Location                         | File                                                | Method                                                                              |
| -------------------------------- | --------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Gig controller                   | `lib/features/gigs/gig_controller.dart`             | `_isEndTimeInFuture()`                                                              |
| Rehearsal controller             | `lib/features/rehearsals/rehearsal_controller.dart` | `_isEndTimeInFuture()`                                                              |
| Gig repository (3 methods)       | `lib/features/gigs/gig_repository.dart`             | inline filtering in `fetchPotentialGigs`, `fetchConfirmedGigs`, `fetchUpcomingGigs` |
| Rehearsal repository (2 methods) | `lib/features/rehearsals/rehearsal_repository.dart` | inline filtering in `fetchUpcomingRehearsals`, `fetchNextRehearsal`                 |

---

## 3. Root Cause

**Root Cause Confidence: HIGH** — confirmed by direct code inspection.

Event times are stored as timezone-unaware TEXT strings. The `Band.timezone` field (IANA identifier) exists but is never used in the Flutter display or filtering layers. `TimeFormatter` performs pure string parsing with no timezone parameter. Client-side filtering constructs `DateTime` objects assuming device-local timezone when the stored times are actually in the band's timezone.

Two distinct failures share the same root cause:

1. **Display failure:** Times are shown as-is from the database without conversion to the viewer's local timezone.
2. **Filtering failure:** `_isEndTimeInFuture()` interprets stored times as device-local instead of band-timezone, producing incorrect UTC comparisons for cross-timezone users.

---

## 4. Proposed Solution

### Approach: Display-Layer Timezone Conversion

Add the `timezone` Dart package for IANA timezone support. Create a centralized conversion utility. Update display surfaces to convert from band timezone to device local timezone. Update filtering logic to construct timezone-correct DateTimes.

### Conversion Path

```
DB TEXT "19:30" + event DATE "2026-03-20" + band timezone "America/Chicago"
  → TZDateTime(Chicago, 2026, 3, 20, 19, 30)   // timezone package
  → .toLocal()                                    // Dart built-in
  → DateTime in device timezone
  → Format for display: "8:30 PM" (if device is in New York)
```

### Key Design Decisions

1. **Display-only change**: Event creation/editing continues to work in the band's timezone. The stored format does not change. Only READ paths are affected.

2. **Constructor propagation**: Card widgets receive `bandTimezone` as a constructor parameter from parent widgets (which already have access to `activeBand.timezone`). This follows the unidirectional data flow guardrail.

3. **No date shift for same-day events**: If timezone conversion crosses midnight (e.g., 11 PM Chicago → 12 AM New York), the displayed DATE should also reflect the viewer's local date. The conversion utility handles this naturally since `TZDateTime.toLocal()` produces a full DateTime.

4. **Initialization**: `tz.initializeTimeZones()` added at app startup between `WidgetsFlutterBinding.ensureInitialized()` and `usePathUrlStrategy()`. This is a pure data-loading operation with no side effects. **Architect approved** — does not change the order of existing initialization steps, only inserts a new step before any UI/service work.

5. **Same-timezone optimization**: When `band.timezone` matches the device timezone, the conversion is effectively a no-op. No special-casing needed — `TZDateTime.toLocal()` handles this correctly.

### Scope Constraint

The event editor/form (`event_editor_drawer.dart`) is **explicitly excluded** from this change. It continues to display and capture times in the band's timezone because that is what gets stored. Changing the editor would risk data integrity regressions.

---

## 5. Database Impact

**Database: not applicable.**

No schema changes, no migrations, no RLS changes, no RPC changes, no trigger changes. The `bands.timezone` column already exists with correct IANA timezone values.

---

## 6. RLS / RPC Changes

None.

---

## 7. Flutter Architecture Changes

### New Dependency

| Package    | Version   | Purpose                                                                                       |
| ---------- | --------- | --------------------------------------------------------------------------------------------- |
| `timezone` | `^0.10.0` | IANA timezone database for Dart — enables constructing DateTimes in arbitrary named timezones |

### New File

| File                                 | Purpose                                 |
| ------------------------------------ | --------------------------------------- |
| `lib/app/utils/timezone_helper.dart` | Centralized timezone conversion utility |

### Modified Architecture

| Component         | Change                                                                                 |
| ----------------- | -------------------------------------------------------------------------------------- |
| `TimeFormatter`   | Add `formatRangeLocal()` method that accepts `DateTime date` and `String bandTimezone` |
| Card constructors | Accept `String bandTimezone` parameter                                                 |
| Parent widgets    | Pass `activeBand.timezone` to card constructors                                        |
| Controllers       | Use timezone-aware DateTime construction in `_isEndTimeInFuture()`                     |
| Repositories      | Accept `String bandTimezone` parameter in filtered fetch methods                       |

No new controllers, providers, repositories, or state management layers. No architectural refactors.

---

## 8. Exact Files to Create

| File                                 | Justification                                                                                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/app/utils/timezone_helper.dart` | Centralizes TZ initialization check and conversion logic. Single file keeps the diff localized and avoids scattering timezone logic across multiple widgets. |

### `timezone_helper.dart` Contract

```dart
class TimezoneHelper {
  /// Initialize timezone database. Safe to call multiple times (idempotent).
  static void initialize();

  /// Convert a time string (24h format "HH:MM") on a given date from the
  /// band's timezone to the device's local timezone.
  /// Returns a local DateTime.
  static DateTime toLocal(DateTime eventDate, String timeStr24, String bandTimezone);

  /// Build a timezone-aware DateTime for accurate UTC comparison.
  /// Used by _isEndTimeInFuture filtering logic.
  static DateTime toUtc(DateTime eventDate, String timeStr24, String bandTimezone);
}
```

---

## 9. Exact Files to Modify

Files are grouped by change category. All modifications stem from the approved design: adding `bandTimezone` as a required constructor/method parameter on display widgets and using `TimezoneHelper` for timezone-aware conversion.

### 9a. Core infrastructure (dependency + init + utility)

| #   | File                                | What Changes                                                                                                                                                         |
| --- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `pubspec.yaml`                      | Add `timezone: ^0.10.0` under dependencies                                                                                                                           |
| 2   | `lib/main.dart`                     | Add `TimezoneHelper.initialize()` call after `WidgetsFlutterBinding.ensureInitialized()`, before `usePathUrlStrategy()`                                              |
| 3   | `lib/app/utils/time_formatter.dart` | Add `formatRangeLocal(String? startTime, String? endTime, DateTime date, String bandTimezone)` static method that uses `TimezoneHelper` to convert before formatting |

### 9b. Display widgets (add `required String bandTimezone` constructor param)

| #   | File                                                         | What Changes                                                                                                                                                                                            |
| --- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 4   | `lib/features/home/widgets/confirmed_gig_card.dart`          | Add `String bandTimezone` constructor param; replace `TimeFormatter.formatRange(startTime, endTime)` with `TimeFormatter.formatRangeLocal(startTime, endTime, gig.date, bandTimezone)`                  |
| 5   | `lib/features/home/widgets/potential_gig_card.dart`          | Add `String bandTimezone` constructor param; use `formatRangeLocal` for time display                                                                                                                    |
| 6   | `lib/features/home/widgets/rehearsal_card.dart`              | Add `String bandTimezone` constructor param; use `formatRangeLocal` for time display                                                                                                                    |
| 7   | `lib/features/calendar/widgets/calendar_event_card.dart`     | Add `String bandTimezone` constructor param; use `formatRangeLocal` instead of `widget.event.timeRange`                                                                                                 |
| 8   | `lib/features/gigs/widgets/availability_prompt_modal.dart`   | Add `String bandTimezone` to constructor AND `show()` static method; use `formatRangeLocal` for the time display row                                                                                    |
| 9   | `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` | Add `String bandTimezone` to constructor AND `show()` static method; thread to `CalendarEventCard` instances inside the sheet. Required because this widget instantiates `CalendarEventCard` (file #7). |

### 9c. Parent / caller widgets (thread `bandTimezone` to child constructors)

These files instantiate the widgets from §9b. Because `bandTimezone` is a `required` constructor parameter, every call site must supply it. Each derives the value from `ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`.

| #   | File                                                  | What Changes                                                                                                                                                                                       | Supplies `bandTimezone` to          |
| --- | ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| 10  | `lib/features/home/home_screen.dart`                  | Pass `bandTimezone` to `ConfirmedGigCard`, `PotentialGigCard`, `RehearsalCard` constructors                                                                                                        | Files #4, #5, #6                    |
| 11  | `lib/features/home/home_tab_content.dart`             | Pass `bandTimezone` to `ConfirmedGigCard`, `PotentialGigCard`, `RehearsalCard` constructors. Parallel caller to `home_screen.dart` — both screens instantiate the same card widgets.               | Files #4, #5, #6                    |
| 12  | `lib/features/calendar/calendar_screen.dart`          | Pass `bandTimezone` to `_EventsSection` (private widget with `CalendarEventCard`) and `DayDetailBottomSheet.show()`                                                                                | Files #7 (via `_EventsSection`), #9 |
| 13  | `lib/features/calendar/calendar_tab_content.dart`     | Pass `bandTimezone` to `_EventsSection` (private widget with `CalendarEventCard`) and `DayDetailBottomSheet.show()`. Parallel caller to `calendar_screen.dart`.                                    | Files #7 (via `_EventsSection`), #9 |
| 14  | `lib/features/gigs/potential_gig_prompt_service.dart` | Read `bandTimezone` from `activeBandProvider`; pass to `AvailabilityPromptModal.show()`. This is the only non-widget caller of the modal — it's the service that triggers the availability prompt. | File #8                             |

### 9d. Filtering logic (timezone-aware future/past comparison)

| #   | File                                                | What Changes                                                                                                                                                               |
| --- | --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 15  | `lib/features/gigs/gig_controller.dart`             | Update `_isEndTimeInFuture()` to use `TimezoneHelper.toUtc()` instead of `DateTime(...).toUtc()`; read band timezone from `fullState.band.timezone` in `_categorizeGigs()` |
| 16  | `lib/features/rehearsals/rehearsal_controller.dart` | Update `_isEndTimeInFuture()` to use `TimezoneHelper.toUtc()`; read band timezone from `fullState.band.timezone` in `_categorizeRehearsals()`                              |
| 17  | `lib/features/gigs/gig_repository.dart`             | Add `String? bandTimezone` parameter to `fetchPotentialGigs`, `fetchConfirmedGigs`, `fetchUpcomingGigs`; use `TimezoneHelper.toUtc()` in inline filtering                  |
| 18  | `lib/features/rehearsals/rehearsal_repository.dart` | Add `String? bandTimezone` parameter to `fetchUpcomingRehearsals` and `fetchNextRehearsal`; use `TimezoneHelper.toUtc()` in inline filtering                               |

### 9e. Complete call-site audit

The following audit confirms that every instantiation of every modified widget is accounted for in §9b–§9c. QA can use this table to verify completeness.

| Widget                    | Instantiated in                                     | Covered by task # |
| ------------------------- | --------------------------------------------------- | ----------------- |
| `ConfirmedGigCard`        | `home_screen.dart`                                  | #10               |
| `ConfirmedGigCard`        | `home_tab_content.dart`                             | #11               |
| `PotentialGigCard`        | `home_screen.dart`                                  | #10               |
| `PotentialGigCard`        | `home_tab_content.dart`                             | #11               |
| `RehearsalCard`           | `home_screen.dart`                                  | #10               |
| `RehearsalCard`           | `home_tab_content.dart`                             | #11               |
| `CalendarEventCard`       | `calendar_screen.dart` (via `_EventsSection`)       | #12               |
| `CalendarEventCard`       | `calendar_tab_content.dart` (via `_EventsSection`)  | #13               |
| `CalendarEventCard`       | `day_detail_bottom_sheet.dart`                      | #9                |
| `AvailabilityPromptModal` | `potential_gig_prompt_service.dart` (via `.show()`) | #14               |
| `DayDetailBottomSheet`    | `calendar_screen.dart` (via `.show()`)              | #12               |
| `DayDetailBottomSheet`    | `calendar_tab_content.dart` (via `.show()`)         | #13               |

---

## 10. Files Off-Limits

| File                                                     | Reason                                                                                                        |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart`   | Event creation/editing must continue to work in band timezone — changing this risks data integrity regression |
| `lib/features/events/models/event_form_data.dart`        | Form data model stores times for submission in band timezone; must not change                                 |
| `lib/features/events/events_repository.dart`             | Write path — times are stored in band timezone; must not convert                                              |
| `lib/main.dart` init order                               | Only the timezone initialization INSERT is permitted; do not reorder existing steps                           |
| `lib/app/models/gig.dart`                                | Model `timeRange` getter is retained for backward compatibility; display conversion happens at widget layer   |
| `lib/app/models/rehearsal.dart`                          | Same as above                                                                                                 |
| `lib/features/calendar/models/calendar_event.dart`       | Same as above — `timeRange` getter stays, widget overrides for display                                        |
| `supabase/`                                              | No server-side changes                                                                                        |
| `sql/`                                                   | No migration changes                                                                                          |
| Any `.entitlements`, `AndroidManifest.xml`, `Info.plist` | No platform config changes                                                                                    |

---

## 11. System Impact Map

| System                 | Impact       | Notes                                                       |
| ---------------------- | ------------ | ----------------------------------------------------------- |
| Gigs                   | **affected** | Display + filtering + availability prompt                   |
| Rehearsals             | **affected** | Display + filtering                                         |
| Calendar               | **affected** | Calendar event card + day detail bottom sheet + tab content |
| Home                   | **affected** | home_screen.dart + home_tab_content.dart (parallel callers) |
| Setlists / Catalog     | unaffected   | No time display                                             |
| Members / RBAC         | unaffected   | No time display                                             |
| Auth / Session         | unaffected   | No change                                                   |
| Routing                | unaffected   | No change                                                   |
| Notifications          | unaffected   | Push notifications do not display event times               |
| iOS                    | **affected** | Same Flutter code                                           |
| Android                | **affected** | Same Flutter code                                           |
| Web                    | **affected** | Same Flutter code                                           |
| macOS                  | **affected** | Same Flutter code                                           |
| Event creation/editing | unaffected   | Explicitly excluded                                         |
| Calendar ICS export    | unaffected   | Already uses band timezone correctly                        |
| Block-outs             | unaffected   | All-day events, no time display                             |

---

## 12. Regression Risk

**MEDIUM**

Rationale:

- 18 files modified (1 new + 17 existing) plus `pubspec.yaml` — moderate surface area. The original plan listed 14 files; 4 additional caller-site files are required propagation, not scope expansion.
- The 4 added files (`home_tab_content.dart`, `calendar_tab_content.dart`, `day_detail_bottom_sheet.dart`, `potential_gig_prompt_service.dart`) are mechanical parameter-threading. They contain no conversion logic — they only pass `bandTimezone` from the provider to child constructors.
- Auth, session, routing, and init order are NOT meaningfully changed (only an additive init step)
- No database mutations or schema changes
- No write-path changes — event creation/editing untouched
- Risk is concentrated in the display layer: if timezone conversion malfunctions, times display incorrectly but data integrity is preserved
- `timezone` package is mature and well-maintained (maintained by the Dart team)
- Same-timezone users (majority case) experience a no-op conversion — regression risk is lower for the common case
- The extra call-site files do NOT increase regression risk meaningfully — they are one-line parameter additions with no behavioral logic

---

## 13. Engineer Task Breakdown

Execute in order. Each task is atomic.

### Task 1: Add dependency

- Add `timezone: ^0.10.0` to `pubspec.yaml` under dependencies
- Run `flutter pub get`

### Task 2: Create timezone helper

- Create `lib/app/utils/timezone_helper.dart`
- Implement `initialize()`, `toLocal()`, `toUtc()` methods
- `initialize()` calls `tz.initializeTimeZones()` from the `timezone` package
- `toLocal()`: parses 24h time string, creates `TZDateTime` in band timezone, returns `.toLocal()`
- `toUtc()`: parses 24h time string, creates `TZDateTime` in band timezone, returns `.toUtc()` as DateTime
- Handle fallback: if band timezone is invalid or empty, default to `'America/Chicago'`

### Task 3: Add `formatRangeLocal` to TimeFormatter

- Add static method `formatRangeLocal(String? startTime, String? endTime, DateTime date, String bandTimezone)` to `TimeFormatter`
- Method uses `TimezoneHelper.toLocal()` to convert start/end times to local DateTimes
- Formats result using 12-hour format consistent with existing `formatRange` output
- Fallback: if conversion fails, fall back to `formatRange()` (timezone-unaware) to avoid display breakage

### Task 4: Initialize timezone data at startup

- In `lib/main.dart`, add `TimezoneHelper.initialize()` after `WidgetsFlutterBinding.ensureInitialized()` and before `usePathUrlStrategy()`
- Import `timezone_helper.dart`

### Task 5: Update display cards — ConfirmedGigCard

- Add `required String bandTimezone` to constructor
- Replace `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)` with `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`

### Task 6: Update display cards — PotentialGigCard

- Add `required String bandTimezone` to constructor
- Use `formatRangeLocal` for time display (non-multidate path)

### Task 7: Update display cards — RehearsalCard

- Add `required String bandTimezone` to constructor
- Update `_formatTimeLine` to use `formatRangeLocal`

### Task 8: Update display cards — CalendarEventCard

- Add `required String bandTimezone` to constructor
- Replace `widget.event.timeRange` with `TimeFormatter.formatRangeLocal(widget.event.startTime, widget.event.endTime, widget.event.date, widget.bandTimezone)`

### Task 9: Update display widget — DayDetailBottomSheet

- Add `required String bandTimezone` to constructor and `show()` static method
- Thread `bandTimezone` to `CalendarEventCard` instances inside the sheet
- Required because this widget instantiates `CalendarEventCard` (Task 8)

### Task 10: Update display widget — AvailabilityPromptModal

- Add `required String bandTimezone` to constructor and `show()` static method
- Use `formatRangeLocal` for the time display `_DetailRow`

### Task 11: Thread `bandTimezone` through parent — HomeScreen

- In `home_screen.dart`, at the call sites for `ConfirmedGigCard`, `PotentialGigCard`, `RehearsalCard`, pass `bandTimezone: activeBand.timezone` (derive from `bandState.activeBand?.timezone ?? 'America/Chicago'`)

### Task 12: Thread `bandTimezone` through parent — HomeTabContent

- In `home_tab_content.dart`, pass `bandTimezone` to `ConfirmedGigCard`, `PotentialGigCard`, `RehearsalCard` constructors
- This file is a parallel caller to `home_screen.dart` — both instantiate the same 3 card widgets
- Derive from `ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`

### Task 13: Thread `bandTimezone` through parent — CalendarScreen

- In `calendar_screen.dart`, pass `bandTimezone` to `_EventsSection` (which wraps `CalendarEventCard`) and to `DayDetailBottomSheet.show()`
- Note: `_EventsSection` is instantiated inside `_buildContent()` which does not have `bandState` in scope — use `ref.watch(activeBandProvider)` directly

### Task 14: Thread `bandTimezone` through parent — CalendarTabContent

- In `calendar_tab_content.dart`, pass `bandTimezone` to `_EventsSection` and to `DayDetailBottomSheet.show()`
- Parallel caller to `calendar_screen.dart` — both screens host the same `_EventsSection` pattern and `DayDetailBottomSheet` invocations

### Task 15: Thread `bandTimezone` through caller — PotentialGigPromptService

- In `potential_gig_prompt_service.dart`, read `bandTimezone` from `ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`
- Pass to `AvailabilityPromptModal.show()`
- This is the only non-widget caller of the modal

### Task 16: Update gig controller filtering

- In `gig_controller.dart`, update `_categorizeGigs` to accept `String bandTimezone` and pass it to `_isEndTimeInFuture`
- Update `_isEndTimeInFuture(Gig gig, DateTime nowUtc)` signature to `_isEndTimeInFuture(Gig gig, DateTime nowUtc, String bandTimezone)`
- Replace `DateTime(date, hour, min).toUtc()` with `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)`
- In `build()`: pass `fullState.band.timezone` to `_categorizeGigs`
- In `loadGigs()`: read band timezone from `ref.read(activeBandProvider).activeBand?.timezone ?? 'America/Chicago'`

### Task 17: Update rehearsal controller filtering

- Same pattern as Task 16 for `rehearsal_controller.dart`
- `_categorizeRehearsals` accepts `String bandTimezone`
- `_isEndTimeInFuture` uses `TimezoneHelper.toUtc()`
- `build()` passes `fullState.band.timezone`
- `loadRehearsals()` reads band timezone from provider

### Task 18: Update gig repository filtering

- Add `String? bandTimezone` parameter (default `'America/Chicago'`) to `fetchPotentialGigs`, `fetchConfirmedGigs`, `fetchUpcomingGigs`
- Replace inline `DateTime(...).toUtc()` with `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone ?? 'America/Chicago')`

### Task 19: Update rehearsal repository filtering

- Add `String? bandTimezone` parameter to `fetchUpcomingRehearsals` and `fetchNextRehearsal`
- Replace inline `DateTime(...).toUtc()` with `TimezoneHelper.toUtc(rehearsal.date, rehearsal.endTime, bandTimezone ?? 'America/Chicago')`

---

## 14. Verification Plan

### Engineer Validation Commands

```bash
flutter pub get
flutter analyze     # Must pass with 0 errors
flutter test        # Must pass all existing tests
flutter run -d macos  # Manual smoke test
```

### Manual Verification Steps

1. **Same-timezone test**: With device and band both in `America/Chicago`, confirm event times display identically to current behavior (no regression).

2. **Cross-timezone test**: Change device timezone to a different zone (e.g., `America/New_York`). Confirm:
   - Gig times on home dashboard show converted times (e.g., Chicago 7:30 PM → NY 8:30 PM)
   - Rehearsal times on home dashboard show converted times
   - Calendar event times show converted times
   - Event editor still shows original band-timezone times (no conversion)

3. **Midnight-crossing test**: Create an event at 11:00 PM in Chicago timezone. View from New York (should show 12:00 AM next day). Confirm the date also adjusts.

4. **Filtering test**: Create an event that just ended in the band's timezone. Confirm it disappears from the dashboard regardless of the viewer's device timezone.

5. **Availability modal test**: Trigger a potential gig availability prompt. Confirm the time shown reflects the viewer's local timezone.

6. **Fallback test**: Temporarily set a band's timezone to an invalid string. Confirm the app falls back to `'America/Chicago'` gracefully without crashes.

---

## 15. QA Regression Areas

- Home dashboard (`home_screen.dart` AND `home_tab_content.dart`): confirmed gig cards, potential gig cards, rehearsal card — time display
- Calendar view (`calendar_screen.dart` AND `calendar_tab_content.dart`): event card time display
- Day detail bottom sheet: event time display when tapping a calendar day
- Availability prompt modal: time display (triggered by `potential_gig_prompt_service.dart`)
- Event creation: MUST still work in band timezone (no conversion in editor)
- Event editing: pre-filled times MUST match stored band-timezone values
- Pull-to-refresh: events should re-render with correct timezone conversion
- Band switching: switching bands should use the new band's timezone
- Load-in time display (if shown on confirmed gig cards)
- Multi-date potential gigs: date range display
- All platforms: iOS, Android, Web, macOS

### QA Checkpoint: Caller completeness

QA should verify that `flutter analyze` produces 0 errors. Any missing `bandTimezone` argument at a call site will surface as a compile error (`missing_required_argument`). A clean analyze confirms all call sites are wired.

---

## 16. Rollout / Migration Strategy

No migration needed. The `bands.timezone` column already exists with valid IANA timezone values. The `timezone` package includes its own bundled IANA timezone database — no server-side data changes required.

**Rollout is immediate upon deploy** — all users get timezone-converted display automatically. No feature flag needed; the behavior is correct for same-timezone users (no visible change) and improved for cross-timezone users.

---

## 17. Out of Scope

- Event creation/editing timezone conversion (times continue to be entered/stored in band timezone)
- Timezone picker UI for band settings (already exists or separate feature)
- Server-side timezone conversion (not needed; client-side is sufficient)
- Calendar ICS export (already handles timezone correctly via Edge Function)
- Block-out dates (all-day events, no time conversion needed)
- Push notification time display (notifications don't include event times)
- Migration of existing time data (stored format remains TEXT 24-hour; no data migration)
- Adding timezone abbreviation labels to displayed times (e.g., "8:30 PM ET") — could be a follow-up enhancement
- Event editor changes (`event_editor_drawer.dart`, `event_form_data.dart`)
- Write-path changes (`events_repository.dart`)
- Storage format changes (TEXT 24-hour format is unchanged)
- Model semantic changes (`gig.dart`, `rehearsal.dart`, `calendar_event.dart` — `timeRange` getters retained)
- New providers, controllers, or repositories
- Unrelated calendar/home refactors

### Scope Clarification — Caller-Site Propagation

The 4 files added to the plan in the post-implementation revision (`home_tab_content.dart`, `calendar_tab_content.dart`, `day_detail_bottom_sheet.dart`, `potential_gig_prompt_service.dart`) are **not new feature scope**. They are required propagation from the approved `required String bandTimezone` constructor parameter on display widgets. Each file receives a one-line parameter addition — no conversion logic, no behavioral change, no new imports beyond what the parent already has access to. These additions do not authorize any further changes in those files.

---

## Widget Contracts (Public API)

### TimezoneHelper (new)

```dart
class TimezoneHelper {
  static void initialize();
  static DateTime toLocal(DateTime eventDate, String timeStr24, String bandTimezone);
  static DateTime toUtc(DateTime eventDate, String timeStr24, String bandTimezone);
}
```

### TimeFormatter (extended)

```dart
// Existing (unchanged):
static ParsedTime parse(String? timeStr);
static String formatRange(String? startTime, String? endTime);
static int durationMinutes(String? startTime, String? endTime);

// New:
static String formatRangeLocal(String? startTime, String? endTime, DateTime date, String bandTimezone);
```

### Card Constructors (updated)

```dart
// ConfirmedGigCard
const ConfirmedGigCard({
  required this.gig,
  required this.bandTimezone,  // NEW
  this.onTap,
  this.index = 0,
});

// PotentialGigCard
const PotentialGigCard({
  required this.gig,
  required this.bandTimezone,  // NEW
  this.onTap,
  this.width,
});

// RehearsalCard
const RehearsalCard({
  required this.rehearsal,
  required this.bandTimezone,  // NEW
  this.onTap,
  this.setlistName,
});

// CalendarEventCard
const CalendarEventCard({
  required this.event,
  required this.bandTimezone,  // NEW
  this.onTap,
});

// AvailabilityPromptModal
const AvailabilityPromptModal({
  required this.gig,
  required this.bandTimezone,  // NEW
  required this.onRespond,
});

// DayDetailBottomSheet
const DayDetailBottomSheet({
  required this.date,
  required this.events,
  required this.bandTimezone,  // NEW
  this.onEventTap,
  this.onAddEvent,
});
// static show() also accepts required String bandTimezone
```

---

## Data Flow Architecture

### Display Path (after fix)

```
Supabase DB
  │
  ├── gigs.start_time: "19:30" (TEXT, band timezone implicit)
  ├── gigs.date: "2026-03-20" (DATE)
  └── bands.timezone: "America/Chicago" (TEXT)
        │
        ▼
  bandFullStateProvider (RPC)
        │
        ├── fullState.band.timezone → "America/Chicago"
        └── fullState.gigs[i].startTime → "19:30"
              │
              ▼
  GigNotifier._categorizeGigs(gigs, bandId, bandTimezone)
        │
        ▼
  HomeScreen (parent widget)
  │  activeBand.timezone → "America/Chicago"
  │
  └── ConfirmedGigCard(gig: gig, bandTimezone: "America/Chicago")
        │
        ▼
  TimeFormatter.formatRangeLocal("19:30", "22:00", date, "America/Chicago")
        │
        ▼
  TimezoneHelper.toLocal(date, "19:30", "America/Chicago")
        │
        ├── TZDateTime(Chicago, 2026, 3, 20, 19, 30)
        ├── .toLocal() → DateTime in device TZ
        └── Format → "8:30 PM" (if device is in New York)
```

### Filtering Path (after fix)

```
  _isEndTimeInFuture(gig, nowUtc, bandTimezone)
        │
        ▼
  TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)
        │
        ├── TZDateTime(Chicago, 2026, 3, 20, 22, 0)
        └── .toUtc() → correct UTC DateTime
              │
              ▼
  endDateTimeUtc.isAfter(nowUtc) → accurate comparison
```

---

## Exact Code Locations

### Display — time formatting call sites to update

| File                             | Line(s)                    | Current Code                                                          | New Code                                                                                                               |
| -------------------------------- | -------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `confirmed_gig_card.dart`        | Time display section       | `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)` | `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`       |
| `potential_gig_card.dart`        | Non-multidate time section | `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)` | `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`       |
| `rehearsal_card.dart`            | `_formatTimeLine()`        | `TimeFormatter.formatRange(rehearsal.startTime, rehearsal.endTime)`   | `TimeFormatter.formatRangeLocal(rehearsal.startTime, rehearsal.endTime, rehearsal.date, widget.bandTimezone)`          |
| `calendar_event_card.dart`       | Time text widget           | `widget.event.timeRange`                                              | `TimeFormatter.formatRangeLocal(widget.event.startTime, widget.event.endTime, widget.event.date, widget.bandTimezone)` |
| `availability_prompt_modal.dart` | `_DetailRow` for time      | `TimeFormatter.formatRange(widget.gig.startTime, widget.gig.endTime)` | `TimeFormatter.formatRangeLocal(widget.gig.startTime, widget.gig.endTime, widget.gig.date, widget.bandTimezone)`       |

### Filtering — DateTime construction sites to update

| File                        | Method                           | Current                         | New                                                                     |
| --------------------------- | -------------------------------- | ------------------------------- | ----------------------------------------------------------------------- |
| `gig_controller.dart`       | `_isEndTimeInFuture()`           | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)`             |
| `rehearsal_controller.dart` | `_isEndTimeInFuture()`           | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(rehearsal.date, rehearsal.endTime, bandTimezone)` |
| `gig_repository.dart`       | `fetchPotentialGigs` inline      | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)`             |
| `gig_repository.dart`       | `fetchConfirmedGigs` inline      | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)`             |
| `gig_repository.dart`       | `fetchUpcomingGigs` inline       | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(gig.date, gig.endTime, bandTimezone)`             |
| `rehearsal_repository.dart` | `fetchUpcomingRehearsals` inline | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(rehearsal.date, rehearsal.endTime, bandTimezone)` |
| `rehearsal_repository.dart` | `fetchNextRehearsal` inline      | `DateTime(y,m,d,h,min).toUtc()` | `TimezoneHelper.toUtc(rehearsal.date, rehearsal.endTime, bandTimezone)` |
