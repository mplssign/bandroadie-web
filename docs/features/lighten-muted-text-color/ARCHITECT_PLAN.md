# ARCHITECT_PLAN.md

## Feature Slug

`feature/lighten-muted-text-color`

## Feature Title

Lighten the app's muted/label text color (Zinc-500 → Zinc-300)

## Problem Summary

The design-token color `BrandColors.dark.textMuted` — used app-wide via
`context.colors.textMuted` for secondary labels, timestamps, helper text,
detail-row labels (e.g. "Soundcheck", "Load in" in the gig drawer that
prompted this) — is currently rendered at Zinc-500 (`0xFF71717A`). Against
the app's dark surfaces (`0xFF09090B` background, `0xFF18181B` surface,
`0xFF27272A` elevated surface) this reads as too dim for comfortable
scanning. Tony has given an explicit, unambiguous target: two shades
lighter on the Zinc scale — Zinc-300 (`0xFFD4D4D8`).

## Root Cause

**Confidence: HIGH** (confirmed by reading source).

The value `Color(0xFF71717A)` is set literally at
[lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart#L57)
inside the `BrandColors.dark` static instance. This is the single source
of truth for the token; every reachable read of muted text color in the
UI resolves through the `BrandColorsX.colors` extension defined at
[lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart#L158-L165),
which reads the `BrandColors` `ThemeExtension` registered on the active
`ThemeData`. So a one-line value change at line 57 is the complete fix —
there is no shadow copy, no per-widget hardcode of Zinc-500 that is
supposed to track this token, and no runtime derivation that would
override it.

Two other files in `lib/` also literally spell `0xFF71717A`, but they are
independent constants with their own design rationale, **not** aliases
of `textMuted`:

- [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart#L158-L159)
  — `AppColors.switchTrackOff`, documented as "chosen to clear WCAG 2.1
  SC 1.4.11 (3:1) against every dark surface the app renders switches on."
  Deliberate. Do not touch.
- [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart#L18)
  — `kEdMutedForegroundFaint`, used at exactly one site
  ([lib/features/events/widgets/event_editor_actions.dart](lib/features/events/widgets/event_editor_actions.dart#L39)),
  scoped to the event editor drawer's Forui-themed subtree.
  Independent constant, not routed through `BrandColors`. Whether it
  should track `textMuted` is a separate question Tony has not asked;
  see Out of Scope.

## Existing System Analysis

**Theme wiring** (all HIGH confidence):

- [lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart)
  defines `BrandColors extends ThemeExtension<BrandColors>` with two
  static instances (`dark`, `light`) and a `BrandColorsX.colors`
  `BuildContext` extension.
- [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart#L49) registers
  `BrandColors.dark` on `darkTheme.extensions`;
  [lib/app/theme/app_theme.dart](lib/app/theme/app_theme.dart#L342) registers
  `BrandColors.light` on `lightTheme.extensions`.
- [lib/main.dart](lib/main.dart#L168) wires
  `themeMode: ref.watch(themeModeProvider)` on `MaterialApp` with both
  `theme: AppTheme.lightTheme` and `darkTheme: AppTheme.darkTheme`.
- [lib/app/theme/theme_mode_controller.dart](lib/app/theme/theme_mode_controller.dart)
  starts in `ThemeMode.dark`, loads
  `SharedPreferences('light_mode_enabled')` async, and exposes `toggle()`.
- [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart#L388)
  renders `_LightModeToggle`, a user-facing switch that calls that
  `toggle()`.

**Conclusion re: the light theme.** The
`.github/copilot-instructions.md` line "Dark mode only, rose accent
`#F43F5E`" describes intended UX. The **implementation** actually
supports a user-toggleable light mode that persists across restarts, so
`BrandColors.light` is reachable and not dead code. However, its current
state is clearly a not-yet-designed placeholder:
`light.textPrimary`, `light.textSecondary`, and `light.textMuted` are
**all** set to `0xFF020617` (Slate-950 near-black), so there is no
existing "muted" semantic in light mode to preserve or improve. Applying
Tony's target `0xFFD4D4D8` (Zinc-300) to `light.textMuted` would produce
Zinc-300 text on a Slate-50 (`0xFFF8FAFC`) background — a contrast
ratio of roughly **1.15:1**, well below WCAG AA's 4.5:1 for normal
text, and it would make muted text nearly invisible in light mode.
Therefore this plan leaves `light.textMuted` untouched — see Proposed
Solution.

**Usage surface.** `context.colors.textMuted` is referenced 150 times
across 64 files under `lib/` (grep count; Manager's estimate of 139/64
was slightly low but same order of magnitude). Every reference is a
consumer of the token, not a redefinition. Wide blast radius, but the
change is mechanically a single value swap.

**Existing test coverage for this token.** Zero. No test in `test/` reads
`textMuted` or the literal `0xFF71717A`. The two theme-adjacent tests
([test/app/theme/rose_primary_color_test.dart](test/app/theme/rose_primary_color_test.dart)
and
[test/features/financials/widgets/transaction_card_test.dart](test/features/financials/widgets/transaction_card_test.dart))
assert other tokens (`primaryDim`, `primarySubtle`, `success`) and are
not affected by this change.

## Proposed Solution

Change `BrandColors.dark.textMuted` from `Color(0xFF71717A)` to
`Color(0xFFD4D4D8)` in
[lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart#L57).
Leave `BrandColors.light.textMuted` untouched. Add a unit test locking
in the new value (and one asserting the light-theme value is
unchanged) to
[test/app/theme/rose_primary_color_test.dart](test/app/theme/rose_primary_color_test.dart)
— this test file already imports `BrandColors` and asserts other
token values in the same style, so co-locating there beats creating a
new file for one assertion pair.

That is the entire fix. No new files, no new classes, no new
dependencies, no controller/provider/repository changes, no schema
change, no migration, no init-order change.

## Database Impact

n/a

## Flutter Architecture Changes

n/a — no controller, provider, repository, model, service, screen, or
routing changes. Only a design-token value swap and its lock-in test.

## Files to Create

n/a

## Files to Modify

- [lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart)
  — line 57: change the `textMuted` value in the `BrandColors.dark`
  static const from `Color(0xFF71717A)` to `Color(0xFFD4D4D8)`. Do not
  touch any other field in `BrandColors.dark`. Do not touch any field
  in `BrandColors.light`.
- [test/app/theme/rose_primary_color_test.dart](test/app/theme/rose_primary_color_test.dart)
  — add two `test(...)` cases inside the existing
  `group('Rose Primary Color Swap Verification', ...)`:
  1. `test('BrandColors.dark.textMuted is Zinc-300 #D4D4D8', ...)`
     asserting `BrandColors.dark.textMuted` equals
     `const Color(0xFFD4D4D8)`.
  2. `test('BrandColors.light.textMuted is unchanged (#020617)', ...)`
     asserting `BrandColors.light.textMuted` equals
     `const Color(0xFF020617)`.

  These two asserts serve as a regression tripwire against silent
  drift and against a well-meaning follow-up patch accidentally
  bringing `light.textMuted` along.

## Files Off-Limits

- [lib/app/theme/design_tokens.dart](lib/app/theme/design_tokens.dart)
  — `AppColors.switchTrackOff = Color(0xFF71717A)` is deliberate and
  WCAG-motivated per its comment. Off-limits.
- [lib/app/theme/event_editor_theme.dart](lib/app/theme/event_editor_theme.dart)
  and [lib/features/events/widgets/event_editor_actions.dart](lib/features/events/widgets/event_editor_actions.dart)
  — `kEdMutedForegroundFaint = Color(0xFF71717A)` is a separate
  Forui-scoped constant. Whether it should also be lightened is a
  distinct decision Tony has not made. Off-limits for this feature.
- All 64 consumer files under `lib/` that read
  `context.colors.textMuted`. They **must not** be edited — the whole
  point of the token indirection is that they auto-pick up the change.
  Editing any of them would defeat the design and introduce hardcodes.
- Every other field of `BrandColors.dark` and every field of
  `BrandColors.light`. This is a single-token fix.

## Change Budget

- **Expected net line delta per file:**
  - `lib/app/theme/brand_colors.dart`: **0** (one-value replacement,
    no line added or removed).
  - `test/app/theme/rose_primary_color_test.dart`: **+8 to +10** (two
    small `test(...)` blocks inside the existing group).
- **Expected new files:** 0.
- **Expected new public classes / methods:** 0.
- **Expected new dependencies:** 0.

QA should measure the actual diff against these numbers. Anything
materially larger — new files, new classes, edits to any of the 64
consumer widgets, edits to `event_editor_theme.dart` /
`design_tokens.dart` / `app_theme.dart` — is out of scope for this
plan.

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Gigs | affected (visual) | Gig drawer detail-row labels ("Soundcheck", "Load in", etc.) render lighter — this is the reported symptom. |
| Rehearsals | affected (visual) | `view_rehearsal_drawer.dart` and rehearsal form fields use `textMuted`. |
| Setlists | affected (visual) | Many setlist widgets use `textMuted` (song details, pause/set-break creators, empty states). No logic changes. |
| Members / Contacts | affected (visual) | `band_member_detail_drawer.dart`, `contact_detail_drawer.dart` labels lighten. |
| Auth | unaffected | Auth screens do not read `textMuted`. |
| Routing | unaffected | Pure theme value change. |
| Notifications | affected (visual) | Notification card and settings modal read `textMuted`. |
| Home / Financials / Calendar / Lyrics / Songs | affected (visual) | Various label / helper text lightens. |
| Platforms | affected (visual, all) | iOS, Android, macOS, Web — no platform-conditional code touched. Init order untouched. Firebase / DeepLinkService untouched. |
| Database / RLS / RPC | unaffected | No SQL. |
| Config (`--dart-define`) | unaffected | No config touched. |

## Regression Risk

**LOW** overall.

Rationale: no auth, session, routing, init-order, database, RPC, RLS,
config, or platform-conditional code is touched. No logic path
changes. The change is a single design-token value.

The wide surface (150 usages, 64 files) is a **UX / accessibility**
concern, not a code-regression concern — Zinc-300 on the app's dark
surfaces yields contrast ratios well above WCAG AA for normal text
(roughly 12:1 against `0xFF09090B` background, 11:1 against
`0xFF18181B` surface, 9:1 against `0xFF27272A` elevated surface), so
legibility improves everywhere. The only theoretical worry is that a
specific screen might have designed its layout around muted text
being visually subordinate to nearby non-`textMuted` elements; see
QA Regression Areas and the Owner-Run Punch List for how that gets
caught.

## Engineer Task Breakdown

1. Open [lib/app/theme/brand_colors.dart](lib/app/theme/brand_colors.dart)
   and, inside the `BrandColors.dark` `static const` block (around line
   57), change the `textMuted` field's value from
   `Color(0xFF71717A)` to `Color(0xFFD4D4D8)`. Do not modify any other
   field. Do not add a comment beyond an optional one-line
   `// Zinc-300` at end of line if it aids scanning — no
   multi-line doc comment.
2. Open [test/app/theme/rose_primary_color_test.dart](test/app/theme/rose_primary_color_test.dart)
   and add, inside the existing
   `group('Rose Primary Color Swap Verification', ...)`, two `test(...)`
   cases matching the style of the surrounding tests:
   - `test('BrandColors.dark.textMuted is Zinc-300 #D4D4D8', () { expect(BrandColors.dark.textMuted, equals(const Color(0xFFD4D4D8))); });`
   - `test('BrandColors.light.textMuted is unchanged (#020617)', () { expect(BrandColors.light.textMuted, equals(const Color(0xFF020617))); });`
3. Do not edit any other file. In particular, do not edit
   `event_editor_theme.dart`, `design_tokens.dart`, `app_theme.dart`,
   or any of the 64 files that consume `context.colors.textMuted`.

## Verification Plan

**Tier 1 — pre-deploy, mechanical (QA-runnable, no running app required):**

1. `flutter analyze` returns clean (no new warnings from either
   modified file).
2. `flutter test test/app/theme/rose_primary_color_test.dart` passes,
   including the two new assertions.
3. Full `flutter test` suite still passes (the two existing
   theme-adjacent tests —
   `test/app/theme/rose_primary_color_test.dart` and
   `test/features/financials/widgets/transaction_card_test.dart` —
   should be unaffected).
4. Static grep audit: `grep -rn "0xFF71717A" lib/` returns exactly
   two matches after the change — `design_tokens.dart` line 159 and
   `event_editor_theme.dart` line 18. Any third match means either
   `brand_colors.dart` was not updated, or an unintended file was
   changed. Also `grep -rn "0xFFD4D4D8" lib/app/theme/brand_colors.dart`
   returns exactly one match (the new value). QA runs both greps and
   reports the counts.
5. Static grep audit: `grep -rn "textMuted" lib/` shows the same 150
   matches across 64 files (verifying no consumer was accidentally
   edited).

Tier 1 tests never call anything they replace — they read the new
value directly and assert it, which is the correct pattern for a
design-token change.

**Tier 2 — post-deploy:** n/a. There is no database change, no
migration, no RPC, no edge function. Nothing runs in production
against Supabase as a result of this feature.

**Owner-run punch list (Tony, at PR-test time — QA cannot execute
these because QA cannot launch the app):**

1. On dark mode (default), open a gig with soundcheck / load-in
   times set and view its detail drawer.
   *Expected:* the label text on the left ("Soundcheck", "Load in",
   date row label, etc.) is visibly lighter than before but still
   clearly less prominent than the primary value text on the right.
2. Same dark mode: open a rehearsal drawer with location / notes set.
   *Expected:* helper / label text is legible without straining;
   no label appears to have vanished into the background.
3. Same dark mode: open Home, Setlists (including a setlist detail
   with song rows), Calendar, and Notifications tab. Spot-check for
   any screen where the lighter muted text now visually competes with
   or dominates its adjacent primary text — none is expected, but
   this is where a hierarchy-inversion problem would show up first.
4. Toggle to light mode via Settings → *Light mode* switch.
   *Expected:* light-theme text appearance is **identical** to
   before this PR (all three text tokens remain near-black on
   Slate-50). If muted text has visibly changed color in light
   mode, `light.textMuted` was accidentally modified — fail.
5. Toggle back to dark mode.
   *Expected:* dark theme active, lightened muted text still
   applied.

Steps 1–5 are the exact numbered walk-through Tony runs. Do not
delegate any of them to QA.

## QA Regression Areas

Focus on Tier 1 items above. Beyond those:

- **Do not** attempt to launch the app, run `./run.sh`, spin up a
  simulator/emulator, or use `flutter_driver` — this pipeline
  cannot execute them, and the fix is entirely mechanical from a
  QA-gate perspective.
- Confirm the diff touches exactly two files
  (`lib/app/theme/brand_colors.dart` and
  `test/app/theme/rose_primary_color_test.dart`). If any other file
  is modified, that is a plan violation — flag it.
- Confirm the change to `brand_colors.dart` is a single-value swap
  on the `textMuted` line inside `BrandColors.dark`, and that
  `BrandColors.light` is byte-identical to `main`. QA can verify
  this with `git diff main -- lib/app/theme/brand_colors.dart` and
  by grepping for `light.textMuted` in the diff output (expected:
  no line touched inside the `light` block).
- Confirm Change Budget numbers hold (net delta on `brand_colors.dart`
  is 0 ± 1 line; net delta on the test file is +8 to +10 lines).
  Materially larger diffs get flagged.

## Rollout Strategy

Ship in a single PR against `main`. No feature flag, no staged
rollout, no data backfill — this is a pure client-side visual
token change. Web and native platforms pick it up on the next
build/deploy of each respective release channel. If a regression
is spotted post-merge, `git revert` of the single commit fully
restores the prior appearance; there is no state to unwind.

## Out of Scope

- **`BrandColors.light.textMuted`.** The light theme is reachable
  (via Settings → Light mode toggle) but is currently a placeholder
  where `textPrimary`, `textSecondary`, and `textMuted` are all
  Slate-950. Applying Zinc-300 there would drop contrast on the
  Slate-50 background to ~1.15:1 and fail WCAG. A proper light-theme
  color-token pass is a separate, larger feature.
- **`kEdMutedForegroundFaint` in
  `event_editor_theme.dart`.** This is an independent constant
  (also literally `0xFF71717A`) used in the event editor drawer's
  Forui subtree. Whether the event editor's muted text should also
  lighten is a separate decision. Not addressed here.
- **`AppColors.switchTrackOff` in `design_tokens.dart`.** Also
  literally `0xFF71717A` but deliberate — its comment cites WCAG
  2.1 SC 1.4.11 (3:1 non-text contrast) as the design constraint.
  Not addressed here.
- **Visual-hierarchy inversion note (flag, do not fix here).** After
  this change, `dark.textMuted` (Zinc-300, `#D4D4D8`) will render
  **lighter / more prominent** than `dark.textSecondary` (Zinc-400,
  `#A1A1AA`). Typical design vocabularies expect "muted" to be less
  prominent than "secondary", so this inverts the token semantics
  in the dark theme. Tony gave an explicit unambiguous target, so
  this plan honors it, but the inversion is worth a follow-up
  conversation — either rename `textMuted` to match its new visual
  weight, or revisit `textSecondary` in a subsequent pass. Flagging
  in this document is the entirety of the response for this
  feature; no action taken.
- **Contrast-audit sweep across all 64 consumer files.** Zinc-300 on
  the app's three dark surfaces clears WCAG AA for normal text by
  a wide margin, so a full audit is not warranted. If a specific
  screen turns out to have designed against muted-being-subordinate,
  it will surface in the Owner-Run Punch List and can be handled as
  a distinct follow-up.
