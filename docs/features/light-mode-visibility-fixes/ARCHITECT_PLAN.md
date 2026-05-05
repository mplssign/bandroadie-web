# ARCHITECT PLAN

## Feature: light-mode-visibility-fixes

---

## 1. Feature Slug

`feature/light-mode-visibility-fixes`

**Docs path:** `docs/features/light-mode-visibility-fixes/ARCHITECT_PLAN.md`
**Branch:** `main` (no active feature branch — workspace clean except unrelated working files)

---

## 2. Problem Summary

Multiple UI elements are invisible or have poor contrast when the app runs in light mode. Two distinct categories:

**Category A — Elements hardcoded to near-white colors** (invisible on light backgrounds):

- Gig name in Upcoming Gigs card: hardcoded `Color(0xFFFFF1F2)` (near-white rose)
- Setlist card name: hardcoded `Color(0xFFFFF1F2)` (near-white rose)
- Tips & Tricks section header titles: hardcoded `Colors.white`

**Category B — Navigation bars render as transparent/white glass** (no visible distinction, icons/labels become invisible):

- `GlassSurface` and `FrostedGlassBar` use `context.colors.appBarBg` as their tint color
- `BrandColors.light.appBarBg = Color(0xFFFFFFFF)` → white tint at 10–25% opacity ≈ no visual effect
- Result: nav bars appear transparent/white with no contrast against the white scaffold background
- Icons and labels designed for dark glass (white text) become dark-on-white when the theme provides `textPrimary = Color(0xFF18181B)` in light mode
- Band name is hardcoded to `Color(0xFF334155)` (dark slate) — designed for dark glass, invisible issue when background matches

**Category C — AppBar title text on dark backgrounds** (ripple effect of the appBarBg fix):

- Several screens explicitly set `backgroundColor: context.colors.appBarBg` AND use `context.colors.textPrimary` for the title text color
- After correcting `appBarBg` to dark gray, these titles would be dark text on dark background = invisible
- Must be remediated alongside the root fix

**Category D — Gray text in light mode content areas:**

- Tip body text uses `context.colors.textSecondary` = `Color(0xFF52525B)` (zinc-600 gray) in light mode
- Setlist card metadata text inherits gray from the theme's `bodyMedium` (`textSecondary` color)

---

## 3. Root Cause (per fix area)

| Fix                                   | Root Cause                                                                                                                                                                                    | Confidence |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| 1, 4 — Nav bar backgrounds            | `BrandColors.light.appBarBg = Color(0xFFFFFFFF)` → GlassSurface/FrostedGlassBar tint provides no contrast                                                                                     | HIGH       |
| 2, 3 — Hamburger icon, band name      | Icons use `context.colors.textPrimary` (dark in light mode) on a nav bar that should be dark; band name hardcoded `Color(0xFF334155)` (dark slate)                                            | HIGH       |
| 5 — Unselected bottom nav tabs        | `_AnimatedNavItem` unselected color = `context.colors.textSecondary` = gray on a dark-glass nav bar                                                                                           | HIGH       |
| 7 — Gig name                          | `confirmed_gig_card.dart` hardcodes `Color(0xFFFFF1F2)` (near-white rose). Card container has no explicit background → inherits white scaffold bg                                             | HIGH       |
| 8, 9, 10 — Setlist card text + border | `setlist_card.dart` hardcodes `Color(0xFFFFF1F2)` for name; `StandardCardBorder.color = Color(0xFF334155)` per design_tokens.dart; metadata inherits gray from ThemeData.textTheme.bodyMedium | HIGH       |
| 11 — Page titles                      | `AppBarTheme.titleTextStyle.color = bc.textPrimary` (dark in light); screens that use explicit `context.colors.textPrimary` for title will be dark-on-dark after `appBarBg` fix               | MEDIUM     |
| 12 — Tips & Tricks section headers    | Hardcoded `color: Colors.white`                                                                                                                                                               | HIGH       |
| 13 — Gray text                        | `context.colors.textSecondary = Color(0xFF52525B)` in light mode (zinc-600 = readable gray, but design intends black)                                                                         | HIGH       |

---

## 4. Reference Docs Consulted

- `lib/app/theme/design_tokens.dart` — `AppColors`, `StandardCardBorder`, `AppTextStyles`
- `lib/app/theme/brand_colors.dart` — `BrandColors.dark` and `BrandColors.light` definitions
- `lib/app/theme/app_theme.dart` — `darkTheme` and `lightTheme` getters, all theme component overrides
- `lib/features/home/widgets/home_app_bar.dart`
- `lib/features/home/widgets/animated_bottom_nav_bar.dart`
- `lib/features/setlists/widgets/setlists_app_bar.dart`
- `lib/features/setlists/widgets/back_only_app_bar.dart`
- `lib/features/home/widgets/confirmed_gig_card.dart`
- `lib/features/setlists/widgets/setlist_card.dart`
- `lib/features/tips/tips_and_tricks_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/profile/my_profile_screen.dart`
- `lib/features/setlists/create_setlist_screen.dart`
- `lib/features/setlists/new_setlist_screen.dart`
- `lib/features/bands/band_form_screen.dart`
- `lib/components/ui/frosted_glass_bar.dart`
- `lib/shared/widgets/glass_surface.dart`

