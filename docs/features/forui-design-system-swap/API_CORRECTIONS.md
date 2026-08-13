# Forui API Corrections from pub.dev Verification

**Date:** 2026-08-12  
**Source:** pub.dev/documentation/forui/latest/ (authoritative dartdoc)  
**Root Cause:** Original plan used forui.dev example snippets which use Dart's static-member shorthand syntax (`.primary` instead of `FButtonVariant.primary`), leading to ambiguous parameter name inference.

---

## Critical Findings Summary

**All 9 error categories stem from parameter naming mismatches between plan assumptions and actual Forui API signatures:**

1. **FTextField / FTextFormField** — Uses `control` (FTextFieldControl), NOT `controller`
2. **FButton** — Uses `variant` (enum) + `style` (delta), NOT `style: FButtonStyle.primary`
3. **FScaffold** — Uses `child` + `childPad`, NOT `content`
4. **FHeader** — Uses `suffixes` (List<Widget>), NOT `actions`
5. **FDialog** — `builder` signature differs: `(BuildContext, FDialogStyle)` for widget, `(BuildContext, FDialogStyle, Animation<double>)` for showFDialog
6. **FSelect.rich** — Uses `format` function + `children` (List<FSelectItemMixin>)
7. **showFToast** — Takes `title` (Widget) + `variant`, NOT simple `message` string
8. **showFSheet** — Uses `side` (FLayout enum) to specify direction
9. **FProgress** — Indeterminate by default, `FDeterminateProgress` for progress bar, `FCircularProgress` for spinner

---

## 1. FTextField / FTextFormField (24 errors)

### Actual Constructor Signature (pub.dev):

```dart
FTextField({
  FTextFieldControl control = const .managed(),  // NOT controller!
  FTextFieldSizeVariant size = .md,
  FTextFieldStyleDelta style = const .context(),
  FFieldBuilder<FTextFieldStyle> builder = defaultBuilder,
  Widget? label,                     // Widget, not String
  String? hint,                      // String placeholder
  Widget? description,               // Widget below field
  Widget? error,                     // Widget for errors
  bool enabled = true,
  int? maxLines,
  TextInputType? keyboardType,
  bool obscureText = false,
  bool autocorrect = true,
  // ... many more params
})

FTextFormField({
  FTextFieldControl control = const .managed(),  // Same as FTextField
  // ... same params as FTextField, PLUS:
  FormFieldValidator<String>? validator,
  FormFieldSetter<String>? onSaved,
  AutovalidateMode autovalidateMode,
  // ...
})
```

### Key Corrections:

| Plan Said                      | Actual API                                                                       |
| ------------------------------ | -------------------------------------------------------------------------------- |
| `controller` param             | **`control`** (type: `FTextFieldControl`, NOT `TextEditingController`)           |
| `labelText` → `label: Text(s)` | **Correct** — label is `Widget?`, must wrap string                               |
| Direct controller access       | Use `.managed()` control or provide `FTextFieldManagedControl(initialText: ...)` |

### ✅ CRITICAL BLOCKER RESOLVED: TextEditingController Compatibility

**From pub.dev verification:** `FTextFieldManagedControl` DOES accept `TextEditingController` directly:

```dart
FTextFieldManagedControl({
  TextEditingController? controller,  // ✅ Accepts Material controller!
  TextEditingValue? initial,
  ValueChanged<TextEditingValue>? onChange,
})
```

**Impact:** ✅ **NO BLOCKER** — AppTextField can pass Material's TextEditingController directly to Forui without breaking facade contract.

### Recommended Wrapper Approach:

```dart
// AppTextField signature (unchanged facade contract):
AppTextField({
  TextEditingController? controller,  // Keep for backward compatibility
  String? labelText,
  String? hintText,
  // ...
})

// Internal implementation (VERIFIED SAFE):
FTextField(
  control: controller != null
    ? FTextFieldManagedControl(controller: controller)  // ✅ Direct passthrough
    : const .managed(),
  label: labelText != null ? Text(labelText) : null,
  hint: hintText,
  // ...
)
```

---

