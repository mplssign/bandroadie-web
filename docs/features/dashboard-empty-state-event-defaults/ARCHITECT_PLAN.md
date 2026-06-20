# Architect Plan — Dashboard Empty-State Event Defaults

## Feature Slug

`dashboard-empty-state-event-defaults`

---

## Problem Summary

The dashboard empty-state component (`EmptyHomeState`) displays two sections when a band has no upcoming events:

1. **"No Rehearsal Scheduled"** section with a button labeled **"Add Event"** (should be "Create Rehearsal")
2. **"No Upcoming Gigs"** section with a button labeled **"Create Gig"** (correct)

Both buttons currently open the Add Event sheet defaulting to **Rehearsal** (incorrect for the gig button). The expected behavior is:

- "+ Create Rehearsal" → opens Add Event sheet with `EventType.rehearsal` pre-selected
- "+ Create Gig" → opens Add Event sheet with `EventType.gig` pre-selected

This is a UI-only bug affecting button labels and the event-type parameter passed when opening the Add Event sheet.

---

## Root Cause

**Confidence:** HIGH — confirmed in code

The `EmptyHomeState` widget (`lib/features/home/widgets/empty_home_state.dart`) accepts a single generic callback `onAddEvent` that is bound to both the rehearsal and gig empty-state cards:

```dart
// Line 136 — Rehearsal section
EmptySectionCard(
  title: 'No Rehearsal Scheduled',
  subtitle: 'The stage is empty and the amps are cold.',
  buttonLabel: 'Add Event',  // ← BUG: Should be 'Create Rehearsal'
  onButtonPressed: widget.onAddEvent,
),

// Line 147 — Gigs section
EmptySectionCard(
  title: 'No Upcoming Gigs',
  subtitle: 'The spotlight awaits — time to book your next show.',
  buttonLabel: 'Create Gig',  // ← Label is correct
  onButtonPressed: widget.onAddEvent,  // ← BUG: Calls same generic handler
),
```

Both call sites (`home_screen.dart` line 345 and `home_tab_content.dart` line 604) bind `onAddEvent` to `_handleAddEvent()`, which defaults to `EventType.rehearsal` for admin/member users:

```dart
// home_tab_content.dart lines 371-386
void _handleAddEvent() {
  final permsAsync = ref.read(currentUserPermissionsProvider);
  final perms = permsAsync.when(
    data: (p) => p,
    loading: () => null,
    error: (__, _) => null,
  );
  // Default to rehearsal for admin/member, gig for contributor
  final eventType =
      (perms?.isContributor == true) ? EventType.gig : EventType.rehearsal;
  _openAddEventSheet(eventType);
}
```

**Why this causes the bug:**
The generic `onAddEvent` callback has no way to distinguish between the rehearsal button and the gig button — both call the same handler, which defaults to rehearsal.

**Contrast with the correct implementation:**
The non-empty-state dashboard sections (`_buildDashboardContent` in both files) correctly pass specific event types when creating empty-state cards:

```dart
// home_screen.dart lines 789-797 — Rehearsal section
EmptySectionCard(
  title: 'No Rehearsal Scheduled',
  subtitle: 'The stage is empty and the amps are cold.',
  buttonLabel: 'Schedule Rehearsal',
  onButtonPressed: isContributor
      ? null
      : () => _openAddEventSheet(EventType.rehearsal),  // ← Correct
),

// home_screen.dart lines 807-814 — Gig section
EmptySectionCard(
  title: 'No Gigs Booked',
  subtitle: 'The world clearly isn\'t ready yet.',
  buttonLabel: 'Create Gig',
  onButtonPressed: canCreateGig
      ? () => _openAddEventSheet(EventType.gig)  // ← Correct
      : null,
),
```

These sections pass closures that call `_openAddEventSheet` with the specific event type, bypassing the generic handler.

---

## Reference Docs Consulted

Not applicable — this is a UI component bug with no domain-specific dependencies (no notifications, no auth, no data model changes).

---

## Existing System Analysis

### Current Behavior

**Dashboard empty-state flow (`EmptyHomeState` widget):**

