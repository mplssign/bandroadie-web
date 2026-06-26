# QA REPORT — One Calendar / Shared Block-Out Dates

## Feature Slug

`feature/one-calendar-shared-blockout`

## QA Status

**✅ PASS — APPROVED FOR COMMIT**

---

## Executive Summary

**Status:** Full re-validation complete. All critical validations passed.

**Database Migration:** Successfully deployed. Migration `20260626005216_add_user_calendar_preferences` confirmed present in remote database via `supabase migration list`.

**Code Quality:** 0 analyzer errors, 2 cosmetic info warnings (Flutter Radio deprecation, framework-level, non-blocking).

**Completeness:** All 11 tasks from Architect Plan implemented and verified via code analysis.

**Safety:** Database RLS policies verified safe (no self-reference), RPC signatures match Dart client calls, graceful error handling confirmed, no secrets or debug artifacts in diff.

**Regression Risk:** MEDIUM (matches Architect assessment). Feature is opt-in, single-band users unaffected, errors in propagation/auto-blocking do not fail primary operations.

**Validation Method:** Code-path analysis (not runtime testing). All required regression areas verified via source code inspection.

---

## Validation Phases Completed

### Phase 0 — Load Rules ✅

Read in full:

- `docs/agents/GUARDRAILS.md`
- `docs/agents/QA.md`
- `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md`
- `docs/features/one-calendar-shared-blockout/ENGINEER_REPORT.md`

### Phase 1 — Verify Workspace ✅

```bash
Branch: feature/one-calendar-shared-blockout
Status: Unstaged changes (expected for QA review)
```

**Verification:**

- ✅ Branch name matches feature slug exactly
- ✅ Working tree contains expected feature changes and documentation files
- ✅ All new files present: migration, models, repository, controller, UI screen, service

### Phase 2 — Resolve Slug and Load Documents ✅

**Documents loaded and validated:**

- `docs/features/one-calendar-shared-blockout/ARCHITECT_PLAN.md`
- `docs/features/one-calendar-shared-blockout/ENGINEER_REPORT.md`

**Validation:**

- ✅ Both files exist at correct slug path
- ✅ Feature Slug matches branch identifier in both files
- ✅ Both files refer to same feature

### Phase 3 — Extract Validation Baseline ✅

**Problem Being Solved:**
Users who belong to multiple bands must enter the same unavailability dates separately on each band's calendar. This creates friction, risks missed conflicts, and wastes time.

**Expected Behavior After Fix:**

1. Users can enable "One Calendar" mode (visible only for users with 2+ bands)
2. Users can choose to apply block-out dates to "All bands" or "Selected bands only"
3. Users can enable automatic conflict blocking so gigs/rehearsals scheduled in one band automatically create block-out dates on other bands

**Files Expected to Change:**

- ✅ `supabase/migrations/20260626005216_add_user_calendar_preferences.sql` (created)
- ✅ `lib/features/calendar/models/one_calendar_preferences.dart` (created)
- ✅ `lib/features/calendar/one_calendar_preferences_repository.dart` (created)
- ✅ `lib/features/calendar/one_calendar_preferences_controller.dart` (created)
- ✅ `lib/features/calendar/one_calendar_settings_screen.dart` (created)
- ✅ `lib/features/calendar/auto_conflict_blocking_service.dart` (created)
- ✅ `lib/features/calendar/widgets/add_block_out_drawer.dart` (modified)
- ✅ `lib/features/events/events_repository.dart` (modified)
- ✅ `lib/features/settings/settings_screen.dart` (modified)

**Database Impact:**

- New table: `user_calendar_preferences`
- New RPC functions: `get_or_create_calendar_preferences`, `update_calendar_preferences`
- New RLS policies for user-level access control
- New trigger: `update_updated_at_column` for `user_calendar_preferences`

**System Impact Map:**

- Gigs: affected (auto-conflict blocking integration)
- Rehearsals: affected (auto-conflict blocking integration)
- Calendar: affected (core feature)
- Settings: affected (new settings screen and conditional menu item)
- Routing: affected (new route for OneCalendarSettingsScreen)
- All other systems: unaffected

**QA Regression Areas:**

- One Calendar settings visibility (2+ bands vs single-band users)
- Block-out propagation (all bands vs selected bands)
- Auto-conflict blocking (gig/rehearsal creation side effects)
- Delete propagation (single-band vs multi-band choice)
- Graceful degradation (propagation errors do not block primary operations)
- Existing block-out flow (unchanged when One Calendar disabled)
- Existing gig/rehearsal creation (unchanged when auto-blocking disabled)

---

### Phase 4 — Review Engineer Implementation ✅

**Engineer Report Review:**

- ✅ All 11 tasks from Architect task breakdown completed
- ✅ Post-implementation fix applied: Band name made required parameter in AutoConflictBlockingService
- ✅ Post-implementation fix applied: Delete propagation (Task 4.2) fully implemented in BlockOutDrawer.\_handleDelete()
- ✅ flutter analyze: 0 errors, 2 info warnings (Radio deprecation, cosmetic only)
- ✅ No test requirements in Architect plan (tests not run)

**Git Diff Review:**

Reviewed all changes via `git diff`:

- ✅ Modified files: add_block_out_drawer.dart, events_repository.dart, settings_screen.dart
- ✅ Created files: migration, model, repository, controller, UI screen, service
- ✅ All changes align with Architect plan
- ✅ No files outside approved list were modified
- ✅ No architectural patterns changed without approval
- ✅ Change surface is minimal and appropriate
- ✅ No formatting-only churn in unrelated files

---

### Phase 5 — Completeness Check ✅

**Verification:** All tasks from Architect Plan completed and verified in code.

**Phase 1: Database Migration**

- ✅ Task 1.1: Create migration file (20260626005216_add_user_calendar_preferences.sql)
- ✅ Task 1.2: Deploy migration (confirmed via `supabase migration list`)

**Phase 2: Flutter Data Layer**

- ✅ Task 2.1: Create OneCalendarPreferences model (enum ApplyToMode + data class with fromJson/toJson/copyWith)
- ✅ Task 2.2: Create OneCalendarPreferencesRepository (getPreferences, updatePreferences, getBandIdsToApplyBlockOut)
- ✅ Task 2.3: Create OneCalendarPreferencesController (AsyncNotifier with all required methods)

**Phase 3: Settings UI**

- ✅ Task 3.1: Create OneCalendarSettingsScreen (master toggle, apply-to section, band picker, auto-conflict toggle)
- ✅ Task 3.2: Modify SettingsScreen (conditional menu item: bandCount >= 2)

**Phase 4: Block-Out Propagation**

- ✅ Task 4.1: Modify BlockOutDrawer.\_handleSave() (cross-band propagation after primary save)
- ✅ Task 4.2: Modify BlockOutDrawer.\_handleDelete() (choice dialog + multi-band delete)

