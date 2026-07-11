# Architect Plan: Theme Mode Architecture Audit

## Feature Slug

`bug/theme-mode-architecture-audit`

---

## Problem Summary

Dark/light mode theming is implemented inefficiently across the codebase. While the application-level theme architecture is correct (`ThemeModeNotifier` → `MaterialApp.themeMode` → `lightTheme`/`darkTheme`), 20+ widget files bypass the centralized theme system by manually checking `Theme.of(context).brightness` and conditionally applying colors. This creates maintenance burden, inconsistency risk, and violates the single-source-of-truth principle established in the copilot instructions constraint: "Never add global color definitions outside `AppColors` in `design_tokens.dart`."

**Impact:** As more screens are added, the pattern proliferates. Theme adjustments require updating 20+ files instead of one.

---

## Root Cause

**Confidence Level:** HIGH

Widgets do not trust the centralized theme system. Instead of using `context.colors` (the `BrandColors` theme extension) or `Theme.of(context).colorScheme`, widgets branch on brightness locally:

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
// Then conditional color logic:
color: isLight ? Colors.black : const Color(0xFFFFF1F2)
border: isLight ? Colors.black : StandardCardBorder.color
```

This pattern appears in 20 widget files across features: calendar, contacts, events, home, members, setlists.

**Why this happened:** The theme infrastructure was added after many screens were built. Widgets adopted a "check brightness and apply colors" pattern before `BrandColors.light` and `BrandColors.dark` theme extensions existed.

---

## Reference Docs Consulted

- `docs/reference/audits/CODEBASE_AUDIT.md` — §3.3 flagged duplicate color definitions (now unified)
- `docs/reference/architecture/architecture.md` — confirmed design tokens location
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — theme tokens reference
- `.github/copilot-instructions.md` — constraint: centralized color definitions only

No dedicated theming reference doc exists. This is acceptable; theme architecture is simple.

---

## Existing System Analysis

### Current Theme Architecture (Correct Implementation)

```
User toggles light mode (settings_screen.dart line 420)
      ↓
ThemeModeNotifier.toggle() updates state + SharedPreferences
      ↓
themeModeProvider notifies listeners (main.dart line 150)
      ↓
MaterialApp.themeMode switches between ThemeMode.light / ThemeMode.dark
      ↓
MaterialApp applies AppTheme.lightTheme or AppTheme.darkTheme
      ↓
Widgets SHOULD read Theme.of(context).extension<BrandColors>() via context.colors
```

### Theme Files (All Correct)

| File                                                          | Purpose                                       | Status    |
| ------------------------------------------------------------- | --------------------------------------------- | --------- |
| `lib/app/theme/theme_mode_controller.dart`                    | ThemeModeNotifier + themeModeProvider         | ✓ Correct |
| `lib/app/theme/app_theme.dart`                                | ThemeData for light & dark modes              | ✓ Correct |
| `lib/app/theme/brand_colors.dart`                             | BrandColors.light & BrandColors.dark palettes | ✓ Correct |
| `lib/app/theme/design_tokens.dart`                            | AppColors, spacing, typography                | ✓ Correct |
| `lib/main.dart` (line 150)                                    | Wires themeModeProvider to MaterialApp        | ✓ Correct |
| `lib/features/settings/settings_screen.dart` (lines 387, 420) | User toggle control                           | ✓ Correct |

### Duplicate Color Issue (CODEBASE_AUDIT.md §3.3)

**Finding from audit:** `primaryColor = 0xFFBE123C` in `app_theme.dart` and `accent = 0xFFBE123C` in `design_tokens.dart` — same hex, different names.

**Actual state:** No duplicate exists. Both files correctly reference `AppColors.primary = Color(0xFFBE123C)` from `design_tokens.dart`. The audit finding is now resolved (likely fixed after the March 2026 audit date).

### Files with Manual Brightness Checks (20 widgets)

| File                                                                 | Line | Pattern                                                             |
| -------------------------------------------------------------------- | ---- | ------------------------------------------------------------------- |
| `lib/components/ui/frosted_glass_bar.dart`                           | 81   | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`            | 514  | `final isDark = Theme.of(context).brightness == Brightness.dark;`   |
| `lib/features/calendar/widgets/calendar_event_card.dart`             | 104  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/calendar/widgets/calendar_grid.dart`                   | 195  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/contacts/widgets/contact_card.dart`                    | 32   | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/contacts/widgets/venue_card.dart`                      | 33   | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/events/widgets/event_editor_drawer.dart`               | 2521 | `final isDark = Theme.of(context).brightness == Brightness.dark;`   |
| `lib/features/events/widgets/event_form_fields.dart`                 | 459  | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/home/widgets/animated_bottom_nav_bar.dart`             | 287  | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/home/widgets/confirmed_gig_card.dart`                  | 61   | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/home/widgets/potential_gig_card.dart`                  | 283  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/home/widgets/rehearsal_card.dart`                      | 294  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/members/widgets/member_card.dart`                      | 88   | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/setlists/setlist_detail_screen.dart`                   | 2514 | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart` | 426  | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/setlists/widgets/reorderable_song_card.dart`           | 164  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/setlists/widgets/set_break_creator.dart`               | 281  | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/setlists/widgets/setlist_card.dart`                    | 92   | `final isLight = Theme.of(context).brightness == Brightness.light;` |
| `lib/features/setlists/widgets/song_card.dart`                       | 113  | `Theme.of(context).brightness == Brightness.light` (inline)         |
| `lib/features/settings/settings_screen.dart`                         | 387  | Legitimate — checks theme mode to show toggle state                 |

