# ARCHITECT PLAN: Rehearsal Potential Dates UI Parity

**Slug:** `feature/rehearsal-potential-dates-ui-parity`  
**Branch:** `feature/rehearsal-potential-dates-ui-parity`  
**Type:** Feature  
**Confidence:** HIGH (all root causes confirmed in code)  
**Database changes required:** None  
**STOP required:** No

---

## 1. Feature Summary

The Edit Rehearsal screen (Potential toggle ON) must display each proposed date as a separate section with per-date member availability pills and per-date YES/NO buttons — matching the Edit Gig screen's per-date layout for multi-date potential gigs.

Currently:

- Edit Gig (multi-date potential): renders one section per proposed date with member availability pills and YES/NO buttons scoped to that date ✅
- Edit Rehearsal (multi-date potential): renders a flat list of proposed dates (icons + text), then a single shared member availability grid and a single YES/NO toggle at the bottom ❌

---

## 2. Key Finding: No Database Migration Required

Migration `20260519160119_add_rehearsal_multi_date_support.sql` **already applied** the following schema:

- `rehearsal_dates` table: `(id, rehearsal_id, date, start_time, created_at, updated_at)` with RLS
- `rehearsal_date_id UUID REFERENCES rehearsal_dates(id) ON DELETE CASCADE` on `rehearsal_responses`
- Unique constraint: `(rehearsal_id, user_id, COALESCE(rehearsal_date_id, '00000000-0000-0000-0000-000000000000'::uuid))`
- `get_band_full_state` RPC includes `rehearsal_dates` in the rehearsals payload

This is a **client-side only implementation gap**. The data layer is complete; the repository methods and UI components were never wired up for per-date display.

---

## 3. Root Cause Diagnosis

### Gap 1 — `RehearsalResponse` Dart model missing `rehearsalDateId`

**File:** `lib/app/models/rehearsal_response.dart`  
The model has `rehearsalId`, `userId`, `response` — but no `rehearsalDateId`. The DB column `rehearsal_date_id` is present but not mapped in `fromJson`/`toJson`.

### Gap 2 — `RehearsalResponseRepository` missing `fetchAllDateResponses`

**File:** `lib/features/rehearsals/rehearsal_response_repository.dart`  
The gig equivalent `GigResponseRepository.fetchAllDateResponses()` returns `Map<String, Map<String, String?>>` (date key → member userId → response). No equivalent method exists for rehearsals. The drawer's `_loadPerDateAvailability()` calls only the gig version.

> Note: `upsertResponseForDate`, `_performUpsertForDate`, and `deleteResponseForDate` **already exist** in the repository. Only `fetchAllDateResponses` is missing.

### Gap 3 — `fetchAllMemberResponses` and `fetchUserResponse` don't filter `rehearsal_date_id IS NULL`

**File:** `lib/features/rehearsals/rehearsal_response_repository.dart`

- `fetchUserResponse()` does not add `.isFilter('rehearsal_date_id', null)` — it may return per-date responses for the primary date field
- `fetchAllMemberResponses()` does not add `.isFilter('rehearsal_date_id', null)` — same issue
- `_performUpsert()` does not explicitly set `'rehearsal_date_id': null` on insert

The gig equivalents correctly use `.isFilter('gig_date_id', null)` for primary-date-only queries.

### Gap 4 — `RehearsalFormFields` widget renders single-date layout only

**File:** `lib/features/events/widgets/rehearsal_form_fields.dart`  
`_buildPotentialToggle()` always renders:

1. A flat `_buildProposedDatesSection()` list (icons + date text — no availability)
2. A single shared `ButtonGroupGrid<MemberVM>` for all members
3. A single `_buildUserAvailabilitySection()` below

It has no `_buildMultiDateAvailabilitySection()` or `_buildPerDateSection()` equivalents, and no `perDateAvailability`, `existingDateIds`, `onPerDateResponseChanged`, or `currentUserId` constructor parameters.

### Gap 5 — `EventEditorDrawer._loadPerDateAvailability()` is gig-only

