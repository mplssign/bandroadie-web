# ARCHITECT_PLAN.md — Light Mode Setting

## 1. Feature Slug

`feature/light-mode-setting`

---

## 2. Problem Summary

BandRoadie currently hardcodes `ThemeMode.dark` in `MaterialApp` with no user control. Users need a toggle in the Settings screen to switch between dark and light mode. Dark mode must remain the default. The preference must persist across app restarts.

---

## 3. Gap Analysis

| Gap                        | Current State                                                                                                                                                 | Required State                                                                                                                                              |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Light ThemeData**        | Only `AppTheme.darkTheme` exists (`app_theme.dart`). No `lightTheme` getter.                                                                                  | A `lightTheme` getter using `Brightness.light` with the same Rose accent palette.                                                                           |
| **ThemeMode control**      | `themeMode: ThemeMode.dark` is hardcoded in `BandRoadieApp.build()` (main.dart:127).                                                                          | `themeMode` is driven by a Riverpod provider that reads from `SharedPreferences`.                                                                           |
| **Provider**               | No theme mode provider exists anywhere in the codebase.                                                                                                       | A `themeModeProvider` (Notifier + NotifierProvider) that initializes to `ThemeMode.dark`, persists to `SharedPreferences`, and exposes a `toggle()` method. |
| **Settings toggle**        | Settings screen has one item (Notifications) plus Delete Account. No toggle-style widget — all items navigate via tap.                                        | A `SwitchListTile`-style "Light mode" toggle added above Notifications in `_buildSettingsItems()`.                                                          |
| **MaterialApp reactivity** | `BandRoadieApp` is a `StatelessWidget`. Cannot watch Riverpod providers.                                                                                      | `BandRoadieApp` must become a `ConsumerWidget` so it can `ref.watch(themeModeProvider)`.                                                                    |
| **Persistence**            | `shared_preferences` is already a dependency (pubspec.yaml:30) and used in `active_band_controller.dart`, `notification_permission_service.dart`, and others. | Same mechanism — `SharedPreferences.getBool('light_mode_enabled')`.                                                                                         |

**Design confidence: HIGH** — Pattern is clear (matches `ActiveBandNotifier` persistence pattern), `shared_preferences` is already available, only a `lightTheme` getter needs to be authored.

---

## 4. Reference Docs Consulted

| Document                                              | Relevant?                                                                           |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `docs/reference/settings/`                            | Directory does not exist. No prior settings docs.                                   |
| `docs/reference/general/AI_DECISIONS.md`              | Read. No prior theme-related decisions. DECISION-001 (PKCE migration) is unrelated. |
| `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` | Not read — not required for this feature.                                           |

---

## 5. Existing System Analysis

### 5a. Theme Wiring

- **`lib/app/theme/app_theme.dart`**: Defines `AppTheme` with a single static getter `darkTheme` returning a `ThemeData` with `Brightness.dark`, `ColorScheme.fromSeed(brightness: Brightness.dark, ...)`, Zinc background ramp, Rose accent, DM Sans font, and full M3 component overrides (~290 lines).
- **`lib/app/theme/design_tokens.dart`**: Defines `AppColors` with hardcoded dark-mode Zinc scale colors (background: zinc-950, surface: zinc-900, text: zinc-50/400/500/600) and Rose accent palette. These are static `const Color` values — not brightness-aware.
- **`lib/main.dart`**: `BandRoadieApp` is a `StatelessWidget`. `MaterialApp` sets `themeMode: ThemeMode.dark` and `darkTheme: AppTheme.darkTheme`. No `theme:` property is set (which is where light theme goes).
- **`ConfigErrorApp`** (main.dart:213) also hardcodes `ThemeMode.dark` — this is acceptable and should NOT be changed (error screen always dark).

### 5b. Settings Screen Structure

- **`lib/features/settings/settings_screen.dart`** (~420 lines): `ConsumerStatefulWidget`. Uses a `_buildSettingsItems()` method that returns a list of `SettingsItem` objects. Currently has one regular item (Notifications — tap to navigate) and one destructive item (Delete Account — always last). Items render via `_SettingsListItem` widget which shows icon + label + subtitle + chevron. The list uses `ListView.builder`.
- **No toggle widget exists** in settings currently. The Notifications item navigates on tap. For the Light Mode toggle, a `Switch` widget needs to be added as a new pattern. This should use the existing `_SettingsListItem` visual style but replace the chevron with a `Switch`.