**Phase 5: Auto-Conflict Blocking**

- ✅ Task 5.1: Create AutoConflictBlockingService (autoBlockConflictingDate method)
- ✅ Task 5.2: Integrate into gig creation (via EventsRepository.createGig)
- ✅ Task 5.3: Integrate into rehearsal creation (via EventsRepository.createRehearsal)

**Result:** No skipped requirements, no partial implementations, no missing edge-case handling.

---

### Phase 6 — Behavior Verification ✅

**Validation Method:** Code-path analysis (not runtime testing).

**Behavior 1: One Calendar Toggle Visibility**

Verified in code (settings_screen.dart):

```dart
final bandCount = ref.watch(activeBandProvider).userBands.length;
if (bandCount >= 2) {
  regularItems.add(SettingsItem(...One Calendar...));
}
```

✅ **CONFIRMED:** Settings item only appears when user belongs to 2+ bands.

**Behavior 2: Apply-To Mode Logic**

Verified in code (one_calendar_preferences_repository.dart):

```dart
if (!prefs.oneCalendarEnabled) { return []; }
if (prefs.applyToMode == ApplyToMode.allBands) { return userBandIds; }
// Apply to selected bands only
final selectedIds = prefs.selectedBandIds.where((id) => userBandIds.contains(id)).toList();
return selectedIds;
```

✅ **CONFIRMED:** Repository correctly returns empty list when disabled, all bands when mode is "all_bands", and selected bands when mode is "selected_bands".

**Behavior 3: Block-Out Propagation on Create**

Verified in code (add_block_out_drawer.dart):

```dart
// After primary save to active band
final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userId, userBandIds);
final otherBandIds = bandIds.where((id) => id != widget.bandId).toList();
for (final bandId in otherBandIds) {
  await repository.createBlockOut(bandId: bandId, ...);
}
```

✅ **CONFIRMED:** Block-out dates are created for all bands returned by getBandIdsToApplyBlockOut, excluding the current band.

**Behavior 4: Delete Propagation**

Verified in code (add_block_out_drawer.dart):

```dart
// Check if One Calendar applies to multiple bands
final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userId, userBandIds);
if (bandIds.isNotEmpty && bandIds.length > 1) {
  shouldShowChoice = true;
}
// Show choice dialog: "This band only" or "All bands"
if (deleteChoice == 'all_bands') {
  for (final bandId in bandIdsToDeleteFrom) {
    await repository.deleteBlockOutSpan(...);
  }
}
```

✅ **CONFIRMED:** Choice dialog shown when One Calendar applies to 2+ bands, both delete paths implemented correctly.

**Behavior 5: Auto-Conflict Blocking**

Verified in code (auto_conflict_blocking_service.dart + events_repository.dart):

```dart
// Service checks preferences
if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) { return; }

// EventsRepository fetches band name
final bandResponse = await supabase.from('bands').select('name').eq('id', bandId).single();
final bandName = bandResponse['name'] as String;

// Service creates block-out with band name in reason
final reason = 'Unavailable (scheduled with $bandName)';
```

✅ **CONFIRMED:** Auto-conflict blocking checks preferences, fetches band name from database, creates block-out dates on other bands with reason containing band name.

**Behavior 6: Graceful Degradation**

Verified in code:

```dart
// Block-out propagation
try { ...propagation logic... }
catch (e) { debugPrint('...propagation error: $e'); }  // Does not rethrow

// Auto-conflict blocking
try { ...auto-blocking logic... }
catch (e) { debugPrint('...Auto-conflict blocking failed: $e'); }  // Does not rethrow
```

✅ **CONFIRMED:** Both propagation and auto-blocking wrapped in try-catch, errors logged but do not throw, primary operations complete successfully.

**No Extra Behavior Added:** All implemented behavior matches Architect scope. No features added outside plan.

---

### Phase 7 — Regression Check ✅

**System Impact Review:**

**Affected Systems:**

1. **Gigs** — Auto-conflict blocking integrated in EventsRepository.createGig()
   - Risk: Additional async operation after gig creation
   - Mitigation: Wrapped in try-catch, does not block primary operation ✅
   - Regression: None detected (code analysis)

2. **Rehearsals** — Auto-conflict blocking integrated in EventsRepository.createRehearsal()
   - Risk: Additional async operation after rehearsal creation
   - Mitigation: Wrapped in try-catch, does not block primary operation ✅
   - Regression: None detected (code analysis)

3. **Calendar** — Block-out propagation added to BlockOutDrawer
   - Risk: Additional async operations in save/delete flows
   - Mitigation: Wrapped in try-catch, primary operations complete first ✅
   - Regression: None detected (code analysis)

4. **Settings** — Conditional menu item added
   - Risk: UI logic depends on band count
   - Mitigation: Simple length check, no complex logic ✅
   - Regression: Existing settings items unchanged ✅

5. **Routing** — New route for OneCalendarSettingsScreen
   - Risk: None (additive only)
   - Regression: None detected

**Unaffected Systems Verified:**

- Setlists / Catalog: No changes ✅
- Members / RBAC: No changes ✅
- Auth / Session: No changes ✅
- Notifications: No changes ✅
- Platform (iOS / Android / Web / macOS): All platforms supported equally ✅

**Critical Safety Checks:**

- ✅ Auth and session behavior: No changes to auth flow
- ✅ Supabase RPC calls: New RPCs added, signatures match Dart client calls, all parameters passed explicitly
- ✅ Initialization order: No changes to main.dart or initialization sequence
- ✅ Controller disposal: No new controllers/FocusNodes requiring disposal
- ✅ setState after async gaps: BlockOutDrawer.\_handleDelete() includes `if (!mounted) return;` guard after async prefs lookup
- ✅ Rebuild triggers: No new watchers added that would cause excessive rebuilds

**Regression Risk Level:** **MEDIUM**

- Feature is opt-in (default: One Calendar disabled)
- Single-band users never see the feature
- Block-out propagation is additive, does not modify existing logic
- Auto-conflict blocking should be non-blocking (verified via code)
- Error handling prevents cascading failures

---

### Phase 8 — Database Safety ✅

**Migration File:** `supabase/migrations/20260626005216_add_user_calendar_preferences.sql`

**Table Schema Verification:**

```sql
CREATE TABLE user_calendar_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  one_calendar_enabled BOOLEAN NOT NULL DEFAULT false,
  apply_to_mode TEXT NOT NULL DEFAULT 'all_bands' CHECK (...),
  selected_band_ids UUID[] DEFAULT '{}',
  auto_block_conflicts_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);
```

✅ **Schema matches Architect plan**
✅ **Unique constraint on user_id enforces one row per user**
✅ **CHECK constraint on apply_to_mode validates enum values**

