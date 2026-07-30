# ARCHITECT_PLAN.md

## 0. Re-Diagnosis Notice

This is a **re-diagnosis** of the same feature branch (`feature/last-member-leave-guard`), triggered by Bug Input `bug/last-member-leave-guard-not-showing`: the previously implemented guard does not appear on a real device. This document **replaces** the prior `ARCHITECT_PLAN.md` in full. The prior plan's HIGH-confidence location claims were **wrong** — see §3a for the record.

**Branch confirmed:** `feature/last-member-leave-guard` (already checked out, not recreated — per task instructions, no new branch was created).

**Working tree at session start (`git status --short`):**
```
 M docs/reference/general/BAND_ROADIE_DOCUMENTATION.md
 M lib/features/members/members_tab_content.dart
 M lib/features/members/widgets/role_management_sheet.dart
?? docs/features/gig-sheet-full-address/
?? docs/features/last-member-leave-guard/
```
The two modified `lib/` files are the prior Engineer's uncommitted diff (built from the prior, incorrect plan). This diff is confirmed **dead code** (§3b) and must be reverted, not built upon — see §9/§10.

---

## 1. Feature Slug
`feature/last-member-leave-guard`

---

## 2. Problem Summary

**What:** When a band member is the sole active member of their own band, no UI anywhere tells them they cannot leave and must delete the band instead. Tony's real repro path — tap own member card → info drawer opens → tap "Edit" → land in the actual role/remove-member editor — shows no such text.

**Why:** The band would be stranded if the sole member could self-remove. The required fix is UI messaging: replace the (would-be) "Remove from band" affordance with fixed explanatory text when the viewer is the sole active member, in whichever screen the user actually reaches by that path.

**What went wrong the first time:** The prior plan diagnosed and the prior Engineer implemented the guard in `RoleManagementSheet` / `MembersTabContent`. Those files are **not part of the live navigation graph** — see §3a/§3b. The fix was real, correctly written, and analyzer-clean, but wired into a screen the app never shows. QA's own report (`QA_REPORT.md`) explicitly flagged that no simulator/device was available and all validation was code-path analysis only — that gap is exactly what let a "wrong screen" defect through undetected.

---

## 3. Root Cause

**Confidence: HIGH** — confirmed by direct code reading and by a repo-wide grep for every reference to both widget names (see evidence below; every result is accounted for).

The guard was added to `RoleManagementSheet` (`lib/features/members/widgets/role_management_sheet.dart`) via `MembersTabContent` (`lib/features/members/members_tab_content.dart`). Neither of these is reachable from the running app:

```
$ grep -rn "MembersTabContent\|ContactsTabContent" lib/ --include="*.dart" | grep -v "features/members/members_tab_content.dart\|features/contacts/contacts_tab_content.dart"

lib/features/shell/app_shell.dart:166:                  const ContactsTabContent()
lib/features/contacts/widgets/band_members_view.dart:16:// Extracted member list view used within ContactsTabContent.
lib/shared/widgets/native_app_banner_integration.dart:45:                MembersTabContent(),
```

- `lib/features/shell/app_shell.dart:166` — the **real, live** `AppShell` wires the Contacts tab (permission-gated on `canViewMembers`) to `ContactsTabContent`, not `MembersTabContent`.
- `lib/shared/widgets/native_app_banner_integration.dart:45` — the *only* other reference to `MembersTabContent` in the entire `lib/` tree, and it sits inside a `/* ... */` block-comment labeled "INTEGRATION EXAMPLE 1" — a documentation file showing a *hypothetical old* `AppShell` structure. It is not compiled into any widget tree. `MembersTabContent` is never instantiated anywhere the app actually runs.
- `RoleManagementSheet` has exactly one call site in the entire repo — `members_tab_content.dart:142` — which is itself unreachable per above. There are zero other references to `RoleManagementSheet` anywhere in `lib/`.