1. User sees empty dashboard (no gigs, no rehearsals)
2. Two `EmptySectionCard` instances are rendered:
   - "No Rehearsal Scheduled" with button "Add Event"
   - "No Upcoming Gigs" with button "Create Gig"
3. Both buttons call `widget.onAddEvent` (bound to `_handleAddEvent()`)
4. `_handleAddEvent()` defaults to `EventType.rehearsal` for admin/member users
5. Add Event sheet opens with Rehearsal tab pre-selected (incorrect for gig button)

**Data flow:**

```
EmptyHomeState (widget)
  ├─ Rehearsal EmptySectionCard → widget.onAddEvent → _handleAddEvent() → EventType.rehearsal
  └─ Gig EmptySectionCard       → widget.onAddEvent → _handleAddEvent() → EventType.rehearsal
```

### Correct Behavior (non-empty-state sections)

When the dashboard has events (gigs or rehearsals), the empty-state cards in `_buildDashboardContent` correctly specify the event type:

```
_buildDashboardContent
  ├─ Rehearsal EmptySectionCard → () => _openAddEventSheet(EventType.rehearsal)
  └─ Gig EmptySectionCard       → () => _openAddEventSheet(EventType.gig)
```

This is the pattern the `EmptyHomeState` widget should follow.

---

## Proposed Solution

Replace the single generic `onAddEvent` callback in `EmptyHomeState` with two specific callbacks:

1. **`onCreateRehearsal`** (`VoidCallback?`) — for the rehearsal empty-state card
2. **`onCreateGig`** (`VoidCallback?`) — for the gig empty-state card

Update the widget to:
- Change the rehearsal button label from "Add Event" to "Create Rehearsal"
- Bind the rehearsal button to `onCreateRehearsal`
- Bind the gig button to `onCreateGig`

Update both call sites (`home_screen.dart` and `home_tab_content.dart`) to pass:
- `onCreateRehearsal: () => _openAddEventSheet(EventType.rehearsal)` (gated by `!isContributor`)
- `onCreateGig: () => _openAddEventSheet(EventType.gig)` (gated by `canCreateGig`)

This mirrors the pattern used in the non-empty-state dashboard sections and ensures each button opens the Add Event sheet with the correct event type pre-selected.

---

## Database Impact

**Not applicable** — this is a UI-only change. No migrations, RLS policies, RPC functions, or triggers are affected.

---

## Flutter Architecture Changes

### State Management

**Not affected** — no Riverpod providers, controllers, or state classes are modified.

### Widgets Modified

**`EmptyHomeState` (`lib/features/home/widgets/empty_home_state.dart`)**
- Remove constructor parameter: `onAddEvent` (`VoidCallback?`)
- Add constructor parameters: `onCreateRehearsal` (`VoidCallback?`), `onCreateGig` (`VoidCallback?`)
- Update rehearsal `EmptySectionCard`:
  - Change `buttonLabel` from `'Add Event'` to `'Create Rehearsal'`
  - Change `onButtonPressed` from `widget.onAddEvent` to `widget.onCreateRehearsal`
- Update gig `EmptySectionCard`:
  - Change `onButtonPressed` from `widget.onAddEvent` to `widget.onCreateGig`
- Update `QuickActionsRow` instantiation (if needed):
  - The Quick Actions section uses `widget.onAddEvent` for the "+ Add Event" button
  - This should remain unchanged (it correctly defaults to rehearsal for admin/member)
  - No change required to `QuickActionsRow` invocation

### Repositories

**Not affected** — no repository changes.

---

## Files to Create

