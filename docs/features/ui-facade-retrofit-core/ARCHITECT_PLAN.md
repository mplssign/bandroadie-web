# ARCHITECT_PLAN.md

**Feature Slug:** `ui-facade-retrofit-core`

---

## Problem Summary

Piece 1 (commit 6a76eae) and its follow-up wrapper-gaps cycle created 15 App\* wrapper widgets in `lib/components/ui/` with complete prop surfaces—fully merged to `experiment/ui-facade`. Zero production call sites reference them yet. This cycle retrofits the smallest, lowest-risk folders first (profile, settings, notifications, auth — 12 files after confirming `notification_navigation_handler.dart` is a navigation-only file with no UI widget instantiation) by replacing raw Material widget calls with wrapper equivalents. Purely mechanical substitution: same props, same values, same behavior. The app must look and behave identically afterward, proving the wrapper layer is a safe drop-in before touching riskier folders (setlists, gigs, calendar, rehearsals) in later cycles.

**Why this is critical:** This is the first retrofit cycle touching live call sites. Unlike Piece 1 and wrapper-gaps (purely additive, zero production impact), a mistake here is user-visible. Each raw Material→wrapper substitution must be validated as prop-for-prop equivalent with no logic drift. The mapping table below defines every single substitution the Engineer must make—no judgment calls, only execution.

---

## Current State

**Wrapper layer status (as of wrapper-gaps cycle):**

