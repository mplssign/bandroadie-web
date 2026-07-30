# Engineer Report

## Feature Slug
feature/band-member-manual-reorder

## Feature Title
Manual Drag-to-Reposition for Band Member Cards

## Goal
Add server-persisted manual drag-to-reorder for Band Members (admin-only), mirroring the existing Setlists drag-reorder mechanism, while preserving alphabetical sort as the default for any band that never manually reorders.

## Architect Tasks Completed
- [x] Task 1 — Migration: `position` column, unique deferrable constraint, `reorder_band_members` RPC — done
- [x] Task 2 — `MemberVM`: add `position` field — done
- [x] Task 3 — `MembersRepository`: select `position`, conditional sort, `reorderMembers` — done
- [x] Task 4 — `MembersState`/`MembersNotifier`: optimistic reorder + persist — done
- [x] Task 5 — `ReorderableBandMemberCard` (new file) — done
- [x] Task 6 — `BandMembersView`: conditional `SliverReorderableList` — done
- [x] Task 7 — `ContactsTabContent`: debounce + wire `onReorder` — done
- [x] Task 8 — `flutter analyze` — done, 0 errors / 0 warnings

## Files Created
- `supabase/migrations/20260729120000_add_position_to_band_members.sql`
- `lib/features/contacts/widgets/reorderable_band_member_card.dart`

## Files Modified
- `lib/features/members/member_vm.dart`
- `lib/features/members/members_repository.dart`
- `lib/features/members/members_controller.dart`
- `lib/features/contacts/widgets/band_members_view.dart`
- `lib/features/contacts/contacts_tab_content.dart`

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings

## Test Results
Not run — the Architect plan's Engineer Task Breakdown (Task 8) specifies only `flutter analyze`, and its Verification Plan is entirely SQL-based (Tier 1 pre-deploy / Tier 2 post-deploy, to be run by QA against the live database once the migration is pushed). No existing Flutter test file references `MemberVM`, `MembersRepository`, `MembersState`, or `MembersNotifier` (confirmed via grep across `test/`), so there was no pre-existing suite to run against the changed code.

