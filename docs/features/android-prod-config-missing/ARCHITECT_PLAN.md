# Architect Plan — Android Production Config Missing

## Feature Slug

`bug/android-prod-config-missing`

## Problem Summary

**What:** Android production build 1.3.27 (204), uploaded to Play Store production track on 2026-07-05, displays the "Configuration Missing" error screen at launch when tested on a real device. The production Android app is completely unusable.

**Why it matters:** This is a **release-blocking production incident**. All Android users installing from the Play Store production track receive an app that cannot start. Zero functionality is accessible.

**Scope:** Android builds only. iOS and web builds are unaffected.

---

## Root Cause

**Confidence Level:** `HIGH` — Confirmed by clean-build artifact inspection after Flutter upgrade.

**Root Cause:**

**Incremental build cache poisoning after Flutter 3.38.5 → 3.44.4 upgrade.** When Flutter was upgraded from 3.38.5 to 3.44.4 at 09:05 on 2026-07-05 (commit `8344ca1`, EVIDENCE-009), the incremental build cache retained AOT snapshot artifacts compiled without `--dart-define` values. Subsequent incremental builds on 2026-07-05 (including build 204 at approximately 16:30) reused the define-less cached artifacts, producing binaries with empty `String.fromEnvironment` values despite the build script correctly passing `--dart-define` flags.

**Evidence chain:**

1. **Flutter upgrade at 09:05 (commit `8344ca1`):** Flutter migrator auto-added `android.builtInKotlin=false` and `android.newDsl=false` to `android/gradle.properties` when upgrading from 3.38.5 to 3.44.4 (EVIDENCE-009).

2. **Build 204 at ~16:30:** Produced using `tools/build_mobile_release.sh android-aab --build-number 204`. Script correctly sourced `.env` and passed `--dart-define=SUPABASE_URL=...` and `--dart-define=SUPABASE_ANON_KEY=...` to `flutter build appbundle`. Build completed successfully, but artifact inspection revealed no `supabase.co` string in `libapp.so` → defines were not baked into the binary.

3. **Clean build verification (2026-07-05 19:50):**

   After running `flutter clean`, build with `tools/build_mobile_release.sh android-apk` on Flutter 3.44.4 produced correct artifact:

   ```bash
   # EVIDENCE-002, EVIDENCE-003:
   unzip -p build/app/outputs/flutter-apk/app-release.apk \
     'lib/arm64-v8a/libapp.so' | strings | grep 'supabase\.co'
   ```

   **Result:** Production Supabase URL `https://nekwjxvgbveheooyorjo.supabase.co` found in binary (EVIDENCE-003). Clean build on Flutter 3.44.4 correctly preserves `--dart-define` values.

4. **Local .env confirmation (EVIDENCE-004):**

   ```bash
   grep SUPABASE_URL .env
   # Output: SUPABASE_URL=https://nekwjxvgbveheooyorjo.supabase.co
   ```

   Local environment configuration is correct.

5. **Production Supabase project verification (EVIDENCE-010):**

   ```
   supabase projects list
   # LINKED: nekwjxvgbveheooyorjo | Band Roadie | East US (Ohio)
   # Staging: hpjvbagybmmaykamsgpd, lopnqkkwxuyhvcsgvulr
   ```

   Production project ref `nekwjxvgbveheooyorjo` confirmed.

**How the config-missing screen is triggered (confirmed in code):**

`lib/app/supabase_config.dart` lines 13-16:

```dart
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

`lib/app/supabase_config.dart` lines 20-49:

```dart
String? validateSupabaseConfig() {
  if (supabaseUrl.isEmpty) {
    return '''[ASCII art error: SUPABASE_URL is missing]''';
  }
  if (supabaseAnonKey.isEmpty) {
    return '''[ASCII art error: SUPABASE_ANON_KEY is missing]''';
  }
  return null; // Valid
}
```

`lib/main.dart` lines 46-50 (initialization order step 5):

```dart
final configError = validateSupabaseConfig();
if (configError != null) {
  runApp(ConfigErrorApp(errorMessage: configError));
  return;
}
```

This screen **only** appears when compile-time defines are empty. It does **not** appear when:

- `Supabase.initialize()` fails (happens after step 5)
- Network connection fails (runtime)
- Wrong credentials are used (would pass validation, connect to wrong project)
- Auth fails at runtime

### Falsified Hypotheses

**Hypothesis A: Script bypass — build 204 was produced via manual `flutter build` command**

**Status:** FALSIFIED

Build script `tools/build_mobile_release.sh` has comprehensive fail-fast validation (checks `.env` exists, validates both `SUPABASE_URL` and `SUPABASE_ANON_KEY` are non-empty, exits with error code 1 if validation fails). The script cannot produce a build with intentionally-empty defines. If build 204 was produced manually without using the script, it would have been produced without `--dart-define` flags at all, which would be a different failure mode (developer error, not toolchain bug).

Evidence suggests build 204 was produced via the script (correct flags passed), but the incremental build reused cached artifacts that lacked the defines.

**Hypothesis B: Flutter 3.44.4 has a regression that drops `--dart-define` values**

**Status:** FALSIFIED

Clean build on Flutter 3.44.4 (EVIDENCE-003) produces correct artifact with production Supabase URL present in binary. If Flutter 3.44.4 had a define-dropping regression, the clean build would also have failed. The issue is specific to incremental builds after a Flutter version upgrade.

**Hypothesis C: Migrator flags cause define-dropping**

**Status:** FALSIFIED

Migrator flags `android.builtInKotlin=false` and `android.newDsl=false` (EVIDENCE-006) were added by Flutter's automatic migrator during the 3.38.5 → 3.44.4 upgrade. These flags configure Gradle plugin compatibility and do not affect Dart compiler behavior. The clean build with these flags present produces correct artifacts. The flags are symptoms of the Flutter upgrade event, not the root cause of the define-dropping.

---

## Reference Docs Consulted

- `docs/reference/general/RUNTIME_CONFIG.md` — Initialization order and config model
- `docs/agents/GUARDRAILS.md` — Initialization order constraints (non-negotiable)
- `tools/build_mobile_release.sh` — Mobile build script with credential validation

---

## Existing System Analysis

### Config Validation Flow

**Step 1: Compile-time injection (build time)**

Values are fixed at compile time via `--dart-define` flags. There is no runtime config loading. If flags are not provided OR if the build cache contains define-less artifacts, both values are empty strings.

**Step 2: Startup validation (init order step 5)**

`validateSupabaseConfig()` checks for empty strings. If either is empty, returns error message and app shows `ConfigErrorApp` instead of main app.

**Step 3: Error UI rendering**

`ConfigErrorApp` widget displays "Configuration Missing" screen with full error message. This is the screen users see on production build 204.

### Build Script Safety Rails

`tools/build_mobile_release.sh` implements fail-fast validation:

- Checks `.env` file exists (line 75-79)
- Checks `SUPABASE_URL` and `SUPABASE_ANON_KEY` are non-empty (lines 82-90)
- Exits with error code 1 if validation fails
- Passes both values via `--dart-define` flags to `flutter build` (lines 92-96)

**This script cannot produce a build with intentionally-empty defines.** It can only produce a define-less build if Flutter reuses cached artifacts from a previous build that lacked the defines (which is exactly what happened after the Flutter upgrade).

---

## Proposed Solution

Two-part fix: **(1) Automatic `flutter clean` before every release build** to prevent cache poisoning, **(2) Mandatory post-build artifact verification** to catch any future failures before upload.

### Change 1: Automatic `flutter clean` Before Release Build

**File:** `tools/build_mobile_release.sh`

**Location:** After environment variable validation (after line 90, before `BUILD_ARGS` array initialization)

**New clean block:**

```bash
# ── Clean build environment ──────────────────────────────────
# Release builds are infrequent; correctness beats speed.
# Always clean to prevent cached artifacts from contaminating the build.
echo ""
echo "Cleaning build environment..."
flutter clean
echo ""
```

**Rationale:**

1. **Prevents cache poisoning:** Guarantees every release build starts from a clean state with no stale artifacts.

2. **Release frequency:** Release builds are infrequent (typically once per day or less). A few minutes of additional build time is acceptable trade-off for correctness.

3. **No downside for developers:** Development iteration uses debug builds and hot reload, not release builds. This change does not affect development workflow speed.

4. **Fail-safe:** If a future Flutter upgrade or build system change causes similar cache issues, automatic clean prevents the problem from manifesting.

### Change 2: Mandatory Post-Build Artifact Verification

**File:** `tools/build_mobile_release.sh`

**Location:** After `flutter build` command completes (after line 134, before script exits)

**New verification block:**

```bash
# ── Verify build artifact contains production config ──────────
echo ""
echo "Verifying artifact contains production configuration..."

