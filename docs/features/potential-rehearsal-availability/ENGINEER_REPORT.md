# Engineer Report

## Feature Slug

`feature/potential-rehearsal-availability`

## Feature Title

Potential Rehearsal Availability System

## Goal

Implement a complete member availability (RSVP) system for potential rehearsals that mirrors the existing potential gig pattern. Enable members to respond yes/no to potential rehearsals, store responses in a dedicated database table with RLS policies, prompt members on app open for pending responses, and display availability counts on the dashboard. This brings potential rehearsals to full parity with potential gigs across all layers: database, models, repositories, services, UI, and integration.

## Architect Tasks Completed

- [x] **Task 1** — Add database migration `20260507135822_add_rehearsal_responses.sql` with table creation, RLS helper function, policies, and trigger
- [x] **Task 2** — Create `RehearsalResponse` model in `lib/app/models/rehearsal_response.dart` mirroring `GigResponse` structure (enum, fromJson, toJson, getters)
- [x] **Task 3** — Create `RehearsalResponseRepository` in `lib/features/rehearsals/rehearsal_response_repository.dart` with 6 methods (fetch pending, upsert, summaries) and error handling
- [x] **Task 4** — Create `PotentialRehearsalPromptService` in `lib/features/rehearsals/potential_rehearsal_prompt_service.dart` and modal widget in `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`
- [x] **Task 5** — Modify `lib/features/home/widgets/rehearsal_card.dart` and `lib/features/home/widgets/potential_gig_card.dart` to accept `responseSummary` parameter and display availability counts
- [x] **Task 6** — Integrate rehearsal response system into `lib/features/home/home_tab_content.dart` (watch summaries provider, call prompts, pass summaries to cards)
- [x] **Task 7** — Run `flutter analyze` to verify no errors or warnings remain
- [x] **Task 8** — Write this ENGINEER_REPORT.md

## Files Created

1. `supabase/migrations/20260507135822_add_rehearsal_responses.sql` — Database table with id, rehearsal_id, user_id, response (yes/no), timestamps; RLS helper function `check_rehearsal_response_access()` SECURITY DEFINER; 4 RLS policies (SELECT/INSERT/UPDATE/DELETE); updated_at trigger
2. `lib/app/models/rehearsal_response.dart` — Domain model with `RehearsalResponseType` enum (yes, no), RehearsalResponse class (id, rehearsalId, userId, response, timestamps), fromJson/toJson methods, isYes/isNo getters
3. `test/app/models/rehearsal_response_test.dart` — Unit tests for fromJson (yes/no/invalid), toJson (yes/no), round-trip serialization, toString (7 tests total)
4. `lib/features/rehearsals/rehearsal_response_repository.dart` — Repository with `RehearsalResponseError` class, `RehearsalResponseSummary` model, `PendingPotentialRehearsal` model, 6 methods (fetchPendingPotentialRehearsals, fetchUserResponse, upsertResponse with retry logic, fetchRehearsalResponseSummary, fetchAllMemberResponses, fetchMultipleRehearsalResponseSummaries), rehearsalResponseRepositoryProvider, potentialRehearsalResponseSummariesProvider (FutureProvider watching rehearsalProvider.potentialRehearsals and activeBandIdProvider)
5. `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart` — Blocking modal with `RehearsalAvailabilityResponse` enum (yes, no), RehearsalAvailabilityPromptModal widget, static show() method, \_handleResponse with RehearsalResponseError handling, gradient header, YES/NO buttons with loading states, "Not Sure Yet" dismiss link
6. `lib/features/rehearsals/potential_rehearsal_prompt_service.dart` — `PotentialRehearsalPromptState` (isShowingPrompt, isChecking, pendingCount), PotentialRehearsalPromptNotifier with \_isShowingModal lock, checkAndShowPendingPrompts() method, \_showPromptsSequentially() with band validation, potentialRehearsalPromptProvider

## Files Modified

