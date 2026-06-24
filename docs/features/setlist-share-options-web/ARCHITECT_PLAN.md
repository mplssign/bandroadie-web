# Architect Plan — Setlist Share Options Not Showing on Web

## Feature Slug

`bug/setlist-share-options-web`

---

## Problem Summary

The setlist share format picker bottom sheet does not render or is not visible in the web app when tapping the share icon on the Setlist Detail screen. Users expect to see a format picker with "Text / Email" and "Spreadsheet" options (as works on macOS), but on web the options do not appear. The feature code exists in the deployed version (v1.2.21+176) and works correctly on macOS.

---

## Root Cause

**Confidence Level:** MEDIUM (web-specific rendering issue confirmed via code analysis and git history, exact failure mode requires runtime validation)

The share format picker feature was restored in commit abbb764 (June 20, 2026) via branch `bug/share-drawer-regression` and is confirmed present in main. Code analysis shows:

1. **No platform checks exist** — no `kIsWeb`, `Platform.is*`, or conditional compilation suppressing the feature on web
2. **Code is structurally correct** — `IconButton`, `_handleShare()`, `_showShareFormatPicker()`, and `_ShareFormatSheet` all implemented per spec
3. **Git history confirms prior web gap** — the previous fix (abbb764) restored the format picker but QA testing did not explicitly validate web platform behavior
4. **Deployment confirmed current** — version.json shows v1.2.21+176 matching main, deployed version includes the fix

**Primary hypothesis:**

Flutter web's `showModalBottomSheet` has different rendering behavior than native platforms. The bottom sheet widget may be:

- Rendered with zero height or off-screen positioning
- Covered by other UI elements (z-index issue)
- Using theme colors that render invisible against the web background
- Failing silently due to web-specific layout constraints

**Secondary hypothesis:**

The Share `IconButton` itself might be clipped or hidden on web due to responsive layout issues when the setlist name is long or the viewport is narrow (mobile web), though this is less likely given the button works on macOS with similar screen widths.

---

## Reference Docs Consulted

**Files checked:**

- `docs/reference/` — no setlist or share domain documentation exists
- `docs/features/share-drawer-regression/` — ARCHITECT_PLAN.md, ENGINEER_REPORT.md, QA_REPORT.md reviewed

**Key findings from prior fix (bug/share-drawer-regression):**

- Feature was never in main originally, was added June 20
- QA report approved the fix but did not explicitly test web platform
- QA report states "Platform (affected system): Share behavior changes on iOS, Android, Web, macOS (all platforms)" but this was acknowledgment of scope, not validation

---

## Existing System Analysis

**Current behavior on web (reported by user):**

```
User taps share icon on web
  ↓
Share format picker does not appear (or is invisible)
  ↓
Unknown if Share.share() is called or errors occur
```

**Expected behavior (confirmed working on macOS):**

```
User taps share icon
  ↓
_handleShare() executes
  ↓
_showShareFormatPicker() displays modal bottom sheet with two options:
  - "Text / Email" (plain-text format with BPM/tuning on separate lines)
  - "Spreadsheet" (tab-delimited: Title\tArtist\tBPM\tTuning)
  ↓
User taps format option
  ↓
Bottom sheet closes, returns ShareFormat enum value
  ↓
_generateShareText() or _generateSpreadsheetText() called based on selection
  ↓
Share.share() opens native/web share with formatted text
```

**Components that exist (verified in setlist_detail_screen.dart):**

- Line 56: `ShareFormat` enum with `textEmail` and `spreadsheet` values
- Line 1842: Share `IconButton` with `onPressed: _handleShare` (unconditionally rendered)
- Line 1231: `_handleShare()` method that calls `_showShareFormatPicker()`
- Line 1269: `_showShareFormatPicker()` that shows modal bottom sheet
- Line 3088: `_ShareFormatSheet` widget with two format option tiles
- Line 3136: `_ShareFormatOption` widget for individual format tiles
- Line 1395: `_generateSpreadsheetText()` for tab-delimited output
- Line 1286: `_generateShareText()` for plain-text output

