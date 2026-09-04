# Revert: Sheet Scroll-Collapse Header/Footer

## Feature Slug
`revert-sheet-scroll-collapse-header-footer`

## Feature Title
Revert: Sheet Scroll-Collapse Header/Footer

## Problem Summary
Tony requested a mechanical revert of the scroll-collapse feature (PR #242,
squash-merged as commit `8b91331` — currently the tip of `main`). Because it is
the tip and nothing merged after it, reverting `8b91331` restores the working
tree to the exact state of the preceding commit `891c86a` (the footer-
standardization feature, PR #241).

This is a MECHANICAL revert, not a diagnosis. No product/UX decision to make,
no root-cause analysis required.

## Root Cause
n/a (revert, not a fix). Confidence: HIGH — `git show 8b91331 --stat`
confirms the footprint (25 files) matches what the Manager summarized.

## Existing System Analysis
PR #242 introduced `CollapsingSheetScaffold` (a scroll-driven header/footer
collapse widget) and adopted it across 20 sheet/drawer files. It also shipped
3 feature docs. All 25 files land in a single squash commit at the tip of
`main`, so a single `git revert` is guaranteed to apply cleanly.

## Proposed Solution
Run `git revert --no-commit 8b91331`. Because `8b91331` is a non-merge squash
commit at the tip, no `-m` parent flag is needed and no conflicts are
expected. The inverse changes are left UNSTAGED on the working tree for QA to
review; the Manager commits at release time.

**Fallback (only if the revert reports a conflict, which it should not):**
`git checkout 891c86a -- <exact paths #242 touched>` for the 20 modified
sheets, then `rm` the two new source files. The 3 scroll-collapse docs are
handled by the same checkout of the `docs/features/sheet-scroll-collapse-
header-footer/` paths from `891c86a` (where they did not exist), or by
explicit `rm`.

## Database Impact
n/a — no migrations, no RLS, no RPCs, no triggers.

