# ARCHITECT_PLAN — Remove Hardcoded Credentials from Git History and Source Code

**Slug:** `feature/remove-credentials-from-git-history`
**Branch:** `feature/remove-credentials-from-git-history`
**Date:** 2026-04-01 (revised 2026-04-02)
**Regression Risk:** HIGH
**Priority:** CRITICAL — active production credential exposure confirmed and partially resolved

---

## 0. Live Exposure Verification

**Confirmed 2026-04-01 via curl:**

```
$ curl -s https://app.bandroadie.com/assets/.env
SUPABASE_URL=https://nekwjxvgbveheooyorjo.supabase.co
SUPABASE_ANON_KEY=<REDACTED — key rotated>
```

**Resolved 2026-04-02:** `.env` removed from `pubspec.yaml` assets (commit `9e7d59e`). Emergency deploy completed. Both production domains now return 404 for `/assets/.env`. Supabase anon key rotated and new key deployed.

---

## 1. Problem Summary

Four credential exposure problems exist in the repository:

1. **`.env` bundled as a Flutter asset** — ~~CRITICAL~~ **RESOLVED** — `pubspec.yaml` asset entry removed (commit `9e7d59e`), emergency deploy completed 2026-04-02. `.env` no longer served at `/assets/.env`.

2. **`.env` (root) tracked in git** — contains real Supabase URL and anon key. Currently tracked by git on `main` despite being listed in `.gitignore`. The `.gitignore` entry was added after initial commit, so git continues tracking the file. Present in git history since commit `58c0094`.

3. **`android/app/src/main/assets/public/assets/.env`** — contains identical Supabase credentials. Tracked on `main`. Not gitignored.

4. **`lib/main.dart` lines 79–86** — hardcoded Firebase web config in a `FirebaseOptions(...)` block with plaintext `apiKey`, `authDomain`, `projectId`, `storageBucket`, `messagingSenderId`, `appId`, and `measurementId`.

A prior removal attempt (commit `c5384b6` on branch `pro/lyrics`) was never merged to `main`.

---

## 2. Existing System Analysis

### Supabase Config Loading (Needs Modification)

`lib/app/supabase_config.dart` implements a two-tier pattern:

1. `String.fromEnvironment('SUPABASE_URL')` — compile-time `--dart-define` (highest priority)
2. `dotenv.env['SUPABASE_URL']` — runtime `.env` fallback via `flutter_dotenv`

The dotenv fallback is the root cause of the original asset bundling requirement. Removing the fallback and switching to `--dart-define` only eliminates the need for `.env` as a bundled asset entirely.

### Firebase Config Loading (No Pattern Exists)

`lib/main.dart` directly constructs `FirebaseOptions(...)` with hardcoded string literals for web builds. There is no `--dart-define` injection path for Firebase credentials. Native builds (iOS/Android) use platform config files (`GoogleService-Info.plist`, `google-services.json`), which are standard client distribution files and not a security issue.

### flutter_dotenv Usage (Isolated to One File)

`flutter_dotenv` is used only in `lib/app/supabase_config.dart`:

- `import 'package:flutter_dotenv/flutter_dotenv.dart';`
- `dotenv.env['SUPABASE_URL']` (line 25)
- `dotenv.env['SUPABASE_ANON_KEY']` (line 36)
- `dotenv.load(fileName: '.env')` (line 43)

No other Dart file imports or uses dotenv. Removing it is a clean, isolated change.

### Build/Deploy Process

- Local: `flutter run -d <platform>` — currently `.env` provides Supabase creds natively. After this change, `--dart-define` required for all platforms.
- Web release: `flutter build web --release` → `vercel --prod` from `build/web/`.
- `deploy_web.sh` already updated to source `.env` and pass `SUPABASE_URL` and `SUPABASE_ANON_KEY` as `--dart-define` flags.
- `COMMIT_SHA` is already injected via `--dart-define` for web builds (see `app_version_service.dart`).

### Initialization Order (Must Not Change)

