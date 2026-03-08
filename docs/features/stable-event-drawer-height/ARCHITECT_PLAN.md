# ARCHITECT PLAN — Stable Event Drawer Height

**Feature Slug:** `feature/stable-event-drawer-height`
**Branch:** `feature/stable-event-drawer-height`
**Feature Type:** feature
**Date:** 2026-03-08

---

## 1. Problem Summary

The Add/Edit Event bottom drawer dynamically resizes its height based on content. When the user toggles between event types (Rehearsal, Gig, Block Out), the visible form fields change — Rehearsal and Gig have significantly more fields than Block Out. Because the outer `Column` uses `MainAxisSize.min`, the drawer shrinks to fit shorter content, causing a visible layout jump.

Additionally, `event_editor_drawer.dart` is 4546 lines, containing the entire event editor UI, all form field builders, state management, Supabase queries, autocomplete logic, RBAC checks, and save/delete operations in a single file. This makes the file difficult to maintain, debug, and safely modify with AI agents.

---

## 2. Existing System Analysis

### File Structure

```
lib/features/events/
├── models/event_form_data.dart          # EventType, RecurrenceConfig, EventFormData
├── events_repository.dart               # CRUD for rehearsals + gigs, 5-min TTL cache
├── widgets/
│   ├── event_editor_drawer.dart         # 4546 lines — ALL event editor UI + logic
│   ├── add_edit_event_bottom_sheet.dart  # Thin wrapper: showModalBottomSheet → EventEditorDrawer
│   └── button_group_grid.dart           # Reusable toggle grid (selection + availability)
```

### Drawer Architecture (Current)

The drawer is shown via `AddEditEventBottomSheet.show()` which calls:

```dart
showModalBottomSheet<bool>(
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => EventEditorDrawer(...)
)
```

`EventEditorDrawer` is a `ConsumerStatefulWidget`. Its build method returns:

```
Container(maxHeight: 90% of screen)
  └─ Column(mainAxisSize: MainAxisSize.min)    ← ROOT CAUSE
       ├─ Drag handle (fixed)
       ├─ Header row (fixed)
       ├─ Flexible(child: SingleChildScrollView)  ← scrollable form region
       │   └─ Column of form fields (conditional on _eventType)
       └─ Bottom buttons (sticky, keyboard-aware)
```

### Height Behavior

- `Container` constrains max height to 90% of screen via `BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9)`
- The outer `Column` uses `mainAxisSize: MainAxisSize.min`, which **shrink-wraps** content
- The scrollable `Flexible` region takes remaining space, with 100dp bottom padding for button overlay
- Bottom action buttons sit outside the scroll area, pinned with keyboard and safe area padding

### Event Type Toggle

- Three types: Rehearsal, Gig, Block Out (enum `EventType` in `event_form_data.dart`)
- Toggle is disabled in edit mode (cannot change type after creation)
- RBAC: Contributors cannot create Rehearsals

### Form Fields by Event Type

**Shared (all types):** Date, Start Time, Duration, Location/City, Setlist, Notes
**Rehearsal-only:** Recurring toggle + animated recurring section (days, frequency, until date)
**Gig-only:** Name (autocomplete), Potential Gig section (member grid, availability, multi-date), Load-in Time, Gig Pay
**Block Out:** Only shared fields (significantly less content)

### State Management

`_EventEditorDrawerState` contains 60+ state variables covering:

- Basic event data (type, date, time, duration, location, notes)
- Recurring data (days, frequency, until date, animation controllers)
- Potential gig data (member IDs, availability maps, multi-date)
- Load-in time (hour, minutes, AM/PM — all nullable)
- Gig pay (CurrencyInputController)
- Autocomplete (suggestions lists, debounce timers, focus nodes)
- UI flags (isSaving, isDeleting, isDirty, errorMessage, fieldErrors)
- Hint controllers (venue, city, location, notes)

### Provider Dependencies

**Watched:** `membersProvider`, `setlistsProvider`
**Read:** `currentUserPermissionsProvider`, `gigResponseRepositoryProvider`, `eventsRepositoryProvider`, `gigProvider.notifier`, `rehearsalProvider.notifier`, `calendarProvider.notifier`, `potentialGigResponseSummariesProvider`, `blockOutRepositoryProvider`, `activeBandIdProvider`

### Supabase Integrations

**Direct queries (in the widget):**

1. Location autocomplete → `rehearsals` table
2. Gig name autocomplete → `gigs` table
3. Gig city autocomplete → `gigs` table

**Repository calls:** `createRehearsal`, `updateRehearsal`, `deleteRehearsal`, `deleteRehearsalSeries`, `createGig`, `updateGig`, `deleteGig`, `invalidateCache`
**Gig Response calls:** `fetchUserResponse`, `fetchAllMemberResponses`, `fetchAllDateResponses`, `upsertResponse`, `upsertResponseForDate`

### Callers (all use AddEditEventBottomSheet.show)

- `home_screen.dart` (3 call sites)
- `home_tab_content.dart` (3 call sites)
- `calendar_screen.dart` (3 call sites)
- `calendar_tab_content.dart` (4 call sites)

All callers go through the `AddEditEventBottomSheet` wrapper. No caller directly instantiates `EventEditorDrawer`.

### Migration Impact Analysis

Recent migrations (March 2026):

- `20260305100000_fix_rehearsal_rls_and_trigger.sql` — Fixes rehearsal RLS policies and trigger column names. No event editor impact.
- `20260305000000_band_scoped_calendar.sql` — Adds calendar subscription table. No event editor impact.
- `20260302000000_band_user_roles.sql` — RBAC role system. Already integrated into event editor via `currentUserPermissionsProvider`.