---

## 5. Existing System Analysis

### 5.1 Color Palette Relevant to This Feature

**`BrandColors.dark` (partial):**

```
background:       Color(0xFF09090B)  // zinc-950
surface:          Color(0xFF18181B)  // zinc-900
surfaceElevated:  Color(0xFF27272A)  // zinc-800
textPrimary:      Color(0xFFFAFAFA)  // near-white
textSecondary:    Color(0xFFA1A1AA)  // zinc-400 gray
appBarBg:         Color(0xFF09090B)  // zinc-950
```

**`BrandColors.light` (partial):**

```
background:       Color(0xFFFFFFFF)  // white
surface:          Color(0xFFFAFAFA)  // near-white
textPrimary:      Color(0xFF18181B)  // near-black
textSecondary:    Color(0xFF52525B)  // zinc-600 gray
appBarBg:         Color(0xFFFFFFFF)  // white ← ROOT CAUSE for nav bars
```

**`AppColors` (design_tokens.dart):**

```
primary:    Color(0xFFBE123C)  // rose-700
error:      Color(0xFFEF4444)  // red-500
blueAccent: Color(0xFF2563EB)  // blue-600
```

Note: `AppColors` has no dark gray. Dark grays reside in `BrandColors.dark.*`. The appropriate value for the light-mode nav bar dark gray is `Color(0xFF18181B)` (zinc-900, already defined as `BrandColors.dark.surface`).

### 5.2 GlassSurface Tint Mechanism

`GlassSurface` builds its background color as:

```dart
final bgColor = (tintColor ?? context.colors.appBarBg).withValues(alpha: tintOpacity);
```

`tintOpacity` ranges from `0.10` (at rest) to `0.25` (scrolled). With `appBarBg = white`, white at 10–25% = visually transparent. With `appBarBg = Color(0xFF18181B)`, dark zinc-900 at 10–25% = visually dark frosted glass.

### 5.3 AppBarTheme in Light Theme (current state)

```dart
AppBarTheme(
  backgroundColor: bc.background,  // Color(0xFFFFFFFF)
  foregroundColor: bc.textPrimary,  // Color(0xFF18181B) - dark
  titleTextStyle: TextStyle(
    color: bc.textPrimary,          // Color(0xFF18181B) - dark
    fontSize: 20,
    fontWeight: FontWeight.w600,
  ),
  iconTheme: IconThemeData(color: bc.primary),  // rose
)
```

### 5.4 Current Nav Bar Element Colors

| Element              | Widget                                       | Current Color                       | In Light Mode     | Issue                       |
| -------------------- | -------------------------------------------- | ----------------------------------- | ----------------- | --------------------------- |
| Top nav bg           | GlassSurface                                 | `context.colors.appBarBg` at 10-25% | White/transparent | No contrast                 |
| Hamburger icon       | `home_app_bar.dart`                          | `context.colors.textPrimary`        | `0xFF18181B` dark | Dark on dark (after bg fix) |
| Band name            | `home_app_bar.dart`, `setlists_app_bar.dart` | `const Color(0xFF334155)`           | Dark slate        | Dark on dark (after bg fix) |
| Bottom nav bg        | GlassSurface                                 | `context.colors.appBarBg` at 10-25% | White/transparent | No contrast                 |
| Unselected nav items | `animated_bottom_nav_bar.dart`               | `context.colors.textSecondary`      | `0xFF52525B` gray | Gray on dark (after bg fix) |

### 5.5 Current Content Element Colors

| Element               | Widget                        | Current Color                                  | In Light Mode            | Issue              |
| --------------------- | ----------------------------- | ---------------------------------------------- | ------------------------ | ------------------ |
| Gig name              | `confirmed_gig_card.dart`     | `const Color(0xFFFFF1F2)`                      | Near-white on white card | Invisible          |
| Setlist card name     | `setlist_card.dart`           | `const Color(0xFFFFF1F2)`                      | Near-white on white card | Invisible          |
| Setlist card metadata | `setlist_card.dart`           | No explicit color (inherits theme)             | `textSecondary` gray     | Gray               |
| Setlist card border   | `setlist_card.dart`           | `StandardCardBorder.color = Color(0xFF334155)` | Dark slate               | Not black per spec |
| Tips section headers  | `tips_and_tricks_screen.dart` | `Colors.white`                                 | White on white           | Invisible          |
| Tips body text        | `tips_and_tricks_screen.dart` | `context.colors.textSecondary`                 | `0xFF52525B` gray        | Gray               |

