# ARCHITECT_PLAN.md

## Feature: bug/contact-email-pills-inconsistent

**Type:** bug  
**Slug:** `bug/contact-email-pills-inconsistent`  
**Branch:** `bug/contact-email-pills-inconsistent`  
**Status:** APPROVED

---

## Problem Statement

### What is broken

The email domain shortcut chips in the venue contact form (`venue_contact_block.dart`) and the add-contact form (`contact_form_screen.dart`) use the generic `EmailDomainShortcutBar` widget, which displays flat, non-pill-shaped chips that are visually inconsistent with the `DomainChip` pill style used on the login and invite members screens.

### Impact

- **Visual consistency regression:** The email domain shortcuts appear in two different visual styles across the app
- **UX inconsistency:** The flat chips lack the selection state highlight and animated pill interaction present in `DomainChip`
- **Design debt:** The generic bar widget was intended as a placeholder and should have been replaced with `DomainChip` during the `feature/email-domain-shortcut-bar` implementation

### Expected behavior

All email domain pills should use the `DomainChip` component — `AnimatedContainer` pill shape (100px border radius), selection state highlight (rose primary with opacity background), and `BouncingScrollPhysics` scroll behavior.

---

## Root Cause Analysis

**Confidence:** HIGH (confirmed via direct code inspection)

### Diagnosis

**Current state:**

- `venue_contact_block.dart` (line 225): `EmailDomainShortcutBar(controller: _emailController)`
- `contact_form_screen.dart` (line 270): `EmailDomainShortcutBar(controller: _emailController)`

**Why it's broken:**

1. Both files were integrated with `EmailDomainShortcutBar` during the `feature/email-domain-shortcut-bar` implementation
2. The `DomainChip` component was created later as the canonical pill design
3. `invite_members_screen.dart` was upgraded to use `DomainChip` in the feature
4. The two contact-related files were never upgraded and retained the generic bar widget

**Evidence:**

- `invite_members_screen.dart` lines 481-499 show the correct implementation pattern:
  - `String? _selectedInviteDomain` state variable
  - `_applyInviteDomainShortcut(String domain)` method using `applyEmailDomainShortcut()` helper
  - Horizontal scrolling `Row` with `DomainChip` widgets
  - Selection state tracking and highlighting
  - `isEnabled` gated by `_isSendingInvite` state
- `DomainChip` is already implemented at `lib/components/ui/domain_chip.dart`
- `emailDomainShortcuts` list and `applyEmailDomainShortcut()` helper exist in `lib/shared/utils/email_domain_helper.dart`

---

## Solution Design

### Minimal Fix Strategy

**Scope:** Upgrade the email domain shortcuts in both contact forms to use `DomainChip`, replicating the exact pattern from `invite_members_screen.dart`.

**Why this is the right fix:**

- `DomainChip` is the established canonical component
- The integration pattern is proven and complete in `invite_members_screen.dart`
- No new architecture or components are required
- Preserves all existing form behavior — only the visual presentation of domain shortcuts changes

### Changes Required

#### 1. `venue_contact_block.dart`

**Add state variable:**

```dart
String? _selectedDomain;
```

**Add domain shortcut method:**

```dart
void _applyDomainShortcut(String domain) {
  final current = _emailController.text;
  final result = applyEmailDomainShortcut(current, domain);

  if (result.isEmpty) {
    return;
  }

  _emailController.text = result;
  _emailController.selection = TextSelection.fromPosition(
    TextPosition(offset: result.length),
  );

  setState(() {
    _selectedDomain = domain;
  });
}
```

**Replace EmailDomainShortcutBar (line 225):**

```dart
const SizedBox(height: 8),
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  physics: const BouncingScrollPhysics(),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: emailDomainShortcuts.asMap().entries.map((entry) {
      final index = entry.key;
      final domain = entry.value;
      return Padding(
        padding: EdgeInsets.only(
          right: index < emailDomainShortcuts.length - 1 ? 8 : 0,
        ),
        child: DomainChip(
          domain: domain,
          isSelected: _selectedDomain == domain,
          isEnabled: true, // No loading state in this widget
          onTap: () => _applyDomainShortcut(domain),
        ),
      );
    }).toList(),
  ),
),
```

**Update imports:**

- Add: `import 'package:bandroadie/components/ui/domain_chip.dart';`
- Keep: `import 'package:bandroadie/shared/utils/email_domain_helper.dart';` (if already present, otherwise add)
- Remove: `import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';`

#### 2. `contact_form_screen.dart`

**Add state variable:**

```dart
String? _selectedDomain;
```

**Add domain shortcut method:**

