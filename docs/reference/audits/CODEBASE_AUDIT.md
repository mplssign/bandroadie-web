# BandRoadie — Production Codebase Audit

**Date:** March 13, 2026
**Auditor:** Claude (Senior Flutter Architect)
**Scope:** Full repository — 225 Dart files across lib/, supabase/, build configs, and deployment pipeline
**Context:** Production app with 100+ bands. Recommendations prioritize stability over rewrites.

> This is a point-in-time audit. Items marked with **Update** notes have been resolved since the audit date. Verify current state before acting on any recommendation.

---

## 1. Critical Issues (Must Fix)

### 1.1 Exposed Android Keystore Credentials
**File:** `android/key.properties`
**Issue:** Plaintext keystore passwords committed to version control. The file is listed in `.gitignore` but appears to already be tracked.
**Risk:** Anyone with repo access can sign APKs as the legitimate app.
**Fix:** Remove from git history (`git rm --cached`), rotate the keystore password, and use GitHub Secrets or Fastlane for CI signing.

### 1.2 Exposed Firebase API Keys in iOS Config
**File:** `ios/GoogleService-Info.plist`
**Issue:** Firebase API key, project ID, and GCM sender ID are hardcoded in a committed plist.
**Risk:** Firebase key can be used to impersonate the app. While Firebase keys are semi-public by design, pairing with other leaked config is dangerous.
**Fix:** Use environment variable injection at build time. Consider Firebase App Check for additional protection.

### 1.3 Incomplete Firebase Service Worker (Web Push Broken)
**File:** `web/firebase-messaging-sw.js`
**Issue:** Contains placeholder values (`YOUR_API_KEY`, `YOUR_PROJECT_ID`). Web push notifications are non-functional.
**Fix:** Replace with actual Firebase config or inject at build time via the deploy script.

### 1.4 Zero Test Coverage
**File:** `test/`
**Issue:** Only 2 test files exist. `widget_test.dart` tests `1 + 1 = 2`. No tests for core business logic, repositories, controllers, or critical flows.
**Risk:** Regressions in gig management, setlists, RBAC, or push notifications go undetected.
**Fix:** Start with integration tests for the 5 most critical paths: auth flow, gig CRUD, setlist reorder, band switching, and member RBAC. Target 40% coverage on repositories and controllers first.

### 1.5 Silent Error Swallowing in Repositories
**Files:** `features/bands/band_repository.dart`, `features/bands/active_band_controller.dart`, `features/calendar/calendar_controller.dart`
**Issue:** Multiple `catch (e) { return []; }` or `catch (e) { // Silently fail }` blocks. When Supabase calls fail, the user sees empty state with no error indication.
**Risk:** Data loss appears as "no data" — users can't distinguish between empty state and a failed fetch.
**Fix:** Create a shared `AppError` base class. Return `Result<T, AppError>` from repositories. Show error banners in UI on failure.

---

## 2. Architectural Improvements

### 2.1 Monolithic Files Requiring Decomposition

| File | Lines | Problem |
|------|-------|---------|
| `features/setlists/setlist_repository.dart` | 4,027 | Single repository handles CRUD, catalog, bulk ops, tuning, and debug methods |
| `features/setlists/setlist_detail_screen.dart` | 2,788 | Widget manages state, animations, reordering, search, multi-select, and rendering |
| `features/bands/band_form_screen.dart` | 2,575 | Form, image upload, color picker, animations, and keyboard management in one widget |
| `features/profile/my_profile_screen.dart` | 1,826 | Profile editing + role management + UI |
| `features/setlists/setlist_detail_controller.dart` | 1,784 | Controller handles song broadcasting, reordering, deletion, and multiple derived providers |

**Recommended splits:**

`setlist_repository.dart` → Split into `SetlistRepository` (CRUD), `CatalogRepository` (catalog logic), `SetlistBulkRepository` (bulk operations). Move `debugFetchSongsRaw()` to a debug-only utility.

`setlist_detail_screen.dart` → Extract into `SetlistDetailContainer` (data coordination), `SetlistDetailView` (rendering), `SetlistSongList` (reorderable list), and `SetlistToolbar` (search/filter controls).

`band_form_screen.dart` → Extract `BandImagePicker` (image selection and upload) and `BandAvatarSelector` (color/image choice) as standalone widgets.

