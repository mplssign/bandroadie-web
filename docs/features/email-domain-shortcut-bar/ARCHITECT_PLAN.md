# ARCHITECT_PLAN.md

**Feature:** `feature/email-domain-shortcut-bar`  
**Type:** Feature  
**Date:** 2026-05-09  
**Architect:** AI

---

## Executive Summary

Add a reusable `EmailDomainShortcutBar` widget that displays below every email text field in the app. Tapping a domain shortcut (e.g., `@gmail.com`) intelligently replaces or appends the domain to the current field value. This is a pure UI enhancement—no backend, database, or RLS changes required.

**Confidence:** HIGH — all email field sites identified via code inspection; widget design is straightforward; no architectural concerns.

---

## Phase 0 — Guardrails Loaded

✓ Read `GUARDRAILS.md`  
✓ Read `OPERATING_MODEL.md`

---

## Phase 1 — Workspace State

```bash
Branch: main
Status: M .gitignore, M BandRoadie/tools/build_ios.sh, M docs/agents/ARCHITECT.md,
        M docs/agents/ENGINEER.md, M docs/agents/MANAGER_AGENT.md, M docs/agents/QA.md,
        M ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme,
        M lib/features/home/home_tab_content.dart, M pubspec.yaml,
        M tools/build_mobile_release.sh, A tools/gen_dart_defines.sh, M web/version.json
```

---

## Phase 2 — Feature Slug Validated

✓ Feature identifier: `feature/email-domain-shortcut-bar`  
✓ Branch name: `feature/email-domain-shortcut-bar`  
✓ Docs path: `docs/features/email-domain-shortcut-bar/ARCHITECT_PLAN.md`

---

## Phase 3 — Feature Input Analysis

**Problem:**  
Email input UX is tedious—users must manually type full domain names (e.g., `@gmail.com`). Adding one-tap domain shortcuts will improve speed and reduce typos.

**Expected Behavior:**

- Tapping `@gmail.com` replaces everything from `@` onward in the current field value
- If no `@` is present, the domain is appended to the end
- Works consistently across all email fields in the app
- Horizontally scrollable on all platforms (no overflow)

**Actual Behavior:**  
No domain shortcut bar exists.

**Affected Platforms:**  
iOS, Android, macOS, Web

**Constraints:**

- No backend changes
- Use existing `AppColors` and theme tokens only
- No new color definitions
- Must not break existing send/submit flows

---

## Phase 4 — Domain Reference Docs Consulted

**Relevant directories inspected:**

- `docs/reference/ui/` — contains `LANDING_PAGE_PREVIEW_GUIDE.md` (not applicable)
- `docs/reference/auth/` — contains `MAGIC_LINK_FIX_VERIFICATION.md` (not applicable)

**Design tokens loaded:**

- `lib/app/theme/design_tokens.dart` — `AppColors`, `Spacing`, typography confirmed

**Conclusion:**  
No domain-specific reference docs apply. This is a UI-only feature. Design tokens are sufficient.

---

## Phase 5 — Email Field Audit (Code Inspection)

### Search Methodology

Searched for:

1. `TextInputType.emailAddress` across `lib/**/*.dart` → 6 matches
2. `emailController` pattern across `lib/features/**/*.dart` → 20+ matches
3. Read each file to confirm controller names and widget structure

### Confirmed Email Field Sites

| #   | File                                                       | Widget/Screen                                  | Controller Name          | Line |
| --- | ---------------------------------------------------------- | ---------------------------------------------- | ------------------------ | ---- |
| 1   | `lib/features/auth/login_screen.dart`                      | `LoginScreen._buildEmailField()`               | `_emailController`       | 460  |
| 2   | `lib/features/auth/invite_screen.dart`                     | `InviteScreen` (body)                          | `_emailController`       | 393  |
| 3   | `lib/features/bands/band_form_screen.dart`                 | `BandFormScreen._buildEmailInput()`            | `_emailController`       | 2061 |
| 4   | `lib/features/contacts/widgets/invite_members_screen.dart` | `InviteMembersScreen._buildInviteEmailInput()` | `_inviteEmailController` | 334  |
| 5   | `lib/features/contacts/widgets/contact_form_screen.dart`   | `ContactFormScreen` (body)                     | `_emailController`       | 294  |
| 6   | `lib/features/contacts/widgets/venue_contact_block.dart`   | `VenueContactBlock` (body)                     | `_emailController`       | 208  |

