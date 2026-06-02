# ARCHITECT_PLAN.md

## Feature: `gig-pay-financials`

**Title:** Gig Pay Details and Financials Page
**Branch:** `feature/gig-pay-financials`
**Docs path:** `docs/features/gig-pay-financials/ARCHITECT_PLAN.md`
**Status:** APPROVED FOR ENGINEERING

---

## 1. Summary

This feature has two tightly coupled parts:

**Part 1 — Gig Pay Bottom Sheet.** Replace the single `CurrencyTextField` ("Gig Pay") in the gig form with a button that opens a structured payment bottom sheet. The bottom sheet captures: amount, payor name, 1099 toggle, paid-to band member, and payment date.

**Part 2 — Financials Screen.** A new top-level screen (`lib/features/financials/`) that aggregates financial entries (initially: gig pay records) into a filterable income/expense view accessible via a new Dashboard Quick Actions button.

---

## 2. Codebase Analysis

### 2.1 Existing `gig_pay` Column

`gigs.gig_pay` is a `NUMERIC` column (stored as dollars, e.g., `150.00`). The client model:

- `Gig.gigPayCents` (`int?`) — parsed from DB, stored in cents
- `Gig.formattedPay` — display helper
- `EventFormData.gigPayCents` (`int?`) — drives form state and DB writes
- `EventEditorDrawer._gigPayController` (`CurrencyInputController`) — form controller; disposed on widget dispose

Decision: **Keep `gigs.gig_pay` as a denormalized display cache.** It continues to drive gig card display. A database trigger syncs it automatically from the new `financial_entries` table. No breaking changes to `Gig` model.

### 2.2 Event Editor Form (Gig Pay Field)

Current location in `event_editor_drawer.dart` (line ~2065):

```dart
// Gig Pay (gigs only)
gigFormFields!.buildGigPayField(),
```

`GigFormFields.buildGigPayField()` returns a `CurrencyTextField` bound to `_gigPayController`. This is what gets replaced with a button.

### 2.3 Dashboard Quick Actions

`QuickActionsRow` widget (`lib/features/home/widgets/quick_actions_row.dart`) is a pure stateless widget with nullable `onAddEvent` and `onCreateSetlist` callbacks. It is used in:

- `HomeTabContent` (active — used by `AppShell` IndexedStack)
- `EmptyHomeState` (empty state variant — **Financials button will NOT be added here**: empty state is onboarding-focused)
- `home_screen.dart` is imported by `setlists_screen.dart` only; it is **not** the active dashboard — no change required.

### 2.4 Routing

Current routing: `main.dart` uses `onGenerateRoute` (Navigator 1.0 named routes). `FinancialsScreen` will be pushed **anonymously** via `Navigator.push()` from `HomeTabContent` — no named route registration needed. **No changes to `main.dart` are required.**

> **Routing flag:** If `FinancialsScreen` later needs deep linking or a shareable URL path, a named route must be added to `main.dart`. That change requires an Architect session.

### 2.5 State Management Pattern

`GigNotifier` (in `gig_controller.dart`) is the model to follow: `Notifier<State>` watching `bandFullStateProvider` in `build()` for automatic band-change reactivity. The `FinancialsNotifier` follows the same pattern: no `_lastLoadedBandId` tracking, no manual `loadGigs()`-on-band-switch logic.

### 2.6 RBAC

Financials contains sensitive payment data. The Financials button is visible to `admin` and `member` roles only. Contributors do not see it. The guard in `home_tab_content.dart` follows the existing `isContributor` pattern.

---

## 3. Data Model Design

### 3.1 Decision: New `financial_entries` Table

The new `financial_entries` table is the canonical store for all financial records. It is:

- Band-scoped (RLS enforced via band membership check)
- Extensible: `entry_type` covers `gig_pay`, `merch_sale`, `equipment_sale`, `misc_income`, `expense` — new types can be added without schema changes
- Not gig-coupled: `gig_id` is nullable for future non-gig income/expense entries

The `gigs.gig_pay` column is kept as a denormalized display cache and is synced automatically by a DB trigger.

### 3.2 Schema

