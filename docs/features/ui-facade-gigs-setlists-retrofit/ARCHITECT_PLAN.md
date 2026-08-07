# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-gigs-events-retrofit-cycle-a`

---

## Problem Summary

Previous UI facade retrofit cycles completed auth, profile, settings, notifications (Cycle 1), contacts, venues (Cycle 2a), and members, calendar, rehearsals (Cycle 2b). This is **Cycle 3a: Gigs + Events Domain**, the first of four cycles completing the comprehensive retrofit effort.

**Why separate from setlists?** Per Feature Input: "do not attempt [large files] in the same cycle as smaller files" — setlists will be handled in Cycles 3b-3d separately to manage risk and scope.

Fresh scope verification confirms **11 files** with **~136 Material widget call sites** combined across `lib/features/gigs/` (3 files, ~20 sites) and `lib/features/events/` (8 files, ~116 sites). The events folder contains gig/rehearsal creation and editing UI, including the massive `event_editor_drawer.dart` (3,153 lines) with complex form logic, financial data editing, date pickers, recurring event logic, and multiple destructive delete dialogs.

**Critical challenges:**

1. **Event editor drawer** (3,153 lines): Largest file in this cycle, contains ~33+ Material call sites including multiple delete dialogs with AppColors.error (delete event, delete block out, delete recurring rehearsal, delete expense), 7 showDatePicker instances for multi-date selection, expense tracking with DropdownButton/TextField/Switch, recurring event logic
2. **Destructive action patterns:** 5+ delete/remove confirmation dialogs with AppColors.error styling requiring explicit QA verification (delete event standard/recurring, delete block out, delete expense—all with visual destructive cues)
3. **Financial data editing:** Expense subview and gig pay forms with currency inputs, conditional fields (Other category, Other payer), reimbursement tracking with Switch toggles, date pickers with theme wrappers
4. **Complex autocomplete patterns:** Venue name/location autocomplete in gig_form_fields with suggestion linking, location autocomplete in rehearsal_form_fields with custom TitleCaseTextFormatter, error styling with `hasError` conditional
5. **Multi-date availability tracking:** Both gig and rehearsal forms track per-date member availability with loading states, YES/NO response buttons, animated state updates, 4+ CircularProgressIndicator instances per file
6. **Loading state variations:** Buttons with isLoading state (save/delete in expense forms), standalone CircularProgressIndicator for availability fetching, inline small spinners (strokeWidth: 2)
7. **Blocking modal:** availability_prompt_modal.dart (gigs folder) with barrierDismissible: false, PopScope(canPop: false), requires YES/NO response, cannot dismiss via tap-outside, dual error handling with ScaffoldMessenger.showSnackBar
8. **Recurring event complexity:** rehearsal_form_fields.dart has 10 GestureDetector widgets for day/frequency selection in recurring section, animated toggles with custom styling, "until date" picker

**Why this is critical:** First cycle tackling event creation/editing UI. Contains financial data handling, destructive delete actions, and RBAC enforcement (forcePotentialOnly state on gig switch). Must maintain exact form validation logic, conditional field visibility, and autocomplete suggestion logic. No behavior change intended—purely mechanical Material→wrapper substitution.

---

## Current State

**Wrapper layer status (as of Cycle 2b merge to main):**

- 15 wrapper widgets exist in `lib/components/ui/` with complete prop surfaces:
  - `AppScaffold` - supports resizeToAvoidBottomInset, backgroundColor, body, appBar
  - `AppAppBar` - supports backgroundColor, leading, title, actions, centerTitle
  - `AppButton` - supports variants (primary, secondary, text, destructive), isLoading, icon, fullWidth, onPressed, disabled states
  - `AppIconButton` - supports icon, color, onPressed, size, tooltip, with custom BorderSide support
  - `AppTextField` / `AppTextFormField` - full decoration prop + simplified props (focusNode, textCapitalization, textInputAction, style, inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus, maxLines, maxLength, validator, initialValue, onChanged, enabled, keyboardType, obscureText)
  - `AppProgressIndicator` - supports type (circular/linear), color, value
  - `AppCheckbox` / `AppSwitch` - supports value, onChanged, activeColor
  - `AppChip` - supports label, onDeleted, selected, avatar
  - `AppCard` - supports child, color, elevation, borderRadius
  - `AppDropdown` - supports items, value, onChanged, hint, decoration
  - `showAppDialog` - supports title, message, actions (DialogAction with label, onPressed, isDestructive), builder for custom content
  - `showAppBottomSheet` - supports backgroundColor, shape, isScrollControlled, isDismissible, enableDrag, builder
  - `showAppSnackBar` - supports message, type (success/error/info)
