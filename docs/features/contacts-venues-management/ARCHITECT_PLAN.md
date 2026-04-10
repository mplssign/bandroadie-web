# ARCHITECT_PLAN.md

## 1. Feature Slug

`feature/contacts-venues-management`

---

## 2. Problem Summary

The app's tab index 3 currently renders a Members-only view (`MembersTabContent`). Users need a unified Contacts page that retains the existing band-member list and adds two new data domains — Venues (with nested venue contacts) and standalone Contacts — accessible via a segmented toggle within the same tab. No new navigation tabs are added; the bottom nav label changes from "Members" to "Contacts".

---

## 3. Root Cause

**Not applicable** — this is a feature request, not a bug. There is no root cause to diagnose.

---

## 4. Reference Docs Consulted

| File                                             | Relevance                                                 |
| ------------------------------------------------ | --------------------------------------------------------- |
| `docs/reference/architecture/architecture.md`    | Feature-first folder structure, Riverpod Notifier pattern |
| `docs/reference/architecture/database_schema.md` | Existing table schemas (bands, band_members, songs, gigs) |
| `.github/copilot-instructions.md`                | Project conventions, theme tokens, brand voice            |
| `docs/agents/GUARDRAILS.md`                      | File size targets, RLS safety, code change discipline     |
| `docs/agents/OPERATING_MODEL.md`                 | Pipeline gates, safety non-negotiables                    |

---

## 5. Existing System Analysis

### Current Data Flow (Members Tab)

1. `AppShell` hosts an `IndexedStack` with tab index 3 → `MembersTabContent`.
2. `MembersTabContent` reads `activeBandProvider` for the band ID, then calls `membersProvider.notifier.loadMembers(bandId)`.
3. `MembersNotifier` delegates to `MembersRepository.fetchMembersAndInvites()` which runs 4 queries (band_members, users, band_invitations, user_band_roles) and merges them into `MembersData`.
4. The UI renders a `CustomScrollView` with `SliverList` of `MemberCard` widgets.
5. Admin actions open `RoleManagementSheet` via `fadeSlideRoute`.
6. The "+ Add" action navigates to `BandFormScreen(mode: BandFormMode.edit)`.

### Key Patterns Identified

- **State management:** `Notifier` + `NotifierProvider` (GUARDRAILS-compliant).
- **Repository pattern:** Class with in-memory cache, explicit band_id requirement, `NoBandSelectedError` guard.
- **Card styling:** `_MemberCardTokens` defines rose-border pill badges, glow box-shadow, 24px card radius, 24px card padding.
- **Animation infra:** `AppDurations` (instant/fast/normal/medium/slow/entrance), `AppCurves` (ease/overshoot/slideIn/bounce/rubberband), `fadeSlideRoute`, `FadeSlideIn`, `AnimatedPressable`, `AnimatedCardPressable`.
- **Nav bar:** `kDefaultNavItems` list with `NavItem(icon, label)` and `NavTabIndex` constants. 4 fixed tabs.
- **Permission gating:** `currentUserPermissionsProvider` gates tab visibility in `AppShell`.
- **File sizes:** `MembersTabContent` = 384 lines (within Container target of 350, slightly over but acceptable).

### Venue/Contact Tables

No `venues`, `venue_contacts`, or `contacts` tables exist in the database. These must be created.

---

## 6. Proposed Solution

### Overview

Replace the monolithic `MembersTabContent` with a thin `ContactsTabContent` container widget that hosts a segmented toggle and switches between three child views:

1. **Band view** — wraps the existing member list (extracted into `BandMembersView`).
2. **Venues view** — new `VenuesView` backed by new `VenuesRepository` + `VenuesController`.
3. **Contacts view** — new `ContactsView` backed by new `ContactsRepository` + `ContactsController`.

### Design Decisions

**D1 — Extract, don't rewrite the Band view.** The current `MembersTabContent` body (the `_buildContent` method's sliver list, loading, error, and empty states) is extracted into a standalone `BandMembersView` widget. The existing `membersProvider`, `MembersRepository`, `MemberVM`, and all member widgets remain untouched.

**D2 — New feature folder: `lib/features/contacts/`.** Venues and Contacts are a new domain. The `contacts` feature folder houses:

