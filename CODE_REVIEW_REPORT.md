# Code Review Report — Efficiency & Optimization

Date: 2026-05-26

---

## Summary

| Category                          | Finding Count                                                                    |
| --------------------------------- | -------------------------------------------------------------------------------- |
| 1. Design Token Violations        | ~148 `Color(0x…)` + 28 `Colors.*` hardcoded values outside theme files           |
| 2. Riverpod Provider Issues       | 7 distinct issues across providers and screens                                   |
| 3. Repository / Data Layer Issues | 13 silent-swallow catch blocks + 2 N+1 patterns + 40 wildcard `.select()` calls  |
| 4. Controller / State Issues      | 4 issues (anti-pattern persistence, whole-list rebuilds)                         |
| 5. Widget Build Issues            | 6 issues (inline `_build*` helpers, `ListView` without builder, missing `const`) |
| 6. Dead Code                      | 1 dead edge function (`acousticbrainz_bpm`) still deployed and called from Dart  |

---

## 1. Design Token Violations

### 1a. Hardcoded `Color(0x…)` outside theme files

148 instances found. The following are non-landing app features. Theme-internal files (`brand_colors.dart`, `app_theme.dart`, `design_tokens.dart`) are excluded as legitimate definition sites.

```
FILE: lib/features/lyrics/widgets/lyrics_editor_sheet.dart
LINE: 371
VIOLATION: Hardcoded `const Color(0xFFD1D5DB)` — Tailwind gray-300; no equivalent token exists. Add `AppColors.inputDivider` or use `AppColors.blueAccent` family.

FILE: lib/features/home/widgets/potential_gig_card.dart
LINE: 199, 201
VIOLATION: Hardcoded `Color(0xFFFF6900)` and `Color(0xFFCA3500)` — orange gradient for fire icon. Not in token system; candidate for a `AppColors.fireGradientStart/End` token or inline constants in a private class.

FILE: lib/features/home/widgets/potential_gig_card.dart
LINE: 226, 238, 248
VIOLATION: Hardcoded `Color(0xFFFAF8F5)` (warm white), `Color(0xFF4A1F0F)` (dark brown) — used for the orange themed availability section. Should be named constants or tokens.

FILE: lib/features/home/widgets/potential_gig_card.dart
LINE: 532–538
VIOLATION: Hardcoded `Color(0xFF00A63E)` (green) and `Color(0xFFE7000B)` (red) for RSVP yes/no button backgrounds. Should be `AppColors.success` / `AppColors.error`.

FILE: lib/features/home/widgets/rehearsal_card.dart
LINE: 204, 206, 231, 243, 253, 420, 421, 670, 671, 675, 676
VIOLATION: Identical pattern to `potential_gig_card.dart`. Same hardcoded orange/brown/green/red values duplicated verbatim. Both files should share constants.

FILE: lib/features/home/widgets/confirmed_gig_card.dart
LINE: 103
VIOLATION: Hardcoded `const Color(0xFFFFF1F2)` — rose-50, not in `AppColors`. Should be named.

FILE: lib/features/home/widgets/confirmed_gig_card.dart
LINE: 214, 215, 217, 218
VIOLATION: Hardcoded `Color(0xFF2563EB)` (blue-600) and `Color(0xFF7C3AED)` (violet) for animated gradient. `AppColors.blueAccent` covers blue-600; violet has no token.

FILE: lib/features/home/widgets/home_app_bar.dart
LINE: 98
VIOLATION: Hardcoded `const Color(0xFFD1D5DB)` — Tailwind gray-300, used as divider color. No token exists for neutral divider; should be added or use `StandardCardBorder.color`.

FILE: lib/features/calendar/widgets/calendar_event_card.dart
LINE: 76, 81, 257
VIOLATION: Hardcoded `Color(0xFFF97316)` (orange-500 for potential events), `Color(0xFF3B82F6)` (blue-500 for rehearsals), `Color(0xFF1E3A5F)` / `Color(0xFF333333)` (dark overlays). None are in token system.

FILE: lib/features/calendar/widgets/calendar_app_bar.dart
LINE: 97, 98
VIOLATION: Hardcoded `Color(0xFFD1D5DB)` and `Color(0xFF334155)` — same values as `StandardCardBorder.color` (0xFF334155) but not using that constant.

FILE: lib/features/shell/no_band_shell.dart
LINE: 385–389
VIOLATION: Hardcoded rose/white/amber/emerald/blue confetti colors. `AppColors.primary` covers rose. Others should be named constants.

FILE: lib/features/gigs/widgets/availability_prompt_modal.dart
LINE: 147, 148
VIOLATION: Hardcoded `Color(0xFFF77800)` (orange) and `Color(0xFFE11D48)` (rose-600) for gradient stop. Rose-600 matches `AppColors.primary`'s family; both duplicated in `rehearsal_availability_prompt_modal.dart`.

FILE: lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart
LINE: 154, 155
VIOLATION: Duplicate of the above. The two availability modal files share no constants despite having identical gradient colors.

FILE: lib/features/profile/my_profile_screen.dart
LINE: 1662
VIOLATION: Hardcoded `Color(0xFF6366F1)` (indigo-500) for custom role badge. No indigo token exists.

FILE: lib/features/members/widgets/role_management_sheet.dart
LINE: 172
VIOLATION: Hardcoded `Color(0xFFD1D5DB)` — same recurrent gray-300. Should use a divider token.

FILE: lib/features/members/widgets/pending_invite_card.dart
LINE: 136, 148
VIOLATION: Hardcoded `Color(0xFF422006)` (amber-950) and `Color(0xFFFBBF24)` (amber-400) for pending invite warning. No amber token.

FILE: lib/features/setlists/setlist_pdf_preview_screen.dart
LINE: 135
VIOLATION: Hardcoded `Color(0x4D000000)` — semi-transparent black overlay. Could use `Colors.black.withValues(alpha: 0.3)` or a token.

FILE: lib/features/setlists/widgets/setlists_app_bar.dart
LINE: 156, 157
VIOLATION: Hardcoded `Color(0xFFD1D5DB)` and `Color(0xFF334155)`. Same pattern as `calendar_app_bar.dart`; `Color(0xFF334155)` matches `StandardCardBorder.color` exactly — use it.

FILE: lib/features/setlists/widgets/setlist_picker_bottom_sheet.dart
LINE: 225
VIOLATION: Hardcoded `Color(0xFFD1D5DB)`. Pattern repeated in at least 6 files.

FILE: lib/features/setlists/widgets/song_details_bottom_sheet.dart
LINE: 453
VIOLATION: Hardcoded `Color(0xFFD1D5DB)` divider. Same as above.

FILE: lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
LINE: 402
VIOLATION: Hardcoded `Color(0xFFD1D5DB)` divider. Same pattern.

FILE: lib/features/setlists/tuning/tuning_helpers.dart
LINE: 207–316
VIOLATION: 30+ hardcoded `Color(0x…)` values for the tuning color map. These are intentionally distinct semantic colors (one per tuning), not brand tokens — this is a reasonable use case. However, the map itself is reconstructed on every call to `getColorForTuning()` because it is declared inline in the function body. Extracting to a top-level `const` map eliminates repeated allocation.
```