```sql
CREATE TABLE public.financial_entries (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  band_id          UUID         NOT NULL REFERENCES public.bands(id) ON DELETE CASCADE,
  entry_type       TEXT         NOT NULL CHECK (entry_type IN (
                                  'gig_pay', 'merch_sale', 'equipment_sale',
                                  'misc_income', 'expense'
                                )),
  category         TEXT         NOT NULL,        -- Display label: 'Gig Pay', 'Merch', etc.
  amount_cents     INTEGER      NOT NULL CHECK (amount_cents >= 0),
  is_income        BOOLEAN      NOT NULL DEFAULT TRUE,
  description      TEXT,                          -- Payor name or free-text note
  entry_date       DATE         NOT NULL,
  is_1099_expected BOOLEAN,                       -- NULL = not applicable
  paid_to_user_id  UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  gig_id           UUID         REFERENCES public.gigs(id) ON DELETE SET NULL,
  created_by       UUID         NOT NULL REFERENCES public.users(id),
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

**Indexes:**

```sql
CREATE INDEX idx_financial_entries_band_id   ON public.financial_entries(band_id);
CREATE INDEX idx_financial_entries_gig_id    ON public.financial_entries(gig_id);
CREATE INDEX idx_financial_entries_band_date ON public.financial_entries(band_id, entry_date DESC);
```

### 3.3 RLS Policies

The `financial_entries` table must not self-reference. Use a `SECURITY DEFINER` helper:

```sql
CREATE OR REPLACE FUNCTION public.check_band_member(p_band_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM band_members
    WHERE band_id = p_band_id
      AND user_id = auth.uid()
      AND status = 'active'
  );
$$;
```

Policies:

- `SELECT`: `check_band_member(band_id)` — any active band member can read
- `INSERT`: `check_band_member(band_id) AND created_by = auth.uid()`
- `UPDATE`: `check_band_member(band_id)`
- `DELETE`: `check_band_member(band_id)`

> **GUARDRAIL:** If `check_band_member` already exists in the schema (check existing migrations), use `CREATE OR REPLACE` to avoid collision. The migration must be idempotent for this function.

### 3.4 Trigger: Sync `gigs.gig_pay`

```sql
CREATE OR REPLACE FUNCTION public.sync_gig_pay_from_financial_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.entry_type = 'gig_pay' AND OLD.gig_id IS NOT NULL THEN
      UPDATE public.gigs
        SET gig_pay = NULL, updated_at = NOW()
        WHERE id = OLD.gig_id;
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.entry_type = 'gig_pay' AND NEW.gig_id IS NOT NULL THEN
    UPDATE public.gigs
      SET gig_pay = (NEW.amount_cents / 100.0), updated_at = NOW()
      WHERE id = NEW.gig_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_gig_pay
  AFTER INSERT OR UPDATE OR DELETE ON public.financial_entries
  FOR EACH ROW EXECUTE FUNCTION public.sync_gig_pay_from_financial_entry();
```

---

## 4. Dart Data Models

### 4.1 `GigPayDetails`

Ephemeral in-memory model for the gig pay bottom sheet draft. Lives alongside `FinancialEntry` in the financials models file.

```dart
/// In-memory representation of payment details captured via GigPayBottomSheet.
/// Held in EventFormData while a gig is being created/edited.
/// Persisted to financial_entries on gig save.
class GigPayDetails {
  final int amountCents;           // e.g., 15000 = $150.00
  final bool is1099Expected;       // default false
  final String? payorName;         // Who is paying
  final String? paidToUserId;      // Band member receiving payment (FK to users)
  final DateTime paymentDate;      // Defaults to gig date
  final String? existingEntryId;   // Set in edit mode when entry already exists
}
```

### 4.2 `FinancialEntry`

Persisted model matching `financial_entries` table. Includes `fromJson` / `toJson`.

### 4.3 `FinancialEntryType` enum

```dart
enum FinancialEntryType {
  gigPay,
  merchSale,
  equipmentSale,
  miscIncome,
  expense;