- All wrappers tested, `flutter analyze` clean, web/iOS/Android builds succeed
- Cycles 1, 2a, 2b retrofits landed and QA-approved on main branch

**Target files (11 confirmed via fresh grep + wc -l):**

### Gigs folder (3 files, ~20 call sites):

**MEDIUM RISK:**

1. `lib/features/gigs/widgets/availability_prompt_modal.dart` (**422 lines, BLOCKING MODAL**) — showDialog with barrierDismissible: false, PopScope(canPop: false), TextButton "Not Sure Yet", CircularProgressIndicator in YES/NO response buttons with conditional loading states (\_isSubmitting ternary), dual error handling (GigResponseError + generic catch), ScaffoldMessenger.showSnackBar (2 instances with backgroundColor: Colors.red)

**LOW RISK:** 2. `lib/features/gigs/widgets/gig_notes_sheet.dart` (**114 lines**) — showModalBottomSheet (simple read-only notes display, no state management) 3. `lib/features/gigs/widgets/view_gig_drawer.dart` (**511 lines**) — showModalBottomSheet (2 instances: main drawer + nested navigation app picker), IconButton with BorderSide styling (primary color border), TextButton (Edit button with conditional rendering via `if (canEdit)`)

---

### Events folder (8 files, ~116 call sites):

**HIGH RISK (3 files with 600+ lines, destructive actions, complex state):**

4. `lib/features/events/widgets/event_editor_drawer.dart` (**3,153 LINES, HIGHEST RISK IN CYCLE A**) — 33+ Material call sites:
   - **Dialogs (4 destructive):** showDialog for delete event (line ~2140), delete block out (line ~1579), delete recurring rehearsal (line ~2178 with "Delete This Only"/"Delete All" options both AppColors.error), block out conflict info (non-blocking)
   - **Date pickers (7 instances):** showDatePicker for expense date (line ~166), reimbursement date (line ~178), block out start (line ~2950), block out end (line ~2965), primary date (line ~3010), until date recurring (line ~3126), additional dates (lines ~2993)
   - **Buttons:** OutlinedButton (3 instances: date pickers + cancel), FilledButton (save expense with CircularProgressIndicator when saving), TextButton (delete expense with AppColors.error foregroundColor)
   - **Inputs:** TextField (3 instances: custom category, custom payer, notes multiline), DropdownButton (2 instances: category selector with 11 presets, paid-by member selector dynamic list)
   - **Switches:** Switch (reimbursement toggle with activeTrackColor: AppColors.primary)
   - **Loading:** CircularProgressIndicator (3+ instances: delete button, save expense, expense list loading)

5. `lib/features/events/widgets/gig_form_fields.dart` (**1,444 lines**) — 31+ Material call sites:
   - **Autocomplete:** TextField (3 instances: venue name with fieldViewBuilder + error styling, city with fieldViewBuilder, state with maxLength:2 + textCapitalization:characters)
   - **Switches:** Switch.adaptive (potential gig toggle with forcePotentialOnly RBAC state, activeTrackColor: AppColors.primary)
   - **Dropdowns:** DropdownButton (2 instances: load-in hour selector, load-in minutes selector)
   - **Buttons:** OutlinedButton.icon ("Set Gig Pay" with dollar icon), TextButton.icon ("Add Expense" with AppColors.primary foregroundColor)
   - **Loading:** CircularProgressIndicator (4+ instances: member loading, user response loading, per-date availability loading)
   - **Interactive cards:** InkWell (tappable expense card with forward icon indicator)

6. `lib/features/events/widgets/gig_expense_subview.dart` (**655 lines**) — 15 Material call sites:
   - **Date pickers (2 with theme wrappers):** showDatePicker for expense date, reimbursement date
   - **Dropdowns:** DropdownButton (2 instances: category selector + "Other", paid-by member selector + "Other", both with DropdownButtonHideUnderline wrapper)
   - **Inputs:** TextField (3 instances: custom category when "Other" selected, custom payer, notes multiline 3-4 lines)
   - **Buttons:** OutlinedButton (3 instances: 2 date pickers with minimumSize:Size(double.infinity, 48) + cancel), FilledButton (save expense with AppColors.primary, shows CircularProgressIndicator when isSaving), TextButton.icon (delete expense with AppColors.error foregroundColor, shows CircularProgressIndicator when isDeleting)
   - **Switches:** Switch (reimbursement toggle affects date field visibility)
   - **Loading:** CircularProgressIndicator (2 instances: save with strokeWidth:2 color:white, delete with strokeWidth:2)