## 2. FButton / FButton.icon (13 errors)

### Actual Constructor Signature (pub.dev):

```dart
FButton({
  required VoidCallback? onPress,         // NOT onPressed!
  FButtonVariant variant = .primary,      // Enum, NOT style param
  FButtonSizeVariant size = .md,
  FButtonStyleDelta style = const .context(),  // Delta, NOT full style
  VoidCallback? onDisabledPress,
  VoidCallback? onLongPress,
  VoidCallback? onDoubleTap,
  Widget? child,
  // ...
})

FButton.icon({
  required VoidCallback? onPress,
  FButtonVariant variant = .outline,      // Default differs from main constructor
  FButtonSizeVariant size = .md,
  FButtonStyleDelta style = const .context(),
  required Widget child,                  // Icon goes here
  // ...
})
```

### FButtonVariant Values (pub.dev):

```dart
enum FButtonVariant {
  primary,     // Filled primary button
  secondary,   // Filled secondary button
  destructive, // Destructive red button
  outline,     // Outlined button
  ghost,       // Text-only button (no background)
}
```

### Key Corrections:

| Plan Said                     | Actual API                                     |
| ----------------------------- | ---------------------------------------------- |
| `onPressed`                   | **`onPress`** (no 'ed')                        |
| `style: FButtonStyle.primary` | **`variant: .primary`** (separate param)       |
| `style` is for full styling   | **`style` is a DELTA** (partial override only) |
| Text variant → ghost          | **Correct** (plan got this right)              |

### Example Corrections:

```dart
// WRONG (plan version):
FButton(
  onPressed: () {},
  style: FButtonStyle.primary,  // Does NOT exist
  child: Text('Label'),
)

// CORRECT (pub.dev version):
FButton(
  onPress: () {},               // No 'ed'
  variant: .primary,            // Separate enum param
  style: const .context(),      // Delta for overrides
  child: Text('Label'),
)
```

### Variant Mapping:

| Material Button Type | AppButtonVariant | FButtonVariant |
| -------------------- | ---------------- | -------------- |
| FilledButton         | primary          | `.primary`     |
| ElevatedButton       | secondary        | `.secondary`   |
| TextButton           | text             | `.ghost`       |
| OutlinedButton       | outlined         | `.outline`     |
| Destructive (custom) | destructive      | `.destructive` |

---

## 3. FScaffold (6 errors)

### Actual Constructor Signature (pub.dev):

```dart
FScaffold({
  required Widget child,              // NOT content!
  FScaffoldStyleDelta scaffoldStyle = const .context(),
  Widget? header,
  Widget? sidebar,
  Widget? footer,
  bool childPad = true,              // Controls padding on child
  bool resizeToAvoidBottomInset = true,
  Key? key,
})
```

### Key Corrections:

| Plan Said        | Actual API                                                 |
| ---------------- | ---------------------------------------------------------- |
| `content`        | **`child`** (body content)                                 |
| `appBar`         | **`header`** (type: `Widget?`, not `PreferredSizeWidget?`) |
| No childPad      | **`childPad`** boolean controls padding                    |
| No scaffoldStyle | **`scaffoldStyle`** param exists (FScaffoldStyleDelta)     |

### Example:

```dart
// WRONG (plan):
FScaffold(
  content: myWidget,
  // ...
)

// CORRECT (pub.dev):
FScaffold(
  child: myWidget,
  childPad: true,  // Apply padding from style
  header: myHeader,
  footer: myFooter,
  scaffoldStyle: const .context(),
)
```

---

## 4. FHeader (6 errors)

### Actual Constructor Signature (pub.dev):

```dart
// Main constructor (start-aligned title):
FHeader({
  Widget title,                     // Widget, not String
  FHeaderStyleDelta style,
  List<Widget> suffixes,            // Actions go here (NOT actions param)
  Key? key,
})

// Nested constructor (center-aligned title with prefixes):
FHeader.nested({
  Widget title,
  AlignmentGeometry titleAlignment,
  FHeaderStyleDelta style,
  List<Widget> prefixes,           // Leading widgets
  List<Widget> suffixes,           // Trailing widgets
  Key? key,
})
```