### 1b. `Colors.*` references that should use tokens

```
FILE: lib/features/auth/auth_confirm_screen.dart
LINES: 341, 423, 433, 443, 450
VIOLATION: `Colors.orange` and `Colors.red` for icon states. Should be `AppColors.error` (red) and a named warning token.

FILE: lib/features/auth/invite_screen.dart
LINES: 288, 292, 316
VIOLATION: `Colors.red` and `Colors.green` for error/success icons. Should be `AppColors.error` / `AppColors.success`.

FILE: lib/features/gigs/widgets/availability_prompt_modal.dart
LINE: 91, 103
VIOLATION: `Colors.red` used directly on `SnackBar.backgroundColor`. Should use `showErrorSnackBar()` from `snackbar_helper.dart` instead of raw SnackBar construction.

FILE: lib/features/rehearsals/widgets/rehearsal_availability_prompt_modal.dart
LINE: 97, 110
VIOLATION: Same raw `Colors.red` SnackBar pattern. Use `showErrorSnackBar()`.

FILE: lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
LINE: 424, 1048, 1053
VIOLATION: `Colors.red` for delete action styling. Should be `AppColors.error`.

FILE: lib/features/setlists/widgets/custom_tuning_modal.dart
LINE: 398, 454
VIOLATION: `Colors.red.shade400` for input error borders. Should be `AppColors.error`.
```

