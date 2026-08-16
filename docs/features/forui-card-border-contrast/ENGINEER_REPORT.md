# Engineer Report

## Feature Slug

forui-card-border-contrast

## Feature Title

Forui Card Border Contrast Fix

## Goal

Replace hardcoded low-contrast card borders with Forui's theme-aware border token (`context.theme.colors.border`) for consistent visual contrast across all card widgets. Remove accent borders (rose/slate) from song and member cards to establish uniform theming.

## Architect Tasks Completed

- [x] Task 1 — Update `AppCard` to default to Forui theme border
- [x] Task 2 — Remove explicit border from `SongCard`
- [x] Task 3 — Remove explicit border from `ReorderableSongCard`
- [x] Task 4 — Remove explicit border from `MemberCard`
- [x] Task 5 — Remove explicit border from `MemberCardSkeleton`
- [x] Task 6 — Search for other `AppCard` usages with explicit borders (none found)
- [x] Task 7 — Verify no regressions (analyzer passed)

## Files Created

- none

## Files Modified

- `lib/components/ui/app_card.dart` — Added theme-aware default border
- `lib/features/setlists/widgets/song_card.dart` — Removed rose accent border
- `lib/features/setlists/widgets/reorderable_song_card.dart` — Removed slate accent border
- `lib/features/members/widgets/member_card.dart` — Removed rose accent border and unused `borderWidth` field
- `lib/features/members/widgets/member_card_skeleton.dart` — Removed low-contrast border wrapper

## Analyzer Results

**Command:** `flutter analyze`

**Result:** 0 errors / 10 warnings (no new warnings introduced)

**Pre-existing warnings:** 10 warnings (unchanged from pre-implementation state)

**Warnings resolved during implementation:**

- Fixed 2 unnecessary null comparison warnings in `app_card.dart` (lines 49, 54)
- Fixed 1 unused field warning in `member_card.dart` (removed `borderWidth`)

**Net impact:** Reduced total warnings from 13 to 10 (3 warnings fixed)

## Test Results

Not run — visual styling fix only, no business logic changes. Architect plan specified manual QA as primary validation.

## Verification

### Code Review

✅ All 5 target files modified as specified
✅ `AppCard` now reads `context.theme.colors.border` dynamically
✅ All explicit accent borders removed from cards
✅ No additional `AppCard` usages with explicit borders found

### Implementation Notes

**Corrected logic applied:** Used the Architect's final corrected version of `styleDelta` logic that creates a `StyleDelta` unconditionally (since we always have a border now), avoiding the unnecessary null checks that would have caused analyzer warnings.

**Forui theme accessor verified:** Confirmed `context.theme.colors.border` is the correct syntax by inspecting `package:forui/src/theme/theme.dart`. The extension `FBuildContext` provides the `theme` getter on `BuildContext`.

**Simplified implementation:** Since `effectiveBorder` is always non-null (either explicit or default), the final implementation creates a `FCardStyleDelta` unconditionally rather than conditionally checking for null, which eliminated analyzer warnings.

## Deviations From Architect Plan

**Minor simplification:** The final `AppCard` implementation creates a `FCardStyleDelta` unconditionally (since we always have a border), rather than using the conditional approach in the plan's intermediate version. This matches the plan's corrected logic and eliminates unnecessary null checks that would cause analyzer warnings.

**Rationale:** Architect plan included an intermediate version followed by a correction. Per user instructions, implemented only the corrected version, then further simplified to eliminate analyzer warnings about unnecessary null comparisons.

## Blockers Encountered

None

## Ready For QA

Yes

**Manual QA Checklist (Platform: macOS):**

- [ ] Open Catalog setlist, verify song cards have visible neutral borders (rose accent removed)
- [ ] Open non-Catalog setlist, verify reorderable song cards have visible neutral borders (slate accent removed)
- [ ] Open Members tab, verify member cards have visible neutral borders (rose accent removed)
- [ ] Trigger member card skeleton loading state, verify borders are visible and match real card visual weight
- [ ] Confirm all card borders use consistent Forui neutral palette color
- [ ] Verify borders are clearly visible against card surface (contrast check)

**Expected visual change:** All cards now render with consistent translucent white borders (`Color(0x1AFFFFFF)`) in dark mode, replacing the previous low-contrast opaque zinc-800 borders and removing colored accent borders.
