# ARCHITECT_PLAN — Android Demo Login Invalid Credentials

---

## 1. Feature Slug

`bug/android-demo-login-invalid-credentials`

---

## 2. Problem Summary

The demo login feature (7-tap logo easter egg on login screen) fails on the current Play Store production Android build with error "Demo login failed: Invalid login credentials". The same flow works correctly on the current iOS build, confirming that the Supabase Auth credentials for the demo account (`hello@bandroadie.com`) are valid.

**User Request:** Tony's strong preference is a fix that does NOT require a new Android build (e.g., a Supabase Auth/database-side fix). A rebuild is the fallback, not the default.

**Investigation Finding:** After inspecting the compiled AAB artifact, a no-build fix is **NOT POSSIBLE**. The root cause is an empty DEMO_PASSWORD compiled into the production Android binary, and Supabase Auth cannot authenticate with an empty password. The only path forward is a corrected Android build.

---

## 3. Root Cause

**Classification: Root Cause B — Empty or missing DEMO_PASSWORD compiled in**

**Confidence: HIGH (confirmed through binary artifact inspection)**

**Primary Cause:** The `tools/build_mobile_release.sh` script does not pass the `DEMO_PASSWORD` dart-define to the Flutter compiler when building the Android AAB. This causes the code in `lib/app/constants/demo_credentials.dart` to compile with an empty string for `kDemoPassword`, which Supabase Auth rejects as "Invalid login credentials".

### Evidence

#### 1. AAB Binary Artifact Inspection (Decisive Evidence)

**Artifact inspected:** `build/app/outputs/bundle/release/app-release.aab`  
**Build timestamp:** July 5, 2026 at 23:06:43  
**Git commit at build time:** `37e690d` (2026-07-05 23:12:14)

**Extraction and analysis:**

```bash
# Extracted AAB to /tmp/aab_extract
unzip -q app-release.aab

# Extracted strings from ARM64 binary
strings ./base/lib/arm64-v8a/libapp.so > /tmp/libapp_strings.txt

# Search results:
✅ Email string FOUND: "hello@bandroadie.com" (appears 4 times)
❌ Password string NOT FOUND: "BandRoadie-Demo-2026!" (0 matches)
❌ Old email NOT FOUND: "bandroadie2026@gmail.com" (0 matches)
❌ Old password NOT FOUND: "banana-stand-demo" (0 matches)
```

**Conclusion:** The correct email (`hello@bandroadie.com`) is compiled in, but NO password value of any kind is present in the binary. This is consistent with the dart-define default behavior: when `DEMO_PASSWORD` is not provided at compile time, `String.fromEnvironment('DEMO_PASSWORD', defaultValue: '')` compiles to an empty string.

#### 2. Build Script Analysis

**File:** `tools/build_mobile_release.sh` at commit `37e690d` (used for the July 5 build)

**Lines 98-103:**

```bash
BUILD_ARGS=(
  "--release"
  "--target=$TARGET"
  "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
  "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
)
```

**Missing:** `--dart-define=DEMO_PASSWORD` is NOT in BUILD_ARGS.  
**Missing:** `--dart-define-from-file=dart_defines.json` is NOT used.

**Comparison with iOS build script (`tools/build_ios.sh`):**

**Lines 93-94 (IPA build):**

```bash
flutter build ipa --release --dart-define-from-file=dart_defines.json \
  --dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"
```

**Lines 101-102 (App build):**

```bash
flutter build ios --release --dart-define-from-file=dart_defines.json \
  --dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"
```

iOS build script BOTH uses `--dart-define-from-file` (which contains DEMO_PASSWORD from `gen_dart_defines.sh`) AND explicitly passes `--dart-define=DEMO_PASSWORD` as a redundant safeguard. Android script does neither.

#### 3. Code Behavior Confirmation

**File:** `lib/app/constants/demo_credentials.dart` lines 13-20

```dart
const String kDemoEmail = 'hello@bandroadie.com';

const String kDemoPassword = String.fromEnvironment(
  'DEMO_PASSWORD',
  defaultValue: '',  // ← Compiles to empty string when not provided
);
```

**File:** `lib/features/auth/login_screen.dart` lines 176-180

```dart
await supabase.auth.signInWithPassword(
  email: kDemoEmail,      // 'hello@bandroadie.com'
  password: kDemoPassword, // '' (empty string in production AAB)
);
```

**Supabase Auth behavior:** Attempting to authenticate with an empty password returns `AuthException` with message "Invalid login credentials" regardless of whether the account exists or has a password set.

#### 4. Previous Incomplete Fix

**Commit `d74bd1e` (2026-06-24):** "feat: multi-date response, keyboard nav, dashboard spacing, auth/demo login fixes"

This commit:

- ✅ Added `"DEMO_PASSWORD": "${DEMO_PASSWORD:-}"` to `tools/gen_dart_defines.sh` (line 38)
- ✅ Added `mounted` guard in `auth_gate.dart` to fix iOS crash
- ✅ Updated `supabase/config.toml` redirect URLs for Android magic link
- ❌ Did NOT update `build_mobile_release.sh` to use `--dart-define-from-file` or pass `DEMO_PASSWORD`

**Result:** `gen_dart_defines.sh` now generates `dart_defines.json` with DEMO_PASSWORD correctly, but the Android build script doesn't consume it. iOS works because its build script explicitly passes DEMO_PASSWORD.

#### 5. Why iOS Works