### 1c. Hardcoded font sizes (not using `AppTextStyles`)

```
FILE: lib/features/settings/settings_screen.dart
LINES: 101, 116, 125, 140, 153, 170, 194, 202, 270, 290, 298, 379, 388, 437, 449
VIOLATION: 15 inline `fontSize:` values (14, 16, 20, 13) — entire screen bypasses `AppTextStyles`. Should use `AppTextStyles.callout`, `AppTextStyles.headline`, etc.

FILE: lib/features/home/widgets/side_drawer.dart
LINES: 70, 78, 86, 94, 103, 111, 403
VIOLATION: 7 hardcoded font sizes (12, 16, 18). Should use text style tokens.

FILE: lib/features/home/widgets/band_switcher.dart
LINES: 63, 235, 250, 472
VIOLATION: 4 hardcoded font sizes.

FILE: lib/features/home/widgets/potential_gig_card.dart
LINES: 236, 246, 264, 283, 305, 316, 332, 496, 565, 597, 662
VIOLATION: 11 hardcoded font sizes. Many could be replaced with `AppTextStyles.footnote`, `AppTextStyles.callout`.
```

---

## 2. Riverpod Provider Issues

### 2a. Broad `ref.watch` on full state providers — no `select()` narrowing

135 `ref.watch(…Provider)` calls exist across the codebase. Zero use `.select()` for narrowing. This is the most systemic Riverpod issue in the app.

**High-impact examples:**

```
FILE: lib/features/home/home_tab_content.dart
LINES: 461–548
ISSUE: Watches `activeBandProvider`, `gigProvider`, `rehearsalProvider`, `membersProvider`, `setlistsProvider` as full state objects. Any field change in any of these providers causes the entire `HomeTabContent` subtree to rebuild.

For example, `activeBandProvider` is watched 4 times in the same file (lines 461, 996, 1122, 1177) just to read `.activeBand?.timezone`. This should be:
  ref.watch(activeBandProvider.select((s) => s.activeBand?.timezone))
```

```
FILE: lib/features/home/home_screen.dart
LINES: 278–306
ISSUE: Same pattern — 6 providers watched as full state on every `build()` call.
```

```
FILE: lib/features/calendar/calendar_tab_content.dart
LINES: 240–257
ISSUE: `activeBandProvider` watched as full state when only `bandId` is needed in the majority of call sites.
```

**Recommendation:** Introduce `activeBandIdProvider` (which already exists) uniformly at call sites that only need the ID. For field access patterns like `.activeBand?.timezone`, use `.select()`.

### 2b. `ref.watch(activeBandProvider)` — 20 call sites watching full state

```
FINDING: `ref.watch(activeBandProvider)` is called 20 times across feature files.
Most call sites only use one field (`.activeBand?.id`, `.activeBand?.timezone`, `.activeBand?.name`).
Since `activeBandProvider` is a `Notifier<ActiveBandState>`, any mutation (even loading flags toggling) forces all 20 watchers to rebuild.
The existing `activeBandIdProvider` select-style provider should be used wherever only the ID is needed, but is underutilised.
```

### 2c. FutureProvider error swallowing with empty-return

```
FILE: lib/features/gigs/gig_response_repository.dart
LINES: 900, 928 (inside currentUserGigResponsesProvider, currentUserGigAllDateResponsesProvider)
ISSUE: `catch (e) { debugPrint(...); return {}; }` inside FutureProviders.
A FutureProvider that silently returns `{}` on error makes the error invisible to the UI — the widget sees "success with no data" instead of an error state. Should either rethrow (so `.when(error:...)` handles it) or expose error state explicitly.
```

### 2d. Missing `.autoDispose` on per-screen FutureProviders

```
FINDING: 73 `NotifierProvider` / `FutureProvider` / `StreamProvider` declarations found with no `.autoDispose`.
Most are app-level shared providers (correct). However, the following are logically per-screen and hold data that is no longer relevant when the user leaves:

- `currentUserGigResponsesProvider` (gig_response_repository.dart) — loads on every home screen open; never freed
- `currentUserGigAllDateResponsesProvider` — same
- `currentUserRehearsalResponsesProvider` — same
- `unreadNotificationCountProvider` — correctly uses `.autoDispose` (good example to follow)

These providers hold user-specific response maps that are invalidated by user action but never garbage-collected between navigation events.
```