- The `ContactsTabContent` container (segmented toggle + view switcher).
- Venues sub-domain (models, repository, controller, widgets).
- Contacts sub-domain (models, repository, controller, widgets).

The existing `lib/features/members/` folder is NOT moved or renamed. `BandMembersView` lives in `contacts/widgets/` and imports from `members/`.

**D3 — Segmented toggle is a reusable widget.** `SegmentedToggle` is a shared widget placed in `lib/shared/widgets/` since it could be reused elsewhere. It uses `AnimatedAlign` for the sliding indicator and `AnimatedDefaultTextStyle` for label transitions, driven by `AppDurations.fast` and `AppCurves.ease`.

**D4 — Pill badge title selector.** The title selector for venue contacts and standalone contacts is a new `TitlePillSelector` widget in `lib/features/contacts/widgets/`. It visually matches `_MemberCardTokens` pill styling (rose border, 16px radius, 12H/6V padding) but is single-select with a "Custom" entry option. Color transitions on selection use `AnimatedContainer` with `AppDurations.fast`.

**D5 — Three new Supabase tables: `venues`, `venue_contacts`, `contacts`.** All band-scoped via `band_id` foreign key, with RLS policies following the established `band_members` subquery pattern. No RPCs needed — direct table queries are sufficient since all operations are simple CRUD with band-scoped RLS.

**D6 — Nav bar label change only.** `kDefaultNavItems[3]` label changes from `'Members'` to `'Contacts'`. The icon may change to `AppIcons.contacts` if that icon exists, otherwise keep `AppIcons.users`. Tab count remains 4. `NavTabIndex.members` constant is preserved (renaming to `NavTabIndex.contacts` is out of scope to minimize diff surface).

**D7 — Animated view transitions.** The segmented toggle content area uses `AnimatedSwitcher` with a custom `FadeTransition` + slight `SlideTransition` (matching existing `FadeSlideIn` pattern) keyed by the active segment index. `AppDurations.normal` (250ms) with `AppCurves.slideIn`.

**D8 — Venue contact add/remove animation.** Uses `AnimatedList` for dynamic add/remove with `SizeTransition` + `FadeTransition` wrappers, driven by `AppDurations.normal`.

---

## 7. Database Impact

### New Tables (1 migration file)

**Migration file:** `supabase/migrations/20260410000000_contacts_venues_tables.sql`

#### `venues` table

```sql
CREATE TABLE public.venues (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  address    TEXT,
  city       TEXT,
  state      TEXT,
  phone      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_venues_band_id ON public.venues(band_id);

ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view venues" ON public.venues
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create venues" ON public.venues
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update venues" ON public.venues
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins only
CREATE POLICY "Admins can delete venues" ON public.venues
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venues.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role = 'admin'
    )
  );
```

#### `venue_contacts` table

```sql
CREATE TABLE public.venue_contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  venue_id   UUID NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  title      TEXT,
  phone      TEXT,
  email      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_venue_contacts_venue_id ON public.venue_contacts(venue_id);
CREATE INDEX idx_venue_contacts_band_id ON public.venue_contacts(band_id);

ALTER TABLE public.venue_contacts ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view venue contacts" ON public.venue_contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create venue contacts" ON public.venue_contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update venue contacts" ON public.venue_contacts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins and members
CREATE POLICY "Admins and members can delete venue contacts" ON public.venue_contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = venue_contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );
```

#### `contacts` table (standalone contacts)

```sql
CREATE TABLE public.contacts (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id    UUID NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  title      TEXT,
  phone      TEXT,
  email      TEXT,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_contacts_band_id ON public.contacts(band_id);

ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;

-- SELECT: any active band member
CREATE POLICY "Band members can view contacts" ON public.contacts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
    )
  );

-- INSERT: admins and members
CREATE POLICY "Admins and members can create contacts" ON public.contacts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- UPDATE: admins and members
CREATE POLICY "Admins and members can update contacts" ON public.contacts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );

-- DELETE: admins and members
CREATE POLICY "Admins and members can delete contacts" ON public.contacts
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.band_members bm
      WHERE bm.band_id = contacts.band_id
        AND bm.user_id = auth.uid()
        AND bm.status = 'active'
        AND bm.role IN ('admin', 'member')
    )
  );
```

### Updated_at Trigger

Add a shared `updated_at` auto-update trigger for all three tables:

```sql
-- Reusable trigger function (if not already present)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_venues_updated_at
  BEFORE UPDATE ON public.venues
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_venue_contacts_updated_at
  BEFORE UPDATE ON public.venue_contacts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER set_contacts_updated_at
  BEFORE UPDATE ON public.contacts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
```

### RLS Safety Analysis

- All RLS policies use subqueries against `band_members` (not self-referencing). **GUARDRAILS §4 compliant.**
- No SECURITY DEFINER RPCs are needed — all operations are standard CRUD within the user's band scope.
- `venue_contacts` carries its own `band_id` column (denormalized from `venues.band_id`) to enable direct RLS policy checks without cross-table joins in the policy itself. The application layer must ensure `venue_contacts.band_id` matches `venues.band_id` on insert.

### Migration Policy

**Required.** One migration file: `20260410000000_contacts_venues_tables.sql`

### Edge Function Deploy

**Not required.**

---

## 8. Flutter Architecture Changes

### State

| Provider           | Type                                                | Purpose                               |
| ------------------ | --------------------------------------------------- | ------------------------------------- |
| `venuesProvider`   | `NotifierProvider<VenuesNotifier, VenuesState>`     | Venues list + CRUD state              |
| `contactsProvider` | `NotifierProvider<ContactsNotifier, ContactsState>` | Standalone contacts list + CRUD state |

`membersProvider` is **not modified**. The Band view reuses it as-is.

### New Models

| Model          | File                                              | Fields                                                                                                      |
| -------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Venue`        | `lib/features/contacts/models/venue.dart`         | id, bandId, name, address, city, state, phone, notes, createdAt, updatedAt, contacts (List\<VenueContact\>) |
| `VenueContact` | `lib/features/contacts/models/venue_contact.dart` | id, venueId, bandId, name, title, phone, email, notes                                                       |
| `Contact`      | `lib/features/contacts/models/contact.dart`       | id, bandId, name, title, phone, email, notes, createdAt, updatedAt                                          |

All models use `factory Model.fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()` for Supabase serialization.

### New Repositories

| Repository           | File                                             | Methods                                                                                                                                                                                                          |
| -------------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `VenuesRepository`   | `lib/features/contacts/venues_repository.dart`   | `fetchVenues(bandId)`, `createVenue(bandId, data)`, `updateVenue(id, data)`, `deleteVenue(id)`, `addVenueContact(venueId, bandId, data)`, `updateVenueContact(contactId, data)`, `removeVenueContact(contactId)` |
| `ContactsRepository` | `lib/features/contacts/contacts_repository.dart` | `fetchContacts(bandId)`, `createContact(bandId, data)`, `updateContact(id, data)`, `deleteContact(id)`                                                                                                           |

Both repositories follow the `MembersRepository` pattern: explicit band_id guard, in-memory cache, `forceRefresh` option.

### New Controllers

| Controller         | File                                             |
| ------------------ | ------------------------------------------------ |
| `VenuesNotifier`   | `lib/features/contacts/venues_controller.dart`   |
| `ContactsNotifier` | `lib/features/contacts/contacts_controller.dart` |

Both follow the `MembersNotifier` pattern: `Notifier<XState>`, `build()` returns initial state, band-scoped load/refresh/reset methods.

### Widgets

| Widget               | File                                                      | Size Target | Purpose                                                                                                                             |
| -------------------- | --------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ContactsTabContent` | `lib/features/contacts/contacts_tab_content.dart`         | ≤350 lines  | Container: header, toggle, view switcher. Replaces `MembersTabContent` in `AppShell`.                                               |
| `BandMembersView`    | `lib/features/contacts/widgets/band_members_view.dart`    | ≤350 lines  | Extracted member list from `MembersTabContent._buildContent()`. Reuses `membersProvider`, `MemberCard`, loading/error/empty states. |
| `VenuesView`         | `lib/features/contacts/widgets/venues_view.dart`          | ≤350 lines  | Venue list with loading/error/empty states.                                                                                         |
| `VenueCard`          | `lib/features/contacts/widgets/venue_card.dart`           | ≤200 lines  | Card rendering venue name, address, phone, notes preview, contact count.                                                            |
| `VenueFormScreen`    | `lib/features/contacts/widgets/venue_form_screen.dart`    | ≤400 lines  | Full-screen create/edit form with nested venue contacts.                                                                            |
| `VenueContactBlock`  | `lib/features/contacts/widgets/venue_contact_block.dart`  | ≤200 lines  | Single venue contact form fields within `VenueFormScreen`.                                                                          |
| `ContactsView`       | `lib/features/contacts/widgets/contacts_view.dart`        | ≤350 lines  | Standalone contacts list with loading/error/empty states.                                                                           |
| `ContactCard`        | `lib/features/contacts/widgets/contact_card.dart`         | ≤200 lines  | Card rendering contact name, title, phone, email, notes preview.                                                                    |
| `ContactFormScreen`  | `lib/features/contacts/widgets/contact_form_screen.dart`  | ≤400 lines  | Full-screen create/edit form for standalone contacts.                                                                               |
| `TitlePillSelector`  | `lib/features/contacts/widgets/title_pill_selector.dart`  | ≤200 lines  | Horizontally scrollable, single-select pill badge for title. Predefined options + custom entry.                                     |
| `SegmentedToggle`    | `lib/shared/widgets/segmented_toggle.dart`                | ≤200 lines  | Reusable 3-way toggle with animated indicator.                                                                                      |
| `ContactsEmptyState` | `lib/features/contacts/widgets/contacts_empty_state.dart` | ≤100 lines  | Empty state for Contacts view.                                                                                                      |
| `VenuesEmptyState`   | `lib/features/contacts/widgets/venues_empty_state.dart`   | ≤100 lines  | Empty state for Venues view.                                                                                                        |