Per `GUARDRAILS.md`, the init sequence is:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. URL strategy
3. Portrait lock
4. `AppVersionService.init()`
5. `loadEnvConfig()` ← **will be removed** — dotenv is being eliminated
6. `validateSupabaseConfig()`
7. `Supabase.initialize()`
8. `Firebase.initializeApp()` ← Firebase credentials consumed here
9. `DeepLinkService` setup
10. `runApp()`

The init order must remain unchanged except for the removal of step 5. The remaining sequence is preserved.

---

## 3. Root Cause

**Root Cause Confidence: HIGH** — directly confirmed in code, git state, and live production curl.

| Issue                    | Root Cause                                                                                                     |
| ------------------------ | -------------------------------------------------------------------------------------------------------------- |
| **Live web exposure**    | **RESOLVED** — `.env` removed from `pubspec.yaml` assets, emergency deploy completed                           |
| `.env` in git            | File committed in initial commit (`58c0094`). `.gitignore` added later but `git rm --cached` never run         |
| Android `.env` copy      | Same — committed early, never untracked, not in `.gitignore`                                                   |
| Firebase hardcoded creds | No externalized config pattern for Firebase. Values inlined in `main.dart`                                     |
| dotenv dependency        | `flutter_dotenv` reads `.env` at runtime, requiring it as a bundled asset. Root cause of original web exposure |
| History exposure         | No git history rewrite performed. Credentials remain in all historical commits                                 |

---

## 4. Proposed Solution

### ~~Part F — Rotate Supabase Anon Key~~ **DONE**

Completed 2026-04-02. New publishable key (`flutter_prod`) created and deployed. Old `flutter_2025` key deleted from Supabase dashboard. New key live in production.

### ~~Part E (sub-task 1) — Remove `.env` from pubspec.yaml assets~~ **DONE**

Completed 2026-04-02, commit `9e7d59e`. Emergency deploy confirmed closed the web exposure.

**Remaining Part E tasks (Engineer implements):**

- Remove `flutter_dotenv: ^6.0.0` from `pubspec.yaml` dependencies
- Rewrite `lib/app/supabase_config.dart` to `--dart-define` only (remove dotenv import, fallbacks, and `loadEnvConfig()`)
- Remove `await loadEnvConfig();` from `lib/main.dart`
- Update `validateSupabaseConfig()` error messages to reference `--dart-define` only

### Part B — Externalize Firebase Web Credentials

Create `lib/app/firebase_config.dart` using `--dart-define` only. No dotenv fallback. No `flutter_dotenv` import.

- Define getters for each Firebase field using `String.fromEnvironment()` only.
- Provide a `firebaseWebOptions` getter returning `FirebaseOptions(...)` constructed from these getters.
- Provide a `validateFirebaseWebConfig()` function returning an error string if any required field is empty (web only).

Modify `lib/main.dart` lines 78–87:

- Replace the hardcoded `FirebaseOptions(...)` block with `firebaseWebOptions`.
- Add import for `firebase_config.dart`.
- Add `validateFirebaseWebConfig()` call before `Firebase.initializeApp()` on web.

### Part A — Remove Tracked `.env` Files from Git Index

1. Run `git rm --cached .env` — file stays on disk.
2. Run `git rm --cached android/app/src/main/assets/public/assets/.env` — file stays on disk.
3. Add `android/app/src/main/assets/public/assets/.env` to `.gitignore`.
4. Commit on this feature branch.

### Part C — Developer Ergonomics and Documentation

1. Update `.env.example` with all `--dart-define` keys (Supabase + Firebase) and full command examples.
2. Create `run.sh` — reads `.env` on disk and passes values as `--dart-define` flags to `flutter run`. Replaces the ergonomics of the removed dotenv runtime fallback.
3. `run.sh` must be added to `.gitignore` — not committed to the repo.

**`run.sh` wrapper:**

```bash
#!/usr/bin/env bash
# Reads .env from disk and passes values as --dart-define flags.
# Usage: ./run.sh macos | ios | chrome
set -e
DEVICE=${1:-macos}
set -a
source "$(dirname "$0")/.env"
set +a
flutter run -d "$DEVICE" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY}" \
  --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
  --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID}" \
  --dart-define=FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID}"
```

