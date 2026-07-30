# ARCHITECT_PLAN.md

## 1. Feature Slug
`feature/admin-crown-right-align`

---

## 2. Problem Summary
On the "Band Members" listing page, member cards for admins/owners show a crown icon
positioned **before** (left of) the member's name. Tony wants the crown moved to the
**right** side of the card instead. Scope is strictly repositioning — no new icons for
`member`/`contributor` roles, no new interactivity, no change to admin-detection logic.

---

## 3. Root Cause
**Confidence: HIGH** (confirmed by direct code inspection and cross-reference of live
navigation wiring).

The Feature Input assumed the crown lives in `lib/features/members/widgets/member_card.dart`
(`MemberCard`, rendered by `MembersTabContent`). **This assumption does not match the live
codebase.** `MembersTabContent` is not mounted anywhere in live navigation:

- `lib/features/shell/app_shell.dart:166` mounts `ContactsTabContent`, not `MembersTabContent`.
- `ContactsTabContent` (`lib/features/contacts/contacts_tab_content.dart:145`) renders
  `BandMembersView` for the "Band" segment.
- The only other reference to `MembersTabContent` is inside
  `lib/shared/widgets/native_app_banner_integration.dart`, which is a commented-out
  integration-guide example file (wrapped in `/* ... */`), not live app code.

The **actual live "Band Members" listing page** (page title literally reads "Band Members" —
`lib/features/contacts/widgets/band_members_view.dart:73`) is:

- `lib/features/contacts/widgets/band_members_view.dart` — the list screen (`BandMembersView`)
- `lib/features/contacts/widgets/band_member_card.dart` — the card widget that renders the
  crown (`BandMemberCard`)

This is a documented discrepancy between the Feature Input and codebase evidence, per
Architect Phase 3. The plan below targets the live widget, `BandMemberCard`.

---

## 4. Reference Docs Consulted
`docs/reference/notifications/` was checked (per template Phase 4) but is not applicable —
this feature has no notification surface. No `docs/reference/members/` or `docs/reference/ui/`
content applies to card layout specifics; `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md`
was checked and is unrelated (marketing landing page, not the members list).

---

## 5. Existing System Analysis
**File:** `lib/features/contacts/widgets/band_member_card.dart` (84 lines)

`BandMemberCard` is a `StatelessWidget` wrapped in `AnimatedCardPressable` (tap opens
`BandMemberDetailDrawer` via the callback wired in `band_members_view.dart:106-114`). Its
build method renders a `Container` → `Column` whose first child is a header `Row`:

```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (member.isAdmin)                          // <-- crown, currently LEADING
      const Padding(
        padding: EdgeInsets.only(top: 6, right: 10),
        child: Icon(AppIcons.crown, size: 18, color: AppColors.primary),
      ),
    Expanded(
      child: Text(member.name, ... maxLines: 2, overflow: TextOverflow.ellipsis),
    ),
  ],
),
```

- **Visibility gate:** `member.isAdmin` — a getter on `MemberVM`
  (`lib/features/members/member_vm.dart:226`): `bandRole == 'admin' || bandRole == 'owner'`.
  Sourced from `band_members.role` in Supabase. This condition is not changing.
- **Interactivity:** The crown `Icon` is a bare widget — no `GestureDetector`, `InkWell`,
  `Tooltip`, or `IconButton` wraps it. It is already purely decorative; the enclosing card
  (not the icon) carries the tap-to-open-drawer behavior. This is unaffected by reordering.
- **No contributor/member icon exists in this card** — unlike the legacy `member_card.dart`,
  `BandMemberCard` has no icon logic for non-admin roles, so there is no risk of accidentally
  moving or affecting a second badge type.
