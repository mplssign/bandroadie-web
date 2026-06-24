# ARCHITECT_PLAN — demo-mode-credentials-update

---

## 1. Feature Slug

`feature/demo-mode-credentials-update`

---

## 2. Problem Summary

The demo mode (triggered by tapping the login screen logo 7 times) currently authenticates as `bandroadie2026@gmail.com`. This needs to be updated to use a dedicated demo account: `hello@bandroadie.com` (user ID `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`) belonging to band "The Banana Stand" (band ID `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`).

**CURRENT STATE (as of investigation):**

✅ **Code update complete:** [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart) already contains the new credentials  
❌ **Environment file out of sync:** `.env` still references the old account (`DEMO_EMAIL=bandroadie2026@gmail.com`, `DEMO_PASSWORD=banana-stand-demo`)  
❓ **Password verification needed:** Must confirm `hello@bandroadie.com` has a password set in Supabase Auth

The new demo user and band already exist in Supabase. No user creation or band setup logic is required — only verification that the password is configured correctly in Supabase, and updating the `.env` file to match the code.

---

## 3. Root Cause

**Confidence: HIGH**

**ORIGINAL PROBLEM (now resolved):**
The demo credentials were hardcoded in [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart) to use `bandroadie2026@gmail.com`.

**CURRENT STATE:**
The code file has been updated to the new credentials, but the `.env` file is out of sync.

**Evidence:**

- ✅ Code file (`demo_credentials.dart`) already updated:
  - `kDemoEmail = 'hello@bandroadie.com'` (line 14)
  - Band ID comment: `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` (line 9)
  - User ID comment: `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925` (line 10)

- ❌ Environment file (`.env`) still has old values:
  - `DEMO_EMAIL=bandroadie2026@gmail.com` (not used by code, but misleading)
  - `DEMO_PASSWORD=banana-stand-demo` (for old account — will fail if used with new account)

- ❓ Supabase Auth password status unknown:
  - Must verify `hello@bandroadie.com` has a password set
  - Must obtain correct password value for `.env` update

**Remaining work:**

1. Tony verifies `hello@bandroadie.com` has password auth enabled in Supabase
2. Tony updates `.env` with correct password for `hello@bandroadie.com`
3. QA verifies demo login works end-to-end

---

## 4. Reference Docs Consulted

- [docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md](docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md) — Reviewed for auth flow context; not directly relevant to demo mode (magic link vs. password auth)
- [docs/features/feature/play-store-demo-login/ARCHITECT_PLAN.md](docs/features/feature/play-store-demo-login/ARCHITECT_PLAN.md) — Original implementation of demo mode password authentication
- No dedicated demo mode reference documentation exists

---

## 4.1 Authentication Method Clarification

**BLOCKER RESOLVED — Password Auth is Intentional**

The app uses **magic link (passwordless) authentication** for all normal users. However, demo mode uses **password authentication** (`signInWithPassword`) as an intentional design decision implemented for Play Store review requirements (see `docs/features/feature/play-store-demo-login/`).

**Key facts:**

- **Demo mode uses `signInWithPassword()`** — not magic link
- **Password is injected at compile time** via `--dart-define=DEMO_PASSWORD` from `.env`
- **Current `.env` value:** `DEMO_PASSWORD=banana-stand-demo`
- **This is a parallel auth path** — does not affect normal magic link login

**Original implementation rationale (April 2026):**

> Google Play requires static test credentials (email + password) for reviewer access. Magic link auth cannot satisfy this requirement because reviewers cannot access email. The 7-tap easter egg was created to enable password-based login exclusively for reviewers without disrupting the magic link flow for real users.

**Implication for this change:**
The new demo account (`hello@bandroadie.com`) **MUST have a password set in Supabase Auth** for demo login to work. This is a prerequisite, not a code change.

---

## 5. Pre-Implementation Requirements

**CRITICAL — Tony Must Complete Before Engineer Starts:**

