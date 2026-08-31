# Feature Slug

bug/android-build-kotlin-version-mismatch

# Problem Summary

The Android release build (`./tools/build_mobile_release.sh android-aab`) failed at the Gradle `bundleRelease` task. The Flutter Gradle plugin (`dev.flutter.flutter-gradle-plugin`) now enforces a minimum Kotlin Gradle Plugin (KGP) version of `2.2.20`, but `android/settings.gradle` was still pinned to the original scaffolding value of `2.1.0`. This blocked producing a signed AAB for gate review. iOS, macOS, and Web release builds were unaffected because they do not consume the Android KGP pin. The fix must be minimal: bump the KGP pin only, without touching AGP, Gradle wrapper, iOS/macOS SwiftPM lockfiles, or any application source.

# Root Cause

The Flutter Gradle plugin bundled with the current Flutter SDK enforces a **minimum** Kotlin plugin version of `2.2.20`. The project's `android/settings.gradle` declared:

```groovy
id "org.jetbrains.kotlin.android" version "2.1.0" apply false
```

That version is below the enforced minimum, so the Gradle configuration phase rejected the build before compilation started. `android/settings.gradle.kts` also exists in the repo, but Gradle prefers the Groovy `settings.gradle` when both are present, which is why editing the Groovy file is sufficient and correct.

Root cause confidence: **HIGH**. Confirmed by direct reproduction: with `2.1.0` pinned the build fails at `bundleRelease`; with `2.2.20` pinned the build succeeds and produces `build/app/outputs/bundle/release/app-release.aab`.

## Compatibility research (why AGP and Gradle stay pinned)

Per JetBrains' Kotlin Gradle Plugin compatibility matrix:

- **Kotlin 2.2.20 ↔ Gradle**: fully supported up to Gradle **8.14**. The repo uses **8.14** — at the top of the fully-supported window, but still OK.
- **Kotlin 2.2.20 ↔ AGP**: fully supported up to AGP **8.11.1**. The repo uses AGP **8.13.2**, which sits **above** the fully-supported max but within the "permitted with possible deprecation warnings" range documented by JetBrains.
- Flutter emits three non-fatal warnings during the build ("Gradle support will soon be dropped", "AGP support will soon be dropped", "Kotlin support will soon be dropped"). These are the expected forward-looking deprecation notices and are tracked separately.

**Decision**: leave AGP (`8.13.2`) and Gradle (`8.14`) untouched for this bug. Bumping either one would expand scope beyond the Kotlin minimum-version enforcement that actually caused the failure, and would introduce additional regression risk unrelated to unblocking gate review.

# Reference Docs Consulted

This is not a notifications-domain bug, so `docs/reference/notifications/` was not consulted per the ARCHITECT.md guidance (notification reference is required only for notification failures). No BandRoadie reference docs cover Android toolchain versioning.

External evidence relied on:

- Flutter tool's own build-time warnings, which explicitly named the minimum Kotlin version (2.2.20), the minimum Gradle (9.1.0), and the minimum AGP (9.0.1) currently emitted as "soon" deprecations.
- JetBrains Kotlin Gradle Plugin compatibility matrix for KGP ↔ Gradle and KGP ↔ AGP support windows.

# Existing System Analysis

Android build flow at the time of failure:

1. `./tools/build_mobile_release.sh android-aab` loads `.env`, validates Supabase and demo-password variables, and runs `flutter clean` for a cold release build.
2. It invokes `flutter build appbundle --release --target=lib/main.dart --dart-define=...`.
3. Flutter shells out to Gradle: `Running Gradle task 'bundleRelease'…`.
4. Gradle's configuration phase applies `dev.flutter.flutter-gradle-plugin`, which reads the Kotlin plugin version declared in `settings.gradle` and compares it against the enforced minimum.
5. With `2.1.0` declared, Gradle aborts with a clear "minimum Kotlin version" error before compilation.
6. The wrapper script's post-build verification (Supabase URL and DEMO_PASSWORD string checks against the AAB) never runs because no AAB was produced.

Nothing else in the flow was broken. Dart entry point, `.env` loading, `--dart-define` injection, the AAB verifier, signing config, and the Play Store keystore path were all correct.

# Proposed Solution

Change the Kotlin plugin pin from `2.1.0` to `2.2.20` in `android/settings.gradle` (single line). This is the minimum-scoped change that satisfies the Flutter Gradle plugin's enforced floor and unblocks the release build.

What changes:

- `android/settings.gradle`: `id "org.jetbrains.kotlin.android" version "2.1.0" apply false` → `id "org.jetbrains.kotlin.android" version "2.2.20" apply false`

What must NOT change:

- `android/settings.gradle.kts` (unused when the Groovy variant exists — no need to keep two files in sync speculatively).
- `android/build.gradle` and `android/build.gradle.kts` — no root-level `ext.kotlin_version` change is needed because the plugins-block pin is the authoritative source.
- `android/gradle/wrapper/gradle-wrapper.properties` — Gradle 8.14 stays.
- AGP (`8.13.2`) declared in the same plugins block — stays; JetBrains permits the KGP↔AGP pairing with deprecation warnings only.
- Any iOS, macOS, or Web files. The SwiftPM `Package.resolved` lockfiles under `ios/**` and `macos/**` must be reverted if `flutter clean && flutter pub get` (which the release script performs) causes them to re-resolve, because that Firebase iOS SDK bump (12.15.0 → 12.18.0) is unrelated to this Android-only bug and should not ride along.
- Any `lib/**` application code, tests, migrations, edge functions, or `pubspec.yaml` entries.

# Database Impact

Database: **not applicable**.

No schema, RLS policy, RPC, trigger, edge function, or migration is touched. The fix is entirely a build-tooling version pin and produces no runtime behavior change.

# Flutter Architecture Changes

Flutter architecture changes: **none**.

No state management, widget, repository, provider, controller, model, service, routing, or theme code is modified. This is a Gradle-plugin version bump only.

# Files to Create

**none**

# Files to Modify

| File                      | What changes                                                                            |
| ------------------------- | --------------------------------------------------------------------------------------- |
| `android/settings.gradle` | Bump `org.jetbrains.kotlin.android` plugin version from `2.1.0` to `2.2.20` — one line. |

# Files Off-Limits

| File                                                | Reason                                                                                                                               |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `android/settings.gradle.kts`                       | Not the active settings file when the Groovy variant exists. Editing both would be speculative and out of scope.                     |
| `android/build.gradle` / `android/build.gradle.kts` | Root-level Kotlin version property is not the source of truth; the plugins block in `settings.gradle` is.                            |
| `android/gradle/wrapper/gradle-wrapper.properties`  | Gradle 8.14 is compatible with Kotlin 2.2.20 per JetBrains' matrix. Bumping Gradle expands scope and adds unrelated regression risk. |
| `pubspec.yaml`, `pubspec.lock`                      | No pub dependency change is required.                                                                                                |
| `ios/**`, `macos/**` (all)                          | Android-only bug. In particular, the four `Package.resolved` SwiftPM lockfiles must not be committed as part of this fix.            |
| `lib/**`                                            | No application code is affected.                                                                                                     |
| `supabase/**`, `sql/**`, `database/**`              | No database or backend change is required.                                                                                           |
| `.github/workflows/**`                              | CI change is out of scope; the local release script is what surfaced the failure and what is being unblocked.                        |

# System Impact Map

| System                             | Impact                                                                            |
| ---------------------------------- | --------------------------------------------------------------------------------- |
| Gigs                               | unaffected                                                                        |
| Rehearsals                         | unaffected                                                                        |
| Setlists / Catalog                 | unaffected                                                                        |
| Members / RBAC                     | unaffected                                                                        |
| Auth / Session                     | unaffected                                                                        |
| Routing                            | unaffected                                                                        |
| Notifications                      | unaffected                                                                        |
| Platform — iOS                     | unaffected                                                                        |
| Platform — macOS                   | unaffected                                                                        |
| Platform — Web                     | unaffected                                                                        |
| Platform — Android                 | affected (build toolchain only; runtime code unchanged)                           |
| Release automation / build scripts | unaffected (script itself is unchanged; only the plugin version it invokes moves) |

# Regression Risk

Regression risk: **LOW**.

Rationale:

- Single-line change to a plugin version pin, isolated to Android build configuration.
- No app source, no Dart, no database, no notification code touched.
- Kotlin 2.1.0 → 2.2.20 is a supported KGP upgrade path per JetBrains. No source-level Kotlin changes are needed because the project's `android/app/*.kt` files use standard Flutter template constructs.
- AGP and Gradle stay pinned, so no build-tool cascade is triggered.
- Verified end-to-end by producing a signed AAB and passing the release script's Supabase-URL and DEMO_PASSWORD embedded-string checks.
- iOS, macOS, and Web release paths are structurally untouched.

# Engineer Task Breakdown

1. Confirm current branch: `bug/android-build-kotlin-version-mismatch`.
2. Edit `android/settings.gradle`: change the Kotlin plugin pin from `2.1.0` to `2.2.20`. No other edits.
3. Run `flutter pub get` to make sure Dart deps are resolved (release script does this internally too).
4. Run `./tools/build_mobile_release.sh android-aab` and confirm it produces `build/app/outputs/bundle/release/app-release.aab`.
5. If the release script's internal `flutter clean` re-resolves the SwiftPM `Package.resolved` files under `ios/**` and `macos/**`, revert those four files with `git checkout --` so they are **not** part of this commit.
6. Confirm `git status --short` shows only `android/settings.gradle` (or, if already committed, nothing at all).
7. Do not touch any other files.

# Verification Plan

This bug does not modify database objects, so the Tier 1 / Tier 2 SQL structure from `ARCHITECT.md` collapses into build-tooling checks. Tiers are preserved to match the required format.

**Tier 1 — Pre-deployment (must pass before running the release build):**

- `-- PRE-DEPLOY TEST 1:` confirm the only source change is the Kotlin pin
  `git diff --stat main..HEAD -- android/settings.gradle` shows `1 insertion(+), 1 deletion(-)`.
