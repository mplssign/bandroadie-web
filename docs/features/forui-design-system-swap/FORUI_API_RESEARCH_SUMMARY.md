# Forui API Research Summary

**Date:** 2026-08-12  
**Objective:** Verify actual Forui API signatures from pub.dev dartdoc for all 9 error categories (64 compile errors total)  
**Status:** ✅ **Complete** — All 9 categories researched, corrections documented

---

## Research Completed (9/9 Categories)

| Widget Category           | Errors | Status | Critical Finding                               |
| ------------------------- | ------ | ------ | ---------------------------------------------- |
| FTextField/FTextFormField | 24     | ✅     | Uses `control` param, NOT `controller`         |
| FButton/FButton.icon      | 13     | ✅     | Uses `variant` + `style`, NOT `style` alone    |
| FScaffold                 | 6      | ✅     | Uses `child`, NOT `content`                    |
| FHeader                   | 6      | ✅     | Uses `suffixes`, NOT `actions`                 |
| FDialog                   | 5      | ✅     | Builder signatures differ (widget vs function) |
| FSelect.rich              | 4      | ✅     | Requires `format` function + `children` list   |
| showFToast                | 4      | ✅     | Takes `title: Widget`, NOT `message: String`   |
| showFSheet                | 1      | ✅     | Requires `side: FLayout` param                 |
| FProgress                 | 1      | ✅     | Separate classes for determinate/circular      |

**Total errors researched:** 64/64

---

## Root Cause Confirmed

**Diagnosis:** ARCHITECT_PLAN.md's API signatures were inferred from forui.dev example code, which uses Dart's static member shorthand syntax (`.primary` instead of `FButtonVariant.primary`). This led to ambiguous interpretations when reverse-engineering constructor signatures.

**Example of the problem:**

```dart
// forui.dev example code:
FButton(
  onPress: () {},
  variant: .primary,   // Static shorthand - looks like a named parameter assignment
)

// Architect misread as:
FButton(
  onPress: () {},
  style: FButtonStyle.primary,  // ❌ Wrong - inferred "style" from ".primary" shorthand
)

// Actual pub.dev signature:
FButton({
  required VoidCallback? onPress,
  FButtonVariant variant = .primary,      // ✅ "variant" is the actual param name
  FButtonStyleDelta style = const .context(),  // ✅ "style" is for deltas only
})
```

This pattern repeated across most widgets: shorthand syntax made it unclear which parameter name the value belonged to.

---

## Deliverables Created

1. **API_CORRECTIONS.md** (this directory)
   - Comprehensive corrections for all 9 error categories
   - Actual pub.dev constructor signatures (copy-pasteable)
   - Side-by-side "Plan Said" vs "Actual API" tables
   - Severity ratings (Critical/Medium/Minor)
   - Examples showing wrong vs correct usage

2. **This summary** (for handoff to you)

---

## Key Corrections by Category

### 1. FTextField/FTextFormField (24 errors) - 🔴 CRITICAL