### Requirement 1: Verify New Demo Account Has Password Auth Enabled

**Action required:**

1. Log into Supabase Dashboard → Authentication → Users
2. Locate user `hello@bandroadie.com` (user ID `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`)
3. **Verify:** User has a password set (look for "Password" in auth methods)

**If password is NOT set:**

1. In Supabase Dashboard, set a password for `hello@bandroadie.com`
2. Choose a strong, memorable password (it will be public in Play Store App Access declaration)
3. Document the password securely

**Once password is confirmed/set:**

4. Update `.env` file:

   ```bash
   DEMO_EMAIL=hello@bandroadie.com
   DEMO_PASSWORD=<actual-password-for-hello@bandroadie.com>
   ```

5. **Notify Engineer that Requirement 1 is complete** and provide confirmation that password is set

### Requirement 2: Verify Band Membership

**Action required:**

1. In Supabase Dashboard, verify `hello@bandroadie.com` is a member of band `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` ("The Banana Stand")
2. Verify the user is **only** a member of this band (no other bands)
3. If not, update `band_members` table accordingly

**Rationale:** Demo login relies on `bands.first` auto-selection. If the user is a member of multiple bands, the wrong band may be selected.

---

**⚠️ DO NOT PROCEED TO IMPLEMENTATION UNTIL TONY CONFIRMS BOTH REQUIREMENTS ARE COMPLETE ⚠️**

---

## 6. Existing System Analysis

### 6.1 Demo Mode Trigger