- 15 wrapper widgets exist in `lib/components/ui/` with complete prop surfaces
- AppTextField/AppTextFormField support full `decoration` prop + simplified props (focusNode, textCapitalization, textInputAction, style)
- showAppBottomSheet supports backgroundColor, shape, isScrollControlled
- showAppDialog supports custom builder pattern for non-AlertDialog cases
- All wrappers tested (95 passing tests), `flutter analyze` clean, web build succeeds
- Zero production call sites use any wrapper yet (Piece 2 hasn't started)

**Target files (12 confirmed after grep + inspection):**

1. `lib/features/profile/profile_screen.dart` — Profile view/edit screen
2. `lib/features/profile/my_profile_screen.dart` — Full profile editor with roles
3. `lib/features/settings/settings_screen.dart` — App settings + account deletion
4. `lib/features/notifications/widgets/notification_settings_modal.dart` — Deep link modal for system settings
5. `lib/features/notifications/widgets/notification_permission_prompt.dart` — In-app permission prompt banner
6. `lib/features/notifications/widgets/notification_card.dart` — Individual notification item card
7. `lib/features/notifications/notification_settings_screen.dart` — Master notification toggle + category checkboxes
8. `lib/features/notifications/notification_preferences_screen.dart` — Alternative notification preferences UI
9. `lib/features/auth/login_screen.dart` — Magic link login screen
10. `lib/features/auth/invite_screen.dart` — Band invitation acceptance flow
11. `lib/features/auth/auth_gate.dart` — Auth routing + profile gate
12. `lib/features/auth/auth_confirm_screen.dart` — Magic link token verification

**Excluded file (false positive from grep):**

- `lib/features/notifications/notification_navigation_handler.dart` — Navigation/logic only, no UI widget instantiation

**Pattern observed in target files:**

- Scaffold/AppBar pair in most screens (direct props passthrough)
- Buttons: Mix of ElevatedButton, FilledButton, TextButton, OutlinedButton, IconButton (map to AppButton/AppIconButton variants)
- Text fields: TextField/TextFormField with inline InputDecoration construction (map to AppTextField/AppTextFormField with either simplified props or full `decoration` prop)
- Dialogs: showDialog + AlertDialog (map to showAppDialog with title/message/actions pattern)
- Progress indicators: CircularProgressIndicator for loading states (map to AppProgressIndicator with type=circular)
- Switches/Checkboxes: Switch, Switch.adaptive, Checkbox (map to AppSwitch/AppCheckbox)
- Card: Used in notification_card.dart (already minimal, but wrap with AppCard)

---

## Reference Docs Consulted

- `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — Landing page marketing guide, not relevant to component architecture

**No relevant design-system or retrofit guidance exists in reference docs.** Per ARCHITECT.md fallback protocol for missing/irrelevant reference directories, proceeded with codebase inspection and established precedent pattern from Piece 1.

---

## Proposed Solution

Replace every raw Material widget instantiation in the 12 target files with its wrapper equivalent, maintaining exact prop values and behavior. Each substitution is a 1:1 mapping documented in the Per-File Retrofit Mapping Table below. The Engineer must execute each mapping exactly as specified—no prop inference, no logic changes, no opportunistic refactors.

**Retrofit principles:**

1. **Prop-for-prop equivalence:** If Material widget has `backgroundColor: AppColors.primary`, wrapper call must have `backgroundColor: AppColors.primary` (or the wrapper's default if that's the intended behavior)
2. **No logic drift:** Controllers, focus nodes, validators, callbacks—all preserved exactly as written
3. **Import additions only:** Add `import 'package:bandroadie/components/ui/<wrapper>.dart';` at top of file, do not remove Material imports (some widgets like `Colors`, `Icons`, theme objects are still needed)
4. **Conditional preservation:** If Material widget call is inside a conditional (e.g., `_isLoading ? CircularProgressIndicator(...) : Text(...)`), wrapper call must preserve the same conditional structure
5. **Style/decoration consolidation:** Where Material widget uses inline `decoration:` prop with many properties, use wrapper's `decoration` passthrough prop for AppTextField/AppTextFormField, or individual props for simple cases

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

---

### File 1: `lib/features/profile/profile_screen.dart`

**Line ~102:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: profileAsync.when(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: profileAsync.when(...), // no change
)
```

**Line ~103:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.appBarBg,
  title: Text('My Profile', style: AppTextStyles.title3),
  leading: IconButton(...), // see below
  actions: [...], // contains IconButton and TextButton, see below
)
→
AppAppBar(
  backgroundColor: context.colors.appBarBg, // no change
  title: Text('My Profile', style: AppTextStyles.title3), // no change (title accepts Widget)
  leading: AppIconButton(...), // see below
  actions: [...], // replace children, see below
)
```

**Line ~104:** `IconButton` (leading, back button)

```dart
IconButton(
  icon: const Icon(AppIcons.arrowLeft, color: AppColors.primary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.arrowLeft, // icon data only
  color: AppColors.primary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~108:** `IconButton` (edit button in actions)

```dart
IconButton(
  icon: const Icon(AppIcons.edit, color: Colors.white),
  onPressed: () { /* ... */ },
)
→
AppIconButton(
  icon: AppIcons.edit, // icon data only
  color: Colors.white, // no change
  onPressed: () { /* ... */ }, // no change
)
```

**Line ~115-125:** `TextButton` (Save button in actions)

```dart
TextButton(
  onPressed: _isSaving ? null : _saveProfile,
  child: _isSaving
      ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator( // see below
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
      : const Text(
          'Save',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
)
→
AppButton(
  label: 'Save',
  variant: AppButtonVariant.text, // map variant
  onPressed: _isSaving ? null : _saveProfile, // no change
  isLoading: _isSaving, // use wrapper's loading state (replaces conditional child)
)
```

**Line ~119:** `CircularProgressIndicator` (inside TextButton)

```
// Removed — handled by AppButton's isLoading prop (see above)
```

**Line ~131:** `CircularProgressIndicator` (loading state in body)

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

**Line ~152:** `ElevatedButton` (Retry button in error state)

```dart
ElevatedButton(
  onPressed: () => ref.invalidate(userProfileProvider),
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
  ),
  child: const Text('Retry'),
)
→
AppButton(
  label: 'Retry',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () => ref.invalidate(userProfileProvider), // no change
)
// Note: backgroundColor from style → omit (AppButton's secondary variant uses theme's ElevatedButton style, which is configured with primary color in app_theme.dart)
```

**Line ~281-301:** `TextFormField` (First Name, Last Name, Phone, City fields)

```dart
TextFormField(
  controller: controller,
  keyboardType: keyboardType,
  style: const TextStyle(color: Colors.white),
  onChanged: (value) { setState(() {}); },
  validator: customValidator ?? (isRequired ? (value) { /* ... */ } : null),
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.surfaceOverlay),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.surfaceOverlay),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.primaryDim, width: 2),
    ),
  ),
)
→
AppTextFormField(
  controller: controller, // no change
  keyboardType: keyboardType, // no change
  style: const TextStyle(color: Colors.white), // no change
  onChanged: (value) { setState(() {}); }, // no change
  validator: customValidator ?? (isRequired ? (value) { /* ... */ } : null), // no change
  decoration: InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.colors.textMuted),
    filled: true,
    fillColor: context.colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.surfaceOverlay),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.surfaceOverlay),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.colors.primaryDim, width: 2),
    ),
  ), // full decoration passthrough (wrapper supports this after wrapper-gaps cycle)
)
```

**Line ~305:** `OutlinedButton` (Cancel button in edit form)

```dart
OutlinedButton(
  onPressed: () => setState(() => _isEditing = false),
  style: OutlinedButton.styleFrom(
    side: BorderSide(color: context.colors.border),
    padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
  ),
  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
)
→
AppButton(
  label: 'Cancel',
  variant: AppButtonVariant.outlined, // map variant
  onPressed: () => setState(() => _isEditing = false), // no change
)
// Note: style.side and padding → omit (AppButton's outlined variant uses theme's OutlinedButton style, which is configured in app_theme.dart; padding is handled by theme)
```

---

### File 2: `lib/features/profile/my_profile_screen.dart`

**Line ~679:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: _buildBody(),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: _buildBody(), // no change
)
```

**Line ~680:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.appBarBg,
  title: Text(
    widget.isGated ? 'Complete Your Profile' : 'My Profile',
    style: const TextStyle(...).copyWith(color: Colors.white),
  ),
  automaticallyImplyLeading: false,
  leading: widget.isGated ? null : IconButton(...), // see below
)
→
AppAppBar(
  backgroundColor: context.colors.appBarBg, // no change
  title: Text(
    widget.isGated ? 'Complete Your Profile' : 'My Profile',
    style: const TextStyle(...).copyWith(color: Colors.white),
  ), // no change (title accepts Widget)
  leading: widget.isGated ? null : AppIconButton(...), // see below
)
```

**Line ~692:** `IconButton` (back button)

```dart
IconButton(
  icon: const Icon(AppIcons.arrowLeft, color: AppColors.primary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.arrowLeft, // icon data only
  color: AppColors.primary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~701:** `CircularProgressIndicator` (loading state)

```dart
Center(
  child: CircularProgressIndicator(color: context.colors.primaryDim),
)
→
Center(
  child: AppProgressIndicator(
    type: ProgressIndicatorType.circular, // explicit type
    color: context.colors.primaryDim, // no change
  ),
)
```

**Line ~387-438:** `showDialog` + `AlertDialog` (Add custom role dialog)

```dart
await showDialog<String>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, setDialogState) {
      return AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add custom role', style: TextStyle(...)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a custom role...', style: TextStyle(...)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Rhythm Guitar',
                hintStyle: TextStyle(color: context.colors.textMuted),
                errorText: errorText,
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(...),
                enabledBorder: OutlineInputBorder(...),
                focusedBorder: OutlineInputBorder(...),
              ),
              onSubmitted: (value) { /* ... */ },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
          ),
          TextButton(
            onPressed: () { /* ... */ },
            child: Text('Add', style: TextStyle(color: context.colors.primaryDim, fontWeight: FontWeight.w600)),
          ),
        ],
      );
    },
  ),
);
→
await showAppDialog<String>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, setDialogState) {
      return AppAlertDialog( // use widget directly when custom builder logic is needed
        title: 'Add custom role',
        message: 'Enter a custom role to add to your roles list.', // consolidate subtitle into message
        actions: [
          DialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          DialogAction(
            label: 'Add',
            onPressed: () { /* ... */ },
          ),
        ],
      );
      // NOTE: This dialog has a TextField in content, which AppAlertDialog doesn't support.
      // Must use custom builder pattern from wrapper-gaps cycle.
      // Correction: Use showAppDialog's builder prop:
    },
  ),
);
// CORRECTION: This dialog needs custom content (TextField), so use builder:
await showAppDialog<String>(
  context: context,
  builder: (context) => StatefulBuilder(
    builder: (context, setDialogState) {
      return AlertDialog( // Keep AlertDialog here, wrap only the showDialog call
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add custom role', style: TextStyle(...)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter a custom role...', style: TextStyle(...)),
            const SizedBox(height: 16),
            AppTextField( // Replace TextField here
              controller: controller,
              style: TextStyle(color: context.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. Rhythm Guitar',
                hintStyle: TextStyle(color: context.colors.textMuted),
                errorText: errorText,
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(...),
                enabledBorder: OutlineInputBorder(...),
                focusedBorder: OutlineInputBorder(...),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (value) { /* validation */ },
            ),
          ],
        ),
        actions: [
          AppButton( // Replace TextButton
            label: 'Cancel',
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton( // Replace TextButton
            label: 'Add',
            variant: AppButtonVariant.text,
            onPressed: () { /* ... */ },
          ),
        ],
      );
    },
  ),
);
```

**Line ~479-515:** `showDialog` + `AlertDialog` (Delete role confirmation)

```dart
await showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surface,
    title: Text('Delete Role', style: TextStyle(color: context.colors.textPrimary)),
    content: Text(
      'Remove "$roleLabel" from your roles?',
      style: TextStyle(color: context.colors.textSecondary),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text('Cancel', style: TextStyle(color: context.colors.textSecondary)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text('Delete', style: TextStyle(color: context.colors.primaryDim)),
      ),
    ],
  ),
);
→
await showAppDialog<bool>(
  context: context,
  title: 'Delete Role',
  message: 'Remove "$roleLabel" from your roles?',
  actions: [
    DialogAction(
      label: 'Cancel',
      onPressed: () => Navigator.of(context).pop(false),
    ),
    DialogAction(
      label: 'Delete',
      onPressed: () => Navigator.of(context).pop(true),
    ),
  ],
);
```

**Line ~843-894:** `TextButton` (Cancel/Skip button in footer)

```dart
TextButton(
  onPressed: _cancel, // or widget.onSkip
  style: TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(vertical: 14),
  ),
  child: Text(
    'Cancel', // or 'Skip for now'
    style: TextStyle(
      fontSize: AppFontSizes.body,
      fontWeight: FontWeight.w500,
      color: context.colors.textSecondary,
    ),
  ),
)
→
AppButton(
  label: 'Cancel', // or 'Skip for now'
  variant: AppButtonVariant.text, // map variant
  onPressed: _cancel, // or widget.onSkip, no change
)
```

**Line ~860-952:** `TextField` fields in form (First Name, Last Name, Phone, etc.)

```
// Same as profile_screen.dart TextFormField mapping (use AppTextFormField with full decoration prop)
```

---

### File 3: `lib/features/settings/settings_screen.dart`

**Line ~105:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: _isDeleting ? Center(...) : Column(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: _isDeleting ? Center(...) : Column(...), // no change
)
```

