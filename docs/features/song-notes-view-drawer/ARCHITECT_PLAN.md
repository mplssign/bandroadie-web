# ARCHITECT_PLAN.md

## Feature Slug

`feature/song-notes-view-drawer`

---

## Problem Summary

The Song Details "Notes" button currently jumps directly into inline edit mode whether adding a new note or viewing an existing one. Once a note exists, there is no read-only "View notes" state — tapping the button (labeled "Edit Notes") or the notes preview card immediately replaces the main content area with an editable text field. Users cannot view their saved notes without the UI being in an editable state.

This feature restores the previously-approved UX from July 2026 (commits `780478e`, `d7893bc` — QA APPROVED but never merged) where notes have a dedicated read-only view in a bottom drawer, with an explicit "Edit" button to enter edit mode. However, the implementation cannot be directly reapplied: `song_details_bottom_sheet.dart` has diverged by 383 lines (289 insertions, 94 deletions) since then due to enrichment button work, key/tuning changes, and metrics layout refactoring.

---

## Root Cause

**Confidence: HIGH (direct code observation)**

In `song_details_bottom_sheet.dart`:

- Line 1312: The "Add Notes"/"Edit Notes" button's `onTap` handler calls `setState(() => _isEditingNotes = true)`, which immediately swaps the main content area to show `_buildNotesSubView()` — an inline editable text field.
- Line 1329: The button label reads `hasNotes ? 'Edit Notes' : 'Add Notes'` — there is no "View notes" label or state.
- Line 1356: The notes preview card's `onTap` also calls `setState(() => _isEditingNotes = true)`, bypassing any view-only affordance.

When `_isEditingNotes` becomes `true`, the scrollable area (line 921-922) renders `[_buildNotesSubView()]` instead of the main song info content, replacing the entire view with an editable `TextField`. There is no intermediate drawer or read-only display — the transition goes directly from "button/preview visible" to "editable field occupies full content area."

---

## Reference Docs Consulted

No domain-specific reference docs exist for the setlists/notes feature. Checked:

- `docs/reference/` — contains `architecture/`, `auth/`, `banners/`, `bpm/`, `deployment/`, `general/`, `notifications/`, `ui/` subdirectories. No `setlists/` or `notes/` reference.

Historical reference retrieved from deleted branch:

- `780478e:docs/features/song-notes-view-drawer/ARCHITECT_PLAN.md` — July 2026 approved design
- `d7893bc:lib/features/setlists/widgets/song_notes_drawer.dart` — QA-approved drawer implementation
- `d7893bc:lib/features/setlists/widgets/song_details_bottom_sheet.dart` — integration points (now stale)

---

## Existing System Analysis

### Current Behavior (main branch as of 2026-08-05)

**Notes persistence path:**

1. User opens Song Details via `showSongDetailsBottomSheet()`
2. `_SongDetailsSheet` initializes `_notesController` from `widget.song.notes` (String?)
3. If user taps "Add Notes" or "Edit Notes" button, `_isEditingNotes` becomes `true`
4. Main content area is replaced by `_buildNotesSubView()` — an inline multiline `TextField` bound to `_notesController`, with a "Back" link to restore main view
5. Edits to the field trigger `_checkForChanges()` → `_hasChanges` becomes `true`
6. User taps outer "Save" button → `_handleSave()` returns `SongDetailsResult` with `notesChanged: true`
7. `setlist_detail_screen.dart` line 1787 calls `notifier.updateSongNotes(song.id, result.notes)`
8. `setlist_repository.dart` line 2042 `updateSongNotes()` performs `UPDATE songs SET notes = $1 WHERE id = $2`

**Gap:**

- No dedicated read-only view exists once a note is saved
- No drawer or modal sub-sheet for notes — editing happens inline, replacing the main content
- Button never says "View notes" — it says "Edit Notes" when notes exist, and immediately enters edit mode

**File structure (current main):**

