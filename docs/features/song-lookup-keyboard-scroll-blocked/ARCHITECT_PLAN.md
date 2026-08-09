# ARCHITECT PLAN — Song Lookup Keyboard Scroll Blocked

## Feature Slug

`bug/song-lookup-keyboard-scroll-blocked`

---

## Problem Summary

In the Song Lookup overlay (`lib/features/setlists/widgets/song_lookup_overlay.dart`), the search results list cannot be scrolled while the on-screen keyboard is visible on iOS (and likely Android), even when there are enough results to overflow the viewport. The user can see a partially-cut-off result card at the bottom of the visible area, but dragging on it does not scroll the list.

---

## Root Cause

**Confidence: HIGH** (confirmed via code inspection)

`SongLookupOverlay.build()` never reads `MediaQuery.of(context).viewInsets.bottom` (the keyboard height) and does not adjust its layout when the keyboard appears.

The widget structure is:

```
Material > SafeArea > Container > ClipRRect > Column([
  _buildHeader(),           // 56px
  _buildSearchField(),      // 68px
  Divider,                  // 1px
  Expanded(_buildBody())    // Results ListView
])
```

When the keyboard appears:

1. `viewInsets.bottom` increases to the keyboard height (~336px on iPhone)
2. The layout never consults this value
3. `SafeArea` only accounts for device notches, not the keyboard
4. The `Expanded` widget calculates remaining space based on the full screen height
5. Flutter lays out the results `ListView` into the region the keyboard occupies
6. Touch input in that region is captured by the native keyboard surface, never delivered to Flutter
7. Scroll gestures starting on the partially-visible bottom card never register

---

## Reference Docs Consulted

Not applicable — this is a UI layout bug, not a domain feature requiring reference documentation.

---

## Existing System Analysis

**Current behavior:**

- Song Lookup overlay opens with search field auto-focused, keyboard appears immediately
- Results list is rendered in an `Expanded` widget within a `Column`
- No adjustment for keyboard height
- Bottom portion of results list is laid out underneath the keyboard region
- Touch input in that region is intercepted by the keyboard, scroll gestures fail

**Working pattern in codebase:**
`bulk_add_songs_overlay.dart` line 240 demonstrates the correct approach:

```dart
final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

return Material(
  color: Colors.transparent,
  child: SafeArea(
    // Don't apply bottom safe area when keyboard is showing
    bottom: keyboardHeight == 0,
    child: Container(
      margin: EdgeInsets.fromLTRB(
        Spacing.space16,
        Spacing.space16,
        Spacing.space16,
        keyboardHeight > 0 ? 0 : Spacing.space16,
      ),
      ...
```

This pattern:

1. Reads `viewInsets.bottom` to detect keyboard presence
2. Disables `SafeArea.bottom` when keyboard is showing (keyboard provides its own safe area)
3. Adjusts `Container.margin` to eliminate bottom margin when keyboard is showing
4. Result: content area shrinks to fit above the keyboard, scrolling works normally

**Confirmed usage:** Grep search shows 8 widgets in `lib/features/setlists/widgets/` already use this pattern:

- `bulk_add_songs_overlay.dart` (line 240)
- `song_details_bottom_sheet.dart` (line 877)
- `song_enrichment_review_sheet.dart` (line 239)
- `custom_tuning_modal.dart` (line 213)
- `pause_creator.dart` (line 153)
- `set_break_creator.dart` (line 95)
- `setlist_picker_bottom_sheet.dart` (line 237)
- `song_notes_drawer.dart` (line 87)

---

## Proposed Solution

Apply the proven keyboard-avoidance pattern from `bulk_add_songs_overlay.dart` to `song_lookup_overlay.dart`.

**Changes:**

1. In `SongLookupOverlay.build()`, add at the start of the method:

   ```dart
   final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
   ```

2. Modify the `SafeArea` widget to conditionally disable bottom padding:

   ```dart
   child: SafeArea(
     bottom: keyboardHeight == 0,  // Don't apply bottom safe area when keyboard is showing
     child: Container(
   ```

3. Change the `Container.margin` from:
   ```dart
   margin: const EdgeInsets.all(Spacing.space16),
   ```
   to:
   ```dart
   margin: EdgeInsets.fromLTRB(
     Spacing.space16,
     Spacing.space16,
     Spacing.space16,
     keyboardHeight > 0 ? 0 : Spacing.space16,
   ),
   ```

This causes the overlay container to:

- Shrink its bottom margin to 0 when the keyboard appears
- Respect the keyboard's own safe area
- Allow the `Expanded` results `ListView` to occupy only the space above the keyboard
- Preserve touch input delivery to the Flutter app in the visible results area

---

## Database Impact

**Not applicable.** No database schema, RLS, RPC, trigger, or migration changes required.

---

## Flutter Architecture Changes