```dart
void _applyDomainShortcut(String domain) {
  final current = _emailController.text;
  final result = applyEmailDomainShortcut(current, domain);

  if (result.isEmpty) {
    return;
  }

  _emailController.text = result;
  _emailController.selection = TextSelection.fromPosition(
    TextPosition(offset: result.length),
  );

  setState(() {
    _selectedDomain = domain;
  });
}
```

**Replace EmailDomainShortcutBar (line 270):**

```dart
const SizedBox(height: 8),
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  physics: const BouncingScrollPhysics(),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: emailDomainShortcuts.asMap().entries.map((entry) {
      final index = entry.key;
      final domain = entry.value;
      return Padding(
        padding: EdgeInsets.only(
          right: index < emailDomainShortcuts.length - 1 ? 8 : 0,
        ),
        child: DomainChip(
          domain: domain,
          isSelected: _selectedDomain == domain,
          isEnabled: !_isSaving, // Gate on saving state
          onTap: () => _applyDomainShortcut(domain),
        ),
      );
    }).toList(),
  ),
),
```

**Update imports:**

- Add: `import 'package:bandroadie/components/ui/domain_chip.dart';`
- Keep: `import 'package:bandroadie/shared/utils/email_domain_helper.dart';` (if already present, otherwise add)
- Remove: `import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';`

---

## System Impact Assessment

### Database Impact

**Status:** NOT APPLICABLE  
This is a UI-only change. No database schema, RLS policies, RPC functions, or migrations are affected.

### Cross-Feature Impact

| System             | Impact       | Notes                                             |
| ------------------ | ------------ | ------------------------------------------------- |
| Gigs               | unaffected   | No gig-related code touched                       |
| Rehearsals         | unaffected   | No rehearsal-related code touched                 |
| Setlists / Catalog | unaffected   | No setlist-related code touched                   |
| Members / RBAC     | unaffected   | No permission or membership logic touched         |
| Auth / Session     | unaffected   | No auth flow touched                              |
| Routing            | unaffected   | No route definitions or navigation logic changed  |
| Contacts           | **affected** | Two contact form widgets upgraded to `DomainChip` |
| Venues             | **affected** | Venue contact block upgraded to `DomainChip`      |

---

## Files to Modify

### Modified (2 files)

1. `lib/features/contacts/widgets/venue_contact_block.dart`
   - Add `_selectedDomain` state variable
   - Add `_applyDomainShortcut()` method
   - Replace `EmailDomainShortcutBar` with `DomainChip` row (line 225)
   - Update imports

2. `lib/features/contacts/widgets/contact_form_screen.dart`
   - Add `_selectedDomain` state variable
   - Add `_applyDomainShortcut()` method
   - Replace `EmailDomainShortcutBar` with `DomainChip` row (line 270)
   - Update imports

### Forbidden Files

- **Do not modify:** `lib/components/ui/domain_chip.dart` (component is final)
- **Do not modify:** `lib/shared/utils/email_domain_helper.dart` (helper is complete)
- **Do not modify:** `lib/components/ui/email_domain_shortcut_bar.dart` (deprecated widget, may be removed later)
- **Do not modify:** Any files in `lib/features/auth/` (reference implementation is stable)
- **Do not modify:** Any files in `lib/features/bands/` (not affected by this bug)

---

## Verification Plan

### Tier 1 — Visual & Functional Correctness

**Test Steps:**

1. **`flutter analyze` passes** — 0 errors, 0 warnings
2. **Venue contact form visual check:**
   - Navigate to Venues → Add Venue or Edit Venue
   - Scroll to Contacts section
   - Add a contact
   - **Verify:** Email domain shortcuts render as `DomainChip` pills (rounded pill shape, not flat chips)
   - Tap `@gmail.com` domain
   - **Verify:** Domain fills the email field, pill highlights with rose border and background
   - Type a username (e.g., `john`)
   - Tap `@icloud.com`
   - **Verify:** Domain replaces `@gmail.com` in the field, `@icloud.com` pill highlights
   - **Verify:** Previous selection (`@gmail.com`) un-highlights
3. **Contact form visual check:**
   - Navigate to Contacts → Add Contact
   - **Verify:** Email domain shortcuts render as `DomainChip` pills
   - Tap `@yahoo.com` domain
   - **Verify:** Domain fills the email field, pill highlights
   - Type a username (e.g., `jane`)
   - Tap `@outlook.com`
   - **Verify:** Domain replaces `@yahoo.com` in the field, `@outlook.com` pill highlights
4. **Disabled state check (contact form only):**
   - Fill in Name and Email fields
   - Tap Save
   - **While saving indicator is active:** attempt to tap domain pills
   - **Verify:** Pills are visually muted and do not respond to taps