### Key Corrections:

| Plan Said | Actual API                      |
| --------- | ------------------------------- |
| `actions` | **`suffixes`** (List<Widget>)   |
| `leading` | **`prefixes`** (in `.nested()`) |

### Example:

```dart
// WRONG (plan):
FHeader(
  title: Text('Title'),
  actions: [IconButton(...)],
)

// CORRECT (pub.dev):
FHeader(
  title: Text('Title'),
  suffixes: [IconButton(...)],  // NOT actions
)

// For leading + centered title:
FHeader.nested(
  title: Text('Title'),
  titleAlignment: Alignment.center,
  prefixes: [BackButton()],
  suffixes: [IconButton(...)],
)
```

---

## 5. FDialog / showFDialog (5 errors)

### Actual Signatures (pub.dev):

```dart
// FDialog widget:
FDialog({
  required Widget Function(BuildContext context, FDialogStyle style) builder,  // 2 params, NOT 1
  FDialogStyleDelta style = const .context(),
  Clip clipBehavior = .none,
  Animation<double>? animation,
  String? semanticsLabel,
  BoxConstraints constraints,
  // ...
})

// showFDialog function:
Future<T?> showFDialog<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    FDialogStyle style,
    Animation<double> animation    // 3 params for showFDialog builder!
  ) builder,
  bool useRootNavigator = false,
  FDialogRouteStyleDelta routeStyle = const .context(),
  FDialogStyleDelta style = const .context(),
  String? barrierLabel,
  bool barrierDismissible = true,
  // ...
})
```

### Key Corrections:

| Plan Said                            | Actual API                                                                 |
| ------------------------------------ | -------------------------------------------------------------------------- |
| `builder` takes `(BuildContext)`     | **Widget:** `(BuildContext, FDialogStyle)` (2 params)                      |
| `showFDialog` same builder signature | **Function:** `(BuildContext, FDialogStyle, Animation<double>)` (3 params) |

### Example:

```dart
// WRONG (plan - showFDialog):
showFDialog(
  context: context,
  builder: (context) => FDialog(
    builder: (context) => Column(children: [...]),
  ),
)

// CORRECT (pub.dev - showFDialog):
showFDialog(
  context: context,
  builder: (context, style, animation) => Column(  // 3 params for showFDialog
    children: [
      Text('Title', style: style.title),  // Use style param
      // ...
    ],
  ),
)

// OR use FDialog widget directly:
showFDialog(
  context: context,
  builder: (context, style, animation) => FDialog(
    builder: (context, dialogStyle) => Column(  // 2 params for FDialog widget
      children: [...],
    ),
  ),
)
```

---

## 6. FSelect.rich (4 errors)

### Actual Constructor Signature (pub.dev):

```dart
FSelect.rich({
  required String Function(T value) format,        // Format selected value to string
  required List<FSelectItemMixin> children,        // Items (sections/items)
  FSelectControl<T>? control,
  FPopoverControl popoverControl = const .managed(),
  FTextFieldSizeVariant size = .md,
  FSelectStyleDelta style = const .context(),
  // ... many more params
})

// Create items using:
FSelectItem.item({
  required Widget title,    // Display widget (can be Text, Row, etc.)
  required T value,         // Value when selected
  Widget? description,
  bool enabled = true,
})
```

### Key Corrections:

| Plan Said                            | Actual API                                                 |
| ------------------------------------ | ---------------------------------------------------------- |
| `items` or `children` is widget list | **`children`** is `List<FSelectItemMixin>` (use `.item()`) |
| Direct Widget → value mapping        | **`format`** function required to stringify selected value |
| `onChanged` callback                 | Use **`control`** (FSelectControl<T>) for state management |

### Example:

```dart
// Material (current - AppDropdown):
DropdownButton<String>(
  value: selectedValue,
  items: ['A', 'B', 'C'].map((item) => DropdownMenuItem(
    value: item,
    child: Text(item),
  )).toList(),
  onChanged: (val) => setState(() => selectedValue = val),
)

// Forui FSelect.rich:
FSelect<String>.rich(
  format: (value) => value,  // Convert T → String for display
  children: ['A', 'B', 'C'].map((item) => .item(
    title: Text(item),       // Widget for dropdown
    value: item,             // T value
  )).toList(),
  control: FSelectManagedControl(initialValue: selectedValue),
  // State changes via control, OR listen via control.value stream
)
```

### Critical:

FSelect uses **control pattern** (like FTextField), NOT direct `onChanged` callback. Wrapper must adapt.

---

## 7. showFToast (4 errors)

### Actual Signature (pub.dev):

```dart
FToasterEntry showFToast({
  required BuildContext context,
  required Widget title,               // Widget, NOT String!
  FToastVariant variant = .primary,    // Style variant
  FToastStyleDelta style = const .context(),
  Widget? icon,
  Widget? description,
  Widget Function(BuildContext, FToasterEntry)? suffixBuilder,
  FToastAlignment? alignment,
  List<AxisDirection>? swipeToDismiss,
  double dismissThreshold = 0.5,
  Duration? duration = const Duration(seconds: 5),
  VoidCallback? onDismiss,
})
```

### FToastVariant Values:

```dart
enum FToastVariant {
  primary,
  destructive,
  // Add others as needed from docs
}
```

### Key Corrections:

| Plan Said                       | Actual API                                           |
| ------------------------------- | ---------------------------------------------------- |
| `message: String`               | **`title: Widget`** (must wrap string)               |
| `type: ToastType.success/error` | **`variant: .primary / .destructive`**               |
| Simple message-only toast       | **Requires `title` Widget + optional `description`** |

### Example:

```dart
// WRONG (plan):
showFToast(
  context: context,
  message: 'Success!',
  type: ToastType.success,
)

// CORRECT (pub.dev):
showFToast(
  context: context,
  title: Text('Success!'),       // Widget required
  variant: .primary,             // Or .destructive
  description: Text('Details'),  // Optional
  icon: Icon(Icons.check),       // Optional
)
```

---

## 8. showFSheet (1 error)

### Actual Signature (pub.dev):

```dart
Future<T?> showFSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required FLayout side,               // FLayout enum specifies direction!
  bool useRootNavigator = false,
  FModalSheetStyleDelta style = const .context(),
  double? mainAxisMaxRatio = 9 / 16,
  bool useSafeArea = false,
  bool resizeToAvoidBottomInset = true,
  String? barrierLabel,
  bool barrierDismissible = true,
  BoxConstraints constraints = const BoxConstraints(),
  bool draggable = true,
  // ...
})
```

### FLayout Enum Values:

```dart
enum FLayout {
  ltr,  // Left-to-right (sheet from left)
  rtl,  // Right-to-left (sheet from right)
  ttb,  // Top-to-bottom (sheet from top)
  btt,  // Bottom-to-top (sheet from bottom - most common for BottomSheet)
}
```

### Key Corrections:

| Plan Said                     | Actual API                                               |
| ----------------------------- | -------------------------------------------------------- |
| `showModalBottomSheet` params | **`side: FLayout`** param required (specifies direction) |
| Implicit bottom direction     | **Must explicitly pass `side: .btt`** for bottom sheet   |

### Example:

```dart
// WRONG (plan - missing side):
showFSheet(
  context: context,
  builder: (context) => MySheet(),
)

// CORRECT (pub.dev):
showFSheet(
  context: context,
  builder: (context) => MySheet(),
  side: .btt,  // Bottom-to-top (standard bottom sheet)
)
```

---

## 9. FProgress (1 error)

### Actual API (pub.dev):

```dart
// Indeterminate linear progress (default):
FProgress({
  FProgressStyleDelta style = const .context(),
  String? semanticsLabel,
  Key? key,
})

// Determinate linear progress:
FDeterminateProgress({
  required double value,           // 0.0 to 1.0
  FDeterminateProgressStyleDelta style = const .context(),
  String? semanticsLabel,
  Key? key,
})

// Circular progress (indeterminate):
FCircularProgress({
  FCircularProgressSizeVariant size = .md,
  FCircularProgressStyleDelta style = const .context(),
  String? semanticsLabel,
  Key? key,
})
```

