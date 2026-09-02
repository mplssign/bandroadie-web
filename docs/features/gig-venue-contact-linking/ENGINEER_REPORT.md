# Feature Slug

feature/gig-venue-contact-linking

# Feature Title

Link band-wide Contacts to Gigs (autocomplete + inline create)

# Cycle Number

2

# Goal

Address the three QA follow-ups on the existing gig-contact linking implementation: remove shipping debug prints, clear info-level analyzer hints in the touched feature files, and reduce the `event_editor_drawer.dart` feature delta by moving gig-contact dialog/state code out of the drawer.

# Architect Tasks Completed

1. Complete. Removed the three QA-flagged `debugPrint(` calls introduced by this feature from `lib/features/events/widgets/event_editor_drawer.dart` and `lib/features/gigs/widgets/view_gig_drawer.dart`.
2. Complete. Applied scoped automated fixes across the touched feature files with the local SDK `dart fix --apply` path, then verified the focused analyzer returns no issues.
3. Complete. Extracted the gig contact inline-create dialog and the repeatable gig-contact row state bookkeeping out of `EventEditorDrawer` into a single small helper in `gig_form_fields.dart`, reducing the drawer add-line count to `181`.

# Files Created

- None in Cycle 2.

# Files Modified

- `lib/features/events/events_repository.dart`
- `lib/features/events/models/event_form_data.dart`
- `lib/features/events/widgets/event_editor_drawer.dart`
- `lib/features/events/widgets/gig_form_fields.dart`
- `lib/features/gigs/gig_repository.dart`
- `lib/features/gigs/widgets/view_gig_drawer.dart`
- `test/app/models/gig_test.dart`
- `docs/features/gig-venue-contact-linking/ENGINEER_REPORT.md`

# Analyzer Results

- Command run: `flutter analyze lib/app/models/gig.dart lib/features/events/events_repository.dart lib/features/events/models/event_form_data.dart lib/features/events/widgets/event_editor_drawer.dart lib/features/events/widgets/gig_form_fields.dart lib/features/gigs/gig_repository.dart lib/features/gigs/widgets/view_gig_drawer.dart test/app/models/gig_test.dart`
- Environment note: the shell PATH could not resolve the Flutter wrapper by name, so the command was executed successfully via `/bin/bash /opt/homebrew/share/flutter/bin/flutter` with `PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin`.
- Result: `No issues found!`
- Effective status: `0` errors, `0` warnings, `0` info issues in the touched files.

# Test Results

- Command run: `flutter test test/app/models/gig_test.dart`
- Result: `All tests passed!` (`6` tests)

# Code Efficiency/Bloat Check

- Helper reuse search performed before extraction:
  - searched `lib/**` for `showCreate.*ContactDialog|ContactFormScreen|is not in your contacts list|Create Contact`
  - searched `lib/**` for repeatable row/controller patterns around `FAutocompleteController`, append/remove row helpers, and focus-node disposal
  - result: no existing gig-contact dialog helper or repeatable contact-row state helper matched this behavior, so one small public helper (`GigContactRowsController`) was added in an already-authorized file.
- `lib/features/events/widgets/event_editor_drawer.dart` remains an oversized existing file, but this cycle reduced the feature add-line count from the QA-reported `+482` to `181`, which is within the Architect plan budget (`+120 to +220`).
- Existing oversized touched files remain existing debt, not introduced by Cycle 2:
  - `lib/features/events/events_repository.dart`
  - `lib/features/events/models/event_form_data.dart`
  - `lib/features/events/widgets/event_editor_drawer.dart`
  - `lib/features/events/widgets/gig_form_fields.dart`
  - `lib/features/gigs/widgets/view_gig_drawer.dart`

# Verification

- Read `docs/features/gig-venue-contact-linking/ARCHITECT_PLAN.md` in full and confirmed the branch matches `feature/gig-venue-contact-linking`.
- Confirmed the three QA-targeted debug prints were present before editing and removed afterward.
- Ran a focused analyzer first on the three directly edited UI files after extraction to catch local issues before broader cleanup.
- Applied scoped automated fixes only to the approved touched files using `/opt/homebrew/share/flutter/bin/cache/dart-sdk/bin/dart fix --apply` one file at a time.
- Re-ran focused `flutter analyze` on the full touched-file list and confirmed `No issues found!`.
- Ran `flutter test test/app/models/gig_test.dart` and confirmed all tests passed.
- Measured the current `event_editor_drawer.dart` add-line count with `git diff ... | grep '^+' ... | wc -l` and recorded `181`.

# Deviations From Plan

- The exact multi-file `dart fix --apply` command requested by QA is not accepted by the local Dart SDK (`Only one file or directory is expected.`), so the same fix scope was applied by invoking `dart fix --apply` once per approved file.
- The shell environment in this session did not expose `flutter`, `dart`, `git`, or core utilities on PATH by default, so verification commands were run with explicit absolute binaries and a minimal restored PATH. No project configuration was changed.

# Blockers Encountered

- No blocker remained after switching to absolute SDK/tool paths.

# Ready For QA

Yes