**Total sites:** 6

**Verification:**  
Each file was read in full to confirm:

- `TextField` or `TextFormField` with `keyboardType: TextInputType.emailAddress`
- Controller is a `TextEditingController` accessible in the widget tree
- No other email fields exist in `lib/features/` or `lib/components/`

---

## Phase 6 — Widget Design

### File: `lib/components/ui/email_domain_shortcut_bar.dart`

**Purpose:**  
Render a horizontally scrollable row of domain shortcut buttons. When tapped, modify the provided `TextEditingController` to replace or append the selected domain.

**Signature:**

```dart
class EmailDomainShortcutBar extends StatelessWidget {
  const EmailDomainShortcutBar({super.key, required this.controller});
  final TextEditingController controller;
  // ...
}
```

**Domain list (order preserved):**

1. `@gmail.com`
2. `@icloud.com`
3. `@yahoo.com`
4. `@hotmail.com`
5. `@outlook.com`

**Tap Logic:**

```dart
void _applyDomain(String domain) {
  final currentText = controller.text;
  final atIndex = currentText.indexOf('@');

  final newText = atIndex >= 0
      ? currentText.substring(0, atIndex) + domain
      : currentText + domain;

  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newText.length),
  );
}
```

**Layout:**

- `SingleChildScrollView` with `scrollDirection: Axis.horizontal`
- `Row` with `spacing: Spacing.space8` (or use a `Wrap` with spacing)
- Each domain rendered as an `ActionChip` or `OutlinedButton`
- Chip/button styling:
  - Background: `context.colors.surface` (from `BrandColors` extension)
  - Border: `context.colors.border` (1px)
  - Text: `context.colors.textPrimary`
  - Border radius: `Spacing.buttonRadius` (8px)
  - Padding: `EdgeInsets.symmetric(horizontal: 12, vertical: 6)`
  - No new colors — use existing tokens only

**Height:**

- Intrinsic (likely ~40-44px with padding)
- Does not impose a fixed height constraint

**Platform considerations:**

- Scrollable → no overflow on narrow screens
- Touch targets ≥ 48px (iOS/Android HIG) — ActionChip default suffices
- Web: mouse hover supported automatically by Material widgets

---

## Phase 7 — Integration Plan

For each email field site, insert the `EmailDomainShortcutBar` **immediately below** the email `TextField` / `TextFormField`, separated by a `SizedBox(height: 8)` spacer.

### Site 1: `login_screen.dart`

**Method:** `_buildEmailField()`  
**Controller:** `_emailController`  
**Insertion point:** After the `AutofillGroup` widget (which wraps the `TextField`), before the conditional validation error text  
**Special considerations:**

- The method returns a `Column` with `crossAxisAlignment: CrossAxisAlignment.start`
- Insert `SizedBox(height: 8)` then `EmailDomainShortcutBar(controller: _emailController)` immediately after the `AutofillGroup` widget closes
- Do not disturb the `FieldHint` widget or validation error display below

### Site 2: `invite_screen.dart`

**Method/Context:** Body `Column` in main `build()` method  
**Controller:** `_emailController`  
**Insertion point:** After the `TextField` widget (line ~393), before the `SizedBox(height: 16)` spacer and button  
**Special considerations:**

- The `TextField` is wrapped in a `SizedBox(width: 320)`
- Insert the shortcut bar **outside** the width constraint (so it can scroll freely)
- Place it immediately after the `SizedBox(width: 320, child: TextField(...))` closes

### Site 3: `band_form_screen.dart`