**File:** `lib/features/events/widgets/event_editor_drawer.dart` (line ~2406)  
`_loadPerDateAvailability()` early-returns if `gigId == null` using `widget.existingEventId` — this works for both event types — but then calls only `gigResponseRepositoryProvider.fetchAllDateResponses()`. It needs to branch on `_eventType`.

### Gap 6 — Rehearsal save path doesn't call `_savePerDateResponses()`

**File:** `lib/features/events/widgets/event_editor_drawer.dart` (line ~1304)  
The rehearsal edit path (lines ~1304–1330) calls only single-date `upsertResponse()`. The gig path calls `_savePerDateResponses()` when `_isPotentialGig && _isMultiDate && _perDateAvailability.isNotEmpty`. No equivalent call exists for rehearsals.

`_savePerDateResponses()` is also gig-only — it calls `gigResponseRepositoryProvider.upsertResponseForDate()`.

### Gap 7 — `_createRehearsalFormFields()` doesn't pass per-date params

**File:** `lib/features/events/widgets/event_editor_drawer.dart` (line ~1703)  
The call to `RehearsalFormFields(...)` does not pass:

- `perDateAvailability`
- `isLoadingPerDateAvailability`
- `existingDateIds`
- `onPerDateResponseChanged`
- `currentUserId`

---

## 4. Files to Modify

| File                                                         | Nature of Change                                                                    |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `lib/app/models/rehearsal_response.dart`                     | Add `rehearsalDateId` field                                                         |
| `lib/features/rehearsals/rehearsal_response_repository.dart` | Fix primary-date filters; add `fetchAllDateResponses`                               |
| `lib/features/events/widgets/rehearsal_form_fields.dart`     | Add per-date params + `_buildMultiDateAvailabilitySection` + `_buildPerDateSection` |
| `lib/features/events/widgets/event_editor_drawer.dart`       | Branch load/save for rehearsals; pass per-date params to form                       |

---

## 5. Detailed Implementation

### A. `lib/app/models/rehearsal_response.dart`

Add `final String? rehearsalDateId;` to the class.

```dart
class RehearsalResponse {
  final String id;
  final String rehearsalId;
  final String userId;
  final String? rehearsalDateId;   // ADD: null = primary date
  final RehearsalResponseType response;
  final DateTime createdAt;
  final DateTime updatedAt;
```

Update constructor:

```dart
  const RehearsalResponse({
    required this.id,
    required this.rehearsalId,
    required this.userId,
    this.rehearsalDateId,          // ADD
    required this.response,
    required this.createdAt,
    required this.updatedAt,
  });
```

Update `fromJson`:

```dart
  factory RehearsalResponse.fromJson(Map<String, dynamic> json) {
    return RehearsalResponse(
      id: json['id'] as String,
      rehearsalId: json['rehearsal_id'] as String,
      userId: json['user_id'] as String,
      rehearsalDateId: json['rehearsal_date_id'] as String?,  // ADD
      response: _parseResponse(json['response'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
```

Update `toJson`:

```dart
  Map<String, dynamic> toJson() {
    return {
      'rehearsal_id': rehearsalId,
      'user_id': userId,
      if (rehearsalDateId != null) 'rehearsal_date_id': rehearsalDateId,  // ADD
      'response': response.name,
    };
  }
```

---

### B. `lib/features/rehearsals/rehearsal_response_repository.dart`

#### B1. Fix `fetchUserResponse` to scope to primary date only

```dart
Future<String?> fetchUserResponse({
  required String rehearsalId,
  required String userId,
}) async {
  final response = await supabase
      .from('rehearsal_responses')
      .select('response')
      .eq('rehearsal_id', rehearsalId)
      .eq('user_id', userId)
      .isFilter('rehearsal_date_id', null)   // ADD
      .maybeSingle();

  if (response == null) return null;
  return response['response'] as String?;
}
```

#### B2. Fix `fetchAllMemberResponses` to scope to primary date only

In the query for `rehearsal_responses`, add `.isFilter('rehearsal_date_id', null)`:

