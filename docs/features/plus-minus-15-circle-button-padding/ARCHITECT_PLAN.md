# ARCHITECT_PLAN — plus-minus-15-circle-button-padding

## Feature Slug
`feature/plus-minus-15-circle-button-padding`

## Feature Title
Give the "-15" and "+15" circle buttons more padding around the number

## Problem Summary
The circular "-15" and "+15" step buttons in the event Duration selector render as
tight 40 × 40 circles with only a few pixels of breathing room around the "-15" /
"+15" label. The label reads visually cramped inside the circle. Enhancement: grow
the circle so there is visibly more space between the number and the circle's
edge, without changing the label's font size and without disturbing surrounding
layout.

## Root Cause (Confidence: HIGH — confirmed in code)
The buttons are built inline in `_buildDurationSelector` in
[lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart#L459-L544).

Each button is:

```dart
GestureDetector(
  onTap: ...,
  child: Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: roseColor),
    ),
    child: Center(
      child: Text(
        '-15',              // or '+15'
        style: TextStyle(
          fontSize: AppFontSizes.body,   // 16.0
          fontWeight: FontWeight.w600,
          color: roseColor,
        ),
      ),
    ),
  ),
),
```

There is no `padding` property — the perceived padding is `(diameter - textWidth) / 2`
on each side. At 40 px diameter with a 16 px / w600 label "-15" (≈28–30 px wide),
that leaves only ~5–6 px of breathing room per side. The circle also sits at 40 px,
which is below the project's stated minimum 48 px touch target
(`.github/copilot-instructions.md` → "minimum touch target: 48px").

Root cause: the container diameter is too tight for the label. Increasing the
diameter — while leaving the `Text` style untouched — directly increases the
`(diameter - textWidth) / 2` gap on all sides and simultaneously brings the tap
target to the project-standard 48 px.

## Existing System Analysis
- The "-15" / "+15" pair is used in **exactly one place** and is **not extracted
  into a shared widget**. Grep for `-15` / `+15` across `lib/**` returns matches
  only in `event_form_fields.dart` (lines 494 and 532); the only other hit is an
  unrelated docstring in `external_song_lookup_service.dart` for search-ranking
  weights.
- Both circles are visually and structurally symmetric (same size, same border,
  same text style; only the label sign and the enabled/disabled logic differ).
- The stepper Row is
  `Row(mainAxisAlignment: MainAxisAlignment.center, [circle, SizedBox(120), circle])`.
  Total intrinsic width today: 40 + 120 + 40 = **200 px**. After bump to 48:
  48 + 120 + 48 = **216 px** — still well below the drawer's usable width, so no
  overflow risk.
- A visually similar `+5` / `-5` minute stepper exists in
  `lib/features/setlists/widgets/set_break_creator.dart` and
  `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart`. It is a
  different control (different label text, different step value, different
  screen). The Feature Input scopes this change specifically to "-15" / "+15", so
  the set-break steppers are **explicitly out of scope**.
- The 44 × 44 circular buttons elsewhere in the app (calendar app bar, home app
  bar, setlist app bars, category buttons) are icon-only chevron / add / menu
  buttons — a different visual pattern, not text-label steppers. Out of scope.

## Proposed Solution
Change the circle `Container` diameter for both the "-15" and "+15" buttons from
**40 × 40 → 48 × 48**. Leave the `Text` style (`fontSize: AppFontSizes.body` = 16,
`fontWeight: FontWeight.w600`) unchanged.

**Why 48:**
1. **Project convention.** `.github/copilot-instructions.md` explicitly names 48
   px as the minimum touch target. This change aligns the stepper with that
   standard.
2. **Concrete padding delta.** With 16 px / w600 "-15" (~28–30 px wide), padding
   per side grows from ~5–6 px to ~9–10 px — a clearly perceptible increase
   without over-inflating the control.
3. **Symmetry and layout safety.** Row math (48 + 120 + 48 = 216) stays well
   inside the drawer's content width on all supported screen sizes (smallest
   supported iPhone ≈ 320 px content width). No overflow risk, no wrap risk.