### Part D — Purge Git History (Manual Step — Tony Executes, Post-Merge)

1. Back up the repository.
2. Run BFG Repo Cleaner:
   ```bash
   bfg --delete-files .env
   git reflog expire --expire=now --all
   git gc --prune=now --aggressive
   ```
3. Force-push the rewritten history.
4. All collaborators must re-clone or hard-reset.

**The Engineer agent must NOT perform Part D.**

---

## 5. Database Impact

Not applicable. No schema, RLS, RPC, trigger, or migration changes.

---

## 6. RLS / RPC Changes

None.

---

## 7. Flutter Architecture Changes

**New file:** `lib/app/firebase_config.dart` — Firebase credential getters via `--dart-define` only. No dotenv dependency.

**Modified file:** `lib/app/supabase_config.dart` — Remove all `flutter_dotenv` references. Simplify to `--dart-define` only. Remove `loadEnvConfig()`.

**New file:** `run.sh` — Convenience wrapper for local development. Not bundled into builds. Not committed to git.

**Removed dependency:** `flutter_dotenv` from `pubspec.yaml`.

**Init order change:** `await loadEnvConfig()` removed from `main.dart`. Remaining sequence is unchanged. `GUARDRAILS.md` init sequence documentation must be updated to remove step 5.

---

## 8. Exact Files to Create

| File                           | Purpose                                                                                                     |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| `lib/app/firebase_config.dart` | Firebase credential getters via `--dart-define`, `firebaseWebOptions` getter, `validateFirebaseWebConfig()` |
| `run.sh`                       | Convenience wrapper: sources `.env`, passes values as `--dart-define` to `flutter run`. Gitignored.         |

---

## 9. Exact Files to Modify

| File                           | What Changes                                                                                                                                            |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pubspec.yaml`                 | ~~Remove `.env` from `assets:`~~ **DONE**. Remove `flutter_dotenv: ^6.0.0` from dependencies                                                            |
| `lib/app/supabase_config.dart` | Remove `flutter_dotenv` import. Remove `dotenv.env[]` fallbacks. Remove `loadEnvConfig()`. Update error messages                                        |
| `lib/main.dart`                | Remove `await loadEnvConfig()`. Import `firebase_config.dart`. Replace hardcoded `FirebaseOptions` with `firebaseWebOptions`. Add web config validation |
| `.gitignore`                   | Add `android/app/src/main/assets/public/assets/.env`. Add `run.sh`                                                                                      |
| `.env.example`                 | Add Firebase placeholder keys. Add full `--dart-define` command examples. Remove dotenv runtime references                                              |
| `tools/deploy_web.sh`          | Add Firebase `--dart-define` flags to build command. Add Firebase key validation guards                                                                 |
| `docs/agents/GUARDRAILS.md`    | Remove `loadEnvConfig()` from documented init sequence                                                                                                  |

**Git index changes (not file content):**

- `git rm --cached .env`
- `git rm --cached android/app/src/main/assets/public/assets/.env`

---

## 10. Risks / Edge Cases

| Risk                                                    | Mitigation                                                                                                                             |
| ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| **All platforms break if `--dart-define` not provided** | `validateSupabaseConfig()` provides clear error. `run.sh` injects flags automatically for local dev                                    |
| **Vercel/deploy_web.sh builds**                         | `deploy_web.sh` already sources `.env` for Supabase flags. Firebase flags must also be added to `deploy_web.sh` as part of this plan   |
| **Firebase init fails silently**                        | Existing try/catch handles failures. `validateFirebaseWebConfig()` adds early warning on web                                           |
| **`.env` deleted from disk during `git rm --cached`**   | `git rm --cached` only removes from index. Verify file exists after operation                                                          |
| **`const` keyword on FirebaseOptions**                  | With `--dart-define` only, all `String.fromEnvironment()` values are compile-time constants. `const FirebaseOptions(...)` is preserved |
| **`flutter_dotenv` removal breaks pubspec resolution**  | Run `flutter clean && flutter pub get` after pubspec changes                                                                           |
| **History rewrite coordination**                        | Part D is manual and Tony-executed. Collaborators must re-clone. Document in plan                                                      |
| **Native Firebase config files (plist/json) in git**    | Standard client distribution files per Firebase documentation. Out of scope                                                            |

---

## 11. Verification Plan

### Engineer Validation Commands

```bash
# Verify .env is no longer tracked
git ls-files -- .env
# Expected: empty output