**MEDIUM-HIGH RISK:**

7. `lib/features/events/widgets/rehearsal_form_fields.dart` (**1,042 lines**) — 17+ Material call sites:
   - **Autocomplete:** TextField (location with fieldViewBuilder, TitleCaseTextFormatter, hasError conditional styling)
   - **Switches:** Switch.adaptive (2 instances: potential toggle, recurring toggle both with activeTrackColor: AppColors.primary)
   - **Loading:** CircularProgressIndicator (5 instances: member loading, user response loading, per-date availability, recurring availability all with strokeWidth:2)
   - **Recurring section:** GestureDetector (10 instances: 7 day selection buttons + 3 frequency buttons Weekly/Biweekly/Monthly with animated circles)
   - **Date picker trigger:** GestureDetector ("until date" with formatted display or "No end date")

**MEDIUM RISK (2 files):**

8. `lib/features/events/widgets/event_form_fields.dart` (**765 lines**) — 9 Material call sites:
   - **Dropdowns (6 instances):** DropdownButton for hour/minutes selectors across multiple dates (primary hour, primary minutes, additional hour, additional minutes, start hour, start minutes)
   - **Loading:** CircularProgressIndicator (setlist loading with strokeWidth:2)
   - **Input helper:** TextField (via EventTextField helper component)

9. `lib/features/events/widgets/event_editor_actions.dart` (**136 lines**) — 4 Material call sites:
   - **Buttons:** OutlinedButton (2 instances: Cancel disabled when isSaving||isDeleting, Close in viewOnly mode), TextButton (delete event with AppColors.error color)
   - **Loading:** CircularProgressIndicator (delete loading with strokeWidth:2, color:AppColors.error)

**LOW RISK (2 files):**

10. `lib/features/events/widgets/event_editor_helpers.dart` (**286 lines**) — 6 Material call sites:
    - **Helper components:** TextField (EventTextField generic styled component), DropdownButton (2 instances: generic with DropdownButtonHideUnderline wrapper), CircularProgressIndicator (2 instances: availability button loading with dynamic activeColor based on response state)

11. `lib/features/events/widgets/add_edit_event_bottom_sheet.dart` (**79 lines**) — 1 Material call site:
    - **Wrapper method:** showModalBottomSheet (backward compatibility, delegates to EventEditorDrawer.show())

---

**Files excluded (false positives from grep):**

- **Model files:** All `*_vm.dart`, `*.dart` files in `models/` folders (Gig, Rehearsal, GigPayDetails, etc.) — No UI widgets
- **Controller/Repository files:** `*_controller.dart`, `*_repository.dart`, `*_service.dart` — No UI widgets
- **Custom component definitions:** AvailabilityButton (already custom widget with CircularProgressIndicator handling), CurrencyTextField (precedent component), precedent components from previous cycles (BrandActionButton, ConfirmActionDialog, etc.)
- **Business logic folders:** Pure logic files with no UI

---

**Destructive action call sites (require explicit QA verification per Cycle 2a/2b lesson):**

**Gigs folder:**

1. **availability_prompt_modal.dart** lines ~93, ~104: ScaffoldMessenger.showSnackBar with `backgroundColor: Colors.red` (GigResponseError + generic error handling) — maps to `showAppSnackBar(type: SnackBarType.error)`

**Events folder:** 2. **event_editor_drawer.dart** line ~1595 (approx): TextButton "Delete" in delete block out dialog with AppColors.error 3. **event_editor_drawer.dart** line ~2162 (approx): TextButton "Delete" in delete event dialog with AppColors.error 4. **event_editor_drawer.dart** lines ~2196, ~2203 (approx): TextButton "Delete This Only" + "Delete All" in recurring rehearsal delete dialog, both with AppColors.error 5. **event_editor_drawer.dart** line ~649 (approx): TextButton.icon "Delete" in expense subview with `foregroundColor: AppColors.error` 6. **gig_expense_subview.dart** line ~649 (approx): TextButton.icon "Delete Expense" with `foregroundColor: AppColors.error` 7. **event_editor_actions.dart** line ~123 (approx): TextButton "Delete Event" with `color: AppColors.error`

**All destructive actions must map to:**

- `AppButton(variant: AppButtonVariant.destructive)` for button-based deletes
- `DialogAction(isDestructive: true)` for dialog action buttons
- `showAppSnackBar(type: SnackBarType.error)` for error snackbars

---

**Loading-state-inside-button call sites (consolidate to AppButton isLoading prop):**

