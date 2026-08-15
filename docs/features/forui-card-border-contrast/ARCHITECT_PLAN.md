# ARCHITECT_PLAN — bug/forui-card-border-contrast

**Branch:** `feature/forui-card-consolidation` (existing — additional commits on top of WIP)  
**Date:** 2026-08-15  
**Architect:** AI Agent

---

## Problem Summary

Cards currently render borders using `BrandColors.dark.border` (`#27272A`, opaque zinc-800) or explicit per-widget color overrides. This color has nearly identical lightness to the card surface (`#18181B`) — result is low contrast, borders are barely visible.

Forui's own design system provides `FColors.neutralDark.border` (`Color(0x1AFFFFFF)`, translucent white overlay) for exactly this purpose — it's the canonical theme-consistent card border token. BandRoadie's card widgets should **consume this value live from Forui's theme** rather than using a hardcoded BrandColors duplicate.

**Affected cards:**

- All cards via `AppCard` when no explicit `border:` override is passed
- 4 cards currently pass explicit borders: `SongCard`, `ReorderableSongCard`, `MemberCard`, `MemberCardSkeleton`

---

## Feature Input Validation

**Feature Identifier:** `bug/forui-card-border-contrast`  
**Type:** bug  
**Slug:** `forui-card-border-contrast`  
**Branch:** `feature/forui-card-consolidation` (exists, confirmed via `git branch --show-current`)  
**Docs Path:** `<PROJECT_ROOT>/docs/features/forui-card-border-contrast/ARCHITECT_PLAN.md`

✅ Valid

---

## Root Cause

**Confidence Level:** HIGH

BandRoadie's `AppCard` widget defaults to no border when the `border:` parameter is omitted. Call sites that want a visible border must explicitly pass `border: Border.all(color: ...)`, which leads to two failure modes:

1. **Hardcoded BrandColors.dark.border** — opaque `#27272A`, nearly same lightness as surface `#18181B`, low contrast
2. **No border at all** — when call sites don't pass explicit border, cards have no separation from background

**Evidence (confirmed via code inspection):**

- `lib/components/ui/app_card.dart` line 13-18: `AppCard` accepts optional `BoxBorder? border` param, but does not default to any border when omitted
- `lib/app/theme/brand_colors.dart` line 53: `BrandColors.dark.border` is `Color(0xFF27272A)` — opaque, low contrast
- `package:forui/src/theme/colors.dart` line 73 (Forui v0.25.0): `FColors.neutralDark.border` is `Color(0x1AFFFFFF)` — translucent white, visible contrast
- `lib/app/theme/app_theme.dart` line 620: `foruiTheme()` does NOT override `border` in its `colors.copyWith(...)` call — Forui's own border token flows through unchanged

**Why this happened:**