### 2e. `Future.microtask` to trigger loads — anti-pattern still present

```
FILE: lib/features/setlists/setlists_screen.dart
LINES: 99–113
ISSUE: Uses `_lastLoadedBandId` instance variable + `Future.microtask(() => loadSetlists())` to defer loading out of `initState`. This is the known anti-pattern documented as replaced in `calendar_controller.dart` (line 183). The setlists screen has not been migrated.

Additional `Future.microtask` load triggers (may be acceptable in context, but should be reviewed):
- lib/features/home/home_screen.dart:94
- lib/features/contacts/contacts_tab_content.dart:67
- lib/features/contacts/widgets/venues_view.dart:30
- lib/features/contacts/widgets/contacts_view.dart:30
- lib/features/members/members_tab_content.dart:64
- lib/features/setlists/setlist_detail_controller.dart:315, 858, 1807
```

### 2f. `ref.watch` of entire `gigProvider` when only `potentialGigs` is needed

```
FILE: lib/features/gigs/gig_response_repository.dart
LINES: ~882, ~904
ISSUE: `ref.watch(gigProvider)` is used inside FutureProviders purely to extract `gigState.potentialGigs.map((g) => g.id)`. Any change to `GigState` (loading flags, confirmed gigs list, etc.) triggers these providers to re-run even when `potentialGigs` is unchanged.
Fix: `ref.watch(gigProvider.select((s) => s.potentialGigs.map((g) => g.id).toList()))`
```

---

## 3. Repository / Data Layer Issues

### 3a. Silent error swallowing — full catalogue

Every instance where `catch (e) { return []/{}/<default>; }` loses the error entirely:

```
FILE: lib/features/profile/user_band_roles_repository.dart
LINE: 101 — catch returns `[]` (empty roles list). Caller cannot distinguish "no roles" from "fetch failed".
LINE: 176 — catch returns `{}` (empty map). Same ambiguity.
LINE: 220 — catch returns `{}`.
LINE: 255 — catch returns `false`. Boolean return swallows the failure.

FILE: lib/features/members/members_repository.dart
LINE: 355 — catch returns `false` from `removeMember()`. Caller gets `false` whether the member doesn't exist OR a network error occurred.
LINE: 379 — catch returns `null` from `fetchContributorPermissions()`.
LINE: 421 — catch returns `false` from `updateMemberRole()` (note: also re-throws on line 431 in a different branch — inconsistent).
LINE: 468 — catch returns `false` from `isAdmin()`. A network failure silently appears as "not admin".

FILE: lib/features/gigs/gig_response_repository.dart
LINE: 900 — FutureProvider returns `{}` on error (see §2c above).
LINE: 928 — Same.

FILE: lib/features/rehearsals/rehearsal_response_repository.dart
LINE: 815 — catch returns `{}`.
LINE: 842 — catch returns `{}`.
LINE: 873 — catch returns `{}`.

FILE: lib/features/setlists/setlist_repository.dart
LINE: 420 — deduplication failure caught, silently continues (acceptable — documented).
LINE: 439 — catalog creation failure caught, silently continues (acceptable — documented).
LINE: 458 — catalog metadata update failure caught, silently continues (acceptable — documented).
LINE: 659 — parse error during song enrichment caught silently.
LINE: 698, 774, 846, 906, 987, 1088, 1170, 1343, 1382, 1450 — various catch blocks that log and rethrow (correct). Not violations — listed for completeness.

FILE: lib/features/calendar/block_out_repository.dart
LINE: 164 — catches duplicate constraint violations (acceptable and documented).
```

**Pattern summary:** The most dangerous silent swallows are in `members_repository.dart` (boolean returns masking errors) and `user_band_roles_repository.dart` (empty returns). The setlist and calendar repos generally rethrow or are intentionally swallowed with comments.

### 3b. N+1 query patterns — awaits inside loops