**Method:** `_buildEmailInput()`  
**Controller:** `_emailController`  
**Insertion point:** After the `Expanded(child: TextFormField(...))` within the `Row`, after the `Row` closes and before the following `SizedBox` (if any)  
**Special considerations:**

- The method returns a `Row` containing a `TextFormField` and a "+" button
- The shortcut bar should appear **below** the row (not inside it)
- Insert as a new child in the parent `Column` (wherever `_buildEmailInput()` is called)
- The Engineer must trace the call site and insert the shortcut bar there

**Amended integration guidance:**  
After reviewing the structure, the shortcut bar should be added **immediately after the Row** in the parent widget that calls `_buildEmailInput()`. The Engineer must:

1. Locate where `_buildEmailInput()` is called in the build tree
2. Insert `const SizedBox(height: 8)` after the `Row` closes
3. Insert `EmailDomainShortcutBar(controller: _emailController)`

### Site 4: `invite_members_screen.dart`

**Method:** `_buildInviteEmailInput()`  
**Controller:** `_inviteEmailController`  
**Insertion point:** After the `Row` closes (which contains the `TextFormField` and "+" button), before the next widget in the parent `Column`  
**Special considerations:**

- Same structure as Site 3 — shortcut bar goes below the row
- The Engineer must trace where `_buildInviteEmailInput()` is called and insert the bar there

### Site 5: `contact_form_screen.dart`

**Method/Context:** Body `ListView` in main `build()` method  
**Controller:** `_emailController`  
**Insertion point:** After the `TextField` (line ~294), before the following `SizedBox(height: 16)` spacer  
**Special considerations:**

- The `TextField` is a direct child in a `Column` (within a `ListView`)
- Insert `const SizedBox(height: 8)` immediately after the `TextField`
- Insert `EmailDomainShortcutBar(controller: _emailController)` after the spacer

### Site 6: `venue_contact_block.dart`

**Method/Context:** Body `Column` in `build()` method  
**Controller:** `_emailController`  
**Insertion point:** After the email `TextField` (line ~208), before the following `SizedBox(height: 12)` spacer  
**Special considerations:**

- The `TextField` is a direct child in a `Column`
- Insert `const SizedBox(height: 8)` immediately after the `TextField`
- Insert `EmailDomainShortcutBar(controller: _emailController)` after the spacer

---

## Phase 8 — Files Enumeration

### New Files

1. `lib/components/ui/email_domain_shortcut_bar.dart`

### Modified Files

1. `lib/features/auth/login_screen.dart`
2. `lib/features/auth/invite_screen.dart`
3. `lib/features/bands/band_form_screen.dart`
4. `lib/features/contacts/widgets/invite_members_screen.dart`
5. `lib/features/contacts/widgets/contact_form_screen.dart`
6. `lib/features/contacts/widgets/venue_contact_block.dart`

### Files That Must NOT Be Touched

- `lib/main.dart`
- `supabase/**`
- `vercel.json`
- `web/**`
- `pubspec.yaml`
- Any file not listed above

---

## Phase 9 — Database Impact Assessment

| Area            | Impact            |
| --------------- | ----------------- |
| Database schema | ❌ Not applicable |
| Migrations      | ❌ Not applicable |
| RLS policies    | ❌ Not applicable |
| RPC functions   | ❌ Not applicable |
| Edge functions  | ❌ Not applicable |
| Triggers        | ❌ Not applicable |

**Conclusion:**  
No backend or database changes required. This is a pure client-side UI enhancement.

---

## Phase 10 — System Impact Map

| System                    | Impact                                                    |
| ------------------------- | --------------------------------------------------------- |
| Auth (login/invite flows) | ✅ Affected — shortcuts added to login and invite screens |
| Band management           | ✅ Affected — shortcuts added to band form                |
| Contacts                  | ✅ Affected — shortcuts added to contact and venue forms  |
| Member invites            | ✅ Affected — shortcuts added to invite members screen    |
| Gigs                      | ❌ Unaffected — no email fields in gig flows              |
| Rehearsals                | ❌ Unaffected — no email fields in rehearsal flows        |
| Setlists                  | ❌ Unaffected — no email fields in setlist flows          |
| Calendar                  | ❌ Unaffected — no email fields in calendar               |
| Settings                  | ❌ Unaffected — no email fields in settings               |