---

## 6. Proposed Solution

### Fix Layer Decision

**Option A — ThemeData change** is used for:

- `brand_colors.dart`: Change `BrandColors.light.appBarBg` — single value, fixes ALL `GlassSurface` and `FrostedGlassBar` nav bar backgrounds at once
- `app_theme.dart`: Update `AppBarTheme` in `lightTheme` — fixes ALL standard `AppBar` title text inherited from the theme

**Option B — Widget-level brightness check** is used for:

- Any widget where the current dark mode value differs from what light mode needs (to preserve dark mode behavior exactly)
- Hardcoded colors that are wrong only in light mode
- Icon/text that directly follows its container (nav bars always dark → always white, regardless of mode)

### Fix Strategy Per Area

#### 6.1 Nav Bar Background (Fixes 1 & 4)

**Layer:** ThemeData (`brand_colors.dart`)

**Change:** `BrandColors.light.appBarBg`: `Color(0xFFFFFFFF)` → `Color(0xFF18181B)`

`Color(0xFF18181B)` is zinc-900. This is already defined in the codebase as `BrandColors.dark.surface`. No new color definition introduced. This propagates to every component that calls `context.colors.appBarBg`:

- `GlassSurface` (used by HomeAppBar, SetlistsAppBar, BackOnlyAppBar, AnimatedBottomNavBar)
- `FrostedGlassBar` (used by band_form_screen.dart)
- `AppBarTheme.backgroundColor` after update in app_theme.dart (see 6.7)

**Dark mode impact:** None. `BrandColors.dark.appBarBg = Color(0xFF09090B)` is unchanged.

#### 6.2 Hamburger Menu Icon (Fix 2)

**Layer:** Widget-level — `home_app_bar.dart` and `setlists_app_bar.dart`

**Change:** Icon color `context.colors.textPrimary` → `Colors.white`

Rationale: Nav bar background is dark in BOTH light mode (after fix 6.1) and dark mode. White is correct in both modes. In dark mode, `textPrimary = Color(0xFFFAFAFA)` ≈ white — behavioral result unchanged.

#### 6.3 Band Name in Top Nav Bar (Fix 3)

**Layer:** Widget-level brightness check — `home_app_bar.dart` and `setlists_app_bar.dart`

**Current:** `const Color(0xFF334155)` (dark slate-700)

**Change:** Brightness check:

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
color: isLight ? Colors.white : const Color(0xFF334155)
```

Rationale: Dark mode uses `Color(0xFF334155)` (the existing behavior must not change). Light mode now has a dark nav bar background, so white is correct.

#### 6.4 Bottom Nav Bar Background (Fix 4)

Covered by fix 6.1. `AnimatedBottomNavBar` uses `GlassSurface` which uses `context.colors.appBarBg`. No additional change needed in `animated_bottom_nav_bar.dart` for the background.

#### 6.5 Unselected Bottom Nav Items (Fix 5)

**Layer:** Widget-level brightness check — `animated_bottom_nav_bar.dart`

**Current:** `context.colors.textSecondary` (gray in light mode, medium gray in dark)

**Change:** Brightness check:

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
color: isActive
    ? Colors.white
    : (isLight ? Colors.white : context.colors.textSecondary),
```

Rationale: After fix 6.1 the bottom nav has a dark background in light mode → white unselected icons needed. In dark mode, `textSecondary = Color(0xFFA1A1AA)` is preserved exactly.

#### 6.6 Selected Bottom Nav Tab (Fix 6)

**No change.** Active item is already `Colors.white` (hardcoded). Unchanged in both modes.

#### 6.7 Page Titles (Fix 11) — AppBarTheme

**Layer:** ThemeData (`app_theme.dart`) — light `AppBarTheme`

**Changes:**

- `backgroundColor`: `bc.background` → `bc.appBarBg` (now dark gray after 6.1)
- `foregroundColor`: `bc.textPrimary` → `Colors.white`
- `titleTextStyle.color`: `bc.textPrimary` → `Colors.white`

This covers all `AppBar` title widgets that inherit color from the theme (i.e., use `AppTextStyles.title3` or similar without explicit color override). Affected screens that are fixed automatically by this change:

- `bug_report_screen.dart` (title: `AppTextStyles.title3`, no explicit color)
- `profile_screen.dart` (title: `AppTextStyles.title3`, no explicit color)
- `create_setlist_screen.dart` (title: `AppTextStyles.title3`, no explicit color)
- `tips_and_tricks_screen.dart` (title: `AppTextStyles.title3`, no explicit color)

**Dark mode impact:** None. This modifies only `lightTheme`. The `darkTheme` getter is separate and unmodified.

> Note: Screens that explicitly override title color with `context.colors.textPrimary` require individual widget fixes (see 6.8).