```
FILE: lib/features/setlists/setlist_repository.dart
LINES: 973–979 — `reorderSetlists()` issues one `UPDATE` per setlist in a `for` loop:
  for (int i = 0; i < setlistIdsInOrder.length; i++) {
    await supabase.from('setlists').update({'position': i + 1})…
  }
  A band with 10 setlists issues 10 sequential round trips.
  Fix: Use a single RPC call (`reorder_setlists`) or batch with `upsert()`.

FILE: lib/features/setlists/setlist_repository.dart
LINES: 1111–1127 — `_reorderSongsFallback()` issues 2N sequential `UPDATE` calls (N songs × 2 phases). A setlist with 30 songs = 60 sequential Supabase round trips.
  Fix: The primary path already uses an RPC (`reorder_setlist_items`). The fallback should be removed or replaced with a `upsert()` batch once the RPC is confirmed stable.

FILE: lib/features/setlists/special_item_repository.dart
LINES: 353–366 — Same two-phase loop pattern for special item reordering. 2N sequential updates per reorder.
  Fix: Same RPC-or-batch approach.
```

### 3c. Missing `.select()` column limiting — wildcard queries

40 instances of `.select()` (no columns) found across the codebase, fetching all columns:

```
FILE: lib/features/profile/my_profile_screen.dart
LINE: 194 — `supabase.from('users').select()` fetches all user columns when only a subset is needed.

FILE: lib/features/profile/profile_screen.dart
LINE: 22 — Same.

FILE: lib/features/bands/band_repository.dart
LINE: 81 — `supabase.from('bands').select()` — fetches all band columns.

FILE: lib/features/members/members_repository.dart
LINE: 373 — Wildcard select on a join query.

FILE: lib/features/members/permissions/band_permissions_provider.dart
LINE: 72 — Wildcard select for permissions query.

FILE: lib/features/calendar/block_out_repository.dart
LINES: 86, 160, 185, 236 — Four wildcard selects on `block_dates`.

FILE: lib/features/contacts/venues_repository.dart
LINES: 122, 138 — Two wildcard selects on `venues` (includes address, phone, notes — large rows).

FILE: lib/features/notifications/notification_repository.dart
LINE: 26 — `supabase.from('notifications').select()` — `notifications` has a large `metadata JSONB` column always fetched.

FILE: lib/features/setlists/special_item_repository.dart
LINES: 47, 60, 102 — Three wildcard selects on `setlist_special_items`.

FILE: lib/features/setlists/print_template_repository.dart
LINES: 12, 32, 46 — Three wildcard selects on `print_templates`.

FILE: lib/features/events/events_repository.dart
LINES: 373, 436, 828, 892 — Four wildcard selects on `rehearsals` and `gigs`. Gigs table has `notes`, `gig_pay`, `required_member_ids[]` — non-trivial payload.

NOTE: lib/features/settings/data_backup_service.dart wildcard selects (×11) are intentional — backup service must export all columns.
```

---

## 4. Controller / State Issues

### 4a. `_lastLoadedBandId` + `Future.microtask` anti-pattern still in setlists screen

```
FILE: lib/features/setlists/setlists_screen.dart
LINES: 82, 93, 99–113
ISSUE: Uses `String? _lastLoadedBandId` widget-level instance state to track which band was loaded, and `Future.microtask(() => loadSetlists())` to defer loading. This is explicitly identified in `calendar_controller.dart` (line 183) as a race-condition-prone anti-pattern that was already fixed there. The setlists screen is the last known instance of this pattern.

The fix (as documented in calendar_controller.dart): move band-switching logic into the Notifier's `build()` method using `ref.watch(activeBandIdProvider)` and start the async load directly — no `_lastLoadedBandId`, no `microtask`.
```

### 4b. Whole-list scan on single-item update

```
FILE: lib/features/setlists/setlist_detail_controller.dart
LINES: 888–893, 939–944, 994–999, 1059–1064, 1129–1137, 1194+
ISSUE: Every single-song update (BPM, duration, tuning) performs:
  final updatedSongs = state.songs.map((song) {
    if (song.id == songId) return song.copyWith(bpm: bpm);
    return song;
  }).toList();
This is O(n) even when changing one song in a 50-song setlist. The list is fully iterated and a new `List` object is allocated on every BPM keypress (inline editing fires on every character).

Fix: Use an index-based approach:
  final idx = state.songs.indexWhere((s) => s.id == songId);
  if (idx == -1) return;
  final newSongs = [...state.songs];
  newSongs[idx] = state.songs[idx].copyWith(bpm: bpm);
  _syncSongStateWith(newSongs);
This still allocates a new list (required for immutability) but avoids the map iteration.
```

