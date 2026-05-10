# Architect Plan — Email Domain Chips Missing from Multiple Screens

**Feature Identifier:** `bug/domain-chips-missing-multiple-screens`  
**Type:** Bug  
**Branch:** `bug/domain-chips-missing-multiple-screens`

---

## Problem Statement

Email domain shortcut chips (DomainChip row) are absent from multiple screens that contain email input fields. Users must type complete email addresses manually instead of using convenient domain shortcuts (@gmail.com, @yahoo.com, @icloud.com, @outlook.com).

The correct implementation pattern exists in `contact_form_screen.dart` and `venue_contact_block.dart` on the `bug/contact-email-pills-inconsistent` branch (not yet merged to main). This bug fix will apply the same pattern consistently across all other screens with email inputs.

---

## Diagnosis

### Confidence: HIGH

Direct code observation confirms that multiple screens have email input fields (`TextInputType.emailAddress`) without the DomainChip widget row. The reference implementation pattern on branch `bug/contact-email-pills-inconsistent` provides a clear, tested model.

### Evidence

**Reference Implementation Pattern (from `bug/contact-email-pills-inconsistent` branch):**

```dart
// 1. Imports
import 'package:bandroadie/components/ui/domain_chip.dart';
import 'package:bandroadie/shared/utils/email_domain_helper.dart';

// 2. State variable
String? _selectedDomain;

// 3. Method
void _applyDomainShortcut(String domain) {
  final current = _emailController.text;
  final result = applyEmailDomainShortcut(current, domain);

  if (result.isEmpty) return;

  _emailController.text = result;
  _emailController.selection = TextSelection.fromPosition(
    TextPosition(offset: result.length),
  );
  setState(() => _selectedDomain = domain);
}

// 4. Widget placement (after email TextField)
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
          isEnabled: !_isSaving, // or equivalent loading state
          onTap: () => _applyDomainShortcut(domain),
        ),
      );
    }).toList(),
  ),
),
const SizedBox(height: 16),
```

**Files searched:**

- All `lib/features/**/*.dart` files containing `TextField` or `TextFormField` widgets
- Filtered to email input fields via `TextInputType.emailAddress`

**Complete list of email input fields found:**

| File                                                       | Line | Purpose                             | Status                                                            |
| ---------------------------------------------------------- | ---- | ----------------------------------- | ----------------------------------------------------------------- |
| `lib/features/auth/login_screen.dart`                      | 460  | Login email entry                   | ✅ Has private `_DomainChip` (out of scope per feature input)     |
| `lib/features/auth/invite_screen.dart`                     | 393  | Sign in to accept band invite       | ⚠️ Auth-related — needs clarification                             |
| `lib/features/contacts/widgets/invite_members_screen.dart` | 334  | Invite members to band              | ❌ **MISSING** (confirmed in scope)                               |
| `lib/features/bands/band_form_screen.dart`                 | 2061 | Invite members during band creation | ⚠️ Has custom implementation (needs evaluation)                   |
| `lib/features/contacts/widgets/contact_form_screen.dart`   | 294  | Contact email                       | ✅ Fixed on `bug/contact-email-pills-inconsistent` (out of scope) |
| `lib/features/contacts/widgets/venue_contact_block.dart`   | 208  | Venue contact email                 | ✅ Fixed on `bug/contact-email-pills-inconsistent` (out of scope) |

---

## Root Cause Analysis

### 1. `invite_members_screen.dart` — CONFIRMED MISSING

**Current state:**

- Email `TextFormField` exists at line 332-370
- No `domain_chip.dart` import
- No `email_domain_helper.dart` import
- No `_selectedDomain` state variable
- No `_applyDomainShortcut()` method
- No `DomainChip` widget row after email input

**Why missing:**
Screen was built before the domain chip pattern was established. The `_buildInviteEmailInput()` method returns a Row with the TextField and an "Invite" button, but no domain shortcuts below.

**Loading state variable:** `_isSendingInvite`

---

### 2. `band_form_screen.dart` — CUSTOM IMPLEMENTATION

**Current state:**