```dart
final responsesResponse = await supabase
    .from('rehearsal_responses')
    .select('user_id, response')
    .eq('rehearsal_id', rehearsalId)
    .isFilter('rehearsal_date_id', null);   // ADD
```

#### B3. Fix `_performUpsert` to explicitly set `rehearsal_date_id: null`

In the insert branch:

```dart
await supabase.from('rehearsal_responses').insert({
  'rehearsal_id': rehearsalId,
  'rehearsal_date_id': null,   // ADD — ensures unique constraint targets primary date slot
  'user_id': userId,
  'response': response,
});
```

Also scope update and lookup queries to `rehearsal_date_id IS NULL`:

```dart
final existing = await supabase
    .from('rehearsal_responses')
    .select('id')
    .eq('rehearsal_id', rehearsalId)
    .eq('user_id', userId)
    .isFilter('rehearsal_date_id', null)   // ADD
    .maybeSingle();
```

Update query:

```dart
await supabase
    .from('rehearsal_responses')
    .update({'response': response, 'updated_at': now})
    .eq('rehearsal_id', rehearsalId)
    .eq('user_id', userId)
    .isFilter('rehearsal_date_id', null);   // ADD
```

#### B4. Add `fetchAllDateResponses`

Mirror `GigResponseRepository.fetchAllDateResponses` exactly, using `rehearsal_responses` and `rehearsal_date_id`:

```dart
/// Fetch member availability for ALL dates of a multi-date potential rehearsal.
/// Returns a map keyed by 'primary' (primary date) or rehearsalDateId (additional dates).
/// Each value is a map of userId → response ('yes', 'no', or null for not responded).
Future<Map<String, Map<String, String?>>> fetchAllDateResponses({
  required String rehearsalId,
  required String bandId,
  required List<String> rehearsalDateIds,
}) async {
  debugPrint(
    '[RehearsalResponseRepository] fetchAllDateResponses: rehearsalId=$rehearsalId, dates=${rehearsalDateIds.length}',
  );

  // Get all active band members
  final membersResponse = await supabase
      .from('band_members')
      .select('user_id')
      .eq('band_id', bandId)
      .eq('status', 'active');

  final memberIds =
      membersResponse.map((m) => m['user_id'] as String).toList();

  // Initialize result map
  final result = <String, Map<String, String?>>{};

  // Initialize primary date with all members as not responded
  result['primary'] = {for (var id in memberIds) id: null};

  // Initialize each additional date
  for (final dateId in rehearsalDateIds) {
    result[dateId] = {for (var id in memberIds) id: null};
  }

  // Get ALL responses for this rehearsal (all dates)
  final responsesResponse = await supabase
      .from('rehearsal_responses')
      .select('user_id, response, rehearsal_date_id')
      .eq('rehearsal_id', rehearsalId);

  // Populate responses
  for (final r in responsesResponse) {
    final userId = r['user_id'] as String;
    final response = r['response'] as String?;
    final rehearsalDateId = r['rehearsal_date_id'] as String?;

    final dateKey = rehearsalDateId ?? 'primary';
    if (result.containsKey(dateKey) && memberIds.contains(userId)) {
      result[dateKey]![userId] = response;
    }
  }

  debugPrint(
    '[RehearsalResponseRepository] Loaded responses for ${result.length} dates',
  );
  return result;
}
```

---

### C. `lib/features/events/widgets/rehearsal_form_fields.dart`

#### C1. Add new constructor parameters

```dart
const RehearsalFormFields({
  // ... existing params ...

  // Per-date availability (for multi-date potential rehearsals in edit mode)
  this.perDateAvailability = const {},
  this.isLoadingPerDateAvailability = false,
  this.existingDateIds = const {},
  this.onPerDateResponseChanged,
  this.currentUserId,
});
```

Add the corresponding field declarations:

```dart
// Per-date availability (multi-date potential rehearsals)
final Map<String, Map<String, String?>> perDateAvailability;
final bool isLoadingPerDateAvailability;
final Map<DateTime, String> existingDateIds;
final void Function(DateTime date, bool isPrimaryDate, String response)?
    onPerDateResponseChanged;
final String? currentUserId;
```

