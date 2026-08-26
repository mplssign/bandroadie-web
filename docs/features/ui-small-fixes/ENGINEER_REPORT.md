# Engineer Report — feature/ui-small-fixes

## Feature Slug

feature/ui-small-fixes

## Feature Title

Small UI/UX polish pass (batch of independent minor visual/interaction fixes)

## Goal

Apply a series of small, low-risk, UI-only adjustments given directly by Tony during this session, one prompt per fix.

## Fixes Applied

### Fix 1 — Four-field song detail metrics row ordered and laid out as a single 4-column section

Files: lib/features/setlists/widgets/song_details_bottom_sheet.dart
Change: Combined the BPM, Duration, Key, and Tuning controls into a single side-by-side metrics row in the requested BPM → Duration → Key → Tuning order, instead of rendering them as separate stacked rows.
Analyzer: 0 errors / 0 warnings

### Fix 2 — BPM and Duration edit dialogs use full-width primary save button with side-by-side text actions

Files: lib/features/setlists/widgets/bpm_input_dialog.dart, lib/features/setlists/widgets/duration_input_dialog.dart
Change: Updated the BPM/Duration dialog action layout so Cancel and Clear sit side by side as text buttons and Save is a full-width filled primary action matching the mock.
Analyzer: 0 errors / 0 warnings

### Fix 3 — Key picker bottom sheet has an opaque background

Files: lib/features/setlists/widgets/key_picker_bottom_sheet.dart
Change: Wrapped the key picker sheet in an opaque rounded container so the underlying screen content is no longer visible through the sheet background.
Analyzer: 0 errors / 0 warnings

### Fix 4 — Tuning picker sheet uses the maximum available height

Files: lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
Change: Increased the tuning sheet’s draggable size to expand to nearly the full screen height so more tuning options and capo controls remain visible without clipping.
Analyzer: 0 errors / 0 warnings

### Fix 5 — Key picker sheet uses the maximum available height

Files: lib/features/setlists/widgets/key_picker_bottom_sheet.dart
Change: Increased the key picker’s maximum sheet height so the full major/minor key list stays visible without the drawer feeling cramped.
Analyzer: 0 errors / 0 warnings

### Fix 6 — Key picker sheet matches tuning sheet height and header/footer styling

Files: lib/features/setlists/widgets/key_picker_bottom_sheet.dart
Change: Reworked the key picker to use the same draggable modal sheet pattern as tuning (matching height, drag handle, header with close action, and fixed Save/Cancel footer styling).
Analyzer: 0 errors / 0 warnings

### Fix 7 — Shared card outlines use one brighter border color

Files: lib/components/ui/app_card.dart
Change: Updated the default AppCard border to use the stronger shared border token so Song, Setlist, This Month's Events, Band Contact, Venue Contact, and Contact cards have a consistent and more noticeable outline.
Analyzer: 0 errors / 0 warnings

### Fix 8 — Key picker opens centered on the selected key

Files: lib/features/setlists/widgets/key_picker_bottom_sheet.dart
Change: Added one-time auto-scroll on open to center the currently selected key in view; when no key is selected, the drawer keeps the default top position.
Analyzer: 0 errors / 0 warnings

### Fix 9 — Dashboard Quick Actions use rose outlined buttons with rose labels

Files: lib/features/home/widgets/quick_actions_row.dart
Change: Updated the Quick Actions row buttons to outlined styling with a rose border and rose label text for all dashboard actions.
Analyzer: 0 errors / 0 warnings

### Fix 10 — Shared card backgrounds are opaque during drag overlap

Files: lib/components/ui/app_card.dart
Change: Set AppCard to default to the screen background color when no explicit card color is provided, preventing transparent overlap artifacts while dragging Setlist, This Month's Events, Band Contact, Venue Contact, and Contact cards.
Analyzer: 0 errors / 0 warnings

### Fix 11 — Tips & Tricks header matches Report Bugs back-arrow style

Files: lib/components/overlays/tips_and_tricks_overlay.dart
Change: Replaced the Tips & Tricks close icon header action with a left-side rose back-arrow icon button and matching title row structure to align with Report Bugs header styling.
Analyzer: 0 errors / 0 warnings

### Fix 12 — Menu destination headers now use identical back-arrow button config

Files: lib/features/tips/tips_and_tricks_screen.dart, lib/features/feedback/bug_report_screen.dart
Change: Standardized both screen app bar leading back-arrow icon buttons to the same explicit padding and constraints so Tips & Tricks and Report Bugs headers match exactly from the menu flow.
Analyzer: 0 errors / 0 warnings

### Fix 13 — Tips & Tricks now uses the same header component stack as Settings

Files: lib/features/tips/tips_and_tricks_screen.dart
Change: Switched Tips & Tricks from Scaffold/AppBar to AppScaffold/AppAppBar with AppIconButton and matching title typography so its header structure aligns with Settings.
Analyzer: 0 errors / 0 warnings

### Fix 14 — Report Bugs now uses the same header component stack as Settings

Files: lib/features/feedback/bug_report_screen.dart
Change: Switched Report Bugs from Scaffold/AppBar to AppScaffold/AppAppBar with AppIconButton and matching title typography so its header structure aligns with Settings.
Analyzer: 0 errors / 0 warnings

