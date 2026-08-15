# Architect Plan — Dashboard Card Glow

**Feature Identifier:** `feature/dashboard-card-glow`  
**Type:** feature  
**Branch:** `feature/forui-card-consolidation` (additional commits on existing branch)  
**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-15

---

## Executive Summary

Add soft, color-coded outer glows to dashboard cards (rehearsals and gigs) to reinforce card type at a glance. This is a visual enhancement following the card-consolidation work that removed all gradient/color from card surfaces. The glow provides subtle type indication without disrupting the neutral Forui card styling now in place.

**Root Cause Confidence:** N/A (feature addition, not a bug fix)  
**Database Impact:** None  
**Migration Required:** No  
**Affected Platforms:** Web, iOS, Android, macOS

---

## Problem Description

After the Forui card consolidation (commits `ff6689e` and `ae65ab2` on branch `feature/forui-card-consolidation`), all dashboard cards now use neutral AppCard styling with no color differentiation on the card surface itself. While this achieves visual consistency with the Forui design system, it removes the at-a-glance type identification that gradient backgrounds previously provided.

**User Impact:**  
Users scanning the home dashboard must read text labels to distinguish rehearsal cards from gig cards, and confirmed events from potential events. A subtle visual cue (color-coded glow) would improve scanability without re-introducing the visual noise removed by card consolidation.

---

## Expected Behavior

Each dashboard card renders with a soft, faint outer glow matching its type:

| Card Type           | Glow Color | Hex Value             |
| ------------------- | ---------- | --------------------- |
| Confirmed Rehearsal | Soft blue  | `#2563EB` (blue-600)  |
| Confirmed Gig       | Soft green | `#22C55E` (green-500) |
| Potential Rehearsal | Soft amber | `#F59E0B` (amber-500) |
| Potential Gig       | Soft amber | `#F59E0B` (amber-500) |

**Glow characteristics (matching existing pattern from [home_screen.dart:585-591](home_screen.dart)):**

- Alpha: `0.2` (20% opacity, hex: `0x33`)
- Blur radius: `24`
- Spread radius: `4`
- Offset: `Offset.zero` (default)

**Visual priority:**

- Potential state (amber) overrides type color (blue/green) for both rehearsals and gigs
- Glow is visible in dark mode (app is dark-only)
- Glow does not obscure content or clash with neutral card surfaces
- Glow renders outside the card's border, not clipped by border radius

---

## Current Code Analysis

### 1. AppCard Component (`lib/components/ui/app_card.dart`)

**Current Implementation (as of commit `ae65ab2`):**

```dart
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.height,
    this.borderRadius,
    this.border,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final themeBorderColor = context.theme.colors.border;
    final effectiveBorder =
        border ?? Border.all(color: themeBorderColor, width: 1);

    final styleDelta = FCardStyleDelta.delta(
      padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
      decoration: DecorationDelta.boxDelta(
        borderRadius: borderRadius,
        border: effectiveBorder,
      ),
    );

    final card = FCard(style: styleDelta, child: child);
    final cardWithHeight =
        height != null ? SizedBox(height: height, child: card) : card;

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: cardWithHeight);
    }

    return cardWithHeight;
  }
}
```

**Key Finding:**  
`DecorationDelta.boxDelta` (from `package:forui/src/theme/delta/decoration.dart`) **does support `boxShadow`** as a parameter:

```dart
const factory DecorationDelta.boxDelta({
  Color? color,
  DecorationImage? image,
  BoxBorder? border,
  BorderRadiusGeometry? borderRadius,
  List<BoxShadow>? boxShadow,  // ← Supported!
  Gradient? gradient,
  BlendMode? Function()? backgroundBlendMode,
  BoxShape? shape,
}) = _DecorationBoxDelta;
```

This confirms we can extend `AppCard` with a `boxShadow` parameter and pass it through to `DecorationDelta.boxDelta` exactly as `border` was added in commit `ae65ab2`.

### 2. Dashboard Card Widgets

All dashboard cards use `AppCard` with consistent parameters:

**RehearsalCard (`lib/features/home/widgets/rehearsal_card.dart`):**

- `_buildConfirmedCard` (line 509): `AppCard(padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(Spacing.cardRadius), ...)`
- `_buildPotentialCard` (line 287): `AppCard(padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(Spacing.cardRadius), ...)`

