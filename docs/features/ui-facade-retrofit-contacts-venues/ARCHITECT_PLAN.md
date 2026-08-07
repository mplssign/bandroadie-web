# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-retrofit-contacts-venues`

---

## Problem Summary

Cycle 1 (commit `ad50e71`) successfully retrofitted profile/settings/notifications/auth folders (12 files) to use `App*` wrapper components from `lib/components/ui/`, proving the facade-layer pattern works for safe, mechanical Material→wrapper substitution with zero behavior change. This is Cycle 2a: retrofit `lib/features/contacts/` (which contains both member-contact screens **and all venue screens** — there is no separate `venues` folder).

Pre-scoping grep identified 55+ raw Material widget call sites across 11 files in this folder. Critical challenge: 4 files contain **destructive-styled actions** (delete buttons, remove-member buttons) using `AppColors.error` for text/icon color, plus several files have loading indicators nested inside button children. Cycle 1's QA process caught 3 near-miss mapping errors before sign-off (lost SizedBox constraint, wrong button variant, dropped onSubmitted callback) — those were only caught by deliberate behavioral read, not table-matching alone. For this cycle, every destructive-styled call site and every custom-dialog-builder call site must be explicitly verified by QA for prop-for-prop equivalence and correct variant mapping, not just cross-checked against the table.

**Why this is critical:** This is the first retrofit cycle touching screens with destructive user actions (delete venue, remove member from band). A wrong button variant or lost AppColors.error styling could either make a destructive action look non-destructive (user clicks without realizing consequences) or vice versa. The wrapper layer supports destructive styling via `AppButton.destructive` variant (confirmed available per wrapper-gaps cycle follow-up), but Engineer must map every destructive call site correctly.

---

## Current State

**Wrapper layer status (as of latest push to experiment/ui-facade):**

- 15 wrapper widgets exist in `lib/components/ui/` with complete prop surfaces
- AppTextField/AppTextFormField support full `decoration` prop + simplified props (focusNode, textCapitalization, textInputAction, style, inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus)
- AppScaffold supports resizeToAvoidBottomInset
- showAppBottomSheet supports backgroundColor, shape, isScrollControlled
- showAppDialog supports custom builder pattern for non-AlertDialog cases
- AppButton supports `destructive` variant explicitly (added in wrapper-gaps follow-up per user request confirmation)
- All wrappers tested, `flutter analyze` clean, web build succeeds
- Cycle 1 retrofits (profile/settings/notifications/auth) landed and QA-approved

**Target files (11 confirmed):**

1. `lib/features/contacts/widgets/az_search_field.dart` — Search input widget with clear button
2. `lib/features/contacts/widgets/band_member_detail_drawer.dart` — Read-only member detail modal bottom sheet
3. `lib/features/contacts/widgets/band_member_edit_drawer.dart` — Edit member role/permissions modal, includes **destructive "Remove from band" button**
4. `lib/features/contacts/widgets/contact_form_screen.dart` — Create/edit contact form, includes **destructive delete button**
5. `lib/features/contacts/widgets/contacts_view.dart` — Contact list view
6. `lib/features/contacts/widgets/invite_members_screen.dart` — Band invitation screen with custom dialog
7. `lib/features/contacts/widgets/title_pill_selector.dart` — Custom title/role selector widget
8. `lib/features/contacts/widgets/venue_contact_block.dart` — Venue contact sub-form, includes **destructive remove button**
9. `lib/features/contacts/widgets/venue_detail_screen.dart` — Read-only venue detail view
10. `lib/features/contacts/widgets/venue_form_screen.dart` — Create/edit venue form, includes **destructive delete venue button**
11. `lib/features/contacts/widgets/venues_view.dart` — Venue list view

**Pattern observed in target files:**

- Scaffold/AppBar pair in form screens (contact_form_screen, venue_form_screen, invite_members_screen)
- Buttons: Mix of ElevatedButton, FilledButton, TextButton, IconButton (map to AppButton/AppIconButton variants)
- **Destructive buttons:** TextButton or IconButton with `AppColors.error` text/icon color (map to `AppButton.destructive` or `AppIconButton` with `color: AppColors.error`)
- TextField: Extensive use with `_inputDecoration(String label)` helper method pattern (map to AppTextField with full `decoration` prop)
- TextFormField: Used in invite_members_screen (map to AppTextFormField)
- Loading states: Several buttons conditionally show CircularProgressIndicator inside child (map to AppButton's `isLoading` prop)
- showDialog + AlertDialog: Delete confirmations with destructive action buttons (map to showAppDialog with DialogAction list, marking destructive actions)
- showModalBottomSheet: Used for drawers and pickers (map to showAppBottomSheet)

**Destructive action call sites (require explicit QA verification per Cycle 1 lesson):**

1. `band_member_edit_drawer.dart` line ~230: AlertDialog "Remove" button with `AppColors.error`
2. `band_member_edit_drawer.dart` line ~545-550: TextButton.icon "Remove from band" with `AppColors.error` icon/text
3. `contact_form_screen.dart` line ~173: AlertDialog "Delete" button with `AppColors.error`
4. `contact_form_screen.dart` line ~382: TextButton "Delete Contact" with `AppColors.error`
5. `venue_contact_block.dart` line ~164: IconButton delete with `color: AppColors.error`
6. `venue_form_screen.dart` line ~266: AlertDialog "Delete" button with `AppColors.error`
7. `venue_form_screen.dart` line ~483: TextButton "Delete Venue" with `AppColors.error`

**Loading-state-inside-button call sites (map to AppButton isLoading prop):**

1. `band_member_edit_drawer.dart` line ~585-597: FilledButton with conditional CircularProgressIndicator child
2. `contact_form_screen.dart` line ~247-260: TextButton with conditional CircularProgressIndicator child
3. `invite_members_screen.dart` line ~365: Button with CircularProgressIndicator child
4. `venue_form_screen.dart` line ~345-360: TextButton with conditional CircularProgressIndicator child

**TextField controller preservation requirement:**

- contact_form_screen.dart: 5 TextEditingController + 5 FocusNode instances
- venue_form_screen.dart: 6 TextEditingController + 6 FocusNode instances
- venue_contact_block.dart: 4 TextEditingController + 4 FocusNode instances
- All controllers/focus nodes must be passed to wrapper TextField props exactly as written

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture

**No relevant design-system or retrofit guidance exists in reference docs.** Per user's "Reference doc override" instruction, checked `docs/reference/ui/` as instructed and found only landing-page doc, not actionable for this feature. Proceeded with codebase inspection and established precedent pattern from Cycle 1 (retrofit-core).

---

## Proposed Solution

Replace every raw Material widget instantiation in the 11 target files with its wrapper equivalent, maintaining exact prop values and behavior. Each substitution is a 1:1 mapping documented in the Per-File Retrofit Mapping Table below. The Engineer must execute each mapping exactly as specified—no prop inference, no logic changes, no opportunistic refactors.

**Retrofit principles (inherited from Cycle 1):**

1. **Prop-for-prop equivalence:** If Material widget has `backgroundColor: AppColors.primary`, wrapper call must have `backgroundColor: AppColors.primary` (or the wrapper's default if that's the intended behavior)
2. **No logic drift:** Controllers, focus nodes, validators, callbacks—all preserved exactly as written
3. **Import additions only:** Add `import 'package:bandroadie/components/ui/<wrapper>.dart';` at top of file, do not remove Material imports (some widgets like `Colors`, `Icons`, theme objects are still needed)
4. **Conditional preservation:** If Material widget call is inside a conditional (e.g., `_isLoading ? CircularProgressIndicator(...) : Text(...)`), wrapper call must preserve the same conditional structure OR consolidate into wrapper's built-in loading prop (AppButton's `isLoading`)
5. **Style/decoration consolidation:** Where Material widget uses inline `decoration:` prop with many properties, use wrapper's `decoration` passthrough prop for AppTextField/AppTextFormField
6. **Destructive variant mapping:** Any button with `AppColors.error` text/icon color maps to `AppButton.destructive` variant or `AppIconButton(color: AppColors.error)`

