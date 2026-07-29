# Architect Plan — Bulk Entry Modal Missing Instructions + Undersized Paste Field on iOS

## Feature Slug

`bug/bulk-entry-instructions-cutoff-ios`

---

## Problem Summary

On iOS, the Bulk Entry modal (reached via Setlists → "Add to setlist" → Bulk Entry) shows only the header and an undersized paste `TextField` — the instructional intro line and the bordered column-order/example/required-optional info box that appear on web are missing entirely, and the field itself renders collapsed (fewer lines, tight padding) rather than as a properly sized multi-line paste target. Web shows both correctly. This is a shared-Dart-widget layout bug, not a platform-specific native code path — `BulkEntryScreen` (`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`) is the single widget rendered on every platform.

---

## Root Cause

**Confidence: HIGH — confirmed by direct read of the current file.**

`bulk_entry_screen.dart`, `build()` (lines 349–543):

1. Line 351: `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;`
2. Line 367: `if (keyboardHeight == 0) ...[ <intro Text>, <bordered info-box Container> ]` — the entire instructional block (intro line + bordered column-order/example/required-optional box) is only added to the widget tree when `keyboardHeight == 0`. When `keyboardHeight > 0`, these widgets are never constructed (this is a Dart collection-`if`, not a `Visibility`/`Opacity` toggle — the content genuinely does not exist in the tree).
3. Line 435: `minLines: keyboardHeight > 0 ? 1 : 3` — the paste `TextField` drops from 3 minimum lines to 1 whenever `keyboardHeight > 0`.
4. Line 442 / 451–453: `isDense: keyboardHeight > 0` and tighter `contentPadding` under the same condition — the field additionally loses its normal padding.
5. Line 433: `autofocus: true` on the same `TextField` — this has been present since the CSV-ingestion model was introduced (commit `2564b4c`, pre-dating all of the above) and is unconditional on every platform.

**Why this reproduces on iOS but not on web:** on iOS, `autofocus: true` causes the on-screen software keyboard to appear immediately when `BulkEntryScreen` first builds and gains focus — `MediaQuery.of(context).viewInsets.bottom` becomes greater than zero essentially on the first post-layout frame, before the user has done anything. This immediately satisfies `keyboardHeight > 0`, which permanently hides the instructional block (per point 2) and shrinks the field (points 3–4) for as long as the keyboard-triggering focus persists — which, from the user's perspective, is instantly and by default. On web (verified: the sibling ticket's QA/Engineer sessions tested only macOS desktop and Chrome web — no touch/mobile-web device), there is no on-screen software keyboard triggered by `autofocus`, so `viewInsets.bottom` stays `0`, `keyboardHeight == 0`, and the instructional block and full-size field render normally. The same code path applies to Android (real on-screen keyboard triggered by autofocus) — the Feature Input marks Android as "unknown," but this is the same shared widget with no platform branch, so it is very likely affected too; this plan does not require confirming that to proceed, since the fix is platform-agnostic.

**Git provenance (why this regressed now, not always):** the `if (keyboardHeight == 0)` gating (point 2) and the `minLines`/`isDense`/`contentPadding` conditionals (points 3–4) were introduced by commit `f3e400c` (`feat(setlists): update bulk import instructions, add Key column guidance, fix keyboard overflow`), documented in `docs/features/bulk-import-flexible-columns/`. That work added the six-line instructional block and bordered info box (previously a single line existed and did not overflow), then added the `keyboardHeight`-based collapse specifically to prevent a real, QA-verified `RenderFlex` overflow when the keyboard is manually opened on a narrow phone. `autofocus: true` (point 5) pre-dates that work by several commits and was never a problem on its own — it only became one once the collapse logic started keying off `keyboardHeight` unconditionally, because `autofocus` now triggers that same collapse condition on the very first frame, before the user has ever seen the instructional content.

This is a genuine interaction bug between two independently-reasonable pieces of code, not a missing conditional branch and not dead/placeholder content — the "column-order text rendering faintly as placeholder text" the user observed is the `TextField`'s `hintText` (line 443, always rendered regardless of `keyboardHeight`), which is why it's visible even though the real instructional content above it is not.

---

## Reference Docs Consulted

Per ARCHITECT.md Phase 4 (written for a notification-domain bug and templated as such): `docs/reference/notifications/` exists but is **not applicable** — this is a setlists/UI layout bug, not a notification bug. No `docs/reference/setlists/`, `docs/reference/bulk-import/`, or `docs/reference/catalog/` directory exists. `docs/reference/ui/` exists but contains only `LANDING_PAGE_PREVIEW_GUIDE.md` (marketing landing page, unrelated to the in-app Bulk Entry modal) — read and confirmed not applicable.

The directly relevant prior work is `docs/features/bulk-import-flexible-columns/` (`ARCHITECT_PLAN.md`, `ENGINEER_REPORT.md`, `QA_REPORT.md`) — read in full. This is the immediately-prior change to the exact same widget and is where the `keyboardHeight`-gated collapse logic implicated in this bug's root cause originates (see Root Cause, git provenance). `docs/reference/general/AI_DECISIONS.md` was also read in full — no logged decision covers this widget or this behavior; this fix does not require a new decision entry (see Files to Modify / Regression Risk — no init-order, config, auth-flow, RLS, or new-dependency change is involved).

---

## Existing System Analysis

1. User taps "Bulk Entry" from the "Add to setlist" flow → `add_to_setlist_overlay.dart` presents `BulkEntryScreen` (line 321) inside `showGeneralDialog` → `Material` → `SafeArea` → `Container` → `Column` (no `Scaffold` in this chain — confirmed by the sibling ticket's QA re-verification pass, and independently confirmed here: `grep` of `add_to_setlist_overlay.dart` shows no autofocus/focus-management logic that would interfere).
2. `BulkEntryScreen.build()` computes `keyboardHeight` from `MediaQuery.viewInsets.bottom` once per build (line 351) and uses it to conditionally render the instructional block, and to resize/re-pad the paste `TextField`.
3. The paste `TextField` (lines 431–474) has `autofocus: true` — on mount, this requests focus, which on native platforms (iOS/Android) triggers the OS on-screen keyboard.
4. The keyboard's appearance changes `MediaQuery.viewInsets.bottom` from `0` to a positive value, which Flutter delivers via a rebuild. That rebuild re-evaluates `keyboardHeight > 0` as `true` before the user has interacted with the screen at all, hiding the instructional content and shrinking the field on the very first meaningful frame the user sees.
5. Nothing in this flow ever restores `keyboardHeight == 0` unless the keyboard is dismissed (e.g., via the "Done" button in `_buildKeyboardToolbar()`, line 740) — which the user has no reason to tap, since they haven't seen the instructional content that would tell them why they'd want to.
6. `_buildFooter()` (line 788) independently adds `MediaQuery.viewInsets.bottom + Spacing.space16` as bottom padding to keep the submit/cancel buttons above the keyboard — unrelated to this bug, unaffected by this fix, not touched.

---

## Proposed Solution

Remove `autofocus: true` from the paste `TextField` (line 433). This is the entire fix.

**Why this is the correct, minimal, root-cause fix (not a workaround):**
- It removes the only trigger that makes `keyboardHeight > 0` true before the user has interacted with the modal. With `autofocus` removed, the field is not focused on mount, no on-screen keyboard opens automatically, and `keyboardHeight == 0` at first render on every platform — the instructional block and full-size field render exactly as they already do on web today, achieving the Feature Input's "should match the web layout" requirement without introducing any platform-conditional code (`kIsWeb`, `Platform.isIOS`, etc.).
- It does **not** touch or weaken the `keyboardHeight`-based collapse logic itself. That logic is intentional, QA-verified behavior from the immediately-prior ticket (`bulk-import-flexible-columns`) that prevents a real `RenderFlex` overflow when the user manually taps into the field and the keyboard opens on a small screen. Once the user taps the field to paste (post-fix, with no autofocus), the keyboard opens deliberately as a result of their action, and the existing collapse behavior correctly kicks in at that point — exactly as designed and already tested by that ticket's QA pass. This plan does not modify, and does not need to modify, any of that logic.
- It is a single line removed, in the one file already implicated, with no new state, no new widgets, and no new conditional branches.

**Trade-off, stated explicitly:** users (on every platform, including web) will need to tap into the paste field once before pasting, rather than the field being pre-focused on modal open. This is a minor UX step, not a functional regression — no platform currently relies on `autofocus` for correctness, and web's actual current behavior (per the sibling ticket's QA docs, tested on macOS desktop and Chrome) shows the instructional content precisely because no software keyboard was ever triggered there — this fix makes iOS/Android match that same "keyboard only opens on deliberate user interaction" behavior, rather than special-casing either platform.

---

## Database Impact

**Not applicable.** No schema, RLS, RPC, migration, or repository code is touched. `setlist_repository.dart` is not modified.

---

## Flutter Architecture Changes

None. No new state, no new widgets, no new providers, no new conditional branches. `_BulkEntryScreenState.build()` loses one constructor argument (`autofocus: true`) from the existing `TextField`. The existing `keyboardHeight`-based conditional rendering (Dart collection-`if`s already in the file) is unchanged in its logic — it will simply no longer be triggered spuriously on mount.

---

## Files to Create

**None required.**

---

## Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Line 433: remove `autofocus: true,` from the paste `TextField` (the one at line 431, `controller: _csvController`). No other line in this file changes. The row-table `TextField`s (`_TableTextField`, lines 873–921) do not use `autofocus` and are unaffected/untouched. |

---

## Files Off-Limits

| File | Reason |
|------|--------|
| `lib/features/setlists/services/bulk_song_parser.dart` | Not implicated — this is a focus/layout bug in the modal widget, not a parsing bug. Confirmed uninvolved by direct read of the failure mechanism (Root Cause above). Do not modify. |
| `lib/features/setlists/models/bulk_song_row.dart` | Not implicated — same reasoning. Do not modify. |
| `lib/features/setlists/setlist_repository.dart` | Not implicated, and separately flagged as architecture debt (4,027 lines) — do not add to it. Do not modify. |
| `lib/features/setlists/setlist_detail_screen.dart` | Not implicated, and separately flagged as architecture debt (2,788 lines) — do not add to it. Do not modify. |
| `lib/features/setlists/widgets/add_to_setlist/add_to_setlist_overlay.dart` | Thin presentation wrapper (`showGeneralDialog` → `BulkEntryScreen`) with no autofocus/focus-management logic of its own (confirmed via grep) — no involvement in the bug. Do not modify. |
| `lib/features/setlists/widgets/bulk_add_songs_overlay.dart` | Different widget (a separate bulk-add surface); not the modal described in the Feature Input's reproduction steps (which is `BulkEntryScreen`, reached via "Add to setlist" → "Bulk Entry"). Out of scope. Do not modify. |
| `lib/main.dart` | Init order must not change — unrelated to this feature. |
| `supabase/migrations/*.sql` | No migration needed or relevant — this is a client-side widget-property change with no data-layer involvement. Do not create a migration file. |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed / none needed
**New files:** none
**AI_DECISIONS.md entry:** not required — this change does not touch init order, config loading, auth flow, RLS policy architecture, a new SECURITY DEFINER function, or a new external dependency (see `docs/reference/general/AI_DECISIONS.md` "Categories Requiring a Logged Decision").

---

## System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's initial-focus behavior and, as a direct consequence, whether the instructional block/full-size paste field render on first open. No parsing, validation, or persistence behavior changes. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **affected uniformly** — shared Dart widget, no platform branch introduced or removed. iOS is the confirmed-broken case being fixed; Android is very likely fixed as a side effect (same code path, same failure mechanism) though not independently confirmed by the Feature Input; web and macOS behavior is preserved (web already showed the correct layout since no software keyboard fires there; macOS desktop is not expected to show a software keyboard either, so behavior there is unchanged in practice). |

---

## Regression Risk

**LEVEL: LOW**

Rationale:
- Single line removed (`autofocus: true`), zero lines added, in one file already implicated by the prior sibling ticket.
- No auth, session, routing, init-order, database, or repository changes.
- Does not modify the `keyboardHeight`-based collapse logic that the prior ticket's QA pass specifically verified prevents a real overflow — that logic is left completely intact and will still trigger correctly once the user deliberately opens the keyboard by tapping the field.
- The only user-visible behavior change is that the paste field is no longer pre-focused on modal open, on every platform (see Trade-off in Proposed Solution) — a minor UX step, not a functional regression, and not a change QA needs to treat as a new capability requiring broad re-testing.

---

## Engineer Task Breakdown

Execute in order:

### Task 1 — Remove `autofocus: true` from the paste `TextField`
1. In `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, locate the `TextField` at line 431 (`controller: _csvController`).
2. Delete the `autofocus: true,` line (line 433). Do not change `controller`, `maxLines`, `minLines`, `style`, or any part of `decoration` — those are all still correctly driven by the existing `keyboardHeight` conditionals and must remain exactly as they are.
3. Do not touch any other `TextField` in this file (the five per-row `_TableTextField` instances do not have `autofocus` and must remain untouched).

### Task 2 — `flutter analyze`
Ensure `0 errors` before handing off to QA.

### Task 3 (verification only, no code change expected)
Confirm via the running app (or a widget test, per QA's judgment) that on first opening the Bulk Entry modal, on a platform with an on-screen keyboard (iOS simulator/device, or Android emulator/device if available), the instructional intro line, the bordered column-order/example/required-optional info box, and the full-size (`minLines: 3`, normal padding) paste field are all visible before any tap into the field — i.e., `keyboardHeight == 0` holds on first render because nothing auto-triggers the keyboard anymore.

---

## Verification Plan

No database migration or backend change is involved. Tier 1/Tier 2 is adapted to a client-side-only change, consistent with the sibling `bulk-import-flexible-columns` plan's precedent.

### Tier 1 — Pre-deployment (before merge)

- **PRE-DEPLOY TEST 1:** Open the Bulk Entry modal on iOS (simulator or device). Confirm the intro line ("Paste songs from a spreadsheet, then tap Load Songs.") and the bordered info box (Column order / Artist, Song, BPM, Tuning, Key / example / Required columns / Optional columns) are both visible immediately on open, with no tap required.
- **PRE-DEPLOY TEST 2:** On the same screen, confirm the paste `TextField` renders at its full size (`minLines: 3` — i.e., visibly multi-line, not collapsed to a single dense row) and with normal (not tightened) content padding, before any interaction.
- **PRE-DEPLOY TEST 3:** Tap into the paste field on iOS. Confirm the on-screen keyboard opens as expected (this is now a deliberate result of the tap, not automatic), and confirm the existing keyboard-open collapse behavior still engages correctly at that point (instructional block hides, field shrinks to `minLines: 1`/dense padding, "Done" keyboard toolbar appears) — this is the pre-existing, already-QA-verified behavior from `bulk-import-flexible-columns` and must be unchanged.
- **PRE-DEPLOY TEST 4:** Tap "Done" on the keyboard toolbar (or otherwise dismiss the keyboard). Confirm the instructional block and full-size field reappear — i.e., the collapse is reversible, matching pre-existing behavior.
- **PRE-DEPLOY TEST 5 (regression, functional):** Paste a valid multi-row CSV/TSV block into the field and tap "Load Songs." Confirm songs load into the editable table exactly as before — this fix does not touch `_handleCsvIngestion()`, `BulkSongParser`, or any parsing logic, so no behavior change is expected here; this test exists purely to confirm no incidental breakage.
- **PRE-DEPLOY TEST 6 (web, no-regression check):** Open the Bulk Entry modal on web (desktop). Confirm the instructional block and full-size field are still visible on open (same as before this fix — web never auto-triggered a keyboard, so this should be visually unchanged), and confirm the only difference from before is that the field is no longer pre-focused (user must click into it before pasting/typing).
- **PRE-DEPLOY TEST 7 (Android, best-effort):** If an Android emulator/device is available, repeat Tests 1–4 there. The Feature Input marks Android as "unknown," and this plan's root-cause analysis predicts Android was very likely affected by the same mechanism and is very likely fixed by the same change — but this is not independently confirmed by the Feature Input, so treat this as a bonus check, not a blocking requirement, if no Android device is available in the Engineer/QA session.

### Tier 2 — Post-deployment (after merge, in the running app)

- **POST-DEPLOY TEST 1:** On a real iOS device (not just simulator), open the Bulk Entry modal and confirm the same visual result as Tier 1 Tests 1–2 — instructional content and full-size field visible on open, with no tap required.
- No production data verification query applies — this is a pure UI/focus-behavior fix with no data written or read differently.

### SQL test authoring rules

Not applicable — no SQL is introduced or modified by this plan.

---

## QA Regression Areas

QA must specifically test:
1. **Primary requirement:** on iOS, the instructional intro line and the bordered info box are both visible immediately when the Bulk Entry modal opens, with no tap/interaction required.
2. **Primary requirement:** on iOS, the paste field renders at full size (`minLines: 3`, normal padding) on open, not collapsed.
3. **No regression:** the keyboard-open collapse behavior (instructional block hides, field shrinks, "Done" toolbar appears) from `bulk-import-flexible-columns` still functions correctly once the user deliberately taps into the field — this fix must not silently disable that prior, QA-verified overflow protection.
4. **No regression:** CSV/TSV parsing, row population, and "Load Songs"/"Add Songs" submission flow are unaffected (this fix does not touch `bulk_song_parser.dart`, `bulk_song_row.dart`, or `setlist_repository.dart`).
5. **No regression:** web (desktop) still shows the instructional content and full-size field on open, matching its pre-fix appearance (the only expected difference is loss of pre-focus, which QA should confirm is the only behavior change on web).
6. **Cross-platform, best-effort:** Android and macOS, if a device/emulator is available — confirm the modal is not broken and, ideally, confirm the same fix (no premature collapse) applies there too.

---

## Rollout / Migration Strategy

Not applicable — pure client-side widget-property change, no backend deploy, no migration, no feature flag. Standard release per `docs/agents/OPERATING_MODEL.md`'s deployment protocol.

---

## Out of Scope

Explicitly excluded from this change:
1. **Any change to the `keyboardHeight`-based collapse logic itself** (the `if (keyboardHeight == 0)` gating, `minLines`, `isDense`, `contentPadding` conditionals) — that logic is correct, intentional, and already QA-verified by the prior `bulk-import-flexible-columns` ticket for its actual purpose (preventing overflow when the user deliberately opens the keyboard). This plan only removes the spurious trigger (`autofocus`) that fired it prematurely.
2. **Any change to `bulk_song_parser.dart`, `bulk_song_row.dart`, or `setlist_repository.dart`** — not implicated in this bug; diagnosis is confined entirely to `bulk_entry_screen.dart`'s focus/layout behavior.
3. **A platform-conditional (`kIsWeb`/`Platform.isIOS`) alternative fix** (e.g., autofocus only on web) — rejected in favor of the simpler, uniform fix (removing autofocus everywhere), which achieves the same result without introducing platform branching, per Guardrails §3's caution against blurring/multiplying platform-specific code paths and the "smallest change" principle.
4. **Restoring pre-focus via a delayed/deferred `FocusScope.requestFocus()` after first frame** — considered and rejected: this would still open the keyboard automatically shortly after the modal appears (just delayed by one frame), which would still hide the instructional content almost immediately and defeat the purpose of this fix; it also adds a `WidgetsBinding.addPostFrameCallback` and additional state for no real benefit over simply not auto-focusing.
5. **Independent confirmation of the Android-affected status** — this plan predicts (root cause is platform-agnostic, same shared widget) but does not require confirming Android was broken before proceeding; Tier 1 Test 7 is best-effort only.

---

**Architect Signature:** Plan complete. Ready for Engineer implementation.

---
---

## Addendum — 2026-07-28 — Bottom Sheet Glitch on Manual Tap

### Context for This Addendum

The original fix above (removing `autofocus: true`) is confirmed working and is **not reverted or modified** by this addendum. QA's `APPROVED` verdict is superseded: QA disclosed it could not get reliable interactive tap-testing working in the Simulator (Tier 1 Tests 3–4 were code-path-analysis only) and rated that gap LOW risk. Tony then manually tap-tested on a real iPhone 17 Simulator (iOS 26.4) and found that gap was hiding a real, distinct bug:

> Tapping into the (now-unfocused) paste `TextField` for the first time causes a glitchy bottom-sheet-like flash that covers the field momentarily and then resets — the field cannot be focused, so pasting is impossible.

### Root Cause

**Confidence: HIGH — confirmed by direct read of the current file, applying documented Flutter framework mechanics to the exact code structure. Not independently confirmed via an interactive on-device debugger/print trace — the same Simulator UI-automation limitation Engineer and QA both disclosed in their reports applies here too; see Verification Plan Addendum below for the runtime check that should close this.**

`bulk_entry_screen.dart`, `build()` (current line numbers, post-autofocus-removal):

1. Line 367: `if (keyboardHeight == 0) ...[ <Text>, <SizedBox>, <Container info-box>, <SizedBox> ]` — a **collection-`if`** inside the `Column`'s `children` list. When `keyboardHeight` crosses between `0` and `>0`, this adds or removes exactly four widgets *before* the paste `TextField` in that list.
2. Line 431: `TextField(controller: _csvController, ...)` — **this widget has no `Key`.**
3. Line 474: `if (keyboardHeight == 0) const SizedBox(height: Spacing.space8)` — one more conditional sibling *immediately after* the `TextField`, also gated on the same condition.

**Why this destroys focus, per Flutter's documented `Element.updateChildren` reconciliation algorithm** (used by `Column`/`MultiChildRenderObjectWidget` to diff old vs. new children lists):
- The algorithm matches children from the front while `(oldChild.runtimeType, oldChild.key) == (newChild.runtimeType, newChild.key)`, then matches from the back the same way, then resolves the remaining "middle" region using a map keyed **only by children that have a non-null `Key`**.
- When `keyboardHeight` flips (either direction), the old list's first child (`Text`, when expanding→collapsing) and the new list's first child (`TextField`) have different `runtimeType`s, so **forward matching fails at position 0** — it never gets a chance to match the `TextField` positionally.
- Backward matching successfully matches the trailing invariant widgets (the "Load Songs" button, the ingestion-summary text if present), but the `TextField` always falls into the unmatched **middle region** on one side or the other.
- Because the `TextField` has no `Key`, it is never inserted into (or looked up from) the middle-region key map. The old `TextField` element is deactivated/disposed; the new `TextField` widget gets a **brand-new element created from scratch**.
- The `TextField` does not pass an explicit `focusNode:` (unlike every `_TableTextField` cell, which does). Its focus is held by an **internally-created, implicit `FocusNode`** owned by the old `TextField`'s `EditableText` state. Disposing that element destroys that implicit `FocusNode` and its focus state along with it.

**The resulting sequence on a real device/Simulator tap:**
1. User taps the field → focus is requested → the OS keyboard begins its animated show transition. iOS reports intermediate keyboard-frame metrics during this animation, so `MediaQuery.viewInsets.bottom` — and therefore `keyboardHeight` — increases across several rebuilds, not in one jump.
2. On the first rebuild where `keyboardHeight > 0` (even fractionally, well before the keyboard is fully up), the collection-`if` removes the four preceding widgets and the trailing spacer. The `TextField`'s position in the children list shifts. Per the mechanism above, its element is destroyed and recreated **unfocused**.
3. Because the field is no longer focused, the OS begins **dismissing** the keyboard it had just started showing.
4. As `viewInsets.bottom` falls back toward `0`, the reverse rebuild fires: the four widgets reappear, the `TextField` shifts position again, and it is recreated again — still unfocused, since nothing in the current code re-requests focus.
5. The net visible effect — a keyboard/panel starting to rise, the instructional block and field abruptly snapping in size (non-animated, unlike the smoothly-animating keyboard inset), and everything reversing within a fraction of a second — is what a user, without visibility into the widget tree, reasonably describes as "a glitchy bottom sheet that appears, covers the field, then resets." **No such distinct sheet/overlay widget exists anywhere in this code path** (confirmed — see "What Is Actually Appearing," below). The end state is the field sitting unfocused, so pasting is impossible.

**Why this exact mechanism also explains why it was never seen before this session:** with `autofocus: true` still present (pre-fix), every time the `TextField` was recreated by this same mechanism, the *new* `TextField` widget instance still carried `autofocus: true`. Flutter's autofocus logic re-requests focus on a newly-mounted element that isn't already focused, so the field immediately refocused itself after each destructive recreation. Given `autofocus` fires on `initState`/first frame, this loop played out automatically during the very first frames of the screen's life, before the user had done anything — and it self-stabilized into a **"collapsed layout + focused, functional field"** end state, because the last recreation in the loop was always immediately followed by an autofocus-driven refocus. That end state is exactly what the *original* bug report described (undersized field, missing instructions — but the field itself worked once you started typing). It was never reported as "can't focus/paste," because with autofocus present, it always ended up focused. Removing `autofocus` (the correct fix for the original bug) removed the one thing that was silently absorbing this pre-existing defect. **The autofocus removal did not create this bug — it removed the accidental workaround that had been masking it.**

### Answering the Investigation Questions Directly

- **Is this a pre-existing bug in the modal/sheet presentation chain (`showGeneralDialog` in `add_to_setlist_overlay.dart`)?** No. Re-read in full for this addendum: `_AddToSetlistOverlay` and `_EditSpecialItemOverlay` contain no autofocus, no focus-management, no `showModalBottomSheet`/`showCupertinoModalPopup`/`showBottomSheet` calls, and no widget that could independently produce a "bottom sheet" appearance. The `Material` → `SafeArea` → fixed-margin `Container` chain there does not react to `viewInsets.bottom` at all (Flutter's `SafeArea` consumes static `MediaQuery.padding`, not the keyboard's `viewInsets`), so the outer dialog card's size is unaffected by the keyboard. This file is confirmed uninvolved and does not need to change.
- **What "bottom sheet" is actually appearing?** Nothing literal. A repo-wide grep for `showModalBottomSheet`, `showCupertinoModalPopup`, `showBottomSheet`, and `BottomSheet` confirms dozens of legitimate bottom sheets exist elsewhere in the app (financials, calendar, gigs, contacts, setlist pickers, etc.) but **none are reachable from, or referenced by, `bulk_entry_screen.dart` or `add_to_setlist_overlay.dart`.** What the user is perceiving as a "bottom sheet" is the combination of (a) the OS on-screen keyboard's own animated rise, starting and then immediately reversing, plus (b) this screen's own non-animated, binary layout collapse (the instructional block vanishing, the `TextField` shrinking, and the keyboard toolbar bar — `_buildKeyboardToolbar()`, line 739, which does have its own background color and top border and could itself read as a small "sheet" — flashing in and out) happening out of sync with that keyboard animation. The mismatch between one smoothly-animating value (`viewInsets.bottom`, driving the footer's padding) and several instantly-snapping conditional widgets driven by the same value is what produces the "glitchy, appears-then-resets" visual.
- **Is this a genuine interaction between the fix and something else, or a pre-existing bug simply never exposed?** Both, precisely: the *defect* (unkeyed `TextField` positioned after conditionally-rendered siblings) is pre-existing, dating to the same `bulk-import-flexible-columns` commit (`f3e400c`) that introduced the `if (keyboardHeight == 0)` gating already documented in this plan's original Root Cause section. It was never exposed as a focus-loss bug because `autofocus: true` was independently re-triggering focus on every recreation. The autofocus-removal fix is what stopped masking it.

### Database Impact

**Not applicable.** No schema, RLS, RPC, or repository code is touched by this addendum's diagnosis or its proposed fix.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's paste-field focus behavior. No parsing, validation, or persistence behavior implicated. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS confirmed broken** (Tony's manual test). **Android very likely affected** — same shared widget, same platform-agnostic mechanism (any platform with an animated on-screen keyboard triggers the same element-recreation sequence); not independently confirmed, same as the original plan's Android caveat. **Web/macOS: very likely unaffected in practice** — no software keyboard animates in on desktop/web, so `keyboardHeight` never transitions through intermediate frames the way it does with an on-screen keyboard; QA's prior Flutter-web pass (Tier 1 Test 6) is still valid evidence here, though it did not specifically test rapid focus/unfocus cycling. |

### Regression Risk of the Additional Fix

**LEVEL: LOW**

Rationale:
- The recommended fix (below) is a single `Key` addition to a widget already in the one file this plan already has full authorization to modify. It adds no lines of logic, no new conditionals, no new state.
- It does not touch, weaken, or otherwise modify the `keyboardHeight`-based collapse logic itself (the `if` gating, `minLines`, `isDense`, `contentPadding` conditionals) — all of that remains completely intact and Out-of-Scope Item 1 from the original plan still holds.
- It is the textbook, minimal, well-established Flutter idiom for this exact class of problem (an unkeyed stateful widget whose position in a children list can change) — not a novel abstraction or workaround.

### Proposed Solution (Addendum)

Add a stable, explicit `Key` to the paste `TextField` (line 431) — e.g. `const ValueKey('bulk-entry-csv-field')` (or a `GlobalKey`, either is sufficient; `ValueKey` is preferred as the smaller, non-`State`-coupled option). With a `Key` present, Flutter's middle-region reconciliation can look the old element up by key regardless of how many preceding/following conditional siblings are present or absent, so the same element (and its implicit `FocusNode`/focus state) is reused across every `keyboardHeight` transition instead of being destroyed and recreated.

**Why this is the correct, minimal, root-cause fix (not a workaround):** it directly addresses the actual defect identified above (element identity loss due to positional reordering of an unkeyed widget), rather than papering over the symptom (e.g., re-adding `autofocus`, which would only resurrect the original bug this branch already fixed; or wrapping the collapse in `Visibility`/`Offstage` instead of a collection-`if`, which would also solve it but is a larger, riskier change than adding one `Key` and is not necessary here since none of the *other* conditionally-shown widgets — `Text`, `SizedBox`, `Container` — hold any state worth preserving).

**Alternative considered and rejected:** passing an explicit, instance-held `FocusNode` to the `TextField` (matching the pattern already used by `_TableTextField`/row cells) instead of a `Key`. Rejected because it does not, on its own, guarantee the underlying `EditableText`/element's focus survives a full element disposal-and-recreation cycle the way a `Key` does — it would require additional verification of engine-level focus-node re-attachment behavior across element disposal, which is a larger and less certain change than the single-line `Key` fix. Not pursued further given the smallest-safe-change principle.

### Revised / Additional Engineer Tasks

Execute in order, after (not replacing) the original Task 1–3 already completed:

**Task A — Add a `Key` to the paste `TextField`**
1. In `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, locate the `TextField` at line 431 (`controller: _csvController`).
2. Add `key: const ValueKey('bulk-entry-csv-field'),` as the first named argument (or immediately after `controller:`).
3. Do not change `controller`, `maxLines`, `minLines`, `style`, `decoration`, or any other property. Do not touch the `keyboardHeight`-based conditionals anywhere in this file.
4. Do not add a `Key` to any other widget in the file (the surrounding `Text`/`SizedBox`/`Container` instructional widgets and the `_TableTextField` row cells hold no state and do not need one).

