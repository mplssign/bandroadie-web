# ARCHITECT_PLAN

## 1) Feature Slug

`feature/potential-rehearsal-availability`

## 2) Problem Summary

Potential gigs have a complete member availability (RSVP) system: members can respond yes/no to potential gigs, responses are stored in `gig_responses`, a prompt modal appears when a member first opens the app after a potential gig is created, and availability counts are displayed on the dashboard. Potential rehearsals (added in `feature/rehearsal-potential-toggle`) have **none of this infrastructure**. There is no response storage, no prompt system, no availability display, and no way for members to RSVP to potential rehearsals.

This feature brings potential rehearsals to full parity with potential gigs across every layer: database, models, repositories, services, UI, and integration.

## 3) Root Cause

**Primary root cause:** Complete absence of rehearsal availability infrastructure.

The rehearsal domain has `is_potential` support (column, model field, UI toggle, persistence) from the prior feature, but no member response system. Specifically:

- **Database gap:** No `rehearsal_responses` table exists to store member yes/no responses.
- **Model gap:** No `RehearsalResponse` domain model.
- **Repository gap:** No `RehearsalResponseRepository` for data access.
- **Service gap:** No `PotentialRehearsalPromptService` to orchestrate app-open prompts.
- **UI gap:** `RehearsalCard` does not display availability counts (yes/no/not responded).
- **Integration gap:** No prompt check integration in `home_tab_content.dart` for rehearsals.

**Secondary observation:** The existing gig pattern has an implementation gap. The `potentialGigResponseSummariesProvider` loads availability data but `PotentialGigCard` does not display it. The feature input's statement that "availability counts are shown on the potential gig card" describes the **desired end state**, not current state. This feature will fix both the gig display gap and implement the full rehearsal pattern.

**Confidence: HIGH**

Direct code observation confirms the complete absence of rehearsal response components. The gig pattern exists as a working reference that has been validated through production use.

## 4) Reference Docs Consulted

Required by Architect phase sequence:

- `docs/reference/architecture/database_schema.md` — confirmed `gig_responses` table structure (67 rows), confirmed no `rehearsal_responses` table exists
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — general system architecture and event management overview

No dedicated RSVP/availability domain docs exist in `docs/reference/`.

## 5) Existing System Analysis

### Current data flow (gigs — reference pattern)

**Database layer:**

- Table: `gig_responses` (id, gig_id, user_id, response [yes/no], gig_date_id, created_at, updated_at)
- RLS policies enforce band-scoped access via join to gigs → band_members
- RPC helper: `check_gig_response_access()` (referenced in schema doc)

**Model layer:**

- `lib/app/models/gig_response.dart`
- Enum: `GigResponseType { yes, no }`
- Fields: id, gigId, userId, response, createdAt, updatedAt
- Methods: fromJson, toJson, isYes, isNo

**Repository layer:**

- `lib/features/gigs/gig_response_repository.dart`
- Class: `GigResponseRepository` with methods:
  - `fetchPendingPotentialGigs()` — returns gigs where user hasn't responded
  - `fetchUserResponse()` — gets user's response for a specific gig
  - `upsertResponse()` — saves/updates response with retry logic
  - `fetchGigResponseSummary()` — returns yesCount/noCount/notRespondedCount for one gig
  - `fetchAllMemberResponses()` — returns map of userId → response for all members
  - `fetchMultipleGigResponseSummaries()` — bulk summary fetch for dashboard
- Error handling: `GigResponseError` with user-friendly messages and retry logic
- Summary model: `GigResponseSummary` (yesCount, noCount, notRespondedCount, totalMembers)
- Pending model: `PendingPotentialGig` (gigId, bandId, name, date, times, location)

**Provider layer:**

- `gigResponseRepositoryProvider` — singleton repository
- `potentialGigResponseSummariesProvider` — FutureProvider that watches `gigProvider.potentialGigs` and `activeBandIdProvider`, fetches summaries for all potential gigs, invalidated by EventEditorDrawer after updates

**Prompt service layer:**

- `lib/features/gigs/potential_gig_prompt_service.dart`
- Class: `PotentialGigPromptNotifier` (extends Notifier)
- State: `PotentialGigPromptState` (isShowingPrompt, isChecking, pendingCount)
- Method: `checkAndShowPendingPrompts(BuildContext)` — fetches pending gigs, shows modal sequentially
- Lock mechanism: `_isShowingModal` prevents duplicate modals
- Modal: `AvailabilityPromptModal.show()` — blocking UI, yes/no buttons, saves response on submit
- Provider: `potentialGigPromptProvider`

