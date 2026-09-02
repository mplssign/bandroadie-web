# ARCHITECT_PLAN.md

**Feature Slug:** `gig-contact-entry-and-form-crash`

**Feature Title:** Edit Contact screen crashes on Title field; gig contact entry button is not discoverable

---

## Problem Summary

Two UI bugs affect the contact-related editing flows across iOS, Android, macOS, and Web because both issues live in shared Flutter widget code.

Bug 1 is a debug-build crash on the Edit Contact screen. The Title section wraps `TitlePillSelector` in a `Padding` widget with `EdgeInsets.only(right: -Spacing.pagePadding)`, which violates Flutter's `padding.isNonNegative` assertion and crashes as soon as the widget tree builds that section.

Bug 2 is a discoverability failure in the gig create/edit form. When the Contacts section is empty, the header action still says `Add another`, which implies an existing contact row, and the placeholder body is passive text with no tap affordance. Users therefore miss the entry point for linking the first contact.

---

## Root Cause (+confidence)

**Confidence:** **HIGH**

### Bug 1

`lib/features/contacts/widgets/contact_form_screen.dart` uses negative right padding around `TitlePillSelector`. Flutter explicitly rejects negative `EdgeInsets` values in debug mode, so the crash is deterministic in debug builds.

The negative padding is unnecessary because `TitlePillSelector` already renders its pills inside a horizontal `SingleChildScrollView`, so it can scroll normally inside the existing page padding without forcing an overflow.

### Bug 2

`lib/features/events/widgets/gig_form_fields.dart` hardcodes the header action label as `Add another` regardless of whether any contact rows exist, and the empty-state container is display-only. The UI therefore presents no clear first-contact affordance even though `onAddContact` already exists and is the correct entry path.

---

## Existing System Analysis

`ContactFormScreen` is a standalone full-screen contact editor. Its body is a `ListView` with page padding applied at the screen level, and the Title section is a simple label plus `TitlePillSelector`. Removing the extra negative `Padding` wrapper does not change controller flow, save behavior, or layout ownership; it only stops an invalid layout assertion.

`TitlePillSelector` is already responsible for horizontal overflow handling through `SingleChildScrollView(scrollDirection: Axis.horizontal)`. That means the screen-level workaround is not part of the selector's contract and can be removed safely.

`GigFormFields._buildContactsSection` already owns all empty-state and add-row presentation for gig contacts. The method has the state it needs to render the correct affordance now: `contactAutocompleteControllers.isEmpty` tells it whether this is the first add, and `onAddContact` is already the existing callback used by the header button.

No repository, provider, notifier, route, database query, platform conditional, or app initialization path participates in either bug. These are localized widget-layer issues.

`GigContactRowsController.showCreateDialog()` in the same file also contains the same negative `Padding` pattern around `TitlePillSelector`. Because that dialog is the gig form's shipped "not in your contacts list" creation path and crashes identically in iOS debug, it is included in scope alongside `_buildContactsSection`.

---

## Proposed Solution

Apply the smallest possible UI-only fix in the two approved edit surfaces.

### 1. Remove invalid negative padding in ContactFormScreen

In `lib/features/contacts/widgets/contact_form_screen.dart`, remove the `Padding(
  padding: EdgeInsets.only(right: -Spacing.pagePadding),
  child: ...,
)` wrapper and render `TitlePillSelector` directly beneath the `Title` label.

This fixes the debug assertion at the root cause and preserves the intended scrolling behavior because the selector already handles horizontal overflow internally.

### 2. Make the first-contact affordance explicit in GigFormFields

In `lib/features/events/widgets/gig_form_fields.dart`, update `_buildContactsSection` and remove the duplicated negative-padding wrapper in `showCreateDialog()`:

- Change the header button label to `Add` when `contactAutocompleteControllers.isEmpty` is true.
- Keep `Add another` when one or more contact rows already exist.
- Wrap the empty-state box in a tappable widget that invokes the same `onAddContact` path used by the header button.
- Mirror the existing save-state guard so the empty-state tap target is disabled when the form is saving.
- Replace the passive empty-state copy with an affordance-signaling string such as `No contacts linked — tap to add one`.

This keeps the existing callback path, placement, and interaction model intact while making the first entry point obvious.

---

## Database Impact

Not applicable.

---

## Flutter Architecture Changes

No architecture changes.

- No new controllers, providers, repositories, models, routes, or shared abstractions.
- No init-order changes. `lib/main.dart` remains untouched.
- No platform-conditional behavior changes. The same shared widget fixes apply to iOS, Android, macOS, and Web, and Firebase/DeepLinkService behavior remains unchanged.

---

## Files to Create

None.

---

## Files to Modify

| File | Planned change |
| --- | --- |
| `lib/features/contacts/widgets/contact_form_screen.dart` | Remove the negative right-padding wrapper around `TitlePillSelector` in the Title section so the selector becomes the direct child under the label. Also apply the two adjacent `dart fix` style cleanups in the same file: add `const` to `USPhoneInputFormatter(isUSTimezone: true)` in `_getPhoneFormatters()` and simplify `onDomainSelected: (domain) => _applyDomainShortcut(domain)` to `onDomainSelected: _applyDomainShortcut`. |
| `lib/features/events/widgets/gig_form_fields.dart` | Update `_buildContactsSection`: conditionalize the header button label for empty vs non-empty state, wrap the empty-state container in a tappable widget that calls `onAddContact`, preserve save-state disabling, and update the empty-state copy to indicate tap-to-add behavior. Also remove the negative right-padding wrapper around `TitlePillSelector` in `GigContactRowsController.showCreateDialog()`. |

