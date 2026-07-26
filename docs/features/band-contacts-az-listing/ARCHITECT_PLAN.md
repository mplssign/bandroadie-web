# Band Members & Contacts A-Z Listing — Architectural Plan

## Feature Slug

`feature/band-contacts-az-listing`

---

## Problem Summary

The Contacts tab has three segments: **Band**, **Venues**, **Contacts**. Only **Venues** currently has the iOS Contacts-style listing (search bar, A-Z section headers, right-side A-Z+# index column, simplified plain cards) shipped via `feature/venue-detail-view` (merged to `main` in PR #81). **Band** and **Contacts** still use their original, unsearchable, ungrouped list implementations with heavier detailed cards.

**Why:** Consistency and discoverability. Bands with many members or contacts have no way to search or jump to a section; the Venues segment already solved this and the pattern should extend to the other two segments — with one intentional divergence: **Band Members does not get the index column** (per explicit product decision — its list stays full-width).

---

## Root Cause

**Confidence:** HIGH (direct observation)

No root cause — this is a greenfield UI feature addition, not a bug fix. Current `BandMembersView` and `ContactsView` are flat `CustomScrollView`/`SliverList` implementations with no search, no grouping, and detailed decorated cards (`MemberCard`, `ContactCard`) carried over from before the Venues pattern existed.

---

## Reference Docs Consulted

- `docs/features/venue-detail-view/ARCHITECT_PLAN.md` (full file, including Amendments 1–4) — read in full per Architect Feature Input instructions.
- `docs/features/venue-detail-view/ARCHITECT_PLAN_AMENDMENT_2.md` — stray untracked duplicate of the Amendment 2 section already embedded in `ARCHITECT_PLAN.md`. Not authoritative; superseded by the merged plan file. Left untouched (see Dirty Tree Check below).

**Important discrepancy found and resolved by direct code observation:** Amendments 1 and 2 of the Venues plan describe a "sticky section header" feature (current section letter pinned at top while scrolling, via `ItemPositionsListener`). **This was never actually implemented in the shipped code.** `venues_view.dart` (current, on `origin/main` via PR #81) declares `ItemPositionsListener` and wires it into `ScrollablePositionedList.builder`, but never reads `.itemPositions` and has no sticky-header overlay widget or state field. The aspirational amendment and the shipped reality diverged. Per Architect Phase 3 ("If the input conflicts with codebase evidence, rely on the codebase and document the discrepancy"): **this plan targets the pattern as it actually ships today — no sticky headers** — for Band and Contacts, so all three segments behave identically (no inconsistency between segments).

---

## Existing System Analysis

### Where things live

All three segments live under `lib/features/contacts/`, wired together by `contacts_tab_content.dart` (`SegmentedToggle` with labels `['Band', 'Venues', 'Contacts']`, `_selectedSegment` 0/1/2, lazy-load on first visit to segment 1/2; segment 0 "Band" is loaded eagerly in `ContactsTabContent.initState()`).

| Segment | View widget | State source | Card widget | Model |
|---|---|---|---|---|
| Band (0) | `widgets/band_members_view.dart` — `StatelessWidget`, fed via constructor props from `ContactsTabContent` | `membersProvider` (`members_controller.dart`) — **shared app-wide**, also consumed by `financials/`, `events/` (assignee pickers), `home/`, `profile/my_profile_screen.dart`, and the legacy (non-routed) `members_tab_content.dart` | `member_card.dart` → `MemberCard` (also used by legacy `members_tab_content.dart`) | `member_vm.dart` → `MemberVM` |
| Venues (1) | `widgets/venues_view.dart` — `ConsumerStatefulWidget`, owns its own search/scroll state | `venuesProvider` (`venues_controller.dart`) — scoped to this view | `venue_card.dart` → `VenueCard` (already simplified) | `models/venue.dart` → `Venue` |
| Contacts (2) | `widgets/contacts_view.dart` — `ConsumerStatefulWidget` | `contactsProvider` (`contacts_controller.dart`) — scoped to this view | `contact_card.dart` → `ContactCard` (still the old detailed rose-border/gradient card) | `models/contact.dart` → `Contact` |

### Venues pattern (the thing being replicated), as it actually ships

`venues_view.dart` (current, matches `origin/main`):

- `TextEditingController _searchController`, `ItemScrollController _itemScrollController` (from `scrollable_positioned_list: ^0.3.8`, already in `pubspec.yaml` — no new dependency needed).
- Fixed (non-scrolling) title row + search bar rendered as plain `Column` children **outside** the scrollable — not as sliver/list items. This is deliberate: `ScrollablePositionedList` is **not Sliver-based**; anything placed inside its `itemBuilder` participates in flat-index arithmetic, and Amendment 1 of the Venues plan hit a real bug when title/search were treated as scrollable list items (`ItemScrollController.scrollTo()` silently landed on the wrong row). Keeping them as fixed `Column` children above the `Expanded(ScrollablePositionedList.builder(...))` avoids that class of bug entirely and is what's actually shipped.
- `_groupVenuesByLetter()`: groups by first char of `venue.name`, regex-matched to `A-Z`, everything else (digits, symbols, empty) bucketed into `#`, map ordered A→Z then `#` last.
- `_getFlatIndexForSection(letter, grouped)`: single shared helper computing the flat item index of a section's header, by walking the ordered map and summing `1 (header) + venues.length` per prior section. Used by the index column's `onTap`.
- `_calculateItemCount()` / `_buildItem()`: single source of truth for the flat index → widget mapping (header vs. venue vs. bottom spacer), used by `itemCount`/`itemBuilder`. Search mode bypasses sections entirely (flat filtered list, no headers, index column hidden).
- `_buildIndexColumn()`: `Positioned(right: 8, top: <below search bar>, bottom: <above bottom nav>)` wrapping a `Column` of **all 27** entries (A–Z + `#`), each `Expanded` for even vertical distribution. Populated letters render at full `AppColors.primary` opacity; empty letters render at `alpha: 0.3` (dimmed, never omitted). Tapping an empty letter resolves to the nearest letter `>=` target (or `#`, or last section) via inline fallback logic in the `onTap` closure.
- List item horizontal padding reserves `Spacing.pagePadding + 40` on the right so cards never sit under the index column.
- `VenueCard` (`venue_card.dart`): plain `Container` (surface color, 16px radius, 16px padding, no border/gradient), bold name (`AppFontSizes.title`) + subtitle line always rendered (empty string when no city/state) so card height stays uniform.

### Band Members (current)

`band_members_view.dart` — `StatelessWidget` fed `membersState`/`bandState`/callbacks from `ContactsTabContent`. `CustomScrollView` with a fixed title row (`SliverToBoxAdapter`) and a flat `SliverList` of `MemberCard`s inside `SliverPadding`. No search, no grouping.

`MemberCard` (`member_card.dart`): heavy card (24px radius, 2px rose border, gradient wash) showing name + optional role icon (crown/eye) + optional kebab `IconButton` (`_buildAdminButton()`, visible only when `showAdminActions: membersState.isCurrentUserAdmin`, calls `onManageRole`) + role pills (`member.displayRoles` = `member.musicalRoles`) + contact rows (phone/email/address/birthday, each individually tappable). **Card-level `onTap` is currently a no-op** (`onTap: () {}` in `band_members_view.dart:109`) — the comment in `member_card.dart:85` confirms this is intentional: "No card-level tap handler - contact rows handle their own taps (phone, email)." The only functional card-level interaction today is the admin kebab → `RoleManagementSheet`.

**`MemberVM` already carries everything needed** — `musicalRoles: List<String>` (`member_vm.dart:72`), sourced by `MembersRepository.fetchMembersAndInvites()` Query D (`user_band_roles` table, band-specific instruments/positions) with fallback to `users.roles` (global) if no band-specific row exists. This is explicitly distinct from `bandRole` (`band_members.role` — the RBAC permission level: owner/admin/member/contributor), confirmed at `member_vm.dart:18-29` and `members_repository.dart:26-29`. **No repository or query change needed** — `musicalRoles` is already fetched and already used today (`band_members_view.dart:98` even keys list items on it: `member_${member.memberId}_${member.musicalRoles.join(',')}`).

`membersProvider`/`MembersState`/`MembersRepository` are used well beyond this one view (financials, events forms, home, profile). **This plan does not touch `members_controller.dart`, `members_repository.dart`, `member_vm.dart`, or `member_card.dart`** — search/grouping state for the Band segment will be owned locally inside a new/modified view widget, not pushed into the shared provider.

`members_tab_content.dart` also renders `MemberCard` but is **not wired into the live app shell** — `app_shell.dart` renders `ContactsTabContent`, not `MembersTabContent`. The only other reference to `MembersTabContent` is inside `shared/widgets/native_app_banner_integration.dart`, which is a commented-out documentation/example file (the entire body is inside a `/* */` block), not live code. Confirmed via `grep`. `members_tab_content.dart` is therefore legacy/unrouted — left untouched and off-limits.

### Contacts (current)

`contacts_view.dart` — `ConsumerStatefulWidget`, `CustomScrollView` with fixed title (`SliverToBoxAdapter`) + flat `SliverList` of `ContactCard`s. No search, no grouping. Tapping a card today calls `_openContactForm(context: context, contact: contact)`, which pushes `ContactFormScreen(contact: contact)` — **i.e. tap-to-edit, with no separate detail screen** (unlike Venues, which grew a `VenueDetailScreen` in a later amendment).

`ContactCard` (`contact_card.dart`): same heavy visual language as `MemberCard`/old `VenueCard` (24px radius, 2px rose border, gradient wash), showing name, optional title pill, phone/email/notes rows.

`Contact` model (`models/contact.dart`) already has `title` (nullable `String`) — **this is the role/title field** the feature asks for ("what field holds a contact's role/title"). Already fetched by `ContactsRepository.fetchContacts()` (`select('*')`, no embedded joins needed). **No repository or model change needed.**

---

## Proposed Solution

### Design decision: extract shared A-Z helpers/widgets, retrofit Venues to use them

The feature input explicitly asks me to weigh "guardrails' caution against opportunistic refactors" against "the real maintenance cost of a third copy" of the ~40-line grouping/flat-index/index-column logic. My call: **extract, and retrofit Venues** — not leave Venues untouched with its private copy while Band/Contacts get a second near-identical copy (net: 3 total implementations of the same non-trivial arithmetic, which is exactly the failure mode that caused the off-by-N bug documented in the Venues plan's Amendment 1).

**What gets extracted (pure logic + small composable presentational widgets — not a monolithic list widget):**

1. `lib/features/contacts/widgets/az_list_helpers.dart` — pure, generic, no Flutter dependency beyond nothing:
   - `Map<String, List<T>> groupByLetter<T>(List<T> items, String Function(T) nameOf)` — the A-Z + `#` grouping logic currently inlined in `_groupVenuesByLetter()`.
   - `int flatIndexForSection(String targetLetter, Map<String, List> grouped)` — the single flat-index bookkeeping helper (today's `_getFlatIndexForSection`).
   - `String resolveTargetLetter(String letter, Map<String, List> grouped)` — the "nearest populated section" fallback currently inlined in the index column's `onTap` closure in `venues_view.dart:550-564`. Extracting this specifically matters because Contacts needs byte-for-byte identical fallback behavior, and inlining it a second time is exactly the kind of duplication that caused the prior bug.

2. `lib/features/contacts/widgets/az_search_field.dart` — `AzSearchField` stateless wrapper around the `TextField` search bar (controller, hint text, clear button, styling) — today duplicated near-identically between `_buildSearchBar()` in `venues_view.dart` and (soon) Contacts/Band. One parameterized widget (hint text differs per segment).

3. `lib/features/contacts/widgets/az_index_column.dart` — `AzIndexColumn`, the `Positioned` A-Z+# column. Takes `Map<String, List> grouped` and `void Function(String letter) onLetterTap`. Used by Venues and Contacts only. **This is the "optional/composable piece"** the feature input calls for: it's just a widget that Band Members' view never instantiates — not a flag on a shared mega-widget. Its presence/absence also drives whether the list reserves the 40px right padding (a constant each view applies to its own item padding — not baked into the column widget itself).

4. `lib/features/contacts/widgets/az_section_header.dart` — `AzSectionHeader`, the small rose bold letter-header `Text`, parameterized by right-padding (Venues/Contacts reserve 40px for the index column; Band Members does not).

**What does NOT get extracted:** the `ScrollablePositionedList.builder` wiring, `itemCount`/`itemBuilder` flat-index-to-widget mapping, and per-item card rendering. Each view's underlying model (`Venue`, `Contact`, `MemberVM`) and card widget differ, and Band Members additionally omits the index column and its associated 40px padding reservation. Forcing all three into one generic `AzListView<T>` widget would require either a generic type param plumbed through three different card builders and three different right-padding constants, or a boolean "hasIndexColumn" flag threaded through a monolithic widget — which is precisely the anti-pattern the feature input warns against ("not baked into a single monolithic 'AZ list' widget that Band Members would have to disable or hide"). Keeping the scroll-list wiring per-view (three short, near-identical `_calculateItemCount`/`_buildItem` methods, ~40-60 lines each) while sharing the actual bug-prone arithmetic is the better risk/reuse trade-off.

**Retrofit scope on `venues_view.dart`:** swap the three inline pieces (`_groupVenuesByLetter`, `_getFlatIndexForSection`, the inline nearest-letter fallback, the inline search `TextField`, the inline index column `Positioned`/`Column`) for calls into the four new shared files. `ScrollablePositionedList` wiring, `_calculateItemCount`, `_buildItem`, sticky-header (nonexistent, per discrepancy above), `RefreshIndicator`, empty states, and `VenueCard` itself are **not touched**. Behavior must be pixel-for-pixel and logic-for-logic identical after the swap — this is a mechanical extraction, not a redesign. Elevated regression risk from touching already-shipped Venues code is called out explicitly below and mitigated by full Venues regression retest in the Verification Plan.

### Band Members segment

New file `lib/features/contacts/widgets/band_member_card.dart` — `BandMemberCard`, a new simplified card, **not** a modification of `member_card.dart` (which stays untouched — it's still used by the legacy `members_tab_content.dart` and is a bigger, differently-scoped widget). Visual style matches `VenueCard`: plain surface `Container`, 16px radius, 16px padding, no border/gradient.

Layout:
- Row: bold name (`member.name`, `AppFontSizes.title`, `w700`) `Expanded`, plus — **preserved, not dropped** — the existing admin kebab `IconButton` when `showAdminActions` is true, calling `onManageRole` (identical wiring to today's `_buildAdminButton()`). This is existing functional behavior (opens `RoleManagementSheet`); the feature input's "preserve or sensibly adapt" instruction governs this, and there's no reason to remove working admin functionality as a side effect of a visual simplification.
- Subtitle line (always rendered, empty string when no roles, to keep uniform card height per the lesson from Venues): `member.musicalRoles.join(', ')` — instruments/positions, in the position `VenueCard` uses for city/state (`AppFontSizes.body`, `textSecondary`).
- **Dropped, by design, matching the minimalism of the Venues redesign:** the decorative role badge icon (crown/eye), the role pills row, and the phone/email/address/birthday contact rows. These are purely informational/decorative in list context; the card's job here is scannable identification + navigation, matching how `VenueCard` dropped address/phone/contacts in favor of the (now separate) `VenueDetailScreen`. There is no equivalent "member detail screen" to push this information to and the feature input does not ask for one — this information simply isn't shown in the simplified list card, same as Venues' address/phone/notes aren't shown in `VenueCard` anymore.
- Card-level `onTap`: preserved as a no-op passthrough (`VoidCallback? onTap`, default null), matching current behavior exactly — there was no functional card-tap behavior to preserve or adapt beyond the admin kebab, which is handled separately.

New/modified `band_members_view.dart`: convert from `StatelessWidget` to a small `StatefulWidget` (still fed the same props from `ContactsTabContent` — **no change to `membersProvider` or its shared consumers**) holding a local `TextEditingController` and `String _searchQuery`. Filters `membersState.members` client-side by `member.name` (case-insensitive `contains`), matching the Venues/Contacts search-by-primary-name-field convention. Groups via the shared `groupByLetter()` helper using a grouping key of **last name** (falling back to first name, then full `name`, mirroring the existing `#`-bucket empty-name fallback pattern) — see Design Decision below for why. Renders: fixed title row (unchanged "Band Members" + Add button) → fixed `AzSearchField` (hint: "Search band members") → `Expanded(ScrollablePositionedList.builder(...))` using local `_calculateItemCount`/`_buildItem` (same flat-index shape as Venues, using `BandMemberCard`). **No `AzIndexColumn`, and no 40px right-padding reservation** — cards use full list width (`Spacing.pagePadding` both sides), matching the explicit product requirement that Band Members' list width is not reserved for an index it doesn't have.

**Design Decision — Band Members grouping key is last name, not full display name:** Venues and Contacts group by the exact field the card displays (`venue.name`, `contact.name`), and that field is also what the repository already sorts by server-side (`.order('name', ascending: true)`), so grouping key, display text, and server order are all the same field — self-consistent by construction. Band Members is different: `MembersRepository.fetchMembersAndInvites()` explicitly sorts server-side by **last name, then first name** (`members_repository.dart:222-235`), while the card displays the combined `"$firstName $lastName"`. Per Guardrails §6 ("ordering logic lives in Supabase RPC/repo, never implement client-side ordering that can drift from server"), this plan does not introduce a second, divergent client-side sort (e.g., re-sorting by full display name for grouping purposes) — that would silently fight the server's established order. Instead, the A-Z grouping key is the same field the list is already ordered by (last name, with the existing fallback chain for missing values), so section boundaries fall exactly where the already-correct list order changes letter. No repository change; this is purely how the client picks a grouping key from data it already has, in a way that stays consistent with existing ordering.

### Contacts segment

Modify `contact_card.dart` in place (mirroring exactly how `venue_card.dart` was simplified in Amendment 2 of the Venues plan — same treatment, same precedent, and `ContactCard` has exactly one call site to update): strip the 2px border, gradient wash, title pill, and phone/email/notes rows down to the `VenueCard` pattern — plain `Container`, 16px radius, 16px padding, bold name (`AppFontSizes.title`), subtitle line always rendered (`contact.title ?? ''`, `textSecondary`) using the role/title field confirmed above.

Modify `contacts_view.dart`: same shape of change as Band Members but **with** the index column — fixed title row (unchanged) → fixed `AzSearchField` (hint: "Search contacts") → `Expanded(ScrollablePositionedList.builder(...))` with local `_calculateItemCount`/`_buildItem` grouping `contactsState.contacts` via shared `groupByLetter()` keyed on `contact.name` (matches the server's existing `.order('name', ascending: true)` — self-consistent, no divergence concern) → `AzIndexColumn` in a `Stack`, identical wiring to Venues (all 27 entries, dimmed-not-omitted, nearest-letter fallback via shared `resolveTargetLetter()`). List items reserve `Spacing.pagePadding + 40` on the right, same as Venues.

**Tap behavior — preserved exactly, no new detail screen:** `ContactCard.onTap` continues to call `_openContactForm(context: context, contact: contact)`, opening the existing `ContactFormScreen` in edit mode. The feature input explicitly says not to assume a new detail screen is needed, and nothing in the Summary/Expected Behavior calls for one — Contacts never had a read-only detail view (unlike Venues, which grew one across three amendments before edit was even re-added to it). Building one here would be scope creep not asked for.

Add `searchQuery`/`filteredContacts` fields to `ContactsState` and a `setSearchQuery()`/`_filterContacts()` pair on `ContactsNotifier`, mirroring `VenuesState`/`VenuesNotifier` exactly (`contacts_controller.dart`). Filter matches `contact.name` case-insensitively (Venues also matches city + contact-person-name per its later amendment, but Contacts has no equivalent secondary fields worth matching — `title`/`phone`/`email` are not name-like fields a user would search by name-matching intuition, so single-field name search is the correct, minimal scope here, not an oversight).

---

## Database Impact

**Not applicable.** Confirmed by direct inspection, not assumption, per the feature input's explicit request:

- Band Members: `musicalRoles` (instruments) already fetched by `MembersRepository.fetchMembersAndInvites()` Query D against `user_band_roles`, already present on `MemberVM`, already used today. No query, RLS, or RPC change.
- Contacts: `title` (role/title) already fetched by `ContactsRepository.fetchContacts()` (`select('*')`), already present on `Contact`. No query, RLS, or RPC change.
- No new tables, columns, migrations, RPCs, or RLS policy changes anywhere in this feature. All work is client-side filtering/grouping/rendering of already-fetched data, identical in kind to the (already-shipped, backend-untouched) Venues feature.

---

## Flutter Architecture Changes

### New files

- `lib/features/contacts/widgets/az_list_helpers.dart` — pure functions: `groupByLetter<T>()`, `flatIndexForSection()`, `resolveTargetLetter()`.
- `lib/features/contacts/widgets/az_search_field.dart` — `AzSearchField` widget.
- `lib/features/contacts/widgets/az_index_column.dart` — `AzIndexColumn` widget.
- `lib/features/contacts/widgets/az_section_header.dart` — `AzSectionHeader` widget.
- `lib/features/contacts/widgets/band_member_card.dart` — `BandMemberCard` widget.

### Modified state

- `ContactsState`/`ContactsNotifier` (`contacts_controller.dart`): add `searchQuery`, `filteredContacts`, `setSearchQuery()`, `_filterContacts()` — structurally identical to `VenuesState`/`VenuesNotifier`.
- No changes to `MembersState`/`MembersNotifier` — Band segment's search/grouping state lives locally in the view, not in the shared provider (see below).

### Modified widgets

- `venues_view.dart` — internal-only retrofit to consume the four new shared files instead of its private inline copies. No behavioral change intended; no change to `VenuesState`/`VenuesController`/`VenueCard`/`VenueDetailScreen`/`VenueFormScreen`.
- `band_members_view.dart` — `StatelessWidget` → `StatefulWidget` holding local search state; renders `AzSearchField` + `AzSectionHeader` + `BandMemberCard` via `groupByLetter()`; **no** `AzIndexColumn`.
- `contact_card.dart` — simplified in place to the `VenueCard` visual pattern.
- `contacts_view.dart` — gains `AzSearchField` + `AzSectionHeader` + `AzIndexColumn`, `ScrollablePositionedList.builder` replacing `CustomScrollView`/`SliverList`.

### Unidirectional data flow (Guardrails §9)

Unchanged: `ContactsTabContent` still owns band-switch reset logic and still passes `membersState`/callbacks down to `BandMembersView` by constructor. `VenuesNotifier`/`ContactsNotifier` remain the sole mutation points for their respective search state, called via `ref.read(...).setSearchQuery()` from the view — same pattern as today's Venues.

---

## Files to Create

| File | Justification |
|---|---|
| `lib/features/contacts/widgets/az_list_helpers.dart` | Centralizes A-Z grouping, flat-index bookkeeping, and nearest-letter fallback in one place, per the explicit lesson from the Venues plan's Amendment 1 off-by-N bug. Used by Venues (retrofit), Contacts, and (grouping only) Band Members. |
| `lib/features/contacts/widgets/az_search_field.dart` | Shared search bar widget, removes 3x duplication of ~50 lines of `TextField` decoration boilerplate. |
| `lib/features/contacts/widgets/az_index_column.dart` | Shared, genuinely optional index column widget — instantiated by Venues and Contacts only, never by Band Members. |
| `lib/features/contacts/widgets/az_section_header.dart` | Shared section-letter header widget, parameterized by right-padding (differs between index-column and no-index-column segments). |
| `lib/features/contacts/widgets/band_member_card.dart` | New simplified Band Members card. Not a modification of `member_card.dart`, which remains in use elsewhere (legacy `members_tab_content.dart`) and is a larger, differently-scoped widget. |

---

## Files to Modify

| File | What changes |
|---|---|
| `lib/features/contacts/widgets/venues_view.dart` | Swap inline `_groupVenuesByLetter`, `_getFlatIndexForSection`, inline nearest-letter fallback, inline search `TextField`, and inline index-column `Positioned` for calls into the four new shared files. No change to `ScrollablePositionedList` wiring, `_calculateItemCount`/`_buildItem`, `RefreshIndicator`, empty states, or navigation. |
| `lib/features/contacts/widgets/band_members_view.dart` | Convert to `StatefulWidget` with local search state; add `AzSearchField`, A-Z grouping via shared helper (grouping key: last name, see Design Decision), `AzSectionHeader`; render `BandMemberCard` in place of `MemberCard`; replace `CustomScrollView`/`SliverList` with `ScrollablePositionedList.builder`; no `AzIndexColumn`; cards use full list width. |
| `lib/features/contacts/widgets/contacts_view.dart` | Add `AzSearchField`, A-Z grouping via shared helper (grouping key: `contact.name`), `AzSectionHeader`, `AzIndexColumn`; replace `CustomScrollView`/`SliverList` with `ScrollablePositionedList.builder`; render simplified `ContactCard`; preserve existing tap→`ContactFormScreen` behavior. |
| `lib/features/contacts/widgets/contact_card.dart` | Simplify in place to `VenueCard`'s visual pattern: drop border/gradient/title-pill/contact-rows; show bold name + role/title subtitle (always-reserved space). |
| `lib/features/contacts/contacts_controller.dart` | Add `searchQuery`/`filteredContacts` to `ContactsState`; add `setSearchQuery()`/`_filterContacts()` to `ContactsNotifier`, mirroring `VenuesState`/`VenuesNotifier`. |
| `pubspec.yaml` | **No change expected** — `scrollable_positioned_list: ^0.3.8` already present from the Venues feature. Engineer must confirm this before starting and flag immediately if it's somehow absent (it should not be). |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/features/contacts/widgets/venue_card.dart` | Already at target state (Venues Amendment 2). Not touched by this feature. |
| `lib/features/contacts/widgets/venue_detail_screen.dart` | Out of scope — Venues detail screen unaffected. |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Out of scope. |
| `lib/features/contacts/widgets/venue_contact_block.dart` | Out of scope. |
| `lib/features/contacts/venues_controller.dart` | Out of scope — Venues state shape unchanged (view swaps internals only, not the controller). |
| `lib/features/contacts/venues_repository.dart` | Data fetch already correct; no change needed. |
| `lib/features/contacts/models/venue.dart`, `models/venue_contact.dart`, `models/contact.dart` | Models already contain all required fields (`title` on `Contact` confirmed above). |
| `lib/features/members/member_vm.dart` | `musicalRoles` already present and correct; no change needed. |
| `lib/features/members/members_controller.dart`, `members_repository.dart` | `membersProvider` is shared app-wide (financials, events, home, profile) — this feature reads from it but does not modify its shape or query behavior. |
| `lib/features/members/widgets/member_card.dart` | Stays in use by legacy `members_tab_content.dart`; not modified. A new, separate `BandMemberCard` is created instead. |
| `lib/features/members/widgets/role_management_sheet.dart` | Admin role-management flow unchanged; `BandMemberCard`'s kebab button wires to the exact same `onManageRole` callback already passed down from `ContactsTabContent`. |
| `lib/features/members/members_tab_content.dart` | Confirmed unrouted (not referenced by `app_shell.dart`); legacy/dead in the live app. Out of scope, not cleaned up as part of this feature (no opportunistic cleanup per Guardrails §7). |
| `lib/features/contacts/contacts_tab_content.dart` | Segment toggle, lazy-load, and band-switch-reset logic already correct; no change needed. |
| `lib/features/contacts/widgets/venues_empty_state.dart`, `widgets/contacts_empty_state.dart`, `members/widgets/members_empty_state.dart` | "Zero items at all" empty states unchanged; only the "search has no results" inline state (new, matching Venues' existing inline pattern) is added per view. |
| `lib/main.dart` | No routing/init changes — this feature uses `Navigator.push`/existing screens only. |

---

## Migration Policy

**Not required.** No database changes.

---

## Edge Function Deploy

**Not required.** No backend changes.

---

## New Dependencies

**None.** `scrollable_positioned_list: ^0.3.8` is already a dependency (added by the Venues feature). Engineer must verify it's present in `pubspec.yaml` before starting; do not re-add if already there.

---

## System Impact Map

| System | Impact |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | **affected** — `band_members_view.dart` rendering changes; `membersProvider`/`MembersState`/`MembersRepository`/`MemberVM` themselves unaffected (read-only consumption), so other consumers (financials, events, home, profile) see no change. Admin role-management (kebab → `RoleManagementSheet`) preserved. |
| Auth / Session | unaffected |
| Routing | unaffected — no new screens, `Navigator.push` targets unchanged (Contacts still → `ContactFormScreen`) |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — UI-only changes, no platform-specific code paths |

---

## Regression Risk

**Level:** MEDIUM

**Rationale:**

- Zero backend changes; all client-side, read-only consumption of already-fetched data.
- Two brand-new list implementations (Band, Contacts) carry the same class of risk the Venues feature already worked through (and documented via its amendments) — flat-index arithmetic, `ScrollablePositionedList` non-Sliver quirks, index-column dimming/always-27 — but this plan explicitly reuses centralized, already-correct logic rather than re-deriving it, which meaningfully lowers risk relative to Venues' original build-from-scratch process.
- **The retrofit of already-shipped `venues_view.dart`** is the main source of elevated risk in this plan — Venues search, grouping, and index-scroll are live, working, and used today; swapping their internals for shared helpers must be verified to produce byte-identical behavior. This is called out explicitly as its own regression area below, and is why this plan is MEDIUM rather than LOW despite touching no backend.
- `band_members_view.dart` conversion from `StatelessWidget` to `StatefulWidget` and the card swap (`MemberCard` → `BandMemberCard`) touches a view fed by a widely-shared provider (`membersProvider`) — but since the provider itself and `MemberVM` are untouched, and `BandMemberCard` is a new, additive widget (not a modification of the shared `MemberCard`), the blast radius to other `membersProvider` consumers is contained.
- Admin role-management (kebab menu) is a real, currently-working feature being carried into a simplified card — must be explicitly verified, not assumed to "just work" because the callback signature matches.

---

## Engineer Task Breakdown

Execute in strict order.

### Task 1: Verify dependency present

- Confirm `scrollable_positioned_list: ^0.3.8` exists in `pubspec.yaml`. Do not modify `pubspec.yaml` if present (expected case). If genuinely absent, stop and report to Architect before proceeding — this would mean the Venues feature's dependency was somehow removed, which is outside this plan's scope to diagnose.

### Task 2: Extract shared A-Z helpers

- Create `lib/features/contacts/widgets/az_list_helpers.dart`:
  - `Map<String, List<T>> groupByLetter<T>(List<T> items, String Function(T) nameOf)` — port logic from `venues_view.dart`'s `_groupVenuesByLetter()` (regex `^[A-Z]$` match, else `#`, map ordered A→Z then `#`).
  - `int flatIndexForSection(String targetLetter, Map<String, List> grouped)` — port from `_getFlatIndexForSection()`.
  - `String resolveTargetLetter(String letter, Map<String, List> grouped)` — port the nearest-populated-section fallback currently inlined in `venues_view.dart`'s index column `onTap` (lines ~550-564): if `grouped` doesn't contain `letter`, find the first key where `key.compareTo(letter) >= 0 || key == '#'`, else fall back to `grouped.keys.last`.

### Task 3: Extract shared search field widget

- Create `lib/features/contacts/widgets/az_search_field.dart` — `AzSearchField` (`StatelessWidget`): `controller`, `hintText`, `currentQuery` (for clear-button visibility), `onChanged`, `onClear`. Port styling exactly from `venues_view.dart`'s `_buildSearchBar()` (16px radius, `context.colors.surface` fill, `context.colors.border`/`AppColors.primary` focus border).

### Task 4: Extract shared index column widget

- Create `lib/features/contacts/widgets/az_index_column.dart` — `AzIndexColumn` (`StatelessWidget`): `grouped` map, `onLetterTap(String letter)` callback, `topOffset`, `bottomPadding`. Port exactly from `venues_view.dart`'s `_buildIndexColumn()` (all 27 entries A-Z+#, `Expanded` even spacing, dimmed-not-omitted via `alpha: 0.3`). Caller (each view) resolves the tapped letter via `resolveTargetLetter()` and computes the scroll target via `flatIndexForSection()`, then drives its own `ItemScrollController` — the widget itself only reports which letter was tapped, it does not own scrolling.

### Task 5: Extract shared section header widget

- Create `lib/features/contacts/widgets/az_section_header.dart` — `AzSectionHeader` (`StatelessWidget`): `letter`, `rightPadding` (0 for Band Members, `Spacing.pagePadding + 40` for Venues/Contacts). Port styling from `venues_view.dart`'s inline section header `Text` (rose, `AppFontSizes.pageTitle`, `w700`).

### Task 6: Retrofit VenuesView to shared helpers

- Edit `venues_view.dart`: replace `_groupVenuesByLetter()` calls with `groupByLetter(venues, (v) => v.name)`; replace `_getFlatIndexForSection()` calls with `flatIndexForSection()`; replace the inline nearest-letter fallback in the index column `onTap` with `resolveTargetLetter()`; replace the inline `_buildSearchBar()` body with `AzSearchField`; replace the inline `_buildIndexColumn()` body with `AzIndexColumn`; replace the inline section-header `Text` in `_buildItem()` with `AzSectionHeader`.
- Do not change `_calculateItemCount()`, `_buildItem()`'s overall flat-index branching structure, `ScrollablePositionedList` wiring, `RefreshIndicator`, empty-search-state, or any navigation call. This task is a mechanical swap of internals, not a rewrite.
- Manually verify (see Verification Plan) that search, grouping, index-scroll-to-section, dimmed/nearest-letter behavior, and `#` bucketing are unchanged before moving on.

### Task 7: Add search state to ContactsController

- Edit `contacts_controller.dart`: add `searchQuery` (default `''`) and `filteredContacts` (default `[]`) to `ContactsState` + `copyWith()`. Add `setSearchQuery(String query)` and `_filterContacts(List<Contact> contacts, String query)` (case-insensitive `contact.name.contains`) to `ContactsNotifier`, mirroring `VenuesState`/`VenuesNotifier` exactly. Update `load()`/`refresh()` to populate `filteredContacts` alongside `contacts`, same pattern as `VenuesNotifier.load()`/`refresh()`.

### Task 8: Simplify ContactCard

- Edit `contact_card.dart`: remove `Border.all`, gradient `Stack`/`Positioned.fill`, title pill, phone/email/notes rows, `_buildInfoRow()`, `_launchPhone()`, `_launchEmail()`. Result: plain `Container` (surface, 16px radius, 16px padding), bold name (`AppFontSizes.title`), subtitle line always rendered (`contact.title ?? ''`, `textSecondary`, `AppFontSizes.body`).

### Task 9: Rebuild ContactsView on the shared pattern

- Edit `contacts_view.dart`: add `TextEditingController`, `ItemScrollController`; render fixed title row (unchanged) → fixed `AzSearchField` (hint "Search contacts") → `Expanded(ScrollablePositionedList.builder(...))` using local `_calculateItemCount()`/`_buildItem()` (structurally identical to Venues', grouping via `groupByLetter(contacts, (c) => c.name)`, rendering `AzSectionHeader` + `ContactCard`) → `Stack` with `AzIndexColumn` (hidden while searching, same as Venues). List items reserve `Spacing.pagePadding + 40` right padding. Preserve `onTap: () => _openContactForm(context: context, contact: contact)` unchanged. Add inline "No contacts found" empty-search state matching Venues' pattern.

### Task 10: Create BandMemberCard

- Create `band_member_card.dart`: plain `Container` (surface, 16px radius, 16px padding). Header `Row`: bold name (`AppFontSizes.title`) `Expanded` + optional admin kebab `IconButton` (`showAdminActions` + `onManageRole`, ported from `MemberCard._buildAdminButton()`). Subtitle line always rendered: `member.musicalRoles.join(', ')` (`textSecondary`, `AppFontSizes.body`). `onTap: VoidCallback?` (default null, no-op — matches current behavior).

### Task 11: Rebuild BandMembersView on the shared pattern (no index column)

- Edit `band_members_view.dart`: convert `StatelessWidget` → `StatefulWidget`. Add local `TextEditingController`, `ItemScrollController`, `String _searchQuery`. Filter `membersState.members` by `member.name` (case-insensitive `contains`). Group filtered members via `groupByLetter(filtered, (m) => _groupingKey(m))` where `_groupingKey` returns `lastName` if non-empty, else `firstName` if non-empty, else `name` (mirrors existing `#`-bucket empty-value fallback pattern). Render fixed title row (unchanged "Band Members" + Add button) → fixed `AzSearchField` (hint "Search band members") → `Expanded(ScrollablePositionedList.builder(...))` with local `_calculateItemCount()`/`_buildItem()` rendering `AzSectionHeader(rightPadding: 0)` + `BandMemberCard(onManageRole: () => onManageRole(member), showAdminActions: membersState.isCurrentUserAdmin)`. **No `AzIndexColumn`.** List items use `Spacing.pagePadding` on both sides (no 40px reservation). Add inline "No members found" empty-search state.
- Preserve existing loading/error/empty (zero members) states unchanged (`_buildLoadingState()`, `_buildErrorState()`, `MembersEmptyState`).

### Task 12: Cross-platform manual verification

- Web, iOS, Android, macOS: exercise all three segments per Verification Plan below.

---

## Verification Plan

All testing is client-side UI validation — no database changes, so there is no Tier 1/Tier 2 SQL split; this section lists manual verification for each platform.

### Test 1: Venues Retrofit — No Regression

1. Navigate to Contacts tab → Venues segment.
2. Confirm A-Z sections render identically to before (empty letters omitted from sections, but all 27 shown dimmed-vs-lit in the index column).
3. Confirm `#` section still catches non-letter-starting venue names and sorts last.
4. Type in search → confirm live filtering, index column hides, section headers hide.
5. Clear search → confirm full sectioned list + index column return.
6. Tap several index letters (including at least one empty one) → confirm scroll lands on the correct section, and empty-letter taps jump to the nearest populated section (or `#`, or last section).
7. Tap a venue card → confirm `VenueDetailScreen` still opens (unchanged navigation).
8. Tap "Add" → confirm `VenueFormScreen` still opens.
9. Pull to refresh → confirm still works.

### Test 2: Band Members — New A-Z List

1. Navigate to Contacts tab → Band segment (default).
2. Confirm search bar present, A-Z section headers render (empty letters omitted), **no index column visible**, cards span full list width (no dead space on the right where an index column would be).
3. Confirm section boundaries match the existing last-name-based order (no member appears to "jump" out of alphabetical order relative to today's list).
4. Type in search → confirm live filter by name; clear → confirm full list restored.
5. Confirm each card shows bold first+last name and, on the line below, the member's instruments/positions (or blank space, not a missing/collapsed line, if none) — verify at least one member with multiple `musicalRoles` shows them comma-joined.
6. As an admin user: confirm the kebab (⋮) button still appears on cards and still opens `RoleManagementSheet`, and role changes still persist and reload correctly.
7. As a non-admin user: confirm the kebab button does not appear.
8. Confirm tapping a card (not the kebab) does nothing, matching current behavior.
9. Pull to refresh → confirm still works; confirm zero-members empty state (`MembersEmptyState`) still renders correctly when a band has no members.

### Test 3: Contacts — New A-Z List (Full Venues Pattern)

1. Navigate to Contacts tab → Contacts segment.
2. Confirm search bar, A-Z section headers (empty letters omitted), and the right-side A-Z+# index column (all 27 shown, dimmed when empty) all render.
3. Confirm cards show bold name + role/title subtitle (or blank line if no title) with uniform card height.
4. Type in search → confirm live filter by name, index column hides; clear → confirm restored.
5. Tap several index letters including an empty one → confirm scroll-to-section and nearest-letter fallback work identically to Venues.
6. Tap a contact card → confirm it still opens `ContactFormScreen` in edit mode (no new detail screen).
7. Tap "Add" → confirm `ContactFormScreen` opens in create mode.
8. Pull to refresh → confirm still works; confirm zero-contacts empty state (`ContactsEmptyState`) still renders correctly.

### Test 4: Cross-Segment Consistency

1. Confirm search bar styling, section header styling, and card visual language (radius, padding, name/subtitle typography) are visually consistent across all three segments except for the intentional index-column difference.
2. Confirm switching segments (Band ↔ Venues ↔ Contacts) via `SegmentedToggle` still animates/loads correctly, and band-switch reset (switching active band resets Venues/Contacts search state and reloads Band members) still works.

### Test 5: Edge Cases

1. Band/Contacts with 0 items → zero-state empty views (not the search-empty state).
2. Band/Contacts with 1 item → single section header + index column (Contacts only) still renders sensibly.
3. Search with no matches → "No results" inline state on all three segments, no crash.
4. A band member with no `musicalRoles` at all → subtitle line renders blank, card height still matches siblings.
5. A contact with no `title` → subtitle line renders blank, card height still matches siblings.
6. A band member whose `lastName` is null/empty (only `firstName` or only email-derived name available) → confirm grouped sensibly (falls back per `_groupingKey`) and doesn't crash or get silently dropped from the list.

---

## QA Regression Areas

### Primary (new functionality)

1. Band Members search (live filter, clear).
2. Band Members A-Z sectioning (correct letters, empty omitted, section order matches existing last-name-based order).
3. Band Members card content (name, instruments subtitle, uniform height) and **absence** of an index column (no dead space, full-width cards).
4. Band Members admin kebab → `RoleManagementSheet` still functions (this is the highest-risk item in this feature — a working admin flow is being carried into a new card).
5. Contacts search (live filter, clear).
6. Contacts A-Z sectioning + `#` bucket.
7. Contacts index column (all 27 shown, dimmed vs. lit, nearest-letter fallback, tap-to-scroll).
8. Contacts simplified card content (name, role/title subtitle, uniform height).
9. Contacts tap → `ContactFormScreen` edit flow unchanged.

### Regression (existing functionality touched by the shared-helper retrofit)

10. **Venues search, grouping, `#` bucket, index column (including dimmed/nearest-letter behavior), and tap→`VenueDetailScreen`/`VenueFormScreen` navigation — full re-test, not spot-check, since `venues_view.dart` internals were swapped.**
11. Other `membersProvider` consumers unaffected: spot-check financials assignee picker, events gig/rehearsal forms, home tab, and My Profile still show correct member data (these read `MembersState`/`MemberVM`, neither of which changed shape).
12. `SegmentedToggle` segment switching, lazy-load-on-first-visit, and active-band-switch reset (all in `contacts_tab_content.dart`, untouched) still behave correctly across all three segments.

---

## Rollout / Migration Strategy

Not applicable — client-only UI change, no backend migration.

**Deployment steps:**

1. Merge PR to `main`.
2. Deploy web via `./tools/deploy_web.sh`.
3. Mobile: standard build/release process for iOS/Android/macOS.

---

## Out of Scope

1. **Sticky section headers for any segment** — confirmed absent from the actual shipped Venues implementation (see discrepancy note above); not added anywhere in this feature, keeping all three segments consistent with each other and with reality.
2. **A new Band Member detail screen** — not requested, not built. Card-level tap remains a no-op; admin actions remain reachable via the kebab.
3. **A new Contacts detail screen** — not requested, not built. Tap continues to open `ContactFormScreen` (edit), exactly as today.
4. **Adding an index column to Band Members** — explicitly excluded by the feature input; list uses full width instead.
5. **Search matching secondary fields** (phone, email, notes, role/title, instruments) — all three segments search by primary display name only, matching the Venues precedent's original (pre-amendment) scope and the fact that Contacts/Band have no equivalent secondary "name-like" field worth matching.
6. **Any change to `MemberVM`, `membersProvider`, `MembersRepository`, or `member_card.dart`** — Band segment consumes existing shared state read-only; `member_card.dart` remains available for its existing (legacy, unrouted) consumer.
7. **Any change to `venue_card.dart`, `venue_detail_screen.dart`, `venue_form_screen.dart`, or `VenuesState`/`VenuesController`** — only `venues_view.dart`'s internals are touched, and only to swap in shared helpers with identical behavior.
8. **Cleanup of the unrouted `members_tab_content.dart`** — confirmed dead in the live app shell, but removing it is unrelated cleanup outside this feature's scope (Guardrails §7 — no opportunistic refactors).
9. **Backend/database changes of any kind** — confirmed not needed for either segment's required fields.
10. **Role badge icon (crown/eye) in the simplified Band Member card** — dropped as part of the intentional minimalism, matching how Venues dropped its own decorative elements; full role context remains available via the admin kebab → `RoleManagementSheet`, which already surfaces role information.