iOS build was done with `build_ios.sh` which:

1. Calls `gen_dart_defines.sh` to generate `dart_defines.json` (line 69)
2. Passes `--dart-define-from-file=dart_defines.json` to `flutter build` (lines 93, 101)
3. ALSO explicitly passes `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` (lines 94, 102)

At least one of these mechanisms ensures DEMO_PASSWORD is compiled into the iOS binary.

### Why a Database/Server-Side Fix is NOT Possible

**Option rejected:** Restore old demo account (`bandroadie2026@gmail.com`) with old password in Supabase Auth.

**Why this fails:** The AAB binary contains `hello@bandroadie.com` as the email (confirmed by strings inspection). Even if we create/restore `bandroadie2026@gmail.com` with any password, the app will still attempt to authenticate as `hello@bandroadie.com` with an empty password, which will fail.

**Option rejected:** Set the password for `hello@bandroadie.com` to empty string in Supabase Auth.

**Why this fails:** Supabase Auth does not support empty passwords. Attempting to set an empty password via the dashboard or API is rejected with a validation error. Even if it were allowed, password authentication with an empty password is a security violation that Supabase Auth correctly blocks.

**Conclusion:** The only fix is to rebuild the Android AAB with DEMO_PASSWORD correctly compiled in.

---

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md` — Architect role definition and execution phases
- `docs/agents/GUARDRAILS.md` — Technical constraints (config rules, build safety, async lifecycle)
- `docs/agents/OPERATING_MODEL.md` — Four-role pipeline, gates, escalation protocol
- `docs/features/demo-mode-credentials-update/ARCHITECT_PLAN.md` — Credential migration from `bandroadie2026@gmail.com` to `hello@bandroadie.com`
- `docs/features/bug/auth-and-demo-login/ARCHITECT_PLAN.md` — Previous fix that added DEMO_PASSWORD to `gen_dart_defines.sh` but missed updating the Android build script

**Code files inspected (read in full):**

- `lib/app/constants/demo_credentials.dart` — Demo credential constants and compile-time injection
- `lib/features/auth/login_screen.dart` — 7-tap logo trigger and `_triggerDemoLogin()` implementation
- `tools/build_mobile_release.sh` — Unified iOS/Android release build script (missing DEMO_PASSWORD)
- `tools/build_ios.sh` — iOS-specific build script (correctly passes DEMO_PASSWORD)
- `tools/gen_dart_defines.sh` — Generates `dart_defines.json` from `.env` (includes DEMO_PASSWORD as of commit `d74bd1e`)

**Binary artifact inspected:**

- `build/app/outputs/bundle/release/app-release.aab` — Production Android AAB built on 2026-07-05 at 23:06:43 from commit `37e690d`
- Extracted and analyzed `base/lib/arm64-v8a/libapp.so` using `strings` command
- Confirmed presence of email (`hello@bandroadie.com`) and absence of password (`BandRoadie-Demo-2026!`)

---

## 5. Existing System Analysis

### 5.1 Demo Login Flow (Current Implementation)

**Trigger:** User taps BandRoadie logo on login screen 7 times in rapid succession.

**Code:** `lib/features/auth/login_screen.dart` lines 135-200

**Flow:**

1. `_handleLogoTap()` increments `_logoTapCount` (line 139)
2. After 7th tap, `_triggerDemoLogin()` is called (line 150)
3. Tap counter auto-resets after 3 seconds of inactivity (lines 156-162)
4. `_triggerDemoLogin()` calls `supabase.auth.signInWithPassword(email: kDemoEmail, password: kDemoPassword)` (lines 176-180)
5. On success, `authStateProvider` fires state change and `AuthGate` routes to `AppShell`
6. On `AuthException`, displays error message: `'Demo login failed: ${e.message}'` (line 185)

**Demo account details:**

- **Email:** `hello@bandroadie.com` (user ID `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`)
- **Password (configured in .env):** `BandRoadie-Demo-2026!`
- **Band:** "The Banana Stand" (band ID `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`)

**Current failure:** Step 4 fails with `AuthException: Invalid login credentials` because `kDemoPassword` is empty string in the production AAB.

### 5.2 Build Process (Android)

**Normal development builds:**

- Developer runs `flutter run` or `flutter build appbundle` directly
- Uses `--dart-define-from-file=dart_defines.json` if specified
- Local `dart_defines.json` is generated by `gen_dart_defines.sh` and includes DEMO_PASSWORD

**Production release builds (current broken process):**

1. Developer sources `.env` file (contains DEMO_PASSWORD)
2. Developer runs `./tools/build_mobile_release.sh android-aab`
3. Script validates SUPABASE_URL and SUPABASE_ANON_KEY are set (lines 85-95)
4. Script calls `flutter clean` (line 132)
5. Script calls `flutter build appbundle` with BUILD_ARGS (line 142)
6. BUILD_ARGS contains ONLY SUPABASE_URL and SUPABASE_ANON_KEY (lines 98-103)
7. Script verifies production Supabase URL is in artifact (lines 148-186)
8. AAB is written to `build/app/outputs/bundle/release/app-release.aab`

**Result:** DEMO_PASSWORD is never passed to the compiler, so it compiles to empty string.

### 5.3 Build Process (iOS) — Why It Works

**iOS build script:** `tools/build_ios.sh`

**Key differences:**

1. Explicitly calls `gen_dart_defines.sh` (line 69) before building
2. Uses `--dart-define-from-file=dart_defines.json` (lines 93, 101)
3. ALSO explicitly passes `--dart-define=DEMO_PASSWORD="${DEMO_PASSWORD:-}"` (lines 94, 102)

**Result:** DEMO_PASSWORD is compiled into the iOS binary via at least one of these mechanisms (likely both).

---

## 6. Proposed Solution

### 6.1 Fix the Android Build Script

**Change:** Update `tools/build_mobile_release.sh` to pass `DEMO_PASSWORD` to the Flutter compiler when building Android AAB/APK.

**Implementation approach:** Add explicit `--dart-define=DEMO_PASSWORD` to BUILD_ARGS, matching the iOS build script pattern.

**Why explicit `--dart-define` instead of `--dart-define-from-file`:**

- The script already sources `.env` directly (line 83)
- It already validates and extracts SUPABASE_URL and SUPABASE_ANON_KEY from env vars (lines 85-95)
- Using explicit `--dart-define` keeps the pattern consistent within the same script
- Avoids dependency on `dart_defines.json` file state (which is gitignored and may be stale)
- Matches the iOS script's redundant safeguard approach (uses both mechanisms)

**Alternative approach considered and REJECTED:**

- Use `--dart-define-from-file=dart_defines.json` instead of explicit defines
- **Rejected because:** Would require calling `gen_dart_defines.sh` before build, adding a dependency and potential failure point. Current script is self-contained and sources `.env` directly. Explicit defines are more transparent and match the existing pattern.

### 6.2 Add Password Verification to Build Script

**Change:** After building, verify that the AAB artifact contains the DEMO_PASSWORD string before allowing the build to succeed.

**Rationale:** Defense-in-depth. If `.env` is missing DEMO_PASSWORD or the value is empty, the build should FAIL immediately with a clear error message, not produce a broken artifact that fails silently in production.

**Implementation:** Extend the existing artifact verification block (lines 148-186) to also search for the DEMO_PASSWORD string in the compiled binary.

**IMPORTANT CAVEAT:** String literal verification is fragile. If Flutter's compiler optimizes, obfuscates, or encodes the password differently in a future release, the verification may false-fail. This is acceptable as a build-time canary — better to catch the issue during build than in production.

### 6.3 Rebuild Android AAB with Corrected Script

**Process:**

1. Engineer updates `build_mobile_release.sh` per section 6.1
2. Engineer updates artifact verification per section 6.2
3. Engineer runs `./tools/build_mobile_release.sh android-aab` locally
4. Engineer verifies build succeeds and password verification passes
5. Engineer extracts AAB and manually verifies password string is present using `strings` command (belt-and-suspenders check)
6. QA tests demo login on a physical Android device using the new AAB via `adb install` or internal testing track
7. If QA approves, upload AAB to Play Console (production track submission is out of scope for this fix)

---

## 7. Database Impact

**Database: Not applicable**

No database schema changes, no RLS policy changes, no RPC function changes, no trigger changes. The demo account and band already exist in Supabase production with correct credentials.

**Verification required:** Engineer must confirm (via Supabase dashboard or psql) that user `hello@bandroadie.com` (user ID `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`) has:

1. Password authentication enabled (not just magic link)
2. Correct password set to `BandRoadie-Demo-2026!`
3. Membership in band `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` ("The Banana Stand")

If any of these are NOT true, demo login will still fail even after rebuilding. This verification is NOT a code change — it's a pre-flight check.

---

## 8. Flutter Architecture Changes

**Affected:** None

No changes to Flutter code, state management, widgets, repositories, or providers. This is a pure build configuration fix.

**Files modified:**

- `tools/build_mobile_release.sh` only

**Files explicitly unchanged:**

- `lib/app/constants/demo_credentials.dart` — Already correct, uses `String.fromEnvironment` properly
- `lib/features/auth/login_screen.dart` — Already correct, demo login implementation is sound
- `tools/gen_dart_defines.sh` — Already correct as of commit `d74bd1e`, includes DEMO_PASSWORD
- `.env` — Already correct, contains `DEMO_PASSWORD=BandRoadie-Demo-2026!`

---

## 9. Files to Create

**None**

All necessary files already exist. This is a build script fix, not a code change.

---

## 10. Files to Modify

| File                            | What changes                                                                                                                                                                                                                        |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools/build_mobile_release.sh` | Add `DEMO_PASSWORD` validation (lines 85-95 area) and add `--dart-define=DEMO_PASSWORD` to BUILD_ARGS (lines 98-103 area). Extend artifact verification (lines 148-186 area) to search for DEMO_PASSWORD string in compiled binary. |