## Verification
Manual steps performed:
- Read the full reference implementation (`reorderable_song_card.dart`, `setlist_detail_controller.dart:1032-1122`, `setlist_repository.dart:1029-1122`, `setlist_detail_screen.dart:544-570`) before writing each mirrored counterpart, to keep the optimistic-update/debounce/persist/revert shape and the drag-handle Stack/Listener structure faithful to the pattern the plan specifies.
- Read the live `reorder_setlist_items` and `remove_band_member` function definitions directly from the production database (via Supabase MCP, read-only `SELECT`, no writes) to copy the exact two-phase negative-position update syntax and the exact admin-check/RLS-qual shape (`role = 'admin'::band_role_type AND status = 'active'::text`) into the new `reorder_band_members` migration, rather than approximating it from the plan's prose alone.
- Confirmed the conditional sort in `MembersRepository.fetchMembersAndInvites` is byte-identical to the prior unconditional alphabetical sort when no member has a `position` set (verified by inspection: the `else` branch calls the exact same comparator function used before this change).
- Confirmed via `git status --short` that only the five Architect-approved files were modified and only the two Architect-approved new files were created — no off-limits file (per the plan's "Files Off-Limits" table) shows any diff.
- Ran `flutter analyze` twice — once immediately after implementation, once again after `dart format` — both clean (0 errors, 0 warnings).
- Did not run the app on a device/simulator or exercise the drag gesture visually — no GUI/device-interaction tooling is available in this session. Genuine on-device drag/reorder/persist/revert behavior is unexercised and should be verified by QA or a human before/soon after shipping, per the plan's own Verification Plan framing.
- Did not run `supabase db push` or otherwise deploy the migration — deployment is out of Engineer scope; the migration file is created and ready for QA/deploy per the plan's Rollout section.

## Deviations From Architect Plan
None. Every file created/modified matches the plan's "Files to Create" and "Files to Modify" tables exactly. The new RPC's SQL body was informed by reading the live `reorder_setlist_items`/`remove_band_member` definitions (as the plan itself instructs Engineer to be aware of, since these aren't in tracked migrations) rather than being invented from scratch, but its shape matches Task 1's specification verbatim (inlined admin check, row-count validation, two-phase negative-position update, `json_build_object('success', TRUE, 'reordered_count', v_expected)` return).

One implementation judgment call, within scope: Task 4 describes `MembersNotifier.reorderLocal` as reindexing `state.members` "by moving the item," mirroring `SetlistDetailController.reorderLocal`. Unlike `SetlistSong`, `MemberVM` has no mutable `position`-bearing `copyWith` needed for local display (the UI renders `state.members` in list order directly, not by re-sorting on a `position` field), so the local reorder moves the item in the list without also rewriting an in-memory `position` value on each `MemberVM` — the persisted `position` values are only ever set server-side by the RPC and re-read on the next fetch. This preserves the intended optimistic-UI/debounce/persist/revert behavior while avoiding an unnecessary field mutation the plan didn't ask for.

## Blockers Encountered
None.

## Ready For QA
Yes.

---

## Post-QA Fix

### Bug Reported
On iOS (and macOS), the Band Members tab (Contacts → Band segment) rendered completely blank — no "Band Members" header, no Add button, no member cards, no empty-state or error-state message. This was new: before the `band_members.position` migration was deployed, the same screen correctly showed an explicit `PostgrestException` error via `BandMembersView._buildErrorState`. The migration was confirmed correctly deployed (column exists, nullable, no default; RPC has the correct shape; test band had 2 active `band_members` rows). Reported against band "The Banana Stand" (`band_id e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`), which has 2 active members and thus renders via the admin `SliverReorderableList` branch.

### Investigation
Ran the app with console logging attached (`flutter run -d macos`, using `./run.sh macos`) and reproduced the bug live by navigating to Contacts → Band as an admin user. The screen rendered exactly as reported: segmented toggle visible, everything below it blank. The console captured the real exception:

```
══╡ EXCEPTION CAUGHT BY RENDERING LIBRARY ╞═══════════════════════════
The following assertion was thrown during performLayout():
A Stack requires bounded constraints from its parent. ...
Failed assertion: line 666 pos 7: 'size.isFinite'

The relevant error-causing widget was:
  Stack
  Stack:file:///.../lib/features/contacts/widgets/reorderable_band_member_card.dart:101:18
```

### Root Cause
**Confidence: HIGH (direct observation, exception captured live).**

`ReorderableBandMemberCard`'s `Stack` had **both** of its children wrapped in `Positioned` (the drag-handle strip and the content area). A `Stack` with zero non-positioned children has no basis to compute its own size — it falls back to requiring bounded constraints from its parent. Inside a `SliverList`/`SliverReorderableList` item slot, the incoming height constraint is unbounded (`0.0 <= h <= Infinity`, confirmed in the captured `BoxConstraints`), so `RenderStack._computeSize`'s `assert(size.isFinite)` failed during layout.

The reference implementation this widget mirrors, `reorderable_song_card.dart`, avoids this because its outer `Container` has a hardcoded `height: 121` that bounds the `Stack` from above — masking the same "all-Positioned Stack" shape. That works for song cards because title/artist are both `maxLines: 1`. It does not translate to `ReorderableBandMemberCard`, whose content mirrors `BandMemberCard` (member name is `maxLines: 2` and can wrap), so a hardcoded fixed height was never part of this widget's design — the original Architect plan and my initial implementation both missed that the borrowed Stack/Positioned shape depends on that fixed-height bound.

Because the exception was thrown synchronously during `BandMembersView.build()`'s returned widget tree (inside the admin `SliverReorderableList` branch), the *entire* return value failed — not just the one card — which is why the header, Add button, and everything else in the view also disappeared, not just the list.

### Fix
In `lib/features/contacts/widgets/reorderable_band_member_card.dart`: restructured the `Stack` so the content area is the Stack's one non-positioned child (letting the Stack size itself to the content's natural, variable height — the same way `BandMemberCard` sizes itself), and kept only the drag-handle strip as `Positioned` (`left: 0, top: 0, bottom: 0, width: _contentLeftPadding`), overlaid on top in paint/hit-test order so it still exclusively owns the drag gesture. The content is still wrapped in the same pointer-absorbing `Listener` as before. No other file was touched; no visual/behavioral change other than fixing the crash — drag-to-reorder, tap-to-open-drawer, crown icon, and 2-line name wrapping all behave identically to before, just without throwing.

### Verification
- Reproduced the exact reported bug live on macOS (`flutter run -d macos`) against band "The Banana Stand" before applying the fix; captured the real stack trace (above) rather than guessing.
- Applied the fix, ran `flutter analyze` — 0 errors, 0 warnings.
- Ran `dart format` on the changed file — no changes needed beyond the edit itself.
- Hot-restarted the app and re-navigated to Contacts → Band: header, Add button, and both member cards (with drag handles, admin crown) rendered correctly. Console log confirmed zero exceptions on this render pass.
- Performed an actual drag gesture (via `cliclick`, simulating a real drag on the handle) to reorder the two members; the on-screen order updated optimistically and persisted after the 500ms debounce.
- Queried the live database directly (read-only `SELECT`) after the drag and confirmed `band_members.position` was persisted correctly and in the order shown on screen (`position 0` for the member dragged to the top, `position 1` for the other) — full end-to-end confirmation that the fix didn't just silence the crash but that the feature's actual data flow (drag → optimistic reorder → debounce → RPC persist) works correctly.

### Files Modified (this fix)
- `lib/features/contacts/widgets/reorderable_band_member_card.dart` — already an Architect-approved file (created by this feature); no new files touched, no file outside the original plan's scope modified.

### Analyzer Results (post-fix)
Command: `flutter analyze`
Result: 0 errors / 0 warnings

### Ready For QA
Yes.
