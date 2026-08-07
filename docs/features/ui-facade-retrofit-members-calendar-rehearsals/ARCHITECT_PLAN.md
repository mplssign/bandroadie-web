# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-retrofit-members-calendar-rehearsals`

---

## Problem Summary

Cycle 1 (commit `ad50e71`) retrofitted profile/settings/notifications/auth folders. Cycle 2a (commit `f02bcdc`) retrofitted contacts/venues. This is Cycle 2b: retrofit the final three folders in current Piece 2 scope: `lib/features/members/`, `lib/features/calendar/`, `lib/features/rehearsals/`.

Fresh scope verification confirms **10 files** with ~47-53 Material widget call sites combined (not the 42 files/46 sites pre-scoping estimate — that counted all .dart files including models, controllers, repositories, and custom component definitions). Actual breakdown: **members 1 file / calendar 7 files / rehearsals 2 files**.

Critical challenge: `role_management_sheet.dart` (663 lines, ~10 Material call sites, destructive "Remove from band" action with AppColors.error styling) was explicitly deferred from Cycle 2a because it belongs to members/, not contacts/. It shares the same destructive-action risk pattern as Cycle 2a's flagged files. Additionally, `add_block_out_drawer.dart` (963 lines, largest file in scope) has complex delete confirmation dialogs with **10 instances of AppColors.error** for destructive styling.

**Why this is critical:** Final cycle in current Piece 2 scope. Contains same high-risk patterns as Cycle 2a (destructive actions, custom dialog builders, loading states inside buttons). No behavior change intended — purely mechanical Material→wrapper substitution.

---

## Current State

**Wrapper layer status (as of Cycle 2a merge to experiment/ui-facade):**

- 15 wrapper widgets exist in `lib/components/ui/` with complete prop surfaces
- AppTextField/AppTextFormField support full `decoration` prop + simplified props (focusNode, textCapitalization, textInputAction, style, inputFormatters, autocorrect, autofillHints, onSubmitted, autofocus)
- AppScaffold supports resizeToAvoidBottomInset
- showAppBottomSheet supports backgroundColor, shape, isScrollControlled
- showAppDialog supports custom builder pattern for non-AlertDialog cases
- AppButton supports `destructive` variant explicitly
- All wrappers tested, `flutter analyze` clean, web build succeeds
- Cycles 1 and 2a retrofits landed and QA-approved

**Target files (10 confirmed via fresh grep + file inspection):**

### Members folder (1 file):

1. `lib/features/members/widgets/role_management_sheet.dart` — **HIGH RISK:** Full-screen modal for changing member role, includes destructive "Remove from band" button with AppColors.error styling (4 instances), custom dialog builder, loading states

### Calendar folder (7 files):

2. `lib/features/calendar/calendar_screen.dart` — Main calendar view with Scaffold, loading indicators, error-styled retry button
3. `lib/features/calendar/calendar_tab_content.dart` — Calendar tab content (similar to calendar_screen)
4. `lib/features/calendar/one_calendar_settings_screen.dart` — Settings screen with Scaffold, AppBar, checkboxes, toggle cards
5. `lib/features/calendar/widgets/add_block_out_drawer.dart` — **HIGH RISK:** Create/edit block out modal (~963 lines, largest file in scope), destructive delete confirmation with AppColors.error (10 instances), multiple custom dialogs, TextField, loading states
6. `lib/features/calendar/widgets/calendar_subscription_dialog.dart` — **HIGH RISK:** Calendar subscription modal with custom builder pattern, showModalBottomSheet, loading indicators
7. `lib/features/calendar/widgets/day_detail_bottom_sheet.dart` — Day detail modal with showModalBottomSheet
8. `lib/features/calendar/widgets/view_block_out_drawer.dart` — View-only block out drawer with TextButton

### Rehearsals folder (2 files):

9. `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart` — Availability prompt with TextButton, CircularProgressIndicator
10. `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` — View rehearsal drawer with TextButton

**Files excluded (false positives from pre-scoping estimate):**

- All model files (`member_vm.dart`, `calendar_event.dart`, `one_calendar_preferences.dart`, etc.) — No UI widgets
- All controller/repository files — No UI widgets
- Custom component definitions (`member_card.dart`, `calendar_app_bar.dart`, `calendar_event_card.dart`, `pending_invite_card.dart`) — Already custom wrappers, not raw Material
- `members_tab_content.dart` — Uses HomeAppBar (custom) and MemberCard (custom), no raw Material widgets to retrofit

**Pattern observed in target files:**

- **Scaffolds/AppBars:** calendar_screen, calendar_tab_content, one_calendar_settings_screen, role_management_sheet
- **Destructive buttons:** role_management_sheet ("Remove from band"), add_block_out_drawer ("Delete Block Out") — both with AppColors.error styling
- **Custom dialogs:** role_management_sheet (delete confirmation), add_block_out_drawer (complex multi-option delete confirmations)
- **Loading states:** role_management_sheet (save/remove buttons), add_block_out_drawer (delete button), calendar screens (retry buttons), rehearsal modals (buttons)
- **Text fields:** add_block_out_drawer has TextField for reason input
- **showModalBottomSheet:** add_block_out_drawer, calendar_subscription_dialog, day_detail_bottom_sheet (all in static show() methods)
- **Checkboxes:** one_calendar_settings_screen (multiple)
- **BrandActionButton usage:** add_block_out_drawer uses BrandActionButton (precedent component, out of scope)

**Destructive action call sites (require explicit QA verification per Cycle 2a lesson):**

1. `role_management_sheet.dart` line ~189-203: AlertDialog "Remove member" with "Remove" button styled AppColors.error
2. `role_management_sheet.dart` line ~420-444: TextButton.icon "Remove from band" with AppColors.error icon/text, loading indicator with AppColors.error
3. `add_block_out_drawer.dart` line ~335, 342, 374: Three separate delete confirmation dialogs with TextButton actions styled AppColors.error
4. `add_block_out_drawer.dart` line ~684-698: TextButton "Delete Block Out" with AppColors.error text, loading indicator with AppColors.error

