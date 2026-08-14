# Architect Plan — Domain Chip Forui Migration & Consolidation

## Feature Slug

`domain-chip-forui-consolidation`

## Feature Title

Migrate email-domain-shortcut chip UI from Material to Forui and consolidate duplicated implementations

## Problem Summary

BandRoadie has three separate chip/pill implementations for email domain shortcuts:

1. **AppChip** — Material-only facade wrapper (Chip/FilterChip/ActionChip), zero call sites, documented as "Cycle 4" future work in README.md
2. **DomainChip** — Hand-rolled AnimatedContainer + GestureDetector with selection and enabled/disabled states, 4 call sites that each independently build their own Row layout with local state
3. **EmailDomainShortcutBar** — Stateless Material ActionChip row, 2 call sites, no selection concept, tap-to-apply-domain only

This creates:

- Dead code (AppChip has no usage)
- Duplication (4 DomainChip call sites each hand-roll the same Row pattern)
- Inconsistent APIs (DomainChip has selection, EmailDomainShortcutBar doesn't)
- Incomplete Forui migration (AppChip blocked on "unclear FTappable API", per README.md line 26-30)

The blocker documented in README.md is partially incorrect: while FBadge is indeed purely presentational (no tap/selection params), FTappable.static has a well-defined API with `selected: bool` and `onPress: VoidCallback?` params. The correct pattern is to wrap FBadge inside FTappable.static for selectable badges.

## Root Cause

**Confidence Level:** HIGH (confirmed by code inspection)

Three independent implementations exist because:

1. AppChip was never completed after initial Forui swap (stalled on API uncertainty)
2. DomainChip was created for selection use cases before AppChip had Forui support
3. EmailDomainShortcutBar was created for stateless tap-to-apply use cases
4. No consolidation pass happened during Forui migration cycles 1-3

## Reference Docs Consulted

- `lib/components/ui/README.md` — Forui migration state, documents AppChip as Cycle 4 blocker
- pub.dev documentation for forui package (FBadge, FTappable.static APIs verified externally)
- `lib/shared/utils/email_domain_helper.dart` — Domain constants and mutation logic

## Existing System Analysis

### Current Implementations

**AppChip** (`lib/components/ui/app_chip.dart`):

- Props: `label` (String), `onTap` (VoidCallback?), `isSelected` (bool?), `variant` (enum: defaultChip/filter/action)
- Renders Material Chip/FilterChip/ActionChip based on variant
- **Missing:** enabled/disabled state (DomainChip needs this, AppChip doesn't have it)
- **Call sites:** 0 (dead code)

**DomainChip** (`lib/components/ui/domain_chip.dart`):

- Props: `domain` (String), `isSelected` (bool), `isEnabled` (bool), `onTap` (VoidCallback)
- Hand-rolled AnimatedContainer with pill border, 3 visual states (selected/enabled-unselected/disabled)
- **Call sites:** 4, each independently building Row + local `_selectedDomain` state
  - `lib/features/auth/invite_screen.dart:503` — `isEnabled: !_signingIn`
  - `lib/features/auth/login_screen.dart:726` — `isEnabled: !_isLoading`, wrapped in FadeTransition/SlideTransition
  - `lib/features/contacts/widgets/venue_contact_block.dart:240` — `isEnabled: true` (static)
  - `lib/features/contacts/widgets/contact_form_screen.dart:317` — `isEnabled: !_isSaving`

**EmailDomainShortcutBar** (`lib/components/ui/email_domain_shortcut_bar.dart`):

- Props: `controller` (TextEditingController)
- Renders Material ActionChip row, stateless, no selection
- Tap behavior: calls `applyEmailDomainShortcut()` which mutates controller text (appends domain if no @, replaces from @ onward if present)
- **Call sites:** 2, neither using selection
  - `lib/features/bands/band_form_screen.dart:1596` — simple tap-to-apply
  - `lib/features/contacts/widgets/invite_members_screen.dart:525` — simple tap-to-apply

### Shared Constants

All three implementations use `emailDomainShortcuts` from `lib/shared/utils/email_domain_helper.dart:44-50`:

```dart
const List<String> emailDomainShortcuts = [
  '@gmail.com',
  '@icloud.com',
  '@yahoo.com',
  '@hotmail.com',
  '@outlook.com',
];
```

## Proposed Solution

Migrate to Forui using the FBadge + FTappable.static pattern and consolidate into a single API surface (EmailDomainShortcutBar backed by AppChip).

### A. Implement AppChip Forui Rendering

Replace Material Chip/FilterChip/ActionChip with FBadge wrapped in FTappable.static:

**New API:**

- Add `enabled` or `isEnabled` param (bool, defaults to true)
- Keep existing params: `label`, `onTap`, `isSelected`, `variant`

**Rendering strategy:**

- When `isSelected` is provided (filter variant): wrap FBadge in `FTappable.static(selected: isSelected, onPress: enabled ? onTap : null, child: FBadge(...))`
- When `isSelected` is null (action/default variant): render FBadge standalone or in FTappable depending on whether onTap is provided
- Variant enum: evaluate whether 3-variant split (defaultChip/filter/action) still makes sense after unifying selection/enablement, or collapse to simpler distinction (may reduce to just filter vs. action)

### B. Extend EmailDomainShortcutBar

Add optional selection mode while preserving stateless tap-to-apply behavior for existing call sites:

**New props:**

- `selectedDomain: String?` — when provided, render chips as selectable
- `onDomainSelected: ValueChanged<String>?` — callback when domain chip tapped in selection mode
- `enabled: bool` (defaults to true) — single loading flag applied to all chips

**Rendering logic:**

- When `selectedDomain` and `onDomainSelected` are provided: render via AppChip filter variant with selection
- When both are null: keep existing tap-to-apply behavior via AppChip action variant
- Use applyEmailDomainShortcut() for tap-to-apply mode (unchanged for 2 existing call sites)

### C. Migrate DomainChip Call Sites

Replace all 4 DomainChip usages with EmailDomainShortcutBar in selection mode:

**Call site changes:**

1. Remove hand-rolled Row + SingleChildScrollView wrapping
2. Remove local `_selectedDomain` state (pass via props instead)
3. Preserve each site's enabled-state wiring and animation wrappers
4. Pass `selectedDomain` and `onDomainSelected` props to EmailDomainShortcutBar

**Special handling for login_screen.dart:726:**

- Preserve existing FadeTransition + SlideTransition wrapper around EmailDomainShortcutBar

### D. Delete domain_chip.dart

Once zero call sites remain (verified via grep search), delete `lib/components/ui/domain_chip.dart`.

### E. Update README.md

- Move AppChip out of "Material-Only Wrappers" section (line 26-30)
- Move into "Forui-Styled Wrappers" section (add as #15)
- Mark Cycle 4 complete (line 142, matching Cycle 3 completion note format)
- Document the FBadge + FTappable.static pattern used

## Database Impact

**Not applicable** — pure client-side UI widget migration, no database changes.

## Flutter Architecture Changes

### State Management

No new controllers or providers. Local `_selectedDomain` state remains in each screen (invite_screen, login_screen, venue_contact_block, contact_form_screen), just wired differently through props instead of direct DomainChip instantiation.

### Widgets Modified

- `lib/components/ui/app_chip.dart` — implement Forui rendering
- `lib/components/ui/email_domain_shortcut_bar.dart` — add selection mode support

### Widgets Deleted

- `lib/components/ui/domain_chip.dart` — removed after migration complete

### Call Sites Modified (6 total)

**DomainChip migrations (4):**

- `lib/features/auth/invite_screen.dart:503`
- `lib/features/auth/login_screen.dart:726`
- `lib/features/contacts/widgets/venue_contact_block.dart:240`
- `lib/features/contacts/widgets/contact_form_screen.dart:317`

**EmailDomainShortcutBar unchanged (2):**

- `lib/features/bands/band_form_screen.dart:1596` — no API change, but will render via Forui internally
- `lib/features/contacts/widgets/invite_members_screen.dart:525` — no API change, but will render via Forui internally

## Files to Create

**None** — all changes are modifications to existing files.

## Files to Modify

| File                                                     | Changes                                                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `lib/components/ui/app_chip.dart`                        | Add Forui rendering (FBadge + FTappable.static), add `enabled`/`isEnabled` param, optionally simplify variant enum                 |
| `lib/components/ui/email_domain_shortcut_bar.dart`       | Add `selectedDomain`, `onDomainSelected`, `enabled` params; render via AppChip; preserve tap-to-apply mode for existing call sites |
| `lib/features/auth/invite_screen.dart`                   | Replace DomainChip Row with EmailDomainShortcutBar (selection mode)                                                                |
| `lib/features/auth/login_screen.dart`                    | Replace DomainChip Row with EmailDomainShortcutBar (selection mode), preserve FadeTransition/SlideTransition wrapper               |
| `lib/features/contacts/widgets/venue_contact_block.dart` | Replace DomainChip Row with EmailDomainShortcutBar (selection mode)                                                                |
| `lib/features/contacts/widgets/contact_form_screen.dart` | Replace DomainChip Row with EmailDomainShortcutBar (selection mode)                                                                |
| `lib/components/ui/README.md`                            | Move AppChip to Forui-Styled section, mark Cycle 4 complete                                                                        |

## Files to Delete

| File                                 | Reason                                    |
| ------------------------------------ | ----------------------------------------- |
| `lib/components/ui/domain_chip.dart` | Zero remaining call sites after migration |

## Files Off-Limits

| File                                                                          | Reason                                                |
| ----------------------------------------------------------------------------- | ----------------------------------------------------- |
| `lib/main.dart`                                                               | Init order must not change                            |
| `lib/shared/utils/email_domain_helper.dart`                                   | Mutation logic and constants unchanged                |
| `lib/features/bands/band_form_screen.dart` (beyond call site)                 | Only touch EmailDomainShortcutBar call site line 1596 |
| `lib/features/contacts/widgets/invite_members_screen.dart` (beyond call site) | Only touch EmailDomainShortcutBar call site line 525  |

## System Impact Map

| System                                 | Impact                                                                         |
| -------------------------------------- | ------------------------------------------------------------------------------ |
| Gigs                                   | unaffected                                                                     |
| Rehearsals                             | unaffected                                                                     |
| Setlists / Catalog                     | unaffected                                                                     |
| Members / RBAC                         | unaffected                                                                     |
| Auth / Session                         | affected (login_screen, invite_screen modified — UI only, no auth flow change) |
| Routing                                | unaffected                                                                     |
| Notifications                          | unaffected                                                                     |
| Contacts                               | affected (contact_form_screen, venue_contact_block modified — UI only)         |
| Bands                                  | affected (band_form_screen modified — UI only)                                 |
| Platform (iOS / Android / Web / macOS) | affected (all platforms — visual rendering via Forui instead of Material)      |
| Theme / Design System                  | affected (completes Forui Cycle 4)                                             |

## Regression Risk

**MEDIUM**

### Rationale

- **8 files modified** (2 components + 4 auth/contact screens + README + 1 deletion)
- **6 call sites touched** across auth, contacts, and bands features
- **Public API changes** to 2 widgets (AppChip gains enabled param, EmailDomainShortcutBar gains selection mode)
- **Visual changes** from Material to Forui styling (pill shape, colors, animations may differ)
- **State wiring changes** at 4 call sites (DomainChip → EmailDomainShortcutBar)
- **Auth screens touched** (login_screen, invite_screen — high-traffic, critical paths)

### Mitigating Factors

- **No business logic changes** — email mutation logic in `email_domain_helper.dart` unchanged
- **No state management changes** — local `_selectedDomain` state remains, just wired via props
- **No database, RLS, or RPC impact**
- **Existing EmailDomainShortcutBar call sites unchanged** (backward compatible)
- **Widget tests can validate behavior** without device access

### Risk is NOT LOW because:

- This is NOT a narrow token swap (unlike rose-primary-color-swap)
- Touches 2 high-traffic auth screens
- Deletes a file (domain_chip.dart)
- Changes widget APIs
- Affects visual rendering on all 4 platforms

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Implement AppChip Forui Rendering

**File:** `lib/components/ui/app_chip.dart`

1. Add `import 'package:forui/forui.dart';`
2. Add `enabled` or `isEnabled` bool param (defaults to true)
3. Replace Material Chip/FilterChip/ActionChip with FBadge + FTappable.static pattern:
   - For filter variant (isSelected provided): `FTappable.static(selected: isSelected ?? false, onPress: enabled ? onTap : null, child: FBadge(...))`
   - For action/default variants: decide whether to use FTappable or standalone FBadge
4. Choose appropriate FBadge variant based on selection/enabled state
5. Update doc comment to document Forui implementation and enabled param

**Verification:** `flutter analyze` passes for this file (0 errors).

### Task 2: Extend EmailDomainShortcutBar

**File:** `lib/components/ui/email_domain_shortcut_bar.dart`

1. Import AppChip: `import 'package:bandroadie/components/ui/app_chip.dart';`
2. Add params:
   - `selectedDomain: String?`
   - `onDomainSelected: ValueChanged<String>?`
   - `enabled: bool` (default true)
3. Update rendering logic:
   - When selectedDomain/onDomainSelected provided: render AppChip in filter variant with selection
   - When both null: render AppChip in action variant with tap-to-apply (\_applyDomain) behavior
4. Remove Material ActionChip, replace with AppChip
5. Update doc comment to document selection mode

**Verification:** `flutter analyze` passes for this file (0 errors).

### Task 3: Migrate invite_screen.dart

**File:** `lib/features/auth/invite_screen.dart`

Replace DomainChip Row (lines ~492-513) with:

```dart
EmailDomainShortcutBar(
  controller: _emailController,
  selectedDomain: _selectedDomain,
  onDomainSelected: (domain) => _applyDomainShortcut(domain),
  enabled: !_signingIn,
),
```

Remove SingleChildScrollView + Row wrapping.

**Verification:**

- `flutter analyze` passes
- Verify `_selectedDomain` state variable and `_applyDomainShortcut` method remain unchanged

### Task 4: Migrate login_screen.dart

**File:** `lib/features/auth/login_screen.dart`

Replace DomainChip Row inside `_buildDomainPills()` method (lines ~716-741) with:

```dart
EmailDomainShortcutBar(
  controller: _emailController,
  selectedDomain: _selectedDomain,
  onDomainSelected: (domain) => _applyDomainShortcut(domain),
  enabled: !_isLoading,
),
```

**Critical:** Preserve FadeTransition + SlideTransition wrapper around EmailDomainShortcutBar.

**Verification:**

- `flutter analyze` passes
- Verify animation wrapper structure unchanged
- Verify `_selectedDomain` state and `_applyDomainShortcut` method unchanged

### Task 5: Migrate venue_contact_block.dart

**File:** `lib/features/contacts/widgets/venue_contact_block.dart`

Replace DomainChip Row (lines ~232-252) with:

```dart
EmailDomainShortcutBar(
  controller: _emailController,
  selectedDomain: _selectedDomain,
  onDomainSelected: (domain) => _applyDomainShortcut(domain),
  enabled: true,
),
```

**Verification:**

- `flutter analyze` passes
- Verify `_selectedDomain` state and `_applyDomainShortcut` method remain unchanged

### Task 6: Migrate contact_form_screen.dart

**File:** `lib/features/contacts/widgets/contact_form_screen.dart`

Replace DomainChip Row (lines ~309-329) with:

```dart
EmailDomainShortcutBar(
  controller: _emailController,
  selectedDomain: _selectedDomain,
  onDomainSelected: (domain) => _applyDomainShortcut(domain),
  enabled: !_isSaving,
),
```

**Verification:**

- `flutter analyze` passes
- Verify `_selectedDomain` state and `_applyDomainShortcut` method unchanged

### Task 7: Verify Zero DomainChip References

Run grep search:

```bash
grep -r "DomainChip" lib/ --include="*.dart"
```

Expected result: only the import in domain_chip.dart itself, or zero results if imports already removed.

If any unexpected references found, STOP and report before proceeding.

### Task 8: Delete domain_chip.dart

**File:** `lib/components/ui/domain_chip.dart`

Delete the file entirely.

**Verification:** File no longer exists, `flutter analyze` still passes (0 errors).

### Task 9: Update README.md

**File:** `lib/components/ui/README.md`

1. Remove AppChip from "Material-Only Wrappers" section (lines 26-30)
2. Add AppChip to "Forui-Styled Wrappers" section as #15:
   ```markdown
   15. **AppChip** → `FBadge` + `FTappable.static` (selectable badge pattern)
   ```
3. Update Cycle 4 section (around line 142):
   ```markdown
   ~~**Cycle 4:** Address AppChip (build custom Forui chip widget or investigate FTappable API)~~ — **COMPLETED** in `feature/domain-chip-forui-consolidation`
   ```
4. Add a brief note documenting the FBadge + FTappable.static pattern for future reference

**Verification:** Markdown renders correctly, no broken links.

### Task 10: Run Full Static Analysis

```bash
flutter analyze
```

**Expected:** 0 errors (warnings allowed if pre-existing on main branch).

**If any new errors:** fix immediately before proceeding.

### Task 11: Generate Git Diff

```bash
git diff > domain-chip-forui-diff.patch
```

**Verification:** Diff shows exactly 8 files modified (7 modified + 1 deleted), no unexpected changes.

## Verification Plan

### Widget Tests

Create `test/components/ui/email_domain_shortcut_bar_test.dart`:

**Test 1: Tap-to-apply mode (backward compatibility)**

- Render EmailDomainShortcutBar with only controller prop
- Tap a domain chip
- Verify applyEmailDomainShortcut logic applied to controller text

**Test 2: Selection mode**

- Render EmailDomainShortcutBar with selectedDomain and onDomainSelected props
- Verify selected domain chip renders as selected
- Tap an unselected domain chip
- Verify onDomainSelected callback fired with correct domain

**Test 3: Enabled/disabled state**

- Render EmailDomainShortcutBar with enabled: false
- Verify chips render as disabled (taps have no effect)

**Test 4: Email mutation logic (existing)**

- Verify applyEmailDomainShortcut() behavior unchanged from email_domain_helper.dart

### AppChip Tests

Create or extend `test/components/ui/app_chip_test.dart`:

**Test 5: Filter variant with selection**

- Render AppChip filter variant with isSelected: true
- Verify selection state renders correctly (FTappable.static selected prop)

**Test 6: Action variant**

- Render AppChip action variant
- Tap chip
- Verify onTap callback fired

**Test 7: Disabled state**

- Render AppChip with enabled: false
- Tap chip
- Verify onTap not fired

### Call Site Smoke Tests

No new test files required — verify existing screen-level tests still pass:

- `test/features/auth/login_screen_test.dart` (if exists)
- `test/features/auth/invite_screen_test.dart` (if exists)

### Static Analysis Regression Check

Compare analyzer output before/after:

```bash
flutter analyze > analyzer-before.txt  # on main
flutter analyze > analyzer-after.txt   # on feature branch
diff analyzer-before.txt analyzer-after.txt
```

**Expected:** No new errors, no new warnings (pre-existing warnings allowed).

## QA Regression Areas

### Primary Validation (must verify)

1. **Visual consistency** — EmailDomainShortcutBar renders with Forui styling (FBadge appearance) on all 6 call sites
2. **Selection state** — Domain chips in invite_screen, login_screen, contact forms show visual selection feedback matching old DomainChip behavior
3. **Enabled/disabled** — Disabled chips (when loading flags active) render as non-interactive
4. **Email mutation** — Tap-to-apply behavior in band_form_screen and invite_members_screen still correctly appends/replaces domain
5. **Animation preservation** — login_screen domain pills still fade/slide in as before

### Regression Testing (must not break)

1. **Auth flows**
   - Login screen email entry with domain shortcuts
   - Invite screen email entry with domain shortcuts
   - Magic link send with domain-assisted email input
2. **Contact flows**
   - Venue contact creation with email domain shortcuts
   - Contact form editing with email domain shortcuts
3. **Band flows**
   - Band member invite with email domain shortcuts
4. **Platform coverage**
   - iOS, Android, Web, macOS — visual rendering works on all

### Visual Acceptance

- Domain chip pill shape matches or improves on old DomainChip styling
- Selection state is clearly visible (primary color border/background)
- Disabled state is clearly visible (muted text)
- Horizontal scroll works smoothly on narrow screens
- No layout jank when selecting/deselecting chips

## Rollout / Migration Strategy

Standard feature branch → PR → merge workflow:

1. Engineer completes implementation on `feature/domain-chip-forui-consolidation` branch
2. All verification tests pass (widget tests + static analysis)
3. QA validates against regression areas listed above
4. On QA APPROVED: merge to main
5. Deploy web (`./tools/deploy_web.sh`)
6. Monitor for visual/interaction issues on production

**Rollback plan:** Revert merge commit if critical visual regression found (chip rendering broken, selection not working, email mutation broken).

## Out of Scope

- **Other chip/badge/pill widgets** — `_TypePill`, `_FilterChip`, `_RolePill`, song_card.dart tuning badges, etc. (approximately 20 other pill-like widgets exist in the codebase, none are DomainChip/EmailDomainShortcutBar/AppChip)
- **Dropdown migration** — AppDropdown remains unused (5 raw DropdownButton usages bypass facade, documented as Cycle 5 in README.md)
- **Custom FBadge variants** — use Forui's default badge variants, no custom StyleDelta overrides unless required by QA feedback
- **New features** — no new email domain shortcuts added, no additional tap behaviors beyond existing selection + tap-to-apply modes

---

**Architect:** GitHub Copilot  
**Date:** 2026-08-14  
**Branch:** `feature/domain-chip-forui-consolidation`