**Conclusion:** No pending or recent migrations affect this feature. No database changes are required.

---

## 3. Root Cause

**Height instability:** The outer `Column` in `EventEditorDrawer.build()` uses `mainAxisSize: MainAxisSize.min` (line 1370). This causes the Column to shrink-wrap to its content height. When the event type changes from a field-heavy type (Rehearsal/Gig) to a field-light type (Block Out), the content height decreases and the drawer visibly shrinks.

The `Container` provides a `maxHeight` constraint of 90%, but `MainAxisSize.min` prevents the Column from expanding to fill that constraint. It only fills as much as its children need.

**File size:** All UI, state, logic, queries, and builders are in one 4546-line class — `_EventEditorDrawerState`. There is no decomposition into sub-widgets.

---

## 4. Proposed Solution

### Part A: Stable Drawer Height

**Change the outer Column from shrink-wrap to fill-available:**

Replace `mainAxisSize: MainAxisSize.min` with no explicit mainAxisSize (defaults to `MainAxisSize.max`), which causes the Column to fill the maxHeight constraint (90% screen).

This single change stabilizes the drawer height because:

- The Container already constrains max height to 90%
- The `Flexible` child with `SingleChildScrollView` already handles scrollable content
- Shorter content (Block Out) will have empty scrollable space below the form — the drawer height stays constant
- Bottom buttons remain pinned via the sticky container outside the scroll area

**No other layout changes required.** The existing Flexible + SingleChildScrollView + bottom button architecture already supports this behavior — only the `MainAxisSize.min` prevents it from working correctly.

### Part B: File Decomposition

Extract `event_editor_drawer.dart` (4546 lines) into a container shell (~350 lines) plus focused sub-widget files.

**Architecture pattern:** Callback-based extraction. The parent `_EventEditorDrawerState` retains all state variables and provides data + callbacks to extracted StatelessWidget children. This avoids premature state management refactoring while achieving the file size and separation goals.

**Why not extract state into a Riverpod controller?** The 60+ state variables include TextEditingControllers, AnimationControllers, FocusNodes, and debounce timers — all tied to the widget lifecycle. Moving these to a Riverpod Notifier would require significant lifecycle management changes with high regression risk. The callback-based extraction achieves the maintainability goal with minimal risk.

**Target file structure:**

```
lib/features/events/widgets/
├── event_editor_drawer.dart          # Container shell (~350 lines)
│                                      # Owns: all state, initState, dispose, build scaffold
│                                      # Delegates: form rendering to sub-widgets
│
├── event_type_selector.dart          # Event type toggle (Rehearsal/Gig/Block Out)
│                                      # ~120 lines
│
├── event_form_fields.dart            # Shared form fields (date, time, duration, notes)
│                                      # ~600 lines
│
├── rehearsal_form_fields.dart        # Rehearsal-specific: location autocomplete,
│                                      # recurring toggle + section
│                                      # ~450 lines
│
├── gig_form_fields.dart              # Gig-specific: name autocomplete, city autocomplete,
│                                      # potential gig section, load-in time, gig pay,
│                                      # member availability, multi-date
│                                      # ~1200 lines
│
├── event_editor_actions.dart         # Save/Cancel/Delete/Close buttons
│                                      # ~250 lines
│
├── event_editor_helpers.dart         # Shared private widgets: _AvailabilityButton,
│                                      # _MemberDisambiguation, dropdown/ampm builders,
│                                      # text field builder, setlist selector
│                                      # ~600 lines
│
├── add_edit_event_bottom_sheet.dart   # UNCHANGED — backward compat wrapper
└── button_group_grid.dart             # UNCHANGED — reusable toggle grid
```

**Data flow pattern for extracted widgets:**

Each extracted widget receives:

- Current state values as constructor parameters (e.g., `selectedDate`, `eventType`, `isSaving`)
- Callback functions for mutations (e.g., `onDateChanged`, `onEventTypeChanged`, `onSave`)
- `WidgetRef` only when the widget needs direct provider access (e.g., gig form fields need `membersProvider`, `setlistsProvider`)

Example signature:

```dart
class EventTypeSelector extends StatelessWidget {
  final EventType selectedType;
  final bool isEditMode;
  final bool isSaving;
  final bool isContributor;
  final ValueChanged<EventType> onTypeChanged;
  ...
}
```

---

## 5. Database Impact

**None.** This is a pure Flutter UI refactor. No tables, columns, constraints, triggers, or data are affected.

---

## 6. RLS / RPC Changes

**None.** No RLS policies or RPC functions are modified. RBAC permission checks (`currentUserPermissionsProvider`) move with the form widgets but the logic is identical.

---

## 7. Flutter Architecture Changes

### 7.1 Layout Change

| Property                  | Before                              | After                                            |
| ------------------------- | ----------------------------------- | ------------------------------------------------ |
| Outer Column mainAxisSize | `MainAxisSize.min`                  | `MainAxisSize.max` (default)                     |
| Drawer height behavior    | Shrinks to content                  | Fills 90% constraint                             |
| Scrollable area behavior  | Only scrolls when content overflows | Always scrollable, empty space for short content |
| Bottom buttons            | Pinned at bottom of content         | Pinned at bottom of 90% container                |

### 7.2 File Decomposition

**Parent retains:**

- All state variables (60+)
- `initState()` / `dispose()` lifecycle
- `_buildFormData()` — aggregates state into `EventFormData`
- `_handleSave()` / `_handleDelete()` — repository calls + provider invalidation
- `_markDirty()` — change tracking
- All autocomplete query methods (they mutate state)
- All availability loading methods
- `build()` — assembles the container shell and delegates to sub-widgets