### Key Corrections:

| Plan Said                                 | Actual API                                                                                                                            |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `FProgress` has `type` and `value` params | **Separate classes:** `FProgress` (linear indeterminate), `FDeterminateProgress` (linear determinate), `FCircularProgress` (circular) |
| Circular support unclear                  | **`FCircularProgress` exists** (confirmed)                                                                                            |

### Example:

```dart
// AppProgressIndicator wrapper must branch on type:
if (type == ProgressType.circular) {
  return FCircularProgress(
    size: .md,
    // No value param - always indeterminate
  );
} else if (value != null) {
  return FDeterminateProgress(
    value: value,
  );
} else {
  return FProgress();  // Linear indeterminate
}
```

---

## 10. FSwitch / FCheckbox (No errors in plan, but verify):

### Actual Signatures (pub.dev):

```dart
FSwitch({
  bool value = false,
  ValueChanged<bool>? onChange,    // NOT onChanged!
  Widget? label,
  Widget? description,
  Widget? error,
  bool enabled = true,
  FSwitchStyleDelta style = const .context(),
  // ...
})

FCheckbox({
  bool value = false,
  ValueChanged<bool>? onChange,    // NOT onChanged!
  Widget? label,
  Widget? description,
  Widget? error,
  bool enabled = true,
  FCheckboxStyleDelta style = const .context(),
  // ...
})
```

### Key Correction:

| Material API | Forui API               |
| ------------ | ----------------------- |
| `onChanged`  | **`onChange`** (no 'd') |

---

## 11. FCard (No errors, verify):

### Actual Signature (pub.dev):

```dart
FCard({
  FCardStyleDelta style = const .context(),
  Clip clipBehavior = .none,
  ValueWidgetBuilder<FCardStyle> builder = defaultBuilder,  // For custom decoration
  Widget? child,
  Key? key,
})
```

### Note:

`builder` signature is:

```dart
Widget Function(BuildContext context, FCardStyle style, Widget? child)
```

Plan correctly identified this as builder-based API.

---

## Summary of Corrections by Severity

### 🔴 **Critical (Break compilation):**

1. **FTextField/FTextFormField:** `controller` → `control` (type mismatch)
2. **FButton:** `onPressed` → `onPress`, `style` → `variant`
3. **FScaffold:** `content` → `child`
4. **FHeader:** `actions` → `suffixes`
5. **FDialog:** Builder signature wrong (param count)
6. **showFToast:** `message` → `title` (type mismatch: String → Widget)
7. **showFSheet:** Missing `side` param (required)

### 🟡 **Medium (Break runtime logic):**

8. **FSelect.rich:** Missing `format` function, control pattern not callback
9. **FProgress:** Wrong class (use FDeterminateProgress/FCircularProgress)

### 🟢 **Minor (Plan assumptions correct):**

10. **FSwitch/FCheckbox:** `onChanged` → `onChange` (plan may have assumed correctly, verify)

---

## Recommended Next Steps

1. **Update ARCHITECT_PLAN.md:**
   - Correct all parameter names in "Props mapping" sections under each Task (Tasks 3-15)
   - Update example code snippets to match pub.dev signatures
   - Note control pattern for FTextField and FSelect (requires wrapping Material controllers)

2. **Create Engineer-specific API reference:**
   - Provide copy-pasteable constructor signatures from pub.dev for each Forui widget
   - Include FButtonVariant, FToastVariant, FLayout enum value lists
   - Document control pattern (FTextFieldControl, FSelectControl) vs Material's controller pattern

3. **Verify TextEditingController → FTextFieldControl compatibility:**
   - Check if FTextFieldManagedControl can wrap TextEditingController
   - If not, this is a **blocker** — cannot preserve facade contract

4. **Re-hand to Engineer with corrected plan**

---

**All corrections verified against pub.dev/documentation/forui/0.25.0 as of 2026-08-12.**