**RLS Policies Verification:**

```sql
CREATE POLICY "Users can view their own calendar preferences"
  ON user_calendar_preferences FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "Users can insert their own calendar preferences"
  ON user_calendar_preferences FOR INSERT
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own calendar preferences"
  ON user_calendar_preferences FOR UPDATE
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

✅ **RLS policies do NOT self-reference** (use external auth.uid())
✅ **No privilege escalation** (users can only access their own preferences)
✅ **No DELETE policy** (as designed — preferences persist)
✅ **No infinite recursion risk**

**RPC Function Signatures:**

Function: `get_or_create_calendar_preferences(p_user_id UUID)`

- ✅ SECURITY INVOKER (uses RLS)
- ✅ SET search_path = public
- ✅ Returns JSONB
- ✅ Creates default row if missing

Function: `update_calendar_preferences(p_user_id UUID, p_one_calendar_enabled BOOLEAN, p_apply_to_mode TEXT, p_selected_band_ids UUID[], p_auto_block_conflicts_enabled BOOLEAN)`

- ✅ SECURITY INVOKER (uses RLS)
- ✅ SET search_path = public
- ✅ Validates apply_to_mode with RAISE EXCEPTION
- ✅ Returns JSONB

**Dart Client Call Verification:**

Repository calls (one_calendar_preferences_repository.dart):

```dart
await supabase.rpc('get_or_create_calendar_preferences', params: {'p_user_id': userId});
await supabase.rpc('update_calendar_preferences', params: {
  'p_user_id': prefs.userId,
  'p_one_calendar_enabled': prefs.oneCalendarEnabled,
  'p_apply_to_mode': prefs.applyToMode.value,
  'p_selected_band_ids': prefs.selectedBandIds,
  'p_auto_block_conflicts_enabled': prefs.autoBlockConflictsEnabled,
});
```

✅ **All parameters match RPC signatures**
✅ **Correct types (String, bool, List<String>)**
✅ **No missing or extra parameters**

**Cascade Behavior:**

- ✅ ON DELETE CASCADE from auth.users (standard pattern, appropriate)
- ✅ No unintended cascades that could cause data loss

**Trigger Verification:**

```sql
CREATE TRIGGER update_user_calendar_preferences_updated_at
  BEFORE UPDATE ON user_calendar_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

✅ **Standard pattern using existing function**
✅ **No side effects or recursion risk**

**Index Verification:**

```sql
CREATE INDEX idx_user_calendar_preferences_user_id ON user_calendar_preferences(user_id);
```

✅ **Appropriate for lookup performance**

**Database Safety Result:** **PASS** — No safety issues detected.

---

### Phase 9 — Run Baseline Validation ✅

**Command:** `flutter analyze`

**Result:**

```
Analyzing bandroadie...

   info • 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup
          ancestor to manage group value instead. This feature was deprecated
          after v3.32.0-0.0.pre •
          lib/features/calendar/one_calendar_settings_screen.dart:315:15 •
          deprecated_member_use
   info • 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to
          handle value change instead. This feature was deprecated after
          v3.32.0-0.0.pre •
          lib/features/calendar/one_calendar_settings_screen.dart:316:15 •
          deprecated_member_use

2 issues found. (ran in 4.8s)
```

✅ **0 analyzer errors**
✅ **2 info warnings (Flutter framework deprecation, cosmetic only)**

**Note on Radio Deprecation Warnings:**

- These are Flutter framework-level deprecations introduced in v3.32.0+
- The warnings are informational only, not errors
- Radio widgets still function correctly (RadioGroup is the newer recommended pattern)
- This is a framework evolution issue, not a bug in the feature implementation
- Runtime behavior is unaffected

**Tests:**

No test requirements specified in Architect plan. Tests not run.

**Deployment:**

```bash
supabase db push
# Output: "Remote database is up to date."

supabase migration list
# Output: Migration 20260626005216 present in both Local and Remote columns
```

✅ **Migration successfully deployed to remote database**

---

### Phase 10 — Diff Safety Review ✅

**Files Modified:**

1. `lib/features/calendar/widgets/add_block_out_drawer.dart`
2. `lib/features/events/events_repository.dart`
3. `lib/features/settings/settings_screen.dart`

**Files Created:**

1. `supabase/migrations/20260626005216_add_user_calendar_preferences.sql`
2. `lib/features/calendar/models/one_calendar_preferences.dart`
3. `lib/features/calendar/one_calendar_preferences_repository.dart`
4. `lib/features/calendar/one_calendar_preferences_controller.dart`
5. `lib/features/calendar/one_calendar_settings_screen.dart`
6. `lib/features/calendar/auto_conflict_blocking_service.dart`

**Diff Safety Checks:**

✅ **No secrets or API keys** (reviewed all new files and migrations)
✅ **No environment variables or config outside approved scope** (uses existing supabase client)
✅ **No hardcoded credentials** (all auth via supabase.auth.currentUser)
✅ **Debug artifacts appropriate** (debugPrint statements follow existing pattern with [ClassName] prefix)
✅ **No TODO hacks or temporary flags** (no TODOs or FIXME comments)
✅ **No test scaffolding in production code** (no test-only code paths)
✅ **No accidental file deletions** (only additions and modifications)
✅ **No formatting-only changes to unrelated files** (some minor spacing cleanup in events_repository.dart, acceptable)

**Debug Logging Review:**

All debugPrint statements follow the existing pattern:

- `[BlockOutDrawer] ...` — appropriate logging for save/delete operations
- `[EventsRepository] ...` — appropriate logging for auto-blocking integration
- `[OneCalendarPreferencesRepository] ...` — appropriate logging for preferences operations
- `[AutoConflictBlockingService] ...` — appropriate logging for auto-blocking service

✅ **All debug statements are appropriate and follow project conventions**

**Diff Safety Result:** **PASS** — No safety issues detected in diff.

---

## Required Regression Areas Verification

**All regression areas verified via code-path analysis (not runtime testing).**

### 1. One Calendar Settings — Toggle Visibility ✅

**Requirement:** Toggle appears only for users with 2+ bands; hidden for single-band users.

**Code Verification (settings_screen.dart):**

```dart
final bandCount = ref.watch(activeBandProvider).userBands.length;
if (bandCount >= 2) {
  regularItems.add(SettingsItem(
    icon: AppIcons.calendar,
    label: 'One Calendar',
    subtitle: 'Share block-out dates across bands',
    onTap: _openOneCalendar,
  ));
}
```

✅ **CONFIRMED:** Settings item only appears when `bandCount >= 2`. Single-band users (bandCount = 1) will not see the menu item.

---

### 2. Apply To — All Bands ✅

**Requirement:** Block-out date propagates to all other bands on save.

**Code Verification (one_calendar_preferences_repository.dart):**

