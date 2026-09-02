# ARCHITECT_PLAN

## 1. Feature Slug
`bug/az-index-column-clipped-small-screens`

## 2. Problem Summary
On small-height screens, the right-edge A-Z index column letters are rendered at a fixed size that does not reliably fit the per-letter vertical slot. The result is visual crowding/clipping while tap-to-scroll behavior still works.

## 3. Root Cause
`AzIndexColumn` in `lib/features/contacts/widgets/az_index_column.dart` renders all 27 index entries (`A-Z` + `#`) with `fontSize: 18` and `fontWeight: w600`, while each entry's slot height is forced by `Expanded` inside a `Positioned` column bounded by `topOffset`/`bottomPadding` from parent views.

On short screens, available column height divided by 27 yields a slot height that is too close to (or below, once glyph metrics/padding are considered) the fixed rendered glyph height, causing clipping/crowding.

Confidence: `HIGH` (directly confirmed in code).

Codebase discrepancy vs. feature input: `BandMembersView` no longer uses this A-Z index widget. Current active call sites are `ContactsView` and `VenuesView` only.

## 4. Reference Docs Consulted
Read in full from `docs/reference/notifications/` (per required phase process):
- `docs/reference/notifications/NOTIFICATION_SYSTEM.md`
- `docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md`
- `docs/reference/notifications/notifications.md`

Note: these documents are notification-domain references and do not govern this contacts UI layout bug directly.

## 5. Existing System Analysis
Current UI flow:
1. `ContactsView` / `VenuesView` group list items by letter using `groupByLetter(...)`.
2. Each view computes index-column bounds (`topOffset`, `bottomPadding`) and renders `AzIndexColumn`.
3. `AzIndexColumn` draws a `Positioned` right-edge column with 27 `Expanded` slices.
4. Each slice centers a `Text(letter)` with fixed `fontSize: 18`.
5. Tap handler resolves nearest populated section (`resolveTargetLetter`) and scrolls (`flatIndexForSection` + `ScrollablePositionedList`).

Failure origin:
- Presentation layer (`AzIndexColumn`) sizing policy is static while available vertical space is dynamic.
- No responsive typography logic based on actual column height.

## 6. Proposed Solution
Implement adaptive index-letter typography in `AzIndexColumn` only.

Design:
- Compute available column height at render time (via local layout constraints in the index widget).
- Derive per-slot height: `slotHeight = availableHeight / 27`.
- Compute font size from slot height with a safe clamp (example policy for Engineer to implement):
  - `adaptiveFontSize = clamp(slotHeight * 0.75, min: 10, max: 18)`
- Keep existing tap behavior, grouping logic, ordering (`A-Z` + `#`), and visual enabled/disabled color semantics unchanged.

Why this is minimal/safe:
- Fix is localized to shared rendering component.
- No changes to data flow, scrolling logic, providers, repositories, or backend.
- Automatically benefits all active consumers of `AzIndexColumn`.

What must not change:
- Letter ordering and hit targets structure (`Expanded` entries).
- Scroll-to-section behavior and nearest-letter fallback.
- Search behavior and grouping helpers.

## 7. Database Impact
`Database: not applicable`.

- Migrations: unaffected
- RLS policies: unaffected
- RPC signatures/functions: unaffected
- DB triggers: unaffected

## 8. Flutter Architecture Changes
- State management: unaffected (no provider/controller changes)
- Repositories/services: unaffected
- Widget layer: `AzIndexColumn` render logic updated to be height-aware
- Consumer widgets (`ContactsView`, `VenuesView`): no behavioral changes expected

## 9. Files to Create
none

## 10. Files to Modify
| File | What changes |
|------|-------------|
| `lib/features/contacts/widgets/az_index_column.dart` | Replace fixed 18px letter size with constrained-height adaptive font sizing inside the index column layout. |