### Tier 2 — Data Integrity

**Test Steps:**

1. **Venue contact save:**
   - Add a venue with a contact
   - Use `@gmail.com` domain shortcut to fill contact email
   - Save venue
   - **Verify:** Venue saves successfully, contact email persists correctly
   - Navigate back to venue detail screen
   - **Verify:** Contact email displays correctly
2. **Standalone contact save:**
   - Add a standalone contact
   - Use `@icloud.com` domain shortcut to fill email
   - Save contact
   - **Verify:** Contact saves successfully, email persists correctly
   - Navigate back to contacts list
   - **Verify:** Contact email displays correctly

### Tier 3 — Regression Check

**Test Steps:**

1. **Invite members screen (reference implementation):**
   - Navigate to a band → Invite Members
   - **Verify:** Email domain shortcuts still render correctly as `DomainChip` pills
   - **Verify:** Interaction behavior unchanged
2. **Login screen (reference implementation):**
   - Sign out
   - Navigate to login screen
   - **Verify:** Email domain shortcuts still render correctly as `DomainChip` pills
   - **Verify:** Interaction behavior unchanged

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1 — Upgrade `venue_contact_block.dart`

1. Add `String? _selectedDomain;` state variable to `_VenueContactBlockState`
2. Add `_applyDomainShortcut(String domain)` method (copy exact implementation from `invite_members_screen.dart`)
3. Locate line 225: `EmailDomainShortcutBar(controller: _emailController)`
4. Replace with `DomainChip` row (exact pattern from `invite_members_screen.dart` lines 481-499)
5. Update imports:
   - Add: `import 'package:bandroadie/components/ui/domain_chip.dart';`
   - Add: `import 'package:bandroadie/shared/utils/email_domain_helper.dart';` (if not already present)
   - Remove: `import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';`
6. Run `flutter analyze`
7. Verify: 0 errors

### Task 2 — Upgrade `contact_form_screen.dart`

1. Add `String? _selectedDomain;` state variable to `_ContactFormScreenState`
2. Add `_applyDomainShortcut(String domain)` method (copy exact implementation from `invite_members_screen.dart`)
3. Locate line 270: `EmailDomainShortcutBar(controller: _emailController)`
4. Replace with `DomainChip` row (exact pattern from `invite_members_screen.dart` lines 481-499)
5. **Important:** Set `isEnabled: !_isSaving` (not `!_isSendingInvite`) — gate on the `_isSaving` state variable
6. Update imports:
   - Add: `import 'package:bandroadie/components/ui/domain_chip.dart';`
   - Add: `import 'package:bandroadie/shared/utils/email_domain_helper.dart';` (if not already present)
   - Remove: `import 'package:bandroadie/components/ui/email_domain_shortcut_bar.dart';`
7. Run `flutter analyze`
8. Verify: 0 errors

### Task 3 — Generate Git Diff

1. Run: `git diff lib/features/contacts/widgets/venue_contact_block.dart > venue_contact_block.diff`
2. Run: `git diff lib/features/contacts/widgets/contact_form_screen.dart > contact_form_screen.diff`
3. Review both diffs to confirm only the expected changes are present

### Task 4 — Produce Engineer Report

1. Document completion of all 3 tasks
2. Attach both git diffs
3. State whether `flutter analyze` passed (must be YES)
4. List any blockers or unexpected findings
5. Save to `docs/features/bug-contact-email-pills-inconsistent/ENGINEER_REPORT.md`

---

## Additional Context

### Implementation Notes

- The `_applyDomainShortcut()` method is identical across all files — no customization required
- The `DomainChip` row pattern is identical — only the `isEnabled` parameter varies:
  - `venue_contact_block.dart`: always `true` (no loading state in this widget)
  - `contact_form_screen.dart`: `!_isSaving` (gate on form save state)
  - `invite_members_screen.dart` (reference): `!_isSendingInvite` (gate on invite send state)
- The `_selectedDomain` state variable tracks which domain was last tapped — this powers the selection highlight

### Design Rationale

This fix eliminates the visual inconsistency introduced by using two different chip styles for the same feature across the app. By standardizing on `DomainChip`, all email domain shortcuts now share the same animated pill interaction, selection state behavior, and visual design tokens.

### Future Cleanup

After this fix is merged, `lib/components/ui/email_domain_shortcut_bar.dart` can be safely deleted — it will no longer be referenced by any file in the codebase. This cleanup is out of scope for this bug fix but should be tracked as technical debt.

---

**Plan Status:** APPROVED  
**Ready for Engineer:** YES  
**Blocked:** NO