---

## 9. Files to Create

| File                                                            | Justification                                    |
| --------------------------------------------------------------- | ------------------------------------------------ |
| `supabase/migrations/20260410000000_contacts_venues_tables.sql` | New tables, indexes, RLS, triggers               |
| `lib/features/contacts/models/venue.dart`                       | Venue data model                                 |
| `lib/features/contacts/models/venue_contact.dart`               | VenueContact data model                          |
| `lib/features/contacts/models/contact.dart`                     | Contact data model                               |
| `lib/features/contacts/venues_repository.dart`                  | Supabase data access for venues + venue contacts |
| `lib/features/contacts/contacts_repository.dart`                | Supabase data access for standalone contacts     |
| `lib/features/contacts/venues_controller.dart`                  | Riverpod notifier for venues state               |
| `lib/features/contacts/contacts_controller.dart`                | Riverpod notifier for contacts state             |
| `lib/features/contacts/contacts_tab_content.dart`               | Container widget — header, toggle, view switcher |
| `lib/features/contacts/widgets/band_members_view.dart`          | Extracted member list (from `MembersTabContent`) |
| `lib/features/contacts/widgets/venues_view.dart`                | Venues list view                                 |
| `lib/features/contacts/widgets/venue_card.dart`                 | Venue card widget                                |
| `lib/features/contacts/widgets/venue_form_screen.dart`          | Venue create/edit form                           |
| `lib/features/contacts/widgets/venue_contact_block.dart`        | Single venue contact form block                  |
| `lib/features/contacts/widgets/contacts_view.dart`              | Contacts list view                               |
| `lib/features/contacts/widgets/contact_card.dart`               | Contact card widget                              |
| `lib/features/contacts/widgets/contact_form_screen.dart`        | Contact create/edit form                         |
| `lib/features/contacts/widgets/title_pill_selector.dart`        | Pill badge title selector                        |
| `lib/features/contacts/widgets/contacts_empty_state.dart`       | Empty state for Contacts view                    |
| `lib/features/contacts/widgets/venues_empty_state.dart`         | Empty state for Venues view                      |
| `lib/shared/widgets/segmented_toggle.dart`                      | Reusable animated segmented toggle               |

---

## 10. Files to Modify

| File                                                     | What Changes                                                                                 |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `lib/features/shell/app_shell.dart`                      | Replace `MembersTabContent()` with `ContactsTabContent()` at tab index 3. Update import.     |
| `lib/features/home/widgets/animated_bottom_nav_bar.dart` | Change `kDefaultNavItems[3]` label from `'Members'` to `'Contacts'`. Optionally update icon. |

---

## 11. Files Off-Limits