#### 6.8 AppBar Title — Explicit Override Screens

**Layer:** Widget-level — 4 screens use `context.colors.textPrimary` explicitly in the AppBar and will be dark-text-on-dark after 6.1 + 6.7.

**`settings_screen.dart`** — AppBar title Text: `color: context.colors.textPrimary` → `Colors.white`

**`my_profile_screen.dart`** — AppBar title Text: `color: context.colors.textPrimary` → `Colors.white`

**`create_setlist_screen.dart`** — Close icon: `color: context.colors.textPrimary` → `Colors.white`

**`new_setlist_screen.dart`** — Close icon: `color: context.colors.textPrimary` → `Colors.white`

**`band_form_screen.dart`** — Back icon + back text in `FrostedGlassBar`: `color: context.colors.textPrimary` → `Colors.white`

**Rationale for `Colors.white` (not brightness check):** Nav bar is dark in BOTH modes (dark mode: `appBarBg = Color(0xFF09090B)` dark; light mode: `appBarBg = Color(0xFF18181B)` dark after fix). White is correct in both modes. In dark mode, `textPrimary` was already near-white so behavioral result is equivalent.

#### 6.9 Back Button in Glass Nav Bars (Fix 2 adjacent)

**Layer:** Widget-level — `back_only_app_bar.dart` and `setlists_app_bar.dart` (backOnly mode)

**Current:** Back icon + "Back" text use `context.colors.textPrimary`

**Change:** → `Colors.white`

Same rationale as 6.8. Nav bar always dark.

#### 6.10 Gig Name in Upcoming Gigs (Fix 7)

**Layer:** Widget-level brightness check — `confirmed_gig_card.dart`

**Current:** `const Color(0xFFFFF1F2)` (near-white rose)

**Change:**

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
color: isLight ? Colors.black : const Color(0xFFFFF1F2),
```

The card container has no explicit background color — it inherits the scaffold background. In light mode: white scaffold → white card. In dark mode: dark scaffold → dark card. Near-white text on dark = correct (unchanged). Black text on white = correct (fix).

#### 6.11 Setlist Card Text & Border (Fixes 8, 9, 10)

**Layer:** Widget-level brightness check — `setlist_card.dart`

Three sub-fixes:

**a) Setlist name:**

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
// current: const Color(0xFFFFF1F2)
color: isLight ? Colors.black : const Color(0xFFFFF1F2),
```

**b) Card border color** (non-Catalog draggable and non-draggable variants both affected):

```dart
// current: StandardCardBorder.color (= Color(0xFF334155))
color: isLight ? Colors.black : StandardCardBorder.color,
```

**c) Metadata text** (currently inherits gray from `Theme.textTheme.bodyMedium`):
Add explicit color to all metadata `TextSpan` / `Text` widgets:

```dart
color: isLight ? Colors.black : null, // null inherits dark mode default
```

**Dark mode:** `const Color(0xFFFFF1F2)` and `StandardCardBorder.color` are unchanged.

#### 6.12 Tips & Tricks Section Headers (Fix 12)

**Layer:** Widget-level brightness check — `tips_and_tricks_screen.dart`, `_TipSectionWidget`

**Current:** `color: Colors.white` (invisible in light mode)

**Change:**

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
color: isLight ? Colors.black : Colors.white,
```

#### 6.13 Gray Text in Light Mode — Tips & Tricks Body (Fix 13)

**Layer:** Widget-level brightness check — `tips_and_tricks_screen.dart`, `_TipRow`

**Current:** `color: context.colors.textSecondary` → `Color(0xFF52525B)` in light mode (gray)

**Change:**

```dart
color: isLight ? context.colors.textPrimary : context.colors.textSecondary,
```

---

## 7. Database Impact

**Not applicable.** This feature is UI-only. No Supabase queries, RPC calls, RLS policies, or schema changes.

---

## 8. Flutter Architecture Changes

### Theme layer

- `brand_colors.dart`: Single field value change on `BrandColors.light`
- `app_theme.dart`: Three field changes within `lightTheme` AppBarTheme block only

### Component layer

All changes are in-place modifications to existing widgets. No new widgets, providers, or repositories.

The brightness check pattern used throughout:

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
```

This is a standard Flutter idiom and does not require `ref` or any Riverpod provider.

---

## 9. Files to Create

**None.** All changes are in-place modifications to existing files.

---

## 10. Files to Modify

