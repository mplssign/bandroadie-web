# Architect Plan — Dashboard Hang on Same-Band Reselection

## 1. Feature Slug

`bug/same-band-reselect-dashboard-hang`

---

## 2. Problem Summary

Tapping the band avatar to open the band switcher, then tapping the band that is already active, permanently strands the dashboard on "Setting up the stage..." loading spinner. The user must kill and relaunch the app. Selecting a different band works correctly.

---

## 3. Root Cause

**Confidence: HIGH** — Confirmed via direct code inspection.

Band switcher tap handlers unconditionally call:

1. `ref.read(gigProvider.notifier).resetForBandChange()` — sets `state = GigState(isLoading: true)`
2. `ref.read(rehearsalProvider.notifier).resetForBandChange()` — sets `state = RehearsalState(isLoading: true)`
3. `ref.read(activeBandProvider.notifier).selectBand(band)` — updates active band state

When the tapped band equals the active band:

- `selectBand()` updates state but `activeBandId` doesn't change (same ID value)
- `activeBandIdProvider` doesn't notify (no value change)
- `bandFullStateProvider` (which watches `activeBandIdProvider`) doesn't refire
- `GigNotifier.build()` and `RehearsalNotifier.build()` never re-run to consume data
- The manually-set `isLoading: true` state persists indefinitely

The `resetForBandChange()` method bypasses the provider build lifecycle by directly mutating state. This works when the band actually changes (causing `bandFullStateProvider` to refire), but creates a permanent loading state when the band is already active.

The 15s RPC timeout (commit `c3b9ac9`) doesn't engage because no RPC is in flight.

**Provider dependency chain:**

```
activeBandProvider.selectBand(band)
  → activeBandIdProvider (no change if same band)
    → bandFullStateProvider (no refire if dependency didn't change)
      → GigNotifier.build() / RehearsalNotifier.build() (never re-run)
```

**Code locations:**

- `resetForBandChange()` definitions: `gig_controller.dart:237-240`, `rehearsal_controller.dart:223-225`
- `selectBand()`: `active_band_controller.dart:320-333`
- `activeBandIdProvider`: `active_band_controller.dart:515-517`
- `bandFullStateProvider`: `band_full_state.dart:120-126`
- Provider build methods: `gig_controller.dart:108-141`, `rehearsal_controller.dart:102-128`

---

## 4. Reference Docs Consulted

- `docs/reference/architecture/architecture.md` — State management patterns, Riverpod conventions
- `docs/agents/GUARDRAILS.md` — Unidirectional data flow, code change discipline
- `docs/agents/OPERATING_MODEL.md` — Minimal diff surface principle

---

## 5. Existing System Analysis

**Band Selection Flow:**

1. User taps band avatar → band switcher drawer opens
2. User taps a band → tap handler fires:
   - Calls `resetForBandChange()` on gig/rehearsal notifiers (imperative state mutation)
   - Calls `selectBand(band)` on active band notifier (reactive state update)
   - Closes drawer, navigates to dashboard (some call sites)
3. If band changed → `activeBandIdProvider` notifies → `bandFullStateProvider` refires → notifiers rebuild with fresh data
4. If band is same → `activeBandIdProvider` doesn't notify → `bandFullStateProvider` doesn't refire → notifiers never rebuild → `isLoading: true` persists

**Current call sites with reset+select pattern:**

- `home_screen.dart:162-170` — Dashboard band switcher
- `app_shell.dart:311-316` — AppBar band switcher (always navigates to dashboard)
- `calendar_screen.dart:155-161` — Calendar band switcher
- `setlists_screen.dart:416-421` — Setlists band switcher

**Call site NOT affected:**

- `no_band_shell.dart:710` — Only calls `selectBand()`, no reset pattern

**Intent of reset pattern (from code comments):**

- `home_screen.dart:162`: "Reset gig/rehearsal state before band switch to clear stale errors"
- Purpose: Show loading immediately, clear stale error messages from previous failed load

---

## 6. Proposed Solution

**Guard at call sites:** Add early-return guard at the top of each band selection handler:

```dart
final currentBandId = ref.read(activeBandIdProvider);
if (band.id == currentBandId) return;
```

This prevents ALL side effects of re-selecting the same band, not just the reset calls:

- No unnecessary provider invalidations (`displayBandProvider`, `currentUserPermissionsProvider`)
- No unnecessary setlist selection clear
- No unnecessary tab navigation
- No unnecessary SharedPreferences write

**Why this solution:**

1. **Minimal change** — 2 lines added per call site, no method signature changes
2. **Explicit and auditable** — Guard is visible at each call site, easy to verify in code review
3. **Prevents all side effects** — Not just the loading state bug, but also unnecessary downstream work
4. **Aligns with UX expectation** — Tapping the already-active band should be a no-op (close drawer, no reload)
5. **Safer than alternatives** — Doesn't modify `selectBand()` behavior (which may have legitimate reasons to run even for same band in other contexts)