| File                                                      | Reason                                          |
| --------------------------------------------------------- | ----------------------------------------------- |
| `lib/main.dart`                                           | Init order must not change (GUARDRAILS §1)      |
| `lib/features/members/members_controller.dart`            | Existing members state management — reuse as-is |
| `lib/features/members/members_repository.dart`            | Existing members data access — reuse as-is      |
| `lib/features/members/member_vm.dart`                     | Existing member model — reuse as-is             |
| `lib/features/members/widgets/member_card.dart`           | Existing card widget — import, do not modify    |
| `lib/features/members/widgets/role_management_sheet.dart` | Existing overlay — reuse as-is                  |
| `lib/features/members/widgets/member_card_skeleton.dart`  | Existing skeleton — reuse as-is                 |
| `lib/features/members/widgets/members_empty_state.dart`   | Existing empty state — reuse as-is              |
| `lib/features/members/widgets/pending_invite_card.dart`   | Existing invite card — reuse as-is              |
| `lib/features/members/pending_invite_vm.dart`             | Existing model — reuse as-is                    |
| `lib/features/bands/active_band_controller.dart`          | Band isolation provider — must not change       |
| `lib/features/bands/band_form_screen.dart`                | Invite flow — must not change                   |
| `lib/app/theme/design_tokens.dart`                        | Design tokens — no additions needed             |
| `lib/app/theme/app_animations.dart`                       | Animation utilities — no additions needed       |

---

## 12. System Impact Map

| System                                 | Impact                                                                                                |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                            |
| Rehearsals                             | unaffected                                                                                            |
| Setlists / Catalog                     | unaffected                                                                                            |
| Members / RBAC                         | unaffected — Band view reuses existing providers as-is                                                |
| Auth / Session                         | unaffected                                                                                            |
| Routing                                | affected — tab index 3 widget swap (`MembersTabContent` → `ContactsTabContent`), nav bar label change |
| Notifications                          | unaffected                                                                                            |
| Platform (iOS / Android / Web / macOS) | affected — all platforms; no platform-specific code required                                          |

---

## 13. Regression Risk

**Level: LOW**

Rationale:

- The existing members data flow is not modified — only consumed from a new location.
- Auth, session, routing init, and initialization order are untouched.
- Database mutations are additive (new tables only; no existing table changes).
- The only modified production files are `app_shell.dart` (widget swap) and `animated_bottom_nav_bar.dart` (label change) — both minimal, low-risk edits.
- No shared notification/setlist/gig code paths are affected.

---

## 14. Engineer Task Breakdown

### Task 0 — Create Database Migration

**File:** `supabase/migrations/20260410000000_contacts_venues_tables.sql`

- Create `venues`, `venue_contacts`, `contacts` tables with all columns, indexes, RLS policies, and `updated_at` triggers as specified in §7.
- Run `supabase db push` to apply.

### Task 1 — Create Data Models

**Files:** `lib/features/contacts/models/venue.dart`, `venue_contact.dart`, `contact.dart`

- Implement `Venue`, `VenueContact`, `Contact` classes with `fromJson`/`toJson` factory constructors.
- `Venue.fromJson` must handle an embedded `venue_contacts` array (or empty list if not joined).

### Task 2 — Create Repositories

**Files:** `lib/features/contacts/venues_repository.dart`, `contacts_repository.dart`

- Follow `MembersRepository` pattern: explicit band_id guard, in-memory cache, `forceRefresh`.
- `VenuesRepository.fetchVenues()` uses `.select('*, venue_contacts(*)')` to eagerly load contacts.
- `ContactsRepository.fetchContacts()` uses `.select('*')` with `.eq('band_id', bandId)`.
- All write methods (`create`, `update`, `delete`) invalidate cache and return updated data.

### Task 3 — Create Controllers

**Files:** `lib/features/contacts/venues_controller.dart`, `contacts_controller.dart`

- Follow `MembersNotifier` pattern: `Notifier<VenuesState>` / `Notifier<ContactsState>`.
- State classes: `VenuesState` (venues list, isLoading, error), `ContactsState` (contacts list, isLoading, error).
- Methods: `load(bandId)`, `refresh(bandId)`, `create(...)`, `update(...)`, `delete(...)`, `reset()`.

### Task 4 — Create Shared SegmentedToggle

**File:** `lib/shared/widgets/segmented_toggle.dart`