  bool get isIncome => this != expense;
  String get displayName { /* ... */ }
  String get dbValue { /* ... */ }
}
```

---

## 5. Part 1 — Gig Pay Bottom Sheet

### 5.1 Bottom Sheet Widget

**File:** `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`

`GigPayBottomSheet` is a `StatefulWidget` — pure form state, no provider needed.

**Constructor parameters:**

- `required DateTime defaultPaymentDate` — pre-fills payment date from gig date
- `required String bandId` — for member list scoping
- `required List<BandMemberVm> members` — pre-loaded by the drawer, passed in
- `GigPayDetails? initialDetails` — pre-fills all fields in edit mode
- `bool viewOnly = false`

**Returns on save:** `Navigator.pop(context, GigPayDetails(...))` — the drawer receives the result via `await showModalBottomSheet(...)`.

**Returns on dismiss/cancel:** `Navigator.pop(context, null)` — no changes applied.

**Fields:**

1. **Amount** — `CurrencyTextField` + `CurrencyInputController` (reuse existing component)
2. **Payment Date** — date picker button; defaults to `defaultPaymentDate`
3. **Payor Name** — `TextField`, free text, optional
4. **Paid-to Member** — `DropdownButton<String?>` populated from `members` list; nullable (no selection = null)
5. **1099 Expected** — `Switch` row with label

**Controller disposal:** All `TextEditingController` and `CurrencyInputController` instances are disposed in `dispose()`.

**Async gap safety:** Any `setState` after an `async` operation (e.g., date picker) must check `mounted`.

### 5.2 Changes to `EventEditorDrawer`

**File:** `lib/features/events/widgets/event_editor_drawer.dart`

**State changes:**

- Remove: `final _gigPayController = CurrencyInputController();`
- Remove: `_gigPayController.addListener(_markDirty);`
- Remove: `_gigPayController.dispose();`
- Add: `GigPayDetails? _gigPayDetails;`

**initState edit-mode population** (replaces `_gigPayController.cents = data.gigPayCents!`):

```dart
// Populate initial pay amount from existing gig (structured details
// are lazily fetched when user taps the Gig Pay button)
if (data.gigPayCents != null) {
  _gigPayDetails = GigPayDetails(
    amountCents: data.gigPayCents!,
    is1099Expected: false,
    paymentDate: data.date,
    existingEntryId: null, // unknown until user taps and fetches
  );
}
```

**New method `_handleGigPayTap()`:**

```dart
Future<void> _handleGigPayTap() async {
  // In edit mode, lazily fetch the full financial entry to pre-populate the sheet.
  GigPayDetails? initialDetails = _gigPayDetails;
  if (widget.mode == EventEditorMode.edit && widget.existingEventId != null) {
    final repo = ref.read(financialEntryRepositoryProvider);
    final existing = await repo.fetchGigPayEntry(widget.existingEventId!);
    if (!mounted) return;
    if (existing != null) {
      initialDetails = GigPayDetails.fromEntry(existing);
    }
  }

  final members = ref.read(membersProvider).members;
  final result = await showModalBottomSheet<GigPayDetails>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => GigPayBottomSheet(
      defaultPaymentDate: _selectedDate,
      bandId: widget.bandId,
      members: members,
      initialDetails: initialDetails,
      viewOnly: widget.viewOnly,
    ),
  );
  if (!mounted) return;

  if (result != null) {
    setState(() {
      _gigPayDetails = result;
      _isDirty = true;
    });
  }
}
```

**`_buildFormData()` update** (line ~896):

```dart
// Replace:
gigPayCents: _eventType == EventType.gig && _gigPayController.isNotEmpty
    ? _gigPayController.cents
    : null,

// With:
gigPayCents: _eventType == EventType.gig
    ? _gigPayDetails?.amountCents
    : null,