**Detailed change specification:**

### Change 1: Validate DEMO_PASSWORD from .env

**Location:** After line 95 (after SUPABASE_ANON_KEY validation)  
**Add:**

```bash
if [[ -z "${DEMO_PASSWORD:-}" ]]; then
  echo "ERROR: DEMO_PASSWORD missing in .env"
  exit 1
fi
```

### Change 2: Add DEMO_PASSWORD to BUILD_ARGS

**Location:** Line 103 (after `--dart-define=SUPABASE_ANON_KEY` line)  
**Add:**

```bash
  "--dart-define=DEMO_PASSWORD=${DEMO_PASSWORD}"
```

### Change 3: Verify DEMO_PASSWORD in artifact

**Location:** Inside the `android-aab` case of the artifact verification switch (after PROD_CONFIG_PATTERN check succeeds, before the `;;` terminator around line 175)  
**Add:**

```bash
    # Verify DEMO_PASSWORD is compiled in (defense against empty/missing password)
    PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c "${DEMO_PASSWORD}" || true)
    if [[ "$PASSWORD_MATCHES" -gt 0 ]]; then
      echo "✅ PASS: DEMO_PASSWORD found in artifact ($PASSWORD_MATCHES occurrences)"
    else
      echo "❌ FAIL: DEMO_PASSWORD NOT found in artifact"
      echo "   This usually means the --dart-define was not passed correctly."
      echo "   Demo login will fail with 'Invalid login credentials'."
      exit 1
    fi
```