### 4c. Duplicated band-loading state logic across controllers

```
FINDING: The following controllers each independently maintain:
  - A "loading" flag
  - A "last loaded band ID" guard (or equivalent)
  - A `loadXxx(bandId)` method that checks whether to skip or reload

  lib/features/contacts/contacts_controller.dart
  lib/features/contacts/venues_controller.dart
  lib/features/members/members_controller.dart
  lib/features/gigs/gig_controller.dart
  lib/features/rehearsals/rehearsal_controller.dart

Each implements the same pattern with subtle differences. No shared base class or mixin exists. This is not a blocking issue but a DRY violation that accumulates maintenance debt.
```

### 4d. `setlist_detail_controller.dart` oversize

```
FILE: lib/features/setlists/setlist_detail_controller.dart
SIZE: 1,818 lines
ISSUE: A single Notifier file containing loading, editing, reordering, BPM enrichment, deduplication, and song-move logic. State mutations for unrelated concerns are co-located. When any method calls `state = state.copyWith(...)`, all 63 copyWith call sites are in the same file — change locality is low.
This is an architectural observation, not a single fix, but it is a maintenance risk.
```

---

## 5. Widget Build Issues

### 5a. `_build*` helper methods in StatefulWidget — rebuild on every parent build

```
FILE: lib/features/home/home_tab_content.dart
LINES: 647, 692, 746, 965, 1104, 1131
ISSUE: Six `Widget _buildXxx()` methods defined on the State class. Each is called inside `build()`. Because they are methods (not `const` constructors or extracted `StatelessWidget` subclasses), Flutter cannot skip them during rebuilds — they run on every rebuild of `HomeTabContent`.

Notable: `_buildHorizontalGigsList()` and `_buildHorizontalRehearsalsList()` each construct `SizedBox` containers with `ListView` + `AnimatedSwitcher` — non-trivial widget subtrees built unconditionally every rebuild.

FILE: lib/features/home/home_screen.dart
LINES: 469, 516, 630, 732, 864
ISSUE: Same pattern — 5 `_buildXxx()` helpers. Since `home_screen.dart` watches 6 providers, any provider change triggers all 5 helpers to re-execute.
```

### 5b. `ListView` without `ListView.builder` where list is dynamic

```
FILE: lib/features/setlists/widgets/song_lookup_overlay.dart
LINE: 633
ISSUE: `return ListView(children: [...])` where children are dynamically mapped from search results. If results are large (catalog has hundreds of songs), all items are built at once. Should be `ListView.builder`.

FILE: lib/features/setlists/widgets/tuning_picker_bottom_sheet.dart
LINE: 536
ISSUE: `ListView(children: tunings.map(...).toList())` — full list rendered upfront. For ~20 tuning entries this is acceptable, but the same file has complex tuning cards so build cost per item is non-trivial.

FILE: lib/features/home/widgets/quick_actions_row.dart
LINE: 62
ISSUE: `ListView(children: [...])` for a horizontal actions row. `ListView.builder` with known item count is preferred for consistency.
```

### 5c. Missing `const` constructors on leaf widgets

```
FILE: lib/features/home/widgets/empty_section_card.dart
LINES: 102, 116
ISSUE: `fontSize: 16` raw `TextStyle` in `Text` widget prevents `const` — the enclosing widget is not eligible for const promotion even though its content is static.

FINDING: flutter analyze would surface additional `prefer_const_constructors` lint hits. Running `dart fix --apply` would resolve many mechanically. The 2,877 existing `const` uses shows the team is generally diligent; the gaps are isolated.
```

### 5d. `itemExtent` not used on any `ListView.builder`

```
FINDING: No `ListView.builder` in the codebase sets `itemExtent`. Song cards (`SongCard`, `ReorderableSongCard`) have deterministic heights defined in `SongCardLayout` constants:
  - `SongCardLayout.metricsRowHeight = 36`
  - `SongCardLayout.cardVerticalPadding = 14` (×2)

Setting `itemExtent: SongCardLayout.metricsRowHeight + (2 * SongCardLayout.cardVerticalPadding) + <title row height>` on the setlist `SliverList` would allow Flutter to compute item positions without measuring, improving scroll performance on long setlists.

Most impacted: `setlist_detail_screen.dart` (SliverList for catalog view, which can be 200+ songs).
```