**State:** No state changes. No new providers, notifiers, or repositories.

**Widgets:** Layout-only modification to `SongLookupOverlay.build()`. No changes to widget tree structure, no new widgets introduced.

**Repositories:** Not affected.

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                     | Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | In `build()` method: (1) Add `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` at line ~351. (2) Modify `SafeArea` at line ~353 to set `bottom: keyboardHeight == 0`. (3) Change `Container.margin` at line ~354 from `EdgeInsets.all(Spacing.space16)` to `EdgeInsets.fromLTRB(Spacing.space16, Spacing.space16, Spacing.space16, keyboardHeight > 0 ? 0 : Spacing.space16)`. (4) Add inline comment: `// Don't apply bottom safe area when keyboard is showing`. |

---

## Files Off-Limits

| File                                                              | Reason                                                                    |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`       | Already handles keyboard correctly — reference only, do not modify        |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`    | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/print_options_bottom_sheet.dart`   | Not affected (TextField in dialog context, uses DraggableScrollableSheet) |
| `lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart`   | Not affected (no keyboard inputs)                                         |
| `lib/features/setlists/widgets/custom_tuning_modal.dart`          | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/pause_creator.dart`                | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/set_break_creator.dart`            | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`  | Already handles keyboard correctly                                        |
| `lib/features/setlists/widgets/song_notes_drawer.dart`            | Already handles keyboard correctly                                        |
| All search/filter logic                                           | Not in scope — only layout changes                                        |
| All state management                                              | Not in scope — no state changes                                           |
| All business logic                                                | Not in scope — UI-only fix                                                |

---

## System Impact Map

| System                                 | Impact                                                                                                                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                                                                       |
| Rehearsals                             | unaffected                                                                                                                                                       |
| Setlists / Catalog                     | **affected** — Song Lookup overlay is used when adding songs to setlists                                                                                         |
| Members / RBAC                         | unaffected                                                                                                                                                       |
| Auth / Session                         | unaffected                                                                                                                                                       |
| Routing                                | unaffected                                                                                                                                                       |
| Notifications                          | unaffected                                                                                                                                                       |
| Platform (iOS / Android / Web / macOS) | **affected** — iOS confirmed; Android likely has same issue; Web/macOS keyboard behavior differs (floating, not fullscreen) so less critical but fix is harmless |

---

## Regression Risk

**Level: LOW**

**Rationale:**

- Single file modification, 3 lines changed
- Proven pattern already used successfully in 8+ widgets in the same codebase (`bulk_add_songs_overlay.dart`, `song_details_bottom_sheet.dart`, etc.)
- No business logic, state management, or data flow changes
- No database, API, or backend changes
- Isolated to UI layout adjustment when keyboard appears
- Flutter's `MediaQuery.viewInsets` is a stable, documented API used throughout the framework
- No changes to initialization order, auth flow, routing, or cross-feature dependencies
- Change is additive (reads a value, adjusts layout) — does not remove or disable existing behavior
- Worst-case failure mode: layout unchanged (same as current bug), not a new crash or data corruption

---

## Engineer Task Breakdown

