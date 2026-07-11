# Architect Plan — Gig Drawer Navigate Icon

## Feature Slug

`bug/gig-drawer-navigate-icon`

---

## Problem Summary

The Navigate icon in the gig detail drawer (`ViewGigDrawer`) does not display in the expected rose accent color. The icon is present in the widget tree but renders in the default theme color (white/`textPrimary`) instead of rose (`AppColors.primary`), making it inconsistent with the design specification and potentially low-contrast or invisible depending on the background.

**User Report:** Icon is "missing" or "not visible" on web platform.

**Design Specification:** Icon should render in rose accent color (`AppColors.primary` / `#BE123C`).

---

## Root Cause

**Confidence:** HIGH

**Diagnosis:**
The Icon widget at line 310 of `lib/features/gigs/widgets/view_gig_drawer.dart` is constructed without a `color` parameter:

```dart
icon: const Icon(LucideIcons.navigation2),
```

The `color: AppColors.primary` property on the `IconButton` (line 311) does **not** color the icon itself. In Flutter, the `color` property on `IconButton` affects the button's splash/overlay color, not the icon widget. To color the icon, the color must be passed directly to the `Icon` constructor.

**Confirmed by:**

1. Direct code observation (line 310 has no color parameter)
2. Flutter `IconButton` API documentation (color property is for overlay, not icon)
3. Codebase pattern analysis: 5 other files correctly pass `color: AppColors.primary` to the Icon constructor (bug_report_screen.dart, my_profile_screen.dart, profile_screen.dart, settings_screen.dart, tips_and_tricks_screen.dart)
4. Previous feature `gig-cosmetic-polish` added the rose border styling but did not address the icon color

**Why It Fails:**
Without an explicit color parameter, the Icon inherits from `ThemeData.iconTheme`, which is configured to use `bc.textPrimary` (white in dark mode, dark in light mode). The design specification requires rose (`AppColors.primary`).

---

## Reference Docs Consulted

**Gig Domain:**
No reference docs exist in `docs/reference/` for gigs/events. This is a UI rendering bug requiring only codebase inspection.

**UI/Theme Reference:**

- `lib/app/theme/app_theme.dart` — confirmed default `iconTheme` uses `bc.textPrimary`
- `lib/app/theme/design_tokens.dart` — confirmed `AppColors.primary` is `const Color(0xFFBE123C)` (rose-700)
- `lib/app/theme/brand_colors.dart` — confirmed theme structure

**Previous Feature Context:**

- `docs/features/gig-cosmetic-polish/ARCHITECT_PLAN.md` — added rose border to IconButton but did not fix icon color
- `docs/features/view-gig-drawer-polish/ARCHITECT_PLAN.md` — referenced the navigation button but did not address icon color

---

## Existing System Analysis

**Current Behavior:**

1. User opens gig detail drawer by tapping a gig from the gigs list
2. `ViewGigDrawer` renders with gig details and a Navigate IconButton (line 309-324)
3. The IconButton renders with:
   - A rose border (`side: BorderSide(color: AppColors.primary)`) — added in `gig-cosmetic-polish`
   - An icon that inherits the theme's default color (`bc.textPrimary`, which is white in dark mode)
   - Expected: icon should be rose (`AppColors.primary`)
   - Actual: icon is white (or theme default), creating either low contrast or invisible appearance depending on background

**Data Flow:**
This is a pure UI rendering issue. No data flow, state management, or business logic is involved. The icon color is determined at widget construction time based on the Icon widget's color parameter (or lack thereof).

**Failure Point:**
Icon construction at line 310 — missing `color` parameter causes theme fallback instead of explicit rose.

---

## Proposed Solution

**Minimal Fix:**
Modify line 310 in `lib/features/gigs/widgets/view_gig_drawer.dart` to add the `color` parameter to the Icon constructor.

**Change:**

```dart
// Before
icon: const Icon(LucideIcons.navigation2),

// After
icon: const Icon(LucideIcons.navigation2, color: AppColors.primary),
```

**Why This Works:**