1. `lib/features/home/widgets/rehearsal_card.dart` — Added `RehearsalResponseSummary? responseSummary` parameter, conditional availability row when `isPotential && responseSummary != null`, format: "✓ X available • ✗ Y unavailable • ? Z not responded" in white text 14px, added import for rehearsal_response_repository
2. `lib/features/home/widgets/potential_gig_card.dart` — Added `GigResponseSummary? responseSummary` parameter, conditional availability row when `responseSummary != null`, same format as rehearsal card, added import for gig_response_repository (fixed implementation gap noted in ARCHITECT_PLAN)
3. `lib/features/home/home_tab_content.dart` — Added imports for rehearsal_response_repository and potential_rehearsal_prompt_service, added watch for potentialRehearsalResponseSummariesProvider, created \_checkPendingRehearsalPrompts() method parallel to gig version, called rehearsal prompt check in didChangeAppLifecycleState() on app resume and in \_listenForBandAndCheckPrompts() after band switch, invalidated potentialRehearsalResponseSummariesProvider in onResponseSubmitted, added rehearsalResponseSummaries parameter to \_buildContentState signature and call site, replaced \_buildHorizontalPotentialGigs with \_buildHorizontalPotentialEvents to combine gigs and rehearsals in unified horizontal scroll sorted by date
4. `lib/app/models/rehearsal.dart` — Added `final bool isPotential` field with default false, included in constructor, fromJson (with backward-compatible default), and toJson methods (prerequisite for potential rehearsal support)
5. `lib/features/rehearsals/rehearsal_controller.dart` — Added `potentialRehearsals` and `confirmedRehearsals` fields to RehearsalState, updated copyWith/equality/hashCode methods, modified \_categorizeRehearsals to separate potential vs confirmed using `r.isPotential` predicate, changed nextRehearsal to first confirmed rehearsal (not potential), added hasPotentialRehearsalsProvider (prerequisite for dashboard integration)
6. `lib/features/rehearsals/rehearsal_response_repository.dart` — Removed unused import `package:bandroadie/app/models/rehearsal_response.dart` (flutter analyze warning fix)

## Analyzer Results

Command: `flutter analyze`

**First run result:** 1 warning (unused import in rehearsal_response_repository.dart)

**After fix:** 0 errors, 0 warnings

```
Analyzing bandroadie...
No issues found! (ran in 4.8s)
```

## Test Results

Command: `flutter test test/app/models/rehearsal_response_test.dart`

Result: **All 7 tests passed**

```
00:01 +7: All tests passed!
```

Tests verified:

- `RehearsalResponse.fromJson` parses `response: 'yes'` correctly
- `RehearsalResponse.fromJson` parses `response: 'no'` correctly
- `RehearsalResponse.fromJson` throws ArgumentError on invalid response value
- `RehearsalResponse.toJson` serializes `response: yes` correctly
- `RehearsalResponse.toJson` serializes `response: no` correctly
- `RehearsalResponse` fromJson → toJson round-trip preserves all fields
- `RehearsalResponse.toString()` includes id, rehearsalId, userId, response

## Verification

### Manual Steps Performed

1. ✓ Verified feature branch `feature/potential-rehearsal-availability` is active
2. ✓ Confirmed all 6 new files were created at correct paths
3. ✓ Confirmed all 6 files were modified as specified in Architect plan
4. ✓ Ran `flutter test test/app/models/rehearsal_response_test.dart` → 7/7 tests passed
5. ✓ Ran `flutter analyze` → 0 errors, 0 warnings after unused import fix
6. ✓ Verified migration file exists with timestamp format `20260507135822`
7. ✓ Verified migration includes RLS helper function with SECURITY DEFINER
8. ✓ Verified all modified files use correct import paths for new repositories
9. ✓ Verified RehearsalCard and PotentialGigCard both have responseSummary parameter
10. ✓ Verified home_tab_content.dart calls both gig and rehearsal prompt checks

### Database Migration Verification (Tier 1)

**Not yet deployed** — Migration file created but not pushed to Supabase. Requires `supabase db push` for Tier 2 verification.

Migration validation steps pending deployment:

- Table creation with correct columns and types
- RLS helper function executes without recursion (PostgreSQL 42P17 error)
- All 4 RLS policies enforce band-scoped access
- updated_at trigger fires on UPDATE

