# ARCHITECT_PLAN.md — bug/notification-preferences-duplicate-provider

## 1. Feature Slug

`bug/notification-preferences-duplicate-provider`

Branch name: `bug/notification-preferences-duplicate-provider`
Docs path: `docs/features/notification-preferences-duplicate-provider/`

## 2. Problem Summary

Two files in `lib/features/notifications/` each declare top-level Riverpod providers named `notificationPreferencesProvider` and `notificationRepositoryProvider`:

- [lib/features/notifications/notification_controller.dart](lib/features/notifications/notification_controller.dart) — declares one `notificationPreferencesProvider` backed by `NotificationPreferencesNotifier`; also declares a duplicate `notificationRepositoryProvider`.
- [lib/features/notifications/notification_preferences_controller.dart](lib/features/notifications/notification_preferences_controller.dart) — declares a second, differently-typed `notificationPreferencesProvider` backed by `NotificationPreferencesController`; also declares its own `notificationRepositoryProvider`.

The compiler tolerates this today only because no single translation unit imports both files. The `notificationPreferencesProvider` in `notification_controller.dart` is consumed exclusively by [lib/features/notifications/notification_preferences_screen.dart](lib/features/notifications/notification_preferences_screen.dart), and that screen is not reachable from anywhere in the app. The result is ~500 lines of dead/orphaned code and a name-collision hazard where any future file that imports both files will fail to compile, and where a reported preferences bug can easily be "fixed" in the wrong (dead) location.

