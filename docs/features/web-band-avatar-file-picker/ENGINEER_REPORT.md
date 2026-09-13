# ENGINEER_REPORT — web-band-avatar-file-picker

## Feature Slug

`web-band-avatar-file-picker`

## Feature Title

Use a desktop file picker for band avatar uploads on web

## Cycle Number

2

## Goal

Resolve QA Cycle 1's Critical `[code-quality]` finding by removing the two newly added `debugPrint(` calls while preserving the web upload helper's silent-null contract, the web picker helper's user-facing error contract, and all existing native behavior.

## Architect Tasks Completed

- Removed the newly added `debugPrint(` call from `_uploadPickedBytesToStorage()`; its catch still returns `null` silently so the caller presents the existing upload error snackbar.
- Removed the newly added `debugPrint(` call from `_pickImageFromWebFilePicker()`; its catch still guards `mounted`, resets `_isUploadingImage`, and presents the existing picker error snackbar.
- Added the `kIsWeb` import and early-return branch at the top of `_pickImage()`.
- Added `_pickImageFromWebFilePicker()` using `FilePicker`, in-memory bytes, existing upload-state fields, draft-band URL propagation, haptics, mounted guards, and existing snackbar behavior.
- Added `_uploadPickedBytesToStorage()` with authenticated object naming, lowercase extension normalization, the `png|jpg|jpeg|gif|webp` whitelist, `png` fallback, direct `uploadBinary`, and public-URL retrieval.
- Preserved `_uploadImageToStorage(File)` and every line of the existing mobile/macOS `_pickImage()` path after the new web guard.
- Left the stale `unused_element` ignore, avatar contracts, tests, dependencies, Supabase code, routing, auth, and initialization unchanged.

## Files Created

- None in Cycle 2.

## Files Modified

- `lib/features/bands/band_form_screen.dart`
- `docs/features/web-band-avatar-file-picker/ENGINEER_REPORT.md` (pipeline report only)

## Analyzer Results

- `dart fix --dry-run`: `Nothing to fix!`
- Final focused `flutter analyze lib/features/bands/band_form_screen.dart`: `No issues found! (ran in 2.5s)`
- Full `flutter analyze`: `No issues found! (ran in 4.7s)`

## Test Results

- Full `flutter test`: 322 passed, 0 failed.
- No test files were added or modified, as required by the plan.

## Code Efficiency/Bloat Check

- Final implementation delta: 72 insertions, 0 deletions, within the revised approved net +53 to +73 budget.
- Existing-helper search across `lib/`: no existing helper for web band-avatar image picking or direct band-avatar byte upload; the only matching upload was the existing `File`-based helper in the owning screen.
- Both new methods are private; no provider, model field, widget contract, dependency, or public API was added.
- `band_form_screen.dart` remains above the Dart file-size target because the approved plan confines this web-only behavior to the existing owning screen and explicitly prohibits the broader extraction/refactor.
- Zero implementation deletions are intentional: the root cause was a missing web platform branch and bytes upload path, while the plan requires the existing mobile path to remain unchanged.

## Verification

- QA Cycle 1 Critical `[code-quality]` finding corrected: both newly added catch-level `debugPrint(` calls were removed without changing their silent-null or user-facing error behavior.
- Ran `dart format lib/features/bands/band_form_screen.dart`: `Formatted 1 file (1 changed) in 0.01 seconds`; restored two unrelated pre-existing format-only hunks so the final diff contains only planned code.
- Mandatory added-`debugPrint(` diff gate: exactly 0.
- `showModalBottomSheet` count: exactly 2.
- `kIsWeb`: import plus guard at the top of `_pickImage()`.
- `_uploadImageToStorage`: original definition plus its existing three call sites; definition unchanged.
- `_uploadPickedBytesToStorage`: exactly one definition and one call site.
- Extension whitelist and `png` fallback are present in the bytes upload helper.
- `visibleForTesting` search under `lib/features/bands/`: no output.
- Test-tree diff/status, `BandAvatar`/`DraftBandState` diff, dependency diff, Supabase diff, and `git diff --check`: all produced empty output.
- Final source diff size: 72 insertions, 0 deletions in `lib/features/bands/band_form_screen.dart`.
- Final worktree scope before this report: only `lib/features/bands/band_form_screen.dart` modified and `docs/features/web-band-avatar-file-picker/` untracked.
- Tier 2 owner-run punch list W1-W9 was not performed; the plan reserves it for Tony at PR-test/apply time.

## Deviations From Plan

None.

## Blockers Encountered

None.

## Ready For QA

Yes