**Extracted to sub-widgets:**

- Event type toggle → `EventTypeSelector`
- Shared form fields (date, time, duration, setlist, notes) → `EventFormFields`
- Rehearsal-specific fields (location autocomplete, recurring) → `RehearsalFormFields`
- Gig-specific fields (name, city, potential gig, load-in, pay) → `GigFormFields`
- Bottom action buttons → `EventEditorActions`
- Shared builder helpers (dropdown, AM/PM, text field) → `event_editor_helpers.dart`

### 7.3 Provider Access Pattern

Extracted widgets that need `ref` (for `membersProvider`, `setlistsProvider`) should be `ConsumerWidget` or receive the data pre-resolved from the parent. The preferred approach:

- `EventFormFields` (setlist selector watches `setlistsProvider`) → `ConsumerWidget`
- `GigFormFields` (member grid watches `membersProvider`) → `ConsumerWidget`
- All other extracted widgets → `StatelessWidget` with callbacks

### 7.4 Backward Compatibility

- `AddEditEventBottomSheet.show()` API is **unchanged**
- `EventEditorDrawer` public constructor is **unchanged**
- `EventEditorMode` enum is **unchanged**
- All 13 caller sites continue to work without modification

---

## 8. Exact Files to Create

| File                                                     | Purpose                                                    | Estimated Lines |
| -------------------------------------------------------- | ---------------------------------------------------------- | --------------- |
| `lib/features/events/widgets/event_type_selector.dart`   | Event type toggle widget                                   | ~120            |
| `lib/features/events/widgets/event_form_fields.dart`     | Shared form fields (date, time, duration, setlist, notes)  | ~600            |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | Rehearsal-specific form fields                             | ~450            |
| `lib/features/events/widgets/gig_form_fields.dart`       | Gig-specific form fields                                   | ~1200           |
| `lib/features/events/widgets/event_editor_actions.dart`  | Save/Cancel/Delete/Close buttons                           | ~250            |
| `lib/features/events/widgets/event_editor_helpers.dart`  | Shared builder widgets (dropdown, AM/PM, text field, etc.) | ~600            |

---

## 9. Exact Files to Modify

| File                                                   | Change                                                                                                                                                                                                                     | Risk                                                          |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `lib/features/events/widgets/event_editor_drawer.dart` | 1. Remove `mainAxisSize: MainAxisSize.min` from outer Column (line 1370). 2. Replace inline builder methods with extracted widget instantiations. 3. Remove extracted builder method bodies. Target: ~350 lines remaining. | MEDIUM — largest change surface, must verify all state wiring |

**Files NOT modified:**

- `add_edit_event_bottom_sheet.dart` — No changes
- `button_group_grid.dart` — No changes
- `event_form_data.dart` — No changes
- `events_repository.dart` — No changes
- All caller files (home_screen, calendar_screen, etc.) — No changes

---

## 10. Risks / Edge Cases

### Risk 1: State Synchronization (MEDIUM)

**Risk:** Extracted widgets receive state via constructor params. If a callback mutates state in the parent but the child doesn't rebuild, form data could become stale.
**Mitigation:** Parent calls `setState()` in all callbacks — standard Flutter rebuild propagation ensures children receive updated props. No special synchronization needed.

### Risk 2: Provider Access in Extracted Widgets (LOW)

**Risk:** Extracted ConsumerWidgets need the same `ref` context as the parent.
**Mitigation:** ConsumerWidget provides its own `ref`. Alternatively, pre-resolve provider data in parent and pass as constructor params.

### Risk 3: Animation Controller Scope (LOW)

**Risk:** The recurring section uses `_recurringAnimController` with `SlideTransition` and `FadeTransition`. These are tied to `SingleTickerProviderStateMixin` on the parent state.
**Mitigation:** Keep animation controllers in the parent. Pass animation objects (`_recurringSlideAnimation`, `_recurringFadeAnimation`) to `RehearsalFormFields` as constructor params.

### Risk 4: FocusNode and TextEditingController Lifecycle (LOW)

**Risk:** Controllers/FocusNodes created in parent `initState()` and disposed in `dispose()` must still be passed correctly to child widgets.
**Mitigation:** Parent retains ownership and lifecycle. Children receive them as constructor params — standard Flutter pattern.

### Risk 5: Keyboard-Aware Padding (LOW)

**Risk:** `MediaQuery.of(context).viewInsets.bottom` must still resolve correctly after decomposition.
**Mitigation:** Both the parent build method and `EventEditorActions` read `MediaQuery` from their own context — both are within the same modal route, so values are identical.

### Risk 6: Autocomplete Overlay Positioning (LOW)

**Risk:** Autocomplete suggestion lists use `BoxConstraints(maxHeight: 200)` positioned within the scroll view. Extracting these into a child widget could affect overlay positioning.
**Mitigation:** Autocomplete widgets are rendered inline (not as overlays) — they are constrained containers within the scroll column. Position is unaffected by parent/child restructuring.

### Edge Case: Empty Block Out Form

**Behavior:** With stable height, Block Out will show shared fields (date, time, duration, location, setlist, notes) with empty space below. Bottom buttons remain at the bottom of the 90% container. This is expected and acceptable behavior per the feature requirements.

---

## 11. Verification Plan

### Pre-Implementation Baseline

- `flutter analyze` — zero issues ✓ (verified Phase 1)

### Post-Implementation Verification

**Step 1: Static Analysis**

```bash
flutter analyze
```

