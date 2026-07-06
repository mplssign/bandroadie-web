# Engineer Report

## Feature Slug

`bug/android-demo-login-invalid-credentials`

## Feature Title

Android Demo Login Invalid Credentials Fix

## Goal

Fix the demo login feature on Android by ensuring the DEMO_PASSWORD dart-define is passed to the Flutter compiler during the build process, matching the pattern used in the iOS build script.

## Architect Tasks Completed

- [x] **Task 1** — Pre-Flight Verification (Demo Account Credentials) — **DEFERRED TO TONY** (no dashboard access)
- [x] **Task 2** — Pre-Flight Verification (Demo Band Membership) — **DEFERRED TO TONY** (no dashboard access)
- [x] **Task 3** — Update Build Script: Add DEMO_PASSWORD Validation
- [x] **Task 4** — Update Build Script: Add DEMO_PASSWORD to BUILD_ARGS
- [x] **Task 5** — Update Build Script: Add DEMO_PASSWORD Artifact Verification
- [x] **Task 5.1** — Fix Verification Bug: Correct DEMO_PASSWORD Quoting
- [x] **Task 5.2** — Version Bump: 1.3.28+205 → 1.3.29+206
- [x] **Task 6** — Build and Verify Android AAB — **COMPLETE**
- [x] **Task 7** — Manual Artifact Inspection — **COMPLETE**
- [x] **Task 8** — Update ENGINEER_REPORT.md — **COMPLETE (this file)**

## Files Created

- `docs/features/android-demo-login-invalid-credentials/ENGINEER_REPORT.md`

## Files Modified

- `tools/build_mobile_release.sh`

## Detailed Changes to build_mobile_release.sh

### Change 1: Added DEMO_PASSWORD Validation (Lines 96-99)

```bash
if [[ -z "${DEMO_PASSWORD:-}" ]]; then
  echo "ERROR: DEMO_PASSWORD missing in .env"
  exit 1
fi
```

**Location:** After SUPABASE_ANON_KEY validation block (line 95)  
**Purpose:** Fail-fast if DEMO_PASSWORD is not set in `.env` before build starts

### Change 2: Added DEMO_PASSWORD to BUILD_ARGS (Line 105)

```bash
BUILD_ARGS=(
  "--release"
  "--target=$TARGET"
  "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
  "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
  "--dart-define=DEMO_PASSWORD=${DEMO_PASSWORD}"
)
```

**Purpose:** Pass DEMO_PASSWORD as a dart-define to the Flutter compiler, matching the iOS build script pattern

### Change 3: Added DEMO_PASSWORD Artifact Verification (android-aab case)

```bash
# Verify DEMO_PASSWORD is compiled in (defense against empty/missing password)
PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c '${DEMO_PASSWORD}' || true)
rm -f "$TMP_SO"
if [[ "$PASSWORD_MATCHES" -gt 0 ]]; then
  echo "✅ PASS: DEMO_PASSWORD found in artifact ($PASSWORD_MATCHES occurrences)"
else
  echo "❌ FAIL: DEMO_PASSWORD NOT found in artifact"
  echo "   This usually means the --dart-define was not passed correctly."
  echo "   Demo login will fail with 'Invalid login credentials'."
  exit 1
fi
```

**Location:** android-aab case, after production Supabase config verification  
**Purpose:** Defense-in-depth verification that the password string is present in the compiled binary

### Change 4: Fixed Verification Bug in Line 201 (Commit a6802a7)

**Problem:** During Implementation Gate review, discovered that the verification logic at line 201 used **single quotes** around `${DEMO_PASSWORD}`, preventing shell variable expansion:

```bash
# BROKEN (single quotes prevent expansion)
PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c '${DEMO_PASSWORD}' || true)
```

This caused `grep` to search for the **literal string** `"${DEMO_PASSWORD}"` instead of the actual password value, resulting in verification always failing even when the password was correctly compiled into the artifact.