- Email `TextFormField` exists at line 2058-2107
- **Has its own custom domain shortcut implementation:**
  - State variable: `_selectedEmailDomain` (line 124)
  - Method: `_addEmailDomain(String domain)` (line 1479-1496)
  - Widget: `_buildEmailDomainShortcuts()` (line 2117-2163)
  - Custom pill widget with inline `AnimatedContainer` and `GestureDetector`
- Does NOT use shared `DomainChip` widget
- Does NOT use `email_domain_helper.dart`

**Why different:**
This screen was likely built independently or before the shared pattern was established. It has working domain shortcuts but uses a custom UI implementation instead of the standardized `DomainChip` widget.

**Decision required:**
Should this screen be refactored to use the shared `DomainChip` widget for consistency, or should the custom implementation be left as-is?

**Recommendation:** Refactor to shared pattern for maintainability and consistency. However, if this screen is complex or mission-critical, the custom implementation can remain with a note documenting the deviation.

**Loading state variable:** Not used in domain shortcut context (emails are added to a list immediately)

---

### 3. `invite_screen.dart` — AUTH-RELATED (CLARIFICATION NEEDED)

**Current state:**

- Email `TextField` exists at line 391-410
- No domain chip implementation
- Purpose: Sign in to accept a band invitation via deep link

**Why ambiguous:**
The feature input excludes "Auth/login screens (email entry there is a different UX context)", and `login_screen.dart` is explicitly excluded. However, `invite_screen.dart` is not technically a login screen — it's a band invitation acceptance flow that requires authentication.

**Question for Tony:**
Should `invite_screen.dart` be included in this bug fix, or is it considered part of the auth context and excluded?

**If included:** Apply the same pattern as `invite_members_screen.dart`  
**Loading state variable:** `_signingIn`

---

## Affected Systems

| System                 | Impact                                                                   |
| ---------------------- | ------------------------------------------------------------------------ |
| Gigs                   | unaffected                                                               |
| Rehearsals             | unaffected                                                               |
| Setlists / Catalog     | unaffected                                                               |
| Members (invite flow)  | **affected** — `invite_members_screen.dart`                              |
| Contacts (create/edit) | unaffected (fixed on `bug/contact-email-pills-inconsistent`)             |
| Venues (create/edit)   | unaffected (fixed on `bug/contact-email-pills-inconsistent`)             |
| Bands (create flow)    | **potentially affected** — `band_form_screen.dart` custom implementation |
| Auth / Session         | **clarification needed** — `invite_screen.dart`                          |
| Routing                | unaffected                                                               |

---

## Database / RLS / RPC Impact

**Database:** Not applicable — UI-only change  
**RLS Policies:** Not applicable  
**RPC Functions:** Not applicable  
**Migrations:** Not applicable

This bug fix is purely a UI enhancement. No backend changes are required.

---

## Dependencies

### Files Required from `bug/contact-email-pills-inconsistent` Branch

This bug fix depends on the following files being available (either merged from `bug/contact-email-pills-inconsistent` or cherry-picked to this branch):

1. **`lib/components/ui/domain_chip.dart`**  
   The shared DomainChip widget component.

2. **`lib/shared/utils/email_domain_helper.dart`**  
   Helper function `applyEmailDomainShortcut()` and constant `emailDomainShortcuts`.

**If these files do not exist on the target branch, the Engineer must:**

- Copy them from `bug/contact-email-pills-inconsistent` branch via `git show bug/contact-email-pills-inconsistent:<file_path>`
- OR wait for that branch to be merged into main before proceeding
- OR coordinate with Tony to determine the correct approach

---

## Proposed Solution

### Scope

**UI-only changes** to screens with email input fields that are missing the DomainChip pattern.

**In scope:**

- Add DomainChip pattern to `invite_members_screen.dart`
- (Optional) Refactor `band_form_screen.dart` to use shared DomainChip widget
- (Pending clarification) Add DomainChip pattern to `invite_screen.dart`

**Out of scope:**