**None** — all required files exist.

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/home/widgets/empty_home_state.dart` | Replace `onAddEvent` parameter with `onCreateRehearsal` and `onCreateGig`; update button labels and bindings for both `EmptySectionCard` instances |
| `lib/features/home/home_screen.dart` | Update `EmptyHomeState` instantiation to pass `onCreateRehearsal` and `onCreateGig` closures instead of `onAddEvent` |
| `lib/features/home/home_tab_content.dart` | Update `EmptyHomeState` instantiation to pass `onCreateRehearsal` and `onCreateGig` closures instead of `onAddEvent` |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/main.dart` | Initialization order must not change |
| `lib/features/home/widgets/quick_actions_row.dart` | Quick Actions row behavior is correct (defaults to rehearsal for admin/member) |
| `lib/features/events/models/event_form_data.dart` | `EventType` enum is correct as-is |
| `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` | Add Event sheet behavior is correct (accepts `initialType` parameter) |
| All other files | Not required for this fix |

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | **unaffected** — only button labels and callbacks change, no data flow or repository changes |
| Rehearsals | **unaffected** — only button labels and callbacks change, no data flow or repository changes |
| Setlists / Catalog | **unaffected** — no changes to setlist logic |
| Members / RBAC | **unaffected** — permission gates remain unchanged (use existing `isContributor`, `canCreateGig`) |
| Auth / Session | **unaffected** — no auth changes |
| Routing | **unaffected** — no navigation changes |
| Notifications | **unaffected** — no notification logic changes |
| Platform (iOS / Android / Web / macOS) | **unaffected** — changes are platform-agnostic UI updates |

---

## Regression Risk

**LOW**

**Rationale:**
- Change is localized to 3 files (1 widget + 2 call sites)
- No state management, controller, or repository changes
- No database or backend changes
- No initialization order changes
- No new dependencies
- No changes to permission gating logic (uses existing `isContributor`, `canCreateGig`)
- Change is purely cosmetic + parameter passing — worst-case failure mode is button remains non-functional (same as if permission check fails), not a crash or data corruption

**Regression validation focus:**
- Verify "+ Create Rehearsal" button opens Add Event sheet with Rehearsal selected
- Verify "+ Create Gig" button opens Add Event sheet with Gig selected
- Verify permission gating still works (contributors see only gig button, admin/member see both)
- Verify Quick Actions "+ Add Event" button still works (should continue to default to rehearsal for admin/member)

---

## Engineer Task Breakdown

### Task 1: Update `EmptyHomeState` widget

**File:** `lib/features/home/widgets/empty_home_state.dart`

1. Remove the `onAddEvent` parameter from the constructor (line 24)
2. Add two new parameters: `onCreateRehearsal` and `onCreateGig` (both `VoidCallback?`)
3. Update the rehearsal `EmptySectionCard` (line 136):
   - Change `buttonLabel` from `'Add Event'` to `'Create Rehearsal'`
   - Change `onButtonPressed` from `widget.onAddEvent` to `widget.onCreateRehearsal`
4. Update the gig `EmptySectionCard` (line 147):
   - Change `onButtonPressed` from `widget.onAddEvent` to `widget.onCreateGig`
5. Update the Quick Actions visibility check (line 158):
   - Change condition from `if (widget.onAddEvent != null || widget.onCreateSetlist != null)` to check for any of the three callbacks
   - The Quick Actions row itself does not need updating (it should continue to use a generic callback for the "+ Add Event" button)

**Note:** After review, the Quick Actions section should remain unchanged. It has its own "+ Add Event" button that correctly defaults to rehearsal for admin/member users. Only the two `EmptySectionCard` instances need updating.

### Task 2: Update `home_screen.dart` instantiation

**File:** `lib/features/home/home_screen.dart`

1. Locate the `EmptyHomeState` instantiation (line 335)
2. Remove the `onAddEvent` parameter (line 345)
3. Add `onCreateRehearsal` parameter:
   ```dart
   onCreateRehearsal: isContributor
       ? null
       : () => _openAddEventSheet(EventType.rehearsal),
   ```
4. Add `onCreateGig` parameter:
   ```dart
   onCreateGig: canCreateGig
       ? () => _openAddEventSheet(EventType.gig)
       : null,
   ```

### Task 3: Update `home_tab_content.dart` instantiation

**File:** `lib/features/home/home_tab_content.dart`

1. Locate the `EmptyHomeState` instantiation (line 595)
2. Remove the `onAddEvent` parameter (line 604)
3. Add `onCreateRehearsal` parameter:
   ```dart
   onCreateRehearsal: isContributor
       ? null
       : () => _openAddEventSheet(EventType.rehearsal),
   ```
4. Add `onCreateGig` parameter:
   ```dart
   onCreateGig: canCreateGig
       ? () => _openAddEventSheet(EventType.gig)
       : null,
   ```