git ls-files -- android/app/src/main/assets/public/assets/.env
# Expected: empty output

# Verify .env still exists on disk
ls -la .env
# Expected: file exists

# Verify no hardcoded Firebase credentials in main.dart
grep -n "AIzaSy\|bandroadie-65b18\|119100589120\|efcfb0cdf1501488" lib/main.dart
# Expected: empty output

# Verify no dotenv imports remain
grep -rn "flutter_dotenv\|dotenv" lib/ --include="*.dart"
# Expected: empty output

# Verify .env not in pubspec.yaml assets
grep -A 5 "assets:" pubspec.yaml | grep "\.env"
# Expected: empty output

# Verify flutter_dotenv not in pubspec.yaml
grep "flutter_dotenv" pubspec.yaml
# Expected: empty output

# Verify loadEnvConfig removed from main.dart
grep "loadEnvConfig" lib/main.dart
# Expected: empty output

# Clean rebuild
flutter clean && flutter pub get

# Code analysis
flutter analyze
# Expected: 0 errors

# Web build with dart-define
flutter build web --release \
  --dart-define=SUPABASE_URL=https://nekwjxvgbveheooyorjo.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=test-key \
  --dart-define=FIREBASE_API_KEY=test \
  --dart-define=FIREBASE_AUTH_DOMAIN=test \
  --dart-define=FIREBASE_PROJECT_ID=test \
  --dart-define=FIREBASE_STORAGE_BUCKET=test \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=test \
  --dart-define=FIREBASE_APP_ID=test \
  --dart-define=FIREBASE_MEASUREMENT_ID=test
# Expected: build succeeds

# Verify .env NOT in build output
ls build/web/assets/.env 2>/dev/null
# Expected: No such file or directory
```

### Post-Deploy Verification (Tony)

```bash
curl -s -o /dev/null -w "%{http_code}" https://bandroadie.com/assets/.env
# Expected: 404