- `lib/features/auth/login_screen.dart` — excluded per feature input (auth/login context)
- `lib/features/contacts/widgets/contact_form_screen.dart` — fixed on `bug/contact-email-pills-inconsistent`
- `lib/features/contacts/widgets/venue_contact_block.dart` — fixed on `bug/contact-email-pills-inconsistent`
- Any other screens without email input fields
- Any database, RLS, RPC, or state management changes
- Modifications to `domain_chip.dart` or `email_domain_helper.dart` (use as-is)

---

### Task 1: Add DomainChip to `invite_members_screen.dart`

**File:** `lib/features/contacts/widgets/invite_members_screen.dart`

**Changes:**

1. **Add imports** (after existing imports, before the class comment):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Add state variable** (in `_InviteMembersScreenState`, after line 31):

   ```dart
   String? _selectedDomain;
   ```

3. **Add method** (in `_InviteMembersScreenState`, after `_cancelInvite()` method, before `_buildInviteEmailInput()`):

   ```dart
   void _applyDomainShortcut(String domain) {
     if (_isSendingInvite) return;

     final current = _inviteEmailController.text;
     final result = applyEmailDomainShortcut(current, domain);

     if (result.isEmpty) {
       return;
     }

     _inviteEmailController.text = result;
     _inviteEmailController.selection = TextSelection.fromPosition(
       TextPosition(offset: result.length),
     );
     setState(() => _selectedDomain = domain);
   }
   ```

4. **Modify `build()` method** (after the call to `_buildInviteEmailInput()` in the Column, around line 469):

   **Current:**

   ```dart
   _buildInviteEmailInput(),
   if (_pendingInvites.isNotEmpty) ...[
   ```

   **Replace with:**

   ```dart
   _buildInviteEmailInput(),
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
             isEnabled: !_isSendingInvite,
             onTap: () => _applyDomainShortcut(domain),
           ),
         );
       }).toList(),
     ),
   ),
   const SizedBox(height: 16),
   if (_pendingInvites.isNotEmpty) ...[
   ```

   **Explanation:**
   - 8px spacing after email input
   - Horizontal scrollable row of DomainChip widgets
   - Chips are disabled while `_isSendingInvite` is true
   - 16px spacing before the next section (pending invites list)

---

### Task 2 (Optional): Refactor `band_form_screen.dart` to Use Shared DomainChip

**File:** `lib/features/bands/band_form_screen.dart`

**Decision required:** Should this screen be refactored to use the shared `DomainChip` widget, or should the custom implementation remain?

**If refactoring is approved:**

1. **Add imports** (after existing imports):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Rename state variable** (line 124):
   - **Current:** `String? _selectedEmailDomain;`
   - **New:** `String? _selectedDomain;`

3. **Replace `_addEmailDomain()` method** (lines 1479-1496) with:

   ```dart
   void _applyDomainShortcut(String domain) {
     final current = _emailController.text;
     final result = applyEmailDomainShortcut(current, domain);

     if (result.isEmpty) {
       showAppSnackBar(
         context,
         message: 'Please enter a username first',
         backgroundColor: context.colors.warning,
       );
       return;
     }

     _emailController.text = result;
     _emailController.selection = TextSelection.fromPosition(
       TextPosition(offset: result.length),
     );
     setState(() => _selectedDomain = domain);
     HapticFeedback.selectionClick();
   }
   ```

4. **Replace `_buildEmailDomainShortcuts()` method** (lines 2117-2163) with:

   ```dart
   Widget _buildEmailDomainShortcuts() {
     return SingleChildScrollView(
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
               isEnabled: true, // Always enabled in create mode
               onTap: () => _applyDomainShortcut(domain),
             ),
           );
         }).toList(),
       ),
     );
   }
   ```

5. **Update state reset** (line 1488 in `_addEmailDomain` is now in `_applyDomainShortcut`):
   - State variable `_selectedDomain` is updated inside `_applyDomainShortcut()`

**Impact:**

- Removes ~50 lines of custom UI code
- Unifies visual appearance with other screens
- Simplifies maintenance (one shared widget instead of duplicated logic)

**Risk:**

- Low — the functionality is equivalent, just using a shared widget
- Verify that haptic feedback is preserved (added in new `_applyDomainShortcut()`)

**If refactoring is NOT approved:**