| #   | File                                                     | Changes                                                                                                                                                                             |
| --- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `lib/app/theme/brand_colors.dart`                        | `BrandColors.light.appBarBg`: `Color(0xFFFFFFFF)` → `Color(0xFF18181B)`                                                                                                             |
| 2   | `lib/app/theme/app_theme.dart`                           | Light `AppBarTheme`: `backgroundColor` → `bc.appBarBg`; `foregroundColor` → `Colors.white`; `titleTextStyle.color` → `Colors.white`                                                 |
| 3   | `lib/features/home/widgets/home_app_bar.dart`            | Hamburger icon: `context.colors.textPrimary` → `Colors.white`; Band name: `Color(0xFF334155)` → brightness check white/original                                                     |
| 4   | `lib/features/setlists/widgets/setlists_app_bar.dart`    | Hamburger icon: `context.colors.textPrimary` → `Colors.white`; Band name: `Color(0xFF334155)` → brightness check; Back btn icon+text: `context.colors.textPrimary` → `Colors.white` |
| 5   | `lib/features/setlists/widgets/back_only_app_bar.dart`   | Back btn icon + text: `context.colors.textPrimary` → `Colors.white`                                                                                                                 |
| 6   | `lib/features/home/widgets/animated_bottom_nav_bar.dart` | Unselected icon + label: `context.colors.textSecondary` → brightness check white/original                                                                                           |
| 7   | `lib/features/home/widgets/confirmed_gig_card.dart`      | Gig name: `Color(0xFFFFF1F2)` → brightness check black/original                                                                                                                     |
| 8   | `lib/features/setlists/widgets/setlist_card.dart`        | Setlist name: `Color(0xFFFFF1F2)` → brightness check; Border color: `StandardCardBorder.color` → brightness check; Metadata text: add explicit brightness-aware color               |
| 9   | `lib/features/tips/tips_and_tricks_screen.dart`          | Section header: `Colors.white` → brightness check black/white; Body text: `textSecondary` → brightness check textPrimary/textSecondary                                              |
| 10  | `lib/features/settings/settings_screen.dart`             | AppBar title text: `context.colors.textPrimary` → `Colors.white`                                                                                                                    |
| 11  | `lib/features/profile/my_profile_screen.dart`            | AppBar title text: `context.colors.textPrimary` → `Colors.white`                                                                                                                    |
| 12  | `lib/features/setlists/create_setlist_screen.dart`       | Close icon: `context.colors.textPrimary` → `Colors.white`                                                                                                                           |
| 13  | `lib/features/setlists/new_setlist_screen.dart`          | Close icon: `context.colors.textPrimary` → `Colors.white`                                                                                                                           |
| 14  | `lib/features/bands/band_form_screen.dart`               | Back icon + back text in FrostedGlassBar: `context.colors.textPrimary` → `Colors.white`                                                                                             |

---

## 11. Files Off-Limits

| File                                            | Reason                                                                                                            |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                 | Init order must not change; no routing impact from this feature                                                   |
| `supabase/`                                     | No database impact                                                                                                |
| `lib/app/theme/design_tokens.dart`              | `StandardCardBorder.color` and `AppColors` are used by multiple features; change is widget-level, not token-level |
| `android/`, `ios/`, `macos/`, `web/`            | No platform-level changes required                                                                                |
| Any file in `lib/features/*/` not listed in §10 | Minimal diff surface — no opportunistic changes                                                                   |

---

## 12. System Impact Map

| System                | Impact                    | Notes                                                                                                                  |
| --------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Home / nav            | **Affected**              | HomeAppBar bg, hamburger, band name, bottom nav                                                                        |
| Setlists              | **Affected**              | SetlistsAppBar, BackOnlyAppBar, SetlistCard, SetlistsBottomNavBar (via re-export)                                      |
| Gigs                  | **Affected**              | ConfirmedGigCard gig name only                                                                                         |
| Settings              | **Affected**              | AppBar title text only                                                                                                 |
| Profile               | **Affected**              | AppBar title text only                                                                                                 |
| Tips & Tricks         | **Affected**              | AppBar bg (via appBarBg), section headers, body text                                                                   |
| Bands                 | **Affected**              | BandFormScreen back button in FrostedGlassBar                                                                          |
| Bug Report            | **Affected (indirectly)** | AppBarTheme change auto-corrects title; no widget change needed                                                        |
| Auth / Session        | **Unaffected**            |                                                                                                                        |
| Calendar / Rehearsals | **Unaffected**            | No hardcoded whites or appBarBg AppBar backgrounds found                                                               |
| Contacts / Members    | **Unaffected**            |                                                                                                                        |
| Routing               | **Unaffected**            |                                                                                                                        |
| Database / RLS        | **Unaffected**            |                                                                                                                        |
| **Dark mode**         | **Unaffected**            | All changes scoped to `BrandColors.light`, `lightTheme`, or guarded by brightness checks; `darkTheme` getter untouched |

---

## 13. Regression Risk

**Level: LOW**

**Rationale:**

