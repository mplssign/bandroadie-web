# ARCHITECT PLAN

**Feature Slug:** `feature/section-titles-title-case`
**Feature Title:** Event editor section card titles should use Title Case
**Branch:** `feature/section-titles-title-case`
**Date:** 2026-09-03

---

## 1. Motivation

The Add/Edit Event drawer groups its form into named section cards. Two titles are sentence case instead of Title Case, inconsistent with the rest:
- `The gig` → `The Gig`
- `Show prep` → `Show Prep`

The remaining section titles (`Schedule`, `Location`, `Money`, `Notes`) are already Title Case. Home-screen `SectionHeader` titles (`Upcoming Rehearsals`, `Upcoming Gigs`, `Quick Actions`) are already Title Case — no changes needed there.

Confidence: HIGH (confirmed in code).

## 2. Solution

Change the two `_SectionCard(title: ...)` string literals in `event_editor_drawer.dart`:
- Line ~2903: `title: 'The gig'` → `title: 'The Gig'`
- Line ~2916: `title: 'Show prep'` → `title: 'Show Prep'`

No other titles change. Text-only; no logic, layout, state, DB, or RPC impact.

## 3. Files to Modify

| File | Change |
|---|---|
| `lib/features/events/widgets/event_editor_drawer.dart` | Retitle the two sentence-case `_SectionCard` titles to Title Case. |

**Off-limits:** everything else. Do not touch home `SectionHeader` titles (already Title Case), the `Update Venue` dialog title (already Title Case), form-field sub-labels, or any other file.

## 4. DB/RLS/RPC Impact
None.

## 5. Verification Plan

- `flutter analyze --no-pub` → 0 errors.
- Confirm via grep that `_SectionCard` titles are now `The Gig`, `Schedule`, `Location`, `Show Prep`, `Money`, `Notes` (all Title Case) and that no sentence-case section titles remain.

## 6. Task Breakdown

1. In `event_editor_drawer.dart`, change `title: 'The gig'` → `title: 'The Gig'`.
2. In `event_editor_drawer.dart`, change `title: 'Show prep'` → `title: 'Show Prep'`.
3. Run `flutter analyze --no-pub`; confirm 0 errors.