1. **availability_prompt_modal.dart** line ~377 (approx): CircularProgressIndicator inside custom \_ResponseButton (YES/NO buttons) — keep as-is (custom widget, out of scope)
2. **event_editor_drawer.dart** line ~634 (approx): FilledButton save expense with conditional CircularProgressIndicator child when `isSaving`
3. **event_editor_drawer.dart** line ~653 (approx): TextButton.icon delete expense with conditional CircularProgressIndicator when `isDeleting`
4. **gig_expense_subview.dart** line ~634 (approx): FilledButton save with conditional CircularProgressIndicator when `isSaving`
5. **gig_expense_subview.dart** line ~653 (approx): TextButton.icon delete with conditional CircularProgressIndicator when `isDeleting`
6. **event_editor_actions.dart** line ~127 (approx): TextButton delete event with conditional CircularProgressIndicator when `isDeleting`

**Pattern:** `child: isSaving ? CircularProgressIndicator(...) : Text(label)` → `AppButton(label: label, isLoading: isSaving)`

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture

**No relevant design-system or retrofit guidance exists in reference docs.** Per ARCHITECT.md Phase 5 instruction, checked `docs/reference/ui/` and found only landing-page doc. Proceeded with codebase inspection and established precedent patterns from Cycles 1, 2a, 2b.

---

## Proposed Solution

Replace every raw Material widget instantiation in the 11 target files with its wrapper equivalent, maintaining exact prop values and behavior. Each substitution is a 1:1 mapping—no prop inference, no logic changes, no opportunistic refactors.

**Retrofit principles (inherited from Cycles 1, 2a, 2b):**

1. **Prop-for-prop equivalence:** If Material widget has `backgroundColor: AppColors.primary`, wrapper call must have `backgroundColor: AppColors.primary`
2. **No logic drift:** Controllers, focus nodes, validators, callbacks, autocomplete logic—all preserved exactly as written
3. **Import additions only:** Add `import 'package:bandroadie/components/ui/<wrapper>.dart';` at top of file, do not remove Material imports (Colors, Icons, EdgeInsets, BorderRadius, theme objects still needed)
4. **Conditional preservation:** If Material widget call is inside a conditional (e.g., `_isLoading ? CircularProgressIndicator(...) : Text(...)`), wrapper call must preserve the same conditional structure OR consolidate into wrapper's built-in loading prop (AppButton's `isLoading`) if it's a direct button child
5. **Style/decoration consolidation:** Where Material widget uses inline `decoration:` prop with many properties, use wrapper's `decoration` passthrough prop for AppTextField/AppTextFormField
6. **Destructive variant mapping:** Any button with `AppColors.error` or `Colors.red` text/icon/foreground color maps to `AppButton(variant: AppButtonVariant.destructive)` or `DialogAction(isDestructive: true)` for dialog actions
7. **Modal/sheet passthrough:** `showDialog` → `showAppDialog`, `showModalBottomSheet` → `showAppBottomSheet` with all props preserved (barrierDismissible, backgroundColor, shape, isScrollControlled, etc.)
8. **Dropdown mapping:** `DropdownButton` → `AppDropdown` with items/value/onChanged props preserved
9. **Switch mapping:** `Switch` / `Switch.adaptive` → `AppSwitch` with value/onChanged/activeColor props preserved
10. **Date picker preservation:** `showDatePicker` → keep as-is (no AppDatePicker wrapper exists, out of scope for this cycle)

**Boundary conditions:**

- If a Material widget has a prop the wrapper doesn't support → **STOP and report** (should not happen after wrapper-gaps cycle, but if discovered, this is a showstopper)
- If a widget is already a precedent component (BrandActionButton, ConfirmActionDialog, AvailabilityButton, CurrencyTextField, EventTextField as helper) → **Do not touch** (out of scope)
- If a widget is a third-party UI component (not Material) → **Do not touch**
- Custom animation widgets (GestureDetector for day/frequency toggles, AnimatedContainer) → **Do not touch** (animation widgets, no wrappers)
- `showDatePicker` → **Do not touch** (no wrapper, out of scope)
- `Autocomplete` widget itself → **Do not touch** (wrapper widget, but the TextField inside should be retrofitted to AppTextField)

---

## Per-File Retrofit Mapping Summary

**Format:** File path, risk level, call site count, top widget types

### Retrofit Summary Table