#### C2. Update `_buildPotentialToggle` to branch on multi-date edit mode

Replace the member grid section within `_buildPotentialToggle`. Current code:

```dart
if (additionalDates.isNotEmpty) ...[
  _buildProposedDatesSection(context),
  const SizedBox(height: Spacing.space12),
],
if (membersState.isLoading || isLoadingMemberAvailability)
  ...loading indicator...
else ...[
  ButtonGroupGrid<MemberVM>(...),
  if (isEditMode && existingEventId != null)
    _buildUserAvailabilitySection(context),
],
```

Replace with:

```dart
final isMultiDateEditMode =
    isEditMode && existingEventId != null && additionalDates.isNotEmpty;

AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOut,
  alignment: Alignment.topCenter,
  child: isMultiDateEditMode
      ? _buildMultiDateAvailabilitySection(
          context, members, membersState.isLoading)
      : Column(
          children: [
            if (additionalDates.isNotEmpty) ...[
              _buildProposedDatesSection(context),
              const SizedBox(height: Spacing.space12),
            ],
            if (membersState.isLoading || isLoadingMemberAvailability)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              )
            else ...[
              ButtonGroupGrid<MemberVM>(
                items: members,
                labelBuilder: (member) =>
                    _getMemberLabel(member, members),
                labelWidgetBuilder: (member) =>
                    _buildMemberLabelWidget(
                        context, member, members, memberAvailability),
                isSelected: (_) => false,
                availabilityMode: true,
                availabilityState: (member) {
                  final response = memberAvailability[member.userId];
                  if (response == 'yes') return AvailabilityState.available;
                  if (response == 'no') return AvailabilityState.notAvailable;
                  return AvailabilityState.notResponded;
                },
                onTap: null,
              ),
              if (isEditMode && existingEventId != null)
                _buildUserAvailabilitySection(context),
            ],
          ],
        ),
),
```

#### C3. Add `_buildMultiDateAvailabilitySection`

```dart
Widget _buildMultiDateAvailabilitySection(
  BuildContext context,
  List<MemberVM> members,
  bool isLoading,
) {
  // Build (date, timeDisplay) pairs sorted by date
  final allEntries = <(DateTime, String)>[
    (selectedDate, primaryStartTime),
    ...additionalDates.map((e) => (e.date, e.startTimeDisplay)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: Spacing.space12),
      for (int i = 0; i < allEntries.length; i++) ...[
        if (i > 0) const SizedBox(height: Spacing.space16),
        _buildPerDateSection(
          context: context,
          date: allEntries[i].$1,
          timeDisplay: allEntries[i].$2,
          members: members,
          isLoading: isLoading,
          isPrimaryDate: allEntries[i].$1 == selectedDate,
        ),
      ],
    ],
  );
}
```

#### C4. Add `_buildPerDateSection`