### Integration Verification (Tier 1 — Static Analysis)

**Code path tracing:**

1. App opens → `HomeTabContent.didChangeAppLifecycleState(AppLifecycleState.resumed)` triggers
2. Calls `_checkPendingRehearsalPrompts()` → delays 500ms for UI stability
3. Reads `activeBandIdProvider` → guards for null band
4. Calls `ref.read(potentialRehearsalPromptProvider.notifier).checkAndShowPendingPrompts(context, onResponseSubmitted: ...)`
5. Prompt service fetches pending rehearsals from `rehearsalResponseRepository.fetchPendingPotentialRehearsals()`
6. For each pending rehearsal, shows `RehearsalAvailabilityPromptModal` sequentially
7. User taps YES/NO → calls `rehearsalResponseRepository.upsertResponse(rehearsalId, response)`
8. On success, executes `onResponseSubmitted` callback → refreshes rehearsalProvider, invalidates potentialRehearsalResponseSummariesProvider
9. Dashboard re-renders with updated availability counts via `RehearsalCard(responseSummary: summary)`

**Provider dependency graph validated:**

- `potentialRehearsalResponseSummariesProvider` watches:
  - `rehearsalProvider.potentialRehearsals` (source of rehearsal list)
  - `activeBandIdProvider` (band context for queries)
- `home_tab_content.dart` watches:
  - `potentialRehearsalResponseSummariesProvider` → extracts Map<String, RehearsalResponseSummary>
- Invalidation on band switch:
  - `activeBandIdProvider` change → `rehearsalProvider` auto-refreshes → `potentialRehearsalResponseSummariesProvider` auto-refreshes

## Deviations From Architect Plan

### Deviation 1: Added isPotential Support to Rehearsal Model and Controller (Prerequisite)

**Plan assumption:** "The rehearsal domain has `is_potential` support (column, model field, UI toggle, persistence) from the prior feature (`feature/rehearsal-potential-toggle`)."

**Actual state discovered:** The `is_potential` column exists in the database (confirmed via migration file `20260507000000_add_rehearsal_is_potential.sql`), but the Dart model and controller did **not** have isPotential support. The `Rehearsal` model was missing the `isPotential` field, and `RehearsalState` did not categorize potential vs confirmed rehearsals.

**Action taken:** Added missing prerequisite support to unblock feature implementation:

- Modified `lib/app/models/rehearsal.dart` to add `final bool isPotential` field (default false), included in constructor, fromJson (with backward-compatible `?? false` default), and toJson
- Modified `lib/features/rehearsals/rehearsal_controller.dart` to add `potentialRehearsals` and `confirmedRehearsals` fields to `RehearsalState`, updated `_categorizeRehearsals` method to filter by `isPotential` predicate, changed `nextRehearsal` to first **confirmed** rehearsal (excluding potentials), added `hasPotentialRehearsalsProvider`

**Justification:** Without these prerequisite changes, the feature could not function as specified. The Architect plan explicitly states that the rehearsal domain "has `is_potential` support", and the implementation required it for:

1. Filtering potential rehearsals for RSVP prompts (`fetchPendingPotentialRehearsals` queries by `is_potential = true`)
2. Displaying availability counts only on potential rehearsal cards (`if (rehearsal.isPotential && responseSummary != null)`)
3. Categorizing rehearsals in the dashboard (combining potentialGigs + potentialRehearsals in horizontal scroll)

This deviation adds 2 modified files beyond the original "Files to Modify" list, but aligns with the Architect plan's stated prerequisites. The prior feature (`feature/rehearsal-potential-toggle`) appears to have been partially implemented or reverted.

### Deviation 2: Fixed Implementation Gap in PotentialGigCard (Task 5)

**Plan note:** "The Architect plan's secondary observation notes that `PotentialGigCard` currently does not display availability counts despite the provider loading them — this is an implementation gap to fix alongside the rehearsal pattern."

**Action taken:** Added `GigResponseSummary? responseSummary` parameter to `PotentialGigCard` constructor and conditional availability row rendering (identical pattern to RehearsalCard).