```dart
if (prefs.applyToMode == ApplyToMode.allBands) {
  return userBandIds;  // Returns all user's band IDs
}
```

**Code Verification (add_block_out_drawer.dart):**

```dart
final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userId, userBandIds);
final otherBandIds = bandIds.where((id) => id != widget.bandId).toList();
for (final bandId in otherBandIds) {
  await repository.createBlockOut(bandId: bandId, userId: userId, startDate: _startDate, untilDate: _untilDate, reason: _reasonController.text.trim());
}
```

✅ **CONFIRMED:** When apply_to_mode is "all_bands", getBandIdsToApplyBlockOut returns all user band IDs. Block-out is created for all bands except the current one.

---

### 3. Apply To — Selected Bands Only ✅

**Requirement:** Band picker works; block-out propagates only to chosen bands.

**Code Verification (one_calendar_preferences_repository.dart):**

```dart
// Apply to selected bands only
final selectedIds = prefs.selectedBandIds.where((id) => userBandIds.contains(id)).toList();
return selectedIds;
```

**Code Verification (one_calendar_settings_screen.dart):**

```dart
if (prefs.applyToMode == ApplyToMode.selectedBands) {
  ...userBands.map((band) {
    final isSelected = prefs.selectedBandIds.contains(band.id);
    return _BandCheckboxTile(
      bandName: band.name,
      isSelected: isSelected,
      onChanged: (selected) async {
        final updatedIds = List<String>.from(prefs.selectedBandIds);
        if (selected == true) {
          if (!updatedIds.contains(band.id)) { updatedIds.add(band.id); }
        } else {
          updatedIds.remove(band.id);
        }
        await ref.read(oneCalendarPreferencesProvider.notifier).updateSelectedBands(updatedIds);
      },
    );
  }),
}
```

✅ **CONFIRMED:** Band picker (checkboxes) appears when apply_to_mode is "selected_bands". Block-out propagates only to band IDs in the selected_band_ids list.

---

### 4. Delete Propagation ✅

**Requirement:** When One Calendar is enabled and user deletes a block-out, they are prompted: "This band only" or "All bands"; both paths execute correctly.

**Code Verification (add_block_out_drawer.dart):**

```dart
// Check One Calendar preferences
final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userId, userBandIds);
if (bandIds.isNotEmpty && bandIds.length > 1) {
  shouldShowChoice = true;
  bandIdsToDeleteFrom = bandIds;
}

if (shouldShowChoice) {
  // Show choice dialog
  deleteChoice = await showDialog<String>(
    ...
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, null), child: Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, 'this_band'), child: Text('This band only')),
      TextButton(onPressed: () => Navigator.pop(context, 'all_bands'), child: Text('All bands')),
    ],
  );
}

if (deleteChoice == 'all_bands') {
  for (final bandId in bandIdsToDeleteFrom) {
    await repository.deleteBlockOutSpan(userId: ..., bandId: bandId, ...);
  }
} else {
  // Delete from current band only
  await repository.deleteBlockOutSpan(userId: ..., bandId: widget.bandId, ...);
}
```

✅ **CONFIRMED:** Choice dialog shown when One Calendar applies to 2+ bands. "This band only" path deletes from current band. "All bands" path loops through all bands in propagation list.

---

### 5. Auto-Conflict Blocking ✅

**Requirement:** Creating a gig or rehearsal in one band blocks that date on other bands with the reason `"Unavailable (scheduled with [Band Name])"` — verify the actual band name appears.

**Code Verification (auto_conflict_blocking_service.dart):**

```dart
// Generate block-out reason
final reason = 'Unavailable (scheduled with $bandName)';

// Create block-out dates for other bands
for (final bandId in otherBandIds) {
  await _blockOutRepository.createBlockOut(
    bandId: bandId,
    userId: userId,
    startDate: blockOutDate,
    untilDate: null,  // Single day
    reason: reason,
  );
}
```

**Code Verification (events_repository.dart — createRehearsal and createGig):**

```dart
// Fetch band name for auto-conflict blocking reason
final bandResponse = await supabase.from('bands').select('name').eq('id', bandId).single();
final bandName = bandResponse['name'] as String;

await _autoConflictBlockingService.autoBlockConflictingDate(
  userId: userId,
  eventBandId: bandId,
  eventDate: firstRehearsal.date,  // or formData.date for gigs
  eventStartTime: null,
  eventEndTime: null,
  eventName: 'Rehearsal',  // or formData.name for gigs
  bandName: bandName,
);
```

✅ **CONFIRMED:** Band name is fetched from the `bands` table via SQL query. Band name is passed as a required parameter to the service. Reason string includes the actual band name via string interpolation.

---

### 6. Graceful Degradation ✅

**Requirement:** Propagation or auto-blocking failure does not prevent the primary operation from completing.

**Code Verification (add_block_out_drawer.dart — Block-out propagation):**

```dart
// Primary save to active band happens FIRST
await repository.createBlockOut(
  bandId: widget.bandId,
  userId: userId,
  startDate: _startDate,
  untilDate: _untilDate,
  reason: _reasonController.text.trim(),
);

// THEN propagation wrapped in try-catch
try {
  ...propagation logic...
} catch (e) {
  // Do not fail the primary save if propagation fails
  debugPrint('[BlockOutDrawer] One Calendar propagation error: $e');
  // Does NOT rethrow
}
```

**Code Verification (events_repository.dart — Auto-conflict blocking):**

```dart
// Event creation happens FIRST
final gigId = response['id'] as String;
invalidateCache(bandId);

// THEN auto-blocking wrapped in try-catch
try {
  ...auto-blocking logic...
} catch (e) {
  // Do not fail gig creation if auto-blocking fails
  debugPrint('[EventsRepository] Auto-conflict blocking failed: $e');
  // Does NOT rethrow
}
```

✅ **CONFIRMED:** Primary operations (create block-out, create gig, create rehearsal) complete successfully before propagation/auto-blocking runs. Errors in propagation/auto-blocking are caught, logged, and do NOT rethrow, ensuring primary operations always succeed.

---

### 7. Single-Band User ✅

**Requirement:** No One Calendar settings visible anywhere in the UI.

**Code Verification (settings_screen.dart):**

```dart
final bandCount = ref.watch(activeBandProvider).userBands.length;
if (bandCount >= 2) {
  regularItems.add(SettingsItem(...One Calendar...));
}
```

✅ **CONFIRMED:** If `bandCount < 2` (i.e., user belongs to only 1 band), the "One Calendar" menu item is not added to the settings list. Single-band users will not see this feature anywhere in the UI.

---

### 8. Existing Block-Out Flow ✅

**Requirement:** Unaffected for users with One Calendar disabled.

**Code Verification (one_calendar_preferences_repository.dart):**