gigPayDetails: _eventType == EventType.gig ? _gigPayDetails : null,
```

**Post-save financial entry creation** (in `_save()`, after `eventsRepository.createGig` / `updateGig`):

```dart
// After gig is saved and gigId is known:
if (_gigPayDetails != null) {
  final repo = ref.read(financialEntryRepositoryProvider);
  await repo.upsertGigPayEntry(
    bandId: widget.bandId,
    gigId: savedGig.id,
    gigDate: savedGig.date,
    details: _gigPayDetails!,
  );
}
```

**`mounted` guard:** Every `await` in `_save()` that leads to `setState` already requires a `mounted` check (existing pattern). The financial entry call is within the existing try/catch block.

### 5.3 Changes to `GigFormFields`

**File:** `lib/features/events/widgets/gig_form_fields.dart`

- Remove parameter: `required CurrencyInputController gigPayController`
- Add parameters: `GigPayDetails? gigPayDetails`, `required VoidCallback onGigPayTap`
- Rename `buildGigPayField()` → `buildGigPayButton()`:

```dart
Widget buildGigPayButton() {
  final hasDetails = gigPayDetails != null && gigPayDetails!.amountCents > 0;
  final label = hasDetails
      ? '${gigPayDetails!.formattedAmount}${gigPayDetails!.payorName != null ? ' · ${gigPayDetails!.payorName}' : ''}'
      : 'Set Gig Pay';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Gig Pay (optional)', style: /* footnote / textSecondary */),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: isSaving ? null : onGigPayTap,
        icon: Icon(hasDetails ? AppIcons.edit : AppIcons.dollar, size: 16),
        label: Text(label),
        style: /* Rose-outlined, radius 8px */,
      ),
    ],
  );
}
```

**Caller site in `event_editor_drawer.dart`** (line ~1839):

- Replace `gigPayController: _gigPayController,`
- With `gigPayDetails: _gigPayDetails, onGigPayTap: _handleGigPayTap,`

### 5.4 Changes to `EventFormData`

**File:** `lib/features/events/models/event_form_data.dart`

- Add field: `final GigPayDetails? gigPayDetails;`
- Add to constructor: `this.gigPayDetails,`
- Add to `copyWith`: `GigPayDetails? gigPayDetails, bool clearGigPayDetails = false`
  - Preserves `gigPayCents` and `clearGigPay` parameters **unchanged** (existing callers unaffected)
- `EventFormData.fromGig(Gig gig)`: add `gigPayDetails: null,` (details are lazily loaded; only amount is known from the Gig model)

> `EventFormData.gigPayCents` remains an `int?` field (no removal, no getter conversion). Backwards compat is maintained for all existing callers. The drawer keeps both in sync at form-data build time.

### 5.5 `FinancialEntryRepository`

**File:** `lib/features/financials/financial_entry_repository.dart`

```dart
class FinancialEntryRepository {
  /// Fetch all financial entries for a band, ordered by entry_date DESC.
  Future<List<FinancialEntry>> fetchEntriesForBand(String bandId) async { ... }

  /// Fetch the gig_pay entry for a specific gig (at most one).
  Future<FinancialEntry?> fetchGigPayEntry(String gigId) async { ... }

  /// Create or update a gig_pay entry.
  /// Uses upsert on (gig_id, entry_type) to prevent duplicates.
  Future<FinancialEntry> upsertGigPayEntry({
    required String bandId,
    required String gigId,
    required DateTime gigDate,
    required GigPayDetails details,
  }) async { ... }

  /// Delete a financial entry.
  Future<void> deleteEntry(String entryId, String bandId) async { ... }
}

final financialEntryRepositoryProvider = Provider<FinancialEntryRepository>(
  (_) => FinancialEntryRepository(),
);
```

**Upsert logic:** Use `.upsert({...}, onConflict: 'gig_id,entry_type').match({'entry_type': 'gig_pay'})` — or perform a fetch-then-insert/update if Supabase upsert on partial key is not supported. Use `existingEntryId` from `GigPayDetails` to decide INSERT vs UPDATE.

> Band isolation: All queries require non-null `bandId`. Throw `NoBandSelectedError` if null (follow `GigRepository` pattern).

---

## 6. Part 2 — Financials Screen

### 6.1 Feature Folder

```
lib/features/financials/
├── models/
│   └── financial_entry.dart        # FinancialEntry, GigPayDetails, FinancialEntryType
├── financial_entry_repository.dart  # Supabase data access
├── financials_controller.dart       # FinancialsNotifier + financialsProvider
├── financials_screen.dart           # Screen widget
└── widgets/
    └── gig_pay_bottom_sheet.dart    # Gig Pay bottom sheet
