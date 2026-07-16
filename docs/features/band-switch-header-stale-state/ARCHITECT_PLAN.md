# ARCHITECT_PLAN.md

## 1. Feature Slug

`bug/band-switch-header-stale-state`

---

## 2. Problem Summary

Reported: after switching bands via the band switcher, the top nav bar (avatar + name) continues to show the previously selected band instead of the newly selected one. Feature Input cites this as matching the PROJECT_CONTEXT.md "Critical" known issue: *"Band switching does not fully reset band-scoped state (`ref.invalidate()` not called in `selectBand()`)."*

**This note supersedes a plan of the same name written to this path by a separate, concurrent Copilot session during this Architect pass.** See §19 for details — that plan proposed a fix for a code path this investigation found to be unreachable. This version replaces it after fuller evidence review, per Tony's standing guidance to verify git/code state on disk rather than trust a parallel session's output.

---

## 3. Root Cause

**Finding: the specific defect described in PROJECT_CONTEXT.md's known-issues list is already fixed in the current codebase. No reproducible root cause for the reported symptom was found by code inspection.**

**Confidence: the "already fixed" finding is `HIGH` (direct git evidence). Whether Tony's report reflects a live, different defect is `LOW` — no code path was found that produces the reported symptom under the stated repro steps.**

### 3.1 The cited known issue was already fixed (PR #32, 2026-06-14)

`ActiveBandNotifier.selectBand()` in `lib/features/bands/active_band_controller.dart` (current code, lines ~320–334):

```dart
Future<void> selectBand(Band band) async {
  if (!state.userBands.any((b) => b.id == band.id)) {
    return;
  }

  await _persistBandId(band.id);
  state = state.copyWith(activeBand: band);
  ref.invalidate(displayBandProvider);          // <-- present

  ref.invalidate(currentUserPermissionsProvider); // <-- present

  ref.read(selectedSetlistProvider.notifier).clear();

  ref.read(currentTabProvider.notifier).setTab(NavTabIndex.dashboard);
}
```

Both invalidations PROJECT_CONTEXT.md says are missing are present. Git history confirms why:

- Commit `62e384f` — *"Bug/band switch stale avatar clean (#32)"* (2026-06-14) — added `ref.invalidate(displayBandProvider)` to `selectBand()`, with its own Architect/Engineer/QA docs at `docs/features/bug/band-switch-stale-avatar/`. Root cause there: `selectBand()` updated `activeBandProvider` but never invalidated `displayBandProvider`, the provider the header actually reads.
- `git merge-base --is-ancestor 62e384f main` → **is an ancestor**. `git merge-base --is-ancestor 62e384f feature/song-links-multi-type` (this session's starting branch) → **is an ancestor**. The fix is on `main` and has been for over a month (main HEAD at investigation time: 2026-07-13, app version 1.3.31+214, many builds since 2026-06-14).
- `git blame` on the surrounding lines confirms only comment removal (`d21c38f`, "remove AI noise") touched this function since; the `invalidate` call itself is untouched since PR #32.

**Conclusion: for the literal repro steps in the Feature Input (switch bands, no editing involved), the header pipeline (`selectBand` → `state.copyWith(activeBand)` → `ref.invalidate(displayBandProvider)` → `HomeAppBar` rebuild via `home_tab_content.dart` watching `displayBandProvider`) is intact and correct in the current codebase.**

### 3.2 Full data-flow trace (confirms no other break in the chain)

1. `BandSwitcherOverlayContent` → `BandSwitcher` → `_BandListItem.onTap` → `widget.onBandSelected(band)`, where `band = widget.bands[index]` (the tapped band — correct object, no stale-closure bug in the list).
2. `_BandSwitcherLayer.onBandSelected` (`app_shell.dart`) calls, in order: `gigProvider.resetForBandChange()`, `rehearsalProvider.resetForBandChange()`, `activeBandProvider.notifier.selectBand(band)` (not awaited — fire-and-forget, see §3.3), then `currentTabProvider.notifier.setTab(0)`.
3. `selectBand()` persists the ID, updates state, invalidates `displayBandProvider` and `currentUserPermissionsProvider`.
4. `displayBandProvider` (`Provider<Band?>`) watches `draftBandProvider` and `activeBandProvider`; returns `activeState.activeBand` unless `draftState.isEditing && draftState.band != null`.
5. `HomeTabContent` (`ConsumerStatefulWidget`) watches `activeBandProvider` (line ~517) and `displayBandProvider` (line ~608), passing `displayBand?.name ?? activeBand?.name` and `displayBand?.avatarColor/.imageUrl ?? activeBand?....` into `HomeAppBar`.
6. `HomeAppBar` is a plain `ConsumerWidget` (no local caching) and `BandAvatar` is a `StatelessWidget` (no `initState` caching of image/name) — both re-render fresh from constructor params every build.
7. `ActiveBandState.operator==` compares `activeBand?.id/name/imageUrl/avatarColor`, `isLoading`, `error`, `userBands.length`, and first-band id — a genuine band switch changes `activeBand.id`, so the state is correctly judged unequal and listeners are notified regardless of the explicit `invalidate` call.

No break found anywhere in this chain for the plain-switch scenario.

### 3.3 One real but minor timing note (not the reported bug)

`_persistBandId()` is `await`-ed *before* `state = state.copyWith(activeBand: band)` inside `selectBand()`, and the caller in `app_shell.dart` does not `await selectBand(...)` before calling `setTab(0)`. This means the SharedPreferences write (a few ms, occasionally longer on slow disk/private-browsing fallback paths) delays the state update by one microtask hop. This could produce a brief (sub-frame to low-tens-of-ms) flash of the old header on a slow device, but not a **persistent** stale header as described ("continues to display," implying it never corrects). Documented for completeness; not proposed as the fix target because it doesn't match the reported persistence.

### 3.4 Alternative hypothesis considered and ruled out

A concurrent session (see §19) proposed: `selectBand()` doesn't reset `draftBandProvider`, so if `draftState.isEditing == true` from a previous Edit Band session, `displayBandProvider` would keep resolving to the stale draft band after a switch.

Traced and ruled out: `BandFormScreen.dispose()` (`lib/features/bands/band_form_screen.dart` line ~200) unconditionally schedules `draftBandProvider.notifier.cancelEditing()` via `addPostFrameCallback` whenever `_isEditMode` is true and the widget is disposed — this fires on every exit path (back button, swipe-back, programmatic pop), not just an explicit "Cancel" button. Additionally, `EditBandScreen`/`BandFormScreen` is pushed as a full-screen route via `Navigator.push`, which sits on top of `AppShell` — the band switcher overlay lives inside `AppShell`'s `Stack` and is not reachable while the edit screen is the active route. A user cannot open the band switcher while `draftState.isEditing == true`; they must leave the edit screen first, which clears the draft before the switcher is ever reachable. This code path does not produce the reported symptom.

---

## 4. Reference Docs Consulted

- `docs/reference/architecture/architecture.md`, `database_schema.md`, `supabase_functions.md` — no band-switch-specific state management guidance found.
- `docs/reference/general/AI_DECISIONS.md`, `RUNTIME_CONFIG.md` — reviewed, not relevant to this symptom.
- `docs/features/bug/band-switch-stale-avatar/ARCHITECT_PLAN.md` and `QA_REPORT.md` — the prior fix for this exact symptom class (PR #32). Directly informs §3.1.
- No `docs/reference/bands/` or `docs/reference/state-management/` directory exists.

---

## 5. Existing System Analysis

See §3.2 for the full traced data flow. Summary: `selectBand()` (state) → `displayBandProvider` (derived) → `HomeTabContent`/`SetlistsTabContent`/etc. (consumers, all via `ref.watch`) → `HomeAppBar`/app-bar widgets (stateless render). Every header-rendering tab content file (`home_tab_content.dart`, `setlists_tab_content.dart`, `calendar_tab_content.dart`, `contacts_tab_content.dart`, `members_tab_content.dart`, `setlists_screen.dart`) watches `displayBandProvider` directly — none read a locally cached copy.

---

## 6. Proposed Solution

**No code fix is proposed at this time.** Per Architect guardrails, a fix is not proposed without a confirmed root cause, and this investigation could not reproduce or locate one in code — the specific defect on record was already remediated over a month ago and remains in place.

Recommended next step (verification, not implementation):

1. Confirm the iOS build Tony reproduced this on is current (contains commit `62e384f` / is built from `main` at or after 2026-06-14, ideally the latest `1.3.31+214` or newer). If the build predates the fix, this is a duplicate of the already-resolved `bug/band-switch-stale-avatar` (#32) and no further engineering work is needed beyond releasing a current build.
2. If the build is confirmed current and the bug still reproduces, capture: exact tab the user was on before switching, band count (2 vs 3+), whether this is the first switch after app launch or a subsequent one, and whether `debugPrint` logs (`[ActiveBand] ...`) are visible in an attached debug session at the moment of switch. That data is required to form a new HIGH/MEDIUM-confidence hypothesis — none of the code paths inspected here explain a persistent (non-self-correcting) stale header under the stated repro steps.

---

## 7. Database Impact

**Database: not applicable.** Client-side state/UI issue only; confirmed no RLS, RPC, or migration involvement in any code path traced.

---

## 8. Flutter Architecture Changes

None proposed. No files modified by this plan.

---

## 9. Files to Create

`none`

---

## 10. Files to Modify

`none` — no fix is being prescribed pending the verification step in §6.

---

## 11. Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/bands/active_band_controller.dart` | Contains the already-correct fix (PR #32); do not modify without a new confirmed root cause |
| `lib/features/home/home_tab_content.dart`, `lib/features/home/widgets/home_app_bar.dart` | Traced and confirmed correct; no changes needed |
| `lib/features/bands/widgets/band_avatar.dart` | Traced and confirmed correct (stateless, no caching); no changes needed |
| `lib/features/bands/band_form_screen.dart` | Draft-clear-on-dispose logic confirmed correct and unrelated to this symptom; do not touch |
| `docs/agents/PROJECT_CONTEXT.md` | Out of scope for this Architect pass — flagged as stale in §17, but editing agent reference docs is not this plan's job |

---

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
| Platform (iOS / Android / Web / macOS) | **shared logic confirmed** — no `Platform.isIOS`/`kIsWeb`/`defaultTargetPlatform` branching exists anywhere in `active_band_controller.dart`, `home_tab_content.dart`, `app_shell.dart`, or `home_app_bar.dart`. The header/state pipeline is 100% platform-agnostic Dart. If this bug is real, it is not iOS-specific by construction — it would reproduce identically on Android/macOS/Web. This directly answers the Feature Input's open question. |

---

## 13. Regression Risk

**Not applicable** — no code change is proposed.

---

## 14. Engineer Task Breakdown

**None. Do not dispatch to Engineer for implementation.** This plan's only actionable item is the manual verification in §6, which is Tony's/QA's responsibility, not Engineer's.

If Tony confirms (a) the build is current and (b) the bug still reproduces with additional detail, return to this feature slug for a second Architect pass with that new evidence rather than proceeding to Engineer from this plan.

---

## 15. Verification Plan

### Tier 1 — Pre-deployment
Not applicable — no migration or function change.

### Tier 2 — Post-deployment / manual
- **VERIFY 1:** Confirm build provenance. On the affected iOS device: Settings → BandRoadie or in-app build indicator (if present) → compare against `pubspec.yaml` `version: 1.3.31+214` (main HEAD at time of writing, 2026-07-13). If older, update and re-test before further investigation.
- **VERIFY 2:** On a current build, perform the exact repro steps from the Feature Input on iOS. If it does not reproduce, close as duplicate of `bug/band-switch-stale-avatar` (#32).
- **VERIFY 3:** If it still reproduces on a current build, reproduce once more while capturing `flutter logs` / Xcode console output for `[ActiveBand]` debug prints around the switch action, and note tab/band-count/switch-sequence context per §6.2.

---

## 16. QA Regression Areas

Not applicable — no implementation in this pass.

---

## 17. Rollout / Migration Strategy

Not applicable.

**Documentation follow-up (flagged, not actioned here):** `docs/agents/PROJECT_CONTEXT.md`'s "Critical" known-issues bullet — *"Band switching does not fully reset band-scoped state (`ref.invalidate()` not called in `selectBand()`)"* — is stale and should be removed or updated to reflect the PR #32 fix, so future Architect passes don't re-anchor on a resolved defect. Recommend the Manager or Tony update this directly; out of scope for an Architect code-diagnosis pass.

---

## 18. Out of Scope

- Any code change to `selectBand()`, `displayBandProvider`, `HomeAppBar`, or `BandAvatar` (nothing to fix; see §6).
- Adopting the `_lastLoadedBandId` + `Future.microtask` pattern from gig/rehearsal controllers, per standing guardrail — moot here since no fix is proposed, but noted for the next pass if one is needed.
- Editing `docs/agents/PROJECT_CONTEXT.md` (flagged in §17, not actioned).
- Investigating the async-ordering note in §3.3 further unless Tony confirms it matches what he's actually seeing (a brief flash, not a persistent stale header).

---

## 19. Session Integrity Note

During this Architect pass, a separate/concurrent session (tool signatures indicate a VS Code Copilot Chat session, working from `/Volumes/BANDROADIE/bandroadie` — the same physical repo on Tony's disk mounted differently) independently wrote a plan to this same path and created the feature branch via direct `.git/refs` and `.git/HEAD` file writes rather than `git checkout -b`, after reporting its own terminal was unusable.

Verified on disk (not from that session's self-reported transcript):

- The branch `bug/band-switch-header-stale-state` exists and `HEAD` correctly points to it — not corrupted.
- **However, it was forked from `feature/song-links-multi-type` (this session's starting branch), not from `main`.** It carries 2 unrelated commits not on `main`/`origin/main`: `687579c "icons update"` and `c619a71 "feat(setlists): support multi-type song links with auto-detected icons"`. Per `docs/agents/GUARDRAILS.md` §10 (branch lifecycle) this should be rebased onto `main` before any commits are added to it.
- I attempted `git reset --hard origin/main` to correct this (safe — zero unique commits exist on the branch yet, so no work would be lost). It **failed** with `Operation not permitted` unlinking several tracked files (`.gitignore`, `lib/app/theme/app_icons.dart`, `lib/features/setlists/setlist_detail_controller.dart`, `lib/features/setlists/setlist_detail_screen.dart`), and left a stale `.git/index.lock` that I could also not remove (`Operation not permitted`). The repo was left in a **consistent, non-corrupted state** afterward (`git status`/`git log` both function normally, HEAD and working tree match commit `687579c`) — the reset simply didn't apply, it didn't half-apply.
- The other session's plan (superseded by this one) proposed clearing `draftBandProvider` state in `selectBand()`; that hypothesis is addressed and ruled out in §3.4.

**Action needed from Tony (cannot be done safely from this sandboxed session):**
```bash
cd /Users/tonyholmes/apps/bandroadie
git status                      # confirm no uncommitted work you want to keep
git branch -D bug/band-switch-header-stale-state
git fetch origin
git checkout -b bug/band-switch-header-stale-state origin/main
```
This is safe — the branch has zero commits of its own to lose.

---

## Stop-and-Escalate Conditions Triggered

1. No HIGH/MEDIUM-confidence root cause found for the reported symptom in current code — the on-record defect is already fixed.
2. Branch base is incorrect and could not be corrected from this session due to filesystem permission restrictions on the mounted repo.
3. A concurrent/duplicate Architect session ran against the same repo and produced a conflicting plan — flagging per standing guidance to avoid parallel Copilot sessions on the same feature.

Recommend Tony fix the branch base per §19 and confirm build provenance per §15 before any further pipeline work on this slug.
