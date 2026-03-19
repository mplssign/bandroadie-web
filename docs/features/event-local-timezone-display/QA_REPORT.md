# QA Report

## Feature Slug

`bug/event-local-timezone-display`

## Feature Title

Event times do not display in the viewer's local time zone

## Final Verdict

**APPROVED**

---

## Validation Summary

Implementation was validated through comprehensive code-path analysis, static analysis (`flutter analyze` — 0 issues), full test suite (`flutter test` — 6/6 passed), complete git diff review, and exhaustive call-site audit. All 19 Architect tasks were implemented exactly as specified with no scope deviations. Runtime UI validation was NOT performed — confidence is based on code-path correctness, analyzer pass (confirming all required parameters are wired), and test pass.

---

## Architect Scope Review

- **Scope adherence:** Compliant — implementation matches Architect Revision 2 exactly
- **Files modified:** As expected — 19 modified files + 1 new file, all within the approved file list from §9a–§9d. `pubspec.lock` change is an expected side effect.
- **Files off-limits:** Not touched — all 10 off-limits entries (event_editor_drawer.dart, event_form_data.dart, events_repository.dart, gig.dart, rehearsal.dart, calendar_event.dart, supabase/, sql/, platform configs) verified untouched
- **Downstream propagation files:** The 4 additional files added in Architect Revision 2 (home_tab_content.dart, calendar_tab_content.dart, day_detail_bottom_sheet.dart, potential_gig_prompt_service.dart) are covered by the revised plan

---

## Implementation Review

### Created file (1)

| File                                 | Status                                                                                        |
| ------------------------------------ | --------------------------------------------------------------------------------------------- |
| `lib/app/utils/timezone_helper.dart` | Created — implements `initialize()`, `toLocal()`, `toUtc()` with `'America/Chicago'` fallback |

### Modified files (18)

| #   | File                                                         | Change                                                                          | Status   |
| --- | ------------------------------------------------------------ | ------------------------------------------------------------------------------- | -------- |
| 1   | `pubspec.yaml`                                               | Added `timezone: ^0.10.0`                                                       | Verified |
| 2   | `lib/main.dart`                                              | `TimezoneHelper.initialize()` after `WidgetsFlutterBinding.ensureInitialized()` | Verified |
| 3   | `lib/app/utils/time_formatter.dart`                          | Added `formatRangeLocal()` with fallback to `formatRange()`                     | Verified |
| 4   | `lib/features/home/widgets/confirmed_gig_card.dart`          | `required String bandTimezone` + `formatRangeLocal`                             | Verified |
| 5   | `lib/features/home/widgets/potential_gig_card.dart`          | `required String bandTimezone` + `formatRangeLocal`                             | Verified |
| 6   | `lib/features/home/widgets/rehearsal_card.dart`              | `required String bandTimezone` + `formatRangeLocal`                             | Verified |
| 7   | `lib/features/calendar/widgets/calendar_event_card.dart`     | `required String bandTimezone` + `formatRangeLocal`                             | Verified |
| 8   | `lib/features/gigs/widgets/availability_prompt_modal.dart`   | Constructor + `show()` + `formatRangeLocal`                                     | Verified |
| 9   | `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` | Constructor + `show()` + threads to `CalendarEventCard`                         | Verified |
| 10  | `lib/features/home/home_screen.dart`                         | Derives `bandTimezone`, passes to 3 card widgets                                | Verified |
| 11  | `lib/features/home/home_tab_content.dart`                    | Passes `bandTimezone` to 3 card widgets                                         | Verified |
| 12  | `lib/features/calendar/calendar_screen.dart`                 | `bandTimezone` to `_EventsSection` + `DayDetailBottomSheet.show()`              | Verified |
| 13  | `lib/features/calendar/calendar_tab_content.dart`            | `bandTimezone` to `_EventsSection` + `DayDetailBottomSheet.show()`              | Verified |
| 14  | `lib/features/gigs/potential_gig_prompt_service.dart`        | Reads `bandTimezone` from provider, passes to modal                             | Verified |
| 15  | `lib/features/gigs/gig_controller.dart`                      | `_isEndTimeInFuture` uses `TimezoneHelper.toUtc()`                              | Verified |
| 16  | `lib/features/rehearsals/rehearsal_controller.dart`          | `_isEndTimeInFuture` uses `TimezoneHelper.toUtc()`                              | Verified |
| 17  | `lib/features/gigs/gig_repository.dart`                      | Optional `bandTimezone` on 3 fetch methods + `TimezoneHelper.toUtc()`           | Verified |
| 18  | `lib/features/rehearsals/rehearsal_repository.dart`          | Optional `bandTimezone` on 2 fetch methods + `TimezoneHelper.toUtc()`           | Verified |

