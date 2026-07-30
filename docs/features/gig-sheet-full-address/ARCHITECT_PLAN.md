# ARCHITECT_PLAN.md

## 1. Feature Slug
`bug/gig-sheet-full-address`

---

## 2. Problem Summary
From the dashboard, tapping an upcoming gig opens `ViewGigDrawer`, a bottom sheet showing gig details. Its location row renders only the raw `gig.location` string (which functions as the "city" field). It never displays the gig's street address (`gig.address`) or state (`gig.state`), even when those fields were entered at creation/edit time. Users cannot see the complete venue location without leaving the dashboard and opening the edit form.

This is a display-completeness bug confined to a single widget, not a data-availability or data-integrity bug: the data (`address`, `state`) already exists on the `Gig` object when the sheet renders — the widget simply never reads two of the three fields it has.

---

## 3. Root Cause
**Confidence: HIGH — confirmed in code.**

`lib/features/gigs/widgets/view_gig_drawer.dart:303` renders:
```dart
Text(
  gig.location,
  style: AppTextStyles.callout.copyWith(color: context.colors.textMuted),
),
```
This is the entire location display in the sheet. It:
- Shows only `gig.location` (city/freeform text).
- Never reads `gig.state` for display anywhere in this file.
- Reads `gig.address` only inside `_openNavigation()` (line 55–58) to build an external Maps query string — never rendered as visible text.
- Does not even use the model's own `Gig.locationDisplay` getter (`lib/app/models/gig.dart:195-199`), which the dashboard's own gig cards (`ConfirmedGigCard`, `PotentialGigCard`) already use to append state to location. The bottom sheet is therefore less complete than the cards that open it.
- Even `locationDisplay` itself is insufficient for this bug: it combines `location` + `state` but omits `address` entirely, so no existing getter on `Gig` can produce a full "street address / city, state" display today. A new getter is required.

