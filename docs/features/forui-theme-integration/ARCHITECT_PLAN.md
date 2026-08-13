# ARCHITECT_PLAN: Forui Theme Integration + Geist Font Swap

## Feature Slug

`feature/forui-theme-integration`

---

## Problem Summary

**Part 1 — Forui theme disconnected from BrandRoadie brand:**  
`FTheme` is wired in `lib/main.dart` with hardcoded preset `FTheme.neutral.dark.touch`, disconnected from BandRoadie's actual brand tokens (`AppColors.primary` = Rose-700 `#BE123C`, `BrandColors.dark`/`.light` palettes). MaterialApp correctly uses `themeModeProvider` for reactive light/dark switching with `AppTheme.lightTheme`/`.darkTheme`, but FTheme ignores this toggle and always renders stock Forui neutral-gray colors. Result: all 14 Forui-based UI facade wrappers (`lib/components/ui/`) render generic gray, not BandRoadie rose accent.

**Part 2 — Font swap from DM Sans to Geist:**  
Current font is DM Sans (3 static TTF weights bundled locally per `bug/google-fonts-runtime-fetch` pattern), referenced as `fontFamily: 'DM Sans'` in 48 locations across 6 files. Geist (Vercel's typeface, SIL Open Font License) must replace it. `google_fonts: ^8.0.0` dependency is dead code (no imports found). PDF export service (`lib/features/setlists/services/setlist_print_service.dart`) uses Noto Sans and is explicitly out of scope.

---

## Root Cause

**Confidence Level:** **HIGH**

### Part 1 — Forui Theme

**Current behavior (line 156 of `lib/main.dart`):**

```dart
builder: (context, child) => FTheme(
  data: FTheme.neutral.dark.touch,
  child: FToaster(...),
),
```

- `FTheme.data` is static — never reacts to `themeModeProvider` changes
- `FTheme.neutral.dark.touch` uses stock Forui gray palette:
  - `primary: Color(0xFFE5E5E5)` (neutral gray)
  - `background: Color(0xFF0A0A0A)` (neutral black)
  - No connection to `AppColors.primary` (Rose-700 `#BE123C`)
  - No connection to `BrandColors.dark`/`.light` semantic tokens

**Root cause:** Forui's `FColors` class (from `package:forui/src/theme/colors.dart`) has no automatic Material theme bridge. Custom `FColors` instances must be manually constructed by mapping BrandRoadie's `BrandColors` palette to Forui's semantic color slots (`primary`, `secondary`, `background`, `foreground`, etc.). The preset `FTheme.neutral.dark.touch` was used as a placeholder during the initial Forui swap (PR #145) and never customized.

**Evidence:**

- `FColors.neutralDark` preset (from package source):
  - `primary: Color(0xFFE5E5E5)` — neutral gray, not rose
  - `background: Color(0xFF0A0A0A)` — stock black
- `BrandColors.dark` palette (from `lib/app/theme/brand_colors.dart`):
  - `primary: AppColors.primary` → `#BE123C` (Rose-700)
  - `background: Color(0xFF09090B)` — BandRoadie's branded background
  - Full semantic token set for surface, border, text colors
- No reactive rebuild: `FTheme.data` is a constructor parameter, not wired to `ref.watch(themeModeProvider)`

### Part 2 — Font Swap

**Current state:** `fontFamily: 'DM Sans'` appears 48 times across 6 files (from grep search):

1. `lib/app/theme/app_theme.dart` — 22 occurrences (Material theme TextTheme definitions)
2. `lib/app/theme/design_tokens.dart` — 10 occurrences (AppTypography token definitions)
3. `lib/features/setlists/widgets/empty_setlists_state.dart` — 1 occurrence
4. `lib/features/home/widgets/rehearsal_card.dart` — 8 occurrences
5. `lib/features/home/widgets/potential_gig_card.dart` — 7 occurrences
6. `lib/features/home/widgets/empty_section_card.dart` — 1 occurrence

DM Sans fonts are bundled locally (per `bug/google-fonts-runtime-fetch` pattern):

- `assets/fonts/DMSans-Regular.ttf` (weight 400)
- `assets/fonts/DMSans-SemiBold.ttf` (weight 600)
- `assets/fonts/DMSans-Bold.ttf` (weight 700)

`google_fonts` package (`pubspec.yaml` line 18) is dead code:

- Grep search for `import 'package:google_fonts/google_fonts.dart'` found zero results
- No `GoogleFonts.*` calls anywhere in `lib/` (confirmed by prior `google-fonts-runtime-fetch` cycle)

**Root cause:** Simple global find-replace + asset swap task. No architectural complexity. Risk is entirely in download verification — prior cycle (`google-fonts-runtime-fetch`) encountered GitHub 404 HTML error pages downloaded as "font files" that weren't caught until QA ran `file` command. Same verification step required here.

---

## Reference Docs Consulted

### Forui Theme Documentation

- `package:forui/src/theme/colors.dart` — `FColors` class structure, preset definitions (neutralDark/neutralLight)
- `package:forui/src/theme/theme.dart` — `FTheme` widget API (InheritedWidget wrapper)
- `package:forui/src/theme/theme_data.dart` — `FThemeData` structure (inferred from existing code usage)

### Prior BandRoadie Cycles

- `docs/features/forui-design-system-swap/ARCHITECT_PLAN.md` — Initial Forui integration, placeholder theming
- `docs/features/forui-style-overrides/ARCHITECT_PLAN.md` — StyleDelta mechanism for per-widget customization
- `docs/features/google-fonts-runtime-fetch/ARCHITECT_PLAN.md` — Local font bundling pattern, download verification trap

### Design Tokens

- `lib/app/theme/brand_colors.dart` — `BrandColors.dark`/`.light` palettes (source of truth for all colors)
- `lib/app/theme/design_tokens.dart` — `AppColors.primary`, typography tokens
- `lib/app/theme/app_theme.dart` — Material theme definitions (shows font usage pattern)

---

## Existing System Analysis

### Part 1 — Current Forui Theme Flow

**Static Forui theming (current):**

```
MaterialApp (line 149, main.dart)
├─ themeMode: ref.watch(themeModeProvider)  ← reactive ✓
├─ theme: AppTheme.lightTheme               ← Material theme responds ✓
├─ darkTheme: AppTheme.darkTheme            ← Material theme responds ✓
└─ builder: (context, child) => FTheme(
      data: FTheme.neutral.dark.touch,      ← HARDCODED, IGNORES TOGGLE ✗
      child: FToaster(child: ...)
   )
```

**Material theme works correctly:**

- `ThemeModeNotifier` (in `theme_mode_controller.dart`) manages state via SharedPreferences
- `themeModeProvider` exposes `ThemeMode.light` or `.dark`
- MaterialApp switches between `AppTheme.lightTheme`/`.darkTheme` correctly
- Both Material themes reference `BrandColors.light`/`.dark` via theme extensions

**Forui theme is static:**

- `FTheme.data` receives static `FThemeData` object at build time
- No `ref.watch(themeModeProvider)` in FTheme construction
- Forui widgets (`FButton`, `FTextField`, etc.) inherit theme via `FTheme.of(context)`
- Theme never changes even when user toggles light/dark in settings

**Color mismatch between Material and Forui widgets:**

- Material buttons/cards/text use `AppColors.primary` (Rose-700 `#BE123C`)
- Forui buttons/cards/text use `FColors.neutralDark.primary` (gray `#E5E5E5`)
- Inconsistent brand identity within same screen

### Part 2 — Current Font Architecture

**Font bundling (established in `bug/google-fonts-runtime-fetch`):**

- Fonts declared in `pubspec.yaml` lines 89-106 under `fonts:` section
- Files live in `assets/fonts/` (7 files total: 3 DM Sans, 4 Noto Sans)
- Flutter's native `fontFamily` mechanism used everywhere (no `google_fonts` package calls)

**Font usage layers:**

1. **Material theme layer** (`app_theme.dart`, `design_tokens.dart`) — defines `TextTheme` with `fontFamily: 'DM Sans'`
2. **Direct widget usage** (4 feature widget files) — inline `TextStyle(fontFamily: 'DM Sans', ...)` for custom styling
3. **PDF generation layer** (`setlist_print_service.dart`) — uses Noto Sans via `pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-*.ttf'))`, explicitly out of scope

**Precedent from `google-fonts-runtime-fetch` cycle:**

- Downloaded font files from Google Fonts
- Verified each `.ttf` with `file` command before committing
- Updated `pubspec.yaml` fonts section
- Replaced all `GoogleFonts.dmSans(...)` → `TextStyle(fontFamily: 'DM Sans', ...)`
- Removed runtime HTTP fetching

**Same pattern applies here, but simpler:**

- Download Geist from `github.com/vercel/geist-font/releases` (static .ttf or .otf)
- Verify with `file` command (do NOT skip — this is where prior cycle almost failed)
- Replace DM Sans files in `assets/fonts/`
- Update `pubspec.yaml` fonts section (change family name, keep weight mappings)
- Find-replace `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'` (49 occurrences)
- Remove `google_fonts: ^8.0.0` from `pubspec.yaml` dependencies

---

## Proposed Solution

### Part 1 — Reactive Forui Theme with BrandRoadie Colors

**Approach:** Start from Forui's Neutral preset (`FColors.neutralLight` / `.neutralDark`) and override only the `primary` accent color to BandRoadie's Rose-700, leaving all other colors (background, surface, text, etc.) as Forui's stock Neutral values. Make `FTheme.data` reactive to `themeModeProvider` for light/dark mode switching.

#### Step 1: Create Theme Builder Function

Add to `lib/app/theme/app_theme.dart`:

```dart
/// Builds Forui theme data from Forui's Neutral preset, overriding only
/// the primary accent color to BandRoadie's brand color (Rose-700).
/// Other colors (background, surface, text, etc.) intentionally remain
/// Forui's stock Neutral palette — brand colors can be layered in
/// incrementally in a future cycle if needed.
static FThemeData foruiTheme(Brightness brightness) {
  final baseColors = brightness == Brightness.light
      ? FColors.neutralLight
      : FColors.neutralDark;

  final colors = baseColors.copyWith(
    primary: AppColors.primary, // Rose-700 #BE123C
    // primaryForeground stays near-white in both modes — Rose-700 is a
    // dark, saturated color, so text/icons on top of it need a light
    // foreground regardless of overall page brightness. Matches the
    // existing precedent in this file's Material filledButtonTheme
    // (light theme hardcodes Colors.white; dark theme's bc.textPrimary
    // is #FAFAFA — both effectively near-white).
    primaryForeground: Colors.white,
  );

  return FThemeData(colors: colors, touch: true);
}
```

**Color Mapping Rationale:**
| Forui Token | Customization | Value | Justification |
|-------------|---------------|-------|---------------|
| `primary` | **Overridden** | Rose-700 `#BE123C` | BandRoadie's primary brand accent (buttons, links, focus states) |
| `primaryForeground` | **Overridden** | `Colors.white` | Near-white text/icons on Rose-700 background for sufficient contrast in both light/dark modes |
| `background`, `foreground`, `secondary`, `muted`, `destructive`, `error`, `card`, `border` | **Stock Forui Neutral** | Varies by light/dark mode | Intentionally using Forui's battle-tested neutral palette — can refine incrementally later if needed |

**Scope Narrowing Rationale:** This minimal-override approach avoids premature commitment to a full custom color palette. Starting from Forui's Neutral preset ensures a coherent, well-tested foundation. Brand colors beyond `primary` can be layered in as a separate, deliberate decision after observing how the Neutral palette works in practice across all screens and interaction states.

#### Step 2: Make FTheme Reactive

Update `lib/main.dart` line 156:

```dart
// BEFORE:
builder: (context, child) => FTheme(
  data: FTheme.neutral.dark.touch,
  child: FToaster(...),
),

// AFTER:
builder: (context, child) {
  final brightness = ref.watch(themeModeProvider) == ThemeMode.light
      ? Brightness.light
      : Brightness.dark;

  return FTheme(
    data: AppTheme.foruiTheme(brightness),
    child: FToaster(
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: KeyboardAwareWrapper(child: child!),
      ),
    ),
  );
},
```

**Why this works:**

- `ref.watch(themeModeProvider)` triggers rebuild when theme changes
- Brightness derived from ThemeMode (light vs dark)
- `AppTheme.foruiTheme(brightness)` returns correct color palette
- Forui widgets automatically pick up new theme via `FTheme.of(context)`

**Compatibility check:**

- FTheme is already an InheritedWidget (confirmed from package source inspection)
- All 14 Forui-based wrappers use `FTheme.of(context)` internally (inherited during PR #145)
- No breaking changes to facade API — call sites unchanged

### Part 2 — Geist Font Swap

**Approach:** Follow exact pattern established in `bug/google-fonts-runtime-fetch` cycle.

#### Step 1: Download Geist Fonts

Source: https://github.com/vercel/geist-font/releases

**Required weights (to match DM Sans usage):**

- Geist Regular (400) — replaces DMSans-Regular.ttf
- Geist SemiBold (600) — replaces DMSans-SemiBold.ttf
- Geist Bold (700) — replaces DMSans-Bold.ttf

**File format:** Static `.ttf` or `.otf` (both valid Flutter assets). Do NOT download the variable font unless verifying static instances aren't available.

**Critical verification step (learned from prior cycle):**

```bash
file assets/fonts/Geist-Regular.ttf
# Expected output: "TrueType font data" or "OpenType font data"
# NOT: "HTML document" (GitHub 404 error page)
```

Run `file` command on each downloaded asset BEFORE committing. Prior cycle (`google-fonts-runtime-fetch`) silently pulled HTML error pages as "font files" — only caught during QA.

#### Step 2: Replace Font Files

```bash
# Backup old files (optional safety)
mv assets/fonts/DMSans-Regular.ttf assets/fonts/DMSans-Regular.ttf.bak
mv assets/fonts/DMSans-SemiBold.ttf assets/fonts/DMSans-SemiBold.ttf.bak
mv assets/fonts/DMSans-Bold.ttf assets/fonts/DMSans-Bold.ttf.bak

# Place new files
cp ~/Downloads/Geist-Regular.ttf assets/fonts/
cp ~/Downloads/Geist-SemiBold.ttf assets/fonts/
cp ~/Downloads/Geist-Bold.ttf assets/fonts/

# Verify
file assets/fonts/Geist-*.ttf
```

#### Step 3: Update pubspec.yaml

**Change 1: Update fonts section (lines 89-99)**

```yaml
# BEFORE:
fonts:
  - family: DM Sans
    fonts:
      - asset: assets/fonts/DMSans-Regular.ttf
        weight: 400
      - asset: assets/fonts/DMSans-SemiBold.ttf
        weight: 600
      - asset: assets/fonts/DMSans-Bold.ttf
        weight: 700

# AFTER:
fonts:
  - family: Geist
    fonts:
      - asset: assets/fonts/Geist-Regular.ttf
        weight: 400
      - asset: assets/fonts/Geist-SemiBold.ttf
        weight: 600
      - asset: assets/fonts/Geist-Bold.ttf
        weight: 700
```

**Change 2: Remove dead dependency (line 18)**

```yaml
# BEFORE:
google_fonts: ^8.0.0

# AFTER:
# (line removed)
```

#### Step 4: Replace fontFamily References

49 occurrences across 6 files — all mechanical find-replace:

```dart
// BEFORE:
fontFamily: 'DM Sans'

// AFTER:
fontFamily: 'Geist'
```

**Files:**

1. `lib/app/theme/app_theme.dart` (22 replacements)
2. `lib/app/theme/design_tokens.dart` (10 replacements)
3. `lib/features/setlists/widgets/empty_setlists_state.dart` (1 replacement)
4. `lib/features/home/widgets/rehearsal_card.dart` (8 replacements)
5. `lib/features/home/widgets/potential_gig_card.dart` (7 replacements)
6. `lib/features/home/widgets/empty_section_card.dart` (1 replacement)

**Explicitly NOT touched:**

- `lib/features/setlists/services/setlist_print_service.dart` — PDF export stays on Noto Sans (separate rendering pipeline, out of scope per Tony)

#### Step 5: Update Stale Documentation

`lib/components/ui/README.md` "Future Work" section (lines ~180-185) currently says:

```markdown
## Future Work

If Tony approves Forui after this preview:

1. **Cycle 2:** Address remaining StyleDelta gaps (elevation, disabled colors, etc.)
2. **Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (`#F43F5E`) and dark-only aesthetic
3. **Cycle 4:** Address AppChip (build custom Forui chip widget or investigate FTappable API)
4. **Cycle 5:** Fix facade gap — migrate 5 raw `DropdownButton` usages to AppDropdown
```

**Update line 3 to reflect completion:**

```markdown
3. ~~**Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (`#F43F5E`) and dark-only aesthetic~~ — **COMPLETED** in `feature/forui-theme-integration`
```

**Also update outdated color reference:**  
Line 3 mentions `#F43F5E` (Rose-500) but BandRoadie's actual `AppColors.primary` is Rose-700 `#BE123C`. Correct to:

```markdown
3. ~~**Cycle 3:** Customize Forui theme to match BandRoadie's rose accent (Rose-700 `#BE123C`) and reactive light/dark mode~~ — **COMPLETED** in `feature/forui-theme-integration`
```

---

## Database Impact

**Not applicable** — pure Flutter client-side theming and asset configuration change. No database schema, migrations, RPC functions, RLS policies, or triggers affected.

---

## Flutter Architecture Changes

### Part 1 — Forui Theme

**New code:**

- `lib/app/theme/app_theme.dart` — add `static FThemeData foruiTheme(Brightness brightness)` method

**Modified code:**

- `lib/main.dart` — make `FTheme.data` reactive to `themeModeProvider` (line ~156)

**Architecture pattern:**

- Follows existing `BrandColors` theme extension pattern
- Uses same brightness-switching logic as Material theme
- No new state management — reuses `themeModeProvider`
- FTheme remains InheritedWidget (no API changes)

**Widget impact:**

- 14 Forui-based facade wrappers automatically pick up new colors via `FTheme.of(context)`
- No call-site changes required (facade abstraction holds)
- Existing StyleDelta overrides (from `forui-style-overrides` PR #146) continue to work

### Part 2 — Font Swap

**Modified files:**

- `pubspec.yaml` — update fonts section, remove `google_fonts` dependency
- `lib/app/theme/app_theme.dart` — 22 font family replacements
- `lib/app/theme/design_tokens.dart` — 10 font family replacements
- `lib/features/setlists/widgets/empty_setlists_state.dart` — 1 replacement
- `lib/features/home/widgets/rehearsal_card.dart` — 8 replacements
- `lib/features/home/widgets/potential_gig_card.dart` — 7 replacements
- `lib/features/home/widgets/empty_section_card.dart` — 1 replacement

**Asset changes:**

- Remove: `assets/fonts/DMSans-Regular.ttf`, `DMSans-SemiBold.ttf`, `DMSans-Bold.ttf`
- Add: `assets/fonts/Geist-Regular.ttf`, `Geist-SemiBold.ttf`, `Geist-Bold.ttf`

**Architecture impact:**

- Zero — same local bundling mechanism, just different font files
- PDF export unchanged (Noto Sans isolated in `setlist_print_service.dart`)

---

## Files to Create

**None** — all changes are modifications to existing files.

---

## Files to Modify

| File                                                      | What Changes                                                                                                                         |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Part 1 — Forui Theme**                                  |
| `lib/app/theme/app_theme.dart`                            | Add `static FThemeData foruiTheme(Brightness brightness)` method that maps `BrandColors` to `FColors`                                |
| `lib/main.dart`                                           | Make `FTheme.data` reactive: `data: AppTheme.foruiTheme(brightness)` where brightness is derived from `ref.watch(themeModeProvider)` |
| **Part 2 — Font Swap**                                    |
| `pubspec.yaml`                                            | Update `fonts:` section family name `DM Sans` → `Geist`, update asset paths. Remove `google_fonts: ^8.0.0` dependency.               |
| `assets/fonts/` (directory)                               | Remove 3 DM Sans TTF files, add 3 Geist TTF files (verified with `file` command)                                                     |
| `lib/app/theme/app_theme.dart`                            | Replace 22 occurrences of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                            |
| `lib/app/theme/design_tokens.dart`                        | Replace 10 occurrences of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                            |
| `lib/features/setlists/widgets/empty_setlists_state.dart` | Replace 1 occurrence of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                              |
| `lib/features/home/widgets/rehearsal_card.dart`           | Replace 8 occurrences of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                             |
| `lib/features/home/widgets/potential_gig_card.dart`       | Replace 7 occurrences of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                             |
| `lib/features/home/widgets/empty_section_card.dart`       | Replace 1 occurrence of `fontFamily: 'DM Sans'` → `fontFamily: 'Geist'`                                                              |
| `lib/components/ui/README.md`                             | Update "Future Work" section: mark Cycle 3 complete, correct color from Rose-500 to Rose-700                                         |

---

## Files Off-Limits

| File                                                        | Reason                                                                                                              |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `lib/main.dart` (initialization order)                      | Only modify FTheme builder block (lines ~154-162). Do NOT touch initialization sequence before `runApp()`.          |
| `lib/features/setlists/services/setlist_print_service.dart` | PDF export stays on Noto Sans — separate rendering pipeline (`printing` package), explicitly out of scope per Tony. |
| `lib/app/theme/theme_mode_controller.dart`                  | State management logic must not change — only consumed, not modified.                                               |
| All test files                                              | No test updates required (theme/font changes are visual, not behavioral). Existing tests pass without modification. |
| `pubspec.lock`                                              | Auto-generated, do not manually edit.                                                                               |

---

## System Impact Map

| System                                 | Impact                                                                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| Gigs                                   | **affected** — UI widgets render with rose accent, Geist font                                          |
| Rehearsals                             | **affected** — UI widgets render with rose accent, Geist font                                          |
| Setlists / Catalog                     | **affected** — UI widgets render with rose accent, Geist font (PDF export unaffected)                  |
| Members / RBAC                         | **affected** — UI widgets render with rose accent, Geist font                                          |
| Auth / Session                         | **affected** — login/signup screens render with rose accent, Geist font                                |
| Routing                                | unaffected — no navigation changes                                                                     |
| Notifications                          | unaffected — backend/trigger logic unchanged                                                           |
| Platform (iOS / Android / Web / macOS) | **affected** — all platforms see consistent theming and font (Geist renders natively on all platforms) |

---

## Regression Risk

**Level:** **LOW-MEDIUM**

### Risk Factors

**Part 1 — Forui Theme (LOW risk):**

- Minimal color overrides (only `primary` and `primaryForeground`) reduce surface area for visual regressions
- Stock Forui Neutral palette is battle-tested across Forui's own documentation and examples
- Brightness switching reuses existing `themeModeProvider` logic (proven stable)
- FTheme is already wired (just changing data parameter)
- All 14 Forui widgets inherit theme automatically (no call-site changes)
- Material theme unaffected (separate code path)

**Part 2 — Font Swap (MEDIUM risk):**

- 48 find-replace operations across 6 files (potential typo risk)
- Font rendering is platform-dependent — requires visual verification on iOS/Android/Web/macOS
- Download verification is critical (prior cycle nearly shipped HTML error pages as fonts)
- Font metrics may differ from DM Sans (character widths, line heights) → potential layout shifts

**Mitigations:**

1. Download verification with `file` command (non-negotiable)
2. Visual regression testing across all major screens (Home, Setlists, Gigs, Settings)
3. Multi-platform verification (at least web + iOS OR Android)
4. Diff review of all 48 font family changes (catch typos before commit)

**Rollback path:**

- Part 1: Revert `lib/main.dart` and `lib/app/theme/app_theme.dart` changes → back to stock Forui neutral theme
- Part 2: Restore DM Sans fonts to `assets/fonts/`, revert font family changes, restore `google_fonts` dependency

---

## Engineer Task Breakdown

Execute in strict order. Do NOT skip verification steps.

### Phase A — Forui Theme Integration

**A1. Create theme builder function**

- Open `lib/app/theme/app_theme.dart`
- Add `static FThemeData foruiTheme(Brightness brightness)` method after `darkTheme` getter
- Start from `FColors.neutralLight` or `FColors.neutralDark` based on brightness
- Override only `primary` (to `AppColors.primary` — Rose-700 `#BE123C`) and `primaryForeground` (to `Colors.white`) via `copyWith`
- Return `FThemeData(colors: colors, touch: true)` — all other Forui color slots remain Forui's stock Neutral values

**A2. Make FTheme reactive**

- Open `lib/main.dart`
- Find `FTheme(` invocation (line ~156)
- Wrap in block that derives brightness from `ref.watch(themeModeProvider)`
- Replace `data: FTheme.neutral.dark.touch` with `data: AppTheme.foruiTheme(brightness)`

**A3. Verify import statements**

- Ensure `lib/main.dart` imports `package:flutter/services.dart` (for SystemUiOverlayStyle)
- Ensure `lib/app/theme/app_theme.dart` imports `package:forui/forui.dart`

### Phase B — Font Download and Verification

**B1. Download Geist fonts**

- Navigate to https://github.com/vercel/geist-font/releases
- Download latest release
- Extract static TTF files for weights 400, 600, 700
- If only variable font available, extract static instances using fonttools or similar

**B2. Verify downloaded fonts (MANDATORY)**

```bash
cd ~/Downloads  # or wherever fonts were extracted
file Geist-Regular.ttf
file Geist-SemiBold.ttf
file Geist-Bold.ttf
```

- **Expected output:** "TrueType font data" or "OpenType font data"
- **If output says "HTML document":** Download failed, GitHub served 404 page. Re-download correct asset.
- **Do NOT proceed to B3 until all 3 files verify as font data.**

**B3. Replace font files**

```bash
cd /path/to/bandroadie
rm assets/fonts/DMSans-Regular.ttf
rm assets/fonts/DMSans-SemiBold.ttf
rm assets/fonts/DMSans-Bold.ttf
cp ~/Downloads/Geist-Regular.ttf assets/fonts/
cp ~/Downloads/Geist-SemiBold.ttf assets/fonts/
cp ~/Downloads/Geist-Bold.ttf assets/fonts/
```

### Phase C — Font Configuration

**C1. Update pubspec.yaml**

- Change `fonts:` section family name `DM Sans` → `Geist`
- Update asset paths to `assets/fonts/Geist-*.ttf`
- Remove `google_fonts: ^8.0.0` from dependencies section
- Run `flutter pub get`

**C2. Replace font family references**

Use global find-replace in IDE:

- Find: `fontFamily: 'DM Sans'`
- Replace: `fontFamily: 'Geist'`
- Scope: 6 files listed in "Files to Modify" table
- Review each replacement in diff before committing

**Files (49 total replacements):**

1. `lib/app/theme/app_theme.dart` — 22
2. `lib/app/theme/design_tokens.dart` — 10
3. `lib/features/setlists/widgets/empty_setlists_state.dart` — 1
4. `lib/features/home/widgets/rehearsal_card.dart` — 8
5. `lib/features/home/widgets/potential_gig_card.dart` — 7
6. `lib/features/home/widgets/empty_section_card.dart` — 1

**Verification:**

```bash
# Confirm all 49 replaced
rg "fontFamily: 'DM Sans'" lib/
# Expected: 0 results

# Confirm PDF service untouched
rg "Noto Sans" lib/features/setlists/services/setlist_print_service.dart
# Expected: 4 results (Regular, Bold, Italic, BoldItalic)
```

### Phase D — Documentation Updates

**D1. Update README.md**

- Open `lib/components/ui/README.md`
- Find "Future Work" section (line ~183)
- Mark Cycle 3 as complete with strikethrough
- Correct color reference from Rose-500 `#F43F5E` to Rose-700 `#BE123C`
- Add note: "— **COMPLETED** in `feature/forui-theme-integration`"

### Phase E — Build and Verification

**E1. Clean build**

```bash
flutter clean
flutter pub get
flutter analyze
```

- **Expected:** 0 errors, 0 warnings

**E2. Build for web (primary target)**

```bash
flutter run -d chrome
```

- Open DevTools → Network tab
- Confirm NO requests to fonts.gstatic.com
- Confirm NO requests to font CDNs

**E3. Visual verification checklist**

- [ ] Home screen: rehearsal cards, gig cards, text all render in Geist
- [ ] Setlists: song cards, BPM/duration metrics render in Geist
- [ ] Settings: toggle light/dark mode
  - [ ] Forui widgets (buttons, switches, text fields) change color
  - [ ] Rose accent visible in both modes
  - [ ] Background switches (white→dark gray, black→white)
- [ ] Login screen: text fields, buttons use rose accent + Geist
- [ ] AppBar: title text renders in Geist
- [ ] Bottom nav: icon labels render in Geist

**E4. Cross-platform verification (if time permits)**

```bash
flutter run -d macos      # or
flutter run -d ios        # or
flutter run -d android
```

- Repeat visual checklist on at least one additional platform

---

## Verification Plan

### Tier 1 — Pre-deployment

Not applicable — no database or backend changes.

### Tier 2 — Post-deployment (after `flutter clean && flutter pub get`)

**POST-DEPLOY TEST 1: Verify font files exist**

```bash
ls -la assets/fonts/

# Expected output:
# Geist-Regular.ttf
# Geist-SemiBold.ttf
# Geist-Bold.ttf
# NotoSans-Regular.ttf
# NotoSans-Bold.ttf
# NotoSans-Italic.ttf
# NotoSans-BoldItalic.ttf
```

**POST-DEPLOY TEST 2: Verify font files are valid**

```bash
file assets/fonts/Geist-*.ttf

# Expected output for each:
# "TrueType font data" or "OpenType font data"
# NOT "HTML document" or "ASCII text"
```

**POST-DEPLOY TEST 3: Verify pubspec.yaml fonts section**

```bash
grep -A 8 "family: Geist" pubspec.yaml

# Expected:
# family: Geist
# fonts:
#   - asset: assets/fonts/Geist-Regular.ttf
#     weight: 400
#   - asset: assets/fonts/Geist-SemiBold.ttf
#     weight: 600
#   - asset: assets/fonts/Geist-Bold.ttf
#     weight: 700
```

**POST-DEPLOY TEST 4: Verify google_fonts removed**

```bash
grep "google_fonts" pubspec.yaml

# Expected: 0 results
```

**POST-DEPLOY TEST 5: Verify DM Sans removed**

```bash
rg "DM Sans" lib/ --type dart

# Expected: 0 results in code
```

**POST-DEPLOY TEST 6: Verify Geist references**

```bash
rg "fontFamily: 'Geist'" lib/ --type dart --count

# Expected: 49 total across 6 files
```

**POST-DEPLOY TEST 7: Verify PDF service untouched**

```bash
rg "Noto Sans" lib/features/setlists/services/setlist_print_service.dart

# Expected: 4 results (Regular, Bold, Italic, BoldItalic)
```

**POST-DEPLOY TEST 8: Flutter analyze passes**

```bash
flutter analyze

# Expected: 0 issues
```

**POST-DEPLOY TEST 9: App builds for web**

```bash
flutter build web --release

# Expected: build succeeds, no font-related errors
```

**POST-DEPLOY TEST 10: Verify Forui theme reactivity**

Manual test in running app:

1. Launch app: `flutter run -d chrome`
2. Navigate to Settings
3. Toggle "Light Mode" switch
4. **Expected behavior:**
   - Background switches: dark gray → white
   - Text color switches: white → black
   - Rose accent visible in both modes
   - No console errors
   - Switch animates smoothly
5. Toggle back to dark mode
6. **Expected:** reverts to dark theme, no errors

**POST-DEPLOY TEST 11: Visual spot-check (Forui widgets)**

Manual test in running app (dark mode):

1. Home screen:
   - [ ] Rehearsal cards have rose outline (not gray)
   - [ ] Button text renders in Geist
2. Setlists screen:
   - [ ] "Add Song" button is rose (not gray)
   - [ ] Song cards render Geist font
3. Login screen (logout first):
   - [ ] Text field borders/focus state use rose
   - [ ] "Send Magic Link" button is rose
   - [ ] Input text renders in Geist

**POST-DEPLOY TEST 12: Visual spot-check (light mode)**

Manual test (switch to light mode in Settings):

1. Home screen:
   - [ ] Background is white (not dark)
   - [ ] Text is black (not white)
   - [ ] Rose accent still visible
2. Settings screen:
   - [ ] Surface cards are light gray (not dark)
   - [ ] Toggle switches animate correctly

---

## QA Regression Areas

### Primary Validation (Must Test)

1. **Theme switching (core feature):**
   - Settings → toggle "Light Mode" → verify background/text/accent colors switch
   - Confirm rose accent visible in both modes (not gray)
   - No console errors during switch

2. **Font rendering (core feature):**
   - Visual check: all text renders in Geist across Home, Setlists, Gigs, Settings
   - No missing characters or rendering glitches
   - Line heights/spacing look reasonable (no major layout shifts)

3. **Cross-widget consistency:**
   - Material widgets (raw Flutter components) vs Forui widgets (UI facade) — both use rose accent
   - No "mixed brand" appearance (gray buttons next to rose buttons)

### Secondary Validation (Spot Check)

4. **Forui facade wrappers:**
   - AppButton: rose background (not gray) in both themes
   - AppTextField: rose border on focus (not gray)
   - AppSwitch: rose active color (not gray)
   - AppCheckbox: rose checkmark (not gray)
   - AppCard: correct background color in both themes

5. **PDF export (sanity check):**
   - Generate setlist PDF
   - Confirm PDF renders in Noto Sans (NOT Geist)
   - Text is readable, no missing glyphs

6. **Platform-specific (if time):**
   - iOS: font renders correctly, system keyboard appears
   - Android: font renders correctly, back button works
   - macOS: font renders correctly, window resize works

---

## Rollout / Migration Strategy

**Not applicable** — client-only visual change, no data migration, no backend deployment, no database schema changes.

**Deployment:**

- Merge PR into main
- Deploy web via `./tools/deploy_web.sh`
- Native apps: next App Store / Play Store release cycle

**Feature flag:** Not needed — visual change only, no risk of data corruption.

**Rollback:** Revert PR, redeploy. No data cleanup required.

---

## Out of Scope

1. **PDF export font change** — `lib/features/setlists/services/setlist_print_service.dart` stays on Noto Sans (separate rendering pipeline, explicit user requirement)

2. **AppColors.primary doc comment correction** — comment claims Rose-500, actual value is Rose-700. This plan uses the constant as truth. Correcting the comment is Tony's decision, not this cycle's.

3. **Forui typography customization** — only colors are customized, not font sizes/weights/line heights defined in FThemeData. Forui's preset typography is used as-is.

4. **Full BrandColors palette mapping** — only `primary` and `primaryForeground` are overridden. Background, surface, text, border, error, and other semantic colors intentionally remain Forui's stock Neutral values. Incremental brand color refinement is deferred to a future cycle.

5. **Material theme changes** — `AppTheme.lightTheme`/`.darkTheme` are not modified. Only FTheme changes.

6. **AppChip Forui swap** — still Material-only (no Forui equivalent), unchanged from PR #145/146 state.

7. **Facade gap fix** — 5 raw `DropdownButton` usages that bypass `AppDropdown` are not migrated (separate future work).

8. **Animation/transition customization** — theme changes apply instantly, no custom transition animations.

9. **Haptic feedback tuning** — Forui's default haptic feedback settings used as-is.

10. **Dark mode preference persistence** — already handled by `theme_mode_controller.dart`, not modified.