### 2.2 Empty Router File — Routing Hardcoded in main.dart
**File:** `app/app_router.dart` (0 bytes, empty)
**Issue:** All routing logic lives in `main.dart` lines 131–187 using `onGenerateRoute`. No named route constants. `_isMarketingHost()` check repeated 4 times.
**Fix:** Extract routing into `app_router.dart` or adopt GoRouter for type-safe, deep-link-aware routing.
**Note:** `go_router` is listed as a key dependency in `BAND_ROADIE_DOCUMENTATION.md` and the directory structure shows `app/router/`. Verify current state of router migration.

### 2.3 Anemic Service Layer
**Files:** `app/services/band_service.dart` (14 lines), `app/services/user_profile_service.dart` (14 lines)
**Issue:** Single-function wrappers around Supabase queries with no error handling, caching, or retry logic. They add indirection without value.
**Fix:** Either promote to proper services with caching and error handling, or delete and call Supabase directly from Riverpod providers.

### 2.4 Controller Pattern Inconsistency
**Issue:** Each controller reinvents state management differently:

| Controller | Pattern | Problem |
|-----------|---------|---------|
| `GigNotifier` | `Notifier<GigState>` | Manual `_lastLoadedBandId` + `Future.microtask` in `build()` |
| `RehearsalNotifier` | `Notifier<RehearsalState>` | Identical pattern to GigNotifier — code duplication |
| `ActiveBandNotifier` | `Notifier<ActiveBandState>` | Manages persistence + switching; does too much |
| `NotificationPreferencesNotifier` | `AsyncNotifier` | Different pattern entirely |
| `SetlistDetailController` | Custom Notifier (1,784 lines) | Handles 6+ concerns in one class |

**Fix:** Create a `BandScopedNotifier<T>` base class that handles band-change detection. Eliminates the duplicated `_lastLoadedBandId` / `Future.microtask` pattern across GigNotifier and RehearsalNotifier.

### 2.5 No Centralized Error Handling
**Issue:** Three different error classes exist (`SetlistQueryError`, `GigResponseError`, `NoBandSelectedError`), plus most code throws raw exceptions.
**Fix:** Create `AppError` hierarchy: `NetworkError`, `AuthError`, `ValidationError`, `NotFoundError`. Return `Result<T, AppError>` from all repository methods.

---

## 3. Redundancies to Eliminate

### 3.1 Duplicated Band-Change Detection
**Files:** `gig_controller.dart`, `rehearsal_controller.dart`
**Issue:** Both implement identical `_lastLoadedBandId` tracking with `Future.microtask()` in `build()`. This is fragile and violates Riverpod best practices (side effects in `build()`).
**Fix:** Extract into shared `BandScopedNotifier` base, or use Riverpod family providers keyed by `bandId`.

### 3.2 Duplicated Time-Filtering Logic
**File:** `features/gigs/gig_repository.dart` (lines 83–98, 122–137, 160–175)
**Issue:** The same date/time parsing and filtering logic is copy-pasted across `fetchPotentialGigs`, `fetchConfirmedGigs`, and `fetchUpcomingGigs`. Each includes a `try/catch` that silently swallows parse errors.
**Fix:** Extract `_filterFutureGigs(List<Gig>)` helper.

### 3.3 Duplicate Color Definitions
**Files:** `app/theme/app_theme.dart` vs `app/theme/design_tokens.dart`
**Issue:** `primaryColor = 0xFFBE123C` in app_theme.dart and `accent = 0xFFBE123C` in design_tokens.dart. Same hex, different names.
**Fix:** Single source of truth: always reference `AppColors.accent` from design_tokens.

### 3.4 Inconsistent Date Parsing Across Models
**Files:** `app/models/block_out.dart` (manual parsing), `app/models/gig.dart` (DateTime.parse)
**Issue:** BlockOut manually parses dates to handle local midnight edge cases. Gig uses raw `DateTime.parse()`. Different timezone behavior.
**Fix:** Extract shared `parseDateOnly()` utility in `TimeFormatter`.

### 3.5 Duplicated copyWith and Equality Implementations
**Issue:** Every state class (GigState, RehearsalState, CalendarState, etc.) manually implements copyWith, equality, and hashCode.
**Fix:** Use `freezed` code generation or at minimum a shared pattern/mixin.

---

## 4. Performance Risks

### 4.1 Parallel Network Calls on Band Switch
**Impact:** HIGH
**Issue:** When user switches bands, `activeBandProvider` changes trigger `GigNotifier.build()`, `RehearsalNotifier.build()`, and `CalendarNotifier.build()` — all firing network calls in parallel, potentially 3+ simultaneous requests.
**Fix:** Coordinate via a single `BandChangeEvent` or throttle refreshes.

