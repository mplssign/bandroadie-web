# ARCHITECT_PLAN.md — contacts-venues-followup

## Feature Slug
`feature/contacts-venues-followup`

---

## Problem Summary

This feature addresses 5 separate but related issues in the Contacts/Venues domain:

1. **Double plus sign on empty-state buttons**: VenuesEmptyState and ContactsEmptyState both pass `label: '+ Add Venue'` (or `'+ Add Contact'`) to BrandActionButton, which then prepends an icon (LucideIcons.plus). Result: two `+` symbols are shown.

2. **Phone field auto-format missing for non-US bands**: Phone input fields in VenueFormScreen, VenueContactBlock, and ContactFormScreen lack timezone-aware auto-formatting. US bands should see (123) 456-7890 format, but non-US bands should get plain text input.

3. **Address forms are US-centric**: VenueFormScreen hardcodes "State" label and layout; ContactFormScreen has no address fields at all. Non-US bands (Canada, UK) need geographically appropriate labels and fields.

4. **Band member invitations mixed in Edit Band form**: BandFormScreen edit mode includes an "Invite Members" section in the form, conflating band-level settings with member management. Member invitations should live exclusively in the Contacts tab under the Members section.

5. **Timezone picker outdated and not grouped**: BandFormScreen's timezone list is small (11 entries), not grouped by region, and missing Canadian timezones. The label and helper text are vague.

---

## Root Causes

### Issue 1: Double plus sign
**Confidence: HIGH**

Root cause: BrandActionButton in `lib/components/ui/brand_action_button.dart` (lines 79–94) renders `[icon][space][label]`. The label already contains a `+` character from the empty-state files (lines 62–64 in venues_empty_state.dart, lines 61–64 in contacts_empty_state.dart).

Evidence: 
- VenuesEmptyState line 62: `label: '+ Add Venue'`
- ContactsEmptyState line 62: `label: '+ Add Contact'`
- BrandActionButton line 79–94 renders both icon and label in sequence.

---

### Issue 2: Missing phone auto-formatter for non-US timezone
**Confidence: HIGH**

Root cause: Phone fields in venue_form_screen.dart (line 339–343), venue_contact_block.dart (line 181–187), and contact_form_screen.dart (line 202–208) all use bare `TextInputType.phone` with no TextInputFormatter. There is no timezone-aware formatting logic anywhere.

Evidence:
- All three phone field declarations lack `inputFormatters` parameter.
- activeBandProvider in active_band_controller.dart exposes `activeBand?.timezone` but is never read in these widgets.
- No TextInputFormatter exists in lib/shared/utils for phone formatting.

---

### Issue 3: US-centric address form layout
**Confidence: HIGH**

Root cause:
- VenueFormScreen (lines 313–336) hardcodes "City" + "State" in a two-column row with fixed-width "State" field (100px). No alternative label logic based on timezone.
- ContactFormScreen (lines 176–228) has no address fields at all (only name, title, phone, email, notes).
- Neither form reads activeBandProvider to detect timezone and adapt labels/fields accordingly.

Evidence:
- venue_form_screen.dart line 332: `decoration: _inputDecoration('State')` is literal.
- contact_form_screen.dart omits all address fields.
- activeBandProvider is imported but never used in either form.

---

### Issue 4: Member invitations in BandFormScreen edit mode
**Confidence: HIGH**

Root cause: BandFormScreen has duplicate invite logic:
- CREATE mode (lines 1861–1894): `_buildEmailInput()`, `_buildEmailDomainShortcuts()`, `_buildSectionLabel('Invites sent')`, `_EmailPill`.
- EDIT mode (lines 1835–1858): `_buildInviteEmailInput()` (different UI, same purpose), `_buildPendingInvitesList()`, `_InvitePill`.
- Methods used only in edit mode: `_loadPendingInvites()` (line 1058), `_sendInvite()` (line 1105), `_cancelInvite()` (line 1247), `_isSendingInvite` state (line 135), `_inviteEmailController` (line 133), `_pendingInvites` (line 134).

ContactsTabContent calls `_openInviteScreen()` (line 102) which navigates to `BandFormScreen(mode: edit)` (lines 107–111) specifically to invite members. This logic should be decoupled.

Evidence:
- band_form_screen.dart line 190: `_loadPendingInvites()` called only in initState edit mode.
- line 1835–1858: entire "Invite Members" edit-mode section has no relation to band name/avatar/timezone settings.
- contacts_tab_content.dart line 102–114: `_openInviteScreen()` explicitly uses BandFormScreen for invites.