The activity-feed portion of `notification_controller.dart` (`NotificationListState`, `notificationListProvider`, `NotificationListNotifier`, `unreadNotificationCountProvider`) is live and consumed by [lib/features/notifications/widgets/notification_card.dart](lib/features/notifications/widgets/notification_card.dart#L30); only the preferences-related portion is dead.

## 3. Root Cause

**Confidence: HIGH** (direct code observation).

Two independent implementations of notification preferences were introduced into the same feature directory. One (`notification_preferences_controller.dart` + `notification_settings_screen.dart`) was wired up and used to replace the older one, but the older implementation (`notification_controller.dart`'s preferences half + `notification_preferences_screen.dart`) was never removed. Independent verification on `main` (2026-08-30):

- `NotificationPreferencesScreen` — 6 grep matches in `lib/`, all internal to `notification_preferences_screen.dart` itself. Zero imports, zero navigation call sites, zero references in any deep-link handler or push-tap handler. Unreachable.
- `NotificationSettingsScreen` — 3 grep matches: 2 self-references + 1 navigation call site at [lib/features/settings/settings_screen.dart:97](lib/features/settings/settings_screen.dart#L97) inside `_openNotifications()`. Single entry point confirmed.
- `NotificationPreferencesNotifier` — 3 grep matches, all internal to `notification_controller.dart` (class declaration + provider generic + provider constructor). Zero external consumers.
- `main.dart` `onGenerateRoute` handles only `/`, `/privacy`, `/invite`, `/auth/confirm` — no notification-related named routes.
- `DeepLinkService` handles auth callbacks only and returns early ("Not an auth callback, ignoring") for anything else.
- `PushNotificationService` routes notification taps via the `_handleNotificationOpen` → `onNotificationTap` callback path, which resolves to gig/rehearsal/blockout destinations via `AppNotification.deepLink` metadata; no path resolves to `NotificationPreferencesScreen`.
- No test file references any of the dead symbols (`NotificationPreferencesScreen`, `NotificationPreferencesNotifier`, `notification_preferences_screen`).

## 4. Reference Docs Consulted

Read in full from [docs/reference/notifications/](docs/reference/notifications/):

- [docs/reference/notifications/NOTIFICATION_SYSTEM.md](docs/reference/notifications/NOTIFICATION_SYSTEM.md)
- [docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md](docs/reference/notifications/NOTIFICATION_PERMISSION_FLOW.md)
- [docs/reference/notifications/notifications.md](docs/reference/notifications/notifications.md)

Relevant facts from the reference docs that constrain this plan:

- `NOTIFICATION_SYSTEM.md` → "Settings UI" section names `NotificationSettingsScreen` at `lib/features/notifications/notification_settings_screen.dart` as the canonical settings screen.
- `NOTIFICATION_SYSTEM.md` → "Client-Side Components" section names `NotificationPreferencesController` in `lib/features/notifications/notification_preferences_controller.dart` as the canonical preferences controller, and gives an example `notificationRepositoryProvider` declaration matching the one in `notification_preferences_controller.dart`.
- `NOTIFICATION_SYSTEM.md` → "File Inventory" section lists exactly these Flutter files: `notification_repository.dart`, `notification_preferences_controller.dart`, `notification_settings_screen.dart`, `push_notification_service.dart`, plus the models directory. Neither `notification_controller.dart` nor `notification_preferences_screen.dart` appears in any reference doc.
- `NOTIFICATION_PERMISSION_FLOW.md` → describes the master-toggle/categories UI implemented in `notification_settings_screen.dart` (the live screen).

Conclusion: reference docs confirm which files are canonical. The two files this plan removes/trims are not part of the documented notification architecture.

## 5. Existing System Analysis

Symbol inventory of the two colliding files as they exist on `main`:

`notification_controller.dart` (245 lines):

| Symbol                                               | Status                              | Consumers                                                                                                                                                            |
| ---------------------------------------------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `NotificationListState`                              | LIVE                                | Return type of `notificationListProvider`; consumed inside `NotificationListNotifier`                                                                                |
| `notificationRepositoryProvider`                     | DUPLICATE — internal-only consumers | `unreadNotificationCountProvider` (this file) + `NotificationListNotifier` methods (this file). No external file imports this declaration by path.                   |
| `unreadNotificationCountProvider`                    | LIVE (internal ref only)            | Invalidated by `NotificationListNotifier.markAsRead` / `markAllAsRead`; no external UI watches it, but it is part of the live notifier's contract                    |
| `notificationPreferencesProvider` (this file's copy) | DEAD                                | Only consumed by `notification_preferences_screen.dart`                                                                                                              |
| `NotificationPreferencesNotifier`                    | DEAD                                | Only used to construct the dead `notificationPreferencesProvider`                                                                                                    |
| `notificationListProvider`                           | LIVE                                | [widgets/notification_card.dart:30](lib/features/notifications/widgets/notification_card.dart#L30) via `ref.read(notificationListProvider.notifier).markAsRead(...)` |
| `NotificationListNotifier`                           | LIVE                                | Backs `notificationListProvider`                                                                                                                                     |

`notification_preferences_controller.dart` (113 lines) — all live:

| Symbol                              | Status | Consumers                                                                        |
| ----------------------------------- | ------ | -------------------------------------------------------------------------------- |
| `notificationRepositoryProvider`    | LIVE   | Used inside `NotificationPreferencesController.build()`                          |
| `notificationPreferencesProvider`   | LIVE   | Consumed by `notification_settings_screen.dart` (5 `ref.watch`/`ref.read` sites) |
| `NotificationPreferencesController` | LIVE   | Backs the live `notificationPreferencesProvider`                                 |

`notification_preferences_screen.dart` (251 lines): entire file is DEAD (no imports, no navigation call sites, no route registrations).

Data flow of the current, reachable preferences UI (unchanged by this plan):

1. `SettingsScreen._openNotifications()` pushes a `MaterialPageRoute` to `NotificationSettingsScreen`.
2. `NotificationSettingsScreen.build()` calls `ref.watch(notificationPreferencesProvider)` — resolved from `notification_preferences_controller.dart`.
3. `NotificationPreferencesController.build()` reads `notificationRepositoryProvider` (also in `notification_preferences_controller.dart`) and calls `NotificationRepository.getOrCreatePreferences()`.
4. Toggle callbacks invoke `.updateXxxEnabled(...)` on the controller, which does optimistic UI + `NotificationRepository.updatePreferences()`.

Data flow of the activity feed (also unchanged by this plan):

1. `NotificationCard` (activity feed row) calls `ref.read(notificationListProvider.notifier).markAsRead(notification.id)` on tap.
2. `NotificationListNotifier` uses `ref.read(notificationRepositoryProvider)` to hit `NotificationRepository.markAsRead(...)` and invalidates `unreadNotificationCountProvider`.
3. After this plan, `notificationRepositoryProvider` will be resolved via `notification_preferences_controller.dart` (imported from `notification_controller.dart`) instead of via the local duplicate declaration. Behavior is identical.

Backend pipeline (unchanged and untouched by this plan): database triggers → `notifications` table → pg_cron / webhook → `send-push` / `deliver-notifications` Edge Function → FCM HTTP v1 → device.

## 6. Proposed Solution

Minimal deletion + one import redirect.

1. Delete [lib/features/notifications/notification_preferences_screen.dart](lib/features/notifications/notification_preferences_screen.dart) in full (all 251 lines). The class has zero external references; the file has zero external importers.
2. Inside [lib/features/notifications/notification_controller.dart](lib/features/notifications/notification_controller.dart), remove the dead preferences half of the file — specifically the duplicate `notificationRepositoryProvider` declaration, the `notificationPreferencesProvider` declaration, and the `NotificationPreferencesNotifier` class (with all its methods). Preserve the entire activity-feed half: `NotificationListState`, `unreadNotificationCountProvider`, `notificationListProvider`, `NotificationListNotifier`.
3. Add `import 'notification_preferences_controller.dart';` to `notification_controller.dart` so that `unreadNotificationCountProvider` and `NotificationListNotifier` continue to resolve the symbol `notificationRepositoryProvider` after the local declaration is removed. Remove the three imports that become unused as a result of the deletions (`package:supabase_flutter/supabase_flutter.dart`, `models/notification_preferences.dart`, `notification_repository.dart`).

Result: exactly one `notificationPreferencesProvider` in the codebase (in `notification_preferences_controller.dart`), exactly one `notificationRepositoryProvider` (also in `notification_preferences_controller.dart`), exactly one preferences screen (`NotificationSettingsScreen`).

Why not move `notificationRepositoryProvider` to `notification_repository.dart` (arguably the most idiomatic home): that would require editing `notification_preferences_controller.dart`, which Guardrail §7 and the Feature Input's Additional Context both flag as "keep as-is". Redirecting via import keeps the diff surface off the untouchable file.

Why not add `show notificationRepositoryProvider` to the new import: `notification_controller.dart` has no other symbol overlap with `notification_preferences_controller.dart` after the deletions, so the plain import matches the existing style in `notification_settings_screen.dart:8` and adds no risk. Engineer must use the plain form.

## 7. Database Impact

`Database: not applicable`.

No migration, no RLS change, no RPC signature change, no trigger change, no edge function change. The `notification_preferences` table schema (including the legacy `gig_updates`/`rehearsal_updates` columns called out in the Feature Input's Out of Scope) is not touched. The `NotificationRepository.updatePreferences()` payload (which writes both legacy and current columns) is not touched.

## 8. Flutter Architecture Changes

- **State**: the dead `notificationPreferencesProvider` in `notification_controller.dart` is removed. The live `notificationPreferencesProvider` in `notification_preferences_controller.dart` is unchanged. Provider name resolution across the notifications feature becomes unambiguous.
- **Widgets**: `NotificationPreferencesScreen` is deleted. `NotificationSettingsScreen` is unchanged.
- **Repositories**: no change. The class `NotificationRepository` is untouched. Only the duplicate provider declaration for it is removed.
- **Cross-file dependency**: `notification_controller.dart` will depend on `notification_preferences_controller.dart` for the `notificationRepositoryProvider` symbol. This is a one-directional import; no circular dependency (`notification_preferences_controller.dart` does not import `notification_controller.dart`).

## 9. Files to Create

`none`

## 10. Files to Modify

| File                                                                                                               | What changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/notifications/notification_controller.dart](lib/features/notifications/notification_controller.dart) | Delete the duplicate `notificationRepositoryProvider` declaration, the entire `notificationPreferencesProvider` declaration, and the entire `NotificationPreferencesNotifier` class (build + all six `toggle*` methods + `updatePreferences`). Remove three now-unused imports: `package:supabase_flutter/supabase_flutter.dart`, `models/notification_preferences.dart`, `notification_repository.dart`. Add one import: `notification_preferences_controller.dart`. Preserve `NotificationListState`, `unreadNotificationCountProvider`, `notificationListProvider`, `NotificationListNotifier` byte-for-byte. Keep the `NOTIFICATION CONTROLLER` banner comment; the file now legitimately covers only the notification list. |

## 11. Files to Delete

| File                                                                                                                               | Reason                                                                                                                                                         |
| ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/notifications/notification_preferences_screen.dart](lib/features/notifications/notification_preferences_screen.dart) | Full file (251 lines). Class `NotificationPreferencesScreen` has zero external references. No named route, no deep-link path, no push-tap path resolves to it. |

## 12. Files Off-Limits

| File                                                                                                                                       | Reason                                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [lib/features/notifications/notification_preferences_controller.dart](lib/features/notifications/notification_preferences_controller.dart) | Feature Input directive: "code to keep as-is, not to refactor beyond what's needed to remove the dead sibling." This is the canonical preferences controller.                                                                                           |
| [lib/features/notifications/notification_settings_screen.dart](lib/features/notifications/notification_settings_screen.dart)               | Feature Input directive: same clause. This is the sole reachable preferences UI.                                                                                                                                                                        |
| [lib/features/notifications/notification_repository.dart](lib/features/notifications/notification_repository.dart)                         | Class `NotificationRepository` is correct as written. No behavior change required.                                                                                                                                                                      |
| [lib/features/notifications/models/notification_preferences.dart](lib/features/notifications/models/notification_preferences.dart)         | Model is consumed by the live controller, repository, and settings screen. Legacy fields (`setlist_updates`, `availability_requests`, `member_updates`) remain as they are — a separate schema-consolidation item per the Feature Input's Out of Scope. |
| [lib/features/notifications/widgets/notification_card.dart](lib/features/notifications/widgets/notification_card.dart)                     | Sole external consumer of the live `notificationListProvider`. No change required.                                                                                                                                                                      |
| [lib/features/notifications/push_notification_service.dart](lib/features/notifications/push_notification_service.dart)                     | Constructs its own `NotificationRepository` instance directly (does not depend on either provider declaration). Delivery pipeline is entirely unaffected.                                                                                               |
| [lib/features/settings/settings_screen.dart](lib/features/settings/settings_screen.dart)                                                   | Sole navigation call site (`_openNotifications` at line 97) already points to the correct `NotificationSettingsScreen`.                                                                                                                                 |
| [lib/main.dart](lib/main.dart)                                                                                                             | `onGenerateRoute` handles auth/invite/privacy only. No change. Initialization order is not touched.                                                                                                                                                     |
| Any file outside `lib/features/notifications/` (other than the assertions above)                                                           | Not part of the diagnosed problem.                                                                                                                                                                                                                      |
| `supabase/migrations/*`, `supabase/functions/*`                                                                                            | Backend pipeline is out of scope.                                                                                                                                                                                                                       |

**Migration policy:** not required
**Edge function deploy:** not required
**New dependencies:** not allowed
**New files:** `none`

## 13. System Impact Map

| System                                 | Impact                                                                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                                                  |
| Rehearsals                             | unaffected                                                                                                                                  |
| Setlists / Catalog                     | unaffected                                                                                                                                  |
| Members / RBAC                         | unaffected                                                                                                                                  |
| Auth / Session                         | unaffected                                                                                                                                  |
| Routing                                | unaffected                                                                                                                                  |
| Notifications                          | affected — dead preferences UI removed, duplicate providers collapsed to one canonical source; delivery pipeline and reachable UI unchanged |
| Platform (iOS / Android / Web / macOS) | unaffected                                                                                                                                  |

## 14. Regression Risk

**LOW.**

- Only one system in the impact map is `affected`, and the change on that system is strictly a subtractive cleanup — no new code paths, no changed control flow through any live consumer.
- No auth, session, routing, or init-order changes.
- No database mutations, RLS changes, RPC signature changes, or edge function deploys.
- The backend delivery pipeline (triggers, cron, `send-push` / `deliver-notifications` Edge Functions, FCM) is completely untouched.
- The sole external consumer of the live activity-feed provider (`notification_card.dart` → `notificationListProvider`) sees an unchanged symbol at an unchanged location; the only difference is that the transitively-resolved `notificationRepositoryProvider` now comes from `notification_preferences_controller.dart` instead of the deleted local declaration, but its `Provider<NotificationRepository>` body is identical to what it replaces (verified by direct comparison).
- Zero test files reference any deleted symbol.

## 15. Engineer Task Breakdown

Ordered, atomic. Do not reorder. Do not combine.

1. **Delete file.** Delete `lib/features/notifications/notification_preferences_screen.dart` in full. Do not stage any other change in this step.
2. **Edit `notification_controller.dart` imports.** Remove these three lines:
   - `import 'package:supabase_flutter/supabase_flutter.dart';`
   - `import 'models/notification_preferences.dart';`
   - `import 'notification_repository.dart';`
     Add one line, placed alphabetically with the other relative imports:
   - `import 'notification_preferences_controller.dart';`
     Do not use a `show` clause. Do not reorder other imports.
3. **Delete the duplicate `notificationRepositoryProvider` declaration** in `notification_controller.dart` (the block that begins `final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {` and ends `});`). Do not touch `unreadNotificationCountProvider` immediately below it.
4. **Delete the `notificationPreferencesProvider` declaration and the `NotificationPreferencesNotifier` class** in `notification_controller.dart`. This is a contiguous block that begins `/// Provider for notification preferences` and ends at the closing `}` of the `NotificationPreferencesNotifier` class (immediately before the `/// Provider for notification list with pagination` comment). Do not delete anything below that comment.
5. **Verify residual file structure.** After tasks 1–4, `notification_controller.dart` must contain exactly, in order: the file-level `NOTIFICATION CONTROLLER` banner comment, `NotificationListState` class, `notificationRepositoryProvider` reference (via import) used inside `unreadNotificationCountProvider`, `unreadNotificationCountProvider` declaration, `notificationListProvider` declaration, `NotificationListNotifier` class. No stray blank lines beyond what the file already had between preserved sections.
6. **Run `flutter analyze`.** Must be clean (0 errors, 0 warnings introduced by this change).
7. **Run `flutter test`.** Existing test suite must pass with the same result as `main` (per prior session logs: 176/176 passing).
8. **Confirm three manual sanity greps** and record the results in `ENGINEER_REPORT.md`:
   - `grep -rn "NotificationPreferencesScreen" lib/` → zero matches.
   - `grep -rn "NotificationPreferencesNotifier" lib/` → zero matches.
   - `grep -rn "notificationPreferencesProvider" lib/` → exactly the declaration in `notification_preferences_controller.dart` plus the consumer sites in `notification_settings_screen.dart`; no matches in `notification_controller.dart` or `notification_preferences_screen.dart`.

## 16. Verification Plan

The Tier 1 (pre-`supabase db push`) / Tier 2 (post-`supabase db push`) split from `ARCHITECT.md` §12 does not apply here because this change contains no SQL migration, no edge function change, and no database object modification. Verification is a single tier of Dart-side checks:

**Static analysis**

- `flutter analyze` returns exit 0 with no new warnings.
- The four dead-symbol greps in Task 8 all return the expected results.

**Unit / widget tests**

- `flutter test` — all previously-passing tests still pass. No new tests required (the change is pure deletion + one import redirect; there is no new behavior to test, and existing tests do not depend on the deleted symbols per repo-wide grep on 2026-08-30).

**Runtime smoke — the reachable preferences UI**

Perform on any single platform (iOS or macOS, since these are the fastest local runs). QA is not required to reproduce on all four platforms because the change is platform-agnostic Dart code.

1. Launch the app, sign in, select any band.
2. Open **Settings** → **Notifications**. Confirm `NotificationSettingsScreen` renders (master toggle card + category list when master is on).
3. Toggle **Notifications** master OFF, then ON. Confirm the category checkboxes hide/show as expected and that toggling the master triggers the `enableNotifications` / `disableNotifications` path (system permission flow may prompt; either the granted or denied path is acceptable as long as no crash occurs).
4. With master ON and system permission granted, toggle each category (Gigs, Potential Gigs, Rehearsals, Block-out Dates) OFF then ON. Confirm no error snackbar and no crash. Confirm the toggle state visually reflects the new value.
5. Force-quit and relaunch; open Settings → Notifications again; confirm the toggles reflect the last set values (persistence via `notification_preferences` table is intact).

**Runtime smoke — the live activity feed**

1. From the app shell, open the notifications activity feed (whichever entry point already exists; `NotificationCard` is the row widget).
2. Confirm the list loads (i.e., `notificationListProvider` still initializes and `NotificationListNotifier.loadInitial` still resolves via `notificationRepositoryProvider`).
3. Tap any unread notification card. Confirm it visually transitions to the read state (mark-as-read path uses `NotificationListNotifier.markAsRead`, which uses the imported `notificationRepositoryProvider`).
4. Confirm the unread count provider (`unreadNotificationCountProvider`) refreshes — either through any UI that watches it, or by re-entering the feed.

**Runtime smoke — negative check**

- Confirm that no navigation path in Settings, in the activity feed, in a push notification tap, or in a deep link, opens the old `NotificationPreferencesScreen`. The deleted file guarantees this at compile time — any surviving reference will fail `flutter analyze` — but QA should still spot-check the Settings screen and the notification tap flow to confirm no visible regression.

## 17. QA Regression Areas

Beyond the Verification Plan above, QA must also confirm:

- **Sole navigation call site.** `SettingsScreen` → **Notifications** row still opens `NotificationSettingsScreen` (verify by both tap and by grepping the diff to confirm `settings_screen.dart` was not modified).
- **Activity feed regression.** Notification list still loads, paginates (`loadMore`), refreshes (`refresh`), marks single items read (`markAsRead`), and marks all read (`markAllAsRead`). All four code paths in `NotificationListNotifier` traverse `ref.read(notificationRepositoryProvider)` — the redirected import must resolve identically.
- **No stray provider name.** After the change, grepping `notificationPreferencesProvider` across `lib/` must return matches only from `notification_preferences_controller.dart` (the declaration) and `notification_settings_screen.dart` (the five consumer sites). Zero matches from anywhere else.
- **No stray screen class.** After the change, grepping `NotificationPreferencesScreen` across `lib/` must return zero matches.
- **No behavior change to notification delivery.** QA does not need to end-to-end test push delivery because this change touches no backend, no edge function, no trigger, and no device-token code. But a spot check that creating a gig still produces a notification record and a delivered push (on a real device already registered) confirms no accidental breakage of the shared `notificationRepositoryProvider` symbol.
- **No behavior change to the notification permission flow.** The pre-permission modal, the "Open Settings" modal, and the app-shell first-launch prompt all remain wired to `notification_permission_service.dart` and `notification_preferences_controller.dart`, both untouched.

## 18. Rollout / Migration Strategy

Standard branch → PR → QA → merge → main flow. No feature flag, no staged rollout, no backfill.

- No database migration.
- No edge function redeploy.
- No user-visible change on any platform.
- After merge, `./tools/deploy_web.sh` may run at Manager discretion but is not required by this change (dead-code removal has no user-visible payload).

## 19. Out of Scope

- **`notification_preferences` table schema consolidation.** The table has both legacy columns (`gig_updates`, `rehearsal_updates`, `setlist_updates`, `availability_requests`, `member_updates`, `push_enabled`) and current columns (`notifications_enabled`, `gigs_enabled`, `potential_gigs_enabled`, `rehearsals_enabled`, `blockouts_enabled`). `NotificationRepository.updatePreferences()` writes both. Do not touch. Separate item.
- **Renaming `notification_controller.dart`.** After this plan, the file legitimately covers only the notification list (activity feed), not preferences. A rename to `notification_list_controller.dart` would be more accurate but is opportunistic per Guardrail §7. Not part of this fix.
- **Moving `notificationRepositoryProvider` to `notification_repository.dart`.** Arguably the ideal home. Not done here because it would require editing `notification_preferences_controller.dart`, which the Feature Input flagged as untouchable.
- **`unreadNotificationCountProvider` refactor.** Currently the provider is only invalidated internally by `NotificationListNotifier`; no external UI watches it. This may indicate it is over-engineered for its current usage. Not investigated further; not part of this fix.
- **Notification delivery pipeline** (triggers, cron, `send-push` / `deliver-notifications` Edge Functions, FCM v1 auth, device token lifecycle). Entirely untouched.
- **Notification permission flow** (pre-permission modal, "Open Settings" modal, iOS/Android/Web permission service). Entirely untouched.
- **Deep-link routing.** `DeepLinkService` and `PushNotificationService` tap-handling are untouched.

---

## Workspace state note for the Manager

At the time this plan was written, the working tree on `main` had five pre-existing modified files, all in `macos/` (Podfile, Podfile.lock, `Runner.xcodeproj/project.pbxproj`, and two `Package.resolved` files). These are unrelated to this feature and appear to be CocoaPods/Xcode regeneration artifacts from prior mobile-build sessions. Per `ARCHITECT.md` Phase 13, the Architect is directed not to proceed with branch creation while unrelated uncommitted changes exist. The Manager or Tony should decide whether to stash/commit those macOS files before the Engineer begins Task 1. `git checkout -b bug/notification-preferences-duplicate-provider` will safely carry them across, but they must not be included in this feature's commits.