### 5c. Persistence Layer

- `shared_preferences: ^2.2.2` is in `pubspec.yaml`.
- Used throughout the app: `active_band_controller.dart` (band ID persistence), `notification_permission_service.dart`, `lyrics_view_settings_service.dart`, `custom_tuning_service.dart`, `tuning_sort_service.dart`.
- Standard pattern: `SharedPreferences.getInstance()` → `getBool/setBool` with try/catch for private browsing mode (see `active_band_controller.dart:263-273` for the defensive pattern).

### 5d. Navigation to Settings

Settings screen is reached from multiple screens via menu overlays:

- `home_screen.dart:425`
- `calendar_screen.dart:345`
- `setlists_screen.dart:689`
- `app_shell.dart:266`
- `no_band_shell.dart:440`

No navigation changes required — the path already exists.

---

## 6. Proposed Solution

### 6a. Persistence: Local via `SharedPreferences`

**Decision**: Store theme preference locally using `SharedPreferences.setBool('light_mode_enabled', value)`.

**Justification**:

- Theme preference is a UI comfort setting, not band data
- No cross-device sync requirement specified
- `shared_preferences` is already a dependency with established patterns
- No Supabase schema change needed
- Matches how `active_band_id` and notification preferences are persisted

### 6b. Provider: `themeModeProvider`

Create a `ThemeModeNotifier` + `themeModeProvider` following the existing `Notifier`/`NotifierProvider` pattern.

**Shape**:

```
class ThemeModeNotifier extends Notifier<ThemeMode> {
  build() → ThemeMode.dark  (sync — default is always dark)

  Future<void> initialize()  — reads SharedPreferences, updates state if light was persisted
  Future<void> toggle()      — flips between dark/light, persists to SharedPreferences
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
```

**Key design decisions**:

- `build()` returns `ThemeMode.dark` synchronously — no async init required at provider construction time. This ensures the app always starts dark (matching current behavior) with zero delay.
- `initialize()` is called once after `runApp()` from `BandRoadieApp.build()` on first render, reading the persisted preference. If `light_mode_enabled == true`, state updates to `ThemeMode.light`, triggering a rebuild. The visual flash is negligible (single frame).
- `toggle()` flips the current state and persists. No debouncing needed — toggle is a discrete user action.
- Provider state type is `ThemeMode` directly (not a wrapper class) — minimal and sufficient.

### 6c. MaterialApp Wiring

- `BandRoadieApp` changes from `StatelessWidget` to `ConsumerWidget`.
- `build()` gains `WidgetRef ref` parameter.
- `themeMode:` changes from `ThemeMode.dark` to `ref.watch(themeModeProvider)`.
- Add `theme: AppTheme.lightTheme` property (new) alongside existing `darkTheme: AppTheme.darkTheme`.
- The `initialize()` call goes in `build()` via a one-shot pattern: `ref.read(themeModeProvider.notifier).initialize()` — called inside a `ref.listen` or simply called and cached. **Preferred approach**: use a `FutureProvider` or call `initialize()` in the widget's first build with a flag to avoid re-calling. Simplest: fire-and-forget in the Notifier's `build()` using `Future.microtask` to read prefs after sync return.

**Revised approach (cleaner)**: The `ThemeModeNotifier.build()` method returns `ThemeMode.dark` and immediately schedules an async read:

```dart
@override
ThemeMode build() {
  _loadFromPrefs();  // async, fire-and-forget
  return ThemeMode.dark;
}

Future<void> _loadFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final isLight = prefs.getBool('light_mode_enabled') ?? false;
  if (isLight) {
    state = ThemeMode.light;
  }
}
```

This guarantees dark on first frame, updates to light on second frame if persisted. No init order change.

### 6d. Light ThemeData

`AppTheme` gets a new static getter `lightTheme` that mirrors `darkTheme` but with:

- `brightness: Brightness.light`
- `ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light)` with overrides for surfaces using light Zinc equivalents
- Light background colors: white/zinc-50/zinc-100 instead of zinc-950/900/800
- Text colors: zinc-900/zinc-600/zinc-400 instead of zinc-50/400/500
- Same Rose accent (#F43F5E) — brand color stays consistent
- Same DM Sans font, same component shapes/radii
- Same component theming structure (AppBar, buttons, inputs, cards, etc.)

**Note**: `AppColors` currently has hardcoded dark-mode colors. The light theme should define its own inline color values within `AppTheme.lightTheme` rather than adding light-mode variants to `AppColors`. This keeps the change minimal. A future refactoring could add `AppColors.lightBackground` etc., but that is out of scope.

### 6e. Settings Toggle

In `settings_screen.dart`:

- Add a new `SettingsItem`-like entry at the **top** of `_buildSettingsItems()` regular items list, **before** Notifications.
- Since `SettingsItem` uses `onTap` + chevron pattern (navigation), and the light mode toggle needs a `Switch`, the simplest approach is to add a dedicated toggle widget directly in the `build()` method's `regularItems` section, OR extend the item model.

**Chosen approach**: Add a dedicated `_LightModeToggle` widget rendered above the `ListView` of navigation items. This widget:

- Shows icon (sun/brightness icon) + "Light mode" label + subtitle "Switch to light theme" + `Switch` widget
- Reads `ref.watch(themeModeProvider)` to determine switch state
- Calls `ref.read(themeModeProvider.notifier).toggle()` on change
- Visually matches `_SettingsListItem` padding and styling

This avoids modifying the `SettingsItem` model (which is tap-only) and keeps the toggle isolated.

---

## 7. Database Impact

**Database: not applicable** — preference stored via `SharedPreferences` (local device storage).

No migration required. No RLS impact. No RPC changes. No Supabase schema changes.

---

## 8. Flutter Architecture Changes

### State

- New `ThemeModeNotifier` (Notifier) managing `ThemeMode` state
- New `themeModeProvider` (NotifierProvider)

### Widgets

- `BandRoadieApp` changes from `StatelessWidget` → `ConsumerWidget`
- `SettingsScreen` gains a `_LightModeToggle` widget in its body

### Providers

- `themeModeProvider` — new, follows existing `Notifier`/`NotifierProvider` pattern

---

## 9. Files to Create

| File                                       | Justification                                                                                                                                                                            |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/theme_mode_controller.dart` | Houses `ThemeModeNotifier` + `themeModeProvider`. Follows feature-adjacent placement (theme provider lives with theme code). Keeps `app_theme.dart` focused on `ThemeData` construction. |

**Total new files: 1**

---

## 10. Files to Modify

| File                                         | What Changes                                                                                                                                                                                                                                                               |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/app_theme.dart`               | Add `static ThemeData get lightTheme` getter mirroring `darkTheme` with light-mode colors.                                                                                                                                                                                 |
| `lib/main.dart`                              | (1) `BandRoadieApp`: change from `StatelessWidget` to `ConsumerWidget`. (2) `MaterialApp`: change `themeMode: ThemeMode.dark` → `themeMode: ref.watch(themeModeProvider)`. (3) Add `theme: AppTheme.lightTheme` property. (4) Add import for `theme_mode_controller.dart`. |
| `lib/features/settings/settings_screen.dart` | Add `_LightModeToggle` widget above the regular items ListView. Import `theme_mode_controller.dart`.                                                                                                                                                                       |

**Total files modified: 3**

---

## 11. Files Off-Limits

| File                                         | Reason                                                                                      |
| -------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `lib/main.dart` (init sequence, lines 28-99) | Initialization order must not change per guardrails. Only `BandRoadieApp` class is touched. |
| `lib/app/theme/design_tokens.dart`           | No changes to color constants — light theme defines its own inline colors.                  |
| `supabase/**`                                | No backend changes.                                                                         |
| `lib/features/home/**`                       | Navigation to Settings already works.                                                       |
| `lib/features/auth/**`                       | Not related.                                                                                |
| `lib/features/setlists/**`                   | Not related.                                                                                |
| `ConfigErrorApp` (main.dart:199+)            | Error screen stays dark always.                                                             |

**Migration policy**: Not required — no database changes.
**Edge function deploy**: Not required.
**New dependencies**: None — `shared_preferences` already in pubspec.yaml.
**New files**: 1 — `lib/app/theme/theme_mode_controller.dart` (justified above).

---

## 12. System Impact Map

| System                                 | Impact                                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------------------------- |
| Theme / Design Tokens                  | **Affected** — new `lightTheme` getter in `app_theme.dart`, new `theme_mode_controller.dart` |
| Settings Screen                        | **Affected** — new Light mode toggle widget                                                  |
| App Entry / MaterialApp                | **Affected** — `BandRoadieApp` becomes `ConsumerWidget`, `themeMode` reactively bound        |
| Home / Navigation                      | Unaffected                                                                                   |
| Auth / Session                         | Unaffected                                                                                   |
| Routing                                | Unaffected                                                                                   |
| Notifications                          | Unaffected                                                                                   |
| Platform (iOS / Android / Web / macOS) | Unaffected — `SharedPreferences` + `ThemeMode` work identically on all platforms             |

---

## 13. Regression Risk

**Level: MEDIUM**

**Rationale**:

- `BandRoadieApp` changing from `StatelessWidget` to `ConsumerWidget` is a top-level widget change. If done incorrectly, it could break the entire app. However, this is a well-documented, minimal change (add `WidgetRef ref` parameter, change extends clause).
- `MaterialApp` now receives both `theme` and `darkTheme` props. Flutter's `themeMode` switch between them is framework-level behavior — well-tested.
- The light theme is entirely new UI territory. Some widgets may use hardcoded dark-mode colors (e.g., `Colors.white` for text, `Color(0xFF...)` literals outside design tokens). These will look wrong in light mode. The plan does NOT attempt to fix every widget — the light theme provides a best-effort M3-based light palette. Hardcoded colors in individual features are pre-existing tech debt and out of scope.
- `SharedPreferences` read is async with fire-and-forget pattern. In private browsing mode (Safari), `SharedPreferences` may throw — the defensive try/catch pattern from `active_band_controller.dart` must be followed.

---

## 14. Engineer Task Breakdown

Execute in order. Each task is atomic and independently verifiable.

### Task 1: Create `theme_mode_controller.dart`

**File**: `lib/app/theme/theme_mode_controller.dart` (new)

- Define `ThemeModeNotifier extends Notifier<ThemeMode>`
- `build()` returns `ThemeMode.dark`, calls `_loadFromPrefs()` fire-and-forget
- `_loadFromPrefs()` reads `SharedPreferences.getBool('light_mode_enabled')`, updates state if true
- `toggle()` flips state, persists via `SharedPreferences.setBool('light_mode_enabled', value)`
- All `SharedPreferences` calls wrapped in try/catch (private browsing safety)
- Define `themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new)`
- SharedPreferences key: `'light_mode_enabled'`

### Task 2: Add `lightTheme` to `AppTheme`

**File**: `lib/app/theme/app_theme.dart`

- Add a private `_lightColorScheme` static field mirroring `_colorScheme` but with `Brightness.light`
- Add `static ThemeData get lightTheme` mirroring `darkTheme` structure with light-appropriate colors
- Light surface colors: white (`#FFFFFF`) for background, zinc-50 (`#FAFAFA`) for surface, zinc-100 (`#F4F4F5`) for elevated surface
- Light text colors: zinc-900 (`#18181B`) for primary, zinc-500 (`#71717A`) for secondary, zinc-400 (`#A1A1AA`) for muted
- Same Rose accent (#F43F5E / #BE123C)
- Same component shapes, radii, font sizes, DM Sans font
- Same `scaffoldBackgroundColor`, `appBarTheme`, button themes, input themes, card themes, nav themes, snackbar theme — all adapted for light brightness

### Task 3: Wire `MaterialApp` to theme provider

**File**: `lib/main.dart`

- Add import: `import 'app/theme/theme_mode_controller.dart';`
- Change `class BandRoadieApp extends StatelessWidget` → `class BandRoadieApp extends ConsumerWidget`
- Change `Widget build(BuildContext context)` → `Widget build(BuildContext context, WidgetRef ref)`
- Change `themeMode: ThemeMode.dark` → `themeMode: ref.watch(themeModeProvider)`
- Add `theme: AppTheme.lightTheme,` property after `darkTheme: AppTheme.darkTheme,`
- Do NOT touch `ConfigErrorApp` or the init sequence

### Task 4: Add Light mode toggle to Settings screen

**File**: `lib/features/settings/settings_screen.dart`

- Add import: `import '../../app/theme/theme_mode_controller.dart';`
- Add a `_LightModeToggle` StatelessWidget (or embed inline) above the `ListView.builder` in the `build()` method's `Column`
- Toggle visually matches `_SettingsListItem` style: 16px horizontal padding, icon (use `Icons.light_mode` or equivalent from `AppIcons`), "Light mode" label, "Switch to light theme" subtitle
- Replace chevron with a `Switch` widget
- Switch value: `ref.watch(themeModeProvider) == ThemeMode.light`
- Switch onChanged: `ref.read(themeModeProvider.notifier).toggle()`
- Switch active color: `AppColors.primary`
- Place toggle before the Notifications item, after any top padding
- Ensure a divider separates the toggle from the navigation items below

### Task 5: Verify with `flutter analyze`

- Run `flutter analyze` and confirm zero new warnings/errors
- Fix any issues introduced by the changes

---

## 15. Verification Plan

### Tier 1 — Pre-deploy (automated / local)

| Check                 | Method                                          | Pass criteria                  |
| --------------------- | ----------------------------------------------- | ------------------------------ |
| Static analysis       | `flutter analyze`                               | Zero errors, zero new warnings |
| Build (macOS)         | `flutter build macos` or `flutter run -d macos` | Builds successfully            |
| Build (web)           | `flutter build web`                             | Builds successfully            |
| Provider construction | App launches in dark mode                       | No crash on startup            |

### Tier 2 — Post-deploy (manual / E2E)

| Check               | Method                                                      | Pass criteria                                                                       |
| ------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Default dark mode   | Fresh app launch (clear SharedPreferences)                  | App is in dark mode                                                                 |
| Toggle to light     | Settings → enable "Light mode" toggle                       | Entire app switches to light theme immediately                                      |
| Toggle back to dark | Settings → disable "Light mode" toggle                      | Entire app switches back to dark theme immediately                                  |
| Persistence         | Enable light mode → kill app → relaunch                     | App launches in light mode                                                          |
| Persistence (dark)  | Disable light mode → kill app → relaunch                    | App launches in dark mode                                                           |
| Cross-screen        | Enable light mode → navigate home, calendar, setlists, gigs | All screens render in light theme                                                   |
| Private browsing    | Open app in Safari private browsing                         | App works in dark mode; toggle functions but may not persist (graceful degradation) |

---

## 16. QA Regression Areas

| Area                  | What to test                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------------------- |
| **Default theme**     | Fresh install / cleared storage → app launches dark                                               |
| **Toggle behavior**   | Toggle on → light; toggle off → dark; immediate, no flicker                                       |
| **Persistence**       | Preference survives app restart on all four platforms                                             |
| **Settings screen**   | Toggle appears above Notifications, below app bar; Delete Account still at bottom                 |
| **All platforms**     | iOS, Android, macOS, Web — toggle and theme switch work identically                               |
| **Navigation**        | Menu → Settings path still works from all entry points (home, calendar, setlists, app shell)      |
| **Existing features** | Setlist cards, song cards, gig cards, rehearsal cards, profile — render acceptably in both themes |
| **Error states**      | Config error screen stays dark regardless of preference                                           |
| **Auth screens**      | Login screen, auth confirm screen render acceptably in light mode                                 |
| **Text legibility**   | All text readable in both themes (check for hardcoded `Colors.white` text on light backgrounds)   |

---

## 17. Out of Scope

- Refactoring `AppColors` to be brightness-aware (future work)
- Fixing hardcoded `Color(0xFF...)` literals scattered in feature widgets
- System theme detection / "follow system" option
- Cross-device theme sync via Supabase
- Per-band theme preferences
- Full visual QA of every screen in light mode (the light theme is best-effort M3-based; individual widget fixes are separate tasks)
- Dark/light variants of image assets or gradient colors
- Changes to the landing page (marketing, web only)
- Any changes to `ConfigErrorApp`