```

### 6.2 Controller

**File:** `lib/features/financials/financials_controller.dart`

```dart
enum FinancialViewMode { income, expenses }

enum FinancialDateFilter { thisMonth, thisYear, allTime }

class FinancialsState {
  final List<FinancialEntry> allEntries;
  final bool isLoading;
  final String? error;
  final FinancialViewMode viewMode;
  final FinancialDateFilter dateFilter;

  List<FinancialEntry> get filteredEntries { /* filter allEntries by viewMode + dateFilter */ }
}

class FinancialsNotifier extends Notifier<FinancialsState> {
  @override
  FinancialsState build() {
    // Watch activeBandId — auto-reloads when band changes
    final bandId = ref.watch(activeBandIdProvider);
    if (bandId == null) return const FinancialsState();

    // Trigger load; return loading state immediately
    Future.microtask(() => _load(bandId));
    return const FinancialsState(isLoading: true);
  }

  Future<void> _load(String bandId) async { ... }
  void setViewMode(FinancialViewMode mode) { ... }
  void setDateFilter(FinancialDateFilter filter) { ... }
  Future<void> refresh() async { ... }
}

final financialsProvider = NotifierProvider<FinancialsNotifier, FinancialsState>(
  FinancialsNotifier.new,
);
```

> **Anti-pattern warning:** Do NOT use `_lastLoadedBandId` tracking. Band isolation is handled by watching `activeBandIdProvider` directly in `build()`.

### 6.3 Screen

**File:** `lib/features/financials/financials_screen.dart`

`FinancialsScreen` is a `ConsumerStatefulWidget`.

**Layout:**

```
Scaffold
  ├── AppBar("Financials", leading: back button)
  ├── Column
  │   ├── Date filter row          // This Month | This Year | All Time
  │   ├── Income/Expenses toggle   // SegmentedButton or custom toggle
  │   └── Expanded(
  │         ListView.builder of FinancialEntryCard widgets
  │         — or empty state message
  │       )
  └── (no bottom nav — pushed screen)
