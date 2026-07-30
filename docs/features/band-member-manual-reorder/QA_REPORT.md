# QA Report

## Feature Slug
feature/band-member-manual-reorder

## Feature Title
Manual Drag-to-Reposition for Band Member Cards

## Final Verdict
**APPROVED**

## Validation Summary
Reviewed the full `git diff origin/main` (working tree, uncommitted) hunk-by-hunk across all 5 modified files and both new files, cross-checked against the Architect's Engineer Task Breakdown (8 tasks) and Files to Create/Modify/Off-Limits tables. Compared the new `reorder_band_members` RPC's SQL, statement-by-statement, against the live production `reorder_setlist_items` and `remove_band_member` function definitions (read directly from the `nekwjxvgbveheooyorjo` project via Supabase MCP) and against the live `band_members` UPDATE RLS policy. Ran all four Tier 1 pre-deployment SQL checks against production (read-only) — all passed. Ran `flutter analyze` — 0 issues. Tier 2 post-deployment SQL checks and on-device drag verification were not executed (see Regression Check / Behavior Verification below for why) and are explicitly flagged as unexercised, not assumed passing.

## Architect Scope Review
- Scope adherence: compliant
- Files modified: exactly as expected — `lib/features/contacts/contacts_tab_content.dart`, `lib/features/contacts/widgets/band_members_view.dart`, `lib/features/members/member_vm.dart`, `lib/features/members/members_controller.dart`, `lib/features/members/members_repository.dart`. No file outside this list shows a diff.
- Files off-limits: not touched — verified `git diff --name-only` / `git status --porcelain` against the Architect's full Files Off-Limits table (`band_member_card.dart`, `az_*` helpers, Contacts/Venues files, drawers, `band_permissions*.dart`, legacy `members/widgets/*`, all `lib/features/setlists/**`, all pre-existing migrations, `lib/main.dart`) — none appear in the diff.
- Files created: exactly as expected — `supabase/migrations/20260729120000_add_position_to_band_members.sql` and `lib/features/contacts/widgets/reorderable_band_member_card.dart`. No other new file.

## Completeness Check
- All Architect tasks implemented: yes (Tasks 1–8, verified individually against the diff — see Behavior Verification)
- Missing tasks: none

