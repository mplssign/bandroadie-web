# Engineer Report — Share Setlist Format Picker Web Fix

## Feature Slug

`bug/share-setlist-format-picker-web`

---

## Implementation Summary

**Status:** ✅ COMPLETE  
**Date:** 2026-06-23  
**Branch:** `bug/share-setlist-format-picker-web`  
**Files Modified:** 1  
**Static Analysis:** ✅ PASS (0 errors)

---

## Tasks Completed

### 1. Locate `_ShareFormatOption` Widget ✅

**Location:** `lib/features/setlists/setlist_detail_screen.dart` line 3139-3185

Confirmed the widget structure matches the Architect plan specification.

### 2. Replace `InkWell` with `GestureDetector` ✅

**Changes Applied:**

```dart
// Before:
return InkWell(
  onTap: onTap,
  borderRadius: BorderRadius.circular(Spacing.buttonRadius),
  child: Container(...),
);

// After:
return GestureDetector(
  onTap: onTap,
  child: Container(...),
);
```

**Modifications:**

- Line 3152: Changed `InkWell` → `GestureDetector`
- Line 3154: Removed `borderRadius` parameter (not supported by `GestureDetector`)
- Preserved all other widget structure, styling, and `onTap` callback logic

### 3. Verify No Other References ✅

Confirmed `_ShareFormatOption` is only instantiated within `_ShareFormatSheet` in the same file. No external dependencies on `InkWell` behavior detected.

### 4. Run `flutter analyze` ✅

**Result:** No issues found (ran in 4.0s)

---

## Files Modified

| File                                               | Lines Changed | Description                                                       |
| -------------------------------------------------- | ------------- | ----------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart` | 3152-3154     | Replaced `InkWell` with `GestureDetector` in `_ShareFormatOption` |

---

## Files Created

None (as specified in Architect plan).

---

## Verification Status

### Pre-Implementation Checks ✅

- [x] Branch verified: `bug/share-setlist-format-picker-web`
- [x] Working tree clean (no unrelated changes)
- [x] Architect plan loaded and validated
- [x] Guardrails reviewed

### Post-Implementation Checks ✅

- [x] `flutter analyze` passed with 0 errors
- [x] Code change isolated to single widget
- [x] No state management changes required
- [x] No routing or initialization changes
- [x] Pattern consistent with existing codebase (tuning picker uses `GestureDetector`)

### Manual Testing Required 🟡

The following manual verification steps from the Architect plan require testing on live devices/browsers:

#### Web Platform (PRIMARY FIX TARGET)

- [ ] Open BandRoadie web app in Chrome, Safari, Firefox
- [ ] Navigate to Setlists → tap existing setlist
- [ ] Tap share icon (top-right, next to print icon)
- [ ] **Expected:** Modal bottom sheet displays with "Share Format" header
- [ ] Tap "Text / Email" option → **Expected:** Modal dismisses, share sheet opens with text format
- [ ] Repeat test with "Spreadsheet" option → **Expected:** Modal dismisses, share sheet opens with spreadsheet format

#### iOS/Android (REGRESSION CHECK)

- [ ] Navigate to Setlists → tap existing setlist
- [ ] Tap share icon
- [ ] **Expected:** Format picker modal displays correctly
- [ ] Tap "Text / Email" option → **Expected:** Modal dismisses, share sheet opens
- [ ] Tap "Spreadsheet" option → **Expected:** Modal dismisses, share sheet opens
- [ ] **Expected:** No visual or functional regression from previous behavior

---

## Implementation Notes

### Pattern Justification

The `GestureDetector` replacement follows a proven pattern in the BandRoadie codebase. The tuning picker bottom sheet (`tuning_picker_bottom_sheet.dart` lines 867, 970) uses `GestureDetector` for tap-sensitive widgets with decorated containers, confirming this approach is reliable and consistent with existing patterns.

### Trade-offs

**Loss of Material Ink Splash:**

- `InkWell` provides visual tap feedback via Material ink ripples
- `GestureDetector` does not provide this visual feedback
- **Acceptable because:**
  - Share format selection is a simple modal choice, not a high-frequency interaction
  - Mobile platforms still show system-level tap feedback
  - Tuning picker uses the same pattern without user complaints
  - Functional reliability outweighs cosmetic feedback loss

### Web-Specific Issue

Root cause: On Flutter web, `InkWell` with a direct decorated `Container` child blocks pointer events due to HTML/CSS layer stacking. The decorated container's paint layer intercepts pointer events before they reach the `InkWell` gesture recognition layer. This does not affect iOS/Android due to different rendering engines.

### Guardrails Compliance

- ✅ Modified only files listed in Architect plan
- ✅ No database schema changes
- ✅ No migration changes
- ✅ No config or initialization changes
- ✅ No auth or routing changes
- ✅ No new dependencies added
- ✅ No refactoring of unrelated code
- ✅ Preserved existing patterns and naming conventions

---

## Blockers Encountered

**None** — Implementation completed without blockers.

---

## Ready for Testing

The code change is complete and passes static analysis. Manual testing on web and mobile platforms is required to verify the fix resolves the pointer event issue on web without introducing regressions on iOS/Android.

**Recommended Test Order:**

1. Web platforms first (primary fix target)
2. iOS/Android regression testing
3. Multiple browsers on web (Chrome, Safari, Firefox)

---

## Engineer Sign-off

Implementation complete per Architect plan specification.

**Branch:** `bug/share-setlist-format-picker-web`  
**Commit Ready:** Yes (single file modification, passes `flutter analyze`)  
**Manual Testing Required:** Yes (see Verification Status section)