curl -s -o /dev/null -w "%{http_code}" https://app.bandroadie.com/assets/.env
# Expected: 404
```

### QA Regression Areas

- App initialization on web (Firebase + Supabase)
- App initialization on iOS/Android (Firebase via native config, Supabase via `--dart-define`)
- App initialization on macOS (Supabase via `--dart-define`)
- Push notification registration (depends on Firebase init)
- Auth flow (depends on Supabase init)

---

## 12. Engineer Task Breakdown

**Execution order matters.**

| #     | Task                                                                                                                                                                            | Files                                | Part           |
| ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | -------------- |
| ~~1~~ | ~~Remove `.env` from `assets:` in `pubspec.yaml`~~                                                                                                                              | ~~`pubspec.yaml`~~                   | ~~E~~ **DONE** |
| 2     | Remove `flutter_dotenv: ^6.0.0` from `pubspec.yaml` dependencies                                                                                                                | `pubspec.yaml`                       | E              |
| 3     | Rewrite `lib/app/supabase_config.dart`: remove `flutter_dotenv` import, remove `dotenv.env[]` fallbacks, remove `loadEnvConfig()`, update error messages                        | `lib/app/supabase_config.dart`       | E              |
| 4     | Create `lib/app/firebase_config.dart` with `--dart-define` getters (no dotenv fallback), `firebaseWebOptions` getter, `validateFirebaseWebConfig()`                             | `lib/app/firebase_config.dart` (new) | B              |
| 5     | Update `lib/main.dart`: remove `await loadEnvConfig()`, import `firebase_config.dart`, replace hardcoded `FirebaseOptions` with `firebaseWebOptions`, add web config validation | `lib/main.dart`                      | E+B            |
| 6     | Add Firebase `--dart-define` flags and validation guards to `tools/deploy_web.sh`                                                                                               | `tools/deploy_web.sh`                | C              |
| 7     | Run `flutter clean && flutter pub get`                                                                                                                                          | —                                    | E              |
| 8     | Run `flutter analyze` — must pass with 0 errors                                                                                                                                 | —                                    | E+B            |
| 9     | Run `git rm --cached .env` and `git rm --cached android/app/src/main/assets/public/assets/.env`                                                                                 | Git index only                       | A              |
| 10    | Add `android/app/src/main/assets/public/assets/.env` and `run.sh` to `.gitignore`                                                                                               | `.gitignore`                         | A+C            |
| 11    | Update `.env.example` with Firebase placeholder keys and full `--dart-define` command documentation                                                                             | `.env.example`                       | C              |
| 12    | Create `run.sh` wrapper script                                                                                                                                                  | `run.sh` (new)                       | C              |
| 13    | Update `docs/agents/GUARDRAILS.md` init sequence — remove `loadEnvConfig()` step                                                                                                | `GUARDRAILS.md`                      | E              |
| 14    | Verify `.env` still exists on disk and is no longer tracked                                                                                                                     | —                                    | A              |
| 15    | Verify `lib/main.dart` contains no hardcoded credential values                                                                                                                  | —                                    | B              |
| 16    | Verify no `dotenv` imports remain in any Dart file                                                                                                                              | —                                    | E              |
| 17    | Verify `.env` is not in `build/web/assets/` after web build                                                                                                                     | —                                    | E              |

**Part D (Tony-only, post-merge):**

| #   | Task                                                                      |
| --- | ------------------------------------------------------------------------- |
| D1  | Back up repository                                                        |
| D2  | `bfg --delete-files .env`                                                 |
| D3  | `git reflog expire --expire=now --all && git gc --prune=now --aggressive` |
| D4  | Force-push rewritten history                                              |
| D5  | Notify collaborators to re-clone                                          |

---

## 13. Rollout / Migration Strategy

**Phase 1 — Emergency (COMPLETE):**

- Removed `.env` from `pubspec.yaml` assets — committed `9e7d59e`
- Rotated Supabase anon key, deployed new key
- Web exposure confirmed closed

**Phase 2 — This Feature Branch (Engineer implements):**

- Remove `flutter_dotenv` dependency
- Rewrite `supabase_config.dart` to `--dart-define` only
- Create `firebase_config.dart`
- Update `main.dart`
- Update `deploy_web.sh` with Firebase `--dart-define` flags
- Untrack `.env` files from git index
- Update `.gitignore`, `.env.example`, `run.sh`, `GUARDRAILS.md`
- Deploy via `deploy_web.sh`

**Phase 3 — Purge Git History (Tony executes, post-merge):**

- BFG history rewrite
- Force-push
- Collaborator re-clone

**Phase 4 — Post-Rewrite Hardening:**

- Consider restricting Firebase API key in Google Cloud Console (authorized domains)

---

## 14. Out of Scope

- Native Firebase config files (`GoogleService-Info.plist`, `google-services.json`) — standard client distribution files, not secrets
- Firebase API key restriction in Google Cloud Console — separate security decision
- CI/CD pipeline setup — no automated CI exists
- Vercel build automation — builds are manual
- Changes to initialization order beyond removing `loadEnvConfig()`
- Supabase anon key rotation — DONE

---

## 15. Widget Contracts (Public API)

No widget changes. Config-layer change only.

---

## 16. Data Flow Architecture

### Before (Original State)

```
main.dart
  ├─ loadEnvConfig()          → dotenv loads .env (bundled asset)
  ├─ supabaseUrl              → dart-define > .env fallback
  ├─ supabaseAnonKey          → dart-define > .env fallback
  └─ FirebaseOptions(...)     → HARDCODED literals
```

### After (This Branch)

```
main.dart
  ├─ (loadEnvConfig removed)
  ├─ supabaseUrl              → dart-define only  (supabase_config.dart)
  ├─ supabaseAnonKey          → dart-define only  (supabase_config.dart)
  └─ firebaseWebOptions       → dart-define only  (firebase_config.dart)
