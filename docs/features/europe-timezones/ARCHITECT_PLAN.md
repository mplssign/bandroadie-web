# ARCHITECT_PLAN.md — feature/europe-timezones

**Date:** 2026-06-11  
**Status:** Ready for Engineering  
**Confidence:** HIGH

---

## 1. Feature Slug

`feature/europe-timezones`

---

## 2. Problem Summary

The timezone location screen (band creation/edit form) currently offers only a single "United Kingdom" entry representing all of Europe, with no regional grouping or expansion. Users outside North America have extremely limited options: only London (UK) is available. The feature input requests expanding Europe to 15 distinct city entries, each with the correct IANA timezone identifier, organized under a new "Europe" section header that mirrors the existing "United States" and "Canada" grouping pattern.

**Current state:**

- United Kingdom section with 1 entry: `Europe/London` → "London"

**Desired state:**

- Europe section (new header) with 15 entries covering major European timezones (London, Lisbon, Paris, Berlin, Rome, Madrid, Amsterdam, Stockholm, Warsaw, Athens, Helsinki, Bucharest, Kyiv, Moscow, Istanbul)

---

## 3. Root Cause

**Confidence: HIGH**

**Root cause:** Timezone picker design was initially sparse and region-specific. The `_timezoneOptions` list in [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L1887) was built for North American use cases (US and Canada). A recent feature (contacts-venues-followup) established the grouped structure pattern and added Canada entries. Europe was not expanded at that time, leaving only the UK entry as a placeholder.

**Evidence:**

- Code audit of [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L1887-L1913) confirms the list structure supports grouping via `'isHeader': true` flag.
- Existing headers (United States, Canada, United Kingdom) use the same pattern.
- Database schema already uses `TEXT` type for `timezone` column with `'America/Chicago'` default; no migration required.
- Edge function `calendar-feed` already has VTIMEZONE definitions for multiple European timezones (`Europe/London`, `Europe/Paris`, `Europe/Berlin`, etc.), confirming system readiness.

---