```dart
if (!prefs.oneCalendarEnabled) {
  debugPrint('One Calendar disabled, returning empty list');
  return [];  // No propagation
}
```

**Code Verification (add_block_out_drawer.dart):**

```dart
// Primary block-out creation (unchanged)
await repository.createBlockOut(
  bandId: widget.bandId,
  userId: userId,
  startDate: _startDate,
  untilDate: _untilDate,
  reason: _reasonController.text.trim(),
);

// Propagation check
final bandIds = await prefsRepo.getBandIdsToApplyBlockOut(userId, userBandIds);
final otherBandIds = bandIds.where((id) => id != widget.bandId).toList();

// If getBandIdsToApplyBlockOut returns empty list (One Calendar disabled),
// otherBandIds will be empty, loop does not execute, no propagation occurs
for (final bandId in otherBandIds) { ... }
```

✅ **CONFIRMED:** When One Calendar is disabled, getBandIdsToApplyBlockOut returns an empty list. The propagation loop does not execute. Primary block-out creation flow is unchanged.

---

### 9. Existing Gig/Rehearsal Creation ✅

**Requirement:** Unaffected for users with One Calendar disabled.

**Code Verification (auto_conflict_blocking_service.dart):**

```dart
if (!prefs.oneCalendarEnabled || !prefs.autoBlockConflictsEnabled) {
  debugPrint('Auto-block disabled, skipping');
  return;  // Early return, no auto-blocking occurs
}
```

**Code Verification (events_repository.dart):**

```dart
// Event creation (unchanged)
final gigId = response['id'] as String;
invalidateCache(bandId);

// Auto-blocking wrapped in try-catch
try {
  await _autoConflictBlockingService.autoBlockConflictingDate(...);
} catch (e) {
  debugPrint('Auto-conflict blocking failed: $e');
  // Does NOT rethrow
}

// Return the created gig/rehearsal (unchanged)
return Gig.fromJson(gigWithDates);
```

✅ **CONFIRMED:** Auto-conflict service checks preferences and returns early if One Calendar or auto-blocking is disabled. Event creation flow completes normally. Even if auto-blocking were to fail, the try-catch ensures event creation is not blocked.

---

### Radio Deprecation Warnings ✅

**Note:** Radio deprecation warnings on the apply-to mode selector are cosmetic only and do not affect runtime behavior.

**Analyzer Output:**

```
info • 'groupValue' is deprecated and shouldn't be used. Use a RadioGroup
       ancestor to manage group value instead. This feature was deprecated
       after v3.32.0-0.0.pre •
       lib/features/calendar/one_calendar_settings_screen.dart:315:15 •
       deprecated_member_use
info • 'onChanged' is deprecated and shouldn't be used. Use RadioGroup to
       handle value change instead. This feature was deprecated after
       v3.32.0-0.0.pre •
       lib/features/calendar/one_calendar_settings_screen.dart:316:15 •
       deprecated_member_use
```

**Analysis:**

- These are Flutter framework-level deprecations introduced in v3.32.0+
- The warnings are informational (`info` level), not errors
- Radio widgets still function correctly (RadioGroup is the newer recommended pattern from Flutter)
- This is a framework evolution issue, not a bug in the feature implementation
- Runtime behavior is completely unaffected

✅ **CONFIRMED:** Cosmetic only. No functional impact.

---

### AppIcons.ban Icon ✅

**Note:** `AppIcons.ban` icon is semantically appropriate for the auto-conflict blocking toggle.

**Code Verification (one_calendar_settings_screen.dart):**

```dart
Icon(
  AppIcons.ban,
  color: enabled ? AppColors.primary : context.colors.textMuted,
  size: 24,
),
```

**Analysis:**

- `AppIcons.ban` is used for the "Automatically block conflicting dates" toggle
- The icon semantically represents "blocking" or "prohibition"
- This is appropriate for a feature that blocks dates on other calendars
- No `AppIcons.lock` or `AppIcons.lockClosed` exists in the codebase (as noted in Engineer Report)

✅ **CONFIRMED:** `AppIcons.ban` is semantically appropriate for the auto-conflict blocking toggle.

---

## Final Approval Checklist

✅ **All Architect tasks completed** (11/11)
✅ **All files created/modified match Architect plan**
✅ **0 analyzer errors** (2 cosmetic info warnings, non-blocking)
✅ **Database migration deployed successfully**
✅ **RLS policies verified safe** (no self-reference, no privilege escalation)
✅ **RPC signatures match Dart client calls**
✅ **Graceful error handling confirmed** (propagation/auto-blocking do not block primary operations)
✅ **No secrets or debug artifacts in diff**
✅ **All required regression areas verified** (9/9)
✅ **Regression risk: MEDIUM** (opt-in feature, single-band users unaffected)
✅ **No files outside approved scope modified**
✅ **No initialization order changes**
✅ **No architectural patterns changed**
✅ **Change surface minimal and appropriate**

---

## Recommendation

**✅ APPROVED FOR COMMIT**

This feature is ready for production deployment. All validations passed via code-path analysis. The implementation matches the Architect plan exactly. Database safety verified. Graceful error handling ensures no regressions to existing functionality.

**Post-Merge Actions:**

1. Monitor error logs for propagation/auto-blocking failures
2. Monitor Supabase query performance for user_calendar_preferences table
3. Gather user feedback on One Calendar feature adoption

---

**QA Validation Completed:** 2026-06-26
**QA Agent:** GitHub Copilot (Claude Sonnet 4.5)
**Validation Method:** Code-path analysis (not runtime testing)

- Rehearsals: affected (auto-conflict blocking integration)
- Calendar: affected (core feature)
- Settings: affected (new settings screen)
- Routing: affected (new route for OneCalendarSettingsScreen)
- All other systems: unaffected

### Phase 4 — Review Engineer Implementation ✅

**ENGINEER_REPORT.md Review:**

- ✅ All tasks marked complete
- ✅ Files created match Architect plan
- ✅ Files modified match Architect plan
- ✅ Analyzer results: 0 errors (2 deprecation info warnings only)
- ✅ Post-implementation fix documented (band name required parameter)
- ✅ No deviations from Architect plan
- ✅ No blockers reported
- ✅ Ready for QA: Yes

**git diff Review:**

**Modified Files Analysis:**

1. **`lib/features/calendar/widgets/add_block_out_drawer.dart`** (+40 lines)
   - ✅ Adds One Calendar propagation logic after primary block-out creation
   - ✅ Fetches preferences via repository
   - ✅ Resolves band IDs to propagate to based on preferences
   - ✅ Creates block-out dates for other bands in try-catch blocks
   - ✅ Graceful error handling (does not fail primary save)
   - ✅ Proper imports added
   - ✅ No unrelated changes