| #          | File                             | Risk        | Call Sites | Top Widget Types                                                                                                                                            |
| ---------- | -------------------------------- | ----------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GIGS**   |
| 1          | availability_prompt_modal.dart   | MEDIUM      | ~10        | showDialog, TextButton, CircularProgressIndicator, ScaffoldMessenger                                                                                        |
| 2          | gig_notes_sheet.dart             | LOW         | 1          | showModalBottomSheet                                                                                                                                        |
| 3          | view_gig_drawer.dart             | LOW         | 5          | showModalBottomSheet (2x), IconButton, TextButton                                                                                                           |
| **EVENTS** |
| 4          | event_editor_drawer.dart         | HIGH        | 33+        | showDialog (4x), showDatePicker (7x), TextField (3x), DropdownButton (2x), Switch, FilledButton, TextButton, OutlinedButton, CircularProgressIndicator (3x) |
| 5          | gig_form_fields.dart             | HIGH        | 31+        | TextField (3x autocomplete), Switch.adaptive, DropdownButton (2x), OutlinedButton.icon, TextButton.icon, CircularProgressIndicator (4x), InkWell            |
| 6          | gig_expense_subview.dart         | HIGH        | 15         | showDatePicker (2x), DropdownButton (2x), TextField (3x), OutlinedButton (3x), FilledButton, TextButton.icon, Switch, CircularProgressIndicator (2x)        |
| 7          | rehearsal_form_fields.dart       | MEDIUM-HIGH | 17+        | TextField (autocomplete), Switch.adaptive (2x), CircularProgressIndicator (5x), GestureDetector (10x day/freq)                                              |
| 8          | event_form_fields.dart           | MEDIUM      | 9          | DropdownButton (6x hour/min), CircularProgressIndicator, TextField (helper)                                                                                 |
| 9          | event_editor_actions.dart        | MEDIUM      | 4          | OutlinedButton (2x), TextButton, CircularProgressIndicator                                                                                                  |
| 10         | event_editor_helpers.dart        | LOW         | 6          | TextField, DropdownButton (2x), CircularProgressIndicator (2x)                                                                                              |
| 11         | add_edit_event_bottom_sheet.dart | LOW         | 1          | showModalBottomSheet                                                                                                                                        |

**Total: 11 files, ~136 Material widget call sites**

---

## Detailed Retrofit Mappings (Selected HIGH RISK Patterns)

Due to the 11-file scope and ~136 call sites, this section provides **key retrofit patterns** rather than exhaustive line-by-line mappings. Engineers should apply these patterns consistently across all files.

### Pattern 1: Destructive Delete Dialogs (showDialog → showAppDialog)

**Example from event_editor_drawer.dart (delete event dialog):**

```dart
// BEFORE
final confirmed = await showDialog<bool>(
  context: context,
  builder: (ctx) => AlertDialog(
    backgroundColor: context.colors.surface,
    title: Text('Delete Event?', style: TextStyle(color: context.colors.textPrimary)),
    content: Text('This action cannot be undone.', style: TextStyle(color: context.colors.textSecondary)),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(false),
        child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
      ),
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        child: const Text('Delete', style: TextStyle(color: AppColors.error)), // ← DESTRUCTIVE
      ),
    ],
  ),
);

// AFTER
final confirmed = await showAppDialog<bool>(
  context: context,
  title: 'Delete Event?',
  message: 'This action cannot be undone.',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(ctx).pop(false),
    ),
    DialogAction(
      label: 'Delete',
      onPressed: () => Navigator.of(ctx).pop(true),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

### Pattern 2: Loading States in Buttons (consolidate to isLoading)

**Example from gig_expense_subview.dart (save button):**

```dart
// BEFORE
FilledButton(
  onPressed: isSaving ? null : _saveExpense,
  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
  child: isSaving
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : const Text('Save Expense'),
)

// AFTER
AppButton(
  label: 'Save Expense',
  variant: AppButtonVariant.primary, // FilledButton → primary
  onPressed: isSaving ? null : _saveExpense, // no change
  isLoading: isSaving, // consolidate — replaces conditional child
  fullWidth: true, // if button spans full width
)
```

### Pattern 3: TextField with Autocomplete (preserve RawAutocomplete logic)

**Example from gig_form_fields.dart (venue name autocomplete):**

```dart
// BEFORE
RawAutocomplete<Venue>(
  // ...autocomplete config...
  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onSubmitted: (_) => onSubmitted(),
      style: TextStyle(color: context.colors.textPrimary),
      decoration: InputDecoration(
        labelText: 'Gig Name',
        border: hasError ? OutlineInputBorder(borderSide: BorderSide(color: AppColors.error)) : null,
        // ...other decoration props...
      ),
    );
  },
)

