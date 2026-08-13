# ARCHITECT_PLAN: Restore Dropped Style and Behavioral Props on Forui UI Wrappers

## 1. Feature Summary

**Feature ID:** `feature/forui-style-overrides`  
**Cycle:** Post-Forui design system swap (PR #145)  
**Objective:** Restore ~40 deliberately dropped prop overrides across 14 Forui-based UI facade wrappers in `lib/components/ui/`.

**Context:** The prior cycle (`feature/forui-design-system-swap`, merged as PR #145) swapped the underlying implementation of 14 BandRoadie UI facade wrappers from Material widgets to Forui design system widgets. To ship the preview quickly and avoid API signature mismatches (which caused two blocked implementation attempts), ~40 call sites' worth of custom prop overrides were deliberately dropped as silent no-ops. This cycle restores those props by properly wiring them through to Forui's actual API, verified against pub.dev dartdoc (not forui.dev marketing examples).

**Scope:**
- **In Scope:** Restore functional props (callbacks, formatters, capitalization, etc.) and visual style overrides (backgroundColor, padding, elevation, borderRadius, activeColor, etc.) on AppButton, AppTextField, AppTextFormField, AppSwitch, AppCheckbox, AppCard, AppScaffold
- **Out of Scope:** AppChip (still uses Material), AppBottomSheet (no public Forui StyleDelta API found), new features beyond restoring prior behavior

**Success Criteria:**
1. All dropped functional props restored and tested at existing call sites
2. All dropped visual style props restored via Forui StyleDelta mechanism
3. Zero regressions in existing Forui appearance
4. README.md "Props Ignored in Preview" section removed

---

## 2. Problem Statement

### 2.1 Core Problem
The current UI facade wrappers in `lib/components/ui/` silently ignore 40+ props that were previously supported in the Material-based implementation. Call sites passing these props receive no errors but also see no effect, creating a confusing developer experience where props appear to work but don't.

### 2.2 Root Cause Analysis

**Historical Context:**
- **Cycle 1 (feature/forui-design-system-swap):** Swapped 14 wrappers from Material to Forui
- **Blockers:** Two implementation attempts blocked by API signature mismatches between forui.dev marketing docs and actual pub.dev dartdoc API
- **Workaround:** Props deliberately dropped as silent no-ops to ship preview
- **Documentation:** lib/components/ui/README.md lists all dropped props per wrapper

**Technical Root Cause:**
1. **API Naming Differences:** Forui uses different names (e.g., `onSubmit` vs `onSubmitted`, `prefixBuilder` vs `prefixIcon`)
2. **Builder Pattern Migration:** Icon props require builder functions instead of direct widget arguments
3. **StyleDelta Mechanism:** Visual overrides require nested StyleDelta API instead of flat properties
4. **Insufficient API Research:** Prior cycle relied on forui.dev examples instead of authoritative pub.dev dartdoc

**Affected Wrapper Prop Counts:**
- **AppTextField:** 16 dropped props (highest impact)
- **AppTextFormField:** 16 dropped props (same as AppTextField)
- **AppButton:** 6 dropped props
- **AppCheckbox:** 2 dropped props (activeColor, tristate)
- **AppSwitch:** 3 dropped props (activeColor, activeTrackColor, useAdaptiveSwitch)
- **AppCard:** 2 dropped props (padding, elevation)
- **AppScaffold:** 1 dropped prop (floatingActionButton)

**Call Site Impact:**
- **onSubmitted:** 14 call sites in 12 files (login forms, search fields, etc.)
- **textInputAction:** 25 call sites in 17 files (form navigation)
- **prefixIcon/suffixIcon:** 3 call sites (search fields)
- **readOnly:** 4 call sites (display-only fields)
- **backgroundColor:** 0 AppButton call sites (searched codebase, no custom colors in use)

**Confidence:** **HIGH**

---

## 3. Database Impact

**Assessment:** **NONE - UI-Only Change**

This feature affects only the client-side UI facade layer. No database schema changes, migrations, RPC functions, or RLS policies are required.

---

## 4. System Impact Map

### 4.1 Directly Modified Files
```
lib/components/ui/
├── app_text_field.dart           [HIGH IMPACT - 16 props + 3 prefix/suffix icon call sites]
├── app_text_form_field.dart      [HIGH IMPACT - 16 props + 14 onSubmitted + 25 textInputAction call sites]
├── app_button.dart               [MEDIUM IMPACT - 6 style props via StyleDelta]
├── app_checkbox.dart             [LOW IMPACT - 2 props, tristate may be blocker]
├── app_switch.dart               [LOW IMPACT - 3 props via StyleDelta]
├── app_card.dart                 [LOW IMPACT - 2 props via StyleDelta]
├── app_scaffold.dart             [LOW IMPACT - 1 prop, FAB may be blocker]
└── README.md                     [DOCUMENTATION - remove "Props Ignored" sections]
```

### 4.2 Call Site Files (Read-Only Analysis)
**AppTextField with prefixIcon/suffixIcon:**
- `lib/features/songs/widgets/az_search_field.dart`
- `lib/features/setlists/setlist_detail_screen.dart` (search)
- `lib/features/songs/song_lookup_overlay.dart` (search)

**AppTextFormField with onSubmitted:**
- 14 call sites across login, forms, search UIs

**AppTextFormField with textInputAction:**
- 25 call sites for form field navigation (next, done, search, etc.)

**readOnly TextFields:**
- 4 call sites for display-only fields

### 4.3 Dependency Graph
```
┌─────────────────────┐
│   Feature Screens   │  (setlist_detail, login, gig forms, etc.)
│  (40+ call sites)   │
└──────────┬──────────┘
           │ depends on
           ▼
┌─────────────────────┐
│   UI Facade Layer   │  (app_text_field, app_button, etc.)
│  lib/components/ui/ │  ◄── THIS CYCLE: Wire props to Forui API
└──────────┬──────────┘
           │ wraps
           ▼
┌─────────────────────┐
│   Forui Widgets     │  (FTextField, FButton, etc.)
│   forui: ^0.25.0   │
└─────────────────────┘
```

**Ripple Effect:** **ZERO**  
Call sites already pass the props (they're just ignored currently). Restoring them activates existing code with no refactoring required.

### 4.4 Risk Classification

**Regression Risk:** **LOW**
- Changes are additive (restoring props that were no-ops)
- No breaking API changes to facade wrappers
- Forui's existing appearance preserved (StyleDeltas only apply when props are passed)

**Integration Risk:** **MEDIUM**
- **Blocker Potential:** Tristate checkbox, floatingActionButton may genuinely lack Forui support
- **Nested Delta Complexity:** Deep StyleDelta nesting (FButtonStyleDelta → contentStyle → padding) may cause implementation errors
- **Builder Pattern Migration:** prefixIcon → prefixBuilder requires lambda wrapping existing Icon widgets

**Testing Strategy:**
- **Unit Tests:** Verify prop pass-through for functional props (onSubmit, textInputAction, etc.)
- **Widget Tests:** Verify StyleDelta application (backgroundColor, padding) renders correctly
- **Manual Testing:** Smoke test 3 search fields (prefix/suffix icons), 14 onSubmitted forms, login flow

---

## 5. Technical Design

### 5.1 Architecture Approach

**Strategy:** In-place prop restoration with API translation layer in facade wrappers.

**Key Principles:**
1. **API Translation:** Map facade props (Material-style) to Forui API (Forui-style) within wrapper
2. **StyleDelta Construction:** Build Forui StyleDelta objects from flat prop arguments
3. **Backward Compatibility:** Preserve existing facade API surface (call sites unchanged)
4. **Graceful Degradation:** Document any genuinely unsupported props as "Not Available in Forui"

### 5.2 Prop Restoration Categories

#### Category A: Direct Pass-Through (Simple)
Props that exist in Forui with identical names, just wire them through.

**AppTextField/AppTextFormField:**
- `autofillHints` → `FTextField(autofillHints: ...)`
- `autofocus` → `FTextField(autofocus: ...)`
- `inputFormatters` → `FTextField(inputFormatters: ...)`
- `maxLength` → `FTextField(maxLength: ...)`
- `minLines` → `FTextField(minLines: ...)`
- `onEditingComplete` → `FTextField(onEditingComplete: ...)`
- `onTap` → `FTextField(onTap: ...)`
- `readOnly` → `FTextField(readOnly: ...)`
- `textAlign` → `FTextField(textAlign: ...)`
- `textCapitalization` → `FTextField(textCapitalization: ...)`
- `textInputAction` → `FTextField(textInputAction: ...)`

**Implementation:**
```dart
// lib/components/ui/app_text_field.dart (example)
class AppTextField extends StatelessWidget {
  final TextInputAction? textInputAction;  // ADD
  final bool readOnly;                     // ADD (default: false)
  final bool autofocus;                    // ADD (default: false)
  // ... other new params

  @override
  Widget build(BuildContext context) {
    return FTextField(
      // ... existing params
      textInputAction: textInputAction,    // WIRE THROUGH
      readOnly: readOnly,                  // WIRE THROUGH
      autofocus: autofocus,                // WIRE THROUGH
    );
  }
}
```

**Confidence:** **HIGH** (Confirmed in pub.dev FTextField API docs)

#### Category B: API Name Translation
Props that exist in Forui but with different names.

**AppTextField/AppTextFormField:**
- `onSubmitted` → `onSubmit` (Forui's name for submit callback)

**Implementation:**
```dart
// lib/components/ui/app_text_form_field.dart
class AppTextFormField extends StatelessWidget {
  final ValueChanged<String>? onSubmitted;  // Keep facade API name

  @override
  Widget build(BuildContext context) {
    return FTextFormField(
      onSubmit: onSubmitted,  // MAP to Forui API name
      // ...
    );
  }
}
```

**Confidence:** **HIGH** (Confirmed: FTextField has `onSubmit` property, not `onSubmitted`)

#### Category C: Builder Pattern Migration
Props that require wrapping in builder functions.

**AppTextField/AppTextFormField:**
- `prefixIcon` → `prefixBuilder` (FFieldIconBuilder function)
- `suffixIcon` → `suffixBuilder` (FFieldIconBuilder function)

**Forui API Signature:**
```dart
typedef FFieldIconBuilder<T> = Widget Function(
  BuildContext context,
  T style,
  Set<FTextFieldVariant> variants,
  Widget icon,
);

FTextField.prefixIconBuilder(_, style, variants, icon) {
  // Returns styled icon widget
}
```

**Implementation:**
```dart
// lib/components/ui/app_text_field.dart
class AppTextField extends StatelessWidget {
  final Widget? prefixIcon;  // Keep facade API (Widget)
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return FTextField(
      prefixBuilder: prefixIcon != null
        ? (context, style, variants) => FTextField.prefixIconBuilder(
            context,
            style,
            variants,
            prefixIcon!,  // Pass widget to builder
          )
        : null,
      suffixBuilder: suffixIcon != null
        ? (context, style, variants) => FTextField.suffixIconBuilder(
            context,
            style,
            variants,
            suffixIcon!,
          )
        : null,
      // ...
    );
  }
}
```

**Note:** Forui provides static helper `FTextField.prefixIconBuilder()` that wraps a widget in proper icon styling (confirmed in pub.dev docs).

**Confidence:** **HIGH** (Confirmed: FTextField has `prefixBuilder`/`suffixBuilder` and static helper)

#### Category D: StyleDelta Mechanism (Complex)
Visual props that require constructing StyleDelta objects.

**AppButton:**
- `backgroundColor`, `disabledBackgroundColor`, `disabledForegroundColor` → `FButtonStyleDelta.delta(decoration: ...)`
- `borderRadius` → `FButtonStyleDelta.delta(decoration: DecorationDelta.box(borderRadius: ...))`
- `padding` → `FButtonStyleDelta.delta(contentStyle: FButtonContentStyleDelta.delta(padding: ...))`
- `elevation` → May require `decoration` shadow property (needs investigation)

**Implementation Pattern:**
```dart
// lib/components/ui/app_button.dart
class AppButton extends StatelessWidget {
  final Color? backgroundColor;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    // Construct StyleDelta from props
    final styleDelta = FButtonStyleDelta.delta(
      decoration: backgroundColor != null || borderRadius != null
        ? FVariantsDelta.all(
            DecorationDelta.box(
              color: backgroundColor,
              borderRadius: borderRadius != null 
                ? BorderRadiusDelta.circular(borderRadius!) 
                : null,
            ),
          )
        : null,
      contentStyle: padding != null
        ? FButtonContentStyleDelta.delta(
            padding: EdgeInsetsGeometryDelta.only(
              left: padding!.horizontal / 2,
              right: padding!.horizontal / 2,
              // ... extract EdgeInsets values
            ),
          )
        : null,
    );

    return FButton(
      variant: _mapVariantToForui(variant),
      style: styleDelta,
      onPress: onPressed,
      child: Text(label),
    );
  }
}
```

**Complexity Notes:**
- Nested delta construction (FButtonStyleDelta → decoration → DecorationDelta → BorderRadiusDelta)
- May need helper methods to build deltas cleanly
- Need to verify `EdgeInsetsGeometry` → `EdgeInsetsGeometryDelta` conversion

**Confidence:** **MEDIUM** (API confirmed, but complex nesting may have edge cases)

**Other StyleDelta Targets:**
- **AppSwitch:** `FSwitchStyleDelta.delta(trackColor: ..., thumbColor: ...)`
- **AppCheckbox:** `FCheckboxStyleDelta.delta(decoration: ...)`
- **AppCard:** `FCardStyleDelta.delta(padding: ..., decoration: ...)`

#### Category E: Potential Blockers (Investigate)
Props that may not have Forui equivalents.

**AppCheckbox:**
- `tristate` - Forui FCheckbox may not support null value (current code coalesces null → false)
- **Mitigation:** If genuinely unsupported, document in README and keep coalescing behavior

**AppScaffold:**
- `floatingActionButton` - FScaffold may not have FAB concept
- **Mitigation:** Search for alternative patterns (footer action button, modal trigger, etc.)

**AppTextField:**
- `decoration` (InputDecoration) - Forui uses different decoration model, cannot map directly
- **Mitigation:** Document as "Use StyleDelta for decoration instead"

**Confidence:** **LOW** (Needs investigation during implementation)

### 5.3 Files and Change Points

#### Primary Implementation Files
1. **lib/components/ui/app_text_field.dart**
   - Add 13 functional props (autofillHints, autofocus, inputFormatters, maxLength, minLines, onEditingComplete, onTap, readOnly, textAlign, textCapitalization, textInputAction, prefixIcon, suffixIcon)
   - Wire onSubmitted → onSubmit
   - Implement prefixIcon/suffixIcon → prefixBuilder/suffixBuilder mapping
   - Add FTextFieldStyleDelta construction if style prop needed (future)

2. **lib/components/ui/app_text_form_field.dart**
   - Same as AppTextField (shares same dropped prop list)
   - Ensure validator and onSaved still work with restored props

3. **lib/components/ui/app_button.dart**
   - Add 6 style props (backgroundColor, borderRadius, elevation, padding, disabledBackgroundColor, disabledForegroundColor)
   - Construct FButtonStyleDelta.delta() from props
   - Merge with existing variant-based styling

4. **lib/components/ui/app_checkbox.dart**
   - Add activeColor prop → FCheckboxStyleDelta
   - Investigate tristate support (may remain unsupported)

5. **lib/components/ui/app_switch.dart**
   - Add activeColor, activeTrackColor props → FSwitchStyleDelta
   - Investigate useAdaptiveSwitch (may be default Forui behavior)

6. **lib/components/ui/app_card.dart**
   - Add padding, elevation props → FCardStyleDelta

7. **lib/components/ui/app_scaffold.dart**
   - Investigate floatingActionButton alternatives
   - May remain unsupported (document in README)

8. **lib/components/ui/README.md**
   - Remove "Props Ignored in Preview" sections for restored props
   - Add "Props Not Supported in Forui" section for genuine blockers

#### Supporting Files (No Changes)
- Call site files (40+ screens/widgets) - No changes required, props already passed

### 5.4 Edge Cases and Error Handling

**Edge Case 1: Conflicting StyleDeltas**
- **Scenario:** Call site passes both `backgroundColor` and custom `style` delta
- **Handling:** Document that custom `style` takes precedence, or merge deltas if possible

**Edge Case 2: prefixIcon with custom styling**
- **Scenario:** Call site passes styled Icon widget as prefixIcon
- **Handling:** FTextField.prefixIconBuilder should preserve widget styling

**Edge Case 3: elevation without platform shadows**
- **Scenario:** Forui may not support Material-style elevation shadows
- **Handling:** Map to `decoration` shadow property or document as unsupported

**Error Handling:**
- No new error states introduced (props are optional)
- Invalid prop combinations (e.g., minLines > maxLines) pass through to Forui validation

---

## 6. Implementation Boundaries

### 6.1 What This Cycle WILL Do
✅ Restore all functional props (onSubmitted, textInputAction, autofocus, readOnly, etc.)  
✅ Restore prefix/suffix icon support via builder pattern  
✅ Restore visual style props via StyleDelta mechanism (backgroundColor, padding, etc.)  
✅ Update README.md to remove "Props Ignored" sections  
✅ Manual testing at 3 search fields, 14 onSubmitted forms, login flow  

### 6.2 What This Cycle WILL NOT Do
❌ Add new props beyond restoring prior Material API  
❌ Modify call sites (props already passed, just ignored currently)  
❌ Refactor AppChip (still Material-based)  
❌ Implement floatingActionButton if Forui genuinely lacks support  
❌ Support tristate checkbox if Forui genuinely lacks support  
❌ Add comprehensive widget test suite (manual smoke testing only)  

### 6.3 Deferred Work
- **Future Cycle:** Add widget tests for StyleDelta rendering
- **Future Cycle:** Investigate FBottomSheet StyleDelta API (no pub.dev docs found)
- **Future Cycle:** Performance profiling of StyleDelta construction overhead

---

## 7. Dependencies and Risks

### 7.1 External Dependencies
- **forui: ^0.25.0** - No version change required
- **flutter: 3.44.6** - No version change required

### 7.2 Internal Dependencies
- **lib/components/ui/README.md** - Current dropped prop documentation
- **40+ call site files** - Already passing props (read-only dependency)

### 7.3 Key Risks and Mitigations

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| **Nested StyleDelta API errors** | HIGH | MEDIUM | Start with simple props (backgroundColor), test incrementally, use pub.dev docs |
| **prefixBuilder lambda complexity** | MEDIUM | LOW | Use Forui's static `prefixIconBuilder()` helper, test at 3 search field call sites |
| **tristate checkbox unsupported** | LOW | HIGH | Document as Forui limitation, keep null → false coalescing |
| **floatingActionButton unsupported** | LOW | MEDIUM | Search for alternative footer action pattern, document if unavailable |
| **elevation mapping unclear** | MEDIUM | MEDIUM | Research DecorationDelta shadow API, fall back to border if needed |
| **Call site regressions** | MEDIUM | LOW | Manual smoke testing at high-impact call sites (login, search, forms) |

---

## 8. Testing Strategy

### 8.1 Unit Tests
**Scope:** Verify prop pass-through to Forui API.

**Test Cases:**
1. `app_text_field_test.dart` - Assert onSubmitted maps to onSubmit
2. `app_text_field_test.dart` - Assert prefixIcon wraps in prefixBuilder lambda
3. `app_button_test.dart` - Assert backgroundColor constructs FButtonStyleDelta

**Priority:** MEDIUM (Manual testing higher priority given timeline)

### 8.2 Widget Tests
**Scope:** Verify StyleDelta rendering.

**Test Cases:**
1. Render AppButton with backgroundColor, assert decoration contains color
2. Render AppTextField with prefixIcon, assert icon appears in UI tree
3. Render AppCard with padding, assert FCardStyleDelta padding applied

**Priority:** LOW (Deferred to future cycle)

### 8.3 Manual Testing
**Scope:** Smoke test high-impact call sites.

**Test Plan:**
1. **Search Fields (prefixIcon/suffixIcon):**
   - Test `az_search_field.dart` - magnifying glass icon
   - Test `setlist_detail_screen.dart` search bar
   - Test `song_lookup_overlay.dart` search bar
   - **Expected:** Icons render, no layout regressions

2. **onSubmitted Forms (14 call sites):**
   - Test login screen email/password fields
   - Test gig creation form
   - Test band creation form
   - **Expected:** Enter key submits form, keyboard action button shows "done"/"next"

3. **textInputAction Navigation (25 call sites):**
   - Test multi-field forms (gig details, band settings)
   - **Expected:** "Next" button moves focus between fields

4. **readOnly Fields (4 call sites):**
   - Test display-only text fields
   - **Expected:** No keyboard appears, field not editable

5. **Visual Style Props:**
   - Test backgroundColor on buttons (if any call sites exist)
   - Test card padding variations
   - **Expected:** Custom colors/padding render correctly

**Acceptance Criteria:**
- All 3 search fields render icons correctly
- All 14 onSubmitted forms submit on Enter key
- All 25 textInputAction fields navigate correctly
- Zero visual regressions in existing Forui appearance

---

## 9. Rollout Plan

### 9.1 Implementation Phases

**Phase 1: Category A+B (Direct Pass-Through + Name Translation)**
- **Duration:** 2 hours
- **Scope:** Restore functional props on AppTextField/AppTextFormField
- **Validation:** Manual test onSubmitted at login screen, textInputAction in forms

**Phase 2: Category C (Builder Pattern)**
- **Duration:** 2 hours
- **Scope:** Restore prefixIcon/suffixIcon via prefixBuilder/suffixBuilder
- **Validation:** Manual test 3 search fields

**Phase 3: Category D (StyleDelta - Simple)**
- **Duration:** 3 hours
- **Scope:** Restore backgroundColor, padding on AppButton via FButtonStyleDelta
- **Validation:** Manual test button appearance, search for call sites with custom colors

**Phase 4: Category D (StyleDelta - Complex)**
- **Duration:** 3 hours
- **Scope:** Restore activeColor on AppSwitch/AppCheckbox, padding/elevation on AppCard
- **Validation:** Manual test switch/checkbox states, card appearance

**Phase 5: Category E (Blockers)**
- **Duration:** 2 hours
- **Scope:** Investigate tristate checkbox, floatingActionButton, document unsupported props
- **Validation:** Update README.md with "Not Supported in Forui" section

**Phase 6: Documentation + Cleanup**
- **Duration:** 1 hour
- **Scope:** Remove "Props Ignored in Preview" from README, commit feature branch
- **Validation:** README accurately reflects restored props

**Total Estimated Duration:** 13 hours

### 9.2 Rollback Plan
- **Rollback Trigger:** Category D StyleDelta implementation blocked by complex nesting errors
- **Rollback Procedure:** Merge Phases 1-2 (functional props) only, defer StyleDelta to future cycle
- **Rollback Risk:** LOW (Phases 1-2 are high-confidence, independently valuable)

---

## 10. Success Metrics

### 10.1 Completion Criteria
✅ All Category A+B functional props restored and tested (onSubmitted, textInputAction, etc.)  
✅ All Category C builder props restored and tested (prefixIcon, suffixIcon)  
✅ Category D StyleDelta props restored for AppButton, AppSwitch, AppCheckbox, AppCard  
✅ README.md "Props Ignored in Preview" sections removed  
✅ Manual smoke tests pass at 3 search fields, 14 onSubmitted forms, login flow  
✅ Zero visual regressions in existing Forui appearance  

### 10.2 Quality Gates
- **No compiler errors** in wrapper implementations
- **No runtime exceptions** in manual testing
- **No layout shifts** in Forui appearance (StyleDeltas only apply when props passed)

### 10.3 Documentation Deliverables
- **ENGINEER_REPORT.md** - Implementation details, blockers encountered, API patterns used
- **QA_REPORT.md** - Manual test results, screenshots of prefix/suffix icons, regression checklist
- **README.md updates** - Remove "Props Ignored" sections, add "Not Supported" section if needed

---

## 11. Open Questions

1. **FBottomSheet StyleDelta:** No pub.dev docs found. Should we investigate source code or defer?
   - **Answer:** Defer to future cycle, focus on high-impact wrappers first

2. **Elevation mapping:** Does Forui's `DecorationDelta` support shadow elevation?
   - **Answer:** Investigate during Phase 4, fall back to border/outline if unsupported

3. **tristate checkbox:** Does FCheckbox support null value or only true/false?
   - **Answer:** Test during Phase 5, document as unsupported if null coalesces to false

4. **useAdaptiveSwitch:** Is this Forui's default behavior?
   - **Answer:** Test FSwitch on iOS vs Android, check if platform adaptation automatic

5. **floatingActionButton:** Does FScaffold have equivalent concept?
   - **Answer:** Search Forui docs for "action button" patterns during Phase 5

---

## 12. Approval and Sign-Off

**Prepared by:** AI Architect (GitHub Copilot)  
**Date:** 2025-01-26  
**Status:** Ready for Implementation  

**Assumptions:**
- Forui 0.25.0 API is stable (no breaking changes expected)
- Call sites already passing props (verified via grep_search)
- Manual testing sufficient for this cycle (comprehensive tests deferred)

**Next Steps:**
1. Create feature branch `feature/forui-style-overrides`
2. Implement Phase 1 (functional props pass-through)
3. Validate at login screen and forms
4. Proceed through phases sequentially with manual validation at each step

**Review Required?** NO (Architecture phase complete, proceed to implementation per ARCHITECT.md process)