```dart
Widget _buildPerDateSection({
  required BuildContext context,
  required DateTime date,
  required String timeDisplay,
  required List<MemberVM> members,
  required bool isLoading,
  required bool isPrimaryDate,
}) {
  final dateKey = isPrimaryDate ? 'primary' : existingDateIds[date];
  final availability = dateKey != null
      ? perDateAvailability[dateKey] ?? {}
      : <String, String?>{};

  final userResponse =
      currentUserId != null ? availability[currentUserId] : null;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Date + time header
      Container(
        padding: const EdgeInsets.symmetric(vertical: Spacing.space8),
        child: Text(
          '${_formatDateDisplay(date)} · $timeDisplay',
          style: AppTextStyles.calloutEmphasized.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ),

      // Member availability grid
      if (isLoading || isLoadingPerDateAvailability)
        Container(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        )
      else if (members.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
          child: Text(
            'No members to notify',
            style: AppTextStyles.footnote.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        )
      else
        ButtonGroupGrid<MemberVM>(
          items: members,
          labelBuilder: (member) => _getMemberLabel(member, members),
          labelWidgetBuilder: (member) =>
              _buildMemberLabelWidget(context, member, members, availability),
          isSelected: (_) => false,
          availabilityMode: true,
          availabilityState: (member) {
            final response = availability[member.userId];
            if (response == 'yes') return AvailabilityState.available;
            if (response == 'no') return AvailabilityState.notAvailable;
            return AvailabilityState.notResponded;
          },
          onTap: null,
          columns: 4,
          buttonHeight: 48,
        ),

      // Your Availability for this date
      const SizedBox(height: Spacing.space8),
      Text(
        'Your Availability',
        style: AppTextStyles.footnote.copyWith(
          color: context.colors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: Spacing.space8),
      Row(
        children: [
          Expanded(
            child: AvailabilityButton(
              label: 'NO',
              icon: AppIcons.close,
              isSelected: userResponse == 'no',
              isPositive: false,
              isLoading: false,
              onPressed: () =>
                  onPerDateResponseChanged?.call(date, isPrimaryDate, 'no'),
            ),
          ),
          const SizedBox(width: Spacing.space12),
          Expanded(
            child: AvailabilityButton(
              label: 'YES',
              icon: AppIcons.check,
              isSelected: userResponse == 'yes',
              isPositive: true,
              isLoading: false,
              onPressed: () =>
                  onPerDateResponseChanged?.call(date, isPrimaryDate, 'yes'),
            ),
          ),
        ],
      ),
    ],
  );
}
```

---

### D. `lib/features/events/widgets/event_editor_drawer.dart`

#### D1. Update `_loadPerDateAvailability` to branch on event type

```dart
Future<void> _loadPerDateAvailability() async {
  final eventId = widget.existingEventId;
  if (eventId == null || !_isMultiDate) return;

  setState(() => _isLoadingPerDateAvailability = true);

  try {
    final dateIds = _existingGigDateIds.values.toList();
    final Map<String, Map<String, String?>> responses;

    if (_eventType == EventType.rehearsal) {
      responses = await ref
          .read(rehearsalResponseRepositoryProvider)
          .fetchAllDateResponses(
            rehearsalId: eventId,
            bandId: widget.bandId,
            rehearsalDateIds: dateIds,
          );
    } else {
      responses = await ref
          .read(gigResponseRepositoryProvider)
          .fetchAllDateResponses(
            gigId: eventId,
            bandId: widget.bandId,
            gigDateIds: dateIds,
          );
    }

    if (mounted) {
      setState(() {
        _perDateAvailability = responses;
        _isLoadingPerDateAvailability = false;
      });
    }
  } catch (e) {
    debugPrint('[EventEditorDrawer] Error loading per-date availability: $e');
    if (mounted) {
      setState(() => _isLoadingPerDateAvailability = false);
    }
  }
}
```

#### D2. Update `_savePerDateResponses` to branch on event type

```dart
Future<void> _savePerDateResponses() async {
  final eventId = widget.existingEventId;
  final userId = supabase.auth.currentUser?.id;
  if (eventId == null || userId == null) return;

  for (final entry in _perDateAvailability.entries) {
    final dateKey = entry.key;
    final responses = entry.value;
    final userResponse = responses[userId];

    if (userResponse != null) {
      final dateId = dateKey == 'primary' ? null : dateKey;

      if (_eventType == EventType.rehearsal) {
        await ref
            .read(rehearsalResponseRepositoryProvider)
            .upsertResponseForDate(
              rehearsalId: eventId,
              rehearsalDateId: dateId,
              userId: userId,
              response: userResponse,
            );
      } else {
        await ref.read(gigResponseRepositoryProvider).upsertResponseForDate(
              gigId: eventId,
              gigDateId: dateId,
              userId: userId,
              response: userResponse,
            );
      }
    }
  }
}
```

#### D3. Add per-date save to rehearsal edit path

Find the rehearsal edit save block (currently saves single-date response only). After the existing single-date `upsertResponse` call, add the per-date save:

```dart
// Save user availability response if set (potential rehearsals only)
if (_isPotentialGig && _currentUserResponse != null) {
  final userId = supabase.auth.currentUser?.id;
  if (userId != null) {
    await ref
        .read(rehearsalResponseRepositoryProvider)
        .upsertResponse(
          rehearsalId: widget.existingEventId!,
          bandId: widget.bandId,
          userId: userId,
          response: _currentUserResponse!,
        );
    ref.invalidate(potentialRehearsalResponseSummariesProvider);
  }
}

// Save per-date availability responses for multi-date potential rehearsals
if (_isPotentialGig &&
    _isMultiDate &&
    _perDateAvailability.isNotEmpty) {
  await _savePerDateResponses();   // ADD THIS BLOCK
}
```

#### D4. Pass per-date params to `_createRehearsalFormFields`

```dart
RehearsalFormFields _createRehearsalFormFields() {
  return RehearsalFormFields(
    // ... all existing params unchanged ...

    // ADD: per-date availability params
    perDateAvailability: _perDateAvailability,
    isLoadingPerDateAvailability: _isLoadingPerDateAvailability,
    existingDateIds: _existingGigDateIds,
    onPerDateResponseChanged: _updatePerDateResponse,
    currentUserId: supabase.auth.currentUser?.id,
  );
}
```

---

## 6. Acceptance Criteria Mapping

| Criterion                                                                               | Implementation                                                                                                               |
| --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Edit Rehearsal with Potential ON and multiple proposed dates shows one section per date | `_buildMultiDateAvailabilitySection` + `_buildPerDateSection` in `RehearsalFormFields`                                       |
| Each per-date section shows member availability pills                                   | `ButtonGroupGrid<MemberVM>` inside `_buildPerDateSection` using `perDateAvailability[dateKey]`                               |
| Each per-date section shows YES/NO buttons scoped to that date                          | `AvailabilityButton` row inside `_buildPerDateSection`; taps call `onPerDateResponseChanged`                                 |
| Tapping YES/NO updates state and persists on Save                                       | `_updatePerDateResponse` updates `_perDateAvailability`; `_savePerDateResponses` (branched for rehearsal) writes to DB       |
| Single-date potential rehearsals (no additional dates) remain unchanged                 | `isMultiDateEditMode` guard ensures single-date path is used when `additionalDates.isEmpty`                                  |
| Create mode is unchanged                                                                | `_buildMultiDateAvailabilitySection` only renders when `isEditMode && existingEventId != null && additionalDates.isNotEmpty` |
| Primary-date responses are not contaminated by per-date responses                       | `fetchUserResponse`, `fetchAllMemberResponses`, `_performUpsert` all scoped with `isFilter('rehearsal_date_id', null)`       |

---

## 7. System Impact

| System               | Impact                                                                         |
| -------------------- | ------------------------------------------------------------------------------ |
| Rehearsals           | Affected — Edit Rehearsal screen renders per-date availability in edit mode    |
| Gigs                 | Unaffected — no changes to gig screens or `GigResponseRepository`              |
| Setlists / Catalog   | Unaffected                                                                     |
| Members / RBAC       | Unaffected — member list is consumed but no permission changes                 |
| Auth / Session       | Unaffected                                                                     |
| Routing              | Unaffected                                                                     |
| Database             | Unaffected — schema complete since migration `20260519160119`                  |
| Home Tab / Dashboard | Unaffected — `potentialRehearsalResponseSummariesProvider` already invalidated |

---

## 8. Guardrails Compliance

- **No new providers or repositories** — `RehearsalResponseRepository` is extended; no new provider created.
- **No opportunistic refactors** — changes mirror gig pattern exactly without restructuring either widget.
- **`mounted` guard on all async setState** — already present in drawer; maintain the existing pattern.
- **No schema migration** — confirmed not needed.
- **`existingGigDateIds` naming preserved** — this field is intentionally shared between gigs and rehearsals in `EventFormData`. Do not rename it.
- **Single-date behavior unchanged** — `isMultiDateEditMode` guard in `RehearsalFormFields` ensures no regression for single-date potential rehearsals.
- **Create mode unchanged** — `existingEventId == null` guard already present; no per-date load or save is triggered in create mode.

---

## 9. Open Questions / Risks

None. All root causes are confirmed with HIGH confidence from code inspection. No ambiguity in the implementation path.