**ConfirmedGigCard (`lib/features/home/widgets/confirmed_gig_card.dart`):**

- `build` (line 41): `AppCard(padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(Spacing.buttonRadius), ...)`

**PotentialGigCard (`lib/features/home/widgets/potential_gig_card.dart`):**

- `build` (line 186): `AppCard(padding: EdgeInsets.zero, borderRadius: BorderRadius.circular(Spacing.cardRadius), ...)`

**Out of Scope (not dashboard event cards):**

- `load_more_rehearsals_card.dart` — pagination UI
- `empty_section_card.dart` — empty state UI
- Any other card widgets in the codebase

### 3. Existing Glow Pattern Reference

From `lib/features/home/home_screen.dart` lines 585-591 (empty state icon):

```dart
boxShadow: [
  BoxShadow(
    color: AppColors.primary.withValues(alpha: 0.2),
    blurRadius: 24,
    spreadRadius: 4,
  ),
],
```

This establishes the visual weight and blur characteristics to match.

### 4. Color Constants

From `lib/app/theme/design_tokens.dart` and `lib/app/theme/brand_colors.dart`:

```dart
AppColors.blueAccent = Color(0xFF2563EB);  // blue-600
AppColors.success = Color(0xFF22C55E);     // green-500
BrandColors.warning = Color(0xFFF59E0B);   // amber-500 (dark theme)
```

All required colors are already defined. Using hex literals with alpha channel for inline glow definitions (e.g., `Color(0x332563EB)` = blue @ 20% opacity) is more concise and avoids `.withValues()` calls.

---

## Proposed Solution

**Approach:**  
Minimal localized edits. Extend `AppCard` with optional `boxShadow` parameter (same pattern as `border` was added), then update each dashboard card widget to pass the appropriate glow for its type/state.

**Why This Approach:**

- Uses Forui's existing delta system (no wrapper containers needed)
- Consistent with how `border` param was added in commit `ae65ab2`
- Shadows render outside the card's clip region (verified in Forui implementation)
- Minimal diff surface — touches only 5 files
- No new architecture, no new dependencies
- No database, RPC, or backend impact

**Alternative Rejected:**  
Wrapping `AppCard` output in an outer `Container(decoration: BoxDecoration(boxShadow: [...]))` was considered but rejected because it would add unnecessary widget tree depth and is inconsistent with how `border` was added. Forui's delta system is designed to handle this.

---

## Files to Modify

### 1. `lib/components/ui/app_card.dart`

**Change:** Add optional `boxShadow` parameter and pass it to `DecorationDelta.boxDelta`.

**Before (lines 1-16):**

```dart
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.height,
    this.borderRadius,
    this.border,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
```

**After:**

```dart
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.height,
    this.borderRadius,
    this.border,
    this.boxShadow,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
```

**Before (lines 45-54):**

```dart
    final styleDelta = FCardStyleDelta.delta(
      padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
      decoration: DecorationDelta.boxDelta(
        borderRadius: borderRadius,
        border: effectiveBorder,
      ),
    );
```

**After:**

```dart
    final styleDelta = FCardStyleDelta.delta(
      padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
      decoration: DecorationDelta.boxDelta(
        borderRadius: borderRadius,
        border: effectiveBorder,
        boxShadow: boxShadow,
      ),
    );
```

**Rationale:**  
Same pattern as `border` param. Forui's `DecorationDelta.boxDelta` supports `boxShadow` natively. No default value needed — `null` is appropriate for cards without glows.

---

### 2. `lib/features/home/widgets/rehearsal_card.dart`

**Change:** Add `boxShadow` parameter to both `AppCard` invocations (confirmed and potential variants).

**Location 1 — Confirmed Rehearsal (line 520):**