- **Not a shared widget across screens.** The crown is duplicated (not componentized) in two
  other places that independently reimplement `if (member.isAdmin) → Icon(AppIcons.crown)`:
  1. `lib/features/contacts/widgets/band_member_detail_drawer.dart:172-197` — the member
     detail drawer opened when a card is tapped. Same visual pattern, separate code, own file.
  2. `lib/features/members/widgets/member_card.dart:365-384` (`_buildRoleIcon()`) — the legacy,
     unreferenced `MemberCard` widget (dead code per navigation trace above).

  Because these are independent copies rather than a shared component, editing
  `band_member_card.dart` **does not** change the drawer's or the legacy widget's crown
  position. Per Tony's explicit scope ("band members listing page" only), both are left
  untouched — see Files Off-Limits and Out of Scope.

---

## 6. Proposed Solution
In `BandMemberCard`'s header `Row`, move the `if (member.isAdmin)` crown block from the
first child (leading, before the name) to the last child (trailing, after the `Expanded`
name `Text`). Flip the icon's `Padding` from `right: 10` (gap when leading) to `left: 10`
(gap when trailing) so visual spacing from the name is preserved. No other property of the
icon (condition, asset, size, color) changes.

This is a pure JSX/widget-tree reorder within one existing `Row` — no new widgets, no new
state, no new imports.

---

## 7. Database Impact
**Not applicable.** No schema, RLS, RPC, or trigger involvement — this is a client-side
Flutter layout change only.

---

## 8. Flutter Architecture Changes
- **Widget:** `BandMemberCard` (`StatelessWidget`) — one `Row`'s child order and one
  `Padding`'s `EdgeInsets` change. No new widgets, no state, no controller/provider changes.
- **Data flow:** Unchanged. `member.isAdmin` continues to gate visibility exactly as before;
  no change to `MemberVM` or any repository/controller.
- **Platforms:** Single shared Flutter implementation — `band_member_card.dart` has no
  platform-conditional code (`kIsWeb`, `Platform.isIOS`, etc.), so the change applies
  identically to Web / iOS / Android / macOS. Confirmed: no platform-specific layout exists
  for this card.

---

## 9. Files to Create
None.

---

## 10. Files to Modify
| File | What changes |
|------|-------------|
| `lib/features/contacts/widgets/band_member_card.dart` | Move the `if (member.isAdmin)` crown `Padding`/`Icon` block from before the `Expanded` name `Text` to after it, within the header `Row` (lines ~40-66). Change its `Padding` from `EdgeInsets.only(top: 6, right: 10)` to `EdgeInsets.only(top: 6, left: 10)`. No other change. |

---

## 11. Files Off-Limits
| File | Reason |
|------|--------|
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | Separate screen; independently duplicates the crown pattern. Out of scope per Tony's explicit "members listing page" scope — repositioning here would expand scope without being asked. |
| `lib/features/members/widgets/member_card.dart` | Legacy widget, unreferenced by live navigation (dead code). Not the target of this feature; editing it has no user-visible effect and would be wasted/confusing diff. |
| `lib/features/members/members_tab_content.dart` | Not mounted in live navigation. Out of scope. |
| `lib/features/members/member_vm.dart` | `isAdmin` admin-detection logic must not change per Feature Input. |
| `lib/features/contacts/widgets/band_members_view.dart` | Parent list screen; no layout/spacing change required — `BandMemberCard`'s internal reorder does not require parent changes. |
| `lib/main.dart` | Unrelated; init order must never change without separate Architect approval per `GUARDRAILS.md` §1. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed (none needed)
**New files:** none

---

## 12. System Impact Map
| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | affected (visual only — crown position on `BandMemberCard`; no permission/role logic changes) |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected (single shared widget, no platform branches, applies uniformly) |

---

## 13. Regression Risk
**LOW**

- Exactly one file touched, one `Row`'s child order + one `Padding`'s side changed.
- No condition, asset, size, or color changes to the icon itself.
- No auth, session, routing, or init-order involvement.
- No database mutation.
- No other role-icon type exists in this card to accidentally disturb.
- No existing widget/golden tests reference `BandMemberCard` or `band_member_card.dart`
  (confirmed via repo search) — no test breakage expected, but no existing test coverage
  either (noted under QA Regression Areas).