**Secondary observation (not the root cause of this bug, noted for scope clarity):** `GigRepository._gigSelectClause` (`lib/features/gigs/gig_repository.dart:32-42`) does not join the `venues` table — a gig only carries `venueId` as a plain FK. Venue address data is copied onto the gig's own `location`/`address`/`state` columns only transiently, inside the gig editor's venue-name autocomplete (`lib/features/events/widgets/event_editor_drawer.dart:724-782`), and only when those gig fields are currently blank. This means a minority of gigs (created before this autofill existed, or whose linked venue's address changed after linking) could have `venue_id` set but blank `address`/`state` on the gig row itself, with no live fallback to the `venues` table at read time. This is a distinct data-population gap, separate from the display bug reported here — see **Out of Scope**.

---

## 4. Reference Docs Consulted
`ARCHITECT.md` Phase 4 as written is hardcoded to `docs/reference/notifications/` (left over from the template's embedded notifications-bug example). That directory is not relevant to this feature. Applying the phase's intent — load the domain reference before reading code — I instead consulted the domain-relevant reference docs that exist for this codebase:
- `docs/reference/architecture/database_schema.md` — confirmed `gigs` table columns (`location`, `venue_id`, and the migration-added `address`/`state`) and `venues` table columns (`address`, `city`, `state`).
- `docs/reference/architecture/architecture.md` — grepped for gig/venue architecture notes; no additional location-handling detail beyond the schema doc.

No `docs/reference/gigs/` or `docs/reference/venues/` directory exists. This discrepancy (Phase 4 pointing at a domain that doesn't apply) is flagged per Phase 3 guidance to document conflicts between the input template and codebase reality.

---

## 5. Existing System Analysis
**Data flow, dashboard → sheet:**
1. `home_screen.dart` → `_buildHorizontalGigsList` renders gig cards; `onTap` (line 944) calls `_openViewGigSheet(confirmedGigs[index])` (lines 246–266).
2. `_openViewGigSheet` calls `ViewGigDrawer.show(...)`, a `showModalBottomSheet` (`view_gig_drawer.dart:32-52`).
3. The `Gig` passed in was fetched via `GigRepository.fetchGigsForBand` using `_gigSelectClause` (`gig_repository.dart:32-42`), which selects `*` from `gigs` plus a `gig_dates` join — so `location`, `address`, `state`, and `venue_id` are all already present on the `Gig` object (`Gig.fromJson`, `lib/app/models/gig.dart:86-109`) by the time it reaches the sheet.
4. The sheet's header block (`view_gig_drawer.dart:278-329`) renders `gig.name`, then a `Row` with the location `Text` (line 298-308) and a Navigate `IconButton`. Only `gig.location` is shown; `gig.address` and `gig.state` are in memory but unused for display.

**Existing correct pattern elsewhere:** `lib/features/contacts/widgets/venue_detail_screen.dart:454-475`, `_formatAddress()`, builds a two-line address string from a `Venue`, including each piece (street address; city, state) only if non-empty, joined with `\n`, avoiding stray commas or blank lines for missing fields. This is the pattern to adapt for `Gig`.

**Existing partial pattern on `Gig` itself:** `Gig.locationDisplay` (`gig.dart:195-199`) already does the "only append if present" trimming for `state`, appended to `location`. It's reused as-is; only `address` needs to be prepended as an optional first line.

---

## 6. Proposed Solution
Add a new getter to the `Gig` model that composes a full location display (street address line, if entered, followed by the existing `location, STATE` line), and switch the bottom sheet's location `Text` to use it instead of the raw `gig.location` field.

- **New getter `Gig.fullLocationDisplay`** (`lib/app/models/gig.dart`, placed immediately after `locationDisplay`): returns `address` (trimmed, if non-empty) joined by `\n` with the existing `locationDisplay` output (which already omits `state` when blank). Fields left blank at entry are simply omitted — no empty lines, no stray separators — matching the `venue_detail_screen.dart` pattern.
- **`ViewGigDrawer` change** (`lib/features/gigs/widgets/view_gig_drawer.dart:303`): replace `gig.location` with `gig.fullLocationDisplay`. No other change to the widget — the `Text` widget has no `maxLines`/`overflow` constraint today, so a `\n`-joined multi-line string wraps naturally inside the existing `Expanded` layout.

**What must not change:**
- `Gig.locationDisplay` — used as-is by `ConfirmedGigCard` and `PotentialGigCard` for their intentionally compact, single-line card display. Do not alter its signature or behavior.
- `GigRepository._gigSelectClause` — no venue join is required to fix this bug; the fields needed are already present on `gigs` rows and already fetched.
- `_openNavigation()` in `view_gig_drawer.dart` — its existing address-aware query logic (line 55-58) already does the right thing and is unrelated to the display bug.
- Any other `gig.location` call sites (`calendar_event.dart:93`, `event_form_data.dart:578`, `availability_prompt_modal.dart:231-235`) — none of these are the dashboard bottom sheet named in this bug report; out of scope.

No new abstractions, no new files beyond a test file (below), no dependency changes.

---

## 7. Database Impact
**Database: not applicable.** `address` and `state` columns already exist on `public.gigs` (migrations `20260701000000_add_address_to_gigs.sql`, `20260715000000_add_state_to_gigs.sql`). No schema, RLS, RPC, or trigger changes are required — this is a pure Flutter client display fix reading data that is already fetched.

---

## 8. Flutter Architecture Changes
- **Model:** `Gig` (`lib/app/models/gig.dart`) gains one new computed getter. No constructor, field, `fromJson`, or `toJson` changes.
- **Widget:** `ViewGigDrawer` (`lib/features/gigs/widgets/view_gig_drawer.dart`) — one-line change to which getter is passed into the existing `Text` widget. No new widgets, no state, no controllers, no lifecycle changes (this is a `StatelessWidget`).
- **Repository/provider:** unchanged.

---

## 9. Files to Create
| File | Justification |
|------|----------------|
| `test/app/models/gig_test.dart` | No existing test file covers the `Gig` model. Follows the established plain `flutter_test` pattern used by `test/app/models/rehearsal_test.dart` (no widget/mocking dependencies). Required to cover the new `fullLocationDisplay` getter's branching logic (address present/absent, state present/absent, all-present, all-blank). |

---

## 10. Files to Modify
| File | What changes |
|------|-------------|
| `lib/app/models/gig.dart` | Add `fullLocationDisplay` getter directly below the existing `locationDisplay` getter (~line 199). Composes `address` (if non-empty, trimmed) as an optional first line, joined with `\n` to the existing `locationDisplay` output. No other lines in the file change. |
| `lib/features/gigs/widgets/view_gig_drawer.dart` | Line 303: change `gig.location` to `gig.fullLocationDisplay` inside the existing `Text` widget in the header's location `Row`. No structural, layout, or style changes to the surrounding `Row`/`Expanded`/`IconButton`. |

---

## 11. Files Off-Limits
| File | Reason |
|------|--------|
| `lib/features/home/widgets/confirmed_gig_card.dart` | Uses `locationDisplay` intentionally for a compact single-line card; not part of this bug, must not change. |
| `lib/features/home/widgets/potential_gig_card.dart` | Same as above. |
| `lib/features/gigs/gig_repository.dart` | No venue join needed; the fields required for this fix are already selected via `*`. Adding a venue join is a larger, separate change (see Out of Scope). |
| `lib/features/events/widgets/event_editor_drawer.dart` | Venue autofill logic is unrelated to how the dashboard sheet displays already-fetched gig data. |
| `lib/features/contacts/widgets/venue_detail_screen.dart` | Reference pattern only (`_formatAddress()`); not to be modified — it belongs to the Venue feature, not Gigs. |
| `lib/features/contacts/models/venue.dart` | Unrelated model; `Gig` does not hold a nested `Venue` object and this fix does not require one. |
| `lib/features/gigs/widgets/availability_prompt_modal.dart` | A different modal (potential-gig RSVP), not the dashboard "view gig" bottom sheet named in this bug. |
| `lib/features/calendar/models/calendar_event.dart`, `lib/features/events/models/event_form_data.dart` | Other `gig.location` call sites unrelated to the dashboard bottom sheet; out of scope. |
| Any `supabase/migrations/*` file | No schema change required. |
| `lib/main.dart` | Init order must not change (guardrail). |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed
**New files:** `test/app/models/gig_test.dart` (justified above)

---

## 12. System Impact Map
| System | Impact |
|--------|--------|
| Gigs | affected — `Gig` model gains a getter; `ViewGigDrawer` display logic changes |
| Rehearsals | unaffected |
| Setlists / Catalog | unaffected |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | affected — shared Flutter widget, all platforms receive the same fix uniformly; no platform-specific code paths involved |

---

## 13. Regression Risk
**LOW.**
- Only one system (Gigs) is affected, confined to one model getter (additive — no existing getter modified or removed) and one `Text` widget's data source.
- `locationDisplay`, used elsewhere, is untouched and unaffected — verified by grep that its only two call sites (`confirmed_gig_card.dart`, `potential_gig_card.dart`) are not part of this change.
- No auth, session, routing, or init-order code is touched.
- No database mutation or migration involved.
- No `StatefulWidget`, controller, or async lifecycle code is touched — `ViewGigDrawer` is stateless and the change is a pure data-source swap on an existing `Text`.
- No other notification/feature type shares this code path.

---

## 14. Engineer Task Breakdown
1. In `lib/app/models/gig.dart`, add the `fullLocationDisplay` getter immediately after `locationDisplay` (after line 199):
   ```dart
   /// Full location for display: street address (if entered) on its own
   /// line, followed by location display (city, and state if entered).
   /// Omits any line whose fields were left blank — no empty text.
   String get fullLocationDisplay {
     final lines = <String>[];
     final trimmedAddress = address?.trim();
     if (trimmedAddress != null && trimmedAddress.isNotEmpty) {
       lines.add(trimmedAddress);
     }
     lines.add(locationDisplay);
     return lines.join('\n');
   }
   ```
2. In `lib/features/gigs/widgets/view_gig_drawer.dart`, line 303, change `gig.location` to `gig.fullLocationDisplay`.
3. Create `test/app/models/gig_test.dart` with unit tests for `fullLocationDisplay` covering:
   - address + location + state all present → two lines, `"123 Main St\nMinneapolis, MN"`
   - address blank/null, location + state present → one line, `"Minneapolis, MN"`
   - address + location present, state blank/null → one line, `"123 Main St\nMinneapolis"`
   - address blank/null, state blank/null, only location present → one line, `"Minneapolis"`
   - address is whitespace-only string → treated as blank (not shown)
4. Do not modify any file not listed in section 10.

Tasks 1–3 are sequential (task 2 depends on task 1 existing; task 3 tests task 1's output) — no parallelization applicable.

---

## 15. Verification Plan

This change has **no database or migration component** (see Section 7), so the SQL pre/post-deploy tier structure in the Architect template does not apply as written. Adapted to a Flutter-only change:

**Tier 1 — Pre-implementation-complete (must pass before Engineer reports done):**
- PRE-DEPLOY TEST 1: `flutter analyze` passes with 0 errors on the two modified files and the new test file.
- PRE-DEPLOY TEST 2: `flutter test test/app/models/gig_test.dart` passes — all `fullLocationDisplay` branch cases from Task 3 above.
- PRE-DEPLOY TEST 3: Manual code read confirms `gig.dart`'s `locationDisplay` getter body is byte-identical to before the change (only a new getter was added below it).

**Tier 2 — Post-implementation (manual/QA verification, run after Engineer's diff is applied):**
- POST-DEPLOY TEST 1: Open the dashboard, tap an upcoming confirmed gig whose venue has address + city + state entered → bottom sheet shows both lines correctly formatted, no stray commas.
- POST-DEPLOY TEST 2: Tap a gig with only city (location) entered, no address/state → bottom sheet shows a single line, no blank line above/below, no placeholder text.
- POST-DEPLOY TEST 3: Tap a gig with city + state but no address → bottom sheet shows one line: `"City, ST"`.
- POST-DEPLOY TEST 4: Confirm the Navigate button still opens the correct external maps query (unchanged `_openNavigation` logic) for a gig with and without an address.
- POST-DEPLOY TEST 5: Confirm `ConfirmedGigCard` and `PotentialGigCard` on the dashboard are visually unchanged (still single-line, still using `locationDisplay`, no address line added there).
- POST-DEPLOY TEST 6: Repeat POST-DEPLOY TEST 1 on iOS, Android, Web, and macOS builds (shared widget — confirm no platform-specific rendering divergence).

---

## 16. QA Regression Areas
- Gig detail bottom sheet (`ViewGigDrawer`) location display — primary fix area.
- Dashboard gig cards (`ConfirmedGigCard`, `PotentialGigCard`) — confirm `locationDisplay` behavior and single-line layout are unchanged.
- Navigate button in the bottom sheet — confirm maps deep-link behavior is unchanged (it already reads `gig.address` independently; not modified by this fix).
- Gig editor / event editor — confirm no changes leaked into `event_editor_drawer.dart` (off-limits).
- Cross-platform check: iOS, Android, Web, macOS — this is a shared widget with no platform branching, but visually confirm on at least two platforms given "Affected Platforms: all."
- Potential gigs and confirmed gigs both — confirm the sheet fix applies to both `is_potential` states (the sheet code path does not branch on this field for location).

---

## 17. Rollout / Migration Strategy
Not applicable — no database change, no feature flag, no phased rollout. Ships as a normal client release once QA approves.

---

## 18. Out of Scope
- **Venue-to-gig address sync:** ensuring `gig.address`/`gig.state` are populated from the linked `venues` row (via `venue_id`) when those gig-row fields are blank — e.g., legacy gigs created before the address/state columns existed, or gigs whose linked venue's address was edited after linking. This is a data-population/backfill concern distinct from the display bug reported here, and would require either a `venues` join in `GigRepository` or a live venue lookup — a larger change requiring separate Architect review.
- Adding a `city` field distinct from `location` — the codebase's existing convention (per migration comment in `20260715000000_add_state_to_gigs.sql`) treats `location` as the city field; not changing that convention here.
- Any change to `GigRepository._gigSelectClause` or venue joins.
- Any change to the gig editor's venue autofill behavior.
- Any change to other `gig.location` call sites outside the dashboard bottom sheet (calendar export, event form seeding, availability prompt modal).