**Risk level:** LOW  
**Rationale:**

- UI-only change
- No state management modifications
- No API contract changes
- Existing submit/send logic unchanged — shortcuts only modify field values

---

## Phase 11 — Verification Plan

### Tier 1: Pre-Deployment (Engineer executes)

**Static Analysis:**

1. `flutter analyze` must pass with 0 errors, 0 warnings

**Manual Testing (required platforms: Chrome + one native):**

**Test Case 1: Empty field**

- Given: email field is empty
- When: tap `@gmail.com`
- Then: field value becomes `@gmail.com`, cursor at end

**Test Case 2: Local part only**

- Given: field value is `john`
- When: tap `@icloud.com`
- Then: field value becomes `john@icloud.com`, cursor at end

**Test Case 3: Partial domain**

- Given: field value is `john@gm`
- When: tap `@yahoo.com`
- Then: field value becomes `john@yahoo.com`, cursor at end

**Test Case 4: Full address**

- Given: field value is `john@gmail.com`
- When: tap `@outlook.com`
- Then: field value becomes `john@outlook.com`, cursor at end

**Test Case 5: Scroll behavior**

- Given: narrow screen (iPhone SE / 320px width)
- When: render shortcut bar
- Then: all 5 domains visible via horizontal scroll, no overflow

**Test Case 6: Submit flow**

- Given: email field populated via shortcut
- When: submit form (login / invite / save contact)
- Then: submission proceeds normally, no errors

**Platform matrix:**
| Platform | Required | Status |
|----------|----------|--------|
| Chrome | ✅ Yes | Not started |
| iOS Simulator | ✅ Yes (one of iOS/Android/macOS) | Not started |
| Android Emulator | ⚠️ Optional | Not started |
| macOS | ⚠️ Optional | Not started |

### Tier 2: Post-Deployment (QA executes)

**Critical path validation:**

1. **Auth flow:** Complete login using shortcut-populated email → magic link received → login successful
2. **Invite flow:** Send band invite using shortcut-populated email → invite email received (verified via Supabase dashboard)
3. **Contact flow:** Create contact using shortcut-populated email → contact saved, email visible in UI

**Regression check:**

- Create new band, invite member, add contact — all flows complete without errors

---

## Phase 12 — Engineer Task Breakdown

Execute in strict order. Do not parallelize. Report completion after each task.

### Task 1: Create `EmailDomainShortcutBar` widget

- File: `lib/components/ui/email_domain_shortcut_bar.dart`
- Implement widget as specified in Phase 6 (Widget Design)
- Domain list: `@gmail.com`, `@icloud.com`, `@yahoo.com`, `@hotmail.com`, `@outlook.com`
- Tap logic: replace from `@` onward if `@` present, otherwise append
- Styling: use `AppColors` and `Spacing` tokens only
- Layout: `SingleChildScrollView` horizontal, `Row` of `ActionChip` or `OutlinedButton`

### Task 2: Integrate into `login_screen.dart`

- File: `lib/features/auth/login_screen.dart`
- Method: `_buildEmailField()`
- Insert shortcut bar after `AutofillGroup`, before validation error
- Controller: `_emailController`
- Spacing: `SizedBox(height: 8)`

### Task 3: Integrate into `invite_screen.dart`

- File: `lib/features/auth/invite_screen.dart`
- Context: main body `Column`
- Insert shortcut bar after `SizedBox(width: 320, child: TextField(...))`, outside width constraint
- Controller: `_emailController`
- Spacing: `SizedBox(height: 8)`

### Task 4: Integrate into `band_form_screen.dart`

- File: `lib/features/bands/band_form_screen.dart`
- Locate where `_buildEmailInput()` is called in the build tree
- Insert shortcut bar after the `Row` closes
- Controller: `_emailController`
- Spacing: `SizedBox(height: 8)`