**Note on password visibility:** The script already sources `.env` which contains the plaintext password. Echoing the password in the verification grep is acceptable because this is a local build script, not logged to CI. The password is already semi-public (disclosed to Play Store reviewers in App Access declaration).

---

## 11. Files Off-Limits

| File                                       | Reason                                                           |
| ------------------------------------------ | ---------------------------------------------------------------- |
| `lib/main.dart`                            | Init order must not change                                       |
| `lib/app/app.dart`                         | App initialization must not change                               |
| `lib/app/constants/demo_credentials.dart`  | Already correct, no change needed                                |
| `lib/features/auth/login_screen.dart`      | Demo login implementation is correct, no change needed           |
| `lib/features/auth/auth_gate.dart`         | Auth flow is correct, no change needed                           |
| `tools/gen_dart_defines.sh`                | Already fixed in commit `d74bd1e`, no further change needed      |
| `tools/build_ios.sh`                       | iOS build works correctly, no change needed                      |
| `tools/build_android.sh`                   | Superseded by `build_mobile_release.sh`, not used for production |
| `.env`                                     | Already contains correct DEMO_PASSWORD, no change needed         |
| `dart_defines.json`                        | Generated file, not edited manually                              |
| `supabase/config.toml`                     | Already fixed in commit `d74bd1e`, no change needed              |
| `android/app/src/main/AndroidManifest.xml` | Deep link configuration is correct, no change needed             |

---

## 12. System Impact Map

| System             | Impact                                                                                   |
| ------------------ | ---------------------------------------------------------------------------------------- |
| Gigs               | unaffected                                                                               |
| Rehearsals         | unaffected                                                                               |
| Setlists / Catalog | unaffected                                                                               |
| Members / RBAC     | unaffected                                                                               |
| Auth / Session     | **affected** — Demo login (password auth path) will work after rebuild                   |
| Routing            | unaffected                                                                               |
| Notifications      | unaffected                                                                               |
| Platform (iOS)     | unaffected — already works                                                               |
| Platform (Android) | **affected** — Demo login will work after corrected build                                |
| Platform (Web)     | unknown — demo login untested on web, likely does not work (no way to 7-tap logo on web) |
| Platform (macOS)   | unknown — demo login untested on macOS                                                   |

**Auth/Session impact detail:** This fix enables the password authentication path for the demo account on Android. Normal users continue to use magic link (PKCE) authentication. No changes to session lifecycle, token refresh, or sign-out behavior.

---

## 13. Regression Risk

**Overall risk: LOW**

**Rationale:**

1. **Isolated change:** Only `build_mobile_release.sh` is modified. No Flutter code, no database schema, no RLS policies, no auth flow logic.
2. **Additive change:** The script adds a dart-define that was already intended to be present. It does not remove or replace anything that works.
3. **No shared code path risk:** Demo login is an independent code path (`signInWithPassword`) that does not share logic with normal magic link auth (`signInWithOtp` + `verifyOTP`). Fixing demo login cannot break magic link.
4. **Existing pattern:** The change matches the iOS build script pattern exactly. iOS has been shipping with this configuration since commit `d74bd1e` (2026-06-24) with no issues.
5. **Verification gate:** The added artifact verification will fail the build if DEMO_PASSWORD is missing, preventing bad artifacts from being produced.

**Affected systems:** Only "Auth / Session (Android demo login)" as noted in System Impact Map. 1 out of 9 systems affected, and it's a currently-broken feature being fixed, not a working feature being modified.

**Failure mode if this fix introduces a bug:**