```

**Date filter row:** Three `TextButton`/chip-style buttons. Active filter shown with rose accent. Tapping calls `ref.read(financialsProvider.notifier).setDateFilter(...)`.

**Income/Expenses toggle:** Two-segment control. Tapping calls `setViewMode(...)`.

**`FinancialEntryCard`:** Row widget showing:

- Leading: amount (bold, green for income / red for expenses)
- Title: description / payor name (or gig name for gig_pay entries)
- Subtitle: category badge + formatted date
- Trailing: `is_1099_expected` badge if applicable

**Empty state:** "No entries yet" with contextual hint based on current filter.

**Disposal:** `ScrollController` disposed in `dispose()` if used for scroll-triggered loading (not required in v1).

### 6.4 Dashboard Entry Point

**File:** `lib/features/home/widgets/quick_actions_row.dart`

Add to `QuickActionsRow`:

```dart
final VoidCallback? onFinancials;
final bool showFinancials;   // default: true
```

Add a "Financials" button after the existing buttons. The button is hidden (not rendered) when `!showFinancials`.

**File:** `lib/features/home/home_tab_content.dart`

Add `_handleOpenFinancials()`:

```dart
void _handleOpenFinancials() {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const FinancialsScreen(),
      fullscreenDialog: false,
    ),
  );
}
```

Pass to `QuickActionsRow`:

```dart
QuickActionsRow(
  onAddEvent: ...,
  onCreateSetlist: ...,
  onFinancials: (!isContributor) ? _handleOpenFinancials : null,
  showFinancials: !isContributor,
)
```

---

## 7. Migration

**File:** `supabase/migrations/20260601000000_create_financial_entries.sql`

Contents (in order):

1. Create `financial_entries` table with schema from §3.2
2. Create indexes from §3.2
3. Enable RLS
4. Create `check_band_member` helper function (SECURITY DEFINER, `SET search_path = public`)
5. Create RLS policies from §3.3
6. Create trigger function `sync_gig_pay_from_financial_entry` (SECURITY DEFINER, `SET search_path = public`)
7. Create trigger `trg_sync_gig_pay` on `financial_entries`

> **Naming:** Migration uses timestamp format `YYYYMMDDHHMMSS`. File: `20260601000000_create_financial_entries.sql`. This follows the existing convention observed in the migrations directory.

> **Safety:** The `check_band_member` function must use `CREATE OR REPLACE` in case a similarly named function exists. Do not assume a clean schema.

---

## 8. System Impact

| System                 | Impact                   | Notes                                                                    |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------ |
| Gigs / Event Editor    | **Affected**             | `gigPayController` → `gigPayDetails`; post-save financial entry creation |
| Gig Model (`gig.dart`) | **Unaffected**           | `gigPayCents` / `formattedPay` / `hasPay` remain unchanged               |
| Rehearsals             | **Unaffected**           | No rehearsal fields touched                                              |
| Setlists / Catalog     | **Unaffected**           |                                                                          |
| Home Dashboard         | **Affected**             | `QuickActionsRow` + `HomeTabContent` wired for Financials button         |
| Members / RBAC         | **Affected (read-only)** | Financials button gated by `!isContributor`                              |
| Calendar               | **Unaffected**           |                                                                          |
| Auth / Session         | **Unaffected**           |                                                                          |
| Routing / `main.dart`  | **Unaffected**           | `FinancialsScreen` pushed anonymously via `Navigator.push`               |
| Settings               | **Unaffected**           |                                                                          |
| Notifications          | **Unaffected**           |                                                                          |
| DB: `gigs` table       | **Affected**             | `gig_pay` column kept; updated by trigger                                |
| DB: RLS                | **Affected**             | New table + new helper function + new policies                           |

---

## 9. Database Impact

| Area                           | Status                | Notes                                                     |
| ------------------------------ | --------------------- | --------------------------------------------------------- |
| New table: `financial_entries` | Required              | Full schema in §3.2                                       |
| `gigs.gig_pay` column          | Affected              | Denormalized cache; synced by trigger from §3.4           |
| RLS policies                   | New policies required | `financial_entries` table                                 |
| SECURITY DEFINER function      | Required              | `check_band_member` + `sync_gig_pay_from_financial_entry` |
| Trigger                        | Required              | `trg_sync_gig_pay` on `financial_entries`                 |
| Existing RPC functions         | Unaffected            |                                                           |
| `band_full_state` RPC          | Unaffected            | Does not need to include financial_entries in v1          |

---

## 10. Files to Create and Modify

### New Files (Engineer creates from scratch)

| File                                                              | Purpose                                                       |
| ----------------------------------------------------------------- | ------------------------------------------------------------- |
| `lib/features/financials/models/financial_entry.dart`             | `FinancialEntry`, `GigPayDetails`, `FinancialEntryType` enum  |
| `lib/features/financials/financial_entry_repository.dart`         | Supabase data access; `financialEntryRepositoryProvider`      |
| `lib/features/financials/financials_controller.dart`              | `FinancialsState`, `FinancialsNotifier`, `financialsProvider` |
| `lib/features/financials/financials_screen.dart`                  | Screen widget                                                 |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`       | Bottom sheet widget                                           |
| `supabase/migrations/20260601000000_create_financial_entries.sql` | DB migration                                                  |

### Modified Files (Engineer edits)

| File                                                   | Changes                                                                                              |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| `lib/features/events/models/event_form_data.dart`      | Add `gigPayDetails` field; update constructor, `copyWith`, `fromGig`                                 |
| `lib/features/events/widgets/event_editor_drawer.dart` | Replace `CurrencyInputController` with `GigPayDetails?`; add `_handleGigPayTap`; call repo post-save |
| `lib/features/events/widgets/gig_form_fields.dart`     | Replace `gigPayController` param; replace `buildGigPayField()` with `buildGigPayButton()`            |
| `lib/features/home/widgets/quick_actions_row.dart`     | Add `onFinancials` + `showFinancials`; add Financials button                                         |
| `lib/features/home/home_tab_content.dart`              | Add `_handleOpenFinancials`; pass `onFinancials` to `QuickActionsRow`                                |

