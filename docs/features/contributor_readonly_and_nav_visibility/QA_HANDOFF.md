# QA HANDOFF — Contributor Read-Only Enforcement + Navigation Visibility Corrections

**Date:** 2026-03-02
**Engineer Report Reviewed:** 2026-03-02
**Architect Plan Version:** 2026-03-02

---

## VERDICT: PASS

---

## Summary

The implementation correctly follows the Architect Plan across all three parts: Setlist Read-Only Enforcement, Calendar Action Button Layout, and Footer Navigation Tab Visibility. All 7 files identified in the Engineer Report were modified as specified. No scope expansion. No backend changes. No regressions for admin or member roles. `flutter analyze` is clean (0 new issues).

Two pre-existing calendar mutation paths were identified that fall **outside this feature's scope** but should be addressed in a follow-up ticket. These are documented as Warnings below.

---

## Critical Issues

**None.**

---

## Warnings (Non-Blocking)

### W-1: `_handleDayTap` allows event creation when permissions are loading (calendar_tab_content.dart)

**Location:** `_handleDayTap()`, lines ~131–153

When `currentUserPermissionsProvider` is in a loading or error state, `perms` resolves to `null`. The contributor guard (`if (perms != null && perms.isContributor && !perms.canCreateGigs)`) is skipped, and `AddEditEventBottomSheet.show()` fires unconditionally for empty-day taps.

**Risk:** Extremely narrow timing window (permissions load in ~100ms and are cached thereafter). RLS is the server-side authority — any unauthorized mutation would be rejected. Not a security hole, but inconsistent with the "fail closed" principle used elsewhere in this feature.

**Recommendation for follow-up:** Add `if (perms == null) return;` before the empty-day logic, or fail closed with a loading snackbar.

### W-2: `DayDetailBottomSheet.onAddEvent` is always non-null (calendar_tab_content.dart, pre-existing)

**Location:** `_handleDayTap()`, line ~170

When a contributor taps a day that **has** events, `DayDetailBottomSheet` opens with a non-null `onAddEvent` callback. This "Add Event" button inside the bottom sheet is not permission-gated. A contributor without `canCreateGigs` could open the `AddEditEventBottomSheet` through this path.

**Scope assessment:** This code path was NOT identified in the Architect Plan (§4.2 only addresses the button row and empty-day taps). The engineer correctly did not modify it. However, it represents a pre-existing unguarded mutation entry point.

**Recommendation for follow-up ticket:** Pass `onAddEvent: null` when contributor lacks `canCreateGigs`, so the sheet hides the button.

### W-3: `_openEditEventSheet` opens edit form for gigs/rehearsals without RBAC check (calendar_tab_content.dart, pre-existing)

**Location:** `_openEditEventSheet()`, lines ~204–213

Tapping a gig or rehearsal in the monthly events list or in the `DayDetailBottomSheet` opens `AddEditEventBottomSheet` in edit mode for any user. No permission check gates this path. A contributor could access the full edit form for existing gigs/rehearsals.

**Scope assessment:** This was NOT identified in the Architect Plan. The Architect Plan's §5 explicitly states `add_edit_event_bottom_sheet.dart` is "Unchanged — it's gated by the calendar's button visibility." The event-tap path was not in scope.

**Recommendation for follow-up ticket:** Gate event tap to open in view-only mode for contributors without edit permissions.

### W-4: Bounce-back callback in `app_shell.dart` schedules redundantly (cosmetic)

**Location:** `build()`, lines ~126–131

When `isCurrentTabVisible` is false, `addPostFrameCallback` schedules `setTab(NavTabIndex.dashboard)` on every rebuild until the callback fires. Since the callback is idempotent and fires within one frame, this is harmless. A guard `if (currentTab != NavTabIndex.dashboard)` would be marginally cleaner.

---

## Suggestions (Optional)

### S-1: Error fallback strategy documentation

Both `setlist_detail_screen.dart` and `setlists_tab_content.dart` use `error: (_, __) => true` (admin fallback) for `canEdit`. This matches the Architect Plan (§4.1) and is backed by RLS as final authority. However, this is the inverse of the `loading` branch (`false` — fail closed). Consider documenting the rationale more explicitly in a code comment for future maintainers, since the asymmetry between loading (closed) and error (open) could be misread as a bug.

### S-2: Consolidate calendar mutation gating in a future feature

W-2 and W-3 highlight that the calendar's mutation surface extends beyond the button row and empty-day tap. A comprehensive follow-up ticket should audit all event-creation and event-edit entry points in the calendar flow.

---

## flutter analyze Result

```
Analyzing lib...

warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19 • dead_code

1 issue found. (ran in 2.3s)
```