---

## Files Off-Limits

| File / Area | Why |
| --- | --- |
| All venue files | Explicitly excluded by Bug Input. |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Explicitly excluded by Bug Input. |
| `lib/features/events/events_repository.dart` | Explicitly excluded by Bug Input; no data-layer change is needed. |
| `lib/app/models/gig.dart` | Explicitly excluded by Bug Input; no model change is needed. |
| Any file other than `lib/features/contacts/widgets/contact_form_screen.dart` and `lib/features/events/widgets/gig_form_fields.dart` | Scope control. Both bugs are fully addressable in the two named widget files. |
| Any method in `lib/features/events/widgets/gig_form_fields.dart` other than `_buildContactsSection` and the negative-padding wrapper inside `showCreateDialog()` | Scope control. This handoff covers the gig contacts empty-state affordance and the duplicated negative-padding crash only; do not widen into other gig form helpers. |

---

## Change Budget

- `lib/features/contacts/widgets/contact_form_screen.dart`: expected net delta about -1 to -5 lines
- `lib/features/events/widgets/gig_form_fields.dart`: expected net delta about +3 to +11 lines
- Expected new files: 0
- Expected new public classes/methods: 0
- Expected new dependencies: 0

---

## System Impact Map

| System | Impact |
| --- | --- |
| Contacts | affected — Edit Contact Title section crash is fixed locally in the standalone contact form screen |
| Gigs | affected — empty contacts section becomes discoverable and tappable in gig create/edit form |
| Rehearsals | unaffected |
| Setlists | unaffected |
| Members | unaffected |
| Auth | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platforms | affected — shared Flutter widget code change applies equally to iOS, Android, macOS, and Web |

---

## Regression Risk

**Overall risk:** **LOW**

Both changes are localized presentation fixes in existing widgets with no data-flow, persistence, or navigation changes.

Bug 1 removes invalid layout code rather than replacing it with a new pattern. Bug 2 reuses the existing `onAddContact` callback path and only changes the label and empty-state tap affordance, so the blast radius is limited to the existing gig form helpers that already own this UI.

---

## Engineer Task Breakdown

1. In `lib/features/contacts/widgets/contact_form_screen.dart`, remove the negative `Padding` wrapper around the Title section's `TitlePillSelector` and leave the selector as the direct child below the `Title` label.
  Also apply the two adjacent `dart fix` style improvements in the same file: add `const` to the `USPhoneInputFormatter` constructor in `_getPhoneFormatters()`, and simplify `onDomainSelected: (domain) => _applyDomainShortcut(domain)` to `onDomainSelected: _applyDomainShortcut`.
2. In `lib/features/events/widgets/gig_form_fields.dart`, modify `_buildContactsSection` so the header button label is `Add` when no contact rows exist and `Add another` otherwise.
3. In `lib/features/events/widgets/gig_form_fields.dart`, still within `_buildContactsSection`, wrap the empty-state container in a tappable widget that invokes the existing `onAddContact` path while respecting the existing saving-disabled behavior.
4. In `lib/features/events/widgets/gig_form_fields.dart`, update the empty-state text to clearly signal the new affordance, for example `No contacts linked — tap to add one`.
5. In `lib/features/events/widgets/gig_form_fields.dart`, also remove the same negative right-padding `Padding` wrapper around `TitlePillSelector` in `showCreateDialog()`.

---

## Verification Plan

### Tier 1: Pre-deploy checks

1. Run a focused debug-mode UI smoke on the Edit Contact screen and confirm the Title section renders without triggering `padding.isNonNegative` when the screen opens.
2. Run a focused widget-level or manual UI check of the gig create/edit form with zero linked contacts and confirm the header action renders as `Add` before any interaction.
3. In the same empty-state scenario, verify the placeholder renders as an interactive affordance and is disabled only when the form is in the saving state.

### Tier 2: Post-deploy checks

1. On iOS, Android, macOS, and Web, open Edit Contact, scroll to the Title pills, and confirm the screen remains stable with no debug assertion.
2. On iOS, Android, macOS, and Web, open a gig create/edit form with zero contacts, tap the header `Add` action, and confirm a new contact row is added through the existing `onAddContact` flow.
3. On iOS, Android, macOS, and Web, with zero contacts, tap the empty-state box and confirm it triggers the same add-contact path as the header button.
4. After at least one contact row exists, confirm the header action reverts to `Add another` and existing row add/remove behavior is unchanged.

---

## QA Regression Areas

- Edit Contact screen layout in debug mode, specifically the Title section and horizontal pill scrolling
- Gig create form with zero contacts
- Gig edit form with zero contacts
- Gig create/edit form with one or more contacts already linked
- Save-disabled state in the gig form to ensure the new empty-state tap target does not remain active while saving
- Cross-platform parity across iOS, Android, macOS, and Web

---

## Rollout Strategy

Standard code review and normal app release flow. No migration, feature flag, staged rollout, or backend coordination is required.

---

## Out of Scope

- Any venue-related cleanup or contact-linking behavior outside `_buildContactsSection` and the duplicated negative-padding removal in `showCreateDialog()`
- Any repository, model, controller, provider, or navigation refactor