- `song_details_bottom_sheet.dart`: 1633 lines (grown from 1438 in July implementation)
- Changes since July: enrichment button (line 929-942), key selector integration, metrics row refactor (4-column layout), link type handling, `_justEnriched` state flag
- Affected regions: `_buildAddButtonsRow()` (line 1233-1346), `_buildNotesPreview()` (line 1347-1377), `_buildNotesSubView()` (line 1380-1447)

**Database state:**

- `song_notes` table: completely absent from codebase (verified via grep across `lib/**/*.dart`, `supabase/migrations/*.sql`, `sql/schema/*.sql`) — still orphaned/unused as diagnosed in July plan
- Notes are persisted via `songs.notes` column only
- No RPC, trigger, or RLS specific to notes

---

## Proposed Solution

1. **Create `lib/features/setlists/widgets/song_notes_drawer.dart`** — a new `StatefulWidget` `SongNotesDrawer` with internal state `_isEditing` (bool) and `_notesController` (seeded from `notes` parameter). Public entry point: `showSongNotesDrawer(BuildContext context, {required String notes})`.

   **View mode (`_isEditing == false`):**
   - Drag handle + header "Notes" (`AppTextStyles.pageTitle`) + divider
   - Scrollable read-only content: `Text(widget.notes, style: AppTextStyles.callout)`
   - Footer: full-width "Edit" `TextButton` (rose `AppColors.primary`, `calloutEmphasized`) + centered "Cancel" `TextButton` below it

   **Edit mode (`_isEditing == true`):**
   - Same header/divider
   - Body: editable multiline `TextField` (mirrors `_buildNotesSubView()` styling: `context.colors.background` fill, `context.colors.border` outline, `minLines: 8`, hint `'Add notes for this song...'`)
   - Footer: full-width "Save" `FilledButton` (disabled/greyed when `_notesController.text.trim() == widget.notes.trim()` — this was the Critical issue from QA Round 1 that must not regress) + centered "Cancel" `TextButton` below it

   **Return contract:**
   - View-mode "Cancel" → `Navigator.pop(null)` (no edits possible in view mode)
   - Edit-mode "Cancel" → reset `_notesController.text` to `widget.notes`, `setState(() => _isEditing = false)` — does not pop, returns drawer to view
   - Edit-mode "Save" → `Navigator.pop(_notesController.text.trim())`
   - System back/swipe dismiss → use `PopScope` with `onPopInvokedWithResult` (same pattern as `_SongDetailsSheet._handleCancel()`) to treat as edit-mode Cancel if editing, else view-mode Cancel

   **Dark-mode safety:**
   - Use `context.colors.surface` for sheet background (per PR #56 dark-mode fix convention)
   - Use `Spacing.cardRadius` for top corner radius
   - Never hardcode gray/color values

2. **Modify `song_details_bottom_sheet.dart`** (minimal edits to already-large 1633-line file):

   **Import:**

   ```dart
   import 'song_notes_drawer.dart';
   ```

   **New method `_viewNotes()`:**

   ```dart
   Future<void> _viewNotes() async {
     final result = await showSongNotesDrawer(
       context,
       notes: _notesController.text.trim(),
     );
     if (result != null) {
       setState(() {
         _notesController.text = result;
       });
       _checkForChanges();
     }
   }
   ```

   **Update `_buildAddButtonsRow()` line ~1312:**
   - Change `onTap` from `() => setState(() => _isEditingNotes = true)` to `_viewNotes` when `hasNotes` is true
   - Change label (line 1329) from `hasNotes ? 'Edit Notes' : 'Add Notes'` to `hasNotes ? 'View notes' : 'Add Notes'` (note casing: lowercase 'n')
   - When `hasNotes` is false, behavior is unchanged (still sets `_isEditingNotes = true` for inline add)

   **Update `_buildNotesPreview()` line ~1356:**
   - Change `onTap` from `() => setState(() => _isEditingNotes = true)` to `_viewNotes`
   - This provides a consistent entry point: both button and preview card route through the new drawer when notes exist

   **Do not modify:**
   - `_isEditingNotes`, `_buildNotesSubView()`, `_handleSave()`, `_checkForChanges()` — these remain for the "Add notes" (no existing note) inline flow
   - Enrichment, key/tuning, BPM, duration, lyrics, links logic — all untouched

3. **Persistence behavior (explicit):**
   - Saving inside the drawer does NOT write to the database immediately
   - Drawer's "Save" only updates the parent sheet's in-memory `_notesController.text` and triggers `_checkForChanges()` → `_hasChanges = true`
   - The note is persisted only when the user taps the outer Song Details "Save" button, exactly like tuning/BPM/duration/key
   - If the user dismisses the Song Details sheet after saving in the drawer but without tapping outer Save, the existing `_handleCancel()` / unsaved-changes dialog machinery catches it
   - This keeps a single source of truth for "unsaved changes" and reuses the proven "sub-dialog returns value → parent tracks diff → outer Save persists" pattern

---

## Database Impact

**Not applicable.** No migration, RLS, RPC, or trigger changes required.

The feature continues to use:

- `songs.notes` column (already functional, exercised by current inline-edit flow)
- `SetlistRepository.updateSongNotes()` (line 2042) — signature and behavior unchanged
- `SetlistDetailNotifier.updateSongNotes()` — called from `setlist_detail_screen.dart` line 1787, unchanged

The orphaned `song_notes` table remains out of scope (no references in codebase, no migration history).

---

## Flutter Architecture Changes

**New widget:**

- `SongNotesDrawer` (`StatefulWidget`) in new file `song_notes_drawer.dart`
- UI-local state only: `_isEditing` (bool), `_notesController` (TextEditingController)
- No Riverpod provider, no repository call — pure UI state machine

**Modified widget:**

- `_SongDetailsSheet` in `song_details_bottom_sheet.dart`
  - New private method: `_viewNotes()`
  - Two `onTap` handler edits: button (line ~1312) and preview (line ~1356)
  - One label edit: button text (line ~1329)
  - No new state fields (reuses `_notesController`, `_checkForChanges()`)

**No changes to:**

- Riverpod providers
- Repository methods
- Controller methods
- Screen-level routing or state

---

## Files to Create

| File                                                   | Justification                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_notes_drawer.dart` | Houses the new View/Edit Notes bottom drawer. Kept separate to avoid growing the already-oversized `song_details_bottom_sheet.dart` (1633 lines, exceeds 500-line guideline §8). Isolates the view/edit/save/cancel state machine from the parent sheet's already-complex logic (enrichment, multi-field editing, lyrics, links). |

---

## Files to Modify

| File                                                           | What changes                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_details_bottom_sheet.dart` | Add import for `song_notes_drawer.dart`. Add new private method `_viewNotes()` (~7 lines). Update `_buildAddButtonsRow()` notes button: change label to `'View notes'` when notes exist, change `onTap` to call `_viewNotes()` when notes exist (leave inline flow for no-notes case). Update `_buildNotesPreview()` `onTap` to call `_viewNotes()`. No other methods or state fields modified. |

---

## Files Explicitly Off-Limits

| File                                                       | Reason                                                                                                                                          |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlist_detail_screen.dart`         | Oversized (3,462 lines per July report — likely grown further). Its `updateSongNotes` call contract (line 1787) is unchanged; no edit required. |
| `lib/features/setlists/setlist_repository.dart`            | Oversized (4,199 lines per July report). `updateSongNotes()` (line 2042) works correctly; no signature or behavior change needed.               |
| `lib/features/setlists/setlist_detail_controller.dart`     | `updateSongNotes()` signature and behavior unchanged.                                                                                           |
| Any `song_notes` table / migration                         | Orphaned table, out of scope per existing system analysis.                                                                                      |
| `lib/main.dart`                                            | Unrelated; init order must not change (Guardrail §1).                                                                                           |
| Enrichment, key/tuning, BPM, duration, lyrics, links files | Unrelated to notes UI flow.                                                                                                                     |

**Migration policy:** not required  
**Edge function deploy:** not required  
**New dependencies:** not allowed / none needed (Flutter Material + existing design tokens only)  
**New files:** `lib/features/setlists/widgets/song_notes_drawer.dart` (justified above)

---

## System Impact Map

| System                                 | Impact                                                                                                                                                                                                                            |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                                                                                                                                        |
| Rehearsals                             | unaffected                                                                                                                                                                                                                        |
| Setlists / Catalog                     | **affected** — `song_details_bottom_sheet.dart` gains new drawer import, one new method, three small edits (two `onTap` handlers, one label). No change to setlist ordering, drag-reorder, catalog logic, or song card rendering. |
| Members / RBAC                         | unaffected — `isReadOnly` behavior for notes button/preview unchanged (if `isReadOnly: true`, button is hidden; preview `onTap` is `null`)                                                                                        |
| Auth / Session                         | unaffected                                                                                                                                                                                                                        |
| Routing                                | unaffected — modal bottom sheet only, no route or navigation stack change                                                                                                                                                         |
| Notifications                          | unaffected                                                                                                                                                                                                                        |
| Platform (iOS / Android / Web / macOS) | **affected on all four** — pure Flutter widget change, no platform-specific code. `showModalBottomSheet` is already in use throughout codebase, behaves identically across platforms.                                             |

---

## Regression Risk

**LOW**

**Rationale:**

- Only one system (Setlists) affected, and within it only one widget file gains one new method + three small edits
- No auth, session, routing, or init-order changes
- No database mutations, migrations, or RPC signature changes — persistence path is reused byte-for-byte
- The new drawer is self-contained UI-local state (`StatefulWidget`), no cross-feature state or provider involvement
- The two edited methods (`_buildAddButtonsRow()`, `_buildNotesPreview()`) are narrowly scoped, do not touch title/artist/tuning/BPM/duration/key/lyrics/links logic
- The "sub-dialog returns value → parent tracks diff → outer Save persists" pattern is already proven by tuning/BPM/duration/key in the same file
- The inline "Add notes" (no existing note) flow is preserved byte-for-byte — only the "Edit Notes" (note exists) path changes
- This exact UX was QA APPROVED in July 2026 (QA Round 2), so the interaction model has already been validated once (though on a now-stale codebase)

**Risk mitigations:**

- The Critical issue from QA Round 1 (Save button not disabled when text unchanged) is explicitly designed into the solution from the start
- Dark-mode safety is explicitly specified (use `context.colors.surface`, never hardcode colors)
- Verification plan includes all platforms (iOS/Android/Web/macOS) and dark-mode testing
- The new drawer does not persist directly to the database, preserving the single "outer Save = DB write" contract

---

## Engineer Task Breakdown

1. Create `lib/features/setlists/widgets/song_notes_drawer.dart` with `SongNotesDrawer` (`StatefulWidget`) and `showSongNotesDrawer(BuildContext, {required String notes})`. Implement view mode (read-only content, "Edit" button, "Cancel" link) and edit mode (editable `TextField`, "Save" button disabled when text unchanged, "Cancel" link). Use `context.colors.surface` for background, `Spacing.cardRadius` for corner radius. Implement `PopScope` dismiss handling per "Proposed Solution" above.

2. In `song_details_bottom_sheet.dart`, add import: `import 'song_notes_drawer.dart';`

3. In `song_details_bottom_sheet.dart`, add new private method `_viewNotes()` per "Proposed Solution" above (~7 lines: call `showSongNotesDrawer`, check result, update `_notesController.text`, call `_checkForChanges()`).

4. In `song_details_bottom_sheet.dart`, update `_buildAddButtonsRow()` line ~1329: change label from `hasNotes ? 'Edit Notes' : 'Add Notes'` to `hasNotes ? 'View notes' : 'Add Notes'`.

5. In `song_details_bottom_sheet.dart`, update `_buildAddButtonsRow()` line ~1312: change `onTap` from `() => setState(() => _isEditingNotes = true)` to conditional: `hasNotes ? _viewNotes : () => setState(() => _isEditingNotes = true)`. (Preserves inline flow for "Add Notes" case.)

6. In `song_details_bottom_sheet.dart`, update `_buildNotesPreview()` line ~1356: change `onTap` from `() => setState(() => _isEditingNotes = true)` to `_viewNotes`.

7. Run `flutter analyze` — confirm 0 new errors/warnings introduced.

**Task dependencies:**

- Tasks 2–6 depend on Task 1 (file must exist)
- Tasks 2–6 are sequentially ordered (import → method → label → button onTap → preview onTap)
- Task 7 is post-implementation gate

---

## Verification Plan

This feature has no SQL/migration surface. Verification is manual + analyzer only.

### Pre-implementation Gate

Manager/Tony must confirm the following design decisions before Engineer starts:

1. **Commit-timing semantics:** Saving inside the Notes drawer updates in-memory state only (`_notesController.text`), not the database. The note is persisted only when the user taps the outer Song Details "Save" button. If the user backs out of Song Details after saving in the drawer, the existing unsaved-changes dialog will catch it.

2. **Preview card tap behavior:** The truncated notes preview card (below the buttons row) will also route to `_viewNotes()` rather than jumping to inline edit, for consistency. Alternative: leave preview jumping to inline edit (one-line revert if rejected).

### Manual Verification (Post-implementation, Pre-QA)

**Functional flow:**

1. Song with no note → button reads "Add Notes" → tap → inline field opens (unchanged behavior) → type text → tap outer Save → sheet closes → reopen same song → button now reads "View notes."

2. Song with existing note → button reads "View notes" → tap → Notes drawer opens over Song Details, titled "Notes," shows full saved content in read-only mode, "Edit" button visible, "Cancel" link below it.

3. In read-only Notes view, tap "Edit" → drawer body becomes editable `TextField` pre-filled with existing note, footer shows "Save" + "Cancel."

4. Edit text, tap "Save" → drawer closes (or returns to read-only view per final UX decision) → underlying Song Details sheet's outer "Save" button becomes enabled (since `_hasChanges` is now true).

5. Tap outer "Save" → sheet closes → reopen song → note persisted, button still reads "View notes."

6. Repeat step 3, edit text, tap "Cancel" (edit mode) → drawer returns to read-only view showing original (pre-edit) content; outer "Save" button state unchanged (no spurious "unsaved changes" from a discarded edit).

7. From read-only Notes view, tap "Cancel" (view mode) → drawer closes entirely, back to Song Details sheet, no changes.

8. Tap the truncated notes preview card (below the buttons) → confirms it also opens the Notes drawer (not inline edit).

9. Dark mode: open Notes drawer in both view and edit mode → confirm sheet background renders `context.colors.surface` correctly, no hardcoded gray, no duplicate-rendering artifact.

10. Read-only Song Details mode (`isReadOnly: true`): confirm button is hidden, preview card is non-interactive (both already true in current code, must not regress).

**Platform coverage:**

- iOS device/simulator
- Android device/emulator
- Web (Chrome/Safari)
- macOS (if available)

**Critical regression check:**

- Save button in edit mode must be disabled when text is unchanged from the original note (QA Round 1 Critical issue — must not regress)

### Analyzer Gate

Run `flutter analyze` — must report 0 new errors, 0 new warnings.

---

## QA Regression Areas

**Primary validation:**

- Notes button label changes from "Edit Notes" to "View notes" when note exists
- Notes drawer opens in read-only view, not edit mode
- Edit button in drawer enters edit mode correctly
- Save button is disabled when text unchanged (Critical issue guard)
- Cancel in edit mode returns to read-only view (does not close drawer)
- Cancel in view mode closes drawer
- Outer Song Details "Save" persists the note (not the drawer's internal Save)
- Unsaved-changes dialog fires correctly when drawer-edited note is not yet saved via outer Save

**Regression testing:**

- Song Details: title/artist/tuning/BPM/duration/key/lyrics/links editing — confirm no regression from the three touched lines
- Inline "Add Notes" flow (when no note exists) — must be byte-for-byte unchanged
- Setlist save flow: confirm `SongDetailsResult.notesChanged` still correctly gates `updateSongNotes` calls
- Dark/light theme parity for the new drawer (dark-mode-only app per copilot-instructions, but PR #56 precedent requires color token verification)
- `isReadOnly: true` mode: confirm button hidden, preview non-interactive (unchanged)

**Platform parity:**

- iOS: Notes drawer renders, dismiss gestures work
- Android: Notes drawer renders, back button works
- Web: Notes drawer renders, escape key / click-outside dismisses correctly
- macOS: Notes drawer renders (if tested)

---

## Rollout / Migration Strategy

Not applicable — no database, config, or dependency changes. Standard branch → implement → PR → QA → merge flow per Guardrails §10.

Post-merge: no deploy script or cache-clearing required (pure client UI change).

---

## Out of Scope

- **Migrating to `song_notes` table:** The orphaned `song_notes` table is unused, untracked by migration, and structurally mismatched (multi-author `created_by` model vs. single-field note). Addressing this is separate technical debt, not part of this feature.

- **Shared drawer base widget extraction:** Gigs, rehearsals, calendar, setlists all duplicate the same drag-handle/decoration/header pattern. Extracting a reusable base is worth doing eventually but out of scope per Guardrail §7 ("Prefer localized in-place edits over new abstractions").

- **Read-only notes visibility when `isReadOnly: true`:** The button/preview are already hidden in read-only mode. Making them visible (view-only, no Edit) is a separate feature request, not part of this work.

- **Immediate database persistence from drawer:** The drawer's "Save" updates in-memory state only. The outer Song Details "Save" persists to DB. Changing this would introduce a second, inconsistent persistence path and is explicitly rejected per "Proposed Solution" §3.

- **Confirmation dialog on edit-mode Cancel:** The feature input doesn't request one, and the outer sheet already provides unsaved-changes protection. Adding a nested confirmation dialog would be redundant and is out of scope.

---

## Additional Context

**Historical precedent:**

- This feature was designed, implemented, and QA-approved on 2026-07-15 (commits `780478e`, `d7893bc`, branch `feature/song-notes-view-drawer` — now deleted)
- QA Round 1 found a Critical issue: Save button not disabled when text unchanged
- Engineer fixed it
- QA Round 2 was APPROVED with 0 regressions, 0 new analyzer issues
- The branch was never merged to main, and the branch ref was subsequently deleted (commits still exist in git object cache)

**Why re-diagnose:**

- `song_details_bottom_sheet.dart` has diverged by 383 lines (289 insertions, 94 deletions) since `d7893bc` due to unrelated work:
  - Enrichment button added (line 929-942)
  - Key selector integration
  - Metrics row refactored to 4-column layout
  - Link type handling expanded
  - `_justEnriched` state flag introduced
- The old diff cannot be cleanly reapplied
- This plan re-diagnoses current `main` as of 2026-08-05 and designs fresh integration against the current 1633-line file structure
- The old plan and implementation serve as validated UX reference only, not as reapplicable code

**Known gap flagged in old QA but never closed:**

- Manual/device verification (dark-mode render, iOS/Android/Web) was never actually performed in either QA round — only code-path analysis
- This plan explicitly requires platform testing in "Verification Plan" so it isn't lost again

**PR #56 context:**

- A prior PR (number 56) fixed a dark-mode rendering bug where bottom sheets hardcoded gray backgrounds instead of using `context.colors.surface`
- This plan explicitly requires `context.colors.surface` from the start to avoid reintroducing the same issue

---

_END OF ARCHITECT_PLAN.md_