- Document the deviation in code comments
- Leave `band_form_screen.dart` unchanged

---

### Task 3 (Pending Clarification): Add DomainChip to `invite_screen.dart`

**File:** `lib/features/auth/invite_screen.dart`

**Pending decision:** Is this screen in scope, or is it excluded as part of the auth context?

**If in scope, apply the same pattern as Task 1:**

1. **Add imports** (after existing imports):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Add state variable** (in `_InviteScreenState`, after line 31):

   ```dart
   String? _selectedDomain;
   ```

3. **Add method** (in `_InviteScreenState`, after `_sendMagicLink()` method):

   ```dart
   void _applyDomainShortcut(String domain) {
     if (_signingIn) return;

     final current = _emailController.text;
     final result = applyEmailDomainShortcut(current, domain);

     if (result.isEmpty) {
       return;
     }

     _emailController.text = result;
     _emailController.selection = TextSelection.fromPosition(
       TextPosition(offset: result.length),
     );
     setState(() => _selectedDomain = domain);
   }
   ```

4. **Modify the email input section** (after the TextField, around line 410):

   **Current:**

   ```dart
   onSubmitted: (_) => _sendMagicLink(),
   ),
   ),
   const SizedBox(height: 16),
   SizedBox(
   width: 320,
   height: 48,
   child: ElevatedButton(
   ```

   **Replace with:**

   ```dart
   onSubmitted: (_) => _sendMagicLink(),
   ),
   ),
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
          isEnabled: !_signingIn,
          onTap: () => _applyDomainShortcut(domain),
        ),
      );
    }).toList(),
   ),
   ),
   const SizedBox(height: 16),
   SizedBox(
   width: 320,
   height: 48,
   child: ElevatedButton(
   ```

---

## Files to Modify

### Confirmed

1. **`lib/features/contacts/widgets/invite_members_screen.dart`**  
   Add DomainChip pattern (imports, state, method, widget row)

### Conditional (Pending Decision)

2. **`lib/features/bands/band_form_screen.dart`**  
   Refactor to use shared DomainChip widget (if approved)

3. **`lib/features/auth/invite_screen.dart`**  
   Add DomainChip pattern (if determined to be in scope)

---

## Files to NOT Modify

These files either already have the pattern or are explicitly excluded:

- **`lib/features/auth/login_screen.dart`** — has private `_DomainChip`, excluded per feature input
- **`lib/features/contacts/widgets/contact_form_screen.dart`** — fixed on `bug/contact-email-pills-inconsistent`
- **`lib/features/contacts/widgets/venue_contact_block.dart`** — fixed on `bug/contact-email-pills-inconsistent`
- **`lib/components/ui/domain_chip.dart`** — use as-is from reference branch
- **`lib/shared/utils/email_domain_helper.dart`** — use as-is from reference branch
- Any database migration files
- Any RPC function definitions
- Any RLS policy files
- Any state management controllers or providers

---

## Verification Plan

### Pre-Implementation Validation

1. **Verify dependency files exist:**

   ```bash
   test -f lib/components/ui/domain_chip.dart && echo "✅ domain_chip.dart exists"
   test -f lib/shared/utils/email_domain_helper.dart && echo "✅ email_domain_helper.dart exists"
   ```

   If either file does not exist:
   - Copy from `bug/contact-email-pills-inconsistent` branch
   - OR coordinate with Tony for merge/cherry-pick strategy

2. **Verify flutter analyze passes before changes:**
   ```bash
   flutter analyze
   ```

### Post-Implementation Testing

#### Unit Testing (Helper Function)

While this is a UI-only change, the `email_domain_helper.dart` logic should already have tests (if not, tests are out of scope per feature input). The Engineer should verify that `applyEmailDomainShortcut()` behaves correctly:

- Empty input → no change
- `"tony"` + `"@gmail.com"` → `"tony@gmail.com"`
- `"tony@yahoo.com"` + `"@icloud.com"` → `"tony@icloud.com"`

#### Manual UI Testing

**For `invite_members_screen.dart`:**