**Layout structure confirmed:**

```dart
Row (header)
├── Expanded
│   └── Row (name + edit icon)
├── [Conditional: Select button if Catalog]
├── IconButton (Print) — unconditional
└── IconButton (Share) — unconditional
```

The Share button is outside any conditional blocks and should always render. `Expanded` on the left side ensures the name text takes available space while pushing the buttons to the right. This layout should work correctly on all platforms.

**Web-specific considerations:**

Flutter web renders `showModalBottomSheet` as an overlay with CSS positioning. Known differences from native:

- Uses web DOM layering instead of native view hierarchy
- Backdrop uses CSS opacity rather than native scrim
- Modal constraints calculated differently for browser viewport
- Keyboard avoidance behavior differs (no software keyboard on desktop web)

---

## Proposed Solution

**Diagnostic-first approach** — add runtime logging and conditional web-specific styling to isolate the exact failure mode, then apply targeted fix.

### Phase 1: Add diagnostic logging (immediate)

1. **Add debug prints to share flow** in `_handleShare()` to confirm execution path:
   - Log when share button is tapped
   - Log when `_showShareFormatPicker()` is called
   - Log when bottom sheet builder executes
   - Log when format selection is made or dismissed

2. **Add visual debugging** to `_ShareFormatSheet`:
   - Add explicit background color (bright test color) to Container
   - Add minimum height constraint to ensure visibility
   - Add border for visual confirmation

### Phase 2: Apply web-specific fixes (conditional on diagnostic findings)

**If bottom sheet renders but is invisible:**

1. **Add explicit theming** to `_showShareFormatPicker()`:
   - Set `backgroundColor` to explicit color instead of `context.colors.surface`
   - Add `barrierColor` with higher opacity for web
   - Ensure `clipBehavior: Clip.antiAlias` for web rendering

2. **Add explicit sizing** to `_ShareFormatSheet`:
   - Wrap in `ConstrainedBox` with `minHeight: 200`
   - Add `SafeArea` wrapping to handle web viewport edges

**If bottom sheet does not appear at all:**

1. **Add web-specific modal implementation:**
   - Use `showDialog` with custom bottom-sheet-style widget as fallback for web
   - Detect platform with `kIsWeb` and branch implementation
   - Preserve existing `showModalBottomSheet` for native platforms

**If Share button is not visible/clickable:**

1. **Fix Row overflow:**
   - Wrap name text in `Flexible` instead of leaving Expanded Row unconstrained
   - Add `overflow: TextOverflow.ellipsis` to name Text if not present
   - Ensure IconButtons have explicit `constraints` for hit testing

### Phase 3: Validate with local web build

- Run `flutter run -d chrome` with setlist open
- Tap share icon, verify format picker appears
- Select both format options, verify text generation and Share.share() call
- Test with long setlist names to verify button visibility
- Test in narrow browser window (mobile viewport) to verify responsive behavior

---

## Database Impact

**Not applicable** — UI-only bug fix. No migrations, RLS policies, RPC functions, or triggers affected.

---

## Flutter Architecture Changes

**State:**

- No state changes
- No Riverpod provider modifications
- No controller changes

**Widgets:**

- Modify `_ShareFormatSheet` to add diagnostic logging and web-specific styling
- Modify `_handleShare()` to add diagnostic logging
- Potentially add conditional web-specific modal implementation if bottom sheet cannot be fixed

**Repositories:**

- No repository changes

---

## Files to Create

**None** — all changes are within existing file, unless web-specific fallback implementation requires extracting a shared widget (to be determined during implementation based on diagnostic findings).

---

## Files to Modify

| File                                               | Changes                                                                                                                                                                                                   |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | Add diagnostic logging to `_handleShare()` and `_showShareFormatPicker()`, add web-specific styling/sizing to `_ShareFormatSheet`, potentially add `kIsWeb` conditional for fallback modal implementation |