**UI integration:**

- `lib/features/home/home_tab_content.dart`:
  - Watches `potentialGigResponseSummariesProvider` → extracts `responseSummaries` map
  - Calls `ref.read(potentialGigPromptProvider.notifier).checkAndShowPendingPrompts(context)` on app resume and after band switch
  - Invalidates summaries provider after prompt completes
- `lib/features/home/widgets/potential_gig_card.dart`:
  - Currently displays: gig name, location, date/time, animated gradient
  - **Does NOT display availability counts** — implementation gap
- Modal widget: `lib/features/gigs/widgets/availability_prompt_modal.dart` (referenced but not fully inspected)

### Current data flow (rehearsals — target domain)

**Database layer:**

- Table: `rehearsals` has `is_potential BOOLEAN NOT NULL DEFAULT FALSE` (added in prior feature)
- **No `rehearsal_responses` table**

**Model layer:**

- `lib/app/models/rehearsal.dart` has `isPotential` field

**Repository layer:**

- `lib/features/events/events_repository.dart` persists `is_potential` on create/update
- **No rehearsal response repository**

**Controller layer:**

- `lib/features/rehearsals/rehearsal_controller.dart` — `RehearsalState` has potential/confirmed categorization (added in prior feature)

**Prompt service layer:**

- **No prompt service**

**UI layer:**

- `lib/features/home/widgets/rehearsal_card.dart` — displays rehearsal info (date, time, location, setlist)
- **No availability display**
- Rendered in same horizontal scroll area as potential gigs in `home_tab_content.dart`

**Integration:**

- `home_tab_content.dart` renders potential rehearsals alongside potential gigs in `_buildHorizontalPotentialEvents()`
- **No prompt check**, **no response summaries loaded**

## 6) Proposed Solution

Implement rehearsal availability system by creating **parallel components** that mirror the proven gig RSVP pattern. Enhance both gig and rehearsal cards to display availability counts.

### Database layer (new migration)