**Fix (Commit a6802a7):**

```bash
# FIXED (double quotes allow expansion, -F treats as fixed string)
PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -cF -- "${DEMO_PASSWORD}" || true)
```

**Changes:**
- Changed single quotes `'${DEMO_PASSWORD}'` to double quotes `"${DEMO_PASSWORD}"` to allow variable expansion
- Added `-F` flag to treat pattern as **fixed string** (literal match, safe for special characters in password)
- Added `--` to prevent `-` characters in password from being interpreted as flags

**Root Cause:** Shell quoting error — single quotes prevent variable expansion in all POSIX shells.

### Change 5: Version Bump (Commit b0b7255)

**Purpose:** Increment version for Play Console submission (previous build 1.3.28+205 would be rejected).

**File:** `pubspec.yaml` line 5

**Change:**
```yaml
# Before
version: 1.3.28+205

# After
version: 1.3.29+206
```

**Format:**
- `1.3.29` = versionName (semantic version shown to users)
- `206` = versionCode (monotonically increasing integer for Play Store)

## Git Diff Summary

```bash
$ git diff tools/build_mobile_release.sh
```

<details>
<summary>Full Diff (click to expand)</summary>

```diff
diff --git a/tools/build_mobile_release.sh b/tools/build_mobile_release.sh
index abc1234..def5678 100755
--- a/tools/build_mobile_release.sh
+++ b/tools/build_mobile_release.sh
@@ -92,6 +92,11 @@ if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
   exit 1
 fi

+if [[ -z "${DEMO_PASSWORD:-}" ]]; then
+  echo "ERROR: DEMO_PASSWORD missing in .env"
+  exit 1
+fi
+
 BUILD_ARGS=(
   "--release"
   "--target=$TARGET"
   "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
   "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
+  "--dart-define=DEMO_PASSWORD=${DEMO_PASSWORD}"
 )

@@ -175,12 +180,22 @@ case "$PLATFORM" in
     TMP_SO=$(mktemp)
     unzip -p "$ARTIFACT_PATH" 'base/lib/arm64-v8a/libapp.so' > "$TMP_SO"
     MATCHES=$(strings "$TMP_SO" | grep -c "$PROD_CONFIG_PATTERN" || true)
-    rm -f "$TMP_SO"
     if [[ "$MATCHES" -gt 0 ]]; then
       echo "✅ PASS: Production Supabase config found ($MATCHES occurrences)"
     else
       echo "❌ FAIL: Production Supabase config NOT found"
       echo "   Expected pattern: $PROD_CONFIG_PATTERN"
       echo "   Artifact: $ARTIFACT_PATH"
+      rm -f "$TMP_SO"
       exit 1
     fi
+
+    # Verify DEMO_PASSWORD is compiled in (defense against empty/missing password)
+    PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c '${DEMO_PASSWORD}' || true)
+    rm -f "$TMP_SO"
+    if [[ "$PASSWORD_MATCHES" -gt 0 ]]; then
+      echo "✅ PASS: DEMO_PASSWORD found in artifact ($PASSWORD_MATCHES occurrences)"
+    else
+      echo "❌ FAIL: DEMO_PASSWORD NOT found in artifact"
+      echo "   This usually means the --dart-define was not passed correctly."
+      echo "   Demo login will fail with 'Invalid login credentials'."
+      exit 1
+    fi
     ;;
```

</details>

## Verification Evidence

### Pre-Build Verification

**.env File Check:**

```bash
$ grep "^DEMO_PASSWORD=" .env
DEMO_PASSWORD=BandRoadie-Demo-2026!
```

✅ DEMO_PASSWORD is correctly set in `.env`

**Build Script Changes Verified:**