### 4.2 Excessive Widget Rebuilds from Multiple watch() Calls
**Files:** `home_tab_content.dart`, `setlist_detail_screen.dart`
**Issue:** Widgets use multiple `ref.watch()` calls on providers that change independently. Any one change triggers a full rebuild of the entire widget tree.
**Fix:** Use `ref.watch(provider.select((s) => s.specificField))` to narrow rebuild scope. Extract child widgets that watch specific slices of state.

### 4.3 Missing Caching for Repeated Queries
**Files:** `members/members_repository.dart`, `calendar/calendar_controller.dart`
**Issue:** Members and calendar events are fetched fresh on every tab switch. No TTL cache, no stale-while-revalidate pattern. `EventsRepository` uses a 5-minute hardcoded TTL but other repositories have no caching at all.
**Fix:** Implement shared `CacheManager<T>` with configurable TTL. Use Riverpod's `keepAlive` and `ref.invalidateSelf()` for smart cache invalidation.

### 4.4 Heavy Work in build() Methods
**Files:** `setlist_detail_screen.dart`, `home_tab_content.dart`
**Issue:** Complex data transformations, list filtering, and sorting happening inside `build()` on every frame.
**Fix:** Move derived computations to dedicated computed providers or `useMemoized`.

### 4.5 No Web-Specific Performance Optimization
**Files:** `tools/deploy_web.sh`, `web/vercel.json`
**Issue:** PWA strategy is explicitly disabled (`--pwa-strategy=none`). No cache headers for static assets in Vercel config (only `version.json` has cache-control).
**Fix:** Add aggressive caching for versioned build artifacts (JS, CSS, fonts). Consider enabling PWA for offline capability.
**Update (April 2026):** `no-cache, no-store, must-revalidate` headers added to `index.html` and `flutter_service_worker.js` in `web/vercel.json` to prevent stale deploys.
**Update (2026-07-23):** Resolved. `web/vercel.json` now applies `public, max-age=31536000, immutable` cache headers to versioned static build artifacts: `/:path*.js`, `/flutter_bootstrap.js`, `/icons/:path*`, `/assets/:path*`, and `/canvaskit/:path*`.

---

## 5. Structural Improvements

### 5.1 Non-Dart Files Polluting lib/
**Directories:** `lib/config/`, `lib/auth/`, `lib/data/`, `lib/email/`, `lib/server/`, `lib/time/`, `lib/types/`, `lib/utils/`, `lib/supabase/`, `lib/components/`
**Issue:** Multiple top-level directories contain TypeScript files (backend code) or are empty. This is a Flutter project — `lib/` should contain only Dart.
**Fix:** Move TypeScript backend code to a separate `backend/` or `server/` directory at the project root. Remove empty Dart directories.

### 5.2 Inconsistent Feature Module Structure
**Issue:** Some features have clean separation (setlists has models/, services/, widgets/, tuning/). Others are flat files (rehearsals has just a controller and repository with no widgets/models subfolder).
**Fix:** Standardize: every feature gets `models/`, `widgets/`, and optionally `services/`. A flat structure is acceptable for very small features (legal, tips), but any feature with >3 files should organize.

### 5.3 Shared Code Underutilized
**Directory:** `lib/shared/`
**Issue:** Only 3 utilities exist (`scroll_blur_notifier.dart`, `email_domain_helper.dart`, `event_permission_helper.dart`). Many patterns duplicated across features should live in shared.
**Fix:** Move common patterns here: error handling, caching, band-scoped providers, date parsing utilities.

### 5.4 Migration Naming Inconsistency
**Directory:** `supabase/migrations/`
**Issue:** Mixed naming formats — some use 3-digit prefix (`073_fix_gig_responses.sql`), others use timestamps (`20260305100000_fix_rehearsal_rls.sql`).
**Fix:** Standardize on timestamp format going forward. Document migration strategy.

---

## 6. Code Cleanups

### 6.1 Debug Print Statements (947 occurrences)
**Issue:** Heavy `debugPrint()` usage across 51+ files. Creates noise in production logs, makes debugging harder (signal-to-noise ratio).
**Fix:** Create `AppLogger` service with levels (debug, info, warn, error). Replace all `debugPrint()` with structured logging. Gate debug logs behind `kDebugMode`.