---

## Files Off-Limits

| File                                                    | Reason                               |
| ------------------------------------------------------- | ------------------------------------ |
| `lib/main.dart`                                         | Init order must not change           |
| `lib/features/setlists/setlist_repository.dart`         | No repository changes required       |
| `lib/features/setlists/setlist_detail_controller.dart`  | No state management changes required |
| `lib/features/setlists/new_setlist_screen.dart`         | Different screen, unaffected         |
| `lib/features/setlists/widgets/action_buttons_row.dart` | Different component, unaffected      |
| All other files                                         | Not part of approved scope           |

---

## System Impact Map

| System                                 | Impact                                                                |
| -------------------------------------- | --------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                            |
| Rehearsals                             | unaffected                                                            |
| Setlists / Catalog                     | affected (share functionality fixed for web)                          |
| Members / RBAC                         | unaffected (no permission changes)                                    |
| Auth / Session                         | unaffected                                                            |
| Routing                                | unaffected                                                            |
| Notifications                          | unaffected                                                            |
| Platform (iOS / Android / Web / macOS) | affected (web-specific fix, native platforms retain current behavior) |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Change is scoped to web-specific rendering fix
- Native platforms (iOS, Android, macOS) continue using existing working implementation
- If `kIsWeb` conditional is added, it creates a clear separation between web and native paths with no cross-contamination risk
- Worst-case failure: format picker still doesn't work on web (no worse than current state)
- No state management, database, or cross-feature dependencies affected
- Share flow is user-initiated action with no automatic side effects

**Failure modes to guard against:**

1. Web fix breaks native platforms — mitigated by using `kIsWeb` conditional to isolate changes
2. Bottom sheet shows but Share.share() fails on web — `share_plus` package handles web gracefully (falls back to clipboard or Web Share API), no app crash risk
3. Diagnostic logging left in production — low impact (console output only), remove before commit

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Add diagnostic logging to share flow

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Changes:**

1. In `_handleShare()` method (line ~1231), add debug prints:
   - `debugPrint('[SetlistShare] Share button tapped');` at method start
   - `debugPrint('[SetlistShare] Calling _showShareFormatPicker()');` before picker call
   - `debugPrint('[SetlistShare] Format selected: $format');` after picker returns
   - `debugPrint('[SetlistShare] Format picker dismissed (null)');` in null check branch

2. In `_showShareFormatPicker()` method (line ~1269), add debug print:
   - `debugPrint('[SetlistShare] Showing modal bottom sheet');` before `showModalBottomSheet` call
   - `debugPrint('[SetlistShare] Modal result: $result');` before return

3. In `_ShareFormatSheet.build()` method (line ~3092), add debug print:
   - `debugPrint('[SetlistShare] _ShareFormatSheet building');` at method start

**Validation:** Run `flutter run -d chrome`, open setlist, tap share, check browser console for log sequence.

### Task 2: Add explicit styling and sizing to \_ShareFormatSheet for web visibility

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Changes:**

1. Import foundation for `kIsWeb`:
   - Add `import 'package:flutter/foundation.dart' show kIsWeb;` to imports section (after `flutter/services.dart`)

2. In `_showShareFormatPicker()` method (line ~1269), modify `showModalBottomSheet` call:
   - **Before:**
     ```dart
     final result = await showModalBottomSheet<ShareFormat>(
       context: context,
       backgroundColor: context.colors.surface,
       shape: const RoundedRectangleBorder(
         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
       ),
       isDismissible: true,
       enableDrag: true,
       builder: (context) => const _ShareFormatSheet(),
     );
     ```
   - **After:**
     ```dart
     final result = await showModalBottomSheet<ShareFormat>(
       context: context,
       backgroundColor: kIsWeb ? const Color(0xFF1a1a1a) : context.colors.surface,
       barrierColor: kIsWeb ? Colors.black.withOpacity(0.7) : null,
       shape: const RoundedRectangleBorder(
         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
       ),
       isDismissible: true,
       enableDrag: !kIsWeb, // Disable drag on web (no touch gestures)
       isScrollControlled: true, // Allow custom height
       builder: (context) => const _ShareFormatSheet(),
     );
     ```