### Task 4: Run Flutter Analyze

```bash
flutter analyze
```

Confirm 0 errors, 0 warnings.

### Task 5: Manual Testing

**Test Case 1 — Admin/Member user on empty dashboard:**

1. Open BandRoadie as admin or member user with empty band (no gigs, no rehearsals)
2. Observe empty-state dashboard with two sections:
   - "No Rehearsal Scheduled" with button **"Create Rehearsal"** (not "Add Event")
   - "No Upcoming Gigs" with button **"Create Gig"**
3. Tap **"Create Rehearsal"** → Add Event sheet opens with **Rehearsal** tab selected ✓
4. Close sheet
5. Tap **"Create Gig"** → Add Event sheet opens with **Gig** tab selected ✓

**Test Case 2 — Contributor user (without gig permission) on empty dashboard:**

1. Open BandRoadie as contributor (no gig permission) with empty band
2. Observe empty-state dashboard:
   - "No Rehearsal Scheduled" section has **disabled button** (grayed out)
   - "No Upcoming Gigs" section has **disabled button** (grayed out)
3. Verify buttons do not respond to taps (permission-gated correctly)

**Test Case 3 — Contributor user (with gig permission) on empty dashboard:**

1. Open BandRoadie as contributor (has gig permission) with empty band
2. Observe empty-state dashboard:
   - "No Rehearsal Scheduled" section has **disabled button** (contributors cannot create rehearsals)
   - "No Upcoming Gigs" section has **active "Create Gig" button**
3. Tap **"Create Gig"** → Add Event sheet opens with **Gig** tab selected ✓

**Test Case 4 — Quick Actions "+ Add Event" button (no regression):**

1. Open BandRoadie as admin/member with empty band
2. Scroll to Quick Actions section
3. Tap **"+ Add Event"** button → Add Event sheet opens with **Rehearsal** tab selected (default behavior, unchanged) ✓

---

## Verification Plan

### Tier 1 — Pre-deployment (not applicable)

No database or backend changes — skip to Tier 2.

### Tier 2 — Post-deployment (manual testing)

**Manual test matrix:**

| Test | User Role | Action | Expected Result |
|------|-----------|--------|-----------------|
| T1   | Admin/Member | Tap "Create Rehearsal" on empty dashboard | Add Event sheet opens with Rehearsal tab selected |
| T2   | Admin/Member | Tap "Create Gig" on empty dashboard | Add Event sheet opens with Gig tab selected |
| T3   | Admin/Member | Tap "+ Add Event" in Quick Actions | Add Event sheet opens with Rehearsal tab selected (unchanged) |
| T4   | Contributor (no gig perm) | View empty dashboard | Both buttons disabled (grayed out) |
| T5   | Contributor (with gig perm) | Tap "Create Gig" on empty dashboard | Add Event sheet opens with Gig tab selected |
| T6   | Contributor (with gig perm) | View "Create Rehearsal" button | Button is disabled (contributor cannot create rehearsals) |

**Platform coverage:** iOS, Web (Android/macOS optional — behavior is platform-agnostic)

**Flutter Analyze:** Must pass with 0 errors, 0 warnings.

---

## Additional Context

**Design consistency:**
The proposed solution aligns the `EmptyHomeState` widget with the pattern used in the non-empty-state dashboard sections (`_buildDashboardContent`), where each empty-state card explicitly specifies the event type to open.

**RBAC compliance:**
Permission gating remains unchanged:
- Contributors can only create gigs (if `canCreateGig` is true)
- Admin/Member users can create both rehearsals and gigs
- The disabled state is handled by passing `null` for the callback (button becomes non-interactive)

**Quick Actions section:**
The Quick Actions "+ Add Event" button is intentionally left with generic behavior (defaults to rehearsal for admin/member, gig for contributor). This is correct and should not change — it serves as a fallback CTA when the user doesn't specify which event type.

**Label change justification:**
The rehearsal button label changes from "Add Event" to "Create Rehearsal" for consistency with the gig button ("Create Gig") and to clarify what event type will be created when tapped.

---

*Architect Plan Complete — Ready for Engineer Implementation*