Therefore `members_tab_content.dart` and `role_management_sheet.dart` are **orphaned/dead files** in the current codebase — not merely "the wrong screen for this feature," but unreachable in general, pre-existing this branch. This is a broader pre-existing condition the prior plan did not detect because it never traced navigation from `AppShell` outward; it started from "how does a user reach a member's card" and picked the first `MemberCard`/`RoleManagementSheet` pairing it found by name-matching against the Feature Input's mention of "Contacts," without confirming that pairing is actually mounted.

### 3a. Why the prior plan's claims were wrong (for the record)

The prior plan asserted, at HIGH confidence: *"There is no separate 'Contacts' screen — this is the 'Members' tab (`MembersTabContent`)."* This was false. A separate, live `ContactsTabContent` (`lib/features/contacts/contacts_tab_content.dart`) exists, is wired into `AppShell` as the actual "Contacts" tab, and hosts a **Band** segment (`BandMembersView`) alongside Venues and Contacts segments via a segmented toggle. The prior plan's own evidence-gathering never ran the grep above — it inspected `member_card.dart`, `members_tab_content.dart`, `role_management_sheet.dart`, `members_repository.dart`, `members_controller.dart`, `member_vm.dart` in isolation, all of which are internally consistent and analyzer-clean, but never asked "is this tree actually mounted by `AppShell`?" That question is what this re-diagnosis answers.

The prior plan also asserted the leave/remove action is reached via "a kebab (⋮) icon on `MemberCard`." That is true of the *dead* `member_card.dart`/`MembersTabContent` pairing, but Tony's actual card (`BandMemberCard`, `lib/features/contacts/widgets/band_member_card.dart`) has no kebab icon at all — the entire card is one large tap target (`AnimatedCardPressable(onTap: ...)`) that opens an info drawer, matching Tony's repro exactly (see §3c below).

### 3b. `lib/features/contacts/` vs `lib/features/members/` — reconciled

These are **not** the same feature under two names, and they are **not** cleanly separate either — they are a live/legacy pair mid-migration:

- `lib/features/members/` contains the **data layer** everything shares (`member_vm.dart`, `members_controller.dart`, `members_repository.dart`, `members_provider` / `membersProvider`) plus two **dead UI files** (`members_tab_content.dart`, `widgets/role_management_sheet.dart`, `widgets/member_card.dart` — this last one is also unreferenced outside the dead pair, confirmed by the grep above showing no other consumer).
- `lib/features/contacts/` contains the **live UI layer** for the "Contacts" tab: `ContactsTabContent` (mounted by `AppShell`), which hosts three segments (Band / Venues / Contacts) via a `SegmentedToggle`. The "Band" segment renders `BandMembersView` → `BandMemberCard` → `BandMemberDetailDrawer` → `BandMemberEditDrawer`. This live UI layer consumes the **same** `membersProvider` / `MemberVM` data layer from `lib/features/members/` — it does not duplicate the data model, only the presentation widgets.
- `widgets/band_member_edit_drawer.dart` carries this exact header comment, confirming the duplication was intentional and known at the time it was written: *"Bottom-drawer port of RoleManagementSheet's role-management functionality (Amendment 2, Decision 1 revised). Full, faithful port of `_RoleManagementSheetState`'s state and behavior ... role_management_sheet.dart itself is not modified or called by this file."* This is a straight copy-paste port that was never kept in sync afterward — it has its own independent `_isLastAdmin`, `_isSelfAndLastAdmin`, `_removeMember()`, and "Remove from band" button block (`band_member_edit_drawer.dart:101-111`, `183-246`, `456-483`), byte-similar to `RoleManagementSheet`'s but a separate copy that must be edited separately.

**Conclusion:** Tony is using `ContactsTabContent` → `BandMembersView` → `BandMemberCard` → `BandMemberDetailDrawer` → `BandMemberEditDrawer`. This is the only live path. `MembersTabContent` → `MemberCard` → `RoleManagementSheet` is dead code, pre-existing this branch, not introduced by it.

### 3c. Exact live widget trace (matches Tony's repro steps 1-5 precisely)