---

## 6. Dead Code

### 6a. `acousticbrainz_bpm` Edge Function — confirmed dead, still called

```
EDGE FUNCTION: supabase/functions/acousticbrainz_bpm/index.ts
STATUS: Deployed (confirmed present in supabase/functions/)

BACKGROUND: AcousticBrainz API was shut down by MetaBrainz in November 2022.
The edge function calls the AcousticBrainz HTTP API which no longer exists.
Every call to this function either returns HTTP 404/503 or times out.

DART CALL SITE:
FILE: lib/features/setlists/setlist_repository.dart
LINE: 3955 — `bpm = await _fetchAcousticBrainzBpm(title, artist);`
LINE: 4049–4081 — `_fetchAcousticBrainzBpm()` implementation

IMPACT:
- Every BPM enrichment attempt where Spotify lookup fails invokes this function.
- The function is wrapped in a try/catch that returns `null` on failure, so there is no user-visible error.
- However: a Supabase Edge Function invocation is a cold-startable Deno runtime. Even a failing call adds ~200–500ms latency to every song enrichment that lacks a Spotify ID.
- The function counts against Supabase Edge Function invocation quotas with zero value returned.

RECOMMENDATION:
1. Remove the `_fetchAcousticBrainzBpm()` call from `_attemptBpmEnrichment()` (the "Strategy 2" fallback).
2. Undeploy the `acousticbrainz_bpm` edge function from Supabase.
3. Consider MusicBrainz direct lookup as a replacement (the edge function already does MusicBrainz recording lookup as Step 1 — the AcousticBrainz part was Step 2).
```

### 6b. No other dead edge functions identified

The remaining functions (`accept-invite`, `musicbrainz_search`, `send-band-invite`, `send-bug-report`, `send-push`, `spotify_search`, `calendar-feed`) all have active Dart call sites or are infrastructure functions.

---

## Priority Recommendations

Ranked by **impact ÷ effort** — highest ratio first.

### P1 — Remove AcousticBrainz dead code [Effort: XS | Impact: Medium]

Delete the 3-line Strategy 2 call in `_attemptBpmEnrichment()` and undeploy the edge function. Zero risk, immediate latency win for BPM enrichment flows, reduces Supabase invocation cost. This is a single line deletion in Dart + one Supabase CLI command.

---

### P2 — Fix silent error swallowing in `members_repository.dart` [Effort: S | Impact: High]

The `removeMember()` / `isAdmin()` / `updateMemberRole()` functions return `false`/`null` on network errors, making errors invisible to the UI. A failed `removeMember` call silently returns `false` — the same value as "member not found". These should throw named exceptions so the calling controller can surface the error to the user. Five functions, each a 2–3 line change.

---

### P3 — Replace `_lastLoadedBandId` + `microtask` in `setlists_screen.dart` [Effort: S | Impact: Medium]

This is the last instance of the known anti-pattern. The calendar controller already documents how to fix it (move band-switch watch into the Notifier `build()`). Following that pattern eliminates the race condition and removes ~30 lines of widget-level state management.

---

### P4 — Add `.select()` narrowing to `activeBandProvider` watchers [Effort: M | Impact: High]

20 `ref.watch(activeBandProvider)` call sites across screens. Switching bands (or toggling loading state) forces all 20 consumers to rebuild. Adding `.select((s) => s.activeBand?.timezone)` (or similar) at call sites that don't need the full state reduces rebuild cascades significantly, especially in `home_tab_content.dart` which also watches 5 other providers simultaneously.

---

### P5 — Batch setlist/song reorder queries [Effort: M | Impact: High]

The `reorderSetlists()` N+1 loop and `_reorderSongsFallback()` 2N loop issue up to 60 sequential Supabase round trips per reorder. For a 30-song setlist, this is the single most expensive operation in the app. The primary path already uses an RPC for song reorder — the fallback and setlist reorder should follow the same pattern. A single RPC call (or `upsert()` batch) reduces this to 1 round trip.