**Total:** 20 widget files (19 requiring fix + 1 legitimate usage in settings screen)

### Common Brightness-Conditional Patterns Found

**Pattern 1: Text color override**

```dart
style: AppTextStyles.title3.copyWith(
  color: isLight ? Colors.black : const Color(0xFFFFF1F2),
)
```

**Should be:** `color: context.colors.textPrimary` (already defined in theme)

**Pattern 2: Border color conditional**

```dart
border: Border.all(
  color: isLight ? Colors.black : StandardCardBorder.color,
  width: StandardCardBorder.width,
)
```

**Should be:** `border: Border.all(color: context.colors.border, width: ...)`

**Pattern 3: Background color conditional**

```dart
color: isLight ? Colors.white : Colors.transparent
```

**Should be:** `color: context.colors.surface` (or appropriate semantic color)

**Pattern 4: DatePicker theme override**

```dart
final isDark = Theme.of(context).brightness == Brightness.dark;
colorScheme: (isDark ? ColorScheme.dark : ColorScheme.light)(...)
```

**Should be:** `colorScheme: Theme.of(context).colorScheme` (already correct for current mode)

### Hardcoded Colors (Not a Theme Issue)

177 `Color(0xFF...)` literals found across 31 files. Most are **intentional and correct:**

1. **Tuning badge colors** (`tuning_helpers.dart`, 38+ instances) — Semantic domain colors mapping tuning types to visual identifiers. Different tunings need distinct colors for usability. Not theme-dependent.

2. **Avatar color palette** (`band_form_screen.dart`, `band_avatar.dart`, 25+ instances) — User-selectable band avatar colors. These are brand palette options, not theme colors.

3. **Landing page gradients** (`landing/*`, 20+ instances) — Marketing site has fixed aesthetic. Not part of the app theme system.

4. **Semantic colors in financial charts** (`financials_screen.dart`) — Green for income, red for expenses. Domain-specific, not theme colors.

**Verdict:** Hardcoded colors are not part of the theming inefficiency. They are intentional domain semantics or user-selectable palettes. No action required.

---

## Proposed Solution

**Goal:** Eliminate manual brightness checks in widgets. All color decisions should flow through the centralized theme system.

**Approach:** Minimal, surgical edits to the 19 affected widget files. Replace brightness-conditional color logic with direct references to `context.colors` (BrandColors extension) or `Theme.of(context).colorScheme`.

### Example Transformation

**Before:**