**Issue:** Plan assumed `controller: TextEditingController` param.  
**Reality:** Uses `control: FTextFieldControl` (Forui's abstraction over TextEditingController).

**Impact:** AppTextField wrapper must adapt TextEditingController → FTextFieldControl internally, OR verify FTextFieldControl can wrap Material controllers. If not possible, this is a **blocker**.

---

### 2. FButton/FButton.icon (13 errors) - 🔴 CRITICAL

**Issue:** Plan assumed `style: FButtonStyle.primary` param.  
**Reality:**

- `variant: FButtonVariant` (enum) — selects button style (primary/secondary/destructive/outline/ghost)
- `style: FButtonStyleDelta` — narrow delta overrides ONLY

**Impact:** Engineer must use `variant` param, not `style`. Also `onPress` (no 'd'), not `onPressed`.

---

### 3. FScaffold (6 errors) - 🔴 CRITICAL

**Issue:** Plan assumed `content` param for body.  
**Reality:** Uses `child` param. Also has `childPad` boolean for padding control.

---

### 4. FHeader (6 errors) - 🔴 CRITICAL

**Issue:** Plan assumed `actions` param for trailing widgets.  
**Reality:** Uses `suffixes` (List<Widget>). For leading widgets, use `FHeader.nested()` with `prefixes`.

---

### 5. FDialog / showFDialog (5 errors) - 🔴 CRITICAL

**Issue:** Plan assumed builder takes 1 param `(BuildContext)`.  
**Reality:**

- `FDialog` widget builder: `(BuildContext context, FDialogStyle style)` — 2 params
- `showFDialog` function builder: `(BuildContext context, FDialogStyle style, Animation<double> animation)` — 3 params

---

### 6. FSelect.rich (4 errors) - 🟡 MEDIUM

**Issue:** Plan assumed simple `children` widget list.  
**Reality:**

- Requires `format: (T value) => String` function to stringify selected value
- `children` is `List<FSelectItemMixin>`, created via `.item(title: Widget, value: T)`
- Uses control pattern (FSelectControl), not direct `onChanged` callback

---

### 7. showFToast (4 errors) - 🔴 CRITICAL

**Issue:** Plan assumed `message: String` param.  
**Reality:** Uses `title: Widget` (must wrap string in Text()). Also has `variant: FToastVariant` enum, not type string.

---

### 8. showFSheet (1 error) - 🔴 CRITICAL

**Issue:** Plan didn't mention `side` param.  
**Reality:** Requires `side: FLayout` enum (`.btt` for bottom-to-top, standard bottom sheet direction).

---

### 9. FProgress (1 error) - 🟡 MEDIUM

**Issue:** Plan assumed single `FProgress` class with `type` and `value` params.  
**Reality:**

- `FProgress()` — indeterminate linear
- `FDeterminateProgress(value: double)` — determinate linear (0.0-1.0)
- `FCircularProgress()` — indeterminate circular

**Good news:** Circular progress IS supported (plan was uncertain).

---

## Additional Findings

### FSwitch / FCheckbox - 🟢 MINOR

Uses `onChange` callback, NOT `onChanged` (no 'd'). Plan may have assumed correctly, but verify.

### FCard - ✅ NO ISSUES

Plan correctly identified builder-based API. No corrections needed.

---

## Confidence Assessment

| Correction Category | Confidence | Reasoning                                                               |
| ------------------- | ---------- | ----------------------------------------------------------------------- |
| All 9 categories    | **HIGH**   | Signatures pulled directly from pub.dev dartdoc                         |
| Control pattern     | **MEDIUM** | Need to verify TextEditingController → FTextFieldControl wrapper exists |
| Visual appearance   | **MEDIUM** | Forui styling will differ from Material (expected)                      |
| Cross-platform      | **LOW**    | Forui is platform-agnostic; desktop experience uncertain                |

---

## Blockers Identified

### ✅ BLOCKER RESOLVED: TextEditingController Compatibility

**Issue (identified):** FTextField uses `control: FTextFieldControl`, not `controller: TextEditingController`.

**Resolution (verified from pub.dev):** ✅ **NO BLOCKER** — `FTextFieldManagedControl` explicitly accepts `TextEditingController`.

**Actual API (pub.dev confirmed):**

```dart
FTextFieldManagedControl({
  TextEditingController? controller,  // ✅ Accepts Material controller directly!
  TextEditingValue? initial,
  ValueChanged<TextEditingValue>? onChange,
})
```

**Wrapper implementation (safe, preserves facade):**

```dart
// AppTextField signature (unchanged):
AppTextField({
  TextEditingController? controller,
  String? labelText,
  String? hintText,
  // ...
})

// Internal Forui mapping (NO call-site changes):
FTextField(
  control: controller != null
    ? FTextFieldManagedControl(controller: controller)  // ✅ Direct passthrough
    : const .managed(),
  label: labelText != null ? Text(labelText) : null,
  hint: hintText,
  // ...
)
```

**Conclusion:** Facade contract preserved. AppTextField can accept Material's `TextEditingController` and pass it directly to Forui via `FTextFieldManagedControl(controller: ...)`.

### Status: Zero blocking issues identified. All 14 wrapper swaps are technically feasible.

---

## Next Steps

### For Tony:

1. **Review API_CORRECTIONS.md**
   - Verify corrections make sense
   - Confirm understanding of control pattern (FTextField, FSelect)

2. **Decide on TextEditingController blocker:**
   - If you want me to verify FTextFieldControl compatibility, I can deep-dive into pub.dev docs further
   - OR hand this to Engineer to verify during implementation (riskier)

3. **Update ARCHITECT_PLAN.md:**
   - I can apply these corrections to the plan systematically (will be a large multi-replace operation)
   - OR you can hand corrected plan + API_CORRECTIONS.md to Engineer directly

4. **Hand to Engineer:**
   - Provide updated plan + API_CORRECTIONS.md
   - Engineer must verify control pattern compatibility FIRST before starting Task 7 (AppTextField)

### For Engineer (when handed off):

1. **FIRST:** Verify FTextFieldControl can wrap TextEditingController (Task 7 blocker check)
2. Follow updated ARCHITECT_PLAN.md with corrected parameter names
3. Refer to API_CORRECTIONS.md for exact constructor signatures
4. If control pattern is incompatible, STOP and escalate to Tony

---

## Files Modified

| File                                                                          | Status                     |
| ----------------------------------------------------------------------------- | -------------------------- |
| `docs/features/forui-design-system-swap/API_CORRECTIONS.md`                   | ✅ Created                 |
| `docs/features/forui-design-system-swap/FORUI_API_RESEARCH_SUMMARY.md` (this) | ✅ Created                 |
| `docs/features/forui-design-system-swap/ARCHITECT_PLAN.md`                    | ⏳ Pending Tony's decision |

---

## Summary

✅ **Research objective complete:** All 9 error categories' actual API signatures are documented from pub.dev.

⚠️ **One critical blocker needs verification:** TextEditingController → FTextFieldControl compatibility. This must be confirmed before implementation.

📋 **Deliverables ready:** API_CORRECTIONS.md provides Engineer with exact parameter names, types, and examples for all 64 errors.

🎯 **Next action:** Tony decides whether to:

1. Have me update ARCHITECT_PLAN.md with corrections, OR
2. Hand API_CORRECTIONS.md to Engineer directly with current plan, OR
3. Deep-dive into FTextFieldControl compatibility verification first

**Ball is in Tony's court.**
