# Architect Plan

## Feature Slug

`bug/android-16kb-page-size-support`

Docs path: `docs/features/android-16kb-page-size-support/ARCHITECT_PLAN.md`

---

## Problem Summary

Google Play Console flags the BandRoadie Android production release (version `1.4.0`, build `228`) with **"Your app could crash on 16 KB devices"** for two bundled native libraries:

- `base/lib/arm64-v8a/libdatastore_shared_counter.so`
- `base/lib/x86_64/libdatastore_shared_counter.so`

Both libraries were linked with a segment alignment that is not 16 KB-page-safe (the ELF `PT_LOAD` alignment must be `0x4000` for full compatibility with Android 15+ devices that use a 16 KB memory page size). This is a **regression**, not a project-side compilation defect: the app's own Dart/Kotlin code is not the source, and the project's Android NDK is already configured above the minimum recommended version.

Build 228 itself cannot be repaired in place — the fix must be demonstrated by a new build number uploaded to Google Play internal testing.

---

## Root Cause and Confidence

**Confidence: HIGH** — directly confirmed from repository dependency metadata, local pub cache inspection, and corroborated by public upstream issue reports.

`libdatastore_shared_counter.so` is a prebuilt native library shipped inside the **`androidx.datastore:datastore`** AAR. It is not compiled by BandRoadie and is not part of Flutter SDK tooling, Firebase, or any other plugin in the dependency graph.

Evidence chain:

1. `pubspec.lock` resolves `shared_preferences_android` (the Android platform implementation backing the direct `shared_preferences: ^2.2.2` dependency) to **version `2.4.20`**.
2. The cached package source for `shared_preferences_android-2.4.20` (`android/build.gradle`) declares:
   ```
   implementation("androidx.datastore:datastore:1.2.0")
   implementation("androidx.datastore:datastore-preferences:1.2.0")
   ```
3. `androidx.datastore:datastore:1.2.0` bundles a `libdatastore_shared_counter.so` that is **not** 16 KB-page aligned. This is a known upstream regression: `shared_preferences_android` moved from `androidx.datastore 1.1.7` (16 KB-safe) to `1.2.0` (not 16 KB-safe) between plugin versions `2.4.19` and `2.4.20`. Confirmed via Flutter issue tracker reports of the identical symptom (`libdatastore_shared_counter.so`, arm64-v8a + x86_64, `shared_preferences_android: 2.4.20` → `androidx.datastore:datastore: 1.2.0`).
4. A newer plugin release, **`shared_preferences_android 2.4.27`**, was fetched into the local pub cache for inspection (`dart pub cache add shared_preferences_android --version 2.4.27`, a read-only, additive cache fetch — no project file was modified). Its `android/build.gradle.kts` declares:
   ```
   implementation("androidx.datastore:datastore:1.1.7")
   implementation("androidx.datastore:datastore-preferences:1.1.7")
   ```
   confirming the upstream regression was reverted back to the 16 KB-safe `1.1.7` release.
5. `flutter pub outdated --json` reports `shared_preferences_android` as **resolvable to `2.4.27`** under the project's *existing* `pubspec.yaml` constraints (`shared_preferences: ^2.2.2`, which declares `shared_preferences_android: ^2.3.4`) — no `pubspec.yaml` edit is required, only a lockfile re-resolution.
6. A full scan of every package presently in the local pub cache shows `shared_preferences_android` is the **only** package anywhere in BandRoadie's dependency graph that references `androidx.datastore`. No other plugin (Firebase, `app_links`, etc.) is a candidate source.

### Why Google Play still flags it despite the app being generally 16 KB-compiled

