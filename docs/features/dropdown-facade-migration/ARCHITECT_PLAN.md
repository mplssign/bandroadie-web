# Architect Plan — Dropdown Facade Migration (Cycle 5)

## Feature Slug

`dropdown-facade-migration`

## Feature Title

Migrate raw DropdownButton usages to AppDropdown facade (Cycle 5)

## Problem Summary

BandRoadie has an established facade pattern for UI components — 15 wrappers exist in `lib/components/ui/` to abstract Material/Forui implementation details from feature code. However, **AppDropdown** is the only facade with zero call sites: all 6 dropdown selectors in the codebase bypass the facade and call Material's `DropdownButton` or `DropdownButtonFormField` directly.

This creates:

- **Dead facade code** — AppDropdown exists but is unused
- **Styling duplication** — 5 of 6 call sites hand-roll identical `Container` wrappers (background color, border, borderRadius) around raw `DropdownButton`
- **Inconsistent pattern** — EventDropdown exists as a second mini-facade (in `event_editor_helpers.dart`) that itself wraps raw `DropdownButton`, creating two facade layers instead of one
- **Incomplete Forui migration** — Documented as "Cycle 5" future work in README.md line 142, but README incorrectly states "5 raw usages" when actual count is 6

The current AppDropdown implementation is Forui-styled (uses `FSelect.rich`) but lacks critical features that existing call sites require:

1. **No `hint` prop** — 2 call sites (`add_financial_entry_bottom_sheet.dart:765`, `gig_pay_bottom_sheet.dart:417`) use `hint: Text('No member selected')` for nullable member selectors
2. **No custom format function** — AppDropdown uses `toString()` but EventDropdown has a `labelBuilder` param for custom display formatting (e.g., `:30` for minutes)
3. **No enabled/disabled state** — AppDropdown has no way to disable during save/load operations (`isSaving` flag pattern in EventDropdown)
4. **No Container styling wrapper** — Raw dropdown call sites wrap in Container with explicit styling that should be internalized in the facade

## Root Cause

**Confidence Level:** HIGH (confirmed by code inspection)

AppDropdown was created during the Forui migration preview cycle as a future-proofing wrapper but was never adopted because:

1. The facade API was too minimal (no hint, no custom formatting, no disabled state)
2. EventDropdown already existed as a domain-specific wrapper with styling and custom label rendering
3. Financial/expense screens were built after AppDropdown creation and followed the existing raw-DropdownButton pattern instead of extending the facade
4. No consolidation pass happened during Forui cycles 1-4 (cycles focused on other components: buttons, fields, chips)

## Reference Docs Consulted

