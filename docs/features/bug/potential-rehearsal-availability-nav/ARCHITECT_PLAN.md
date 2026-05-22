# ARCHITECT_PLAN

**Feature:** `bug/potential-rehearsal-availability-nav`  
**Type:** Bug + UX improvement  
**Branch:** `bug/potential-rehearsal-availability-nav`  
**Architect:** Claude Sonnet 4.5  
**Date:** 2026-05-21

---

## 1) Problem Statement

On the home dashboard, when a potential rehearsal has multiple proposed dates:

1. **User cannot mark availability** — tapping YES/NO does not register or persist
2. **User cannot navigate between dates** — the next/previous date controls do not work
3. **Navigation controls are too narrow** — 36px width causes accidental taps on YES/NO buttons when user intends to navigate

The multi-date UI renders (chip shows "Multiple Dates"), but the availability marking and navigation are non-functional.

---

## 2) Affected Files — Current State

### Modified in commit `2b2111b` (recent changes)

- `lib/features/home/widgets/potential_gig_card.dart` — cosmetic gradient changes only
- `lib/features/home/widgets/rehearsal_card.dart` — cosmetic gradient changes only
- `lib/features/rehearsals/rehearsal_repository.dart` — added `_rehearsalSelectClause` to fetch rehearsal_dates join
- `lib/features/home/home_tab_content.dart` — added `additionalDates: rehearsal.additionalDates` to widget call
- `lib/features/home/widgets/home_app_bar.dart` — cosmetic theme changes only

### Database layer (already exists)

- Migration `20260519160119_add_rehearsal_multi_date_support.sql` — created `rehearsal_dates` table, added `rehearsal_date_id` column to `rehearsal_responses`, updated unique constraint

### Model layer (already correct)

- `lib/app/models/rehearsal.dart` — parses `additionalDates` correctly via `_parseAdditionalDates()`
- `lib/app/models/rehearsal_date.dart` — model for additional dates

---

## 3) Root Cause Analysis

### Confidence: **HIGH** (confirmed in code)

#### Primary Failure Layer: Repository + Provider

**Root Cause 1: Missing per-date response methods in rehearsal_response_repository.dart**

Location: `lib/features/rehearsals/rehearsal_response_repository.dart`

The repository has these methods:

- `upsertResponse(rehearsalId, bandId, userId, response)` — NO rehearsalDateId parameter
- `deleteResponse(rehearsalId, userId)` — NO rehearsalDateId parameter
- `fetchCurrentUserRehearsalResponses()` — returns `Map<String, String?>` (flat, not per-date)

But it lacks the per-date equivalents that exist in gig_response_repository.dart:

- ❌ `upsertResponseForDate(rehearsalId, rehearsalDateId, userId, response)` — MISSING
- ❌ `deleteResponseForDate(rehearsalId, rehearsalDateId, userId)` — MISSING
- ❌ `fetchCurrentUserRehearsalAllDateResponses()` — MISSING

When the user taps YES/NO on a multi-date potential rehearsal card, the UI calls:

```dart
onRespondForDate: (response, rehearsalDateId) async {
  // Tries to pass rehearsalDateId to repository methods that don't accept it
  await ref.read(rehearsalResponseRepositoryProvider).upsertResponse(...);
}
```

This fails because `upsertResponse` does NOT accept a `rehearsalDateId` parameter. The database supports it (column exists), but the repository doesn't.

**Root Cause 2: Missing per-date responses provider**

Location: `lib/features/rehearsals/rehearsal_response_repository.dart`

The file has:

- `currentUserRehearsalResponsesProvider` — returns `Map<String, String?>` (rehearsalId → response for primary date only)

But it lacks:

- ❌ `currentUserRehearsalAllDateResponsesProvider` — MISSING (should return `Map<String, Map<String?, String?>>`)

The gig equivalent exists and works correctly:

- `currentUserGigAllDateResponsesProvider` — returns `Map<String, Map<String?, String?>>` (gigId → (gigDateId? → response))

Without this provider, the UI cannot fetch or watch per-date responses.

**Root Cause 3: Incorrect perDateUserResponses mapping in home_tab_content.dart**

Location: `lib/features/home/home_tab_content.dart` lines 1051-1053

Current code:

```dart
perDateUserResponses: {
  null: rehearsalUserResponses[rehearsal.id],
},
```

