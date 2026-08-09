# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/song-lookup-keyboard-scroll-blocked-v2`

---

## 2. Problem Summary

The Song Lookup overlay's results list cannot be scrolled while the on-screen keyboard is visible on iPhone. A previous fix (PR #134, commit `f3e4b8a`, merged to `main`) was device-tested on a real iPhone and **confirmed to NOT resolve the issue**—the results list still cannot be scrolled to see items near the bottom when the keyboard is up.

---

## 3. Root Cause

**Confidence: HIGH** (confirmed via code observation and device testing)

The previous fix correctly reads `MediaQuery.of(context).viewInsets.bottom` (the actual keyboard height, typically ~336px on iPhone) but only uses it as a boolean condition:

- Toggles `SafeArea(bottom: keyboardHeight == 0)` — disables SafeArea bottom when keyboard is up
- Toggles Container bottom margin from `Spacing.space16` (16px) to `0` when keyboard is up

Neither approach actually **constrains the Container's height by the keyboard height**:

- `SafeArea` only accounts for device safe-area insets (notch/home indicator), not the keyboard
- Removing 16px of margin is ineffective against a 336px keyboard

The Container is unconstrained—it expands to fill the SafeArea, which fills the Material, which fills the screen. The keyboard appears _over_ the bottom of the screen, but the Container never shrinks. The Expanded ListView inside the Column tries to scroll, but its viewport extends underneath the keyboard because the Column (its parent) was never constrained by the actual keyboard height.

---

## 4. Reference Docs Consulted

No keyboard/overlay-specific reference documentation exists in `docs/reference/`. Checked:

- `docs/reference/ui/` — only contains `LANDING_PAGE_PREVIEW_GUIDE.md`
- `docs/reference/general/` — contains general docs, no UI pattern guidance

This is expected for a localized UI interaction fix.

---

## 5. Existing System Analysis

**Current widget tree:**

```
Material (transparent)
└─ SafeArea (bottom: keyboardHeight == 0)
   └─ Container (margin: 16px all sides, or 0 bottom when keyboard up)
      └─ ClipRRect (rounded corners)
         └─ Column
            ├─ _buildHeader() [56px]
            ├─ _buildSearchField() [~68px]
            ├─ Divider [1px]
            └─ Expanded
               └─ _buildBody() → ListView [scrollable results]
```

**Data flow:**

1. User taps "Add Song" in a setlist
2. `showSongLookupOverlay()` displays the overlay via `showGeneralDialog`
3. Search field auto-focuses after 350ms
4. User types query → debounced search (250ms)
5. Results populate ListView (catalog songs + external API results)
6. User taps result → `onSongAdded` callback → overlay closes

**Keyboard interaction (failed behavior):**

1. Keyboard appears → `viewInsets.bottom` = 336px
2. SafeArea bottom is disabled (removes home indicator padding)
3. Container bottom margin changes from 16px to 0px
4. Container height remains unconstrained (fills SafeArea)
5. ListView viewport extends 336px underneath keyboard
6. User cannot scroll to see bottom items

---

## 6. Proposed Solution

**Approach: Padding method**

Add `Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom))` inside the Container, wrapping the ClipRRect → Column structure. This shrinks the available vertical space by the actual keyboard height, forcing the Expanded ListView to scroll within a reduced viewport that does not extend underneath the keyboard.

**Why Padding over Scaffold:**

1. **Minimal change** — add one widget, no restructuring
2. **Keeps existing structure intact** — Material/SafeArea remain unchanged
3. **Explicit and clear** — directly consumes keyboard height as dimension
4. **Appropriate for dialog context** — introducing Scaffold inside `showGeneralDialog` is unconventional

**Code change:**

```dart
// BEFORE (current failed fix)
child: Container(
  margin: EdgeInsets.fromLTRB(
    Spacing.space16,
    Spacing.space16,
    Spacing.space16,
    keyboardHeight > 0 ? 0 : Spacing.space16,
  ),
  decoration: BoxDecoration(...),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
    child: Column(...),
  ),
),

// AFTER (correct fix)
child: Container(
  margin: const EdgeInsets.all(Spacing.space16), // Uniform margins
  decoration: BoxDecoration(...),
  child: Padding(
    padding: EdgeInsets.only(bottom: keyboardHeight),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Spacing.cardRadius),
      child: Column(...),
    ),
  ),
),
```