```dart
final isLight = Theme.of(context).brightness == Brightness.light;
Text(
  widget.gig.name,
  style: AppTextStyles.title3.copyWith(
    color: isLight ? Colors.black : const Color(0xFFFFF1F2),
  ),
)
```

**After:**

```dart
Text(
  widget.gig.name,
  style: AppTextStyles.title3.copyWith(
    color: context.colors.textPrimary,
  ),
)
```

### Color Mapping Rules

| Conditional Pattern                                                | Replacement                     |
| ------------------------------------------------------------------ | ------------------------------- |
| `isLight ? Colors.black : const Color(0xFFFFF1F2)`                 | `context.colors.textPrimary`    |
| `isLight ? Colors.white : Colors.transparent`                      | `context.colors.surface`        |
| `isLight ? Colors.black : StandardCardBorder.color`                | `context.colors.border`         |
| `isLight ? const Color(0xFFE4E4E7) : const Color(0xFF27272A)`      | `context.colors.border`         |
| DatePicker: `(isDark ? ColorScheme.dark : ColorScheme.light)(...)` | `Theme.of(context).colorScheme` |

**BrandColors palette reference (from `brand_colors.dart`):**

| Semantic Name     | Dark Value | Light Value | Usage                 |
| ----------------- | ---------- | ----------- | --------------------- |
| `background`      | `#09090B`  | `#F8FAFC`   | Screen background     |
| `surface`         | `#18181B`  | `#FAFAFA`   | Card/panel background |
| `surfaceElevated` | `#27272A`  | `#F4F4F5`   | Elevated surface      |
| `border`          | `#27272A`  | `#E4E4E7`   | Standard border       |
| `borderStrong`    | `#52525B`  | `#A1A1AA`   | Emphasized border     |
| `textPrimary`     | `#FAFAFA`  | `#020617`   | Primary text          |
| `textSecondary`   | `#A1A1AA`  | `#020617`   | Secondary text        |
| `textMuted`       | `#71717A`  | `#020617`   | Muted text            |
| `primary`         | `#BE123C`  | `#BE123C`   | Brand accent (rose)   |
| `error`           | `#EF4444`  | `#EF4444`   | Error state           |

**Note:** Light mode text colors converge to `#020617` (slate-950) for accessibility. This is intentional.

### Constraints

- No new color definitions
- No changes to `app_theme.dart`, `brand_colors.dart`, or `design_tokens.dart` (these are correct)
- No opportunistic refactors (resist the urge to extract widgets or rename variables)
- No changes to tuning colors, avatar colors, or landing page gradients (intentional domain semantics)

---

## Database Impact

**Not applicable.** This is a client-side UI theming change. No database tables, RLS policies, RPCs, or migrations are affected.

---

## Flutter Architecture Changes

### State Management

No changes. `ThemeModeNotifier` and `themeModeProvider` are already correct.

### Widgets

19 widget files will be modified to remove brightness checks and use theme colors directly.

### Repositories

No changes.

### Controllers

No changes.

---

## Files to Create

**None.**

---

## Files to Modify