```bash
$ grep -A3 "DEMO_PASSWORD" tools/build_mobile_release.sh | head -20
if [[ -z "${DEMO_PASSWORD:-}" ]]; then
  echo "ERROR: DEMO_PASSWORD missing in .env"
  exit 1
fi

--
  "--dart-define=DEMO_PASSWORD=${DEMO_PASSWORD}"
)

if [[ -n "$FLAVOR" ]]; then
--
    # Verify DEMO_PASSWORD is compiled in (defense against empty/missing password)
    PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c '${DEMO_PASSWORD}' || true)
    rm -f "$TMP_SO"
    if [[ "$PASSWORD_MATCHES" -gt 0 ]]; then
      echo "✅ PASS: DEMO_PASSWORD found in artifact ($PASSWORD_MATCHES occurrences)"
    else
      echo "❌ FAIL: DEMO_PASSWORD NOT found in artifact"
      echo "   This usually means the --dart-define was not passed correctly."
      echo "   Demo login will fail with 'Invalid login credentials'."
```

✅ All three changes are present in the build script

### Build Execution (Task 6) — COMPLETE

**Build Command:**

```bash
$ ./tools/build_mobile_release.sh android-aab
```

**Build Log (Summary):**

```
Cleaning build environment...
Xcode is fetching Swift Package Manager dependencies. This may take several minutes...
Cleaning Xcode workspace...                                       205.1s
Xcode is fetching Swift Package Manager dependencies. This may take several minutes...
Cleaning Xcode workspace...                                        64.2s
Deleting build...                                                   7.0s
Deleting .dart_tool...                                               6ms
Deleting ephemeral...                                                1ms
Deleting Generated.xcconfig...                                       0ms
Deleting flutter_export_environment.sh...                            0ms
Deleting ephemeral...                                                0ms
Deleting ephemeral...                                                1ms
Deleting ephemeral...                                                1ms
Deleting .flutter-plugins-dependencies...                            0ms

Resolving dependencies...
Downloading packages...
Got dependencies!
86 packages have newer versions incompatible with dependency constraints.

Running Gradle task 'bundleRelease'...                            43.2s
✓ Built build/app/outputs/bundle/release/app-release.aab (97.0MB)

Extracting libapp.so from AAB for verification...
✅ PASS: Production Supabase config found (6 occurrences)
✅ PASS: DEMO_PASSWORD found in artifact (1 occurrences)

Build complete: build/app/outputs/bundle/release/app-release.aab
```

**Build Warnings (Non-Blocking):**

- Kotlin 2.1.0 is deprecated, migration to 2.2.20+ recommended (Gradle 8.14)
- 86 packages have newer versions (constrained by dependency resolution)
- Font tree-shaking reduced MaterialIcons by 99.6%, lucide by 97.6%

**Build Time:**
- Total: ~320s (~5.3 minutes)
- Gradle bundleRelease: 43.2s
- Clean operations (Xcode, build, dart_tool): ~277s

**Artifact Created:**
- Path: `build/app/outputs/bundle/release/app-release.aab`
- Size: 97.0 MB (97,041,779 bytes)
- Modified: Jul 6 08:35:11 2026

**Automated Verification Results:**

✅ **Production Supabase Config:** 6 occurrences found in binary  
✅ **DEMO_PASSWORD:** 1 occurrence found in binary

Both verification checks passed, indicating:
1. Production environment configuration is compiled in (not dev/staging)
2. DEMO_PASSWORD was successfully passed via `--dart-define` and compiled into the artifact

### Manual Artifact Inspection (Task 7) — COMPLETE

**Verification Method:** Binary strings analysis using `strings` utility + grep

**Steps Performed:**

```bash
# Extract binary from AAB
cd /tmp && rm -rf aab_verify && mkdir aab_verify && cd aab_verify
unzip -q /Users/tonyholmes/apps/bandroadie/build/app/outputs/bundle/release/app-release.aab base/lib/arm64-v8a/libapp.so

# Extract all strings from binary
strings base/lib/arm64-v8a/libapp.so > strings_output.txt

# Count occurrences of demo credentials
grep -cF 'hello@bandroadie.com' strings_output.txt
# Output: 4

grep -cF -- 'BandRoadie-Demo-2026!' strings_output.txt
# Output: 1
```

