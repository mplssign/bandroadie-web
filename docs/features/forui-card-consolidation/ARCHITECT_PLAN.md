# Architect Plan — Forui Card Consolidation

## Feature Slug

`forui-card-consolidation`

## Feature Title

Standardize all card UI on Forui's FCard/AppCard

## Problem Summary

Card-like surfaces across BandRoadie currently use ad hoc `Container` + `BoxDecoration` implementations instead of the Forui design system's `FCard`. The existing `AppCard` facade (which wraps `FCard`) exists at `lib/components/ui/app_card.dart` but is used in exactly one location. This creates:

- **Visual inconsistency** — cards lack Forui's unified styling
- **Maintenance burden** — 17 card widgets each maintain their own decoration logic
- **Incomplete Forui migration** — cards remain the largest area still using Material-era patterns
- **Design drift** — some cards use custom rose gradients (gig/rehearsal/calendar cards) that deviate from Forui's neutral aesthetic

Tony has explicitly requested migration of 8 surface categories (17 card widget files) to the Forui card system, with full visual redesign of gradient cards to Forui's standard neutral appearance. This is intentionally scoped as a single feature despite being larger than prior Forui retrofits.

**Known constraint:** Several target surfaces have gesture-based functionality (drag-reorder, swipe left/right actions) that must survive the migration unchanged. Prior history shows shared UI wrapper components can cause constraint-composition bugs only visible on-device, so QA must include device/visual confirmation before APPROVED.

## Root Cause

**Confidence Level:** HIGH (confirmed by code inspection)

Cards use `Container` + `BoxDecoration` because:

1. **Historical:** Cards were implemented before Forui design system adoption (pre-2026)
2. **Incremental migration:** Forui migration focused on buttons, text fields, and scaffolds first; cards were deferred
3. **AppCard underutilization:** `AppCard` facade was created but never evangelized — developers continued using Container patterns
4. **Custom requirements:** Gradient animations and complex layouts led developers to bypass AppCard

The custom rose-gradient cards (gig/rehearsal/calendar) were explicit design choices during the Material era but now deviate from Forui's neutral card aesthetic.

## Reference Docs Consulted

- `lib/components/ui/app_card.dart` — existing AppCard facade
- `docs/features/forui-design-system-swap/FORUI_API_RESEARCH_SUMMARY.md` — FCard API reference
- `docs/features/domain-chip-forui-consolidation/ARCHITECT_PLAN.md` — prior consolidation pattern
- `docs/features/dropdown-facade-migration/ARCHITECT_PLAN.md` — facade extension pattern
- `lib/app/theme/app_animations.dart` — AnimatedCardPressable gesture wrapper

No card-specific reference docs exist in `docs/reference/`.

## Existing System Analysis

### Current AppCard Implementation

**File:** `lib/components/ui/app_card.dart`

```dart
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final styleDelta = padding != null
        ? FCardStyleDelta.delta(padding: EdgeInsetsGeometryDelta.value(padding!))
        : null;

    final card = styleDelta != null
        ? FCard(style: styleDelta, child: child)
        : FCard(child: child);

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}
```

**Current usage:** 1 location (`setlist_detail_screen.dart` line ~2800, wraps empty Catalog state)

**Capabilities:**

- ✅ Wraps `FCard` with consistent Forui styling
- ✅ Supports `onTap` callback
- ✅ Supports `padding` override via `FCardStyleDelta`
- ❌ No support for fixed height (song cards require 121px)
- ❌ No support for custom border radius (various cards use 8px, 12px, 16px, 24px)
- ❌ No tap animation (cards currently use internal AnimationController or AnimatedCardPressable wrapper)

### Target Card Implementations (17 widget files)

#### 1. Empty States (1 card)

**`lib/features/home/widgets/empty_section_card.dart`**

- Uses: `Container` + `BoxDecoration` with border
- Complexity: Medium (internal animation controller for button scale, accessibility-aware)
- Gesture requirements: None
- Visual requirements: Neutral card with button inside

#### 2. Gig Cards (2 cards)

**`lib/features/home/widgets/potential_gig_card.dart`**

- Uses: `Container` with animated orange→rose gradient (`AnimatedBuilder` + gradient controller)
- Complexity: High (multi-date navigation, inline availability buttons, keyboard navigation)
- Gesture requirements: None (tap only)
- **Visual requirement:** Remove gradient, restyle to Forui neutral card

**`lib/features/home/widgets/confirmed_gig_card.dart`**

- Uses: `CustomPaint` with `_GradientBorderPainter` (animated rotating gradient border blue→rose)
- Complexity: High (custom painter, animation controller)
- Gesture requirements: None (tap only)
- **Visual requirement:** Remove gradient border, restyle to Forui neutral card

#### 3. Rehearsal Cards (2 cards)

**`lib/features/home/widgets/rehearsal_card.dart`**

- Uses: `Container` with animated gradient (blue→purple for confirmed, orange→rose for potential)
- Complexity: High (multi-date navigation, inline availability buttons, keyboard navigation)
- Gesture requirements: None (tap only)
- **Visual requirement:** Remove gradient, restyle to Forui neutral card

**`lib/features/home/widgets/load_more_rehearsals_card.dart`**

- Uses: `Container` + `BoxDecoration` with primary color tint
- Complexity: Low (simple tap target with text)
- Gesture requirements: None (tap only)
- Visual requirements: Neutral card with primary color accent (can keep colored elements inside)

#### 4. Calendar Events (1 card)

**`lib/features/calendar/widgets/calendar_event_card.dart`**

- Uses: `Container` + `BoxDecoration` with border
- Complexity: Medium (date badge, event type indicator dot, multi-day block outs)
- Gesture requirements: None (tap only)
- Visual requirements: Neutral card (no gradient present, already neutral)

#### 5. Setlist Cards (2 cards + 1 screen)

**`lib/features/setlists/widgets/setlist_card.dart`**

- Uses: `AnimatedGradientBorder` wrapper widget + `Container`
- Complexity: High (deterministic gradient animation based on setlist ID, drag handle support)
- Gesture requirements: **Drag-reorder** (when `isDraggable=true`, has drag handle area)
- Visual requirements: Remove gradient border, restyle to Forui neutral card