This passes a single-entry map containing only the primary date's response. For multi-date rehearsals, this should be:

```dart
perDateUserResponses: rehearsalAllDateResponses[rehearsal.id],
```

Where `rehearsalAllDateResponses` is fetched from `currentUserRehearsalAllDateResponsesProvider` (which doesn't exist yet).

**Root Cause 4: Navigation controls too narrow**

Location: `lib/features/home/widgets/rehearsal_card.dart` line 476

The `_RehearsalDateNavButton` widget has:

```dart
width: 36,
```

With only 8px spacing to YES/NO buttons:

```dart
const SizedBox(width: 8),
```

At normal thumb size, this causes accidental taps on YES/NO when the user intends to navigate. The gig card has the same dimensions and suffers the same UX issue.

**Minimum touch target (iOS/Android HIG):** 44-48px  
**Current nav button + spacing:** 36px + 8px = 44px total (but user perception is 36px)  
**Recommended:** Increase button width to 48px and spacing to 12px for clear separation

---

## 4) Data Flow — Expected vs. Actual

### Expected (how gigs work)

```
User taps YES on date #2
  ↓
onRespondForDate('yes', gigDateId='...') called
  ↓
gigResponseRepository.upsertResponseForDate(gigId, gigDateId, userId, 'yes')
  ↓
Database: INSERT/UPDATE gig_responses SET gig_date_id='...', response='yes'
  ↓
ref.invalidate(currentUserGigAllDateResponsesProvider)
  ↓
Provider re-fetches: fetchCurrentUserGigAllDateResponses(gigIds, userId)
  ↓
UI updates: perDateUserResponses[gigDateId] = 'yes'
```

### Actual (rehearsals, broken)

```
User taps YES on date #2
  ↓
onRespondForDate('yes', rehearsalDateId='...') called
  ↓
rehearsalResponseRepository.upsertResponse(rehearsalId, bandId, userId, 'yes')
  ↑
  ❌ rehearsalDateId parameter ignored — method signature doesn't accept it
  ↓
Database: INSERT/UPDATE rehearsal_responses SET rehearsal_date_id=NULL, response='yes'
  ↑
  ❌ Response always goes to primary date (NULL), not the selected date
  ↓
ref.invalidate(currentUserRehearsalResponsesProvider)
  ↑
  ❌ Provider doesn't fetch per-date responses — only returns flat map
  ↓
UI receives: perDateUserResponses = { null: 'yes' }
  ↑
  ❌ Only primary date has response data; date #2 shows as unresponded
```

---

## 5) System Impact Assessment

| System             | Impact                | Notes                                                               |
| ------------------ | --------------------- | ------------------------------------------------------------------- |
| Gigs               | **Unaffected**        | Uses separate gig_response_repository with correct per-date methods |
| Rehearsals         | **Directly affected** | Multi-date potential rehearsals non-functional                      |
| Setlists / Catalog | **Unaffected**        | No dependency                                                       |
| Members / RBAC     | **Unaffected**        | No dependency                                                       |
| Auth / Session     | **Unaffected**        | No dependency                                                       |
| Routing            | **Unaffected**        | No dependency                                                       |
| Calendar           | **Unaffected**        | Calendar consumes rehearsal dates read-only                         |
| Notifications      | **Unaffected**        | Notifications consume response summaries read-only                  |

---

## 6) Database Impact Assessment

**Database: Affected**

### Schema (already correct — no changes needed)

- `rehearsal_dates` table exists (migration `20260519160119`)
- `rehearsal_responses.rehearsal_date_id` column exists (migration `20260519160119`)
- Unique constraint exists: `rehearsal_responses_rehearsal_user_date_unique` on `(rehearsal_id, user_id, COALESCE(rehearsal_date_id, '00000000-0000-0000-0000-000000000000'))`
- RLS policies exist for `rehearsal_dates` (SELECT/INSERT/UPDATE/DELETE for band members)

### Queries (new queries in repository methods)

1. `upsertResponseForDate` — SELECT + UPDATE or INSERT with `rehearsal_date_id` filter
2. `deleteResponseForDate` — DELETE with `rehearsal_date_id` filter
3. `fetchCurrentUserRehearsalAllDateResponses` — SELECT `rehearsal_id, rehearsal_date_id, response` grouped by rehearsal

**RLS Impact:** None. Queries use existing policies. No new policies needed.

---

## 7) Proposed Solution

### Minimal fix: Mirror the gig pattern exactly

The gig_response_repository.dart already implements per-date responses correctly. Apply the same pattern to rehearsal_response_repository.dart.

### Changes Required

#### 1. Add per-date methods to rehearsal_response_repository.dart

**File:** `lib/features/rehearsals/rehearsal_response_repository.dart`

Add these three methods (mirror gig_response_repository.dart lines 566-780):

```dart
/// Submit or update the user's response for a specific date of a rehearsal.
/// Has automatic retry logic for transient failures.
Future<void> upsertResponseForDate({
  required String rehearsalId,
  required String? rehearsalDateId, // null for primary date
  required String userId,
  required String response, // 'yes' or 'no'
}) async {
  // Retry up to 3 times with exponential backoff for transient errors
  // Implementation mirrors GigResponseRepository.upsertResponseForDate
}

/// Internal method to perform the actual upsert for date
Future<void> _performUpsertForDate({
  required String rehearsalId,
  required String? rehearsalDateId,
  required String userId,
  required String response,
}) async {
  // Query existing response with rehearsal_date_id filter
  // UPDATE if exists, INSERT if not
  // Implementation mirrors GigResponseRepository._performUpsertForDate
}

/// Delete the user's response for a specific date of a rehearsal.
/// Pass rehearsalDateId = null to delete the primary-date response.
Future<void> deleteResponseForDate({
  required String rehearsalId,
  required String userId,
  required String? rehearsalDateId,
}) async {
  // DELETE with rehearsal_date_id filter
  // Implementation mirrors GigResponseRepository.deleteResponseForDate
}

/// Fetch the current user's responses across ALL dates of all potential rehearsals.
/// Returns rehearsalId → (rehearsalDateId? → response). rehearsalDateId? null = primary date.
Future<Map<String, Map<String?, String?>>> fetchCurrentUserRehearsalAllDateResponses({
  required List<String> rehearsalIds,
  required String userId,
}) async {
  // SELECT rehearsal_id, rehearsal_date_id, response WHERE user_id = ... AND rehearsal_id IN (...)
  // Group by rehearsalId, then by rehearsalDateId
  // Implementation mirrors GigResponseRepository.fetchCurrentUserGigAllDateResponses (lines 757-780)
}
```

#### 2. Add per-date responses provider

**File:** `lib/features/rehearsals/rehearsal_response_repository.dart`

Add this provider after `currentUserRehearsalResponsesProvider` (mirror gig_response_repository.dart lines 909-932):

```dart
/// Async provider for the current user's responses across ALL dates of all potential rehearsals.
/// Returns rehearsalId → (rehearsalDateId? → response). rehearsalDateId? null = primary date.
/// Invalidated after the user submits a response for any date.
final currentUserRehearsalAllDateResponsesProvider =
    FutureProvider<Map<String, Map<String?, String?>>>((ref) async {
  final rehearsalState = ref.watch(rehearsalProvider);
  final bandId = ref.watch(activeBandIdProvider);
  final userId = supabase.auth.currentUser?.id;

  if (bandId == null || userId == null || rehearsalState.potentialRehearsals.isEmpty) {
    return {};
  }
  if (rehearsalState.isLoading) return {};

  final repository = ref.read(rehearsalResponseRepositoryProvider);
  final rehearsalIds = rehearsalState.potentialRehearsals.map((r) => r.id).toList();

  try {
    return await repository.fetchCurrentUserRehearsalAllDateResponses(
      rehearsalIds: rehearsalIds,
      userId: userId,
    );
  } catch (e) {
    debugPrint('[currentUserRehearsalAllDateResponsesProvider] Error: $e');
    return {};
  }
});
```

#### 3. Update home_tab_content.dart to use per-date provider

**File:** `lib/features/home/home_tab_content.dart`

**Change 1:** Add provider watch (line ~469, after `rehearsalUserResponses` watch)

```dart
// Watch per-date responses for multi-date potential rehearsal cards
final Map<String, Map<String?, String?>> rehearsalAllDateResponses =
    ref.watch(currentUserRehearsalAllDateResponsesProvider).when(
          data: (r) => r,
          loading: () => {},
          error: (_, _) => {},
        );
```

**Change 2:** Update method signature (line ~800, `_buildContentState` signature)

Add parameter:

```dart
required Map<String, Map<String?, String?>> rehearsalAllDateResponses,
```

**Change 3:** Pass to method call (line ~590, `_buildContentState` call)

Add argument:

```dart
rehearsalAllDateResponses: rehearsalAllDateResponses,
```

**Change 4:** Update `_buildHorizontalPotentialEvents` signature (line ~1000)

Add parameter:

```dart
Map<String, Map<String?, String?>> rehearsalAllDateResponses,
```

**Change 5:** Update `_buildHorizontalPotentialEvents` call (line ~825)

Add argument:

```dart
rehearsalAllDateResponses,
```

**Change 6:** Update RehearsalCard instantiation (line ~1051)

Replace:

```dart
perDateUserResponses: {
  null: rehearsalUserResponses[rehearsal.id],
},
```

With:

```dart
perDateUserResponses: rehearsalAllDateResponses[rehearsal.id] ?? {},
```

**Change 7:** Update onRespondForDate callback (line ~1057)

Replace:

```dart
onRespondForDate: (bandId == null || userId == null)
    ? null
    : (response, rehearsalDateId) async {
        if (response == null) {
          // Delete response (unselect) — rehearsals only have
          // a primary date for now, so rehearsalDateId is always null
          await ref
              .read(rehearsalResponseRepositoryProvider)
              .deleteResponse(
                rehearsalId: rehearsal.id,
                userId: userId,
              );
        } else {
          // Upsert response
          await ref
              .read(rehearsalResponseRepositoryProvider)
              .upsertResponse(
                rehearsalId: rehearsal.id,
                bandId: bandId,
                userId: userId,
                response: response,
              );
        }
        ref.invalidate(currentUserRehearsalResponsesProvider);
        ref.invalidate(
            potentialRehearsalResponseSummariesProvider);
      },
```

With:

```dart
onRespondForDate: (bandId == null || userId == null)
    ? null
    : (response, rehearsalDateId) async {
        if (response == null) {
          // Delete response for this specific date
          await ref
              .read(rehearsalResponseRepositoryProvider)
              .deleteResponseForDate(
                rehearsalId: rehearsal.id,
                userId: userId,
                rehearsalDateId: rehearsalDateId,
              );
        } else {
          // Upsert response for this specific date
          await ref
              .read(rehearsalResponseRepositoryProvider)
              .upsertResponseForDate(
                rehearsalId: rehearsal.id,
                rehearsalDateId: rehearsalDateId,
                userId: userId,
                response: response,
              );
        }
        ref.invalidate(currentUserRehearsalAllDateResponsesProvider);
        ref.invalidate(currentUserRehearsalResponsesProvider);
        ref.invalidate(potentialRehearsalResponseSummariesProvider);
      },
```

#### 4. Widen navigation controls in rehearsal_card.dart

**File:** `lib/features/home/widgets/rehearsal_card.dart`

**Change 1:** Update `_RehearsalDateNavButton` width (line ~476)

Replace:

```dart
width: 36,
```

With:

```dart
width: 48,
```

**Change 2:** Update spacing around nav buttons (line ~364 and ~377)

Replace:

```dart
const SizedBox(width: 8),
```

With:

```dart
const SizedBox(width: 12),
```

(Two occurrences: before the first nav button and before the second nav button)

#### 5. Widen navigation controls in potential_gig_card.dart (parallel fix)

**File:** `lib/features/home/widgets/potential_gig_card.dart`

**Change 1:** Update `_DateNavButton` width (line ~470)

Replace:

```dart
width: 36,
```

With:

```dart
width: 48,
```

**Change 2:** Update spacing around nav buttons (line ~368 and ~381)

Replace:

```dart
const SizedBox(width: 8),
```

With:

```dart
const SizedBox(width: 12),
```

(Two occurrences: before the first nav button and before the second nav button)

---

## 8) Files to Modify (Engineer's Task List)

### Core changes (required)

1. `lib/features/rehearsals/rehearsal_response_repository.dart` — add 4 methods + 1 provider
2. `lib/features/home/home_tab_content.dart` — add provider watch, update method signatures, update RehearsalCard instantiation
3. `lib/features/home/widgets/rehearsal_card.dart` — widen nav buttons + spacing
4. `lib/features/home/widgets/potential_gig_card.dart` — widen nav buttons + spacing (parallel fix)

### Test validation (recommended but not blocking)

- Manual test: Create potential rehearsal with 3 dates, mark availability for each, verify persistence
- Manual test: Tap nav controls without accidentally hitting YES/NO buttons

---

## 9) Files That Are Off-Limits

**DO NOT MODIFY:**

- `lib/app/models/rehearsal.dart` — already correct
- `lib/app/models/rehearsal_date.dart` — already correct
- `lib/features/rehearsals/rehearsal_repository.dart` — already fetching rehearsal_dates correctly
- `lib/features/rehearsals/rehearsal_controller.dart` — does not need changes
- Any database migration files — schema is already correct
- Any RLS policies — existing policies handle per-date responses correctly
- `lib/features/gigs/*` files — do not touch gig code (except potential_gig_card.dart for UX fix)

---

## 10) QA Verification Plan

### Automated Tests

- Run `flutter analyze` — must pass with 0 errors

### Manual Tests (Required)

#### Test 1: Single-date potential rehearsal (regression check)

1. Create a potential rehearsal with 1 date
2. Open home dashboard → potential rehearsal card visible
3. Tap YES → green checkmark appears
4. Refresh page → YES still selected
5. Tap NO → red X appears
6. Refresh page → NO still selected
7. Tap NO again → unselected (empty state)

**Expected:** All interactions persist correctly. No regression.

#### Test 2: Multi-date potential rehearsal (new functionality)

1. Create a potential rehearsal with 3 dates (e.g., June 1, June 8, June 15)
2. Open home dashboard → potential rehearsal card visible
3. Verify chip shows "POTENTIAL REHEARSAL: Multiple Dates"
4. Verify card shows first date (June 1) with YES/NO buttons and nav controls
5. Tap YES for June 1 → green checkmark appears
6. Tap right chevron → card advances to June 8
7. Tap NO for June 8 → red X appears
8. Tap right chevron → card advances to June 15
9. Verify June 15 shows as unresponded (no checkmark, no X)
10. Tap left chevron twice → card returns to June 1
11. Verify June 1 still shows YES (green checkmark)
12. Refresh page → verify all responses persist
13. Tap right chevron → verify June 8 still shows NO (red X)

**Expected:** All three dates are independently navigable and respondable. All responses persist.

#### Test 3: Navigation control touch targets

1. Open potential rehearsal card with multiple dates (or potential gig with multiple dates)
2. Attempt to tap left chevron without accidentally hitting NO button
3. Attempt to tap right chevron without accidentally hitting YES button
4. Verify nav buttons feel clearly separated from YES/NO buttons

**Expected:** No accidental taps on YES/NO when intending to navigate. Clear visual and spatial separation.

#### Test 4: Cross-member validation (optional but recommended)

1. User A creates potential rehearsal with 2 dates
2. User B marks YES for date 1, NO for date 2
3. User A opens Edit Event drawer → Availability tab
4. Verify User B's responses show correctly per date

**Expected:** Per-date responses display correctly in the Edit Event drawer.

---

## 11) Additional Context

### Why the bug occurred

The database migration `20260519160119_add_rehearsal_multi_date_support.sql` added multi-date support to the schema, and commit `2b2111b` added the SELECT clause to fetch rehearsal_dates, but the repository layer was never updated to handle per-date responses. The UI renders the multi-date UI (additionalDates are passed to the widget) but has no data layer to back it up.

### Why the gig code is unaffected

The gig_response_repository.dart was built with per-date support from the start. The rehearsal equivalent was added later but incompletely.

### Why this is a minimal fix

We are not adding new architecture — we are completing the existing multi-date architecture by mirroring the proven gig pattern. No new tables, no new migrations, no new RLS policies. The database already supports it.

### UX improvement rationale

The 36px nav button width violates iOS/Android HIG minimum touch target guidelines (44-48px). Increasing to 48px with 12px spacing provides clear separation and reduces mis-taps. This fix also applies to potential gig cards, which have the same narrow controls.

---

## 12) Engineer Checklist

Before marking this feature complete, the Engineer must verify:

- [ ] All 4 files modified as specified
- [ ] `flutter analyze` passes with 0 errors
- [ ] Manual Test 1 (single-date regression) passes
- [ ] Manual Test 2 (multi-date functionality) passes
- [ ] Manual Test 3 (navigation touch targets) passes
- [ ] No regressions to potential gig cards
- [ ] ENGINEER_REPORT.md written with all changes documented
- [ ] Git diff generated and reviewed

---

**End of ARCHITECT_PLAN**