Must report zero issues.

**Step 2: Height Stability Test (Manual)**

1. Open BandRoadie
2. Navigate to Calendar or Dashboard
3. Tap "Create Event"
4. Observe drawer opens at stable height
5. Toggle Rehearsal → Gig → Block Out → Rehearsal
6. **VERIFY:** Drawer height does not change during any toggle
7. **VERIFY:** Block Out has empty space below form, buttons pinned at bottom
8. **VERIFY:** Rehearsal and Gig fill the form area normally

**Step 3: Form Functionality Test (Manual)**

1. Create a Rehearsal — verify date, time, duration, location, recurring, notes all work
2. Create a Gig — verify name, city, potential gig, member grid, load-in, pay, setlist all work
3. Create a Block Out — verify date, time, duration, notes work
4. Edit an existing Rehearsal — verify "Update" button enables on change (isDirty)
5. Edit an existing Gig — verify availability display, RSVP buttons work
6. Delete a Rehearsal — verify delete confirmation and series delete
7. Delete a Gig — verify delete confirmation

**Step 4: RBAC Verification (Manual)**

1. As a Contributor, open Create Event — verify Rehearsal type is hidden
2. As a Contributor, tap an event — verify viewOnly mode works (fields disabled, "Close" button)

**Step 5: Keyboard Awareness (Manual)**

1. Open Create Event drawer
2. Tap a text field (location, notes, gig name)
3. **VERIFY:** Drawer adjusts for keyboard, bottom buttons remain accessible
4. Dismiss keyboard
5. **VERIFY:** Drawer returns to stable height

**Step 6: Platform Test**
Run on at least macOS and iOS (or Web) to confirm no platform-specific regressions.

---

## 12. Engineer Task Breakdown

All tasks must be executed in order. Each task should be individually testable.

### Task 1: Fix Drawer Height (Part A)

**File:** `event_editor_drawer.dart`
**Change:** Remove `mainAxisSize: MainAxisSize.min` from the outer Column at line 1370.
**Verification:** Build and toggle between event types — drawer height should be stable.
**Risk:** LOW — single property change.

### Task 2: Create event_editor_helpers.dart

**Extract from event_editor_drawer.dart:**

- `_buildTextField()` method → public `EventTextField` widget
- `_buildDropdown<T>()` method → public `EventDropdown<T>` widget
- `_buildAmPmButton()` method → public `AmPmToggleButton` widget
- `_buildLoadInAmPmButton()` method → public `LoadInAmPmToggleButton` widget
- `_AvailabilityButton` class → move to helpers
- `_MemberDisambiguation` class → move to helpers
  **Verification:** `flutter analyze` passes. Parent imports and uses the extracted widgets identically.

### Task 3: Create event_type_selector.dart

**Extract from event_editor_drawer.dart:**

- `_buildEventTypeToggle()` method → `EventTypeSelector` StatelessWidget
  **Constructor params:** `selectedType`, `isEditMode`, `isSaving`, `isContributor`, `availableTypes`, `onTypeChanged`
  **Verification:** Event type toggle works identically in create and edit mode.

### Task 4: Create event_editor_actions.dart

**Extract from event_editor_drawer.dart:**

- `_buildBottomButtons()` → `EventEditorBottomActions` StatelessWidget
- `_buildViewOnlyCloseButton()` → `EventEditorViewOnlyClose` StatelessWidget
- `_buildDeleteButton()` → `EventDeleteButton` StatelessWidget
  **Constructor params:** `canSave`, `isSaving`, `isDeleting`, `primaryButtonLabel`, `viewOnly`, `onSave`, `onCancel`, `onDelete`
  **Verification:** Save/Cancel/Delete buttons work in create, edit, and viewOnly modes.

### Task 5: Create event_form_fields.dart

**Extract from event_editor_drawer.dart:**

- `_buildDatePicker()` + `_buildSingleDatePicker()` + `_buildMultipleDatesToggle()`
- `_buildTimeSelector()`
- `_buildDurationSelector()`
- `_buildSetlistSelector()` + `_buildSetlistPill()`
- Notes text field section
- `_buildErrorBanner()`
  **Make this a ConsumerWidget** for setlist provider access.
  **Constructor params:** All shared form state values + callbacks for date, time, duration changes.
  **Verification:** Shared fields work for all three event types.

### Task 6: Create rehearsal_form_fields.dart

**Extract from event_editor_drawer.dart:**

- `_buildLocationAutocomplete()`
- `_buildRecurringToggle()`
- `_buildRecurringSection()` (day selector, frequency, until date, summary)
  **Constructor params:** Location state + suggestions + callbacks, recurring state + animation objects + callbacks.
  **Verification:** Create a rehearsal with recurring on/off. Location autocomplete works.

### Task 7: Create gig_form_fields.dart

**Extract from event_editor_drawer.dart:**

- `_buildGigNameAutocomplete()`
- `_buildGigCityAutocomplete()`
- `_buildPotentialGigContainer()` (toggle, member grid, availability, multi-date)
- `_buildMultiDateAvailabilitySection()` + `_buildPerDateSection()`
- `_buildUserAvailabilitySection()`
- `_buildMemberSelectionGrid()`
- `_buildLoadInTimeSelector()`
- `_buildGigPayField()`
  **Make this a ConsumerWidget** for members provider access.
  **Constructor params:** All gig state values + suggestions + callbacks.
  **Verification:** Create a gig with potential gig, multi-date, member selection, load-in time, pay. Edit a gig and verify availability display + RSVP.

### Task 8: Slim Down event_editor_drawer.dart