1. `AppShell` (`lib/features/shell/app_shell.dart:166`) mounts `ContactsTabContent` for the Contacts tab.
2. `ContactsTabContent._buildActiveView()` (`contacts_tab_content.dart:145-152`), segment 0 ("Band"), renders `BandMembersView`.
3. `BandMembersView.build()` (`band_members_view.dart:106-114`) renders one `BandMemberCard` per member; `onTap` calls `BandMemberDetailDrawer.show(context, member: member, isAdmin: membersState.isCurrentUserAdmin, onManageRole: () => onManageRole(member))`. **This is Tony's step 2** ("Tap your own band member card").
4. `BandMemberDetailDrawer` (`band_member_detail_drawer.dart`) is the **"view band member info" drawer** in Tony's step 3 — a read-only bottom sheet with Done/Edit footer buttons. The "Edit" button only renders `if (isAdmin)` (`band_member_detail_drawer.dart:260-274`) — true here, since (per the pre-existing invariant that every band has ≥1 active admin) a sole active member is always that band's sole admin. **This is Tony's step 3-4.**
5. Tapping "Edit" calls `_handleEdit()` (`band_member_detail_drawer.dart:49-52`), which pops the drawer and invokes `onManageRole()` → back up the callback chain to `ContactsTabContent._openRoleManagement(member)` (`contacts_tab_content.dart:110-120`), which calls `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)`.
6. `BandMemberEditDrawer` (`band_member_edit_drawer.dart`) is the actual role/remove-member editor — this is where Tony expects to see the blocking text and where the "Remove from band" button (or its absence) is rendered (lines 456-483, guarded only by `if (!_isLastAdmin)`, no sole-active-member check exists here at all). **This is Tony's step 5** ("no blocking text where a leave/remove-from-band action would be expected").

Every step traces cleanly with no ambiguity. `BandMemberEditDrawer` has never had a sole-active-member guard — not before this branch, not in the current diff (the diff never touched this file).

---

## 4. Reference Docs Consulted

`docs/reference/notifications/` is not applicable (no notification trigger involved). Consulted:
- `docs/agents/ARCHITECT.md`, `GUARDRAILS.md`, `OPERATING_MODEL.md`
- Prior `docs/features/last-member-leave-guard/ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md` — read in full per task instructions, location claims treated as unverified and independently re-derived (see §3a for where they diverged from re-derived evidence).

---

## 5. Existing System Analysis

