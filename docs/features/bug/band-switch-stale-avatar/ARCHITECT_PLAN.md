# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/band-switch-stale-avatar`

---

## 2. Problem Summary

When a user switches between bands in the band switcher, the avatar color from the previously selected band persists on the newly selected band in the home screen header. The stale color corrects itself only when the user edits the currently selected band and saves changes, which forces a provider refresh.

Expected: Avatar color updates immediately when band is switched.
Actual: Avatar color shows old band's color until an unrelated band edit occurs.

---

## 3. Root Cause

**Primary root cause:** `selectBand()` in `ActiveBandNotifier` updates `activeBandProvider` state but does NOT invalidate `displayBandProvider` or call `ref.invalidate()` on other band-scoped providers that may cache band data.

**Confidence:** `HIGH`

### Evidence from code

1. **`selectBand()` implementation** ([active_band_controller.dart#L312-L331](lib/features/bands/active_band_controller.dart#L312-L331)):
   ```dart
   Future<void> selectBand(Band band) async {
     if (!state.userBands.any((b) => b.id == band.id)) {
       return;
     }
     await _persistBandId(band.id);
     state = state.copyWith(activeBand: band);
     
     // Force permissions to re-fetch for the new band context
     ref.invalidate(currentUserPermissionsProvider);
     
     // Clear stale setlist selection...
     ref.read(selectedSetlistProvider.notifier).clear();
     
     // Navigate to Dashboard when switching bands
     ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
   }
   ```
   - Only invalidates `currentUserPermissionsProvider`
   - Does NOT invalidate `displayBandProvider` or `bandFullStateProvider`
   - Does NOT invalidate other band-scoped controllers

2. **`displayBandProvider` watches `activeBandProvider`** ([active_band_controller.dart#L519-L533](lib/features/bands/active_band_controller.dart#L519-L533)):
   ```dart
   final displayBandProvider = Provider<Band?>((ref) {
     final draftState = ref.watch(draftBandProvider);
     final activeState = ref.watch(activeBandProvider);
     
     if (draftState.isEditing && draftState.band != null) {
       return draftState.band;
     }
     
     return activeState.activeBand;
   });
   ```
   - This should automatically update when `activeBandProvider` changes
   - However, Riverpod Providers cache their output based on return value equality

3. **Band model lacks value-based equality** ([app/models/band.dart#L1-L50](lib/app/models/band.dart#L1-L50)):
   - Band does NOT override `operator ==` and `hashCode`
   - Falls back to identity-based equality (same reference only)
   - This can cause Riverpod caching issues if the same Band data is returned

4. **ActiveBandState has value-based equality** ([active_band_controller.dart#L208-L225](lib/features/bands/active_band_controller.dart#L208-L225)):
   - Overrides `==` with field-value comparison
   - Compares `activeBand?.avatarColor` and other fields by value
   - However, when a different band is selected, the ID should differ, making states unequal

5. **Avatar color is consumed via `displayBandProvider`** ([home_tab_content.dart#L562, #L974](lib/features/home/home_tab_content.dart#L562)):
   ```dart
   final displayBand = ref.watch(displayBandProvider);
   ...
   bandAvatarColor: displayBand?.avatarColor ?? activeBand?.avatarColor,
   ```
   - HomeTabContent watches `displayBandProvider`
   - Passes `displayBand?.avatarColor` to HomeAppBar
   - Falls back to `activeBand?.avatarColor` if displayBand is null

### Why the issue persists until editing

When editing a band and saving:
- `ref.read(activeBandProvider.notifier).updateActiveBand(updatedBand)` is called
- This updates state AND creates new Band objects in the list
- The state change propagates more forcefully due to the list rebuild
- Additionally, after editing, callers may explicitly invalidate related providers

### Why confidence is HIGH, not MEDIUM

- Exact code path is visible and confirms selectBand() lacks necessary invalidations
- displayBandProvider correctly watches activeBandProvider but relies on automatic notification
- Band model equality is identity-based, which can interfere with Riverpod's caching
- The pattern matches known Riverpod Provider caching gotchas

---

## 4. Reference Docs Consulted

- None exist in the workspace at `docs/reference/notifications/` or similar for band state management
- Relied on copilot-instructions.md and BAND_ROADIE_DOCUMENTATION.md for architectural patterns

---

## 5. Existing System Analysis

### 5.1 Band state flow

1. User taps band in switcher
2. `HomeScreen._handleBandSelected(band)` is called ([home_screen.dart#L155-L167](lib/features/home/home_screen.dart#L155-L167))
3. Manually resets gig/rehearsal state:
   ```dart
   ref.read(gigProvider.notifier).resetForBandChange();
   ref.read(rehearsalProvider.notifier).resetForBandChange();
   ```
4. Calls `selectBand(band)` on `activeBandProvider.notifier`
5. `selectBand()` updates state and navigates to Dashboard
6. HomeTabContent rebuilds and reads band data

### 5.2 Avatar color display path

1. HomeTabContent watches `displayBandProvider` (line 562)
2. HomeTabContent watches `activeBandProvider` (line 500)
3. HomeTabContent watches `draftLocalImageProvider` (line 563)
4. Passes these values to HomeAppBar:
   - `bandAvatarColor: displayBand?.avatarColor ?? activeBand?.avatarColor`
   - `bandImageUrl: displayBand?.imageUrl ?? activeBand?.imageUrl`
   - `localImageFile: ref.watch(draftLocalImageProvider)`
5. HomeAppBar is a StatelessWidget that renders BandAvatar with these props
6. BandAvatar uses `getAvatarColor(avatarColor)` to map Tailwind class to Color

### 5.3 Provider dependency tree

```
activeBandProvider (NotifierProvider)
  ├─ activeBandIdProvider (Provider) → reads activeBand?.id
  ├─ displayBandProvider (Provider) → returns draft or active band
  │   ├─ draftBandProvider (NotifierProvider)
  │   └─ activeBandProvider
  ├─ currentUserPermissionsProvider (FutureProvider) [invalidated in selectBand]
  ├─ bandFullStateProvider (FutureProvider)
  │   └─ activeBandIdProvider
  ├─ gigProvider (NotifierProvider)
  │   └─ bandFullStateProvider
  ├─ rehearsalProvider (NotifierProvider)
  │   └─ bandFullStateProvider
  ├─ draftLocalImageProvider (Provider)
  │   └─ draftBandProvider
  └─ selectedSetlistProvider (NotifierProvider) [cleared in selectBand]
```

### 5.4 Why automatic refresh doesn't work

When `selectBand(bandB)` is called:
1. `state = state.copyWith(activeBand: bandB)` updates the NotifierProvider
2. Riverpod **should** notify all listeners
3. `displayBandProvider` watchers should re-evaluate
4. BUT: If `displayBandProvider` caches based on output equality and the Band object doesn't have value-based `==`, the cache might not invalidate correctly
5. Additionally, no explicit `ref.invalidate(displayBandProvider)` is called to guarantee refresh

---

## 6. Proposed Solution

### Minimal fix approach

Call `ref.invalidate(displayBandProvider)` in `selectBand()` to force displayBandProvider to re-evaluate and notify all listeners.

This ensures the avatar (and any other display-related state derived from the active band) is immediately refreshed when switching bands.

### Why this is minimal and safe

- One-line change in one function
- Explicitly guarantees that displayBandProvider consumers are notified
- No architectural changes required
- No impact on other systems (permissions, gigs, rehearsals already have their own reset logic)
- Follows the pattern already used for invalidating `currentUserPermissionsProvider`

### Alternative: Full invalidation approach

Invalidate all band-scoped providers in `selectBand()`:
```dart
ref.invalidate(displayBandProvider);
ref.invalidate(bandFullStateProvider);
ref.invalidate(gigProvider);
ref.invalidate(rehearsalProvider);
ref.invalidate(membersProvider);
// ... others
```

**Not recommended** because:
- Overkill for an avatar-display issue
- Risk of unintended side effects across multiple controllers
- GigNotifier and RehearsalNotifier already have `resetForBandChange()` called before `selectBand()`
- Violates minimal change principle

---

## 7. Database Impact

**Database: not applicable**

No database changes are required. This is a client-side state management issue.

---

## 8. Flutter Architecture Changes

**Affected files:**
- `lib/features/bands/active_band_controller.dart` — add `ref.invalidate()` call in `selectBand()`

**No changes required to:**
- State model (ActiveBandState, DraftBandState) — no equality issues
- Providers — displayBandProvider logic is correct, just needs invalidation guarantee
- Widgets — HomeAppBar, HomeTabContent all work correctly
- Riverpod initialization or dependency tree

---

## 9. Files to Create

`none`

---

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/bands/active_band_controller.dart` | In `selectBand()` method, add `ref.invalidate(displayBandProvider);` after updating state and before navigating. This forces all consumers of displayBandProvider (header avatar) to re-evaluate immediately. |

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `lib/app/models/band.dart` | Band equality is identity-based intentionally; overriding `==` would have broader implications across the app and is not necessary for this fix |
| `lib/features/bands/active_band_controller.dart` — ActiveBandState's `==` operator | Equality semantics are correct and used correctly; the issue is Provider caching, not state equality |
| `lib/features/home/home_screen.dart` | Band selection logic is correct; manual resets already happen before selectBand() |
| `lib/features/home/home_tab_content.dart` | Display logic correctly watches displayBandProvider; no changes needed |

---

## 12. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected — gigProvider manually reset before selectBand |
| Rehearsals | unaffected — rehearsalProvider manually reset before selectBand |
| Setlists / Catalog | unaffected — selectedSetlistProvider cleared in selectBand |
| Members / RBAC | unaffected — permissions invalidated in selectBand |
| Auth / Session | unaffected |
| Routing | unaffected — navigation already happens in selectBand |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | all affected equally — display logic is platform-agnostic |
| **Avatar display** | **affected** — directly fixed by invalidating displayBandProvider |

---

## 13. Regression Risk

**Risk level: `LOW`**

Rationale:
- Invalidating `displayBandProvider` has narrowly scoped effect — only rebuilds widgets watching that provider
- displayBandProvider only feeds the header (HomeAppBar) and empty state (NoBandState)
- No state mutations, no business logic changes
- Follows established pattern (already invalidating `currentUserPermissionsProvider` in same function)
- Cannot cause loading flickers because displayBandProvider is a simple Provider, not FutureProvider
- No race conditions — invalidation happens immediately during selectBand execution

---

## 14. Engineer Task Breakdown

1. **Modify `selectBand()` in `ActiveBandNotifier`** ([active_band_controller.dart#L312](lib/features/bands/active_band_controller.dart#L312)):
   - After line: `state = state.copyWith(activeBand: band);`
   - Add: `ref.invalidate(displayBandProvider);`
   - This forces displayBandProvider to re-evaluate and notify all listeners
   - Justification: Guarantees displayBand watchers get fresh data immediately

2. **Verify no import needed**: displayBandProvider is defined in the same file, so no new import required.

3. **Build and run manual test**: (QA responsibility, not Engineer)
   - Switch between two bands with different avatar colors
   - Verify avatar color updates immediately without delay or flickering
   - No need for gigs/rehearsals to re-load (they refresh separately)

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before code review)

```dart
// PRE-DEPLOY TEST 1:
// Verify displayBandProvider is accessible and can be invalidated
// This is a code-inspection test — does the imported provider exist?
// If this fails, the change cannot be made as-is.

// In active_band_controller.dart, verify:
// - displayBandProvider is defined in the same file
// - displayBandProvider is exported (or used only internally)
// - No circular dependency: displayBandProvider watches activeBandProvider, 
//   and selectBand() is in ActiveBandNotifier (not in displayBandProvider body)
```

```dart
// PRE-DEPLOY TEST 2:
// Dart analyzer check — no syntax errors or type mismatches
// Run: flutter analyze
// Expected: 0 errors in active_band_controller.dart
```

### Tier 2 — Post-deployment (run after change is committed and app is built)

```dart
// POST-DEPLOY TEST 1:
// Manual UI test — switch bands with different avatar colors
// Steps:
// 1. Launch app and load dashboard
// 2. Note the current band's avatar color
// 3. Tap avatar or open band switcher
// 4. Select a band with a visibly different avatar color (e.g., red vs. blue)
// 5. Observe HomeAppBar avatar color immediately
// Expected: Avatar color updates without delay
// Regression check: No loading spinner, no blank flicker, no "Setting up the stage..." screen

// POST-DEPLOY TEST 2:
// Verify displayBandProvider.invalidate works at runtime
// This is implicitly tested by TEST 1 — if the avatar color updates,
// the invalidation worked. If it still shows stale color, invalidation failed.
```

```dart
// POST-DEPLOY TEST 3:
// Edge case — rapid band switching
// Steps:
// 1. Open band switcher
// 2. Rapidly tap different bands (tap every 200-300ms for ~3 seconds)
// 3. Let it settle
// Expected: Avatar eventually shows the last selected band's color
// Regression check: No crash, no infinite loading, no visual glitches
```

```dart
// POST-DEPLOY TEST 4:
// Confirm selectBand was modified correctly
// Code inspection: Open active_band_controller.dart and verify:
// - selectBand() method contains ref.invalidate(displayBandProvider);
// - invalidate call is AFTER state update and BEFORE navigation
// - No additional unrelated changes present
```

---

## 16. QA Regression Areas

- **Primary**: Band avatar color updates immediately when switching bands (all platforms)
- **Header display**: Band name, hamburger menu, avatar all render correctly after switch
- **Empty state**: NoBandState avatar display (also uses displayBandProvider) updates on creation
- **Edit band**: Draft band preview still works (displayBandProvider still returns draft during editing)
- **No regression**: Gig/rehearsal data still loads correctly (their reset logic unchanged)
- **No regression**: Permissions re-fetch still works (currentUserPermissionsProvider invalidation unchanged)
- **No regression**: Navigation to dashboard still happens (navigation unchanged)
- **No regression**: No loading flickers or blank screens (displayBandProvider is synchronous)

---

## 17. Rollout / Migration Strategy

Single-line change, no rollout sequence needed:

1. Engineer modifies `selectBand()` and commits
2. QA runs manual UI tests on web and mobile
3. Merge to main when QA approves
4. No staged rollout required

---

## 18. Out of Scope

- Refactoring Band to use value-based equality (might have unintended side effects elsewhere)
- Adding loading states or animations to band switching
- Prefetching band data before switch completes
- Changing the band switcher UI or interaction model
- Modifying how gigs/rehearsals refetch (they have separate reset logic)

---

## Stop-and-Escalate Conditions

None identified. This is a straightforward fix with LOW regression risk and HIGH diagnostic confidence.

If any of the following occurs during implementation, escalate to Tony:
1. displayBandProvider cannot be imported or invalidated in selectBand() (suggests a scope/visibility issue)
2. Invalidating displayBandProvider causes compile errors or unexpected cascading invalidations
3. Manual UI test shows avatar still not updating after the change (suggests a different root cause)
4. Performance regression or infinite loop observed during rapid band switching