- `AppColors.primary` is defined as `const Color(0xFFBE123C)`, allowing use in const constructor
- Passing color directly to Icon() overrides the theme default
- Matches established codebase pattern (5 other files use this pattern)
- `AppColors` is already imported at line 9 via `design_tokens.dart`

**No Other Changes Required:**

- IconButton properties (`color`, `iconSize`, `onPressed`, `tooltip`, `style`) remain unchanged
- Border styling (added in `gig-cosmetic-polish`) remains unchanged
- Navigation logic (`_openNavigation` method) remains unchanged
- No imports added/removed

---

## Database Impact

**Database:** Not applicable

This is a pure UI rendering bug in Flutter widget construction. No migrations, RLS policies, RPC functions, or database triggers are involved.

---

## Flutter Architecture Changes

**State Management:** No changes

**Widgets Modified:**

- `lib/features/gigs/widgets/view_gig_drawer.dart` — single-line change to Icon color parameter

**Repositories:** No changes

**Controllers:** No changes

**Theme/Design Tokens:** No changes (using existing `AppColors.primary` constant)

---

## Files to Create

**None**

---

## Files to Modify

| File                                             | Changes                                                                                           |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Line 310: Add `color: AppColors.primary` parameter to `Icon(LucideIcons.navigation2)` constructor |

---

## Files Off-Limits

| File                                                       | Reason                                                                                |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `lib/main.dart`                                            | Initialization order must not change                                                  |
| `lib/app/theme/app_theme.dart`                             | Theme-level iconTheme is intentional and affects global icon defaults — do not modify |
| `lib/app/theme/design_tokens.dart`                         | No color constant changes required — AppColors.primary already correct                |
| `lib/app/theme/brand_colors.dart`                          | No theme extension changes required                                                   |
| `lib/features/gigs/gig_controller.dart`                    | No controller logic affected                                                          |
| `lib/features/gigs/gig_repository.dart`                    | No data access affected                                                               |
| `lib/features/gigs/widgets/gig_notes_sheet.dart`           | Not related to navigate icon                                                          |
| `lib/features/gigs/widgets/availability_prompt_modal.dart` | Not related to navigate icon                                                          |

---

## System Impact Map

| System                                 | Impact                                                                                          |
| -------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Gigs                                   | **affected** — ViewGigDrawer navigate icon color changes from theme default to rose             |
| Rehearsals                             | unaffected                                                                                      |
| Setlists / Catalog                     | unaffected                                                                                      |
| Members / RBAC                         | unaffected                                                                                      |
| Auth / Session                         | unaffected                                                                                      |
| Routing                                | unaffected                                                                                      |
| Notifications                          | unaffected                                                                                      |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms share ViewGigDrawer widget; fix applies universally (not web-only) |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- **Single-line change** in a leaf UI widget — no logic, state, or data flow affected
- **No database writes** — pure presentation layer
- **No navigation changes** — button onPressed handler unchanged
- **No auth/session/routing changes** — gated areas untouched
- **No theme changes** — using existing color constant
- **No controller/repository changes** — no state management affected
- **No new dependencies** — AppColors already imported
- **No initialization order changes** — widget construction only

**Observable Change:**
Navigate icon color changes from white (theme default) to rose (design spec). This is a **correction**, not a regression. The icon's border is already rose (from `gig-cosmetic-polish`), so this change unifies the icon color with its border for visual consistency.

**Potential Visual Regression:**
None. The change moves the icon from an unintended color (theme default) to the intended color (rose), matching the documented design specification and the existing border styling.

---

## Engineer Task Breakdown

### Task 1 — Update Navigate Icon Color

**File:** `lib/features/gigs/widgets/view_gig_drawer.dart`

**Location:** Line 310

**Action:** Add `color: AppColors.primary` parameter to the Icon constructor.

**Before:**

```dart
                            IconButton(
                              icon: const Icon(LucideIcons.navigation2),
                              color: AppColors.primary,
                              iconSize: 20,
```

**After:**

```dart
                            IconButton(
                              icon: const Icon(LucideIcons.navigation2, color: AppColors.primary),
                              color: AppColors.primary,
                              iconSize: 20,
```

**Notes:**