**Justification:** The Architect plan explicitly identified this as an implementation gap to fix in Task 5. The gig RSVP system was incomplete without dashboard display. Fixing this ensures both gig and rehearsal patterns are fully parallel and complete.

### Deviation 3: Combined Potential Events into Unified Horizontal Scroll (Task 6)

**Plan guidance:** "Update `_buildHorizontalPotentialEvents()` to accept both summary maps and pass to card constructors."

**Actual state:** The method `_buildHorizontalPotentialEvents()` did not exist. The prior implementation used `_buildHorizontalPotentialGigs()` which only rendered gigs.

**Action taken:** Replaced `_buildHorizontalPotentialGigs()` with new `_buildHorizontalPotentialEvents()` method that:

- Accepts both `List<Gig> potentialGigs` and `List<Rehearsal> potentialRehearsals`
- Filters past events from both lists
- Combines into unified event list with type metadata
- Sorts by date proximity (DateTime comparison)
- Renders both PotentialGigCard and RehearsalCard in same horizontal scroll

**Justification:** The Architect plan expects potential rehearsals to appear "alongside potential gigs in the same top dashboard potential area" (consistent with `feature/rehearsal-potential-toggle` ENGINEER_REPORT which states "potential rehearsals alongside potential gigs in horizontal scroll"). This implementation matches the intended user experience of seeing all pending potential events in one unified list, sorted chronologically.

## Blockers Encountered

None.

All prerequisite work was completed as part of this feature implementation (see Deviation 1).

## Ready For QA

**Status: YES** (Tier 1 Complete — Tier 2 pending database deployment)

### Tier 1 (Static Analysis) — COMPLETE ✓

- All Architect tasks implemented
- Flutter analyze passes with 0 errors, 0 warnings
- Unit tests pass (7/7)
- Code review readiness verified

### Tier 2 (Runtime + Database) — PENDING ⏳

**Blockers for Tier 2:**

1. Migration deployment required: `cd supabase && supabase db push` (or equivalent production deployment)
2. Requires at least one band with:
   - Multiple members (to test availability counts)
   - At least one potential rehearsal (is_potential = true)
3. Manual testing steps:
   - Create potential rehearsal via EventEditorDrawer
   - Open app → verify prompt modal appears for all members
   - Respond YES/NO → verify response saves to rehearsal_responses table
   - Verify availability counts appear on RehearsalCard in dashboard
   - Verify band switch triggers prompt re-check
   - Verify app resume (background → foreground) triggers prompt re-check

### QA Test Plan

**Acceptance criteria for Tier 2 verification:**

1. **Database migration deploys successfully** without RLS recursion errors or constraint violations
2. **Prompt modal appears on app open** when user has pending potential rehearsal responses (no existing rehearsal_responses row for that user + rehearsal)
3. **User can respond YES/NO** via modal, response saves to database, modal dismisses
4. **Dashboard displays availability counts** on potential rehearsal cards: "✓ X available • ✗ Y unavailable • ? Z not responded"
5. **Counts update immediately** after user changes availability (via prompt or edit drawer)
6. **Prompt respects band isolation** — only shows potential rehearsals for active band
7. **Prompt does not re-show** after user has responded (filtered by fetchPendingPotentialRehearsals)
8. **RLS policies enforce access control** — users can only see/update responses for their bands
9. **Parallel gig prompts work** — both gig and rehearsal prompts show sequentially without conflicts
10. **Potential gig cards also show availability counts** (fixes implementation gap)

### Recommended QA Priority

**P0 — Critical path:**

- Prompt modal appearance and response submission
- Availability counts display on dashboard
- RLS policy enforcement (security)

**P1 — High priority:**

- Band switch behavior
- App resume behavior
- Sequential modal display (gigs then rehearsals)

**P2 — Medium priority:**

- Error handling (network failures, Supabase errors)
- Retry logic in upsertResponse
- Edge cases (zero members, all responded, etc.)

---

**Feature implementation complete. Ready for database deployment and Tier 2 QA validation.**