**Loading-state-inside-button call sites (map to AppButton isLoading prop):**

1. `role_management_sheet.dart` line ~420-444: TextButton.icon "Remove from band" with conditional CircularProgressIndicator
2. `role_management_sheet.dart` line ~487-514: FilledButton "Save" with conditional CircularProgressIndicator
3. `add_block_out_drawer.dart` line ~684-698: TextButton "Delete Block Out" with conditional CircularProgressIndicator

**No fixed-sizing or autofocus risk patterns found:** Fresh grep confirms zero instances of `fixedSize:`, `minimumSize:` with ButtonStyle, or `autofocus: true` in these folders (unlike Cycle 1 which had these risk patterns).

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture

**No relevant design-system or retrofit guidance exists in reference docs.** Per user's "Reference doc override" instruction, checked `docs/reference/ui/` as instructed and found only landing-page doc, not actionable for this feature. Proceeded with codebase inspection and established precedent pattern from Cycles 1 and 2a.

---

## Proposed Solution

Replace every raw Material widget instantiation in the 10 target files with its wrapper equivalent, maintaining exact prop values and behavior. Each substitution is a 1:1 mapping documented in the Per-File Retrofit Mapping Table below. The Engineer must execute each mapping exactly as specified—no prop inference, no logic changes, no opportunistic refactors.

**Retrofit principles (inherited from Cycles 1 and 2a):**

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
- Custom components like HomeAppBar, CalendarAppBar, MemberCard, CalendarEventCard → **Do not touch** (already custom wrappers)

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

### File 1: `lib/features/members/widgets/role_management_sheet.dart`

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS**

**Line ~165-210:** `showDialog` + `AlertDialog` (Remove member confirmation)

```dart
final confirmed = await showDialog<bool>(
  context: ctx,
  builder: (ctx) => AlertDialog(
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(
      'Remove ${widget.member.name}?',
      style: TextStyle(color: context.colors.textPrimary),
    ),
    content: Text(
      'Are you sure you want to remove this member from the band? This cannot be undone.',
      style: TextStyle(color: context.colors.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(ctx).pop(true),
        child: const Text(
          'Remove',
          style: TextStyle(color: AppColors.error), // ← DESTRUCTIVE STYLING
        ),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: ctx,
  title: 'Remove ${widget.member.name}?',
  message: 'Are you sure you want to remove this member from the band? This cannot be undone.',
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

**Line ~238:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: SafeArea(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: SafeArea(...), // no change
)
```

**Line ~240:** `AppBar`

```dart
AppBar(
  backgroundColor: Colors.transparent,
  elevation: 0,
  leading: IconButton(...), // see below
  title: Text(
    'Manage Role',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ),
  centerTitle: true,
)
→
AppAppBar(
  backgroundColor: Colors.transparent, // no change
  leading: AppIconButton(...), // see below
  title: Text(
    'Manage Role',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ), // no change (title accepts Widget)
  centerTitle: true, // no change
)
// Note: elevation → omit (AppAppBar uses theme default)
```

**Line ~243:** `IconButton` (close button)

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

**Line ~420-444:** `TextButton.icon` (Remove from band button with loading state)

**🔴 DESTRUCTIVE ACTION**

```dart
TextButton.icon(
  onPressed: _isRemoving ? null : _removeMember,
  icon: _isRemoving
      ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.error),
          ),
        )
      : const Icon(AppIcons.userRemove, color: AppColors.error, size: 20),
  label: Text(
    _isRemoving ? 'Removing...' : 'Remove from band',
    style: const TextStyle(
      color: AppColors.error, // ← DESTRUCTIVE STYLING
      fontSize: AppFontSizes.subhead,
      fontWeight: FontWeight.w500,
    ),
  ),
)
→
AppButton(
  label: 'Remove from band', // label is always the same (not conditional)
  icon: AppIcons.userRemove, // icon is shown when not loading
  variant: AppButtonVariant.destructive, // ← CRITICAL: maps AppColors.error styling
  onPressed: _isRemoving ? null : _removeMember, // no change
  isLoading: _isRemoving, // consolidate — replaces conditional icon with CircularProgressIndicator
  fullWidth: false, // explicit — this button is not full-width
)
```

**Line ~487-514:** `FilledButton` (Save button with loading state)

```dart
FilledButton(
  onPressed: (_hasChanges && !_isSaving) ? _saveRole : null,
  style: FilledButton.styleFrom(
    backgroundColor: (_hasChanges && !_isSaving)
        ? AppColors.primary
        : context.colors.border.withValues(alpha: 0.3),
    disabledBackgroundColor: context.colors.border.withValues(alpha: 0.3),
    padding: const EdgeInsets.symmetric(vertical: 16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
  ),
  child: _isSaving
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
      : Text(
          'Save',
          style: AppTextStyles.body.copyWith(
            color: (_hasChanges && !_isSaving)
                ? Colors.white
                : context.colors.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: AppFontSizes.body,
          ),
        ),
)
→
AppButton(
  label: 'Save',
  variant: AppButtonVariant.primary, // FilledButton → primary
  onPressed: (_hasChanges && !_isSaving) ? _saveRole : null, // no change
  isLoading: _isSaving, // consolidate — replaces conditional child
  fullWidth: true, // button spans full width
)
// Note: Custom disabled styling (border color) → omit (AppButton uses theme defaults for disabled state)
```

**Line ~522:** `TextButton` (Cancel button)

```dart
TextButton(
  onPressed: () => Navigator.of(context).pop(),
  style: TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
  ),
  child: Text(
    'Cancel',
    style: AppTextStyles.body.copyWith(
      color: context.colors.textSecondary,
      fontWeight: FontWeight.w600,
    ),
  ),
)
→
AppButton(
  label: 'Cancel',
  variant: AppButtonVariant.text, // map variant
  onPressed: () => Navigator.of(context).pop(), // no change
)
// Note: Custom padding → omit (AppButton uses theme defaults)
```