2. **`lib/features/events/events_repository.dart`** (+90 lines, -14 lines)
   - ✅ Adds `AutoConflictBlockingService` dependency injection
   - ✅ Constructor modified to accept service
   - ✅ Auto-conflict blocking integrated in `createRehearsal()` after success
   - ✅ Auto-conflict blocking integrated in `createGig()` after success
   - ✅ Fetches band name from database for block-out reason
   - ✅ Graceful error handling (does not fail event creation)
   - ✅ Provider updated to inject service dependency
   - ⚠️ Formatting-only changes (collection expression simplification) — acceptable
   - ⚠️ Multi-line string formatting — acceptable
   - ✅ No architectural changes
   - ✅ No unrelated functional changes

3. **`lib/features/settings/settings_screen.dart`** (+24 lines)
   - ✅ Adds "One Calendar" settings item
   - ✅ Conditional visibility: only if user has 2+ bands
   - ✅ Navigation to `OneCalendarSettingsScreen`
   - ✅ Proper imports added
   - ✅ No unrelated changes

**Created Files Analysis:**

4. **`supabase/migrations/20260626005216_add_user_calendar_preferences.sql`**
   - ✅ Creates `user_calendar_preferences` table with correct schema
   - ✅ RLS enabled
   - ✅ RLS policies: SELECT, INSERT, UPDATE (no DELETE) — correct
   - ✅ Policies filter by `user_id = auth.uid()` — correct
   - ✅ RPC: `get_or_create_calendar_preferences` — SECURITY INVOKER, `SET search_path = public` ✅
   - ✅ RPC: `update_calendar_preferences` — SECURITY INVOKER, `SET search_path = public` ✅
   - ✅ RPC parameter validation (apply_to_mode check)
   - ✅ Trigger: `update_user_calendar_preferences_updated_at` calls standard function
   - ✅ Index on `user_id` for performance
   - ✅ No RLS self-reference issues
   - ✅ No privilege escalation risks
   - ✅ Follows established migration patterns

5. **`lib/features/calendar/models/one_calendar_preferences.dart`**
   - ✅ Immutable model class
   - ✅ `ApplyToMode` enum with string values
   - ✅ `fromJson` / `toJson` / `copyWith` methods
   - ✅ Proper equality and hashCode overrides
   - ✅ Uses `listEquals` for array comparison
   - ✅ Follows established model patterns

6. **`lib/features/calendar/one_calendar_preferences_repository.dart`**
   - ✅ `getPreferences()` calls `get_or_create_calendar_preferences` RPC
   - ✅ `updatePreferences()` calls `update_calendar_preferences` RPC
   - ✅ `getBandIdsToApplyBlockOut()` implements business logic correctly
   - ✅ Debug logging present
   - ✅ Error handling with rethrow
   - ✅ Provider defined
   - ✅ Follows established repository patterns

7. **`lib/features/calendar/one_calendar_preferences_controller.dart`**
   - ✅ Uses `AsyncNotifier` pattern (not deprecated StateNotifier)
   - ✅ Methods: `toggleOneCalendar`, `setApplyToMode`, `updateSelectedBands`, `toggleAutoBlockConflicts`
   - ✅ Optimistic updates with rollback on error
   - ✅ Proper async/await handling
   - ✅ Provider defined
   - ✅ Follows established controller patterns

8. **`lib/features/calendar/one_calendar_settings_screen.dart`**
   - ✅ Master toggle for One Calendar
   - ✅ Apply-to mode radio buttons (all bands / selected bands)
   - ✅ Band picker (multi-select checkboxes) when "selected bands only" is active
   - ✅ Auto-conflict blocking toggle with description
   - ✅ Conditional visibility based on One Calendar enabled state
   - ✅ Error handling with snackbar feedback
   - ✅ Uses design tokens correctly
   - ✅ Follows established UI patterns
   - ⚠️ Uses deprecated `Radio.groupValue` and `Radio.onChanged` — Flutter framework deprecation (info warning only)

9. **`lib/features/calendar/auto_conflict_blocking_service.dart`**
   - ✅ Checks user's One Calendar preferences
   - ✅ Fetches user's bands from database internally
   - ✅ Resolves band IDs to propagate to based on preferences
   - ✅ Creates block-out dates with required `bandName` parameter
   - ✅ Block-out reason: `"Unavailable (scheduled with [Band Name])"`
   - ✅ Uses date-only (ignores time) for block-out dates
   - ✅ Graceful error handling per band
   - ✅ Debug logging
   - ✅ Provider defined with dependency injection
   - ✅ Correct method signature

### Phase 5 — Completeness Check ✅

**Architect Task Breakdown Review:**

**Phase 1: Database Migration**

- ✅ Task 1.1: Migration file created with correct schema, RLS, RPCs, triggers
- ❌ Task 1.2: Migration deployment **BLOCKED** (see Phase 8)

**Phase 2: Flutter Data Layer**

- ✅ Task 2.1: Model created with enum, fromJson, toJson, copyWith
- ✅ Task 2.2: Repository created with all required methods
- ✅ Task 2.3: Controller created with AsyncNotifier pattern and all methods

**Phase 3: Settings UI**

- ✅ Task 3.1: OneCalendarSettingsScreen created with all sections
- ✅ Task 3.2: SettingsScreen modified with conditional menu item

**Phase 4: Block-Out Propagation**

- ✅ Task 4.1: BlockOutDrawer modified with propagation logic in `_handleSave()`
- ⚠️ Task 4.2: Delete propagation **NOT IMPLEMENTED** (see deviation analysis below)

**Phase 5: Auto-Conflict Blocking**

- ✅ Task 5.1: AutoConflictBlockingService created
- ✅ Task 5.2: Integrated into GigRepository (via EventsRepository)
- ✅ Task 5.3: Integrated into RehearsalRepository (via EventsRepository)

**Deviation Analysis:**

The Architect plan Task 4.2 specified modifying `_handleDelete()` in BlockOutDrawer to prompt users "Delete from this band only" or "Delete from all bands" when One Calendar is enabled. This was **not implemented** in the Engineer's work.

**However**, the Architect plan Section "Out of Scope" does not explicitly list this as a deferred item. Task 4.2 was listed in the task breakdown.

**Assessment:** This is a **partial implementation**. The Engineer Report does not mention deferring Task 4.2 or provide justification for omitting it.

**Conclusion:** Implementation is incomplete. Delete propagation functionality is missing.

### Phase 6 — Behavior Verification ⚠️

**Validation Method:** Code path analysis only (runtime testing blocked by migration deployment failure)

**Feature Implementation Assessment:**

1. **One Calendar Toggle:**
   - Code path confirmed: Settings item visible only when `userBands.length >= 2`
   - Code path confirmed: Controller updates preferences via RPC
   - Code path confirmed: UI sections show/hide based on `oneCalendarEnabled` state
   - ✅ Matches Architect specification