---

### Issue 5: Timezone picker lacks grouping and Canadian timezones
**Confidence: HIGH**

Root cause: BandFormScreen `_timezoneOptions` (lines 2188–2200) is a flat list with 11 entries, no grouping. Existing values (America/New_York, etc.) are still in the list, but removed values (Europe/Paris, Europe/Berlin, Asia/Tokyo, Australia/Sydney) will silently fall back to 'America/Chicago' (line 2230).

The label and helper are vague:
- Line 2214: `_buildSectionLabel('Timezone')` (generic)
- Lines 2216–2224: `'Used for calendar subscription feeds'` (doesn't explain broader use)

No Canadian timezones (America/Vancouver, America/Edmonton, America/Regina, America/Toronto, America/Halifax, America/St_Johns) are present.

Evidence:
- band_form_screen.dart lines 2188–2200: flat list structure, no grouping.
- No Canadian entries in the list.
- Feature input specifies a grouped structure with country headers.

---

## Existing System Analysis

### VenuesEmptyState & ContactsEmptyState
- Stateless widgets that render an empty state message with an optional button.
- Both pass `label: '+ Add Venue'` / `'+ Add Contact'` and `icon: AppIcons.add` / `icon: AppIcons.userAdd` to BrandActionButton.
- BrandActionButton renders `[icon][space][label]` in a Row (line 79–94).
- Result: "[plus icon] + Add Venue" is rendered, showing two `+` symbols.

### BrandActionButton
- Takes optional `icon` and `label` string.
- Renders icon (if present) + space + label in a Row (lines 83–93).
- No logic to strip or handle leading `+` characters in the label.

### Phone Input Fields
- VenueFormScreen: `_phoneController` (line 33), no formatters applied (line 339–343).
- VenueContactBlock: same pattern (line 181–187).
- ContactFormScreen: same pattern (line 202–208).
- No timezone-aware logic exists anywhere in the codebase for phone formatting.

### Address Fields
- VenueFormScreen: hardcoded "City" + "State" layout (lines 313–336), State field width 100px.
- ContactFormScreen: zero address fields (only name, title, phone, email, notes).
- No conditional logic based on band timezone.

### BandFormScreen Invite Logic
- `_inviteEmailController` (line 133) used only in edit mode.
- `_pendingInvites` (line 134) state and `_isSendingInvite` (line 135) flag used only in edit mode.
- `_loadPendingInvites()` (line 1058–1103): queries band_invitations table, dedupes by email.
- `_sendInvite()` (line 1105–1245): validates email, checks membership, inserts invite, calls send-band-invite edge function.
- `_cancelInvite()` (line 1247–1321): deletes invitation.
- Create mode uses a different API (_emailController, _addEmail, _removeEmail) for immediate invites (before band is created).
- Edit mode uses persistent invites stored in band_invitations table.

ContactsTabContent._openInviteScreen() navigates directly to BandFormScreen edit mode to manage invites. This is a UI/UX smell: member management is buried inside band editing.

### Timezone System
- BandFormScreen stores `_selectedTimezone` (line 130) and calls `_buildTimezoneSection()` (line 2202–2285).
- activeBandProvider (active_band_controller.dart) exposes band.timezone as IANA string (e.g., 'America/Chicago').
- No other code uses timezone for conditional behavior (phone formatting, address labels, etc.).

---

## Proposed Solution

### Issue 1: Fix Double Plus Sign

**Fix:** Remove the leading `+` from the button labels in empty-state widgets. BrandActionButton will render the icon automatically.

**Exact Changes:**
- `lib/features/contacts/widgets/venues_empty_state.dart` line 62: change `label: '+ Add Venue'` → `label: 'Add Venue'`
- `lib/features/contacts/widgets/contacts_empty_state.dart` line 62: change `label: '+ Add Contact'` → `label: 'Add Contact'`

**Rationale:** BrandActionButton's icon rendering is the single source of truth for the leading `+`. Labels should contain only the text, not the symbol.

---

### Issue 2: Add Phone Auto-Formatter for US Timezones

**New File:** `lib/shared/utils/phone_input_formatter.dart`
- Create a stateless `USPhoneInputFormatter extends TextInputFormatter` that:
  - Detects if band's timezone is US (America/New_York, America/Chicago, America/Denver, America/Los_Angeles, America/Anchorage, Pacific/Honolulu).
  - If US: formats as (123) 456-7890 on input, handles backspace naturally, normalizes pasted input.
  - If non-US: passes through unchanged (plain text).
  - Uses TextEditingValue manipulation to insert/remove characters while preserving cursor position.

**Implementation Details:**
- Input formatter receives TextEditingValue and returns modified value.
- Track "was formatting active" to avoid double-formatting on edits.
- On backspace: remove the preceding formatting character (dash, paren) before the digit.
- On paste: strip all non-digits, then apply formatting if active.
- Cursor position must follow the last digit entered, not jump.

**Exact Changes:**
1. Create `lib/shared/utils/phone_input_formatter.dart` with `USPhoneInputFormatter` class.
2. Update `lib/features/contacts/widgets/venue_form_screen.dart`:
   - Import activeBandProvider and phone formatter.
   - Line 339–343: add `inputFormatters: _getPhoneFormatters()` to phone TextField.
   - Add helper method `List<TextInputFormatter> _getPhoneFormatters()` that reads `ref.watch(activeBandProvider)` and returns formatter if US timezone, else empty list.
3. Update `lib/features/contacts/widgets/venue_contact_block.dart`:
   - Import phone formatter (cannot use ref here; must pass timezone as parameter or read from context).
   - Since VenueContactBlock is a StatefulWidget (not ConsumerStatefulWidget), cannot directly access ref.
   - Solution: Pass timezone as a parameter from VenueFormScreen to VenueContactBlock.
   - Line 181–187: add `inputFormatters: _getPhoneFormatters(timezone)`.
4. Update `lib/features/contacts/widgets/contact_form_screen.dart`:
   - Import activeBandProvider and phone formatter.
   - Line 202–208: add `inputFormatters: _getPhoneFormatters()`.

**Backward Compatibility:** Existing phone data is unformatted text. Formatter only applies on new input/edits, so no migration needed.

---

### Issue 3: Adapt Address Fields for Band Timezone

**Exact Changes:**

1. **VenueFormScreen** (`lib/features/contacts/widgets/venue_form_screen.dart`):
   - Import `activeBandProvider`.
   - Add helper method to read band timezone and return state label (US → "State", Canada → "Province", UK → "County").
   - Wrap city+state row in a method that conditionally renders based on timezone:
     - US: "City" + "State" (existing layout, 100px state field).
     - Canada: "City" + "Province" (same underlying field name, just relabeled, same 100px width).
     - UK: "City" + "County" (optional county field).
     - Non-US timezones: Show only "City" field, hide state/province/county entirely.
   - Update TextField label decoration to use the dynamic label.
   - Example: 
     ```dart
     String _getStateLabel() {
       final tz = ref.watch(activeBandProvider).activeBand?.timezone ?? 'America/Chicago';
       if (tz.startsWith('America/') && ['Toronto', 'Halifax', 'St_Johns', 'Edmonton', 'Vancouver', 'Regina'].any((city) => tz.contains(city))) {
         return 'Province';
       }
       if (tz == 'Europe/London') return 'County';
       return 'State';
     }
     ```

2. **ContactFormScreen** (`lib/features/contacts/widgets/contact_form_screen.dart`):
   - **Decision:** Per the feature input, assess whether ContactFormScreen should have address fields.
   - **Judgment:** Standalone contacts (agents, promoters) may not require a full address. Keep as-is (name, title, phone, email, notes only).
   - **Document in plan:** ContactFormScreen intentionally omits address fields to keep the contact model lightweight and distinct from venues. If future requirements demand address fields for contacts, they can be added in a follow-up.

---

### Issue 4: Move Member Invitations Out of BandFormScreen

**New File:** `lib/features/contacts/widgets/invite_members_screen.dart`
- Create a new `InviteMembersScreen` ConsumerStatefulWidget that:
  - Takes the band as a constructor parameter.
  - Contains all invite-related UI and logic from BandFormScreen edit mode:
    - `_inviteEmailController`
    - `_pendingInvites` and `_isSendingInvite` state
    - `_loadPendingInvites()`, `_sendInvite()`, `_cancelInvite()` methods
    - `_buildInviteEmailInput()`, `_buildPendingInvitesList()` widgets
    - `_InvitePill` widget class
  - Use ref to access activeBandProvider and show band context if needed.
  - Return to previous screen on completion.

**Exact Changes:**

1. **Create `lib/features/contacts/widgets/invite_members_screen.dart`:**
   - Copy entire invite section UI and logic from BandFormScreen.
   - Make it a standalone screen with AppBar ("Invite Members"), scrollable body.
   - Call `_loadPendingInvites()` in initState.
   - Reuse _InvitePill and _buildPendingInvitesList styling.

2. **Update BandFormScreen** (`lib/features/bands/band_form_screen.dart`):
   - Delete lines 1835–1858 (entire edit-mode "Invite Members" section).
   - Delete methods: `_loadPendingInvites()` (1058–1103), `_sendInvite()` (1105–1245), `_cancelInvite()` (1247–1321), `_buildInviteEmailInput()` (2404–2481), `_buildPendingInvitesList()` (2483–2494).
   - Delete state variables: `_inviteEmailController` (line 133), `_pendingInvites` (line 134), `_isSendingInvite` (line 135).
   - Remove `_inviteEmailController.dispose()` from dispose() (line 225).
   - Delete widget classes: `_InvitePill` (2660–2721).
   - Remove line 190 call to `_loadPendingInvites()` from initState.

3. **Update ContactsTabContent** (`lib/features/contacts/contacts_tab_content.dart`):
   - Import `InviteMembersScreen`.
   - Update `_openInviteScreen()` (lines 102–114) to navigate to InviteMembersScreen instead of BandFormScreen:
     ```dart
     void _openInviteScreen() {
       final bandState = ref.read(activeBandProvider);
       if (bandState.activeBand != null) {
         Navigator.of(context).push(
           fadeSlideRoute(
             page: InviteMembersScreen(band: bandState.activeBand!),
           ),
         );
       }
     }
     ```

**Backward Compatibility:** No DB changes. Existing invites remain in band_invitations table and continue to work. The UI path changes, but the RPC and invite logic are identical.

---

### Issue 5: Expand and Group Timezone Picker

**Exact Changes:**

1. **Update BandFormScreen** (`lib/features/bands/band_form_screen.dart`):
   - Replace `_timezoneOptions` list (lines 2188–2200) with a grouped structure using disabled DropdownMenuItem for headers.
   - New structure:
     ```dart
     static const List<Map<String, dynamic>> _timezoneOptions = [
       {'value': null, 'label': 'Canada', 'isHeader': true},
       {'value': 'America/Vancouver', 'label': 'Vancouver (Pacific)'},
       {'value': 'America/Edmonton', 'label': 'Edmonton (Mountain)'},
       {'value': 'America/Regina', 'label': 'Regina (Central)'},
       {'value': 'America/Toronto', 'label': 'Toronto (Eastern)'},
       {'value': 'America/Halifax', 'label': 'Halifax (Atlantic)'},
       {'value': 'America/St_Johns', 'label': "St. John's (Newfoundland)"},
       {'value': null, 'label': 'United States', 'isHeader': true},
       {'value': 'America/New_York', 'label': 'New York (Eastern)'},
       {'value': 'America/Chicago', 'label': 'Chicago (Central)'},
       {'value': 'America/Denver', 'label': 'Denver (Mountain)'},
       {'value': 'America/Los_Angeles', 'label': 'Los Angeles (Pacific)'},
       {'value': 'America/Anchorage', 'label': 'Anchorage (Alaska)'},
       {'value': 'Pacific/Honolulu', 'label': 'Honolulu (Hawaii-Aleutian)'},
       {'value': null, 'label': 'United Kingdom', 'isHeader': true},
       {'value': 'Europe/London', 'label': 'London'},
     ];
     ```
   - Update `_buildTimezoneSection()` (lines 2202–2285):
     - Change label from 'Timezone' to 'Timezone Location' (line 2214).
     - Change helper text from 'Used for calendar subscription feeds' to 'Used for general formatting and calendar feeds' (line 2217).
     - Update items builder to handle header entries (disabled, styled differently):
       ```dart
       items: _timezoneOptions
           .where((tz) => tz['value'] != null) // Filter out headers for items
           .map((tz) => DropdownMenuItem<String>(
                 value: tz['value'],
                 child: Text(tz['label']!),
               ))
           .toList(),
       ```
     - For better UX with grouping, consider using a custom Dropdown or PopupMenuButton. However, for minimal change, group headers can be rendered as disabled DropdownMenuItem entries with custom styling (grayed out, non-interactive).

2. **Edge Case Handling:**
   - Bands with existing timezone values not in the new list (Europe/Paris, Europe/Berlin, Asia/Tokyo, Australia/Sydney) will fall back to 'America/Chicago' via initialValue logic (line 2228–2230).
   - This is acceptable; the feature input acknowledges this edge case.
   - No data migration required; stored values remain unchanged.

---

## Database Impact

**Not applicable.** No schema changes, migrations, or RLS policy changes required. All changes are UI/logic-level only.

---

## Files to Create

| File | Purpose | Justification |
|------|---------|---------------|
| `lib/shared/utils/phone_input_formatter.dart` | USPhoneInputFormatter for timezone-aware phone formatting | Shared utility, reusable across venues/contacts forms. Encapsulates complex TextInputFormatter logic cleanly. |
| `lib/features/contacts/widgets/invite_members_screen.dart` | Standalone screen for member invitations | Decouples member management from band editing. Follows feature input requirement to move invites to Members section. Reduces BandFormScreen complexity. |

---

## Files to Modify

| File | Changes | Lines |
|------|---------|-------|
| `lib/features/contacts/widgets/venues_empty_state.dart` | Remove leading `+` from button label | Line 62: `'+ Add Venue'` → `'Add Venue'` |
| `lib/features/contacts/widgets/contacts_empty_state.dart` | Remove leading `+` from button label | Line 62: `'+ Add Contact'` → `'Add Contact'` |
| `lib/features/contacts/widgets/venue_form_screen.dart` | Add phone formatter, adapt address labels for timezone | Lines 339–343 (phone), 313–336 (address labels), add import and helper methods |
| `lib/features/contacts/widgets/venue_contact_block.dart` | Add phone formatter parameter, apply in phone field | Add timezone parameter, line 181–187 (phone), update constructor |
| `lib/features/contacts/widgets/contact_form_screen.dart` | Add phone formatter for non-US bands | Lines 202–208 (phone), add import and helper method |
| `lib/features/bands/band_form_screen.dart` | Remove invite section (edit mode), update timezone picker | Delete lines 1835–1858, 190, 1058–1103, 1105–1245, 1247–1321, 2404–2481, 2483–2494, 2660–2721; update 2188–2200, 2202–2285, dispose() |
| `lib/features/contacts/contacts_tab_content.dart` | Update `_openInviteScreen()` to navigate to InviteMembersScreen | Lines 102–114, add import |

---

## Files Off-Limits

- `lib/features/members/` — No changes to member-related logic; InviteMembersScreen is a Contacts feature.
- `lib/app/models/band.dart` — Band model remains unchanged.
- `lib/features/bands/band_repository.dart` — No RPC or data-layer changes.
- Database schema and migrations — No changes.

---

## System Impact Map

| System | Affected? | Notes |
|--------|-----------|-------|
| Gigs | No | No gig-related logic involved. |
| Rehearsals | No | No rehearsal-related logic involved. |
| Setlists / Catalog | No | No setlist-related logic involved. |
| Members / RBAC | Yes (minor) | Member invitations move from BandFormScreen to InviteMembersScreen, but RPC and permissions remain identical. Band admin check in RLS is unchanged. |
| Auth / Session | No | No auth flow changes. |
| Routing | Yes (minor) | New InviteMembersScreen adds a navigation route; ContactsTabContent._openInviteScreen() navigates to it instead of BandFormScreen. |
| Notifications | No | Invite email flow (send-band-invite edge function) unchanged. |
| Platform | Yes | Phone formatting behavior changes for web/iOS/Android based on timezone. Address field labels adapt per timezone. UX improvements across all platforms. |

---

## Regression Risk

**MEDIUM**

**Rationale:**
- **Issue 1 (button label):** Very low risk. Removing a `+` from text is trivial. Only visual regression possible: if anyone relied on the double-plus appearance (unlikely), they'll see a single icon + label instead. No functional impact.
- **Issue 2 (phone formatter):** Medium risk. TextInputFormatter is complex; incorrect cursor handling could break input. Testing on mobile numeric keypad and desktop is essential. Pasting behavior must be validated. Formatter only applies to US timezones, so non-US users unaffected.
- **Issue 3 (address fields):** Low risk. Conditional label changes are straightforward. ContactFormScreen unchanged. Only VenueFormScreen labels adapt; no field removal or restructuring. Existing data unaffected.
- **Issue 4 (move invites):** Medium risk. Extracting and moving stateful logic (invite methods, controllers, state flags) introduces opportunity for bugs if dependencies are incomplete. The new InviteMembersScreen must preserve all Supabase calls, error handling, and UI consistency. RPC and permissions unchanged. QA must verify invite send/cancel workflow end-to-end.
- **Issue 5 (timezone picker):** Low risk. Replacing a flat dropdown with a grouped one is UI-only. All existing timezone values are preserved in the new list. Fallback logic unchanged.

**Mitigation:**
- Phone formatter: Test with (1) manual typing, (2) paste, (3) backspace, (4) mobile keyboards, (5) focus/blur.
- Invite move: Run through full invite workflow (send, cancel, pending display) in ContactsTab before QA approval.
- Manual visual regression test on all three address form variants (US, Canada, UK).

---

## Engineer Task Breakdown

### Task 0: Fix Double Plus Sign
- Remove `+` from `venues_empty_state.dart` line 62.
- Remove `+` from `contacts_empty_state.dart` line 62.
- **Verification:** Visual check that buttons show icon + label, not double plus.

### Task 1: Create Phone Input Formatter Utility
- Create `lib/shared/utils/phone_input_formatter.dart`.
- Implement `USPhoneInputFormatter extends TextInputFormatter`.
- Logic: Detect US timezone, format as (123) 456-7890 or pass through.
- Handle backspace, delete, paste, and cursor positioning.
- Write inline documentation with examples.
- **Verification:** Unit tests or manual testing with sample inputs (pasting "1234567890", backspacing, mixing valid/invalid chars).

### Task 2: Apply Phone Formatter to VenueFormScreen
- Import `activeBandProvider` and `USPhoneInputFormatter`.
- Add `_getPhoneFormatters()` helper method that reads timezone and returns formatter list.
- Update phone TextField (line 339–343) to use `inputFormatters: _getPhoneFormatters()`.
- **Verification:** Test US timezone shows formatting; non-US timezone shows plain text.

### Task 3: Adapt VenueFormScreen Address Labels for Timezone
- Add timezone detection helper method to read band.timezone.
- Replace hardcoded "State" label with dynamic label based on timezone:
  - US → "State"
  - Canada → "Province"
  - UK → "County"
  - Other → hide state field entirely or show "Region" (per judgment).
- Update TextField decoration to use dynamic label.
- **Verification:** Test US band shows "State"; Canada band shows "Province"; UK band shows "County"; other timezones show appropriate variant.

### Task 4: Update VenueContactBlock to Accept Timezone Parameter
- Add `timezone` as a constructor parameter to VenueContactBlock.
- Update initState and build to use timezone.
- Add `_getPhoneFormatters(timezone)` helper that applies formatter if US.
- Update phone TextField (line 181–187) to use `inputFormatters: _getPhoneFormatters(timezone)`.
- Update all call sites in VenueFormScreen to pass timezone when creating VenueContactBlock instances.
- **Verification:** Phone formatting in contact blocks matches venue-level behavior.

### Task 5: Apply Phone Formatter to ContactFormScreen
- Import `activeBandProvider` and `USPhoneInputFormatter`.
- Add `_getPhoneFormatters()` helper method.
- Update phone TextField (line 202–208) to use `inputFormatters: _getPhoneFormatters()`.
- **Verification:** US band shows formatting; non-US band shows plain text.

### Task 6: Decide on ContactFormScreen Address Fields
- Review feature input and existing Contact model.
- **Decision:** Keep ContactFormScreen as-is (no address fields). Standalone contacts are lighter-weight; venues already have full address. Document this in code comment.
- Add a comment above the TextField list explaining why address fields are not included.
- **Verification:** No functional change; documentation added.

### Task 7: Create InviteMembersScreen
- Create new file `lib/features/contacts/widgets/invite_members_screen.dart`.
- Copy invite-related UI and methods from BandFormScreen edit mode:
  - `_inviteEmailController`, `_pendingInvites`, `_isSendingInvite` state.
  - `_loadPendingInvites()`, `_sendInvite()`, `_cancelInvite()` methods.
  - `_buildInviteEmailInput()`, `_buildPendingInvitesList()` widgets.
  - `_InvitePill` widget class.
- Make it a ConsumerStatefulWidget taking band as constructor parameter.
- Add AppBar with "Invite Members" title and close button.
- Call `_loadPendingInvites()` in initState.
- Dispose controller properly.
- **Verification:** Screen opens, shows pending invites, allows sending new invites, handles cancel/error states.

### Task 8: Remove Invite Logic from BandFormScreen
- Delete edit-mode invite section (lines 1835–1858).
- Delete methods: `_loadPendingInvites()`, `_sendInvite()`, `_cancelInvite()`, `_buildInviteEmailInput()`, `_buildPendingInvitesList()`.
- Delete state variables: `_inviteEmailController`, `_pendingInvites`, `_isSendingInvite`.
- Delete widget class: `_InvitePill`.
- Remove `_inviteEmailController.dispose()` call.
- Remove `_loadPendingInvites()` call from initState (line 190).
- Verify no remaining references to these deleted identifiers.
- **Verification:** BandFormScreen compiles without errors; edit mode no longer shows invite section.

### Task 9: Update Timezone Picker List and Label
- Replace `_timezoneOptions` (lines 2188–2200) with new grouped list including Canadian timezones.
- Update label from 'Timezone' to 'Timezone Location'.
- Update helper text from 'Used for calendar subscription feeds' to 'Used for general formatting and calendar feeds'.
- Ensure dropdown builder handles new list structure correctly (group headers disabled, values valid).
- **Verification:** Dropdown displays all timezones grouped; selecting a timezone saves correctly; fallback to 'America/Chicago' works for bands with old timezone values.

### Task 10: Update ContactsTabContent._openInviteScreen()
- Import `InviteMembersScreen`.
- Replace navigation to BandFormScreen(mode: edit) with navigation to InviteMembersScreen(band: activeBand).
- Remove BandFormScreen import if no longer used elsewhere (check first).
- **Verification:** Tapping "Invite" in Members section opens InviteMembersScreen instead of BandFormScreen.

### Task 11: Full Integration Testing
- Test all 5 issues end-to-end:
  1. Empty-state buttons show no double plus.
  2. US band phone fields auto-format; non-US don't.
  3. Venue form labels adapt by timezone.
  4. Inviting members opens standalone screen, not BandFormScreen.
  5. Timezone picker shows grouped options and new timezones.
- Test backward compatibility: existing invites load correctly in new screen, existing bands with old timezones fall back gracefully.
- Test on web and mobile.
- **Verification:** QA sign-off on all scenarios.

---

## Verification Plan

### Manual Verification (No SQL tiers needed; no DB changes)

1. **Issue 1 — Double Plus Sign:**
   - Open Venues view, trigger empty state.
   - Observe "Add Venue" button: should show [icon] Add Venue, not [icon] + Add Venue.
   - Repeat for Contacts → "Add Contact".

2. **Issue 2 — Phone Formatter:**
   - Create a US-timezone band (e.g., America/Chicago).
   - Open VenueFormScreen or ContactFormScreen.
   - Type phone number: 1234567890.
   - Observe formatting: (123) 456-7890 (formatted) or 1234567890 (plain, depending on locale).
   - Create a non-US band (e.g., Europe/London).
   - Repeat: no formatting should occur.
   - Test backspace, paste, and mobile numeric keypad.

3. **Issue 3 — Address Labels:**
   - Create US-timezone band.
   - Open VenueFormScreen; confirm "State" label.
   - Create Canada-timezone band (e.g., America/Toronto).
   - Open VenueFormScreen; confirm "Province" label.
   - Create UK-timezone band (e.g., Europe/London).
   - Open VenueFormScreen; confirm "County" label.
   - Existing venues should display/edit correctly.

4. **Issue 4 — Member Invitations:**
   - In Contacts tab, Members section, tap "Invite Members" button.
   - New InviteMembersScreen should open (not BandFormScreen).
   - Send an invite to a valid email.
   - Observe pending invites list.
   - Cancel an invite; verify it's removed.
   - Navigate back; invites persist (reload to confirm).

5. **Issue 5 — Timezone Picker:**
   - Edit band settings.
   - Open Timezone dropdown.
   - Observe grouped structure: Canada, United States, United Kingdom.
   - Select a new timezone (e.g., America/Vancouver).
   - Save band; confirm timezone is updated.
   - Edit a band with an old timezone (e.g., Europe/Paris).
   - Confirm it falls back to 'America/Chicago' in the dropdown (or is preserved in DB but not shown as selected).

---

## QA Regression Areas

1. **Phone Input Across Platforms:**
   - Test numeric keypad on iOS and Android.
   - Test desktop keyboard (Backspace, Delete, Ctrl+A).
   - Test pasting from clipboard (various formats: "1234567890", "(123)456-7890", "123-456-7890").
   - Verify cursor doesn't jump unexpectedly.
   - Test with very long paste (should normalize).

2. **Address Field Rendering:**
   - Confirm no layout shifts when state/province field width changes.
   - Test all three address variants (US, Canada, UK) on mobile and desktop.
   - Verify edit mode correctly loads and saves existing data.
   - Confirm non-US timezones don't show state field at all.

3. **Member Invitation Workflow:**
   - Send invite → observe pending list → receive email (check test inbox if available).
   - Cancel invite → verify removed from pending list and DB.
   - Re-invite same email after cancel → should succeed.
   - Invite existing band member → should show error.
   - Invite yourself → should show error.
   - Band admin only → non-admin cannot send invite.

4. **Timezone Dropdown:**
   - All 19 timezones selectable and saveable.
   - Grouped layout doesn't break on narrow screens.
   - Fallback for old timezone values (test with a DB record having Europe/Paris).
   - Timezone correctly used by phone formatter and address labels on the same form.

5. **Empty-State UI:**
   - Buttons render with single `+` icon, no double plus.
   - Button colors, spacing, and affordance unchanged.

---

## Out of Scope

- Internationalization (i18n) of the entire app. This feature addresses specific timezone-aware labels only.
- Phone number validation beyond basic format checking. Formatter accepts any digit sequence.
- Address autocomplete or postal code validation.
- Member RBAC or permissions changes. Invite logic is identical; only the UI location changes.
- Creation of new edge functions or changes to send-band-invite function.
- Changes to band_invitations table schema.
- Analytics tracking for new InviteMembersScreen.
- Dark mode or theme-specific styling (assumes existing design tokens apply).

---

## Implementation Notes

### Phone Formatter Implementation
The USPhoneInputFormatter must:
1. Check if `_isUSTimezone(timezone)` is true.
2. If false, return the TextEditingValue unchanged.
3. If true, extract only digits from the input.
4. If <= 3 digits: return as-is.
5. If 4–6 digits: format as (123) and append the rest.
6. If 7+ digits: format as (123) 456-7890, truncate to 10 digits.
7. Preserve cursor position relative to the last digit entered (not the last character).

### InviteMembersScreen Structure
```
InviteMembersScreen(band: Band)
  → AppBar (close button, "Invite Members" title)
  → ScrollView (body)
    → Padding
      → Column
        → SectionLabel ("Invite Members")
        → HelperText
        → _buildInviteEmailInput() [email field + Invite button]
        → Conditional: if (_pendingInvites.isNotEmpty)
          → SectionLabel ("Invited")
          → _buildPendingInvitesList() [_InvitePill widgets]
        → Padding (bottom safe area)
```

### Timezone Detection Helper
```dart
static const List<String> _usTimezones = [
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Anchorage',
  'Pacific/Honolulu',
];

bool _isUSTimezone(String timezone) {
  return _usTimezones.contains(timezone);
}

bool _isCanadianTimezone(String timezone) {
  return ['America/Vancouver', 'America/Edmonton', 'America/Regina', 
          'America/Toronto', 'America/Halifax', 'America/St_Johns']
    .contains(timezone);
}

bool _isUKTimezone(String timezone) {
  return timezone == 'Europe/London';
}
```

---

## Key Decisions & Rationale

1. **Issue 1:** Removing the leading `+` from labels is cleaner than modifying BrandActionButton. Labels should be text-only; the button component controls the icon.

2. **Issue 2:** Creating a dedicated TextInputFormatter is reusable and testable. Timezone awareness is cleanly separated from the formatter logic.

3. **Issue 3:** Adapting labels based on timezone (not adding new fields) keeps the schema simple and the form focused on venue-specific data.

4. **Issue 4:** Extracting InviteMembersScreen decouples concerns: band settings (name, avatar, timezone) stay in BandFormScreen; member management stays in Contacts. This aligns with feature input and improves maintainability.

5. **Issue 5:** Grouping timezones by region and adding Canadian options addresses real-world user needs without schema changes.

6. **ContactFormScreen Decision:** Standalone contacts remain lightweight (no address) to distinguish them from venues. If future features require contact addresses, a separate task can add them.

---

**Plan Author:** Architect Agent  
**Date:** 2026-04-10  
**Status:** Ready for Engineer Phase