1. Navigate to a band's settings → "Invite Members"
2. Verify DomainChip row appears below the email input field
3. Tap each domain chip:
   - With empty input: no change (or remains empty)
   - With "tony": appends domain → "tony@gmail.com"
   - With "tony@yahoo.com": replaces domain → "tony@icloud.com"
4. Verify selected chip has visual selection state (primary color border)
5. Verify chips are disabled while invite is sending (loading state)
6. Verify keyboard behavior: chips do not interfere with typing or submission
7. Test on iOS, Android, macOS, and Web

**For `band_form_screen.dart` (if refactored):**

1. Navigate to "Create New Band"
2. Fill in band name, scroll to "Invite Members" section
3. Verify DomainChip row appears below the email input field
4. Tap each domain chip and verify behavior matches `invite_members_screen.dart`
5. Verify visual consistency with reference implementation
6. Verify haptic feedback on tap (mobile only)
7. Test on iOS, Android, macOS, and Web

**For `invite_screen.dart` (if in scope):**

1. Generate a test invite link: `/invite?token=<test_token>`
2. Open link in browser or deep link on mobile
3. Verify DomainChip row appears below the email input field
4. Tap each domain chip and verify behavior matches other screens
5. Verify chips are disabled while sign-in is in progress
6. Test on iOS, Android, macOS, and Web

#### Visual Regression Testing

- Compare screenshots of affected screens before/after
- Verify spacing: 8px below email field, 16px below chip row
- Verify pill shape: 100px border radius, correct padding
- Verify selected state: primary color border, slightly darker background
- Verify disabled state: muted text color, no interaction

#### Accessibility Testing

- Verify chips are keyboard-navigable on web
- Verify screen reader announces chip labels
- Verify minimum touch target size (48px) is met on mobile

#### Analyzer & Build Validation

```bash
flutter analyze
flutter build macos --release
flutter build web --release
flutter build ios --no-codesign
flutter build apk
```

All builds must succeed with 0 errors.

---

## Engineer Task Breakdown

### Task 0: Dependency Check (BLOCKING)

**Objective:** Verify that `domain_chip.dart` and `email_domain_helper.dart` exist on the current branch.

**Steps:**

1. Check if files exist:

   ```bash
   test -f lib/components/ui/domain_chip.dart && echo "EXISTS" || echo "MISSING"
   test -f lib/shared/utils/email_domain_helper.dart && echo "EXISTS" || echo "MISSING"
   ```

2. If MISSING, copy from `bug/contact-email-pills-inconsistent` branch:

   ```bash
   git show bug/contact-email-pills-inconsistent:lib/components/ui/domain_chip.dart > lib/components/ui/domain_chip.dart
   git show bug/contact-email-pills-inconsistent:lib/shared/utils/email_domain_helper.dart > lib/shared/utils/email_domain_helper.dart
   ```

3. Verify imports and constants are correct:
   - `domain_chip.dart` should export `DomainChip` widget
   - `email_domain_helper.dart` should export `applyEmailDomainShortcut()` and `emailDomainShortcuts`

4. Run `flutter analyze` to confirm no immediate errors

**Blocking:** Tasks 1-3 cannot proceed until this task is complete.

**Output:** Confirmation that dependency files are available and valid.

---

### Task 1: Add DomainChip to `invite_members_screen.dart` (REQUIRED)

**Objective:** Add email domain shortcut chips to the Invite Members screen using the shared DomainChip widget.

**Dependencies:** Task 0 must be complete.

**File:** `lib/features/contacts/widgets/invite_members_screen.dart`

**Steps:**

1. **Add imports** (after line 11, before the comment block):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Add state variable** (after line 31, in `_InviteMembersScreenState`):

   ```dart
   String? _selectedDomain;
   ```

3. **Add `_applyDomainShortcut()` method** (after `_cancelInvite()` method, around line 329, before `_buildInviteEmailInput()`):

   ```dart
   void _applyDomainShortcut(String domain) {
     if (_isSendingInvite) return;

     final current = _inviteEmailController.text;
     final result = applyEmailDomainShortcut(current, domain);

     if (result.isEmpty) {
       return;
     }

     _inviteEmailController.text = result;
     _inviteEmailController.selection = TextSelection.fromPosition(
       TextPosition(offset: result.length),
     );
     setState(() => _selectedDomain = domain);
   }
   ```