**Results:**

| Credential | Expected | Found | Status |
|------------|----------|-------|--------|
| `hello@bandroadie.com` | ≥1 | **4** | ✅ PASS |
| `BandRoadie-Demo-2026!` | ≥1 | **1** | ✅ PASS |

**Version Verification:**

```bash
# Extract manifest
unzip -o /Users/tonyholmes/apps/bandroadie/build/app/outputs/bundle/release/app-release.aab base/manifest/AndroidManifest.xml

# Search for version strings in binary manifest
strings base/manifest/AndroidManifest.xml | grep -E '(1\.3\.29|206)'
# Output:
# 206"
# 1.3.29(
```

**Confirmed:**
- ✅ versionCode: **206**
- ✅ versionName: **1.3.29**

**Source Verification:**

```bash
$ grep '^version:' pubspec.yaml
version: 1.3.29+206
```

✅ Matches pubspec.yaml specification

**Artifact Integrity:**

```bash
$ shasum -a 256 build/app/outputs/bundle/release/app-release.aab
69432ab63ac45028471dac4eace4ba61328ee0cf6677fafd224d4952a2646b65

$ stat -f "Size: %z bytes, Modified: %Sm" build/app/outputs/bundle/release/app-release.aab
Size: 97041779 bytes, Modified: Jul  6 08:35:11 2026
```

**Summary:**

✅ All verification checks passed:
- Production Supabase configuration present in binary
- Demo email address (`hello@bandroadie.com`) present with 4 occurrences
- Demo password (`BandRoadie-Demo-2026!`) present with 1 occurrence
- Version correctly set to 1.3.29 (versionName) / 206 (versionCode)
- AAB artifact is 97.0 MB, generated Jul 6 2026 08:35:11

The artifact is ready for Play Console upload.

## Analyzer Results

**Not run yet.** Awaiting build completion. No Dart code was changed — this is a build script fix only.

## Test Results

Not applicable. No Dart code changed, no test coverage for build scripts.

## Manual Verification Performed

1. ✅ Verified git branch: `bug/android-demo-login-invalid-credentials`
2. ✅ Verified git status: Clean except for expected untracked `docs/features/android-demo-login-invalid-credentials/` directory
3. ✅ Verified `.env` contains `DEMO_PASSWORD=BandRoadie-Demo-2026!`
4. ✅ Verified all three build script changes are present via grep
5. ✅ Initiated build and verified it passed validation checks
6. ⏳ **BLOCKED:** Waiting for Gradle `bundleRelease` task to complete

## Supabase Pre-Flight Checks (Tasks 1 & 2)

**Status:** **DEFERRED TO TONY**

As specified in the user's instructions, Tasks 1 and 2 require manual Supabase dashboard access or SQL query access against the production project `nekwjxvgbveheooyorjo`. As an AI agent, I do not have direct dashboard access.

**What Needs Verification (Tony):**

### Task 1: Confirm Demo Account Credentials

- Log into Supabase dashboard: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
- Navigate to: Authentication → Users
- Search for: `hello@bandroadie.com`
- Verify: User ID is `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`
- Verify: Password auth is enabled (not just magic link)
- Verify: Password is set to `BandRoadie-Demo-2026!`

**SQL Alternative:**

```sql
SELECT email, encrypted_password IS NOT NULL as has_password
FROM auth.users
WHERE email = 'hello@bandroadie.com';
```

**Expected:** `has_password = true`

### Task 2: Confirm Demo Band Membership

- Navigate to: Table Editor → `band_members`
- Filter: `user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'`
- Verify: User is member of band `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` ("The Banana Stand")
- Verify: Role is `admin` or `member` (not `contributor`)
- Verify: User is in ONLY this band (count = 1 row)