**Line ~106:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.appBarBg,
  title: Text('Settings', style: TextStyle(...)),
  leading: IconButton(...), // see below
)
→
AppAppBar(
  backgroundColor: context.colors.appBarBg, // no change
  title: Text('Settings', style: TextStyle(...)), // no change
  leading: AppIconButton(...), // see below
)
```

**Line ~113:** `IconButton` (back button)

```dart
IconButton(
  icon: const Icon(AppIcons.arrowLeft, color: AppColors.primary),
  onPressed: () => Navigator.of(context).pop(),
)
→
AppIconButton(
  icon: AppIcons.arrowLeft, // icon data only
  color: AppColors.primary, // no change
  onPressed: () => Navigator.of(context).pop(), // no change
)
```

**Line ~121:** `CircularProgressIndicator` (deleting state)

```dart
CircularProgressIndicator(color: AppColors.error)
→
AppProgressIndicator(
  type: ProgressIndicatorType.circular, // explicit type
  color: AppColors.error, // no change
)
```

**Line ~160-260:** `showDialog` + `AlertDialog` (Delete account confirmation)

```dart
await showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog(
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Row(
      children: [
        Icon(AppIcons.warning, color: AppColors.error, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text('Delete Account?', style: TextStyle(...))),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This action is permanent...', style: TextStyle(...)),
        // ... more content
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text('Cancel', style: TextStyle(...)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: TextButton.styleFrom(
          backgroundColor: AppColors.error,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Delete Account', style: TextStyle(color: Colors.white, ...)),
      ),
    ],
  ),
);
→
await showAppDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => AlertDialog( // Custom builder for complex layout with icon in title
    backgroundColor: context.colors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Row(
      children: [
        Icon(AppIcons.warning, color: AppColors.error, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Text('Delete Account?', style: TextStyle(...))),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('This action is permanent...', style: TextStyle(...)),
        // ... more content
      ],
    ),
    actions: [
      AppButton(
        label: 'Cancel',
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      AppButton(
        label: 'Delete Account',
        variant: AppButtonVariant.text,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  ),
);
// Note: Custom title with icon + complex content → use builder pattern, but replace actions buttons
```

**Line ~330:** `Switch` (Light mode toggle)

```dart
Switch(
  value: isLight,
  onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
  activeTrackColor: AppColors.primary,
  inactiveTrackColor: context.colors.surfaceOverlay,
  inactiveThumbColor: context.colors.textSecondary,
)
→
AppSwitch(
  value: isLight, // no change
  onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(), // no change
  activeColor: AppColors.primary, // activeTrackColor → activeColor (wrapper uses thumbColor API)
)
// Note: inactiveTrackColor/inactiveThumbColor → omit (AppSwitch uses theme defaults for inactive state)
```

---

### File 4: `lib/features/notifications/widgets/notification_settings_modal.dart`

**Line ~27-39:** `showDialog` (modal display)

```dart
await showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (context) => const NotificationSettingsModal(),
);
→
await showAppDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (context) => const NotificationSettingsModal(),
);
```

**Line ~46:** `Dialog` (root widget)

```dart
Dialog(
  backgroundColor: context.colors.surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Spacing.cardRadius),
  ),
  child: Padding(...),
)
→
// Note: Dialog widget itself doesn't have an App* wrapper (it's the container returned by showDialog's builder).
// Only the showDialog call is wrapped (see above). Keep Dialog as-is since it's the custom-shaped container.
// If we need to standardize Dialog appearance, that would be a showAppDialog enhancement, not a per-call retrofit.
```

**Line ~95:** `ElevatedButton` (Open Settings button)

```dart
ElevatedButton(
  onPressed: () async {
    Navigator.of(context).pop();
    await _openAppSettings();
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: Spacing.space16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
    elevation: 0,
  ),
  child: Text('Open Settings', style: AppTextStyles.calloutEmphasized.copyWith(color: Colors.white)),
)
→
AppButton(
  label: 'Open Settings',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () async {
    Navigator.of(context).pop();
    await _openAppSettings();
  },
  fullWidth: true, // SizedBox(width: double.infinity) wrapper → fullWidth prop
)
```

**Line ~114:** `TextButton` (Cancel button)

```dart
TextButton(
  onPressed: () { Navigator.of(context).pop(); },
  style: TextButton.styleFrom(
    foregroundColor: context.colors.textSecondary,
    padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
  ),
  child: Text('Cancel', style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary)),
)
→
AppButton(
  label: 'Cancel',
  variant: AppButtonVariant.text, // map variant
  onPressed: () { Navigator.of(context).pop(); }, // no change
  fullWidth: true, // SizedBox(width: double.infinity) wrapper → fullWidth prop
)
```

---

### File 5: `lib/features/notifications/widgets/notification_permission_prompt.dart`

**Line ~66:** `IconButton` (close/dismiss button)

```dart
IconButton(
  icon: const Icon(AppIcons.close, size: 20),
  color: context.colors.textSecondary,
  onPressed: () {
    ref.read(permissionPromptDismissedProvider.notifier).dismiss();
  },
)
→
AppIconButton(
  icon: AppIcons.close, // icon data only
  size: 20, // no change
  color: context.colors.textSecondary, // no change
  onPressed: () {
    ref.read(permissionPromptDismissedProvider.notifier).dismiss();
  }, // no change
)
```

**Line ~88:** `TextButton` (Not Now button)

```dart
TextButton(
  onPressed: () {
    ref.read(permissionPromptDismissedProvider.notifier).dismiss();
  },
  child: Text('Not Now', style: AppTextStyles.callout.copyWith(color: context.colors.textSecondary)),
)
→
AppButton(
  label: 'Not Now',
  variant: AppButtonVariant.text, // map variant
  onPressed: () {
    ref.read(permissionPromptDismissedProvider.notifier).dismiss();
  }, // no change
)
```

**Line ~94:** `ElevatedButton` (Enable Notifications button)

```dart
ElevatedButton(
  onPressed: () async { /* ... */ },
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: context.colors.textPrimary,
  ),
  child: Text('Enable Notifications', style: AppTextStyles.callout.copyWith(fontWeight: FontWeight.w600)),
)
→
AppButton(
  label: 'Enable Notifications',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () async { /* ... */ }, // no change
)
```

**Line ~188:** `ElevatedButton` (in EnableNotificationsButton widget)

```dart
ElevatedButton(
  onPressed: _enableNotifications,
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: context.colors.textPrimary,
    padding: const EdgeInsets.symmetric(horizontal: Spacing.space16, vertical: Spacing.space8),
  ),
  child: const Text('Enable'),
)
→
AppButton(
  label: 'Enable',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: _enableNotifications, // no change
)
```

---

### File 6: `lib/features/notifications/widgets/notification_card.dart`

**No changes needed.** This file only uses `Container` and layout widgets, no raw Material widget instantiation. Card wrapper already exists but this file doesn't use Card widget directly.

---

### File 7: `lib/features/notifications/notification_settings_screen.dart`

**Line ~32:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: prefsAsync.when(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: prefsAsync.when(...), // no change
)
```