### 6.2 Debug Methods in Production Code
**File:** `features/setlists/setlist_repository.dart` (lines 680–747)
**Issue:** `debugFetchSongsRaw()` smoke test method left in production repository.
**Fix:** Move to a debug-only utility or remove entirely.

### 6.3 Stale TODOs and Commented Stubs
| File | Issue |
|------|-------|
| `bands/band_form_screen.dart` line 1843 | `TODO: Change back when image upload working` |
| `bands/band_form_screen.dart` line 1847 | `TODO: Uncomment when image upload working` |
| `members/members_tab_content.dart` line 301 | `TODO: Open member detail in future` |
| `profile/my_profile_screen.dart` line 632 | Unclear bug fix comment |

**Fix:** Resolve or create tracked issues for each TODO. Remove dead commented-out code.

### 6.4 Android Code Obfuscation Disabled
**File:** `android/app/build.gradle.kts` (lines 55–56)
**Issue:** `isMinifyEnabled = false` and `isShrinkResources = false` for release builds. APK contains readable code and unused resources.
**Fix:** Enable minification with ProGuard rules for release builds. Test thoroughly after enabling.

### 6.5 Font Configuration Contradiction
**File:** `app/theme/app_theme.dart`
**Issue:** Comment says "DM Sans" but code sets `fontFamily: 'InterTight'`. The textTheme uses DM Sans but the top-level font is InterTight. Unclear which is intended.
**Fix:** Verify against pubspec.yaml font assets. Pick one primary font and document the decision.

---

## 7. Future-Proofing Suggestions

### 7.1 Add Crash Reporting
**Status:** No Sentry, Crashlytics (configured in iOS plist but not Android), or similar.
**Impact:** Production crashes are invisible. Users experience issues silently.
**Recommendation:** Add Sentry or Firebase Crashlytics with symbol upload for both platforms.

### 7.2 Create Staging Environment
**Status:** Deploy script supports `--preview` but no separate Supabase project for staging.
**Risk:** All testing happens against production data.
**Recommendation:** Create a staging Supabase project. Add environment switching to the deploy pipeline.

### 7.3 Adopt Result Types for Data Layer
**Pattern:** Replace `throw` / `try-catch` across repositories with `sealed class Result<T, E>` (or use the `fpdart` or `dartz` package).
**Benefit:** Forces callers to handle errors explicitly. Eliminates silent error swallowing.

### 7.4 Implement Structured Logging
**Pattern:** Create `AppLogger` with log levels, structured output, and optional remote logging.
**Benefit:** Replaces 947 scattered `debugPrint()` calls with filterable, actionable logs.

### 7.5 Consider GoRouter Migration
**Benefit:** Type-safe routing, built-in deep linking, redirect guards, and nested navigation. Eliminates the manual route matching in main.dart.
**Risk:** Moderate effort, but pays off as feature count grows.

### 7.6 Bump iOS Deployment Target
**File:** `ios/Podfile` — currently targets iOS 13.0.
**Recommendation:** Bump to 14.0+. Apple recommends it, and it unlocks modern APIs.

### 7.7 Fix Capacitor Version Mismatch
**File:** `package.json`
**Issue:** `@capacitor/cli: ^7.4.4` vs `@capacitor/core: ^8.0.0` and `@capacitor/android: ^8.0.0`.
**Fix:** Update CLI to `^8.0.0`.

---

## Priority Matrix

| Priority | Category | Items |
|----------|----------|-------|
| **P0 — Do Now** | Security | Rotate keystore password, remove key.properties from git, fix Firebase service worker |
| **P0 — Do Now** | Stability | Add error handling to repositories (stop silent swallowing) |
| **P1 — This Sprint** | Architecture | Split setlist_repository.dart (4,027 lines), extract band-change detection pattern |
| **P1 — This Sprint** | Quality | Add tests for top 5 critical flows |
| **P1 — This Sprint** | Performance | Add caching to members/calendar fetches |
| **P2 — Next Sprint** | Architecture | Decompose setlist_detail_screen.dart, band_form_screen.dart |
| **P2 — Next Sprint** | Code Quality | Replace debugPrint with structured logging, resolve TODOs |
| **P2 — Next Sprint** | Build | Enable Android obfuscation, fix Capacitor version |
| **P3 — Backlog** | Future-Proofing | GoRouter migration, crash reporting, staging environment, Result types |

---

*This audit was performed as a read-only analysis of the full repository. No files were modified.*