## 11. Files Off-Limits
| File | Reason |
|------|--------|
| `lib/main.dart` | App initialization order is guarded and unrelated. |
| `lib/features/contacts/widgets/contacts_view.dart` | Existing offset math is not the root cause; avoid widening diff surface unless Engineer proves necessity. |
| `lib/features/contacts/widgets/venues_view.dart` | Existing offset math is not the root cause; avoid widening diff surface unless Engineer proves necessity. |
| `lib/features/contacts/widgets/az_list_helpers.dart` | Grouping/index resolution logic is correct and unrelated to clipping. |
| `lib/features/contacts/widgets/band_members_view.dart` | Does not currently render `AzIndexColumn`. |
| `supabase/**` | No backend/database involvement. |

## 12. System Impact Map
| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected (UI rendering where contacts/venues index column is visible) |

## 13. Regression Risk
`LOW`

Rationale:
- Single-widget, presentation-only change.
- No data model, backend, navigation, auth, or initialization impact.
- Primary regression vector is readability/tap usability of index letters across screen sizes.

## 14. Engineer Task Breakdown
1. Update `AzIndexColumn` to calculate available index-column height at layout time.
2. Derive per-letter slot height from `availableHeight / 27`.
3. Replace fixed `fontSize: 18` with clamped adaptive size from slot height.
4. Keep all existing color/weight/tap behavior unchanged.
5. Validate no analyzer/test regressions.
6. Manually verify on at least one short-height simulator/device and one tall device.

## 15. Verification Plan
### Tier 1 — Pre-deployment (must pass before `supabase db push`)
No schema/function changes are part of this bugfix; all checks are client/UI validation.

- `-- PRE-DEPLOY TEST 1:` `flutter analyze` returns 0 errors.
- `-- PRE-DEPLOY TEST 2:` On small-height device profile (e.g., iPhone SE 375x667), open Contacts > Venues with populated A-Z sections and verify index letters are fully legible, non-overlapping, non-clipped.
- `-- PRE-DEPLOY TEST 3:` On same device/profile, tap multiple letters including sparse sections and `#`; confirm scroll still lands on nearest populated section.
- `-- PRE-DEPLOY TEST 4:` On taller profile (e.g., iPhone 14/15 class), verify letters are not unintentionally reduced and remain readable.
- `-- PRE-DEPLOY TEST 5:` Repeat checks in Contacts (people) tab to confirm shared-widget behavior is fixed there too.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)
No backend deploy is required for this feature; post-deploy focuses on production UI parity.

- `-- POST-DEPLOY TEST 1:` Production smoke on iOS short-height device: verify index column readability and no clipping in Venues and Contacts.
- `-- POST-DEPLOY TEST 2:` Production smoke on Android small-height form factor (if available): verify same rendering and tap-to-scroll behavior.
- `-- POST-DEPLOY TEST 3:` Verify no regressions in search mode transitions (index hidden when searching; reappears correctly when clearing search).
- `-- POST-DEPLOY TEST 4:` Production verification query for bad data writes: `not applicable` (UI-only change, no data writes introduced).

SQL test authoring rules:
- Not applicable for this feature (no SQL/database changes).

## 16. QA Regression Areas
- Primary: A-Z index readability on short-height screens in Venues.
- Shared component regression: same fix behavior in Contacts.
- Interaction: letter tap-to-scroll remains accurate and responsive.
- Visibility behavior: index still hidden during search and restored after search clear.
- Cross-platform spot check: Android small-height device/emulator for parity.
- Non-target screens: Band Members view remains unchanged (no A-Z index present).

## 17. Rollout / Migration Strategy
- No migration.
- No edge function deploy.
- Standard client release path only.
- Safe to ship as a small UI bugfix once QA confirms short-screen behavior.

## 18. Out of Scope
- Redesign of contacts/venues page layout offsets.
- Changes to list grouping/sorting logic.
- Adding/removing index entries beyond `A-Z` + `#`.
- Any notification, auth, backend, or Supabase changes.