**`lib/features/setlists/widgets/swipeable_setlist_card.dart`**

- Wrapper: `Dismissible` wrapping `SetlistCard`
- Gesture requirements: **Swipe left = delete, swipe right = duplicate**
- Change scope: None (wrapper stays unchanged, inner SetlistCard migrates)

**`lib/features/setlists/setlists_tab_content.dart`** (screen, not a card widget)

- Owns: `SliverReorderableList` with `onReorderItem` callback for setlist drag-reorder
- Change scope: None (list-level logic unchanged)

#### 6. Song Cards (2 cards + 1 screen)

**`lib/features/setlists/widgets/song_card.dart`**

- Uses: `Container` + `BoxDecoration` with 1.5px rose border, 8px radius, **fixed 121px height**
- Complexity: High (metrics row with fixed columns, BPM/Duration/Key/Tuning badges)
- Gesture requirements: None (read-only display card, tap only)
- Visual requirements: Neutral card with rose border (keep border)

**`lib/features/setlists/widgets/reorderable_song_card.dart`**

- Uses: `Container` + `BoxDecoration`, **fixed 121px height**
- Complexity: High (mirrors song_card, adds drag handle strip via Stack + Positioned + ReorderableDragStartListener)
- Gesture requirements: **Drag-reorder** (left 36px strip initiates drag, rest of card is tap/scroll only)
- Visual requirements: Neutral card (slate border, not rose)

**`lib/features/setlists/setlist_detail_screen.dart`** (screen, not a card widget)

- Owns: `Dismissible` wrapper around songs (**swipe left = delete, swipe right = move/copy**)
- Owns: `ReorderableListView` for song drag-reorder
- Change scope: None (screen-level gesture logic unchanged)

#### 7. Member Cards (5 cards)

**`lib/features/members/widgets/member_card.dart`**

- Uses: `Container` + `BoxDecoration` with 2px rose border + subtle gradient overlay
- Complexity: High (role pills, contact info rows, admin menu)
- Gesture requirements: Contact rows have individual tap targets (phone, email)
- **Visual requirement:** Remove gradient overlay, keep rose border

**`lib/features/members/widgets/pending_invite_card.dart`**

- Uses: `Container` + `BoxDecoration` with 1.5px border
- Complexity: Low (email + status badge)
- Gesture requirements: None (tap only)
- Visual requirements: Neutral card

**`lib/features/members/widgets/member_card_skeleton.dart`**

- Uses: `Container` + `BoxDecoration` with shimmer animation (loading skeleton)
- Complexity: Medium (shimmer AnimationController)
- Gesture requirements: None (not interactive)
- Visual requirements: Neutral card with shimmer preserved

**`lib/features/contacts/widgets/band_member_card.dart`**

- Uses: `AnimatedCardPressable` wrapper + `Container` + `BoxDecoration`
- Complexity: Low (simple name + roles display)
- Gesture requirements: Tap animation via AnimatedCardPressable (wrapper stays unchanged)
- Visual requirements: Neutral card

**`lib/features/contacts/widgets/reorderable_band_member_card.dart`**

- Uses: `Container` + `BoxDecoration`, drag handle via Stack + Positioned + ReorderableDragStartListener
- Complexity: Medium (mirrors band_member_card, adds drag strip)
- Gesture requirements: **Drag-reorder** (left strip initiates drag, rest is tap only)
- Visual requirements: Neutral card

#### 8. Venue/Contact Cards (2 cards)

**`lib/features/contacts/widgets/venue_card.dart`**

- Uses: `AnimatedCardPressable` wrapper + `Container` + `BoxDecoration`
- Complexity: Low (name + city/state)
- Gesture requirements: Tap animation via AnimatedCardPressable (wrapper stays unchanged)
- Visual requirements: Neutral card

**`lib/features/contacts/widgets/contact_card.dart`**

- Uses: `AnimatedCardPressable` wrapper + `Container` + `BoxDecoration`
- Complexity: Low (name + title/company)
- Gesture requirements: Tap animation via AnimatedCardPressable (wrapper stays unchanged)
- Visual requirements: Neutral card

### Gesture Preservation Requirements

**Critical:** The following gesture patterns must survive migration unchanged:

1. **Swipe gestures** (implemented via `Dismissible` wrapper at screen level):
   - Setlists: swipe left = delete, swipe right = duplicate
   - Songs: swipe left = delete, swipe right = move/copy

2. **Drag-reorder** (implemented via `ReorderableDragStartListener` inside card + `ReorderableListView` at screen level):
   - Setlist cards: left-edge drag handle when `isDraggable=true`
   - Song cards: left 36px strip initiates drag (`reorderable_song_card.dart`)
   - Band member cards: left strip initiates drag (`reorderable_band_member_card.dart`)

3. **Tap animations** (implemented via `AnimatedCardPressable` wrapper):
   - Venue cards
   - Contact cards
   - Band member cards (non-reorderable variant)

**Pattern observation:** Gesture logic lives **outside** the card decoration:

- Swipe: `Dismissible` wraps the card widget at screen level
- Drag: `ReorderableDragStartListener` wraps a positioned strip **inside** the card widget's Stack
- Tap animation: `AnimatedCardPressable` wraps the entire card widget

**Migration strategy implication:** Replacing `Container` + `BoxDecoration` with `AppCard` should not break gestures because gestures wrap or layer on top of the card surface.

## Proposed Solution

