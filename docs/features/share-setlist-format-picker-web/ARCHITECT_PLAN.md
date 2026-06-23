# Share Setlist Format Picker — Web Platform Fix

## Feature Slug

`bug/share-setlist-format-picker-web`

---

## Problem Summary

The format picker in the Share Setlist flow renders and functions correctly on iOS and Android but fails to register tap events on the web app. Users on web cannot select a share format (Text/Email or Spreadsheet), preventing them from sharing setlists in their preferred format.

---

## Root Cause

**Confidence: HIGH**

The `_ShareFormatOption` widget (line 3152 in `setlist_detail_screen.dart`) uses an `InkWell` with a direct child `Container` that has a `decoration`. On web, this pattern blocks pointer events — the decorated container interferes with Flutter's ink splash layer, preventing tap event registration.

This is a known Flutter web limitation where `InkWell` with decorated child containers fails to capture pointer events reliably. The issue does not affect mobile platforms due to different rendering engines.

---

## Reference Docs Consulted

No domain-specific reference documentation exists for Share Setlist or Setlists. This gap is noted for future documentation work.

---

## Existing System Analysis

### Current Behavior (All Platforms)

1. User taps Share icon in setlist detail header
2. `_handleShare()` is called (line 1232)
3. `_showShareFormatPicker()` displays a modal bottom sheet (line 1270)
4. Modal contains `_ShareFormatSheet` widget with two format options
5. Each option is a `_ShareFormatOption` widget with an `InkWell` wrapper
6. User taps an option → `Navigator.of(context).pop(ShareFormat.xxx)` is called
7. Selected format is used to generate share text

### Web-Specific Failure

On web, step 6 fails — taps on the format options do not trigger the `onTap` callback. The modal displays correctly with web-specific styling (custom background color, barrier color, disabled drag), but the `InkWell` tap handlers do not fire.

### Why Mobile Works

iOS and Android use native rendering pipelines where `InkWell` pointer event handling is not blocked by child decorations. Web uses HTML/CSS layers where the decorated container's paint layer intercepts pointer events before they reach the `InkWell`.

---

## Proposed Solution

Replace `InkWell` with `GestureDetector` in the `_ShareFormatOption` widget.

`GestureDetector` captures pointer events at the gesture recognition layer, which is not blocked by child decorations. This pattern is already proven reliable in the same codebase — the tuning picker bottom sheet uses `GestureDetector` for all tap-sensitive widgets (see `tuning_picker_bottom_sheet.dart` line 867, 970).

**Code Change:**

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

**Trade-off:**
Loss of Material ink splash visual feedback. This is acceptable because:

- The share format sheet is a simple selection modal, not a high-frequency interaction
- Mobile platforms will still show the tap feedback via system UI conventions
- The tuning picker uses the same pattern without user complaints

---

## Database Impact

**Not applicable** — pure UI widget interaction fix with no database queries or state mutations.

---

## Flutter Architecture Changes

### State Management

No changes. The `setlistDetailProvider` and `_handleShare()` flow remain unchanged.

### Widgets Modified

- `_ShareFormatOption` widget (line 3152): Replace `InkWell` with `GestureDetector`

### Repositories

No changes.

---

## Files to Create

**None** — single widget refactor.

---

## Files to Modify

| File                                               | Change Description                                                                                                                                           |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/setlist_detail_screen.dart` | Replace `InkWell` with `GestureDetector` in `_ShareFormatOption` widget (line ~3152). Remove `borderRadius` parameter (not applicable to `GestureDetector`). |

---

## Files Off-Limits

| File                                                   | Reason                                                                                                                               |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/setlists/new_setlist_screen.dart`        | Different screen (setlist creation flow). Its `_handleShare()` does not have a format picker (out of scope per acceptance criteria). |
| `lib/features/setlists/setlist_detail_controller.dart` | No state changes required for this UI fix.                                                                                           |
| `lib/features/setlists/setlist_repository.dart`        | No data access changes required.                                                                                                     |
| `lib/main.dart`                                        | Initialization order must not change.                                                                                                |

---

## System Impact Map

| System                                 | Impact                                                         |
| -------------------------------------- | -------------------------------------------------------------- |
| Gigs                                   | unaffected                                                     |
| Rehearsals                             | unaffected                                                     |
| Setlists / Catalog                     | **affected** — share format picker on web                      |
| Members / RBAC                         | unaffected                                                     |
| Auth / Session                         | unaffected                                                     |
| Routing                                | unaffected                                                     |
| Notifications                          | unaffected                                                     |
| Platform (iOS / Android / Web / macOS) | **Web only** — iOS/Android confirmed working per feature input |