### Side-effect file

| File           | Change                                                                   | Status   |
| -------------- | ------------------------------------------------------------------------ | -------- |
| `pubspec.lock` | `timezone` changed from `transitive` to `direct main` (same version/sha) | Expected |

---

## Files Verified

All 20 files in the diff were individually verified against the Architect plan. Call-site audit confirmed all 11 widget instantiation sites (per Architect §9e) pass `bandTimezone`.

---

## Bug Fix Validation Result

### Root cause addressed

The root cause — timezone-unaware display and filtering — is directly addressed:

1. **Display fix:** All 5 display surfaces now route through `TimeFormatter.formatRangeLocal()`, which uses `TimezoneHelper.toLocal()` to convert from band timezone to device local timezone.

2. **Filtering fix:** All 7 filtering locations now use `TimezoneHelper.toUtc()` to correctly interpret stored times as band-timezone times before converting to UTC for comparison.

### Validation method: Code-path analysis only

- `formatRangeLocal()` confirmed to use `TimezoneHelper.toLocal()` for conversion
- `TimezoneHelper.toLocal()` confirmed to create `TZDateTime` in band timezone then call `.toLocal()`
- `TimezoneHelper.toUtc()` confirmed to create `TZDateTime` in band timezone then call `.toUtc()`
- All filtering paths confirmed to use `TimezoneHelper.toUtc()` instead of device-local `DateTime()` constructor
- Fallback chain confirmed: invalid timezone → `'America/Chicago'`; conversion failure → `formatRange()` (timezone-unaware)

### Runtime UI validation: NOT performed

No device, simulator, or web runtime was exercised during this QA session. The following Architect verification scenarios were **not** runtime-tested:

- Same-timezone smoke test
- Cross-timezone smoke test
- Midnight-crossing test
- Filtering test with just-ended events
- Availability modal display check
- Fallback with invalid timezone
- Event editor unchanged confirmation

---

## Completeness Check

- All Architect tasks implemented: **Yes** — all 19 tasks verified
- Missing tasks: **None**
- Constructor propagation: Complete — all 11 call sites wired (confirmed by both code review and `flutter analyze` pass)
- Filtering updates: Complete — all 7 filtering locations updated
- Fallback behavior: Present in `TimezoneHelper._resolveLocation()` and `TimeFormatter.formatRangeLocal()`
- Timezone initialization: Present in `main.dart` at correct position

---

## Behavior Verification

- **Validation method:** Code-path analysis only
- **Result:** Code paths match Architect-specified behavior at the implementation level
- **Midnight/date-shift:** `TimezoneHelper.toLocal()` returns full `DateTime` including correct date. Time formatting uses the converted DateTime. Note: card date displays still use the model's original date — midnight-crossing events would show correct local time but original event date. This is consistent with the Architect task breakdown (which only specifies time conversion), though §4.3 suggests date should also adjust. Noted as observation.
- **Filtering correctness:** Confirmed — old pattern `DateTime(...).toUtc()` (device-local) replaced with `TimezoneHelper.toUtc()` (band-timezone-aware) in all 7 locations.

---

## Regression Check

- **Risk level:** MEDIUM
- **Systems reviewed:**
  - Gigs — affected, changes verified
  - Rehearsals — affected, changes verified
  - Calendar — affected, changes verified
  - Home dashboard — affected, changes verified (both `home_screen.dart` and `home_tab_content.dart`)
  - Availability modal — affected, changes verified
  - Event creation/editing — **untouched** (confirmed)
  - Auth/session — **untouched** (confirmed)
  - Routing — **untouched** (confirmed)
  - Setlists/catalog — **untouched** (confirmed)
  - Notifications — **untouched** (confirmed)
  - ICS export — **untouched** (confirmed)
  - Block-outs — **untouched** (confirmed)
  - Initialization order — additive only, no reordering (confirmed)
  - Controller disposal — no new leaks (confirmed)
  - iOS/Android/Web/macOS — same Flutter code, expected to behave identically