**Replace** all extracted `_build*` method calls with instantiations of the new widgets.
**Remove** the extracted method bodies from the file.
**Retain** in the file: all state variables, `initState`, `dispose`, `build` (container shell), `_buildFormData`, `_handleSave`, `_handleDelete`, `_markDirty`, autocomplete query methods, availability loading methods, `_showDatePicker`, `_showAdditionalDatePicker`, `_addAdditionalDate`, `_removeAdditionalDate`, `_showDeleteConfirmation`, `_preSelectAllMembersForPotentialGig`, `_checkBlockOutConflicts`, `_showBlockOutConflictDialog`, and the `_isFormValid` getter.
**Verification:** Full manual test cycle (Step 2-6 from Verification Plan).

### Task 9: Final Verification

- Run `flutter analyze`
- Run full manual test suite
- Verify all 13 caller sites work (open event editor from home, calendar, dashboard)
- Test on macOS + one other platform

---

## 13. Rollout / Migration Strategy

**Rollout:** Standard deploy. No feature flags needed.

**Reasoning:**

- No database changes
- No API changes
- No auth changes
- Backward compatible (AddEditEventBottomSheet.show API unchanged)
- All changes are internal to the events widget layer

**Deploy sequence:**

1. Engineer implements all tasks
2. QA validates on all target platforms
3. Merge to main
4. Deploy web via Vercel (`flutter build web --release && cd build/web && vercel --prod`)
5. Deploy iOS/Android via standard release process

---

## 14. Out of Scope

The following are explicitly **not** part of this feature:

- **State management refactor to Riverpod Notifier:** Moving the 60+ state variables to a dedicated controller is a significant architectural change with high regression risk. The callback-based extraction achieves the file decomposition goal safely. A state management refactor can be a future feature if needed.
- **Block Out form enhancement:** Block Out currently shows the same shared fields as other types. Adding Block Out-specific fields (e.g., reason, all-day toggle) is a separate feature.
- **Repository decomposition:** `events_repository.dart` is already well-sized and cleanly structured. No changes needed.
- **Model changes:** `EventFormData` and related enums are not modified.
- **Database schema changes:** No tables, columns, constraints, triggers, or RLS policies are modified.
- **Caller file changes:** All 13 call sites of `AddEditEventBottomSheet.show()` remain unchanged.
- **New dependencies:** No new packages or third-party dependencies.
- **Test creation:** Unit or widget tests for the extracted components. Recommended as a follow-up but not part of this feature scope.

---

## 15. Widget Contracts (Public API)

All widgets below follow unidirectional data flow. The parent `_EventEditorDrawerState` retains full state ownership. Child widgets never mutate state directly — they communicate exclusively via callbacks. Provider usage is declared explicitly per widget.

---

### 15.1 EventTypeSelector

**File:** `lib/features/events/widgets/event_type_selector.dart`
**Purpose:** Renders the Rehearsal / Gig / Block Out segmented toggle. Shows a disabled hint in edit mode.
**Widget type:** `StatelessWidget`
**Provider access:** None

```dart
class EventTypeSelector extends StatelessWidget {
  const EventTypeSelector({
    super.key,
    required this.selectedType,
    required this.availableTypes,
    required this.isEditMode,
    required this.isSaving,
    required this.onTypeChanged,
  });

  /// The currently selected event type.
  final EventType selectedType;

  /// The list of event types available to the user (RBAC-filtered).
  /// Contributors receive a list excluding EventType.rehearsal.
  final List<EventType> availableTypes;

  /// True when editing an existing event. Disables the toggle.
  final bool isEditMode;

  /// True while a save operation is in progress. Disables the toggle.
  final bool isSaving;

  /// Called when the user taps a different event type.
  /// The parent is responsible for setState, RBAC re-checks, and potential gig forcing.
  final ValueChanged<EventType> onTypeChanged;

  @override
  Widget build(BuildContext context);
}
```

---

### 15.2 EventFormFields

**File:** `lib/features/events/widgets/event_form_fields.dart`
**Purpose:** Renders shared form fields used by all event types: error banner, date picker (single + multi-date), time selector, duration selector, setlist selector, and notes field.
**Widget type:** `ConsumerWidget` — watches `setlistsProvider` for the setlist pill list.
**Provider access:** `setlistsProvider` (read via `ref.watch`)