4. **Add DomainChip row in `build()` method** (after `_buildInviteEmailInput()`, around line 469):

   **Find this block:**

   ```dart
   _buildInviteEmailInput(),
   if (_pendingInvites.isNotEmpty) ...[
   ```

   **Replace with:**

   ```dart
   _buildInviteEmailInput(),
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
             isEnabled: !_isSendingInvite,
             onTap: () => _applyDomainShortcut(domain),
           ),
         );
       }).toList(),
     ),
   ),
   const SizedBox(height: 16),
   if (_pendingInvites.isNotEmpty) ...[
   ```

5. **Run `flutter analyze`** and fix any errors.

6. **Test manually** on all platforms (iOS, Android, macOS, Web).

7. **Document changes** in `ENGINEER_REPORT.md`.

**Expected outcome:**

- Email input field in Invite Members screen now has domain shortcut chips below it
- Chips behave identically to the reference implementation in `contact_form_screen.dart`
- No regressions in existing invite functionality

**Estimated time:** 30-45 minutes

---

### Task 2: Refactor `band_form_screen.dart` to Use Shared DomainChip (OPTIONAL — PENDING DECISION)

**Objective:** Replace custom domain shortcut implementation with the shared DomainChip widget for consistency.

**Dependencies:** Task 0 must be complete. Task 1 completion is recommended (to validate the pattern first).

**File:** `lib/features/bands/band_form_screen.dart`

**Decision required from Tony:** Should this screen be refactored, or should the custom implementation remain?

**If approved, steps:**

1. **Add imports** (after line 26, before the comment block):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Rename state variable** (line 124):
   - **Find:** `String? _selectedEmailDomain;`
   - **Replace with:** `String? _selectedDomain;`

3. **Replace `_addEmailDomain()` method** (lines 1479-1496):
   - **Delete the entire `_addEmailDomain()` method**
   - **Insert new `_applyDomainShortcut()` method:**
     ```dart
     void _applyDomainShortcut(String domain) {
       final current = _emailController.text;
       final result = applyEmailDomainShortcut(current, domain);

       if (result.isEmpty) {
         showAppSnackBar(
           context,
           message: 'Please enter a username first',
           backgroundColor: context.colors.warning,
         );
         return;
       }

       _emailController.text = result;
       _emailController.selection = TextSelection.fromPosition(
         TextPosition(offset: result.length),
       );
       setState(() => _selectedDomain = domain);
       HapticFeedback.selectionClick();
     }
     ```

4. **Replace `_buildEmailDomainShortcuts()` method** (lines 2117-2163):
   - **Delete the entire `_buildEmailDomainShortcuts()` method**
   - **Insert new simplified version:**
     ```dart
     Widget _buildEmailDomainShortcuts() {
       return SingleChildScrollView(
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
                 isEnabled: true,
                 onTap: () => _applyDomainShortcut(domain),
               ),
             );
           }).toList(),
         ),
       );
     }
     ```

5. **Update `_selectedEmailDomain` reference** (line 2131):
   - Already handled by renaming state variable in step 2

6. **Run `flutter analyze`** and fix any errors.

7. **Test manually** — verify behavior is identical to before refactoring:
   - Create new band flow
   - Invite members section
   - Domain chip tap behavior
   - Visual appearance
   - Haptic feedback on mobile

8. **Visual regression check** — compare before/after screenshots.

9. **Document changes** in `ENGINEER_REPORT.md`, including rationale for refactoring.

**Expected outcome:**

- Custom domain shortcut UI replaced with shared DomainChip widget
- Functionality remains identical
- ~50 lines of code removed, replaced with shared component
- Visual appearance consistent with other screens

**Estimated time:** 45-60 minutes

**Risk:** Low — functionality is equivalent, visual appearance may have minor differences. Verify thoroughly.

**If NOT approved:**

- Skip this task
- Document the deviation in code comments (add a comment in `band_form_screen.dart` explaining why custom implementation is retained)