- `lib/components/ui/README.md` — Forui migration state, documents AppDropdown as unused with "5 raw usages" (count incorrect — actual is 6)
- `docs/features/domain-chip-forui-consolidation/ARCHITECT_PLAN.md` — Reference for facade consolidation pattern (merged PR #152, commit 377d9cb)
- Forui pub.dev documentation — FSelect.rich API verified during Forui design-system-swap feature

## Existing System Analysis

### Current AppDropdown Implementation

**File:** `lib/components/ui/app_dropdown.dart`

**Props:**

- `value: T?` — currently selected value (nullable)
- `items: List<DropdownMenuItem<T>>` — dropdown menu items
- `onChanged: ValueChanged<T?>?` — callback when selection changes (null disables)
- `hint: Widget?` — documented as "not supported in Forui preview" (accepted but ignored)

**Rendering:** `FSelect<T>.rich` with hardcoded `format: (value) => value.toString()`

**Limitations:**

- No way to provide custom format/label function
- No enabled/disabled state prop
- No internal Container styling (call sites must wrap)
- Hint prop is accepted but does nothing (Forui limitation)

**Call sites:** 0 (dead code)

### Current Raw Dropdown Usages (6 total)

#### 1. add_financial_entry_bottom_sheet.dart:765

**Pattern:** Nullable member selector for "Paid To" (income) / "Paid By" (expense)

**Props used:**

- `value: String?` (nullable user ID)
- `hint: Text('No member selected')` — **critical feature for nullable selector**
- `isExpanded: true`
- `dropdownColor: context.colors.surfaceElevated`
- `style: AppTextStyles.callout.copyWith(...)`
- Wrapped in: `Container(padding, decoration: BoxDecoration(color, border, borderRadius))`

#### 2. gig_pay_bottom_sheet.dart:417

**Pattern:** Identical to #1 — nullable member selector for "Paid To"

**Props used:** Same as #1

#### 3. gig_expense_subview.dart:298

**Pattern:** Non-nullable expense category selector

**Props used:**

- `value: String` (non-nullable)
- `isExpanded: true`
- `dropdownColor: context.colors.surfaceElevated`
- `onChanged: widget.canEdit && !widget.isSaving ? ... : null` — **disabled state via conditional onChanged**
- Wrapped in: Same Container pattern

#### 4. gig_expense_subview.dart:438

**Pattern:** Nullable "Paid By" member selector

**Props used:**

- `value: String?` (nullable)
- No hint prop (uses `items[0]` as "None" option)
- `isExpanded: true`
- `dropdownColor: context.colors.surfaceElevated`
- `onChanged: widget.canEdit && !widget.isSaving ? ... : null` — **disabled state**
- Wrapped in: Same Container pattern

#### 5. band_form_screen.dart:1997

**Pattern:** `DropdownButtonFormField<String>` for timezone selection with custom header rendering

**Props used:**

- `initialValue: String` (defaults to 'America/Chicago')
- `decoration: InputDecoration(filled, fillColor, border, ...)` — **FormField-specific styling**
- `dropdownColor: context.colors.surfaceElevated`
- `style: TextStyle(...)`
- `items: List<DropdownMenuItem>` with custom header widgets (disabled items with Divider + bold text)
- `onChanged: canEdit ? ... : null` — **disabled state**

**Special requirement:** Custom header items (disabled DropdownMenuItem with Divider and styled header text separating timezone groups)

#### 6. event_editor_helpers.dart:130 (EventDropdown<T>)

**Pattern:** Reusable generic dropdown wrapper with custom label builder

**Props:**

- `value: T` (non-nullable)
- `items: List<T>` (generic list, not DropdownMenuItem)
- `onChanged: ValueChanged<T?>`
- `labelBuilder: String Function(T)` — **custom formatting for display text**
- `isSaving: bool` — **explicit disabled state flag**

**Rendering:**

- Wraps in `Container` with background, border, borderRadius
- Uses `DropdownButtonHideUnderline` + `DropdownButton<T>`
- `isExpanded: true`
- `dropdownColor: context.colors.surfaceElevated`
- `style: AppTextStyles.callout.copyWith(...)`
- `onChanged: isSaving ? null : onChanged` — **disabled via null**

**Call sites:** 6 usages across 2 files

- `event_form_fields.dart`: 4 usages (hour/minute selectors for start time and additional dates)
- `gig_form_fields.dart`: 2 usages (hour/minute selectors for load-in time)

### Shared Styling Pattern

All 6 call sites (excluding EventDropdown which wraps them) use nearly identical Container styling:

```dart
Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
  decoration: BoxDecoration(
    color: context.colors.background,
    border: Border.all(color: context.colors.border),
    borderRadius: BorderRadius.circular(Spacing.buttonRadius),
  ),
  child: DropdownButtonHideUnderline(
    child: DropdownButton<T>(...),
  ),
)
```

This is the **exact duplication pattern** the domain-chip consolidation work eliminated for chips. The facade should internalize this styling.

## Proposed Solution

Enhance AppDropdown to support all required use cases and migrate all 6 raw usages to the facade.

### A. Enhance AppDropdown API

Add missing props to match EventDropdown + financial screen requirements:

**New props:**

1. `format: String Function(T value)?` — optional custom formatter (defaults to `toString()` if null), replaces hardcoded `toString()` in current implementation
2. `enabled: bool` (defaults to `true`) — explicit enabled/disabled state flag
3. `labelBuilder: String Function(T value)?` — alias for `format` (semantic clarity for EventDropdown migration)
4. `children: List<FSelectItemMixin>?` — optional list of grouped/sectioned items for use with `FSelectSection` (mutually exclusive with `items` — provide only one)

**Items vs Children:**

- **`items: List<DropdownMenuItem<T>>`** — for flat dropdown lists (internally converted to `FSelectItem` entries). Use for simple selectors (member lists, categories, etc.)
- **`children: List<FSelectItemMixin>?`** — for grouped dropdown lists with section headers (e.g., timezone groups). When provided, passed directly to `FSelect.rich` instead of the `items`-derived list. Both `FSelectSection` and `FSelectItem` mix in `FSelectItemMixin`, so both can be used in this list.
- **Mutual exclusivity:** AppDropdown must receive either `items` OR `children`, not both. If both are provided, throw `AssertionError` with clear message. If neither is provided, throw `AssertionError`.

**Hint workaround strategy:**

Forui's `FSelect.rich` has no native hint support. Options:

1. **Accept limitation and remove hint from call sites** — Replace `hint: Text('No member selected')` with explicit `items[0]` as "No member selected" option (preserves functionality, drops hint API)
2. **Custom hint overlay** — Render hint text on top of FSelect when `value == null` (complex, fragile)
3. **Rethink nullable pattern** — Use non-nullable default value ('None' option always selected)

**Architect decision:** Option 1 (explicit "None" item) — cleanest, matches existing pattern in `gig_expense_subview.dart:438` which already uses this approach. The 2 hint-dependent call sites already include a null-value item in their items list; the hint is redundant.

**Container styling internalization:**

Move the duplicated Container + BoxDecoration pattern inside AppDropdown's build method:

```dart
@override
Widget build(BuildContext context) {
  // Assert mutual exclusivity
  assert(
    (items != null && children == null) || (items == null && children != null),
    'AppDropdown: Must provide exactly one of items or children, not both.',
  );

  // Convert items to FSelectItem list if provided, otherwise use children
  final selectChildren = children ?? items!.map((item) {
    return FSelectItem<T>.item(
      title: item.child!,
      value: item.value as T,
    );
  }).toList();

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    decoration: BoxDecoration(
      color: context.colors.background,
      border: Border.all(color: context.colors.border),
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
    child: FSelect<T>.rich(
      format: format ?? labelBuilder ?? (value) => value.toString(),
      enabled: enabled,
      validator: validator,
      onSaved: onSaved,
      autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled,
      children: selectChildren,
    ),
  );
}
```

**Form integration (band_form_screen.dart:1997):**

`DropdownButtonFormField` is semantically different (integrates with Form validation). However, per FSelect API reference (https://pub.dev/documentation/forui/latest/forui.widgets.select/FSelect-class.html), **FSelect itself is a FormField** — it mixes in `FFormFieldProperties<T>` and exposes `validator`, `onSaved`, `autovalidateMode`, `formFieldKey`, and `onReset` parameters natively.

**Architect decision:** No separate `AppDropdownFormField` needed. Add Form parameters (`validator`, `onSaved`, `autovalidateMode`) directly to `AppDropdown` and use it for all use cases including band_form_screen.dart. This follows GUARDRAILS.md #7 (prefer localized edits over new abstractions).

### B. Migrate EventDropdown Internals

Replace EventDropdown's internal `DropdownButton` with `AppDropdown`:

**Strategy:** Keep EventDropdown as a convenience wrapper that converts `List<T> items` to `List<DropdownMenuItem<T>>` and delegates to AppDropdown. This preserves backward compatibility for the 6 existing EventDropdown call sites in event_form_fields.dart and gig_form_fields.dart.

**Changes:**

1. Import `AppDropdown`
2. Replace Container + DropdownButton with AppDropdown
3. Pass `labelBuilder` directly to AppDropdown's `format` prop
4. Pass `isSaving` as `enabled: !isSaving` to AppDropdown

### C. Migrate Direct Raw Usages

Migrate the 4 non-EventDropdown call sites:

**For add_financial_entry_bottom_sheet.dart:765 and gig_pay_bottom_sheet.dart:417:**

- Replace Container + DropdownButton with AppDropdown
- Remove `hint` prop (add explicit `DropdownMenuItem<String?>(value: null, child: Text('No member selected'))` as first item — already present in items list)
- Pass `enabled: !_signingIn` or `enabled: true` depending on call site

**For gig_expense_subview.dart:298 and 438:**

- Replace Container + DropdownButton with AppDropdown
- Pass `enabled: widget.canEdit && !widget.isSaving`

**For band_form_screen.dart:1997:**

- Replace DropdownButtonFormField with AppDropdown using `children` prop and `FSelectSection` for grouped timezone headers
- Pass `validator` directly to AppDropdown (Form integration via FFormFieldProperties<T> mixin)
- Map timezone items to `FSelectItem.item()` for flat entries, wrap group headers in `FSelectSection(label: Text(header), children: [...])`
- Pass `enabled: canEdit` for disabled state
- Preserve `initialValue` semantics (AppDropdown uses `value` prop)

### D. Update README.md

**File:** `lib/components/ui/README.md`

1. Update AppDropdown call site count: "0 call sites (unused)" → "10 call sites (6 via EventDropdown, 4 direct)"
2. Correct raw usage count: "5 raw `DropdownButton` usages" → "0 raw usages (all migrated)"
3. Mark Cycle 5 complete: `~~**Cycle 5:** Fix facade gap — migrate 5 raw DropdownButton usages to AppDropdown~~ — **COMPLETED** in feature/dropdown-facade-migration`
4. Update "Props Not Supported" section: note that `hint` is not natively supported but emulated via explicit null-value items

### E. Verify Zero Raw DropdownButton References

Run grep to confirm no bypasses remain:

```bash
grep -r "DropdownButton\|DropdownButtonFormField" lib/ --include="*.dart" --exclude="app_dropdown.dart"
```

Expected: zero matches outside `app_dropdown.dart`

## Database Impact

**Not applicable** — pure client-side UI widget migration, no database changes.

## Flutter Architecture Changes

### State Management

No new controllers or providers. Local state (`_selectedCategory`, `_paidToUserId`, etc.) remains in each screen, just rendered via AppDropdown instead of raw DropdownButton.

### Widgets Modified

- `lib/components/ui/app_dropdown.dart` — add format/labelBuilder/enabled/validator/onSaved/autovalidateMode props, internalize Container styling
- `lib/features/events/widgets/event_editor_helpers.dart` — migrate EventDropdown to use AppDropdown internally

### Widgets Created

None. All changes are modifications to existing components.

### Call Sites Modified (5 files, 10 total usages)

**EventDropdown internal migration (1 file, affects 6 indirect usages):**

- `lib/features/events/widgets/event_editor_helpers.dart:130` — replace internal DropdownButton with AppDropdown

**Direct raw usage migrations (4 files):**

- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart:765`
- `lib/features/financials/widgets/gig_pay_bottom_sheet.dart:417`
- `lib/features/events/widgets/gig_expense_subview.dart:298`
- `lib/features/events/widgets/gig_expense_subview.dart:438`
- `lib/features/bands/band_form_screen.dart:1997` (migrate to AppDropdown with FSelectSection for timezone groups)

## Files to Create

None. All changes are modifications to existing files.

## Files to Modify

| File                                                                    | Changes                                                                                                                                                                                                                                           |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_dropdown.dart`                                   | Add `format`/`labelBuilder`/`enabled`/`validator`/`onSaved`/`autovalidateMode`/`children` props, internalize Container styling, add items-vs-children conversion logic, update doc comment to document grouped items support and Form integration |
| `lib/features/events/widgets/event_editor_helpers.dart`                 | Replace EventDropdown's internal DropdownButton with AppDropdown                                                                                                                                                                                  |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` | Replace Container + DropdownButton with AppDropdown (line 765)                                                                                                                                                                                    |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`             | Replace Container + DropdownButton with AppDropdown (line 417)                                                                                                                                                                                    |
| `lib/features/events/widgets/gig_expense_subview.dart`                  | Replace Container + DropdownButton with AppDropdown (lines 298, 438)                                                                                                                                                                              |
| `lib/features/bands/band_form_screen.dart`                              | Replace DropdownButtonFormField with AppDropdown using `children` prop with `FSelectSection` for grouped timezone headers (line 1997)                                                                                                             |
| `lib/components/ui/README.md`                                           | Update AppDropdown status, correct count from 5 to 6, mark Cycle 5 complete                                                                                                                                                                       |

## Files Off-Limits

| File                                                 | Reason                                                                                                 |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                      | Init order must not change                                                                             |
| `lib/features/events/widgets/event_form_fields.dart` | Do not touch EventDropdown call sites (4 usages) — migration is internal to EventDropdown wrapper only |
| `lib/features/events/widgets/gig_form_fields.dart`   | Do not touch EventDropdown call sites (2 usages) — migration is internal to EventDropdown wrapper only |
| `lib/shared/utils/email_domain_helper.dart`          | No dropdown-related code                                                                               |
| All test files (except new tests for AppDropdown)    | Only modify tests for the components being changed                                                     |

## System Impact Map

| System                                 | Impact                                                                                                    |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Gigs                                   | affected (gig_expense_subview, gig_pay_bottom_sheet, gig_form_fields — UI only, no business logic change) |
| Rehearsals                             | affected (event_form_fields via EventDropdown — UI only)                                                  |
| Setlists / Catalog                     | unaffected                                                                                                |
| Members / RBAC                         | unaffected                                                                                                |
| Auth / Session                         | unaffected                                                                                                |
| Routing                                | unaffected                                                                                                |
| Notifications                          | unaffected                                                                                                |
| Financials                             | affected (add_financial_entry_bottom_sheet — UI only)                                                     |
| Bands                                  | affected (band_form_screen timezone selector — UI only)                                                   |
| Contacts                               | unaffected                                                                                                |
| Platform (iOS / Android / Web / macOS) | affected (all platforms — visual rendering via Forui FSelect instead of Material DropdownButton)          |
| Theme / Design System                  | affected (completes Forui Cycle 5)                                                                        |

## Regression Risk

**MEDIUM**

### Rationale

- **6 files modified** (1 component + 5 feature screens + README)
- **0 new files created** (Form integration added directly to AppDropdown)
- **10 dropdown selectors changed** across events, financials, and bands features
- **Visual changes** from Material to Forui styling (dropdown appearance, menu rendering may differ)
- **Hint prop behavior changes** for 2 call sites (hint removed, explicit null-value item used instead)
- **Timezone header rendering changes** — disabled DropdownMenuItem pattern replaced with FSelectSection (semantically different API)
- **Critical forms touched** — timezone selector in band settings (Form validation preserved), expense tracking, gig pay, event time selectors

### Mitigating Factors

- **No business logic changes** — all dropdown state management and callbacks unchanged
- **No state management changes** — local variables (`_selectedCategory`, `_paidToUserId`, etc.) remain
- **No database, RLS, or RPC impact**
- **EventDropdown call sites unchanged** — 6 usages in event_form_fields/gig_form_fields remain backward compatible (internal migration only)
- **Widget tests can validate behavior** without device access
- **Reference implementation** — domain-chip-forui-consolidation (PR #152) successfully used identical consolidation pattern

### Risk is NOT LOW because:

- This is NOT a narrow token swap (unlike rose-primary-color-swap)
- Touches 5 feature screens across 3 domains (events, financials, bands)
- Changes dropdown rendering on all 4 platforms
- Migrates timezone header rendering from Material disabled-item hack to Forui native section API
- Affects user-facing selectors in critical flows (expense tracking, gig pay, band timezone with Form validation)

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Enhance AppDropdown API

**File:** `lib/components/ui/app_dropdown.dart`

1. Add new optional params:
   - `format: String Function(T value)?`
   - `labelBuilder: String Function(T value)?` (alias for format)
   - `enabled: bool` (default `true`)
   - `validator: FormFieldValidator<T>?` — Form validator function
   - `onSaved: FormFieldSetter<T>?` — Form save callback
   - `autovalidateMode: AutovalidateMode?` — Form autovalidation mode
   - `children: List<FSelectItemMixin>?` — optional grouped/sectioned items (mutually exclusive with `items`)
2. Update constructor to enforce mutual exclusivity:
   - Add assertion: `assert((items != null && children == null) || (items == null && children != null), 'Must provide exactly one of items or children')`
3. Update `build()` method:
   - Wrap FSelect.rich in Container with styling (padding, BoxDecoration with border/borderRadius)
   - Convert `items` to `List<FSelectItem>` if provided: `items!.map((item) => FSelectItem<T>.item(title: item.child!, value: item.value as T)).toList()`
   - Use `children` directly if provided (already `List<FSelectItemMixin>`)
   - Pass converted/provided list to `FSelect.rich` `children` param
   - Replace hardcoded `format: (value) => value.toString()` with `format: format ?? labelBuilder ?? (value) => value.toString()`
   - Pass `enabled: enabled` to FSelect.rich (first-class bool parameter, not nullable)
   - Pass Form params: `validator: validator`, `onSaved: onSaved`, `autovalidateMode: autovalidateMode ?? AutovalidateMode.disabled`
4. Update doc comment:
   - Remove "zero call sites" note
   - Document `format`/`labelBuilder` params
   - Document `enabled` param (FSelect.rich native bool parameter)
   - Document Form integration params (`validator`, `onSaved`, `autovalidateMode`)
   - Document `children` param: "For grouped dropdowns with section headers (e.g., timezones). Use FSelectSection to create groups. Mutually exclusive with items."
   - Document `items` param: "For flat dropdown lists. Mutually exclusive with children."
   - Document hint limitation: "Hint prop accepted for backward compatibility but not rendered. Use explicit null-value DropdownMenuItem instead."
5. Remove or update hint-related doc comment (acknowledge Forui limitation, document workaround)

**Verification:** `flutter analyze` passes for this file (0 errors).

### Task 2: (REMOVED — Form Integration Added to AppDropdown)

**Rationale:** FSelect natively supports Form integration via `FFormFieldProperties<T>` mixin (confirmed in API reference at https://pub.dev/documentation/forui/latest/forui.widgets.select/FSelect-class.html). No separate FormField wrapper class is needed. Form parameters (`validator`, `onSaved`, `autovalidateMode`) are added directly to AppDropdown in Task 1.

This follows GUARDRAILS.md #7: "Prefer localized edits over new abstractions."

### Task 3: Migrate EventDropdown Internal Implementation

**File:** `lib/features/events/widgets/event_editor_helpers.dart`

Replace EventDropdown's `build()` method (lines ~121-151):

**Before:** Container + DropdownButtonHideUnderline + DropdownButton

**After:**

```dart
@override
Widget build(BuildContext context) {
  // Convert List<T> items to List<DropdownMenuItem<T>>
  final dropdownItems = items.map((item) {
    return DropdownMenuItem<T>(
      value: item,
      child: Text(labelBuilder(item)),
    );
  }).toList();

  return AppDropdown<T>(
    value: value,
    items: dropdownItems,
    onChanged: onChanged,
    labelBuilder: labelBuilder,
    enabled: !isSaving,
  );
}
```

**Critical:** Remove Container + BoxDecoration wrapping (now handled by AppDropdown internally).

**Verification:**

- `flutter analyze` passes
- Verify EventDropdown's external API unchanged (no call site modifications required)
- Verify `isSaving` prop correctly maps to `enabled: !isSaving`

### Task 4: Migrate add_financial_entry_bottom_sheet.dart

**File:** `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`

Replace Container + DropdownButtonHideUnderline + DropdownButton (lines ~764-810) with:

```dart
AppDropdown<String?>(
  value: _paidToUserId,
  items: [
    DropdownMenuItem<String?>(
      value: null,
      child: Text(
        'No member selected',
        style: AppTextStyles.callout.copyWith(color: context.colors.textMuted),
      ),
    ),
    ...widget.members.map(
      (member) => DropdownMenuItem<String?>(
        value: member.userId,
        child: Text(member.name),
      ),
    ),
    DropdownMenuItem<String?>(
      value: _kOther,
      child: Text(
        'Other',
        style: AppTextStyles.callout.copyWith(color: context.colors.textPrimary),
      ),
    ),
  ],
  onChanged: (value) {
    setState(() => _paidToUserId = value);
  },
  enabled: true,
)
```

**Critical:** Remove `hint` prop (replaced by explicit null-value item already in items list).

**Verification:** `flutter analyze` passes, member selector renders correctly.

### Task 5: Migrate gig_pay_bottom_sheet.dart

**File:** `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`

Replace Container + DropdownButtonHideUnderline + DropdownButton (lines ~416-460) with AppDropdown.

**Changes:** Identical pattern to Task 4 (nullable member selector).

**Verification:** `flutter analyze` passes.

### Task 6: Migrate gig_expense_subview.dart (Category Dropdown)

**File:** `lib/features/events/widgets/gig_expense_subview.dart`

Replace Container + DropdownButtonHideUnderline + DropdownButton (lines ~297-325) with:

```dart
AppDropdown<String>(
  value: _selectedCategory,
  items: _kPresetCategories.map(
    (value) => DropdownMenuItem<String>(
      value: value,
      child: Text(
        value,
        style: AppTextStyles.callout.copyWith(color: context.colors.textPrimary),
      ),
    ),
  ).toList(),
  onChanged: (value) {
    if (value == null) return;
    setState(() => _selectedCategory = value);
  },
  enabled: widget.canEdit && !widget.isSaving,
)
```

**Verification:** `flutter analyze` passes, category dropdown renders correctly.

### Task 7: Migrate gig_expense_subview.dart (Paid By Dropdown)

**File:** `lib/features/events/widgets/gig_expense_subview.dart`

Replace Container + DropdownButtonHideUnderline + DropdownButton (lines ~438-480) with AppDropdown.

**Pattern:** Nullable member selector (similar to Tasks 4-5 but uses "None" instead of "No member selected").

**Verification:** `flutter analyze` passes.

### Task 8: Migrate band_form_screen.dart (Timezone Dropdown)

**File:** `lib/features/bands/band_form_screen.dart`

Replace DropdownButtonFormField (lines ~1997-2060) with AppDropdown.

**Special handling:** Migrate custom header rendering from disabled `DropdownMenuItem` pattern to `FSelectSection` API.

**Implementation:**

1. Replace DropdownButtonFormField with AppDropdown
2. Convert timezone groups to FSelectSection format:
   ```dart
   AppDropdown<String>(
     value: _selectedTimezone,
     onChanged: canEdit ? (value) { setState(() => _selectedTimezone = value); } : null,
     enabled: canEdit,
     validator: (value) => value == null ? 'Timezone is required' : null,
     format: (value) => value,
     children: [
       FSelectSection<String>(
         label: const Text('US Timezones', style: TextStyle(fontWeight: FontWeight.bold)),
         items: {
           'Eastern': 'America/New_York',
           'Central': 'America/Chicago',
           'Mountain': 'America/Denver',
           'Pacific': 'America/Los_Angeles',
         },
       ),
       FSelectSection<String>(
         label: const Text('Other Timezones', style: TextStyle(fontWeight: FontWeight.bold)),
         items: {
           'UTC': 'UTC',
           'London': 'Europe/London',
           // ... other timezones
         },
       ),
     ],
   )
   ```
3. Remove Divider widgets and disabled header DropdownMenuItem items — `FSelectSection` handles group headers natively with proper styling and semantics
4. Preserve Form validation behavior by passing `validator` parameter

**API Reference:** Per pub.dev API docs (https://pub.dev/documentation/forui/latest/forui.widgets.select/FSelectSection-class.html), `FSelectSection(label: Widget, items: Map<String, T>)` is the native Forui API for grouped dropdowns with section headers. `FSelectSection` mixes in `FSelectItemMixin` and can be used in `FSelect.rich`'s `children` list alongside `FSelectItem` entries.

**Verification:** `flutter analyze` passes, timezone dropdown with grouped headers renders correctly, Form validation works.

### Task 9: Verify Zero Raw DropdownButton References

Run grep search:

```bash
grep -rn "DropdownButton\|DropdownButtonFormField" lib/ --include="*.dart" | grep -v "app_dropdown"
```

**Expected result:** Zero matches outside `app_dropdown.dart`.

If any unexpected references found, STOP and report before proceeding.

### Task 10: Update README.md

**File:** `lib/components/ui/README.md`

1. Update "Forui-Styled Wrappers" section (line ~15):
   - Change `**AppDropdown** → FSelect.rich (unused in codebase, future-proofed)` to:
   - `**AppDropdown** → FSelect.rich (10 call sites: 6 via EventDropdown, 4 direct, includes Form integration)`
2. Update "Call Site Coverage" section (line ~126):
   - Change `**AppDropdown:** 0 call sites (unused; 5 raw DropdownButton usages bypass facade)` to:
   - `**AppDropdown:** 10 call sites (4 direct, 6 via EventDropdown wrapper)`
3. Update "Future Work" section (line ~142):
   - Change `**Cycle 5:** Fix facade gap — migrate 5 raw DropdownButton usages to AppDropdown` to:
   - `~~**Cycle 5:** Fix facade gap — migrate raw DropdownButton usages to AppDropdown~~ — **COMPLETED** in feature/dropdown-facade-migration`
4. Update "Props Not Supported in Forui" → "AppDropdown" subsection:
   - Update `hint` limitation note: "Not exposed in FSelect API. Workaround: use explicit null-value DropdownMenuItem as first item instead."
5. Correct the raw usage count in Future Work note from 5 to 6 (if still mentioned elsewhere)

**Verification:** Markdown renders correctly, no broken links, counts match actual state.

### Task 11: Run Full Static Analysis

```bash
flutter analyze
```

**Expected:** 0 errors (warnings allowed if pre-existing on main branch).

**If any new errors:** fix immediately before proceeding.

### Task 12: Generate Git Diff

```bash
git diff > dropdown-facade-migration-diff.patch
```

**Verification:** Diff shows exactly 6 files modified (1 component, 5 feature screens), no unexpected changes.

## Verification Plan

### Widget Tests

#### Test File 1: app_dropdown_test.dart (extend existing)

**Test 1: Custom format function**

- Render AppDropdown with `format: (value) => 'Custom: $value'`
- Verify formatted text displayed

**Test 2: LabelBuilder alias**

- Render AppDropdown with `labelBuilder: (value) => 'Label: $value'`
- Verify works identically to `format`

**Test 3: Enabled/disabled state**

- Render AppDropdown with `enabled: false`
- Verify dropdown renders as disabled (onChanged has no effect)

**Test 4: Container styling internalized**

- Render AppDropdown
- Verify Container wrapper exists with correct padding and BoxDecoration

#### Test File 2: event_dropdown_test.dart (new, optional)

**Test 5: EventDropdown backward compatibility**

- Render EventDropdown with hour/minute pattern (existing usage)
- Verify renders correctly with custom labelBuilder
- Verify isSaving disables dropdown

**Test 6: Form integration (AppDropdown)**

- Render AppDropdown with `validator: (value) => value == null ? 'Required' : null` inside a Form
- Submit form with null value
- Verify validation error displayed
- Verify `onSaved` callback triggered on Form.save()

### Call Site Smoke Tests

No new test files required — verify existing screen-level tests still pass:

- `test/features/events/widgets/gig_expense_subview_test.dart` (if exists)
- `test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart` (if exists)

### Static Analysis Regression Check

Compare analyzer output before/after:

```bash
flutter analyze > analyzer-before.txt  # on main
flutter analyze > analyzer-after.txt   # on feature branch
diff analyzer-before.txt analyzer-after.txt
```

**Expected:** No new errors, no new warnings (pre-existing warnings allowed).

## QA Regression Areas

### Primary Validation (must verify)

1. **Visual consistency** — All 10 dropdown selectors render with Forui styling (FSelect appearance) matching other Forui-styled components
2. **Nullable selectors** — Member "Paid To" / "Paid By" selectors in financial screens show "No member selected" / "None" as first option and can be cleared
3. **Time selectors** — Hour/minute dropdowns in event forms and gig forms render correctly with custom formatting (`:30` for minutes)
4. **Category selector** — Expense category dropdown in gig expense view renders all preset categories
5. **Timezone selector** — Band settings timezone dropdown renders with grouped headers (US timezones, other timezones) and dividers
6. **Disabled state** — Dropdowns correctly disable during save/load operations (grayed out, no interaction)

### Regression Testing (must not break)

1. **Event creation/editing**
   - Start time hour/minute selectors work correctly
   - Additional date time selectors work correctly
   - Load-in time selectors work correctly (gig forms)
   - Disabled state during form submission
2. **Expense tracking**
   - Category dropdown selection persists
   - "Paid By" member selection (nullable)
   - Reimbursed toggle and date picker unaffected
3. **Gig financials**
   - "Paid To" member selection (nullable, income and expense modes)
   - Amount and notes fields unaffected
4. **Band settings**
   - Timezone selection persists on save
   - Grouped timezone headers render with proper styling
   - Timezone change updates calendar feeds (existing behavior)

### Visual Acceptance

- Dropdown trigger (closed state) matches other Forui-styled form elements
- Dropdown menu (open state) renders with correct background color (`context.colors.surfaceElevated`)
- Selected value text is clearly readable
- Disabled state is clearly visible (muted colors)
- Container border matches Forui border style (`Spacing.buttonRadius`)
- Timezone headers (bold text, dividers) render correctly

### Platform Coverage

- iOS, Android, Web, macOS — dropdown rendering and interaction works on all platforms
- FormField validation works on all platforms

## Rollout / Migration Strategy

Standard feature branch → PR → merge workflow:

1. Engineer completes implementation on `feature/dropdown-facade-migration` branch
2. All verification tests pass (widget tests + static analysis)
3. QA validates against regression areas listed above
4. On QA APPROVED: merge to main
5. Deploy web (`./tools/deploy_web.sh`)
6. Monitor for dropdown interaction issues on production (selection, disabled state, nullable handling)

**Rollback plan:** Revert merge commit if critical regression found (dropdown selection broken, time selectors not working, timezone headers not rendering, nullable member selection broken).

## Out of Scope

- **Other dropdown-like widgets** — Time pickers, date pickers, bottom sheet selectors (not Material DropdownButton)
- **Custom dropdown implementations** — Any domain-specific selectors that don't use DropdownButton (e.g., custom popover menus)
- **New dropdown features** — No new selection modes, no multi-select, no search/filter in dropdown
- **Migration of non-dropdown FormField widgets** — TextFormField, CheckboxFormField, etc. remain unchanged
- **StyleDelta customization** — Use Forui's default FSelect styling, no custom style overrides unless required by QA feedback
- **Other facade gaps** — Snackbar, dialog, bottom sheet patterns remain unchanged (not part of Cycle 5 scope)

---

**Architect:** GitHub Copilot  
**Date:** 2026-08-14  
**Branch:** `feature/dropdown-facade-migration`