```dart
class EventFormFields extends ConsumerWidget {
  const EventFormFields({
    super.key,
    required this.eventType,
    required this.isSaving,
    required this.errorMessage,
    // Date state
    required this.selectedDate,
    required this.onDateTap,
    // Multi-date state (potential gigs only)
    required this.isPotentialGig,
    required this.isMultiDate,
    required this.additionalDates,
    required this.onMultiDateToggled,
    required this.onAdditionalDateTap,
    required this.onAdditionalDateRemoved,
    required this.onAdditionalDateAdded,
    // Time state
    required this.selectedHour,
    required this.selectedMinutes,
    required this.isPM,
    required this.onHourChanged,
    required this.onMinutesChanged,
    required this.onAmPmChanged,
    // Duration state
    required this.durationMinutes,
    required this.onDurationDecremented,
    required this.onDurationIncremented,
    // Setlist state
    required this.selectedSetlistId,
    required this.onSetlistSelected,
    required this.onNavigateToCreateSetlist,
    // Notes
    required this.notesController,
    required this.notesHintController,
  });

  /// The active event type — controls multi-date visibility.
  final EventType eventType;

  /// True while saving. Disables all interactive controls.
  final bool isSaving;

  /// Error message to display in the banner, or null if no error.
  final String? errorMessage;

  // --- Date ---

  /// The primary selected date.
  final DateTime selectedDate;

  /// Called when the user taps the primary date picker.
  final VoidCallback onDateTap;

  // --- Multi-date (potential gigs only) ---

  /// Whether this is a potential gig (controls "Multiple" toggle visibility).
  final bool isPotentialGig;

  /// Whether multi-date mode is active.
  final bool isMultiDate;

  /// The list of additional dates (beyond the primary date).
  final List<DateTime> additionalDates;

  /// Called when the "Multiple" toggle is tapped.
  final ValueChanged<bool> onMultiDateToggled;

  /// Called when the user taps an additional date picker at the given index.
  final ValueChanged<int> onAdditionalDateTap;

  /// Called when the user removes an additional date at the given index.
  final ValueChanged<int> onAdditionalDateRemoved;

  /// Called when the user taps "+ Add another date".
  final VoidCallback onAdditionalDateAdded;

  // --- Time ---

  /// Selected hour (1–12).
  final int selectedHour;

  /// Selected minutes (0, 15, 30, 45).
  final int selectedMinutes;

  /// True if PM, false if AM.
  final bool isPM;

  /// Called when the hour dropdown value changes.
  final ValueChanged<int> onHourChanged;

  /// Called when the minutes dropdown value changes.
  final ValueChanged<int> onMinutesChanged;

  /// Called when the user taps AM or PM. Passes true for PM, false for AM.
  final ValueChanged<bool> onAmPmChanged;

  // --- Duration ---

  /// Current duration in minutes.
  final int durationMinutes;

  /// Called when the user taps the -15 button.
  final VoidCallback onDurationDecremented;

  /// Called when the user taps the +15 button.
  final VoidCallback onDurationIncremented;

  // --- Setlist ---

  /// Currently selected setlist ID, or null for "None".
  final String? selectedSetlistId;

  /// Called when a setlist pill is tapped. Passes the setlist ID (or null for "None")
  /// and the setlist name.
  final void Function(String? id, String? name) onSetlistSelected;

  /// Called when the user taps "+ Create Setlist".
  final VoidCallback onNavigateToCreateSetlist;

  // --- Notes ---

  /// TextEditingController for the notes field. Owned by parent.
  final TextEditingController notesController;

  /// FieldHintController for the notes hint. Owned by parent.
  final FieldHintController notesHintController;

  @override
  Widget build(BuildContext context, WidgetRef ref);
}
```

---

### 15.3 RehearsalFormFields

**File:** `lib/features/events/widgets/rehearsal_form_fields.dart`
**Purpose:** Renders rehearsal-specific form fields: location autocomplete with past suggestions, recurring toggle, and the animated recurring section (day selector, frequency, until date, summary).
**Widget type:** `StatelessWidget`
**Provider access:** None — all data passed via constructor.

```dart
class RehearsalFormFields extends StatelessWidget {
  const RehearsalFormFields({
    super.key,
    required this.isSaving,
    // Location autocomplete
    required this.locationController,
    required this.locationHintController,
    required this.locationSuggestions,
    // Recurring state
    required this.isRecurring,
    required this.onRecurringToggled,
    required this.recurringSlideAnimation,
    required this.recurringFadeAnimation,
    // Recurring section data
    required this.selectedDays,
    required this.onDayToggled,
    required this.frequency,
    required this.onFrequencyChanged,
    required this.untilDate,
    required this.onUntilDateTap,
    required this.onUntilDateCleared,
    required this.selectedDate,
    required this.onMarkDirty,
  });

  /// True while saving. Disables all interactive controls.
  final bool isSaving;

  // --- Location autocomplete ---

  /// TextEditingController for the location field. Owned by parent.
  final TextEditingController locationController;

  /// FieldHintController for the location hint. Owned by parent.
  final FieldHintController locationHintController;

  /// List of past rehearsal locations for autocomplete. Loaded by parent.
  final List<String> locationSuggestions;

  // --- Recurring toggle ---

  /// Whether recurring mode is active.
  final bool isRecurring;

  /// Called when the recurring switch is toggled.
  final ValueChanged<bool> onRecurringToggled;

  /// SlideTransition position animation for the recurring section. Owned by parent.
  final Animation<Offset> recurringSlideAnimation;

  /// FadeTransition opacity animation for the recurring section. Owned by parent.
  final Animation<double> recurringFadeAnimation;

  // --- Recurring section data ---

  /// Set of selected days of the week.
  final Set<Weekday> selectedDays;

  /// Called when a day circle is tapped. Passes the toggled day.
  final ValueChanged<Weekday> onDayToggled;

  /// Current recurrence frequency.
  final RecurrenceFrequency frequency;

  /// Called when a frequency toggle is tapped.
  final ValueChanged<RecurrenceFrequency> onFrequencyChanged;

  /// Optional end date for the recurrence.
  final DateTime? untilDate;

  /// Called when the user taps the "Until" date picker.
  final VoidCallback onUntilDateTap;

  /// Called when the user clears the until date.
  final VoidCallback onUntilDateCleared;

  /// The primary event date — used for recurrence summary text.
  final DateTime selectedDate;

  /// Called to mark the form dirty after any field change.
  final VoidCallback onMarkDirty;

  @override
  Widget build(BuildContext context);
}
```

---

### 15.4 GigFormFields

**File:** `lib/features/events/widgets/gig_form_fields.dart`
**Purpose:** Renders gig-specific form fields: name autocomplete, city autocomplete, potential gig section (toggle, member grid, availability, multi-date availability), load-in time selector, and gig pay field.
**Widget type:** `ConsumerWidget` — watches `membersProvider` for the member grid.
**Provider access:** `membersProvider` (read via `ref.watch`)