3. In `_ShareFormatSheet.build()` method (line ~3092), wrap `SingleChildScrollView` child in `ConstrainedBox`:
   - **Before:**
     ```dart
     return SingleChildScrollView(
       child: Container(
         padding: EdgeInsets.only(...),
         child: Column(...),
       ),
     );
     ```
   - **After:**
     ```dart
     return SingleChildScrollView(
       child: ConstrainedBox(
         constraints: const BoxConstraints(minHeight: 200),
         child: Container(
           padding: EdgeInsets.only(...),
           child: Column(...),
         ),
       ),
     );
     ```

**Validation:** Run `flutter run -d chrome`, tap share, verify bottom sheet appears with visible background and sufficient height.

### Task 3: Test share flow end-to-end on web

**Platform:** Chrome (web)

**Test cases:**

1. Open setlist detail screen (any setlist with songs)
2. Tap share icon in header
3. Verify format picker bottom sheet appears with two options visible
4. Tap "Text / Email" option
5. Verify native/web share dialog appears (or clipboard fallback on unsupported browsers)
6. Dismiss share dialog
7. Tap share icon again
8. Tap "Spreadsheet" option
9. Verify share dialog appears with tab-delimited text
10. Test with long setlist name to verify button is not clipped
11. Test in narrow browser window (400px width) to verify responsive behavior

**Expected:** All steps pass, format picker visible and functional on web.

### Task 4: Remove diagnostic logging before commit

**File:** `lib/features/setlists/setlist_detail_screen.dart`

**Changes:**

- Remove all `debugPrint('[SetlistShare] ...')` statements added in Task 1

**Validation:** `flutter analyze` passes with 0 warnings.

### Task 5: Verify native platforms retain existing behavior

**Platforms:** macOS (or iOS simulator)

**Test case:**

1. Run `flutter run -d macos`
2. Open setlist detail screen
3. Tap share icon
4. Verify format picker appears (should use existing native styling, not web-specific changes)
5. Select format, verify share sheet works

**Expected:** No visual or behavioral change from current macOS behavior.

### Task 6: Commit and push

**Commands:**

```bash
git add lib/features/setlists/setlist_detail_screen.dart
git commit -m "fix(setlists): add web-specific styling to share format picker for visibility"
git push origin bug/setlist-share-options-web
```

---

## Verification Plan

### Pre-Deployment Testing (local web build)

All tests must pass before deploying to production.

**Test 1: Format picker visibility on web**

```bash
# Terminal
flutter run -d chrome

# Browser
1. Navigate to setlist detail screen
2. Open browser DevTools console
3. Tap share icon
4. Verify console logs show share flow execution
5. Verify format picker bottom sheet is visible with two options
6. Verify background is opaque (not transparent)
7. Verify text is readable (contrast sufficient)
```

**Expected:** Bottom sheet visible, two format options clearly displayed, proper contrast and sizing.

**Test 2: Format selection on web (Text / Email)**

```bash
# Browser (continuing from Test 1)
1. Tap "Text / Email" option in format picker
2. Verify format picker closes
3. Verify share dialog appears (or clipboard copy message if Web Share API unavailable)
4. Check shared text format matches plain-text spec:
   - Setlist name on first line
   - Song count and duration on second line
   - Each song: title line, then artist/BPM/tuning line
```

**Expected:** Correct plain-text format generated, share mechanism invoked.

**Test 3: Format selection on web (Spreadsheet)**