The project's own compiled artifacts (Dart AOT snapshot glue, any first-party JNI code) are unaffected because Flutter's tooling already links against NDK **r28.2** (`ndkVersion = flutter.ndkVersion` → `28.2.13676358`, confirmed by inspecting the installed Flutter SDK's `FlutterExtension.kt`), which produces 16 KB-safe output by default. The flagged libraries are **prebuilt binaries shipped inside a third-party AAR** (`androidx.datastore:datastore:1.2.0`). BandRoadie's Gradle build does not recompile them — it packages them as-is. Changing `ndkVersion` locally cannot re-link a `.so` that was never compiled by this project in the first place. This exactly matches the caution in the feature input: *"Simply setting `ndkVersion` may not fix a precompiled third-party `.so`."*

---

## Native Library Ownership

| Property | Value |
|---|---|
| Library | `libdatastore_shared_counter.so` |
| Owning artifact | `androidx.datastore:datastore` (native component of AndroidX DataStore's multi-process shared-memory counter) |
| Delivered via | `shared_preferences_android` (Flutter platform implementation of `shared_preferences`) |
| Current resolved plugin version | `shared_preferences_android 2.4.20` |
| Current transitive `androidx.datastore` version | `1.2.0` (not 16 KB-safe — regression) |
| Fixed transitive `androidx.datastore` version | `1.1.7` (16 KB-safe), restored in `shared_preferences_android 2.4.27` |
| Built by BandRoadie? | **No** — precompiled and bundled inside the AAR |
| Other candidate sources ruled out | Firebase (`firebase_core`, `firebase_messaging`), all other plugins in the local pub cache — none reference `androidx.datastore` |

---

## Existing Android Build Analysis

| Setting | Current value | Source |
|---|---|---|
| Flutter | `3.44.6` (stable) | `flutter --version` |
| Dart | `3.12.2` | `flutter --version` |
| `ndkVersion` | `28.2.13676358` (NDK r28.2) | `android/app/build.gradle.kts` → `ndkVersion = flutter.ndkVersion`, resolved from installed Flutter SDK's `FlutterExtension.kt` default |
| Android Gradle Plugin (AGP) | `8.11.1` | `android/settings.gradle.kts` |
| Gradle wrapper | `8.14` (`-all` distribution) | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin | `2.2.20` | `android/settings.gradle.kts` |
| `compileSdk` / `targetSdk` / `minSdk` | `flutter.compileSdkVersion` / `flutter.targetSdkVersion` / `flutter.minSdkVersion` (Flutter-tooling-inherited, no explicit override in `android/app/build.gradle.kts`) | `android/app/build.gradle.kts` |
| `shared_preferences` (direct) | `2.5.4` (resolvable to `2.5.5`) | `pubspec.lock` / `flutter pub outdated` |
| `shared_preferences_android` (transitive) | `2.4.20` (resolvable to `2.4.27` under existing constraints) | `pubspec.lock` / `flutter pub outdated` |
| `firebase_core` / `firebase_messaging` | `direct main`, unrelated to the flagged library | `pubspec.yaml` |

The NDK version is already at or above Google's recommended r28 minimum. **No NDK, AGP, Gradle, or Kotlin upgrade is required or proposed** — the regression lives entirely in a third-party dependency's prebuilt binary.

---

## Proposed Solution

**Upgrade the transitive `shared_preferences_android` dependency from `2.4.20` to the latest version compatible with the existing `pubspec.yaml` constraint (`shared_preferences: ^2.2.2`), which pulls in `androidx.datastore 1.1.7` instead of the regressed `1.2.0`.**

This is a lockfile-only change:

1. Run `flutter pub upgrade` (no `pubspec.yaml` edit required — `shared_preferences_android 2.4.27` is already within range and was confirmed `resolvable` under current constraints via `flutter pub outdated --json`).
2. Confirm `pubspec.lock` now resolves `shared_preferences_android` to `2.4.27` (or newer, provided the Engineer confirms via the same build.gradle inspection method that the resolved version pins `androidx.datastore` to a 16 KB-safe release — do not assume based on version number alone; verify the actual `androidx.datastore` version declared in the resolved package's `android/build.gradle*`).
3. If `pubspec.lock` re-resolution does not naturally select a fixed version (e.g., a future `shared_preferences` major bump changes the transitive range), the Engineer must bump the direct `shared_preferences` constraint in `pubspec.yaml` to the minimum version that resolves to a 16 KB-safe `shared_preferences_android`, using the smallest version bump that achieves this.
4. Do not pin or override `androidx.datastore` directly via Gradle dependency substitution/resolution strategy — that would fight the plugin's own declared dependency and risks binary incompatibility with the rest of `shared_preferences_android`'s internals. Fixing it at the Dart package level (upgrading `shared_preferences_android` itself) is the smallest, most maintainable change.

This is the smallest supported fix: it changes only the resolved version of a dependency BandRoadie already declares, requires no `pubspec.yaml` edit under current evidence, no Android build-tool changes, and no application code changes.

---

## Alternatives Considered

| Alternative | Verdict | Reason |
|---|---|---|
| Upgrade/change `ndkVersion` | **Rejected** | Already at r28.2; would not affect a prebuilt third-party `.so` regardless |
| Upgrade AGP / Gradle / Kotlin | **Rejected** | Not required by the fix; the regression is a Dart-package-level transitive dependency issue, not a build-tool version issue |
| Recompile `libdatastore_shared_counter.so` from AndroidX source with flexible page-size linker flags | **Rejected** | A supported upstream fix already exists (`shared_preferences_android 2.4.27` restores `androidx.datastore 1.1.7`); recompiling a Google-owned library locally is unsupported, high-maintenance, and violates "prefer the smallest change" |
| Force/override `androidx.datastore` version via Gradle `resolutionStrategy` while staying on `shared_preferences_android 2.4.20` | **Rejected** | Fights the plugin's declared dependency graph; could produce a `datastore`/`datastore-preferences` version mismatch or ABI incompatibility inside the plugin's compiled Kotlin, which is exactly the kind of fragile pin the Architect should avoid when an upstream package upgrade is available |
| Remove `shared_preferences` entirely | **Rejected** | Out of scope; large blast radius across the app for an unrelated bug fix; not the smallest change |
| Exclude the transitive `androidx.datastore` module | **Rejected** | Would break `shared_preferences_android`'s runtime functionality (DataStore is its storage backend) |

---

## Build-System Impact

| Area | Impact |
|---|---|
| Flutter SDK requirement | Unaffected — no minimum Flutter version change required |
| Dart SDK requirement | Unaffected |
| `pubspec.yaml` | Unaffected under current evidence (see Proposed Solution step 3 for the conditional fallback) |
| `pubspec.lock` | **Affected** — `shared_preferences_android` (and possibly `shared_preferences`, `shared_preferences_platform_interface`) version bump only |
| Android Gradle Plugin | Unaffected |
| Gradle wrapper | Unaffected |
| Kotlin | Unaffected |
| Android NDK | Unaffected — already r28.2, no change needed |
| `compileSdk` / `targetSdk` / `minSdk` | Unaffected |
| Firebase configuration | Unaffected — unrelated dependency |
| iOS build | Unaffected — `shared_preferences_foundation` (iOS/macOS platform implementation) does not use AndroidX DataStore |
| macOS build | Unaffected — same reason |
| Web build | Unaffected — `shared_preferences_web` does not use AndroidX DataStore |
| CI / local build commands | Unaffected — same `flutter build` invocations, no new flags |
| Google Play App Bundle output | **Affected (intended)** — the two flagged `.so` files should be replaced with 16 KB-aligned versions in the next build |

---

## Flutter and Dependency Impact

- No direct `pubspec.yaml` dependency version bump anticipated (see conditional fallback above).
- `pubspec.lock` changes are expected to be limited to the `shared_preferences*` package family.
- No new dependency is introduced.
- No dependency is removed.
- Migration policy: **N/A** — no Supabase/database migration involved.
- New dependency policy: **No new dependencies permitted** for this fix.
- Lockfile policy: `pubspec.lock` update is the primary artifact of this fix; Engineer must run `flutter pub get`/`flutter pub upgrade` and commit the resulting lockfile diff, not hand-edit it.
- Flutter SDK upgrade policy: **Not permitted** for this fix — out of scope.
- Android NDK upgrade policy: **Not permitted/not needed** — already r28.2.

---

## Files to Create

| File | Purpose |
|---|---|
| `docs/reference/general/AI_DECISIONS.md` (new entry appended, not a new file) | Not required — this fix does not touch initialization order, config loading, auth flow, RLS, or introduce new architecture. No `AI_DECISIONS.md` entry is needed. |

No new files are required for this fix.

---

## Files to Modify

| File | What changes |
|---|---|
| `pubspec.lock` | Re-resolved via `flutter pub get` / `flutter pub upgrade` so `shared_preferences_android` (and its siblings, if the solver bumps them) resolves to a version whose `android/build.gradle*` declares a 16 KB-safe `androidx.datastore` version (confirmed `2.4.27` pins `1.1.7`; Engineer must re-verify against whatever version is newest at implementation time) |
| `pubspec.yaml` | **Conditional only** — modify only if step 3 of the Proposed Solution is triggered (i.e., the current constraint does not naturally resolve to a fixed version). If triggered, bump the `shared_preferences: ^2.2.2` constraint to the smallest version that resolves the fix. |
| Android build number (`android/app/build.gradle.kts` → inherited from `pubspec.yaml` `version:` field, currently `1.4.0+228`) | `pubspec.yaml`'s `version:` line increments the build number (e.g., `1.4.0+229`) — required before the Google Play internal testing upload described in the Verification Plan. This is the only touch to `pubspec.yaml` guaranteed by this plan regardless of whether step 3 triggers. |

---

## Files Off-Limits

| File | Reason |
|---|---|
| `lib/main.dart` | Runtime initialization order is unrelated and must not change |
| Any file under `supabase/migrations/` | Database is unrelated to a native-library page-alignment bug |
| `ios/**`, `macos/**` | Android-only warning; iOS/macOS use different platform implementations of `shared_preferences` that do not reference AndroidX DataStore, so no cross-platform lockfile change is required beyond the shared `pubspec.lock` entries for the plugin's Dart-level package (which is harmless/no-op on those platforms) |
| `web/**` | Android-only warning; `shared_preferences_web` is unaffected |
| `android/app/build.gradle.kts` (`ndkVersion`, `compileSdk`, `targetSdk`, `minSdk`) | Root cause is a precompiled third-party `.so`, not project NDK/SDK configuration; changing these would not fix the issue and is explicitly out of scope |
| `android/build.gradle.kts`, `android/settings.gradle.kts` (AGP/Kotlin/Gradle versions) | Not implicated by the root cause |
| Any file under `lib/features/**` (application/business logic) | This is a dependency-version fix only; no Dart application code changes are needed or permitted |
| `android/app/google-services.json`, Firebase configuration | Unrelated — Firebase does not supply the flagged library |

---

## System Impact Map

| System | Impact |
|---|---|
| Android build | affected |
| iOS build | unaffected |
| Web build | unaffected |
| macOS build | unaffected |
| Authentication | unaffected |
| Push notifications | unaffected |
| Supabase | unaffected |
| Runtime initialization | unaffected |
| Google Play release | affected (new build required to demonstrate the fix; build 228 remains flagged and is not repaired in place) |

---

## Regression Risk

**Overall: LOW**

Considerations:

- The change is a transitive dependency version bump within an already-declared, already-tested `^` range (or, in the fallback case, a minimal direct version bump of `shared_preferences` itself) — not a new library, not a new architecture.
- `shared_preferences` is used across the app for local key-value storage; a platform-implementation version bump carries a small chance of subtle behavioral differences in the underlying Android storage backend (SharedPreferences vs. DataStore-backed implementation details), but this is entirely within the plugin's own responsibility and covered by the plugin's own test suite upstream.
- No Firebase compatibility risk (unrelated dependency).
- No Android build tooling changes (AGP/Gradle/Kotlin/NDK untouched), so no risk of build-tool-driven regressions elsewhere.
- No native notification behavior change.
- No release signing change.
- No other platform (iOS/macOS/web) shares the affected native dependency, so cross-platform blast radius is nil.
- Primary residual risk: if the Engineer's resolved version does not actually revert to a 16 KB-safe `androidx.datastore`, the fix will appear complete locally (`flutter build appbundle` succeeds) but Google Play will still flag the new build. This is why the Verification Plan mandates inspecting the actual native library alignment, not just a successful build.

---

## Engineer Task Breakdown

1. **Pre-change verification** (see Verification Plan) — record baseline versions and confirm current build succeeds.
2. Run `flutter pub upgrade` (do not hand-edit `pubspec.lock`).
3. Inspect the resolved `shared_preferences_android` version in `pubspec.lock`.
4. Locate the resolved package in the local pub cache (or fetch via `dart pub cache add shared_preferences_android --version <resolved-version>` if not already cached) and confirm its `android/build.gradle*` declares `androidx.datastore:datastore` at a version other than the known-bad `1.2.0`.
   - If it still resolves to `1.2.0` or the solver did not move the version at all, proceed to the conditional `pubspec.yaml` bump (Proposed Solution step 3), using the smallest `shared_preferences` version that resolves to a fixed `shared_preferences_android`.
5. Increment the build number in `pubspec.yaml` (`version: 1.4.0+228` → `1.4.0+229`).
6. Run the full local Post-Change Verification sequence (below).
7. Inspect the generated `.aab`'s native libraries for both flagged ABIs (`arm64-v8a`, `x86_64`) and confirm `libdatastore_shared_counter.so` alignment.
8. Write `ENGINEER_REPORT.md` documenting: resolved dependency versions before/after, the exact `androidx.datastore` version now in play, alignment verification output, and confirmation that no other files were touched.
9. Stop and escalate to the Architect/Manager if the resolved dependency chain does not produce a 16 KB-safe `androidx.datastore` version under the existing `pubspec.yaml` constraint range — do not attempt a Gradle-level dependency override as a workaround without new Architect approval.

---

## Verification Plan

### Pre-change verification

1. Record current Flutter/Dart versions: `flutter --version` (baseline: Flutter `3.44.6`, Dart `3.12.2`).
2. Record current AGP/Gradle/Kotlin/NDK versions (baseline: AGP `8.11.1`, Gradle `8.14`, Kotlin `2.2.20`, NDK `28.2.13676358` — see `android/settings.gradle.kts`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/app/build.gradle.kts`).
3. Confirm the dependency that owns `libdatastore_shared_counter.so`: `shared_preferences_android` → `androidx.datastore:datastore`. Re-run the pub-cache inspection method used in this plan:
   ```bash
   grep -A8 "^  shared_preferences_android:" pubspec.lock
   grep -n "datastore" "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -iname 'shared_preferences_android-*' | sort -V | tail -1)"/android/build.gradle*
   ```
4. Confirm both flagged ABIs are present in the current build output: `arm64-v8a`, `x86_64`.
5. Record the current dependency tree: `flutter pub deps --style=list > /tmp/deps_before.txt`.
6. Confirm the current app builds before modification: `flutter clean && flutter pub get && flutter build appbundle --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY` (use the Engineer's local `--dart-define` values per `docs/reference/general/RUNTIME_CONFIG.md`; never hardcode or print the actual secret values in `ENGINEER_REPORT.md`).

### Post-change local verification

Run in order:

```bash
flutter clean
flutter pub get
flutter analyze
flutter build appbundle --release --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

A successful `flutter build appbundle` **does not prove the Play warning is resolved** — it only proves the app compiles and packages. The `.so` alignment must be independently verified:

1. Extract the release `.aab` produced above (`build/app/outputs/bundle/release/app-release.aab`).
2. Generate a device-agnostic universal APK set for inspection using the locally installed `bundletool` (`/opt/homebrew/bin/bundletool`):
   ```bash
   bundletool build-apks \
     --bundle=build/app/outputs/bundle/release/app-release.aab \
     --output=/tmp/bandroadie.apks \
     --mode=universal
   unzip -o /tmp/bandroadie.apks -d /tmp/bandroadie_apks
   ```
3. Locate both flagged libraries inside the extracted universal APK (`lib/arm64-v8a/libdatastore_shared_counter.so`, `lib/x86_64/libdatastore_shared_counter.so`) and inspect their ELF program headers with the NDK's `llvm-readelf` (installed at `~/Library/Android/sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-readelf`):
   ```bash
   llvm-readelf -l /tmp/bandroadie_apks/splits/*/lib/arm64-v8a/libdatastore_shared_counter.so | grep -A1 LOAD
   llvm-readelf -l /tmp/bandroadie_apks/splits/*/lib/x86_64/libdatastore_shared_counter.so | grep -A1 LOAD
   ```
   Confirm every `LOAD` segment's alignment is `0x4000` (16 KB) rather than `0x1000` (4 KB).
4. Alternatively/additionally, use `apkanalyzer` (installed at `~/Library/Android/sdk/cmdline-tools/latest/bin/apkanalyzer`) to inspect the native library listing, or use Android Studio's APK Analyzer UI for a visual 16 KB-alignment indicator, whichever is more convenient for the Engineer at implementation time.
5. Record the exact resolved `androidx.datastore` version alongside the alignment output in `ENGINEER_REPORT.md`.

### Google Play verification

1. Increment the Android build number (`pubspec.yaml` `version:` field, e.g. `1.4.0+229`) — already covered as an Engineer task above.
2. Build and sign a new `.aab` using the existing release signing config (`android/app/build.gradle.kts` `signingConfigs.release`, sourced from `key.properties` — do not modify).
3. Upload the new `.aab` to Google Play's **internal testing** track first. Do not upload to production directly.
4. Wait for Google Play's automated artifact/pre-launch analysis to complete.
5. Confirm the "Your app could crash on 16 KB devices" warning is **absent** for the new build's artifact analysis.
6. Only after confirmation should the build be promoted or a production release created — this step is a Tony/Manager decision, not an Engineer action.

**Do not** attempt to alter, suppress, or dismiss the existing warning on the current production release (version `1.4.0`, build `228`). That build remains flagged permanently; the fix is demonstrated exclusively by the next uploaded build passing artifact analysis.

---

## QA Regression Areas

- Local key-value storage read/write correctness on Android (anything backed by `shared_preferences`: e.g., cached UI preferences, onboarding/first-run flags, any locally persisted non-Supabase state). Confirm existing values are not lost or reset after the dependency upgrade (`shared_preferences_android`'s DataStore-backed implementation maintains its own migration-from-legacy-SharedPreferences path; QA should verify a device/emulator with pre-existing app data upgrades cleanly).
- `flutter analyze` must remain at 0 errors.
- Full regression pass on Android only — iOS, macOS, and Web builds are not expected to change and do not need re-verification beyond a smoke build if convenient.
- Confirm no unrelated `pubspec.lock` entries changed beyond the `shared_preferences*` family (and, if triggered, `pubspec.yaml`'s `shared_preferences` constraint plus the build-number bump).
- Confirm the release `.aab` still installs and launches correctly on an Android emulator/device (smoke test: app launches, auth flow works, dashboard loads) — this is a dependency swap in a widely-used plugin, so a basic smoke test is warranted even though risk is rated LOW.

---

## Rollout Strategy

1. Engineer implements the lockfile (and conditional `pubspec.yaml`) change plus build-number bump on a branch per `docs/agents/GUARDRAILS.md` §10 Git Discipline.
2. QA validates per the Verification Plan and QA Regression Areas above.
3. Upon QA `APPROVED`, Manager authorizes commit and push per the standard pipeline gate.
4. PR merged to `main` following existing Git Discipline (branch → commit → push → PR → merge → confirm `main` → delete branch).
5. Tony builds and uploads the new signed `.aab` to Google Play **internal testing** (this is a Tony-owned release action, not something an agent performs).
6. Once Google Play's artifact analysis confirms the 16 KB warning is absent, Tony promotes to production at their discretion.

---

## Out of Scope

- Edge-to-edge display warning (separate Google Play recommendation, unrelated to this bug).
- Large-screen orientation/resizability warning (separate Google Play recommendation, unrelated to this bug).
- R8/ProGuard optimization recommendation (separate Google Play recommendation; note the current `release` build type has `isMinifyEnabled = false` and `isShrinkResources = false` — not touched by this plan).
- Any Supabase, database, RLS, authentication, routing, or runtime initialization change.
- Any Flutter SDK, Dart SDK, AGP, Gradle, Kotlin, or NDK version change — none are implicated by the confirmed root cause.
- Repairing or repackaging the existing flagged production build (version `1.4.0`, build `228`) — not possible; superseded by a new build only.
- Any other transitive dependency not shown to reference `androidx.datastore` in this investigation.