Migrate all 17 target card widgets to use `AppCard` (which wraps Forui's `FCard`), with AppCard API extensions where needed. Remove all gradient animations and restyle gradient cards to Forui's neutral appearance. Preserve all gesture wrappers and list-level logic unchanged.

### A. Extend AppCard API

**File:** `lib/components/ui/app_card.dart`

**New optional parameters:**

```dart
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.height,           // NEW: fixed height support (song cards need 121px)
    this.borderRadius,     // NEW: custom radius (cards use 8, 12, 16, 24)
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final double? height;         // NEW
  final double? borderRadius;   // NEW
}
```

**Justification:**

- `height`: Song cards require fixed 121px height for metrics row alignment across lists
- `borderRadius`: Cards use varied radii (8px for song cards, 12px for calendar events, 16px for members/contacts/venues, 24px for large member cards). Forui's default FCard radius may not match all existing designs.

**Alternative considered:** Use FCardStyleDelta to override height/radius. Rejected because StyleDelta API is more complex and less discoverable for common cases. Simple optional params are more ergonomic.

### B. Migrate Simple Cards (9 cards)

Cards that only need `Container` + `BoxDecoration` → `AppCard` swap, no gradient removal:

1. `empty_section_card.dart` — wrap content in AppCard
2. `song_card.dart` — replace Container with AppCard(height: 121, borderRadius: 8)
3. `reorderable_song_card.dart` — replace Container with AppCard(height: 121, borderRadius: 8), preserve drag handle Stack structure
4. `calendar_event_card.dart` — replace Container with AppCard(borderRadius: 12)
5. `pending_invite_card.dart` — replace Container with AppCard(borderRadius: 16)
6. `load_more_rehearsals_card.dart` — replace Container with AppCard, preserve primary color tint inside
7. `band_member_card.dart` — replace Container with AppCard(borderRadius: 16), AnimatedCardPressable wrapper stays unchanged
8. `reorderable_band_member_card.dart` — replace Container with AppCard(borderRadius: 16), preserve drag handle Stack structure
9. `venue_card.dart` — replace Container with AppCard(borderRadius: 16), AnimatedCardPressable wrapper stays unchanged
10. `contact_card.dart` — replace Container with AppCard(borderRadius: 16), AnimatedCardPressable wrapper stays unchanged

**Gesture preservation:** Cards #3, #9 have drag handles inside Stack — preserve Stack + Positioned structure, only replace the inner Container with AppCard.

### C. Restyle Gradient Cards (5 cards)

Cards that need gradient animations removed and full visual redesign to Forui neutral:

1. **`potential_gig_card.dart`** — remove AnimatedBuilder + gradient controller, remove animated gradient Container background, replace with AppCard
2. **`confirmed_gig_card.dart`** — remove CustomPaint + \_GradientBorderPainter, remove AnimatedBuilder + rotation controller, replace with AppCard
3. **`rehearsal_card.dart`** — remove AnimatedBuilder + gradient controller, remove animated gradient Container background, replace with AppCard
4. **`member_card.dart`** — remove gradient overlay from Stack (Positioned.fill with gradient), replace outer Container with AppCard(borderRadius: 24), keep rose border via FCardStyleDelta if Forui's default border doesn't match
5. **`setlist_card.dart`** — remove AnimatedGradientBorder wrapper, remove GradientAnimationConfig, replace Container with AppCard(borderRadius: 20), preserve drag handle Stack structure when `isDraggable=true`

**Visual change impact:** These 5 cards will look significantly different — neutral FCard appearance instead of animated gradients. This is intentional per Tony's explicit confirmation.

**Gradient removal process:**

1. Delete AnimationController(s) from State class initState/dispose
2. Delete AnimatedBuilder widget wrapper
3. Delete gradient BoxDecoration or CustomPaint
4. Replace outer Container with AppCard
5. Verify content layout unchanged (text, icons, buttons stay in same positions)

### D. Migrate Skeleton Card

**`member_card_skeleton.dart`** — special case, shimmer animation must be preserved:

- Replace outer Container with AppCard(borderRadius: 24)
- Preserve AnimationController + shimmer gradient animation
- Shimmer gradient remains inside the card content (child of AppCard), not as card decoration

### E. Gesture Wrappers (No Changes)

These files wrap cards with gestures — **do not modify**:

- `swipeable_setlist_card.dart` — Dismissible wrapper unchanged, inner SetlistCard migrates
- `setlists_tab_content.dart` — SliverReorderableList + onReorderItem unchanged
- `setlist_detail_screen.dart` — Dismissible wrapper + ReorderableListView unchanged
- `lib/app/theme/app_animations.dart` — AnimatedCardPressable unchanged

## Database Impact

**Not applicable** — pure client-side UI migration, no database, RLS, RPC, or migration changes.

## Flutter Architecture Changes

### State Management

No new controllers or providers. Cards remain stateless or maintain existing internal AnimationController state (where preserved, e.g., skeleton shimmer).

### Widgets Modified

**AppCard facade (1 file):**

- `lib/components/ui/app_card.dart` — add `height` and `borderRadius` optional params

**Card widgets (17 files):**

1. `lib/features/home/widgets/empty_section_card.dart`
2. `lib/features/home/widgets/potential_gig_card.dart`
3. `lib/features/home/widgets/confirmed_gig_card.dart`
4. `lib/features/home/widgets/rehearsal_card.dart`
5. `lib/features/home/widgets/load_more_rehearsals_card.dart`
6. `lib/features/calendar/widgets/calendar_event_card.dart`
7. `lib/features/setlists/widgets/setlist_card.dart`
8. `lib/features/setlists/widgets/song_card.dart`
9. `lib/features/setlists/widgets/reorderable_song_card.dart`
10. `lib/features/members/widgets/member_card.dart`
11. `lib/features/members/widgets/pending_invite_card.dart`
12. `lib/features/members/widgets/member_card_skeleton.dart`
13. `lib/features/contacts/widgets/band_member_card.dart`
14. `lib/features/contacts/widgets/reorderable_band_member_card.dart`
15. `lib/features/contacts/widgets/venue_card.dart`
16. `lib/features/contacts/widgets/contact_card.dart`

**Total files to modify:** 17 card widgets + 1 facade = **18 files**

### Widgets Potentially Deleted

**`lib/features/setlists/widgets/animated_gradient_border.dart`** — if SetlistCard is its only consumer and gradient is removed, delete this helper widget. Verify zero references with grep before deletion.

## Files to Create

**None** — all changes are modifications to existing files.

## Files to Modify

| File                                                              | Changes                                                                                                                                                             |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_card.dart`                                 | Add `height` and `borderRadius` optional params; pass via FCardStyleDelta when provided                                                                             |
| `lib/features/home/widgets/empty_section_card.dart`               | Replace Container + BoxDecoration with AppCard                                                                                                                      |
| `lib/features/home/widgets/potential_gig_card.dart`               | Remove gradient AnimationController + AnimatedBuilder; replace Container with AppCard; verify inline availability buttons layout unchanged                          |
| `lib/features/home/widgets/confirmed_gig_card.dart`               | Remove CustomPaint + \_GradientBorderPainter + rotation AnimationController; replace Container with AppCard                                                         |
| `lib/features/home/widgets/rehearsal_card.dart`                   | Remove gradient AnimationController + AnimatedBuilder; replace Container with AppCard; verify inline availability buttons layout unchanged                          |
| `lib/features/home/widgets/load_more_rehearsals_card.dart`        | Replace Container + BoxDecoration with AppCard; preserve primary color elements inside                                                                              |
| `lib/features/calendar/widgets/calendar_event_card.dart`          | Replace Container + BoxDecoration with AppCard(borderRadius: 12)                                                                                                    |
| `lib/features/setlists/widgets/setlist_card.dart`                 | Remove AnimatedGradientBorder wrapper + GradientAnimationConfig; replace Container with AppCard(borderRadius: 20); preserve drag handle Stack when isDraggable=true |
| `lib/features/setlists/widgets/song_card.dart`                    | Replace Container + BoxDecoration with AppCard(height: 121, borderRadius: 8); preserve rose border styling                                                          |
| `lib/features/setlists/widgets/reorderable_song_card.dart`        | Replace Container + BoxDecoration with AppCard(height: 121, borderRadius: 8); preserve drag handle Stack + Positioned structure; preserve slate border styling      |
| `lib/features/members/widgets/member_card.dart`                   | Remove gradient overlay from Stack (delete Positioned.fill with gradient); replace outer Container with AppCard(borderRadius: 24); preserve rose border styling     |
| `lib/features/members/widgets/pending_invite_card.dart`           | Replace Container + BoxDecoration with AppCard(borderRadius: 16)                                                                                                    |
| `lib/features/members/widgets/member_card_skeleton.dart`          | Replace outer Container + BoxDecoration with AppCard(borderRadius: 24); preserve shimmer AnimationController + gradient animation inside card content               |
| `lib/features/contacts/widgets/band_member_card.dart`             | Replace Container + BoxDecoration with AppCard(borderRadius: 16); AnimatedCardPressable wrapper unchanged                                                           |
| `lib/features/contacts/widgets/reorderable_band_member_card.dart` | Replace Container + BoxDecoration with AppCard(borderRadius: 16); preserve drag handle Stack + Positioned structure                                                 |
| `lib/features/contacts/widgets/venue_card.dart`                   | Replace Container + BoxDecoration with AppCard(borderRadius: 16); AnimatedCardPressable wrapper unchanged                                                           |
| `lib/features/contacts/widgets/contact_card.dart`                 | Replace Container + BoxDecoration with AppCard(borderRadius: 16); AnimatedCardPressable wrapper unchanged                                                           |

**Conditionally delete:**
| File | Reason |
|------|--------|
| `lib/features/setlists/widgets/animated_gradient_border.dart` | If SetlistCard was its only consumer (verify with grep), delete after migration |

## Files Off-Limits

| File                                                        | Reason                                                                                     |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                             | Init order must not change                                                                 |
| `lib/features/setlists/widgets/swipeable_setlist_card.dart` | Dismissible wrapper unchanged — only inner SetlistCard migrates                            |
| `lib/features/setlists/setlists_tab_content.dart`           | Screen-level SliverReorderableList logic unchanged — only card widgets migrate             |
| `lib/features/setlists/setlist_detail_screen.dart`          | Screen-level Dismissible + ReorderableListView logic unchanged — only card widgets migrate |
| `lib/app/theme/app_animations.dart`                         | AnimatedCardPressable wrapper unchanged                                                    |
| All files not explicitly listed in "Files to Modify"        | No opportunistic cleanup or unrelated changes                                              |

## System Impact Map

| System                                 | Impact                                                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | affected — potential_gig_card, confirmed_gig_card visual redesign                                                                  |
| Rehearsals                             | affected — rehearsal_card, load_more_rehearsals_card visual redesign                                                               |
| Setlists / Catalog                     | affected — setlist_card, song_card, reorderable_song_card migrate to Forui                                                         |
| Members / RBAC                         | affected — member_card, pending_invite_card, band_member_card, reorderable_band_member_card, member_card_skeleton migrate to Forui |
| Auth / Session                         | unaffected                                                                                                                         |
| Routing                                | unaffected                                                                                                                         |
| Notifications                          | unaffected (notification_card not in scope)                                                                                        |
| Contacts                               | affected — contact_card, venue_card migrate to Forui                                                                               |
| Calendar                               | affected — calendar_event_card migrates to Forui                                                                                   |
| Home Screen                            | affected — all home cards migrate to Forui                                                                                         |
| Platform (iOS / Android / Web / macOS) | affected — all platforms see visual changes (Forui card styling replaces custom styling)                                           |
| Theme / Design System                  | affected — completes Forui card consolidation, removes last Material-era card patterns                                             |

**Critical systems affected:** 8 of 12 systems

## Regression Risk

**HIGH**

### Rationale

- **18 files modified** (17 cards + 1 facade)
- **5 cards require visual redesign** (gradient removal = major appearance change)
- **3 gesture-bearing surfaces** (song cards, setlist cards, band member cards) with drag-reorder + swipe actions
- **Shared UI wrapper component** (AppCard) extended with new params — prior history shows these can cause constraint-composition bugs only visible on-device
- **High-traffic surfaces** (Home screen gig/rehearsal cards, Setlists tab, Catalog)
- **Complex cards** (potential_gig_card, rehearsal_card have multi-date navigation, keyboard controls, inline buttons)
- **Tony's explicit scope choice** — intentionally did NOT split into smaller phases despite size

### Mitigating Factors

- **No business logic changes** — pure UI wrapper swap, no data flow or state management changes
- **No database impact** — zero RLS, RPC, migration, or backend changes
- **Gesture patterns well-isolated** — Dismissible and ReorderableDragStartListener wrap/layer on top of card surfaces, not inside BoxDecoration
- **AnimatedCardPressable unchanged** — tap animation wrapper preserved exactly as-is
- **Forui is proven stable** — FCard used successfully in other retrofits without regression

### Risk is HIGH (not MEDIUM) because:

- **Scope size** — 18 files exceeds all prior Forui retrofits (chip consolidation was 8 files, dropdown migration was 6 files)
- **Visual redesign magnitude** — 5 cards lose their defining visual characteristic (gradients) and require QA to confirm the new neutral appearance is acceptable
- **Gesture interaction risk** — drag handles and swipe actions could break if card widget structure changes incorrectly (e.g., if Stack + Positioned layout for drag handles is altered)
- **Device-only validation required** — constraint bugs in wrapper components historically only appear on-device, not in hot reload or code review

### Why this was not split into smaller phases:

Tony chose single-feature scope for all 8 surfaces. If any surface's complexity warrants splitting before Engineer work begins, flag to Manager now.

**Architect recommendation:** Proceed as single feature, but structure Engineer task breakdown to isolate high-risk surfaces (gesture-bearing cards) for early validation before remaining cards.

## Engineer Task Breakdown

Execute in strict order. Tasks are grouped by risk level for early validation of high-risk surfaces.

### Task 1: Extend AppCard Facade

**File:** `lib/components/ui/app_card.dart`

1. Add `height` optional param (double?)
2. Add `borderRadius` optional param (double?)
3. Update build logic:
   - When `height` provided, wrap FCard in SizedBox(height: height, child: ...)
   - When `borderRadius` provided, add to FCardStyleDelta (check Forui API for border radius override)
   - Combine with existing `padding` StyleDelta logic
4. Update doc comment to document new params

**Verification:**

- `flutter analyze` passes for this file (0 errors)
- Existing usage in `setlist_detail_screen.dart` compiles without changes (backward compatible)

### Task 2: Migrate Low-Risk Simple Cards (6 cards)

Migrate cards with no gestures, no gradients, no complex layout:

**Files:**

- `lib/features/home/widgets/empty_section_card.dart`
- `lib/features/calendar/widgets/calendar_event_card.dart`
- `lib/features/members/widgets/pending_invite_card.dart`
- `lib/features/contacts/widgets/band_member_card.dart`
- `lib/features/contacts/widgets/venue_card.dart`
- `lib/features/contacts/widgets/contact_card.dart`

**For each file:**

1. Import AppCard: `import 'package:bandroadie/components/ui/app_card.dart';`
2. Locate the outer Container + BoxDecoration
3. Replace with AppCard(borderRadius: <radius>, child: <content>)
   - empty_section_card: borderRadius: 16 (matches Spacing.cardRadius)
   - calendar_event_card: borderRadius: 12
   - pending_invite_card: borderRadius: 16
   - band_member_card, venue_card, contact_card: borderRadius: 16
4. For cards using AnimatedCardPressable wrapper: leave wrapper unchanged, only replace inner Container
5. Verify no onTap duplication (AnimatedCardPressable provides onTap, AppCard can too — use only one)

**Verification:**

- `flutter analyze` passes (0 errors)
- Hot reload on web/iOS shows cards rendering with Forui styling
- No visual regressions in card content layout (text, icons in same positions)

### Task 3: Migrate Song Cards (Non-Gesture First)

**File:** `lib/features/setlists/widgets/song_card.dart`

1. Import AppCard
2. Replace Container + BoxDecoration with AppCard(height: 121, borderRadius: 8, child: <content>)
3. Preserve rose border (#F43F5E, 1.5px) — check if FCard's default border matches, if not, override via FCardStyleDelta
4. Verify metrics row (BPM/Duration/Key/Tuning) layout unchanged

**Verification:**

- `flutter analyze` passes
- Metrics row alignment preserved (fixed column widths unchanged)
- Rose border visible
- Card height exactly 121px

### Task 4: Migrate Reorderable Song Card (High Risk — Drag Handle)

**File:** `lib/features/setlists/widgets/reorderable_song_card.dart`

**Critical:** Preserve Stack + Positioned structure for drag handle strip.

1. Import AppCard
2. Locate the Container + BoxDecoration at line ~138 (inside Stack)
3. Replace with AppCard(height: 121, borderRadius: 8, child: <content>)
4. **Do not touch:**
   - Positioned widget wrapping ReorderableDragStartListener (drag handle strip)
   - Listener widget preventing drag bubble
   - Stack structure
5. Preserve slate border (StandardCardBorder.color, 1.5px)

**Verification:**

- `flutter analyze` passes
- **Device test (iOS/Android):** Drag by left 36px strip successfully reorders song
- **Device test:** Tapping/scrolling card content does NOT initiate drag
- Metrics row alignment preserved
- Slate border visible

**STOP if drag handle fails.** Report to Manager before proceeding.

### Task 5: Migrate Setlist Card (High Risk — Drag Handle + Gradient Removal)

**File:** `lib/features/setlists/widgets/setlist_card.dart`

**Critical:** Remove AnimatedGradientBorder, preserve drag handle when isDraggable=true.

1. Import AppCard
2. Remove AnimatedGradientBorder import
3. Remove GradientAnimationConfig usage (line ~70, initState)
4. Remove GradientAnimationConfig calculation in didUpdateWidget
5. Locate the innerContent Column (lines ~87-139)
6. For non-draggable variant (line ~142-160): replace AnimatedGradientBorder + Container with AppCard(borderRadius: 20, child: innerContent)
7. For draggable variant (line ~162-223): preserve Stack structure, replace innermost Container with AppCard(borderRadius: 20, ...)
8. **Do not touch:**
   - Positioned widget wrapping ReorderableDragStartListener (when isDraggable)
   - Stack structure (when isDraggable)

**Verification:**

- `flutter analyze` passes
- No AnimatedGradientBorder references remain
- **Device test (iOS/Android):** Draggable setlist cards reorder successfully via left-edge drag
- **Device test:** Non-draggable setlists (default) do not show drag handle
- Forui neutral card styling visible (no gradient border)

**STOP if drag handle fails.** Report to Manager before proceeding.

### Task 6: Verify Animated Gradient Border Deletion (Conditional)

**File:** `lib/features/setlists/widgets/animated_gradient_border.dart`

Run grep search:

```bash
grep -r "AnimatedGradientBorder" lib/ --include="*.dart"
```

Expected result: zero matches (or only in commented-out code).

If any unexpected references found, STOP and report before deletion.

If zero references:

1. Delete `lib/features/setlists/widgets/animated_gradient_border.dart`
2. Verify `flutter analyze` passes (0 errors)

### Task 7: Migrate Reorderable Band Member Card (High Risk — Drag Handle)

**File:** `lib/features/contacts/widgets/reorderable_band_member_card.dart`

**Critical:** Preserve Stack + Positioned structure for drag handle strip (mirrors reorderable_song_card.dart pattern).

1. Import AppCard
2. Replace Container + BoxDecoration (inside Stack) with AppCard(borderRadius: 16, child: <content>)
3. **Do not touch:**
   - Positioned widget for drag handle (does not exist in current impl — verify if needed)
   - Listener widget preventing drag bubble
   - Stack structure (currently absent — verify if card should have Stack like song card)
4. **Clarification needed:** Current code shows drag handle via implicit ReorderableListView behavior, not explicit Positioned strip like song cards. Verify whether Stack + Positioned pattern is needed or if ReorderableListView handles it.

**Verification:**

- `flutter analyze` passes
- **Device test (iOS/Android):** Drag by left edge successfully reorders band member
- Content layout preserved

**STOP if drag handle fails.** Report to Manager before proceeding.

### Task 8: Migrate Gradient Gig Cards (Visual Redesign)

**Files:**

- `lib/features/home/widgets/potential_gig_card.dart`
- `lib/features/home/widgets/confirmed_gig_card.dart`

**For potential_gig_card.dart:**

1. Import AppCard
2. Remove `_gradientController` AnimationController (initState, dispose)
3. Remove AnimatedBuilder wrapper (lines ~130-320 approx)
4. Replace inner Container with animated gradient (lines ~130-320) with AppCard(child: <content>)
5. Preserve all content: chip label, date/time, venue, availability buttons, multi-date navigation
6. **Verify:** Inline availability buttons (YES/NO) still work
7. **Verify:** Multi-date navigation (left/right chevrons) still works

**For confirmed_gig_card.dart:**

1. Import AppCard
2. Remove `_rotationController` AnimationController (initState, dispose)
3. Remove AnimatedBuilder wrapper
4. Remove CustomPaint + \_GradientBorderPainter (lines ~72-91)
5. Delete `_GradientBorderPainter` class (lines ~190-250 approx)
6. Replace inner Container with AppCard(borderRadius: 8, child: <content>)
7. Preserve content: title, location, date, time

**Verification:**

- `flutter analyze` passes (0 errors)
- **Visual QA (all platforms):** Cards render with Forui neutral styling (no gradients)
- **Device test:** Gig cards remain tappable, navigate to detail screen
- **Device test (potential_gig_card):** Availability buttons (YES/NO) functional
- **Device test (potential_gig_card):** Multi-date navigation functional

### Task 9: Migrate Rehearsal Card (Visual Redesign)

**File:** `lib/features/home/widgets/rehearsal_card.dart`

**Critical:** Two visual variants (confirmed vs. potential) both use gradients — remove both.

1. Import AppCard
2. Remove `_gradientController` AnimationController (initState, dispose)
3. Remove AnimatedBuilder wrapper
4. Replace gradient Container background with AppCard(child: <content>)
5. Preserve all content: title, location, date, time, availability buttons (potential only), setlist name (confirmed only)
6. **Verify:** Conditional rendering logic for confirmed vs. potential unchanged
7. **Verify:** Inline availability buttons work (potential rehearsals)

**Verification:**

- `flutter analyze` passes
- **Visual QA:** Both confirmed and potential rehearsal cards render with Forui neutral styling
- **Device test:** Confirmed rehearsals show setlist name, no availability buttons
- **Device test:** Potential rehearsals show availability buttons (YES/NO), functional
- **Device test:** Multi-date navigation functional (if applicable)

### Task 10: Migrate Load More Rehearsals Card

**File:** `lib/features/home/widgets/load_more_rehearsals_card.dart`

1. Import AppCard
2. Replace Container + BoxDecoration with AppCard(child: <content>)
3. Preserve primary color tint elements inside (icon, text color)
4. Preserve AnimatedScale tap feedback

**Verification:**

- `flutter analyze` passes
- Card renders with Forui neutral background
- Primary color elements (icon, text) visible inside
- Tap animation functional

### Task 11: Migrate Member Cards (Visual Redesign for member_card.dart)

**Files:**

- `lib/features/members/widgets/member_card.dart` (gradient overlay)
- `lib/features/members/widgets/member_card_skeleton.dart` (shimmer preserved)

**For member_card.dart:**

1. Import AppCard
2. Remove gradient overlay from Stack (delete Positioned.fill with LinearGradient decoration, lines ~140-160 approx)
3. Replace outer Container + BoxDecoration with AppCard(borderRadius: 24, child: <content>)
4. Preserve rose border (2px, #F43F5E) — check if FCard default matches, override via StyleDelta if needed
5. Preserve role pills, contact rows, admin menu button

**Verification:**

- `flutter analyze` passes
- **Visual QA:** No gradient overlay visible, Forui neutral card
- Rose border visible
- Contact rows remain tappable (phone, email)
- Admin menu button functional

**For member_card_skeleton.dart:**

1. Import AppCard
2. Replace outer Container + BoxDecoration with AppCard(borderRadius: 24, child: <content>)
3. **Preserve:**
   - `_shimmerController` AnimationController
   - AnimatedBuilder wrapper
   - Shimmer gradient animation (LinearGradient inside card content)
4. Shimmer effect applies to placeholder boxes inside card, not to card decoration

**Verification:**

- `flutter analyze` passes
- Shimmer animation visible and functional
- Card structure matches member_card.dart (same padding, spacing)

### Task 12: Final Verification Pass

Run full project analysis and visual smoke test:

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings related to card migrations.

**Visual smoke test (web hot reload or device):**

1. Home screen: empty section cards, gig cards, rehearsal cards render
2. Calendar tab: calendar event cards render
3. Setlists tab: setlist cards render, catalog shows
4. Setlist detail: song cards render, drag-reorder functional, swipe actions functional
5. Members tab: member cards render, invite cards render
6. Contacts tab: band member cards, venue cards, contact cards render

**STOP if any card rendering is broken.** Report to Manager.

### Task 13: Create Engineer Report

Create `docs/features/forui-card-consolidation/ENGINEER_REPORT.md` with:

- Summary of changes (18 files modified, 1 file deleted)
- Verification results for each task
- Any deviations from Architect plan
- Known issues or follow-up needed

## Verification Plan

### Tier 1 — Pre-Deployment (Code Analysis Only)

Not applicable — no database or backend changes.

### Tier 2 — Post-Implementation (Client Validation)

Execute after all 18 files modified and `flutter analyze` passes with 0 errors.

#### Test 1: AppCard API Extension Verification

**Objective:** Verify new `height` and `borderRadius` params work correctly.

**Steps:**

1. Run app in debug mode (web or device)
2. Navigate to Setlist detail (any setlist)
3. Inspect song cards (should be exactly 121px tall)
4. Verify card border radius matches design (8px for songs, 16px for members/contacts, 24px for large member cards, 20px for setlists)

**Expected:**

- Song cards are 121px tall (not variable height)
- Border radii match design specs
- No layout overflow or constraint errors in debug console

**Fail condition:** Song cards have variable height, or border radii are incorrect → STOP, report to Manager.

#### Test 2: Simple Card Visual Regression

**Objective:** Verify simple cards migrated without breaking content layout.

**Steps:**

1. Navigate to:
   - Home screen (empty section card if no events)
   - Calendar tab (calendar event cards)
   - Members tab (member cards, pending invite cards)
   - Contacts tab (venue cards, contact cards)
2. Verify text, icons, buttons remain in expected positions
3. Verify no layout overflow or clipping

**Expected:**

- All content visible and properly aligned
- No text truncation or icon clipping
- Forui neutral card styling (consistent shadows, borders, backgrounds)

**Fail condition:** Content misaligned or clipped → STOP, report to Manager.

#### Test 3: Gradient Removal Visual Confirmation

**Objective:** Verify gradient cards now render with Forui neutral appearance (major visual change).

**Steps:**

1. Navigate to Home screen
2. Observe potential gig cards (if any exist) — should have neutral background, NOT orange→rose gradient
3. Observe confirmed gig cards (if any exist) — should have neutral border, NOT animated gradient border
4. Observe rehearsal cards (if any exist) — should have neutral background, NOT blue→purple or orange→rose gradient
5. Navigate to Setlists tab
6. Observe setlist cards — should have neutral border, NOT animated gradient border
7. Navigate to Members tab
8. Observe member cards — should have neutral background, NOT subtle gradient overlay

**Expected:**

- All gradients removed, Forui neutral card appearance
- Content still readable and properly styled
- No jarring color contrast issues

**Fail condition:** Gradients still visible, OR content unreadable due to color contrast issues → STOP, report to Manager.

#### Test 4: Song Card Gesture Preservation (Critical)

**Objective:** Verify drag-reorder and swipe actions still work on song cards.

**Steps:**

1. Navigate to any non-Catalog setlist detail
2. **Drag test:** Long-press the left 36px strip of a song card, drag up/down → card should reorder
3. **Tap test:** Tap the song card content (not left strip) → should open song detail, NOT initiate drag
4. **Swipe left test:** Swipe song card left → red delete background should appear, confirm delete
5. **Swipe right test:** Swipe song card right → green move/copy background should appear, picker opens

**Expected:**

- Drag by left strip reorders song (optimistic UI, position updates immediately)
- Tap on card content does NOT drag
- Swipe left reveals delete action
- Swipe right reveals move/copy action

**Fail condition:** Any gesture fails → STOP, this is a blocking regression, report to Manager.

#### Test 5: Setlist Card Gesture Preservation (Critical)

**Objective:** Verify drag-reorder and swipe actions still work on setlist cards.

**Steps:**

1. Navigate to Setlists tab
2. **Drag test:** Long-press the left edge of a non-Catalog setlist card, drag up/down → card should reorder
3. **Tap test:** Tap the setlist card content → should navigate to setlist detail, NOT initiate drag
4. **Swipe left test:** Swipe setlist card left → red delete background should appear, confirm delete
5. **Swipe right test:** Swipe setlist card right → green duplicate background should appear, confirm duplicate

**Expected:**

- Drag by left edge reorders setlist (Catalog always stays at top)
- Tap on card navigates to detail
- Swipe left reveals delete action (Catalog protected — should show snackbar instead of deleting)
- Swipe right reveals duplicate action

**Fail condition:** Any gesture fails → STOP, this is a blocking regression, report to Manager.

#### Test 6: Band Member Card Gesture Preservation (Critical)

**Objective:** Verify drag-reorder still works on reorderable band member cards.

**Steps:**

1. Navigate to Contacts tab → Band Members A-Z section
2. **Drag test:** Long-press left edge of a reorderable band member card, drag up/down → card should reorder
3. **Tap test:** Tap card content → should open member detail drawer, NOT initiate drag

**Expected:**

- Drag by left edge reorders band member
- Tap on card opens detail drawer

**Fail condition:** Any gesture fails → STOP, report to Manager.

#### Test 7: Tap Animation Preservation

**Objective:** Verify AnimatedCardPressable wrapper still provides tap feedback.

**Steps:**

1. Navigate to Contacts tab
2. Tap a venue card → should scale down slightly during press
3. Tap a contact card → should scale down slightly during press
4. Navigate to Contacts → Band Members
5. Tap a band member card (non-reorderable variant) → should scale down slightly during press

**Expected:**

- Subtle scale animation on tap (0.98x)
- No delay or janky animation

**Fail condition:** No tap feedback, or janky animation → report to Manager (minor issue, not blocking).

#### Test 8: Cross-Platform Consistency

**Objective:** Verify Forui card styling renders consistently across platforms.

**Steps:**

1. Run app on iOS device
2. Run app on Android device (or emulator)
3. Run app on web (Chrome)
4. Run app on macOS desktop
5. Compare card appearance across platforms: shadows, borders, corner radii, text rendering

**Expected:**

- Forui card styling consistent across all 4 platforms
- No platform-specific rendering glitches
- Text readable, no clipping

**Fail condition:** Major visual inconsistency on any platform → report to Manager.

#### Test 9: Load More Rehearsals Card Functional

**Objective:** Verify load more card still triggers pagination.

**Steps:**

1. Navigate to Home screen
2. If "Load More" rehearsal card visible in horizontal list, tap it
3. Verify additional rehearsals load

**Expected:**

- Tap triggers load
- New rehearsals appear in list
- No errors in console

**Fail condition:** Tap does nothing, or errors occur → report to Manager.

#### Test 10: Member Card Skeleton Shimmer Preserved

**Objective:** Verify skeleton shimmer animation still works.

**Steps:**

1. Navigate to Members tab
2. Force slow network (or clear cache) to trigger loading state
3. Observe member card skeletons — shimmer effect should animate across placeholder boxes

**Expected:**

- Shimmer gradient animates smoothly
- Skeleton card structure matches actual member card

**Fail condition:** No shimmer, or skeleton layout broken → report to Manager (minor issue, not blocking).

## QA Regression Areas

QA must test beyond Engineer verification (which focuses on gesture preservation and visual accuracy). Focus on:

### 1. Gesture Interaction Regression (Critical)

**Song cards:**

- Drag-reorder via left 36px strip (Catalog vs. non-Catalog setlists)
- Swipe left = delete (confirm dialog, Catalog warning)
- Swipe right = move/copy (picker opens, move vs. copy logic)
- Tap song card content = open detail, NOT drag

**Setlist cards:**

- Drag-reorder via left edge (Catalog always stays at top)
- Swipe left = delete (confirm dialog, Catalog shows error snackbar)
- Swipe right = duplicate (confirm dialog)
- Tap card content = navigate to detail, NOT drag

**Band member cards (reorderable variant):**

- Drag-reorder via left edge
- Tap card content = open member detail drawer, NOT drag

### 2. Visual Redesign Acceptance (Subjective)

**Gradient cards** — confirm new neutral appearance is acceptable:

- Potential gig cards (was orange→rose gradient)
- Confirmed gig cards (was blue→rose gradient border)
- Rehearsal cards (was blue→purple or orange→rose gradient)
- Setlist cards (was animated gradient border)
- Member cards (was subtle gradient overlay)

**QA decision:** If neutral appearance is too plain or unreadable, flag to Tony for design adjustment. Do NOT approve if unusable.

### 3. Content Layout Regression

**All cards:**

- Text not truncated or clipped
- Icons visible and properly colored
- Buttons/badges aligned correctly
- Spacing consistent with prior design
- No layout overflow warnings in debug console

### 4. Tap Animation Consistency

**Cards using AnimatedCardPressable:**

- Venue cards
- Contact cards
- Band member cards (non-reorderable variant)

**Expected:** Subtle scale-down on tap, smooth animation, no jank.

### 5. Platform-Specific Issues

Test on all 4 platforms:

- **iOS:** Cards render correctly, gestures work, no SafeArea issues
- **Android:** Cards render correctly, gestures work, no Material theme conflicts
- **Web:** Cards render correctly, gestures work (drag may behave differently), no pointer event issues
- **macOS:** Cards render correctly, gestures work, no desktop-specific layout issues

### 6. Edge Cases

- **Empty states:** Empty section cards render when no data (Home screen with no events)
- **Long text:** Song titles, artist names, venue names that overflow — ellipsis renders correctly
- **Skeleton loading:** Member card skeletons render during loading, shimmer animates
- **Multi-date events:** Potential gig cards and rehearsal cards with multiple dates — navigation functional
- **Catalog protection:** Catalog setlist cannot be deleted or reordered (swipe left shows error snackbar, drag keeps Catalog at top)

## Rollout / Migration Strategy

**Not applicable** — pure client-side UI migration, no backend coordination or gradual rollout required. All changes are client-side widget swaps that deploy atomically with the Flutter web build.

**Deployment:**

- Standard web deploy via `./tools/deploy_web.sh` after QA APPROVED
- iOS/Android releases follow standard app store submission process (no special migration steps)

**Rollback plan:** If critical gesture regression discovered post-deploy, revert git commit and redeploy previous version. No database rollback needed.

## Out of Scope

Explicitly **not included** in this feature:

1. **Notification cards** (`lib/features/notifications/widgets/notification_card.dart`) — not listed in Tony's target surfaces
2. **Special item cards** (`lib/features/setlists/widgets/special_item_card.dart`) — not listed in Tony's target surfaces
3. **New card types** — no new card widgets created, only existing cards migrated
4. **AppCard API expansion beyond height/borderRadius** — no support for shadows, elevation, or other Forui overrides unless required during implementation
5. **AnimatedCardPressable modifications** — gesture wrapper stays unchanged
6. **Dismissible or ReorderableDragStartListener changes** — gesture logic unchanged
7. **Screen-level layout changes** — no changes to Home, Calendar, Setlists, Members, or Contacts screen structure (only card widgets migrate)
8. **Performance optimization** — no profiling or render performance tuning (Forui's FCard is assumed performant)
9. **Accessibility improvements** — no new semantic labels or screen reader support (preserve existing accessibility)
10. **Animation tuning** — no changes to animation durations, curves, or easing (preserve existing AppDurations and AppCurves)
11. **Dark mode adjustments** — app is dark mode only, no light mode testing required
12. **Design token updates** — no changes to `lib/app/theme/design_tokens.dart` (use existing Spacing, AppColors, AppTextStyles)

**Scope boundary clarification:** If Engineer discovers additional card-like surfaces during implementation that were not explicitly listed, STOP and report to Manager before expanding scope. Tony chose this explicit surface list intentionally.