### Task 1: Apply keyboard-avoidance pattern to SongLookupOverlay

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`

**Steps:**

1. Locate the `build()` method (starts around line 350)
2. At the start of the method body (before the `return` statement), add:
   ```dart
   final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
   ```
3. Locate the `SafeArea` widget (around line 353)
4. Add the `bottom` parameter immediately after the opening `SafeArea(`:
   ```dart
   child: SafeArea(
     bottom: keyboardHeight == 0,  // Don't apply bottom safe area when keyboard is showing
     child: Container(
   ```
5. Locate the `Container.margin` property (around line 354)
6. Replace `margin: const EdgeInsets.all(Spacing.space16),` with:
   ```dart
   margin: EdgeInsets.fromLTRB(
     Spacing.space16,
     Spacing.space16,
     Spacing.space16,
     keyboardHeight > 0 ? 0 : Spacing.space16,
   ),
   ```

**Verification:**

- `flutter analyze` must pass with 0 errors
- Visual inspection: code matches the pattern in `bulk_add_songs_overlay.dart` line 240

### Task 2: Run flutter analyze

```bash
flutter analyze
```

Must produce 0 errors. If errors exist, resolve them before proceeding.

### Task 3: Generate git diff

```bash
git diff lib/features/setlists/widgets/song_lookup_overlay.dart
```

Verify diff shows exactly 3 changes:

1. Addition of `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;`
2. Addition of `bottom: keyboardHeight == 0,` to `SafeArea`
3. Replacement of `margin` with conditional `EdgeInsets.fromLTRB()`

No other files should show modifications.

---

## Verification Plan

### Tier 1 — Pre-Deployment (Development Environment)

**Not applicable** — this is a client-side UI bug, no database or edge function changes.

### Tier 2 — Post-Implementation (Device Testing)

#### Test 1: Keyboard obscuration resolved

**Platform:** iOS device (iPhone with on-screen keyboard)

**Steps:**

1. Open the app and navigate to any setlist
2. Tap the "+" button to add a song
3. Tap "Song Lookup" (or equivalent action that opens the Song Lookup overlay)
4. Observe: overlay opens, search field is auto-focused, keyboard appears
5. Type a search query that produces at least 5 results (e.g., "the")
6. Scroll to the bottom of the results list
7. Observe: you can see a partially-cut-off result card at the bottom
8. **Drag upward starting from the partially-visible card**
9. **Expected:** List scrolls smoothly, revealing more results below
10. **Before fix:** Scroll gesture does not register, list does not move

**Pass criteria:** Results list scrolls normally when dragging on cards in the bottom visible area.

#### Test 2: No regression when keyboard is hidden

**Platform:** iOS device

**Steps:**

1. Open the Song Lookup overlay (keyboard appears)
2. Tap the "Back" button or swipe down to dismiss the keyboard
3. Observe: keyboard hides
4. Scroll the results list up and down
5. **Expected:** List scrolls normally, bottom margin of 16px is visible below the last result

**Pass criteria:** No visual layout glitches, bottom spacing is correct when keyboard is hidden.

#### Test 3: Layout on Android

**Platform:** Android device (emulator or physical)

**Steps:**

1. Repeat Test 1 on Android
2. Verify scroll behavior is correct when keyboard is showing
3. Verify layout is correct when keyboard is hidden

**Pass criteria:** Same behavior as iOS — scrolling works with keyboard visible, layout is correct without keyboard.

#### Test 4: Layout on Web (optional — low priority)

**Platform:** Chrome/Safari on desktop

**Steps:**

1. Open the Song Lookup overlay
2. Click in the search field (keyboard does not appear on desktop)
3. Verify layout is visually correct
4. Scroll results list

**Pass criteria:** No visual regressions. (Note: Desktop keyboards are floating/docked, not fullscreen like mobile, so the bug does not reproduce. The fix is harmless on Web.)

#### Test 5: No impact on sibling overlays

**Platform:** iOS device

**Steps:**

1. Open "Bulk Add Songs" overlay (tap "Bulk Add" button if available)
2. Verify keyboard handling still works correctly (should not have changed)
3. Open a song detail sheet and edit a field (BPM, Duration, etc.)
4. Verify keyboard handling still works correctly

**Pass criteria:** No regressions in other overlays/sheets.

---

## QA Regression Areas

QA must specifically test:

### Primary Validation

1. **Song Lookup overlay scroll with keyboard visible** (iOS, Android) — primary bug fix
2. **Song Lookup overlay layout with keyboard hidden** (iOS, Android) — verify no new glitch

### Regression Coverage

3. **Bulk Add Songs overlay** — verify no regression in keyboard handling
4. **Song Details bottom sheet** — verify inline editing (BPM, Duration, Tuning) still works correctly with keyboard
5. **Song Enrichment Review sheet** — verify keyboard handling for Duration/BPM fields
6. **Custom Tuning modal** — verify keyboard handling for string input fields
7. **Setlist Picker bottom sheet** — verify search field keyboard handling
8. **Song Notes drawer** — verify keyboard handling for notes text input

### Platform Coverage

- iOS (primary)
- Android (high priority — likely same issue)
- Web (low priority — different keyboard model, but fix should be harmless)

---

## Rollout / Migration Strategy

**Not applicable.** This is a client-side UI fix. No database migration, no edge function deployment, no backward compatibility concerns.

**Deployment:**

1. Engineer implements fix
2. QA validates on iOS and Android
3. Merge to `main`
4. Deploy web build: `./tools/deploy_web.sh`
5. iOS/Android: next app store release

---

## Out of Scope

Explicitly **not** included in this fix:

- **Business logic changes:** Search logic, filtering, external API calls, song addition flow
- **State management changes:** No changes to controllers, providers, repositories, or notifiers
- **Other overlays/sheets:** `bulk_add_songs_overlay.dart`, `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`, `print_options_bottom_sheet.dart`, `tuning_picker_bottom_sheet.dart` — these are either already correct or not affected
- **Keyboard dismissal logic:** Focus handling, "Done" button, tap-to-dismiss behavior
- **Performance optimization:** Debounce timing, search result rendering, skeleton states
- **Visual redesign:** Colors, spacing (except the conditional bottom margin), typography, animations
- **Accessibility:** Keyboard navigation, screen reader support (existing behavior preserved)
- **Android-specific keyboard handling:** Soft input mode, resize behavior (Flutter's default behavior is sufficient)
- **Web keyboard handling:** Desktop keyboards behave differently (floating, not fullscreen), no mobile-style obscuration issue exists

---

**END OF ARCHITECT PLAN**