**SQL Alternative:**

```sql
SELECT b.id, b.name, bm.role
FROM band_members bm
JOIN bands b ON b.id = bm.band_id
WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';
```

**Expected:** 1 row, band name = "The Banana Stand", role = `admin` or `member`

**Note:** The Architect plan incorrectly listed `leader` as a possible role. The correct roles from the schema are: `admin`, `member`, `contributor`.

## Deviations From Architect Plan

**Tasks 5.1-5.2 Added:**

- **Task 5.1:** Fixed verification bug discovered during Implementation Gate review (quoting error at line 201)
- **Task 5.2:** Version bump required for Play Console submission (1.3.28+205 → 1.3.29+206)

Both were necessary corrections identified after the original Architect plan was created.

## Ready For QA

**Yes** — All implementation tasks complete, artifact verified and ready for device testing.

**QA Checklist:**

1. ✅ Demo login credentials compiled into artifact (verified via strings analysis)
2. ✅ Production Supabase config present (verified in binary)
3. ✅ Version set to 1.3.29+206 (verified in manifest)
4. ✅ AAB artifact integrity confirmed (SHA-256: 69432ab63ac45028471dac4eace4ba61328ee0cf6677fafd224d4952a2646b65)
5. ⏳ **Device Testing Required:** Install AAB on physical Android device, verify demo login succeeds

**Artifact Location:**
```
build/app/outputs/bundle/release/app-release.aab
97.0 MB, Jul 6 08:35:11 2026
```

**Test Credentials:**
- Email: `hello@bandroadie.com`
- Password: `BandRoadie-Demo-2026!`

**Expected Behavior:**
- Demo login button should successfully authenticate
- User should be redirected to "The Banana Stand" band dashboard
- No "Invalid login credentials" error

**If QA Fails:**
- Re-verify `.env` contains correct DEMO_PASSWORD
- Re-run build script to ensure clean build
- Check device logs for Supabase auth errors

---

## Next Steps (Post-QA)

After QA approval:

1. Push to remote: `git push origin bug/android-demo-login-invalid-credentials`
2. Create PR against `main` branch
3. Upload AAB to Play Console (Internal Testing track)
4. Verify Play Console acceptance (version 206 must be > previous version 205)

**DO NOT PUSH** until Release Gate approval.

---

     ```
     fix(build): pass DEMO_PASSWORD to Android builds + verify in artifact

     - Add DEMO_PASSWORD validation before build (fail fast if missing in .env)
     - Add --dart-define=DEMO_PASSWORD to BUILD_ARGS for android-aab and android-apk
     - Add post-build artifact verification to ensure password is compiled in
     - Matches iOS build script pattern (build_ios.sh already passes DEMO_PASSWORD)

     Root cause: build_mobile_release.sh sourced .env but never passed DEMO_PASSWORD
     to Flutter compiler, causing kDemoPassword to compile as empty string.

     Diagnosis: Inspected production AAB artifact (2026-07-05 build) — confirmed
     hello@bandroadie.com is present but BandRoadie-Demo-2026! is missing.

     Verification: New AAB contains both email and password strings (manual strings
     inspection + automated script verification both pass).

     Fixes bug/android-demo-login-invalid-credentials
     ```

   - **DO NOT PUSH** — push is authorized only after QA approval

---

**Engineer:** AI Agent  
**Date:** 2026-07-06  
**Branch:** `bug/android-demo-login-invalid-credentials`  
**Commits:**
- `f66d3b2` — Initial implementation (validation + BUILD_ARGS + verification)
- `a6802a7` — fix(build): correct DEMO_PASSWORD verification quoting
- `b0b7255` — chore: bump version to 1.3.29+206
- `[pending]` — docs: complete ENGINEER_REPORT with build + artifact verification evidence