2. **Apply-To Mode:**
   - Code path confirmed: Radio buttons update preferences
   - Code path confirmed: Repository resolves band IDs correctly based on mode
   - Code path confirmed: Band picker only shown when `ApplyToMode.selectedBands` is active
   - ✅ Matches Architect specification

3. **Block-Out Propagation:**
   - Code path confirmed: Propagation runs after primary save succeeds
   - Code path confirmed: Fetches preferences and user bands
   - Code path confirmed: Resolves band IDs via repository
   - Code path confirmed: Creates block-out dates for each other band
   - Code path confirmed: Errors do not fail primary operation
   - ✅ Matches Architect specification
   - ❌ Delete propagation: NOT IMPLEMENTED

4. **Auto-Conflict Blocking:**
   - Code path confirmed: Service called after gig/rehearsal creation
   - Code path confirmed: Checks preferences before proceeding
   - Code path confirmed: Fetches user bands from database
   - Code path confirmed: Creates block-out dates with band name in reason
   - Code path confirmed: Errors do not fail event creation
   - ✅ Matches Architect specification

**Runtime Verification Status:** ❌ **BLOCKED** — Cannot verify actual runtime behavior without deployed migration.

### Phase 7 — Regression Check ⚠️

**Cannot Perform Runtime Regression Testing** — Migration deployment blocked.

**Code Path Analysis for Regression Risk:**

**Affected Systems:**

1. **Calendar / Block-Out Creation:**
   - Change: Additional logic runs after primary block-out save
   - Risk: LOW — Propagation is additive, wrapped in try-catch, does not modify existing flow
   - Concern: None

2. **Gigs / Rehearsals Creation:**
   - Change: Auto-conflict blocking service called after event creation
   - Risk: LOW — Service call is additive, wrapped in try-catch, does not modify existing flow
   - Concern: Band name fetch adds extra query — could impact performance on slow connections

3. **Settings Screen:**
   - Change: Conditional menu item added
   - Risk: LOW — Only affects users with 2+ bands, no changes to existing items
   - Concern: None

4. **EventsRepository Constructor:**
   - Change: Now requires `AutoConflictBlockingService` dependency
   - Risk: LOW — Provider injection handles this, no manual instantiation in codebase
   - Concern: None

**Unaffected Systems:**

- ✅ Auth / Session: No changes
- ✅ Setlists / Catalog: No changes
- ✅ Members / RBAC: No changes
- ✅ Notifications: No changes
- ✅ Platform-specific code: No changes

**Regression Risk Assessment:** **LOW**

All changes are additive and opt-in. Single-band users see no changes. Multi-band users with One Calendar disabled see no behavior changes.

### Phase 8 — Database Safety ❌ **BLOCKED**

**Migration Deployment Status:** ❌ **FAILED**

**Error:**

```
Applying migration 073_fix_gig_responses_unique_constraint.sql...
ERROR: relation "gig_responses" does not exist (SQLSTATE 42P01)
```

**Root Cause:** Remote database is missing schema elements from earlier migrations (073-087 and others). The database state does not match the local migration history.

**Impact on Feature Migration:**
The One Calendar migration (`20260626005216_add_user_calendar_preferences.sql`) was **not applied** because the deployment process failed on an earlier migration.

**Migration Content Review (Static Analysis):**

**✅ Migration File Safety Checks:**

- ✅ Table schema matches Architect plan exactly
- ✅ RLS policies do NOT self-reference (no recursion risk)
- ✅ No privilege escalation (SECURITY INVOKER used)
- ✅ RPC functions include `SET search_path = public` (prevents search path attacks)
- ✅ Constraints are valid (CHECK constraint on apply_to_mode)
- ✅ Foreign key cascades are appropriate (ON DELETE CASCADE for user_id)
- ✅ Indexes defined for performance
- ✅ Trigger references existing function (`update_updated_at_column`)
- ✅ No destructive operations
- ✅ Migration is idempotent-safe (uses `IF EXISTS` where appropriate)

**RPC Function Signatures Match Dart Client Calls:**

**`get_or_create_calendar_preferences(p_user_id UUID)` → Returns JSONB**

- Dart calls: `supabase.rpc('get_or_create_calendar_preferences', params: {'p_user_id': userId})`
- ✅ Parameter name matches
- ✅ Return type compatible (JSONB → Map<String, dynamic>)

**`update_calendar_preferences(p_user_id, p_one_calendar_enabled, p_apply_to_mode, p_selected_band_ids, p_auto_block_conflicts_enabled)` → Returns JSONB**

- Dart calls: `supabase.rpc('update_calendar_preferences', params: {...})`
- ✅ All parameter names match
- ✅ All parameter types match
- ✅ Return type compatible

**Conclusion:** Migration file content is safe and correct. **However, deployment is blocked by database state issues unrelated to this feature.**

### Phase 9 — Run Baseline Validation ⚠️

**flutter analyze:**

```
2 issues found.
```

**Issues:**

1. ⚠️ `lib/features/calendar/one_calendar_settings_screen.dart:315:15` — `deprecated_member_use` — `Radio.groupValue` deprecated
2. ⚠️ `lib/features/calendar/one_calendar_settings_screen.dart:316:15` — `deprecated_member_use` — `Radio.onChanged` deprecated

**Assessment:**

- Both are **info-level warnings**, not errors
- Flutter framework deprecation (introduced in v3.32.0-0.0.pre)
- Does not affect runtime behavior
- Acceptable per Architect plan and Engineer report

**Analyzer Result:** ✅ **PASS** (0 errors)

**flutter test:**

❌ **NOT RUN** — Architect plan does not require tests, Engineer report states "Not run — no specific test requirements in Architect plan"

### Phase 10 — Diff Safety Review ✅

**Secrets / API Keys:** ✅ None present

**Environment Variables / Config:** ✅ No changes outside approved scope

**Debug Artifacts:**

- ✅ `debugPrint` statements present — appropriate for repository and service layers
- ✅ No `print()` calls
- ✅ No TODO comments or temporary flags

**Test Scaffolding:** ✅ None in production code

**Accidental File Deletions:** ✅ None

**Diff Safety Result:** ✅ **PASS**

---

## Required Regression Testing

**Status:** ❌ **NOT PERFORMED** — Blocked by migration deployment failure

### Planned Tests (Not Executed)

**1. One Calendar Settings Visibility**

- [ ] User with 1 band: "One Calendar" settings item is hidden
- [ ] User with 2+ bands: "One Calendar" settings item is visible

**2. Apply To — All Bands**

- [ ] Block-out date propagates to all other bands on save
- [ ] Block-out reason is preserved across all bands

**3. Apply To — Selected Bands Only**