- Worst case: Build script fails with clear error message during artifact verification. No bad artifact is produced.
- If verification has a false positive (password is in artifact but verification script doesn't find it): Build fails, but manual strings inspection can confirm artifact is correct, and verification can be adjusted or removed.
- If password is compiled in but has wrong value: Demo login fails with "Invalid login credentials" same as current state. QA will catch this in Tier 2 testing.

**Cannot cause:** Magic link regression, normal user auth breakage, session management issues, deep link handling issues (all of those are in separate code paths and files not touched by this fix).

---

## 14. Engineer Task Breakdown

Execute in strict order. Each task is atomic and verifiable. Stop and report if blocked.

### Task 1: Pre-Flight Verification — Confirm Demo Account Credentials

**Type:** Manual verification (no code changes)

**Action:**

1. Log into Supabase production dashboard: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
2. Navigate to: Authentication → Users
3. Search for user `hello@bandroadie.com`
4. Click user to view details
5. Verify: User ID is `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`
6. Verify: "Password" is listed under "Identity" section (confirms password auth is enabled)
7. Attempt to reset password to confirm current value, or use SQL query:
   ```sql
   SELECT email, encrypted_password IS NOT NULL as has_password
   FROM auth.users
   WHERE email = 'hello@bandroadie.com';
   ```
8. Expected result: `has_password = true`

**If password is not set or user does not exist:**

- **STOP.** Escalate to Tony. The user must have password auth enabled for demo login to work, regardless of build fix.
- Tony will need to set password via Supabase dashboard: Authentication → Users → [user] → Reset Password → Set to `BandRoadie-Demo-2026!`

**Deliverable:** Confirmation message: "✅ Verified: `hello@bandroadie.com` (user ID `4b8b4b6c...`) has password auth enabled in production Supabase"

---

### Task 2: Pre-Flight Verification — Confirm Demo Band Membership

**Type:** Manual verification (no code changes)

**Action:**

1. In Supabase dashboard, navigate to: Table Editor → `band_members`
2. Filter: `user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'`
3. Verify: User is a member of band `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` (role should be `leader` or `admin`)
4. Count total rows returned: Should be 1 (user should only be in the demo band)
5. Alternative SQL query:
   ```sql
   SELECT b.id, b.name, bm.role
   FROM band_members bm
   JOIN bands b ON b.id = bm.band_id
   WHERE bm.user_id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925';
   ```
6. Expected result: 1 row, band name = "The Banana Stand"

**If user is not in the band or is in multiple bands:**

- **STOP.** Escalate to Tony. Post-auth band selection relies on `bands.first` for users with no persisted preference. If the demo user is in multiple bands or zero bands, the routing will be incorrect.

**Deliverable:** Confirmation message: "✅ Verified: Demo user is member of band `e89bea44...` ('The Banana Stand') and no other bands"

---

### Task 3: Update Build Script — Add DEMO_PASSWORD Validation

**File:** `tools/build_mobile_release.sh`  
**Location:** After line 95 (after SUPABASE_ANON_KEY validation block)

**Change:** Insert validation check for DEMO_PASSWORD

**Implementation:**

```bash
if [[ -z "${DEMO_PASSWORD:-}" ]]; then
  echo "ERROR: DEMO_PASSWORD missing in .env"
  exit 1
fi
```

**Verification:**

1. Temporarily rename `DEMO_PASSWORD` in `.env` to `DEMO_PASSWORD_DISABLED`
2. Run: `./tools/build_mobile_release.sh android-aab`
3. Expected: Script exits with error "ERROR: DEMO_PASSWORD missing in .env"
4. Restore `DEMO_PASSWORD` in `.env`

**Deliverable:** Commit message: "fix(build): add DEMO_PASSWORD validation to build_mobile_release.sh"

---

### Task 4: Update Build Script — Add DEMO_PASSWORD to BUILD_ARGS

**File:** `tools/build_mobile_release.sh`  
**Location:** Line 103 (end of BUILD_ARGS array initialization, after `--dart-define=SUPABASE_ANON_KEY` line)

**Change:** Add `--dart-define=DEMO_PASSWORD` to the array

**Implementation:**

```bash
BUILD_ARGS=(
  "--release"
  "--target=$TARGET"
  "--dart-define=SUPABASE_URL=${SUPABASE_URL}"
  "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
  "--dart-define=DEMO_PASSWORD=${DEMO_PASSWORD}"
)
```

**Verification:** Read file, confirm line is present. No runtime verification yet (happens in Task 6).

**Deliverable:** Commit message: "fix(build): pass DEMO_PASSWORD dart-define for Android builds"

---

### Task 5: Update Build Script — Add DEMO_PASSWORD Artifact Verification

**File:** `tools/build_mobile_release.sh`  
**Location:** Inside the `android-aab` case of the artifact verification switch, after the PROD_CONFIG_PATTERN check succeeds (around line 175, before the `;;` case terminator)

**Change:** Add password string verification using the same TMP_SO file that's already extracted

**Implementation:**

```bash
    # Verify DEMO_PASSWORD is compiled in (defense against empty/missing password)
    PASSWORD_MATCHES=$(strings "$TMP_SO" | grep -c "${DEMO_PASSWORD}" || true)
    if [[ "$PASSWORD_MATCHES" -gt 0 ]]; then
      echo "✅ PASS: DEMO_PASSWORD found in artifact ($PASSWORD_MATCHES occurrences)"
    else
      echo "❌ FAIL: DEMO_PASSWORD NOT found in artifact"
      echo "   This usually means the --dart-define was not passed correctly."
      echo "   Demo login will fail with 'Invalid login credentials'."
      exit 1
    fi
```

**Verification:** Will be verified in Task 6 when the full build runs.

**Deliverable:** Commit message: "fix(build): verify DEMO_PASSWORD is compiled into Android artifact"

---

### Task 6: Build and Verify Android AAB

**Action:** Run full release build with corrected script

**Steps:**

1. Ensure `.env` contains `DEMO_PASSWORD=BandRoadie-Demo-2026!`
2. Run: `./tools/build_mobile_release.sh android-aab`
3. Monitor console output for validation checks:
   - ✅ Should pass DEMO_PASSWORD validation (Task 3)
   - ✅ Should pass Supabase config verification (existing)
   - ✅ Should pass DEMO_PASSWORD artifact verification (Task 5)
4. Build should succeed and produce: `build/app/outputs/bundle/release/app-release.aab`

**If build fails at DEMO_PASSWORD artifact verification:**

- This indicates the password is not being compiled in despite passing the dart-define
- Investigate: Check `flutter build` verbose output, confirm no typos in variable name
- Fallback: Use `--dart-define-from-file=dart_defines.json` approach instead (requires also adding `gen_dart_defines.sh` call to script)

**Deliverable:** Build log showing all 3 verification passes (validation, supabase config, demo password)

---

### Task 7: Manual Artifact Inspection (Belt-and-Suspenders)

**Action:** Independently verify the password is in the new AAB using the same inspection method from diagnosis

**Steps:**

```bash
cd /tmp
rm -rf aab_verify
mkdir aab_verify
cd aab_verify
unzip -q /Users/tonyholmes/apps/bandroadie/build/app/outputs/bundle/release/app-release.aab
strings ./base/lib/arm64-v8a/libapp.so > strings_output.txt
grep "hello@bandroadie.com" strings_output.txt  # Should find 4 matches
grep "BandRoadie-Demo-2026!" strings_output.txt  # Should find 1+ matches (NEW!)
```

**Expected result:**

```
hello@bandroadie.com     ← Should appear
BandRoadie-Demo-2026!    ← Should appear (was missing in old AAB)
```

**If password is still missing:**

- **STOP.** Something is wrong with the build process. The script verification passed but manual inspection fails — investigate Flutter build internals or Dart compiler optimization stripping the string.

**Deliverable:** Screenshot or terminal output showing both email AND password strings present in the new AAB

---

### Task 8: Update ENGINEER_REPORT.md

**File:** `docs/features/android-demo-login-invalid-credentials/ENGINEER_REPORT.md`

**Required sections:**

1. **Tasks Completed** — List Tasks 1-7 with checkmarks
2. **Files Modified** — `tools/build_mobile_release.sh` with line numbers and description
3. **Verification Evidence** — Copy/paste of:
   - Build log showing 3 passes (Task 6)
   - Manual strings inspection showing password present (Task 7)
   - Demo account verification results (Tasks 1-2)
4. **Git Diff Summary** — Output of `git diff tools/build_mobile_release.sh`
5. **AAB Details** — File size, build timestamp, SHA-256 hash
6. **Ready for QA** — Explicit statement: "✅ Ready for QA testing — AAB contains correct demo password"

**Deliverable:** Complete ENGINEER_REPORT.md file committed to feature branch

---

### Task 9: Commit and Push

**Action:** Commit all changes to feature branch and push

**Steps:**

```bash
git add tools/build_mobile_release.sh
git add docs/features/android-demo-login-invalid-credentials/ENGINEER_REPORT.md
git commit -m "fix(build): pass DEMO_PASSWORD to Android builds + verify in artifact

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

Fixes bug/android-demo-login-invalid-credentials"

git push origin bug/android-demo-login-invalid-credentials
```

**Deliverable:** Branch pushed to remote, commit hash recorded in ENGINEER_REPORT.md

---

## 15. Verification Plan

This plan is split into Tier 1 (pre-rebuild) and Tier 2 (post-rebuild with new AAB).

### Tier 1 — Pre-Rebuild Verification (Diagnostic Confirmation)

**Purpose:** Confirm root cause analysis is correct by reproducing the failure mode on the current production AAB.

**Run these BEFORE Engineer starts Task 3 (code changes).**

#### PRE-REBUILD TEST 1: Confirm Current AAB Has Empty Password

**Environment:** macOS terminal

**Steps:**

```bash
cd /tmp
rm -rf aab_current
mkdir aab_current
cd aab_current
unzip -q /Users/tonyholmes/apps/bandroadie/build/app/outputs/bundle/release/app-release.aab
strings ./base/lib/arm64-v8a/libapp.so > current_strings.txt
echo "Email check:"
grep "hello@bandroadie.com" current_strings.txt && echo "✅ Email found" || echo "❌ Email missing"
echo "Password check:"
grep "BandRoadie-Demo-2026!" current_strings.txt && echo "✅ Password found" || echo "❌ Password missing"
```

**Expected result:**

```
Email check:
hello@bandroadie.com
✅ Email found
Password check:
❌ Password missing
```

**If both are found:** Root cause analysis is WRONG. Do not proceed with this plan. Escalate to Architect.

**Pass criteria:** Email found, password NOT found.

---

#### PRE-REBUILD TEST 2: Confirm Current Build Script Lacks DEMO_PASSWORD

**Environment:** Code inspection

**Steps:**

```bash
grep -n "DEMO_PASSWORD" tools/build_mobile_release.sh
```

**Expected result:** No matches (grep exits with code 1).

**If DEMO_PASSWORD is found:** The script has already been fixed. Check git history to see if this was fixed but not rebuilt. If so, skip to Task 6 (rebuild).

**Pass criteria:** `DEMO_PASSWORD` does not appear in current `build_mobile_release.sh`.

---

#### PRE-REBUILD TEST 3: Confirm gen_dart_defines.sh Includes DEMO_PASSWORD

**Environment:** Code inspection

**Steps:**

```bash
grep -A2 "DEMO_PASSWORD" tools/gen_dart_defines.sh
```

**Expected result:**

```bash
  "DEMO_PASSWORD": "${DEMO_PASSWORD:-}"
}
EOF
```

**Pass criteria:** `DEMO_PASSWORD` is in the generated JSON template.

---

### Tier 2 — Post-Rebuild Verification (New AAB Testing)

**Purpose:** Confirm the rebuilt AAB has the password compiled in and demo login works end-to-end.

**Run these AFTER Engineer completes Task 6 (new AAB built).**

#### POST-REBUILD TEST 1: Confirm New AAB Contains Password

**Environment:** macOS terminal

**Steps:**

```bash
cd /tmp
rm -rf aab_new
mkdir aab_new
cd aab_new
unzip -q /Users/tonyholmes/apps/bandroadie/build/app/outputs/bundle/release/app-release.aab
strings ./base/lib/arm64-v8a/libapp.so > new_strings.txt
echo "Email check:"
grep "hello@bandroadie.com" new_strings.txt && echo "✅ Email found" || echo "❌ Email missing"
echo "Password check:"
grep "BandRoadie-Demo-2026!" new_strings.txt && echo "✅ Password found" || echo "❌ Password missing"
```

**Expected result:**

```
Email check:
hello@bandroadie.com
✅ Email found
Password check:
BandRoadie-Demo-2026!
✅ Password found
```

**Pass criteria:** Both email AND password found in new AAB.

**If password is still missing:** Build script fix did not work. Investigate Flutter build logs. Do not proceed to QA testing.

---

#### POST-REBUILD TEST 2: Install and Test Demo Login on Physical Android Device

**Environment:** Physical Android device (not emulator — emulators may have different build artifacts)

**Prerequisites:**

- Android device with USB debugging enabled
- `adb` installed and device connected
- Device is logged OUT of BandRoadie (or app is uninstalled)

**Steps:**

1. Build and install from new AAB:
   ```bash
   # Convert AAB to APK using bundletool (or use internal testing track)
   cd /Users/tonyholmes/apps/bandroadie
   bundletool build-apks --bundle=build/app/outputs/bundle/release/app-release.aab \
     --output=/tmp/bandroadie.apks --mode=universal
   unzip -p /tmp/bandroadie.apks universal.apk > /tmp/bandroadie.apk
   adb install -r /tmp/bandroadie.apk
   ```
2. Launch BandRoadie on device
3. On login screen, tap the BandRoadie logo rapidly 7 times
4. Observe: Loading indicator appears immediately
5. Wait 2-5 seconds
6. Expected: App lands on Dashboard screen showing "The Banana Stand" band

**Pass criteria:**

- No error message displayed
- App successfully authenticates and routes to Dashboard
- Active band is "The Banana Stand"

**If demo login still fails with "Invalid login credentials":**

- Check Supabase Auth logs (dashboard → Auth → Logs) for the failed attempt
- Verify the email and password being sent (may require adding temporary debug logging to `login_screen.dart` line 177)
- Confirm Supabase production has the correct password set for `hello@bandroadie.com` (see Task 1)

**If demo login fails with different error (e.g., "Profile incomplete"):**

- Demo user may be missing profile data in `users` table
- Check: `SELECT * FROM users WHERE id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'`
- User should have `name` set (required for profile complete check)

---

#### POST-REBUILD TEST 3: Verify Normal Magic Link Auth Still Works (Regression Test)

**Environment:** Same Android device from TEST 2

**Steps:**

1. On Dashboard (logged in as demo user), tap Settings → Sign Out
2. On login screen, enter a test email (use a real email you can access): `your-test-email@example.com`
3. Tap "Send Magic Link"
4. Check email inbox on device or desktop
5. Tap magic link in email
6. Expected: App opens directly (no browser shown) and user is logged in

**Pass criteria:**

- Magic link email received
- Tapping link opens app (not browser)
- User is authenticated and routed to Dashboard or Profile setup

**If magic link fails:**

- This would indicate a regression in the Android deep link flow
- **BLOCKER:** This should NOT happen (build script change does not touch deep link code), but if it does, bisect git history to find which commit broke it
- Verify Android App Links are verified: `adb shell pm get-app-links com.bandroadie.app` should show `app.bandroadie.com` as `verified`

---

#### POST-REBUILD TEST 4: Verify Build Script Validation Gates Work

**Environment:** macOS terminal

**Purpose:** Confirm the new validation checks prevent bad builds

**Test 4a: Missing DEMO_PASSWORD**

```bash
cd /Users/tonyholmes/apps/bandroadie
# Temporarily disable DEMO_PASSWORD in .env
sed -i.bak 's/^DEMO_PASSWORD=/#DEMO_PASSWORD=/' .env
./tools/build_mobile_release.sh android-aab
# Expected: Script exits with "ERROR: DEMO_PASSWORD missing in .env"
# Restore .env
mv .env.bak .env
```

**Pass criteria:** Build fails with clear error message before `flutter build` is called.

**Test 4b: Empty DEMO_PASSWORD**

```bash
cd /Users/tonyholmes/apps/bandroadie
# Temporarily set DEMO_PASSWORD to empty
sed -i.bak 's/^DEMO_PASSWORD=.*/DEMO_PASSWORD=/' .env
./tools/build_mobile_release.sh android-aab
# Expected: Script exits with "ERROR: DEMO_PASSWORD missing in .env"
# (The -z check treats empty string as missing)
# Restore .env
mv .env.bak .env
```

**Pass criteria:** Build fails with clear error message.

---

## 16. QA Regression Areas

QA must test these areas to confirm no regression. Testing should use the new AAB from Task 6.

### Primary Test: Demo Login (Android)

**What to test:**

- Install new AAB on Android device
- Tap logo 7 times on login screen
- Verify demo login succeeds and lands in "The Banana Stand" band

**Expected result:** Demo login works. No "Invalid login credentials" error.

**Devices:** Test on at least 2 physical Android devices (different manufacturers/Android versions if possible)

---

### Regression Test: Magic Link Auth (Android)

**What to test:**

- Normal email-based magic link login on Android
- Tap magic link in email app (Gmail, Outlook, etc.)
- Verify deep link opens app directly (no browser intermediary)

**Expected result:** Magic link auth works exactly as before. No regression.

---

### Regression Test: Magic Link Auth (iOS)

**What to test:**

- Normal email-based magic link login on iOS
- Tap magic link in Mail app
- Verify deep link opens app

**Expected result:** iOS magic link auth works exactly as before. No regression.

**Rationale:** Although we only modified the Android build script, verify iOS as a sanity check. iOS build script was NOT changed.

---

### Regression Test: Demo Login (iOS)

**What to test:**

- Install current iOS build (from TestFlight or local build via Xcode)
- Tap logo 7 times on login screen
- Verify demo login succeeds

**Expected result:** iOS demo login still works. No regression.

**Rationale:** Confirm our diagnosis was correct (iOS works because its build script already passes DEMO_PASSWORD).

---

## 17. Rollout / Migration Strategy

**No database migration required.** This is a client build fix only.

**Rollout plan:**

### Phase 1: Internal Testing (Engineer + QA)

1. Engineer builds new AAB locally per Task 6
2. Engineer installs via `adb` on personal Android device, tests demo login
3. QA receives AAB file, installs on 2-3 test Android devices
4. QA executes Tier 2 verification tests (POST-REBUILD TESTS 1-4)
5. QA executes regression tests (magic link Android + iOS, demo login iOS)

**Gate:** QA must approve before Phase 2.

---

### Phase 2: Play Console Internal Testing Track

1. Upload new AAB to Play Console → Internal Testing track
2. Add 2-3 internal testers (Tony + Engineer + QA)
3. Install via Play Store (not sideload)
4. Re-verify demo login works when installed from Play Store distribution
5. Monitor for any crashes or ANRs in Play Console crashlytics

**Why this phase:** Confirms the AAB works when distributed via Play Store's signing and delivery pipeline, not just when sideloaded via `adb`.

**Duration:** 24-48 hours

**Gate:** No crashes, demo login works for all internal testers.

---

### Phase 3: Play Console Production Track Submission

1. Promote AAB from Internal Testing to Production track
2. Submit for review (Play Store review may take 1-5 days)
3. Monitor review status in Play Console

**Out of scope for this feature:** Actual production release is a business decision. This plan covers submitting the fixed AAB for review. Tony decides when to roll out to users (can be staged rollout, e.g., 10% → 50% → 100%).

---

### Rollback Plan

**If demo login still fails in production after rollout:**

1. Immediate: Verify via Play Console which APK variant users are getting (ARM64, ARMv7, x86)
2. Download the exact APK from Play Console "Release Management → App bundle explorer"
3. Inspect downloaded APK using `strings` to confirm password is present
4. If password is missing: Play Store signing process may have stripped it (unlikely but possible). Investigate Google Play App Signing settings.
5. If password is present but auth still fails: Escalate to Architect. May indicate Supabase Auth configuration issue or demo account state issue.

**Rollback AAB:** No rollback needed — old AAB has broken demo login too. If new AAB is worse, investigate and fix forward, don't roll back.

---

## 18. Out of Scope

Explicitly NOT included in this fix:

1. **Demo login on Web platform** — The 7-tap logo trigger likely does not work on web (no way to rapidly tap an image in a browser). If demo login is needed for web, a different trigger mechanism is required (e.g., keyboard shortcut, hidden URL parameter).

2. **Demo login on macOS platform** — Untested. May work if `build_mobile_release.sh` is used for macOS builds (it's not — macOS builds are typically done via Xcode). If needed, macOS build process must be documented and fixed separately.

3. **Changing demo account credentials** — The email (`hello@bandroadie.com`) and password (`BandRoadie-Demo-2026!`) are fixed for this fix. If Tony wants to rotate credentials, that's a separate change requiring updates to `.env`, Supabase Auth user, and potentially re-disclosure to Play Store reviewers.

4. **Updating Play Store App Access declaration** — If the demo credentials have changed since the last Play Store submission, Tony must update the "App access" section in Play Console with the new credentials. This is NOT a code change, it's a Play Console form update.

5. **Fixing `build_android.sh`** — There's an older `tools/build_android.sh` script that is NOT used for production builds. It's superseded by `build_mobile_release.sh`. If `build_android.sh` is still used for development builds, it may need the same fix, but that's a separate task.

6. **Migrating to `--dart-define-from-file` for all builds** — This plan uses explicit `--dart-define=DEMO_PASSWORD` to match the existing pattern in `build_mobile_release.sh`. A future refactor could switch to always using `--dart-define-from-file=dart_defines.json` for consistency with iOS, but that's a broader build system refactor, not part of this fix.

7. **Supabase password reset automation** — If the demo account password expires or is locked out (Supabase Auth password policies), it must be manually reset via dashboard. No automation is in scope.

8. **CI/CD integration** — This plan assumes local builds by Tony or Engineer. If BandRoadie moves to automated CI/CD builds (GitHub Actions, etc.), the CI environment must also have access to `.env` with `DEMO_PASSWORD`. That's a separate CI/CD setup task.

---

**END OF ARCHITECT PLAN**