**Before:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          child: Container(
```

**After:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x332563EB), // blue-600 @ 20%
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
          child: Container(
```

**Location 2 — Potential Rehearsal (line 298):**

**Before:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          child: Container(
```

**After:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33F59E0B), // amber-500 @ 20%
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
          child: Container(
```

**Rationale:**

- Confirmed rehearsals get blue glow (type color)
- Potential rehearsals get amber glow (overrides type color per spec)
- Using hex literals with alpha (`0x33` = 51 = ~20%) for brevity
- `const` qualifier for compile-time optimization

---

### 3. `lib/features/home/widgets/confirmed_gig_card.dart`

**Change:** Add `boxShadow` parameter to `AppCard` invocation.

**Location — Confirmed Gig (line 46):**

**Before:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          child: Container(
```

**After:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.buttonRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3322C55E), // green-500 @ 20%
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
          child: Container(
```

**Rationale:**  
Confirmed gigs get green glow (type color).

---

### 4. `lib/features/home/widgets/potential_gig_card.dart`

**Change:** Add `boxShadow` parameter to `AppCard` invocation.

**Location — Potential Gig (line 197):**

**Before:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          child: Container(
```

**After:**

```dart
        child: AppCard(
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(Spacing.cardRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33F59E0B), // amber-500 @ 20%
              blurRadius: 24,
              spreadRadius: 4,
            ),
          ],
          child: Container(
```

**Rationale:**  
Potential gigs get amber glow (overrides type color per spec).

---

## Implementation Checklist

**Engineer must complete in order:**

1. ✅ Checkout branch `feature/forui-card-consolidation` (already on this branch)
2. ⬜ Extend `AppCard` with `boxShadow` parameter (`lib/components/ui/app_card.dart`)
3. ⬜ Update `AppCard` `build()` to pass `boxShadow` to `DecorationDelta.boxDelta`
4. ⬜ Update `RehearsalCard._buildConfirmedCard` with blue glow
5. ⬜ Update `RehearsalCard._buildPotentialCard` with amber glow
6. ⬜ Update `ConfirmedGigCard.build` with green glow
7. ⬜ Update `PotentialGigCard.build` with amber glow
8. ⬜ Run `flutter analyze` — must pass with 0 errors
9. ⬜ Verify no unintended changes to other widgets (check `git diff`)
10. ⬜ Generate full `git diff` for QA review
11. ⬜ Complete `ENGINEER_REPORT.md` with all tasks marked complete

**Post-Implementation Verification (QA):**

- Visual inspection on all platforms (Web, iOS, Android, macOS)
- Confirm glows render outside card borders (not clipped)
- Confirm colors match spec (blue/green/amber at correct opacity)
- Confirm no impact on other cards (empty state, load more, etc.)
- Confirm no performance regression (shadows are hardware-accelerated)

---

## Database Impact

**Database:** Not applicable  
**RLS Policies:** Not applicable  
**RPC Functions:** Not applicable  
**Migrations:** Not applicable

This is a pure client-side visual enhancement with no backend interaction.

---

## System Impact Matrix

| System             | Impact     | Notes                                           |
| ------------------ | ---------- | ----------------------------------------------- |
| Gigs               | Affected   | `ConfirmedGigCard`, `PotentialGigCard` modified |
| Rehearsals         | Affected   | `RehearsalCard` modified (both variants)        |
| Setlists / Catalog | Unaffected | No changes to setlist UI                        |
| Members / RBAC     | Unaffected | No authorization changes                        |
| Auth / Session     | Unaffected | No auth flow changes                            |
| Routing            | Unaffected | No navigation changes                           |
| Home Dashboard     | Affected   | Visual enhancement to dashboard cards           |
| Forui Theme System | Affected   | `AppCard` component extended                    |
| Design Tokens      | Unaffected | Uses existing color constants                   |

---

## Risk Assessment

**Risk Level:** Low

**Risks:**

1. **Shadow clipping by border radius**  
   **Mitigation:** Forui's `DecorationDelta.boxDelta` applies shadows to the outer `BoxDecoration`, which renders outside the clip region. Verified in Forui source (`_BoxDelta` class). QA will confirm visually.

2. **Performance impact from multiple shadow layers**  
   **Mitigation:** Flutter hardware-accelerates `BoxShadow`. The home dashboard already renders 10+ cards with animations. Adding one shadow per card is negligible. Monitor frame times during QA (release mode only — debug mode inflates shadow costs).

3. **Color contrast in light mode (if ever implemented)**  
   **Mitigation:** App is dark-mode-only per design spec. If light mode is added later, glow colors may need adjustment (reduce alpha or change hue). Document this in the plan for future reference.

4. **Glow visibility on high-contrast displays**  
   **Mitigation:** The 20% alpha is soft by design. If users with accessibility needs report poor contrast, increase alpha to 30% (`0x4D`) or add a user preference. Not a blocker for initial implementation.

---

## Testing Requirements

### Manual Testing (QA Agent)

**Platforms:** Web, iOS, Android, macOS

**Test Cases:**

1. **Visual Inspection**
   - Open home dashboard with at least one of each card type visible
   - Confirm blue glow on confirmed rehearsal cards
   - Confirm green glow on confirmed gig cards
   - Confirm amber glow on potential rehearsal cards
   - Confirm amber glow on potential gig cards
   - Confirm glows are soft/faint (not overpowering)
   - Confirm glows do not obscure text or icons

2. **Edge Cases**
   - Cards at screen edges (glow not clipped by viewport)
   - Overlapping cards (e.g., in horizontal scroll) — glows do not bleed into adjacent cards
   - Empty states and "Load More" cards — no glows (unmodified)

3. **Performance**
   - Scroll through 20+ cards on home dashboard
   - Confirm smooth 60fps scroll (release mode)
   - Confirm no jank when cards enter/exit viewport

4. **Accessibility**
   - High contrast mode (if supported by OS) — glows remain visible
   - Dark mode (default) — glows visible against dark background

### Automated Testing

**Not Required:**  
This is a visual-only change with no business logic. Manual QA on all platforms is sufficient. Widget tests would be low-value (testing that a parameter is passed through).

---

## Rollback Plan

If QA identifies a blocking issue:

1. **Immediate:** `git revert <commit-sha>` of the glow feature commit(s)
2. **Push revert to branch:** `git push origin feature/forui-card-consolidation`
3. **Notify Architect and Manager:** Document the issue for re-planning
4. **Branch state:** Reverts to commit `ae65ab2` (border-contrast fix)

Rollback is safe because:

- No database changes
- No breaking API changes
- `boxShadow` parameter is optional — existing `AppCard` call sites unaffected
- Commit is atomic (one feature, one revert)

---

## Open Questions / Decisions

**None.** All requirements are explicit, all dependencies are confirmed, all colors are specified.

---

## References

**Forui API Documentation:**

- `package:forui/src/theme/delta/decoration.dart` — `DecorationDelta.boxDelta` signature
- Verified `boxShadow` parameter support on 2026-08-15

**Existing Code Patterns:**

- Commit `ae65ab2`: Added `border` parameter to `AppCard` — same pattern for `boxShadow`
- `lib/features/home/home_screen.dart:585-591`: Existing glow pattern (blurRadius: 24, spreadRadius: 4, alpha: 0.2)

**Design Tokens:**

- `lib/app/theme/design_tokens.dart`: Spacing constants (cardRadius, buttonRadius)
- `lib/app/theme/brand_colors.dart`: Color constants (success, warning, blueAccent)

**Feature Specification:**

- User request dated 2026-08-15
- Feature identifier: `feature/dashboard-card-glow`
- Branch: `feature/forui-card-consolidation` (additional commits)

---

## Commit Strategy

**Commit Message (after QA approval):**

```
feat(ui): add color-coded soft glow to dashboard cards by type

Dashboard cards now render with subtle outer glows to reinforce type at a
glance following card-consolidation work:

- Confirmed rehearsals: soft blue glow (#2563EB @ 20%)
- Confirmed gigs: soft green glow (#22C55E @ 20%)
- Potential rehearsals/gigs: soft amber glow (#F59E0B @ 20%)

Extended AppCard with optional boxShadow param (same pattern as border param
added in ae65ab2). Uses Forui's DecorationDelta.boxDelta for native shadow
support. No wrapper containers, no performance impact.

Affects: Web, iOS, Android, macOS
Testing: Manual QA on all platforms (visual inspection, scroll perf)
```

**Branch Flow:**

1. Commit to `feature/forui-card-consolidation`
2. Push branch
3. Open PR (or amend existing PR for this branch)
4. Merge to `main` after approval

---

## Architect Sign-Off

**Architect:** GitHub Copilot (Claude Sonnet 4.5)  
**Date:** 2026-08-15  
**Status:** ✅ Plan Complete — Ready for Engineer

**Confidence:**

- ✅ Forui API support confirmed (read package source)
- ✅ Existing pattern verified (commit `ae65ab2`)
- ✅ Color constants verified (design_tokens.dart)
- ✅ Card usage patterns verified (read all 4 card widgets)
- ✅ No database/backend dependencies
- ✅ Minimal diff surface (5 files, <50 LOC)

**Next Steps:**

1. Manager reviews and approves plan
2. Engineer implements per checklist
3. QA validates on all platforms
4. Commit after QA approval

---

_End of Architect Plan_