1. Create `rehearsal_responses` table:
   - Columns: id (uuid PK), rehearsal_id (uuid FK → rehearsals), user_id (uuid FK → auth.users), response (text CHECK 'yes'/'no'), created_at (timestamptz), updated_at (timestamptz)
   - Unique constraint: (rehearsal_id, user_id) — one response per member per rehearsal
   - No `rehearsal_date_id` column (rehearsals don't support multi-date like gigs)
2. Enable RLS on `rehearsal_responses`
3. Add RLS policies:
   - SELECT: band members can view responses for rehearsals in their bands
   - INSERT: users can insert their own responses for rehearsals in their bands
   - UPDATE: users can update their own responses
   - DELETE: users can delete their own responses
4. Create RLS helper function: `check_rehearsal_response_access(p_rehearsal_id uuid, p_user_id uuid)` RETURNS boolean — checks if user is active member of rehearsal's band

### Model layer (new file)

5. Create `lib/app/models/rehearsal_response.dart`:
   - Mirror `GigResponse` structure
   - Enum: `RehearsalResponseType { yes, no }`
   - Class: `RehearsalResponse` with fields (id, rehearsalId, userId, response, createdAt, updatedAt)
   - Methods: fromJson, toJson, isYes, isNo

### Repository layer (new file)

6. Create `lib/features/rehearsals/rehearsal_response_repository.dart`:
   - Mirror `GigResponseRepository` structure
   - Class: `RehearsalResponseRepository` with methods:
     - `fetchPendingPotentialRehearsals()` — returns rehearsals where user hasn't responded
     - `fetchUserResponse()` — gets user's response for a specific rehearsal
     - `upsertResponse()` — saves/updates response with retry logic (same error handling pattern)
     - `fetchRehearsalResponseSummary()` — returns yesCount/noCount/notRespondedCount
     - `fetchAllMemberResponses()` — returns map of userId → response
     - `fetchMultipleRehearsalResponseSummaries()` — bulk fetch for dashboard
   - Error class: `RehearsalResponseError` (mirror GigResponseError)
   - Summary model: `RehearsalResponseSummary` (mirror GigResponseSummary)
   - Pending model: `PendingPotentialRehearsal` (mirror PendingPotentialGig)
   - Provider: `rehearsalResponseRepositoryProvider`
   - Provider: `potentialRehearsalResponseSummariesProvider` (FutureProvider, watches `rehearsalProvider.potentialRehearsals` and `activeBandIdProvider`)

### Prompt service layer (new file)

7. Create `lib/features/rehearsals/potential_rehearsal_prompt_service.dart`:
   - Mirror `PotentialGigPromptService` structure
   - Class: `PotentialRehearsalPromptNotifier` (extends Notifier)
   - State: `PotentialRehearsalPromptState` (mirror gig state)
   - Method: `checkAndShowPendingPrompts(BuildContext)` — fetches pending rehearsals, shows modal sequentially
   - Reuse existing `AvailabilityPromptModal` widget (should be generic enough to handle both gigs and rehearsals)
   - Provider: `potentialRehearsalPromptProvider`

### UI layer modifications

8. **Modify `lib/features/home/widgets/rehearsal_card.dart`:**
   - Add optional `responseSummary` parameter (RehearsalResponseSummary?)
   - When `rehearsal.isPotential == true` AND `responseSummary != null`, display availability row at bottom:
     - Format: "✓ X available • ✗ Y unavailable • ? Z not responded"
     - Style: white text, smaller font (14-15px), single line
     - Position: above existing setlist info or replace bottom row content
   - When not potential or no summary, render as before

9. **Modify `lib/features/home/widgets/potential_gig_card.dart`:**
   - Add optional `responseSummary` parameter (GigResponseSummary?)
   - When `responseSummary != null`, display availability row at bottom (same format as rehearsal card)
   - This **fixes the gig implementation gap** where summaries are loaded but not displayed

10. **Modify `lib/features/home/home_tab_content.dart`:**
    - Watch `potentialRehearsalResponseSummariesProvider` alongside gig summaries
    - Extract rehearsal summaries: `Map<String, RehearsalResponseSummary> rehearsalResponseSummaries`
    - Call `ref.read(potentialRehearsalPromptProvider.notifier).checkAndShowPendingPrompts(context)` in same locations as gig prompt:
      - On app resume (WidgetsBindingObserver didChangeAppLifecycleState)
      - After band switch
    - Invalidate `potentialRehearsalResponseSummariesProvider` after prompt completes
    - Pass both `responseSummaries` (gigs) and `rehearsalResponseSummaries` to `_buildHorizontalPotentialEvents()`
    - Update `_buildHorizontalPotentialEvents()` to accept both summary maps and pass to card constructors

### Must not change

- `lib/main.dart` — off-limits, init order cannot change
- `lib/features/gigs/potential_gig_prompt_service.dart` — off-limits, create parallel instead
- `lib/features/gigs/gig_response_repository.dart` — off-limits, create parallel instead
- Notification trigger behavior — CREATE-only must remain unchanged
- No copying of anti-patterns: no `_lastLoadedBandId` + `Future.microtask`, no silent `catch (e) { return []; }`

## 7) Database Impact

**Database: affected**

**Migrations: required**

**New migration:** `supabase/migrations/<timestamp>_add_rehearsal_responses.sql`

Migration content must include:

1. CREATE TABLE rehearsal_responses with all columns and constraints
2. CREATE UNIQUE INDEX on (rehearsal_id, user_id)
3. ALTER TABLE ... ENABLE ROW LEVEL SECURITY
4. CREATE POLICY for SELECT (band members can view)
5. CREATE POLICY for INSERT (users can insert own responses)
6. CREATE POLICY for UPDATE (users can update own responses)
7. CREATE POLICY for DELETE (users can delete own responses)
8. CREATE FUNCTION check_rehearsal_response_access() RETURNS boolean SECURITY DEFINER SET search_path = public
9. Add comments on table and columns for documentation

**RLS policies:**
Band-scoped access enforced via join: `rehearsal_responses` → `rehearsals` → `band_members` (filter on status='active')

Policies must **NOT** query the table they protect (no self-referencing — guardrails rule). Use SECURITY DEFINER helper function pattern as in gig_responses.

**RPC functions:**

- `check_rehearsal_response_access(p_rehearsal_id uuid, p_user_id uuid)` — new helper function
- Signature mirrors gig pattern
- Returns TRUE if user is active member of rehearsal's band
- Used in RLS policies via: `USING (check_rehearsal_response_access(rehearsal_id, auth.uid()))`

**Triggers:**

- None required for this feature
- Existing notification triggers remain unchanged (CREATE-only behavior preserved)

**No self-referencing RLS:** Confirmed — policies will use helper function, not direct table query.

**Migration rollback safety:**

- Additive only (new table, no schema changes to existing tables)
- Can be rolled back with `DROP TABLE rehearsal_responses CASCADE;`

## 8) Flutter Architecture Changes

**No new architecture layers.**

Existing patterns:

- Feature-first structure: new files go in `lib/features/rehearsals/`
- Riverpod state management: use `Notifier` + `NotifierProvider` (not deprecated StateNotifier)
- Repository pattern: new repository for data access
- Provider invalidation: same pattern as gig responses

State management:

- New providers: `rehearsalResponseRepositoryProvider`, `potentialRehearsalResponseSummariesProvider`, `potentialRehearsalPromptProvider`
- All follow existing Riverpod conventions
- No new state abstractions

Widget modifications:

- `RehearsalCard` gains optional parameter, conditional rendering
- `PotentialGigCard` gains optional parameter, conditional rendering
- No new widget abstractions needed (reuse AvailabilityPromptModal)

Data flow:

- Mirrors gig pattern exactly: repository → provider → notifier → modal → save → invalidate → refresh
- Band isolation maintained via `activeBandIdProvider` dependency

## 9) Files to Create

| File                                                              | Justification                                                                                                        |
| ----------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/<timestamp>_add_rehearsal_responses.sql`     | Required to create persistence layer for rehearsal responses. No existing table.                                     |
| `lib/app/models/rehearsal_response.dart`                          | Required domain model for type-safe response handling. Mirrors GigResponse proven pattern.                           |
| `lib/features/rehearsals/rehearsal_response_repository.dart`      | Required data access layer. Replicates GigResponseRepository pattern with rehearsal-specific queries.                |
| `lib/features/rehearsals/potential_rehearsal_prompt_service.dart` | Required prompt orchestration. Mirrors PotentialGigPromptService — manages app-open check, sequential modals, state. |

Total: **4 new files**. All justified by feature scope and proven pattern replication.

## 10) Files to Modify

| File                                                | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/home/widgets/rehearsal_card.dart`     | Add optional `responseSummary` parameter. Conditionally render availability row (yes/no/not responded counts) when `isPotential == true` and summary provided. Format: "✓ X available • ✗ Y unavailable • ? Z not responded". White text, 14-15px, bottom position. No changes to non-potential rendering.                                                                                                                                                                                        |
| `lib/features/home/widgets/potential_gig_card.dart` | Add optional `responseSummary` parameter. Conditionally render availability row (same format as rehearsal card). Fixes gig implementation gap — summaries are already loaded but not displayed.                                                                                                                                                                                                                                                                                                   |
| `lib/features/home/home_tab_content.dart`           | (1) Watch `potentialRehearsalResponseSummariesProvider`. (2) Call `potentialRehearsalPromptProvider.notifier.checkAndShowPendingPrompts(context)` on app resume and after band switch (same locations as gig check). (3) Invalidate rehearsal summaries provider after prompt. (4) Pass both gig and rehearsal summary maps to `_buildHorizontalPotentialEvents()`. (5) Update card constructors in item builder to accept and pass summaries. Estimated ~50-80 lines of additions/modifications. |

Total: **3 files modified**. All changes are localized, additive, and follow existing patterns.

## 11) Files Off-Limits

| File                                                  | Reason                                                                                  |
| ----------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `lib/main.dart`                                       | Init order must not change (guardrails).                                                |
| `lib/features/gigs/potential_gig_prompt_service.dart` | Explicitly forbidden by feature constraints. Create parallel service for rehearsals.    |
| `lib/features/gigs/gig_response_repository.dart`      | Explicitly forbidden by feature constraints. Create parallel repository for rehearsals. |
| All notification edge function files                  | CREATE-only trigger behavior must remain unchanged (feature constraint).                |
| All database trigger SQL files                        | Notification triggers off-limits.                                                       |

## 12) System Impact Map

| System                                 | Impact                                                                              |
| -------------------------------------- | ----------------------------------------------------------------------------------- |
| Gigs                                   | **affected** (PotentialGigCard gains availability display — implementation gap fix) |
| Rehearsals                             | **affected** (full RSVP system added — primary scope)                               |
| Setlists / Catalog                     | unaffected                                                                          |
| Members / RBAC                         | unaffected (reuses existing band membership for authorization)                      |
| Auth / Session                         | unaffected                                                                          |
| Routing                                | unaffected                                                                          |
| Notifications                          | unaffected (CREATE-only trigger behavior preserved)                                 |
| Platform (iOS / Android / Web / macOS) | **affected** (new prompts on app open, new UI elements on cards — all platforms)    |

## 13) Regression Risk

**Risk Level: MEDIUM**

**Rationale:**

**Factors increasing risk:**

- Multi-layer change: database (new table + RLS) → model → repository → service → UI integration → cross-platform
- Touches home dashboard integration and app lifecycle hooks (app resume/band switch)
- New RLS policies — potential for permission errors if policies don't match gig pattern exactly
- Prompt modal reuse — AvailabilityPromptModal might need rehearsal-specific copy or handling
- Cross-platform UI changes (iOS, Android, Web, macOS) — card layout and prompt behavior must work everywhere

**Factors reducing risk (preventing HIGH):**

- **Pure additive feature** — no existing rehearsal RSVP to break, potential rehearsals currently have zero response functionality
- **Proven pattern replication** — gig RSVP is battle-tested in production with 67 rows in gig_responses
- **Parallel implementation** — gig files remain untouched, no risk of breaking existing gig RSVP
- **No architectural changes** — uses existing Riverpod patterns, feature-first structure, repository pattern
- **No auth/routing/init changes** — main.dart off-limits, no session/auth modifications
- **No database mutations of existing data** — additive table only, no UPDATE/DELETE on existing tables
- **Band isolation pattern preserved** — uses activeBandIdProvider consistently
- **Notification behavior unchanged** — CREATE-only triggers preserved per constraint

**Risk not LOW because:** Multi-layer change spanning database to UI with lifecycle integration is inherently moderate risk even when replicating proven patterns.

## 14) Engineer Task Breakdown

Execute in strict order. Mark complete only when verified working.

1. **Database migration:**
   - Write `supabase/migrations/<timestamp>_add_rehearsal_responses.sql`
   - Include: table creation, RLS enable, unique constraint, 4 policies, helper function
   - Test locally before committing

2. **Domain model:**
   - Create `lib/app/models/rehearsal_response.dart`
   - Implement: RehearsalResponseType enum, RehearsalResponse class, fromJson/toJson, isYes/isNo
   - Unit test: fromJson/toJson round-trip with synthetic data (pure Dart, no DB dependency)

3. **Repository layer:**
   - Create `lib/features/rehearsals/rehearsal_response_repository.dart`
   - Implement: RehearsalResponseRepository with all 6 methods
   - Implement: RehearsalResponseError, RehearsalResponseSummary, PendingPotentialRehearsal
   - Implement: rehearsalResponseRepositoryProvider
   - Implement: potentialRehearsalResponseSummariesProvider (FutureProvider, watch rehearsalProvider + activeBandId)
   - Manual test: insert test response via Supabase dashboard, verify fetch methods return correct data

4. **Prompt service layer:**
   - Create `lib/features/rehearsals/potential_rehearsal_prompt_service.dart`
   - Implement: PotentialRehearsalPromptState, PotentialRehearsalPromptNotifier, provider
   - Implement: checkAndShowPendingPrompts() method
   - Verify: AvailabilityPromptModal can handle rehearsal data (might need minor copy/type adjustments)
   - If needed: create rehearsal-specific modal variant OR make existing modal fully generic

5. **UI modifications (cards):**
   - Modify `lib/features/home/widgets/rehearsal_card.dart`:
     - Add optional `responseSummary` parameter
     - Add conditional availability display row (bottom position)
     - Test: render with/without summary, potential/confirmed states
   - Modify `lib/features/home/widgets/potential_gig_card.dart`:
     - Add optional `responseSummary` parameter
     - Add conditional availability display row (same format)
     - Test: render with/without summary

6. **Integration (home dashboard):**
   - Modify `lib/features/home/home_tab_content.dart`:
     - Watch `potentialRehearsalResponseSummariesProvider`
     - Call rehearsal prompt check in app resume and band switch handlers
     - Invalidate rehearsal summaries after prompt
     - Pass both summary maps to `_buildHorizontalPotentialEvents()`
     - Update card constructors to accept and pass summaries
   - Test: potential rehearsal appears → app close → app open → prompt modal shows

7. **Manual end-to-end testing:**
   - Create potential rehearsal
   - Close and reopen app → verify prompt appears
   - Respond yes → verify response saves
   - Verify availability counts appear on rehearsal card
   - Verify prompt doesn't reappear after response
   - Test with multiple pending rehearsals → verify sequential prompts
   - Test gig pattern still works → verify gig card now shows availability (regression check)
   - Test band switch → verify prompts refresh correctly

8. **Cross-platform smoke test:**
   - Test on Web, iOS, Android, macOS
   - Verify prompt modal renders correctly on all platforms
   - Verify card layout with availability row doesn't break on different screen sizes

## 15) Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

These tests run **BEFORE** applying the migration. They verify supporting code without touching the new table.

**-- PRE-DEPLOY TEST 1:** Flutter static analysis

```bash
flutter analyze lib/app/models/rehearsal_response.dart
flutter analyze lib/features/rehearsals/rehearsal_response_repository.dart
flutter analyze lib/features/rehearsals/potential_rehearsal_prompt_service.dart
flutter analyze lib/features/home/widgets/rehearsal_card.dart
flutter analyze lib/features/home/widgets/potential_gig_card.dart
flutter analyze lib/features/home/home_tab_content.dart
```

Expected: 0 errors, 0 warnings. Any issues must be fixed before deployment.

**-- PRE-DEPLOY TEST 2:** Unit test RehearsalResponse model (pure Dart, no DB)

```dart
// test/app/models/rehearsal_response_test.dart
void main() {
  test('RehearsalResponse.fromJson parses correctly', () {
    final json = {
      'id': '123e4567-e89b-12d3-a456-426614174000',
      'rehearsal_id': '123e4567-e89b-12d3-a456-426614174001',
      'user_id': '123e4567-e89b-12d3-a456-426614174002',
      'response': 'yes',
      'created_at': '2026-05-07T12:00:00Z',
      'updated_at': '2026-05-07T12:00:00Z',
    };
    final response = RehearsalResponse.fromJson(json);
    expect(response.response, RehearsalResponseType.yes);
    expect(response.isYes, true);
  });

  test('RehearsalResponse.toJson serializes correctly', () {
    final response = RehearsalResponse(
      id: '123e4567-e89b-12d3-a456-426614174000',
      rehearsalId: '123e4567-e89b-12d3-a456-426614174001',
      userId: '123e4567-e89b-12d3-a456-426614174002',
      response: RehearsalResponseType.no,
      createdAt: DateTime.parse('2026-05-07T12:00:00Z'),
      updatedAt: DateTime.parse('2026-05-07T12:00:00Z'),
    );
    final json = response.toJson();
    expect(json['response'], 'no');
  });
}
```

Run: `flutter test test/app/models/rehearsal_response_test.dart`
Expected: All tests pass.

**-- PRE-DEPLOY TEST 3:** Verify no notification code changed

```bash
git diff --name-only | grep -i "notification\|trigger" || echo "No notification files changed"
```

Expected: Output "No notification files changed" OR list only unrelated files.

**-- PRE-DEPLOY TEST 4:** Verify gig RSVP files untouched

```bash
git diff --name-only | grep "gig_response_repository.dart\|potential_gig_prompt_service.dart" && echo "ERROR: Off-limits files modified" || echo "Off-limits files safe"
```

Expected: "Off-limits files safe"

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

These tests run **AFTER** the migration is applied. They verify the database objects and full integration.

**-- POST-DEPLOY TEST 1:** Verify rehearsal_responses table exists

```sql
-- Run in Supabase SQL Editor
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name='rehearsal_responses'
ORDER BY ordinal_position;
```

Expected result: 6 rows (id, rehearsal_id, user_id, response, created_at, updated_at)

- `response` type: text
- `is_nullable`: NO for all columns

**-- POST-DEPLOY TEST 2:** Verify unique constraint exists

```sql
-- Run in Supabase SQL Editor
SELECT
  constraint_name,
  constraint_type
FROM information_schema.table_constraints
WHERE table_schema='public'
  AND table_name='rehearsal_responses'
  AND constraint_type IN ('UNIQUE', 'PRIMARY KEY');
```

Expected: At least 2 rows — one PRIMARY KEY (id), one UNIQUE (rehearsal_id, user_id combination)

**-- POST-DEPLOY TEST 3:** Verify RLS enabled and policies exist

```sql
-- Run in Supabase SQL Editor
-- Check RLS enabled
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname='public' AND tablename='rehearsal_responses';
-- Expected: rowsecurity = true

-- Check policies exist
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname='public' AND tablename='rehearsal_responses'
ORDER BY policyname;
-- Expected: 4 policies (SELECT, INSERT, UPDATE, DELETE)
```

**-- POST-DEPLOY TEST 4:** Verify helper function exists

```sql
-- Run in Supabase SQL Editor
SELECT
  proname,
  prosrc
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND proname = 'check_rehearsal_response_access';
```

Expected: 1 row returned, `prosrc` contains band_members join logic

**-- POST-DEPLOY TEST 5:** Test INSERT with real band/rehearsal (integration test)

```sql
-- Run in Supabase SQL Editor as authenticated user
-- PREREQUISITE: Must have a test band and a potential rehearsal in database

DO $$
DECLARE
  v_band_id uuid;
  v_user_id uuid;
  v_rehearsal_id uuid;
  v_response_id uuid;
BEGIN
  -- Get current authenticated user
  v_user_id := auth.uid();

  -- Get a test band where user is a member
  SELECT band_id INTO v_band_id
  FROM band_members
  WHERE user_id = v_user_id AND status = 'active'
  LIMIT 1;

  IF v_band_id IS NULL THEN
    RAISE EXCEPTION 'User is not a member of any band';
  END IF;

  -- Get or create a potential rehearsal in that band
  SELECT id INTO v_rehearsal_id
  FROM rehearsals
  WHERE band_id = v_band_id AND is_potential = true
  LIMIT 1;

  IF v_rehearsal_id IS NULL THEN
    -- Create test rehearsal
    INSERT INTO rehearsals (band_id, date, start_time, end_time, location, is_potential)
    VALUES (v_band_id, CURRENT_DATE + 7, '19:00', '21:00', 'Test Location', true)
    RETURNING id INTO v_rehearsal_id;
  END IF;

  -- Insert response (should succeed via RLS)
  INSERT INTO rehearsal_responses (rehearsal_id, user_id, response)
  VALUES (v_rehearsal_id, v_user_id, 'yes')
  RETURNING id INTO v_response_id;

  RAISE NOTICE 'Response inserted successfully: %', v_response_id;

  -- Clean up test data
  DELETE FROM rehearsal_responses WHERE id = v_response_id;

  -- Note: Don't delete rehearsal if it existed before test
  -- If you created it: DELETE FROM rehearsals WHERE id = v_rehearsal_id;

  RAISE NOTICE 'Test passed, cleanup complete';
END $$;
```

Expected output: "Response inserted successfully" notice with UUID, "Test passed" notice.
If fails: Check RLS policies and helper function logic.

**-- POST-DEPLOY TEST 6:** App integration test (manual)

1. Open app on iOS/Android/Web/macOS
2. Create a potential rehearsal for tomorrow
3. Close app completely
4. Reopen app → verify modal prompt appears
5. Respond "yes" → verify modal closes
6. Verify availability count appears on rehearsal card ("✓ 1 available • ...")
7. Close and reopen app → verify prompt does NOT reappear
8. Edit rehearsal via tap → verify response is saved (visible in event editor if applicable)
9. Switch bands → verify no prompt (no rehearsals for other band)
10. Create potential rehearsal in new band → verify prompt appears for new band's rehearsal

Expected: All steps pass, no errors in console, no RLS errors, availability displays correctly.

**-- POST-DEPLOY TEST 7:** Gig availability display regression check

1. Create a potential gig
2. Have 2+ band members respond (via event editor or prompt)
3. Navigate to home dashboard
4. Verify potential gig card NOW shows availability counts (fixes implementation gap)
5. Verify gig prompt still works (app close/reopen)

Expected: Gig pattern enhanced but not broken. Availability now visible.

**-- POST-DEPLOY TEST 8:** Production verification query (no bad data)

```sql
-- Run in Supabase SQL Editor against production
SELECT COUNT(*) as bad_data_count
FROM rehearsal_responses
WHERE response NOT IN ('yes', 'no')
   OR rehearsal_id IS NULL
   OR user_id IS NULL;
```

Expected: `bad_data_count = 0`. If non-zero, investigate and clean up.

### SQL Test Authoring Rules (Enforced)

All SQL tests MUST follow these rules:

- Tests that INSERT data: wrap in `DO $$ ... END $$;` with cleanup DELETEs OR use `BEGIN; ... ROLLBACK;` transaction
- Tests that UPDATE existing rows: save original value, restore in all code paths (including EXCEPTION), assert restore succeeded
- Never use hardcoded production UUIDs — use `gen_random_uuid()` or query for test-only data
- If test requires real FK (band_members, auth.users): document dependency explicitly, place in Tier 2
- Tests calling the migrated function: MUST be in Tier 2 (function doesn't exist in Tier 1)
- Tests verifying schema: Tier 2 only (schema not changed until push)

## 16) QA Regression Areas

QA must specifically test these areas after Engineer implementation:

**Primary scope (rehearsals):**

- Create potential rehearsal → verify no errors
- App close → app open → verify prompt modal appears
- Respond yes → verify saves, modal closes, doesn't reappear
- Respond no → verify saves correctly
- Availability counts display on rehearsal card in horizontal scroll area (home dashboard)
- Multiple pending rehearsals → verify sequential prompts (oldest first)
- Band switch → verify prompts refresh for new band's rehearsals
- Edit potential rehearsal → verify response persists

**Regression scope (gigs):**

- Create potential gig → verify prompt still works
- Verify potential gig card NOW displays availability counts (enhancement)
- Verify gig RSVP flow unchanged (no breakage from parallel implementation)
- Verify gig response summaries still load correctly

**Notification behavior (must remain unchanged):**

- Create potential rehearsal → verify notification sent to other members (if applicable via CREATE-only trigger)
- Verify no new notification types introduced
- Verify response submission does NOT trigger additional notifications

**Cross-platform:**

- iOS: prompt modal renders correctly, card layout doesn't break
- Android: same as iOS
- Web: modal works in browser, card layout responsive
- macOS: prompt behavior consistent with iOS

**Edge cases:**

- No band members → verify availability shows 0/0/0 gracefully
- User not logged in → verify no errors (prompt check should skip)
- No potential rehearsals → verify no prompts, no errors
- User already responded → verify prompt doesn't show again
- Rehearsal deleted after response → verify no orphaned data errors

**Performance:**

- Dashboard load time with 10+ potential events (gigs + rehearsals) → should remain fast (<2s)
- Prompt check on app resume → should not block UI (async operation)

## 17) Rollout / Migration Strategy

**Deployment sequence:**

1. Merge feature branch to main after QA APPROVED
2. Deploy migration:
   - Run Tier 1 verification locally (pre-deploy tests)
   - Run `supabase db push` to production
   - Run Tier 2 verification immediately (post-deploy tests)
3. Deploy Flutter app:
   - Web: `./tools/deploy_web.sh`
   - iOS/Android: Standard release pipeline
   - Verify app loads without errors in production

**Rollback plan:**
If migration succeeds but app has critical issues:

- Rollback app release (redeploy previous version)
- Keep database migration in place (backward compatible — new table doesn't break old app)
- Fix app issues in new branch, redeploy after QA

If migration fails or causes RLS errors:

- Do NOT proceed with app deploy
- Diagnose migration failure
- Fix migration
- Test again in staging before production

**Post-deployment monitoring:**

- Check Supabase logs for RLS errors on rehearsal_responses table (first 24 hours)
- Monitor user reports of prompt not appearing or responses not saving
- Verify response counts in rehearsal_responses table grow as expected

**Backward compatibility:**

- Old app versions (before this feature) will not see rehearsal prompts → **acceptable, feature is new**
- Old app can still view potential rehearsals (is_potential column already exists)
- New table doesn't affect old app behavior

## 18) Out of Scope

Explicitly NOT included in this feature:

- **Multi-date potential rehearsals** — rehearsals don't support multiple dates like gigs (no rehearsal_dates table, no rehearsal_date_id column)
- **Notification changes** — no new notification types, no changes to CREATE-only trigger behavior
- **Response editing in event editor drawer** — gig pattern has this, but not implementing for rehearsals in this phase (future enhancement)
- **Response history/audit trail** — only current response is stored, no change history
- **Deadline for responses** — no time limit on when members must respond
- **Reminder notifications for unanswered rehearsals** — no follow-up prompts
- **Response visibility to other members** — members can only see aggregate counts, not who responded what (matches gig pattern)
- **Admin override of responses** — only the user can change their own response
- **Integration with calendar subscriptions** — rehearsal responses don't affect iCal feed
- **Block dates / availability conflicts** — no automatic conflict detection with block_dates table

---

**End of ARCHITECT_PLAN.md**
