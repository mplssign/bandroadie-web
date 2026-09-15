# ARCHITECT PLAN

## Feature Slug

`member-invitations-after-phone-change`

## Feature Title

Member invitations fail after a band member changes phone number

## Problem Summary

A band owner/admin could not add or re-add a member whose phone number changed and who reinstalled the app on a new phone. As a workaround they created a brand-new band and still could not add any members to it. No exact client error was reported by the reviewer.

## Root Cause (Confidence: HIGH — confirmed directly in code)

The "phone number changed" detail in the review is not mechanically relevant — invitations are matched entirely by **email** (`band_invitations.email`, `accept-invite` edge function matches on `authUser.email`). There is no phone-based identity or uniqueness logic anywhere in the invite path. The phone number is only a plain profile field (`users.phone`).

The real, deterministic bug is a **stale/broken navigation entry point in the Members tab**, left over from an earlier refactor that extracted the invite UI out of `BandFormScreen`'s edit mode into a dedicated `InviteMembersScreen`:

- [lib/features/members/members_tab_content.dart](lib/features/members/members_tab_content.dart#L96) — `_openInviteScreen()` still pushes `BandFormScreen(mode: BandFormMode.edit, initialBand: ...)`.
- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L1649) — the entire "Invite Members" section is gated `if (!_isEditMode) ...`, i.e. **edit mode renders zero invite UI**. The section only exists in create mode.
- A stale comment in [members_tab_content.dart](lib/features/members/members_tab_content.dart#L305) still reads `// NOTE: Pending invites are shown in Edit Band screen, not here` — this is no longer true; confirms the extraction was never back-ported to this file.
- By contrast, [lib/features/contacts/contacts_tab_content.dart](lib/features/contacts/contacts_tab_content.dart#L102) already correctly pushes `InviteMembersScreen(band: bandState.activeBand!)` — the working, current implementation.

Two concrete, reproducible failure modes result, matching both repro steps exactly, with no client error thrown (this is a missing/misrouted feature, not a caught exception — explains "no exact error message"):

1. **Band with existing members** (the reporter's original band): `MembersTabContent`'s non-empty-state render path (`_buildContent`, lines ~234–319) has **no invite/"Add" affordance at all** — only the empty state wires `onInviteTap`. An admin looking at the Members tab of a populated band has no way to invite anyone from that screen.
2. **Brand-new band** (the reported workaround): a fresh band starts with zero members, so `MembersTabContent` shows `MembersEmptyState`, whose CTA calls the broken `_openInviteScreen()` → lands on `BandFormScreen` in edit mode → no invite section renders (`if (!_isEditMode)`) → dead end.

The only currently-working invite entry point in the app is the Contacts tab (`ContactsTabContent` → `BandMembersView` → `InviteMembersScreen`). If the admin used the Members tab (the more natural place to look), they would hit a genuine dead end in both scenarios described in the review.

## Existing System Analysis

- `InviteMembersScreen` ([lib/features/contacts/widgets/invite_members_screen.dart](lib/features/contacts/widgets/invite_members_screen.dart)) is fully functional: validates email, checks active-membership and duplicate-invite state, inserts into `band_invitations`, retries `error`-status rows instead of duplicating, and calls the `send-band-invite` edge function. No defects found in this flow.
- `accept_band_invite` RPC and its RLS/grants (migrations `20260328000000`, `20260717085528`, `20260822120002`) are correct and unaffected by this bug — confirmed current, no drift.
- `create_band` RPC ([supabase/migrations/087_fix_create_band_no_profile.sql](supabase/migrations/087_fix_create_band_no_profile.sql)) correctly inserts the creator as an `active`/`admin` `band_members` row; new-band admin authorization is intact.
- The `band_members_band_id_user_id_key` UNIQUE(band_id, user_id) constraint (relied on by `accept_band_invite`'s `ON CONFLICT`) is confirmed still present per [docs/features/db-index-optimization/ENGINEER_REPORT.md](docs/features/db-index-optimization/ENGINEER_REPORT.md) — the sibling duplicate constraint `band_members_band_user_unique` was the one dropped, not this one.
- Recent RLS-hardening migrations (`20260822*` revoke batches, `20260823120000_wrap_rls_auth_functions.sql`, `20260905*` fixes) were reviewed in full for `band_invitations`/`band_members`/`bands` policies — all are semantically unchanged (`(select auth.uid())` wrapping is a performance-only rewrite) and none are implicated.
- Secondary observation, **not part of this fix**: `MembersRepository.fetchMembersAndInvites` ([lib/features/members/members_repository.dart](lib/features/members/members_repository.dart#L149)) queries pending invites with `.eq('status', 'pending')` only, so an invite that has progressed to `'sent'` no longer appears anywhere in the Members tab. This does not block sending invites and does not explain the reported dead end, but it is a related rough edge worth Tony's awareness (see Out of Scope).

## Proposed Solution

Point `MembersTabContent`'s invite entry point at the same working `InviteMembersScreen` that `ContactsTabContent` already uses, and add a visible invite affordance to the populated-members view (mirroring the existing header pattern already shipped in `BandMembersView`). Pure Flutter navigation/UI fix — no new abstractions, no new screens, no state-management changes.

## Database Impact

Not applicable. No migration, RLS, RPC, or trigger changes — this is a client-side navigation/UI defect only.

## Flutter Architecture Changes

- `members_tab_content.dart`: swap the pushed page in `_openInviteScreen()` from `BandFormScreen(mode: edit)` to `InviteMembersScreen(band: ...)`; swap the corresponding import.
- `members_tab_content.dart`: add a header "Add" affordance to the populated-members branch of `_buildContent()`, wired to the existing `_openInviteScreen()`, mirroring the header row already shipped in `band_members_view.dart` (title + `TextButton.icon(AppIcons.add, 'Add')`, unconditional visibility — matches existing convention, not a new admin-gating decision).
- Remove the stale comment `// NOTE: Pending invites are shown in Edit Band screen, not here`.
- No changes to `BandFormScreen`, `InviteMembersScreen`, Riverpod providers/controllers, or any repository.

## Files to Create

- `test/features/members/members_tab_content_test.dart` — no widget-test coverage exists today for `MembersTabContent` (`test/features/members/` does not exist; confirmed via search of `test/**`). This is the smallest appropriate location: it mirrors the existing convention of one `<widget>_test.dart` file per widget under `test/features/<feature>/` (e.g. [test/features/setlists/widgets/reorderable_song_card_test.dart](test/features/setlists/widgets/reorderable_song_card_test.dart)), and both required cases (empty-state and populated-state invite navigation) belong together in a single file since they exercise the same widget and the same `_openInviteScreen()` destination.

## Files to Modify

- [lib/features/members/members_tab_content.dart](lib/features/members/members_tab_content.dart) — fix `_openInviteScreen()` destination + import; add "Add" button to the populated-members header; remove stale comment.

## Files Off-Limits

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart) — the edit-mode invite section removal was an intentional prior extraction; do not resurrect or duplicate invite UI here.
- [lib/features/contacts/widgets/invite_members_screen.dart](lib/features/contacts/widgets/invite_members_screen.dart) and [lib/features/contacts/contacts_tab_content.dart](lib/features/contacts/contacts_tab_content.dart) — already correct; read-only reference for the fix, no edits needed.
- [lib/features/members/members_repository.dart](lib/features/members/members_repository.dart) — the `status='pending'`-only query is a separate, non-blocking issue; out of scope (see below).
- `supabase/migrations/**`, `supabase/functions/**` — not implicated; no DB/RLS/RPC/edge-function changes.
- Any auth/session/init-order files (`lib/main.dart`, `lib/features/auth/**`) — not implicated.

## Change Budget

- `members_tab_content.dart`: expected net line delta ≈ +15 (one import swap, one navigation destination swap, one small header widget addition, one comment removal).
- `test/features/members/members_tab_content_test.dart`: new file, expected ≈ +70–100 lines (two widget-test cases plus minimal Riverpod/provider setup, following the pattern of existing widget tests under `test/features/setlists/widgets/`).
- Expected new files: 1 (test file only; no new production files).
- Expected new public classes/methods: 0 in production code (only edits existing private `_openInviteScreen`/`_buildContent`); the new test file adds no public API, only test cases.
- Expected new dependencies: 0.

## System Impact Map

- Gigs: unaffected
- Rehearsals: unaffected
- Setlists: unaffected
- Members: affected (fixed) — invite entry point corrected, "Add" affordance added for populated bands
- Auth: unaffected
- Routing: affected in a narrow sense — one in-app `Navigator.push` destination corrected within `MembersTabContent`; no app-level route table (`lib/main.dart`) or init-order changes
- Notifications: unaffected
- Platforms: iOS/Android/macOS/Web all affected identically — pure shared Dart widget-tree logic, no platform-conditional code touched; native/web parity unchanged

## Regression Risk: LOW

Single-file, additive UI/navigation change. Reuses an already-shipped, production-working screen (`InviteMembersScreen`) and mirrors an already-shipped header pattern (`BandMembersView`). No auth, session, init-order, or database code is touched.

## Engineer Task Breakdown

1. In `members_tab_content.dart`, replace `import '../bands/band_form_screen.dart';` with an import of `InviteMembersScreen` (`lib/features/contacts/widgets/invite_members_screen.dart`). Confirm no other symbol from `band_form_screen.dart` is used elsewhere in this file before removing the import.
2. In `_openInviteScreen()`, replace the pushed page with `InviteMembersScreen(band: bandState.activeBand!)`, matching the existing implementation in `contacts_tab_content.dart` exactly.
3. In `_buildContent()`'s populated-members branch, add a header row (title + `TextButton.icon` labeled "Add", `AppIcons.add`, `AppColors.primary` foreground) wired to `_openInviteScreen()`, mirroring the existing header in `band_members_view.dart`.
4. Remove the stale comment `// NOTE: Pending invites are shown in Edit Band screen, not here`.
5. Create `test/features/members/members_tab_content_test.dart` with two widget-test cases: (a) pump `MembersTabContent` with an empty `MembersState` and an active band, tap the empty-state invite CTA, assert `InviteMembersScreen` is pushed and `BandFormScreen` is not; (b) pump `MembersTabContent` with a `MembersState` containing 1+ members, assert the new "Add" control is present, tap it, assert `InviteMembersScreen` is pushed. Override only the providers needed to supply the band/members state (do not stand up live Supabase calls).

## Verification Plan

### Tier 1 (pre-deploy, headless — QA's actual gate)

1. `flutter analyze` on the modified file — zero new errors/warnings.
2. Widget test (in the new `test/features/members/members_tab_content_test.dart`): pump `MembersTabContent` with a `MembersState(members: [])` (empty) and an active band; tap the empty-state invite CTA; assert `InviteMembersScreen` is pushed (`find.byType(InviteMembersScreen)` after `pumpAndSettle`) and `BandFormScreen` is not.
3. Widget test (same file): pump `MembersTabContent` with a `MembersState` containing 1+ members; assert an "Add" control is present (`find.text('Add')` or equivalent finder); tap it; assert `InviteMembersScreen` is pushed.
4. Full `flutter test` run — no regressions in existing Members/Contacts widget or controller tests.

### Tier 2 (owner-run, requires a live app — hand to Tony verbatim)

1. Open BandRoadie, select a band that already has 2+ active members, go to the Members tab. Expected: an "Add" button is visible in the header, and tapping it opens the Invite Members screen (email field + role selector) — not the Edit Band screen.
2. From that screen, invite a test email you control. Expected: success snackbar "Invite sent to `<email>`", no "Only band admins can invite members" error.
3. Create a brand-new band (no members yet). Go to its Members tab — confirm the empty state's CTA also opens the Invite Members screen (not Edit Band).
4. Send a test invite from the new band and confirm the invited email actually receives the invite, and the pending invite is visible in the Contacts tab's Band Members section.
5. Regression: open Edit Band (tap band name/avatar) for an existing band — confirm it still works for renaming/avatar/timezone, and no invite section appears there (unchanged, intentional).

## QA Regression Areas

- Members tab: empty state and populated state rendering.
- Contacts tab → Band Members section (must remain unaffected — parity reference for this fix).
- Edit Band screen (create vs. edit mode invite-section gating must remain unchanged).
- In-app navigation stack / `fadeSlideRoute` behavior for the corrected push destination.

## Rollout Strategy

Standard PR → code review → merge to `main` → normal release channel. No feature flag, no migration, no phased rollout — isolated, low-risk client UI fix.

## Out of Scope

- Group chat feature — explicitly requested by the reviewer; Tony explicitly said not to build it. Not addressed here.
- Any investigation into email deliverability (Resend API key/domain/quota) — not verifiable from this codebase; if invites still don't arrive after this fix, that is a separate infra investigation, not a code defect found here.
- `MembersRepository`'s `status='pending'`-only pending-invite query (invites that reach `'sent'` disappear from the Members tab's list) — a real, separate, non-blocking rough edge noted above for Tony's awareness. Not required to resolve the reported dead end and not included to keep this change minimal.
- Consolidating the two invite code paths (`InviteMembersScreen` vs. the legacy create-mode section still in `BandFormScreen`) into one shared component — no opportunistic refactor.
- Adding admin-only gating to the new "Add" button — mirrors the existing unconditional-visibility convention already shipped in `BandMembersView`; not a new design decision.