---

## Regression Risk

**LOW**

### Rationale

- Single isolated widget change with no state or routing impact
- Pattern proven reliable in same codebase (tuning picker uses `GestureDetector`)
- Web-only fix with no changes to mobile code paths
- No database, auth, or initialization layers involved
- Loss of ink splash is visual-only with no functional impact

---

## Engineer Task Breakdown

1. **Locate `_ShareFormatOption` widget** in `setlist_detail_screen.dart` (line ~3152)
2. **Replace `InkWell` wrapper** with `GestureDetector`:
   - Change widget type: `InkWell` → `GestureDetector`
   - Remove `borderRadius` parameter (not supported by `GestureDetector`)
   - Keep `onTap` callback unchanged
   - Keep `child` structure unchanged
3. **Verify no other references** to `_ShareFormatOption` exist that depend on `InkWell` behavior
4. **Run `flutter analyze`** — must pass with 0 errors
5. **Test on web**:
   - Navigate to an existing setlist
   - Tap the share icon
   - Verify format picker modal displays
   - Tap "Text / Email" option → verify modal dismisses and share sheet opens
   - Repeat for "Spreadsheet" option
6. **Test on iOS/Android** (regression check):
   - Navigate to an existing setlist
   - Tap share icon → verify format picker displays
   - Verify both options work
   - Confirm no visual or functional regression
7. **Generate `ENGINEER_REPORT.md`** with tasks 1–6 marked complete

---

## Verification Plan

### Tier 1 — Pre-deployment

**Not applicable** — no database migrations or RPC changes.

### Tier 2 — Post-implementation

#### Web Platform Verification

1. Open BandRoadie web app in browser (Chrome, Safari, Firefox)
2. Navigate to Setlists tab → tap an existing setlist
3. Tap the share icon (top-right, next to print icon)
4. **Expected:** Modal bottom sheet displays with "Share Format" header and two options
5. Tap "Text / Email" option
6. **Expected:** Modal dismisses, system share sheet opens with plain-text formatted setlist
7. Repeat steps 2-3, tap "Spreadsheet" option
8. **Expected:** Modal dismisses, system share sheet opens with tab-delimited formatted setlist
9. Repeat on multiple browsers to confirm cross-browser compatibility

#### Mobile Platform Regression Check

1. Open BandRoadie on iOS device
2. Navigate to existing setlist → tap share icon
3. **Expected:** Format picker modal displays correctly
4. Tap "Text / Email" → verify share sheet opens
5. Repeat with "Spreadsheet" option
6. Repeat steps 1-5 on Android device
7. **Expected:** No functional or visual regression from current mobile behavior

#### Edge Cases

- Tap outside modal (on barrier) → **Expected:** Modal dismisses, no format selected, share flow cancels
- Tap close icon (if present) → **Expected:** Modal dismisses, no format selected
- Rapidly tap an option multiple times → **Expected:** Modal dismisses once, no duplicate share sheets

---

## QA Regression Areas

QA must validate the following:

1. **Primary:** Web format picker tap handling
   - Modal displays on web
   - Both format options register taps and dismiss modal correctly
   - Share sheet opens with correct format

2. **Regression:** Mobile format picker behavior
   - iOS: Format picker displays and both options work
   - Android: Format picker displays and both options work
   - No visual changes to modal appearance or animation

3. **Cross-browser (Web):**
   - Chrome, Safari, Firefox all handle taps correctly

4. **Share text generation:**
   - Text/Email format produces correct plain-text output (title, metadata, song list)
   - Spreadsheet format produces correct tab-delimited output (4-column structure)

5. **Other setlist share paths:**
   - Share from newly created setlist (`new_setlist_screen.dart`) still works (note: this screen does not have a format picker — verify direct share still functions)

---

## Rollout / Migration Strategy

**Not applicable** — pure client-side UI change. No backend deployment, database migration, or feature flag required.

Deploy via standard web build process:

```bash
./tools/deploy_web.sh
```

Post-deploy verification: Open production web app in incognito, test share format picker on a sample setlist.

---

## Out of Scope

1. Adding format picker to `new_setlist_screen.dart` (creation flow) — that screen currently shares with a fixed format and is not mentioned in the bug report
2. Visual redesign of the format picker modal
3. Adding additional share format options (e.g., JSON, CSV)
4. Share functionality for other features (events, financials)
5. Mobile app format picker UI changes — current mobile behavior is correct per acceptance criteria
6. Analytics tracking for format picker usage