- Generic 3-way segmented toggle widget.
- Props: `labels: List<String>`, `selectedIndex: int`, `onChanged: ValueChanged<int>`.
- Uses `AnimatedAlign` for sliding indicator with `AppDurations.fast` and `AppCurves.ease`.
- Indicator uses `AppColors.primary` background, labels use `AppColors.textPrimary` (active) / `AppColors.textSecondary` (inactive).
- Dark surface background matching `AppColors.surface`.

### Task 5 — Create TitlePillSelector

**File:** `lib/features/contacts/widgets/title_pill_selector.dart`

- Horizontally scrollable, single-select pill badge selector.
- Predefined options: `['Booking Agent', 'Sound', 'Owner', 'Manager']`.
- Custom entry: tapping "Custom" toggles a `TextField` inline.
- Pill styling matches `_MemberCardTokens`: rose border (1.5px), 16px radius, 12H/6V padding, `AppColors.primary` text.
- Selected pill: filled `AppColors.primary` background, white text.
- Uses `AnimatedContainer` with `AppDurations.fast` for selection transitions.

### Task 6 — Create VenueCard and ContactCard

**Files:** `lib/features/contacts/widgets/venue_card.dart`, `contact_card.dart`

- Card styling consistent with existing `MemberCard` visual language (rose border, glow shadow, 24px radius).
- `VenueCard`: name, formatted city+state, phone, notes preview (1-line truncated), contact count badge.
- `ContactCard`: name, title pill, phone, email, notes preview (1-line truncated).
- Both wrap in `AnimatedCardPressable` for tap feedback.
- Tappable phone/email rows use `url_launcher` (same pattern as `MemberCard`).

### Task 7 — Create VenueContactBlock

**File:** `lib/features/contacts/widgets/venue_contact_block.dart`

- Form block for a single venue contact within `VenueFormScreen`.
- Fields: Name (`TextField`), Title (`TitlePillSelector`), Phone, Email, Notes.
- Includes a remove button (trash icon, top-right).
- Wrapped in `SizeTransition` + `FadeTransition` for animated add/remove.

### Task 8 — Create Form Screens

**Files:** `lib/features/contacts/widgets/venue_form_screen.dart`, `contact_form_screen.dart`

- Full-screen Scaffold with AppBar (close button, title, save button).
- `VenueFormScreen`: fields for Name, Address, City, State, Phone, Notes; section for venue contacts using `AnimatedList` of `VenueContactBlock`; "+ Add Contact" button.
- `ContactFormScreen`: fields for Name, Title (`TitlePillSelector`), Phone, Email, Notes.
- Both support create mode (empty fields) and edit mode (pre-populated).
- Save triggers repository write, then pops with result.
- All `TextEditingController` and `FocusNode` instances properly disposed (GUARDRAILS §5).

### Task 9 — Create Empty States

**Files:** `lib/features/contacts/widgets/venues_empty_state.dart`, `contacts_empty_state.dart`

- Follow `MembersEmptyState` pattern.
- Brand-voice messages (roadie humor).
- Venues: "No venues yet — where's the gig at? 🎸"
- Contacts: "No contacts yet — who's your booking agent? 🎸"
- Both include an action button that triggers the "+ Add" flow.

### Task 10 — Create BandMembersView

**File:** `lib/features/contacts/widgets/band_members_view.dart`

- Extract the body of `MembersTabContent._buildContent()` into this widget.
- Receives `membersState` and `bandState` as constructor props.
- Reuses `MemberCard`, `MemberCardSkeleton`, `MembersEmptyState`.
- Includes pull-to-refresh, loading, error, and empty states.
- The invite action callback and role management callback are passed in as constructor params from `ContactsTabContent`.

### Task 11 — Create VenuesView and ContactsView

**Files:** `lib/features/contacts/widgets/venues_view.dart`, `contacts_view.dart`

- List views backed by `venuesProvider` / `contactsProvider`.
- Pull-to-refresh, loading, error, empty states.
- `SliverList` with `FadeSlideIn` staggered entrance for list items.
- Tap opens detail/edit form via `fadeSlideRoute`.

### Task 12 — Create ContactsTabContent

**File:** `lib/features/contacts/contacts_tab_content.dart`

