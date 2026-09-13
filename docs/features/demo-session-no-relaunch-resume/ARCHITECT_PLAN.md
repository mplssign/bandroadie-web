# ARCHITECT_PLAN — demo-session-no-relaunch-resume

## Feature Slug

`feature/demo-session-no-relaunch-resume`

## Feature Title

Demo/anonymous sessions should not survive an app relaunch

## Cycle Number

**5 (Architect amendment — cumulative).** Cycles 1–3 designed a *post-init* local
sign-out (init step 6.5) that was QA-approved and then **failed Tony's owner
relaunch test**. Cycle 4 Engineer re-diagnosed the root cause in the resolved SDK
source and implemented a *pre-init* disk purge (init step 5.5); Cycle 4 QA
independently confirmed that implementation is analyzer-clean, 298/298 tests
pass, and regression risk is LOW–MEDIUM, but returned **REQUIRES CHANGES** for a
single `[out-of-scope]` reason: this plan still described the disproven step-6.5
mechanism while the implementation, `DECISION-006`, and `RUNTIME_CONFIG.md`
already described step 5.5. This Cycle 5 amendment ratifies the pre-init
disk-purge mechanism the implementation already ships and reconciles the plan
with those docs. **The superseded step-6.5 mechanism now survives only in the
clearly-labeled “Superseded Mechanism” section at the end — it is not an active
instruction anywhere above it.**

**Does the current Cycle 4 implementation require any code change? No.** This
amendment is plan-catch-up only. Architect independently re-verified the shipped
code against the resolved SDK source this cycle (`supabase_flutter` 2.17.2,
gotrue 2.27.2 — see Root Cause) and found it technically sound and matching this
amended plan. The Engineer Task Breakdown below is the definition-of-done the
shipped code already satisfies; Engineer Cycle 5 is expected to make **no** source
change, and QA Cycle 5 re-validates the already-verified implementation against
this amended plan.

## Problem Summary

On native platforms (iOS, Android, macOS) the demo entry point creates an
anonymous Supabase session. `supabase_flutter` persists that session to local
storage exactly like a real-user session, so on the next cold start it is
restored and the app auto-routes straight back into the Demo Band, skipping the
login screen — for as long as the underlying `demo_sessions` slot has not yet
been reclaimed by the existing TTL + cron mechanism shipped in #289.

This auto-resume is correct and wanted for authenticated **real** users. It is
**not** wanted for the anonymous demo flow: a demo entry should always start
clean at the login screen on relaunch, regardless of how much TTL remains.

**Owner test that disproved the first fix (Cycles 1–3).** Tony ran the exact
repro on macOS: enter Demo Band → fully quit (Cmd-Q) well within the 8-minute
TTL → `./run.sh macos` (a genuine cold `main()` launch). The app reopened
**directly into Demo Band** instead of the login screen — the post-init local
sign-out shipped in Cycles 1–3 did **not** prevent the resume. Cycle 4 diagnosed
why in the resolved SDK source (see Root Cause) and replaced the mechanism; this
plan is now amended to that mechanism.

## Root Cause

**Confidence: HIGH** (independently confirmed by Architect in the resolved SDK
source this cycle — `supabase_flutter` 2.17.2, gotrue 2.27.2 — not taken on the
Engineer's or QA's word).

`supabase_flutter` restores a persisted session **twice** during startup, and
the second restore is a **non-awaited background task that runs after
`Supabase.initialize()` returns**. Any fix that clears the session *after*
`initialize()` is therefore deterministically undone:

1. `SupabaseAuth.initialize()` (`supabase_flutter-2.17.2/lib/src/supabase_auth.dart`
   L107–124) reads `_localStorage.hasAccessToken()` / `accessToken()` and calls
   `setInitialSession(persistedSession)`, which synchronously seeds
   `currentSession` from disk. `is_anonymous` survives persistence (see below),
   so the restored session is a full anonymous session.