## Flutter Architecture Changes
n/a — reverting removes the `CollapsingSheetScaffold` abstraction and returns
every touched sheet to its prior structure (which is either a standard
`DraggableScrollableSheet` / `showModalBottomSheet` body or the `SheetFooter`
widget from PR #241).

## Files to Create
None.

## Files to Modify
The exact inverse of PR #242's 25-file diff, produced by `git revert
--no-commit 8b91331`:

- **2 files DELETED:**
  - `lib/components/ui/collapsing_sheet_scaffold.dart`
  - `test/components/ui/collapsing_sheet_scaffold_test.dart`
- **20 sheets/drawers RESTORED to their pre-#242 form** (from `lib/features/**`):
  - calendar: `add_block_out_drawer.dart`, `day_detail_bottom_sheet.dart`,
    `view_block_out_drawer.dart`
  - contacts: `band_member_detail_drawer.dart`,
    `band_member_edit_drawer.dart`, `contact_detail_drawer.dart`
  - events: `event_editor_drawer.dart`
  - financials: `add_financial_entry_bottom_sheet.dart`,
    `financial_entry_details_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`
  - gigs: `gig_notes_sheet.dart`, `view_gig_drawer.dart`
  - rehearsals: `rehearsal_notes_sheet.dart`, `view_rehearsal_drawer.dart`
  - setlists: `pause_creator.dart`, `setlist_picker_bottom_sheet.dart`,
    `song_details_bottom_sheet.dart`, `song_enrichment_review_sheet.dart`,
    `song_notes_drawer.dart`
  - songs: `enrichment_selector_bottom_sheet.dart`
- **3 scroll-collapse docs REMOVED** (from
  `docs/features/sheet-scroll-collapse-header-footer/`):
  - `ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md`

## Files Off-Limits
Anything outside PR #242's diff. Specifically:
- `lib/main.dart`, init order, `AppVersionService`, `DeepLinkService`,
  Supabase config — untouched by #242, must stay untouched here.
- `supabase/**`, `pubspec.yaml`, `pubspec.lock` — no dependency or DB change.
- Existing rescue branches (`rescue/scroll-collapse-format-reflow` and any
  siblings) — do not delete.
- The revert's OWN feature docs (`docs/features/revert-sheet-scroll-collapse-
  header-footer/ARCHITECT_PLAN.md` / `ENGINEER_REPORT.md` / `QA_REPORT.md`)
  are added separately by the Manager at release; the Engineer does not
  create/modify them as part of the revert.

## Change Budget
- Expected net line delta: `-3482 / +2078` (exact inverse of #242's stat).
- Expected new files: 0.
- Expected deleted files: 5 (2 source + 3 docs).
- Expected new public classes/methods: 0.
- Expected new dependencies: 0.

## System Impact Map
- Setlists: affected (5 sheets restored).
- Gigs: affected (2 sheets restored).
- Rehearsals: affected (2 sheets restored).
- Calendar / Members / Contacts / Events / Financials / Songs: affected (11
  sheets restored across these features).
- Auth: unaffected.
- Routing: unaffected.
- Notifications: unaffected.
- Platforms (iOS / Android / macOS / Web): unaffected — no platform-conditional
  code in #242.
- Init order: unaffected.

## Regression Risk
LOW. The tree after revert is byte-identical to `891c86a`, which shipped and
has been running in production. No auth, session, routing, init-order, or DB
surface is touched. The only risk is the revert itself misbehaving; QA's tree-
equality check (`git diff 891c86a -- lib test` empty) proves that did not
happen.

## Engineer Task Breakdown
1. From branch `revert/sheet-scroll-collapse-header-footer`, run `git revert
   --no-commit 8b91331`. Confirm it reports success with no conflicts and
   leaves the 25-file inverse diff UNSTAGED on the working tree.
   - If (and only if) it reports a conflict, stop and report — do not
     hand-resolve. Fallback approach in Proposed Solution is available but
     should not be needed.
2. Do not stage, commit, or push. The Manager stages and commits at release.

## Verification Plan
All checks below run against the working tree AFTER step 1, with the revert
applied but not yet committed.

**Tier 1 (pre-deploy, run locally):**
1. `flutter analyze` → 0 errors, 0 warnings.
2. `flutter test` (full suite) → all green, total test count DOWN to **195**
   (the 11 `CollapsingSheetScaffold` cases in
   `test/components/ui/collapsing_sheet_scaffold_test.dart` are gone).
3. `grep -rn "CollapsingSheetScaffold" lib test` → **zero matches**.
4. `git diff 891c86a -- lib test` (after staging the revert with `git add -A
   lib test`) → **empty** (working tree in `lib/` and `test/` matches
   `891c86a` byte-for-byte).
5. `ls docs/features/sheet-scroll-collapse-header-footer/` → the 3 scroll-
   collapse docs (`ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md`)
   are gone. (Other stray files like `PR_BODY.md` that existed only as
   untracked-on-main artifacts are outside the revert's scope.)

**Tier 2 (post-deploy):** n/a — this is a code revert, no server-side surface
changes.

## QA Regression Areas
QA smoke-tests the 20 restored sheets/drawers by opening each and confirming
- header/footer no longer collapse on scroll (they stay pinned, as they did
  pre-#242);
- form submission still works (add/edit financial entry, add block-out, edit
  band member, etc.);
- the shared `SheetFooter` from PR #241 still renders correctly (that
  feature is untouched by the revert).

Focused smoke targets (highest-touched sheets): `add_financial_entry_bottom_
sheet.dart`, `band_member_edit_drawer.dart`, `pause_creator.dart`,
`view_gig_drawer.dart`.

## Rollout Strategy
Standard: PR → CI → merge to `main` → next release. No feature flag, no
staged rollout — the reverted state is what was already in production two
weeks ago.

## Out of Scope
- Re-implementing scroll-collapse in a different form (Tony asked to revert,
  not to redesign).
- Adding the revert's own feature docs (`ARCHITECT_PLAN.md` /
  `ENGINEER_REPORT.md` / `QA_REPORT.md` under `docs/features/revert-sheet-
  scroll-collapse-header-footer/`) — Manager adds these separately at release.
- Cleaning up other untracked files on `main` (stray `PR_BODY.md` files,
  simulator screenshots) — not related to #242.