---

### Task 3: Add DomainChip to `invite_screen.dart` (CONDITIONAL — PENDING CLARIFICATION)

**Objective:** Add email domain shortcut chips to the Invite Screen (band invitation acceptance flow).

**Dependencies:** Task 0 must be complete. Task 1 completion is recommended.

**File:** `lib/features/auth/invite_screen.dart`

**Decision required from Tony:** Is this screen in scope, or is it excluded as part of the auth context?

**Reason for ambiguity:**

- Feature input excludes "Auth/login screens (email entry there is a different UX context)"
- `invite_screen.dart` is not technically a login screen — it's for accepting band invitations via deep link
- Users enter email to sign in (or sign up) to accept the invite
- It's in the `lib/features/auth/` directory, which suggests auth context

**If determined to be IN SCOPE, steps:**

1. **Add imports** (after line 8, before the class comment):

   ```dart
   import 'package:bandroadie/components/ui/domain_chip.dart';
   import 'package:bandroadie/shared/utils/email_domain_helper.dart';
   ```

2. **Add state variable** (after line 31, in `_InviteScreenState`):

   ```dart
   String? _selectedDomain;
   ```

3. **Add `_applyDomainShortcut()` method** (after `_sendMagicLink()` method, around line 200):

   ```dart
   void _applyDomainShortcut(String domain) {
     if (_signingIn) return;

     final current = _emailController.text;
     final result = applyEmailDomainShortcut(current, domain);

     if (result.isEmpty) {
       return;
     }

     _emailController.text = result;
     _emailController.selection = TextSelection.fromPosition(
       TextPosition(offset: result.length),
     );
     setState(() => _selectedDomain = domain);
   }
   ```

4. **Add DomainChip row in `_buildAuthForm()` method** (after the email TextField, around line 410):

   **Find this block:**

   ```dart
   onSubmitted: (_) => _sendMagicLink(),
   ),
   ),
   const SizedBox(height: 16),
   SizedBox(
   width: 320,
   height: 48,
   child: ElevatedButton(
   ```

   **Replace with:**

   ```dart
   onSubmitted: (_) => _sendMagicLink(),
   ),
   ),
   const SizedBox(height: 8),
   SizedBox(
   width: 320,
   child: SingleChildScrollView(
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
            isEnabled: !_signingIn,
            onTap: () => _applyDomainShortcut(domain),
          ),
        );
      }).toList(),
    ),
   ),
   ),
   const SizedBox(height: 16),
   SizedBox(
   width: 320,
   height: 48,
   child: ElevatedButton(
   ```

5. **Run `flutter analyze`** and fix any errors.

6. **Test manually:**
   - Generate test invite token
   - Open `/invite?token=<token>` on web or via deep link on mobile
   - Verify domain chips appear and function correctly
   - Test on iOS, Android, macOS, and Web

7. **Document changes** in `ENGINEER_REPORT.md`, including the decision to include this screen.

**Expected outcome:**

- Email input field in Invite Screen now has domain shortcut chips below it
- Chips behave identically to the reference implementation
- No regressions in invite acceptance flow

**Estimated time:** 30-45 minutes

**If determined to be OUT OF SCOPE:**

- Skip this task
- Document the decision in `ENGINEER_REPORT.md` with rationale

---

## QA Validation Checklist

After the Engineer completes implementation, QA must verify:

### Functional Testing

- [ ] **Invite Members Screen (`invite_members_screen.dart`)**
  - [ ] Domain chips visible below email input
  - [ ] Tapping chip with empty input does nothing (or shows empty)
  - [ ] Tapping chip with "tony" appends domain → "tony@gmail.com"
  - [ ] Tapping chip with "tony@yahoo.com" replaces domain → "tony@icloud.com"
  - [ ] Selected chip shows visual selection state (primary border)
  - [ ] Chips are disabled while invite is sending
  - [ ] Invite functionality works as before
  - [ ] No visual regressions

