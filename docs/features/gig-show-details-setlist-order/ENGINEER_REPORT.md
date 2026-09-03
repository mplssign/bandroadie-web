# ENGINEER_REPORT.md

## Feature Slug
`gig-show-details-setlist-order`

## Feature Title
Rename "Show Prep" to "Show Details" and move Setlists above Contact in the Add Event (Gig) drawer

## Cycle Number
1

## Goal
Two mechanical presentation changes in the Add/Edit Event drawer for Gig events:
1. Rename the `_SectionCard` title literal from `'Show Prep'` to `'Show Details'`.
2. Swap the `Column` children inside `_buildShowPrepSection` so `buildSetlistSelector` appears above `buildContactsSection`, with the `SizedBox` spacer unchanged between them.

## Architect Tasks Completed
1. ✅ Changed `title: 'Show Prep'` → `title: 'Show Details'` on the `_SectionCard` in the Gig branch of `_buildEventBody` (line 2916).
2. ✅ Swapped `Column` children inside `_buildShowPrepSection` so `eventFormFields.buildSetlistSelector(context, ref)` is first and `gigFormFields!.buildContactsSection(context)` is third (lines 3097–3099).

## Files Created
None.

## Files Modified
- `lib/features/events/widgets/event_editor_drawer.dart` — 2 lines changed, 0 net line delta.

## Analyzer Results
```
Analyzing event_editor_drawer.dart...
No issues found! (ran in 3.5s)
```

## Test Results
No tests run (plan explicitly states no automated test is warranted for this two-line presentation swap, and no existing test covers this section's title or child ordering).

## Code Efficiency / Bloat Check
- No new helpers, extensions, utils, or private widget classes introduced.
- No new providers, models, parameters, or `copyWith` entries.
- No dead code, unused imports, or `debugPrint` in the diff.
- Net line delta is exactly 0 as the plan specified (two swapped lines, not added).
- `dart format` reported 0 changes (file was already formatted; the swap did not alter formatting).

**Helper/util search**: no search needed — no new code was written, only two existing lines were reordered and one string literal was changed.

## Verification (Tier 1 Static — all pass)
| Check | Expected | Result |
|---|---|---|
| `grep -RIn "'Show Prep'" lib/` | no matches | PASS |
| `grep -n "'Show Details'" event_editor_drawer.dart` | exactly 1 match, `_SectionCard` title line | PASS — line 2916 |
| `grep -n "buildSetlistSelector\|buildContactsSection" event_editor_drawer.dart` | `buildSetlistSelector` on lower line number | PASS — 3097 vs 3099 |
| `flutter analyze event_editor_drawer.dart` | no issues | PASS |

Tier 2 (runtime smoke) is for QA per the verification plan.

## Deviations From Plan
None. `_buildShowPrepSection` method name retained as specified. No files outside the plan were touched.

## Blockers Encountered
None.

## Ready For QA
**Yes.**