// AFTER
RawAutocomplete<Venue>(
  // ...autocomplete config (no change)...
  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
    return AppTextField(
      controller: controller, // no change
      focusNode: focusNode, // no change
      onSubmitted: (_) => onSubmitted(), // no change
      style: TextStyle(color: context.colors.textPrimary), // no change
      decoration: InputDecoration(
        labelText: 'Gig Name',
        border: hasError ? OutlineInputBorder(borderSide: BorderSide(color: AppColors.error)) : null,
        // ...other decoration props (no change)...
      ), // full decoration passthrough
    );
  },
)
```

### Pattern 4: Switch with RBAC State (preserve forced state logic)

**Example from gig_form_fields.dart (potential gig toggle):**

```dart
// BEFORE
Switch.adaptive(
  value: isPotential,
  onChanged: forcePotentialOnly ? null : (val) => setState(() => isPotential = val),
  activeTrackColor: AppColors.primary,
)

// AFTER
AppSwitch(
  value: isPotential, // no change
  onChanged: forcePotentialOnly ? null : (val) => setState(() => isPotential = val), // no change — preserve RBAC logic
  activeColor: AppColors.primary, // activeTrackColor → activeColor
)
```

### Pattern 5: DropdownButton with Dynamic Lists (preserve item generation logic)

**Example from gig_expense_subview.dart (paid-by selector):**

```dart
// BEFORE
DropdownButtonHideUnderline(
  child: DropdownButton<String>(
    value: paidBy,
    items: [
      ...bandMembers.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
      const DropdownMenuItem(value: 'other', child: Text('Other')),
    ],
    onChanged: (val) => setState(() => paidBy = val),
    // ...styling props...
  ),
)

// AFTER
AppDropdown<String>(
  value: paidBy, // no change
  items: [
    ...bandMembers.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name))),
    const DropdownMenuItem(value: 'other', child: Text('Other')),
  ], // no change — preserve dynamic generation
  onChanged: (val) => setState(() => paidBy = val), // no change
  // ...decoration if needed via AppDropdown props...
)
// Note: DropdownButtonHideUnderline is handled by AppDropdown internally
```

### Pattern 6: showModalBottomSheet (standard replacement)

**Example from add_edit_event_bottom_sheet.dart:**

```dart
// BEFORE
return showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => EventEditorDrawer(...),
);

// AFTER
return showAppBottomSheet<bool>(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (ctx) => EventEditorDrawer(...), // no change
);
```

### Pattern 7: Nested showModalBottomSheet (preserve hierarchy)

**Example from view_gig_drawer.dart (navigation app picker):**

```dart
// BEFORE
// Main drawer (line ~47)
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => ViewGigDrawer(...), // Inside ViewGigDrawer, another modal:
);

// Nested picker (line ~104 inside ViewGigDrawer)
final provider = await showModalBottomSheet<_NavigationApp>(
  context: context,
  builder: (ctx) => /* navigation app picker UI */,
);

// AFTER
// Main drawer (line ~47)
showAppBottomSheet<void>(
  context: context, // no change
  isScrollControlled: true, // no change
  builder: (_) => ViewGigDrawer(...), // no change
);

// Nested picker (line ~104 inside ViewGigDrawer)
final provider = await showAppBottomSheet<_NavigationApp>(
  context: context, // no change
  builder: (ctx) => /* navigation app picker UI (no change) */,
);
```

### Pattern 8: ScaffoldMessenger.showSnackBar (error handling)

**Example from availability_prompt_modal.dart:**

```dart
// BEFORE
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(e.userMessage),
    backgroundColor: Colors.red,
  ),
);

