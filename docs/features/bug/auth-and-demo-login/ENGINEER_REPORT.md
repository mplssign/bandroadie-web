# Engineer Report

## Feature Slug

bug/auth-and-demo-login

## Feature Title

Auth and Demo Login Fixes

## Goal

Fix three independent authentication-related bugs: (1) Android magic link loop caused by redirect URL mismatch, (2) iOS crash after auth due to missing mounted guard in auth state listener, and (3) Demo login failure due to missing DEMO_PASSWORD in dart_defines.json.

## Architect Tasks Completed

- [x] Task 1 — Fix Android Magic Link Deep Linking (Issue 1)
  - Updated `supabase/config.toml` to list correct redirect URLs matching platform-specific code paths
  - Replaced stale URLs with: `https://app.bandroadie.com/auth/confirm` (web), `https://app.bandroadie.com/auth/callback` (Android), `bandroadie://login-callback/` (iOS/macOS)
- [x] Task 2 — Fix iOS Post-Auth Crash (Issue 2)
  - Added `if (!mounted) return;` guard in `auth_gate.dart` listener callback before any `setState()` calls
  - Guard placed immediately after debugPrint and before auth state change handling
- [x] Task 3 — Fix Demo Login (Issue 3)
  - Added `"DEMO_PASSWORD": "${DEMO_PASSWORD:-}"` to `tools/gen_dart_defines.sh` JSON output
  - Regenerated `dart_defines.json` to include DEMO_PASSWORD value
  - Verified DEMO_PASSWORD is present in generated file

## Files Created

- none

## Files Modified

- `supabase/config.toml` (line 50) — Updated `additional_redirect_urls` array
- `lib/features/auth/auth_gate.dart` (line 147) — Added mounted guard in listener callback
- `tools/gen_dart_defines.sh` (line 37) — Added DEMO_PASSWORD to JSON output
- `dart_defines.json` (regenerated) — Now includes DEMO_PASSWORD

## Analyzer Results

Command: `flutter analyze`
Result: **0 errors, 0 warnings**

```
Analyzing bandroadie...
No issues found! (ran in 5.6s)
```

## Test Results

Not run — Architect plan specifies manual testing only (physical device required for deep link and crash verification).

## Verification

Manual steps performed:

- ✅ Confirmed `supabase/config.toml` contains all three correct redirect URLs
- ✅ Confirmed `lib/features/auth/auth_gate.dart` has `if (!mounted) return;` guard before first `setState` in listener callback
- ✅ Confirmed `tools/gen_dart_defines.sh` includes DEMO_PASSWORD in JSON output
- ✅ Ran `./tools/gen_dart_defines.sh` successfully
- ✅ Verified `dart_defines.json` contains `"DEMO_PASSWORD": "BandRoadie-Demo-2026!"`
- ✅ Ran `flutter analyze` — 0 errors
- ✅ Formatted changed Dart file with `dart format`

## Deviations From Architect Plan

None — All changes implemented exactly as specified in ARCHITECT_PLAN.md "Files to Modify" section.

## Blockers Encountered

None — All three tasks completed without issues.

## Manual Steps Required (Critical)

### Issue 1 — Android Magic Link

**Before deployment**, Engineer must:

1. Log into Supabase production dashboard: https://supabase.com/dashboard/project/nekwjxvgbveheooyorjo
2. Navigate to: Authentication → URL Configuration → Redirect URLs
3. Verify/update the redirect URLs list to include:
   - `https://app.bandroadie.com/auth/confirm` (web)
   - `https://app.bandroadie.com/auth/callback` (Android)
   - `bandroadie://login-callback/` (iOS/macOS)
4. Remove stale URLs if present:
   - `https://app.bandroadie.com` (missing path)
   - `https://bandroadie.com` (missing path)
   - `com.bandroadie.app://callback` (old custom scheme)
5. Save changes in Supabase dashboard

**Note:** The local `supabase/config.toml` file has been updated, but production Supabase configuration is managed via the web dashboard and must be verified/updated manually.

### Issue 3 — Demo Login

**Before marking resolved**, Engineer must:

1. Log into Supabase production dashboard
2. Navigate to: Authentication → Users
3. Verify user `bandroadie2026@gmail.com` exists with correct password
4. Verify user is a member of "The Banana Stand" band (band_id: `9187f897-1731-4337-bbd3-4f80afbe88ec`)
5. If user does not exist, it must be recreated manually before demo login will work

## Ready For QA

**Yes** — All code changes complete and verified. Ready for QA testing on physical devices.

**QA Prerequisites:**

- Physical Android device (for magic link deep linking verification — emulator cannot test Android App Links)
- Physical iPhone (for crash testing — lifecycle behavior differs from simulator)
- Production Supabase dashboard verification (manual steps above must be completed first)

**Primary QA Tests Required:**

1. Android magic link end-to-end flow (tap link in email → app opens directly)
2. iOS magic link flow (cold start and warm resume scenarios — verify no crash)
3. Demo login (tap logo 7 times on both platforms)