4. **Minimal.** Four literal changes, no new imports, no new tokens, no
   structural refactor.

Rejected alternatives:
- Adding an explicit `padding:` on the `Container` while keeping `width/height` —
  works, but `Container` cannot combine `padding` with `BoxDecoration(shape:
  BoxShape.circle)` and also produce a perfectly round circle around a
  padded child unless the label is a specific size. Adjusting the diameter is
  cleaner and idiomatic for a circular hit target.
- Making the diameter proportional to text size (e.g. `AppFontSizes.body * 3`) —
  premature abstraction. This is a one-off control; two literals stay clearer.
- Extracting a shared `CircleStepButton` widget — out of scope; the +5/-5
  set-break stepper is explicitly not being unified per Feature Input.

## Database Impact
n/a

## Flutter Architecture Changes
n/a — no new providers, controllers, repositories, or files. No state model
changes. No init-order changes. No routing changes. Not platform-conditional.

## Files to Create
n/a

## Files to Modify

### `lib/features/events/widgets/event_form_fields.dart`
- In `_buildDurationSelector`, on the **"-15" (decrement)** button: change
  `Container(width: 40, height: 40, ...)` → `Container(width: 48, height: 48, ...)`.
  Do not touch anything else in that `Container` subtree.
- In `_buildDurationSelector`, on the **"+15" (increment)** button: change
  `Container(width: 40, height: 40, ...)` → `Container(width: 48, height: 48, ...)`.
  Do not touch anything else in that `Container` subtree.
- Do **not** touch the `Text('-15' / '+15', style: TextStyle(fontSize:
  AppFontSizes.body, ...))` — the label font size must remain 16.
- Do **not** touch the `SizedBox(width: 120)` centered readout between them.
- Do **not** touch the `Row`'s `MainAxisAlignment.center`.
- Do **not** touch the disable/enable logic (`onTap: isSaving || durationMinutes
  <= minDuration ? null : ...`), the `minDuration` constant, or the alpha-based
  disabled color.
- Do **not** touch any other section of the file (Date, Time, Additional dates,
  Setlist selector, Notes, etc.).

## Files Off-Limits
- `lib/features/events/widgets/event_editor_drawer.dart` — parent widget; owns
  duration state and callbacks. No behavioral change is needed.
- `lib/features/events/models/event_form_data.dart` — duration model unchanged.
- `lib/features/setlists/widgets/set_break_creator.dart`,
  `lib/features/setlists/widgets/add_to_setlist/set_break_screen.dart` — the
  `+5/-5` set-break steppers. Explicitly out of scope per Feature Input.
- Any app bar / setlist / category circular buttons (`width: 44`) — different
  pattern, not this control.
- `lib/app/theme/design_tokens.dart` — no new tokens are being introduced.
- All Supabase artifacts: `supabase/migrations/**`, `supabase/functions/**`,
  RLS policies, RPCs — none affected.
- `pubspec.yaml`, `pubspec.lock` — no new dependencies.
- All platform config: `ios/**`, `android/**`, `macos/**`, `web/**`,
  `windows/**`, `linux/**` — none affected.

## Change Budget
- Files modified: **1** (`lib/features/events/widgets/event_form_fields.dart`).
- Files created: **0**.
- Net line delta per file: **0** (four in-place value edits: two `width:` and
  two `height:` literals, 40 → 48).
- New public classes / methods: **0**.
- New dependencies: **0**.
- New tokens / constants: **0**.

## System Impact Map
| System         | Status     | Notes                                                        |
|----------------|------------|--------------------------------------------------------------|
| Gigs           | affected   | Duration stepper visible in the Add/Edit Gig flow (visual only). |
| Rehearsals     | affected   | Duration stepper visible in the Add/Edit Rehearsal flow (visual only). |
| Setlists       | unaffected | Set-break stepper is a different control, out of scope.       |
| Members        | unaffected |                                                              |
| Auth           | unaffected |                                                              |
| Routing        | unaffected |                                                              |
| Notifications  | unaffected |                                                              |
| Platforms      | unaffected | Shared Flutter widget; renders identically on iOS/Android/macOS/Web. No platform-conditional code touched. |