- `AppColors.primary` is const, so the Icon constructor can remain const
- No import changes required — `AppColors` is already imported via `design_tokens.dart` (line 9)
- Do not modify any other IconButton properties (color, iconSize, onPressed, tooltip, style)

---

## Verification Plan

### Tier 1 — Pre-Deployment (Flutter Analyze + Manual Visual Check)

**PRE-DEPLOY TEST 1: Flutter analyze passes with 0 errors**

```bash
flutter analyze
```

Expected: No errors, no warnings related to the modified file.

**PRE-DEPLOY TEST 2: Visual inspection — Icon renders in rose**

1. Run app on web:

   ```bash
   flutter run -d chrome
   ```

2. Navigate to Gigs → tap any gig to open detail drawer

3. Verify Navigate icon:
   - Icon is visible
   - Icon color is rose (`#BE123C` — matches the border color)
   - Icon size is 20px (unchanged)
   - Border is rose with rounded corners (unchanged from `gig-cosmetic-polish`)

4. Tap Navigate icon → verify navigation logic still works (opens map picker or launches default map app)

**PRE-DEPLOY TEST 3: Visual inspection — Other platforms**

Repeat PRE-DEPLOY TEST 2 on:

- macOS: `flutter run -d macos`
- iOS simulator (if available): `flutter run -d ios`

Confirm icon color is rose on all platforms (not just web).

---

### Tier 2 — Post-Deployment (Production Verification)

**POST-DEPLOY TEST 1: Production web visual check**

After deploying to production (`./tools/deploy_web.sh`):

1. Open production web app in incognito: `https://bandroadie.com`
2. Log in
3. Navigate to Gigs → open any gig detail drawer
4. Confirm Navigate icon is visible and rose-colored

**POST-DEPLOY TEST 2: Cross-browser verification (web only)**

Test on:

- Chrome (desktop + mobile viewport)
- Safari (desktop + mobile)
- Firefox (desktop)

Confirm icon renders consistently in rose across all browsers.

---

## QA Regression Areas

### Primary Validation

1. **Navigate icon color:** Icon must render in rose (`AppColors.primary`) on all platforms
2. **Navigate icon visibility:** Icon must be visible (not transparent, not size 0, not hidden)
3. **Navigate functionality:** Tapping icon must open navigation (map picker or default map app)

### Cross-Feature Regression

4. **Gig drawer layout:** No layout shifts or spacing changes
5. **IconButton border:** Rose border from `gig-cosmetic-polish` must remain intact
6. **Other gig drawer elements:** Venue name, location text, date/time, setlist link, notes — all unchanged
7. **Other IconButtons in app:** Verify no global theme changes affected other screens (spot-check back buttons on Settings, Profile screens)

### Platform-Specific

8. **Web:** Icon visible and rose on Chrome, Safari, Firefox
9. **Native (iOS/Android/macOS):** Icon visible and rose (if testable)

---

## Rollout / Migration Strategy

**Not applicable**

This is a pure client-side UI change with no database or backend dependencies. Deploy follows standard web deployment:

```bash
./tools/deploy_web.sh
```

No migration required. No edge function changes. No Supabase schema changes.

---

## Out of Scope

The following are explicitly **not** part of this fix:

1. **Navigation logic changes:** The `_openNavigation` method, platform-specific URI building, and map app picker remain unchanged
2. **Icon size changes:** iconSize remains 20 (do not modify)
3. **IconButton styling changes:** Border, shape, tooltip remain unchanged (border was added in `gig-cosmetic-polish`)
4. **Other icons in ViewGigDrawer:** No other icons exist in this widget — this is the only icon
5. **Global icon theme changes:** Do not modify `lib/app/theme/app_theme.dart` iconTheme — this fix is local to one Icon widget
6. **Accessibility improvements:** Tooltip is already present (`tooltip: 'Navigate'`) — no additional a11y work
7. **Design system documentation:** No new design tokens or patterns introduced — using existing `AppColors.primary`

---

**Engineer:** Implement Task 1 exactly as specified. Run Tier 1 verification tests. Report completion with visual confirmation (screenshot acceptable).

**QA:** Execute Tier 2 post-deployment tests and QA regression checks. Confirm Navigate icon is rose on all tested platforms and browsers.