- `-- PRE-DEPLOY TEST 2:` confirm no unintended files are staged or modified
  `git status --short` returns empty, or shows only `android/settings.gradle`.
- `-- PRE-DEPLOY TEST 3:` confirm the new Kotlin pin is exactly `2.2.20`
  `grep 'org.jetbrains.kotlin.android' android/settings.gradle` returns `id "org.jetbrains.kotlin.android" version "2.2.20" apply false`.
- `-- PRE-DEPLOY TEST 4:` confirm AGP and Gradle wrapper are unchanged
  `grep 'com.android.application' android/settings.gradle` still shows `8.13.2`; `grep 'distributionUrl' android/gradle/wrapper/gradle-wrapper.properties` still shows `gradle-8.14`.
- `-- PRE-DEPLOY TEST 5:` confirm the SwiftPM lockfiles are not modified
  `git status --short ios macos` returns empty.

**Tier 2 — Post-deployment (run after the Android release build):**

- `-- POST-DEPLOY TEST 1:` confirm the AAB was produced
  `test -f build/app/outputs/bundle/release/app-release.aab && echo OK`.
- `-- POST-DEPLOY TEST 2:` confirm the AAB size matches expectation (~100 MB)
  `ls -l build/app/outputs/bundle/release/app-release.aab` — evidence captured on the verification run below.
- `-- POST-DEPLOY TEST 3:` confirm the release script's production-config verifier passed
  Script prints `✅ PASS: Production Supabase config found` and `✅ PASS: DEMO_PASSWORD found in artifact`.
- `-- POST-DEPLOY TEST 4:` confirm SwiftPM lockfiles are still clean after the build
  `git status --short ios macos` returns empty (revert if the internal `flutter clean` re-resolved them).
- `-- POST-DEPLOY TEST 5:` confirm the only warnings emitted are the expected Flutter forward-looking deprecations for Gradle/AGP/Kotlin support windows closing "soon" — no ERROR-level messages, no `bundleRelease` failure.

## Verification Result (evidence)

Reproduced after reverting the SwiftPM lockfiles a second time (the release script's internal `flutter clean` re-resolves them; they are reverted post-build to keep the commit Android-only):

- **AAB produced**: `build/app/outputs/bundle/release/app-release.aab`
- **Size**: `104,753,286 bytes` (100 MB / 104.8 MB)
- **Modified timestamp**: `Aug 30 20:52:35 2026`
- **Script output**:
  - `Running Gradle task 'bundleRelease'... 58.7s`
  - `✓ Built build/app/outputs/bundle/release/app-release.aab (104.8MB)`
  - `✅ PASS: Production Supabase config found (6 occurrences)`
  - `✅ PASS: DEMO_PASSWORD found in artifact (1 occurrences)`
- **Working tree after final revert**: `git status --short` empty. Only `android/settings.gradle` (already committed as `e13ecb4`) differs from `main`.

# QA Regression Areas

QA should specifically verify:

- Android release AAB installs and launches on a physical Android device.
- Auth flow (magic link) works on Android against production Supabase.
- Demo login path is intact (DEMO_PASSWORD embedded in AAB confirms this at build time).
- Push notifications on Android still register and receive (Firebase Messaging is unaffected by KGP version, but sanity-check anyway).
- iOS build and app behavior are unchanged (no SwiftPM `Package.resolved` changes were committed).
- macOS build and app behavior are unchanged.
- Web build (`./tools/build_web.sh`) still succeeds and deploys.
- No new Kotlin compilation warnings appear in `android/app/src/main/kotlin/**` beyond the Flutter-tool "support will be dropped" advisories.

# Rollout / Migration Strategy

No migration is required. Rollout is:

1. Merge the single-line commit to `main` via the standard PR flow.
2. Any subsequent release build (`./tools/build_mobile_release.sh android-aab`) picks up the new pin automatically.
3. No user-facing change, no version bump for this bug alone.
4. If the "soon" deprecation warnings for Gradle 8.14, AGP 8.13.2, or Kotlin 2.2.20 become hard errors in a future Flutter SDK, that will be tracked and fixed as a separate ticket (moving to Gradle ≥ 9.1.0, AGP ≥ 9.0.1, Kotlin ≥ 2.3.20 per Flutter's stated targets).

# Out of Scope

- Bumping AGP to 9.0.1 or Gradle to 9.1.0 to silence Flutter's forward-looking deprecation warnings.
- Bumping Kotlin further to 2.3.20.
- Consolidating `android/settings.gradle` and `android/settings.gradle.kts` (removing the unused `.kts` variant).
- Bumping Firebase iOS SDK from 12.15.0 to 12.18.0 (the SwiftPM re-resolution side effect from `flutter clean`).
- Any iOS, macOS, or Web build changes.
- Any Dart source, database, RLS, RPC, edge function, or notification changes.
- CI workflow changes.
- Adding new tests; this is a build-configuration pin, not runtime behavior, and existing analyzer + build verification are sufficient.