## Regression Risk
**LOW.** Pure visual change to two symmetric container dimensions in a single
private helper method. No state, no callbacks, no routing, no auth, no init
order, no DB. Tap target grows (40 → 48), never shrinks. Row layout math stays
comfortably inside the container width.

## Engineer Task Breakdown
1. In [lib/features/events/widgets/event_form_fields.dart](lib/features/events/widgets/event_form_fields.dart#L459-L544) → `_buildDurationSelector`, change the two circle `Container`s from `width: 40, height: 40` to `width: 48, height: 48` — one on the "-15" button, one on the "+15" button. Leave every other line in the method (including the inner `Text` styles, disabled-color logic, and the sibling `SizedBox(width: 120)` readout) untouched.

## Verification Plan

### Tier 1 — pre-deploy (static + local)
1. `flutter analyze` — must be clean; no new warnings or errors.
2. `git diff --stat` on the branch — expect exactly one file changed
   (`lib/features/events/widgets/event_form_fields.dart`) with a net delta of
   0 lines.
3. `git diff -U0 lib/features/events/widgets/event_form_fields.dart` — expect
   exactly four value-only edits inside `_buildDurationSelector`: two
   `width: 40` → `width: 48` and two `height: 40` → `height: 48`. Any other
   change fails verification.
4. Grep confirms label font size is unchanged:
   `grep -n "AppFontSizes.body" lib/features/events/widgets/event_form_fields.dart`
   must still return the same two matches at the "-15" and "+15" `Text.style`
   lines. `fontSize: AppFontSizes.body` on both must remain intact.
5. Grep confirms scope was not expanded:
   `grep -rn "'-15'\|'+15'" lib/` must still return **only** the two matches in
   `event_form_fields.dart` (plus the unrelated docstring in
   `external_song_lookup_service.dart`). No new "-15"/"+15" literals introduced
   elsewhere.

### Tier 2 — post-deploy (manual visual QA, all platforms in scope)
On iOS, Android, macOS, and Web:
1. Open the Add Event flow → Gig (or Rehearsal) → scroll to the Duration
   section.
2. Confirm the "-15" and "+15" circles are visibly larger than before, with
   noticeably more empty space between the number and the circle's edge.
3. Confirm the "-15" / "+15" text itself is **the same size as before** (not
   larger). Side-by-side with any other 16 px body text on the screen it
   should look identical in size.
4. Confirm the readout in the middle ("1h", "1h 15m", etc.) has not moved
   font size or weight and the whole Row still visually centers.
5. Tap each circle: decrement clamps at 15 minutes (button visibly dims),
   increment continues to work. No new haptic / animation changes.
6. Resize the drawer / rotate the device (where applicable) — no overflow
   warnings in the debug console, no wrapping of the Row.
7. Repeat on the Edit Event flow to confirm the same widget renders for edit
   with the same larger circles.

## QA Regression Areas
- Add Event → Gig → Duration stepper (visual only, all four platforms).
- Add Event → Rehearsal → Duration stepper (visual only, all four platforms).
- Edit Event → Gig → Duration stepper (visual only).
- Edit Event → Rehearsal → Duration stepper (visual only).
- No regression expected in: date selection, time selection, AM/PM toggle,
  additional-date rows (for potential gigs), setlist selector, notes field,
  save/cancel behavior, or the Set Break stepper (which is a separate widget
  and untouched).

## Rollout Strategy
Standard PR merge to `main`. No feature flag, no migration, no coordinated
deploy. Web deploys via existing Vercel pipeline; native picks up in the next
release build. Fully reversible via a single revert commit.

## Out of Scope
- Any change to the `+5` / `-5` set-break stepper in
  `set_break_creator.dart` / `set_break_screen.dart`.
- Extracting a shared `CircleStepButton` widget.
- Introducing a new design token for stepper circle diameter.
- Any change to the label's font size, weight, or color.
- Any change to the disabled-state alpha value or the `minDuration = 15`
  clamp.
- Any change to the AM/PM toggle, dropdowns, or additional-date rows in the
  same file.