## Behavior Verification
- Validation method: code-path analysis only for on-device drag interaction (no GUI/device tooling available in this session, consistent with the Engineer's own report); code-path analysis + live production SQL comparison for the database layer.
- Result: matches expected design in all respects reviewable by code inspection.
  - **Task 1 (migration):** `position INTEGER NULL`, `UNIQUE (band_id, position) DEFERRABLE INITIALLY DEFERRED`, and `reorder_band_members(p_band_id uuid, p_member_ids uuid[])` all present and match the plan's specification. RPC's inlined admin check (`role = 'admin' AND status = 'active'`) matches the live `band_members` UPDATE RLS policy's qual verbatim (confirmed by direct query — see Database Safety). Two-phase negative-position update is byte-for-byte structurally identical to the live `reorder_setlist_items` (Phase 1: `unnest(...) WITH ORDINALITY`, negative ordinal; Phase 2: `(-position) - 1`), substituting `band_members`/`position` for `setlist_songs`/`position` as specified. `SET search_path = public` present on the function signature (Guardrails §4).
  - **Task 2 (`MemberVM.position`):** added as nullable `int?`, populated from `bandMember['position']`. Confirmed `memberId` (used later as the RPC's `p_member_ids` element) is sourced from `bandMember['id']` — the `band_members` primary key the RPC validates against, not `user_id`. Correct.
  - **Task 3 (`MembersRepository`):** `position` added to the `band_members` select; sort logic replaced with a conditional (`hasManualOrder` check) — unpositioned-only case calls the *same* `alphabeticalCompare` function used for the positioned case's tiebreak, so the no-manual-order path is provably identical to the pre-change comparator, not just similar. `reorderMembers()` added, calls the RPC with both params always passed explicitly (Guardrails §4: no partial-parameter RPC calls), clears `_cache[bandId]` on success.
  - **Task 4 (`MembersState`/`MembersNotifier`):** `lastKnownGoodMembers`/`isReordering` fields and `clearLastKnownGood` copyWith flag added, mirroring `SetlistDetailState`. `reorderLocal`/`persistReorder` mirror `SetlistDetailController`'s optimistic-update/single-baseline-backup/revert-or-refetch shape.
  - **Task 5 (`ReorderableBandMemberCard`):** new file, `Stack` + `Positioned` drag-handle strip (`ReorderableDragStartListener`) + pointer-absorbing `Listener` over the content area, matching `reorderable_song_card.dart`'s structure. Renders the same name/crown/musical-roles content as `BandMemberCard` (compared both files side by side — presentational content matches, `BandMemberCard` itself is untouched). **Superseded for the drag-handle/content Stack shape specifically by the Re-Verification Pass below**, following the Post-QA Fix.
  - **Task 6 (`BandMembersView`):** `onReorder` param added; member sliver branches on `membersState.isCurrentUserAdmin` between `SliverReorderableList` (admin, draggable) and the original static `SliverList` (non-admin, unchanged, no drag handle rendered) — matches the plan's admin-gating and the setlists precedent.
  - **Task 7 (`ContactsTabContent`):** `Timer? _reorderDebounceTimer`, `_handleMemberReorder` (optimistic `reorderLocal` call + 500ms debounce + `persistReorder`), timer cancelled in existing `dispose()`, `onReorder: _handleMemberReorder` wired into the existing `BandMembersView(...)` call — matches `setlist_detail_screen.dart`'s reference shape.
  - **Task 8:** `flutter analyze` re-run independently this session — 0 issues (see Analyzer Results).
- **Not validated at runtime (unexercised, not assumed passing):** persistence across app restart, debounce collapsing of rapid drags, revert-on-network-failure UX, and cross-platform (Web/Android) behavior. No device/simulator/GUI tooling was available in this QA session, consistent with the Engineer's own report of the same limitation. (Drag/tap on macOS and the underlying data flow were subsequently exercised by the Engineer as part of the Post-QA Fix — see Re-Verification Pass below.)

## Regression Check
- Risk level: MEDIUM (consistent with Architect's own assessment — unchanged by this review)
- Systems reviewed: Members/RBAC (affected, as expected), Setlists (confirmed zero setlist files touched — read-only reference only), Auth/Session (unaffected — no diff in any auth-related file), Routing/init order (unaffected — `lib/main.dart` not touched, no diff), Gigs/Rehearsals/Notifications (unaffected, no diff in those areas).
- Regressions found: none identified via code-path analysis.
  - Default alphabetical sort: confirmed provably unchanged for any band with no manual reorder — the `else` branch of the new conditional calls the exact same `alphabeticalCompare` function that was the entire body of the old unconditional `.sort(...)` call, not a re-derived equivalent.
  - Mixed positioned/unpositioned state (new member joins after a manual reorder): sort comparator correctly places any `position == null` member after all positioned members, falling back to alphabetical among unpositioned members — matches the plan's specified behavior.
  - `remove_band_member` (hard `DELETE`), `update_member_role`, and the `band_members` insert path are unaffected by an added nullable column with no default — confirmed no diff touches these paths, and Postgres `ALTER TABLE ADD COLUMN ... NULL` (no default) is non-destructive to existing rows/queries.
  - Unidirectional data flow preserved: `BandMembersView` and `ReorderableBandMemberCard` only receive state via constructor and emit `onReorder` upward; no leaf widget calls the repository or notifier directly.
- **Why full runtime regression testing was not performed:** this QA session has no device/simulator/browser access; on-device drag and cross-platform behavior are explicitly flagged as unexercised above rather than assumed to pass.

## Database Safety
Verified (with one scope caveat noted below).
- Migration content read directly (not inferred from filename) and compared statement-by-statement against the live `reorder_setlist_items` and `remove_band_member` definitions, pulled from the production database via Supabase MCP.
- RLS: no policy added, dropped, or modified — confirmed no diff to any policy. The RPC's `SECURITY DEFINER` bypass is compensated by an inlined `EXISTS` check that matches the live `band_members` UPDATE policy's qual verbatim (confirmed by direct query, not assumed): `role = 'admin'::band_role_type AND status = 'active'::text`.
- No self-referencing RLS policy risk (Guardrails §4) — the check is a plain `EXISTS` subquery inside a function body, not a policy.
- No privilege escalation: only band admins (server-verified, not just client-hidden) can invoke a successful reorder.
- No unintended cascade/destructive behavior: `ADD COLUMN ... NULL` with no default and `ADD CONSTRAINT ... DEFERRABLE INITIALLY DEFERRED` are both non-destructive; Postgres treats each `NULL` as distinct under `UNIQUE`, so no existing row can violate the new constraint on creation.
- RPC signature (`p_band_id uuid, p_member_ids uuid[]`) matches the Dart client call in `MembersRepository.reorderMembers` exactly, with both parameters always passed explicitly (no partial-parameter RPC call, per Guardrails §4).
- **Tier 1 pre-deployment SQL checks — all run against production (read-only), all passed:**
  1. `band_members` has no `position` column yet: **passed**
  2. Reference `reorder_setlist_items` still contains `WITH ORDINALITY`: **passed**
  3. Live `band_members` UPDATE RLS policy is admin-only: **passed**
  4. Baseline row counts not separately recorded as a persisted artifact (informational-only baseline per the plan; not a pass/fail gate)
- **Tier 2 post-deployment SQL checks: unexercised.** The migration has not been applied to any database (confirmed by Test 1 above — the `position` column does not yet exist in production, and `git status` shows the migration file as untracked/undeployed). Per QA's Hard Rules, QA does not push, deploy, or run migrations — deployment happens after QA approval per Guardrails §10's branch lifecycle. This is the expected state at this pipeline stage, not a defect; Tier 2 checks (constraint deferrability, RPC-shape verification, row-count-preserved, `position IS NULL` on all existing rows, end-to-end reorder smoke test) should be run against the target database immediately after `supabase db push`, before this feature is considered fully verified in that environment.

## Analyzer Results
Command: `flutter analyze`
Result: 0 errors / 0 warnings (re-run independently this session, not solely relying on the Engineer's reported result)

## Test Results
Not run — no existing test file references `MemberVM`, `MembersRepository`, `MembersState`, or `MembersNotifier` (confirmed via `grep` across `test/` this session), and the Architect's Engineer Task Breakdown (Task 8) specifies only `flutter analyze`, not a test run. Consistent with the Engineer's report.

## Diff Safety Review
- Secrets: none found
- Debug artifacts: two `debugPrint` calls added (`members_controller.dart`, `members_repository.dart`), both gated behind `if (kDebugMode)` — this matches the existing codebase convention for error logging (e.g. `SetlistRepository`) and is not a stray/temporary debug artifact.
- Unrelated changes: none found — every hunk in the diff is directly attributable to the reorder feature; no formatting-only churn in unrelated code.
- Accidental deletions: none — `band_members_view.dart`'s member-sliver block was restructured (branched into two cases) but no existing functionality was removed; the non-admin path is textually identical to the prior single-path implementation.

## Issues Found

### Critical (must fix before commit)
None

### Warnings (should fix)
None

### Suggestions (optional)
1. `lib/features/members/members_repository.dart` is now 504 lines, 4 lines over the Guardrails §8 general-file target of 500. This is a warning-only threshold per Guardrails §8, the growth (+64/-4 lines) is directly attributable to this feature's `reorderMembers` method and conditional sort, and no further action is required — flagging only for awareness if this file is touched again soon.
2. In `MembersRepository.reorderMembers`, the `response['success'] == false` branch is currently unreachable: `reorder_band_members` only ever returns `{'success': true, ...}` on success or raises a Postgres exception (caught by the surrounding `catch`) on failure — it never returns a JSON body with `success: false`. Harmless (the branch would only ever fire if the RPC's contract changes in the future), not a functional bug, no action required.

---

## Re-Verification Pass (Post-QA Fix)

**Trigger:** After the original APPROVED verdict above, a blank-screen crash was found on-device (iOS/macOS) when opening Contacts → Band as an admin. Root cause and fix are documented in full in `ENGINEER_REPORT.md`'s "Post-QA Fix" addendum. This section re-verifies the fix against the current diff; it does not re-run every check from the original pass — only what could plausibly be affected by the fix, per this session's scope.

### Diff scope confirmed
- `git status --porcelain` / `git diff --name-only HEAD` show the same 5 modified tracked files as the original pass, plus the same 2 new files and 1 new migration — no file list change.
- File modification timestamps confirm only `lib/features/contacts/widgets/reorderable_band_member_card.dart` was touched after the original QA_REPORT.md was written (`reorderable_band_member_card.dart`: 2026-07-30 07:45:32; all 5 tracked files and the migration: 2026-07-29 23:05–23:08, predating the original QA_REPORT.md's own 23:16 write). This corroborates the Engineer's claim, verified independently rather than taken on trust.
- No off-limits file, and no file outside the original Architect scope, shows a diff.

### Root cause re-verification
Confirmed in code: the `Stack` in `ReorderableBandMemberCard.build()` now has exactly one non-`Positioned` child (the content `Listener`/`Padding`/`Column`, lines 101–161) and one `Positioned` child (the drag-handle strip, lines 164–183). A `Stack` sizes itself from its non-positioned children when available, so it no longer requires bounded incoming height constraints — this directly addresses the captured exception (`RenderStack._computeSize`'s `assert(size.isFinite)` failing inside the unbounded-height `SliverReorderableList` item slot). Root cause addressed, not just the symptom.

### Stack sizing — 1-line and 2-line names
- The content `Column`'s height is driven entirely by its `Text(member.name, maxLines: 2, ...)` and the role-list `Text` below it — for a 1-line name the `Column` (and therefore the `Stack`) is shorter; for a wrapped 2-line name it is taller. Both cases are handled identically by the same code path (no fixed-height assumption anywhere in this file, unlike the reference `reorderable_song_card.dart`, which hardcodes `height: 121` and is only safe because its own title text is `maxLines: 1`).
- The drag-handle `Positioned(left: 0, top: 0, bottom: 0, width: _contentLeftPadding)` has both `top: 0` and `bottom: 0` set, so it stretches to match the `Stack`'s own height in both the 1-line and 2-line cases automatically — no separate height calculation needed, and no risk of the handle strip being shorter or taller than the card.
- Verified via code inspection only in this pass (no on-device measurement of exact 2-line pixel heights was performed by QA); the Engineer's own post-fix on-device verification (macOS, real render pass, zero exceptions) exercised the actual card render for the reproducing band, which has real member names — this QA pass did not independently re-run the app.

### Drag-handle gesture ownership — code-path analysis
Traced Flutter's actual hit-test semantics for this Stack shape (read directly from the installed Flutter SDK source, `packages/flutter/lib/src/widgets/reorderable_list.dart` and `RenderProxyBoxWithHitTestBehavior`/`RenderStack`, not assumed from memory):
- `Stack` hit-tests children in reverse paint order (last-in-list first) and stops at the first child whose own `hitTest` returns `true`. In this file the drag-handle `Positioned` is the *last* child in the list, so it is both painted on top of and hit-tested before the content — consistent with the Engineer's stated intent ("overlaid on top in paint/hit-test order").
- One geometric difference from the reference `reorderable_song_card.dart` pattern was identified: in the reference, the content `Positioned` explicitly starts at `left: contentLeftPadding`, so it never geometrically overlaps the handle's strip. Here, because the content is now the Stack's non-positioned sizing child, its `Listener`/`Padding` box spans the *full* card width (the `_contentLeftPadding` is applied only via internal `EdgeInsets`, not as a bounding-box offset), so it geometrically overlaps the drag-handle strip's `[0, _contentLeftPadding)` region.
- Traced whether this overlap causes any leak: `ReorderableDragStartListener` wraps its child in a plain `Listener` with default `HitTestBehavior.deferToChild`, whose own `hitTestSelf` is `false`; it only claims a touch that lands on its actual (non-interactive) `Icon` descendant's rect, i.e. the handle strip has a real "dead zone" outside the icon glyph itself — a characteristic shared with the reference song-card pattern, not introduced by this fix. Where the handle claims the touch (on/near the icon), the Stack's stop-at-first-hit rule means content underneath is never reached — drag ownership is exclusive there, as required. Where the handle does *not* claim it (the dead-zone padding around the icon, within the same 36px-wide strip), the touch falls through to the content `Listener` underneath (opaque, so it claims the hit) and up to the outer `GestureDetector`'s tap recognizer — meaning a touch that starts in that dead zone resolves as a *tap*, never as a drag (content's `Listener.onPointerDown` is a no-op, not a drag-start call, so there is no path by which a touch anywhere outside the icon glyph can be misinterpreted as a drag-start). Net effect: drag can only ever be initiated from the icon glyph itself (identical to the reference implementation's actual behavior, despite the reference's non-overlapping geometry), and tap-to-open-drawer fires correctly everywhere else on the card, including the strip's dead zone — no gesture leak in either direction.
- This trace is code-path analysis against SDK source, not on-device confirmation. The Engineer's Post-QA Fix verification did perform a real on-device drag gesture (via `cliclick`) that reordered two members correctly end-to-end (optimistic UI → debounce → RPC → confirmed via direct DB read), which exercises the "drag succeeds from the handle" side. Neither the Engineer's report nor this QA pass explicitly re-exercised tap-to-open-drawer *after* this specific fix on a real device — this is flagged as unvalidated at runtime, not assumed to pass, notwithstanding the code-path analysis above.

### Analyzer re-run
Command: `flutter analyze`
Result: 0 errors / 0 warnings (re-run independently this session, after the fix)

### Diff safety re-check (fix-scoped)
- No secrets, no debug artifacts (`print`/`TODO`/`FIXME`/`debugPrint`) introduced in `reorderable_band_member_card.dart`.
- No unrelated changes — the diff to this file is scoped to the `Stack`-shape restructuring described above.

### Re-Verification Verdict
**APPROVED.** The fix addresses the reported root cause directly (verified in code), correctly handles both 1-line and 2-line member names via the same non-fixed-height mechanism, and — per SDK-source-level hit-test tracing — preserves exclusive drag-handle ownership with no tap/drag gesture leak, despite a geometric overlap between the content and handle regions that does not exist in the reference implementation. No other file changed. `flutter analyze` remains clean. The one gap versus a full sign-off: tap-to-open-drawer was not re-exercised on a real device after this specific fix (by either Engineer or QA) — recommended as a quick manual smoke check before/soon after shipping, consistent with the original pass's same category of caveat for on-device interaction testing, but not a blocker given the code-path trace above and the Engineer's confirmed real-device drag test.

### Issues Found (Re-Verification Pass)

### Critical (must fix before commit)
None

### Warnings (should fix)
None

### Suggestions (optional)
1. Consider a quick manual on-device tap test (open the member detail drawer by tapping a card's content area, not the handle) as a final smoke check before shipping — not re-exercised by Engineer or QA after this specific fix, though code-path analysis indicates no regression.
