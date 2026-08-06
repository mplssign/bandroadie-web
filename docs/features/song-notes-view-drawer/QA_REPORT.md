# QA Report

## Feature Slug
`feature/song-notes-view-drawer`

## Feature Title
Song Notes View Drawer — Read-only notes view with dedicated Edit mode

## Final Verdict
**APPROVED** (with Warning — see Issues Found)

## Validation Summary
Implementation matches Architect specification with all 7 tasks complete. Critical Save-button-disabled guard from QA Round 1 (July 2026) is verified fixed via code-path analysis. No functional regressions detected. One minor cosmetic inconsistency flagged (drag handle color uses hardcoded white instead of design token). Analyzer passes with 0 errors. Manual device/platform testing not performed (marked as outstanding gap per historical context).

## Architect Scope Review
- **Scope adherence:** Compliant — only approved files created/modified
- **Files modified:** As expected:
  - Created: `lib/features/setlists/widgets/song_notes_drawer.dart` (283 lines)
  - Modified: `lib/features/setlists/widgets/song_details_bottom_sheet.dart` (5 edits: 1 import, 1 method, 3 onTap/label updates)
- **Files off-limits:** Not touched — verified via `git diff --name-only` (setlist_detail_screen, setlist_repository, setlist_detail_controller, migrations, main.dart all unchanged)

## Completeness Check
- **All Architect tasks implemented:** Yes
  - ✅ Task 1: Created `song_notes_drawer.dart` with `SongNotesDrawer` widget and `showSongNotesDrawer()` entry point
  - ✅ Task 2: Added import in `song_details_bottom_sheet.dart`
  - ✅ Task 3: Added `_viewNotes()` method (lines 607-619)
  - ✅ Task 4: Updated button label to `'View notes'` when notes exist (line 1347)
  - ✅ Task 5: Updated button `onTap` to route through `_viewNotes` when notes exist (lines 1328-1330)
  - ✅ Task 6: Updated preview `onTap` to call `_viewNotes` (line 1372)
  - ✅ Task 7: Ran `flutter analyze` — 0 errors/warnings
- **Missing tasks:** None

## Behavior Verification
- **Validation method:** Code-path analysis (runtime behavior not tested on devices/browsers)
- **Result:** Matches expected behavior per Architect plan