**Boundary conditions:**

- If a Material widget has a prop the wrapper doesn't support → **STOP and report** (should not happen after wrapper-gaps cycle, but if discovered, this is a showstopper)
- If a widget is already a precedent component (BrandActionButton, ConfirmActionDialog, etc.) → **Do not touch** (out of scope)
- If a widget is a third-party UI component (not Material) → **Do not touch** (out of scope)

---

## Per-File Retrofit Mapping Table

This is the core design artifact. Each entry specifies:

- **File + Line Range:** Approximate line numbers (may shift slightly during editing—Engineer must search for exact code)
- **Current Material Call:** Exact widget name + key props
- **Wrapper Replacement:** Exact wrapper name + prop mapping (show what changes, what stays the same)

**Notation:**

- `→` means "replace with"
- `// no change` means prop value is preserved exactly
- `// map variant` means translate to wrapper's variant enum
- `// omit` means Material prop is not needed in wrapper (handled by theme or wrapper default)
- `// consolidate` means replace conditional child with wrapper's built-in prop

---

### File 1: `lib/features/contacts/widgets/az_search_field.dart`

**Line ~30:** `TextField`

```dart
TextField(
  controller: controller,
  decoration: InputDecoration(
    hintText: 'Search contacts',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    prefixIcon: Icon(AppIcons.search, color: context.colors.textMuted, size: 20),
    suffixIcon: showClearButton ? IconButton(...) : null, // see below
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(...),
    enabledBorder: OutlineInputBorder(...),
    focusedBorder: OutlineInputBorder(...),
  ),
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  onChanged: onChanged,
)
→
AppTextField(
  controller: controller, // no change
  decoration: InputDecoration(
    hintText: 'Search contacts',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    prefixIcon: Icon(AppIcons.search, color: context.colors.textMuted, size: 20),
    suffixIcon: showClearButton ? AppIconButton(...) : null, // replace IconButton, see below
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(...),
    enabledBorder: OutlineInputBorder(...),
    focusedBorder: OutlineInputBorder(...),
  ), // full decoration passthrough, no change
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  onChanged: onChanged, // no change
)
```

**Line ~44-52:** `IconButton` (clear button inside TextField suffixIcon)

```dart
IconButton(
  icon: const Icon(AppIcons.close, size: 16),
  onPressed: onClear,
  splashRadius: 18,
  padding: EdgeInsets.zero,
  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
)
→
AppIconButton(
  icon: AppIcons.close, // icon data only
  size: 16, // no change
  onPressed: onClear, // no change
)
// Note: splashRadius, padding, constraints → omit (AppIconButton uses theme defaults)
```

---

### File 2: `lib/features/contacts/widgets/band_member_detail_drawer.dart`