**Line ~33:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  elevation: 0,
  leading: IconButton(...), // see below
  title: Text('Notifications', style: TextStyle(...)),
)
→
AppAppBar(
  backgroundColor: context.colors.background, // no change
  leading: AppIconButton(...), // see below
  title: Text('Notifications', style: TextStyle(...)), // no change
)
```

**Line ~37:** `IconButton` (back button)

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

**Line ~53:** `CircularProgressIndicator` (loading state)

```dart
const Center(child: CircularProgressIndicator())
→
const Center(child: AppProgressIndicator(type: ProgressIndicatorType.circular))
```

**Line ~239:** `Switch.adaptive` (Master toggle)

```dart
Switch.adaptive(
  value: enabled,
  onChanged: onChanged,
  activeTrackColor: AppColors.primary,
  inactiveTrackColor: context.colors.surfaceOverlay,
  inactiveThumbColor: context.colors.textSecondary,
)
→
AppSwitch(
  value: enabled, // no change
  onChanged: onChanged, // no change
  activeColor: AppColors.primary, // activeTrackColor → activeColor
)
```

**Line ~290:** `Checkbox` (Category checkboxes)

```dart
Checkbox(
  value: value,
  onChanged: onChanged,
  activeColor: AppColors.primary,
  side: BorderSide(
    color: isEnabled ? context.colors.border : context.colors.textMuted,
  ),
)
→
AppCheckbox(
  value: value, // no change
  onChanged: onChanged, // no change
  activeColor: AppColors.primary, // no change
)
// Note: side prop → omit (AppCheckbox uses theme's checkboxTheme for border styling)
```

---

### File 8: `lib/features/notifications/notification_preferences_screen.dart`

**Line ~47:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  appBar: AppBar(...),
  body: prefsAsync.when(...),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  appBar: AppAppBar(...), // see below
  body: prefsAsync.when(...), // no change
)
```

**Line ~48:** `AppBar`

```dart
AppBar(
  backgroundColor: context.colors.background,
  elevation: 0,
  title: Text('Notifications', style: AppTextStyles.title3.copyWith(...)),
  leading: IconButton(...), // see below
)
→
AppAppBar(
  backgroundColor: context.colors.background, // no change
  title: Text('Notifications', style: AppTextStyles.title3.copyWith(...)), // no change
  leading: AppIconButton(...), // see below
)
```

**Line ~52:** `IconButton` (back button)

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

**Line ~57:** `CircularProgressIndicator` (loading state)

```dart
const Center(child: CircularProgressIndicator(color: AppColors.primary))
→
const Center(child: AppProgressIndicator(
  type: ProgressIndicatorType.circular,
  color: AppColors.primary,
))
```

**Line ~192:** `ElevatedButton` (Enable Notifications button)

```dart
ElevatedButton(
  onPressed: _requestPermission,
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: Spacing.space12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
  ),
  child: const Text('Enable Notifications'),
)
→
AppButton(
  label: 'Enable Notifications',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: _requestPermission, // no change
  fullWidth: true, // SizedBox(width: double.infinity) wrapper → fullWidth prop
)
```

---

### File 9: `lib/features/auth/login_screen.dart`

**Line ~466:** `Scaffold` (early-return loading state when session detected)

```dart
if (_sessionDetected) {
  return Scaffold(
    backgroundColor: context.colors.background,
    body: Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    ),
  );
}
→
if (_sessionDetected) {
  return AppScaffold(
    backgroundColor: context.colors.background, // no change
    body: Center(
      child: AppProgressIndicator( // see separate entry for CircularProgressIndicator
        type: ProgressIndicatorType.circular,
        color: AppColors.primary,
      ),
    ),
  );
}
```

**Line ~467:** `CircularProgressIndicator` (inside \_sessionDetected Scaffold)

```
// Replaced as part of Scaffold retrofit above (see AppProgressIndicator)
```

**Line ~480:** `Scaffold` (main build method — has keyboard handling gap)

```dart
return Scaffold(
  backgroundColor: context.colors.background,
  resizeToAvoidBottomInset: false,
  body: SafeArea(...),
);
```

**No change** — Keep Scaffold as-is. `resizeToAvoidBottomInset: false` is not exposed by AppScaffold (gap). This file has unique keyboard animation needs. See Boundary Conditions section.

**Line ~492:** `TextField` (email input)