- [ ] Band picker works; block-out propagates only to chosen bands
- [ ] Non-selected bands do not receive block-out date

**4. Auto-Conflict Blocking**

- [ ] Creating a gig in one band blocks that date on other bands
- [ ] Creating a rehearsal in one band blocks that date on other bands
- [ ] Block-out reason reads `"Unavailable (scheduled with [Band Name])"`
- [ ] Actual band name appears (not fallback string)

**5. Graceful Degradation**

- [ ] Propagation failure does not prevent primary block-out from being saved
- [ ] Auto-blocking failure does not prevent gig/rehearsal from being created

**6. Single-Band User**

- [ ] No One Calendar settings visible anywhere in the UI
- [ ] No behavior changes to existing block-out or event creation flows

**7. Existing Block-Out Flow**

- [ ] Unaffected for users with One Calendar disabled
- [ ] Block-out creation, editing, deletion work as before

**8. Existing Gig/Rehearsal Creation**

- [ ] Unaffected for users with One Calendar disabled
- [ ] Event creation works as before

---

## Issues Identified

### BLOCKING ISSUE 1: Database Migration Deployment Failed

**Severity:** CRITICAL

**Description:**
Database migration deployment failed with error:

```
ERROR: relation "gig_responses" does not exist (SQLSTATE 42P01)
At statement: 0
-- Drop the old constraint
ALTER TABLE gig_responses
DROP CONSTRAINT IF EXISTS gig_responses_gig_user_unique
```

**Root Cause:**
Remote Supabase database is out of sync with local migration history. Migrations 073-087 and others (20260109 onwards) were never applied to the remote database.

**Impact:**

- Cannot deploy One Calendar migration
- Cannot verify database schema
- Cannot test RPC functions
- Cannot perform runtime validation
- Feature is completely untestable

**Required Action:**
Database administrator must synchronize remote database state with local migration history before this feature can be deployed.

### BLOCKING ISSUE 2: Delete Propagation Not Implemented

**Severity:** HIGH

**Description:**
Architect plan Task 4.2 specifies that when a user deletes a block-out date with One Calendar enabled, they should be prompted:

- "Delete from this band only"
- "Delete from all bands"

This functionality was **not implemented**. The `_handleDelete()` method in `BlockOutDrawer` was not modified.

**Impact:**

- Users can create cross-band block-out dates but cannot delete them across all bands in one action
- Asymmetric behavior: propagation on create, but not on delete
- Users must manually delete block-out dates from each band individually

**Code Location:**
`lib/features/calendar/widgets/add_block_out_drawer.dart` — `_handleDelete()` method

**Required Action:**
Implement delete propagation logic as specified in Architect plan Task 4.2.

---

## Deprecation Warnings Assessment

**Radio Deprecation Warnings:**

The `OneCalendarSettingsScreen` uses `Radio.groupValue` and `Radio.onChanged`, both deprecated in Flutter v3.32.0-0.0.pre in favor of `RadioGroup`.

**Assessment:**

- Info-level warnings only (not errors)
- Does not affect runtime behavior
- Flutter framework change, not application bug
- Acceptable for current deployment

**Recommendation:**
Add to technical debt backlog to migrate to `RadioGroup` when convenient, but not blocking for this feature.

---

## AppIcons.ban Semantic Appropriateness

**Icon Used:** `AppIcons.ban` (for auto-conflict blocking toggle)

**Context:** The icon represents the action of automatically blocking dates on other bands when a gig/rehearsal is scheduled.

**Assessment:**

- ✅ Semantically appropriate — "ban" suggests blocking/preventing access
- ✅ Visually distinct from other icons
- ✅ Aligns with feature purpose

**Conclusion:** Icon choice is acceptable.

---

## Code Quality Observations

### Strengths

1. **Consistent Patterns:** All new code follows established BandRoadie patterns (Riverpod controllers, repository layer, model structure)
2. **Error Handling:** Graceful degradation throughout — propagation/auto-blocking failures do not break primary operations
3. **Debug Logging:** Comprehensive debug logging for troubleshooting
4. **Type Safety:** Proper use of Dart type system, no unsafe casts
5. **Immutability:** Models are properly immutable with copyWith methods
6. **Dependency Injection:** Correct use of Riverpod providers for dependency injection

### Areas for Improvement

1. **Delete Propagation Missing:** Task 4.2 not implemented
2. **Performance Consideration:** Auto-conflict blocking adds an extra database query (band name fetch) on every gig/rehearsal creation — consider caching band names if this becomes a bottleneck

---

## Validation Summary

| Phase                          | Status      | Result                               |
| ------------------------------ | ----------- | ------------------------------------ |
| Phase 0: Load Rules            | ✅ Complete | Pass                                 |
| Phase 1: Verify Workspace      | ✅ Complete | Pass                                 |
| Phase 2: Resolve Slug          | ✅ Complete | Pass                                 |
| Phase 3: Extract Baseline      | ✅ Complete | Pass                                 |
| Phase 4: Review Implementation | ✅ Complete | Pass (with noted deviation)          |
| Phase 5: Completeness Check    | ⚠️ Complete | Partial (delete propagation missing) |
| Phase 6: Behavior Verification | ❌ Blocked  | Cannot verify runtime behavior       |
| Phase 7: Regression Check      | ❌ Blocked  | Cannot perform runtime testing       |
| Phase 8: Database Safety       | ❌ Blocked  | Migration deployment failed          |
| Phase 9: Baseline Validation   | ✅ Complete | Pass (0 errors, 2 info warnings)     |
| Phase 10: Diff Safety          | ✅ Complete | Pass                                 |

---

## Final Verdict

**QA STATUS: REQUIRES CHANGES**

**Blocking Issues:**

1. Database migration deployment failed — remote database state mismatch
2. Delete propagation functionality not implemented (Architect plan Task 4.2)

**Next Steps:**

1. **Database Administrator:** Synchronize remote database with local migration history
2. **Engineer:** Implement delete propagation logic as specified in Task 4.2
3. **QA:** Re-run validation after above items are resolved

**Code Quality:** Implementation quality is high where completed. Code follows established patterns, includes proper error handling, and has minimal regression risk.

**Readiness for Production:** ❌ **NOT READY** — Cannot deploy until blocking issues are resolved.

---

## QA Validation Metadata

- **QA Agent:** GitHub Copilot (Claude Sonnet 4.5)
- **Validation Date:** 2026-06-26
- **Branch:** `feature/one-calendar-shared-blockout`
- **Validation Method:** Code path analysis only (runtime testing blocked)
- **Analyzer Version:** Flutter 3.32.0+
- **Database:** Supabase (deployment blocked)

---

**Report Status:** COMPLETE
**Validation Completeness:** PARTIAL (runtime validation blocked)
**Recommendation:** DO NOT MERGE — Resolve blocking issues first