**Concrete dimensions when keyboard is up:**

- Keyboard height: ~336px
- Padding shrinks Column's available height by 336px
- Expanded ListView viewport ends just above keyboard
- User can scroll to see all results

---

## 7. Database Impact

**Not applicable** — pure client-side UI fix with no backend, database, or Supabase interaction.

---

## 8. Flutter Architecture Changes

**State management:** No changes — overlay remains stateful widget with local state  
**Widgets modified:** `SongLookupOverlay._build()` method only  
**Repositories:** No changes  
**Providers:** No changes  
**Services:** No changes

---

## 9. Files to Create

**None**

---

## 10. Files to Modify

| File                                                     | Changes                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_lookup_overlay.dart` | In `build()` method (lines ~360-375): <br/>1. Simplify Container margin to uniform `EdgeInsets.all(Spacing.space16)` (remove conditional toggle)<br/>2. Add `Padding` widget inside Container, wrapping ClipRRect with `padding: EdgeInsets.only(bottom: keyboardHeight)`<br/>3. Remove obsolete comment about margin toggle<br/>4. Keep SafeArea bottom toggle (defensive code, no harm) |

---

## 11. Files Off-Limits

| File                                                              | Reason                                                                  |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `lib/features/setlists/widgets/bulk_add_songs_overlay.dart`       | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart`    | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/setlists/widgets/song_enrichment_review_sheet.dart` | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/setlists/widgets/custom_tuning_modal.dart`          | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/gigs/widgets/pause_creator.dart`                    | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/gigs/widgets/set_break_creator.dart`                | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart`  | Uses same flawed 16px-margin pattern—unverified, separate future ticket |
| `lib/features/songs/widgets/song_notes_drawer.dart`               | Uses same flawed 16px-margin pattern—unverified, separate future ticket |

**Note:** The above 8 files all use the same unverified 16px-margin toggle pattern. They represent a latent risk but require individual device testing to confirm the bug exists in each context. This ticket addresses only the Song Lookup overlay where the bug has been device-confirmed.

---

## 12. System Impact Map

| System             | Impact                                                                                                     |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| Gigs               | unaffected                                                                                                 |
| Rehearsals         | unaffected                                                                                                 |
| Setlists / Catalog | **affected** — Song Lookup overlay is used for adding songs to setlists                                    |
| Members / RBAC     | unaffected                                                                                                 |
| Auth / Session     | unaffected                                                                                                 |
| Routing            | unaffected                                                                                                 |
| Notifications      | unaffected                                                                                                 |
| Platform           | **iOS: affected** (confirmed); Android/Web/macOS: unknown, likely affected if keyboard behavior is similar |

---

## 13. Regression Risk

**Level: LOW**

**Rationale:**

- Single file modified
- No database, auth, routing, or initialization order changes
- Isolated to Song Lookup overlay UI behavior
- No shared state or cross-feature mutations
- Pure layout fix with no business logic changes
- Padding approach is standard Flutter pattern with no edge case brittleness
- No new dependencies or abstractions introduced

---

## 14. Engineer Task Breakdown

Execute in strict order:

**Task 1: Modify `build()` method in `song_lookup_overlay.dart`**

- Read `keyboardHeight` from `MediaQuery.of(context).viewInsets.bottom` (already present)
- Change Container `margin` from conditional `EdgeInsets.fromLTRB(...)` to uniform `EdgeInsets.all(Spacing.space16)`
- Add `Padding` widget inside Container, before ClipRRect, with `padding: EdgeInsets.only(bottom: keyboardHeight)`
- Keep SafeArea `bottom: keyboardHeight == 0` toggle (defensive code)
- Remove or update any outdated comments about margin toggling

**Task 2: Verify `flutter analyze` passes**

- Run `flutter analyze` in project root
- Confirm 0 errors, 0 warnings related to the modified file

**Task 3: Generate `git diff`**

- Run `git diff lib/features/setlists/widgets/song_lookup_overlay.dart`
- Confirm diff shows only the expected changes (margin simplification + Padding addition)
- Include diff in `ENGINEER_REPORT.md`

**Task 4: Write `ENGINEER_REPORT.md`**

- Document all changes made
- Include `flutter analyze` output
- Include git diff
- Confirm all Architect tasks completed

---

## 15. Verification Plan

### Device Testing Required (Pre-Deployment)

This fix requires device testing on a real iPhone (or iPhone simulator with software keyboard enabled) because the bug manifests in keyboard interaction, which cannot be fully validated via static analysis or unit tests.

**Pre-merge verification:**

1. Build and deploy to iPhone (physical device or simulator)
2. Navigate to any setlist
3. Tap "Add Song" to open Song Lookup overlay
4. Verify search field auto-focuses and keyboard appears
5. Type a search query that returns many results (10+ songs)
6. **Critical test:** Attempt to scroll the results list while keyboard is visible
7. **Expected:** Results list scrolls smoothly, bottom items are accessible
8. **Previous bug:** Results list does not scroll, or bottom items remain hidden under keyboard

**Keyboard dismissal test:** 9. Dismiss keyboard (swipe down or tap outside search field on iOS 15+) 10. Verify results list scrolls normally 11. Verify overlay margins remain consistent (16px on all sides)

**Edge cases:** 12. Rotate device (portrait ↔ landscape) with keyboard up 13. Open overlay on iPhone with home indicator (verify SafeArea handling) 14. Open overlay on iPhone without home indicator (older models)

### Tier 1 — Pre-Deployment (Static Analysis)

**Not applicable** — this is a pure UI layout fix with no SQL, RPC, or backend logic.

### Tier 2 — Post-Deployment (Not Applicable)

**Not applicable** — no backend deployment required.

### Flutter Analyze Validation

```bash
flutter analyze
```

**Expected:** 0 errors, 0 warnings related to `song_lookup_overlay.dart`

---

## 16. QA Regression Areas

QA must specifically test the following on iPhone (physical device or simulator):

**Primary verification:**

1. Song Lookup overlay keyboard scrolling — the core bug fix
   - Open Song Lookup from any setlist
   - Keyboard appears → verify results list can scroll to bottom
   - Dismiss keyboard → verify layout remains correct

**Secondary regression checks:** 2. Song Lookup functionality end-to-end

- Search for catalog songs → tap to add → verify success
- Search for external songs (Spotify/MusicBrainz) → tap to add → verify enrichment review flow → verify success
- Verify duplicate detection messages appear correctly
- Verify search debouncing works (250ms delay)

3. Layout regression on other platforms
   - Test on Android (if available) — verify keyboard behavior is not broken
   - Test on Web (keyboard should work, though behavior may differ)
   - Test on macOS (no on-screen keyboard, but verify no layout breakage)

4. Related overlays with same pattern (spot check only — not exhaustive)
   - `bulk_add_songs_overlay.dart` — verify no accidental changes
   - Other overlays listed in "Files Off-Limits" — verify not modified

**Out of scope for this QA cycle:**

- The 8 other files using the same flawed pattern (separate future ticket)
- Setlist ordering, BPM editing, or other setlist features unrelated to Song Lookup

---

## 17. Rollout / Migration Strategy

**Not applicable** — no database migration, no backend deployment, no feature flag required. Pure client-side layout fix that deploys with the next app build.

---

## 18. Out of Scope

**Explicitly NOT included in this fix:**

1. **The 8 other files using the same 16px-margin pattern** — flagged for future investigation but unverified:
   - `bulk_add_songs_overlay.dart`
   - `song_details_bottom_sheet.dart`
   - `song_enrichment_review_sheet.dart`
   - `custom_tuning_modal.dart`
   - `pause_creator.dart`
   - `set_break_creator.dart`
   - `setlist_picker_bottom_sheet.dart`
   - `song_notes_drawer.dart`

2. **Android keyboard behavior** — this fix should work cross-platform, but Android device testing is not required for merge (iOS is the confirmed platform)

3. **Web keyboard behavior** — Web keyboard interaction is fundamentally different (no viewInsets), fix should not break it but is not the primary target

4. **Opportunistic cleanup** — no refactoring, renaming, or formatting changes unrelated to the keyboard fix

5. **Alternative keyboard avoidance patterns** — Scaffold approach was considered but rejected in favor of minimal Padding approach

---

**END OF ARCHITECT_PLAN.md**