- Replaces `MembersTabContent` in `AppShell`.
- Structure:
  - `HomeAppBar` (reused from existing — hamburger + band avatar).
  - Header row: "Contacts" title (left) + "+ Add" button (right). The "+ Add" button action changes based on selected segment.
  - `SegmentedToggle` with labels `['Band', 'Venues', 'Contacts']`.
  - `AnimatedSwitcher` body switching between `BandMembersView`, `VenuesView`, `ContactsView`.
- Loads venues/contacts data on segment change (lazy — only fetch when first switched to).
- Band view data loading delegated to `BandMembersView` (which reads `membersProvider`).

### Task 13 — Wire Into AppShell and Nav Bar

**Files:** `lib/features/shell/app_shell.dart`, `lib/features/home/widgets/animated_bottom_nav_bar.dart`

- `app_shell.dart`: Replace `const MembersTabContent()` with `const ContactsTabContent()` at index 3. Add import for `contacts_tab_content.dart`. Permission gating keeps `canViewMembers` check (same permission governs the full Contacts tab).
- `animated_bottom_nav_bar.dart`: Change `kDefaultNavItems[3]` from `NavItem(icon: AppIcons.users, label: 'Members')` to `NavItem(icon: AppIcons.users, label: 'Contacts')`.
- Remove the `MembersTabContent` import from `app_shell.dart` (it is now imported indirectly through `BandMembersView`).

### Task 14 — Band-Switch Reset

**File:** `lib/features/contacts/contacts_tab_content.dart`

- Listen to `activeBandProvider` changes. On band switch:
  - Call `venuesProvider.notifier.reset()` and `contactsProvider.notifier.reset()`.
  - Reset toggle to default segment (Band).
  - Reload data for active segment.
- This mirrors how `MembersTabContent` reloads on band change.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (runnable before `supabase db push`)

```sql
-- PRE-DEPLOY TEST 1: Verify venues table does not exist yet
SELECT NOT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'venues'
) AS venues_not_exists;
-- Expected: true

-- PRE-DEPLOY TEST 2: Verify venue_contacts table does not exist yet
SELECT NOT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'venue_contacts'
) AS venue_contacts_not_exists;
-- Expected: true

-- PRE-DEPLOY TEST 3: Verify contacts table does not exist yet
SELECT NOT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'contacts'
) AS contacts_not_exists;
-- Expected: true

-- PRE-DEPLOY TEST 4: Verify band_members table exists (dependency for RLS)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'band_members'
) AS band_members_exists;
-- Expected: true

-- PRE-DEPLOY TEST 5: Verify bands table exists (FK dependency)
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'bands'
) AS bands_exists;
-- Expected: true
```

### Tier 2 — Post-deployment (run after `supabase db push`)

```sql
-- POST-DEPLOY TEST 1: Verify venues table exists with expected columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'venues'
ORDER BY ordinal_position;
-- Expected: id (uuid), band_id (uuid), name (text), address (text), city (text),
-- state (text), phone (text), notes (text), created_at (timestamp with time zone),
-- updated_at (timestamp with time zone)

-- POST-DEPLOY TEST 2: Verify venue_contacts table exists with expected columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'venue_contacts'
ORDER BY ordinal_position;
-- Expected: id (uuid), venue_id (uuid), band_id (uuid), name (text), title (text),
-- phone (text), email (text), notes (text), created_at (timestamp with time zone),
-- updated_at (timestamp with time zone)

-- POST-DEPLOY TEST 3: Verify contacts table exists with expected columns
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'contacts'
ORDER BY ordinal_position;
-- Expected: id (uuid), band_id (uuid), name (text), title (text), phone (text),
-- email (text), notes (text), created_at (timestamp with time zone),
-- updated_at (timestamp with time zone)

-- POST-DEPLOY TEST 4: Verify RLS is enabled on all three tables
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public' AND tablename IN ('venues', 'venue_contacts', 'contacts');
-- Expected: all three rows show rowsecurity = true

-- POST-DEPLOY TEST 5: Verify RLS policies exist for venues
SELECT policyname FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'venues'
ORDER BY policyname;
-- Expected: 4 policies (select, insert, update, delete)

-- POST-DEPLOY TEST 6: Verify RLS policies exist for venue_contacts
SELECT policyname FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'venue_contacts'
ORDER BY policyname;
-- Expected: 4 policies (select, insert, update, delete)

-- POST-DEPLOY TEST 7: Verify RLS policies exist for contacts
SELECT policyname FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'contacts'
ORDER BY policyname;
-- Expected: 4 policies (select, insert, update, delete)

-- POST-DEPLOY TEST 8: Verify updated_at triggers exist
SELECT trigger_name, event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('venues', 'venue_contacts', 'contacts')
ORDER BY event_object_table;
-- Expected: one trigger per table (set_venues_updated_at, set_venue_contacts_updated_at, set_contacts_updated_at)

-- POST-DEPLOY TEST 9: Verify indexes exist
SELECT indexname FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN ('idx_venues_band_id', 'idx_venue_contacts_venue_id', 'idx_venue_contacts_band_id', 'idx_contacts_band_id');
-- Expected: 4 rows

-- POST-DEPLOY TEST 10: Verify no self-referencing RLS (GUARDRAILS §4 compliance)
-- Check that no policy on venues references the venues table itself
SELECT policyname, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'venues'
  AND qual::text LIKE '%venues%';
-- Expected: 0 rows (policies reference band_members, not venues)
```