- [ ] **Band Form Screen (`band_form_screen.dart`)** — IF REFACTORED
  - [ ] Domain chips visible below email input in create mode
  - [ ] Behavior matches invite_members_screen.dart
  - [ ] Haptic feedback on chip tap (mobile)
  - [ ] Visual appearance consistent with reference implementation
  - [ ] Band creation flow works as before

- [ ] **Invite Screen (`invite_screen.dart`)** — IF IN SCOPE
  - [ ] Domain chips visible below email input
  - [ ] Behavior matches other screens
  - [ ] Chips are disabled while signing in
  - [ ] Invite acceptance flow works as before

### Platform Testing

- [ ] iOS: All affected screens tested
- [ ] Android: All affected screens tested
- [ ] macOS: All affected screens tested
- [ ] Web: All affected screens tested

### Visual Regression

- [ ] Spacing is correct (8px below email, 16px below chips)
- [ ] Pill shape matches reference (100px border radius)
- [ ] Selected state matches reference (primary border, darker background)
- [ ] Disabled state matches reference (muted text)

### Build Validation

- [ ] `flutter analyze` passes with 0 errors
- [ ] `flutter build macos --release` succeeds
- [ ] `flutter build web --release` succeeds
- [ ] `flutter build ios --no-codesign` succeeds
- [ ] `flutter build apk` succeeds

### Documentation

- [ ] `ENGINEER_REPORT.md` completed with all changes documented
- [ ] Task completion status reported for each task
- [ ] Any deviations from plan documented with rationale

---

## Additional Context

### Why This Bug Exists

The email domain shortcut feature was added in branch `feature/email-domain-shortcut-bar` (commit 23b3bff) and applied to multiple screens. A subsequent bug fix in branch `bug/contact-email-pills-inconsistent` (commit 8bc79d1) refined the implementation for `contact_form_screen.dart` and `venue_contact_block.dart`.

However, neither branch has been merged to main yet. This bug fix is designed to apply the finalized pattern from `bug/contact-email-pills-inconsistent` to ALL screens with email inputs, ensuring consistency across the app.

### Why Some Screens Have Custom Implementations

`band_form_screen.dart` has a custom domain shortcut implementation because it was likely built independently or before the shared `DomainChip` widget was created. This is technical debt that can optionally be addressed in Task 2.

### Why `login_screen.dart` is Excluded

The login screen has its own private `_DomainChip` implementation that is visually and functionally tailored to the login UX. The feature input explicitly excludes auth/login screens from this bug fix. Unifying login with the shared pattern is out of scope.

### Why `invite_screen.dart` is Ambiguous

`invite_screen.dart` is for accepting band invitations via deep link. Users enter their email to sign in (or sign up) to accept the invite. While it's in the `lib/features/auth/` directory, it's not a traditional login screen. The decision to include or exclude it depends on whether Tony considers it part of the "auth/login" context or part of the "band invitation" context.

---

## Summary

**Diagnosis confidence:** HIGH — confirmed via direct code observation  
**Root cause:** Email domain shortcut chips are missing from multiple screens due to incomplete feature rollout  
**Proposed solution:** Apply the shared DomainChip pattern from `bug/contact-email-pills-inconsistent` branch to all affected screens  
**Files to modify:** 1-3 files depending on decisions (confirmed: 1, conditional: 2)  
**Database impact:** None — UI-only change  
**RLS/RPC impact:** None  
**Risk:** Low — localized UI changes with clear reference implementation

**Engineer task order:**

1. Task 0: Verify dependency files exist (BLOCKING)
2. Task 1: Add DomainChip to `invite_members_screen.dart` (REQUIRED)
3. Task 2: Refactor `band_form_screen.dart` (OPTIONAL — pending decision)
4. Task 3: Add DomainChip to `invite_screen.dart` (CONDITIONAL — pending clarification)

**Blocking decisions required from Tony:**

- [ ] Should `band_form_screen.dart` be refactored to use shared DomainChip, or should the custom implementation remain?
- [ ] Is `invite_screen.dart` in scope, or is it excluded as part of the auth context?

---

**Plan Author:** Architect Agent  
**Date:** May 9, 2026  
**Status:** Ready for Engineer implementation (pending Task 0 dependency check and Tony's decisions on Tasks 2 & 3)