**No change** — Keep TextField as-is. AppTextField doesn't expose `autocorrect`, `autofillHints`, or `onSubmitted` props (critical for email input UX). See Boundary Conditions section.

**Line ~578:** `FilledButton` (Email Login Link button)

```dart
FilledButton(
  onPressed: isDisabled ? null : _sendMagicLink,
  style: FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
    padding: const EdgeInsets.symmetric(vertical: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  child: _isLoading
      ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        )
      : Text(buttonText, style: const TextStyle(...)),
)
→
AppButton(
  label: _cooldownSeconds > 0 ? 'Resend in ${_cooldownSeconds}s' : 'Email Login Link',
  variant: AppButtonVariant.primary, // FilledButton → primary
  onPressed: isDisabled ? null : _sendMagicLink, // no change
  isLoading: _isLoading, // replaces conditional child with CircularProgressIndicator
  fullWidth: true, // SizedBox(width: double.infinity) wrapper → fullWidth prop
)
```

**Line ~583:** `CircularProgressIndicator` (inside FilledButton)

```
// Removed — handled by AppButton's isLoading prop (see above)
```

---

### File 10: `lib/features/auth/invite_screen.dart`

**Line ~306:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  body: SafeArea(child: Center(child: Padding(...))),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  body: SafeArea(child: Center(child: Padding(...))), // no change
)
```

**Line ~319-324:** `CircularProgressIndicator` (accepting/loading states)

```dart
const CircularProgressIndicator(color: AppColors.primary)
→
const AppProgressIndicator(
  type: ProgressIndicatorType.circular,
  color: AppColors.primary,
)
```

**Line ~361, 420:** `ElevatedButton` (Go to App, Email login link buttons)

```dart
ElevatedButton(
  onPressed: () { /* ... */ },
  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
  child: const Text('Go to App'),
)
→
AppButton(
  label: 'Go to App',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () { /* ... */ }, // no change
)
```

**Line ~520:** `TextField` (email input)

**No change** — Keep TextField as-is. AppTextField doesn't expose `onSubmitted` prop (critical for form submission UX). See Boundary Conditions section.

**Line ~557:** `ElevatedButton` (Email login link button, different instance)

```dart
ElevatedButton(
  onPressed: _signingIn ? null : _sendMagicLink,
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ),
  child: _signingIn
      ? const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        )
      : const Text('Email login link', style: TextStyle(...)),
)
→
AppButton(
  label: 'Email login link',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: _signingIn ? null : _sendMagicLink, // no change
  isLoading: _signingIn, // replaces conditional child with CircularProgressIndicator
)
```

**Line ~468:** `TextButton` (Use a different email button)

```dart
TextButton(
  onPressed: () { setState(() { _magicLinkSent = false; }); },
  child: const Text('Use a different email', style: TextStyle(color: AppColors.primary)),
)
→
AppButton(
  label: 'Use a different email',
  variant: AppButtonVariant.text, // map variant
  onPressed: () { setState(() { _magicLinkSent = false; }); }, // no change
)
```

---

### File 11: `lib/features/auth/auth_gate.dart`

**Line ~239, 258, 287, 335, 365:** `Scaffold` (multiple loading/error states)

```dart
Scaffold(
  backgroundColor: context.colors.background,
  body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  body: Center(child: AppProgressIndicator(
    type: ProgressIndicatorType.circular,
    color: AppColors.primary,
  )), // replace CircularProgressIndicator
)
```

**Line ~240, 259, 288, 336, 366:** `CircularProgressIndicator` (in Scaffold body)

```
// See above — replaced with AppProgressIndicator
```

**Line ~383:** `ElevatedButton` (Try Again button in error state)

```dart
ElevatedButton(
  onPressed: () { ref.read(activeBandProvider.notifier).loadUserBands(); },
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
  ),
  child: const Text('Try Again'),
)
→
AppButton(
  label: 'Try Again',
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () { ref.read(activeBandProvider.notifier).loadUserBands(); }, // no change
)
```

**Line ~419:** `IconButton` (close button in pending invite banner)

```dart
IconButton(
  icon: const Icon(AppIcons.close, color: Colors.white),
  onPressed: () { setState(() { _pendingInviteMessage = null; }); },
)
→
AppIconButton(
  icon: AppIcons.close, // icon data only
  color: Colors.white, // no change
  onPressed: () { setState(() { _pendingInviteMessage = null; }); }, // no change
)
```

---

### File 12: `lib/features/auth/auth_confirm_screen.dart`

**Line ~478:** `Scaffold`

```dart
Scaffold(
  backgroundColor: context.colors.background,
  body: Center(child: _loading ? Column(...) : (_error != null ? _buildErrorUI() : Text(...))),
)
→
AppScaffold(
  backgroundColor: context.colors.background, // no change
  body: Center(child: _loading ? Column(...) : (_error != null ? _buildErrorUI() : Text(...))), // no change
)
```

**Line ~481:** `CircularProgressIndicator` (verifying state)

```dart
const CircularProgressIndicator(color: AppColors.primary)
→
const AppProgressIndicator(
  type: ProgressIndicatorType.circular,
  color: AppColors.primary,
)
```

**Line ~267, 319, 460:** `ElevatedButton` (Retry, Back to Login, Request New Magic Link buttons)

```dart
ElevatedButton.icon(
  onPressed: () { /* ... */ },
  icon: const Icon(AppIcons.refresh), // or AppIcons.back, AppIcons.email
  label: const Text('Retry'), // or 'Back to Login', 'Request New Magic Link'
  style: ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
)
→
AppButton(
  label: 'Retry', // or 'Back to Login', 'Request New Magic Link'
  icon: AppIcons.refresh, // or AppIcons.back, AppIcons.email (AppButton supports icon prop)
  variant: AppButtonVariant.secondary, // ElevatedButton → secondary
  onPressed: () { /* ... */ }, // no change
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

| File                                                                     | What changes                                                                                                                                                                                                          |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/profile/profile_screen.dart`                               | Replace Scaffold, AppBar, IconButton, TextButton, CircularProgressIndicator, ElevatedButton, TextFormField, OutlinedButton with wrapper equivalents (see mapping)                                                     |
| `lib/features/profile/my_profile_screen.dart`                            | Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, showDialog, TextField (in dialogs), TextButton with wrapper equivalents                                                                              |
| `lib/features/settings/settings_screen.dart`                             | Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, showDialog, TextButton, Switch with wrapper equivalents                                                                                              |
| `lib/features/notifications/widgets/notification_settings_modal.dart`    | Replace showDialog, ElevatedButton, TextButton with wrapper equivalents                                                                                                                                               |
| `lib/features/notifications/widgets/notification_permission_prompt.dart` | Replace IconButton, TextButton, ElevatedButton with wrapper equivalents                                                                                                                                               |
| `lib/features/notifications/notification_settings_screen.dart`           | Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, Switch.adaptive, Checkbox with wrapper equivalents                                                                                                   |
| `lib/features/notifications/notification_preferences_screen.dart`        | Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, ElevatedButton with wrapper equivalents                                                                                                              |
| `lib/features/auth/login_screen.dart`                                    | Replace FilledButton and CircularProgressIndicator with wrapper equivalents. Retrofit \_sessionDetected Scaffold (early-return loading state). Keep main build Scaffold and TextField as-is (see Boundary Conditions) |
| `lib/features/auth/invite_screen.dart`                                   | Replace Scaffold, CircularProgressIndicator, ElevatedButton, TextButton with wrapper equivalents. TextField kept as-is (see Boundary Conditions)                                                                      |
| `lib/features/auth/auth_gate.dart`                                       | Replace Scaffold, CircularProgressIndicator, ElevatedButton, IconButton with wrapper equivalents                                                                                                                      |
| `lib/features/auth/auth_confirm_screen.dart`                             | Replace Scaffold, CircularProgressIndicator, ElevatedButton with wrapper equivalents                                                                                                                                  |

---

## Files Off-Limits

| File                                                                    | Reason                                                                                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                         | Init order must not change                                                                                               |
| `lib/app/theme/*.dart`                                                  | Theme configuration is stable—wrappers delegate to it, never override it                                                 |
| All files in `lib/components/ui/`                                       | Wrapper layer is stable from Piece 1 + wrapper-gaps cycle—do not modify wrappers even if gaps are found (report instead) |
| All precedent components (BrandActionButton, ConfirmActionDialog, etc.) | Already stable, out of scope                                                                                             |
| All files in `lib/features/` except the 12 listed above                 | Later retrofit cycles (setlists, gigs, calendar, rehearsals, members, venues)                                            |
| All files in `lib/shared/`                                              | Later retrofit cycle or out of scope                                                                                     |
| `lib/features/notifications/notification_navigation_handler.dart`       | False positive from grep—navigation/logic file, no UI widget instantiation                                               |

---

## Boundary Conditions & Exceptions

**TextField gap in login_screen.dart and invite_screen.dart:**

After detailed inspection, `TextField` in these files uses:

- `autocorrect: false` (login_screen only) — not exposed by AppTextField
- `autofillHints: const [AutofillHints.email]` (login_screen only) — not exposed by AppTextField
- `onSubmitted: (_) => ...` (both files) — not exposed by AppTextField

**DECISION:** These props are critical for email input UX. Two options:

1. **Stop and add props to AppTextField before retrofit** (recommended but adds scope)
2. **Keep TextField as-is in these 2 files, retrofit everything else** (minimal scope expansion)

**Architect recommendation:** Option 2—keep `TextField` as-is in `login_screen.dart` and `invite_screen.dart`. Retrofit all other widgets in these files (Scaffold, buttons, progress indicators). Document this as "partial retrofit" in ENGINEER_REPORT.md. The TextField gap can be closed in a follow-up micro-cycle if needed, but it's not blocking the core goal of proving the wrapper layer works across 12 files.

**Scaffold gap in login_screen.dart (main build method only):**

The main build method's `Scaffold` uses `resizeToAvoidBottomInset: false` for custom keyboard handling. AppScaffold doesn't expose this prop. This is a genuine gap, specific to login's unique animation needs (logo shrink on keyboard show).

**DECISION:** Keep main build method's `Scaffold` as-is in `login_screen.dart`. However, the early-return `Scaffold` in the `_sessionDetected` branch (line ~466) has no special props and should be retrofitted to `AppScaffold` normally. This is a ~1-line exception in a 600+ line file, acceptable boundary condition.

**Dialog with custom content:**

In `my_profile_screen.dart` (~line 387), the "Add custom role" dialog has a TextField in the content section. `showAppDialog` with title/message/actions pattern doesn't support this. The wrapper-gaps cycle added a `builder` prop to `showAppDialog` for exactly this case.

**DECISION:** Use `showAppDialog` with custom builder, wrap the showDialog call but keep AlertDialog widget as-is inside the builder (since it has custom layout). Replace the TextField inside with AppTextField, and replace action TextButtons with AppButtons.

---

## System Impact Map

| System                                 | Impact                                                                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected (out of scope for this cycle)                                                                                                                |
| Rehearsals                             | unaffected                                                                                                                                              |
| Setlists / Catalog                     | unaffected                                                                                                                                              |
| Members / RBAC                         | unaffected                                                                                                                                              |
| Calendar                               | unaffected                                                                                                                                              |
| Venues                                 | unaffected                                                                                                                                              |
| Auth / Session                         | affected (auth folder is in scope—auth_gate, login_screen, invite_screen, auth_confirm_screen)                                                          |
| Profile                                | affected (profile folder is in scope—profile_screen, my_profile_screen)                                                                                 |
| Settings                               | affected (settings folder is in scope—settings_screen)                                                                                                  |
| Notifications                          | affected (notifications folder is in scope—notification_settings_screen, notification_preferences_screen, 3 widget files)                               |
| Routing                                | unaffected (AuthGate routing logic unchanged, only widget calls replaced)                                                                               |
| Platform (iOS / Android / Web / macOS) | affected (must render correctly across all 4 platforms—but wrappers delegate to Material widgets with theme config, so platform equivalence is default) |

---

## Regression Risk

**Risk Level:** MEDIUM

**Rationale:**

- **First retrofit touching live call sites** — Unlike Piece 1 (purely additive), mistakes here are user-visible
- **12 files modified, ~100+ widget call substitutions** — Large surface area for mechanical errors
- **No automated tests for target screens** — Regression check is code-path analysis only (QA diff review), not runtime-validated
- **But: Zero logic changes, zero new state, zero backend surface** — Pure widget-call substitution preserves all existing behavior if mapping is executed correctly

**Primary risks:**

1. **Prop mapping error:** Engineer maps prop incorrectly (e.g., `activeTrackColor` → wrong wrapper prop), causing visual regression
2. **Conditional structure drift:** Engineer flattens/changes conditional logic while replacing widget (e.g., `_isLoading ? CircularProgressIndicator() : Text()` → loses conditional), causing runtime crash
3. **Import omission:** Engineer forgets to import wrapper, causing compile error caught by `flutter analyze` (low severity, caught early)
4. **Theme override unintentionally removed:** Engineer omits a critical style prop thinking wrapper handles it, but wrapper delegates to theme which has different default (e.g., button background color changes), causing visual regression

**Mitigation:**

- **Exhaustive mapping table above** — Every single substitution is pre-defined, Engineer executes only (no judgment calls)
- **flutter analyze as gate** — Catches import/compile errors immediately
- **QA code-path analysis** — QA must diff every changed file and verify each substitution is 1:1 per mapping table (no logic drift, no prop mismatches)
- **Manual smoke test recommended** — Tony should manually test each of the 4 folders (profile, settings, notifications, auth) on a real device/browser after QA approval, since no automated tests exist (this is out of scope for Engineer/QA but critical for user confidence)

---

## Engineer Task Breakdown

Execute in strict order. Do not proceed to next task until current task is verified passing.

### Task 1: Verify working directory and branch

- **Command:** `pwd` (expect `/Users/tonyholmes/apps/bandroadie-ui-experiment`)
- **Command:** `git branch --show-current` (expect `experiment/ui-facade`)
- **Command:** `git status --short` (expect clean—no dirty files)
- **If any check fails:** STOP and report to Tony

### Task 2: Create feature docs directory

- **Command:** `mkdir -p docs/features/ui-facade-retrofit-core`
- **Verification:** Directory exists

### Task 3: Read all 12 target files for context

- **Action:** Read each of the 12 files listed in Files to Modify table to understand their structure before editing
- **Purpose:** Familiarize with code patterns, confirm line numbers in mapping table are approximately correct

### Task 4: Retrofit profile_screen.dart

- **File:** `lib/features/profile/profile_screen.dart`
- **Action:** Execute every substitution listed in Per-File Retrofit Mapping Table for this file
- **Add imports:** `import 'package:bandroadie/components/ui/app_scaffold.dart';`, `app_app_bar.dart`, `app_icon_button.dart`, `app_button.dart`, `app_text_form_field.dart`, `app_progress_indicator.dart`
- **Verification:** `flutter analyze lib/features/profile/profile_screen.dart` — 0 errors
- **Verification:** File compiles, no missing symbols

### Task 5: Retrofit my_profile_screen.dart

- **File:** `lib/features/profile/my_profile_screen.dart`
- **Action:** Execute every substitution per mapping table, including showAppDialog with custom builder for "Add custom role" dialog
- **Add imports:** Same as Task 4, plus `app_dialog.dart`, `app_text_field.dart`
- **Verification:** `flutter analyze lib/features/profile/my_profile_screen.dart` — 0 errors

### Task 6: Retrofit settings_screen.dart

- **File:** `lib/features/settings/settings_screen.dart`
- **Action:** Execute every substitution per mapping table
- **Add imports:** app_scaffold, app_app_bar, app_icon_button, app_button, app_progress_indicator, app_switch, app_dialog
- **Verification:** `flutter analyze lib/features/settings/settings_screen.dart` — 0 errors

### Task 7: Retrofit notification_settings_modal.dart

- **File:** `lib/features/notifications/widgets/notification_settings_modal.dart`
- **Action:** Replace showDialog call, replace buttons per mapping table
- **Add imports:** app_dialog, app_button
- **Verification:** `flutter analyze lib/features/notifications/widgets/notification_settings_modal.dart` — 0 errors

### Task 8: Retrofit notification_permission_prompt.dart

- **File:** `lib/features/notifications/widgets/notification_permission_prompt.dart`
- **Action:** Replace IconButton, TextButton, ElevatedButton per mapping table
- **Add imports:** app_icon_button, app_button
- **Verification:** `flutter analyze lib/features/notifications/widgets/notification_permission_prompt.dart` — 0 errors

### Task 9: Retrofit notification_settings_screen.dart

- **File:** `lib/features/notifications/notification_settings_screen.dart`
- **Action:** Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, Switch.adaptive, Checkbox per mapping table
- **Add imports:** app_scaffold, app_app_bar, app_icon_button, app_progress_indicator, app_switch, app_checkbox
- **Verification:** `flutter analyze lib/features/notifications/notification_settings_screen.dart` — 0 errors

### Task 10: Retrofit notification_preferences_screen.dart

- **File:** `lib/features/notifications/notification_preferences_screen.dart`
- **Action:** Replace Scaffold, AppBar, IconButton, CircularProgressIndicator, ElevatedButton per mapping table
- **Add imports:** app_scaffold, app_app_bar, app_icon_button, app_progress_indicator, app_button
- **Verification:** `flutter analyze lib/features/notifications/notification_preferences_screen.dart` — 0 errors

### Task 11: Retrofit login_screen.dart (partial)

- **File:** `lib/features/auth/login_screen.dart`
- **Action:**
  - Replace early-return `Scaffold` (line ~466, in `_sessionDetected` branch) with `AppScaffold`
  - Replace `CircularProgressIndicator` inside that Scaffold with `AppProgressIndicator`
  - Replace `FilledButton` with `AppButton` per mapping table
  - Replace standalone `CircularProgressIndicator` with `AppProgressIndicator` per mapping table
  - **Keep main build method's `Scaffold` (line ~480) and `TextField` (line ~492) as-is** (see Boundary Conditions section)
- **Add imports:** `app_scaffold`, `app_button`, `app_progress_indicator`
- **Verification:** `flutter analyze lib/features/auth/login_screen.dart` — 0 errors
- **Note in ENGINEER_REPORT.md:** TextField kept as-is due to autocorrect/autofillHints/onSubmitted gaps. Main build Scaffold kept as-is due to resizeToAvoidBottomInset gap. Early-return Scaffold retrofitted successfully.

### Task 12: Retrofit invite_screen.dart (partial)

- **File:** `lib/features/auth/invite_screen.dart`
- **Action:**
  - Replace `Scaffold` with `AppScaffold` per mapping table
  - Replace `CircularProgressIndicator` instances with `AppProgressIndicator` per mapping table
  - Replace `ElevatedButton` instances with `AppButton` per mapping table
  - Replace `TextButton` with `AppButton` per mapping table
  - **Keep `TextField` (line ~520) as-is** (see Boundary Conditions section — onSubmitted gap)
- **Add imports:** `app_scaffold`, `app_progress_indicator`, `app_button`
- **Verification:** `flutter analyze lib/features/auth/invite_screen.dart` — 0 errors
- **Note in ENGINEER_REPORT.md:** TextField kept as-is due to onSubmitted gap

### Task 13: Retrofit auth_gate.dart

- **File:** `lib/features/auth/auth_gate.dart`
- **Action:** Replace Scaffold, CircularProgressIndicator, ElevatedButton, IconButton per mapping table
- **Add imports:** app_scaffold, app_progress_indicator, app_button, app_icon_button
- **Verification:** `flutter analyze lib/features/auth/auth_gate.dart` — 0 errors

### Task 14: Retrofit auth_confirm_screen.dart

- **File:** `lib/features/auth/auth_confirm_screen.dart`
- **Action:** Replace Scaffold, CircularProgressIndicator, ElevatedButton per mapping table
- **Add imports:** app_scaffold, app_progress_indicator, app_button
- **Verification:** `flutter analyze lib/features/auth/auth_confirm_screen.dart` — 0 errors

### Task 15: Run flutter analyze on all modified files

- **Command:** `flutter analyze lib/features/profile/ lib/features/settings/ lib/features/notifications/ lib/features/auth/`
- **Expected output:** 0 errors, 0 warnings
- **If errors exist:** Fix them before proceeding (most likely import issues or typos in wrapper names)

### Task 16: Build app for web (mandatory)

- **Command:** `flutter build web --release`
- **Expected output:** Build succeeds, output in `build/web/`
- **Purpose:** Proves app compiles and no runtime imports are broken

### Task 17: Verify zero files modified outside target 12

- **Command:** `git diff --stat`
- **Expected output:** Exactly 12 files modified (the 12 listed in Files to Modify table), no other changes
- **If extra files modified:** Revert them and investigate why they changed

### Task 18: Git diff sanity check

- **Command:** `git diff lib/features/profile/profile_screen.dart | head -100` (repeat for each file)
- **Manual review:** Scan diff for each file, confirm changes match mapping table (Scaffold → AppScaffold, IconButton → AppIconButton, etc.)
- **Purpose:** Catch any accidental logic changes, prop mismatches, or unintended edits

### Task 19: Document boundary conditions in ENGINEER_REPORT.md

- **Action:** Create `docs/features/ui-facade-retrofit-core/ENGINEER_REPORT.md`
- **Content:** List of completed tasks, note TextField/Scaffold kept as-is in login_screen/invite_screen with rationale, confirm flutter analyze clean, confirm web build succeeded

---

## Verification Plan

**Tier 1 — Pre-deployment (N/A for this feature—no migrations):**

This feature has no database migrations, edge functions, or backend changes. All verification is Flutter-local.

**Tier 2 — Post-implementation (Engineer must complete before QA):**

### Test 1: flutter analyze passes with 0 errors

```bash
cd /Users/tonyholmes/apps/bandroadie-ui-experiment
flutter analyze lib/features/profile/ lib/features/settings/ lib/features/notifications/ lib/features/auth/
```

**Expected output:** No issues found! (0 errors, 0 warnings)

**If errors:** Fix before submitting to QA.

### Test 2: Web build succeeds

```bash
flutter clean
flutter pub get
flutter build web --release
```

**Expected output:** Build completes successfully, `build/web/` directory contains compiled output.

**If build fails:** Check error message for missing imports or compile errors, fix before submitting to QA.

### Test 3: Git diff matches mapping table

**Manual verification:** For each of the 12 modified files, open `git diff <file>` and verify every change matches the Per-File Retrofit Mapping Table exactly. No logic changes, no conditional structure changes, only widget name + prop substitutions.

**If mismatch found:** Correct the substitution to match mapping table exactly.

---

**Tier 3 — QA Verification (QA Agent executes):**

### QA Test 1: Code-path analysis (per-file diff review)

**Action:** For each of the 12 files, QA must:

1. Open the git diff
2. For each changed line, verify it matches the mapping table entry for that file
3. Confirm no logic drift (e.g., conditionals preserved, controller assignments unchanged, callback logic identical)
4. Confirm no prop mismatches (e.g., `activeTrackColor` correctly mapped to wrapper's `activeColor`, not omitted)

**Pass criteria:** Every substitution in every file matches mapping table exactly, zero logic changes detected.

### QA Test 2: Import completeness check

**Action:** For each modified file, verify all necessary wrapper imports are present at top of file.

**Pass criteria:** `flutter analyze` passes (Test 1 already confirms this, but QA double-checks imports are correct package paths).

### QA Test 3: Boundary condition compliance

**Action:** Verify `login_screen.dart` and `invite_screen.dart` kept TextField as-is (not replaced with AppTextField), and `login_screen.dart` kept Scaffold as-is (not replaced with AppScaffold).

**Pass criteria:** Documented in ENGINEER_REPORT.md, code matches documented exception.

---

**Tier 4 — Manual Smoke Test (Tony, post-QA-approval):**

Since no automated tests exist for these 4 folders, QA's verification is code-path analysis only (cannot runtime-test behavior). Tony should manually test after QA approval:

1. **Profile folder:** Open profile_screen, edit profile, save changes, verify no visual/behavioral changes
2. **Settings folder:** Open settings, toggle light mode, verify Delete Account flow still works, verify no visual changes
3. **Notifications folder:** Open notification settings, toggle master switch, toggle category checkboxes, verify permission prompt banner works
4. **Auth folder:** Log out, request magic link, verify login flow works (email input, button states, error handling)

**Purpose:** Catch any subtle visual regressions (e.g., button color slightly off, padding changed) that code review can't detect. This is the final confidence gate before merging to main.

---

## Out of Scope / Future Work

**TextField gap closure:** Add `autocorrect`, `autofillHints`, `onSubmitted` props to AppTextField/AppTextFormField in a micro-cycle, then retrofit login_screen/invite_screen TextField calls. Low priority—these files work correctly as-is.

**Scaffold gap closure:** Add `resizeToAvoidBottomInset` prop to AppScaffold, then retrofit login_screen Scaffold call. Very low priority—login screen's keyboard handling is unique and may never need wrapper.

**Dialog content flexibility:** Enhance showAppDialog/AppAlertDialog to support custom content sections (not just title/message), reducing reliance on custom builder pattern. Medium priority—current builder prop works, but explicit content slot would be cleaner.

**Automated tests for target screens:** Add widget tests for profile_screen, settings_screen, notification screens, auth screens to enable runtime regression testing. High value but large scope—separate initiative.

**Remaining retrofit cycles:** After this cycle proves wrappers are safe, retrofit the riskier folders:

- Setlists / Catalog (large, complex widget trees)
- Gigs / Calendar (complex state management)
- Rehearsals
- Members / Venues

Each should be its own Piece 2 cycle with dedicated ARCHITECT_PLAN.md and QA validation.

---

**Architect Sign-off:**

This plan defines every single Material→wrapper substitution the Engineer must execute across 12 files. No judgment calls, no inference—only mechanical execution of the mapping table. QA's pass/fail is binary: does each substitution match the mapping table exactly, yes or no. The boundary conditions (TextField/Scaffold kept as-is in 2 files) are explicitly documented and justified. The verification plan acknowledges the testing limitation (code-path analysis only, no runtime validation) and recommends Tony's manual smoke test as the final gate.

**Ready for Engineer execution.**