### Flutter Verification

| Check                                                 | How to verify                                                               |
| ----------------------------------------------------- | --------------------------------------------------------------------------- |
| `flutter analyze` returns 0 errors                    | Run `flutter analyze` after all tasks complete                              |
| Tab label reads "Contacts"                            | Visual inspection on all platforms                                          |
| Band segment shows existing member list unchanged     | Compare member list before/after the change                                 |
| Venues segment: create, edit, delete venue            | Manual test on each platform                                                |
| Venues segment: add/remove venue contacts             | Verify animated add/remove in venue form                                    |
| Contacts segment: create, edit, delete contact        | Manual test on each platform                                                |
| Title pill selector: select predefined + enter custom | Verify single-select behavior, custom entry                                 |
| Segmented toggle animation                            | Verify sliding indicator + content fade/slide                               |
| Band switch resets contacts/venues state              | Switch bands, verify data reloads                                           |
| Permission gating preserved                           | Log in as contributor with `canViewMembers: false`, verify restricted state |
| Pull-to-refresh works on all three views              | Pull down on each view                                                      |
| No existing member functionality broken               | Full existing member flow: view list, manage role, invite                   |

---

## 16. QA Regression Areas

| Area              | What to test                                                                                               |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| Members list      | Verify existing member cards, role badges, admin actions, role management sheet — all unchanged            |
| Invite flow       | Verify "+ Add" in Band view opens `BandFormScreen` in edit mode — unchanged                                |
| Band switching    | Verify all three views reset and reload correctly on band switch                                           |
| Permission gating | Verify contributor with `canViewMembers: false` sees restricted state for entire Contacts tab              |
| Bottom nav        | Verify 4 tabs still appear; label reads "Contacts"; spring animation still works                           |
| Other tabs        | Verify Dashboard, Setlists, Calendar tabs are completely unaffected                                        |
| Gig venue field   | Verify existing gig venue text field is unaffected (it writes to `gigs.venue`, not the new `venues` table) |

---

## 17. Rollout / Migration Strategy

1. **Database first:** Deploy migration `20260410000000_contacts_venues_tables.sql` via `supabase db push`. Verify all Tier 2 tests pass.
2. **Client deploy:** Build and deploy Flutter web (`flutter build web --release` → Vercel). Publish iOS/Android builds.
3. **No feature flag needed:** The new Venues and Contacts views start empty per-band. No data migration from existing tables is required. Band view is backward-compatible (same provider, same data).
4. **Rollback:** If issues arise, reverting the Flutter client to the previous version restores the Members-only tab. The empty database tables are harmless and can be dropped in a subsequent migration if needed.

---

## 18. Out of Scope

- Linking venues to gigs (associating a venue record with a gig's venue field) — future feature.
- Importing contacts from device address book.
- Venue map/location display.
- Contact photo/avatar support.
- Searching or filtering within venue/contact lists.
- Exporting contacts.
- Renaming `NavTabIndex.members` constant to `NavTabIndex.contacts` (minimal diff principle).
- Modifying `MembersTabContent` — it is replaced, not edited. It may be deprecated/removed in a follow-up cleanup task.
- Notification triggers for venue/contact changes.
- Modifying the `gigs.venue` text field to reference the new `venues` table.