// AFTER
showAppSnackBar(
  context,
  message: e.userMessage,
  type: SnackBarType.error, // maps backgroundColor: Colors.red
);
```

### Pattern 9: GestureDetector for Custom Toggles (keep as-is)

**Example from rehearsal_form_fields.dart (recurring day selection):**

```dart
// BEFORE & AFTER (NO CHANGE — out of scope)
GestureDetector(
  onTap: () => setState(() => selectedDays.toggle(Weekday.monday)),
  child: AnimatedContainer(
    // ...animated circle styling...
  ),
)
// Note: These are custom UI elements, not Material widget replacements
```

### Pattern 10: showDatePicker (keep as-is, no wrapper)

**Example from event_editor_drawer.dart:**

```dart
// BEFORE & AFTER (NO CHANGE — no AppDatePicker wrapper exists)
final date = await showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: DateTime(2020),
  lastDate: DateTime(2030),
  builder: (context, child) {
    return Theme(
      data: ThemeData.dark().copyWith(/* theme customization */),
      child: child!,
    );
  },
);
```

---

## Rollout / Migration Strategy

**Implementation Order (Risk-Ascending):**

Execute retrofits in **risk-ascending order** to build confidence with simple files first, tackle complex files last:

**Batch 1: LOW RISK (3 files, ~7 call sites) — 30-45 minutes**

1. add_edit_event_bottom_sheet.dart (79 lines, 1 call site)
2. gig_notes_sheet.dart (114 lines, 1 call site)
3. view_gig_drawer.dart (511 lines, 5 call sites)

**After Batch 1:** Run `flutter analyze` (must be clean), spot-check gig viewing in running app

**Batch 2: MEDIUM RISK (3 files, ~30 call sites) — 1.5-2 hours** 4. event_editor_helpers.dart (286 lines, 6 call sites — helper components) 5. event_editor_actions.dart (136 lines, 4 call sites — delete button with loading) 6. event_form_fields.dart (765 lines, 9 call sites — dropdowns)

**After Batch 2:** Run `flutter analyze` (must be clean), test event editor open/close flow

**Batch 3: MEDIUM-HIGH RISK (2 files, ~27 call sites) — 2-3 hours** 7. availability_prompt_modal.dart (422 lines, ~10 call sites — blocking modal, error handling) 8. rehearsal_form_fields.dart (1,042 lines, 17+ call sites — autocomplete, multi-date availability, recurring logic)

**After Batch 3:** Run `flutter analyze` (must be clean), test rehearsal creation with recurring toggle, test availability prompt modal

**Batch 4: HIGH RISK (3 files, ~79 call sites) — 4-5 hours** 9. gig_expense_subview.dart (655 lines, 15 call sites — financial forms, destructive delete) 10. gig_form_fields.dart (1,444 lines, 31+ call sites — autocomplete, multi-date, RBAC switch) 11. event_editor_drawer.dart (3,153 lines, 33+ call sites — multiple dialogs, date pickers, expense integration, recurring logic)

**After Batch 4:** Run `flutter analyze` (must be clean), comprehensive manual testing:

- Create gig with expenses, test save/delete
- Create recurring rehearsal with block out conflicts
- Test venue autocomplete linking
- Test multi-date availability tracking
- Test all 5 destructive delete dialogs

**Total estimated time:**

- Implementation: 8-11 hours (across 4 batches)
- QA validation: 3-4 hours
- **Total cycle time: 11-15 hours**

---

## Out of Scope

1. **Custom component widgets:** AvailabilityButton (already contains CircularProgressIndicator handling), CurrencyTextField (precedent), BrandActionButton, ConfirmActionDialog, EventTextField (used as helper in event_editor_helpers.dart)
2. **Third-party widgets:** None in this cycle
3. **Date pickers:** showDatePicker (no AppDatePicker wrapper exists)
4. **Animation widgets:** GestureDetector (day/frequency toggles in recurring section), AnimatedContainer, FadeTransition, SlideTransition
5. **Layout widgets:** Container, Column, Row, Stack, SafeArea, Center, Expanded, SizedBox, Padding, Divider (unless they are Material widget equivalents)
6. **Non-Material widgets:** Icon (Flutter widget), Text, Image, InkWell (keep as-is for expense cards)
7. **Autocomplete widget wrapper:** RawAutocomplete / Autocomplete (keep wrapper, retrofit TextField inside fieldViewBuilder)
8. **Model/Controller/Service files:** All `*_controller.dart`, `*_repository.dart`, `*_service.dart`, `*_vm.dart` files with no UI code
9. **Business logic:** Venue linking logic, suggestion generation, validation rules, RBAC enforcement — all preserved exactly

---

## Risk Assessment

**HIGH RISK (3 files):**

1. **Financial data editing:** Expense forms with conditional field visibility (Other category, Other payer) — any logic drift will break form UX
2. **Destructive action styling:** 5+ delete dialogs must map to `isDestructive: true` — any missed mapping will lose visual destructive cue
3. **Event editor drawer complexity:** 3,153 lines, 33+ call sites, nested state management — highest risk of introducing errors during manual editing
4. **Autocomplete logic preservation:** Venue name linking, suggestion filtering — must preserve exact callback/controller logic
5. **RBAC enforcement:** `forcePotentialOnly` state on gig switch — any logic change will break permission system

**MEDIUM-HIGH RISK (1 file):**

1. **Recurring event logic:** Day/frequency toggles with GestureDetector (custom widgets, keep as-is), "until date" picker — complex conditional visibility

**MEDIUM RISK (3 files):**

1. **Loading state consolidation:** 6 buttons with conditional CircularProgressIndicator must consolidate to `isLoading` — any missed consolidation will break loading UX
2. **Multi-date availability:** Per-date tracking with 4+ CircularProgressIndicator instances per file — must preserve state keys and loading indicators

**LOW RISK (3 files):**

1. **Simple replacements:** 1-5 call sites per file, straightforward 1:1 mappings with no edge cases

---

## Success Criteria

1. **Zero `flutter analyze` errors** after all 11 files retrofitted
2. **All destructive actions styled correctly:** AppColors.error visual cue present on all 5+ delete/remove dialogs
3. **All loading states functional:** 6+ loading state patterns (buttons with isLoading, standalone spinners) work as before
4. **No logic changes:** Controllers, validators, callbacks, autocomplete logic, RBAC enforcement, recurring logic exactly as written in original files
5. **No visual regressions:** Buttons, inputs, dropdowns, switches, modals render identically (spacing, colors, borders) to pre-retrofit state (acceptable losses: custom padding/tapTargetSize per Cycles 1-2b precedent)
6. **All manual tests pass:**
   - Create gig with multi-date, track availability, add expenses, test save/delete
   - Create rehearsal with location autocomplete, multi-date, recurring toggle with day/frequency selection
   - Test availability prompt modal (blocking behavior, YES/NO responses, error handling)
   - Test all 5 destructive delete dialogs (event standard, event recurring, block out, expense)
   - Test venue autocomplete suggestion linking
   - Test RBAC enforcement on potential gig switch

---

## Dependencies

- **No new wrapper creation required:** All 15 wrappers needed for this retrofit already exist and are QA-approved from Cycles 1, 2a, 2b
- **No API surface gaps expected:** Cycles 1-2b closed all known wrapper gaps; if any new gaps discovered during implementation, **STOP and report** (showstopper)
- **Clean main branch required:** This retrofit is built off main branch which already includes Cycles 1, 2a, 2b
- **No showDatePicker wrapper:** Acknowledged out-of-scope limitation — showDatePicker calls remain as Material API

---

## Notes for Engineer

1. **Do NOT consolidate loading states opportunistically:** Only consolidate CircularProgressIndicator to `isLoading` when it's a **direct conditional child** of a button widget. Standalone CircularProgressIndicator in Center/Column → replace with `AppProgressIndicator` in same layout.
2. **Do NOT refactor autocomplete logic:** Preserve exact RawAutocomplete/Autocomplete wrapper structure, only retrofit the TextField inside fieldViewBuilder to AppTextField
3. **Do NOT remove Material imports:** After adding `import 'package:bandroadie/components/ui/...';`, keep `import 'package:flutter/material.dart';` — many files still need `Colors`, `Icons`, `EdgeInsets`, `BorderRadius`, `showDatePicker`, etc.
4. **Do NOT touch GestureDetector/AnimatedContainer:** These are custom UI elements in recurring section, not Material widget replacements
5. **Do NOT touch showDatePicker:** No wrapper exists, keep as-is with theme wrappers
6. **Do NOT touch AvailabilityButton:** Custom component already handles YES/NO state and loading, out of scope
7. **Do NOT touch CurrencyTextField:** Precedent component from earlier work, out of scope
8. **Do NOT change RBAC logic:** `forcePotentialOnly` state on gig switch must be preserved exactly — `onChanged: forcePotentialOnly ? null : callback`
9. **Do NOT batch-edit with find-replace:** Each call site requires manual inspection due to varying prop patterns, especially autocomplete and conditional fields
10. **Do NOT skip QA verification:** All 5 destructive delete dialogs must be manually tested to confirm AppColors.error visual cue renders correctly

---

## Timeline Estimate

- **Batch 1 (LOW risk, 3 files):** 30-45 minutes
- **Batch 2 (MEDIUM risk, 3 files):** 1.5-2 hours
- **Batch 3 (MEDIUM-HIGH risk, 2 files):** 2-3 hours
- **Batch 4 (HIGH risk, 3 files):** 4-5 hours
- **Total implementation time:** 8-11 hours (Engineer estimate)
- **QA validation time:** 3-4 hours (QA Agent estimate)
- **Total cycle time:** 11-15 hours

Recommend allocating 2-3 work sessions to complete all 4 batches, with QA spot-checks after Batches 1-3 and comprehensive testing after Batch 4.

---

**END OF ARCHITECT_PLAN.md**