### Fix 15 — Calendar marker widths now clamp safely on narrow cells

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Hardened block-out marker segment and gap calculations to avoid negative widths/overflow on constrained layouts, preventing runtime constraint assertions and small-device RenderFlex overflow side effects.
Analyzer: 0 errors / 0 warnings

### Fix 16 — Report Bugs overlay fixed for Material ancestor and type-chip overflow

Files: lib/features/feedback/bug_report_screen.dart
Change: Wrapped the Report Bugs form body in a transparent Material to satisfy TextField requirements under AppScaffold, and made type-chip labels responsive with tighter horizontal padding + ellipsis so the Feature Request chip no longer overflows on narrow screens.
Analyzer: 0 errors / 0 warnings

### Fix 17 — Song card metrics adjusted so key sits closer to tuning badge

Files: lib/features/setlists/widgets/song_card.dart, lib/features/setlists/widgets/reorderable_song_card.dart
Change: Updated metric-slot alignments to spread BPM/Duration/Key slightly (Duration centered) and move Key to the right edge of its slot so it sits closer to the tuning badge on both standard and reorderable song cards.
Analyzer: 0 errors / 0 warnings (2 existing style infos unrelated to this change)

### Fix 18 — Song key badge changed to outlined amber style

Files: lib/features/setlists/widgets/song_card.dart, lib/features/setlists/widgets/reorderable_song_card.dart
Change: Replaced filled key badges with transparent outlined pills and set key text to amber, matching the badge accent color while keeping tuning badge styling unchanged.
Analyzer: 0 errors / 0 warnings (2 existing style infos unrelated to this change)

### Fix 19 — Song key letters made bold on song cards

Files: lib/features/setlists/widgets/song_card.dart, lib/features/setlists/widgets/reorderable_song_card.dart
Change: Increased key badge text weight from w600 to w700 so key letters render bolder on both standard and reorderable song cards.
Analyzer: 0 errors / 0 warnings (2 existing style infos unrelated to this change)

### Fix 20 — Calendar weekday labels styled as bold, white, uppercase

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Added a weekday header overlay in the calendar grid that renders uppercase day labels (SU–SA) with bold white text while preserving existing Forui calendar interactions and layout.
Analyzer: 0 errors / 0 warnings

### Fix 21 — Removed duplicate weekday row and styled native calendar weekdays

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Removed the added overlay weekday row and applied the bold white weekday styling directly to the built-in Forui weekday header so only one weekday row appears.
Analyzer: 0 errors / 0 warnings

### Fix 22 — Calendar day grid now uses single shared borders between adjacent cells

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Replaced per-cell full borders with edge-aware grid borders (top/left only on outer edges, right/bottom on each cell) so adjacent days share one divider line instead of rendering doubled borders; kept today highlighted with an inner rose outline.
Analyzer: 0 errors / 0 warnings

### Fix 23 — Calendar day cells are slightly larger and flush to outer border

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Increased day-cell height slightly and removed the default calendar container padding so the day grid expands to the calendar’s outer border with the extra outside margin eliminated.
Analyzer: 0 errors / 0 warnings

### Fix 24 — Calendar month/year title slightly indented

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Added a small start-side increase to the calendar header tappable padding so the month/year title is slightly indented while preserving the day-grid sizing and outer-border alignment.
Analyzer: 0 errors / 0 warnings

### Fix 25 — Calendar month/year title indentation increased further

Files: lib/features/calendar/widgets/calendar_grid.dart
Change: Increased the header title start inset again (from +4 to +8) for a more noticeable month/year indentation while keeping all other calendar layout settings unchanged.
Analyzer: 0 errors / 0 warnings

### Fix 26 — Nashville tuning badges now use dark screen-background label text

Files: lib/features/setlists/tuning/tuning_helpers.dart, lib/features/setlists/widgets/song_card.dart, lib/features/setlists/widgets/reorderable_song_card.dart, lib/features/setlists/widgets/song_metrics_row.dart, lib/features/setlists/widgets/bulk_add_songs_overlay.dart, lib/features/setlists/setlist_detail_screen.dart
Change: Added a Nashville-specific text-color override in tuning badge helpers (`#09090B`) and passed the tuning key through badge call sites so Nashville labels render in dark text while all other tunings keep existing contrast behavior.
Analyzer: 0 errors / 2 infos (pre-existing `sized_box_for_whitespace` in song/reorderable card)

### Fix 27 — Setlist search field no longer overflows at the bottom

Files: lib/features/setlists/setlist_detail_screen.dart
Change: Increased the fixed search field height from 40 to 44 so the Forui text field (with icon/keyboard focus state) fits cleanly without the 4px bottom overflow seen when opening search.
Analyzer: 0 errors / 0 warnings

### Fix 28 — Catalog card border made more subtle on Setlists page

Files: lib/features/setlists/widgets/setlist_card.dart
Change: Added a Catalog-only border override using a softer border tone (reduced-opacity neutral border) so the Catalog card outline appears less prominent while other setlist cards retain the stronger shared border.
Analyzer: 0 errors / 0 warnings

### Fix 29 — Release version/build bump for approved UI polish batch

Files: pubspec.yaml, web/version.json
Change: Bumped app version/build from `1.4.5+245` to `1.4.6+246` and kept web runtime version metadata in sync.
Analyzer: N/A (metadata-only change)

## Ready For QA

No — session in progress