### Critical Issue from QA Round 1 (July 2026) — VERIFIED FIXED
**Save button disabled when notes text unchanged:**
- ✅ Line 63: `bool get _hasChanges => _notesController.text.trim() != widget.notes.trim()`
- ✅ Line 215: `onPressed: _hasChanges ? _handleSave : null` (button's `onPressed` is **actually `null`** when unchanged, not just visually disabled)
- ✅ Line 201: `onChanged: (_) => setState(() {})` ensures button re-enables **live as user types**
- **Verdict:** Critical guard is correctly implemented and will function as required

### Primary Validation (Code-Path Analysis)
1. ✅ **Button label:** Changes from "Edit Notes" to "View notes" when notes exist (line 1347)
2. ✅ **Drawer default state:** Opens in read-only view mode (line 49: `bool _isEditing = false;`)
3. ✅ **Edit button:** Enters edit mode correctly (line 248: `setState(() => _isEditing = true)`)
4. ✅ **Save disabled guard:** Confirmed (line 215, see above)
5. ✅ **Cancel in edit mode:** Returns to view mode, does not close drawer (lines 71-75: resets controller, sets `_isEditing = false`)
6. ✅ **Cancel in view mode:** Closes drawer (lines 76-79: `Navigator.pop(null)`)
7. ✅ **Outer Save persists:** Drawer returns value via `Navigator.pop()`, parent's `_viewNotes()` updates controller and calls `_checkForChanges()`, outer Save button becomes enabled
8. ✅ **Unsaved-changes dialog:** Preserved — parent sheet's existing `_handleCancel()` / `PopScope` logic unchanged
9. ✅ **Inline "Add Notes" flow:** Preserved byte-for-byte when `!hasNotes` (lines 1328-1330: conditional routes to inline flow or drawer)
10. ✅ **`isReadOnly: true` mode:** Button row hidden (line 1235: `if (!widget.isReadOnly)`), preview `onTap` is `null` (line 1372: `widget.isReadOnly ? null : _viewNotes`)

### Persistence Flow Verification
- Drawer's "Save" updates in-memory `_notesController.text` only (line 80: `Navigator.pop(_notesController.text.trim())`)
- Parent's `_viewNotes()` receives result, updates controller, calls `_checkForChanges()` (lines 615-618)
- Outer Song Details "Save" button becomes enabled when `_hasChanges = true`
- Database write occurs via `_handleSave()` → `SongDetailsResult(notesChanged: true)` → caller invokes `updateSongNotes()` (unchanged from current main)
- **Verdict:** Persistence pattern matches Architect specification exactly

## Regression Check
- **Risk level:** LOW
- **Systems reviewed:**
  - Setlists / Catalog: Only 3 lines touched in `_buildAddButtonsRow()` and `_buildNotesPreview()` — title/artist/tuning/BPM/duration/key/lyrics/links logic completely untouched
  - Auth / Session: No changes
  - Routing: No changes
  - Database: No changes
  - Platform-specific code: None added
- **Regressions found:** None (code-path analysis)

### Regression Testing Detail
- **Title/artist/tuning/BPM/duration/key/lyrics/links editing:** Unchanged — verified via diff (no changes outside notes-specific methods)
- **Inline "Add Notes" flow:** Preserved — when `hasNotes` is false, button still calls `() => setState(() => _isEditingNotes = true)` (line 1330)
- **Setlist save flow:** `SongDetailsResult.notesChanged` flag unchanged (lines 46-89), caller contract preserved
- **Dark-mode safety:** Uses `context.colors.surface` (line 97), `context.colors.background` (line 167), `context.colors.border` (line 169, 108, others), `context.colors.textPrimary/textSecondary/textMuted` throughout — **Warning:** drag handle uses `Colors.white.withValues(alpha: 0.3)` instead of design token (see Issues Found)
- **`isReadOnly` mode:** Existing behavior preserved (button hidden, preview non-interactive)

## Database Safety
**Not applicable** — no migrations, RLS policies, RPC functions, or database schema changes. Feature continues to use existing `songs.notes` column and `SetlistRepository.updateSongNotes()` method (signature and behavior unchanged).

## Analyzer Results
**Command:** `flutter analyze`  
**Result:** ✅ **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 5.3s)
```

## Test Results
**Not run** — Architect plan specifies manual verification only (no SQL/migration surface, analyzer gate only). No existing test coverage for `song_details_bottom_sheet.dart` or related UI components.

## Diff Safety Review
- **Secrets:** ✅ None found
- **Debug artifacts:** ✅ None found (no `print()`, `debugPrint()`, `TODO`, `FIXME`, or test scaffolding)
- **Unrelated changes:** ✅ None — diff is minimal (28 lines total: 1 import, 15 lines for new method, 3 onTap/label edits in two methods)
- **Accidental file deletions:** ✅ None
- **Formatting churn:** ✅ None

### New File Quality (`song_notes_drawer.dart`)
- ✅ Proper disposal: `_notesController.dispose()` in line 56
- ✅ PopScope dismiss handling: lines 87-91 (matches parent sheet pattern)
- ✅ Keyboard-aware layout: line 95 (`padding: EdgeInsets.only(bottom: keyboardHeight)`)
- ✅ Responsive height constraints: line 97 (`maxHeight: screenHeight * 0.85`)
- ✅ SafeArea wrapping: line 93
- ✅ No controller/FocusNode used after dispose

## Platform Parity Verification
⚠️ **NOT VERIFIED — Requires manual device/browser testing**

The following manual verification steps from the Architect plan (§15 "Verification Plan") were **not performed** and remain outstanding:

- iOS device/simulator: Notes drawer renders, dismiss gestures work
- Android device/emulator: Notes drawer renders, back button works
- Web (Chrome/Safari): Notes drawer renders, escape key / click-outside dismisses correctly
- macOS: Notes drawer renders

**Historical context:** Manual device verification (dark-mode render, iOS/Android/Web) was never actually performed in either QA round of the original July 2026 implementation — only code-path analysis. This gap is explicitly carried forward here and should be addressed via manual testing before production deployment.

**QA limitation disclosure:** As QA agent, I cannot reliably perform live browser/device interaction testing. Per instructions, I do not fabricate test results. These platform checks are marked as explicitly outstanding rather than asserting success without verification.

## Issues Found

### Warnings (should fix)

1. **Drag handle color uses hardcoded white instead of design token**
   - **File:** `lib/features/setlists/widgets/song_notes_drawer.dart`, line 132
   - **Current:** `color: Colors.white.withValues(alpha: 0.3)`
   - **Architect directive:** "Never hardcode gray/color values" (ARCHITECT_PLAN.md, line 103)
   - **Codebase precedent:** Other drawers (`view_gig_drawer.dart`, `view_rehearsal_drawer.dart`) use `context.colors.border` for drag handle (width 40, height 4)
   - **Parent file precedent:** `song_details_bottom_sheet.dart` uses `context.colors.textMuted.withValues(alpha: 0.3)` (width 36, height 4)
   - **Impact:** Cosmetic inconsistency, no functional issue (white with alpha renders correctly in dark mode)
   - **Recommendation:** Change line 132 to `color: context.colors.border` to match newer drawers and comply with Architect directive

2. **Button text colors use hardcoded white**
   - **Files:** `song_notes_drawer.dart`, lines 218-219, 240
   - **Current:** `color: Colors.white` and `color: Colors.white.withValues(alpha: 0.5)`
   - **Context:** Button text on rose `AppColors.primary` background
   - **Codebase precedent:** Parent file `song_details_bottom_sheet.dart` also uses `Colors.white` for button text (lines 578, 794, 1620)
   - **Impact:** Inconsistent with "never hardcode" directive, but follows existing pattern in parent file
   - **Recommendation:** Accept as-is if parent file's pattern is intentional, OR extract to design token (e.g., `AppColors.buttonTextOnPrimary`) if codebase-wide consistency is desired

### Critical (must fix before commit)
None

### Suggestions (optional)
None — implementation is complete and matches Architect specification

## Additional Notes

### QA Round 1 Critical Issue — Verification Detail
The Save button disabled guard was the Critical issue that blocked approval in QA Round 1 (July 2026). Here is the explicit verification of the fix:

**Requirement:** Save button must be disabled (not just styled as disabled) when notes text is unchanged from the original, and must re-enable live as the user types.

**Implementation verification:**
1. **Disabled condition computed correctly:**
   ```dart
   bool get _hasChanges => _notesController.text.trim() != widget.notes.trim();
   ```
   This getter compares the current trimmed text to the original trimmed notes. Returns `false` when unchanged, `true` when changed.

2. **Button's `onPressed` is actually `null` when unchanged:**
   ```dart
   onPressed: _hasChanges ? _handleSave : null,
   ```
   When `_hasChanges` is false, `onPressed` is `null`. Flutter's `FilledButton` treats `null` `onPressed` as truly disabled (not clickable, styled as disabled). When `_hasChanges` is true, `onPressed` is `_handleSave` (button is enabled and functional).

3. **Live re-enable as user types:**
   ```dart
   TextField(
     controller: _notesController,
     // ...
     onChanged: (_) => setState(() {}),
   )
   ```
   Every keystroke in the `TextField` triggers `setState(() {})`, which rebuilds the widget tree. The rebuild re-evaluates `_hasChanges` getter and updates the Save button's enabled/disabled state immediately.

**Verdict:** The Critical issue from QA Round 1 is definitively fixed and will function correctly at runtime.

### File Size Compliance
- New file: `song_notes_drawer.dart` = 283 lines ✅ (well under 500-line guideline for Dart files)
- Modified file: `song_details_bottom_sheet.dart` = 1633 lines (already oversized per Guardrails §8, but change is minimal — only +15 lines for new method and +3 net lines from edits)

### Historical Context — July 2026 Implementation
This feature was previously designed, implemented, and QA-approved on 2026-07-15 (commits `780478e`, `d7893bc`) but never merged to main. The branch was subsequently deleted. The current implementation re-applies the approved UX against the diverged codebase (383 lines of unrelated changes since July). The old implementation serves as validated UX reference only — this is a fresh integration, not a rebase.

---

**End of QA Report**