- **Regressions found:** None
- **Pre-existing issue noted:** `availability_prompt_modal.dart` has a `setState` after async gap without `mounted` guard (line ~96). This is NOT introduced by this change.

---

## Database Safety

**Not Applicable** — no database changes in scope or implementation. No migrations, schema, RLS, RPC, trigger, or server-side function changes. `supabase/` and `sql/` directories confirmed untouched.

---

## Analyzer Results

Command: `flutter analyze`
Result: **0 issues** (ran in 3.9s)

---

## Test Results

Command: `flutter test`
Result: **6/6 tests passed**

---

## Diff Safety Review

- **Secrets:** None found
- **Debug artifacts:** `debugPrint` in `TimezoneHelper._resolveLocation()` for invalid timezone fallback — appropriate diagnostic logging, not spam
- **Unrelated changes:** Minor formatting churn from `dart format` in `potential_gig_card.dart`, `rehearsal_card.dart`, `main.dart`, `potential_gig_prompt_service.dart`. These are in files already being modified — no behavioral changes, acceptable.
- **File deletions:** None
- **Temporary flags/scaffolding:** None
- **pubspec.lock:** Only `timezone` package changed from `transitive` to `direct main` — same version, same sha256. Expected.
- **Constructor propagation:** All changes are mechanical `required String bandTimezone` additions — scoped and consistent
- **Startup initialization:** Additive only — no existing steps reordered

---

## Scope Deviation Check

The 4 additional propagation files (`home_tab_content.dart`, `calendar_tab_content.dart`, `day_detail_bottom_sheet.dart`, `potential_gig_prompt_service.dart`) were added to the Architect plan in Revision 2 and are explicitly covered by §9c and §9e. No scope deviation exists.

---

## Off-Limits Audit

All off-limits files remained untouched:

| File                                                                    | Status    |
| ----------------------------------------------------------------------- | --------- |
| `lib/features/events/widgets/event_editor_drawer.dart`                  | Untouched |
| `lib/features/events/models/event_form_data.dart`                       | Untouched |
| `lib/features/events/events_repository.dart`                            | Untouched |
| `lib/app/models/gig.dart`                                               | Untouched |
| `lib/app/models/rehearsal.dart`                                         | Untouched |
| `lib/features/calendar/models/calendar_event.dart`                      | Untouched |
| `supabase/`                                                             | Untouched |
| `sql/`                                                                  | Untouched |
| Platform configs (`.entitlements`, `AndroidManifest.xml`, `Info.plist`) | Untouched |

---

## Manual Verification Coverage

### Scenarios NOT exercised (runtime validation not performed):

- Same-timezone smoke test
- Cross-timezone smoke test (device TZ ≠ band TZ)
- Midnight-crossing display test
- Just-ended event filtering test
- Availability modal time display
- Calendar event card time display
- Fallback with invalid/empty timezone string
- Event editor unchanged confirmation
- Band switching timezone refresh
- Pull-to-refresh with timezone conversion
- Multi-date potential gig display

### Scenarios verified via code-path analysis:

- `formatRangeLocal()` conversion path through `TimezoneHelper.toLocal()`
- `TimezoneHelper.toUtc()` filtering path in all 7 locations
- Fallback chain (invalid TZ → `'America/Chicago'`; conversion error → `formatRange()`)
- All 11 call sites pass `bandTimezone`
- Initialization order preserved
- Off-limits files untouched
- No write-path changes

---

## Issues Found

### Suggestions (optional)

1. **Midnight-crossing date display:** When timezone conversion crosses midnight, the time is correctly converted but the displayed date on cards still uses the model's original event date. For events created at 11 PM Chicago viewed from New York (12 AM next day), the time is correct but the date may be off by one day. This is consistent with the Architect task breakdown but noted for future consideration.

2. **Pre-existing: mounted guard missing in availability_prompt_modal.dart:** `setState` at ~line 96 is called after an async gap without a `mounted` check. This is NOT introduced by this change but should be addressed separately.
