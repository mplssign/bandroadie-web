# ARCHITECT PLAN — bug/rehearsal-edit-setlist-spinner

---

## 1. Feature Slug

`bug/rehearsal-edit-setlist-spinner`

Branch: `bug/rehearsal-edit-setlist-spinner`
Docs path: `docs/features/bug/rehearsal-edit-setlist-spinner/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

When a user opens the Edit Rehearsal sheet, the Setlist section shows
"Setting up the stage..." and never resolves. All other fields in the drawer
work correctly. The spinner is indefinite — the setlist picker never transitions
to showing the list of setlists.

---

## 3. Root Cause

**Is this a P3 regression or pre-existing?**

**Verdict: P3 REGRESSION. Confidence: HIGH (confirmed via Riverpod 3.0.3 source
analysis).**

---

### Mechanism

The P3 fix in `bug/cleanup-p1-p2-p3` rewrote `SetlistsNotifier.build()` to call
`loadSetlists()` directly instead of deferring via `Future.microtask()`:

```dart
// P3 new build()
@override
SetlistsState build() {
  final bandId = ref.watch(activeBandIdProvider);
  if (bandId == null || bandId.isEmpty) {
    return const SetlistsState(error: 'No band selected');
  }
  loadSetlists();                               // ← direct call (no microtask)
  return const SetlistsState(isLoading: true);
}
```

`loadSetlists()` is an `async` function. When called without `await`, Dart runs
it synchronously up to its first suspension point. The first thing `loadSetlists()`
does before any `await` is:

```dart
Future<void> loadSetlists() async {
  final bandId = _bandId;
  if (bandId == null || bandId.isEmpty) return;

  // Update state to loading          ← LINE A (sync, before any await)
  state = state.copyWith(isLoading: true, clearError: true);

  try {
    final setlists = await _repository.fetchSetlistsForBand(bandId);  // ← first await
```

**LINE A runs synchronously during `build()`, before `build()` has returned.**

In Riverpod 3.x (`riverpod 3.0.3` installed), reading `state` before
`build()` returns is not safe. The state getter calls:

```
state getter
  → ref._element.readSelf()
    → resultForValue(AsyncValue.loading())   // initial value before build returns
      → returns null (AsyncLoading has no result)
    → state == null → returns $ResultError(StateError("Tried to read the state
                        of an uninitialized provider…"))
  → valueOrRawException → Error.throwWithStackTrace(StateError, stackTrace)
```

**Result:** `state` (the right-hand side of LINE A) throws `StateError`. Because
`loadSetlists()` is async and is called **without** `await` in `build()`, this
`StateError` is captured in the unresolved Future returned by `loadSetlists()`.
Nobody awaits that Future inside `build()`, so:

1. The `StateError` becomes an unhandled Future exception (Flutter logs it).
2. `loadSetlists()` never reaches the `await _repository.fetchSetlistsForBand()`
   call — it bailed out at LINE A before the `try` block.
3. `build()` returns `SetlistsState(isLoading: true)` — the provider's initial
   state.
4. No subsequent code updates the provider state.
5. **Provider is permanently stuck in `isLoading: true`.**

---

### Why the pre-P3 code worked

On the `main` branch (before P3), `build()` scheduled the load via
`Future.microtask()`:

```dart
Future.microtask(() => loadSetlists());
```

A microtask runs **after** `build()` has returned and the Riverpod framework
has set the initial state. By the time `loadSetlists()` ran, `state` was already
initialized (to `SetlistsState(isLoading: true)` from build's return value), so
`state = state.copyWith(…)` succeeded.

The P3 fix removed the microtask to eliminate the anti-pattern, but did not
account for the fact that `loadSetlists()` contains a synchronous `state = …`
write before its first `await`. The calendar controller reference implementation
(`_loadEventsForBand()`) does NOT write to `state` before its first `await`,
which is why that pattern works unmodified.

---

### Why it manifests specifically in the Edit Rehearsal sheet

`setlistsProvider` is watched in multiple places:

| Location                                            | Effect of `isLoading: true`                                                                                                                                                                                                           |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `home_screen.dart` / `home_tab_content.dart`        | Watches `setlistsProvider` but gates the "Setting up the stage…" loading screen on `bandState.isLoading` / `gigState.isLoading` / `rehearsalState.isLoading` — **not** on `setlistsState.isLoading`. Home content renders regardless. |
| `event_form_fields.dart` → `buildSetlistSelector()` | Explicitly checks `setlistsState.isLoading` and renders a spinner + "Setting up the stage…" text. This is the only code path that blocks the user with a visible, indefinite spinner.                                                 |

The Edit Rehearsal sheet is the most visible symptom because it calls
`buildSetlistSelector()`. The `setlistsProvider` is broken everywhere, but the
spinner is only displayed in this one UI path.

---

### Exact failure location

| File                                         | Line | Content                                                      |
| -------------------------------------------- | ---- | ------------------------------------------------------------ |
| `lib/features/setlists/setlists_screen.dart` | 106  | `state = state.copyWith(isLoading: true, clearError: true);` |

This line runs synchronously during `build()` before `state` is initialized,
throwing `StateError` and aborting `loadSetlists()`.

---

## 4. Reference Docs Consulted

Files read during diagnosis:

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/features/bug/cleanup-p1-p2-p3/ARCHITECT_PLAN.md` (P3 change description)
- `lib/features/setlists/setlists_screen.dart` (full file — current, post-P3)
- `lib/features/events/widgets/event_form_fields.dart` (setlist selector)
- `lib/features/events/widgets/event_editor_drawer.dart` (drawer structure)
- `lib/features/events/widgets/add_edit_event_bottom_sheet.dart`
- `lib/features/home/home_tab_content.dart` (setlistsProvider usage)
- `lib/features/calendar/calendar_controller.dart` (reference implementation)
- `~/.pub-cache/hosted/pub.dev/riverpod-3.0.3/lib/src/core/element.dart` (readSelf, value setter)
- `~/.pub-cache/hosted/pub.dev/riverpod-3.0.3/lib/src/core/provider/notifier_provider.dart` (state getter/setter)
- `~/.pub-cache/hosted/pub.dev/riverpod-3.0.3/lib/src/common/result.dart` (valueOrRawException)
- `git show main:lib/features/setlists/setlists_screen.dart` (pre-P3 comparison)

---

## 5. Existing System Analysis

### Setlist data flow (post-P3, broken)

```
build()
  └─> loadSetlists()  [sync execution starts]
        └─> state = state.copyWith(…)  [LINE A — throws StateError]
            └─> StateError captured in Future, unhandled
            └─> loadSetlists() ABORTS (never reaches fetchSetlistsForBand)
  └─> returns SetlistsState(isLoading: true)  [provider stuck here]

buildSetlistSelector()  [in edit rehearsal drawer]
  └─> ref.watch(setlistsProvider)  [gets isLoading: true forever]
  └─> renders "Setting up the stage…" spinner  [never clears]
```

### Setlist data flow (post-P3, FIXED)

```
build()
  └─> loadSetlists()  [sync execution starts]
        └─> stateOrNull == null → skip state mutation  [LINE A guarded]
        └─> fetchSetlistsForBand(bandId)  [first await — suspends here]
  └─> returns SetlistsState(isLoading: true)  [provider initialized]

  [async resumes after build() returns]
  └─> state = state.copyWith(setlists: setlists, isLoading: false)  [works]

buildSetlistSelector()
  └─> ref.watch(setlistsProvider)  [gets loaded state]
  └─> renders setlist pills  [correct]
```

### `stateOrNull` — safe API for build() context

Riverpod 3.x provides `stateOrNull` on `Notifier` specifically for use during
`build()`:

> "As opposed to state, this is guaranteed to be safe to use inside Notifier.build.
> If used inside Notifier.build, may return null if the notifier is not yet
> initialized."

When `loadSetlists()` is called from `build()`, `stateOrNull` returns `null`
(provider not yet initialized). When called from `refresh()` or any post-build
call site, `stateOrNull` returns the current `SetlistsState`. This makes it
the correct guard for distinguishing the two call contexts.

---

## 6. Proposed Fix

**One-line change in `loadSetlists()`.**

Wrap the synchronous pre-`await` state mutation in a `stateOrNull != null` guard.

### Before

```dart
// Update state to loading
state = state.copyWith(isLoading: true, clearError: true);
```

### After

```dart
// Only set loading explicitly if the notifier is already initialized.
// When called directly from build(), state is uninitialized and reading it
// throws StateError. build() already returns isLoading: true for that path.
if (stateOrNull != null) {
  state = state.copyWith(isLoading: true, clearError: true);
}
```

**Why this is correct:**

- When called from `build()`: `stateOrNull` is `null` → guard skips the
  mutation → `loadSetlists()` proceeds past the first `await` safely. After
  `build()` returns, the provider's state is `SetlistsState(isLoading: true)`
  (from build's return value). When the fetch completes, `state.copyWith(…)`
  works because `state` is now initialized.
- When called from `refresh()` or any explicit call site post-build:
  `stateOrNull` is the current `SetlistsState` (non-null) → guard allows the
  mutation → loading indicator is shown during refresh, as before.

**What does NOT change:**

- `loadSetlists()` fetch logic, error handling, state shape
- `SetlistsState`, `setlistsProvider`, `SetlistsScreen`
- `build()` method and its return value
- `deleteSetlist()`, `reorderLocal()`, `persistReorder()`
- All call sites of `setlistsProvider.notifier.refresh()`
- `lib/features/setlists/setlist_repository.dart` (explicitly off-limits)

---

## 7. Database Impact

Not applicable. No database, RLS, or migration changes.

---

## 8. Flutter Architecture Changes

None. This is a single conditional guard around an existing assignment.
No new providers, notifiers, repositories, or classes are introduced.
The provider API surface and state shape are unchanged.

---

## 9. Files to Create

`docs/features/bug/rehearsal-edit-setlist-spinner/ARCHITECT_PLAN.md` — this file.

---

## 10. Files to Modify

| File                                         | Change                                                                                                                                  |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/setlists/setlists_screen.dart` | Wrap `state = state.copyWith(isLoading: true, clearError: true)` in `if (stateOrNull != null)` guard inside `loadSetlists()` (line 106) |

### Exact edit

**File:** `lib/features/setlists/setlists_screen.dart`

**Location:** `SetlistsNotifier.loadSetlists()`, immediately after the band-id
guard, before the `try` block.

**Old text (lines 104–106):**

```dart
    if (bandId == null || bandId.isEmpty) return;

    // Update state to loading
    state = state.copyWith(isLoading: true, clearError: true);
```

**New text:**

```dart
    if (bandId == null || bandId.isEmpty) return;

    // Only set loading explicitly if the notifier is already initialized.
    // When called directly from build(), state is uninitialized and reading it
    // throws StateError. build() already returns isLoading: true for that path.
    if (stateOrNull != null) {
      state = state.copyWith(isLoading: true, clearError: true);
    }
```

---

## 11. Files Must NOT Be Touched

- `lib/features/setlists/setlist_repository.dart`
- Any Supabase migration, schema, or RLS policy file
- `pubspec.yaml`, `pubspec.lock`, any config or lockfile
- Any other source file not listed in Section 10

---

## 12. Merge Dependency Note

This bug is introduced by the P3 change on branch `bug/cleanup-p1-p2-p3`
(commit `19b35e6`). That branch has not yet been merged to `main`.

The `bug/rehearsal-edit-setlist-spinner` branch is cut from `main`. The fix
documented here must be applied **on top of** the P3 changes — i.e., it should
be applied either:

- Directly to `bug/cleanup-p1-p2-p3` before that branch is merged, **or**
- To `main` after P3 is merged.

The Engineer implementing this plan should confirm the target branch with the
Manager before proceeding.

---

## 13. Validation Criteria

After the fix is applied:

1. `flutter analyze` passes with 0 errors.
2. Opening the Edit Rehearsal sheet: Setlist section loads and shows setlist
   pills (or "None" + "+ Create Setlist" if no setlists exist). No indefinite
   spinner.
3. Creating a new setlist from the sheet still works (navigates and refreshes).
4. Switching bands: setlistsProvider reloads correctly (Riverpod re-runs
   `build()` → `loadSetlists()` → loads for new band).
5. The SetlistsScreen loads and displays setlists correctly.
6. `setlistsProvider.notifier.refresh()` still shows a loading indicator during
   refresh (because `stateOrNull` is non-null at that call site).