| File                                                                 | Change Description                                                                        |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `lib/components/ui/frosted_glass_bar.dart`                           | Remove `isLight` check, use `context.colors.textPrimary`                                  |
| `lib/features/calendar/widgets/add_block_out_drawer.dart`            | Remove `isDark` check in `_datePickerTheme`, use `Theme.of(context).colorScheme` directly |
| `lib/features/calendar/widgets/calendar_event_card.dart`             | Replace inline brightness checks with `context.colors.border`                             |
| `lib/features/calendar/widgets/calendar_grid.dart`                   | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/contacts/widgets/contact_card.dart`                    | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/contacts/widgets/venue_card.dart`                      | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/events/widgets/event_editor_drawer.dart`               | Remove `isDark` checks, use `context.colors` and `Theme.of(context).colorScheme`          |
| `lib/features/events/widgets/event_form_fields.dart`                 | Remove `isLight` checks, use `context.colors`                                             |
| `lib/features/home/widgets/animated_bottom_nav_bar.dart`             | Remove `isLight` check, use `context.colors`                                              |
| `lib/features/home/widgets/confirmed_gig_card.dart`                  | Remove `isLight` check, use `context.colors.textPrimary`                                  |
| `lib/features/home/widgets/potential_gig_card.dart`                  | Replace inline brightness checks with `context.colors`                                    |
| `lib/features/home/widgets/rehearsal_card.dart`                      | Replace inline brightness checks with `context.colors`                                    |
| `lib/features/members/widgets/member_card.dart`                      | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/setlists/setlist_detail_screen.dart`                   | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart` | Remove `isLight` check, use `context.colors`                                              |
| `lib/features/setlists/widgets/reorderable_song_card.dart`           | Replace inline brightness check with `context.colors.border`                              |
| `lib/features/setlists/widgets/set_break_creator.dart`               | Remove `isLight` check, use `context.colors`                                              |
| `lib/features/setlists/widgets/setlist_card.dart`                    | Remove `isLight` check, use `context.colors.textPrimary` and `context.colors.border`      |
| `lib/features/setlists/widgets/song_card.dart`                       | Replace inline brightness check with `context.colors.border`                              |

**Total:** 19 files

---

## Files Off-Limits

| File                                               | Reason                                                                                        |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                    | Theme wiring is correct; no changes needed                                                    |
| `lib/app/theme/theme_mode_controller.dart`         | Controller implementation is correct                                                          |
| `lib/app/theme/app_theme.dart`                     | Theme definitions are correct                                                                 |
| `lib/app/theme/brand_colors.dart`                  | Color palettes are correct                                                                    |
| `lib/app/theme/design_tokens.dart`                 | Token definitions are correct                                                                 |
| `lib/features/settings/settings_screen.dart`       | Theme toggle control is correct; line 387 legitimately checks theme mode to show toggle state |
| `lib/features/setlists/tuning/tuning_helpers.dart` | Tuning colors are semantic domain logic, not theme colors                                     |
| `lib/features/bands/band_form_screen.dart`         | Avatar color palette is user-selectable, not theme-dependent                                  |
| `lib/features/bands/widgets/band_avatar.dart`      | Avatar color map is intentional domain semantics                                              |
| `lib/features/landing/**`                          | Landing page has fixed marketing aesthetic                                                    |
| `lib/features/financials/**`                       | Financial chart colors are semantic (green/red)                                               |

---

## System Impact Map

| System                                 | Impact                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------ |
| Gigs                                   | **affected** — confirmed_gig_card.dart, potential_gig_card.dart modified |
| Rehearsals                             | **affected** — rehearsal_card.dart modified                              |
| Setlists / Catalog                     | **affected** — 6 setlist widget files modified                           |
| Members / RBAC                         | **affected** — member_card.dart modified                                 |
| Auth / Session                         | **unaffected**                                                           |
| Routing                                | **unaffected**                                                           |
| Notifications                          | **unaffected**                                                           |
| Calendar                               | **affected** — 3 calendar widget files modified                          |
| Contacts / Venues                      | **affected** — contact_card.dart, venue_card.dart modified               |
| Events                                 | **affected** — event_editor_drawer.dart, event_form_fields.dart modified |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms render these widgets                        |

---

## Regression Risk

**Level:** LOW

**Rationale:**

- Changes are purely visual (color resolution)
- No state management, routing, auth, or data logic affected
- Theme mode toggle already works correctly (verified in `settings_screen.dart`)
- Light and dark theme definitions are comprehensive and tested in production (100+ bands)
- All affected widgets already support both light and dark modes; we're only centralizing the color source
- No new colors introduced; only replacing conditional logic with theme references

**Risk factors:**

- 19 files modified (moderate surface area)
- Potential for incorrect color mapping if Engineer misidentifies semantic intent
- Visual regression if light mode colors differ subtly from current conditionals

**Mitigation:**

- Engineer must test both light and dark modes after each file modification
- QA must visually compare before/after screenshots in both modes
- Changes are localized to color properties only — no layout or interaction logic

---

## Engineer Task Breakdown

Execute tasks in order. Test both light and dark modes after each file.

### Phase 1: Component Layer (1 file)

**Task 1.1:** `lib/components/ui/frosted_glass_bar.dart`

- Remove `final isLight = ...` variable
- Replace conditional text color with `context.colors.textPrimary`

### Phase 2: Calendar Feature (3 files)

**Task 2.1:** `lib/features/calendar/widgets/add_block_out_drawer.dart`

- Remove `final isDark = ...` from `_datePickerTheme` method
- Replace `(isDark ? ColorScheme.dark : ColorScheme.light)(...)` with `Theme.of(context).colorScheme.copyWith(...)`

**Task 2.2:** `lib/features/calendar/widgets/calendar_event_card.dart`

- Replace inline `Theme.of(context).brightness == Brightness.light` checks with `context.colors.border`

**Task 2.3:** `lib/features/calendar/widgets/calendar_grid.dart`

- Replace inline brightness check with `context.colors.border`

### Phase 3: Contacts Feature (2 files)

**Task 3.1:** `lib/features/contacts/widgets/contact_card.dart`

- Replace inline brightness check with `context.colors.border`

**Task 3.2:** `lib/features/contacts/widgets/venue_card.dart`

- Replace inline brightness check with `context.colors.border`

### Phase 4: Events Feature (2 files)

**Task 4.1:** `lib/features/events/widgets/event_editor_drawer.dart`

- Remove all `isDark` checks
- Replace DatePicker theme conditional with `Theme.of(context).colorScheme`
- Replace any color conditionals with `context.colors` references

**Task 4.2:** `lib/features/events/widgets/event_form_fields.dart`

- Remove `final isLight = ...` variable
- Replace conditional colors with `context.colors` references

### Phase 5: Home Feature (4 files)

**Task 5.1:** `lib/features/home/widgets/animated_bottom_nav_bar.dart`

- Remove `final isLight = ...` variable
- Replace conditional colors with `context.colors` references

**Task 5.2:** `lib/features/home/widgets/confirmed_gig_card.dart`

- Remove `final isLight = ...` variable
- Replace `color: isLight ? Colors.black : const Color(0xFFFFF1F2)` with `color: context.colors.textPrimary`

**Task 5.3:** `lib/features/home/widgets/potential_gig_card.dart`

- Replace inline brightness checks with `context.colors` references

**Task 5.4:** `lib/features/home/widgets/rehearsal_card.dart`

- Replace inline brightness checks with `context.colors` references

### Phase 6: Members Feature (1 file)

**Task 6.1:** `lib/features/members/widgets/member_card.dart`

- Replace inline brightness check with `context.colors.border`

### Phase 7: Setlists Feature (6 files)

**Task 7.1:** `lib/features/setlists/setlist_detail_screen.dart`

- Replace inline brightness check with `context.colors.border`

**Task 7.2:** `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart`

- Remove `final isLight = ...` variable
- Replace conditional colors with `context.colors` references

**Task 7.3:** `lib/features/setlists/widgets/reorderable_song_card.dart`

- Replace inline brightness check with `context.colors.border`

**Task 7.4:** `lib/features/setlists/widgets/set_break_creator.dart`

- Remove `final isLight = ...` variable
- Replace conditional colors with `context.colors` references

**Task 7.5:** `lib/features/setlists/widgets/setlist_card.dart`

- Remove `final isLight = ...` variable
- Replace conditional text and border colors with `context.colors` references

**Task 7.6:** `lib/features/setlists/widgets/song_card.dart`

- Replace inline brightness check with `context.colors.border`

### Phase 8: Verification

**Task 8.1:** Run `flutter analyze` — must pass with 0 errors

**Task 8.2:** Visual regression test

- Toggle light mode on/off in Settings
- Navigate to: Home, Calendar, Setlists, Members, Contacts, Events
- Verify all cards, borders, and text are visually consistent with previous behavior
- Screenshot before/after for QA comparison

**Task 8.3:** Hot reload test

- Change theme mode via Settings toggle
- Verify all visible widgets update immediately (no stale colors)
- Verify no console errors or warnings

---

## Verification Plan

### Tier 1 — Pre-deployment (Static Analysis)

Not applicable. No database, RLS, or backend changes.

### Tier 2 — Post-deployment (Visual Regression)

**Test 1: Theme Toggle Persistence**

1. Open app in dark mode (default)
2. Navigate to Settings → toggle Light Mode on
3. Close and reopen app
4. Verify light mode persists

**Test 2: Widget Color Consistency — Dark Mode**

1. Ensure dark mode is active
2. Navigate through:
   - Home tab (gig cards, rehearsal cards)
   - Calendar tab (event cards, grid)
   - Setlists tab (setlist cards, song cards)
   - Members tab (member cards)
   - Contacts tab (contact cards, venue cards)
3. Verify:
   - Text is readable (white/light gray on dark backgrounds)
   - Borders are visible (zinc-800 tone)
   - No black-on-black or white-on-white text

**Test 3: Widget Color Consistency — Light Mode**

1. Toggle light mode on in Settings
2. Navigate through same screens as Test 2
3. Verify:
   - Text is readable (dark slate on light backgrounds)
   - Borders are visible (gray-300 tone)
   - No black-on-black or white-on-white text
   - Cards have proper contrast

**Test 4: DatePicker Theme (Light Mode)**

1. In light mode, navigate to Calendar
2. Tap "Add Block-out"
3. Tap "Until Date" picker
4. Verify DatePicker dialog uses light color scheme (not dark)

**Test 5: Hot Reload Theme Change**

1. Open app on any screen with cards
2. Toggle theme mode in Settings
3. Navigate back to the previous screen
4. Verify all colors updated immediately (no stale state)

**Test 6: Cross-Platform Visual Parity**

1. Test on iOS, Android, Web, macOS
2. Verify theme colors render identically across platforms
3. Verify no platform-specific color regressions

**Test 7: Screenshots for QA Comparison**

- Capture before/after screenshots of:
  - Home tab (dark mode)
  - Home tab (light mode)
  - Setlists tab with song cards (dark mode)
  - Setlists tab with song cards (light mode)
  - Calendar event cards (dark mode)
  - Calendar event cards (light mode)
- Submit screenshots in Engineer Report for QA comparison

---

## QA Regression Areas

QA must specifically test:

1. **Theme toggle functionality**
   - Settings toggle switches theme
   - Theme persists across app restarts
   - No console errors or warnings when toggling

2. **Visual consistency — Dark Mode**
   - All cards, borders, and text readable
   - No jarring color mismatches between widgets
   - Compare screenshots to pre-change production

3. **Visual consistency — Light Mode**
   - All cards, borders, and text readable
   - Light mode colors match design intent (not just inverted dark mode)
   - Compare screenshots to pre-change production

4. **Cross-platform parity**
   - iOS, Android, Web, macOS render identically
   - No platform-specific color bugs

5. **No functional regressions**
   - All taps, swipes, drags work as before
   - No layout shifts or broken interactions
   - Setlist reorder still works
   - Calendar events still create/edit correctly

6. **Performance**
   - No frame drops when toggling theme
   - No delayed color updates
   - Hot reload still instant

---

## Rollout / Migration Strategy

**Not applicable.** No database migrations, no backend changes, no feature flags required.

**Deployment:** Standard web deploy after QA approval. Changes apply immediately to all users on next app load.

---

## Out of Scope

Explicitly **not** included in this fix:

1. **Adding new theme modes** (e.g., system-default theme, high-contrast mode)
2. **Refactoring oversized widget files** (e.g., splitting `setlist_detail_screen.dart`)
3. **Extracting color constants to design tokens** for tuning badges, avatars, or landing page
4. **Implementing dynamic theme switching** (e.g., per-band color themes)
5. **Optimizing BrandColors structure** (e.g., reducing 19 color properties)
6. **Auditing widget rebuild performance** when theme changes
7. **Creating a theme preview screen** in Settings
8. **Documenting theme architecture** in `docs/reference/ui/`

These are valid future improvements but are not required to fix the identified inefficiency.

---

**END OF ARCHITECT PLAN**