```bash
# Browser
1. Tap share icon
2. Tap "Spreadsheet" option
3. Verify share dialog appears
4. Check shared text format matches tab-delimited spec:
   - Header row: Title\tArtist\tBPM\tTuning
   - Data rows: song data tab-separated
```

**Expected:** Correct tab-delimited format generated.

**Test 4: Dismissal behavior**

```bash
# Browser
1. Tap share icon
2. Tap outside the bottom sheet (on backdrop)
3. Verify bottom sheet closes
4. Verify no error in console
5. Tap share icon again
6. Press Escape key
7. Verify bottom sheet closes
```

**Expected:** Bottom sheet dismisses cleanly on backdrop tap and Escape key.

**Test 5: Responsive layout (narrow viewport)**

```bash
# Browser
1. Resize window to 400px width (mobile viewport)
2. Navigate to setlist detail with long name
3. Verify share icon is visible (not clipped)
4. Tap share icon
5. Verify format picker appears and is properly sized for narrow viewport
```

**Expected:** Share button visible, format picker sized appropriately for mobile web.

**Test 6: Native platform unchanged (macOS)**

```bash
# Terminal
flutter run -d macos

# macOS app
1. Navigate to setlist detail screen
2. Tap share icon
3. Verify format picker appears with native styling
4. Select format, verify share sheet works
5. Verify no visual difference from prior behavior
```

**Expected:** Native platforms use existing styling, no regression.

---

## QA Regression Areas

QA must explicitly test the following to confirm no regression:

### Primary: Share functionality on web

- **Web Chrome:** Format picker appears, both formats work, Share.share() or fallback invoked
- **Web Safari:** Format picker appears, both formats work (test macOS Safari specifically)
- **Web Firefox:** Format picker appears, both formats work
- **Web mobile viewport (Chrome DevTools):** Share button visible, format picker sized correctly

### Secondary: Share functionality on native platforms

- **macOS:** Format picker appears, both formats work, native share sheet appears
- **iOS (if available):** Format picker appears, both formats work, native share sheet appears
- **Android (if available):** Format picker appears, both formats work, native share sheet appears

### Tertiary: Setlist detail screen layout

- **All platforms:** Share and print icons visible in header, not clipped
- **All platforms:** Long setlist names ellipsize correctly, do not overflow
- **All platforms:** Other setlist detail functionality unaffected (reorder, add songs, delete, etc.)

### Edge cases to verify

- **Empty setlist:** Share icon still appears, format picker works (edge case: zero songs)
- **Catalog setlist:** Share icon appears alongside "Select" button, no layout conflict
- **After rotating device (mobile):** Share icon remains visible after orientation change
- **After dismissing picker multiple times:** No memory leak or performance degradation

---

## Rollout / Migration Strategy

**Deployment:**

1. Merge PR after QA APPROVED
2. Deploy web via `./tools/deploy_web.sh`
3. Monitor Sentry/console for web-specific errors in share flow
4. If issues detected, rollback is simple (revert commit, redeploy)

**No database migration required.**

**No cache-busting required** (Flutter web uses content hash in filenames, browsers automatically fetch new build).

---

## Out of Scope

The following are explicitly excluded from this bug fix:

- **Share functionality changes on native platforms** — native behavior is working correctly, preserve as-is
- **New share formats** — only Text/Email and Spreadsheet are in scope, no PDF or image exports
- **Share button repositioning** — button location in header is correct, no layout changes
- **Share.share() package upgrade** — `share_plus` v10.1.4 is stable, no upgrade needed
- **New setlist screen share** — different screen, separate share implementation, not affected by this bug
- **Share functionality on other screens** — only setlist detail screen in scope
- **Web Share API polyfill** — if Web Share API is unavailable, `share_plus` handles fallback, no custom implementation needed
- **Analytics for share usage** — no tracking added, out of scope
- **Accessibility improvements** — format picker uses standard Flutter widgets with inherent a11y, no additional work required
- **Internationalization** — format option labels are English-only, no i18n changes