**Data layer (shared, unaffected by this re-diagnosis, unchanged from prior plan's analysis — re-confirmed, not re-litigated):**
- `MemberVM.isActive` (`lib/features/members/member_vm.dart:223`): `status == 'active'`.
- `MemberVM.isAdmin` (`member_vm.dart:226`): `bandRole == 'admin' || bandRole == 'owner'`.
- `remove_band_member` RPC unconditionally rejects self-targeting regardless of band size (unchanged; not touched by this plan).
- Every band is guaranteed ≥1 active admin (enforced server-side); a genuine sole-active-member band therefore always has that member as its sole admin.
- No test files reference `role_management_sheet`, `members_tab_content`, or `band_member_edit_drawer` (confirmed via `grep -rl` over `test/` — no matches for any of the three), so reverting the dead-code diff carries zero test-breakage risk.

**Live UI data flow (corrected, replaces prior plan's §5 in full):**

1. `ContactsTabContent` (`contacts_tab_content.dart`) is mounted by `AppShell` as the "Contacts" tab (permission-gated on `canViewMembers`, `app_shell.dart` ~line 163-168).
2. Its "Band" segment renders `BandMembersView`, which renders `BandMemberCard` per member — tapping the card (no kebab icon; the whole card is the tap target) opens `BandMemberDetailDrawer`.
3. `BandMemberDetailDrawer`'s "Edit" button (visible only for admins — always true for a sole member) calls back up to `ContactsTabContent._openRoleManagement(member)`.
4. `_openRoleManagement` (`contacts_tab_content.dart:110-120`) computes `adminCount` from `membersState.members.where((m) => m.isAdmin && m.isActive).length` — **note: does not currently compute an active-member count at all** — and opens `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount)`.
5. `BandMemberEditDrawer` (`band_member_edit_drawer.dart`) renders the "Remove from band" button at lines 456-483, gated only by `if (!_isLastAdmin)` (`_isLastAdmin` defined at line 109-111, identical logic to the dead `RoleManagementSheet` copy). There is no `activeMemberCount` field on this widget's constructor (lines 26-34) and no sole-active-member predicate anywhere in this file. For a genuine sole-member band, `_isLastAdmin` is true (member is admin, `adminCount <= 1`), so the button is suppressed and **nothing renders in its place** — exactly matching Tony's observed "no blocking text."

**"One active member" counting decision:** unchanged from the prior plan — count only `status == 'active'` rows, for the same reasoning already established (invited members have no functional access; `'inactive'`/`'removed'` statuses are never written in practice). This determination was about data semantics, not screen location, and remains correct.

---

## 6. Proposed Solution

Two parts:

**Part A — Revert the dead-code diff.** The uncommitted changes to `lib/features/members/members_tab_content.dart` and `lib/features/members/widgets/role_management_sheet.dart` must be reverted to their pre-diff state. These files are unreachable from any live screen (§3), so the added guard logic there is inert dead code that would silently diverge from the real fix over time and cannot satisfy the Feature Input. Per Guardrails §7 ("never leave... opportunistic" additions) and the task's explicit instruction not to leave orphaned dead code, this diff is removed as part of this plan rather than left in place alongside a new, separate fix.

Note: this plan does **not** propose deleting `members_tab_content.dart` / `role_management_sheet.dart` / `member_card.dart` themselves, or any other broader dead-code cleanup of the legacy `lib/features/members/` UI layer. That these three widget files are wholly orphaned is a pre-existing condition of the codebase, not introduced by this branch, and removing them is a separate, larger decision (touches file deletion, needs its own review of whether they're intentionally kept as a rollback path for the Contacts migration) that is out of scope for this bug fix — see §18.

**Part B — Implement the guard on the live path.** Port the same guard logic (predicate name, condition, and exact required text) from the reverted diff into the two files that are actually live:
- `ContactsTabContent._openRoleManagement` gains an `activeMemberCount` computation, passed into `BandMemberEditDrawer`.
- `BandMemberEditDrawer` gains the `activeMemberCount` field/constructor param, the `_isSoleActiveMember` getter, and the same `if (_isSoleActiveMember) [text] else if (!_isLastAdmin) [button]` branch structure, inserted at its own "Remove from band" block (lines 456-483).

Exact text to render (verbatim, per Feature Input, unchanged from prior plan):
> "Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right (arrow right icon) → Edit band (arrow right icon) → Delete)"

This does not touch: `band_member_card.dart`, `band_member_detail_drawer.dart` (info drawer stays read-only, unchanged), `remove_band_member` RPC, `delete_band` RPC, or the admin-removes-another-member flow in either the live or dead file.

---

## 7. Database Impact

**Not applicable.** No migration, no RLS change, no RPC change. Same server-side guard assessment as the prior plan (§12 there): `remove_band_member` already unconditionally rejects self-targeting at the database layer regardless of band size; this remains true and unchanged. No new `AI_DECISIONS.md` entry required (no SECURITY DEFINER function, no RLS change, no auth flow change).

---

## 8. Flutter Architecture Changes

- `ContactsTabContent._openRoleManagement`: compute total active member count from already-loaded `membersState.members` (no new fetch, no new provider) and pass it to `BandMemberEditDrawer` as a new required constructor parameter, mirroring the (reverted) approach from `MembersTabContent`.
- `BandMemberEditDrawer`: accept the new parameter on both the widget constructor and its `static Future<void> show(...)` factory; add one new getter; add one new conditional branch in `build()` replacing the existing bare `if (!_isLastAdmin)` block with an `if / else if` that inserts the sole-member text case first — identical structure to what was (incorrectly) added to `RoleManagementSheet`.
- `members_tab_content.dart` / `role_management_sheet.dart`: reverted to pre-diff state — net zero architecture change in the dead-code layer.
- No new providers, controllers, repositories, or state management patterns. No new widget files.

---

## 9. Files to Create

None.

---

## 10. Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/members/members_tab_content.dart` | **Revert.** Remove the uncommitted `activeMemberCount` computation and the extra constructor argument added to the `RoleManagementSheet(...)` call — restore to the state at `origin/main`. |
| `lib/features/members/widgets/role_management_sheet.dart` | **Revert.** Remove the uncommitted `activeMemberCount` field, `_isSoleActiveMember` getter, and the `if (_isSoleActiveMember) [...] else if (!_isLastAdmin) [...]` branch — restore the original single `if (!_isLastAdmin) [...]` block and original constructor. |
| `lib/features/contacts/contacts_tab_content.dart` | In `_openRoleManagement` (~line 110-120): compute `final activeMemberCount = membersState.members.where((m) => m.isActive).length;` alongside the existing `adminCount` computation, and pass it into `BandMemberEditDrawer.show(context, member: member, adminCount: adminCount, activeMemberCount: activeMemberCount)`. |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart` | Add `final int activeMemberCount;` to the widget constructor (required param) and to the static `show(...)` factory's parameters (required param, threaded through to the constructor call). Add getter `bool get _isSoleActiveMember { final currentUserId = supabase.auth.currentUser?.id; return widget.member.userId == currentUserId && widget.activeMemberCount <= 1; }` alongside the existing `_isSelfAndLastAdmin`/`_isLastAdmin` getters (~line 101-111). In `build()`, change the block at lines 456-483 from `if (!_isLastAdmin) [button]` to: `if (_isSoleActiveMember) [Text with the exact required copy, styled consistently with the existing `_isSelfAndLastAdmin` warning container at lines 424-453] else if (!_isLastAdmin) [existing button, unchanged]`. |

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/contacts/widgets/band_member_card.dart` | Read-only card, no button lives here; unrelated to the guard. |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | The read-only info drawer — must remain a pure pass-through to `onManageRole()`; the guard belongs one screen deeper, in the actual editor. |
| `lib/features/members/widgets/member_card.dart` | Dead code (§3), not touched by revert or by the new fix; already off-limits per prior plan and remains so. |
| `supabase/migrations/*` (incl. `remove_band_member`, `delete_band` definitions) | UI-only guard; RPC already provides unconditional self-removal defense-in-depth. No migration warranted. |
| `lib/features/bands/band_form_screen.dart`, `lib/features/bands/edit_band_screen.dart` | Delete Band flow is the required escape hatch and must remain untouched and fully functional as-is. |
| `lib/features/members/members_repository.dart`, `lib/features/members/members_controller.dart` | Existing fetch/state already exposes everything needed (`MembersState.members`, `MemberVM.isActive`); no new queries or state needed. |
| `lib/main.dart` | Unrelated to this feature; initialization order must not change. |
| Any admin-removes-*another*-member code path, in either `band_member_edit_drawer.dart` or the (reverted) `role_management_sheet.dart` | Explicitly out of scope — must remain byte-for-byte unchanged from `origin/main`. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed
**New files:** none

---

## 12. Server-Side Guard Assessment

Unchanged from prior plan: **not warranted, UI-only guard is sufficient.** `remove_band_member` already unconditionally rejects self-targeting at the database layer, independent of which client screen calls it. This re-diagnosis does not change that assessment — it only changes which client screen needs the messaging.

---

## 13. System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | affected — additive UI branch in `BandMemberEditDrawer` (live); reversion of dead-code branch in `RoleManagementSheet`/`MembersTabContent` (no live behavior change, since neither is reachable today) |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — shared Flutter widget code, no platform-specific branches; identical behavior on all four |

---

## 14. Regression Risk

**LOW**

- Only one system (Members/RBAC) is affected, and only additively, in the live file.
- The revert of `members_tab_content.dart`/`role_management_sheet.dart` cannot cause a regression: those files are unreachable from any mounted screen, confirmed by repo-wide grep (§3), so their behavior — reverted or not — is not observable by any user.
- No database, RLS, RPC, auth, session, routing, or init-order changes.
- No new dependencies, no new state management pattern.
- The new conditional branch in `BandMemberEditDrawer` is scoped by `widget.member.userId == currentUserId`, so it cannot alter behavior for any card that isn't the viewer's own.
- The pre-existing `_isLastAdmin`-only branch (sole admin in a multi-member band) is left completely untouched in `BandMemberEditDrawer` — same blank/no-button behavior as today for that distinct condition.

---

## 15. Engineer Task Breakdown

1. **Revert** `lib/features/members/members_tab_content.dart` to its `origin/main` state (remove the uncommitted `activeMemberCount` addition and the extra constructor argument).
2. **Revert** `lib/features/members/widgets/role_management_sheet.dart` to its `origin/main` state (remove the uncommitted `activeMemberCount` field, `_isSoleActiveMember` getter, and the added conditional branch — restore the original single `if (!_isLastAdmin)` block).
3. In `lib/features/contacts/contacts_tab_content.dart`, inside `_openRoleManagement`, compute `activeMemberCount` from `membersState.members` (filter on `.isActive`) alongside the existing `adminCount` computation.
4. Pass `activeMemberCount` into the `BandMemberEditDrawer.show(...)` call.
5. In `lib/features/contacts/widgets/band_member_edit_drawer.dart`, add the new required `activeMemberCount` field to the widget class, its constructor, and the static `show(...)` factory's parameter list (threaded through to the constructor call inside `show`).
6. Add the `_isSoleActiveMember` getter to `_BandMemberEditDrawerState`, following the existing style of `_isSelfAndLastAdmin`/`_isLastAdmin` in the same file.
7. Replace the `if (!_isLastAdmin) [...]` block (lines 456-483) with:
   - `if (_isSoleActiveMember) [...]` rendering the exact required text (verbatim string from §6), styled consistently with the file's existing `_isSelfAndLastAdmin` warning container (lines 424-453) — same `context.colors.warning` / `AppIcons.warning` tokens, no new color constants.
   - `else if (!_isLastAdmin) [...]` — the existing button, unmodified.
   - (implicit else: unchanged blank state for sole-admin-of-multi-member-band, unmodified.)
8. Do not modify `_removeMember()`, `_saveRole()`, `_isLastAdmin`, `_isSelfAndLastAdmin`, `BandMemberDetailDrawer`, `BandMemberCard`, or any RPC call.

---

## 16. Verification Plan

**Database: not applicable — no migration, no SQL changes.** Verification is manual/UI-driven:

1. **Sole-member band (1 active member), live path:** From the Contacts tab → Band segment, tap own card → info drawer opens → tap "Edit" → `BandMemberEditDrawer` opens → "Remove from band" button is **not** shown; the exact required text is shown in its place. No console/RPC errors.
2. **2+ member band — admin removes another member:** Unaffected. From the Contacts tab → Band segment, tap another member's card → Edit → button shows, tapping it, confirming, and removing succeeds via the existing `remove_band_member` RPC path (unchanged use case).
3. **2+ member band — admin views own card, is not sole admin:** Button still shows (unchanged, pre-existing).
4. **2+ member band — admin views own card, IS sole admin (but band has other, non-admin members):** Unchanged from today — blank, no button, no text. Confirms the new sole-member text does *not* leak into this different, broader condition.
5. **Escape hatch — Delete Band:** From a sole-member band, follow Band avatar (top right) → Edit Band → Delete. Confirm the band is deleted via the existing `delete_band` RPC and the former member has no lingering access.
6. **Cross-platform:** Verify on Web and at least one native target (iOS or Android) to confirm identical rendering; no platform-specific behavior is expected.
7. **Dead-code confirmation:** After the revert (tasks 1-2), confirm via `git diff lib/features/members/members_tab_content.dart lib/features/members/widgets/role_management_sheet.dart` against `origin/main` that both files show **zero** diff — i.e., the revert is complete and clean, not a partial rollback.

**Mandatory device re-test before this bug is considered resolved (required by this re-diagnosis, not optional):**

> Tony must re-run the exact repro steps from the Bug Input on a real device, end to end:
> 1. Open a band where you are the sole active member.
> 2. Tap your own band member card.
> 3. Confirm the "view band member info" drawer opens.
> 4. Tap the "Edit" text button at the bottom of that drawer.
> 5. **Confirm the exact text renders:** "Since you are the only member in this band, you cannot leave the band, instead you must delete the band (Tap band avatar top right (arrow right icon) → Edit band (arrow right icon) → Delete)"
>
> This is a hard gate on top of the standard Gate 4 (QA APPROVED) — given this exact class of failure (code-path-correct, screen-wrong) previously passed QA without device testing, QA's report for this re-diagnosis must not be marked APPROVED on code-path analysis alone if a device/simulator is unavailable. If QA again cannot get device access, QA must say so explicitly and the Manager must escalate to Tony for a manual confirmation before commit, rather than defaulting to APPROVED.

**QA Regression Areas:**
- Sole-member text rendering on the **live** path (`ContactsTabContent` → `BandMemberEditDrawer`) — primary, new, and the specific defect being fixed.
- Confirm zero diff in `members_tab_content.dart` / `role_management_sheet.dart` vs. `origin/main` (revert completeness).
- Admin-removes-other-member flow in `BandMemberEditDrawer` (must be byte-identical to pre-change behavior).
- Sole-admin-in-multi-member-band blank state in `BandMemberEditDrawer` (must be byte-identical to pre-change behavior).
- Role toggle / contributor sub-permission flows within `BandMemberEditDrawer` (untouched, but same file — confirm no unrelated breakage).
- `BandMemberDetailDrawer`'s Edit button and Done button (untouched — confirm no regression in the info drawer itself).
- Delete Band flow (confirm untouched, still fully functional as escape hatch).

---

## 17. Rollout / Migration Strategy

Standard Flutter release — no backend deploy, no migration, no feature flag needed. Ship with the next normal app build/deploy for all four platforms simultaneously (shared code).

---

## 18. Out of Scope

- Deleting the orphaned `lib/features/members/members_tab_content.dart`, `lib/features/members/widgets/role_management_sheet.dart`, and `lib/features/members/widgets/member_card.dart` files entirely. They are confirmed dead code (§3) but predate this branch; removing them is a separate cleanup decision (may be an intentional rollback path kept during the Contacts migration — not confirmed either way, and not this Architect's call to make unilaterally). Flagging for a future decision, not actioning here.
- Building a genuine self-leave (`leave_band`) RPC for non-sole-member cases — self-removal remains non-functional for all members today via this RPC path; pre-existing, unrelated to this feature.
- Fixing the generic error-swallowing in `_removeMember()`'s catch block in `BandMemberEditDrawer` (masks specific RPC exception messages behind a generic "Failed to remove member" toast) — pre-existing, unrelated to this feature.
- Changing the `_isLastAdmin` suppression for a sole admin in a *multi-member* band (a different condition than "sole member of the band") — left exactly as-is.
- Any change to `remove_band_member`, `update_member_role`, or `delete_band` RPCs.
- Any change to the Delete Band UI/flow itself.
- Any change to `BandMemberDetailDrawer` or `BandMemberCard` — both remain pure pass-throughs / read-only, unchanged.

---

## Dirty-Tree / Branching Note (carried forward from prior plan, still accurate)

`docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` remains modified in the working tree, and `docs/features/gig-sheet-full-address/` remains untracked. Both are unrelated to this feature (confirmed by the prior QA pass, re-confirmed here — no new changes to either since). Neither is touched by this plan.