### Task 5: Integrate into `invite_members_screen.dart`

- File: `lib/features/contacts/widgets/invite_members_screen.dart`
- Locate where `_buildInviteEmailInput()` is called in the build tree
- Insert shortcut bar after the `Row` closes
- Controller: `_inviteEmailController`
- Spacing: `SizedBox(height: 8)`

### Task 6: Integrate into `contact_form_screen.dart`

- File: `lib/features/contacts/widgets/contact_form_screen.dart`
- Context: body `ListView` (line ~294)
- Insert shortcut bar after email `TextField`, before next spacer
- Controller: `_emailController`
- Spacing: `SizedBox(height: 8)`

### Task 7: Integrate into `venue_contact_block.dart`

- File: `lib/features/contacts/widgets/venue_contact_block.dart`
- Context: body `Column` (line ~208)
- Insert shortcut bar after email `TextField`, before next spacer
- Controller: `_emailController`
- Spacing: `SizedBox(height: 8)`

### Task 8: Run static analysis

- Execute: `flutter analyze`
- Expected: 0 errors, 0 warnings
- If errors exist, fix and re-run until clean

### Task 9: Manual testing (Chrome)

- Run: `flutter run -d chrome`
- Execute all Tier 1 test cases from Phase 11
- Verify: all 6 email fields display shortcut bar, all test cases pass

### Task 10: Manual testing (native simulator)

- Run: `flutter run -d ios` or `flutter run -d macos`
- Execute all Tier 1 test cases from Phase 11
- Verify: all test cases pass on native platform

### Task 11: Generate `ENGINEER_REPORT.md`

- Document all tasks completed
- Report any deviations from plan
- Include `flutter analyze` output
- Confirm all integration sites tested

---

## Phase 13 — Risk Assessment

**Technical Risks:**

| Risk                                               | Likelihood | Impact | Mitigation                                                       |
| -------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------- |
| Shortcut bar overflows on narrow screens           | Low        | Medium | Use `SingleChildScrollView` with horizontal scroll               |
| Cursor position incorrect after domain replacement | Low        | Medium | Explicitly set `TextSelection.collapsed(offset: newText.length)` |
| Shortcut bar disrupts existing form layout         | Low        | Low    | Use consistent `SizedBox(height: 8)` spacing; QA validates       |
| Domain replacement fails when multiple `@` present | Very Low   | Low    | Logic uses `indexOf('@')` which finds first occurrence only      |

**User-Facing Risks:**

| Risk                                           | Likelihood | Impact   | Mitigation                                                                            |
| ---------------------------------------------- | ---------- | -------- | ------------------------------------------------------------------------------------- |
| Users accidentally tap shortcut when scrolling | Low        | Low      | Standard touch target size (48px); Material widgets handle accidental taps gracefully |
| Shortcut bar confuses users on first encounter | Very Low   | Very Low | Behavior is intuitive (tap = domain appears); no onboarding needed                    |

**Overall Risk Level:** LOW

---

## Phase 14 — Branch and Commit Strategy

**Branch name:** `feature/email-domain-shortcut-bar`

**Commit structure:**

```
feat(ui): add EmailDomainShortcutBar widget

- Create reusable email domain shortcut bar component
- Integrate below all email fields (auth, bands, contacts)
- Domain list: gmail, icloud, yahoo, hotmail, outlook
- Smart replace/append logic based on @ presence
- Fully responsive, horizontally scrollable
```

**PR title:**  
`feat(ui): Add email domain shortcuts to all email fields`

**PR description:**