```

No dotenv. No bundled `.env`. No hardcoded literals. Init order unchanged minus the removed step.

---

## 17. Exact Code Locations

### `lib/main.dart` — Lines to Modify

**Remove (line ~45):**

```dart
await loadEnvConfig();
```

**Replace hardcoded FirebaseOptions (lines 78–87):**

```dart
// REMOVE:
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyD3nIWOdtwNuSkggGs_4Du_rsfvsd7qHxo',
          authDomain: 'bandroadie-65b18.firebaseapp.com',
          projectId: 'bandroadie-65b18',
          storageBucket: 'bandroadie-65b18.firebasestorage.app',
          messagingSenderId: '119100589120',
          appId: '1:119100589120:web:efcfb0cdf1501488c3cba5',
          measurementId: 'G-QFC8JXHKDC',
        ),
      );

// REPLACE WITH:
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: firebaseWebOptions,
      );
```

**Add import:**

```dart
import 'app/firebase_config.dart';
```

### `lib/app/firebase_config.dart` — New File

`--dart-define` only. No dotenv import. No runtime fallback.

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// All values injected at compile time via --dart-define.
// No runtime .env fallback — flutter_dotenv has been removed.

const FirebaseOptions firebaseWebOptions = FirebaseOptions(
  apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
  authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
  projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
  messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
  appId: String.fromEnvironment('FIREBASE_APP_ID'),
  measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID'),
);

String? validateFirebaseWebConfig() {
  if (!kIsWeb) return null;
  const fields = {
    'FIREBASE_API_KEY': String.fromEnvironment('FIREBASE_API_KEY'),
    'FIREBASE_AUTH_DOMAIN': String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    'FIREBASE_PROJECT_ID': String.fromEnvironment('FIREBASE_PROJECT_ID'),
    'FIREBASE_STORAGE_BUCKET': String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    'FIREBASE_MESSAGING_SENDER_ID': String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    'FIREBASE_APP_ID': String.fromEnvironment('FIREBASE_APP_ID'),
  };
  final missing = fields.entries
      .where((e) => e.value.isEmpty)
      .map((e) => e.key)
      .toList();
  if (missing.isEmpty) return null;
  return 'Missing Firebase --dart-define values: ${missing.join(', ')}';
}
```

### `lib/app/supabase_config.dart` — Pattern After Modification

Remove all `flutter_dotenv` references. `--dart-define` only:

```dart
// REMOVE:
import 'package:flutter_dotenv/flutter_dotenv.dart';
// dotenv.env['SUPABASE_URL'] fallback
// dotenv.env['SUPABASE_ANON_KEY'] fallback
// loadEnvConfig() function entirely

// RESULT: supabaseUrl and supabaseAnonKey use String.fromEnvironment() only
// validateSupabaseConfig() error messages updated to reference --dart-define only
```

### `.gitignore` — Add Lines

```
android/app/src/main/assets/public/assets/.env
run.sh
```

### `.env.example` — Firebase Placeholders and Command Reference

```
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-publishable-key

# Firebase Web (Firebase Console > Project Settings > Web app)
FIREBASE_API_KEY=your-firebase-api-key
FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_STORAGE_BUCKET=your-project.firebasestorage.app
FIREBASE_MESSAGING_SENDER_ID=your-sender-id
FIREBASE_APP_ID=your-firebase-app-id
FIREBASE_MEASUREMENT_ID=G-XXXXXXXXXX

# Local dev: ./run.sh macos
# Web build: see deploy_web.sh (sources this file automatically)
```

### `tools/deploy_web.sh` — Updated Build Command

```bash
# Add these validation guards in the "Load credentials" section:
[[ -z "${FIREBASE_API_KEY:-}" ]] && fail "FIREBASE_API_KEY not set in .env"
[[ -z "${FIREBASE_APP_ID:-}" ]] && fail "FIREBASE_APP_ID not set in .env"

# Updated flutter build command:
flutter build web \
  --release \
  --pwa-strategy=none \
  --dart-define=BUILD_TIMESTAMP=$BUILD_TS \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY}" \
  --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID}" \
  --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID}" \
  --dart-define=FIREBASE_MEASUREMENT_ID="${FIREBASE_MEASUREMENT_ID}" \
  || fail "Flutter build failed"
```