---

## 14. Engineer Task Breakdown
1. Open `lib/features/contacts/widgets/band_member_card.dart`.
2. In the header `Row` (currently lines ~40-66), remove the `if (member.isAdmin) Padding(...)`
   crown block from its current position (first child, before `Expanded`).
3. Re-insert the same `if (member.isAdmin) Padding(...)` block as the **last** child of the
   `Row`, after the `Expanded(child: Text(member.name, ...))`.
4. Change the re-inserted block's `padding` from `EdgeInsets.only(top: 6, right: 10)` to
   `EdgeInsets.only(top: 6, left: 10)`.
5. Leave the `Icon(AppIcons.crown, size: 18, color: AppColors.primary)` and the `member.isAdmin`
   condition byte-identical — only position and padding side change.
6. Do not touch any other file, widget, or condition.

---

## 15. Verification Plan

**Tier 1 — Pre-build (static verification, before running the app):**
- PRE-DEPLOY TEST 1: Diff `band_member_card.dart` and confirm the only changes are (a) the
  crown block's position within the `Row`'s `children` list and (b) `right: 10` → `left: 10`
  in its `Padding`. The `if (member.isAdmin)` condition, `AppIcons.crown`, `size: 18`, and
  `color: AppColors.primary` must be byte-identical to the pre-change version.
- PRE-DEPLOY TEST 2: Grep the modified block for `GestureDetector`, `InkWell`, `Tooltip`, and
  `IconButton` — confirm none wrap the crown `Icon` (must remain purely decorative).
- PRE-DEPLOY TEST 3: Run `git diff --stat` and confirm only
  `lib/features/contacts/widgets/band_member_card.dart` appears — no other file touched.

**Tier 2 — Post-build (after `flutter run` on at least one platform):**
- POST-DEPLOY TEST 1: Navigate to Contacts → Band Members with at least one admin/owner
  member and one plain member present. Confirm the crown renders at the right/trailing edge
  of the admin's card, and the plain member's card shows no crown and no layout shift.
- POST-DEPLOY TEST 2: With a long member name (long enough to wrap to 2 lines per
  `maxLines: 2, overflow: TextOverflow.ellipsis`), confirm the name still truncates correctly
  and the crown does not get pushed off-card or overlap the name now that it trails.
- POST-DEPLOY TEST 3: Tap the admin's card and confirm `BandMemberDetailDrawer` still opens
  normally (tap target unaffected by the icon reorder), and that the drawer's own crown
  (separate, unmodified file) still renders in its original left/leading position — confirming
  the two surfaces are correctly decoupled as expected.

---

## 16. QA Regression Areas
- Crown renders on the right side of `BandMemberCard` for admin/owner members (primary).
- Non-admin (`member`, `contributor`) cards remain unaffected — no crown, no layout shift.
- Card tap-to-open-`BandMemberDetailDrawer` behavior unaffected.
- `BandMemberDetailDrawer`'s own crown position is unchanged (confirms no unintended shared-code effect).
- Long member name wrapping behaves correctly with the crown in its new trailing position.
- Cross-platform smoke check: verify on at least one native platform (iOS or Android) and Web,
  since this is a shared Flutter widget with no existing platform-specific layout.

---

## 17. Rollout / Migration Strategy
Not applicable — standard feature-branch → PR → merge flow per `GUARDRAILS.md` §10. No
migration, no feature flag, no staged rollout needed for a pure layout change.

---

## 18. Out of Scope
- Adding icons for `member` or `contributor` roles (explicitly declined by Tony).
- Any change to admin-detection logic (`member.isAdmin` / `bandRole` computation in `MemberVM`).
- Adding tap, tooltip, or any other interactivity to the crown icon.
- Repositioning the crown in `band_member_detail_drawer.dart` (separate screen, separate code).
- Any change to the legacy/unreferenced `lib/features/members/widgets/member_card.dart` or
  `MembersTabContent`.
- Any change to `band_members_view.dart` list layout, spacing, or sectioning.