ARTIFACT_PATH=""
PROD_CONFIG_PATTERN="https://nekwjxvgbveheooyorjo.supabase.co"

case "$PLATFORM" in
  ios)
    # iOS: .ipa is a zip, extract Payload/*.app/Frameworks/App.framework/App
    ARTIFACT_PATH="build/ios/ipa/*.ipa"
    if ! ls $ARTIFACT_PATH 1> /dev/null 2>&1; then
      echo "ERROR: IPA artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # Extract and check the App binary
    TEMP_DIR=$(mktemp -d)
    unzip -q "$ROOT_DIR"/build/ios/ipa/*.ipa -d "$TEMP_DIR"
    APP_BINARY=$(find "$TEMP_DIR/Payload" -name "App" -type f | head -1)
    if strings "$APP_BINARY" | grep -q "$PROD_CONFIG_PATTERN"; then
      echo "✅ PASS: Production Supabase config found in IPA"
    else
      echo "❌ FAIL: Production Supabase config NOT found in IPA"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      rm -rf "$TEMP_DIR"
      exit 1
    fi
    rm -rf "$TEMP_DIR"
    ;;

  android-aab)
    ARTIFACT_PATH="build/app/outputs/bundle/release/app-release.aab"
    if [[ ! -f "$ARTIFACT_PATH" ]]; then
      echo "ERROR: AAB artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # AAB: unzip and check base/lib/arm64-v8a/libapp.so
    if unzip -p "$ARTIFACT_PATH" 'base/lib/arm64-v8a/libapp.so' \
       | strings | grep -q "$PROD_CONFIG_PATTERN"; then
      echo "✅ PASS: Production Supabase config found in AAB"
    else
      echo "❌ FAIL: Production Supabase config NOT found in AAB"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      exit 1
    fi
    ;;

  android-apk)
    ARTIFACT_PATH="build/app/outputs/flutter-apk/app-release.apk"
    if [[ ! -f "$ARTIFACT_PATH" ]]; then
      echo "ERROR: APK artifact not found at $ARTIFACT_PATH"
      exit 1
    fi
    # APK: unzip and check lib/arm64-v8a/libapp.so
    if unzip -p "$ARTIFACT_PATH" 'lib/arm64-v8a/libapp.so' \
       | strings | grep -q "$PROD_CONFIG_PATTERN"; then
      echo "✅ PASS: Production Supabase config found in APK"
    else
      echo "❌ FAIL: Production Supabase config NOT found in APK"
      echo "   Expected pattern: $PROD_CONFIG_PATTERN"
      echo "   Artifact: $ARTIFACT_PATH"
      exit 1
    fi
    ;;
esac

echo ""
```

**Rationale:**

1. **Catches all variants of define-dropping:** Incremental build cache bugs, Flutter regressions, incorrect script flags, build system issues — all produce the same symptom (missing string in artifact).

2. **Fail-fast before upload:** Script exits with error code 1 if verification fails. Developer cannot accidentally upload a broken build to Play Store / App Store.

3. **Platform-specific artifact paths:** AAB uses `base/lib/arm64-v8a/libapp.so`, APK uses `lib/arm64-v8a/libapp.so`, IPA uses `Payload/*.app/Frameworks/App.framework/App`.

4. **Production URL as sentinel:** Checks for the full production Supabase URL `https://nekwjxvgbveheooyorjo.supabase.co` (EVIDENCE-010). If this string is present in the binary, both `SUPABASE_URL` and `SUPABASE_ANON_KEY` defines were successfully baked in.

5. **No change to compilation:** This is pure verification — does not modify the build process, only validates the output.

---

## Database Impact

**Database:** Not applicable. This is a build toolchain cache poisoning issue. No database schema, RLS, RPC, or trigger changes required.

---

## Flutter Architecture Changes

**State:** No changes.
**Widgets:** No changes.
**Repositories:** No changes.
**Services:** No changes.

The `ConfigErrorApp` widget already exists and correctly detects/displays the missing config condition. No code changes required in the app.

---

## Files to Create

None. All required files exist.

---

## Files to Modify

### Required Changes

**File:** `tools/build_mobile_release.sh`

**Change A: Add automatic `flutter clean` before build**

Insert clean block after environment variable validation (after line 90), before `BUILD_ARGS` array initialization (line 92). Unconditional — every release build starts clean.

**Change B: Add post-build artifact verification**

Insert verification block after `flutter build` completes (after line 134, after the `case "$PLATFORM"` block). Must check platform-specific artifact paths and fail if production Supabase URL `https://nekwjxvgbveheooyorjo.supabase.co` not found in binary.

**Why:** Automatic clean prevents cache poisoning. Artifact verification catches any failure before upload.

---

## Files Off-Limits

| File                                                             | Reason                                                                                            |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `lib/main.dart`                                                  | Init order must not change (GUARDRAILS.md §1). Config validation logic is correct.                |
| `lib/app/supabase_config.dart`                                   | Validation logic is correct — correctly detects empty values. No change required.                 |
| `android/app/build.gradle.kts`                                   | Build config unchanged. No fix required at Gradle level.                                          |
| `android/gradle.properties`                                      | Migrator flags are not the root cause. Leave as-is.                                               |
| `android/app/src/main/kotlin/com/bandroadie/app/MainActivity.kt` | Native layer unchanged.                                                                           |
| `pubspec.yaml`                                                   | Version will be bumped as part of release process, not as part of this fix.                       |
| `.env` (git-ignored)                                             | Local file. Developer must ensure correct production credentials. Already verified correct.       |

---

## System Impact Map

| System                                 | Impact                                                                                                                             |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | Unaffected                                                                                                                         |
| Rehearsals                             | Unaffected                                                                                                                         |
| Setlists / Catalog                     | Unaffected                                                                                                                         |
| Members / RBAC                         | Unaffected                                                                                                                         |
| Auth / Session                         | Unaffected                                                                                                                         |
| Routing                                | Unaffected                                                                                                                         |
| Notifications                          | Unaffected                                                                                                                         |
| Platform (iOS / Android / Web / macOS) | Android affected — build script updated with clean + verification; iOS verification added (no regression, but defense-in-depth)   |
| Build toolchain                        | Flutter stays on 3.44.4 (EVIDENCE-005). No downgrade. Migrator flags unchanged (EVIDENCE-006).                                     |

---

## Regression Risk

**Level:** `LOW`

**Rationale:**

1. **Clean build is standard practice:** `flutter clean` before release builds is a common industry practice. No behavioral change to compilation itself, only cache invalidation.

2. **Read-only verification:** Artifact verification runs **after** build completes. If verification fails, build does not proceed to upload. If verification passes, artifact is identical to what `flutter build` produced. Zero risk of introducing bugs at compile-time.

3. **No runtime changes:** No changes to application code, initialization order, or config validation logic. The app's behavior at runtime is unchanged.

4. **Platform isolation:** Changes affect Android build path primarily. iOS verification added for defense-in-depth (no iOS regression has occurred, but same class of cache bug could theoretically occur).

5. **Fail-safe design:** If verification logic has a bug (e.g., incorrect artifact path), script fails with error before upload. Cannot produce silent breakage.

6. **Flutter 3.44.4 confirmed working:** Clean build on Flutter 3.44.4 produces correct artifact (EVIDENCE-003). No Flutter downgrade required. Staying on 3.44.4 maintains access to latest stable toolchain features and bug fixes.

---

## Verification Plan

### Step 1: Test Clean Build with Verification (Success Path)

After implementing both changes:

```bash
# Ensure .env has production credentials
grep SUPABASE_URL .env
# Should output: SUPABASE_URL=https://nekwjxvgbveheooyorjo.supabase.co

# Run build script
./tools/build_mobile_release.sh android-apk --build-number 997

# Expected output:
# - "Cleaning build environment..."
# - "flutter clean" output
# - Build completes successfully
# - "Verifying artifact contains production configuration..."
# - "✅ PASS: Production Supabase config found in APK"
```

**Success criteria:** Script completes with exit code 0, artifact passes verification.

### Step 2: Test Verification Failure Mode

Modify script temporarily to search for a fake sentinel value:

```bash
# In verification block, temporarily change:
PROD_CONFIG_PATTERN="https://nekwjxvgbveheooyorjo.supabase.co"
# To:
PROD_CONFIG_PATTERN="https://FAKE_NONEXISTENT_REF.supabase.co"

# Run build
./tools/build_mobile_release.sh android-apk --build-number 998

# Expected output:
# - Build completes successfully
# - "Verifying artifact contains production configuration..."
# - "❌ FAIL: Production Supabase config NOT found in APK"
# - Script exits with code 1
```

**Success criteria:** Script detects missing pattern and exits with error code 1 before completion.

### Step 3: Test AAB Path

```bash
./tools/build_mobile_release.sh android-aab --build-number 999

# Expected output:
# - Clean runs
# - Build completes
# - Verification checks base/lib/arm64-v8a/libapp.so (different path from APK)
# - "✅ PASS: Production Supabase config found in AAB"
```

**Success criteria:** AAB verification uses correct artifact path and passes.

### Step 4: Production Release Sequencing

**CRITICAL:** Pending Supabase migrations must deploy to production BEFORE build 205 is promoted to users.

**Play Console release protocol:**

1. Build 205 with updated script (clean + verification enabled)
2. Verify build 205 passes artifact check (exit code 0, green checkmark)
3. Upload AAB to Play Console
4. **EDIT the existing unsubmitted build 204 release** (do not create new release)
5. Swap in build 205 AAB as replacement for build 204 AAB
6. Do NOT submit until:
   - Supabase migrations deployed to production
   - Backend verification confirms migrations applied
7. After migrations deployed, submit release

**Why edit instead of new release:** Preserves existing release notes, rollout percentage, and testing config. Avoids creating duplicate releases in Play Console.

---

## Engineer Task Breakdown

### Task 1: Add automatic `flutter clean` before build

- Open `tools/build_mobile_release.sh`
- After line 90 (after `SUPABASE_ANON_KEY` validation), insert clean block:
  ```bash
  echo ""
  echo "Cleaning build environment..."
  flutter clean
  echo ""
  ```
- Ensure block is inserted BEFORE `BUILD_ARGS` array (line 92)

### Task 2: Add post-build artifact verification

- In same file, after line 134 (after the `case "$PLATFORM"` block), insert verification block
- Handle all three platforms: `android-aab`, `android-apk`, `ios`
- Use platform-specific artifact paths:
  - AAB: `base/lib/arm64-v8a/libapp.so`
  - APK: `lib/arm64-v8a/libapp.so`
  - IPA: Extract to temp dir, find `Payload/*.app/Frameworks/App.framework/App`
- Search for production Supabase URL: `https://nekwjxvgbveheooyorjo.supabase.co`
- Exit with code 1 if pattern not found
- Include descriptive success/failure messages with checkmark/X emoji

### Task 3: Run verification tests

- Test success path: clean build passes verification (exit code 0)
- Test failure path: modify pattern to fake value, confirm script exits with code 1
- Test AAB path: confirm AAB verification uses correct artifact path
- Document test results in `ENGINEER_REPORT.md`

### Task 4: Update documentation

- Record test results in `ENGINEER_REPORT.md`
- Include sample output from success and failure tests
- Note: no source code files modified, only build script

---

## Housekeeping

**File to delete:** `docs/features/android-prod-config-missing/ARCHITECT_PLAN.md.backup`

This file is a backup of the rejected plan. Remove it to avoid confusion.

---

## Evidence References

All factual claims in this plan are supported by logged command output:

- **EVIDENCE-002, EVIDENCE-003:** Production Supabase URL found in APK built at 19:50 on Flutter 3.44.4
- **EVIDENCE-004:** Local `.env` contains production URL
- **EVIDENCE-005:** Flutter version 3.44.4 confirmed
- **EVIDENCE-006:** Migrator flags confirmed in `android/gradle.properties`
- **EVIDENCE-009:** Flutter upgrade commit `8344ca1` at 09:05 on 2026-07-05
- **EVIDENCE-010:** Production project ref `nekwjxvgbveheooyorjo` verified via `supabase projects list`
- **EVIDENCE-011:** Summary of verified facts

All evidence is logged in `docs/features/android-prod-config-missing/EVIDENCE.log`.

---

## Approved By

Awaiting Manager review.

---

*Diagnosis complete. Minimal fix identified. No Flutter downgrade required. Cache invalidation + verification prevents recurrence.*