- All changes are UI-only with no logic, state, or data pathway impact
- Theme changes are confined to the `lightTheme` getter (a separate static getter from `darkTheme`)
- `BrandColors.light.appBarBg` change affects only the light color scheme; `BrandColors.dark` is untouched
- Widget-level brightness checks are additive guards — they test `Theme.of(context).brightness == Brightness.light`; the `else` branch returns the exact current value for dark mode
- `Colors.white` replacements in nav bar elements have equivalent effect in dark mode (dark mode `textPrimary ≈ white`, `textSecondary` is the only non-white item and is protected by brightness check)
- No new widgets, providers, state management, or network calls

**Dark mode protection explicit confirmation:**

| Change                                                 | Dark Mode Value Before                                                                                                                                              | Dark Mode Value After                     | Change?             |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- | ------------------- |
| `BrandColors.light.appBarBg`                           | Unused by dark                                                                                                                                                      | Unused by dark                            | None                |
| `AppBarTheme` in `lightTheme`                          | Not in `darkTheme`                                                                                                                                                  | Not in `darkTheme`                        | None                |
| Hamburger: `textPrimary` → `Colors.white`              | `textPrimary = Color(0xFFFAFAFA)` ≈ white                                                                                                                           | `Colors.white`                            | Visually equivalent |
| Band name: brightness check                            | `Color(0xFF334155)` in dark                                                                                                                                         | `Color(0xFF334155)` in dark (else branch) | None                |
| Unselected nav: brightness check                       | `textSecondary = Color(0xFFA1A1AA)`                                                                                                                                 | `textSecondary` (else branch)             | None                |
| Gig name: brightness check                             | `Color(0xFFFFF1F2)` in dark                                                                                                                                         | `Color(0xFFFFF1F2)` (else branch)         | None                |
| Setlist name: brightness check                         | `Color(0xFFFFF1F2)` in dark                                                                                                                                         | `Color(0xFFFFF1F2)` (else branch)         | None                |
| Setlist border: brightness check                       | `StandardCardBorder.color` in dark                                                                                                                                  | `StandardCardBorder.color` (else branch)  | None                |
| Section headers: brightness check                      | `Colors.white` in dark                                                                                                                                              | `Colors.white` (else branch)              | None                |
| Back btn/close icon: `textPrimary` → `Colors.white`    | `textPrimary = Color(0xFFFAFAFA)` ≈ white                                                                                                                           | `Colors.white`                            | Visually equivalent |
| AppBar title `textPrimary` → `Colors.white` (explicit) | Dark: `textPrimary = near-white`, but these screens set their AppBar bg via `appBarBg` which is very dark in dark mode — white title was the correct target already | `Colors.white`                            | Equivalent          |

---

## 14. Engineer Task Breakdown

Tasks are ordered to minimize re-work. Complete in the order listed.

### Task 1 — Foundation: Fix `BrandColors.light.appBarBg`

**File:** `lib/app/theme/brand_colors.dart`

- In the `static const light = BrandColors(...)` declaration, change:
  ```
  appBarBg: Color(0xFFFFFFFF),
  ```
  to:
  ```
  appBarBg: Color(0xFF18181B),
  ```
- This is a single-line change.

---

### Task 2 — Update Light `AppBarTheme` in `app_theme.dart`

**File:** `lib/app/theme/app_theme.dart`

- Locate the `static ThemeData get lightTheme` getter.
- Inside `AppBarTheme(...)`, change:
  ```
  backgroundColor: bc.background,  → backgroundColor: bc.appBarBg,
  foregroundColor: bc.textPrimary,  → foregroundColor: Colors.white,
  titleTextStyle: TextStyle(color: bc.textPrimary, ...)  → color: Colors.white
  ```
- Do **not** modify `iconTheme` (keep `bc.primary` for rose icons on non-glass AppBars).
- Do **not** touch `darkTheme`.

---

### Task 3 — Fix `HomeAppBar` nav bar icons and band name

**File:** `lib/features/home/widgets/home_app_bar.dart`

- Hamburger icon: change `color: context.colors.textPrimary` → `color: Colors.white`
- Band name `baseStyle`: change `color: const Color(0xFF334155)` → brightness check:
  ```dart
  final isLight = Theme.of(context).brightness == Brightness.light;
  color: isLight ? Colors.white : const Color(0xFF334155),
  ```

---

### Task 4 — Fix `SetlistsAppBar` nav bar icons, band name, and back button

**File:** `lib/features/setlists/widgets/setlists_app_bar.dart`

- Hamburger icon (default mode): `color: context.colors.textPrimary` → `Colors.white`
- Band name `baseStyle` (default mode): `color: const Color(0xFF334155)` → brightness check (same pattern as Task 3)
- Back button icon (backOnly mode): `color: context.colors.textPrimary` → `Colors.white`
- Back button "Back" text (backOnly mode): `color: context.colors.textPrimary` → `Colors.white`

---

### Task 5 — Fix `BackOnlyAppBar` back button

**File:** `lib/features/setlists/widgets/back_only_app_bar.dart`