### Files Explicitly Not Modified

| File                                              | Reason                                                               |
| ------------------------------------------------- | -------------------------------------------------------------------- |
| `lib/main.dart`                                   | No named route needed; `FinancialsScreen` pushed anonymously         |
| `lib/app/models/gig.dart`                         | `gigPayCents` / `formattedPay` unchanged                             |
| `lib/features/home/home_screen.dart`              | Not the active dashboard shell; no change                            |
| `lib/features/home/widgets/empty_home_state.dart` | Financials button intentionally excluded from empty/onboarding state |
| `lib/features/events/events_repository.dart`      | `gig_pay` column write via `formData.gigPayCents` unchanged          |

---

## 11. Guardrail Compliance

| Guardrail                                         | Status                                                                                                          |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| No `main.dart` routing changes                    | Compliant — anonymous push used                                                                                 |
| Notifier + NotifierProvider pattern               | Compliant — `FinancialsNotifier extends Notifier<FinancialsState>`                                              |
| No `_lastLoadedBandId` anti-pattern               | Compliant — `ref.watch(activeBandIdProvider)` in `build()`                                                      |
| No self-referencing RLS policy                    | Compliant — `check_band_member` queries `band_members`, not `financial_entries`                                 |
| SECURITY DEFINER with `SET search_path = public`  | Compliant — applied to both DB functions                                                                        |
| No `setState` after async without `mounted` guard | Required — `_handleGigPayTap` and `_save` must check `mounted` after every `await`                              |
| Controller disposal                               | Required — `GigPayBottomSheet` must dispose all `TextEditingController` and `CurrencyInputController` instances |
| No new dependencies                               | Compliant — no new `pubspec.yaml` entries required                                                              |
| File size targets                                 | Monitor — `financials_screen.dart` should stay under 400 lines; split into sub-widgets if needed                |
| DB migration timestamp format                     | Compliant — `20260601000000_create_financial_entries.sql`                                                       |

---

## 12. Open Questions / Decisions for Engineer

1. **Upsert strategy for `gig_pay` entries:** A gig should have at most one `financial_entries` row with `entry_type = 'gig_pay'`. The repository's `upsertGigPayEntry` should: check if `details.existingEntryId` is set → UPDATE; otherwise INSERT. If a race condition creates a duplicate, the DB should have a unique partial index: `CREATE UNIQUE INDEX uniq_gig_pay_entry ON financial_entries(gig_id) WHERE entry_type = 'gig_pay';` — add this to the migration.

2. **`GigPayDetails.fromAmountOnly`:** In edit mode, when `Gig.gigPayCents` is set but no `financial_entries` row exists yet (legacy gig), the initial `_gigPayDetails` should default `paymentDate` to the gig date and all other fields to null/false. Define `GigPayDetails.fromAmountOnly({required int amountCents, required DateTime gigDate})` factory constructor.

3. **Members list in `GigPayBottomSheet`:** The drawer already reads `membersProvider`. Pass `ref.read(membersProvider).members` to the bottom sheet at tap time — do NOT watch inside the bottom sheet.

4. **`FinancialEntryCard` amount colour:** Use `AppColors.success` (or equivalent green) for income; `AppColors.error` for expenses. Check `design_tokens.dart` for the correct token name.

5. **Financials data refresh:** After saving a gig with pay details, `ref.invalidate(financialsProvider)` should be called so the Financials screen reflects the new entry on next open. This can be done in the drawer's `_save()` method.

---

## 13. Out of Scope (Future Work)

- Manual (non-gig) income entry creation UI
- Expense entry creation UI
- CSV/PDF export of financial records
- Edit or delete existing financial entries from Financials screen (v1 is read-only list; gig pay is edited through the gig form)
- Deep-link or named route for `FinancialsScreen`
- Server-side date filtering (v1 uses client-side filtering on all-fetched entries)