```markdown
## Summary

Adds a reusable `EmailDomainShortcutBar` widget below every email text field in the app.
Tapping a domain shortcut (@gmail.com, @icloud.com, etc.) intelligently replaces or
appends the domain to improve email input UX.

## Changes

- ✅ New widget: `lib/components/ui/email_domain_shortcut_bar.dart`
- ✅ Integrated at 6 email field sites across auth, bands, and contacts
- ✅ Horizontally scrollable, no overflow on any platform
- ✅ Uses existing AppColors/theme tokens only
- ✅ No backend changes

## Testing

- ✅ `flutter analyze` passes
- ✅ Tested on Chrome + iOS Simulator
- ✅ All domain replacement logic verified
- ✅ No existing flows affected

## Acceptance Criteria Met

- [x] Shortcut bar below every email field
- [x] Tap replaces from @ onward (or appends if no @)
- [x] Works on iOS, Android, macOS, Web
- [x] No new colors defined
- [x] No backend changes
```

---

## Appendix A: Code Snippet (Widget Template)

```dart
// lib/components/ui/email_domain_shortcut_bar.dart
import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';

/// Email domain shortcut bar — tap to replace/append domain to an email field.
///
/// Displays a horizontally scrollable row of common email domain buttons.
/// Tapping a domain either replaces everything from @ onward (if @ is present)
/// or appends the domain to the end of the current text.
class EmailDomainShortcutBar extends StatelessWidget {
  const EmailDomainShortcutBar({super.key, required this.controller});

  /// The TextEditingController for the email field
  final TextEditingController controller;

  static const List<String> _domains = [
    '@gmail.com',
    '@icloud.com',
    '@yahoo.com',
    '@hotmail.com',
    '@outlook.com',
  ];

  void _applyDomain(String domain) {
    final currentText = controller.text;
    final atIndex = currentText.indexOf('@');

    final newText = atIndex >= 0
        ? currentText.substring(0, atIndex) + domain
        : currentText + domain;

    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _domains.map((domain) {
          return Padding(
            padding: const EdgeInsets.only(right: Spacing.space8),
            child: ActionChip(
              label: Text(domain),
              onPressed: () => _applyDomain(domain),
              backgroundColor: context.colors.surface,
              side: BorderSide(color: context.colors.border, width: 1),
              labelStyle: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

---

## Appendix B: Alternative Widget Implementations

If `ActionChip` does not meet design requirements, the Engineer may substitute `OutlinedButton`:

```dart
OutlinedButton(
  onPressed: () => _applyDomain(domain),
  style: OutlinedButton.styleFrom(
    backgroundColor: context.colors.surface,
    side: BorderSide(color: context.colors.border, width: 1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Spacing.buttonRadius),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  ),
  child: Text(
    domain,
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: 14,
    ),
  ),
)
```

The Engineer must choose one approach and apply it consistently.

---

## Appendix C: Integration Example (login_screen.dart)

**Before:**

```dart
Widget _buildEmailField() {
  return FadeTransition(
    opacity: _emailOpacity,
    child: SlideTransition(
      position: _emailSlide,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email address', style: ...),
          const SizedBox(height: 8),
          AutofillGroup(
            child: TextField(
              controller: _emailController,
              // ... rest of TextField config
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(_validationError!, style: ...),
          ],
        ],
      ),
    ),
  );
}
```

**After:**

```dart
Widget _buildEmailField() {
  return FadeTransition(
    opacity: _emailOpacity,
    child: SlideTransition(
      position: _emailSlide,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Email address', style: ...),
          const SizedBox(height: 8),
          AutofillGroup(
            child: TextField(
              controller: _emailController,
              // ... rest of TextField config
            ),
          ),
          const SizedBox(height: 8),  // NEW
          EmailDomainShortcutBar(controller: _emailController),  // NEW
          if (_validationError != null) ...[
            const SizedBox(height: 8),
            Text(_validationError!, style: ...),
          ],
        ],
      ),
    ),
  );
}
```

---

## Sign-Off

**Architect Approval:** Ready for Engineer implementation  
**Manager Gate:** Pending Manager review  
**Blockers:** None

**Next Steps:**

1. Manager reviews this plan
2. Manager assigns Engineer
3. Engineer executes Tasks 1-11 in order
4. Engineer submits `ENGINEER_REPORT.md` + git diff
5. QA validates against this plan

---

_End of ARCHITECT_PLAN.md_