- Back icon: `color: context.colors.textPrimary` → `Colors.white`
- "Back" text: `color: context.colors.textPrimary` → `Colors.white`

---

### Task 6 — Fix unselected bottom nav tab colors

**File:** `lib/features/home/widgets/animated_bottom_nav_bar.dart`

- Locate `_AnimatedNavItem.build()` → the icon `Icon(icon, color: ...)` and label `Text(label, style: TextStyle(color: ...))`.
- Both currently use `isActive ? Colors.white : context.colors.textSecondary`.
- Change the unselected branch to a brightness check:
  ```dart
  final isLight = Theme.of(context).brightness == Brightness.light;
  // Unselected color:
  isActive ? Colors.white : (isLight ? Colors.white : context.colors.textSecondary)
  ```
- The icon and label change are symmetric — apply identically to both.

---

### Task 7 — Fix gig name in `ConfirmedGigCard`

**File:** `lib/features/home/widgets/confirmed_gig_card.dart`

- Locate the gig title `Text(widget.gig.name, style: AppTextStyles.title3.copyWith(color: const Color(0xFFFFF1F2)))`.
- Change to:
  ```dart
  final isLight = Theme.of(context).brightness == Brightness.light;
  style: AppTextStyles.title3.copyWith(
    color: isLight ? Colors.black : const Color(0xFFFFF1F2),
  ),
  ```

---

### Task 8 — Fix setlist card name, border, and metadata

**File:** `lib/features/setlists/widgets/setlist_card.dart`

- Add `final isLight = Theme.of(context).brightness == Brightness.light;` once at the top of `SetlistCard._SetlistCardState.build()`.
- **Setlist name** (inside the `Row` in `innerContent`): change `color: const Color(0xFFFFF1F2)` → `color: isLight ? Colors.black : const Color(0xFFFFF1F2)`
- **Metadata text** (all `TextSpan` children of `Text.rich`): add `color: isLight ? Colors.black : null` to each `TextSpan`'s style. `null` means "inherit" — in dark mode, inherits the dark theme's default text color, which is the current behavior.
- **Border color** (two locations — draggable variant `Container` and non-draggable `Container`): both have `border: Border.all(color: StandardCardBorder.color, ...)`. Change to `color: isLight ? Colors.black : StandardCardBorder.color`.

---

### Task 9 — Fix Tips & Tricks section headers and body text

**File:** `lib/features/tips/tips_and_tricks_screen.dart`

- In `_TipSectionWidget.build()`: change section title color `Colors.white` → `isLight ? Colors.black : Colors.white`
- In `_TipRow.build()`: change both bullet and body text colors `context.colors.textSecondary` → `isLight ? context.colors.textPrimary : context.colors.textSecondary`
- The `isLight` variable is computed once per build method.
- The AppBar title text is **not** changed here — it inherits from the updated AppBarTheme (Task 2) and will be white correctly.

---

### Task 10 — Fix settings AppBar title

**File:** `lib/features/settings/settings_screen.dart`

- Locate the `AppBar` widget's `title:` property.
- Find the `Text` widget inside that has `color: context.colors.textPrimary`.
- Change → `Colors.white`
- Only the title text color changes. Do not modify any other text in the screen body.

---

### Task 11 — Fix my_profile AppBar title

**File:** `lib/features/profile/my_profile_screen.dart`

- Same pattern as Task 10.
- Locate the `AppBar.title` Text widget with `color: context.colors.textPrimary`.
- Change → `Colors.white`
- Only the AppBar title. Do not modify body text.

---

### Task 12 — Fix create_setlist close icon

**File:** `lib/features/setlists/create_setlist_screen.dart`

- Locate the close icon button in the `AppBar`: `Icon(AppIcons.close, color: context.colors.textPrimary)`
- Change → `color: Colors.white`

---

### Task 13 — Fix new_setlist close icon

**File:** `lib/features/setlists/new_setlist_screen.dart`

- Same pattern as Task 12.
- Locate `Icon(AppIcons.close, color: context.colors.textPrimary)` in the `AppBar`.
- Change → `color: Colors.white`

---

### Task 14 — Fix band_form back button in FrostedGlassBar

**File:** `lib/features/bands/band_form_screen.dart`

- Locate `_buildAppBar()` which returns a `FrostedGlassBar`.
- Inside the row: back `Icon` and "Back" `Text` both use `color: context.colors.textPrimary`.
- Change both → `Colors.white`

---

## 15. Verification Plan

### Tier 1 — Pre-build Visual Checklist (code review, no build required)

For each modified file, verify:

- [ ] No raw `Color(0xFF...)` introduced outside of `design_tokens.dart` or `brand_colors.dart`
- [ ] No new global constants added
- [ ] Brightness check pattern used correctly: `Theme.of(context).brightness == Brightness.light`
- [ ] `isLight` variable declared once per `build()` method, not repeated inline
- [ ] Dark mode branch in every brightness check returns the **original** value (not a guess)
- [ ] `brand_colors.dart` change: only `light.appBarBg` is modified; dark and all other fields unchanged
- [ ] `app_theme.dart` change: only within `static ThemeData get lightTheme`, not touching `darkTheme`

### Tier 2 — Post-build Verification

**Build check:**

```bash
flutter analyze
# Must return 0 errors, 0 warnings
```

**Manual walkthrough — Light mode (set device/simulator to light mode):**

| Screen                                      | What to verify in LIGHT MODE                                                                                                                                                                           |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Home / Dashboard                            | Top nav bar background is dark gray; hamburger icon is white; band name is white; bottom nav bar is dark gray; unselected nav icons are white; selected nav icon is rose on rose highlight (unchanged) |
| Upcoming Gigs                               | Gig name is black (not invisible)                                                                                                                                                                      |
| Home section headers ("Upcoming Gigs" etc.) | Text is dark/black — these use `context.colors.textPrimary`, should already be dark in light                                                                                                           |
| Setlists screen                             | AppBar/nav bar is dark gray with white band name; setlist cards show black names, black metadata, dark/black borders                                                                                   |
| Setlist detail                              | BackOnlyAppBar shows white "Back" text on dark bar                                                                                                                                                     |
| Tips & Tricks                               | AppBar is dark gray, title "Tips & Tricks" is white; section headers are black; body tip text is black                                                                                                 |
| Settings                                    | AppBar is dark gray, "Settings" title is white                                                                                                                                                         |
| My Profile                                  | AppBar is dark gray, profile name is white                                                                                                                                                             |
| New Setlist / Create Setlist                | AppBar is dark gray, close icon is white                                                                                                                                                               |
| Band Form                                   | FrostedGlassBar is dark gray, "Back" text is white                                                                                                                                                     |

**Manual walkthrough — Dark mode (switch device/simulator to dark mode after):**

| Screen           | What to verify in DARK MODE                                                                                 |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| Home / Dashboard | Nav bars appear exactly as before (dark glass, white hamburger, dark slate band name, gray unselected tabs) |
| Setlist cards    | Names are near-white rose `Color(0xFFFFF1F2)`, borders are dark slate `Color(0xFF334155)`                   |
| Gig cards        | Gig name is near-white rose `Color(0xFFFFF1F2)`                                                             |
| Tips & Tricks    | Section headers are white                                                                                   |
| All AppBars      | Titles are white, dark background                                                                           |

---

## 16. QA Regression Areas

| Screen                | Light Mode Check                                           | Dark Mode Check                           |
| --------------------- | ---------------------------------------------------------- | ----------------------------------------- |
| Dashboard / Home      | Nav bars visible, all text black/white, gig names black    | No visual regression                      |
| Setlists List         | Card names black, borders dark/black, metadata black       | Card names near-white, borders dark slate |
| Setlist Detail        | BackOnlyAppBar visible                                     | No visual regression                      |
| Tips & Tricks         | Section headers black, body text black, AppBar white title | Section headers white                     |
| Settings              | AppBar dark, title white                                   | No visual regression                      |
| My Profile            | AppBar dark, title white                                   | No visual regression                      |
| Create Setlist        | AppBar dark, close icon white                              | No visual regression                      |
| New Setlist           | AppBar dark, close icon white                              | No visual regression                      |
| Band Form             | FrostedGlassBar dark, Back text white                      | No visual regression                      |
| Bug Report            | AppBar dark, title white (via theme, no widget change)     | No visual regression                      |
| Profile (other)       | AppBar dark, title white (via theme)                       | No visual regression                      |
| Bottom Nav (all tabs) | Dark background, white selected + unselected icons         | Gray unselected icons unchanged           |

---

## 17. Out of Scope

The following are explicitly **not** included in this feature:

- Dark mode changes of any kind
- Calendar event card colors
- Rehearsal card colors (currently use gradient background — text is always white by design)
- Landing page / marketing content (`lib/features/landing/`)
- Song card colors (`song_card.dart`, `reorderable_song_card.dart`) — not mentioned in feature request
- Side drawer colors (`side_drawer.dart`) — not mentioned in feature request
- General `context.colors.textSecondary` sweep across all screens — only scoped to Tips & Tricks per fix 13
- New color tokens in `AppColors` — constraint prohibits new global color definitions
- Animated gradient border colors on Catalog setlist card — gradient is intentional and visible on all backgrounds
- Any gig card secondary text (location, time) — only gig NAME is specified in fix 7
- `StandardCardBorder.color` constant value in `design_tokens.dart` — widening this to a theme-aware token is out of scope; widget-level brightness check is the chosen approach
- `banner_test_screen.dart` — dev/test screen, not user-facing