**Line ~38:** `showModalBottomSheet`

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => /* ... */,
)
→
showAppBottomSheet<void>(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (context) => /* ... */, // no change
)
```

**Line ~280:** `TextButton` (Done button)

**Note:** This file uses `BrandActionButton` for the Done button, not raw `TextButton`. Grep may have flagged a different line. Verify in code — if BrandActionButton is used, leave it as-is (precedent component, out of scope). If raw TextButton exists elsewhere, map it.

**Line ~291:** `TextButton` (Edit button)

```dart
TextButton(
  onPressed: () => _handleEdit(context),
  child: Text(
    'Edit',
    style: TextStyle(
      color: AppColors.primary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
)
→
AppButton(
  label: 'Edit',
  variant: AppButtonVariant.text, // map variant
  onPressed: () => _handleEdit(context), // no change
)
```

---

### File 3: `lib/features/contacts/widgets/band_member_edit_drawer.dart`

**Line ~49:** `showModalBottomSheet`

```dart
showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => /* ... */,
)
→
showAppBottomSheet<void>(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (context) => /* ... */, // no change
)
```

**Line ~207-230:** `showDialog` + `AlertDialog` (Remove member confirmation)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
final confirmed = await showDialog<bool>(
  context: ctx,
  builder: (ctx) => AlertDialog(
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(
      'Remove ${widget.memberName}?',
      style: TextStyle(
        fontSize: AppFontSizes.title2,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    ),
    content: Text(
      'They will no longer have access to this band.',
      style: TextStyle(
        fontSize: AppFontSizes.body,
        color: context.colors.textSecondary,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        child: Text(
          'Remove',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: AppColors.error, // ← DESTRUCTIVE STYLING
          ),
        ),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: ctx,
  title: 'Remove ${widget.memberName}?',
  message: 'They will no longer have access to this band.',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(ctx).pop(false),
    ),
    DialogAction(
      label: 'Remove',
      onPressed: () => Navigator.of(ctx).pop(true),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

**Line ~455-479:** `SwitchListTile` (Permission toggles)

**Note:** `SwitchListTile` is a composite widget. Wrapper layer has `AppSwitch` for Switch widget only, not ListTile. Options:

1. Keep `SwitchListTile` as-is (boundary exception — composite widget)
2. Decompose into `ListTile` + `AppSwitch` (more invasive, higher risk)

**Architect recommendation:** Keep `SwitchListTile` as-is. Document as boundary exception: "SwitchListTile is a composite Material widget with no direct wrapper equivalent. Decomposing into ListTile + AppSwitch would change widget tree structure and risk layout regression. Acceptable boundary exception for Cycle 2a."

**Line ~545-599:** `TextButton.icon` + `FilledButton` with loading states

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
// Remove from band button (line ~545-550)
TextButton.icon(
  onPressed: _isRemoving ? null : _removeMember,
  icon: _isRemoving
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
          ),
        )
      : Icon(AppIcons.userRemove, color: AppColors.error, size: 20),
  label: Text(
    'Remove from band',
    style: TextStyle(
      color: AppColors.error, // ← DESTRUCTIVE STYLING
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
  style: TextButton.styleFrom(
    foregroundColor: AppColors.error,
    padding: EdgeInsets.symmetric(vertical: 12),
  ),
)
→
AppButton(
  label: 'Remove from band',
  icon: AppIcons.userRemove, // icon is shown when not loading
  variant: AppButtonVariant.destructive, // ← CRITICAL: maps AppColors.error styling
  onPressed: _isRemoving ? null : _removeMember, // no change
  isLoading: _isRemoving, // consolidate — replaces conditional icon with CircularProgressIndicator
  fullWidth: false, // explicit — this button is not full-width
)
```

```dart
// Save button (line ~585-599)
FilledButton(
  onPressed: (_hasChanges && !_isSaving) ? _saveRole : null,
  style: FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    padding: EdgeInsets.symmetric(vertical: Spacing.space16),
    minimumSize: Size(double.infinity, 0),
  ),
  child: _isSaving
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
      : Text(
          'Save',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
          ),
        ),
)
→
AppButton(
  label: 'Save',
  variant: AppButtonVariant.primary, // FilledButton → primary
  onPressed: (_hasChanges && !_isSaving) ? _saveRole : null, // no change
  isLoading: _isSaving, // consolidate — replaces conditional child
  fullWidth: true, // minimumSize: Size(double.infinity, 0) → fullWidth
)
```

**Line ~619:** `TextButton` (Cancel button)

```dart
TextButton(
  onPressed: () => Navigator.of(context).pop(),
  child: Text(
    'Cancel',
    style: TextStyle(
      color: context.colors.textSecondary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w500,
    ),
  ),
)
→
AppButton(
  label: 'Cancel',
  variant: AppButtonVariant.text, // map variant
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

---

### File 4: `lib/features/contacts/widgets/contact_form_screen.dart`

**Line ~149-173:** `showDialog` + `AlertDialog` (Delete contact confirmation)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surfaceElevated,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(
      'Delete Contact?',
      style: TextStyle(
        fontSize: AppFontSizes.title2,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    ),
    content: Text(
      'This action cannot be undone.',
      style: TextStyle(
        fontSize: AppFontSizes.body,
        color: context.colors.textSecondary,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          'Delete',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: AppColors.error, // ← DESTRUCTIVE STYLING
          ),
        ),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: context,
  title: 'Delete Contact?',
  message: 'This action cannot be undone.',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(false),
    ),
    DialogAction(
      label: 'Delete',
      onPressed: () => Navigator.of(context).pop(true),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

**Line ~234:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: ListView(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: ListView(...), // no change
)
```

**Line ~235:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  leading: IconButton(...), // see below
  title: Text(
    _isEditMode ? 'Edit Contact' : 'New Contact',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ),
  actions: [
    TextButton(...), // see below
  ],
)
→
AppAppBar(
  backgroundColor: context.colors.background, // no change
  leading: AppIconButton(...), // see below
  title: Text(
    _isEditMode ? 'Edit Contact' : 'New Contact',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ), // no change (title accepts Widget)
  actions: [
    AppButton(...), // see below
  ],
)
```

**Line ~236:** `IconButton` (close button)

```dart
IconButton(
  icon: Icon(AppIcons.close, color: context.colors.textPrimary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.close, // icon data only
  color: context.colors.textPrimary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~247-260:** `TextButton` (Save button with loading state)

```dart
TextButton(
  onPressed: _isSaving ? null : _save,
  child: _isSaving
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        )
      : Text(
          'Save',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
          ),
        ),
)
→
AppButton(
  label: 'Save',
  variant: AppButtonVariant.text, // map variant
  onPressed: _isSaving ? null : _save, // no change
  isLoading: _isSaving, // consolidate — replaces conditional child
)
```

**Line ~270, 321, 331, 341, 373:** `TextField` (Name, Company, Phone, Email, Notes fields)

```dart
TextField(
  controller: _nameController, // and others
  focusNode: _nameFocus, // and others
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  decoration: _inputDecoration('Name *'), // and other labels
  // keyboardType varies per field (phone, email)
  // inputFormatters varies per field (phone formatter)
  // maxLines varies (3 for notes)
)
→
AppTextField(
  controller: _nameController, // no change, preserve exact controller
  focusNode: _nameFocus, // no change, preserve exact focus node
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  decoration: _inputDecoration('Name *'), // no change, full decoration passthrough
  keyboardType: keyboardType, // no change where applicable
  inputFormatters: inputFormatters, // no change where applicable
  maxLines: maxLines, // no change where applicable
)
```

**Line ~382:** `TextButton` (Delete Contact button)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
TextButton(
  onPressed: _deleteContact,
  child: Text(
    'Delete Contact',
    style: TextStyle(
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
      color: AppColors.error, // ← DESTRUCTIVE STYLING
    ),
  ),
)
→
AppButton(
  label: 'Delete Contact',
  variant: AppButtonVariant.destructive, // ← CRITICAL: maps AppColors.error styling
  onPressed: _deleteContact, // no change
)
```

---

### File 5: `lib/features/contacts/widgets/contacts_view.dart`

**Line ~223:** `TextButton` (Retry button in error state)

```dart
TextButton(
  onPressed: _onRefresh,
  child: Text('Retry'),
)
→
AppButton(
  label: 'Retry',
  variant: AppButtonVariant.text, // map variant
  onPressed: _onRefresh, // no change
)
```

**Line ~261, 328:** `TextButton.icon` (Add button — two instances)

```dart
TextButton.icon(
  onPressed: () => _openContactForm(context: context),
  icon: Icon(AppIcons.add, size: 18),
  label: Text('Add'),
  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
)
→
AppButton(
  label: 'Add',
  icon: AppIcons.add, // AppButton supports icon prop
  variant: AppButtonVariant.text, // map variant
  onPressed: () => _openContactForm(context: context), // no change
)
```

---

### File 6: `lib/features/contacts/widgets/invite_members_screen.dart`

**Line ~258-294:** `showDialog` + `AlertDialog` (Cancel invite confirmation)

```dart
final confirmed = await showDialog<bool>(
  context: ctx,
  builder: (ctx) => AlertDialog(
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(
      'Cancel Invite?',
      style: TextStyle(
        fontSize: AppFontSizes.title2,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    ),
    content: Text(
      'Are you sure you want to cancel this invitation?',
      style: TextStyle(
        fontSize: AppFontSizes.body,
        color: context.colors.textSecondary,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
      ElevatedButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
        ),
        child: Text('Cancel Invite'),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: ctx,
  title: 'Cancel Invite?',
  message: 'Are you sure you want to cancel this invitation?',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(ctx).pop(false),
    ),
    DialogAction(
      label: 'Cancel Invite',
      onPressed: () => Navigator.of(ctx).pop(true),
    ),
  ],
);
// Note: Second action uses ElevatedButton → maps to secondary variant, not destructive (action is "cancel an invite", not "delete something")
```

**Line ~329:** `TextFormField` (Email input)

```dart
TextFormField(
  controller: _inviteEmailController,
  keyboardType: TextInputType.emailAddress,
  textInputAction: TextInputAction.done,
  onFieldSubmitted: (_) => _sendInvite(),
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  decoration: InputDecoration(
    hintText: 'member@example.com',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ),
)
→
AppTextFormField(
  controller: _inviteEmailController, // no change
  keyboardType: TextInputType.emailAddress, // no change
  textInputAction: TextInputAction.done, // no change
  onSubmitted: (_) => _sendInvite(), // onFieldSubmitted → onSubmitted (AppTextFormField prop name)
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  decoration: InputDecoration(
    hintText: 'member@example.com',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ), // full decoration passthrough
)
```

**Line ~365:** `CircularProgressIndicator` inside button

```
// This is inside an ElevatedButton or similar. Map the parent button to AppButton with isLoading prop (see below for button mapping)
```

**Line ~523:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: /* ... */,
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: /* ... */, // no change
)
```

**Line ~524:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  leading: IconButton(...), // see below
  title: Text(
    'Invite Members',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ),
)
→
AppAppBar(
  backgroundColor: context.colors.background, // no change
  leading: AppIconButton(...), // see below
  title: Text(
    'Invite Members',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ), // no change
)
```

**Line ~525:** `IconButton` (back button)

```dart
IconButton(
  icon: Icon(AppIcons.back, color: context.colors.textPrimary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.back, // icon data only
  color: context.colors.textPrimary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

---

### File 7: `lib/features/contacts/widgets/title_pill_selector.dart`

**Line ~161:** `TextField` (Custom title input)

```dart
TextField(
  controller: _customController,
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.callout),
  decoration: InputDecoration(
    hintText: 'e.g., Manager',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ),
  onChanged: (value) { /* ... */ },
  onSubmitted: (value) { /* ... */ },
)
→
AppTextField(
  controller: _customController, // no change
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.callout), // no change
  decoration: InputDecoration(
    hintText: 'e.g., Manager',
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ), // full decoration passthrough
  onChanged: (value) { /* ... */ }, // no change
  onSubmitted: (value) { /* ... */ }, // no change
)
```

---

### File 8: `lib/features/contacts/widgets/venue_contact_block.dart`

**Line ~164:** `IconButton` (Remove contact button)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
IconButton(
  icon: Icon(AppIcons.delete, size: 20),
  color: AppColors.error, // ← DESTRUCTIVE STYLING
  onPressed: widget.onRemove,
)
→
AppIconButton(
  icon: AppIcons.delete, // icon data only
  size: 20, // no change
  color: AppColors.error, // ← CRITICAL: preserve error color
  onPressed: widget.onRemove, // no change
)
```

**Line ~172, 210, 220, 262:** `TextField` (Name, Phone, Email, Notes fields)

```dart
TextField(
  controller: _nameController, // and others
  focusNode: _nameFocus, // and others
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  decoration: _inputDecoration('Name'), // and other labels
  // keyboardType varies per field
  // inputFormatters varies per field
  // maxLines varies per field
)
→
AppTextField(
  controller: _nameController, // no change
  focusNode: _nameFocus, // no change
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  decoration: _inputDecoration('Name'), // full decoration passthrough
  keyboardType: keyboardType, // no change where applicable
  inputFormatters: inputFormatters, // no change where applicable
  maxLines: maxLines, // no change where applicable
)
```

---

### File 9: `lib/features/contacts/widgets/venue_detail_screen.dart`

**Line ~22:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: /* ... */,
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: /* ... */, // no change
)
```

**Line ~24:** `AppBar`

```dart
AppBar(
  title: Text(venue.name, style: /* ... */),
  backgroundColor: context.colors.surface,
  foregroundColor: context.colors.textPrimary,
  elevation: 0,
)
→
AppAppBar(
  title: Text(venue.name, style: /* ... */), // no change
  backgroundColor: context.colors.surface, // no change
  // foregroundColor → omit (AppAppBar uses theme's foreground color)
)
```

**Line ~58:** `TextButton` (Edit button)

```dart
TextButton(
  onPressed: () async { /* ... */ },
  child: Text(
    'Edit',
    style: TextStyle(
      color: AppColors.primary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
)
→
AppButton(
  label: 'Edit',
  variant: AppButtonVariant.text, // map variant
  onPressed: () async { /* ... */ }, // no change
)
```

**Line ~129:** `IconButton` (Navigate button with border styling)

```dart
IconButton(
  icon: Icon(LucideIcons.navigation2),
  color: AppColors.primary,
  iconSize: 20,
  tooltip: 'Navigate',
  onPressed: () => _navigateToVenue(context, venue),
  style: IconButton.styleFrom(
    side: BorderSide(color: context.colors.border, width: 1),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
)
→
AppIconButton(
  icon: LucideIcons.navigation2, // icon data only
  size: 20, // iconSize → size
  color: AppColors.primary, // no change
  onPressed: () => _navigateToVenue(context, venue), // no change
)
// Note: style (border, shape) → omit (AppIconButton uses theme defaults, does not support custom border styling)
// BOUNDARY CONDITION: If border styling is critical, this may need to stay as raw IconButton. Verify with Tony.
```

**Line ~295:** `showModalBottomSheet` (Navigation app picker)

```dart
await showModalBottomSheet<void>(
  context: context,
  backgroundColor: context.colors.surface,
  builder: (context) => /* ... */,
)
→
await showAppBottomSheet<void>(
  context: context,
  backgroundColor: context.colors.surface, // no change
  builder: (context) => /* ... */, // no change
)
```

---

### File 10: `lib/features/contacts/widgets/venue_form_screen.dart`

**Line ~242-266:** `showDialog` + `AlertDialog` (Delete venue confirmation)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surfaceElevated,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(
      'Delete Venue?',
      style: TextStyle(
        fontSize: AppFontSizes.title2,
        fontWeight: FontWeight.w600,
        color: context.colors.textPrimary,
      ),
    ),
    content: Text(
      'This action cannot be undone.',
      style: TextStyle(
        fontSize: AppFontSizes.body,
        color: context.colors.textSecondary,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: context.colors.textSecondary,
          ),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(
          'Delete',
          style: TextStyle(
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
            color: AppColors.error, // ← DESTRUCTIVE STYLING
          ),
        ),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: context,
  title: 'Delete Venue?',
  message: 'This action cannot be undone.',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(false),
    ),
    DialogAction(
      label: 'Delete',
      onPressed: () => Navigator.of(context).pop(true),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

**Line ~331:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: ListView(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: ListView(...), // no change
)
```

**Line ~333:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  leading: IconButton(...), // see below
  title: Text(
    _isEditMode ? 'Edit Venue' : 'New Venue',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ),
  actions: [
    TextButton(...), // see below
  ],
)
→
AppAppBar(
  backgroundColor: context.colors.background, // no change
  leading: AppIconButton(...), // see below
  title: Text(
    _isEditMode ? 'Edit Venue' : 'New Venue',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ), // no change
  actions: [
    AppButton(...), // see below
  ],
)
```

**Line ~334:** `IconButton` (close button)

```dart
IconButton(
  icon: Icon(AppIcons.close, color: context.colors.textPrimary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.close, // icon data only
  color: context.colors.textPrimary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~345-360:** `TextButton` (Save button with loading state)

```dart
TextButton(
  onPressed: _isSaving ? null : _save,
  child: _isSaving
      ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        )
      : Text(
          'Save',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: AppFontSizes.body,
            fontWeight: FontWeight.w600,
          ),
        ),
)
→
AppButton(
  label: 'Save',
  variant: AppButtonVariant.text, // map variant
  onPressed: _isSaving ? null : _save, // no change
  isLoading: _isSaving, // consolidate — replaces conditional child
)
```

**Line ~368, 375, 383, 394, 409, 417:** `TextField` (Name, Address, City, State, Phone, Notes fields)

```dart
TextField(
  controller: _nameController, // and others
  focusNode: _nameFocus, // and others
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  decoration: _inputDecoration('Name *'), // and other labels
  // textCapitalization varies per field (State field uses .characters)
  // keyboardType varies per field
  // inputFormatters varies per field
  // maxLines varies per field (3 for notes)
)
→
AppTextField(
  controller: _nameController, // no change
  focusNode: _nameFocus, // no change
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  decoration: _inputDecoration('Name *'), // full decoration passthrough
  textCapitalization: textCapitalization, // no change where applicable
  keyboardType: keyboardType, // no change where applicable
  inputFormatters: inputFormatters, // no change where applicable
  maxLines: maxLines, // no change where applicable
)
```

**Line ~441:** `TextButton.icon` (Add Contact button)

```dart
TextButton.icon(
  onPressed: _addContact,
  icon: Icon(AppIcons.add, size: 18),
  label: Text('Add Contact'),
  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
)
→
AppButton(
  label: 'Add Contact',
  icon: AppIcons.add, // AppButton supports icon prop
  variant: AppButtonVariant.text, // map variant
  onPressed: _addContact, // no change
)
```

**Line ~483:** `TextButton` (Delete Venue button)

**🔴 DESTRUCTIVE ACTION — QA MUST VERIFY**

```dart
TextButton(
  onPressed: _deleteVenue,
  child: Text(
    'Delete Venue',
    style: TextStyle(
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
      color: AppColors.error, // ← DESTRUCTIVE STYLING
    ),
  ),
)
→
AppButton(
  label: 'Delete Venue',
  variant: AppButtonVariant.destructive, // ← CRITICAL: maps AppColors.error styling
  onPressed: _deleteVenue, // no change
)
```

---

### File 11: `lib/features/contacts/widgets/venues_view.dart`

**Line ~224:** `TextButton` (Retry button in error state)

```dart
TextButton(
  onPressed: _onRefresh,
  child: Text('Retry'),
)
→
AppButton(
  label: 'Retry',
  variant: AppButtonVariant.text, // map variant
  onPressed: _onRefresh, // no change
)
```

**Line ~262, 329:** `TextButton.icon` (Add button — two instances)

```dart
TextButton.icon(
  onPressed: () => _openVenueForm(context: context),
  icon: Icon(AppIcons.add, size: 18),
  label: Text('Add'),
  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
)
→
AppButton(
  label: 'Add',
  icon: AppIcons.add, // AppButton supports icon prop
  variant: AppButtonVariant.text, // map variant
  onPressed: () => _openVenueForm(context: context), // no change
)
```

---

## Database Impact

**Database:** not applicable — this feature touches zero backend/Supabase surface. All changes are Flutter UI layer only (widget call substitutions).

---

## Flutter Architecture Changes

**State Management:** None. No Riverpod provider changes, no controller changes, no state model changes.

**Widget Tree:** No new widgets created. Existing widgets replaced with wrappers that delegate to same underlying Material widgets. Visual/behavioral equivalence is the requirement—no tree shape changes, no rendering pipeline changes.

**Repositories:** None.

**Controllers/Notifiers:** None.

---

## Files to Create

**None.** All wrappers already exist from Piece 1 + wrapper-gaps cycle.

---

## Files to Modify

| File                                                           | What changes                                                                                                                                                         |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/contacts/widgets/az_search_field.dart`           | Replace TextField, IconButton with wrapper equivalents                                                                                                               |
| `lib/features/contacts/widgets/band_member_detail_drawer.dart` | Replace showModalBottomSheet, TextButton with wrapper equivalents                                                                                                    |
| `lib/features/contacts/widgets/band_member_edit_drawer.dart`   | Replace showModalBottomSheet, showDialog, TextButton.icon (destructive), FilledButton with wrapper equivalents. **SwitchListTile boundary exception — keep as-is**   |
| `lib/features/contacts/widgets/contact_form_screen.dart`       | Replace Scaffold, AppBar, IconButton, TextButton, TextField, showDialog (destructive delete) with wrapper equivalents                                                |
| `lib/features/contacts/widgets/contacts_view.dart`             | Replace TextButton, TextButton.icon with wrapper equivalents                                                                                                         |
| `lib/features/contacts/widgets/invite_members_screen.dart`     | Replace Scaffold, AppBar, IconButton, showDialog, TextFormField, ElevatedButton with wrapper equivalents                                                             |
| `lib/features/contacts/widgets/title_pill_selector.dart`       | Replace TextField with wrapper equivalent                                                                                                                            |
| `lib/features/contacts/widgets/venue_contact_block.dart`       | Replace IconButton (destructive), TextField with wrapper equivalents                                                                                                 |
| `lib/features/contacts/widgets/venue_detail_screen.dart`       | Replace Scaffold, AppBar, TextButton, IconButton, showModalBottomSheet with wrapper equivalents. **IconButton border styling boundary exception — verify with Tony** |
| `lib/features/contacts/widgets/venue_form_screen.dart`         | Replace Scaffold, AppBar, IconButton, TextButton (save + destructive delete), TextField, TextButton.icon, showDialog (destructive delete) with wrapper equivalents   |
| `lib/features/contacts/widgets/venues_view.dart`               | Replace TextButton, TextButton.icon with wrapper equivalents                                                                                                         |

---

## Files Off-Limits

| File                                                                    | Reason                                                                                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                         | Init order must not change                                                                                               |
| `lib/app/theme/*.dart`                                                  | Theme configuration is stable—wrappers delegate to it, never override it                                                 |
| All files in `lib/components/ui/`                                       | Wrapper layer is stable from Piece 1 + wrapper-gaps cycle—do not modify wrappers even if gaps are found (report instead) |
| All precedent components (BrandActionButton, ConfirmActionDialog, etc.) | Already stable, out of scope                                                                                             |
| All files in `lib/features/` except the 11 listed above                 | Later retrofit cycles (setlists, gigs, calendar, rehearsals, members)                                                    |
| All files in `lib/shared/`                                              | Later retrofit cycle or out of scope                                                                                     |
| `lib/features/members/widgets/role_management_sheet.dart`               | Explicitly out of scope — belongs to members folder, which is Cycle 2b                                                   |

---

## Boundary Conditions & Exceptions

**SwitchListTile in band_member_edit_drawer.dart (line ~455-479):**

`SwitchListTile` is a composite Material widget (combines ListTile + Switch). The wrapper layer has `AppSwitch` for Switch widget only, not a composite SwitchListTile wrapper. Decomposing into `ListTile + AppSwitch` would change widget tree structure and risk layout regression (ListTile has complex padding/alignment logic).

**DECISION:** Keep `SwitchListTile` as-is. Document as boundary exception: "SwitchListTile is a composite Material widget with no direct wrapper equivalent in the current facade layer. Decomposing into ListTile + AppSwitch would alter widget tree structure and risk layout/padding regression. Acceptable boundary exception for Cycle 2a. If future design-system swap requires custom switch styling, SwitchListTile can be addressed in a targeted follow-up."

**IconButton with border styling in venue_detail_screen.dart (line ~129):**

This IconButton has custom `style: IconButton.styleFrom(side: BorderSide(...), shape: RoundedRectangleBorder(...))` for a bordered appearance. `AppIconButton` does not currently support custom border styling (wraps raw IconButton with minimal prop surface).

**DECISION:** Two options:

1. **Keep as raw IconButton** (boundary exception — custom styling not supported by wrapper)
2. **Replace with AppIconButton, lose border styling** (acceptable if border is purely decorative)

**Architect recommendation:** Option 1 — keep as raw IconButton. Document as boundary exception: "IconButton with custom border styling (side, shape props) has no equivalent in AppIconButton's current API. Border is functional (visually groups button with address block), not purely decorative. Acceptable boundary exception for Cycle 2a. If AppIconButton needs border support in future, extend wrapper API in a targeted follow-up."

**TextFormField onFieldSubmitted vs AppTextFormField onSubmitted:**

Material's `TextFormField` uses `onFieldSubmitted` callback. Wrapper's `AppTextFormField` uses `onSubmitted` (consistent with TextField's naming). This is an intentional prop name simplification, not a gap.

**Engineer action:** When mapping `TextFormField(onFieldSubmitted: callback)`, use `AppTextFormField(onSubmitted: callback)`. Same callback, different prop name.

---

## System Impact Map

| System                                 | Impact                                                                                                                                                     |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (out of scope for this cycle)                                                                                                                   |
| Rehearsals                             | unaffected                                                                                                                                                 |
| Setlists / Catalog                     | unaffected                                                                                                                                                 |
| Members / RBAC                         | unaffected (members folder is Cycle 2b, separate from contacts folder)                                                                                     |
| Calendar                               | unaffected                                                                                                                                                 |
| Venues                                 | **affected** (venues screens are in lib/features/contacts/widgets/ — venue_form_screen, venue_detail_screen, venues_view, venue_card, venue_contact_block) |
| Contacts                               | **affected** (contact_form_screen, contacts_view, contact_card, band_member_detail_drawer, band_member_edit_drawer, invite_members_screen)                 |
| Auth / Session                         | unaffected                                                                                                                                                 |
| Profile                                | unaffected                                                                                                                                                 |
| Settings                               | unaffected                                                                                                                                                 |
| Notifications                          | unaffected                                                                                                                                                 |
| Routing                                | unaffected                                                                                                                                                 |
| Platform (iOS / Android / Web / macOS) | affected (must render correctly across all 4 platforms—but wrappers delegate to Material widgets with theme config, so platform equivalence is default)    |

---

## Regression Risk

**Risk Level:** MEDIUM-HIGH

**Rationale:**

- **11 files modified, 55+ widget call substitutions** — Large surface area for mechanical errors
- **7 destructive action call sites with AppColors.error styling** — High-risk mappings per Cycle 1 lesson: wrong variant or lost error styling could make destructive actions look non-destructive (user deletes without realizing) or vice versa
- **4 loading states inside buttons** — Must consolidate correctly to AppButton's isLoading prop; if conditional logic drifts, button breaks or crashes
- **Multiple TextEditingController + FocusNode instances** — 15+ controllers and 15+ focus nodes across form files must be preserved exactly; losing a controller or focus node breaks form state
- **No automated tests for target screens** — Regression check is code-path analysis only (QA diff review), not runtime-validated
- **But: Zero logic changes, zero new state, zero backend surface** — Pure widget-call substitution preserves all existing behavior if mapping is executed correctly

**Primary risks:**

1. **Destructive variant mapping error:** Engineer maps `AppColors.error` button to wrong variant (e.g., `text` instead of `destructive`), causing visual regression where delete button looks like cancel button
2. **isLoading prop consolidation error:** Engineer incorrectly consolidates conditional `_isSaving ? CircularProgressIndicator() : Text(...)` child, causing button to always show loading or always show text (logic drift)
3. **Controller/FocusNode loss:** Engineer omits a controller or focus node during TextField→AppTextField mapping, breaking form state or focus traversal
4. **Conditional structure drift:** Engineer flattens/changes conditional logic while replacing widget, causing runtime crash or wrong widget shown
5. **Import omission:** Engineer forgets to import wrapper, causing compile error caught by `flutter analyze` (low severity, caught early)

**Mitigation:**

- **Exhaustive mapping table above** — Every single substitution is pre-defined, Engineer executes only (no judgment calls)
- **Destructive action call-out list** — QA must explicitly verify each of the 7 destructive action call sites for correct variant mapping and preserved AppColors.error styling
- **flutter analyze as gate** — Catches import/compile errors immediately
- **QA code-path analysis** — QA must diff every changed file and verify each substitution is 1:1 per mapping table (no logic drift, no prop mismatches, no controller loss)
- **Manual smoke test recommended** — Tony should manually test contacts + venues screens on a real device/browser after QA approval, focusing on: (1) delete/remove buttons still show error styling, (2) form inputs still work with keyboard traversal, (3) loading states show correctly in save/invite buttons

---

## Engineer Task Breakdown

Execute in strict order. Do not proceed to next task until current task is verified passing.

### Task 1: Verify working directory and branch

- **Command:** `pwd` (expect `/Users/tonyholmes/apps/bandroadie-ui-experiment`)
- **Command:** `git branch --show-current` (expect `experiment/ui-facade`)
- **Command:** `git status --short` (expect clean—no dirty files)
- **If any check fails:** STOP and report to Tony

### Task 2: Create feature docs directory (already done by Architect)

- **Directory:** `docs/features/ui-facade-retrofit-contacts-venues/`
- **Verification:** Directory exists (Architect created it)

### Task 3: Read all 11 target files for context

- **Action:** Read each of the 11 files listed in Files to Modify table to understand their structure before editing
- **Purpose:** Familiarize with code patterns, confirm line numbers in mapping table are approximately correct
- **Critical focus:** Identify all 7 destructive action call sites and all 4 loading-state-inside-button call sites before starting edits

### Task 4: Retrofit az_search_field.dart

- **File:** `lib/features/contacts/widgets/az_search_field.dart`
- **Action:** Execute every substitution per mapping table: TextField → AppTextField, IconButton → AppIconButton
- **Add imports:** `import 'package:bandroadie/components/ui/app_text_field.dart';`, `app_icon_button.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/az_search_field.dart` — 0 errors
- **Verification:** File compiles, no missing symbols

### Task 5: Retrofit band_member_detail_drawer.dart

- **File:** `lib/features/contacts/widgets/band_member_detail_drawer.dart`
- **Action:** Execute every substitution per mapping table: showModalBottomSheet → showAppBottomSheet, TextButton → AppButton
- **Add imports:** `app_bottom_sheet.dart`, `app_button.dart`
- **Special note:** Verify BrandActionButton is left untouched (precedent component)
- **Verification:** `flutter analyze lib/features/contacts/widgets/band_member_detail_drawer.dart` — 0 errors

### Task 6: Retrofit band_member_edit_drawer.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS**

- **File:** `lib/features/contacts/widgets/band_member_edit_drawer.dart`
- **Action:** Execute every substitution per mapping table:
  - showModalBottomSheet → showAppBottomSheet
  - showDialog (Remove member confirmation) → showAppDialog with `isDestructive: true` on "Remove" action
  - TextButton.icon "Remove from band" → AppButton with `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
  - FilledButton "Save" → AppButton with `variant: AppButtonVariant.primary` and `isLoading: _isSaving`
  - TextButton "Cancel" → AppButton with `variant: AppButtonVariant.text`
- **KEEP AS-IS:** SwitchListTile permission toggles (boundary exception, see plan)
- **Add imports:** `app_bottom_sheet.dart`, `app_dialog.dart`, `app_button.dart`
- **Critical verification:** After editing, manually inspect lines ~230 (AlertDialog delete action) and ~545-550 (Remove from band button) to confirm:
  1. `isDestructive: true` is present on DialogAction
  2. `variant: AppButtonVariant.destructive` is present on AppButton
  3. `isLoading: _isRemoving` is present on AppButton (replaces conditional icon)
- **Verification:** `flutter analyze lib/features/contacts/widgets/band_member_edit_drawer.dart` — 0 errors

### Task 7: Retrofit contact_form_screen.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS**

- **File:** `lib/features/contacts/widgets/contact_form_screen.dart`
- **Action:** Execute every substitution per mapping table:
  - showDialog (Delete contact confirmation) → showAppDialog with `isDestructive: true` on "Delete" action
  - Scaffold → AppScaffold
  - AppBar → AppAppBar
  - IconButton (close button) → AppIconButton
  - TextButton (Save button with loading) → AppButton with `variant: AppButtonVariant.text` and `isLoading: _isSaving`
  - TextField (all 5 fields: Name, Company, Phone, Email, Notes) → AppTextField with full decoration passthrough
  - TextButton "Delete Contact" → AppButton with `variant: AppButtonVariant.destructive`
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_icon_button.dart`, `app_button.dart`, `app_text_field.dart`, `app_dialog.dart`
- **Critical verification:** After editing, manually inspect lines ~173 (AlertDialog delete action) and ~382 (Delete Contact button) to confirm:
  1. `isDestructive: true` is present on DialogAction
  2. `variant: AppButtonVariant.destructive` is present on AppButton
- **Controller/FocusNode verification:** Confirm all 5 TextEditingController and 5 FocusNode instances are passed to AppTextField exactly as written (no omissions)
- **Verification:** `flutter analyze lib/features/contacts/widgets/contact_form_screen.dart` — 0 errors

### Task 8: Retrofit contacts_view.dart

- **File:** `lib/features/contacts/widgets/contacts_view.dart`
- **Action:** Execute every substitution per mapping table: TextButton → AppButton, TextButton.icon → AppButton with icon prop
- **Add imports:** `app_button.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/contacts_view.dart` — 0 errors

### Task 9: Retrofit invite_members_screen.dart

- **File:** `lib/features/contacts/widgets/invite_members_screen.dart`
- **Action:** Execute every substitution per mapping table:
  - showDialog (Cancel invite confirmation) → showAppDialog (note: second action is ElevatedButton → maps to secondary, NOT destructive)
  - Scaffold → AppScaffold
  - AppBar → AppAppBar
  - IconButton (back button) → AppIconButton
  - TextFormField (email input) → AppTextFormField with `onSubmitted` (not `onFieldSubmitted`)
  - Buttons with loading states → AppButton with `isLoading` prop
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_icon_button.dart`, `app_text_form_field.dart`, `app_button.dart`, `app_dialog.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/invite_members_screen.dart` — 0 errors

### Task 10: Retrofit title_pill_selector.dart

- **File:** `lib/features/contacts/widgets/title_pill_selector.dart`
- **Action:** Execute every substitution per mapping table: TextField → AppTextField
- **Add imports:** `app_text_field.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/title_pill_selector.dart` — 0 errors

### Task 11: Retrofit venue_contact_block.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTION**

- **File:** `lib/features/contacts/widgets/venue_contact_block.dart`
- **Action:** Execute every substitution per mapping table:
  - IconButton (delete button) → AppIconButton with `color: AppColors.error` (preserve error color)
  - TextField (all 4 fields: Name, Phone, Email, Notes) → AppTextField with full decoration passthrough
- **Add imports:** `app_icon_button.dart`, `app_text_field.dart`
- **Critical verification:** After editing, manually inspect line ~164 (delete button) to confirm `color: AppColors.error` is present on AppIconButton
- **Controller/FocusNode verification:** Confirm all 4 TextEditingController and 4 FocusNode instances are passed to AppTextField exactly as written
- **Verification:** `flutter analyze lib/features/contacts/widgets/venue_contact_block.dart` — 0 errors

### Task 12: Retrofit venue_detail_screen.dart

- **File:** `lib/features/contacts/widgets/venue_detail_screen.dart`
- **Action:** Execute every substitution per mapping table:
  - Scaffold → AppScaffold
  - AppBar → AppAppBar
  - TextButton (Edit button) → AppButton with `variant: AppButtonVariant.text`
  - showModalBottomSheet → showAppBottomSheet
- **KEEP AS-IS:** IconButton with border styling (boundary exception, see plan — verify with Tony if unsure)
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_button.dart`, `app_bottom_sheet.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/venue_detail_screen.dart` — 0 errors

### Task 13: Retrofit venue_form_screen.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS**

- **File:** `lib/features/contacts/widgets/venue_form_screen.dart`
- **Action:** Execute every substitution per mapping table:
  - showDialog (Delete venue confirmation) → showAppDialog with `isDestructive: true` on "Delete" action
  - Scaffold → AppScaffold
  - AppBar → AppAppBar
  - IconButton (close button) → AppIconButton
  - TextButton (Save button with loading) → AppButton with `variant: AppButtonVariant.text` and `isLoading: _isSaving`
  - TextField (all 6 fields: Name, Address, City, State, Phone, Notes) → AppTextField with full decoration passthrough
  - TextButton.icon "Add Contact" → AppButton with icon prop
  - TextButton "Delete Venue" → AppButton with `variant: AppButtonVariant.destructive`
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_icon_button.dart`, `app_button.dart`, `app_text_field.dart`, `app_dialog.dart`
- **Critical verification:** After editing, manually inspect lines ~266 (AlertDialog delete action) and ~483 (Delete Venue button) to confirm:
  1. `isDestructive: true` is present on DialogAction
  2. `variant: AppButtonVariant.destructive` is present on AppButton
- **Controller/FocusNode verification:** Confirm all 6 TextEditingController and 6 FocusNode instances are passed to AppTextField exactly as written
- **Verification:** `flutter analyze lib/features/contacts/widgets/venue_form_screen.dart` — 0 errors

### Task 14: Retrofit venues_view.dart

- **File:** `lib/features/contacts/widgets/venues_view.dart`
- **Action:** Execute every substitution per mapping table: TextButton → AppButton, TextButton.icon → AppButton with icon prop
- **Add imports:** `app_button.dart`
- **Verification:** `flutter analyze lib/features/contacts/widgets/venues_view.dart` — 0 errors

### Task 15: Verify zero files modified outside target files

- **Command:** `git diff --name-only`
- **Expected output:** Only the 11 files listed in Files to Modify table, no modifications to any file outside `lib/features/contacts/widgets/`
- **Regression guard:** This confirms no unintended files were touched

### Task 16: Run flutter analyze on entire contacts folder

- **Command:** `flutter analyze lib/features/contacts/`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding. Common errors: missing imports, typos in prop names, wrong enum values.

### Task 17: Build app for web (mandatory)

- **Command:** `flutter build web --release`
- **Expected output:** Build succeeds, `build/web/` directory contains compiled output
- **If build fails:** Read error message carefully. Common failures: syntax errors not caught by analyze, missing enum imports.

### Task 18: Spot-check destructive action call sites (manual code review)

**Critical regression check — do not skip**

For each of the 7 destructive action call sites, manually open the file and verify:

1. `band_member_edit_drawer.dart` line ~230: showAppDialog has `DialogAction(label: 'Remove', isDestructive: true)`
2. `band_member_edit_drawer.dart` line ~545-550: AppButton has `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
3. `contact_form_screen.dart` line ~173: showAppDialog has `DialogAction(label: 'Delete', isDestructive: true)`
4. `contact_form_screen.dart` line ~382: AppButton has `variant: AppButtonVariant.destructive`
5. `venue_contact_block.dart` line ~164: AppIconButton has `color: AppColors.error`
6. `venue_form_screen.dart` line ~266: showAppDialog has `DialogAction(label: 'Delete', isDestructive: true)`
7. `venue_form_screen.dart` line ~483: AppButton has `variant: AppButtonVariant.destructive`

**If any verification fails:** Fix immediately before proceeding. These are the highest-risk mappings.

### Task 19: Spot-check controller/focus-node preservation (manual code review)

For each form file with multiple controllers, manually verify all controllers and focus nodes are passed to AppTextField:

1. `contact_form_screen.dart`: 5 controllers + 5 focus nodes
2. `venue_form_screen.dart`: 6 controllers + 6 focus nodes
3. `venue_contact_block.dart`: 4 controllers + 4 focus nodes

**If any controller or focus node is missing:** Fix immediately. Lost controllers break form state.

### Task 20: Create ENGINEER_REPORT.md

- **File:** `docs/features/ui-facade-retrofit-contacts-venues/ENGINEER_REPORT.md`
- **Required sections:**
  1. **Summary** — "Retrofitted 11 files in lib/features/contacts/widgets/ to use App\* wrapper components. 55+ Material widget call sites replaced with wrapper equivalents per ARCHITECT_PLAN.md mapping table. All destructive action call sites verified for correct variant mapping. Zero logic changes, zero behavior changes."
  2. **Files Modified** — List all 11 files with line counts (before/after) and brief description of changes
  3. **Destructive Action Call Sites — Verification** — For each of the 7 destructive action call sites, confirm correct mapping (e.g., "band_member_edit_drawer.dart line 230: showAppDialog 'Remove' action has isDestructive: true ✓")
  4. **Boundary Exceptions** — List SwitchListTile in band_member_edit_drawer.dart and IconButton border styling in venue_detail_screen.dart with justification per plan
  5. **Test Results** — `flutter analyze` output (0 errors), `flutter build web` output (success)
  6. **Known Issues** — None expected. If any discovered, document here.

---

## Verification Plan

**Tier 1 — Pre-deployment (N/A for this feature—no migrations):**

This feature has no database migrations, edge functions, or backend changes. All verification is Flutter-local.

**Tier 2 — Post-implementation:**

### Test 1: flutter analyze passes with 0 errors

```bash
cd /Users/tonyholmes/apps/bandroadie-ui-experiment
flutter analyze lib/features/contacts/
```

**Expected output:** 0 errors, 0 warnings.

### Test 2: flutter build web succeeds

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Expected output:** Build succeeds, `build/web/` directory contains compiled output.

### Test 3: git diff confirms only 11 files modified in contacts/widgets/

```bash
git diff --name-only
```

**Expected output:** Exactly 11 files under `lib/features/contacts/widgets/`, zero other files touched. This is the primary regression guard—confirms no unintended files were changed.

### Test 4: Code-path analysis — Destructive action call sites

QA must manually diff each of the 7 destructive action call sites and verify:

1. `band_member_edit_drawer.dart` ~line 230: AlertDialog "Remove" action has `isDestructive: true` in DialogAction
2. `band_member_edit_drawer.dart` ~line 545-550: "Remove from band" button has `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
3. `contact_form_screen.dart` ~line 173: AlertDialog "Delete" action has `isDestructive: true` in DialogAction
4. `contact_form_screen.dart` ~line 382: "Delete Contact" button has `variant: AppButtonVariant.destructive`
5. `venue_contact_block.dart` ~line 164: Delete icon button has `color: AppColors.error`
6. `venue_form_screen.dart` ~line 266: AlertDialog "Delete" action has `isDestructive: true` in DialogAction
7. `venue_form_screen.dart` ~line 483: "Delete Venue" button has `variant: AppButtonVariant.destructive`

**Each verification must confirm two things:**

- The mapping table was followed exactly (no improvisation)
- The wrapper call uses the correct destructive variant/prop (no visual regression — button still looks dangerous)

**Pass criteria:** All 7 call sites verified correct. Any deviation is a FAIL and must be fixed before QA approval.

### Test 5: Code-path analysis — Loading state consolidation

QA must manually diff each of the 4 loading-state-inside-button call sites and verify:

1. `band_member_edit_drawer.dart` ~line 585-599: Save button consolidated to `AppButton` with `isLoading: _isSaving`
2. `contact_form_screen.dart` ~line 247-260: Save button consolidated to `AppButton` with `isLoading: _isSaving`
3. `invite_members_screen.dart` ~line 365: Invite button consolidated to `AppButton` with `isLoading` prop
4. `venue_form_screen.dart` ~line 345-360: Save button consolidated to `AppButton` with `isLoading: _isSaving`

**Each verification must confirm:**

- Conditional `_isSaving ? CircularProgressIndicator() : Text(...)` child was replaced with `isLoading: _isSaving` prop
- Button's label is always the same (no conditional text)
- Button's onPressed callback is still disabled when loading (`_isSaving ? null : callback`)

**Pass criteria:** All 4 call sites verified correct. Any deviation is a FAIL.

### Test 6: Code-path analysis — Controller/FocusNode preservation

QA must manually verify all TextEditingController and FocusNode instances are passed to AppTextField in form files:

- `contact_form_screen.dart`: 5 controllers + 5 focus nodes
- `venue_form_screen.dart`: 6 controllers + 6 focus nodes
- `venue_contact_block.dart`: 4 controllers + 4 focus nodes

**Pass criteria:** Every TextField→AppTextField mapping has `controller: _xyzController` and `focusNode: _xyzFocus` props exactly as before. Any omission is a FAIL.

---

## QA Regression Areas

**This is the first retrofit cycle touching destructive user actions (delete venue, remove member from band). QA verification must be more thorough than Cycle 1.**

### Critical verification areas (manual testing recommended):

1. **Destructive action styling preserved:**
   - Navigate to Edit Member drawer (from band members list)
   - Verify "Remove from band" button at bottom still has red/error styling (text + icon are red)
   - Tap button, verify confirmation dialog's "Remove" action has red text
   - Navigate to Edit Contact screen (from contacts list)
   - Verify "Delete Contact" button at bottom still has red/error styling
   - Tap button, verify confirmation dialog's "Delete" action has red text
   - Navigate to Edit Venue screen (from venues list)
   - Verify "Delete Venue" button at bottom still has red/error styling
   - Tap button, verify confirmation dialog's "Delete" action has red text
   - Navigate to venue contacts section (in Edit Venue screen)
   - Verify each contact's delete icon button (trash icon) is red

2. **Loading states work correctly:**
   - Navigate to Edit Contact screen, modify a field, tap "Save" in AppBar
   - Verify: button shows loading spinner while saving, then returns to "Save" text
   - Repeat for Edit Venue screen
   - Repeat for Edit Member drawer
   - Navigate to Invite Members screen, enter email, tap invite button
   - Verify: button shows loading spinner while sending, then returns to normal

3. **Form inputs work correctly:**
   - Navigate to New Contact screen, tap through all fields (Name, Company, Phone, Email, Notes)
   - Verify: keyboard tab/next actions advance focus correctly, all text inputs accept text, no crashes
   - Repeat for New Venue screen (Name, Address, City, State, Phone, Notes)
   - Navigate to Edit Venue screen, add a venue contact, fill all contact fields
   - Verify: venue contact sub-form inputs work correctly

4. **Boundary exceptions are acceptable:**
   - Navigate to Edit Member drawer, verify permission toggles (SwitchListTile) still work correctly
   - Navigate to Venue Detail screen, verify navigate button (with border) still looks correct
   - These are boundary exceptions per plan — confirm they're visually/functionally unchanged

### Automated verification (code review):

5. **Confirm zero files modified outside target files:** Review `git diff --name-only` output—only 11 files in lib/features/contacts/widgets/ modified
6. **Confirm all destructive action call sites use correct variant:** Manual diff review per Test 4 above
7. **Confirm all loading states consolidated correctly:** Manual diff review per Test 5 above
8. **Confirm all controllers/focus nodes preserved:** Manual diff review per Test 6 above
9. **Confirm no runtime errors introduced:** Run `flutter analyze lib/features/contacts/`, confirm 0 errors

**Pass criteria:** All 9 verification areas passed. Any failure in critical areas 1-4 is a FAIL verdict and blocks commit.

---

## Rollout / Migration Strategy

Not applicable — this feature introduces no user-facing behavior changes, no database migrations, no backend changes. Rollout is a standard git merge + deploy (no special sequencing required).

After merge to `experiment/ui-facade` and confirmation that branch builds successfully, this becomes part of the ongoing facade-layer migration (Cycle 2b and beyond will follow).

---

## Out of Scope

The following are explicitly deferred to Cycle 2b (members + calendar + rehearsals folders) or later cycles:

1. **lib/features/members/widgets/role_management_sheet.dart** — Explicitly out of scope per feature input. This file is in the `members` folder (not `contacts`), which is Cycle 2b. Do not touch it in this cycle.
2. **Retrofitting other feature folders** — This cycle only touches `lib/features/contacts/`. All other folders (setlists, gigs, calendar, rehearsals, members) are separate cycles.
3. **Extending wrapper API for new gaps** — If a gap is discovered during implementation, STOP and report to Architect. Do not improvise or extend wrappers mid-retrofit. This cycle assumes wrapper API is complete per wrapper-gaps cycle.
4. **Custom styling or behavior changes** — Wrappers remain visually and behaviorally identical to Material defaults (delegating to theme config). Any design-system customization is future work after all retrofits complete.
5. **Decomposing composite widgets** — SwitchListTile is kept as-is per boundary exception. Do not decompose it or other composite widgets unless Architect plan explicitly requires it.
6. **Adding wrapper support for IconButton border styling** — IconButton with custom border in venue_detail_screen.dart is kept as-is per boundary exception. Do not extend AppIconButton API mid-cycle.

---

**Architect:** AI Agent  
**Date:** 2026-08-07  
**Worktree:** `/Users/tonyholmes/apps/bandroadie-ui-experiment`  
**Branch:** `experiment/ui-facade` (existing—not creating new branch per override)