2. Immediately after `await supabaseAuth.initialize(...)`, `Supabase.initialize()`
   starts a **fire-and-forget** background restore
   (`supabase_flutter-2.17.2/lib/src/supabase.dart` L156–159):
   `_restoreSessionCancellableOperation =
   CancelableOperation.fromFuture(supabaseAuth.recoverSession())`. This runs
   **after `initialize()` has already returned** to `main.dart`.
   `recoverSession()` (`supabase_auth.dart` L143–155) re-reads
   `_localStorage.hasAccessToken()` / `accessToken()` from the **still-persisted**
   disk blob and calls `GoTrueClient.recoverSession(...)`, which — for a
   non-expired token (always true inside #289's 8-minute TTL) — re-saves the
   session into `currentSession` and emits `tokenRefreshed`.

The Cycles 1–3 mechanism (a post-init `signOut(scope: SignOutScope.local)` at
init step 6.5) *did* null the in-memory session set in step 1, but the background
`recoverSession()` in step 2 re-reads the untouched disk blob and **resurrects**
the anonymous session; the `signOut()`-triggered disk removal
(`removePersistedSession`, dispatched fire-and-forget from the `signedOut` event)
loses the race against that background restore. `supabase_flutter` exposes **no
public API to await or cancel** `_restoreSessionCancellableOperation` (a private
field cancelled only in `dispose()`), so no post-init sign-out — timed out,
retried, or awaited — can deterministically beat it. This is why the owner
relaunch test failed even though static analysis and the pure predicate passed.

The deterministic repair is upstream of both restores: **remove the persisted
anonymous session from local storage *before* `Supabase.initialize()` reads it.**
With the disk key gone, `hasAccessToken()` returns false in both step 1 and step
2, `currentSession` stays `null` for the whole launch, and every existing auth
path routes to `LoginScreen` with no network involved.

Supporting facts confirmed in source this cycle:

- **Persist key derivation.** `SharedPreferencesLocalStorage`
  (`supabase_flutter-2.17.2/lib/src/local_storage.dart` L67–115) is the default
  native backend when `persistSession == true` (the default). Its key is set by
  `Supabase.initialize()` to
  `"sb-${Uri.parse(url).host.split(".").first}-auth-token"` (`supabase.dart`
  L132–133). It reads via `_preferences.containsKey(key)` / `getString(key)` and
  removes via `_preferences.remove(key)`, where `_preferences =
  SharedPreferences.getInstance()` (L80) — the same process-wide singleton the
  purge writes to, so a pre-init `remove(key)` is visible to the SDK's later
  `containsKey(key)` (no stale-cache race).
- **`is_anonymous` is always serialized.** gotrue `Session.toJson`
  (`gotrue-2.27.2/lib/src/types/session.dart` L67) persists `'user':
  user.toJson()`; `User.toJson` (`types/user.dart` L118) **always** writes
  `'is_anonymous': isAnonymous` (a `bool`, L29, default `false`), and
  `User.fromJson` (L91) reads `json['is_anonymous'] ?? false`. So a real-user blob
  always contains `is_anonymous: false` and an anonymous blob always contains
  `is_anonymous: true` — the classifier reads the **same field from the same
  path** the SDK uses to decide anonymity.
- **Legacy Hive storage is not in use.** `local_storage.dart` L12 documents the
  Hive→SharedPreferences `MigrationLocalStorage` as "Not actually in use," so
  there is no second on-disk location to purge on current versions.

## Existing System Analysis

**Why the fix must null `currentSession` upstream of the app, not in the
provider/widget layer.** Several load-bearing safeguards read the Supabase client
session as ground truth and will actively *resurrect* any session the provider
layer tries to drop:

- `AppAuthState.isAuthenticated` is defined purely as `session != null`
  ([auth_state_provider.dart](../../../lib/features/auth/auth_state_provider.dart#L19)),
  with no anonymous branch; `AuthGate.build()` / `_buildAuthContent()` route
  solely on `isAuthenticated`
  ([auth_gate.dart](../../../lib/features/auth/auth_gate.dart#L440-L487)), so a
  restored anonymous session satisfies every gate and lands in `AppShell`.
- The `build()` safeguard force-refreshes back to the client session if the
  provider says "no session" but `supabase.auth.currentSession != null`
  ([auth_gate.dart](../../../lib/features/auth/auth_gate.dart#L457-L485)); the
  5 s `_startSessionSyncTimer()` does the same
  ([auth_gate.dart](../../../lib/features/auth/auth_gate.dart#L79-L118)).

Consequence: any fix that leaves `supabase.auth.currentSession` non-null would be
undone on the first frame. Combined with the SDK's non-awaited background
`recoverSession()` (see Root Cause), the only robust, low-blast-radius fix is to
make the SDK's on-disk session absent **before** `Supabase.initialize()` ever
reads it.

Cold-start auth path, native (confirmed):

1. `main.dart` runs the fixed init order. **New step 5.5 (this feature):** before
   `Supabase.initialize()`, purge a persisted *anonymous* session from
   `SharedPreferences`. The existing `FormatException` retry inside the
   `Supabase.initialize()` block
   ([main.dart](../../../lib/main.dart#L69-L100)) is unchanged and still handles
   corrupt (unparseable) session blobs.
2. `Supabase.initialize()` reads storage (`setInitialSession`) and starts the
   background `recoverSession()`. With the anonymous key already removed, both
   find nothing → `currentSession == null`.
3. `runApp()` → `AuthStateNotifier.build()` reads `currentSession` (null) →
   `isAuthenticated == false` → `LoginScreen`. No provider/widget change; the
   `build()` safeguard and 5 s timer agree "no session."

Demo lifecycle facts confirmed:

- Demo entry is native-only: `_kDemoBandVisible = !kIsWeb`
  ([login_screen.dart](../../../lib/features/auth/login_screen.dart#L53)). Web
  never calls `signInAnonymously()`, and web's SDK storage backend is
  `window.localStorage`, not `SharedPreferences`, so a `!kIsWeb`-gated
  SharedPreferences purge is both inert and correct on web.
- A **fresh** in-run demo session is created by
  `DemoSessionService.provisionAndEnter()`
  ([demo_session_service.dart](../../../lib/features/auth/demo_session_service.dart#L19))
  only *after* the app is running and the user taps the demo button — it never
  passes through `main.dart`'s startup path, so it is never purged in-run; it is
  purged only on the *next* cold start, as intended.
- The existing `_reconcileOrphanedAnonymousSession()` global sign-out
  ([auth_gate.dart](../../../lib/features/auth/auth_gate.dart#L303-L328)) remains
  an unchanged backstop for any later authenticated cold start that observes an
  anonymous session whose band is already gone.

## Proposed Solution

Add a **pre-init purge of a restored anonymous demo session** to `main.dart` at
init **step 5.5**: after `validateSupabaseConfig()` and **before**
`Supabase.initialize()`, remove any persisted anonymous session from local
storage so the SDK has nothing to restore or resurrect (see Root Cause).

Behavior:

- **Native-only** (`if (!kIsWeb)`): web never creates an anonymous session and
  uses a different storage backend (`window.localStorage`), so the purge is gated
  off there.
- `await DemoSessionService.purgePersistedAnonymousSession(supabaseUrl)`:
  1. `await SharedPreferences.getInstance()` — the same singleton the SDK's
     native backend uses.
  2. Derive the SDK's persist key `sb-<ref>-auth-token` from `supabaseUrl` using
     the SDK's exact expression
     (`'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`).
  3. Read the stored blob (`prefs.getString(key)`), classify it with the pure
     predicate `DemoSessionService.isPersistedSessionAnonymous(raw)` (`true` only
     when `decoded['user']['is_anonymous'] == true`), and **`await
     prefs.remove(key)` only when it is anonymous**. The removal is awaited before
     `main()` proceeds to `Supabase.initialize()`.
  4. The whole body is wrapped in `try/catch` that swallows and continues, so a
     storage read failure can never block startup.

With the anonymous key removed before init, both `setInitialSession` and the
background `recoverSession()` find nothing, `currentSession == null` for the
whole launch, and every existing auth path routes to `LoginScreen` — with
**zero** special-casing in the provider/widget layer and `isAuthenticated ==
session != null` left literally unchanged, so real-user persistence is preserved
exactly.

### Decision (RATIFIED): couple to the SDK's internal persist key directly

`supabase_flutter` exposes **no public API** to (a) read/clear its persisted
session by key before `initialize()`, (b) await or cancel the background
`recoverSession()` `CancelableOperation` (a private field cleared only in
`dispose()`), or (c) classify a persisted blob as anonymous. The public
`signOut()` path is exactly what Cycles 1–3 used and is defeated by the
background restore (see Root Cause). Therefore the only mechanism that satisfies
the absolute requirement is to reach the SDK's own on-disk key directly. This
coupling is **explicitly ratified** with the following bounded assumptions and
fail-safes:

- **Key-derivation assumption.** The purge replicates the SDK's key expression
  verbatim: `'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`
  (matches `supabase.dart` L132–133 exactly, confirmed this cycle), and reads the
  same `SharedPreferences` singleton (`local_storage.dart` L80) the native
  backend uses.
- **Value-shape assumption.** Classification depends only on
  `decoded['user']['is_anonymous'] == true`, the same field/path gotrue writes
  (`user.dart` L118) and reads (L91). This is a stable, public wire field of the
  session JSON, not a private in-memory detail.
- **Upgrade risk + fail-safe.** If a future `supabase_flutter`/gotrue release
  changes the key expression, the storage backend, or the persisted JSON shape,
  the purge **degrades to a silent no-op** (wrong key → nothing found; changed
  shape → not classified as anonymous → not removed). The worst case is the
  pre-fix behavior — a demo could resume for that one launch — backstopped by
  #289's untouched 8-minute TTL + 2-minute cron. It **never** drops a real user's
  session and never crashes. This is an accepted maintenance liability: any SDK
  upgrade touching those three surfaces requires re-confirming the derivation (a
  one-line check against the SDK source), recorded against `DECISION-006`.
- **Why not a safer alternative.** A public `signOut()` (post-init) is disproven
  (Root Cause). Awaiting/cancelling the background restore has no public API.
  Gating the whole auth layer on `isAnonymous` (redefining `isAuthenticated`)
  would touch off-limits files and break both the live in-run demo flow and
  real-user semantics. The pre-init disk purge is the smallest change that is
  deterministic and keeps all auth semantics untouched.

### Decision: local disk purge only (no cold-start server release)

The purge is a **local storage clear only**; it does **not** call
`exit-demo-session` to release the server-side slot. Server-side reclamation is
already owned by #289's 8-minute TTL + 2-minute cron (off-limits) and the
best-effort `detached` release; adding a startup network call would be redundant
and put network/timeout complexity on the cold-start path. This honors the
Manager's preference that the fix depend on no exit-time or startup-time network
completion — the purge is a single local `SharedPreferences` operation.

### Fail-safe classification assessment (malformed / legacy / non-classifiable blobs)

Requirement pair (both absolute): **(A)** a restored anonymous demo session must
**never** resume on relaunch; **(B)** a real user's persisted session must
**never** be dropped. The classifier is deliberately conservative — it removes
the key **only** on a positive `is_anonymous == true`, so a malformed, legacy, or
shape-unexpected blob is **left in place** (satisfies B). The question is whether
that conservatism can violate A (“may resume once if not classifiable”).

Assessment — it does **not**, on current SDK versions, for any real demo session,
because the classifier and the SDK read anonymity from the **identical field and
path**:

- A blob the current SDK can restore **as anonymous** necessarily has
  `user.is_anonymous == true` (exactly how gotrue's `User.fromJson` decides
  `isAnonymous`), which the classifier also reads → it is **always purged**.
  There is no same-version blob the SDK treats as anonymous but the classifier
  does not.
- A blob with `is_anonymous` absent/`false` is restored by the SDK as a
  **non-anonymous (real) user** — the app treats it as a real user everywhere
  (`auth_gate` / `app_shell` check `user.isAnonymous`), so “resuming” it is the
  desired real-user behavior, not a demo resume.
- A blob that is not valid JSON is not restorable by the SDK either
  (`Session.fromJson` throws → caught, or the existing `FormatException` retry
  signs out) → `currentSession` stays null → login is shown. Not a demo resume.

The **only** path by which a demo could resume once is a *future SDK schema/key
change*, already covered by the ratified upgrade fail-safe above (degrades to
no-op, backstopped by #289 TTL/cron, bounded to a single launch within the TTL
window). That is an SDK-coupling maintenance risk, **not** a real-user-
preservation failure. **Conclusion: acceptable within current scope; no safer
classifier is required — and a more aggressive “purge anything not provably a real
user” strategy would *violate* requirement B by dropping real users on an
unexpected blob shape, so the conservative direction is the correct tradeoff.**

## Database Impact

**Not applicable.** No migration, RLS policy, RPC, trigger, grant, or edge
function change. #289's advisory lock, 8-minute TTL, 2-minute cron, migration,
grants, and capacity math are untouched and off-limits.

## Flutter Architecture Changes

No new provider, controller, repository, or state-management pattern. Two new
static members are added to the existing `DemoSessionService` (matching the
established #289 testable-seam pattern): the pure predicate
`isPersistedSessionAnonymous(String?)` and the storage side-effect
`purgePersistedAnonymousSession(String supabaseUrl)`. `AppAuthState`,
`AuthStateNotifier`, `AuthGate`, and `isAuthenticated` semantics are unchanged.

**Init-order change (logged decision `DECISION-006`).** A new step is inserted
into the fixed app initialization order, **before** `Supabase.initialize()`:

```
5.   validateSupabaseConfig()
5.5  Purge persisted anonymous demo session   ← NEW · native-only · BEFORE Supabase.initialize()
6.   Supabase.initialize()
7.   Firebase.initializeApp()   (native only)
8.   DeepLinkService setup
9.   runApp()
```

Per the init-order guardrail this is not silent: it is recorded as
`AI_DECISIONS.md` `DECISION-006` and reflected in `RUNTIME_CONFIG.md`'s
init-order block (both already updated in the Cycle 4 implementation). No other
step is reordered; step 5.5 sits strictly between existing steps 5 and 6.

## Files to Create

**None.** The new unit tests are added to the existing
`test/features/auth/demo_lifecycle_predicate_test.dart`, which already houses the
sibling `DemoSessionService.shouldReleaseDemoOnLifecycle` tests.

## Files to Modify

| File | Change |
| --- | --- |
| [lib/main.dart](../../../lib/main.dart) | Add `import 'features/auth/demo_session_service.dart';`. After `validateSupabaseConfig()` and **before** the `Supabase.initialize()` block, add the native-only pre-init purge: `if (!kIsWeb) { await DemoSessionService.purgePersistedAnonymousSession(supabaseUrl); }`. The old post-init step-6.5 sign-out block is removed. |
| [lib/features/auth/demo_session_service.dart](../../../lib/features/auth/demo_session_service.dart) | Add `dart:convert` + `shared_preferences` imports and two static members: the pure predicate `isPersistedSessionAnonymous(String? rawSessionJson)` and `purgePersistedAnonymousSession(String supabaseUrl)`. Do **not** modify any existing method (`provisionAndEnter`, `exit`, `heartbeat`, `releaseSlotOnDetach`, `shouldReleaseDemoOnLifecycle`). |
| [test/features/auth/demo_lifecycle_predicate_test.dart](../../../test/features/auth/demo_lifecycle_predicate_test.dart) | Add `group('isPersistedSessionAnonymous', …)` (classifier cases) and `group('purgePersistedAnonymousSession (startup storage race)', …)` (seeds `SharedPreferences.setMockInitialValues` under the SDK-derived key, asserts the anon blob is removed and the real-user blob preserved). Remove the obsolete `shouldPurgeRestoredAnonymousSession` truth-table group. |
| [docs/reference/general/AI_DECISIONS.md](../../../docs/reference/general/AI_DECISIONS.md) | `DECISION-006` records the step-5.5 pre-init disk-purge mechanism, the ratified SDK persist-key coupling + upgrade fail-safe, and the Cycle 4 root-cause correction. |
| [docs/reference/general/RUNTIME_CONFIG.md](../../../docs/reference/general/RUNTIME_CONFIG.md) | Init-order block shows step `5.5 Purge persisted anonymous demo session ← native-only; BEFORE Supabase.initialize()`. |

## Files Off-Limits

| File / Area                                                                                                                                                                                                                     | Why                                                                                                                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/**`, `supabase/functions/exit-demo-session/**`, `provision_demo_session`, `heartbeat_demo_session`, `cleanup_demo_sessions` cron, advisory lock `8675309001`, 8-min TTL, 2-min cron, grants, capacity math | Shipped and authoritative in #289 (DECISION-005). This feature changes only relaunch-resume behavior, not TTL/capacity/reclamation.                                                                               |
| `lib/features/auth/auth_state_provider.dart`                                                                                                                                                                                    | `isAuthenticated == session != null` must stay unchanged; the fix works by nulling `currentSession` upstream, not by re-defining auth semantics (which would break the live demo flow and real-user persistence). |
| `AuthGate` routing, safeguards, sync timer, `_reconcileOrphanedAnonymousSession()`                                                                                                                                              | Left intact as an unchanged safety net; the purge makes the restored-anonymous case unreachable at cold start, but the reconcile backstop stays for any residual edge case.                                       |
| `lib/features/auth/login_screen.dart` (`_kDemoBandVisible`, `_enterDemo`)                                                                                                                                                       | Demo entry/gating and fresh-session creation are unchanged.                                                                                                                                                       |
| `lib/features/shell/app_shell.dart` (`Exit Demo`)                                                                                                                                                                               | The in-app exit path already works; not touched.                                                                                                                                                                  |

## Change Budget

Reset this cycle to the pre-init disk-purge mechanism (the Cycles 1–3 budget for
a single pure predicate is obsolete). The net line deltas below are the Cycle 4
`git diff --numstat` actuals QA measured, and are the ratified budget for QA
Cycle 5:

- `lib/main.dart`: net **≈ −11** (+12 / −23 — the post-init block was removed and
  replaced by the smaller pre-init call).
- `lib/features/auth/demo_session_service.dart`: net **≈ +34** (+45 / −11 — two
  new static members + `dart:convert`/`shared_preferences` imports; the obsolete
  `shouldPurgeRestoredAnonymousSession` predicate removed).
- `test/features/auth/demo_lifecycle_predicate_test.dart`: net **≈ +86** (+111 /
  −25 — classifier group + real-storage race group; the obsolete truth-table
  group removed).
- `docs/reference/general/AI_DECISIONS.md`: `DECISION-006` rewrite (≈ +86 / −61).
- `docs/reference/general/RUNTIME_CONFIG.md`: net **≈ ±1** (step 6.5 → 5.5).
- New files: **0**.
- **New public members: 2** (`isPersistedSessionAnonymous`,
  `purgePersistedAnonymousSession`) — up from the obsolete plan's 1; the extra
  member is the disk side-effect the pure predicate cannot perform.
- New dependencies: **0** (`shared_preferences` and `dart:convert` are already
  present; no `pubspec` change).

The larger service/test deltas are intrinsic to the mechanism (a pure truth-table
predicate cannot exercise the failing storage path); they are functional, not
bloat (QA confirmed no `_buildX`, no new provider, no dead flags).

## System Impact Map

| System | Status | Notes |
| --- | --- | --- |
| Auth | **Affected** | Cold start purges a restored anonymous session from disk **before** `Supabase.initialize()`. Real-user (non-anonymous) restore is unaffected; `isAuthenticated` unchanged. |
| Routing | **Affected (indirect)** | With `currentSession == null`, existing routing lands on `LoginScreen`. No routing code changes. |
| Init order | **Affected** | New step **5.5**, before `Supabase.initialize()` (logged as `DECISION-006` + `RUNTIME_CONFIG.md`). |
| Setlists / Gigs / Rehearsals / Members / Notifications | **Unaffected** | No touchpoints. |
| Platforms | **Native (iOS/Android/macOS): affected** by the purge. **Web: unaffected** — `!kIsWeb`-gated; web uses `window.localStorage` (not `SharedPreferences`) and never creates an anonymous session. |
| DB / RLS / RPC | **Unaffected** | No DB change. |

## Regression Risk

**LOW–MEDIUM** (aligned with QA's independent Cycle 4 assessment). Init order and
auth-storage are high-sensitivity surfaces, but the behavioral change is tightly
gated to `user.is_anonymous == true` on disk, is native-only (`!kIsWeb`), and is
wrapped in swallow-and-continue error handling so `main()` always reaches
`Supabase.initialize()`. Real users are provably never matched (the classifier
requires a positive `is_anonymous == true`, and real-user blobs always serialize
`false`); web is untouched (gated off, different backend); the live in-run demo
flow is created after startup and never traverses `main()`. The reconcile backstop
and #289 TTL/cron remain in place.

## Engineer Task Breakdown

The Cycle 4 implementation already satisfies every task below; this is the
ratified definition-of-done, not a request for new code (Architect verified no
code change is required — see Cycle Number). Listed atomically so QA can measure
the diff against it.

1. **`DemoSessionService` — classifier seam.** Pure static
   `isPersistedSessionAnonymous(String? rawSessionJson)`: returns `true` **only**
   when `jsonDecode(raw)['user']['is_anonymous'] == true`; `false` for null,
   malformed JSON, a missing `user` object, or absent/`false` `is_anonymous`
   (fail-safe — never classifies a real or unparseable blob as anonymous).
   Wrapped in `try/catch`.

2. **`DemoSessionService` — purge seam.**
   `purgePersistedAnonymousSession(String supabaseUrl)`: `await
   SharedPreferences.getInstance()`, derive
   `'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token'`, and — only
   when `isPersistedSessionAnonymous(prefs.getString(key))` — `await
   prefs.remove(key)`. The whole body is in a `try/catch` that swallows
   (best-effort; startup must proceed). Requires `dart:convert` +
   `shared_preferences` imports. No existing method altered.

3. **`main.dart` — pre-init purge (init step 5.5).** Add the
   `features/auth/demo_session_service.dart` import; after
   `validateSupabaseConfig()` and **before** the `Supabase.initialize()`
   try/catch block, add:

   ```dart
   if (!kIsWeb) {
     await DemoSessionService.purgePersistedAnonymousSession(supabaseUrl);
   }
   ```

   Remove the old post-init step-6.5 sign-out block entirely. Leave the existing
   `FormatException` retry inside the `Supabase.initialize()` block unchanged.

4. **Tests.** In
   [test/features/auth/demo_lifecycle_predicate_test.dart](../../../test/features/auth/demo_lifecycle_predicate_test.dart),
   add `group('isPersistedSessionAnonymous', …)` (anonymous / real / null /
   malformed / missing-`user` / missing-`is_anonymous`) and
   `group('purgePersistedAnonymousSession (startup storage race)', …)` that seeds
   `SharedPreferences.setMockInitialValues` under the SDK-derived key and asserts
   the anonymous blob is **removed**, a real-user blob is **preserved**, the
   no-session case is a no-op, and a malformed blob is left untouched. Remove the
   obsolete `shouldPurgeRestoredAnonymousSession` truth-table group.

5. **Log the decision (`DECISION-006`).** In
   [docs/reference/general/AI_DECISIONS.md](../../../docs/reference/general/AI_DECISIONS.md)
   — Feature `feature/demo-session-no-relaunch-resume`, Status Active — record:
   (a) init-order step **5.5** (purge persisted anonymous demo session from
   `SharedPreferences`, **before** `Supabase.initialize()`); (b) the ratified SDK
   persist-key coupling + upgrade fail-safe; (c) the local-purge-only choice
   (server reclamation stays with #289 TTL/cron); (d) the login guarantee and the
   Cycle 4 root-cause correction (non-awaited background `recoverSession()`);
   (e) a one-line rollback (revert `main.dart`, the two `DemoSessionService`
   members, the test groups, and the two doc edits — no DB to unwind).

6. **Update RUNTIME_CONFIG.** In
   [docs/reference/general/RUNTIME_CONFIG.md](../../../docs/reference/general/RUNTIME_CONFIG.md),
   the init-order block shows step `5.5 Purge persisted anonymous demo session ←
   native-only; BEFORE Supabase.initialize()`, between `5.
   validateSupabaseConfig()` and `6. Supabase.initialize()`.

## Verification Plan

Client-only change, **no database function** involved, so the "never call the
function being replaced" Tier distinction does not apply. QA's mechanically-
executable gate is static analysis + the headless test harness; the actual
relaunch behavior requires a running app and is an owner-run (Tony) punch list,
not a QA gate.

### Tier 1 — QA gate (headless, no running app)

1. `flutter analyze lib/main.dart lib/features/auth/demo_session_service.dart
   test/features/auth/demo_lifecycle_predicate_test.dart` → **0 issues** at every
   severity.
2. `flutter test test/features/auth/demo_lifecycle_predicate_test.dart` passes:
   - `isPersistedSessionAnonymous`: `true` for an anonymous blob; `false` for a
     real-user blob, `null`, malformed JSON, a missing `user`, and an absent
     `is_anonymous`.
   - `purgePersistedAnonymousSession (startup storage race)`: with the SDK-derived
     key seeded via `setMockInitialValues`, the **anonymous** blob is removed, a
     **real-user** blob is preserved, no-session is a no-op, and a **malformed**
     blob is left untouched (fail-safe).
3. `flutter test` (full suite) → no new failures (298/298 in Cycle 4). Confirm
   `test/features/auth/auth_gate_anonymous_recovery_test.dart` (reconcile
   backstop) still passes unchanged, and that this branch introduces zero changes
   under `test/features/auth/login_screen_demo_button_test.dart` (pre-existing
   unrelated failures documented in prior reports) via `git diff --stat main --
   test/`.
4. Static review: confirm the purge is inserted **before** `Supabase.initialize()`
   (init step 5.5), is `!kIsWeb`-gated, `await`s `prefs.remove(key)`, that the key
   expression matches the SDK's exactly, that `isAuthenticated` is unedited, and
   that `RUNTIME_CONFIG.md` + `DECISION-006` describe step 5.5 (not 6.5).

### Tier 2 — DB apply-check

**n/a** — no migration.

### Owner-run punch list (Tony — requires a running app; QA cannot execute)

Run on a **native** build (macOS, plus at least one of iOS/Android). Each step is
precise + expected-result so it can be handed to Tony verbatim:

1. Login screen → tap "Check out the demo band". **Expected:** lands in Demo Band
   (fresh in-run session unaffected).
2. **Cycle-3 failure repro:** in Demo Band, fully quit (macOS Cmd-Q; mobile
   swipe-kill) **well within the 8-minute TTL**, then `./run.sh macos` (a genuine
   cold `main()` launch). **Expected (was failing):** the **login screen** — does
   **not** resume into Demo Band.
3. Repeat step 2 in **airplane mode / no network**. **Expected:** still the login
   screen (the purge is a local `SharedPreferences` op; no network needed).
4. Real-user regression: sign in as a normal (non-anonymous) account, quit,
   reopen. **Expected:** resumes straight into the account, **no** login prompt.
5. Web smoke (any browser): no demo button; normal real-user resume across a page
   reload is unchanged.

**The macOS relaunch is fixed in code/analysis only until Tony completes steps
2–3** — those are the authoritative runtime confirmation.

## QA Regression Areas

- **Real-user session persistence** (highest priority): a non-anonymous user must
  still auto-resume — the classifier requires `is_anonymous == true` (real blobs
  serialize `false`), covered by the classifier + storage-race tests and
  punch-list #4.
- **Live in-run demo flow**: tapping the demo button in the same run is
  unaffected (created after startup, never purged in-run) — punch-list #1.
- **Anonymous reconcile backstop**: `auth_gate_anonymous_recovery_test.dart` must
  still pass; `_reconcileOrphanedAnonymousSession()` is unchanged.
- **Startup robustness**: `main()` must reach `Supabase.initialize()` even if the
  purge throws (swallow-and-continue) — static review + full suite.
- **Init order**: `RUNTIME_CONFIG.md` + `DECISION-006` reflect step 5.5.
- **Platform parity (web)**: `!kIsWeb` gate; web backend differs and has no anon
  session — punch-list #5.

## Rollout Strategy

Standard single-PR rollout on `feature/demo-session-no-relaunch-resume`. No
migration, no feature flag, no phased deploy. Rollback is a straight revert of
`main.dart` (the pre-init purge call + import), the two `DemoSessionService`
members, the two test groups, and the two doc edits (`DECISION-006`,
`RUNTIME_CONFIG.md`) — nothing to unwind server-side (no DB change).

## Out of Scope

- Any change to #289's TTL, cron, advisory lock, capacity math, migration,
  grants, or the `exit-demo-session` edge function.
- Adding a cold-start **server-side** demo-slot release (reclamation stays with
  #289's TTL + cron).
- Redefining `isAuthenticated` / adding an anonymous branch to the auth
  provider/gate (would touch off-limits files and break the live demo + real-user
  semantics).
- Awaiting or cancelling the SDK's background `recoverSession()` (no public API),
  or the disproven **post-init** `signOut()` mechanism (see Superseded Mechanism).
- The uncommitted `didRequestAppExit()` desktop graceful-exit experiment from
  `bug/demo-capacity-check-race-and-leak` — not adopted; a pre-init purge covers
  force-kill/background on all native platforms, which an exit-time hook cannot.
- Removing or refactoring `_reconcileOrphanedAnonymousSession()` or the auth
  safeguards/sync timer — left intact as backstops.
- Any web demo entry point (does not exist; not being added).

## Superseded Mechanism (Cycles 1–3 — DISPROVEN; historical only)

> This section is the **only** place the old mechanism is recorded. Nothing above
> is an active instruction to implement it. It is retained for traceability and to
> prevent re-proposing a disproven fix.

**What Cycles 1–3 shipped (QA-APPROVED Cycle 3, then failed the owner test):** a
pure predicate `DemoSessionService.shouldPurgeRestoredAnonymousSession({required
bool hasSession, required bool isAnonymous}) => hasSession && isAnonymous`, and in
`main.dart` at init **step 6.5** — *after* `Supabase.initialize()` and before the
Firebase block — reading `currentSession` and, if it matched, `await
signOut(scope: SignOutScope.local).timeout(2s)`. `RUNTIME_CONFIG.md` and the first
draft of `DECISION-006` described that step 6.5.

**Why it failed (root cause, confirmed in SDK source — see Root Cause above):**
`Supabase.initialize()` starts a **non-awaited background `recoverSession()`**
(`supabase.dart` L156–159) that runs *after* `initialize()` returns and re-reads
the still-persisted anonymous blob from disk, resurrecting `currentSession` and
emitting `tokenRefreshed`. The step-6.5 `signOut()` nulled the in-memory session,
but the background restore won the race; the `signOut()`-triggered disk removal is
itself fire-and-forget and also lost. No post-init sign-out (timed out, retried,
or awaited) can beat a restore the SDK gives no public API to await or cancel.
Static analysis and the pure truth-table predicate could not catch this — the
predicate was correct; the *mechanism around it* raced the SDK.

**Replaced by:** the pre-init disk purge at init **step 5.5** (this plan, above),
which removes the anonymous blob before the SDK reads it, so neither
`setInitialSession` nor the background `recoverSession()` finds anything.