**Task B — `flutter analyze`**
Ensure `0 errors` before handing back to QA.

**Task C (verification only, no further code change expected)**
On the iOS Simulator (or a real device), starting from the field unfocused (current post-fix default):
1. Tap into the paste field. Confirm the keyboard rises smoothly with **no flicker, no flash of a panel/sheet, and no reset** — a single clean transition from expanded→collapsed layout.
2. Confirm the field **remains focused** and accepts typed or pasted text.
3. Tap "Done" on the keyboard toolbar. Confirm the keyboard dismisses cleanly and the instructional block/full-size field reappear.
4. **Repeat steps 1–3 two or three times in the same session.** This repeatability check specifically targets the hypothesis that *every* `keyboardHeight` crossing was destructive, not just the first — a fix that only appears to work on the first tap but degrades on subsequent cycles would indicate the root cause was misdiagnosed.

### Verification Plan Addendum

These tests supplement (do not replace) the seven Tier 1 tests already in this plan.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 8:** Tap into the previously-unfocusable paste field. Confirm focus is acquired and holds — no automatic loss of focus, no visual flicker/reset of the surrounding layout.
- **PRE-DEPLOY TEST 9:** With the field focused and keyboard open, type or paste a short string. Confirm it appears correctly and is retained (proves the fix didn't just stabilize focus while silently discarding input).
- **PRE-DEPLOY TEST 10:** Dismiss the keyboard via "Done," then re-tap the field. Repeat this focus/dismiss cycle at least twice more. Confirm the field remains reliably focusable on every cycle, not just the first.
- **PRE-DEPLOY TEST 11 (Android, best-effort):** If an Android emulator/device is available, repeat Tests 8–10 there, consistent with the original plan's Test 7 best-effort posture for Android.
- **PRE-DEPLOY TEST 5 (existing, re-run):** Paste a valid multi-row CSV/TSV block and tap "Load Songs," this time via the newly-fixed tap-to-focus path rather than autofocus. Confirm songs load into the table exactly as before.

**Tier 2 — Post-deployment (after merge, in the running app):**
- **POST-DEPLOY TEST 2 (new):** On a real iOS device, repeat Tests 8–10 above under genuine touch input. Given that this entire bug was invisible to code-path analysis and only surfaced under real interactive tap-testing, this test carries the primary verification burden and should not be waived in favor of screenshot/code-path analysis alone.

### QA Regression Areas Addendum

QA must specifically re-test, this time with **real interactive tap input** rather than code-path analysis or a coordinate-automation approach that both Engineer and QA already found unreliable in this environment:
1. The paste field can be tapped into, focused, and typed/pasted into — repeatedly, across multiple focus/dismiss cycles — with no flicker, flash, or focus loss.
2. The existing keyboard-open collapse/reversibility behavior (Tier 1 Tests 3–4 from the original plan) still functions correctly once focus is reliably held — this addendum's fix should make these tests *newly possible* to runtime-confirm, closing the gap QA flagged as a Warning in its report.
3. No regression to CSV/TSV parsing, row population, or submission (unaffected by this change; confirmed by Task A's scope being limited to a single `Key` addition).
4. If a proper touch-automation harness (e.g., `idb`) is available or can be stood up per QA's own suggestion, use it here — this is precisely the kind of test that ad hoc desktop-coordinate scripting could not reliably perform for either the Engineer or QA in the original session.

### Files to Modify (Addendum)

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Add `key: const ValueKey('bulk-entry-csv-field'),` to the paste `TextField` (line 431). No other change. |

No files outside this single, already-authorized file are implicated. `add_to_setlist_overlay.dart` was read in full for this addendum and confirmed uninvolved — it remains off-limits and unmodified, consistent with the original plan.

### Out of Scope (Addendum)

1. Any change to the `keyboardHeight`-based collapse logic itself — unchanged, per the original plan's Out of Scope Item 1.
2. Re-adding `autofocus` in any form — would resurrect the original, already-fixed bug.
3. Converting the collection-`if` blocks to `Visibility`/`Offstage` — would also solve this defect but is a larger change than necessary; not pursued given a single `Key` addition is sufficient and smaller.
4. Adding `Key`s to the stateless instructional widgets (`Text`, `SizedBox`, `Container`) — they hold no state, so their recreation is harmless and out of scope.

---

**Architect Signature (Addendum):** Diagnosis complete. Root cause confidence HIGH (code + Flutter framework mechanics), not independently runtime-confirmed via interactive tap in this session — Engineer/QA should close that gap per Task C and the Verification Plan Addendum above. No scope expansion beyond the already-authorized file. Ready for Engineer implementation of Task A.

---
---

## Addendum 2 — 2026-07-28 — Key Fix Did Not Resolve the Bug

### Context for This Addendum

Tony applied Addendum 1's fix (`key: const ValueKey('bulk-entry-csv-field')` on the paste `TextField`) and tested on a real iPhone 17 Simulator, with a **full app stop/restart** (not hot reload — ruling out a stale-build explanation). Result: **identical bug, reproducing on every single tap** — the same glitchy panel covers the field, then resets, and the field cannot be focused. The `Key` fix did not resolve it.

Confirmed via `git diff` at the start of this session: the working tree exactly matches what `ENGINEER_REPORT.md` describes — `autofocus: true` removed, `key: const ValueKey('bulk-entry-csv-field')` added to the paste `TextField`, plus the two out-of-plan cosmetic tweaks (info-box border removed, field fill/border made more prominent). Nothing has drifted since QA's last pass.

**Addendum 1's root-cause diagnosis is treated as disproven by controlled testing, not merely unconfirmed.** Its HIGH confidence rating was built entirely from applying Flutter's documented `Element.updateChildren` reconciliation mechanics to two files, in isolation, without a device signal. That specific reasoning is re-examined below — and, on its own terms, it does not actually explain why the fix failed. This addendum widens the investigation substantially rather than re-deriving the same theory with more confidence-language.

### Re-Examining the Key Fix's Own Mechanism

Re-applying `Element.updateChildren`'s forward/backward/middle-region matching to the **current** inner `Column` (`build()`, lines 364–514) confirms the fix's logic is internally sound as far as it goes:

- Forward matching fails at position 0 when the instructional block appears/disappears (`Text` vs the keyed `TextField` are different `runtimeType`s).
- Backward matching succeeds only for the trailing "Load Songs" button (`SizedBox`, unkeyed, same on both sides), then stops at the next pair inward because one side is a spacer `SizedBox` and the other is the keyed `TextField`.
- The keyed `TextField` therefore always falls into the **middle region**, and — because it now carries `key: const ValueKey('bulk-entry-csv-field')` — the middle-region key-map lookup **should** find and reuse the old element on every `keyboardHeight` transition, preserving its implicit `FocusNode` and focus state.

This mechanism, read in isolation, still checks out. Its failure on a real device is strong evidence that **the unkeyed-sibling-reordering theory was not the actual cause (or not the only cause)** of the reported symptom — not that the fix was implemented incorrectly. The Engineer Report and `git diff` confirm the `Key` was added exactly as specified. The investigation was therefore widened well beyond the inner `Column` and beyond `bulk_entry_screen.dart`'s two previously-examined files.

### Widened Investigation

#### 1. New in-scope defect found: unkeyed `Container` identity collision between `_buildKeyboardToolbar()` and `_buildFooter()`

Addendum 1 noted `_buildKeyboardToolbar()` "could itself read as a small sheet" but dismissed it in passing without applying the same reconciliation analysis used elsewhere in that addendum. Doing so now, at the **outer** `Column` (`build()`, lines 355–538):

```
children: [
  Padding(...),                                    // always present
  if (_hasLoadedSongs) [...] else Expanded(...),   // stable across keyboard toggle
  if (keyboardHeight > 0) _buildKeyboardToolbar(),  // Container, line 737 — NO KEY
  _buildFooter(hasValid, validCount),                // Container, line 785 — NO KEY
]
```

`_buildKeyboardToolbar()` returns a `Container` (line 737). `_buildFooter()` returns a `Container` (line 785). Both are unkeyed. `Widget.canUpdate` matches on `runtimeType` + `key` only — it has no knowledge of what's *inside* a `Container`. So when `keyboardHeight` flips from `0` to `>0`:

- Forward matching succeeds through `Padding` and the `_hasLoadedSongs` branch (both stable).
- At the next position, old = `FooterContainer`, new = `ToolbarContainer`. **Both are bare `Container`s with no key — `Widget.canUpdate` returns `true`.** Flutter treats them as the *same* element and updates the old Footer's element in place with the Toolbar's configuration (a completely different subtree: a right-aligned "Done" button vs. the Submit/Cancel buttons). A brand-new element is then mounted for the real Footer at the new trailing position.
- On the reverse transition (keyboard closes), the same collision happens again in the opposite direction, and the *other* element gets discarded.

This is a real, confirmed-by-the-algorithm defect, distinct from and in addition to the inner-`Column` issue Addendum 1 already fixed. It is exactly the kind of thing a user with no visibility into the widget tree would describe as **"a panel appears near the bottom, covers something, then resets"** — because two structurally different bottom-docked bars (Toolbar-with-Done vs. Footer-with-Submit/Cancel) are being crammed through the same recycled element on every keyboard transition, out of sync with the keyboard's own smooth animation. This does not, on its own, explain focus *loss* on the `TextField` (neither `Container` holds a `FocusNode`), but it is a genuine defect in the exact "direct ancestor chain" scope already authorized, and is fixed below regardless of whether it turns out to be the primary cause of the reported symptom.

#### 2. Investigated and not implicated

- **`add_to_setlist_overlay.dart` re-read in full again.** No `FocusScope`, `FocusTraversalGroup`, or route-level focus handling beyond what `ModalRoute`/`RawDialogRoute` provides by default for every dialog in the app (not specific to this bug). `showGeneralDialog`'s `barrierDismissible: true` `ModalBarrier` sits *behind* the dialog card and only intercepts taps outside it — it cannot intercept a tap that lands inside the CSV field. `AnimatedSwitcher` (line 212) keeps the same `ValueKey('bulk-entry')` on `BulkEntryScreen` for as long as the user stays in the Bulk Entry step, so even if this ancestor's `build()` re-runs for unrelated reasons, `AnimatedSwitcher` performs an in-place update, not a teardown/rebuild of `BulkEntryScreen`'s `State` — this does not disturb the `TextField`'s focus.
- **Per-row `FocusNode`s / `_focusedRowIndex` tracking** (lines 164–177): not mounted until after songs are loaded into the table; not reachable on the first tap into an empty CSV field, which is what Tony's report describes.
- **Explicit `unfocus()`/`requestFocus()` calls in `bulk_entry_screen.dart`:** grepped and read every call site (`_handleCsvIngestion`'s empty-text branch, `_populateTableFromParseResult`, `_dismissKeyboard`). None of them run merely from tapping into the CSV field — they all require either "Load Songs," a tap on the toolbar's "Done" button, or a tap on the loaded-table's dismiss-on-drag region. None is a candidate for "can't focus on tap."
- **iOS QuickType/predictive-text suggestion bar:** the `TextField` sets no `autocorrect`, `enableSuggestions`, or `keyboardType`, so OS defaults apply (autocorrect + suggestions on; `keyboardType` defaults to `TextInputType.multiline` because `maxLines: 5 ≠ 1`). This is a plausible contributor to a flickering *native* panel above the keyboard, but doesn't independently explain focus rejection. Not ruled out — see Task C below, which tests it directly and cheaply rather than theorizing further.

#### 3. Strongest new lead — outside the two currently-authorized files: `lib/shared/widgets/keyboard_aware_wrapper.dart`

This file is applied globally via `MaterialApp.builder` (`lib/main.dart`, confirmed by direct read) and wraps **every route, dialog, and bottom sheet in the entire app**, including this one. It was not examined in either prior session. Reading it in full surfaced a mechanism confirmed directly against the installed Flutter SDK source (Flutter 3.44.6, `packages/flutter/lib/src/widgets/editable_text.dart` and `scrollable.dart` — not speculation about framework internals):

- `_KeyboardAwareWrapperState.didChangeMetrics()` fires on **every** change to screen metrics, which includes **every intermediate frame** of the iOS keyboard's animated show/hide transition (this is the same "many rebuilds during one keyboard animation" fact Addendum 1 already established for `MediaQuery.viewInsets.bottom`). Each call schedules a post-frame callback that runs `_updateKeyboardState()` and then **unconditionally** `_scrollFocusedFieldIntoView()`.
- `_scrollFocusedFieldIntoView()` calls `Scrollable.ensureVisible(FocusManager.instance.primaryFocus?.context, duration: 250ms, curve: easeOut, alignment: 0.5)` — with no check for what kind of widget currently holds focus, and no debouncing across the many metrics-change ticks that fire during a single keyboard animation.
- `Scrollable.ensureVisible` (Flutter SDK, `scrollable.dart`, confirmed by direct read) walks **every** ancestor `Scrollable` starting from the nearest one outward, animating each in turn.
- **`EditableText` — the implementation underlying every `TextField`, including this CSV field — wraps its own content in its own internal `Scrollable`** (confirmed at `editable_text.dart`: `Scrollable(key: _scrollableKey, controller: _scrollController, axisDirection: _isMultiline ? AxisDirection.down : AxisDirection.right, ...)`), used for scrolling within the field when its content overflows `maxLines`. Because this field is multi-line (`maxLines: 5`), this internal `Scrollable` is real and active, not a single-line no-op case.

Put together: **every single metrics tick during the keyboard's animated appearance calls `Scrollable.ensureVisible` against whatever the CSV field's `FocusNode.context` resolves to — which is inside the field's own internal `Scrollable` — restarting a new 250ms ease-out scroll animation on the field's own internal viewport, repeatedly, for the duration of the keyboard's rise.** This is a genuinely different, previously-unexamined mechanism from the widget-identity theory, it is **app-wide, not local to this screen**, and it plausibly explains the symptom far better than the disproven theory did:

- It fires on **every tap**, not just the first — matching Tony's "reproducing on every single tap" report, because it's keyed to the keyboard's metrics animation, which runs identically every time the keyboard is summoned, not to a one-time element-identity glitch.
- It targets the exact widget in question, on the exact frames during which the user is trying to interact with it.
- Repeated, restarted 250ms animations on the field's own internal scroll offset, layered on top of the field's own `minLines`/`isDense`/`contentPadding` snapping between states, is a plausible visual match for "a glitchy panel that appears, covers the field, and resets."

**This is presented as the strongest current hypothesis, not a confirmed root cause.** I did not find a line in `keyboard_aware_wrapper.dart` that explicitly rejects or steals focus outright — the mechanism I found is a scroll-animation storm targeting the field's own viewport, and I have not runtime-confirmed that this specific mechanism is sufficient to produce "cannot be focused" as opposed to "visually glitches while remaining usable." Per this session's explicit instruction not to close on code-path confidence alone — even when the reasoning is this concrete and SDK-verified — this is a lead to be confirmed by instrumentation and Tony's direct observation, not a diagnosis to implement blind.

### Root Cause

**Confidence: LOW — diagnostic-first plan required, not another speculative fix.**

Two consecutive HIGH-confidence, code-path-only diagnoses of this exact widget have now failed real-device verification. The strongest remaining lead (`keyboard_aware_wrapper.dart`'s unconditional, undebounced `Scrollable.ensureVisible` call against a multi-line `TextField`'s own internal scrollable) is well-supported by direct SDK source reading, but it sits **outside the two files this plan currently authorizes** (`bulk_entry_screen.dart`, `add_to_setlist_overlay.dart`), and it has not been confirmed against real device behavior. Declaring HIGH confidence here would repeat exactly the mistake this session was opened to correct.

### Stop-Condition Note — Scope Flag (Read Before Proceeding)

`lib/shared/widgets/keyboard_aware_wrapper.dart` is an **app-wide** mechanism — it wraps every screen, dialog, and bottom sheet in BandRoadie via `MaterialApp.builder`, not just the Bulk Entry modal. If the diagnostic step below confirms this file's `_scrollFocusedFieldIntoView()` is implicated, **a fix there requires separate Manager/Architect authorization before an Engineer touches it** — a change to this file is a change to keyboard behavior for every text field in the app (including the numeric-keyboard "Done" bar logic in the same file), not a localized Bulk Entry fix, and is well outside what this plan's original scope review covered.

This is flagged per this plan's own Stop Conditions rather than silently expanding scope. **It does not block the diagnostic step below**, which is fully containable within the two already-authorized files and will produce the evidence needed to decide whether that scope conversation is necessary at all.

### Files Authorized for This Addendum's Engineer Tasks

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Task A (real fix, keeps) + Task B (temporary diagnostic instrumentation, stripped before final commit) + Task C (temporary controlled experiment, stripped before final commit) |

**Not authorized by this addendum:** `lib/shared/widgets/keyboard_aware_wrapper.dart`. Do not modify it. If diagnostics point to it, stop and report back for scope authorization rather than editing it.

### Engineer Task Breakdown (Addendum 2)

Execute in order, after (not replacing) all prior Task 1–3 / A–C work already completed:

**Task A — Fix the outer-`Column` `Container` identity collision (real fix, keep permanently)**
1. In `_buildKeyboardToolbar()` (line 737), add `key: const ValueKey('bulk-entry-keyboard-toolbar'),` as the `Container`'s first named argument.
2. In `_buildFooter()` (line 785), add `key: const ValueKey('bulk-entry-footer'),` as the `Container`'s first named argument.
3. Do not change anything else in either method — same class of minimal, additive fix as Addendum 1's Task A.

**Task B — Temporary diagnostic instrumentation (must be stripped before this addendum is considered done)**

Mark every line added in this task with a trailing `// TEMP-DEBUG` comment so removal is unambiguous.

1. Add two new `State` fields alongside `_csvController`:
   ```dart
   final FocusNode _csvFocusNode = FocusNode(debugLabel: 'DEBUG-bulk-entry-csv'); // TEMP-DEBUG
   final ScrollController _csvScrollController = ScrollController(debugLabel: 'DEBUG-bulk-entry-csv-scroll'); // TEMP-DEBUG
   ```
2. In `initState()`, register listeners on both:
   ```dart
   _csvFocusNode.addListener(() { // TEMP-DEBUG
     debugPrint('[DEBUG-BULK-ENTRY] focus hasFocus=${_csvFocusNode.hasFocus} '
         'node=${identityHashCode(_csvFocusNode)} time=${DateTime.now().toIso8601String()}');
   }); // TEMP-DEBUG
   _csvScrollController.addListener(() { // TEMP-DEBUG
     debugPrint('[DEBUG-BULK-ENTRY] internal scroll offset=${_csvScrollController.offset} '
         'time=${DateTime.now().toIso8601String()}');
   }); // TEMP-DEBUG
   ```
3. In `dispose()`, add `_csvFocusNode.dispose(); _csvScrollController.dispose();` // TEMP-DEBUG
4. At the very top of `build()`, add:
   ```dart
   debugPrint('[DEBUG-BULK-ENTRY] build() keyboardHeight=$keyboardHeight time=${DateTime.now().toIso8601String()}'); // TEMP-DEBUG
   ```
5. On the CSV `TextField` (line 425), add `focusNode: _csvFocusNode,` and `scrollController: _csvScrollController,` as additional named arguments — do not remove or change `controller`, `key`, `maxLines`, `minLines`, `style`, or `decoration`.
6. Wrap the CSV `TextField` in a temporary bright-bordered `Container` for visual identification:
   ```dart
   Container( // TEMP-DEBUG
     decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 4)), // TEMP-DEBUG
     child: TextField( /* unchanged */ ),
   ), // TEMP-DEBUG
   ```
7. In `_buildKeyboardToolbar()`, temporarily change the `Container`'s `decoration` border to `Border.all(color: Colors.lime, width: 4)` (from the current `Border(top: BorderSide(...))`) so it is visually distinguishable from the red-bordered CSV field and from the (unmodified) Footer. // TEMP-DEBUG

**Task C — Controlled experiment: rule the OS predictive-text bar in or out**

On the same CSV `TextField`, temporarily add `autocorrect: false, enableSuggestions: false,` // TEMP-DEBUG. This is a cheap, directly falsifiable test: if the glitch disappears entirely with these off, the iOS QuickType/predictive-text bar is confirmed as a contributing or sole cause; if it persists identically, this is ruled out.

**Task D — `flutter analyze`**
Ensure `0 errors` with all of Task A–C's changes in place before handing to Tony.

**Task E — Do not attempt automated UI-automation verification again**
Both prior sessions independently found `cliclick`/`screencapture`/coordinate-mapped Simulator automation unreliable for this exact screen, including one incident of an errant `screencapture -R` capturing a window outside the Simulator. Do not re-attempt it a third time. This diagnostic is designed to be run by Tony directly, with real touch input, reading the debug console himself — that is the point of this addendum, not a gap to be routed around.

### Diagnostic Protocol — What Tony Should Do and Report

1. Full stop/restart the app (not hot reload) with Task A–D's changes in place.
2. Open the Bulk Entry modal and tap into the CSV paste field. Reproduce the glitch as before.
3. Report back:
   - **The full console output** of every `[DEBUG-BULK-ENTRY]` line logged from the moment of the tap through the glitch settling (focus transitions, scroll offset changes, build() calls with their `keyboardHeight` values, and timestamps).
   - **Whether the visible glitch panel has a red or lime border** (one of our own instrumented widgets) **or no border at all** (a native OS element outside Flutter's widget tree, e.g. the keyboard's own predictive-text bar).
   - **Whether the glitch still occurs** with Task C's `autocorrect: false, enableSuggestions: false` in place.
   - Repeat for 2–3 tap/dismiss cycles if possible, since Addendum 1's Task C already asked for repeatability and that data is still valuable here.

### What Happens After Tony Reports

This addendum intentionally stops short of prescribing the real fix. Once Tony's console output and observations are in hand:
- If the `[DEBUG-BULK-ENTRY]` scroll-offset log shows repeated `animateTo`-driven offset changes coinciding with the glitch, and/or the glitch disappears when `keyboard_aware_wrapper.dart`'s `_scrollFocusedFieldIntoView` is (hypothetically) not running — this confirms the Section 3 lead, and a follow-up Addendum 3 will be written to design a scoped fix in `keyboard_aware_wrapper.dart`, pending the Manager authorization flagged above.
- If focus (`hasFocus`) logs show the `FocusNode`'s own `identityHashCode` changing (a *new* node being created) rather than just toggling `true`/`false` on the *same* node, that would indicate `State` is still being torn down and recreated somewhere despite Task A/Addendum 1's `Key` fixes — pointing back into `bulk_entry_screen.dart` after all, and requiring a third look at this file specifically.
- If the glitch disappears entirely with `autocorrect`/`enableSuggestions` off (Task C), the fix is a one-line, low-risk, fully in-scope change to `bulk_entry_screen.dart` — no scope expansion needed.
- Regardless of outcome: **all Task B and Task C changes must be stripped from `bulk_entry_screen.dart`** — including every `// TEMP-DEBUG` line, the explicit `FocusNode`/`ScrollController`, the colored border `Container`, and the `autocorrect`/`enableSuggestions` overrides — before this bug can be considered commit-ready. None of this instrumentation ships.

### Out of Scope (Addendum 2)

1. Any code change to `lib/shared/widgets/keyboard_aware_wrapper.dart` — flagged as a live suspect, not authorized for modification by this addendum. Requires separate Manager/Architect sign-off given its app-wide blast radius.
2. Any change to `_buildKeyboardToolbar()`'s or `_buildFooter()`'s actual layout, styling, or animation behavior beyond the two `Key` additions in Task A.
3. Shipping any of Task B's debug instrumentation or Task C's `autocorrect`/`enableSuggestions` experiment as permanent behavior — both must be reverted regardless of what the diagnostic reveals.
4. Re-attempting `cliclick`/`screencapture`-based UI automation for verification — already failed twice, not a productive use of a third attempt (see Task E).
5. Everything already out of scope per Addendum 1 (the `keyboardHeight`-based collapse logic itself, `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, platform-conditional fixes) remains out of scope here too.

---

**Architect Signature (Addendum 2):** Investigation widened well beyond the two files examined by prior sessions. Root cause confidence explicitly **LOW** — the previously-disproven theory is not being replaced with another confident guess. One real, low-risk defect (Task A) is fixed outright regardless of outcome. The strongest remaining lead (`keyboard_aware_wrapper.dart`'s global, undebounced `Scrollable.ensureVisible` call against a multi-line field's own internal scrollable) is well-supported by direct Flutter SDK source verification but sits outside this plan's authorized files and is not implemented blind — per this session's explicit instruction, it is handed to Tony as a concrete, in-scope, instrumented diagnostic step instead. Scope flag raised per Stop Conditions: a fix to `keyboard_aware_wrapper.dart`, if warranted, requires Manager authorization before any Engineer touches it. Ready for Engineer implementation of Tasks A–D; pipeline then pauses for Tony's diagnostic report before any further fix is designed.

---
---

## Addendum 3 — 2026-07-28 — The Diagnostic Instrumentation Itself Reintroduced the Bug It Was Built to Catch

### Context for This Addendum

Tony ran Addendum 2's Task A–D instrumented build with a full app stop/restart on **both a physical iOS device and a physical Android device**, reproducing the glitch on both. Full report (visual observation, console capture, Android log excerpt) is reproduced in this session's task input; key facts extracted below.

**What was observed:**
- A brief flash of the **lime-bordered `Container` from `_buildKeyboardToolbar()`** — confirming the visible glitch is the toolbar itself flashing in/out, not the CSV field, not a native OS panel. This holds even with Addendum 2 Task A's toolbar/footer `Key` fix already in place.
- The iOS console captured six `[DEBUG-BULK-ENTRY] build() keyboardHeight=...` lines within ~90ms, monotonically falling from ~0.092 to `0.0`, each interleaved with a full `CalendarTabContent` rebuild (66 events, 8 this month, six `TimeFormatter` parses) — i.e., the Calendar tab (which the user was nowhere near) rebuilt in lockstep with every `keyboardHeight` tick.
- **Zero** `[DEBUG-BULK-ENTRY] focus hasFocus=...` or `internal scroll offset=...` lines appeared anywhere in the capture, despite Task B wiring `_csvFocusNode`/`_csvScrollController` directly onto the CSV field and Tony reproducing the tap/glitch repeatedly.
- The Android log showed `I/IMM_LC: notifyImeHidden` immediately followed by `InputMethodManager: startInputInner - mService.startInputOrWindowGainedFocus` — an IME hide-then-immediately-restart sequence.

### Root Cause

**Confidence: HIGH on the newly-identified defect itself (directly demonstrable by comparing the current file's structure to Addendum 1's already-verified-sound mechanism — not new speculation about undocumented framework internals). MEDIUM on this fully explaining the entire cross-round history of the bug** (see "What This Does and Does Not Explain," below, for the honest boundary).

**The defect: Addendum 2's own Task B diagnostic wrapper defeated Addendum 1's `Key` fix.**

Before Addendum 2, the CSV field was a direct child of the inner `Column`'s `children` list:
```dart
TextField(
  key: const ValueKey('bulk-entry-csv-field'),
  controller: _csvController,
  ...
)
```
Addendum 2's re-verification of this ("Re-Examining the Key Fix's Own Mechanism," above) correctly confirmed that, at this list position, a `keyboardHeight`-driven reshuffle of preceding siblings still lets the middle-region key lookup find and reuse this exact element — the mechanism is sound **for this specific structure**.

Task B then wrapped that same `TextField` for visual identification (current file, lines 444–500):
```dart
Container(                                          // <-- direct Column child now; NO KEY
  decoration: BoxDecoration(border: Border.all(color: Colors.red, width: 4)),
  child: TextField(
    key: const ValueKey('bulk-entry-csv-field'),     // <-- key is now one level too deep
    controller: _csvController,
    focusNode: _csvFocusNode,
    scrollController: _csvScrollController,
    autocorrect: false,
    enableSuggestions: false,
    ...
  ),
),
```
The widget occupying the Column's list slot changed from `TextField(key: ValueKey(...))` to `Container(key: null)`. Element reconciliation (`Widget.canUpdate`) compares `runtimeType` + `key` **at each direct-child slot of the list being diffed** — it does not look inside a widget to find a key on a grandchild. So the `ValueKey('bulk-entry-csv-field')` that Addendum 1 correctly placed is now invisible to the exact reconciliation pass this plan already relied on to diagnose and fix the original defect.

The practical effect: every time `keyboardHeight` crosses a boundary that changes the preceding collection-`if` (which, per Addendum 1's own already-established fact, happens on **multiple intermediate frames during the keyboard's single animated rise**, not once), forward-matching fails at position 0 exactly as before, the unkeyed `Container` falls into the middle region, has no key to be found by, and gets **discarded and remounted from scratch** — child `TextField` included, regardless of the key on that child, because there is no "old subtree" left to match it against once the parent slot itself is freshly mounted. This tears down and recreates the `TextField`'s `Element` (and therefore its `EditableTextState` and its platform `TextInputConnection`) on every one of those frames.

**This is a genuine, self-inflicted regression introduced by the diagnostic instrumentation itself** — not a new theory about the original bug, but a demonstrable flaw in the tooling built to observe it. It is a textbook case of the observer effect: the debug wrapper added to *see* the field's identity changed the field's identity behavior.

### Why This Explains What Tony Reported (and where the explanation still has an honest gap)

**Explains cleanly:**
- **Zero focus-listener output despite real, repeated glitching:** `_csvFocusNode` is externally owned by `_BulkEntryScreenState` (a persistent field, not owned by the churning `Element`). When a fresh `EditableTextState` attaches to an already-`hasFocus == true` external `FocusNode`, the attachment does not toggle `hasFocus` or fire `addListener` callbacks — only the `Element`/platform connection underneath is being destroyed and recreated, repeatedly, invisibly to the Dart-level focus boolean. This is the one piece of this addendum's reasoning that rests on FocusNode/Element attachment semantics rather than pure list-reconciliation, so it is flagged as the weaker link in the chain (see Verification Plan Addendum, below, which is designed to directly confirm or refute it rather than asserting it outright).
- **The Android IME hide-then-restart log line:** each `TextField` Element teardown closes the platform text input connection (`notifyImeHidden`); each fresh mount reopens one immediately (`startInputInner`) — a direct, mechanical match, not a coincidence.
- **The toolbar still flashing even with Task A's collision fix in place:** Task A fixed *what* gets shown when the toolbar mounts (no more borrowing the footer's subtree) — it did not fix *why* `keyboardHeight` might cross the `>0` boundary repeatedly in a fraction of a second. If closing/reopening the CSV field's input connection causes the OS keyboard to itself flicker (begin dismissing, then get re-summoned), `keyboardHeight` oscillates through `0` multiple times per gesture, and the (now individually correct) toolbar `Container` is inserted and removed on each crossing — which reads as "a flash," even though each individual mount is no longer buggy in isolation.
- **Reproducing identically on every single tap:** this mechanism is structural and re-triggered by any keyboard-driven metrics change, not a one-time race — matching "reproducing on every single tap" rather than being intermittent.

**Honest gap — what this does *not*, by itself, explain:** Tony's *first* real-device failure (the one that prompted Addendum 2 to be written at all) happened **before Task B's wrapper existed** — at that point the CSV field was a bare, correctly-keyed `TextField` with no wrapping `Container`, and Addendum 2's own re-verification of that structure found it sound. That earlier failure is what led Addendum 2 to find the *separate* toolbar/footer collision (now fixed as Task A) and to flag `keyboard_aware_wrapper.dart`'s scroll-storm as the strongest remaining unconfirmed lead. This addendum's finding is therefore additive, not a full retraction: it identifies a real, second, independent way the CSV field's own element identity was being destroyed — one that only existed in *this* diagnostic round, layered on top of whatever was or wasn't already happening in the pre-Task-B round. **The combination "Task A's toolbar/footer keys + a properly-keyed, unwrapped CSV field" has never actually been tested clean on a real device** — every prior round tested it either without Task A (pre-Addendum-2) or with Task A but with Task B's confounding wrapper (this round). That untested-clean combination is what this addendum proposes to ship and verify next, rather than a third layer of speculation.

### Answering the Investigation Questions Directly

- **Why is `_buildKeyboardToolbar()` — not the CSV field — the thing visibly flashing, even after Task A's identity-collision fix?** Task A fixed the toolbar/footer *content* collision. It did not, and structurally could not, fix the *rate* at which `keyboardHeight` crosses the `if (keyboardHeight > 0)` boundary that mounts/unmounts the toolbar. That rate is downstream of the CSV field's own input-connection churn (see above) — a different widget than the one that appears to glitch is driving the value that controls whether the glitching widget exists at all.
- **Why does the CSV field's own `FocusNode` listener never fire?** See "Explains cleanly," first bullet, above — the boolean-valued `hasFocus` on the persistent, externally-owned `FocusNode` most likely never actually toggles across the churn, even though the underlying `Element`/platform connection is being destroyed and recreated repeatedly. Flagged as the one link in this chain not yet independently confirmed; Verification Plan Addendum below is designed to close exactly this gap without adding another unverified assumption on top.
- **Is the `CalendarTabContent` rebuild storm causally relevant or coincidental?** **Confirmed coincidental, not hand-waved.** `lib/features/calendar/calendar_tab_content.dart` (lines 332, 514) calls `MediaQuery.of(context)` directly rather than the narrower `MediaQuery.viewInsetsOf(context)` / `MediaQuery.paddingOf(context)`. Calling the broad `MediaQuery.of(context)` subscribes to the *entire* `MediaQueryData` as an `InheritedWidget` dependency — any change to *any* field (including `viewInsets`, which changes on every frame of the Bulk Entry keyboard's animation) triggers a rebuild, even though `CalendarTabContent` only actually uses `.padding`. Separately, `lib/features/shell/app_shell.dart` (line 138) hosts all four tabs, including `CalendarTabContent`, inside a single `IndexedStack` — `IndexedStack` keeps every child mounted and subscribed to `InheritedWidget`s at all times, painting only the active index, so `CalendarTabContent` stays alive and reactive to `MediaQuery` changes even while the Bulk Entry modal is open on top of a different tab. This is a real, confirmable, pre-existing inefficiency (worth its own follow-up ticket — the fix would be switching to `MediaQuery.paddingOf(context)` in `calendar_tab_content.dart`), but it is a parallel *symptom* of the same app-wide `viewInsets` churn this addendum diagnoses, not a contributor to it, and fixing it would require modifying a file (`calendar_tab_content.dart`) that is unrelated to and unauthorized for this bug. **Not pursued further here — flagged as Out of Scope, below.**
- **`keyboard_aware_wrapper.dart` re-examined in light of this new evidence:** Re-read again. Nothing changes the prior conclusion that it is not authorized for modification. Its relevance is now *lower-priority but not eliminated*: if the clean retest proposed below (Task A's keys + an unwrapped, properly-keyed CSV field, zero instrumentation) still glitches, this file's undebounced, app-wide `Scrollable.ensureVisible` call remains the next and most concrete lead, and should be pursued with Manager authorization at that point — see "If the Clean Retest Still Fails," below. One new, mildly negative data point against it being the *primary* driver of this round's specific symptom: Task B's `_csvScrollController` listener (which would fire on every `Scrollable.ensureVisible`-driven offset change on the CSV field's own internal scroll view, had that mechanism been active and consequential here) also never printed a single line — though this is ambiguous given the field's `Element` was churning throughout the same window, so it is not treated as a confirmed rule-out, only as noted here for completeness.

### Files Authorized for This Addendum's Engineer Tasks

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Task F (strip all Addendum 2 Task B/C diagnostic code, restore the clean single-keyed `TextField`) + Task G (verification only) |

**Not authorized by this addendum:** `lib/shared/widgets/keyboard_aware_wrapper.dart`. Do not modify it. `lib/features/calendar/calendar_tab_content.dart`. Do not modify it — the `MediaQuery.of` inefficiency identified above is real but out of scope for this bug and belongs in its own ticket.

### Proposed Solution (Addendum 3)

**Strip all of Addendum 2's Task B (diagnostic instrumentation) and Task C (autocorrect/enableSuggestions experiment) code from `bulk_entry_screen.dart`, restoring the CSV field to exactly the structure Addendum 1 specified: a single, directly-keyed `TextField` with no wrapping `Container`, no explicit `focusNode`/`scrollController`, and no `autocorrect`/`enableSuggestions` overrides.** Keep Addendum 2 Task A's two permanent `Key` additions (`_buildKeyboardToolbar()`'s and `_buildFooter()`'s `Container`s) — that defect and its fix are independently confirmed and unaffected by this addendum's finding.

**This directly answers the note about the red debug border:** yes, it is safe to remove now, and the removal should not be limited to just the red border — all of Task B/C should come out together, for three reasons: (1) the wrapping `Container` that carries the red border is itself the newly-identified defect, so removing "just the color" while leaving the wrapper would leave the regression in place; (2) the explicit `focusNode`/`scrollController` wiring and the four debug `print` statements have already produced two full rounds of data and, per this session's own instruction, should not simply be re-added a third time without a more targeted hypothesis — continuing to layer instrumentation on a structure just shown to corrupt its own subject is not productive; (3) Tony has directly asked for the border gone, and this addendum's diagnosis gives confidence that its removal is not just cosmetic — it restores the exact structure most likely to actually work.

**Why this is not "another confident guess despite two prior failures":** it does not introduce a new theory of the bug. It removes a demonstrated regression in the *diagnostic scaffolding* and, for the first time, tests the one combination of already-diagnosed, already-fixed defects (Addendum 1's key + Addendum 2 Task A's toolbar/footer keys) that has never actually been run clean on a device. If that clean combination still fails, this addendum does not claim victory in advance — see "If the Clean Retest Still Fails," below, which is the honest next step rather than a silent extension of scope.

### Engineer Task Breakdown (Addendum 3)

Execute in order, after (not replacing) all prior Task 1–3 / A–E work already completed:

**Task F — Strip all Addendum 2 Task B/C diagnostic code (permanent removal)**

In `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`:
1. Remove the `_csvFocusNode` and `_csvScrollController` field declarations (current lines 132–135).
2. Remove both `addListener` registrations for them in `initState()` (current lines 152–162).
3. Remove both `.dispose()` calls for them in `dispose()` (current lines 172–173).
4. Remove the `debugPrint(...)` call at the top of `build()` (current lines 369–370). Do not remove the `final keyboardHeight = ...;` line directly above it — that is original, non-diagnostic code.
5. Replace the entire `Container(... TEMP-DEBUG ...) { child: TextField(...) }` block (current lines 444–500) with a single `TextField`, matching Addendum 1's original specification exactly:
   ```dart
   TextField(
     key: const ValueKey('bulk-entry-csv-field'),
     controller: _csvController,
     maxLines: 5,
     minLines: keyboardHeight > 0 ? 1 : 3,
     style: TextStyle(
       fontSize: AppFontSizes.caption,
       color: context.colors.textPrimary,
       fontFamily: 'monospace',
     ),
     decoration: InputDecoration( /* unchanged from current file */ ),
   ),
   ```
   Do not add `focusNode:`, `scrollController:`, `autocorrect:`, or `enableSuggestions:`. Do not wrap it in a `Container` or any other widget. The `key:`, `controller:`, `maxLines:`, `minLines:`, `style:`, and `decoration:` values themselves are unchanged from the current file — only the diagnostic wrapper and diagnostic-only parameters are removed.
6. In `_buildKeyboardToolbar()` (current lines 766–777), restore the original border and remove the `// TEMP-DEBUG` comment: change `border: Border.all(color: Colors.lime, width: 4)` back to `border: Border(top: BorderSide(color: context.colors.border, width: 1))`. **Do not remove `key: const ValueKey('bulk-entry-keyboard-toolbar')`** — that is Addendum 2 Task A's permanent fix.
7. Confirm `_buildFooter()`'s `key: const ValueKey('bulk-entry-footer')` (current line 818) is untouched — it is permanent, not diagnostic.
8. Grep the file for `TEMP-DEBUG` after these edits — zero matches must remain.

**Task G — `flutter analyze`**
Ensure `0 errors` with Task F's changes in place.

**Task H (verification only, no further code change expected)**
On a real device (iOS and/or Android, matching how Tony reproduced this):
1. Full stop/restart the app (not hot reload).
2. Open the Bulk Entry modal and tap into the CSV paste field.
3. Confirm: no flash of any panel (toolbar, red border, or otherwise), the keyboard rises with a single smooth transition, the field acquires and holds focus, and typed/pasted text is accepted and retained.
4. Repeat 2–3 times in the same session (matching Addendum 1's original repeatability check).
5. Confirm the instructional block / full-size field still appear correctly before the first tap (original bug's fix, unaffected by this addendum).
6. Confirm a full CSV paste → Load Songs → table population cycle still works end to end.

### Verification Plan Addendum (Addendum 3)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 12:** Tap into the CSV field on a real iOS device. Confirm no visual flash/flicker of any kind (toolbar, border, or panel) during the keyboard's rise, and that the field is focused and usable immediately.
- **PRE-DEPLOY TEST 13:** Repeat Test 12 on a real Android device.
- **PRE-DEPLOY TEST 14:** With the field focused, type or paste a short string, then a full multi-row CSV block, then tap "Load Songs." Confirm text is retained and rows populate correctly — this specifically re-confirms functional correctness now that `focusNode`/`scrollController` wiring (diagnostic-only, never functionally required) has been removed.
- **PRE-DEPLOY TEST 15 (the specific gap this addendum targets):** If the glitch is fully gone, this is strong (not certain) confirmation that the Task-B-wrapper-defeats-key theory was the operative mechanism for this round. If the glitch is **reduced but not eliminated**, or **eliminated on iOS but not Android** (or vice versa), report the exact difference — that asymmetry would itself be new evidence pointing more specifically at `keyboard_aware_wrapper.dart` (app-wide, platform-agnostic code) versus something more platform-specific.

**Tier 2 — Post-deployment (after merge):** Same posture as prior addenda — real-device confirmation carries the verification burden here, not code-path analysis.

### If the Clean Retest Still Fails

This addendum does not assume success. If Tony reports the glitch persists even with Task F's clean, unwrapped, fully-keyed build:

1. The remaining live suspect is exactly what Addendum 2 already identified and did not get to test in isolation: `lib/shared/widgets/keyboard_aware_wrapper.dart`'s `_scrollFocusedFieldIntoView()`, called unconditionally and undebounced from `didChangeMetrics()` on every metrics tick, against whatever `FocusManager.instance.primaryFocus?.context` currently resolves to.
2. Per this plan's Stop Conditions (unchanged from Addendum 2): a fix to that file requires **Manager/Architect authorization** before an Engineer touches it, given its app-wide blast radius (every text field in every screen, not just Bulk Entry).
3. The next diagnostic, if authorized, should be more targeted than Task B/C were: rather than adding more `debugPrint` instrumentation to `bulk_entry_screen.dart` (already tried twice), the more direct test is temporarily neutralizing `_scrollFocusedFieldIntoView()`'s effect at its source (e.g., gating the call behind a debug flag inside `keyboard_aware_wrapper.dart` itself, or temporarily commenting out just that one call) and having Tony re-test with that single mechanism disabled — a controlled, falsifiable, single-variable experiment, rather than another round of print statements layered onto the already-twice-instrumented Bulk Entry screen. This is described here for planning purposes only; it is **not authorized to be implemented in this session** and would require its own Manager sign-off and, likely, its own brief addendum scoped specifically to that file.

### Regression Risk

**LEVEL: LOW**

Rationale:
- Task F is a net *removal* of code (diagnostic-only, never functionally load-bearing) plus a restoration to a structure (Addendum 1's originally-specified, already-analyzed `TextField`) that has already been reasoned through twice in this plan.
- Task A's toolbar/footer keys (kept, not touched by this addendum) remain a real, independent, low-risk, additive fix.
- No auth, session, routing, database, or repository changes. No change to `keyboardHeight`-based collapse logic. No change to `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, or `add_to_setlist_overlay.dart`.
- The only way this could regress something is if the diagnostic `focusNode`/`scrollController` wiring had accidentally become functionally load-bearing — it has not: those parameters were added purely for observability in Addendum 2 and are not referenced by `_handleCsvIngestion()`, `_populateTableFromParseResult()`, or any submission path, all of which operate on `_csvController.text` directly.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's paste-field focus/visual-stability behavior. No parsing, validation, or persistence behavior implicated. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS and Android both confirmed broken** in this round (Tony's dual-platform test). This addendum's fix is platform-agnostic (removes a Dart-level reconciliation defect, not a platform-specific code path), so it is expected to affect both identically. Web/macOS: unaffected in practice, consistent with all prior addenda (no software keyboard animates in on desktop/web, so the intermediate-frame churn this addendum addresses does not occur there). |

### QA Regression Areas Addendum (Addendum 3)

Once Tony confirms Task F's clean build on real device, QA must re-test:
1. All items from Addendum 1's and Addendum 2's QA Regression Areas (still valid, not superseded).
2. Specifically confirm the red debug border and lime toolbar border are both gone, and the toolbar/footer render with their original styling.
3. Confirm no `TEMP-DEBUG`-tagged code remains anywhere in `bulk_entry_screen.dart` (`grep -n "TEMP-DEBUG"` should return zero matches).
4. Confirm the CSV field has no `focusNode:`/`scrollController:`/`autocorrect:`/`enableSuggestions:` parameters — only `key`, `controller`, `maxLines`, `minLines`, `style`, `decoration`, matching Addendum 1's original spec exactly.

### Out of Scope (Addendum 3)

1. Any code change to `lib/shared/widgets/keyboard_aware_wrapper.dart` — still not authorized; see "If the Clean Retest Still Fails" for the contingency path.
2. Any code change to `lib/features/calendar/calendar_tab_content.dart` — the confirmed `MediaQuery.of(context)`-vs-`MediaQuery.paddingOf(context)` inefficiency identified above is real but unrelated to this bug's root cause and belongs in its own ticket, not this one.
3. Re-adding `autofocus`, a wrapping `Container` around the CSV field, or any new instrumentation to `bulk_entry_screen.dart` beyond Task F's removals — this addendum's entire premise is that this file has enough diagnosis on record; the next data point should come from a clean real-device test, not more code.
4. Everything already out of scope per Addendum 1 and Addendum 2 (the `keyboardHeight`-based collapse logic itself, `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, platform-conditional fixes) remains out of scope here too.

---

**Architect Signature (Addendum 3):** Root cause of this round's specific reproduction identified with HIGH confidence and directly demonstrable from the code: Addendum 2's own Task B diagnostic wrapper (added purely for visual identification) placed the CSV field's `Key` one level too deep to be seen by the reconciliation pass this plan already relied on, silently defeating Addendum 1's fix and reintroducing element-identity churn on every keyboard-driven rebuild — a self-inflicted regression in the diagnostic tooling, not a new theory about the app. This explains the toolbar flash, the Android IME hide/restart log, and (with slightly lower certainty, flagged honestly) the total silence from the focus listener. It does not, by itself, retroactively explain the pre-Addendum-2 failure, which is why Task A's independently-confirmed toolbar/footer fix is kept rather than treated as redundant. Proposed action: strip all Addendum 2 Task B/C diagnostic code (satisfying Tony's request and removing the confound in one move), keep Task A, and test — for the first time — the clean combination of both already-diagnosed fixes with zero instrumentation. `keyboard_aware_wrapper.dart` remains flagged, off-limits, and ready as the next step only if this clean test still fails. Ready for Engineer implementation of Tasks F–H.


---
---

## Addendum 4 — 2026-07-28 — Three New Issues Surfaced Now That the Modal Is Usable

### Context for This Addendum

Addendum 3's clean retest is confirmed working by Tony on a real device: the focus/glitch bug is resolved — keyboard opens smoothly, the field holds focus, typing and pasting both work, across repeated cycles. This is the first session in this ticket's history where the modal has been usable long enough for anyone to observe its behavior past the first tap. Three new, distinct issues surfaced as a direct result, all reported by Tony from real-device use, none of them the focus/glitch bug:

1. A genuine `RenderFlex` overflow (the black-and-yellow debug stripe) when the keyboard is open, with the "Load Songs" button crowding the bottom of the shrunk paste field.
2. A product request: the footer ("Add Songs" / "Cancel") shouldn't float above the keyboard while both actions are unusable (before "Load Songs" has ever been tapped).
3. A functional defect: after "Load Songs," the table area shows only column headers — no parsed song rows.

Per Manager scope authorization, all three are folded into this ticket. Reading and modification authorization is confirmed expanded to every method in `bulk_entry_screen.dart` involved in parsing→table population (`_handleCsvIngestion`, `_populateTableFromParseResult`), and reading-only authorization is confirmed expanded to `bulk_song_parser.dart` and `bulk_song_row.dart`. Both were read in full for this addendum (see Issue 3 below). `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, and `setlist_detail_screen.dart` were not read and are not touched — none of the three diagnoses below required them, so no stop-condition escalation is needed this round.

**A methodological note, carried forward from Addendum 3's own lesson:** this ticket has already produced two HIGH-confidence, code-path-only diagnoses that failed real-device verification (Addenda 1 and 2's initial theories). None of the three findings below are rated HIGH purely on layout-math reasoning for that reason — confidence is capped at MEDIUM wherever the claim rests on reasoning about Flutter's `Flex`/`RenderFlex` sizing behavior that has not been pixel-measured on an actual device in this session. All three fixes are designed to be safe to ship even if the exact severity estimate is off, and the Verification Plan below requires real-device confirmation of all three, exactly as this ticket has required every round since Addendum 1.

All three issues are diagnosed and fixed independently below (Issues 1 and 3 turn out to interact, and Issue 2's fix materially helps Issue 1 — this is called out explicitly where relevant, but each is still a distinct Engineer task with its own verification).

---

### Issue 1 — Layout Overflow When the Keyboard Is Open

#### Root Cause

**Confidence: MEDIUM — the mechanism is confirmed by direct reading of the current file against Flutter's documented `RenderFlex` layout algorithm; the exact device/keyboard-height combination that tips it into overflow is not independently pixel-measured in this session.**

`bulk_entry_screen.dart`, `build()` (current lines 350–538). The outer `Column`'s children, in order:

```
Padding(...)                                    // paste UI: intro + info box + TextField + Load Songs button — line 357
if (_hasLoadedSongs) [...] else Expanded(SizedBox.shrink())   // line 516
if (keyboardHeight > 0) _buildKeyboardToolbar()  // line 535 — Container, ~55–65dp
_buildFooter(hasValid, validCount)               // line 536 — Container, always present
```

There is no `Scaffold` anywhere in this widget's ancestor chain (confirmed by the original plan's Existing System Analysis, re-confirmed here — `add_to_setlist_overlay.dart` is `Material → SafeArea → Container → Column`), so nothing automatically shrinks the available height when the on-screen keyboard appears. Instead, `_buildFooter()` (line 787) manually reserves room above the keyboard by adding `MediaQuery.of(context).viewInsets.bottom + Spacing.space16` as its own bottom padding (line 790–794, unchanged by any addendum to date). This is a deliberate, pre-existing pattern (documented in the original plan's Existing System Analysis, item 6) — it only works if the **total** height of every non-flexible sibling in the outer `Column` (the paste-UI `Padding`, the keyboard toolbar, and the footer including its now-inflated bottom padding) stays within whatever height the outer `Column` is actually given.

The `keyboardHeight`-based collapse of the paste-UI block (hiding the intro text + bordered info box, shrinking the `TextField` to `minLines: 1` with dense padding — lines 367, 429, 436, 445–447) was written by the prior `bulk-import-flexible-columns` ticket specifically to keep that total within bounds. That collapse logic has **not** been touched by any addendum in this ticket and is not modified here either (still Out of Scope, per Addenda 1–3). What has changed since that logic was tuned:

- `_buildKeyboardToolbar()` (line 736) is an **additional, non-flexible sibling** that only exists when `keyboardHeight > 0` — i.e., it adds real height (~55–65dp: padding + a 36–40dp button) at exactly the moment height is already scarcest. This widget pre-dates this entire bug ticket (confirmed in the original plan's Existing System Analysis, item 5), so it is not a regression introduced by this ticket — but nothing in the file's history shows the paste-UI collapse was ever re-budgeted to account for it.
- The footer's bottom-padding term (`viewInsets.bottom`) is not a small, fixed amount — real iOS/Android on-screen keyboards commonly run 300–400dp tall (more with a predictive-text/QuickType bar reserved), which is a large fraction of a typical phone's usable height once the modal's own chrome is subtracted.

Put together: when the keyboard opens, the `Column`'s total non-flexible content height changes by roughly `(toolbar height, ~+60dp) + (footer's added bottom padding, ~+keyboardHeight+16dp) − (paste-UI collapse savings, ~−200 to −260dp depending on font metrics)`. On a sufficiently tall keyboard (predictive-text bar engaged) and/or a shorter device, this nets **positive** — i.e., the `Column` needs *more* total height with the keyboard open than with it closed, despite the existing collapse logic — which is precisely a `RenderFlex` overflow, since none of these three siblings (paste-UI block, toolbar, footer) can currently shrink below their natural size, and `Expanded`/`SizedBox.shrink()` (the only flexible sibling) cannot go negative to absorb the difference. The debug overflow indicator renders at the point in the `Column` where the cumulative height first exceeds the available bound — consistent with Tony's description of the stripe appearing directly under the "Load Songs" button (the end of the paste-UI block, the first sizable fixed region in the list).

**This is very likely a pre-existing defect in the `bulk-import-flexible-columns` collapse logic, not a regression from this ticket's own changes.** None of this ticket's prior addenda altered `minLines`, `isDense`, `contentPadding`, the collapse condition, or `_buildKeyboardToolbar()`'s size — only cosmetic border/opacity tweaks (already logged as out-of-plan deviations) and unrelated `Key` additions. It was very likely never observed before because every previous attempt to reach a stable, keyboard-open state was itself blocked by the focus/glitch bug this ticket has spent three addenda fixing — this is the first session in which anyone has been able to sit in that state long enough to see it.

#### Proposed Solution

Give the paste-UI `Padding` block (line 357) a bounded, scrollable fallback **only when the keyboard is open** — i.e., exactly the state that can overflow — while leaving it completely untouched when the keyboard is closed (the state Addendum 1 already fixed and verified).

Concretely: extract the existing `Padding(...)` subtree (lines 357–515, currently the first child of the outer `Column`) into a local variable computed once per build, then conditionally wrap it:

```dart
final pasteUiBlock = Padding(
  // ...exact existing subtree, byte-for-byte unchanged...
);

return Column(
  children: [
    keyboardHeight > 0
        ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
        : pasteUiBlock,
    if (_hasLoadedSongs) ...[
      // unchanged
    ] else
      const Expanded(child: SizedBox.shrink()),
    if (keyboardHeight > 0) _buildKeyboardToolbar(),
    if (_hasLoadedSongs || keyboardHeight == 0) _buildFooter(hasValid, validCount), // Task J, see Issue 2
  ],
);
```

**Why this is the correct, minimal fix and not a workaround:**
- When `keyboardHeight == 0` (the already-fixed, already-verified state from Addendum 1), the paste-UI block is rendered exactly as it is today — a plain, non-flex `Padding` — with **zero** behavioral change. This is the single most important property of this fix: it cannot regress the state this ticket has already spent three addenda getting right.
- When `keyboardHeight > 0` (the only state that can overflow), the block becomes a `Flexible` child sharing the `Column`'s remaining space with the sibling `Expanded`. Because `Flexible` uses loose sizing, the block still renders at its natural (collapsed) size whenever that fits — it only becomes internally scrollable in the specific case where it doesn't, which converts a hard `RenderFlex` overflow (a rendering error) into a graceful internal scroll (a minor, recoverable UX degradation). This is the standard, well-established Flutter idiom for this exact class of problem.
- It does not touch, weaken, or re-tune the existing `keyboardHeight`-based collapse logic itself (still Out of Scope per Addenda 1–3) — the collapse still runs exactly as before; this only adds a safety net for when that collapse still isn't enough.
- Issue 2's fix (Task J, below) independently removes the single largest term in the overflow calculation — the footer's `keyboardHeight`-sized bottom padding — in the most common reproduction scenario (keyboard open, no songs loaded yet), since the footer will no longer be present at all in that state. Task I's fix is still independently necessary for the residual case where the footer legitimately stays visible (once songs are loaded, per Issue 2's own condition) and the user reopens the keyboard — a state where the overflow risk is smaller (Task K, below, also keeps the paste-UI block compact in that state) but not structurally eliminated the way it is in the pre-load case.

**Alternative considered and rejected:** giving the paste-UI block a plain `Flexible`/`Expanded` unconditionally (i.e., not gated on `keyboardHeight`). Rejected because, in the `keyboardHeight == 0` state, the sibling `Expanded(SizedBox.shrink())` (when `!_hasLoadedSongs`) or `Expanded(ListView)` (when `_hasLoadedSongs`) would then split remaining space with the paste-UI block by flex ratio *regardless of the paste block's actual content size* — capping the table's visible row count below what it gets today (100% of true remaining space) even when there is no overflow risk at all. That would be a real, silent regression to normal-case table visibility, which the `keyboardHeight > 0` gate avoids entirely.

**Alternative considered and rejected:** a static `ConstrainedBox(maxHeight: ...)` fraction of screen height. Rejected because the two states (keyboard open vs. closed) need very different caps, and a single static fraction either breaks the already-working closed-keyboard case (too tight) or fails to prevent the overflow (too loose) — the dynamic, `Column`-native `Flexible` approach correctly derives the real available space in both cases without a hand-tuned magic number.

---

### Issue 2 — Footer Should Not Float Above the Keyboard While Unusable

This is a product/UX request, not a bug with an independent root cause — Tony's direction is direct and unambiguous: the "Add Songs" / "Cancel" footer cannot be meaningfully used until "Load Songs" has populated the table, so it should not be pinned above the keyboard during that state.

#### Design Decision

Hide the footer entirely (not merely disable it in place) whenever the keyboard is open **and** no songs have been loaded yet — i.e., exactly the state Tony described as "cannot be used." Once either condition flips (songs are loaded, or the keyboard is dismissed), the footer reappears exactly as it does today.

**Why hide, not disable-in-place:** Tony's own framing — "there's no need for them to be pinned/visible above the keyboard during that state" — describes visibility, not just interactivity. Disabling in place (greying out the buttons but keeping them mounted) would still consume the `keyboardHeight`-sized bottom padding and still visually clutter the screen with unusable controls, achieving neither the space-reclaiming benefit nor the visual-simplicity Tony asked for. Hiding is also the smaller, more consistent change: it reuses the exact same conditional-widget pattern the file already uses for `_buildKeyboardToolbar()` (`if (keyboardHeight > 0) _buildKeyboardToolbar()`, line 535), rather than introducing a new "disabled" visual state for the footer's buttons that doesn't exist anywhere else in this file.

#### Files to Modify

`lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart`, line 536:

```dart
// Before:
_buildFooter(hasValid, validCount),

// After:
if (_hasLoadedSongs || keyboardHeight == 0) _buildFooter(hasValid, validCount),
```

No change to `_buildFooter()`'s own body (lines 787–863) — its internal logic (submit button enabled/disabled state, "Cancel" tap handler) is untouched. `_buildKeyboardToolbar()`'s own "Done" button (the keyboard's dismiss affordance) is unaffected — it remains visible whenever `keyboardHeight > 0`, regardless of `_hasLoadedSongs`, so the user always retains a way to dismiss the keyboard even while the footer is hidden.

**Side effect, stated honestly:** this change removes the single largest fixed-height contributor (the footer's `viewInsets.bottom`-sized bottom padding, commonly 300–400dp) from the `Column`'s total height demand in precisely the state Issue 1 reports overflowing (keyboard open, not yet loaded). This is expected to make Issue 1's overflow far less likely to reproduce in that specific scenario as a direct consequence of this change — but Task I's own fix (Issue 1, above) is kept as an independent safeguard for the remaining case (keyboard reopened after songs are already loaded, where the footer legitimately stays visible per this same condition).

---

### Issue 3 — Table Shows Only Column Headers After "Load Songs"

#### Investigation

Per the Manager's expanded authorization, the full path was traced with an open mind, not assuming a connection to this ticket's other changes:

`_handleCsvIngestion()` (lines 210–266) → `BulkSongParser.instance.parse()` (`bulk_song_parser.dart`, lines 64–208, read in full) → `_populateTableFromParseResult()` (lines 268–294) → `build()`'s `if (_hasLoadedSongs) [...]` branch (line 516) → `ListView.builder(itemCount: _rows.length, itemBuilder: (context, index) => _buildRow(index))` (lines 519–530).

**`bulk_song_parser.dart` and `bulk_song_row.dart` are both cleared — not implicated:**
- `BulkSongParser.parse()` correctly splits on tab, comma, or 2+-space delimiters (in that priority order), requires only 2 columns (artist, song), and returns `validRows` for any row with a non-empty title — there is no code path here that would silently return zero rows for reasonably-formatted pasted input. `BulkSongRow` (`bulk_song_row.dart`) is a plain immutable data class with no rendering or visibility logic of any kind.
- `_handleCsvIngestion()` correctly calls `_populateTableFromParseResult(parseResult)`, then a final `setState()` (lines 260–265) sets `_hasLoadedSongs = true` and `_isLoadingSongs = false` — this **is** the `setState` that triggers the rebuild; there is no missing or misplaced `setState` here.
- `_populateTableFromParseResult()` (lines 268–294) correctly disposes the old rows, clears `_rows`, and appends a new `_RowData` per `parseResult.validRows` entry with each `TextEditingController`'s `.text` set from the parsed fields (`row.artist.text = parsed.artist`, etc., lines 282–286) — rows are added to the correct (`_rows`) list, not a wrong or shadow list.
- `itemCount: _rows.length` (line 527) correctly reflects the now-populated list; `_buildRow(index)` reads `_rows[index]` directly with no additional filter or visibility condition applied to individual rows.

**Conclusion: this is not a data, state, or rebuild-wiring bug.** Every step of the parse → populate → rebuild chain was read line-by-line and is correct. The rows genuinely exist in `_rows` and genuinely get built into the widget tree.

**The actual defect is the same class of layout-starvation problem as Issue 1, triggered from a different direction.**

`_populateTableFromParseResult()` calls `FocusManager.instance.primaryFocus?.unfocus()` (line 270) as its first step. This causes the on-screen keyboard to dismiss immediately after "Load Songs" is tapped, so `keyboardHeight` returns to `0` within the next frame or two. But the paste-UI block's visibility (the intro text, the bordered info box, the full 3-line `TextField`, the "Load Songs" button, and the ingestion-summary text) is gated **only** on `keyboardHeight`, never on `_hasLoadedSongs` (line 367: `if (keyboardHeight == 0) ...`). So the moment the keyboard dismisses post-load, the **entire, full-size** paste-UI block re-renders directly above the now-populated table — intro text (~20dp) + bordered info box (~150–160dp) + a 3-line `TextField` (~75–80dp) + the "Load Songs" button (40dp) + the new "Loaded N songs..." summary text (~20dp) — roughly 350–400dp of content whose job is already done, stacked directly above `_buildColumnHeaders()` and the table's `Expanded(ListView.builder(...))`.

Because the outer `Column`'s only flexible region is that `Expanded`, and none of the other siblings (paste-UI block, headers, "Add Row" button, footer) can shrink, this large, now-redundant block competes directly with the table for the same fixed pool of vertical space. On a typical phone screen, this can squeeze the `Expanded(ListView)` down to a sliver — visually indistinguishable from "no rows" — while `_buildColumnHeaders()` (a fixed, non-flex sibling immediately above the squeezed `Expanded`, line 518) remains fully visible. This matches Tony's report exactly: "Only the column headers are visible — no songs are listed."

**Confidence: MEDIUM-HIGH.** HIGH on ruling out a data/state bug (directly confirmed, line-by-line, across all three files). MEDIUM-HIGH (not HIGH) on the layout-starvation explanation being complete, since the exact degree of squeeze has not been pixel-measured on a real device in this session — consistent with this ticket's established practice of not over-claiming confidence on layout-math reasoning alone (see the methodological note at the top of this addendum).

#### Proposed Solution

Once songs are loaded, the paste-UI block's job (informing and collecting paste input) is done — collapse it to the same compact form already used for the keyboard-open state, regardless of keyboard state, freeing the space the table needs. This reuses the existing compact styling wholesale rather than inventing a new visual state.

Introduce one derived boolean at the top of `build()` (line 351, immediately after `final keyboardHeight = ...`):

```dart
final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
```

And widen the existing `keyboardHeight`-based conditions to use it:

| Line | Before | After |
|------|--------|-------|
| 360 | `keyboardHeight > 0 ? Spacing.space4 : Spacing.space12` | `showFullPasteUi ? Spacing.space12 : Spacing.space4` |
| 367 | `if (keyboardHeight == 0) ...[` | `if (showFullPasteUi) ...[` |
| 429 | `minLines: keyboardHeight > 0 ? 1 : 3,` | `minLines: showFullPasteUi ? 3 : 1,` |
| 436 | `isDense: keyboardHeight > 0,` | `isDense: !showFullPasteUi,` |
| 445–447 | `contentPadding: keyboardHeight > 0 ? const EdgeInsets.symmetric(horizontal: 12, vertical: 0) : const EdgeInsets.all(12),` | `contentPadding: showFullPasteUi ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),` |
| 471 | `if (keyboardHeight == 0) const SizedBox(height: Spacing.space8),` | `if (showFullPasteUi) const SizedBox(height: Spacing.space8),` |

No other line changes. `_ingestionSummary`'s display (line 503, gated on `_ingestionSummary != null`, not on `keyboardHeight`) is untouched — it's a single line of low-cost, useful confirmation text ("Loaded N songs...") and stays visible regardless, which is out of scope for this fix.

**Why this is the correct, minimal fix and not a workaround:**
- It directly addresses the confirmed mechanism (a large, now-redundant block competing with the table for the same fixed space) rather than a symptom.
- It reuses 100% pre-existing UI states (the "compact" styling already exists and is already QA-verified for the keyboard-open case from the original ticket) — it only changes *when* that state applies, adding one derived boolean and widening two existing boolean expressions. No new widgets, no new styling, no new abstraction.
- It preserves the field's re-paste/reload capability: the compact `TextField` and "Load Songs" button remain visible and usable after load (unlike hiding the whole block outright, which would remove the ability to paste a replacement batch — a capability `_handleCsvIngestion`'s empty-text branch, lines 216–233, is explicitly built to support: clearing the field and reloading resets the table).
- Combined with Task J (Issue 2), the table's actual competing content in the "loaded" state is now just the compact paste block (~90–110dp) rather than the full ~350–400dp block, materially improving the table's visible row count in the common case even without Task I's Flexible wrap.

---

### Files Authorized for This Addendum's Engineer Tasks

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Task I (overflow fix) + Task J (footer visibility) + Task K (paste-UI collapse on load) |

**Read and cleared, not modified:** `lib/features/setlists/services/bulk_song_parser.dart`, `lib/features/setlists/models/bulk_song_row.dart` — both read in full for Issue 3's investigation; neither is implicated (see Issue 3 above); neither requires a change.

**Not authorized, not touched, no stop-condition triggered:** `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart` — none of the three diagnoses above required reading or modifying any of these files, so no escalation is needed this round.

---

### Engineer Task Breakdown (Addendum 4)

Execute in order, after (not replacing) all prior Task 1–3 / A–E / F–H work already completed. Tasks I, J, and K are independent of one another — implement and verify each separately, even though their effects compound favorably (see each Issue's discussion above).

**Task I — Fix the keyboard-open layout overflow**

1. In `build()` (`bulk_entry_screen.dart`), extract the existing `Padding(...)` subtree (current lines 357–515 — the intro text, bordered info box, `TextField`, "Load Songs" button, and ingestion-summary text) into a local variable, e.g. `final pasteUiBlock = Padding(...)`, with the subtree itself byte-for-byte unchanged.
2. Replace the outer `Column`'s first child with:
   ```dart
   keyboardHeight > 0
       ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
       : pasteUiBlock,
   ```
3. Do not change the `pasteUiBlock` subtree's own content, styling, or the existing `keyboardHeight`-based collapse conditions inside it (those are Task K's job, immediately below, and remain conceptually separate — read Task K before implementing to avoid duplicating the `showFullPasteUi` introduction twice).
4. Do not modify `_buildKeyboardToolbar()`, `_buildFooter()`, or the `if (_hasLoadedSongs) [...] else Expanded(...)` branch as part of this task.

**Task J — Hide the footer while the keyboard is open and no songs are loaded**

1. In `build()`, change line 536 from `_buildFooter(hasValid, validCount),` to:
   ```dart
   if (_hasLoadedSongs || keyboardHeight == 0) _buildFooter(hasValid, validCount),
   ```
2. Do not change `_buildFooter()`'s own body (lines 787–863). Do not change `_buildKeyboardToolbar()` — its "Done" button must remain the keyboard's dismiss affordance regardless of this change.

**Task K — Collapse the paste UI once songs are loaded**

1. In `build()`, immediately after `final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;` (line 351), add:
   ```dart
   final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;
   ```
2. Apply the six substitutions listed in the "Proposed Solution" table under Issue 3, above, exactly as specified (lines 360, 367, 429, 436, 445–447, 471). Do not change any other condition, value, or widget in the file.
3. Do not modify `_handleCsvIngestion()` or `_populateTableFromParseResult()` — both were read in full for this addendum and confirmed correct; no code change is needed in either.

**Task L — `flutter analyze`**
Ensure `0 errors` with Tasks I, J, and K's changes in place.

**Task M (verification only, no further code change expected)**
On a real device (iOS and/or Android, per this ticket's established practice — full stop/restart, not hot reload):
1. Open the Bulk Entry modal, tap into the paste field, and confirm no `RenderFlex` overflow indicator (black/yellow stripe) appears anywhere, at any point during the keyboard's rise or while it remains open.
2. Confirm the footer ("Add Songs" / "Cancel") is not visible while the keyboard is open and no songs have been loaded yet, and confirm it reappears immediately once the keyboard is dismissed (even with no songs loaded).
3. Paste a valid multi-row CSV/TSV block and tap "Load Songs." Confirm the table shows the parsed song rows (not just headers), and confirm the "Loaded N songs..." summary text is accurate.
4. With songs loaded, confirm the footer is visible (regardless of keyboard state) and functions normally ("Add Songs" submits, "Cancel" closes).
5. With songs loaded, tap back into the (now compact) paste field to reopen the keyboard. Confirm no overflow indicator appears, and confirm the table (though possibly showing fewer rows without scrolling in this compound state) remains scrollable and does not appear broken or empty.
6. Clear the paste field's text entirely (select-all, delete) with songs already loaded. Confirm the table clears and the full intro/info-box paste UI reappears (per `_handleCsvIngestion`'s existing empty-text branch, unaffected by this addendum).
7. Repeat steps 1–3 on a small-screen device if available (e.g., iPhone SE or equivalent), since Issue 1's overflow risk is most acute on shorter screens.

---

### Verification Plan Addendum (Addendum 4)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 16:** Open the Bulk Entry modal, tap into the paste field, and confirm no overflow indicator appears at any point while the keyboard is open (Issue 1 / Task I).
- **PRE-DEPLOY TEST 17:** With the keyboard open and no songs loaded, confirm the footer is not visible; dismiss the keyboard and confirm it reappears (Issue 2 / Task J).
- **PRE-DEPLOY TEST 18:** Paste a valid CSV/TSV block, tap "Load Songs," and confirm the parsed rows are visible in the table, not just the column headers (Issue 3 / Task K) — this is the specific gap this addendum targets and carries the primary verification burden for Task K.
- **PRE-DEPLOY TEST 19:** With songs loaded, confirm the footer is visible and functional regardless of keyboard state, and confirm the paste field has collapsed to its compact form (no intro text, no bordered info box) even with the keyboard closed.
- **PRE-DEPLOY TEST 20 (compound state):** With songs loaded, tap back into the paste field to reopen the keyboard. Confirm no overflow indicator appears and the table remains usable (scrollable), even if visually cramped.
- **PRE-DEPLOY TEST 21 (regression):** Confirm Addendum 1's original fix is unaffected — on first opening the modal (keyboard closed, no songs loaded), the intro text, bordered info box, and full 3-line paste field all render exactly as before, with no internal scrolling and no change in appearance from the currently-shipped, already-verified behavior.
- **PRE-DEPLOY TEST 22 (small-screen, best-effort):** Repeat Tests 16–18 on the smallest available real device/simulator, since Issue 1's overflow risk is most acute there.

**Tier 2 — Post-deployment (after merge):** Same posture as prior addenda — real-device confirmation carries the verification burden, not code-path analysis, given this ticket's history of two prior code-path-only diagnoses failing real-device testing.

---

### QA Regression Areas Addendum (Addendum 4)

QA must specifically test, on a real device:
1. No `RenderFlex` overflow indicator appears at any point with the keyboard open, before or after songs are loaded (Issue 1).
2. The footer is hidden exactly while `!_hasLoadedSongs && keyboardHeight > 0`, and visible in every other state, including immediately after keyboard dismissal with no songs loaded (Issue 2).
3. After a valid "Load Songs" tap, the table shows the actual parsed rows, matching the "Loaded N songs..." summary count (Issue 3) — this is the primary functional regression check for this addendum.
4. Addendum 1's original fix (full paste UI visible on first open, keyboard closed) is unchanged in appearance.
5. Addenda 2 and 3's focus/glitch fix (smooth keyboard rise, no flicker, focus holds across repeated tap cycles) is unaffected by any of these three changes — none of them touch the `TextField`'s `key`, `controller`, or focus-related properties.
6. The "clear field to clear table" behavior (`_handleCsvIngestion`'s empty-text branch) still works and correctly restores the full paste UI once the table is cleared.
7. All QA Regression Areas from Addenda 1–3 remain valid and are not superseded.

---

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's layout sizing (keyboard-open state), footer visibility, and paste-UI collapse timing. No parsing, validation, or persistence behavior changes; `_handleCsvIngestion()` and `_populateTableFromParseResult()` are read-confirmed correct and unmodified. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS and Android both plausibly affected** by Issue 1 and Issue 3 (both are on-screen-keyboard-driven or table-rendering issues, platform-agnostic in mechanism — no platform-conditional code is introduced). **Web/macOS: very likely unaffected in practice**, consistent with every prior addendum — no software keyboard animates in on desktop/web, so `keyboardHeight` rarely if ever transitions away from `0`, meaning Issues 1 and 2's conditions rarely trigger there; Issue 3's fix (paste-UI collapse on load) is purely additive and cosmetic on web regardless. |

---

### Regression Risk

**LEVEL: LOW**

Rationale:
- All three changes are confined to `bulk_entry_screen.dart`, additive or condition-widening only — no new widgets beyond a `Flexible`/`SingleChildScrollView` wrap (Task I), no new state fields, no new dependencies.
- Task I's fix is gated on `keyboardHeight > 0`, so the already-verified `keyboardHeight == 0` state (Addendum 1) is provably untouched — this was a deliberate design choice specifically to avoid risking a regression to already-fixed behavior.
- Task J reuses an existing conditional-widget pattern already present in the same file (`if (keyboardHeight > 0) _buildKeyboardToolbar()`) rather than introducing a new one.
- Task K reuses 100% pre-existing "compact" styling (already shipped and implicitly exercised by the keyboard-open state since the original `bulk-import-flexible-columns` ticket) — only the triggering condition is widened.
- `_handleCsvIngestion()` and `_populateTableFromParseResult()` were read in full and are explicitly **not modified** — the data/parsing/state-update path is confirmed correct and left alone, eliminating any risk of a data-layer regression from this addendum.
- No auth, session, routing, init-order, database, or repository changes. No change to `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, `keyboard_aware_wrapper.dart`, or `calendar_tab_content.dart`.
- As with every prior addendum in this ticket, confidence on the underlying layout-math reasoning is capped at MEDIUM (Issue 1) / MEDIUM-HIGH (Issue 3) rather than HIGH, and the Verification Plan requires real-device confirmation of all three before this addendum can be considered closed — consistent with this ticket's established, hard-won practice of not shipping layout fixes on code-path reasoning alone.

---

### Out of Scope (Addendum 4)

1. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, or `setlist_detail_screen.dart` — none were read or implicated this round; all remain off-limits per this plan's standing Stop Conditions.
2. Any change to `bulk_song_parser.dart` or `bulk_song_row.dart` — both read in full and confirmed uninvolved; no change needed.
3. Any change to `_handleCsvIngestion()` or `_populateTableFromParseResult()` — both read in full and confirmed correct; the defect is in `build()`'s layout, not in the data/state-update path.
4. Any change to the `TextField`'s `key`, `controller`, `focusNode`, or any property related to the focus/glitch bug already fixed by Addenda 1–3 — that fix is confirmed working and is not touched by this addendum.
5. Re-tuning the original `keyboardHeight`-based collapse logic's specific values (`minLines`, `isDense`, `contentPadding` thresholds) — Task I's `Flexible` wrap is a structural safety net around that logic, not a replacement or re-tuning of it.
6. A "disable in place" (greyed-out, still-visible) treatment of the footer instead of hiding it — considered and rejected under Issue 2, above.
7. Any redesign of the paste-UI block's visual appearance beyond reusing its existing compact/full states under a widened condition (Task K) — no new styling is introduced.

---

**Architect Signature (Addendum 4):** Three new, independent issues diagnosed, each confined to `build()` in `bulk_entry_screen.dart`. Issue 1 (keyboard-open overflow): MEDIUM confidence, mechanism confirmed via code + `RenderFlex` layout semantics — likely a pre-existing `bulk-import-flexible-columns` defect never previously observable due to the now-fixed focus/glitch bug; fixed via a `keyboardHeight`-gated `Flexible`/`SingleChildScrollView` wrap that provably cannot alter the already-verified keyboard-closed state. Issue 2 (footer visibility): a direct, minimal implementation of Tony's explicit product request, reusing an existing conditional-widget pattern. Issue 3 (empty table after load): MEDIUM-HIGH confidence — `_handleCsvIngestion()`, `BulkSongParser`, and `_populateTableFromParseResult()` were all read in full and confirmed correct (not a data/state bug); the actual defect is the same class of layout-starvation as Issue 1, triggered because the full paste-UI block has no gate on `_hasLoadedSongs` and re-expands to full size immediately after the keyboard dismisses post-load, starving the table's `Expanded` region. Fixed by collapsing the paste UI whenever songs are loaded, reusing existing compact styling. All three fixes are additive/condition-widening only, confined to the single already-authorized file, and none require touching `keyboard_aware_wrapper.dart` or any other off-limits file — no Stop Condition triggered this round. Ready for Engineer implementation of Tasks I–L; Task M (real-device verification of all three) must be completed and reported before this addendum is considered closed, consistent with this ticket's established practice.

---
---

## Addendum 5 — 2026-07-28 — Task I Reintroduced the Focus/Glitch Bug

### Context for This Addendum

Tony tested Addendum 4's build (Tasks I, J, K) on both a real iPhone and a real Android device, full stop/restart (not hot reload). Result: **the original focus/glitch bug is back on both platforms** — "a flash of a keyboard coming up and disappearing," the exact symptom Addendum 3's clean retest had confirmed fixed. Nothing in Addenda 1–3's fix (the `TextField`'s `key: const ValueKey('bulk-entry-csv-field')`, or Addendum 2 Task A's `_buildKeyboardToolbar()`/`_buildFooter()` keys) has been removed or altered by Addendum 4 — confirmed by direct read of the current file (see Root Cause, below). This addendum diagnoses why the bug reproduced anyway.

### Manager's Hypothesis — Verified, Not Assumed

The Manager's leading hypothesis was that Task I's conditional wrapper — changing the outer `Column`'s first child from an unconditional `pasteUiBlock` (a `Padding`) to `keyboardHeight > 0 ? Flexible(child: SingleChildScrollView(child: pasteUiBlock)) : pasteUiBlock` — causes the outer `Column`'s first-child slot to change `runtimeType` (`Padding` ↔ `Flexible`) at exactly the moment `keyboardHeight` crosses the `0`/`>0` boundary, and that the new `Flexible` wrapper carries no `Key`, burying the already-keyed `TextField` several levels deeper (`Flexible` → `SingleChildScrollView` → `pasteUiBlock` → ... → `TextField`) — invisible to `Element.updateChildren`'s reconciliation at the outer `Column`'s slot, causing the whole subtree (including the `TextField`'s element, its implicit `FocusNode`, and its platform text-input connection) to be torn down and recreated on every `keyboardHeight` transition.

**This is confirmed, not merely plausible, by direct read of the current file** (`grep -n` confirms Task I's diff landed exactly as Addendum 4 specified, at current lines 516–520):

```dart
return Column(
  children: [
    keyboardHeight > 0
        ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
        : pasteUiBlock,
    if (_hasLoadedSongs) ...[
      ...
    ] else
      const Expanded(child: SizedBox.shrink()),
    if (keyboardHeight > 0) _buildKeyboardToolbar(),
    if (_hasLoadedSongs || keyboardHeight == 0)
      _buildFooter(hasValid, validCount),
  ],
);
```

Applying `Element.updateChildren`'s forward/backward/middle-region algorithm to this exact list, across a `keyboardHeight` `0`→`>0` transition (the common case: modal just opened, `!_hasLoadedSongs`):

- **Old list** (`keyboardHeight == 0`, `!_hasLoadedSongs`, 3 items): `[Padding (pasteUiBlock, no key), Expanded(SizedBox.shrink()) (no key), Container (key: 'bulk-entry-footer')]`.
- **New list** (`keyboardHeight > 0`, `!_hasLoadedSongs`, 3 items): `[Flexible (no key), Expanded(SizedBox.shrink()) (no key), Container (key: 'bulk-entry-keyboard-toolbar')]`.
- **Forward matching** compares position 0: old `Padding` vs new `Flexible` — different `runtimeType`, `Widget.canUpdate` returns `false`. Forward matching fails immediately; **zero** items are matched from the front.
- **Backward matching** compares the last position: old `Container(key: footer)` vs new `Container(key: toolbar)` — same `runtimeType` but different, non-null `Key`s, so `Widget.canUpdate` returns `false` (keys differ). Backward matching also fails immediately; **zero** items matched from the back.
- With both ends failing on the first comparison, **the entire list falls into the middle region** for both old and new. The middle-region algorithm builds a key map from the *old* list's keyed widgets only: `{'bulk-entry-footer': <old Footer element>}`. It then walks the *new* list in order: `Flexible` has no key → not looked up in the map → **a brand-new `Flexible` `Element` is created from scratch** (not an update). `Expanded(SizedBox.shrink())` has no key → also freshly created (harmless — it holds no state). `Container(key: toolbar)` has a key not present in the map → also freshly created. The old `Footer` element (never consumed from the map) is deactivated/disposed.
- **The critical consequence:** because the new `Flexible` at slot 0 has no old counterpart to update in place (it is *mounted*, not *updated*), its entire subtree — `SingleChildScrollView` → `pasteUiBlock` (`Padding`) → ... → the already-keyed `TextField` — is built **fresh, from scratch, in one shot**. A fresh mount does not reconcile against anything; there is no "old `Flexible` element" for the reconciler to compare the inner `TextField`'s key against. The `TextField`'s `key: const ValueKey('bulk-entry-csv-field')` only helps when it is being matched against a *sibling list that already contains a same-keyed widget being reconciled at that level* — exactly the mechanism Addendum 1 fixed for the *inner* `Column` (where the `TextField` is a direct child and siblings shift around it, but the `TextField` itself is never swapped out for a different ancestor type). Here, the swap happens **one level up**, at the *outer* `Column`, in a widget (`Flexible`) that is itself unkeyed and whose presence/absence is exactly what's flipping. The inner key is real, correctly placed, and completely irrelevant to this specific defect, because the defect is a fresh-mount of the *entire ancestor chain* above it, not a reordering *within* an unchanged ancestor.
- The reverse transition (`keyboardHeight` `>0` → `0`) triggers the same failure symmetrically: old `Flexible` vs new `Padding` at slot 0, no key on either — fresh mount again, tearing down the just-created `TextField` element a second time.

**This is exactly the same class of defect Addendum 3 diagnosed and fixed** (a correctly-placed `Key` rendered invisible because it sits below a slot whose own widget type changes) — this time self-inflicted by Task I's conditional wrapper at the *outer* `Column`, not by diagnostic instrumentation. **Confidence: HIGH — confirmed directly against the current file's code and Flutter's documented `Element.updateChildren`/`Widget.canUpdate` mechanics, consistent with (not a repeat guess independent of) the two data points already on record for this exact ticket** (Addendum 3's disproof of the wrapper-defeats-key theory in that round, and its confirmation of the identical mechanism this round).

### Root Cause

**Confidence: HIGH — confirmed by direct code read + Flutter reconciliation mechanics, not re-asserted from a template.**

Task I's conditional `keyboardHeight > 0 ? Flexible(...) : pasteUiBlock` at the outer `Column`'s first-child slot is a genuine, self-inflicted regression. It reintroduces exactly the element-identity churn Addenda 1–3 spent three rounds eliminating from the *inner* `Column` — except this time the churn originates one level higher, at the *outer* `Column`, in a slot that Addenda 1–3 never touched because Task I (Addendum 4) is the first change to ever make that slot's widget type conditional.

### Confirming Tasks J and K Are Not Implicated

Verified directly, not assumed:

- **Task J** (`if (_hasLoadedSongs || keyboardHeight == 0) _buildFooter(hasValid, validCount)`) only toggles whether the *last* list item — a `Container` carrying its own stable, distinct key (`'bulk-entry-footer'`, added by Addendum 2 Task A) — is present. `_buildFooter()`'s subtree contains no `TextField`, no `FocusNode`-bearing widget, and is not an ancestor of the CSV field in any way; it is a structurally independent sibling. Its appearing/disappearing affects only the tail of the outer `Column`'s children list (already correctly handled via Addendum 2's toolbar/footer keys, which let the middle-region key map distinguish them from each other regardless of list-length changes). It does not touch, and cannot affect, the slot-0 `Padding`/`Flexible` type mismatch, since forward matching already fails at position 0 independent of anything happening at the tail. **Not implicated.**
- **Task K** (`showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs`, widening six conditions *inside* `pasteUiBlock`'s own inner `Column`) never changes `pasteUiBlock`'s own root widget type — it is always a `Padding`, in every state, before and after Task K. All of Task K's substitutions operate on `pasteUiBlock`'s *children*, inside the same inner `Column` that Addendum 1's `TextField` key and Addendum 3's clean-structure fix already made safe against sibling reordering. Task K widens *when* those inner collection-`if`s fire; it does not add, remove, or reorder anything at the *outer* `Column`'s slot 0. **Not implicated.** (The bug would reproduce identically with Task I alone, absent Task K entirely — Task K is orthogonal.)

Both are cleared by the same standard applied throughout this ticket: direct reconciliation-mechanics analysis against the current code, not inference from proximity to the reported symptom.

### Proposed Solution

**The conditional-wrapper approach (swapping between `pasteUiBlock` and `Flexible(child: SingleChildScrollView(child: pasteUiBlock))` based on `keyboardHeight`) is fundamentally incompatible with keeping the outer `Column`'s slot-0 element identity stable, and must be redesigned — not patched with a `Key` alone.** A `Key` on the wrapper would not be sufficient: even with a matching `Key` on both branches, `Widget.canUpdate` requires **both** `runtimeType` **and** `key` to match, and the two branches have different `runtimeType`s (`Flexible` vs `Padding`) by construction. The fix must make the widget type at that slot identical in every state.

**Always present the same wrapper — `Flexible(child: SingleChildScrollView(child: pasteUiBlock))` — in both keyboard states; vary only the wrapper's internal, non-structural properties (`flex` and the scroll view's `physics`) based on `keyboardHeight`:**

```dart
Flexible(
  flex: keyboardHeight > 0 ? 1 : 0,
  child: SingleChildScrollView(
    physics: keyboardHeight > 0
        ? const ClampingScrollPhysics()
        : const NeverScrollableScrollPhysics(),
    child: pasteUiBlock,
  ),
),
```

**Why this preserves Task I's actual goal (preventing `RenderFlex` overflow on small screens / tall keyboards) while eliminating the identity churn:**

- The outer `Column`'s slot-0 widget is now `Flexible` in **every** build, regardless of `keyboardHeight`. `Widget.canUpdate` compares `runtimeType` (`Flexible`, always) and `key` (`null`, always) — both match, every time, so this slot is **always an in-place update**, never a fresh mount. The same holds one level down: `SingleChildScrollView` is always the `Flexible`'s single child (only `physics` varies), and `pasteUiBlock` (`Padding`) is always its child. Every widget in the chain from the outer `Column` down to the already-keyed `TextField` is updated in place, on every `keyboardHeight` transition, in both directions. The `TextField`'s element, `FocusNode`, and platform text-input connection are never torn down by this chain — Addendum 1/3's fix now actually reaches the `TextField`, because nothing above it changes type anymore.
- `flex: 0` is a legitimate, documented `Flex`/`Flexible` configuration: a flex child with `flex == 0` is treated as a **non-flexible** child by `RenderFlex` — laid out in the first pass, before flex-space allocation, with loose main-axis constraints bounded only by the `Column`'s own incoming constraint. This is *exactly* the sizing behavior `pasteUiBlock` already has today when unwrapped (`keyboardHeight == 0`, current shipped/verified behavior) — so `flex: 0` reproduces that behavior byte-for-byte, not an approximation of it. `NeverScrollableScrollPhysics` on the `SingleChildScrollView` in this state means the wrapper has no scrolling behavior when it isn't needed, matching today's non-scrollable appearance.
- `flex: 1` (when `keyboardHeight > 0`) reproduces Task I's original overflow protection exactly: the wrapper competes for a bounded share of the outer `Column`'s remaining space (same as Task I's existing, real-device-untested design), and `ClampingScrollPhysics` allows the paste-UI content to scroll internally if it doesn't fit that share, converting a hard `RenderFlex` overflow into a graceful internal scroll — precisely Task I's stated goal, unchanged.
- **Critically, this does not reintroduce the "unconditional `Flexible`" alternative Addendum 4 already considered and rejected** (splitting remaining space 50/50 with the table's `Expanded` regardless of content size, capping table row visibility even with no overflow risk) — because `flex: 0` in the closed-keyboard state means `pasteUiBlock` is excluded from the flex-space split entirely (treated as non-flexible), exactly as it is unwrapped today. The table's `Expanded(ListView)` sibling still receives 100% of the space left over after `pasteUiBlock`'s actual (natural) size is subtracted, identical to current shipped behavior.
- No change to `_buildKeyboardToolbar()`, `_buildFooter()`, the `if (_hasLoadedSongs) [...] else Expanded(...)` branch, Task J's footer condition, or Task K's `showFullPasteUi` gating and its six inner substitutions — all remain exactly as Addendum 4 specified and Engineer implemented. This redesign is confined entirely to the four lines at the outer `Column`'s first-child slot (current lines 518–520).

**Alternative considered and rejected:** adding a `Key` to the existing conditional `Flexible`/`pasteUiBlock` swap (the Manager's suggested starting point). Rejected because a `Key` cannot make `Widget.canUpdate` return `true` across a `runtimeType` mismatch — `canUpdate` requires both to match. A keyed `Flexible` and a keyed `Padding` are still different types at the same slot; the reconciler would still tear down and remount the whole subtree on every transition. This alternative is structurally incapable of solving the problem, regardless of what key is chosen.

**Alternative considered and rejected:** wrapping `pasteUiBlock` in `Flexible`/`SingleChildScrollView` unconditionally with a **fixed** `flex: 1` in both states (no `flex: 0`/`flex: 1` distinction). Rejected because this reproduces the exact "plain `Flexible`/`Expanded` unconditionally" alternative Addendum 4 itself already considered and rejected: it would split remaining space with the table's `Expanded` sibling by ratio regardless of `pasteUiBlock`'s actual content size, silently capping table row visibility in the closed-keyboard state even when there's no overflow risk at all — a real regression to the currently-shipped, already-verified normal case. Varying `flex` between `0` and `1` (rather than the wrapper's presence) avoids this while still keeping the wrapper's *type* constant.

### Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Current lines 516–520 (the outer `Column`'s first child): replace the conditional `Padding`/`Flexible(child: SingleChildScrollView(child: pasteUiBlock))` swap with an unconditional `Flexible(flex: keyboardHeight > 0 ? 1 : 0, child: SingleChildScrollView(physics: keyboardHeight > 0 ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics(), child: pasteUiBlock))`. No other line changes. |

**Files off-limits (unchanged from Addendum 4):** `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`, `bulk_song_parser.dart`, `bulk_song_row.dart` — none read or implicated this round; no Stop Condition triggered. This addendum's fix is fully containable within the single already-authorized file.

### Engineer Task Breakdown (Addendum 5)

Execute after (not replacing) all prior work already completed.

**Task N — Replace Task I's conditional wrapper with a type-stable, property-varying wrapper**

1. In `build()` (`bulk_entry_screen.dart`), locate the outer `Column`'s first child (current lines 518–520):
   ```dart
   keyboardHeight > 0
       ? Flexible(child: SingleChildScrollView(child: pasteUiBlock))
       : pasteUiBlock,
   ```
2. Replace with:
   ```dart
   Flexible(
     flex: keyboardHeight > 0 ? 1 : 0,
     child: SingleChildScrollView(
       physics: keyboardHeight > 0
           ? const ClampingScrollPhysics()
           : const NeverScrollableScrollPhysics(),
       child: pasteUiBlock,
     ),
   ),
   ```
3. Do not change `pasteUiBlock`'s own definition (current lines 356–514) — its content and Task K's `showFullPasteUi`-gated internals are unaffected and must remain untouched.
4. Do not change `_buildKeyboardToolbar()`, `_buildFooter()`, the `if (_hasLoadedSongs) [...] else Expanded(...)` branch, or Task J's footer-visibility condition (current lines 521–542).

**Task O — `flutter analyze`**
Ensure `0 errors` with Task N's change in place.

**Task P (verification only, no further code change expected)**
On a real device (iOS and Android, matching how Tony reproduced this — full stop/restart, not hot reload):
1. Open the Bulk Entry modal and tap into the CSV paste field. Confirm the keyboard rises with a single smooth transition — **no flash, no flicker, no reset** — and the field acquires and holds focus.
2. Repeat step 1 two or three times in the same session (this ticket's established repeatability check).
3. Confirm no `RenderFlex` overflow indicator appears at any point while the keyboard is open (Task I's original goal, now re-verified under the redesigned wrapper).
4. Confirm the footer-hiding behavior (Task J) and paste-UI collapse-on-load behavior (Task K) are both visually unchanged from Addendum 4's intent.
5. Confirm the instructional block / full-size field still render correctly on first open with the keyboard closed (Addendum 1's original fix, unaffected).
6. Paste a valid CSV/TSV block, tap "Load Songs," and confirm the table populates with rows (Task K's fix, unaffected).

### Verification Plan Addendum (Addendum 5)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 23:** Tap into the CSV field on a real iOS device. Confirm no flash/flicker/reset of any kind, and that the field is focused and usable immediately — repeat 2–3 times.
- **PRE-DEPLOY TEST 24:** Repeat Test 23 on a real Android device.
- **PRE-DEPLOY TEST 25:** With the keyboard open, confirm no `RenderFlex` overflow indicator appears (re-confirms Task I's original goal under the redesigned wrapper).
- **PRE-DEPLOY TEST 26 (regression):** Confirm Task J (footer hidden while keyboard open and no songs loaded) and Task K (paste UI collapses once songs are loaded) both still behave exactly as Addendum 4 specified — this redesign changes only the wrapper's internal properties, not either of those conditions.
- **PRE-DEPLOY TEST 27 (regression):** Confirm Addendum 1's original fix (full paste UI visible on first open, keyboard closed) is pixel-for-pixel unchanged, since `flex: 0` is designed to reproduce that exact sizing behavior.

**Tier 2 — Post-deployment (after merge):** Same posture as every prior addendum — real-device confirmation carries the verification burden, not code-path analysis, given this ticket's history of multiple code-path-only diagnoses that required real-device correction.

### QA Regression Areas Addendum (Addendum 5)

QA must specifically re-test, on a real device, full stop/restart:
1. The focus/glitch bug (smooth keyboard rise, no flicker, focus holds across repeated tap cycles) — this is the primary regression this addendum targets, and the one that was reported as fully broken again before this fix.
2. Task I's overflow protection (no `RenderFlex` overflow indicator with the keyboard open) — must still hold under the redesigned wrapper.
3. Task J's footer-visibility condition and Task K's paste-UI-collapse-on-load condition — both unchanged in logic, re-verify they still render correctly now that the wrapper structure around them has changed.
4. Addendum 1's original fix (instructional block + full-size field on first open) — should be pixel-identical to before, since `flex: 0`/`NeverScrollableScrollPhysics` is designed to exactly reproduce the unwrapped-`Padding` sizing behavior.
5. Full CSV paste → Load Songs → table population flow, on both platforms.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's paste-UI wrapper structure (outer `Column` slot 0). No parsing, validation, or persistence behavior changes. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS and Android both confirmed broken** by this regression (Tony's dual-platform test) and both expected to be fixed by this addendum's platform-agnostic redesign (a Dart-level reconciliation fix, no platform branch). Web/macOS: unaffected in practice, consistent with every prior addendum — no software keyboard animates in on desktop/web, so the `keyboardHeight` transition this bug depends on rarely if ever occurs there. |

### Regression Risk

**LEVEL: LOW**

Rationale:
- The fix is confined to four lines at a single, already-authorized slot in one file. It does not touch `pasteUiBlock`'s content, `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's condition, or Task K's `showFullPasteUi` gating and substitutions.
- `flex: 0` is designed to exactly reproduce the current, already-verified `keyboardHeight == 0` sizing behavior (non-flex, loose-constrained, natural size) — not an approximation, a mathematically equivalent layout path for that state.
- `flex: 1` + `ClampingScrollPhysics` when `keyboardHeight > 0` exactly reproduces Task I's original, already-authorized overflow-protection design — only the wrapper's *presence* is no longer conditional; its *behavior* in the open-keyboard state is unchanged.
- Does not touch, weaken, or re-tune the `keyboardHeight`-based collapse logic inside `pasteUiBlock`, `_handleCsvIngestion()`, `_populateTableFromParseResult()`, `bulk_song_parser.dart`, or `bulk_song_row.dart` — all remain exactly as previously verified.
- No auth, session, routing, init-order, database, or repository changes.
- As with every prior round in this ticket, this fix must be confirmed on a real device, full stop/restart, before being considered closed — code-path confidence alone is explicitly not sufficient given this ticket's history.

### Out of Scope (Addendum 5)

1. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, or `setlist_detail_screen.dart` — none implicated this round; all remain off-limits.
2. Any change to `bulk_song_parser.dart` or `bulk_song_row.dart` — not implicated; not touched.
3. Any change to `_handleCsvIngestion()` or `_populateTableFromParseResult()` — not implicated; not touched.
4. Any change to the `TextField`'s `key`, `controller`, or any focus-related property, or to `_buildKeyboardToolbar()`'s/`_buildFooter()`'s own keys — all confirmed correct and unrelated to this regression; not touched.
5. Any change to Task J's footer-visibility condition or Task K's `showFullPasteUi` gating/substitutions — both confirmed uninvolved in this regression; not touched.
6. Adding a `Key` to the wrapper as a standalone fix — considered and rejected; structurally incapable of resolving a `runtimeType` mismatch on its own (see Proposed Solution, Alternative Considered and Rejected).
7. An unconditional, fixed `flex: 1` wrapper — considered and rejected; reintroduces the table-space-competition regression Addendum 4 already identified and avoided.

---

**Architect Signature (Addendum 5):** Manager's hypothesis confirmed with HIGH confidence by direct application of `Element.updateChildren`/`Widget.canUpdate` mechanics to the current code: Task I's conditional `Padding`/`Flexible` swap at the outer `Column`'s first-child slot changes that slot's `runtimeType` across every `keyboardHeight` transition, and because the new `Flexible` wrapper carries no key, the entire subtree beneath it — including the already-correctly-keyed `TextField` — is torn down and freshly mounted on every transition, in both directions. This is a self-inflicted regression from Addendum 4's Task I, structurally identical in kind to the defect Addendum 3 diagnosed and fixed, but newly introduced at a different slot (the outer, not inner, `Column`). Tasks J and K were verified, not assumed, to be uninvolved — neither touches the outer `Column`'s slot-0 widget type. A `Key`-only fix is shown to be structurally insufficient, since `Widget.canUpdate` requires both matching `runtimeType` and matching `key`; the redesign instead makes the wrapper's type (`Flexible(child: SingleChildScrollView(...))`) unconditional in every state, varying only `flex` (`0` vs `1`) and `physics` (`NeverScrollableScrollPhysics` vs `ClampingScrollPhysics`) to preserve Task I's original overflow-protection goal without introducing element-identity churn. No off-limits file is implicated; no Stop Condition triggered. Ready for Engineer implementation of Task N.

---
---

## Addendum 6 — 2026-07-28 — Cosmetic Refinement: Paste Field Height and Spacer Consistency

### Context for This Addendum

Tony confirmed on a real iOS device that both of this ticket's functional defects are resolved: Addendum 5's type-stable `Flexible`/`SingleChildScrollView` wrapper (Task N) fixed the focus/glitch bug — no flash, keyboard rises cleanly, field holds focus — and Task K's `showFullPasteUi` gating fixed the empty-table bug — songs now populate correctly, one per row. This addendum is **not a regression fix**. It addresses two purely cosmetic complaints from a real-device screenshot taken with the keyboard open:

1. The paste `TextField` collapses to a cramped single visible line (`minLines: showFullPasteUi ? 3 : 1`, which evaluates to `1` any time the keyboard is open) instead of keeping its normal, taller multi-line height. Tony wants the field to keep its default/taller height even with the keyboard open.
2. There is no visible gap between the `TextField` and the "Load Songs" button — they touch. The trailing spacer (current line 470, `if (showFullPasteUi) const SizedBox(height: Spacing.space8)`) only renders when `showFullPasteUi` is `true`, which is `false` any time the keyboard is open. Tony wants consistent spacing regardless of keyboard state.

Confirmed via direct read of the current file (`grep -n "showFullPasteUi\|_hasLoadedSongs"`) that the working tree exactly matches Addendum 5's shipped state: six `showFullPasteUi` usages at lines 359, 366, 428, 435, 444, and 470, plus the declaration at line 352 — nothing has drifted.

### Investigation — Do `minLines`, `isDense`, and `contentPadding` Still Need to Vary With Keyboard State?

**Confidence: HIGH — confirmed by direct application of the current `Flexible`/`RenderFlex` layout mechanics Addendum 5 already established, not a new theory.**

Since Addendum 5's Task N, the outer `Column`'s first child is **unconditionally** `Flexible(flex: keyboardHeight > 0 ? 1 : 0, child: SingleChildScrollView(physics: ..., child: pasteUiBlock))`. This changes the safety analysis for anything that grows the paste-UI block's natural content height while the keyboard is open:

- When `keyboardHeight > 0`, the wrapper has `flex: 1` and `ClampingScrollPhysics`. Per standard `RenderFlex` behavior, a `Flexible` child with `flex: 1` is laid out with a **bounded maximum** equal to its share of the `Column`'s remaining space (split with whatever other flexible siblings are present — `Expanded(SizedBox.shrink())` when `!_hasLoadedSongs`, or the table's `Expanded(ListView)` when `_hasLoadedSongs`). If `pasteUiBlock`'s actual content exceeds that bound, the `SingleChildScrollView` absorbs the excess by scrolling internally — it does **not** overflow the `Column`, because the allocated height is fixed by the flex split regardless of the child's intrinsic size.
- Therefore, increasing the block's natural height while the keyboard is open (taller `minLines`, non-dense decoration, full `contentPadding`, an extra spacer) cannot reintroduce the `RenderFlex` overflow Addendum 4's Task I and Addendum 5's Task N already fixed. The allocated flex share is unchanged by any of this; only how much of that share needs to scroll internally changes. **This directly answers the investigation question: `minLines`/`isDense`/`contentPadding` no longer need to vary with `keyboardHeight` specifically, because the wrapper's scroll behavior is a genuine, structural safety net for exactly this kind of change** — not a hypothesis, a direct consequence of the `Flexible`/bounded-max-size mechanics Addendum 5 already verified are in place.

**However, "no longer need to vary with `keyboardHeight`" is not the same as "should become permanently fixed at their full values in every state."** `_hasLoadedSongs` is a separate axis, and Task K's reason for shrinking the field (`showFullPasteUi` requires `!_hasLoadedSongs`) still applies once songs are loaded: the field's compact form was introduced specifically so the now-redundant paste UI stops competing with the table's `Expanded(ListView)` for space (Addendum 4, Issue 3). That reasoning has nothing to do with the keyboard — it applies whether the keyboard is open or closed, any time songs are already loaded. Pinning `minLines`/`isDense`/`contentPadding` to their "full" values unconditionally (ignoring `_hasLoadedSongs`) would silently undo Task K's fix in the keyboard-closed + loaded case (browsing the table with the field visible above it, currently compact and correctly so) — a real, avoidable regression to an already-verified, already-shipped behavior, for no benefit Tony asked for. Tony's screenshot and complaint describe the pre-load paste flow (the field is what's cramped; there's no populated table visible), not the post-load browsing state.

**Conclusion:** these three properties should switch their controlling condition from `showFullPasteUi` (`keyboardHeight == 0 && !_hasLoadedSongs`) to a new condition based on `!_hasLoadedSongs` alone — dropping the `keyboardHeight` dependency Tony flagged, while preserving the `_hasLoadedSongs` dependency Task K needs for an unrelated, still-valid reason. Concretely, this only changes behavior in one of the four `(keyboardHeight, _hasLoadedSongs)` cells — keyboard open + no songs loaded yet, exactly Tony's screenshot — and leaves the other three cells (including the keyboard-closed original fix and the compound loaded+keyboard-open state Addendum 4 Test 20 covers) pixel-identical to today.

### Is `showFullPasteUi` Retired or Simplified?

**Not retired.** Of its six current uses, only the three field-density properties (`minLines`, `isDense`, `contentPadding`) are changing basis. The other three remain exactly as Task K designed them, because their purpose is unrelated to Tony's complaint and still valid:

- **Padding-top** (line 359, `showFullPasteUi ? Spacing.space12 : Spacing.space4`): a minor top-inset on the whole block, not part of the "cramped field" complaint. Left untouched.
- **Intro text + bordered info box gating** (line 366, `if (showFullPasteUi) ...[`): this is the one Task K substitution the plan explicitly flags as a candidate to *stay* conditional — hiding a ~150–200dp instructional block is what actually conserves room for typing when the keyboard is open (before load) and for the table (after load). Tony did not ask for this content back with the keyboard open, and reintroducing it would reduce, not fix, the room available for the now-taller field. Left untouched.
- **`showFullPasteUi` itself** (line 352, `keyboardHeight == 0 && !_hasLoadedSongs`): still the correct condition for the two uses above. Kept as-is.

`showFullPasteUi` is therefore simplified in scope (three uses instead of six) but not removed — it still names a real, distinct condition ("show the full instructional chrome") that is different from the new condition being introduced below ("keep the field itself at its expanded/compact size"). Giving them different names, rather than collapsing them into one, is deliberate: conflating them again would be exactly the mistake this addendum is correcting.

### Proposed Solution

1. Add one new derived boolean immediately after the existing `showFullPasteUi` declaration (current line 352):
   ```dart
   final showExpandedPasteField = !_hasLoadedSongs;
   ```
2. Rewire the three field-density properties from `showFullPasteUi` to `showExpandedPasteField`:
   - Line 428: `minLines: showFullPasteUi ? 3 : 1,` → `minLines: showExpandedPasteField ? 3 : 1,`
   - Line 435: `isDense: !showFullPasteUi,` → `isDense: !showExpandedPasteField,`
   - Lines 444–446: `contentPadding: showFullPasteUi ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),` → `contentPadding: showExpandedPasteField ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),`
3. Make the trailing spacer (line 470) unconditional — remove the `if (showFullPasteUi)` guard entirely:
   - `if (showFullPasteUi) const SizedBox(height: Spacing.space8),` → `const SizedBox(height: Spacing.space8),`

No other line changes. `pasteUiBlock`'s padding-top value, the intro/info-box gate, `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, and the outer `Flexible`/`SingleChildScrollView` wrapper from Task N are all untouched.

**Why the spacer becomes fully unconditional (not re-gated on `_hasLoadedSongs`):** Tony's ask ("consistent spacing regardless of keyboard state") is most directly satisfied by making it unconditional outright, and `Spacing.space8` is a small, fixed value (not a multi-line field's worth of height) — its presence in the one additional cell this touches (keyboard-open + loaded, the compound state from Addendum 4 Test 20) is negligible and does not compete meaningfully with the table for space, unlike `minLines`/`isDense`/`contentPadding`, which is why those three needed the more careful `_hasLoadedSongs`-gated treatment above and the spacer did not.

**Net effect by state, confirmed against all four `(keyboardHeight, _hasLoadedSongs)` combinations:**

| State | Before | After | Changed? |
|---|---|---|---|
| Keyboard closed, no songs loaded (Addendum 1's original, shipped fix) | Full field (3 lines, normal padding), intro/info box shown, spacer shown | Identical | No |
| **Keyboard open, no songs loaded (Tony's screenshot)** | Field collapsed to 1 line, dense/tight padding, no spacer | **Field expanded to 3 lines, normal padding, spacer shown**; intro/info box still hidden (unchanged) | **Yes — this is the fix** |
| Keyboard closed, songs loaded (browsing table) | Field compact (1 line, dense), no spacer | Field compact (unchanged); spacer now shown (negligible 8dp) | Only the spacer |
| Keyboard open, songs loaded (Addendum 4 Test 20 compound state) | Field compact (1 line, dense), no spacer | Field compact (unchanged); spacer now shown (negligible 8dp) | Only the spacer |

### Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Add `final showExpandedPasteField = !_hasLoadedSongs;` after line 352; rewire `minLines` (line 428), `isDense` (line 435), and `contentPadding` (lines 444–446) from `showFullPasteUi` to `showExpandedPasteField`; remove the `if (showFullPasteUi)` guard on the trailing spacer (line 470), making it unconditional. No other line changes. |

**Files off-limits (unchanged from Addenda 4–5):** `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`, `bulk_song_parser.dart`, `bulk_song_row.dart` — none implicated; no Stop Condition triggered.

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** none
**New files:** none

### Engineer Task Breakdown (Addendum 6)

Execute after (not replacing) all prior work already completed.

**Task Q — Decouple field density from keyboard state; make the spacer unconditional**

1. In `build()` (`bulk_entry_screen.dart`), immediately after `final showFullPasteUi = keyboardHeight == 0 && !_hasLoadedSongs;` (current line 352), add:
   ```dart
   final showExpandedPasteField = !_hasLoadedSongs;
   ```
2. Change `minLines: showFullPasteUi ? 3 : 1,` (current line 428) to `minLines: showExpandedPasteField ? 3 : 1,`.
3. Change `isDense: !showFullPasteUi,` (current line 435) to `isDense: !showExpandedPasteField,`.
4. Change the `contentPadding` ternary (current lines 444–446) from testing `showFullPasteUi` to testing `showExpandedPasteField`. Do not change either branch's actual `EdgeInsets` value.
5. Change `if (showFullPasteUi) const SizedBox(height: Spacing.space8),` (current line 470) to an unconditional `const SizedBox(height: Spacing.space8),` — remove the `if` guard, not the widget.
6. Do not change the padding-top ternary (current line 359), the intro-text/info-box gate (current line 366), `showFullPasteUi`'s own declaration (current line 352), `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, or the Task N `Flexible`/`SingleChildScrollView` wrapper.

**Task R — `flutter analyze`**
Ensure `0 errors` with Task Q's changes in place.

**Task S (verification only, no further code change expected)**
On a real device (iOS, matching how Tony reported this; Android best-effort), full stop/restart:
1. Open the Bulk Entry modal with the keyboard closed. Confirm the intro text, bordered info box, and full 3-line field are pixel-identical to the already-shipped behavior (Addendum 1, unaffected by this addendum).
2. Tap into the paste field to open the keyboard. Confirm the field now shows its full/expanded height (3 lines, normal padding) instead of collapsing to 1 dense line, and confirm a visible gap now separates the field from the "Load Songs" button.
3. Confirm the intro text and bordered info box remain hidden while the keyboard is open (unchanged — this addendum does not restore them).
4. Confirm no `RenderFlex` overflow indicator appears at any point with the keyboard open (Task N's safety net, re-confirmed under the taller field).
5. Paste a valid CSV/TSV block and tap "Load Songs." Confirm the table populates correctly (Task K, unaffected).
6. With songs loaded and the keyboard closed, confirm the field is still compact (1 line, dense) — confirming `_hasLoadedSongs`-based collapse still works and was not accidentally removed.
7. With songs loaded, tap back into the field to reopen the keyboard. Confirm the field remains compact (unchanged from Addendum 4's Test 20 compound-state behavior) and the table remains usable/scrollable, not squeezed out.
8. Confirm the focus/glitch fix (smooth keyboard rise, no flash, field holds focus across repeated tap cycles) is unaffected — this addendum does not touch the `TextField`'s `key`, `controller`, or the Task N wrapper.

### Verification Plan Addendum (Addendum 6)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 28:** Tap into the CSV field with the keyboard closed → open. Confirm the field shows 3 lines with normal (non-dense) padding while the keyboard is open, not 1 collapsed line.
- **PRE-DEPLOY TEST 29:** With the keyboard open, confirm a visible gap exists between the field and the "Load Songs" button.
- **PRE-DEPLOY TEST 30 (overflow regression):** With the keyboard open and the field at its new, taller height, confirm no `RenderFlex` overflow indicator appears — this is the specific case the Investigation section above reasons is safe due to Task N's `Flexible`/`SingleChildScrollView` bound, and must be confirmed on-device per this ticket's established practice.
- **PRE-DEPLOY TEST 31 (regression):** Confirm Addendum 1's keyboard-closed, pre-load appearance is pixel-identical to today (intro text, info box, 3-line field, spacer all present and unchanged).
- **PRE-DEPLOY TEST 32 (regression):** With songs loaded, confirm the field is compact (1 line, dense padding) regardless of keyboard state — confirms Task K's table-space-conservation behavior survives this addendum unchanged.
- **PRE-DEPLOY TEST 33 (regression):** Confirm the focus/glitch fix (Addenda 1–5) and the populated-table fix (Task K) are both unaffected — full paste → Load Songs → table population cycle, and repeated tap/dismiss cycles with no flicker.

**Tier 2 — Post-deployment (after merge):** Real-device confirmation of Tests 28–30 carries the primary verification burden, consistent with this ticket's established practice — this is a cosmetic change, but it does touch the same field/layout code this ticket has repeatedly found does not behave as code-path reasoning alone would predict.

### QA Regression Areas Addendum (Addendum 6)

QA must specifically test, on a real device:
1. The paste field renders at full height (3 lines, normal padding) whenever `!_hasLoadedSongs`, regardless of keyboard state — this is the primary change.
2. A consistent gap separates the field from "Load Songs" in every state (this is now an unconditional spacer).
3. The field remains compact (1 line, dense padding, no gap-related layout issue) whenever `_hasLoadedSongs`, regardless of keyboard state — confirms Task K's behavior is unchanged.
4. No `RenderFlex` overflow indicator appears with the keyboard open, at the field's new taller size, before or after songs are loaded.
5. The intro text and bordered info box still hide whenever the keyboard is open or songs are loaded (unchanged from Task K — this addendum does not restore them).
6. The focus/glitch fix (Addenda 1, 3, 5) and the table-population fix (Task K) are both fully re-verified as working, since this addendum touches adjacent code in the same widget.
7. All QA Regression Areas from Addenda 1–5 remain valid and are not superseded.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's paste-field visual density (line count, padding) and inter-element spacing. No parsing, validation, persistence, or focus-management behavior changes. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **iOS confirmed as the reported case** (Tony's screenshot); fix is platform-agnostic (no platform-conditional code), so Android is expected to see the same improvement. Web/macOS: negligible practical effect, consistent with every prior addendum — no software keyboard animates in on desktop/web, so the `keyboardHeight > 0` state this addendum touches rarely if ever occurs there. |

### Regression Risk

**LEVEL: LOW**

Rationale:
- Confined to four lines changed plus one line added, all within the single already-authorized file, all within `build()`'s existing paste-UI block.
- The keyboard-closed, pre-load state (Addendum 1's original, most heavily-verified fix) is provably unchanged: `showExpandedPasteField` (`!_hasLoadedSongs`) and the old `showFullPasteUi` condition it replaces for these three properties evaluate identically in that state (both `true` when `!_hasLoadedSongs`, independent of `keyboardHeight`).
- The keyboard-open + loaded compound state (Addendum 4 Test 20) is provably unchanged for the field itself: `showExpandedPasteField` evaluates `false` there exactly as `showFullPasteUi` did — only the now-unconditional spacer's negligible 8dp is new.
- Does not touch `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, the Task N `Flexible`/`SingleChildScrollView` wrapper, the `TextField`'s `key`/`controller`, `_handleCsvIngestion()`, `_populateTableFromParseResult()`, `bulk_song_parser.dart`, or `bulk_song_row.dart`.
- The one genuinely new state (keyboard open, field taller) is protected against overflow by Task N's already-shipped, already-reasoned-through `Flexible`/`ClampingScrollPhysics` bound — not a new, unverified safety mechanism, but reliance on one this ticket already built and verified for a different but structurally identical purpose.
- No auth, session, routing, init-order, database, or repository changes.
- As with every prior round in this ticket, this must be confirmed on a real device before being considered closed — code-path reasoning alone, however carefully applied, has been wrong twice already in this ticket's history (Addenda 1 and 2's initial theories).

### Out of Scope (Addendum 6)

1. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, or `setlist_detail_screen.dart` — none implicated; all remain off-limits.
2. Any change to `bulk_song_parser.dart` or `bulk_song_row.dart` — not implicated; not touched.
3. Any change to `_handleCsvIngestion()` or `_populateTableFromParseResult()` — not implicated; not touched.
4. Any change to the `TextField`'s `key`, `controller`, or any focus-related property, `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, or the Task N wrapper itself — all confirmed correct and unrelated to this cosmetic request; not touched.
5. Restoring the intro text / bordered info box while the keyboard is open — considered (as part of "should `showFullPasteUi` be retired") and rejected: Tony did not ask for this, and doing so would reduce the room available for the now-taller field, working against this addendum's own goal.
6. Making `minLines`/`isDense`/`contentPadding` unconditionally fixed at their "full" values regardless of `_hasLoadedSongs` — considered and rejected: would silently regress Task K's table-space-conservation fix in the keyboard-closed, songs-loaded browsing state, which Tony did not report as a problem and did not ask to change.
7. Re-gating the trailing spacer on `_hasLoadedSongs` instead of making it fully unconditional — considered and rejected as unnecessary complexity: the spacer's height is small enough that its presence in the one additional (compound) state this reaches is negligible, and Tony's own framing ("regardless of keyboard state") is most directly and simply satisfied by removing the conditional outright.
8. Any change to the six-substitution `showFullPasteUi` mechanism's other three uses (padding-top, intro/info-box gate, the declaration itself) — confirmed still serving a distinct, valid, unrelated purpose; left untouched.

---

**Architect Signature (Addendum 6):** Both of this ticket's functional defects (focus/glitch, empty table) remain fixed and are not touched by this addendum. Tony's two cosmetic requests — taller field with the keyboard open, and a consistent gap before "Load Songs" — are traced to three of `showFullPasteUi`'s six uses (`minLines`, `isDense`, `contentPadding`) and the conditional trailing spacer, all originally gated on a condition that couples keyboard state to load state. Investigation confirms Task N's `Flexible`/`SingleChildScrollView` wrapper (Addendum 5) provides a genuine, structural bound that makes it safe to stop varying these three properties with `keyboardHeight` specifically — but not safe to make them unconditionally "full," since `_hasLoadedSongs` independently justifies keeping the field compact once songs are loaded (Task K's original, unrelated purpose). The fix introduces one new derived boolean (`showExpandedPasteField = !_hasLoadedSongs`), rewires exactly three property sites to it, and removes the spacer's conditional entirely. `showFullPasteUi` is kept, not retired, for its two remaining legitimate uses (padding-top, intro/info-box gating), which still serve Task K's space-conservation goal and were not part of Tony's complaint. All four `(keyboardHeight, _hasLoadedSongs)` states were checked explicitly; only the keyboard-open/pre-load cell (Tony's exact screenshot) changes in any material way. No off-limits file is implicated; no Stop Condition triggered. Ready for Engineer implementation of Task Q.

---
---

## Addendum 7 — 2026-07-28 — Loaded-Songs Table Column Widths

### Context for This Addendum

Both of this ticket's functional defects (focus/glitch, empty table) and both of Addendum 6's cosmetic requests remain fixed and are not touched here. This addendum is a third, independent cosmetic refinement, this time to the loaded-songs table itself (the header row plus per-song data rows that appear once `_hasLoadedSongs` is `true`), not to the paste UI above it. Tony's request: the table's column widths currently don't reflect the actual content — he wants the columns to span the full table width with no wasted space or overflow, Artist and Song to be the widest columns (they hold the longest content — full names and titles), and BPM/Tuning/Key to be narrow, sized only to fit their own header text without wrapping.

### Investigation — Current Column-Width Structure

Read `_buildColumnHeaders()` (lines 558–577), `_headerCell()` (lines 579–595), `_buildRow()` (lines 601–676), and `_tableCell()` (lines 682–706), plus the module-level constants at lines 99–105.

**Headers and rows are not independently laid out — both already consume the same single source of truth.** `_headerCell(label, flex)` (called five times from `_buildColumnHeaders()`, once per data column, plus one `SizedBox(width: _kDeleteWidth)` for the trailing delete-icon column) and `_tableCell({..., flex, ...})` (called five times per row from `_buildRow()`, same column order) both wrap their content in `Expanded(flex: flex, ...)`, and both are driven by the same five module-level `const int` flex constants:

```dart
const int _kFlexArtist = 3;
const int _kFlexSong = 3;
const int _kFlexBpm = 2;
const int _kFlexTuning = 2;
const int _kFlexKey = 2;
const double _kDeleteWidth = 36;
const double _kCellHeight = 42;
```

Both `_buildColumnHeaders()`'s `Row` and `_buildRow()`'s `Row` list their six children (`Artist`, `Song`, `BPM`, `Tuning`, `Key`, delete-icon `SizedBox`) in the same fixed order, unconditionally, on every build — there are no collection-`if`s or any other structural conditional inside either `Row`. This means **there is no risk of the header/row misalignment or reconciliation-churn defect class this ticket has repeatedly diagnosed in the paste-UI block (Addenda 1, 3, 5)**: that entire class of bug requires a widget's *type* at a given slot to change across rebuilds based on runtime state (e.g., `keyboardHeight` crossing a threshold). Here, every column slot's widget type is fixed by source code alone — it never varies at runtime — so `Widget.canUpdate`/`Element.updateChildren` reconciliation is a non-issue for this change regardless of how the constants are edited, as long as headers and rows keep reading from the same constants (which the current structure already guarantees, and this addendum's fix preserves).

**Current widths do not satisfy Tony's requirements.** Flex ratio is 3:3:2:2:2 — Artist/Song get a mild edge over BPM/Tuning/Key (1.5×), but BPM/Tuning/Key are still flex-based (`Expanded`), meaning their actual rendered width grows and shrinks with the table's total available width and with how much room Artist/Song's content needs — they are not "only as wide as needed to display their column header title," they're whatever fraction of the full width the 2-unit flex share happens to work out to on a given device. This does not meet the "narrow, fixed/minimal width" requirement.

### Overflow Risk — Independent of Task N's Paste-UI Safety Net

Per the task's explicit instruction, this is reasoned about independently rather than assumed covered by Task N (Addendum 5): the table (`_buildColumnHeaders()` at line 530, and the `Expanded(GestureDetector(child: ListView.builder(...)))` at lines 531–543) is a **sibling** of the paste-UI `Flexible`/`SingleChildScrollView` wrapper under the same outer `Column` (line 517), not nested inside it. Task N's scroll/flex safety net applies only to the paste-UI block's own subtree and has no bearing on the table's `Row`s.

The relevant risk here is purely **horizontal**, within each `Row` (header row and every data row), not vertical: `_buildColumnHeaders()`'s `Container` (line 559) has no explicit width and stretches to whatever width its ancestor `Column`/dialog chrome provides (unaffected by this change); its child `Row` has default `mainAxisSize: MainAxisSize.max`, so it always claims exactly that full available width. A `Row` containing a mix of `Expanded` (flexible) and `SizedBox` (fixed-width) children lays out the fixed children first at their natural size, then gives 100% of the *remaining* width to the flexible children, split by flex ratio — it cannot overflow from this change alone unless the sum of all fixed-width children's widths alone exceeds the `Row`'s total available width (an extreme case already possible today with just the existing 36dp delete column, and not made meaningfully more likely by adding three modestly-sized narrow columns; see width sizing below). Converting three of five data columns from `Expanded` to fixed-width `SizedBox` does not change this reasoning — it only changes how many children are in the "fixed" bucket versus the "flexible" bucket. **No overflow risk is introduced by this change**, on any screen width this app supports.

### Design Decision — New Column-Width Scheme

- **Artist and Song:** keep `Expanded`, so together they consume 100% of whatever horizontal space remains after the narrow columns and the delete-icon column take their fixed share — this directly satisfies "span the full width, no wasted space." Equal flex (1:1) between them: both artist names and song titles vary comparably in length in practice (there is no structural reason one is reliably longer than the other), so an even split is the simplest, least-arbitrary choice. (Judgment call, per the task's explicit invitation to choose — a fixed asymmetric ratio was considered and rejected as unjustified without real content-length data to back a specific skew.)
- **BPM, Tuning, Key:** convert from `Expanded(flex: ...)` to a fixed-width `SizedBox`, all three sharing one constant, `_kNarrowColumnWidth`, sized to fit "Tuning" (six characters — the longest of the three header labels) without wrapping, at the header's actual text style (`AppFontSizes.caption` = 13.0, `FontWeight.w600`, `letterSpacing: 0.5`) plus its existing horizontal content padding (6dp each side, from `_headerCell`'s `Padding`, unchanged). Reasoning through that metric (13px semibold system font, six characters plus five inter-character 0.5dp letter-spacing gaps, plus 12dp total padding) puts the minimum comfortably in the high-50s/low-60s dp range; **`_kNarrowColumnWidth = 68.0`** is chosen to give a small safety margin against font-rendering variance across devices, without being reasoned from an on-device pixel measurement (consistent with this ticket's established practice — see Addendum 4 — of not over-claiming precision on layout values that haven't been visually confirmed; Task X below requires exactly that on-device confirmation before this is considered closed).
  - **Tradeoff, stated explicitly:** using one shared width (rather than sizing each of BPM/Tuning/Key independently to its own shorter header text) leaves a few dp of unused space in the BPM and Key columns relative to their own header text. This is a deliberate choice: three narrow columns of visibly different widths would read as uneven/jagged in the header row, especially for three short, peer-level metadata fields sitting side by side — a single consistent narrow width is more visually coherent and still satisfies "only as wide as needed" for the longest of the three, which is the binding constraint the task calls out explicitly. If Tony prefers each column sized to its own text, `_kNarrowColumnWidth` can be split into three independently-sized constants with no structural change beyond re-parameterizing the same call sites — noted here as the discarded alternative, not implemented.

### Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Replace `_kFlexBpm`/`_kFlexTuning`/`_kFlexKey` (lines 101–103) with a single `_kNarrowColumnWidth` constant; widen `_kFlexArtist`/`_kFlexSong` to simple equal values (lines 99–100); change `_headerCell()` (lines 579–595) and `_tableCell()` (lines 682–706) to each accept either a `flex` or a `width` parameter and build `Expanded`/`SizedBox` accordingly; update the five call sites in `_buildColumnHeaders()` (lines 568–572) and the five call sites in `_buildRow()` (lines 619, 627, 635, 644, 652) to pass `flex:` for Artist/Song and `width:` for BPM/Tuning/Key. No other line changes. |

**Files off-limits (unchanged from Addenda 4–6):** `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`, `bulk_song_parser.dart`, `bulk_song_row.dart` — none implicated; no Stop Condition triggered. This entire change is confined to `bulk_entry_screen.dart` — the table's column widths are controlled entirely by private, in-file constants and private helper methods (`_headerCell`, `_tableCell`), not by any shared/reusable widget outside this file, so no Manager authorization is required beyond this addendum.

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** none
**New files:** none

### Proposed Solution (Concrete Diff Shape)

Constants (lines 99–105):
```dart
const int _kFlexArtist = 1;
const int _kFlexSong = 1;
const double _kNarrowColumnWidth = 68.0; // fits "Tuning" (longest header) without wrapping
const double _kDeleteWidth = 36;
const double _kCellHeight = 42;
```

`_headerCell()` (lines 579–595) — accept either `flex` or `width`, exactly one supplied:
```dart
Widget _headerCell(String label, {int? flex, double? width}) {
  assert((flex == null) != (width == null),
      'Provide exactly one of flex or width');
  final content = Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    child: Text(
      label,
      style: AppTextStyles.label.copyWith(
        color: context.colors.textSecondary,
        fontSize: AppFontSizes.caption,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    ),
  );
  return flex != null
      ? Expanded(flex: flex, child: content)
      : SizedBox(width: width, child: content);
}
```

`_buildColumnHeaders()` (lines 566–574) call sites:
```dart
_headerCell('Artist', flex: _kFlexArtist),
_headerCell('Song', flex: _kFlexSong),
_headerCell('BPM', width: _kNarrowColumnWidth),
_headerCell('Tuning', width: _kNarrowColumnWidth),
_headerCell('Key', width: _kNarrowColumnWidth),
const SizedBox(width: _kDeleteWidth),
```

`_tableCell()` (lines 682–706) — same pattern, wrapping the existing `SizedBox(height: _kCellHeight, child: _TableTextField(...))`:
```dart
Widget _tableCell({
  required TextEditingController controller,
  required FocusNode focusNode,
  int? flex,
  double? width,
  required String hint,
  required int rowIndex,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
  TextCapitalization textCapitalization = TextCapitalization.none,
}) {
  assert((flex == null) != (width == null),
      'Provide exactly one of flex or width');
  final content = SizedBox(
    height: _kCellHeight,
    child: _TableTextField(
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
    ),
  );
  return flex != null
      ? Expanded(flex: flex, child: content)
      : SizedBox(width: width, child: content);
}
```

`_buildRow()` (lines 616–655) call sites: Artist/Song pass `flex: _kFlexArtist` / `flex: _kFlexSong` (unchanged argument names, same as today); BPM/Tuning/Key pass `width: _kNarrowColumnWidth` in place of their current `flex: _kFlexBpm` / `flex: _kFlexTuning` / `flex: _kFlexKey`.

No change to `_TableTextField` itself (lines 886–933) — its internal `contentPadding` (6dp horizontal, matching `_headerCell`'s) is unchanged, and it already renders as a single-line `TextField` that scrolls horizontally within itself if content exceeds the cell's width, rather than wrapping — so a BPM/Tuning/Key value longer than the header text (e.g., a Tuning value like "Drop D" or "Standard") remains fully enterable and readable via that existing internal-scroll behavior; this addendum only changes the *column's* width, not the field's overflow handling, which was already correct and is untouched.

### Engineer Task Breakdown (Addendum 7)

Execute after (not replacing) all prior work already completed.

**Task T — Replace the flex/width constants**
1. In `bulk_entry_screen.dart` (lines 99–105), change `_kFlexArtist` and `_kFlexSong` to `1` each (from `3`).
2. Remove `_kFlexBpm`, `_kFlexTuning`, `_kFlexKey`.
3. Add `const double _kNarrowColumnWidth = 68.0;` in their place.
4. Leave `_kDeleteWidth` and `_kCellHeight` untouched.

**Task U — Update `_headerCell()` to support fixed-width columns**
1. Change `_headerCell(String label, int flex)` to `_headerCell(String label, {int? flex, double? width})`, with exactly one of the two required at each call site (an `assert` enforcing this is acceptable but not mandatory).
2. Extract the existing `Padding`/`Text` subtree (unchanged content and style) into a local `content` variable, then return `Expanded(flex: flex, child: content)` when `flex` is provided, or `SizedBox(width: width, child: content)` when `width` is provided.
3. Update `_buildColumnHeaders()`'s five call sites: `Artist`/`Song` pass `flex: _kFlexArtist`/`flex: _kFlexSong`; `BPM`/`Tuning`/`Key` pass `width: _kNarrowColumnWidth`. The trailing `SizedBox(width: _kDeleteWidth)` is unchanged.

**Task V — Update `_tableCell()` to support fixed-width columns**
1. Change `_tableCell({..., required int flex, ...})` to `_tableCell({..., int? flex, double? width, ...})`, same one-of-two-required convention as Task U.
2. Extract the existing `SizedBox(height: _kCellHeight, child: _TableTextField(...))` subtree (unchanged) into a local `content` variable, then return `Expanded(flex: flex, child: content)` or `SizedBox(width: width, child: content)` accordingly.
3. Update `_buildRow()`'s five call sites: `Artist`/`Song` pass `flex: _kFlexArtist`/`flex: _kFlexSong`; `BPM`/`Tuning`/`Key` pass `width: _kNarrowColumnWidth`. Do not change `controller`, `focusNode`, `hint`, `rowIndex`, `keyboardType`, `inputFormatters`, or `textCapitalization` at any call site.
4. Do not change `_TableTextField` itself.

**Task W — `flutter analyze`**
Ensure `0 errors` with Tasks T–V's changes in place.

**Task X (verification only, no further code change expected)**
On a real device (or simulator, iOS matching how this ticket has been reported; the smallest available screen width is the most informative case for this specific change), with songs loaded (`_hasLoadedSongs == true`):
1. Confirm the header row's six columns (`Artist`, `Song`, `BPM`, `Tuning`, `Key`, delete-icon) together span the full table width, with no visible gap at the trailing edge and no horizontal overflow indicator.
2. Confirm `Artist` and `Song` are visibly the widest two columns, and are noticeably wider than `BPM`/`Tuning`/`Key`.
3. Confirm `BPM`, `Tuning`, and `Key` header labels each render on a single line, not wrapped — this is the specific case `_kNarrowColumnWidth = 68.0` is reasoned (not pixel-measured) to satisfy; if any of the three wraps on-device, `_kNarrowColumnWidth` is the single constant to increase, with no other change required.
4. Confirm every data row's five cells line up exactly under their corresponding header cell, for several rows.
5. Enter or paste a long Artist name and a long Song title into a row; confirm the `TextField` scrolls internally within its (now wider) `Expanded` column rather than wrapping or overflowing the row.
6. Enter a Tuning value longer than "Tuning" itself (e.g., "Drop D", "Standard") into a row; confirm it remains enterable and readable (scrolls within the fixed-width cell) without breaking the row's layout.
7. Confirm no `RenderFlex` overflow indicator appears anywhere in the table, at any screen width tested.

### Verification Plan Addendum (Addendum 7)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 34:** With songs loaded, confirm the header row's columns span the full width with no wasted trailing space and no overflow.
- **PRE-DEPLOY TEST 35:** Confirm Artist and Song are visibly the widest columns.
- **PRE-DEPLOY TEST 36:** Confirm "BPM", "Tuning", and "Key" header labels each render on one line, not wrapped, at `_kNarrowColumnWidth = 68.0`.
- **PRE-DEPLOY TEST 37:** Confirm header cells and row cells remain pixel-aligned column-to-column across several rows.
- **PRE-DEPLOY TEST 38 (regression):** Confirm no `RenderFlex` overflow indicator appears in the table on the smallest available screen width.
- **PRE-DEPLOY TEST 39 (regression):** Confirm the focus/glitch fix (Addenda 1, 3, 5), the populated-table fix (Task K), and Addendum 6's paste-field sizing are all unaffected — this addendum touches only `_buildColumnHeaders()`, `_headerCell()`, `_buildRow()`, `_tableCell()`, and the module-level flex/width constants; it does not touch the paste-UI block, the outer `Column`'s `Flexible`/`SingleChildScrollView` wrapper, `_buildKeyboardToolbar()`, or `_buildFooter()`.

**Tier 2 — Post-deployment (after merge):** Real-device confirmation of Tests 34–38 carries the primary verification burden, consistent with this ticket's established practice for layout values reasoned from font metrics rather than pixel-measured on-device.

### QA Regression Areas Addendum (Addendum 7)

QA must specifically test, on a real device, with songs loaded:
1. Column widths: Artist/Song widest, BPM/Tuning/Key narrow and un-wrapped, full-width span with no overflow (primary change).
2. Header-to-row alignment across multiple rows.
3. Long content in Artist/Song (scrolls within the field, doesn't wrap/overflow the row) and in BPM/Tuning/Key (same, within the narrower fixed width).
4. No `RenderFlex` overflow indicator anywhere in the table, including on the smallest available screen.
5. All prior QA Regression Areas (Addenda 1–6) remain valid and are not superseded — this addendum does not touch the paste-UI block, focus/glitch fix, or footer/toolbar behavior.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists / Catalog | **affected** — Bulk Entry modal's loaded-songs table column-width distribution only. No parsing, validation, persistence, or focus-management behavior changes. |
| Members / RBAC | unaffected |
| Auth / Session | unaffected |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **Affected uniformly** — shared Dart widget, no platform-conditional code introduced. This change is unrelated to keyboard/`viewInsets` behavior entirely (it applies whenever songs are loaded, regardless of keyboard state or platform), so it is expected to render identically on every platform. |

### Regression Risk

**LEVEL: LOW**

Rationale:
- Confined entirely to `bulk_entry_screen.dart`'s table-rendering code (`_buildColumnHeaders()`, `_headerCell()`, `_buildRow()`, `_tableCell()`, and five module-level constants) — no touch to the paste-UI block, the outer `Column`'s `Flexible`/`SingleChildScrollView` wrapper (Task N), `_buildKeyboardToolbar()`, `_buildFooter()`, or any focus/keyboard-related code from Addenda 1–6.
- No collection-`if`s or other runtime-conditional widget-type switching are introduced at any column slot — every slot's widget type (`Expanded` or `SizedBox`) is fixed by source code, not by state, so this change carries none of the reconciliation-churn risk this ticket has repeatedly diagnosed elsewhere (Addenda 1, 3, 5). This is a structural, not a state-dependent, change.
- Headers and rows are provably kept in alignment because both call sites are edited to draw from the exact same constants and the same `flex`/`width` convention — there is no way for them to drift independently.
- The one genuinely new risk surface — whether `_kNarrowColumnWidth = 68.0` is large enough to avoid wrapping "Tuning" on every device/font-scale combination — is reasoned from font metrics, not pixel-measured, consistent with this ticket's established practice of flagging that gap explicitly (see Addendum 4's methodological note) and requiring on-device confirmation (Task X) before this addendum is considered closed. If wrong, the fix is a single-constant change with no structural rework.
- No auth, session, routing, init-order, database, or repository changes. No change to `bulk_song_parser.dart`, `bulk_song_row.dart`, `setlist_repository.dart`, `keyboard_aware_wrapper.dart`, or `calendar_tab_content.dart`.

### Out of Scope (Addendum 7)

1. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `lib/main.dart`, `setlist_repository.dart`, or `setlist_detail_screen.dart` — none implicated; all remain off-limits.
2. Any change to `bulk_song_parser.dart` or `bulk_song_row.dart` — not implicated; not touched.
3. Any change to the paste-UI block, the outer `Column`'s `Flexible`/`SingleChildScrollView` wrapper (Task N), `_buildKeyboardToolbar()`, `_buildFooter()`, Task J's footer-visibility condition, or the `TextField`'s `key`/`controller`/focus behavior — all confirmed correct and unrelated to this cosmetic table-width request; not touched.
4. Independently sizing BPM, Tuning, and Key to three different widths (each fit to its own header text) instead of one shared `_kNarrowColumnWidth` — considered under Design Decision, above, and not implemented in favor of the more visually consistent shared-width approach; noted as the discarded alternative if Tony prefers per-column sizing later.
5. Changing `_TableTextField`'s own internal padding, font size, or overflow behavior — unrelated to column width and already correct (single-line field, scrolls internally rather than wrapping).
6. A non-equal flex ratio between Artist and Song (e.g., weighting one wider than the other) — considered and rejected without content-length data to justify a specific skew; equal flex is the least-arbitrary default and can be revisited if Tony reports one column is reliably too cramped in practice.

---

**Architect Signature (Addendum 7):** All prior fixes (focus/glitch, empty table, paste-field sizing) remain intact and are not touched by this addendum. Tony's column-width request is satisfied by converting BPM/Tuning/Key from flex-based `Expanded` columns to a single shared fixed-width `SizedBox` (`_kNarrowColumnWidth = 68.0`, sized to fit "Tuning" — the longest of the three headers — without wrapping, reasoned from the header's actual font metrics), while keeping Artist and Song as equally-weighted `Expanded` columns that absorb 100% of the remaining width. Headers (`_headerCell()`) and rows (`_tableCell()`) already shared one set of constants before this change and continue to after it, via the same `flex`/`width` parameter convention on both helper methods, so header/row misalignment is structurally impossible. Because every column slot's widget type is fixed by source code rather than by runtime state, this change introduces none of the element-reconciliation churn risk this ticket has repeatedly diagnosed in the paste-UI block. The table sits in a sibling `Expanded` region to the paste-UI's `Flexible`/`SingleChildScrollView` safety net (Task N) under the same outer `Column`, and this change is a purely horizontal `Row`-layout change that cannot trigger the vertical overflow class that net was built for — reasoned independently, not assumed covered. This entire change is contained within `bulk_entry_screen.dart`'s existing private helpers and constants; no shared/reusable widget outside this file controls these widths, so no Manager authorization is required. `_kNarrowColumnWidth`'s exact value is reasoned from font metrics, not pixel-measured, and Task X requires on-device confirmation before this addendum is considered closed. No off-limits file is implicated; no Stop Condition triggered. Ready for Engineer implementation of Tasks T–V.

---
---

## Addendum 8 — 2026-07-28 — On-Screen Keyboard Renders in Light Mode on Android (App-Wide, Not Bulk-Entry-Scoped)

### Context for This Addendum

This addendum is opened under a distinct Manager scope authorization from Addenda 1–7: it is very likely an **app-wide theming concern**, not a `bulk_entry_screen.dart`-scoped bug like every prior addendum on this ticket. Tony's report: the on-screen software keyboard (e.g., when typing into the Bulk Entry paste field, or any text field anywhere in the app) renders in **light mode** on Android — it should render in **dark mode**, matching BandRoadie's dark theme. iOS's keyboard was to be verified as already-dark, or fixed if not.

Per the Manager's authorization for this addendum: reading `lib/main.dart`, theme configuration (`lib/app/theme/`), and Android/iOS platform configuration was authorized; modifying theme configuration and platform-specific config files was authorized if that's where the fix belongs; `lib/main.dart` was authorized to be touched only if strictly necessary and only in an additive/config-only way, without reordering or removing any step of the init sequence. The standing off-limits files from Addenda 1–7 (`keyboard_aware_wrapper.dart`, `calendar_tab_content.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`) remain off-limits and are unrelated to this concern — not read, not touched.

### Investigation

Read in full for this addendum: `lib/main.dart`, `lib/app/theme/app_theme.dart`, `lib/app/theme/theme_mode_controller.dart`, `android/app/src/main/res/values/styles.xml`, `android/app/src/main/res/values-night/styles.xml`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`, `android/app/build.gradle.kts`, `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift`. Also grepped the entire `lib/` tree for `keyboardAppearance`, `SystemUiOverlayStyle`/`setSystemUIOverlayStyle`, `ThemeData.light()`, and `Theme(data:` overrides, and confirmed via direct read of the installed Flutter SDK source (Flutter 3.44.6, `packages/flutter/lib/src/material/text_field.dart` and `packages/flutter/lib/src/cupertino/text_field.dart`) how `keyboardAppearance` actually resolves on each platform, rather than assuming documented framework behavior without checking this specific SDK version.

**Is the app's theme genuinely dark, or dark-looking-but-light-`ThemeData`?** Genuinely dark, not merely dark-colored widgets. `lib/main.dart`'s `MaterialApp` (`BandRoadieApp.build()`, lines 147–152) sets `theme: AppTheme.lightTheme`, `darkTheme: AppTheme.darkTheme`, and `themeMode: ref.watch(themeModeProvider)`. `AppTheme.darkTheme` (`app_theme.dart` line 45) sets `brightness: Brightness.dark` explicitly on the returned `ThemeData`; `AppTheme.lightTheme` (line 339) sets `brightness: Brightness.light`. `themeModeProvider` (`theme_mode_controller.dart`, `ThemeModeNotifier.build()`, line 9) defaults to `ThemeMode.dark` and is only ever set to `ThemeMode.light` via an explicit in-app toggle (`toggle()`, line 24) persisted to `SharedPreferences` under `light_mode_enabled` — it is never `ThemeMode.system`. So `Theme.of(context).brightness` resolves to a real, explicit `Brightness.dark` app-wide by default (and to `Brightness.light` only if the user has explicitly opted into the app's own light-mode toggle — a real, existing, secondary feature, not a bug). This matters for the fix's shape: the mechanism to drive keyboard appearance from this signal must key off `Theme.of(context).brightness`, not off any Android/iOS *system* dark-mode setting, since BandRoadie's own dark/light state is independent of the device's system-wide setting.

#### iOS — already correct, confirmed by direct SDK read; no fix required

Flutter's `keyboardAppearance` property exists on both `TextField`/`TextFormField` (Material) and `CupertinoTextField`, and is honored only on iOS (documented framework behavior, and the only platform on which UIKit exposes a `UIKeyboardAppearance` API at all). Two things had to be checked, not assumed:

1. **Does BandRoadie's paste `TextField` (or any `TextField` in the app) explicitly override `keyboardAppearance`, forcing it light?** No — a repo-wide `grep -rn "keyboardAppearance" lib/` returns zero matches. No screen anywhere sets this property.
2. **What does Flutter do when `keyboardAppearance` is left unset (`null`)?** Checked directly against the installed SDK (`/opt/homebrew/share/flutter`, Flutter 3.44.6), not from memory of framework behavior in general:
   - `EditableText`'s own constructor default (`editable_text.dart` line 889) is `this.keyboardAppearance = Brightness.light` — i.e., in isolation, an unthemed `EditableText` defaults to a **light** keyboard.
   - However, Material's `TextField` (what `bulk_entry_screen.dart` and, per a broader grep, the overwhelming majority of the app's input fields use) does **not** pass that raw default through. `text_field.dart` line 1550: `final Brightness keyboardAppearance = widget.keyboardAppearance ?? theme.brightness;` — Material's `TextField` explicitly resolves to the ambient `Theme.of(context).brightness` whenever the widget-level property is left `null`, overriding `EditableText`'s own light default before it ever reaches the platform channel. `CupertinoTextField` does the same (`cupertino/text_field.dart` line 1506: `widget.keyboardAppearance ?? CupertinoTheme.brightnessOf(context)`).
   - Since BandRoadie's `MaterialApp.themeMode` defaults to `ThemeMode.dark` (and is never `ThemeMode.system`), `Theme.of(context).brightness` is `Brightness.dark` everywhere in the app by default, for every Material `TextField`/`TextFormField` — including the Bulk Entry paste field and every other input field in the app — with no per-field configuration required.

**Conclusion: iOS's keyboard already renders in dark mode today, by construction, via Flutter's own default resolution chain (`keyboardAppearance` → `Theme.of(context).brightness` → BandRoadie's dark `ThemeData`) — not because anything already explicitly forces it.** No code change is needed on iOS. **Confidence: HIGH** on the mechanism (directly confirmed against this project's exact installed Flutter SDK source, not general framework documentation) — consistent with this ticket's established practice, Task Z below still requires a real-device iOS confirmation before this half of the addendum is considered closed, since this ticket has twice before found code-path-only confidence insufficient (Addenda 1 and 2).

**Considered and rejected:** setting `UIUserInterfaceStyle` to `Dark` in `ios/Runner/Info.plist`. This key forces the entire native UIKit chrome (including any native alerts, action sheets, or share sheets Flutter/plugins present) into dark mode unconditionally at the OS level, regardless of BandRoadie's own Flutter-level theme state. Since the app already correctly derives keyboard (and everything else) brightness from `Theme.of(context).brightness`, adding this key would be redundant for the keyboard specifically and would carry a **larger** and unnecessary blast radius (permanently forcing native chrome dark even if a user is using BandRoadie's own light-mode toggle) for no benefit. Not applied.

#### Android — genuine bug; root cause confirmed by direct config/resource-qualifier read, not guessed

**Confidence: HIGH on the mechanism** (`Configuration.uiMode`'s night flag, and Android resource-qualifier resolution based on it, are directly confirmed from the actual files in this repo, not inferred) — **MEDIUM-HIGH on this being the complete explanation**, since IME dark/light rendering is ultimately the *keyboard app's* (Gboard, Samsung Keyboard, SwiftKey, etc.) own decision and different IME implementations are not guaranteed to be pixel-identical in how strictly they honor a hosting app's forced `uiMode`; per this ticket's own established, hard-won practice (Addenda 1, 2, 4), this is flagged honestly rather than asserted as certain, and Task Z requires real-device confirmation before this addendum is closed.

Flutter's `keyboardAppearance` property has **no effect on Android at all** — it is a UIKit-only concept with no Android platform-channel equivalent; the framework silently ignores it on this platform. Android's on-screen keyboard determines its own light/dark rendering primarily from the **`Configuration.uiMode` night flag of the app window it is currently attached to**, not from anything Flutter-level.

`android/app/src/main/res/values/styles.xml` and `android/app/src/main/res/values-night/styles.xml` are the standard, unmodified `flutter create` template output — confirmed by direct read, and confirmed not to be regenerated/managed by a build-time tool (`grep flutter_native_splash pubspec.yaml` returns nothing; no splash-generation package is in use). Both files define the same two style names (`LaunchTheme`, `NormalTheme`), but with different Android system-theme parents depending on which resource-qualifier folder Android selects at runtime:

- `values/styles.xml` (default / day) — `NormalTheme` parents `@android:style/Theme.Light.NoTitleBar`.
- `values-night/styles.xml` (night) — `NormalTheme` parents `@android:style/Theme.Black.NoTitleBar`.

**Critically, Android chooses between these two folders based on the *device's system-wide* dark/light setting (`Configuration.uiMode`'s night flag at the OS level) — not based on BandRoadie's own in-app `ThemeMode` state**, which lives entirely in Dart (`themeModeProvider`) and `SharedPreferences` and has no native counterpart or platform-channel bridge to Android's `Configuration`. `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt` is confirmed, by direct read, to be a bare `class MainActivity : FlutterActivity()` with no method overrides at all — no `attachBaseContext`, no `Configuration` handling, nothing that would decouple the Activity's `uiMode` from the system-wide setting.

**The concrete failure mode this produces, matching Tony's report exactly:** BandRoadie's Flutter UI defaults to dark (`ThemeMode.dark`, independent of system setting) — but on a device where the **system-wide** Android dark-mode setting is off (a very common real-world case: plenty of users leave their device in system light mode while individual apps default to their own dark theme), `values/styles.xml`'s `Theme.Light.NoTitleBar`-derived `NormalTheme` applies to the Activity, and `Configuration.uiMode`'s night flag is `UI_MODE_NIGHT_NO` for that window. Android's software keyboard, reading that flag from the currently-focused app window, renders itself in light mode — visibly mismatched against BandRoadie's own dark Flutter UI underneath it. This reproduces on **every** text field in the app (Bulk Entry's paste field is simply the one Tony happened to be typing into when he noticed it), because the mechanism is a single, app-wide native `Configuration` signal, not anything scoped to a specific screen or widget.

`android/app/src/main/AndroidManifest.xml`'s `<activity>` tag already lists `uiMode` in `android:configChanges` (line 21) — meaning the Activity is already set up to handle `uiMode` configuration changes without being torn down and recreated, which is a relevant, pre-existing precondition for the fix below (forcing `uiMode` at runtime won't trigger an unwanted Activity restart).

### Proposed Solution

**Force `Configuration.uiMode`'s night flag to `UI_MODE_NIGHT_YES` unconditionally in `MainActivity.kt`, via an `attachBaseContext()` override, independent of the device's system-wide dark/light setting.** This is the standard, minimal, well-established Android idiom for "app forces its own dark theme regardless of system setting, and needs the on-screen keyboard/IME to follow" — it does not require Flutter/Dart changes, does not touch `lib/main.dart`, and is confined to the single native Activity file that already hosts BandRoadie's entire UI.

```kotlin
package com.bandroadie.app

import android.content.Context
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun attachBaseContext(newBase: Context) {
        val configuration = Configuration(newBase.resources.configuration)
        configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            Configuration.UI_MODE_NIGHT_YES
        super.attachBaseContext(newBase.createConfigurationContext(configuration))
    }
}
```

**Why this is the correct, minimal, root-cause fix (not a workaround):**
- It targets the actual mechanism identified above (the Activity's `Configuration.uiMode` night flag, which Android's IME reads to decide its own light/dark rendering) directly, rather than any Flutter-level or visual-only approximation.
- It requires no Dart code changes and no Flutter-side plumbing — the fix lives entirely at the native Android layer that owns this specific signal, matching the Manager's authorization to modify platform-specific config files "if that's where the actual fix belongs."
- `AndroidManifest.xml`'s existing `uiMode` entry in `android:configChanges` (confirmed present, unmodified by this addendum) means this forced value is honored cleanly at every configuration-change event without an Activity recreation.
- As a direct, correctly-desired side effect: forcing `uiMode` to night also means Android will now consistently resolve to `values-night/styles.xml`'s `Theme.Black.NoTitleBar`-derived `NormalTheme`/`LaunchTheme` for the native window background/chrome behind and around the Flutter UI, regardless of the system-wide setting — previously, on a system-light device, that native chrome was `Theme.Light.NoTitleBar` (light) while the Flutter UI on top of it was dark, a second, smaller, previously-unreported mismatch that this same fix also resolves as a natural consequence, not a separate change.
- It touches exactly one file, adds no new dependency, and does not modify `AndroidManifest.xml`, `styles.xml` (either variant), `build.gradle.kts`, or any Dart file.

**Tradeoff, stated explicitly:** BandRoadie has a real, existing in-app light-mode toggle (`theme_mode_controller.dart`'s `ThemeModeNotifier.toggle()`, persisted via `SharedPreferences`). This fix forces the Android-native `uiMode` (and therefore the Android keyboard's rendering) to dark **unconditionally**, with no live link to that toggle. If a user switches BandRoadie to light mode via the in-app toggle, the Android on-screen keyboard will continue to render dark, no longer matching the app's (now light) UI — a mismatch in the opposite direction from the one being fixed here. This is a known, accepted limitation of the minimal fix, not an oversight: Tony's request describes the keyboard matching "the app's dark theme" — the app's default, and by a wide margin its primary, state — not parity with the secondary light-mode toggle. A fully reactive fix (keeping the native `uiMode` in sync with the live `themeModeProvider` state, including on toggle and on app resume) would require a `MethodChannel` from `theme_mode_controller.dart` to native Android code, invoked from `ThemeModeNotifier.toggle()` and `_loadFromPrefs()`, calling into an Android-side handler to update `Configuration.uiMode` (or use `AppCompatDelegate`-equivalent APIs) at runtime — a materially larger, cross-cutting change spanning both Dart and native code, well beyond "the smallest change that fully solves the problem" for what was reported. **This is flagged as a follow-up, not implemented in this addendum.**

**Alternative considered and rejected:** editing `values/styles.xml` directly (e.g., making its `NormalTheme` also parent `Theme.Black.NoTitleBar`, matching `values-night/styles.xml`, removing the day/night distinction at the style level). Rejected because Android resource-qualifier selection (`values/` vs. `values-night/`) determines which *style definition* applies visually — it does not itself alter the `Configuration.uiMode` night flag that the OS and IME actually query. Editing the style alone would make the Activity's chrome *look* dark via `Theme.Black`'s colors while `Configuration.uiMode` remained `UI_MODE_NIGHT_NO` on a system-light device — the keyboard would still read the flag as "not night" and would very likely still render light. The `attachBaseContext` override is necessary specifically because it changes the underlying `Configuration` value itself, not just which style resolves from it.

**Alternative considered and rejected:** wiring a live Dart↔native `MethodChannel` to keep Android's `uiMode` in sync with `themeModeProvider` on every toggle. Considered as the "complete" fix but rejected for this addendum specifically because it is a materially larger change (new channel, new native handler, new Dart call sites in `theme_mode_controller.dart`) than the reported problem calls for, and Tony's framing describes matching the app's default dark theme, not achieving live parity with an already-existing, separately-toggleable feature. Documented above as a known follow-up rather than silently declined.

### Files to Modify

| File | What changes |
|------|-------------|
| `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt` | Add an `attachBaseContext(Context)` override that forces `Configuration.uiMode`'s night flag to `UI_MODE_NIGHT_YES` unconditionally via `createConfigurationContext`, before delegating to `FlutterActivity`'s own `attachBaseContext`. No other change to this file. |

**Files read and cleared, no modification required:** `lib/main.dart` (init sequence confirmed untouched and not required to change — the keyboard-appearance chain already resolves correctly via `MaterialApp.themeMode`/`theme`/`darkTheme`, which are pre-existing, unmodified properties), `lib/app/theme/app_theme.dart`, `lib/app/theme/theme_mode_controller.dart`, `android/app/src/main/res/values/styles.xml`, `android/app/src/main/res/values-night/styles.xml` (both correct as-is once `uiMode` is forced — no edit needed), `android/app/src/main/AndroidManifest.xml` (already lists `uiMode` in `android:configChanges`; no edit needed), `android/app/build.gradle.kts` (`minSdk` uses Flutter's own default, well below what `createConfigurationContext`/`Configuration.uiMode` require; no edit needed), `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift` (both confirmed to need no change — see iOS section above).

**Files off-limits (unchanged from Addenda 1–7, none implicated by this addendum):** `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart` — not read, not touched; no Stop Condition triggered.

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** none
**New files:** none
**Init-order change:** **none.** `lib/main.dart`'s `Future<void> main()` sequence (`WidgetsFlutterBinding.ensureInitialized()` → URL strategy → orientation lock → `AppVersionService.init()` → `validateSupabaseConfig()` → `Supabase.initialize()` → `Firebase.initializeApp()` → `DeepLinkService` setup → `runApp()`) is not read as needing any change and is not modified — this fix is entirely native-Android and sits below and before any of that Dart-level sequence executes (`attachBaseContext` runs during Android `Activity` construction, prior to Flutter engine/Dart entrypoint execution).
**AI_DECISIONS.md entry:** not required — no init-order, config-loading, auth-flow, RLS, SECURITY DEFINER, or new-dependency change is involved (per Guardrails §1 and OPERATING_MODEL.md's Safety Non-Negotiables).

### Engineer Task Breakdown (Addendum 8)

Execute after (not replacing) all prior work already completed on this ticket.

**Task Y — Force Android's native `uiMode` to dark, unconditionally**
1. In `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt`, add the imports `android.content.Context` and `android.content.res.Configuration`.
2. Override `attachBaseContext(Context)` exactly as specified in Proposed Solution, above: build a new `Configuration` copying `newBase.resources.configuration`, set its `uiMode` to `UI_MODE_NIGHT_YES` (clearing the existing night-mode bits first via `UI_MODE_NIGHT_MASK.inv()`), then call `super.attachBaseContext(newBase.createConfigurationContext(configuration))`.
3. Do not add a `MethodChannel`, do not modify `AndroidManifest.xml`, `styles.xml` (either variant), or any Dart file as part of this task.
4. Do not modify `ios/Runner/Info.plist` or `ios/Runner/AppDelegate.swift` — iOS requires no code change (see Investigation, above).

**Task Z (verification only, no further code change expected)**
On a real device, full stop/restart (not hot reload), consistent with this ticket's established practice:
1. **Android, with the device's system-wide dark-mode setting turned OFF (light):** open the Bulk Entry modal (or any other screen with a text field) and tap into a text field. Confirm the on-screen keyboard now renders in dark mode, matching BandRoadie's dark UI — this is the specific case that was broken and that this task's fix targets.
2. **Android, with the device's system-wide dark-mode setting turned ON:** repeat step 1. Confirm the keyboard is (and remains) dark — this case may have already looked correct by coincidence before this fix (system dark happens to line up with app dark), but should be explicitly re-confirmed now that `uiMode` is forced rather than incidentally correct.
3. **Android, with BandRoadie's own in-app light-mode toggle switched on** (Settings → light mode, or equivalent in-app control wired to `theme_mode_controller.dart`): confirm the on-screen keyboard renders dark while the app's own UI renders light — this is the stated, accepted tradeoff above, not a new defect; confirm it matches expectations rather than looking like a regression.
4. **iOS, default (dark) state:** tap into a text field. Confirm the keyboard already renders dark — this is expected to already pass, per the Investigation's HIGH-confidence code-path analysis, and this step exists to close the gap between code-path confidence and real-device confirmation per this ticket's established practice.
5. **iOS, with BandRoadie's in-app light-mode toggle switched on:** confirm the keyboard renders light, matching the app's (now light) UI — confirms the `Theme.of(context).brightness`-driven mechanism correctly follows the toggle in both directions on iOS (unlike the accepted one-directional limitation on Android, per step 3).
6. Confirm no regression to any of Addenda 1–7's fixes (Bulk Entry focus/glitch behavior, table population, paste-field sizing, column widths) — this addendum touches no file any of those addenda modified.

### Verification Plan Addendum (Addendum 8)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 40:** Android device with system-wide dark mode OFF — on-screen keyboard renders dark when focusing any text field (primary fix target).
- **PRE-DEPLOY TEST 41:** Android device with system-wide dark mode ON — on-screen keyboard renders dark (re-confirm, now via the forced mechanism rather than coincidence).
- **PRE-DEPLOY TEST 42:** Android device with BandRoadie's in-app light-mode toggle on — confirm keyboard is dark while app UI is light (accepted, documented tradeoff, not a regression).
- **PRE-DEPLOY TEST 43:** iOS device, default dark state — confirm keyboard is dark (expected to already pass; closes the code-path-vs-device-confirmation gap).
- **PRE-DEPLOY TEST 44:** iOS device, in-app light-mode toggle on — confirm keyboard is light, matching the toggle (confirms bidirectional correctness on iOS).
- **PRE-DEPLOY TEST 45 (regression):** Full Bulk Entry flow (Addenda 1–7) — modal opens, keyboard focus/glitch-free, table populates, paste field sizing and column widths all unchanged — confirms this addendum's native-Android-only, single-file change has no interaction with any prior fix.

**Tier 2 — Post-deployment (after merge):** Real-device confirmation of Tests 40–44 carries the primary verification burden, consistent with this ticket's established practice — IME dark/light rendering is OS/keyboard-app-dependent behavior that code-path analysis alone cannot fully guarantee, per this ticket's own history (Addenda 1 and 2).

### QA Regression Areas (Addendum 8)

QA must specifically test, on real devices (not simulator/emulator alone, given this concern is about actual IME rendering):
1. Android on-screen keyboard renders dark when focusing any text field, regardless of the device's system-wide dark/light setting (primary fix).
2. Android on-screen keyboard's behavior when BandRoadie's own in-app light-mode toggle is active — confirm the documented one-directional limitation (keyboard stays dark) matches expectations and is not reported as a new bug.
3. iOS on-screen keyboard renders dark by default, and correctly switches to light if BandRoadie's in-app light-mode toggle is used.
4. No regression to any Addenda 1–7 Bulk Entry behavior (this addendum touches no file those addenda modified).
5. General smoke test across a few other text-entry surfaces in the app (e.g., login screen, a gig/rehearsal note field) to confirm the fix is genuinely app-wide, not limited to Bulk Entry's paste field.

### System Impact Map

| System | Impact |
|--------|--------|
| Gigs | **affected** — any text field in this feature area inherits the same app-wide keyboard-appearance behavior. |
| Rehearsals | **affected** — same reasoning as Gigs. |
| Setlists / Catalog | **affected** — includes, but is not limited to, the Bulk Entry paste field this ticket has focused on through Addenda 1–7. |
| Members / RBAC | **affected** — any text field (e.g., invite forms) inherits the same behavior. |
| Auth / Session | **affected** — login/signup text fields inherit the same behavior; no auth logic itself is touched. |
| Routing | unaffected |
| Notifications | unaffected |
| Platform (iOS / Android / Web / macOS) | **Android is the confirmed-broken case, fixed by this addendum's native `Configuration.uiMode` override.** **iOS confirmed already-correct** by direct SDK source analysis, no code change. **Web:** unaffected — browsers do not expose an on-screen software keyboard under Flutter's control in the way iOS/Android do, and this fix is entirely native-Android code with no web code path. **macOS:** unaffected — no software on-screen keyboard exists there either, and this fix touches only `android/`. |

### Regression Risk

**LEVEL: LOW**

Rationale:
- The only code change is a single `attachBaseContext()` override added to one native Android file (`MainActivity.kt`), which currently has no overrides at all — there is no existing native behavior in this file that could be disturbed.
- No Dart file is modified. No init-order change (Guardrails §1) — `lib/main.dart`'s sequence is untouched, and this fix executes at the native Android `Activity` layer, prior to and independent of the Dart entrypoint sequence.
- `AndroidManifest.xml` already declares `uiMode` in `android:configChanges` (pre-existing, unmodified), so forcing this value does not trigger an unwanted Activity recreation — confirmed, not assumed.
- Does not touch `styles.xml` (either variant), `build.gradle.kts`, `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift`, or any file from Addenda 1–7's scope (`bulk_entry_screen.dart`, `keyboard_aware_wrapper.dart`, `calendar_tab_content.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`).
- The one accepted, explicitly-documented behavioral tradeoff (Android keyboard no longer reacting to BandRoadie's in-app light-mode toggle) is a known, stated limitation of the minimal fix, not an unintended side effect — flagged for Tony's awareness and QA's regression checklist rather than silently shipped.
- As with every prior round in this ticket, this must be confirmed on real devices (both platforms, all three theme-state combinations in Task Z) before being considered closed — IME rendering is OS/keyboard-app behavior that code-path reasoning, however carefully sourced from the actual installed SDK and repo files, cannot fully substitute for.

### Out of Scope (Addendum 8)

1. A live `MethodChannel`-based sync between `theme_mode_controller.dart`'s `themeModeProvider` and Android's native `Configuration.uiMode`, which would make the Android keyboard's appearance reactively follow BandRoadie's in-app light-mode toggle in real time — considered, described as a known follow-up, and not implemented here; the reported problem is about matching the app's default dark theme, and the accepted one-directional tradeoff is stated explicitly above.
2. Setting `UIUserInterfaceStyle` in `ios/Runner/Info.plist` — considered and rejected; iOS already resolves correctly via `Theme.of(context).brightness`, and this key would have a larger, unnecessary blast radius (forcing all native UIKit chrome dark unconditionally, including during BandRoadie's own light-mode toggle) for no benefit.
3. Editing `android/app/src/main/res/values/styles.xml` or `values-night/styles.xml` — considered and rejected; resource-qualifier style selection does not itself change the `Configuration.uiMode` flag the IME actually reads, so editing styles alone would not fix the reported symptom.
4. Any change to `lib/main.dart`'s initialization sequence — not required; this fix is entirely native-Android and does not interact with the Dart entrypoint's ordering, and Guardrails §1 forbids reordering it regardless.
5. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `setlist_repository.dart`, or `setlist_detail_screen.dart` — none implicated; all remain off-limits per this ticket's standing Stop Conditions.
6. Any change to `bulk_entry_screen.dart` or any other file modified by Addenda 1–7 — this is a distinct, app-wide concern with its own root cause and fix, unrelated to the focus/glitch, table-population, paste-field-sizing, or column-width work already shipped on this ticket.

---

**Architect Signature (Addendum 8):** This addendum diagnoses an app-wide theming concern, distinct in scope from every prior addendum on this ticket. **iOS was investigated and confirmed already correct** by direct read of the installed Flutter SDK source: Material's `TextField` resolves `keyboardAppearance` to `Theme.of(context).brightness` whenever left unset (confirmed no explicit override exists anywhere in `lib/`), and BandRoadie's `MaterialApp` defaults to a genuinely dark `ThemeData` (`brightness: Brightness.dark`, `themeMode: ThemeMode.dark` by default, never `ThemeMode.system`) — so no iOS code change is needed. **Android was confirmed as the genuine bug**: Flutter's `keyboardAppearance` has no effect on Android at all; Android's on-screen keyboard instead reads the hosting Activity's native `Configuration.uiMode` night flag, which BandRoadie's stock, unmodified `flutter create`-template `styles.xml`/`values-night/styles.xml` pair ties to the device's *system-wide* dark/light setting — completely independent of BandRoadie's own in-app dark theme. The fix is a single `attachBaseContext()` override in `MainActivity.kt` that forces `Configuration.uiMode` to night unconditionally, matching the app's default dark theme, with no Dart-side change and no init-order change. This does not achieve live parity with BandRoadie's existing in-app light-mode toggle (a stated, accepted tradeoff, with a documented follow-up path via `MethodChannel` if Tony wants that later) — it is the smallest change that fully solves the problem as reported. No off-limits file (from this addendum's own authorization or from Addenda 1–7's standing list) is implicated; no Stop Condition triggered; `lib/main.dart`'s init sequence is read, confirmed unmodified, and not required to change. Ready for Engineer implementation of Task Y; Task Z (real-device verification across both platforms and all relevant theme-state combinations) must be completed and reported before this addendum is considered closed, consistent with this ticket's established practice.

---
---

## Addendum 9 — 2026-07-28 — Re-Focusing the Paste Field After Songs Are Loaded Should Re-Expand the View

### Context for This Addendum

Back to `bulk_entry_screen.dart`-scoped work (Addendum 8 was an unrelated, app-wide Android keyboard-theming concern and is not touched here). All of this ticket's prior fixes — the focus/glitch fix (Addenda 1, 3, 5), the empty-table fix (Addendum 4 Task K), the field-density decoupling (Addendum 6), and the column-width work (Addendum 7) — remain in place and are not modified.

**Tony's request:** once songs are already loaded into the table (`_hasLoadedSongs == true`), tapping back into the CSV paste field to paste additional songs currently renders the *compact* treatment — the field is very short (`minLines: 1`, dense), and "Load Songs" ends up crowded/covered by the table, the keyboard's "Done" toolbar, and the footer ("Add Songs"/"Cancel"). None of those three are usable or needed while the user is actively re-pasting. The request is for tapping into the field, in this state, to render the same expanded treatment already shown the very first time the modal is used pre-load: full-height field, unobstructed "Load Songs" button, table/footer out of the way. When the field loses focus again, the view should revert to exactly what today's `_hasLoadedSongs`/`keyboardHeight` logic already produces (compact field, table visible, footer visible) — this addendum does not change that reverted state at all.

This requires a state dimension this file does not yet track: whether the CSV paste field currently has focus, independent of both `keyboardHeight` (which only tells you whether the OS keyboard is up, not which widget requested it — a row cell's focus opens the keyboard too) and `_hasLoadedSongs`.

**Given this ticket's history in this exact file** (three separate regressions — Addendum 2's wrapping `Container`, Addendum 4 Task I's conditional `Padding`/`Flexible` swap at the outer `Column`'s first-child slot — both caused by making a `Column`'s direct-child slot swap *widget type* based on state, rather than varying properties inside a type-stable wrapper), this addendum treats the reconciliation-safety analysis as the primary deliverable, not an afterthought. See "Reconciliation-Safety Verification," below, which walks the current file's actual structure rather than asserting safety by analogy.

### Current File State (Confirmed by Direct Read, Not Assumption)

Read `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` in full for this addendum (932 lines). Relevant current structure:

- `build()` (line 350) computes three booleans up front:
  - `keyboardHeight` (line 351) — `MediaQuery.of(context).viewInsets.bottom`.
  - `showFullPasteUi` (line 352) — `keyboardHeight == 0 && !_hasLoadedSongs`. Gates exactly two things inside `pasteUiBlock`'s inner `Column`: the top padding value (line 360) and the intro-text/bordered-info-box collection-`if` (line 367). **Not touched by this addendum** — see "Why `showFullPasteUi` Is Left Alone," below.
  - `showExpandedPasteField` (line 353) — `!_hasLoadedSongs`. Gates three properties on the CSV `TextField` itself: `minLines` (line 429), `isDense` (line 436), `contentPadding` (lines 445–447). Introduced by Addendum 6 specifically to decouple the field's own size from `keyboardHeight` while preserving the `_hasLoadedSongs`-driven compaction. **This is the boolean this addendum widens.**
- The CSV `TextField` itself (lines 425–470) is a direct, unwrapped child of `pasteUiBlock`'s inner `Column`, carrying `key: const ValueKey('bulk-entry-csv-field')` and no `focusNode:` — it still relies on `EditableText`'s own implicit, internally-created `FocusNode`. This is the exact clean structure Addendum 3 restored and Addendum 5/6 have since built on without disturbing.
- `pasteUiBlock` (the whole `Padding` subtree, lines 357–515) is assigned to a local variable, then wrapped once, unconditionally, at the outer `Column`'s first child (lines 519–527):
  ```dart
  Flexible(
    flex: keyboardHeight > 0 ? 1 : 0,
    child: SingleChildScrollView(
      physics: keyboardHeight > 0
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: pasteUiBlock,
    ),
  ),
  ```
  This is Task N (Addendum 5) — the wrapper's own type never changes across any state; only `flex` and `physics` vary. **Not touched by this addendum.**
- The outer `Column`'s remaining children (lines 528–550):
  ```dart
  if (_hasLoadedSongs) ...[
    const SizedBox(height: Spacing.space12),
    _buildColumnHeaders(),
    Expanded(child: GestureDetector(onTap: _dismissKeyboard, child: ListView.builder(...))),
    _buildAddRowButton(),
  ] else
    const Expanded(child: SizedBox.shrink()),
  if (keyboardHeight > 0) _buildKeyboardToolbar(),      // Container, key: 'bulk-entry-keyboard-toolbar'
  if (_hasLoadedSongs || keyboardHeight == 0)
    _buildFooter(hasValid, validCount),                  // Container, key: 'bulk-entry-footer'
  ```
  The table block (line 528) is a collection-`if`/`else` whose two branches have entirely different widget lists (4 widgets vs. 1 `Expanded`) — this already swaps type/count at this slot whenever `_hasLoadedSongs` flips, and has done so safely since Addendum 4. The toolbar and footer `Container`s each carry their own stable, distinct key (Addendum 2 Task A), so their independent present/absent toggling (driven by `keyboardHeight` for the toolbar, by `_hasLoadedSongs || keyboardHeight == 0` for the footer) does not collide.

### Design

**1. New state: `_isPasteFieldFocused`, tracked via an explicit `FocusNode` on the existing `TextField`.**

Add two new fields to `_BulkEntryScreenState`, alongside `_csvController`:
```dart
final FocusNode _csvFocusNode = FocusNode();
bool _isPasteFieldFocused = false;
```
In `initState()`, register a listener:
```dart
_csvFocusNode.addListener(_handleCsvFocusChange);
```
Add the handler:
```dart
void _handleCsvFocusChange() {
  if (!mounted) return;
  setState(() {
    _isPasteFieldFocused = _csvFocusNode.hasFocus;
  });
}
```
In `dispose()`, add `_csvFocusNode.dispose();` alongside the existing `_csvController.dispose();` (Guardrails §5: every `FocusNode` must be disposed). The `mounted` guard is defensive, matching Guardrails §5's `setState`-lifecycle caution, even though this listener fires synchronously off a focus-manager notification rather than after an `async` gap.

Wire the node onto the existing `TextField` (line 425) as an **additional named argument**, alongside the existing `key:`/`controller:`:
```dart
TextField(
  key: const ValueKey('bulk-entry-csv-field'),
  controller: _csvController,
  focusNode: _csvFocusNode,   // new
  maxLines: 5,
  minLines: showExpandedPasteField ? 3 : 1,
  ...
),
```
No wrapping widget is introduced. No other `TextField` in the file (the five `_TableTextField` row cells, which already pass their own `focusNode:`) is touched.

**2. Widen `showExpandedPasteField` in place — do not introduce a third boolean.**

```dart
final showExpandedPasteField = !_hasLoadedSongs || _isPasteFieldFocused;
```
This single change is the crux of the addendum. Because every downstream consumer of `showExpandedPasteField` already exists and is already correctly wired, widening its own definition is sufficient to make the field's size (`minLines`/`isDense`/`contentPadding`) respond to focus — no changes needed at those three call sites.

**3. Reconcile with the table-visibility and footer-visibility conditions.**

- **Table block (line 528):** change `if (_hasLoadedSongs) ...[` to `if (_hasLoadedSongs && !showExpandedPasteField) ...[`. Since `showExpandedPasteField` is `true` whenever either `!_hasLoadedSongs` or the field is focused, this is equivalent to `_hasLoadedSongs && _hasLoadedSongs && !_isPasteFieldFocused` = `_hasLoadedSongs && !_isPasteFieldFocused` — i.e., the table renders exactly as it does today whenever the paste field is *not* focused, and falls back to the existing `else` branch (`Expanded(child: SizedBox.shrink())` — the same widget already used pre-load) whenever it *is*.
- **Footer (line 548):** change `if (_hasLoadedSongs || keyboardHeight == 0)` to `if ((_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0)`. Worked through all four `(_hasLoadedSongs, focus)` combinations crossed with both `keyboardHeight` states:

  | `_hasLoadedSongs` | field focused | `keyboardHeight` | Footer shows? | Matches |
  |---|---|---|---|---|
  | false | (n/a — nothing else to focus pre-load) | `== 0` | yes | today, unchanged |
  | false | (n/a) | `> 0` | no | today, unchanged (Addendum 4 Task J) |
  | true | no (browsing / editing a row cell) | either | yes | today, unchanged |
  | true | **yes (this addendum's case)** | `> 0` | **no** | **new — the fix** |
  | true | **yes** | `== 0` (hardware keyboard, no on-screen keyboard) | yes | matches the pre-load hardware-keyboard cell, which also shows the footer — symmetric, not a special case |

  The one new behavior is the fourth row; every other cell is provably unchanged because the added term (`_hasLoadedSongs && !showExpandedPasteField`) only differs from the original `_hasLoadedSongs` term when the field is focused, and the `keyboardHeight == 0` disjunct is untouched.

- **`_buildKeyboardToolbar()`'s condition (line 547, `if (keyboardHeight > 0)`) is left unchanged.** In the already-shipped, already-verified pre-load "first tap" flow, the toolbar is visible for the entire duration the keyboard is up (nothing in this ticket has ever gated it on anything else). Re-focusing the paste field post-load opens the same on-screen keyboard, so parity with "the exact same expanded view as the very first time" means the toolbar should behave identically here too — visible whenever `keyboardHeight > 0`, which it already is. No change needed.
- **`showFullPasteUi` (padding-top, intro-text/info-box gating) is left unchanged.** Tony's request is specifically about field size, "Load Songs" reachability, and table/footer clutter — not about re-showing the intro paragraph or the bordered column-order box. In the pre-load baseline this addendum is matching, that content *already* hides the instant the keyboard opens (`showFullPasteUi` requires `keyboardHeight == 0`), which is deliberate, already-shipped, out-of-scope behavior from `bulk-import-flexible-columns` and unrelated to Tony's ask here. Widening `showFullPasteUi` to include focus would reintroduce that content while the keyboard is open, which is not what "the exact same expanded view as the very first time" means once the keyboard has actually opened — it means the same *field/button/table/footer* treatment, which is fully covered by `showExpandedPasteField`, the table condition, and the footer condition above.

### What Happens to Already-Loaded Table Content While the Field Is Focused

The table condition change (`_hasLoadedSongs && !showExpandedPasteField`) means the entire table subtree — `_buildColumnHeaders()`, the `ListView.builder`, `_buildAddRowButton()` — is **unmounted**, not merely scrolled off-screen, whenever the paste field is focused (same mechanism already used pre-load, not a new one). This is safe and loses no data:

- Every row's actual state (`artist`/`song`/`bpm`/`tuning`/`key` `TextEditingController`s and their `FocusNode`s) lives in `_RowData` objects held in the `_rows` list on `_BulkEntryScreenState` — plain Dart objects, not tied to the `ListView`'s `Element` tree. Unmounting the `ListView.builder` does not dispose or clear them; only `_removeRow`/`_populateTableFromParseResult`/the empty-text-clear branch explicitly call `.dispose()` on a row, and none of those run merely from focusing the paste field.
- When the field loses focus again (blur, or tapping "Load Songs"/"Done"), `showExpandedPasteField` becomes `false` (assuming `_hasLoadedSongs` is still `true`), the table condition flips back to its `if` branch, and `ListView.builder(itemCount: _rows.length, itemBuilder: ...)` rebuilds from the same `_rows` list with the same controllers/focus nodes — every previously-entered value reappears exactly as it was. This is the identical mechanism this ticket already relies on for the `_hasLoadedSongs` false→true transition (Addendum 4) and needed no new safeguard then; it needs none here either.
- The user's actual scroll position within the table is not preserved across an unmount/remount (a fresh `ListView.builder` starts at its default scroll offset), which is a minor, acceptable cosmetic side effect — not a data-loss concern, and not something Tony's request describes as a problem. Not addressed further; flagged in Out of Scope.

### Reconciliation-Safety Verification (Read Against the Current File, Not by Analogy)

This is the section the task explicitly calls for verifying rather than assuming. Confidence stated at the end of each point.

**1. Does adding `focusNode: _csvFocusNode` to the existing `TextField` introduce any new widget-type instability at any `Column` slot?**

No. `Widget.canUpdate` (and therefore every `Column`/`Element.updateChildren` reconciliation pass in this file) compares only `runtimeType` and `key`. The `TextField` at line 425 keeps the exact same `runtimeType` (`TextField`) and the exact same `key` (`ValueKey('bulk-entry-csv-field')`) before and after this change, in every state, on every rebuild — only its argument list gains one more named parameter. This is categorically different from Addendum 2's mistake, which changed the widget occupying that `Column` slot from `TextField(key: ...)` to `Container(key: null)` — a `runtimeType` change at the slot itself. Adding a constructor argument to an unchanged widget type/key is not a slot-type change by any definition Flutter's reconciliation uses; it is a `didUpdateWidget`-only path (`StatefulElement.update()` swaps the `_widget` reference and calls `didUpdateWidget`, without deactivating/remounting the `Element` or its `State`). **Confidence: HIGH** — this is a direct, deterministic property of `Widget.canUpdate`'s two-field check, not a claim about undocumented framework internals, and is exactly the same reasoning Addendum 1 already relied on (correctly) for adding the `Key` itself.

**2. Does the field's `Element` survive the transition from an implicit, internally-created `FocusNode` to the new explicit `_csvFocusNode`?**

This transition happens exactly once, at the moment this code change is deployed and the app is rebuilt/restarted — not repeatedly at runtime. `EditableText`/`RawEditableText`'s internal `_createLocalFocusNode()` fallback only exists to cover the case where `widget.focusNode` is `null`; once the widget is compiled with a non-null `focusNode:` argument, every build of this `TextField` — including its very first — uses `_csvFocusNode` from the start, since `initState`/first build sees the new widget code, not a live transition on an already-running field. There is no runtime moment in a single app session where the same mounted `TextField` `Element` flips from implicit to explicit focus node — that only happens across a code deploy (app restart), which trivially preserves nothing across restarts anyway. **Confidence: HIGH.**

**3. Does the table-visibility condition change (`if (_hasLoadedSongs)` → `if (_hasLoadedSongs && !showExpandedPasteField)`) introduce a new hazard at that `Column` slot?**

The slot already swaps between two structurally different branches (4 widgets vs. 1 `Expanded`) whenever `_hasLoadedSongs` flips — this is pre-existing, shipped since Addendum 4, and has not been the site of any regression in Addenda 4–8. The reason this kind of swap is safe here, unlike the CSV field's own slot in Addenda 2/4, is that **nothing being destroyed in the discarded branch holds state that needs cross-swap identity preservation**: the `ListView.builder`, `_buildColumnHeaders()`, and `_buildAddRowButton()` hold no `FocusNode`/controller of their own outside of what's supplied via `_rows` (owned by `State`, external to the `Element` tree, as established above); the row cells' `FocusNode`s are explicitly passed in via `_TableTextField(focusNode: row.xFocus, ...)` on every rebuild regardless of whether the `ListView.builder` itself was just freshly mounted, so even a full remount reattaches the same, already-existing `FocusNode` objects. This addendum only widens *how often* this already-safe swap occurs (previously once per `_hasLoadedSongs` transition; now, additionally, once per paste-field focus/blur while `_hasLoadedSongs` is already `true`) — it does not change *what* is swapped or *why* the swap is safe. **Confidence: HIGH**, with one caveat: this reasoning has not been confirmed by an actual interactive tap-cycle on a device with songs already loaded (see Verification Plan) — this ticket's own established practice (Addenda 1, 2) is to not treat code-path confidence, however carefully reasoned, as a substitute for that real-device check when the file's history includes two prior HIGH-confidence diagnoses that failed on-device. The mechanism here is more straightforward than either of those (a property addition and two boolean-widenings, not new reconciliation-algorithm reasoning), but the check is cheap and this ticket does not skip it as a matter of practice.

**4. Does widening the footer's condition introduce a new hazard?**

No new widget-type risk: the footer `Container` already carries its own stable key (`'bulk-entry-footer'`, Addendum 2 Task A) and its presence/absence was already conditional before this addendum (`_hasLoadedSongs || keyboardHeight == 0`). Widening the boolean expression that decides *whether* the condition evaluates to `true`, without changing the `Container`'s key, type, or the surrounding structure, does not add a new dimension of risk beyond what Addendum 2 Task A already resolved. **Confidence: HIGH.**

**5. Could `_isPasteFieldFocused` itself oscillate mid-gesture the way `keyboardHeight` was shown to (Addendum 1) — reintroducing a per-animation-frame churn hazard?**

No — and this is the one point worth stating explicitly rather than waving through. `keyboardHeight`'s hazard was that `viewInsets.bottom` reports *multiple intermediate values* across the OS keyboard's animated show/hide transition (a continuous quantity sampled many times per gesture). `FocusNode.hasFocus` is a **boolean** that transitions once when focus is requested and once when it is relinquished — it does not have "intermediate" states during a keyboard animation, and Addendum 3's clean-structure fix already demonstrated (via Tony's real-device retest) that a properly keyed, unwrapped `TextField` holds focus stably for the entire duration of the keyboard's rise/fall. Given that Addendum 3's fix remains untouched and unwrapped here, `_isPasteFieldFocused` inherits that same stability — it flips once per tap-in, stays `true` throughout that keyboard animation, and flips once per tap-out/blur. **Confidence: HIGH**, on the basis that this is the same clean structure already proven stable across a full keyboard-animation cycle in Addendum 3's real-device retest, not a new, unverified claim about focus behavior in general.

**Overall confidence in this addendum's reconciliation-safety: HIGH**, per points 1–5 above. Per this ticket's own established practice (never shipping a change in this exact danger zone on code-path confidence alone after two prior HIGH-confidence failures), Task S below still requires a real, interactive, on-device tap-cycle confirmation — specifically re-tapping the paste field after songs are already loaded, repeatedly — before this addendum is considered closed. This is the smallest instrumented step available: no new debug instrumentation is proposed (this ticket's own Addendum 3 already found that debug wrappers are themselves a hazard in this exact file), and the change itself is small enough that the existing Tier 1 test protocol, run by Tony on a real device, is sufficient without additional print/telemetry scaffolding.

### Files to Modify

| File | What changes |
|------|-------------|
| `lib/features/setlists/widgets/add_to_setlist/bulk_entry_screen.dart` | Add `_csvFocusNode` (`FocusNode`) and `_isPasteFieldFocused` (`bool`) fields; add a focus-change listener registered in `initState()` and disposed in `dispose()`; wire `focusNode: _csvFocusNode` onto the existing CSV `TextField` (no wrapping widget); widen `showExpandedPasteField` to `!_hasLoadedSongs \|\| _isPasteFieldFocused`; widen the table-visibility condition (line 528) and the footer-visibility condition (line 548) as specified above. No other line changes. |

**Not touched:** `showFullPasteUi` and its two uses; `_buildKeyboardToolbar()`'s own condition and body; Task N's `Flexible`/`SingleChildScrollView` wrapper (`flex`/`physics` still driven by `keyboardHeight` alone); `_buildColumnHeaders()`, `_buildAddRowButton()`, `_buildRow()`, `_tableCell()`, `_TableTextField`; `_handleCsvIngestion()`, `_populateTableFromParseResult()`, `BulkSongParser`, `BulkSongRow`; `add_to_setlist_overlay.dart`; `lib/shared/widgets/keyboard_aware_wrapper.dart`; `lib/features/calendar/calendar_tab_content.dart`; `setlist_repository.dart`; `setlist_detail_screen.dart`; `MainActivity.kt` (Addendum 8, unrelated).

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** none
**New files:** none
**AI_DECISIONS.md entry:** not required — no init-order, config-loading, auth-flow, RLS, or new-dependency change.

### Engineer Task Breakdown (Addendum 9)

Execute in order, after (not replacing) all prior work already completed on this ticket.

**Task R — Add paste-field focus tracking**
1. In `_BulkEntryScreenState`, add `final FocusNode _csvFocusNode = FocusNode();` and `bool _isPasteFieldFocused = false;` alongside the existing `_csvController` and `_hasLoadedSongs` fields.
2. In `initState()`, add `_csvFocusNode.addListener(_handleCsvFocusChange);` after the existing row-population loop.
3. Add a new method:
   ```dart
   void _handleCsvFocusChange() {
     if (!mounted) return;
     setState(() {
       _isPasteFieldFocused = _csvFocusNode.hasFocus;
     });
   }
   ```
4. In `dispose()`, add `_csvFocusNode.dispose();` alongside the existing `_csvController.dispose();`.
5. On the CSV `TextField` (line 425), add `focusNode: _csvFocusNode,` as an additional named argument. Do not change `key`, `controller`, `maxLines`, `minLines`, `style`, or `decoration`. Do not wrap the `TextField` in any new widget.

**Task S — Widen `showExpandedPasteField` and the table/footer conditions**
1. Change `final showExpandedPasteField = !_hasLoadedSongs;` (line 353) to `final showExpandedPasteField = !_hasLoadedSongs || _isPasteFieldFocused;`.
2. Change `if (_hasLoadedSongs) ...[` (line 528) to `if (_hasLoadedSongs && !showExpandedPasteField) ...[`. Do not change anything inside that branch or its `else` (`Expanded(child: SizedBox.shrink())`).
3. Change `if (_hasLoadedSongs || keyboardHeight == 0)` (line 548) to `if ((_hasLoadedSongs && !showExpandedPasteField) || keyboardHeight == 0)`. Do not change `_buildFooter()`'s own body.
4. Do not change `showFullPasteUi`, its two uses (lines 360, 367), or `_buildKeyboardToolbar()`'s condition (line 547).
5. Do not change Task N's `Flexible`/`SingleChildScrollView` wrapper (lines 519–527) — its `flex`/`physics` ternaries remain driven by `keyboardHeight` alone.

**Task T — `flutter analyze`**
Ensure `0 errors` with Tasks R–S in place.

**Task U (verification only, no further code change expected)**
On a real device (or simulator, consistent with how this ticket's tests have been run), full stop/restart:
1. Paste a valid CSV block and tap "Load Songs" — confirm songs populate the table exactly as today (Addendum 4/6 behavior unchanged).
2. Tap into the (now-compact) CSV paste field. Confirm: the field expands to full height/normal padding, the table (headers, rows, "Add Row") disappears, the footer disappears, the keyboard's "Done" toolbar remains visible, and "Load Songs" is fully visible and reachable.
3. Type or paste additional text into the field. Confirm it is accepted and retained (focus holds throughout).
4. Tap "Done" on the toolbar (or tap "Load Songs"). Confirm the table reappears with all previously-loaded rows and their values intact, and the footer reappears.
5. Repeat steps 2–4 two or three more times in the same session — this specifically targets whether focus/table-visibility toggling is stable on repeated cycles, not just the first (mirroring Addendum 1's and Addendum 3's own repeatability checks).
6. Tap "Load Songs" again with new pasted text while already loaded — confirm the additional songs replace/append correctly (per `_handleCsvIngestion`'s existing, unmodified logic) and the end state (compact field, table visible, footer visible) matches today's post-load behavior exactly.
7. Confirm no regression to the pre-load first-tap flow (Addendum 1's original fix): tapping the field before any songs are loaded still shows intro text/info box (while keyboard is closed), expands the field, and behaves exactly as before.

### Verification Plan Addendum (Addendum 9)

These supplement, not replace, all prior Tier 1/Tier 2 tests.

**Tier 1 — Pre-deployment (before merge):**
- **PRE-DEPLOY TEST 46:** With songs already loaded, tap into the CSV paste field. Confirm the field expands to full height, the table and footer both disappear, and "Load Songs" is unobstructed.
- **PRE-DEPLOY TEST 47:** With the field focused per Test 46, type/paste text and confirm it is retained; confirm the keyboard's "Done" toolbar remains visible and functional.
- **PRE-DEPLOY TEST 48:** Tap "Done" (or "Load Songs"). Confirm the table reappears with prior rows and values intact (no data loss from the unmount/remount), and the footer reappears.
- **PRE-DEPLOY TEST 49 (repeatability):** Repeat Tests 46–48 at least twice more in the same session. Confirm behavior is stable on every cycle, not just the first — consistent with this ticket's established practice of not trusting a fix that only works once.
- **PRE-DEPLOY TEST 50 (no regression, pre-load):** Confirm the original pre-load first-tap flow (Addendum 1) is unaffected — intro/info box, field expansion, and "Load Songs" reachability all behave exactly as before when no songs are loaded yet.
- **PRE-DEPLOY TEST 51 (no regression, row-cell editing):** With songs loaded, tap into an individual row's cell (e.g., the Artist field of a table row), not the CSV paste field. Confirm the footer still appears (this must NOT be affected by this addendum — only the CSV field's own focus drives `_isPasteFieldFocused`) and the table remains visible while editing.
- **PRE-DEPLOY TEST 52 (Android, best-effort):** Repeat Tests 46–49 on Android, consistent with this ticket's established best-effort posture for the second platform.

**Tier 2 — Post-deployment (after merge):**
- **POST-DEPLOY TEST 3:** On a real device, repeat Tests 46–49 under genuine touch input, per this ticket's established practice that real-device confirmation — not code-path analysis — carries the verification burden in this exact file.

### QA Regression Areas (Addendum 9)

QA must specifically test:
1. Re-focusing the CSV paste field after songs are loaded expands the field, hides the table, and hides the footer — the primary new behavior.
2. The keyboard's "Done" toolbar remains visible and functional throughout (unchanged).
3. Table content (all rows and their values) survives the field being focused and then blurred again, repeatedly — no data loss from the table's unmount/remount.
4. Focusing an individual row cell (not the CSV field) does **not** trigger this new behavior — footer and table visibility must remain governed by existing rules in that case.
5. The pre-load first-tap flow (Addendum 1) is unaffected.
6. No regression to Addendum 6's field-density decoupling or Addendum 7's column-width work.
7. Full paste → Load Songs → table population cycle, including re-pasting additional songs after an initial load, works end to end.

### Regression Risk

**LEVEL: LOW**

Rationale:
- No new ancestor widget is introduced around the CSV `TextField`; its `key`/`runtimeType` at its existing `Column` slot are unchanged (see Reconciliation-Safety Verification, point 1).
- The two widened conditions (table, footer) reuse widget-swap patterns already shipped and verified safe since Addendum 4 — this addendum changes *when* those swaps occur, not *what* is swapped or introduces any new type of swap.
- `showFullPasteUi`, Task N's `Flexible`/`SingleChildScrollView` wrapper, `_buildKeyboardToolbar()`'s condition, and every row-level table widget are untouched.
- The new `FocusNode`/listener follow the exact same lifecycle pattern (`addListener` in `initState`, `dispose` in `dispose()`) already used by every row's `FocusNode` in this same file.
- The one behavioral change confirmed to affect an existing, already-shipped state (the footer's visibility table above) was worked through explicitly across all four `(_hasLoadedSongs, focus)` × `keyboardHeight` combinations, with only one cell changing.

### Out of Scope (Addendum 9)

1. Preserving the table's scroll position across the focus-driven unmount/remount cycle — a minor, acceptable cosmetic side effect, not a data-loss concern, and not requested by Tony.
2. Re-showing the intro text / bordered info box while the field is refocused post-load — Tony's request is about field size, button reachability, and table/footer clutter, not the instructional content, which already (correctly, by existing design) hides once the keyboard is open even in the original pre-load flow.
3. Hiding `_buildKeyboardToolbar()`'s "Done" button while the field is focused — parity with the pre-load "first tap" treatment means the toolbar should behave identically in both cases, and it already remains visible there.
4. Any change to `_handleCsvIngestion()`, `_populateTableFromParseResult()`, `BulkSongParser`, or `BulkSongRow` — the parse/populate/submit pipeline is unaffected by this addendum; only paste-field-focus-driven layout visibility changes.
5. A live/reactive alternative to `FocusNode` (e.g., `Focus` widget with `onFocusChange`, or `GestureDetector`-based heuristics) — rejected as unnecessary; `FocusNode` is the direct, standard mechanism for this exact need and the file already uses it extensively for every row cell.
6. Any change to `lib/shared/widgets/keyboard_aware_wrapper.dart`, `lib/features/calendar/calendar_tab_content.dart`, `setlist_repository.dart`, `setlist_detail_screen.dart`, or `MainActivity.kt` — none implicated; all remain off-limits per this ticket's standing Stop Conditions.

---

**Architect Signature (Addendum 9):** This addendum adds one new state dimension (`_isPasteFieldFocused`, tracked via an explicit `FocusNode` added as a property on the existing, already-keyed CSV `TextField` — not a new wrapping widget) and widens one existing derived boolean (`showExpandedPasteField`) plus two existing conditional-visibility expressions (table, footer) to incorporate it. It deliberately leaves `showFullPasteUi`, the keyboard toolbar's condition, and Task N's type-stable `Flexible`/`SingleChildScrollView` wrapper untouched. The reconciliation-safety analysis was walked explicitly against the current file's actual structure (not by analogy to prior addenda): the `TextField`'s own `Column`-slot identity is unaffected (same `runtimeType`/`key`, one more constructor argument), and the two widened widget-presence conditions reuse a swap pattern already shipped and safe since Addendum 4, because nothing destroyed in either swap holds state that needs cross-swap preservation. **Confidence: HIGH**, with the explicit caveat that — per this ticket's own hard-won practice after two prior HIGH-confidence, code-path-only diagnoses failed real-device verification (Addenda 1, 2) — this must still be confirmed by a real, interactive, repeated tap-cycle test with songs already loaded (Task U / PRE-DEPLOY TESTS 46–49) before being considered closed. No new debug instrumentation is proposed for this verification, consistent with Addendum 3's own finding that instrumentation wrappers are themselves a hazard in this exact file. Ready for Engineer implementation of Tasks R–T; Task U must be completed and reported before this addendum is considered closed.