```dart
class GigFormFields extends ConsumerWidget {
  const GigFormFields({
    super.key,
    required this.isSaving,
    required this.isEditMode,
    required this.existingEventId,
    // Gig name autocomplete
    required this.nameController,
    required this.venueHintController,
    required this.gigNameFocusNode,
    required this.gigNameSuggestions,
    required this.onGigNameChanged,
    required this.fieldErrors,
    // City autocomplete
    required this.locationController,
    required this.cityHintController,
    required this.gigCityFocusNode,
    required this.gigCitySuggestions,
    required this.onGigCityChanged,
    // Potential gig
    required this.isPotentialGig,
    required this.forcePotentialOnly,
    required this.onPotentialGigToggled,
    // Member availability (edit mode)
    required this.memberAvailability,
    required this.isLoadingMemberAvailability,
    required this.perDateAvailability,
    required this.isLoadingPerDateAvailability,
    // User availability (edit mode)
    required this.currentUserResponse,
    required this.isLoadingUserResponse,
    required this.onUserResponseChanged,
    // Multi-date (potential gig)
    required this.isMultiDate,
    required this.additionalDates,
    required this.selectedDate,
    required this.existingGigDateIds,
    required this.onPerDateResponseChanged,
    // Load-in time
    required this.loadInHour,
    required this.loadInMinutes,
    required this.loadInIsPM,
    required this.onLoadInTimeSet,
    required this.onLoadInTimeCleared,
    required this.onLoadInHourChanged,
    required this.onLoadInMinutesChanged,
    required this.onLoadInAmPmChanged,
    // Gig pay
    required this.gigPayController,
    // General
    required this.onMarkDirty,
  });

  /// True while saving. Disables all interactive controls.
  final bool isSaving;

  /// True when editing an existing gig.
  final bool isEditMode;

  /// The existing gig ID (for edit mode availability lookups). Null in create mode.
  final String? existingEventId;

  // --- Gig name autocomplete ---

  /// TextEditingController for the gig name field. Owned by parent.
  final TextEditingController nameController;

  /// FieldHintController for the venue hint. Owned by parent.
  final FieldHintController venueHintController;

  /// FocusNode for the gig name RawAutocomplete. Owned by parent.
  final FocusNode gigNameFocusNode;

  /// Current list of gig name suggestions (async-fetched by parent).
  final List<String> gigNameSuggestions;

  /// Called when the gig name text changes (triggers parent debounced fetch).
  final ValueChanged<String> onGigNameChanged;

  /// Map of field name → error message. Used for name/city validation.
  final Map<String, String> fieldErrors;

  // --- City autocomplete ---

  /// TextEditingController for the city field. Shared with location. Owned by parent.
  final TextEditingController locationController;

  /// FieldHintController for the city hint. Owned by parent.
  final FieldHintController cityHintController;

  /// FocusNode for the city RawAutocomplete. Owned by parent.
  final FocusNode gigCityFocusNode;

  /// Current list of city suggestions (async-fetched by parent).
  final List<String> gigCitySuggestions;

  /// Called when the city text changes (triggers parent debounced fetch).
  final ValueChanged<String> onGigCityChanged;

  // --- Potential gig ---

  /// Whether potential gig mode is active.
  final bool isPotentialGig;

  /// True when RBAC forces potential-only mode (contributor). Disables the toggle.
  final bool forcePotentialOnly;

  /// Called when the potential gig switch is toggled.
  final ValueChanged<bool> onPotentialGigToggled;

  // --- Member availability (edit mode, potential gig) ---

  /// Map of userId → 'yes' | 'no' | null. Loaded by parent.
  final Map<String, String?> memberAvailability;

  /// True while member availability is loading.
  final bool isLoadingMemberAvailability;

  /// Map of gigDateId → (userId → response). For multi-date potential gigs.
  final Map<String, Map<String, String?>> perDateAvailability;

  /// True while per-date availability is loading.
  final bool isLoadingPerDateAvailability;

  // --- User availability (edit mode, potential gig) ---

  /// Current user's RSVP response: 'yes', 'no', or null.
  final String? currentUserResponse;

  /// True while the current user's response is loading.
  final bool isLoadingUserResponse;

  /// Called when the user taps YES or NO for single-date availability.
  final ValueChanged<String> onUserResponseChanged;

  // --- Multi-date ---

  /// Whether multi-date mode is active.
  final bool isMultiDate;

  /// Additional dates beyond the primary date.
  final List<DateTime> additionalDates;

  /// The primary event date.
  final DateTime selectedDate;

  /// Map of DateTime → gigDateId for existing gig dates.
  final Map<DateTime, String> existingGigDateIds;

  /// Called when the user taps YES/NO for a specific date in multi-date mode.
  /// Passes (date, isPrimaryDate, response).
  final void Function(DateTime date, bool isPrimaryDate, String response) onPerDateResponseChanged;

  // --- Load-in time ---

  /// Load-in hour (1–12), or null if not set.
  final int? loadInHour;

  /// Load-in minutes (0, 15, 30, 45), or null if not set.
  final int? loadInMinutes;

  /// Load-in AM/PM (true = PM), or null if not set.
  final bool? loadInIsPM;

  /// Called when the user taps "Set Load-in Time" to initialize defaults.
  final VoidCallback onLoadInTimeSet;

  /// Called when the user taps "Clear" to remove the load-in time.
  final VoidCallback onLoadInTimeCleared;

  /// Called when the load-in hour dropdown changes.
  final ValueChanged<int> onLoadInHourChanged;

  /// Called when the load-in minutes dropdown changes.
  final ValueChanged<int> onLoadInMinutesChanged;

  /// Called when the load-in AM/PM is toggled. Passes true for PM, false for AM.
  final ValueChanged<bool> onLoadInAmPmChanged;

  // --- Gig pay ---

  /// CurrencyInputController for the gig pay field. Owned by parent.
  final CurrencyInputController gigPayController;

  // --- General ---

  /// Called to mark the form dirty after any field change.
  final VoidCallback onMarkDirty;

  @override
  Widget build(BuildContext context, WidgetRef ref);
}
```