## 4. Reference Docs Consulted

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart) — timezone picker implementation (lines 1887–1950)
- [docs/features/contacts-venues-followup/ARCHITECT_PLAN.md](docs/features/contacts-venues-followup/ARCHITECT_PLAN.md) — established grouping pattern for Canada
- [supabase/functions/calendar-feed/index.ts](supabase/functions/calendar-feed/index.ts#L332+) — confirms VTIMEZONE availability for European zones
- [docs/reference/architecture/database_schema.md](docs/reference/architecture/database_schema.md) — bands table schema
- Copilot instructions: `BAND_ROADIE_DOCUMENTATION.md` — band structure and feature conventions

---

## 5. Existing System Analysis

### Current Timezone Picker Structure

The picker in [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L1887-L1913) implements a **grouped dropdown** using:

- `static const List<Map<String, dynamic>> _timezoneOptions` with 19 entries
- **Header entries:** `{'value': null, 'label': 'Region Name', 'isHeader': true}` — rendered as disabled items with separator styling
- **Timezone entries:** `{'value': 'IANA/Identifier', 'label': 'City (Zone Description)'}` — selectable with actual timezone IDs
- **Renderer:** [lines 1976–1984](lib/features/bands/band_form_screen.dart#L1976) filters headers and disables them:
  ```dart
  final isHeader = tz['isHeader'] == true;
  return DropdownMenuItem<String>(
    value: isHeader ? null : tz['value'] as String,
    enabled: !isHeader,
    // ...
  );
  ```

### Existing Grouping Pattern (for reference)

Current structure:

1. **United States** (header) + 6 entries (New York, Chicago, Denver, Phoenix, Los Angeles, Anchorage, Honolulu)
2. **Canada** (header) + 6 entries (Vancouver, Edmonton, Dawson Creek, Creston, Regina, Toronto, Halifax, St. John's, Whitehorse)
3. **United Kingdom** (header) + 1 entry (London)

### Data Flow

- **Timezone storage:** `bands.timezone` column stores IANA identifier as `TEXT`
- **Default on creation:** `'America/Chicago'`
- **Validation on form init:** [lines 1913–1917](lib/features/bands/band_form_screen.dart#L1913) filter out headers and fallback to default if not found
- **Persistence:** Selected value saved to Supabase via `bandController.updateBand()`

### Filtering & Display

Timezone value is used across the app:

- Calendar feed generation (Supabase edge function): `calendar-feed/index.ts` expects valid IANA identifiers
- Event display: `TimeFormatter.formatRangeLocal()` reads band timezone for display conversion
- Phone formatting logic: Helpers like `isUSTimezone()`, `isCanadianTimezone()` in [lib/shared/utils/phone_input_formatter.dart](lib/shared/utils/phone_input_formatter.dart)

---

## 6. Proposed Solution

**Approach:** Replace the single "United Kingdom" header+entry with a new "Europe" header followed by 15 city entries, each mapped to the correct IANA timezone identifier. No data migration needed (existing "United Kingdom" entry already used `Europe/London`). Reuse the existing grouping pattern and renderer without code changes.

### Data Structure for Europe Section

Insert the following **after the Canada section** and **before the United Kingdom section is removed**:

```dart
// Europe
{'value': null, 'label': 'Europe', 'isHeader': true},
{'value': 'Europe/London', 'label': 'London'},
{'value': 'Europe/Lisbon', 'label': 'Lisbon'},
{'value': 'Europe/Paris', 'label': 'Paris'},
{'value': 'Europe/Berlin', 'label': 'Berlin'},
{'value': 'Europe/Rome', 'label': 'Rome'},
{'value': 'Europe/Madrid', 'label': 'Madrid'},
{'value': 'Europe/Amsterdam', 'label': 'Amsterdam'},
{'value': 'Europe/Stockholm', 'label': 'Stockholm'},
{'value': 'Europe/Warsaw', 'label': 'Warsaw'},
{'value': 'Europe/Athens', 'label': 'Athens'},
{'value': 'Europe/Helsinki', 'label': 'Helsinki'},
{'value': 'Europe/Bucharest', 'label': 'Bucharest'},
{'value': 'Europe/Kyiv', 'label': 'Kyiv'},
{'value': 'Europe/Moscow', 'label': 'Moscow'},
{'value': 'Europe/Istanbul', 'label': 'Istanbul'},
```

**IANA Identifier Verification:**

- All identifiers use the standard IANA Timezone Database format (see IANA TZ database for authoritative definitions).
- `Europe/Kyiv` is the modern, current identifier (superseding deprecated `Europe/Kiev`); confirmed supported by Flutter's `timezone` package and Dart's system.
- All identifiers are already known to the backend (present in edge function `calendar-feed/index.ts` VTIMEZONE definitions).

### Widget Pattern Reuse

- No changes to dropdown renderer (existing code already handles `isHeader` flag correctly).
- Fallback logic remains unchanged (filter headers on init).
- Label and helper text unchanged (already generic: "Timezone Location" and "Used for general formatting and calendar feeds").

### Removal of Old UK Entry

- Delete the old standalone **United Kingdom** section (1 header + 1 entry) that immediately follows Canada.
- Consolidate into the new "Europe" section with London as one of 15 entries.

---

## 7. Database Impact

**Status: NO MIGRATION REQUIRED**

**Rationale:**

- The old "United Kingdom" entry stored `Europe/London` in the `bands.timezone` column.
- The new "Europe" section also maps London to `Europe/London` (identical value).
- Existing bands with `timezone = 'Europe/London'` will continue to resolve correctly with zero data loss.
- No column schema changes needed; `TEXT` type accommodates all IANA identifiers.
- No RLS, RPC, or trigger changes required.

**Verification:**

- Historical data query: Any band with `timezone = 'Europe/London'` will still work seamlessly.
- Forward compatibility: All 15 new entries are valid IANA identifiers supported by the system.

---

## 8. Flutter Architecture Changes

**Status: MINIMAL — DATA-ONLY CHANGE**

The timezone picker is a **pure data-driven dropdown**. No controller, state, repository, or business logic changes needed.

### Files Affected

| File                                       | Change Type       | Scope                                             |
| ------------------------------------------ | ----------------- | ------------------------------------------------- |
| `lib/features/bands/band_form_screen.dart` | Data modification | Replace `_timezoneOptions` list (lines 1887–1913) |

### What Does NOT Change

- `_buildTimezoneSection()` method logic (lines 1917–1950): renders as-is
- Dropdown renderer (lines 1976–1984): filter/disable headers unchanged
- Form validation/save flow: unchanged
- Initial value logic (lines 1913–1917): unchanged
- Band controller and repository: unchanged
- No new providers, notifiers, or controllers

---

## 9. Files to Create

**None.** All work is data-driven within existing structures.

---

## 10. Files to Modify

### 10.1 `lib/features/bands/band_form_screen.dart`

**Location:** Lines 1887–1913 (the `_timezoneOptions` static list)

**Exact change:**

Replace this:

```dart
  // United Kingdom
  {'value': null, 'label': 'United Kingdom', 'isHeader': true},
  {'value': 'Europe/London', 'label': 'London'},
];
```

With this:

```dart
  // Europe
  {'value': null, 'label': 'Europe', 'isHeader': true},
  {'value': 'Europe/London', 'label': 'London'},
  {'value': 'Europe/Lisbon', 'label': 'Lisbon'},
  {'value': 'Europe/Paris', 'label': 'Paris'},
  {'value': 'Europe/Berlin', 'label': 'Berlin'},
  {'value': 'Europe/Rome', 'label': 'Rome'},
  {'value': 'Europe/Madrid', 'label': 'Madrid'},
  {'value': 'Europe/Amsterdam', 'label': 'Amsterdam'},
  {'value': 'Europe/Stockholm', 'label': 'Stockholm'},
  {'value': 'Europe/Warsaw', 'label': 'Warsaw'},
  {'value': 'Europe/Athens', 'label': 'Athens'},
  {'value': 'Europe/Helsinki', 'label': 'Helsinki'},
  {'value': 'Europe/Bucharest', 'label': 'Bucharest'},
  {'value': 'Europe/Kyiv', 'label': 'Kyiv'},
  {'value': 'Europe/Moscow', 'label': 'Moscow'},
  {'value': 'Europe/Istanbul', 'label': 'Istanbul'},
];
```

**List size change:**

- Old: 19 entries total (6 US + 6 Canada + 1 UK header + 1 UK city = 14 data + 3 headers)
- New: 32 entries total (6 US + 6 Canada + 1 Europe header + 15 Europe cities = 28 data + 4 headers)

**No other changes to this file are required.**

---

## 11. Files Off-Limits

| File                                          | Reason                                                                                   |
| --------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `lib/main.dart`                               | Initialization order must not change; no timezone initialization needed for this feature |
| `supabase/migrations/`                        | No data normalization needed; existing data already uses correct identifier              |
| `supabase/functions/calendar-feed/index.ts`   | VTIMEZONE definitions already present; no edge function changes required                 |
| `lib/app/utils/timezone_helper.dart`          | Fallback logic unchanged; no timezone conversion logic touches this feature              |
| `lib/shared/utils/phone_input_formatter.dart` | Phone formatting logic not affected by expanded timezone list                            |
| `pubspec.yaml`                                | No new dependencies required                                                             |

---

## 12. System Impact Map

| System                                       | Status           | Impact                                    | Notes                                           |
| -------------------------------------------- | ---------------- | ----------------------------------------- | ----------------------------------------------- |
| Band creation form                           | **Affected**     | Expanded picker options                   | UI only; no logic change                        |
| Band edit form                               | **Affected**     | Expanded picker options                   | UI only; same form                              |
| Existing bands (Europe/London)               | **Not affected** | Seamless                                  | Timezone value unchanged; continues to work     |
| Calendar feed (edge function)                | **Not affected** | Already supports                          | VTIMEZONE definitions present                   |
| TimeFormatter (event display)                | **Not affected** | Fallback ready                            | `TimezoneHelper` handles invalid IDs gracefully |
| Phone formatting                             | **Not affected** | User would need manual timezone detection | Not in scope; no new helpers added              |
| Authentication/RLS                           | **Not affected** | No schema/permission changes              | Band timezone is not auth-sensitive             |
| Database schema                              | **Not affected** | TEXT column sufficient                    | No migration needed                             |
| Other regions (Asia-Pacific, Americas, etc.) | **Not affected** | No changes                                | Future regions can follow same pattern          |

---

## 13. Regression Risk

**Overall Risk: LOW**

**Rationale:**

1. **Data-only change:** No code logic touched; purely a static list update.
2. **Existing pattern reused:** Europe section uses identical structure as Canada (header + entries).
3. **Backward compatible:** Existing `Europe/London` value persists; no remapping or migration.
4. **Renderer unchanged:** Dropdown builder handles headers correctly already.
5. **No new dependencies or features:** No timezone library calls added; IANA identifiers are standard.
6. **Isolated to band form:** Change confined to single form; no cascading effects to other screens.
7. **Valid IANA identifiers:** All 15 entries are recognized by backend and system timezone libraries.

**Potential edge cases (mitigated):**

- User selects new Europe timezone → saved correctly as IANA identifier → displayed correctly by existing renderers (tested pattern)
- Band switches from Europe timezone to US → fallback logic handles it (unchanged)
- Future app upgrade with bands storing old "United Kingdom" → value `Europe/London` still valid (no data loss)

---

## 14. Engineer Task Breakdown

### Task 1: Update `_timezoneOptions` List

**File:** `lib/features/bands/band_form_screen.dart` (lines 1887–1913)

**Action:** Replace the **United Kingdom section (2 lines)** with the **Europe section (16 lines)** per the exact change specified in Section 10.1.

**Verification:**

- List compiles without syntax errors
- All 15 entries are present with correct IANA identifiers
- `isHeader: true` flag present on Europe header entry
- No accidental whitespace/formatting changes to surrounding code

### Task 2: Manual Testing

**Steps:**

1. Open the band creation form (BandFormScreen)
2. Scroll the timezone picker dropdown
3. Verify "Europe" section appears as a disabled header (grayed out, non-selectable)
4. Verify all 15 city entries appear below the header and are selectable
5. Select "London" (Europe/London) and create/save a test band
6. Verify the band was created with timezone = "Europe/London"
7. Edit the band and confirm "London" is pre-selected in the dropdown
8. Select a different Europe city (e.g., "Paris") and save
9. Verify the timezone updated to "Europe/Paris"
10. Verify no other regions (US, Canada) are affected

### Task 3: Code Review Checklist

- [ ] `_timezoneOptions` list contains all 19 entries (6 US + 6 Canada + 4 Europe headers/cities)
- [ ] No syntax errors; list compiles
- [ ] All IANA identifiers are correctly spelled (e.g., `Europe/Kyiv` not `Europe/Kiev`)
- [ ] Header entries have `'isHeader': true` and `'value': null`
- [ ] City entries have `'value': 'IANA/Identifier'` and `'label': 'City Name'`
- [ ] No unintended changes to surrounding methods or fields

---

## 15. Verification Plan

### Compile & Lint

```bash
cd <PROJECT_ROOT>
flutter analyze
flutter pub get
```

Expected: No errors or warnings introduced.

### Manual UI Verification

1. **Band Creation Flow:**
   - Launch app in emulator/simulator
   - Navigate to band creation screen
   - Tap timezone dropdown
   - Verify sections appear in order: United States, Canada, Europe
   - Verify "Europe" section is visually distinct (disabled header style)
   - Scroll and select "Paris" (Europe/Paris)
   - Complete band creation
   - Check Supabase: band.timezone should be "Europe/Paris"

2. **Band Edit Flow:**
   - Open an existing band edit form
   - Verify timezone dropdown shows currently selected value
   - Switch to a different Europe timezone (e.g., Berlin)
   - Save and verify Supabase updates the timezone field

3. **Existing Band Compatibility:**
   - Create a test band with timezone "Europe/London" via Supabase directly
   - Open that band in the form
   - Verify "London" is selected in the dropdown (not showing as a mismatch)

### Regression Testing (Existing Regions)

- [ ] US timezone picker entries unchanged; all 6 are still selectable
- [ ] Canada timezone picker entries unchanged; all 6 are still selectable
- [ ] Creating/editing bands with US timezones works as before
- [ ] Creating/editing bands with Canada timezones works as before
- [ ] Timezone values persist correctly to database

### Automated Testing (Not Applicable)

No unit tests required for this data-only change. Existing widget tests for BandFormScreen (if present) should pass without modification.

---

## 16. QA Regression Areas

### Forms & Persistence

- [ ] Band creation with each US timezone saves correctly
- [ ] Band creation with each Canada timezone saves correctly
- [ ] Band creation with each new Europe timezone saves correctly
- [ ] Band edit changes timezone correctly
- [ ] Switching between regions (US → Canada → Europe) works smoothly
- [ ] Fallback to 'America/Chicago' activates if invalid timezone in DB

### Event Display (Calendar/Home)

- [ ] Calendar generation for bands with Europe timezones works without error
- [ ] Events display correct times for Europe timezone bands
- [ ] Phone formatting still works for supported zones

### Cross-Platform

- [ ] iOS: Dropdown renders and selects correctly
- [ ] Android: Dropdown renders and selects correctly
- [ ] macOS: Dropdown renders and selects correctly
- [ ] Web: Dropdown renders and selects correctly

### Edge Cases

- [ ] Bands with legacy `Europe/London` value continue to display correctly
- [ ] Switching a band from Europe to US timezone doesn't break other features
- [ ] Timezone picker remains responsive with larger list (32 vs 19 entries)

---

## 17. Rollout / Migration Strategy

**Strategy: Direct Deploy — No Phased Rollout Needed**

### Pre-Deployment

- [ ] Code review approved
- [ ] All verification tests pass
- [ ] No database migrations required

### Deployment Steps

1. Merge feature branch to `main`
2. Run `flutter build web --release` (or `flutter build ipa`/`flutter build apk` as needed)
3. Deploy updated app to distribution channels (App Store, Google Play, web)

### Post-Deployment Verification

- [ ] App stores accept updated build
- [ ] Band creation/edit continues to work
- [ ] Spot-check: Create a test band with a Europe timezone via the new UI
- [ ] Verify timezone persists and displays correctly

### Rollback Plan

If critical issue discovered:

1. Revert commit: `git revert <merge-commit>`
2. Redeploy previous stable build
3. Impact: Users who selected Europe timezones in the narrow window will fallback to 'America/Chicago' on next app load (acceptable; low likelihood)

---

## 18. Out of Scope

The following are **explicitly NOT** part of this feature:

1. **Phone number formatting for European regions** — Currently limited to US/Canada/UK detection. Future feature can extend `isEuropeanTimezone()` helper in `phone_input_formatter.dart`

2. **Additional regions (Asia-Pacific, Americas beyond North America, Africa, etc.)** — Each region can follow the same pattern in future sprints

3. **Currency, language, or locale adaptation** — Timezone selection does not drive localization preferences

4. **Backend calendar feed updates** — VTIMEZONE definitions for Europe already present; no edge function changes needed

5. **Timezone migration for legacy bands** — Existing "United Kingdom" entry already stored `Europe/London`; no data cleansing required

6. **Broad timezone picker redesign** — Only section header typography/color changes are included; no layout or interaction redesign

---

## 19. Amendment — Timezone Section Header Styling (2026-06-11)

### Amendment Summary

Style the timezone section header labels (`isHeader: true` entries for United States, Canada, Europe) to be visually distinct from selectable city rows by making them larger, bolder, and rose-colored using the design-system lighter rose token.

### Design Token Source

- `BrandColors.primaryLight` in `lib/app/theme/brand_colors.dart`
- Value: `Color(0xFFFB7185)`

### Implementation Scope

- UI-only change in the timezone dropdown item builder in `lib/features/bands/band_form_screen.dart`
- No data model, migration, backend, RPC, or repository changes
- No behavior changes to selectability, persistence, or ordering

### File Impact (Amendment)

| File                                       | Change                                                                                                                  |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| `lib/features/bands/band_form_screen.dart` | Update header `TextStyle` for `isHeader: true` entries to `primaryLight`, `fontSize: 18`, `fontWeight: FontWeight.w800` |

---

## Revision History

| Date       | Author    | Change                                                                                        |
| ---------- | --------- | --------------------------------------------------------------------------------------------- |
| 2026-06-11 | Architect | Initial plan — Europe timezone expansion (15 entries, no migration)                           |
| 2026-06-11 | Architect | Amendment — timezone section headers styled larger, bolder, and lighter rose (`primaryLight`) |