During the forui-card-consolidation feature, cards were migrated from raw `Container()` widgets to `AppCard` (Forui's `FCard` wrapper). The migration preserved explicit border colors from prior implementations rather than deferring to Forui's theme system. The assumption was that all color decisions should route through `BrandColors`, but border specifically is a case where Forui's translucent overlay token provides objectively better contrast.

---

## Diagnosis

**Current behavior:**

1. `AppCard` with no `border:` param → renders with no border at all (Forui's default `FCard` has no border)
2. `AppCard` with `border: Border.all(color: BrandColors.dark.border, ...)` → renders opaque zinc-800 border, barely visible
3. 4 cards pass explicit rose or slate borders for brand accent — those are deliberate design decisions, not bugs

**Data flow (current):**

```
AppCard (no border param)
  → FCard (no border override in StyleDelta)
    → No border rendered

AppCard(border: Border.all(color: BrandColors.dark.border))
  → FCard(style: FCardStyleDelta with explicit border)
    → Renders opaque zinc-800 border (low contrast)
```

**Root cause layer:** Widget API design — `AppCard` does not provide a theme-aware default border

---

## Reference Docs Consulted

- `package:forui/src/theme/colors.dart` — Confirmed `FColors.neutralDark.border` is `Color(0x1AFFFFFF)`, `neutralLight.border` is `Color(0xFFE5E5E5)`
- `lib/app/theme/app_theme.dart` line 608-633 — Confirmed Forui's `foruiTheme()` does not override border in `colors.copyWith()` call
- `lib/app/theme/brand_colors.dart` line 53, 77 — Confirmed `BrandColors.dark.border` is `#27272A` (opaque, low contrast), `light.border` is `#E4E4E7` (close to Forui's `#E5E5E5`, acceptable)
- `lib/components/ui/app_card.dart` — Confirmed `AppCard` structure, `border` param is optional `BoxBorder?`, no theme default

---

## Database Impact

**Not applicable** — UI-only change, no database schema, RLS, RPC, or trigger modifications.

---

## System Impact

| System                       | Impact                                                                                                           |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Setlists / Catalog           | **Affected** — `SongCard`, `ReorderableSongCard` accent borders (rose/slate) removed, now use Forui theme border |
| Members / RBAC               | **Affected** — `MemberCard` accent border (rose) removed, now uses Forui theme border                            |
| Gigs / Rehearsals / Calendar | **Unaffected** — Event cards use separate styling, not `AppCard`                                                 |
| Auth / Session               | **Unaffected**                                                                                                   |
| Routing                      | **Unaffected**                                                                                                   |

---

## Proposed Solution

### Step 1: Add theme-aware default border to `AppCard`

**File:** `lib/components/ui/app_card.dart`

**Change:** When no `border:` param is passed, default to Forui's theme border token read via `FTheme.of(context).colors.border`.

**Implementation approach:**

```dart
@override
Widget build(BuildContext context) {
  // Read Forui's theme border color
  final themeBorderColor = context.theme.colors.border;

  // Use explicit border if provided, otherwise default to theme border
  final effectiveBorder = border ?? Border.all(color: themeBorderColor, width: 1);

  // Build StyleDelta if padding, borderRadius, or border override provided
  final styleDelta = (padding != null || borderRadius != null || effectiveBorder != null)
      ? FCardStyleDelta.delta(
          padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
          decoration: (borderRadius != null || effectiveBorder != null)
              ? DecorationDelta.boxDelta(
                  borderRadius: borderRadius,
                  border: effectiveBorder,
                )
              : null,
        )
      : null;

  // ... rest of widget build
}
```

**Rationale:**

- Cards without explicit color accents should defer to Forui's theme system, not hardcode BrandColors
- Forui's `neutralDark.border` (`0x1AFFFFFF`) provides objectively better contrast than `BrandColors.dark.border` (`0xFF27272A`)
- Forwards-compatible: if Forui's border token changes upstream, BandRoadie's cards automatically follow
- Light mode already acceptable: Forui's `neutralLight.border` (`#E5E5E5`) is close to `BrandColors.light.border` (`#E4E4E7`), no regression risk

### Step 2: Remove all explicit accent borders from cards

**Scope expansion from Tony:** All cards should use consistent Forui theme border, no colored accent borders. This includes removing the rose/slate borders that previously distinguished Catalog (rose) from regular setlists (slate).

**Accepted tradeoff:** The Catalog setlist will temporarily lose its visual distinction at the card level (previously signaled by rose border vs slate border on regular setlists). Tony has confirmed this is acceptable — he will implement a separate visual cue for the Catalog card as its own follow-up feature. Do not attempt to design a replacement cue as part of this fix.

**Cards to fix:**

1. **`SongCard`** (lib/features/setlists/widgets/song_card.dart line 113):
   - Remove: `border: Border.all(color: AppColors.primary, width: 1.5)` — rose accent
   - Let `AppCard` default to Forui's theme border

2. **`ReorderableSongCard`** (lib/features/setlists/widgets/reorderable_song_card.dart line 22-23):
   - Remove: `border: Border.all(color: StandardCardBorder.color, width: 1.5)` — slate accent
   - Let `AppCard` default to Forui's theme border

3. **`MemberCard`** (lib/features/members/widgets/member_card.dart line 90-93):
   - Remove: `border: Border.all(color: _MemberCardTokens.borderRose, width: 2.0)` — rose accent
   - Let `AppCard` default to Forui's theme border

4. **`MemberCardSkeleton`** (lib/features/members/widgets/member_card_skeleton.dart line 48):
   - Remove: `border: Border.all(color: context.colors.border.withValues(alpha: 0.3))` — low-contrast BrandColors border
   - Let `AppCard` default to Forui's theme border

### Step 3: Update call sites that currently pass `BrandColors.dark.border`

**Search scope:** All files that import `AppCard` and pass `border:` param with BrandColors reference

**Expected findings (based on grep_search results):**

- `MemberCardSkeleton` — confirmed above, will be fixed
- Any other cards using `AppCard` with `border: Border.all(color: context.colors.border)` should be reviewed

**Action:** Remove `border:` param from these call sites, let `AppCard` default apply

---

## Files to Modify

| File                                                       | Change Description                                                                                                                                                          |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_card.dart`                          | Add theme-aware default border: read `FTheme.of(context).colors.border`, apply as `Border.all(color: themeBorderColor, width: 1)` when no explicit `border:` param provided |
| `lib/features/setlists/widgets/song_card.dart`             | Remove explicit `border:` param (rose accent, line ~113), let `AppCard` default apply                                                                                       |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Remove explicit `border:` param (slate accent, line ~22-23), let `AppCard` default apply                                                                                    |
| `lib/features/members/widgets/member_card.dart`            | Remove explicit `border:` param (rose accent, line ~90-93), let `AppCard` default apply                                                                                     |
| `lib/features/members/widgets/member_card_skeleton.dart`   | Remove explicit `border:` param (line ~48), let `AppCard` default apply                                                                                                     |

---

## Flutter Architecture Changes

**Widget API change:**

- `AppCard.border` param changes from "no default" to "defaults to Forui's theme border"
- This is a non-breaking change — existing call sites that pass explicit `border:` param are unaffected
- Call sites that omit `border:` will now get a visible border (desirable — fixes contrast issue)

**Theme dependency:**

- `AppCard` now reads `FTheme.of(context).colors.border` in its build method
- This is safe — all `AppCard` usage is within the `FTheme` InheritedWidget scope (set up in `lib/main.dart` line 156)
- No new dependencies required

**Forui accessor pattern:**

- Use `context.theme.colors.border` to read Forui's FColors from BuildContext
- This is the standard Forui extension method (available via `package:forui/forui.dart` export)
- Mirrors the existing `context.colors` pattern used for `BrandColors` theme extension

---

## Testing Strategy

**Manual QA (primary validation):**

1. **Visual regression check:**
   - Open setlist detail screen (Catalog setlist)
   - Confirm song cards render with neutral Forui theme border (rose accent border removed)
   - Open non-Catalog setlist (e.g., "Test Setlist")
   - Confirm reorderable song cards render with neutral Forui theme border (slate accent border removed)
   - Confirm both Catalog and regular setlist cards now have consistent border styling

2. **Member cards:**
   - Open Members tab
   - Confirm member cards render with neutral Forui theme border (rose accent border removed)
   - Trigger loading state to show skeleton cards
   - Confirm skeleton borders are visible and match visual weight of real cards

3. **Theme consistency:**
   - Verify all card borders use consistent Forui neutral palette color
   - No jarring color mismatches between Forui widgets and custom cards
   - Border contrast is clearly visible against card surface

**Automated tests:**

Not required — this is a visual styling fix, no business logic change. Widget tests would only verify that `AppCard` passes a border to `FCard`, which is not a meaningful assertion.

---

## QA Regression Areas

**High priority:**

- **Setlist cards** — song cards must render neutral Forui theme borders (rose/slate accent borders removed), borders must be clearly visible
- **Member cards** — member cards must render neutral Forui theme borders (rose accent border removed), skeleton loading must show borders

**Medium priority:**

- **Light mode** — if light mode is ever enabled, confirm Forui's `neutralLight.border` renders acceptably (expected to be fine based on color values)

**Low priority:**

- **Other `AppCard` usages** — any other screens that use `AppCard` (currently rare) should be spot-checked for visual regressions

---

## Engineer Task Breakdown

### Task 1: Update `AppCard` to default to Forui theme border

**File:** `lib/components/ui/app_card.dart`

**Steps:**

1. In `build()` method, before building `styleDelta`, read Forui's theme border:

   ```dart
   final themeBorderColor = context.theme.colors.border;
   ```

2. Compute effective border (explicit param takes precedence, otherwise default to theme):

   ```dart
   final effectiveBorder = border ?? Border.all(color: themeBorderColor, width: 1);
   ```

3. Update `styleDelta` condition to always include border (since we now have a default):

   ```dart
   final styleDelta = (padding != null || borderRadius != null)
       ? FCardStyleDelta.delta(
           padding: padding != null ? EdgeInsetsGeometryDelta.value(padding!) : null,
           decoration: (borderRadius != null || effectiveBorder != null)
               ? DecorationDelta.boxDelta(
                   borderRadius: borderRadius,
                   border: effectiveBorder,
                 )
               : null,
         )
       : null;
   ```

   Wait — this logic needs refinement. If no padding, no borderRadius, but we have a default border, we still need to build a StyleDelta. Correct logic:

   ```dart
   final styleDelta = (padding != null || borderRadius != null || effectiveBorder != null)
       ? FCardStyleDelta.delta(...)
       : null;
   ```

4. Add inline comment explaining the default:
   ```dart
   // Default to Forui's theme border for consistent contrast across all cards
   // (translucent white in dark mode, opaque gray in light mode). Call sites
   // can override with explicit border: param for brand accents (e.g. rose).
   final effectiveBorder = border ?? Border.all(color: themeBorderColor, width: 1);
   ```

**Validation:**

- No compile errors
- `flutter analyze` passes
- Visual check: cards now have visible borders

### Task 2: Remove explicit border from `SongCard`

**File:** `lib/features/setlists/widgets/song_card.dart`

**Steps:**

1. Find `AppCard` invocation (line ~108-118)
2. Remove the `border:` parameter and its value: `Border.all(color: AppColors.primary, width: StandardCardBorder.width)`
3. Remove the comma after `borderRadius: BorderRadius.circular(Spacing.buttonRadius),` if border was the last param

**Validation:**

- No compile errors
- Visual check: Catalog song cards now render with neutral Forui theme border (rose accent removed)

### Task 3: Remove explicit border from `ReorderableSongCard`

**File:** `lib/features/setlists/widgets/reorderable_song_card.dart`

**Steps:**

1. Find `AppCard` invocation (location varies, search for `AppCard(` in the file)
2. Remove the `border:` parameter and its value: `Border.all(color: StandardCardBorder.color, width: StandardCardBorder.width)`
3. Update or remove the comment "Border: StandardCardBorder (#334155) 1.5px" if present

**Validation:**

- No compile errors
- Visual check: reorderable song cards now render with neutral Forui theme border (slate accent removed)

### Task 4: Remove explicit border from `MemberCard`

**File:** `lib/features/members/widgets/member_card.dart`

**Steps:**

1. Find `AppCard` invocation (line ~88-95)
2. Remove the `border:` parameter and its value: `Border.all(color: _MemberCardTokens.borderRose, width: _MemberCardTokens.borderWidth)`

**Validation:**

- No compile errors
- Visual check: member cards now render with neutral Forui theme border (rose accent removed)

### Task 5: Remove explicit border from `MemberCardSkeleton`

**File:** `lib/features/members/widgets/member_card_skeleton.dart`

**Steps:**

1. Find `AppCard` invocation (line ~48)
2. Remove `border: Border.all(color: context.colors.border.withValues(alpha: 0.3))` line
3. Verify skeleton card still renders with visible border (now from `AppCard` default)

**Validation:**

- No compile errors
- Visual check: skeleton border is visible and matches real card visual weight

### Task 6: Search for other `AppCard` usages with explicit borders

**Command:**

```bash
rg -i "AppCard.*border.*context\.colors\.border" lib/
```

**Expected:** No additional matches beyond the 4 cards already handled

**If additional matches found:** Review each for intent (accent vs theme border), fix if appropriate

### Task 7: Verify no regressions

**Platforms:** macOS (primary), iOS (if available)

**Screens to check:**

- Setlist detail (Catalog and non-Catalog)
- Members tab (real cards and loading skeletons)
- Any other screens using `AppCard` (search for `AppCard(` in codebase)

**Pass criteria:**

- All cards have visible borders
- All cards use consistent neutral Forui theme border color
- Rose accent borders (song cards, member cards) removed
- Slate accent borders (reorderable song cards) removed
- No jarring color mismatches, all borders clearly visible against card surface

---

## Acceptance Criteria

✅ **All criteria must pass before commit:**

1. `AppCard` defaults to Forui's theme border (`FTheme.of(context).colors.border`) when no explicit `border:` param is provided
2. `SongCard` renders with neutral Forui theme border (rose accent border removed)
3. `ReorderableSongCard` renders with neutral Forui theme border (slate accent border removed)
4. `MemberCard` renders with neutral Forui theme border (rose accent border removed)
5. `MemberCardSkeleton` renders with visible border matching real card visual weight
6. All card borders are clearly visible and consistent across the app
7. `flutter analyze` passes with 0 errors
8. Visual QA confirms all cards use consistent neutral borders, no regressions to visibility or contrast

---

## Risk Assessment

**Overall Risk:** LOW

**Rationale:**

- Focused scope (5 files modified — 1 widget base + 4 card implementations)
- No business logic changes
- Non-breaking API change (explicit borders still work, new default only affects call sites that omitted border)
- Forui's border token is well-tested (part of Forui's core design system)
- Change is easily reversible if visual issues arise
- Improves visual consistency across all cards

**Mitigation:**

- If Forui's border color proves unacceptable in production, can revert and file separate issue to tune Forui's theme override in `app_theme.dart`
- Light mode impact is low risk (Forui's `neutralLight.border` is already close to `BrandColors.light.border`)

---

## Additional Context

**Why not override Forui's border in `app_theme.dart`?**

Tony's explicit requirement: "consume Forui's real border token live from the theme, not a copied/hardcoded value." Overriding Forui's border in `foruiTheme()` would defeat this purpose — the goal is to stay wired to Forui's design system, not duplicate it.

**What about other BrandColors tokens (background, surface, text)?**

Feature input explicitly scopes this fix to borders only. Background/surface alignment between BrandColors and Forui was noted as "already closely aligned" and intentionally out of scope. If future cycles need broader palette alignment, that's a separate feature.

**Why width: 1 for the default border?**

Forui's default `FCard` has no border, so there's no "canonical" Forui border width. Width 1 is standard for subtle borders. Previously, cards used 1.5px or 2px borders to emphasize accent colors — with accent colors removed, the standard 1px width is appropriate for neutral borders.

**Why remove accent borders?**

Tony explicitly requested scope expansion to remove all colored accent borders for consistent theming. The Catalog vs regular setlist distinction (previously signaled by rose vs slate borders) is temporarily lost, but Tony has confirmed this is acceptable and will implement a separate visual cue as a follow-up feature.

---

**Architect:** AI Agent  
**Date:** 2026-08-15  
**Status:** Ready for Engineer