---

### 15.5 EventEditorActions

**File:** `lib/features/events/widgets/event_editor_actions.dart`
**Purpose:** Renders the bottom action bar: Cancel + Save buttons in normal mode, Close button in viewOnly mode, and the Delete button (edit mode only).
**Widget type:** `StatelessWidget`
**Provider access:** None

```dart
/// Bottom action buttons for the event editor: Cancel + Save (or Close in viewOnly mode).
class EventEditorBottomActions extends StatelessWidget {
  const EventEditorBottomActions({
    super.key,
    required this.canSave,
    required this.isSaving,
    required this.isDeleting,
    required this.primaryButtonLabel,
    required this.onSave,
    required this.onCancel,
  });

  /// Whether the save button should be enabled.
  final bool canSave;

  /// True while saving. Shows loading spinner on primary button.
  final bool isSaving;

  /// True while deleting. Disables both buttons.
  final bool isDeleting;

  /// Label for the primary action button (e.g., "Add Rehearsal", "Update").
  final String primaryButtonLabel;

  /// Called when the user taps the save/primary button.
  final VoidCallback onSave;

  /// Called when the user taps the cancel button.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context);
}

/// Single Close button for viewOnly mode.
class EventEditorViewOnlyClose extends StatelessWidget {
  const EventEditorViewOnlyClose({
    super.key,
    required this.onClose,
  });

  /// Called when the user taps the Close button.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context);
}

/// Delete event button (destructive text style). Shown in edit mode only.
class EventDeleteButton extends StatelessWidget {
  const EventDeleteButton({
    super.key,
    required this.isSaving,
    required this.isDeleting,
    required this.onDelete,
  });

  /// True while saving. Disables the button.
  final bool isSaving;

  /// True while deleting. Shows loading spinner.
  final bool isDeleting;

  /// Called when the user taps the delete button.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context);
}
```

---

### 15.6 Event Editor Helpers (event_editor_helpers.dart)

**File:** `lib/features/events/widgets/event_editor_helpers.dart`
**Purpose:** Shared reusable building blocks used by multiple form field widgets: text field, dropdown, AM/PM buttons, availability button, and member disambiguation helper.
**Widget types:** Multiple `StatelessWidget` classes + one data class.
**Provider access:** None

```dart
/// Styled text field with label, error display, and optional multiline support.
class EventTextField extends StatelessWidget {
  const EventTextField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.maxLines = 1,
    required this.isSaving,
    this.onChanged,
  });

  /// Field label text displayed above the input.
  final String label;

  /// TextEditingController for the field. Owned by parent.
  final TextEditingController controller;

  /// Placeholder hint text.
  final String? hint;

  /// Validation error message, or null if no error.
  final String? error;

  /// Maximum visible lines. Values > 1 enable multiline mode.
  final int maxLines;

  /// True while saving. Disables the field.
  final bool isSaving;

  /// Called when the text changes. Used by parent for setState rebuild.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context);
}

/// Styled dropdown selector.
class EventDropdown<T> extends StatelessWidget {
  const EventDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelBuilder,
    required this.isSaving,
  });

  /// The currently selected value.
  final T value;

  /// The list of selectable items.
  final List<T> items;

  /// Called when the user selects a different item.
  final ValueChanged<T?> onChanged;

  /// Builds the display label for each item.
  final String Function(T) labelBuilder;

  /// True while saving. Disables the dropdown.
  final bool isSaving;

  @override
  Widget build(BuildContext context);
}

/// AM/PM toggle button (used for start time).
class AmPmToggleButton extends StatelessWidget {
  const AmPmToggleButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isSaving,
    required this.onTap,
  });

  /// Button label: "AM" or "PM".
  final String label;

  /// Whether this button is currently selected.
  final bool isSelected;

  /// True while saving. Disables the button.
  final bool isSaving;

  /// Called when the button is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context);
}

/// YES/NO availability response button with animated state transitions.
class AvailabilityButton extends StatelessWidget {
  const AvailabilityButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isPositive,
    required this.isLoading,
    required this.onPressed,
  });

  /// Button label: "YES" or "NO".
  final String label;

  /// Icon to display (e.g., Icons.check, Icons.close).
  final IconData icon;

  /// Whether this button is currently selected.
  final bool isSelected;

  /// True for YES (green), false for NO (red).
  final bool isPositive;

  /// True while a response is being submitted. Shows spinner.
  final bool isLoading;

  /// Called when the button is tapped.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context);
}

/// Helper data class for member name disambiguation.
/// Determines how to display member names when multiple members share
/// the same first name.
class MemberDisambiguation {
  const MemberDisambiguation({
    required this.line1,
    this.line2,
    this.requiresTwoLines = false,
  });

  /// Primary display text (first name, or "First L." for disambiguation).
  final String line1;

  /// Secondary display text (full last name). Only used when requiresTwoLines is true.
  final String? line2;

  /// True when the name requires two-line display (same first name + last initial).
  final bool requiresTwoLines;
}
```