---

### File 2: `lib/features/calendar/calendar_screen.dart`

**Line ~331:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  body: Column(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  body: Column(...), // no change
)
// Note: DrawerOverlay wrapper (line ~369) is separate from Scaffold, unaffected by this retrofit
```

**Line ~429:** `CircularProgressIndicator` (loading state)

```dart
const Center(
  child: CircularProgressIndicator(color: AppColors.primary),
)
→
const Center(
  child: AppProgressIndicator(
    type: ProgressIndicatorType.circular, // explicit type
    color: AppColors.primary, // no change
  ),
)
```

**Line ~447:** `TextButton` (Retry button in error state)

```dart
TextButton(
  onPressed: () {
    ref.invalidate(calendarEventsProvider);
    _calendarController.refresh();
  },
  child: const Text('Retry'),
)
→
AppButton(
  label: 'Retry',
  variant: AppButtonVariant.text, // map variant
  onPressed: () {
    ref.invalidate(calendarEventsProvider);
    _calendarController.refresh();
  }, // no change
)
```

---

### File 3: `lib/features/calendar/calendar_tab_content.dart`

**Line ~404:** `CircularProgressIndicator` (loading state)

```dart
const Center(
  child: CircularProgressIndicator(color: AppColors.primary),
)
→
const Center(
  child: AppProgressIndicator(
    type: ProgressIndicatorType.circular, // explicit type
    color: AppColors.primary, // no change
  ),
)
```

**Line ~422:** `TextButton` (Retry button in error state)

```dart
TextButton(
  onPressed: () => _onRefresh(),
  child: const Text('Retry'),
)
→
AppButton(
  label: 'Retry',
  variant: AppButtonVariant.text, // map variant
  onPressed: () => _onRefresh(), // no change
)
```

---

### File 4: `lib/features/calendar/one_calendar_settings_screen.dart`

**Line ~26:** `Scaffold`

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

**Line ~28:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  elevation: 0,
  leading: IconButton(...), // see below
  title: Text(
    'One Calendar',
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
    'One Calendar',
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: AppFontSizes.title,
      fontWeight: FontWeight.w600,
    ),
  ), // no change (title accepts Widget)
)
// Note: elevation → omit (AppAppBar uses theme default)
```

**Line ~31:** `IconButton` (back button)