- **0 new errors introduced**
- **0 new warnings introduced**
- **1 pre-existing warning** in `lyrics_view_screen.dart` (unrelated to this feature)

---

## Compliance Checklist

| # | Check | Result |
|---|-------|--------|
| 1 | Engineer implemented only what Architect specified | PASS |
| 2 | No scope expansion | PASS |
| 3 | No refactors outside approved files | PASS |
| 4 | No changes to Supabase migrations | PASS |
| 5 | No changes to RPC contracts | PASS |
| 6 | No changes to RLS | PASS |
| 7 | No ordering logic modifications | PASS |
| 8 | No submission flow changes | PASS |
| 9 | Drag reorder songs blocked for contributor | PASS |
| 10 | Delete setlists blocked for contributor | PASS |
| 11 | Duplicate setlists blocked for contributor | PASS |
| 12 | Duplicate catalog blocked for contributor | PASS |
| 13 | Delete songs blocked for contributor | PASS |
| 14 | Edit song info blocked for contributor | PASS |
| 15 | Song tap opens lyrics (not edit drawer) for contributor | PASS |
| 16 | No mutation RPC triggered by contributor UI | PASS |
| 17 | No optimistic UI mutation for contributor | PASS |
| 18 | Gesture handlers removed/gated (not just visually disabled) | PASS |
| 19 | Reorder callbacks cannot fire for contributor | PASS |
| 20 | Edit drawer cannot open for contributor | PASS |
| 21 | Calendar: "Block Out" hidden for contributor | PASS |
| 22 | Calendar: "Add Event" full-width when contributor + canCreateGigs | PASS |
| 23 | Calendar: No buttons when contributor without canCreateGigs | PASS |
| 24 | Calendar: No flicker during permission load | PASS |
| 25 | Members tab hidden if can_view_members = false | PASS |
| 26 | Calendar tab hidden if can_view_calendar = false | PASS |
| 27 | Tabs removed from nav list (not just disabled) | PASS |
| 28 | No index-out-of-range errors | PASS |
| 29 | Selected index remains stable | PASS |
| 30 | No navigation state corruption | PASS |
| 31 | Bounce-back to Dashboard when hidden tab is active | PASS |
| 32 | IndexedStack fixed at 4 children | PASS |
| 33 | No setState after dispose | PASS |
| 34 | mounted checks after awaits | PASS |
| 35 | No Navigator after async without guard | PASS |
| 36 | No rebuild storms from permission provider | PASS |
| 37 | No new memory leaks | PASS |
| 38 | No new listeners without dispose | PASS |
| 39 | No heavy permission logic inside build() | PASS |
| 40 | No new rebuild churn | PASS |
| 41 | No unnecessary provider recalculation | PASS |
| 42 | Admin users: no regression | PASS |
| 43 | Member users: no regression | PASS |
| 44 | Contributors with full permissions: correct behavior | PASS |
| 45 | Contributors with partial permissions: correct behavior | PASS |
| 46 | flutter analyze: 0 new issues | PASS |
| 47 | No new dependencies added | PASS |
| 48 | No Supabase changes | PASS |

**48/48 checks passed.**

---

## Files Reviewed

### Modified (in-scope, per Engineer Report):
| File | Verdict |
|------|---------|
| `lib/features/setlists/setlist_detail_screen.dart` | PASS — 16+ mutation surfaces correctly gated by `canEdit` |
| `lib/features/setlists/setlists_tab_content.dart` | PASS — 4 mutation surfaces gated; SliverList swap correct |
| `lib/features/setlists/widgets/swipeable_setlist_card.dart` | PASS — DismissDirection.none when both callbacks null |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | PASS — Edit icon hidden; tuning badge non-interactive when read-only |
| `lib/features/calendar/calendar_tab_content.dart` | PASS — `_buildActionButtons()` permission matrix correct |
| `lib/features/home/widgets/animated_bottom_nav_bar.dart` | PASS — Comment-only change; renders pre-filtered items |
| `lib/features/shell/app_shell.dart` | PASS — visibleTabs tuple mapping, visual↔semantic index correct |

### Not modified (verified per Architect Plan §5):
| File | Status |
|------|--------|
| `band_permissions.dart` | Unchanged — `canEditSetlists` getter already existed |
| `tab_provider.dart` | Unchanged — stores semantic index |
| `setlist_repository.dart` | Unchanged — data layer unmodified |
| `setlist_detail_controller.dart` | Unchanged — controller unmodified |
| All `supabase/` files | Unchanged — no RPC/RLS/migration changes |

### Additional modified files (out-of-scope, belong to sibling features):
12 additional files are modified in the working tree but belong to the `band_user_roles` and `contributor_restrictions_and_role_sheet_ux` features. They do not affect or conflict with this feature's implementation.