**Location:** [lib/features/auth/login_screen.dart#L135-L163](lib/features/auth/login_screen.dart#L135-L163)

**Flow:**

1. User taps BandRoadie logo on login screen
2. `_handleLogoTap()` increments `_logoTapCount`
3. After 7th tap, `_triggerDemoLogin()` is called
4. Tap counter auto-resets after 3 seconds of inactivity

### 6.2 Demo Login Execution

**Location:** [lib/features/auth/login_screen.dart#L166-L200](lib/features/auth/login_screen.dart#L166-L200)

**Implementation:**

```dart
Future<void> _triggerDemoLogin() async {
  // ... loading state setup ...

  await supabase.auth.signInWithPassword(
    email: kDemoEmail,
    password: kDemoPassword,
  );

  // AuthGate handles routing after successful auth
}
```

**Key observations:**

- Uses standard Supabase `signInWithPassword` (not magic link)
- Reads credentials from constants in `demo_credentials.dart`
- No special user ID or band ID logic — relies on standard post-auth flow

### 6.3 Post-Auth Band Selection

**Location:** [lib/features/auth/auth_gate.dart#L315-L317](lib/features/auth/auth_gate.dart#L315-L317)

After successful authentication:

1. `AuthGate._checkAndProcessPendingInvite()` runs (checks for pending band invitations)
2. `activeBandProvider.notifier.loadUserBands()` is called
3. [ActiveBandNotifier.loadUserBands()](lib/features/bands/active_band_controller.dart#L257-L316) fetches all bands for the authenticated user
4. If no persisted band ID exists, `bands.first` is auto-selected
5. The selected band is persisted to `SharedPreferences`

**For the demo user:**

- The demo account should only be a member of "The Banana Stand"
- `bands.first` will always be "The Banana Stand" (no special client logic needed)

### 6.4 Credential Injection

**Email:** Hardcoded in [lib/app/constants/demo_credentials.dart#L13](lib/app/constants/demo_credentials.dart#L13)

**Password:** Injected at compile time via `--dart-define=DEMO_PASSWORD`:
Code changes:\*\* ✅ ALREADY COMPLETE — no further code modifications needed

**Remaining work:**

1. Tony verifies `hello@bandroadie.com` has password in Supabase Auth (Pre-Implementation Requirement 1)
2. Tony updates `.env` file with correct credentials (Pre-Implementation Requirement 1)
3. Engineer verifies code state matches plan expectations (no-op verification)
4. QA performs end-to-end demo login test

**No source code modifications required** — the code file already contains the correct values.
**Single file modification:**

- Update `kDemoEmail` constant from `'bandroadie2026@gmail.com'` to `'hello@bandroadie.com'`
- UpdateCurrent vs. Required State

**Code file (`lib/app/constants/demo_credentials.dart`):**

| Element         | Current Value (✅ Correct)                | Required Value                            |
| --------------- | ----------------------------------------- | ----------------------------------------- |
| `kDemoEmail`    | `'hello@bandroadie.com'`                  | `'hello@bandroadie.com'`                  |
| Band ID comment | `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`    | `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d`    |
| User ID comment | `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`    | `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925`    |
| `kDemoPassword` | `String.fromEnvironment('DEMO_PASSWORD')` | `String.fromEnvironment('DEMO_PASSWORD')` |

**Environment file (`.env`) — Tony's action required:**

| Variable        | Current Value (❌ Outdated)                | Required Value                        |
| --------------- | ------------------------------------------ | ------------------------------------- |
| `DEMO_EMAIL`    | `bandroadie2026@gmail.com`                 | `hello@bandroadie.com`                |
| `DEMO_PASSWORD` | `banana-stand-demo` (old account password) | `<password-for-hello@bandroadie.com>` |

**NoCode already updated:** The change has been applied and is awaiting verification onlyde uses `kDemoEmail` hardcoded constant), but should be updated for consistency and documentation purposes
| Field | Old Value | New Value |
| --------- | ---------------------------------------- | ---------------------------------------- |
| Email | `bandroadie2026@gmail.com` | `hello@bandroadie.com` |
| User ID | (not in code) | `4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925` |
| Band Name | The Banana Stand | The Banana Stand (unchanged) |
| Band ID | `9187f897-1731-4337-bbd3-4f80afbe88ec` | `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` |
| Password | Injected via `--dart-define` (unchanged) | Injected via `--dart-define` (unchanged) |

**Note:** The password value stored in `.env` must be updated by Tony to match the new demo account's password **before** the code change is deployed. See Section 5 (Pre-Implementation Requirements).

### 7.3 Why This Is Safe

✅ **No secrets exposed:** Email is already public (same as support email); user/band IDs are not secrets  
✅ **No logic changes:** Demo login flow remains identical  
✅ **No database changes:** New user and band already exist in Supabase  
✅ **No initialization changes:** No violation of GUARDRAILS §1  
✅ **Single-file change:** Minimal diff surface per GUARDRAILS §7

---

## 8. Database Impact

**Not applicable.**

The new demo user (`hello@bandroadie.com`) and band ("The Banana Stand") already exist in Supabase per the feature requirements. No migrations, RLS policies, or RPC functions are affected.

---

## 9. Flutter Architecture Changes

**None — code changes already complete.**

The file [lib/app/constants/demo_credentials.dart](lib/app/constants/demo_credentials.dart) has already been updated with the correct values. No further source code modifications are required.

**Engineer task:** Verify the file contains expected values (see Section 15).

- No changes to demo login trigger logic
- No changes to post-auth band selection logic
- Existing `activeBandProvider` flow handles band auto-selection identically

---

## 10. Files to Create

**None.**

---

## 11. Files to Modify

| File                                      | Change Description                                                                                                                                                     |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/constants/demo_credentials.dart` | Update `kDemoEmail` from `'bandroadie2026@gmail.com'` to `'hello@bandroadie.com'`; update comment header to reflect new band ID `e89bea44-8dd4-4e3d-b527-c0f75e94aa7d` |

---

## 12. Files Off-Limits

| File                                             | Reason                                                                   |
| ------------------------------------------------ | ------------------------------------------------------------------------ |
| `lib/features/auth/login_screen.dart`            | No changes to demo trigger logic or demo login flow                      |
| `lib/features/auth/auth_gate.dart`               | No changes to post-auth band selection                                   |
| `lib/features/bands/active_band_controller.dart` | No changes to band auto-selection logic                                  |
| `lib/main.dart`                                  | Init order must not change (GUARDRAILS §1)                               |
| `.env`                                           | Password update is Tony's pre-implementation requirement (see Section 5) |
| `run.sh`, `tools/build_*.sh`                     | No changes to `--dart-define` injection logic                            |
| All other files                                  | No changes needed                                                        |

---

## 13. System Impact Map

| System             | Impact     | Rationale                                                            |
| ------------------ | ---------- | -------------------------------------------------------------------- |
| Authentication     | Unaffected | Uses same `signInWithPassword` flow; only credential values change   |
| Bands              | Unaffected | Standard band auto-selection applies; no special logic for demo user |
| Gigs / Rehearsals  | Unaffected | Band-scoped data loads normally after band selection                 |
| Setlists / Catalog | Unaffected | Band-scoped data loads normally after band selection                 |
| Members / RBAC     | Unaffected | Permissions load based on authenticated user's role in selected band |
| Routing            | Unaffected | `AuthGate` routing logic unchanged                                   |
| Notifications      | Unaffected | Push token registration occurs for any authenticated user            |
| Profile            | Unaffected | User profile loads from `users` table based on auth session          |

---

## 14. Regression Risk

**Risk Level: LOW**

**Rationale:**

- IMPORTANT:\*\* The code changes have already been implemented. This is a verification-only task.

**Task 1: Verify demo email constant**

- **File:** `lib/app/constants/demo_credentials.dart`
- **Action:** Confirm line 14 reads:
  ```dart
  const String kDemoEmail = 'hello@bandroadie.com';
  ```
- **Expected:** Value is already correct (no change needed)

**Task 2: Verify comment header — band ID**

- **File:** `lib/app/constants/demo_credentials.dart`
- **Action:** Confirm line 9 reads:
  ```dart
  // Demo band: The Banana Stand (band_id: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d)
  ```
- **Expected:** Value is already correct (no change needed)

**Task 3: Verify comment — user ID**

- **File:** `lib/app/constants/demo_credentials.dart`
- **Action:** Confirm line 10 reads:
  ```dart
  // Demo user ID: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925
  ```
- **Expected:** Value is already correct (no change needed)

**Task 4: Run flutter analyze**

- **Command:** `flutter analyze`
- **Expected:** 0 errors, 0 warnings

**Task 5: Write ENGINEER_REPORT.md**

- **Location:** `docs/features/demo-mode-credentials-update/ENGINEER_REPORT.md`
- **Content:**
  - Confirm all verification tasks completed
  - Note that no code changes were required (already updated)
  - Include `git diff` output (should show no changes to source files)
  - Document that `.env` update is Tony's responsibility (out of scope for Engineer)
  ```

  ```

**Task 3: Update comment to include user ID**

- **File:** `lib/app/constants/demo_credentials.dart`
- **Action:** Add a new comment line after line 9 (before the blank line):
  ```dart
  // Demo user ID: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925
  ```

**Task 4: Run flutter analyze**

- **Command:** `flutter analyze`
- **Expected:** 0 errors, 0 warnings

**Task 5: Write ENGINEER_REPORT.md**

- **Location:** `docs/features/demo-mode-credentials-update/ENGINEER_REPORT.md`
- **Content:** Confirm all tasks completed, list modified files, include `git diff` output

---

## 16. Verification Plan

### Tier 1 — Pre-Deployment (Static Verification)

Not applicable (no database changes).

### Tier 2 — Post-Deployment (Client Verification)

**TEST 1 — Verify constant updated:**

```bash
grep -n "kDemoEmail" lib/app/constants/demo_credentials.dart
```

**Expected output:**

```
13:const String kDemoEmail = 'hello@bandroadie.com';
```

**TEST 2 — Verify comment updated:**

```bash
grep -n "e89bea44-8dd4-4e3d-b527-c0f75e94aa7d" lib/app/constants/demo_credentials.dart
```

**Expected output:**

```
9:// Demo band: The Banana Stand (band_id: e89bea44-8dd4-4e3d-b527-c0f75e94aa7d)
```

**TEST 3 — Verify user ID documented:**

```bash
grep -n "4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925" lib/app/constants/demo_credentials.dart
```

**Expected output:**

```
10:// Demo user ID: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925
```

**TEST 4 — Verify no references to old email remain:**

```bash
grep -r "bandroadie2026" lib/ --include="*.dart"
```

**Expected output:** No matches (or only matches in unrelated comment/doc strings)

**TEST 5 — Flutter analyze passes:**

```bash
flutter analyze
```

**Expected:** 0 errors

---

## 17. QA Regression Areas

### Primary Verification

**Demo Mode Login — End-to-End (iOS / macOS / Android / Web):**

1. Open BandRoadie on a clean session (logged out)
2. Tap the BandRoadie logo 7 times rapidly
3. Observe: Loading indicator appears
4. **Expected:** Successfully logged in as `hello@bandroadie.com`
5. **Expected:** Active band is "The Banana Stand"
6. **Expected:** Dashboard loads with band's gigs, rehearsals, and setlists visible
7. Navigate to Profile → verify email is `hello@bandroadie.com`
8. Navigate to Band Settings → verify band name is "The Banana Stand"

**Demo Mode Trigger Behavior:**

1. Open login screen
2. Tap logo 6 times → observe: no login triggered
3. Wait 3+ seconds (tap counter should reset)
4. Tap logo 6 times again → observe: no login triggered
5. Tap logo 7 times rapidly (within 3 seconds) → observe: demo login triggered

**Error Handling:**

1. If `.env` has incorrect/missing `DEMO_PASSWORD`, demo login should fail gracefully with error message: "Demo login failed. Please try again." (or "Demo login failed: <specific Supabase error>")

### Regression Verification

**Normal Login Flow (must remain unaffected):**

1. Normal magic link login (without 7 taps) → verify: works as expected
2. Sign out and sign in with different account → verify: correct user/band loaded

**Auth Gate Flow:**

1. After demo login, sign out → verify: returns to login screen (no stuck state)
2. After demo login, navigate to all tabs (Dashboard, Calendar, Setlists, Members, Settings) → verify: no crashes or permission errors

---

## 18. Rollout / Migration Strategy

**Not applicable.**

This is a client-side credential update. No backend deployment, migration, or rollout coordination required.

**Prerequisites verified before implementation:**

- Tony has confirmed `hello@bandroadie.com` has password auth enabled in Supabase (Section 5, Requirement 1)
- Tony has updated `.env` with new credentials (Section 5, Requirement 1)
- Tony has confirmed band membership is correct (Section 5, Requirement 2)

**Deployment:**
After QA approval, rebuild and redeploy all platforms that include demo mode (Play Store / App Store / TestFlight / Web) using the updated `.env` file.

---

## 19. Out of Scope

**Explicitly NOT included in this change:**

❌ Creating the new demo user in Supabase (already exists per feature requirements)  
❌ Creating "The Banana Stand" band in Supabase (already exists per feature requirements)  
❌ Setting password for `hello@bandroadie.com` in Supabase Auth (Tony's pre-implementation requirement — see Section 5)  
❌ Updating `.env` file's `DEMO_EMAIL` and `DEMO_PASSWORD` values (Tony's pre-implementation requirement — see Section 5)  
❌ Modifying demo trigger logic (7-tap behavior remains unchanged)  
❌ Changing demo login flow (still uses `signInWithPassword`)  
❌ Updating historical documentation in `docs/features/feature/play-store-demo-login/` (those are historical records of past work)  
❌ Adding demo mode reference documentation (could be added later as separate feature)  
❌ Changing post-auth band selection logic (existing auto-selection is sufficient)

---

**ARCHITECT PLAN COMPLETE**