**Alternative considered and rejected:**

- Guard inside `selectBand()` — Would change behavior for all callers, not just band switcher UI
- Remove `resetForBandChange()` calls — Would leave stale errors visible during band switch
- Conditional `resetForBandChange()` — Requires method signature change and updates to all call sites

---

## 7. Database Impact

**Not applicable** — This is a client-side state management fix with no database changes.

---

## 8. Flutter Architecture Changes

**State management:**

- No changes to provider definitions or build methods
- No changes to state classes or notifier lifecycle
- Guards added to UI event handlers only

**Affected components:**

- Band selection handlers in 4 screen files (home, app_shell, calendar, setlists)
- All guards read `activeBandIdProvider` to compare against tapped band

**Data flow:**

- Current: tap handler always calls reset → selectBand → (maybe) provider chain fires
- After fix: tap handler checks if same band → early return OR (reset → selectBand → provider chain fires)

---

## 9. Files to Create

**None**

---

## 10. Files to Modify

| File                                         | Change                                                                                                                |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/home_screen.dart`         | Add guard at top of `_onBandSelected()` handler (~line 162): `if (band.id == ref.read(activeBandIdProvider)) return;` |
| `lib/features/shell/app_shell.dart`          | Add guard at top of `onBandSelected:` callback (~line 311): `if (band.id == ref.read(activeBandIdProvider)) return;`  |
| `lib/features/calendar/calendar_screen.dart` | Add guard at top of `_onBandSelected()` method (~line 155): `if (band.id == ref.read(activeBandIdProvider)) return;`  |
| `lib/features/setlists/setlists_screen.dart` | Add guard at top of `_onBandSelected()` method (~line 416): `if (band.id == ref.read(activeBandIdProvider)) return;`  |

**Placement:** Guard must be the first statement in each handler, before `_closeBandSwitcher()`, `onClose()`, or any debug prints.

---

## 11. Files Off-Limits

| File                                                | Reason                                                                             |
| --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `lib/features/bands/active_band_controller.dart`    | No changes to `selectBand()` behavior — other callers may rely on current behavior |
| `lib/features/bands/band_full_state.dart`           | No changes to provider dependency chain                                            |
| `lib/features/gigs/gig_controller.dart`             | No changes to `resetForBandChange()` or build method                               |
| `lib/features/rehearsals/rehearsal_controller.dart` | No changes to `resetForBandChange()` or build method                               |
| `lib/features/shell/no_band_shell.dart`             | Does not use reset pattern, unaffected by bug                                      |
| `lib/main.dart`                                     | Initialization order must not change                                               |

---

## 12. System Impact Map

| System                                 | Impact                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| Gigs                                   | unaffected (fix prevents unnecessary reset when same band selected)    |
| Rehearsals                             | unaffected (fix prevents unnecessary reset when same band selected)    |
| Setlists / Catalog                     | unaffected                                                             |
| Members / RBAC                         | unaffected                                                             |
| Auth / Session                         | unaffected                                                             |
| Routing                                | unaffected (tab navigation still happens for different band selection) |
| Notifications                          | unaffected                                                             |
| Platform (iOS / Android / Web / macOS) | unaffected (fix is platform-agnostic, applies to all)                  |

---

## 13. Regression Risk

**Level: LOW**

**Rationale:**

- Change is localized to 4 UI event handlers (8 lines total)
- No changes to provider lifecycle, state classes, or build methods
- No changes to database, RLS, or backend logic
- Guard is idempotent — only affects same-band tap case, which currently hangs
- Different-band selection continues to work exactly as before (guard doesn't fire)
- No async gaps, no lifecycle interactions, no disposal concerns

**Risk factors considered:**

- Number of affected systems: 0 (band switcher is UI-only concern)
- Auth/session/routing touched: No
- Database mutations: No
- Shared code paths: Only band selection, but guard is very specific

---

## 14. Engineer Task Breakdown

**Task 1: Add guard in `home_screen.dart`**

- Locate `_onBandSelected(Band band)` method (~line 162)
- Insert guard as first statement:
  ```dart
  final currentBandId = ref.read(activeBandIdProvider);
  if (band.id == currentBandId) return;
  ```
- Verify indentation matches surrounding code
- Ensure guard is BEFORE `_closeBandSwitcher()` call

**Task 2: Add guard in `app_shell.dart`**

- Locate `onBandSelected: (band) {` callback (~line 311)
- Insert guard as first statement (same pattern as Task 1)
- Ensure guard is BEFORE `onClose()` call

**Task 3: Add guard in `calendar_screen.dart`**

- Locate `_onBandSelected(Band band)` method (~line 155)
- Insert guard as first statement (same pattern as Task 1)
- Ensure guard is BEFORE any debug prints or reset calls

**Task 4: Add guard in `setlists_screen.dart`**

- Locate `_onBandSelected(Band band)` method (~line 416)
- Insert guard as first statement (same pattern as Task 1)
- Ensure guard is BEFORE `_closeBandSwitcher()` call

**Task 5: Verify no other call sites**

- Run `grep -r "resetForBandChange" lib/` to confirm no additional call sites
- If new call sites exist, apply same guard pattern

**Task 6: Run analyzer**

- Execute `flutter analyze` from project root
- Confirm 0 errors before reporting implementation complete

---

## 15. Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — No database or backend changes.

### Tier 2 — Post-deployment

**Not applicable** — No database migrations or RPC changes. Verification is manual UI testing only (see QA Regression Areas below).

---

## 16. QA Regression Areas

**Primary (Bug Fix Verification):**

1. **Same-band reselection (Android)**
   - Launch app, wait for dashboard to load with gigs/rehearsals
   - Tap band avatar (top-right)
   - Tap the currently selected band
   - **Expected:** Drawer closes, dashboard shows existing data immediately (no spinner, no reload)
   - **Verify:** No spinner, no hanging, no app freeze

2. **Same-band reselection (Web)**
   - Repeat test above on web app (`app.bandroadie.com`)
   - **Expected:** Same behavior as Android

3. **Same-band reselection (iOS/macOS if available)**
   - Repeat test above on native platforms
   - **Expected:** Same behavior as Android

4. **Same-band reselection from all 4 affected screens**
   - Test from Dashboard (`home_screen.dart`)
   - Test from Calendar (`calendar_screen.dart`)
   - Test from Setlists (`setlists_screen.dart`)
   - Test from AppBar switcher (`app_shell.dart`)
   - **Expected:** All 4 screens handle same-band tap correctly (drawer closes, no reload)

**Secondary (Regression Prevention):**

5. **Different-band selection still works**
   - Create/join 2+ bands
   - Open band switcher, select a DIFFERENT band
   - **Expected:** Spinner shows briefly, dashboard reloads with new band's data
   - **Verify:** Gigs/rehearsals update, no errors, no hanging

6. **Band switcher from no-band state**
   - Create first band (triggers automatic selection via `loadAndSelectBand`)
   - **Expected:** Band is selected, dashboard loads
   - **Verify:** No regression in first-band flow

7. **Band switcher after error state**
   - Simulate error (disconnect network, trigger RPC timeout)
   - Observe error message on dashboard
   - Reconnect network, open band switcher, select same band
   - **Expected:** Drawer closes, error persists (no reload triggered)
   - Open band switcher, select DIFFERENT band
   - **Expected:** Spinner shows, error clears, fresh data loads

8. **Tab navigation after same-band tap**
   - Tap same band to close switcher
   - Navigate to Calendar tab, then back to Dashboard tab
   - **Expected:** Dashboard shows same data, no reload, no spinner

9. **Multiple rapid same-band taps**
   - Open/close band switcher rapidly, tapping same band each time
   - **Expected:** No spinner, no hanging, drawer closes each time

---

## 17. Rollout / Migration Strategy

**Not applicable** — No database migrations, no feature flags, no multi-phase rollout. Fix deploys with next web build; native apps receive fix in next release.

---

## 18. Out of Scope

**Not included in this fix:**

1. **Force-refresh on same-band tap** — The feature input suggested this as a possible UX improvement ("If you believe force-refresh is the better UX, flag it in the plan as an open question"). We are implementing the simpler behavior: same-band tap is a no-op (closes drawer, no reload). Force-refresh would require additional product decision and UX design (e.g., visual indication that a refresh is happening, vs. appearing to do nothing).

2. **Removing `resetForBandChange()` pattern** — While the reset+select pattern is architecturally awkward (imperative state mutation in a reactive system), removing it is out of scope. The current fix preserves the pattern for different-band selection (where it works correctly) and simply skips it for same-band selection (where it causes the bug).

3. **Refactoring band switcher UI** — Band switcher appears in 4 separate screens with duplicated logic. Consolidating into a single reusable component is out of scope.

4. **Loading state for no-band shell** — `no_band_shell.dart:710` does not use the reset pattern, so it's unaffected. However, it also doesn't show a loading state during band selection. Adding one is out of scope.

5. **Band switcher accessibility** — No changes to keyboard navigation, screen reader labels, or focus management.

6. **Band switcher analytics** — No tracking added for same-band vs. different-band taps.

---

**End of Plan**