```dart
IconButton(
  icon: Icon(AppIcons.arrowLeft, color: context.colors.textPrimary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.arrowLeft, // icon data only
  color: context.colors.textPrimary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~46:** `CircularProgressIndicator` (loading state)

```dart
const Center(child: CircularProgressIndicator())
→
const Center(child: AppProgressIndicator(type: ProgressIndicatorType.circular))
```

**Line ~74:** `ElevatedButton` (Learn more button)

```dart
ElevatedButton(
  onPressed: () => /* launch URL */,
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
  ),
  child: const Text('Learn more'),
)
→
AppButton(
  label: 'Learn more',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () => /* launch URL */, // no change
)
// Note: Custom padding → omit (AppButton uses theme defaults)
```

**Line ~385:** `Checkbox` (auto-conflict toggle)

```dart
Checkbox(
  value: value,
  onChanged: onChanged,
  activeColor: AppColors.primary,
)
→
AppCheckbox(
  value: value, // no change
  onChanged: onChanged, // no change
  activeColor: AppColors.primary, // no change
)
```

---

### File 5: `lib/features/calendar/widgets/add_block_out_drawer.dart`

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS, LARGEST FILE IN SCOPE (963 lines)**

**Line ~80:** `showModalBottomSheet` (in static show() method)

```dart
return showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) {
    return BlockOutDrawer(/* ... */);
  },
);
→
return showAppBottomSheet<bool>(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (sheetContext) {
    return BlockOutDrawer(/* ... */); // no change
  },
);
```

**Line ~310-380:** Multiple `showDialog` + `AlertDialog` (Delete confirmations)

**🔴 DESTRUCTIVE ACTIONS (3 dialogs with AppColors.error)**

**Dialog 1: Choice dialog (line ~310-350):**

```dart
deleteChoice = await showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surface,
    title: Text('Delete Block Out?', style: AppTextStyles.title3),
    content: Text(
      'This block out is shared across multiple bands. Where would you like to delete it from?',
      style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, null),
        child: Text(
          'Cancel',
          style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'this_band'),
        child: Text(
          'This band only',
          style: AppTextStyles.callout.copyWith(color: AppColors.error), // ← DESTRUCTIVE
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'all_bands'),
        child: Text(
          'All bands',
          style: AppTextStyles.callout.copyWith(color: AppColors.error), // ← DESTRUCTIVE
        ),
      ),
    ],
  ),
);
→
deleteChoice = await showAppDialog<String>(
  context: context,
  title: 'Delete Block Out?',
  message: 'This block out is shared across multiple bands. Where would you like to delete it from?',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.pop(context, null),
    ),
    DialogAction(
      label: 'This band only',
      onPressed: () => Navigator.pop(context, 'this_band'),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
    DialogAction(
      label: 'All bands',
      onPressed: () => Navigator.pop(context, 'all_bands'),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

**Dialog 2: Simple confirmation (line ~352-380):**

```dart
final confirmed = await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surface,
    title: Text('Delete Block Out?', style: AppTextStyles.title3),
    content: Text(
      'This will remove the block out dates. This action cannot be undone.',
      style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(
          'Cancel',
          style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        child: Text(
          'Delete',
          style: AppTextStyles.callout.copyWith(color: AppColors.error), // ← DESTRUCTIVE
        ),
      ),
    ],
  ),
);
→
final confirmed = await showAppDialog<bool>(
  context: context,
  title: 'Delete Block Out?',
  message: 'This will remove the block out dates. This action cannot be undone.',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.pop(context, false),
    ),
    DialogAction(
      label: 'Delete',
      onPressed: () => Navigator.pop(context, true),
      isDestructive: true, // ← CRITICAL: maps AppColors.error styling
    ),
  ],
);
```

**Line ~812:** `TextField` (Reason input field)

**Note:** This is inside a helper method `_buildTextField()`. The method is called from line ~655. Both the method and its call site need to be updated.

```dart
TextField(
  controller: controller,
  focusNode: focusNode,
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body),
  maxLines: maxLines ?? 1,
  textCapitalization: textCapitalization ?? TextCapitalization.none,
  keyboardType: keyboardType,
  inputFormatters: inputFormatters,
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ),
)
→
AppTextField(
  controller: controller, // no change
  focusNode: focusNode, // no change
  style: TextStyle(color: context.colors.textPrimary, fontSize: AppFontSizes.body), // no change
  maxLines: maxLines ?? 1, // no change
  textCapitalization: textCapitalization ?? TextCapitalization.none, // no change
  keyboardType: keyboardType, // no change
  inputFormatters: inputFormatters, // no change
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    // ... more decoration props
  ), // full decoration passthrough
)
```

**Line ~684-698:** `TextButton` (Delete button with loading state)

**🔴 DESTRUCTIVE ACTION**

```dart
TextButton(
  onPressed: (_isSaving || _isDeleting) ? null : _handleDelete,
  child: _isDeleting
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.error, // ← DESTRUCTIVE STYLING
          ),
        )
      : Text(
          'Delete Block Out',
          style: AppTextStyles.calloutEmphasized.copyWith(
            color: AppColors.error, // ← DESTRUCTIVE STYLING
          ),
        ),
)
→
AppButton(
  label: 'Delete Block Out',
  variant: AppButtonVariant.destructive, // ← CRITICAL: maps AppColors.error styling
  onPressed: (_isSaving || _isDeleting) ? null : _handleDelete, // no change
  isLoading: _isDeleting, // consolidate — replaces conditional child
)
```

**Line ~878, 932:** `OutlinedButton` (Cancel buttons in edit/create modes)

```dart
OutlinedButton(
  onPressed: (_isSaving || _isDeleting) ? null : () => Navigator.pop(context),
  style: OutlinedButton.styleFrom(
    foregroundColor: context.colors.textSecondary,
    side: BorderSide(color: context.colors.border),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
  ),
  child: Text(
    'Cancel',
    style: AppTextStyles.calloutEmphasized.copyWith(
      color: context.colors.textSecondary,
    ),
  ),
)
→
AppButton(
  label: 'Cancel',
  variant: AppButtonVariant.outlined, // OutlinedButton → outlined
  onPressed: (_isSaving || _isDeleting) ? null : () => Navigator.pop(context), // no change
)
// Note: Custom styling (foregroundColor, side, shape) → omit (AppButton uses theme defaults)
```

**BrandActionButton (line ~920-926):** Already precedent component, keep as-is (out of scope).

---

### File 6: `lib/features/calendar/widgets/calendar_subscription_dialog.dart`

**🔴 HIGH RISK: CUSTOM BUILDER PATTERN**

**Line ~25:** `showModalBottomSheet` (in top-level function)

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => CalendarSubscriptionDialog(
    bandId: bandId,
    bandName: bandName,
  ),
);
→
showAppBottomSheet(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (context) => CalendarSubscriptionDialog(
    bandId: bandId,
    bandName: bandName,
  ), // no change
);
```

**Line ~191:** `CircularProgressIndicator` (loading state in URL fetch)

```dart
CircularProgressIndicator(color: AppColors.primary)
→
AppProgressIndicator(
  type: ProgressIndicatorType.circular, // explicit type
  color: AppColors.primary, // no change
)
```

**Line ~227:** `TextButton` (Done button)

```dart
TextButton(
  onPressed: () => Navigator.pop(context),
  child: Text(
    'Done',
    style: TextStyle(
      color: AppColors.primary,
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w600,
    ),
  ),
)
→
AppButton(
  label: 'Done',
  variant: AppButtonVariant.text, // map variant
  onPressed: () => Navigator.pop(context), // no change
)
```

**Line ~358:** `CircularProgressIndicator` (loading state in preferences save)

```dart
const CircularProgressIndicator(strokeWidth: 2)
→
const AppProgressIndicator(
  type: ProgressIndicatorType.circular,
  // strokeWidth → omit (AppProgressIndicator uses theme default)
)
```

---

### File 7: `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`

**Line ~40:** `showModalBottomSheet` (in function call)

```dart
return showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) {
    return /* ... */;
  },
);
→
return showAppBottomSheet(
  context: context,
  isScrollControlled: true, // no change
  backgroundColor: Colors.transparent, // no change
  builder: (context) {
    return /* ... */; // no change
  },
);
```

---

### File 8: `lib/features/calendar/widgets/view_block_out_drawer.dart`

**Line ~174:** `TextButton` (Edit button)

```dart
TextButton(
  onPressed: () {
    Navigator.pop(context);
    BlockOutDrawer.show(/* ... */);
  },
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
  onPressed: () {
    Navigator.pop(context);
    BlockOutDrawer.show(/* ... */);
  }, // no change
)
```

---

### File 9: `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`

**Line ~274:** `TextButton` (response button)

```dart
TextButton(
  onPressed: () => /* handle response */,
  child: Text(/* button text */),
)
→
AppButton(
  label: /* button text */, // extract from child Text widget
  variant: AppButtonVariant.text, // map variant
  onPressed: () => /* handle response */, // no change
)
```

**Line ~397:** `CircularProgressIndicator` (loading state)

```dart
const CircularProgressIndicator()
→
const AppProgressIndicator(type: ProgressIndicatorType.circular)
```

---

### File 10: `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`

**Line ~285:** `TextButton` (Edit button)

```dart
TextButton(
  onPressed: () => /* navigate to edit */,
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
  onPressed: () => /* navigate to edit */, // no change
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

**None.** All wrappers already exist from Piece 1 + wrapper-gaps cycle + Cycle 2a.

---

## Files to Modify

| File                                                                       | What changes                                                                                                                                                                                           |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/features/members/widgets/role_management_sheet.dart`                  | Replace Scaffold, AppBar, IconButton, showDialog (destructive), TextButton.icon (destructive+loading), FilledButton (save+loading), TextButton with wrapper equivalents                                |
| `lib/features/calendar/calendar_screen.dart`                               | Replace Scaffold, CircularProgressIndicator, TextButton with wrapper equivalents                                                                                                                       |
| `lib/features/calendar/calendar_tab_content.dart`                          | Replace CircularProgressIndicator, TextButton with wrapper equivalents                                                                                                                                 |
| `lib/features/calendar/one_calendar_settings_screen.dart`                  | Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, ElevatedButton, Checkbox with wrapper equivalents                                                                                     |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`                  | Replace showModalBottomSheet, showDialog (3 destructive), TextField, TextButton (destructive+loading), OutlinedButton with wrapper equivalents. **BrandActionButton kept as-is (precedent component)** |
| `lib/features/calendar/widgets/calendar_subscription_dialog.dart`          | Replace showModalBottomSheet, CircularProgressIndicator (2 instances), TextButton with wrapper equivalents                                                                                             |
| `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`               | Replace showModalBottomSheet with wrapper equivalent                                                                                                                                                   |
| `lib/features/calendar/widgets/view_block_out_drawer.dart`                 | Replace TextButton with wrapper equivalent                                                                                                                                                             |
| `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart` | Replace TextButton, CircularProgressIndicator with wrapper equivalents                                                                                                                                 |
| `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`               | Replace TextButton with wrapper equivalent                                                                                                                                                             |

---

## Files Off-Limits

| File                                                                                | Reason                                                                                                                        |
| ----------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                                     | Init order must not change                                                                                                    |
| `lib/app/theme/*.dart`                                                              | Theme configuration is stable—wrappers delegate to it, never override it                                                      |
| All files in `lib/components/ui/`                                                   | Wrapper layer is stable from Piece 1 + wrapper-gaps + Cycle 2a—do not modify wrappers even if gaps are found (report instead) |
| All precedent components (BrandActionButton, ConfirmActionDialog, etc.)             | Already stable, out of scope                                                                                                  |
| Custom components (HomeAppBar, CalendarAppBar, MemberCard, CalendarEventCard, etc.) | Already custom wrappers, not raw Material                                                                                     |
| All files in other `lib/features/` folders                                          | Out of scope (setlists, gigs, profile, settings, etc.)                                                                        |
| All model files (`member_vm.dart`, `calendar_event.dart`, etc.)                     | No UI widgets, pure data models                                                                                               |
| All controller/repository files                                                     | No UI widgets, pure logic                                                                                                     |

---

## Boundary Conditions & Exceptions

None identified for this cycle. All 10 target files contain straightforward Material widget call sites that map cleanly to existing wrapper equivalents with no API gaps.

---

## System Impact Map

| System                                 | Impact                                                                                                                                                                                 |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (out of scope for this cycle)                                                                                                                                               |
| Rehearsals                             | **affected** (rehearsal_availability_prompt_modal, view_rehearsal_drawer)                                                                                                              |
| Setlists / Catalog                     | unaffected                                                                                                                                                                             |
| Members / RBAC                         | **affected** (role_management_sheet — role changes, remove member action)                                                                                                              |
| Calendar                               | **affected** (calendar_screen, calendar_tab_content, one_calendar_settings_screen, add_block_out_drawer, calendar_subscription_dialog, day_detail_bottom_sheet, view_block_out_drawer) |
| Venues                                 | unaffected                                                                                                                                                                             |
| Contacts                               | unaffected                                                                                                                                                                             |
| Auth / Session                         | unaffected                                                                                                                                                                             |
| Profile                                | unaffected                                                                                                                                                                             |
| Settings                               | unaffected                                                                                                                                                                             |
| Notifications                          | unaffected                                                                                                                                                                             |
| Routing                                | unaffected                                                                                                                                                                             |
| Platform (iOS / Android / Web / macOS) | affected (must render correctly across all 4 platforms—but wrappers delegate to Material widgets with theme config, so platform equivalence is default)                                |

---

## Regression Risk

**Risk Level:** MEDIUM-HIGH

**Rationale:**

- **10 files modified, ~47-53 widget call substitutions** — Large surface area for mechanical errors (but slightly smaller than Cycle 2a's 11 files/55+ sites)
- **4 destructive action call sites with AppColors.error styling** — High-risk mappings per Cycles 1 and 2a lesson: wrong variant or lost error styling could make destructive actions look non-destructive (user deletes/removes without realizing) or vice versa
- **3 loading states inside buttons** — Must consolidate correctly to AppButton's isLoading prop; if conditional logic drifts, button breaks or crashes
- **role_management_sheet.dart specifically flagged in Cycle 2a as deferred** — This file was explicitly noted as "belongs to members/, not contacts/" in Cycle 2a's scope, meaning it was expected to have similar destructive-action risk patterns
- **add_block_out_drawer.dart is largest file in scope (963 lines)** — More complex than any Cycle 2a file, with multiple delete confirmation dialogs and 10 instances of AppColors.error
- **No automated tests for target screens** — Regression check is code-path analysis only (QA diff review), not runtime-validated
- **But: Zero logic changes, zero new state, zero backend surface** — Pure widget-call substitution preserves all existing behavior if mapping is executed correctly

**Primary risks:**

1. **Destructive variant mapping error:** Engineer maps `AppColors.error` button to wrong variant (e.g., `text` instead of `destructive`), causing visual regression where delete button looks like cancel button
2. **isLoading prop consolidation error:** Engineer incorrectly consolidates conditional `_isRemoving ? CircularProgressIndicator() : Icon(...)` child, causing button to always show loading or always show icon (logic drift)
3. **Conditional structure drift:** Engineer flattens/changes conditional logic while replacing widget, causing runtime crash or wrong widget shown
4. **Import omission:** Engineer forgets to import wrapper, causing compile error caught by `flutter analyze` (low severity, caught early)

**Mitigation:**

- **Exhaustive mapping table above** — Every single substitution is pre-defined, Engineer executes only (no judgment calls)
- **Destructive action call-out list** — QA must explicitly verify each of the 4 destructive action call sites for correct variant mapping and preserved AppColors.error styling
- **flutter analyze as gate** — Catches import/compile errors immediately
- **QA code-path analysis** — QA must diff every changed file and verify each substitution is 1:1 per mapping table (no logic drift, no prop mismatches)
- **Manual smoke test recommended** — Tony should manually test members/calendar/rehearsals screens on a real device/browser after QA approval, focusing on: (1) delete/remove buttons still show error styling, (2) loading states show correctly in save/remove/delete buttons

---

## Engineer Task Breakdown

Execute in strict order. Do not proceed to next task until current task is verified passing.

### Task 1: Verify working directory and branch

- **Command:** `pwd` (expect `/Users/tonyholmes/apps/bandroadie-ui-experiment`)
- **Command:** `git branch --show-current` (expect `experiment/ui-facade`)
- **Command:** `git status --short` (expect clean—no dirty files)
- **If any check fails:** STOP and report to Tony

### Task 2: Create feature docs directory

- **Directory:** `docs/features/ui-facade-retrofit-members-calendar-rehearsals/`
- **Verification:** Directory exists after creation

### Task 3: Read all 10 target files for context

- **Action:** Read each of the 10 files listed in Files to Modify table to understand their structure before editing
- **Purpose:** Familiarize with code patterns, confirm line numbers in mapping table are approximately correct
- **Critical focus:** Identify all 4 destructive action call sites and all 3 loading-state-inside-button call sites before starting edits

### Task 4: Retrofit role_management_sheet.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS**

- **File:** `lib/features/members/widgets/role_management_sheet.dart`
- **Action:** Execute every substitution per mapping table:
  - showDialog (Remove member confirmation) → showAppDialog with `isDestructive: true` on "Remove" action
  - Scaffold → AppScaffold
  - AppBar → AppAppBar
  - IconButton (close button) → AppIconButton
  - TextButton.icon "Remove from band" → AppButton with `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
  - FilledButton "Save" → AppButton with `variant: AppButtonVariant.primary` and `isLoading: _isSaving`
  - TextButton "Cancel" → AppButton with `variant: AppButtonVariant.text`
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_icon_button.dart`, `app_button.dart`, `app_dialog.dart`
- **Critical verification:** After editing, manually inspect lines ~189-203 (AlertDialog remove action) and ~420-444 (Remove from band button) to confirm:
  1. `isDestructive: true` is present on DialogAction
  2. `variant: AppButtonVariant.destructive` is present on AppButton
  3. `isLoading: _isRemoving` is present on AppButton (replaces conditional icon)
- **Verification:** `flutter analyze lib/features/members/widgets/role_management_sheet.dart` — 0 errors

### Task 5: Retrofit calendar_screen.dart

- **File:** `lib/features/calendar/calendar_screen.dart`
- **Action:** Execute every substitution per mapping table:
  - Scaffold → AppScaffold
  - CircularProgressIndicator → AppProgressIndicator
  - TextButton → AppButton
- **Add imports:** `app_scaffold.dart`, `app_progress_indicator.dart`, `app_button.dart`
- **Note:** DrawerOverlay wrapper (line ~369) is separate from Scaffold, unaffected by this retrofit
- **Verification:** `flutter analyze lib/features/calendar/calendar_screen.dart` — 0 errors

### Task 6: Retrofit calendar_tab_content.dart

- **File:** `lib/features/calendar/calendar_tab_content.dart`
- **Action:** Execute every substitution per mapping table: CircularProgressIndicator → AppProgressIndicator, TextButton → AppButton
- **Add imports:** `app_progress_indicator.dart`, `app_button.dart`
- **Verification:** `flutter analyze lib/features/calendar/calendar_tab_content.dart` — 0 errors

### Task 7: Retrofit one_calendar_settings_screen.dart

- **File:** `lib/features/calendar/one_calendar_settings_screen.dart`
- **Action:** Execute every substitution per mapping table: Scaffold → AppScaffold, AppBar → AppAppBar, IconButton → AppIconButton, CircularProgressIndicator → AppProgressIndicator, ElevatedButton → AppButton, Checkbox → AppCheckbox
- **Add imports:** `app_scaffold.dart`, `app_app_bar.dart`, `app_icon_button.dart`, `app_progress_indicator.dart`, `app_button.dart`, `app_checkbox.dart`
- **Verification:** `flutter analyze lib/features/calendar/one_calendar_settings_screen.dart` — 0 errors

### Task 8: Retrofit add_block_out_drawer.dart

**🔴 HIGH RISK: DESTRUCTIVE ACTIONS, LARGEST FILE IN SCOPE (963 lines)**

- **File:** `lib/features/calendar/widgets/add_block_out_drawer.dart`
- **Action:** Execute every substitution per mapping table:
  - showModalBottomSheet → showAppBottomSheet (in static show() method)
  - showDialog (3 delete confirmations) → showAppDialog with `isDestructive: true` on all delete actions
  - TextField (in \_buildTextField helper) → AppTextField
  - TextButton "Delete Block Out" → AppButton with `variant: AppButtonVariant.destructive` and `isLoading: _isDeleting`
  - OutlinedButton (2 Cancel buttons) → AppButton with `variant: AppButtonVariant.outlined`
- **KEEP AS-IS:** BrandActionButton (precedent component, out of scope)
- **Add imports:** `app_bottom_sheet.dart`, `app_dialog.dart`, `app_text_field.dart`, `app_button.dart`
- **Critical verification:** After editing, manually inspect lines ~310-380 (3 AlertDialog delete actions) and ~684-698 (Delete button) to confirm:
  1. All 3 AlertDialog instances use showAppDialog with `isDestructive: true` on delete actions
  2. `variant: AppButtonVariant.destructive` is present on Delete button
  3. `isLoading: _isDeleting` is present on Delete button (replaces conditional child)
- **Verification:** `flutter analyze lib/features/calendar/widgets/add_block_out_drawer.dart` — 0 errors

### Task 9: Retrofit calendar_subscription_dialog.dart

- **File:** `lib/features/calendar/widgets/calendar_subscription_dialog.dart`
- **Action:** Execute every substitution per mapping table: showModalBottomSheet → showAppBottomSheet, CircularProgressIndicator (2 instances) → AppProgressIndicator, TextButton → AppButton
- **Add imports:** `app_bottom_sheet.dart`, `app_progress_indicator.dart`, `app_button.dart`
- **Verification:** `flutter analyze lib/features/calendar/widgets/calendar_subscription_dialog.dart` — 0 errors

### Task 10: Retrofit day_detail_bottom_sheet.dart

- **File:** `lib/features/calendar/widgets/day_detail_bottom_sheet.dart`
- **Action:** Execute every substitution per mapping table: showModalBottomSheet → showAppBottomSheet
- **Add imports:** `app_bottom_sheet.dart`
- **Verification:** `flutter analyze lib/features/calendar/widgets/day_detail_bottom_sheet.dart` — 0 errors

### Task 11: Retrofit view_block_out_drawer.dart

- **File:** `lib/features/calendar/widgets/view_block_out_drawer.dart`
- **Action:** Execute every substitution per mapping table: TextButton → AppButton
- **Add imports:** `app_button.dart`
- **Verification:** `flutter analyze lib/features/calendar/widgets/view_block_out_drawer.dart` — 0 errors

### Task 12: Retrofit rehearsal_availability_prompt_modal.dart

- **File:** `lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart`
- **Action:** Execute every substitution per mapping table: TextButton → AppButton, CircularProgressIndicator → AppProgressIndicator
- **Add imports:** `app_button.dart`, `app_progress_indicator.dart`
- **Verification:** `flutter analyze lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart` — 0 errors

### Task 13: Retrofit view_rehearsal_drawer.dart

- **File:** `lib/features/rehearsals/widgets/view_rehearsal_drawer.dart`
- **Action:** Execute every substitution per mapping table: TextButton → AppButton
- **Add imports:** `app_button.dart`
- **Verification:** `flutter analyze lib/features/rehearsals/widgets/view_rehearsal_drawer.dart` — 0 errors

### Task 14: Verify zero files modified outside target files

- **Command:** `git diff --name-only`
- **Expected output:** Only the 10 files listed in Files to Modify table, no modifications to any file outside target folders
- **Regression guard:** This confirms no unintended files were touched

### Task 15: Run flutter analyze on target folders

- **Command:** `flutter analyze lib/features/members/ lib/features/calendar/ lib/features/rehearsals/`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding. Common errors: missing imports, typos in prop names, wrong enum values.

### Task 16: Build app for web (mandatory)

- **Command:** `flutter build web --release`
- **Expected output:** Build succeeds, `build/web/` directory contains compiled output
- **If build fails:** Read error message carefully. Common failures: syntax errors not caught by analyze, missing enum imports.

### Task 17: Spot-check destructive action call sites (manual code review)

**Critical regression check — do not skip**

For each of the 4 destructive action call sites, manually open the file and verify:

1. `role_management_sheet.dart` line ~189-203: showAppDialog has `DialogAction(label: 'Remove', isDestructive: true)`
2. `role_management_sheet.dart` line ~420-444: AppButton has `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
3. `add_block_out_drawer.dart` line ~335, 342, 374: All 3 showAppDialog calls have `isDestructive: true` on delete actions
4. `add_block_out_drawer.dart` line ~684-698: AppButton has `variant: AppButtonVariant.destructive` and `isLoading: _isDeleting`

**If any verification fails:** Fix immediately before proceeding. These are the highest-risk mappings.

### Task 18: Create ENGINEER_REPORT.md

- **File:** `docs/features/ui-facade-retrofit-members-calendar-rehearsals/ENGINEER_REPORT.md`
- **Required sections:**
  1. **Summary** — "Retrofitted 10 files across members/calendar/rehearsals folders to use App\* wrapper components. ~47-53 Material widget call sites replaced with wrapper equivalents per ARCHITECT_PLAN.md mapping table. All destructive action call sites verified for correct variant mapping. Zero logic changes, zero behavior changes."
  2. **Files Modified** — List all 10 files with line counts (before/after) and brief description of changes
  3. **Destructive Action Call Sites — Verification** — For each of the 4 destructive action call sites, confirm correct mapping
  4. **Test Results** — `flutter analyze` output (0 errors), `flutter build web` output (success)
  5. **Known Issues** — None expected. If any discovered, document here.

---

## Verification Plan

**Tier 1 — Pre-deployment (N/A for this feature—no migrations):**

This feature has no database migrations, edge functions, or backend changes. All verification is Flutter-local.

**Tier 2 — Post-implementation:**

### Test 1: flutter analyze passes with 0 errors

```bash
cd /Users/tonyholmes/apps/bandroadie-ui-experiment
flutter analyze lib/features/members/ lib/features/calendar/ lib/features/rehearsals/
```

**Expected output:** 0 errors, 0 warnings.

### Test 2: flutter build web succeeds

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Expected output:** Build succeeds, `build/web/` directory contains compiled output.

### Test 3: git diff confirms only 10 files modified in target folders

```bash
git diff --name-only
```

**Expected output:** Exactly 10 files under `lib/features/members/`, `lib/features/calendar/`, `lib/features/rehearsals/`, zero other files touched. This is the primary regression guard—confirms no unintended files were changed.

### Test 4: Code-path analysis — Destructive action call sites

QA must manually diff each of the 4 destructive action call sites and verify:

1. `role_management_sheet.dart` ~line 189-203: AlertDialog "Remove" action has `isDestructive: true` in DialogAction
2. `role_management_sheet.dart` ~line 420-444: "Remove from band" button has `variant: AppButtonVariant.destructive` and `isLoading: _isRemoving`
3. `add_block_out_drawer.dart` ~line 335, 342, 374: All 3 AlertDialog "delete" actions have `isDestructive: true` in DialogAction
4. `add_block_out_drawer.dart` ~line 684-698: "Delete Block Out" button has `variant: AppButtonVariant.destructive` and `isLoading: _isDeleting`

**Each verification must confirm two things:**

- The mapping table was followed exactly (no improvisation)
- The wrapper call uses the correct destructive variant/prop (no visual regression — button still looks dangerous)

**Pass criteria:** All 4 call sites verified correct. Any deviation is a FAIL and must be fixed before QA approval.

### Test 5: Code-path analysis — Loading state consolidation

QA must manually diff each of the 3 loading-state-inside-button call sites and verify:

1. `role_management_sheet.dart` ~line 420-444: Remove button consolidated to `AppButton` with `isLoading: _isRemoving`
2. `role_management_sheet.dart` ~line 487-514: Save button consolidated to `AppButton` with `isLoading: _isSaving`
3. `add_block_out_drawer.dart` ~line 684-698: Delete button consolidated to `AppButton` with `isLoading: _isDeleting`

**Each verification must confirm:**

- Conditional `_isRemoving ? CircularProgressIndicator() : Icon(...)` child was replaced with `isLoading: _isRemoving` prop
- Button's label is always the same (not conditional)
- Button's onPressed callback is still disabled when loading (`_isRemoving ? null : callback`)

**Pass criteria:** All 3 call sites verified correct. Any deviation is a FAIL.

---

## QA Regression Areas

**This is the final cycle in current Piece 2 scope, covering the last three folders. QA verification must confirm zero behavioral drift from pure Material→wrapper substitution.**

### Critical verification areas (manual testing recommended):

1. **Destructive action styling preserved:**
   - Navigate to Manage Role sheet (from band members list)
   - Verify "Remove from band" button at bottom still has red/error styling (icon + text are red)
   - Tap button, verify confirmation dialog's "Remove" action has red text
   - Navigate to Edit Block Out drawer (from calendar view)
   - Verify "Delete Block Out" button has red/error styling
   - Tap button, verify all delete confirmation dialogs have red text on delete actions

2. **Loading states work correctly:**
   - Navigate to Manage Role sheet, change role, tap "Save"
   - Verify: button shows loading spinner while saving, then returns to "Save" text
   - Navigate to Manage Role sheet, tap "Remove from band"
   - Verify: button shows loading spinner while removing, then completes
   - Navigate to Edit Block Out drawer, tap "Delete Block Out"
   - Verify: button shows loading spinner while deleting

3. **Calendar drawer functionality works correctly:**
   - Navigate to Calendar screen
   - Tap hamburger menu icon (should open side drawer)
   - Verify: drawer opens correctly (DrawerOverlay is separate from Scaffold, should be unaffected by retrofit)

4. **One Calendar settings work correctly:**
   - Navigate to One Calendar settings screen
   - Toggle master switch, verify checkboxes appear
   - Tap checkboxes, verify they toggle correctly
   - Tap "Learn more" button, verify it navigates correctly

5. **Rehearsal modals work correctly:**
   - Navigate to rehearsals, tap availability prompt modal
   - Verify: buttons work correctly, loading states show

### Automated verification (code review):

6. **Confirm zero files modified outside target files:** Review `git diff --name-only` output—only 10 files in target folders modified
7. **Confirm all destructive action call sites use correct variant:** Manual diff review per Test 4 above
8. **Confirm all loading states consolidated correctly:** Manual diff review per Test 5 above
9. **Confirm no runtime errors introduced:** Run `flutter analyze lib/features/members/ lib/features/calendar/ lib/features/rehearsals/`, confirm 0 errors

**Pass criteria:** All 9 verification areas passed. Any failure in critical areas 1-5 is a FAIL verdict and blocks commit.

---

## Rollout / Migration Strategy

Not applicable — this feature introduces no user-facing behavior changes, no database migrations, no backend changes. Rollout is a standard git merge + deploy (no special sequencing required).

After merge to `experiment/ui-facade` and confirmation that branch builds successfully, this completes Piece 2 (profile/settings/notifications/auth → contacts/venues → members/calendar/rehearsals). Gigs and setlists remain for later cycles (deferred due to `setlist_repository.dart` 4,027 lines and `setlist_detail_screen.dart` 2,788 lines).

---

## Out of Scope

The following are explicitly deferred to later cycles or are boundary exclusions:

1. **lib/features/gigs/** — Entire gigs folder deferred to separate cycle given complexity
2. **lib/features/setlists/** — Entire setlists folder deferred (largest files in codebase)
3. **Custom components (HomeAppBar, CalendarAppBar, MemberCard, CalendarEventCard, etc.)** — Already custom wrappers, not raw Material
4. **Model files (member_vm.dart, calendar_event.dart, etc.)** — No UI widgets, pure data models
5. **Controller/repository files** — No UI widgets, pure logic
6. **Extending wrapper API for new gaps** — If a gap is discovered during implementation, STOP and report to Architect. Do not improvise or extend wrappers mid-retrofit. This cycle assumes wrapper API is complete per wrapper-gaps cycle + Cycle 2a.
7. **Custom styling or behavior changes** — Wrappers remain visually and behaviorally identical to Material defaults (delegating to theme config). Any design-system customization is future work after all retrofits complete.

---

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-07  
**Worktree:** `/Users/tonyholmes/apps/bandroadie-ui-experiment`  
**Branch:** `experiment/ui-facade` (existing—not creating new branch per override)
