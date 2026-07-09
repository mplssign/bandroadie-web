# ARCHITECT_PLAN — bug/deploy-web-ephemeral-perm

## 1. Feature Slug

`bug/deploy-web-ephemeral-perm`

---

## 2. Problem Summary

`deploy_web.sh` fails during dependency resolution with error "Unable to delete file or directory at `/Users/tonyholmes/apps/bandroadie/ios/Flutter/ephemeral/Packages/.packages`. This may be due to the project being in a read-only volume."

The script exits with code 1 before completing the web build, blocking the deploy pipeline. The error is misleading — the volume is not read-only, and the issue is not iOS-specific despite the path.

**Trigger:** Running `git checkout main` → `git pull` → `./tools/deploy_web.sh` leaves the iOS ephemeral directory in a state that conflicts with Flutter's dependency resolution cleanup logic.

**Impact:** Blocks web deployment pipeline. Not currently blocking a release — discovered incidentally.

---

## 3. Root Cause

**Confidence:** MEDIUM

**Diagnosis:**

The error "Unable to delete file or directory at `/Users/tonyholmes/apps/bandroadie/ios/Flutter/ephemeral/Packages/.packages`" occurs during Flutter's dependency resolution cleanup phase, triggered by commands that implicitly run dependency resolution (`flutter analyze`, `flutter test`, `flutter build web`).

**What is confirmed:**

- `ios/Flutter/ephemeral/Packages/.packages` is a directory (not a file) containing symlinks to iOS platform plugin packages — this is normal modern Flutter behavior
- `deploy_web.sh` does **not** run `flutter clean` before building
- `build_mobile_release.sh` **does** run `flutter clean` explicitly (line 129)
- Manually deleting `.packages` and running `flutter pub get` succeeds (directory recreates cleanly)
- The error was not reproducible via `git checkout main` → `git pull` → `flutter pub get` during diagnosis

**What is speculative:**

The underlying cause of the deletion failure is unknown. The error message "read-only volume" is misleading — the volume is not read-only. Possible causes (unconfirmed):

- Intermittent filesystem state or timing issue after `git checkout/pull`
- macOS extended attributes (`com.apple.provenance` observed on `.packages`) interfering with deletion
- Flutter SDK ephemeral cleanup logic bug (version-specific, unconfirmed)
- File locking or process holding handle to symlinks in `.packages/`

The error occurred once during the reported sequence but was not reproduced during diagnosis. Without reproduction, the exact trigger remains unconfirmed.

**Why `flutter clean` is proposed as a mitigation:**

- `flutter clean` uses `rm -rf` on `build/` and `.dart_tool/` and all platform ephemeral directories
- This bypasses Flutter's incremental ephemeral cleanup logic (which is what failed)
- `build_mobile_release.sh` has used `flutter clean` successfully for 6+ months without reporting this error
- Side benefit: Guarantees fresh dependency resolution state after `git pull`

---

## 4. Reference Docs Consulted

Not applicable. This is a Flutter tooling / build pipeline issue, not a BandRoadie domain feature. No reference docs in `docs/reference/` apply.

---

## 5. Existing System Analysis

**Current `deploy_web.sh` flow (lines 187–233):**

1. Load credentials from `.env`
2. Preflight checks (branch validation, uncommitted changes check)
3. Sync version (bump build number, commit, push)
4. **Run `flutter analyze`** ← implicit dependency resolution, no clean
5. **Run `flutter test`** (if not skipped) ← implicit dependency resolution
6. **Run `flutter build web`** ← implicit dependency resolution
7. Deploy to Vercel

**Current `build_mobile_release.sh` flow (lines 118–135):**

1. Load credentials from `.env`
2. **Run `flutter clean`** ← explicitly cleans build/ and .dart_tool/ and all ephemeral directories
3. Run `flutter build ipa|appbundle|apk`
4. Verify artifact contains production config

**The gap:**

`deploy_web.sh` skips `flutter clean`, relying on incremental builds for speed. This works most of the time but leaves the iOS ephemeral directory in an inconsistent state after `git pull`, triggering the deletion failure during dependency resolution.

---

## 6. Proposed Solution (Mitigation)

Add `flutter clean` to `deploy_web.sh` **immediately before the analyze step**, matching the pattern already established in `build_mobile_release.sh`.

**This is a mitigation, not a confirmed root-cause fix.** `flutter clean` bypasses Flutter's incremental ephemeral cleanup path (which is where the deletion failure occurs) by using `rm -rf` on all ephemeral directories. The underlying cause in Flutter's cleanup logic remains unconfirmed.

**Rationale for this mitigation:**

- Minimal change: 3 lines (echo, flutter clean, echo)
- Proven pattern: `build_mobile_release.sh` already uses this approach successfully for 6+ months without this error
- Bypasses the failing incremental cleanup: Forces full regeneration of ephemeral state via `rm -rf`
- Side benefit: Guarantees build artifacts are not contaminated by prior builds or git state
- Low risk: If this does not prevent recurrence, it at least narrows the diagnostic space

**Alternative considered and rejected:**

- **Alt 1:** Only clean iOS ephemeral directory: `rm -rf ios/Flutter/ephemeral`
  - Rejects: Too surgical. Leaves other ephemeral state (Android, macOS) potentially stale. Inconsistent with mobile build pattern.
- **Alt 2:** Run explicit `flutter pub get` before analyze
  - Rejects: Does not solve the root cause. `pub get` recreates the directory that may fail to delete on the next invocation.

**Change location:**

`tools/deploy_web.sh`, immediately after the version commit step (after line 196) and before the analyze step (before line 203).

**Exact insertion:**

```bash
# ─────────────────────────────────────────────────────────────
# Clean build environment
# ─────────────────────────────────────────────────────────────

step "Cleaning build environment"

flutter clean

ok "Build environment clean"

# ─────────────────────────────────────────────────────────────
```

---

## 7. Database Impact

**Status:** Not applicable.

This is a build tooling fix. No database tables, RLS policies, RPC functions, migrations, triggers, or Supabase edge functions are involved.

---

## 8. Flutter Architecture Changes

**Status:** Not applicable.

No Dart source code, widgets, controllers, providers, repositories, or models are modified. This is a shell script change only.

---

## 9. Files to Create

None.

---

## 10. Files to Modify

| File                  | What changes                                                                                                                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools/deploy_web.sh` | Add `flutter clean` step with section header and status messages, inserted after version commit (line 196) and before analyze step (line 203). Matches the pattern in `build_mobile_release.sh` line 126–130. |

---

## 11. Files Off-Limits

| File                                             | Reason                                                                                                                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tools/build_mobile_release.sh`                  | Already correct. Contains `flutter clean` at line 129.                                                                                                                    |
| `tools/deploy_web.sh` (except specified section) | Only modify the insertion point between version commit and analyze. Do not alter flag parsing, credential loading, build args, Vercel deploy logic, or rollback handling. |
| `.gitignore`                                     | Already correct. `ios/Flutter/ephemeral/` is excluded on line 52.                                                                                                         |
| `ios/Podfile`                                    | Not related to root cause.                                                                                                                                                |
| `pubspec.yaml`                                   | Not related to root cause.                                                                                                                                                |
| Any Dart source files                            | Not related to root cause.                                                                                                                                                |

---

## 12. System Impact Map

| System                                 | Impact                                                                                      |
| -------------------------------------- | ------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                  |
| Rehearsals                             | unaffected                                                                                  |
| Setlists / Catalog                     | unaffected                                                                                  |
| Members / RBAC                         | unaffected                                                                                  |
| Auth / Session                         | unaffected                                                                                  |
| Routing                                | unaffected                                                                                  |
| Notifications                          | unaffected                                                                                  |
| Platform (iOS / Android / Web / macOS) | **Web deployment pipeline affected** — fix ensures clean builds; no runtime behavior change |

---

## 13. Regression Risk

**Level:** LOW

**Rationale:**

- Single-line functional change: adding `flutter clean`
- Proven pattern: already used successfully in `build_mobile_release.sh` for 6+ months
- No source code changes
- No dependency version changes
- No config model changes
- Side effect: Deploy will take ~10–15 seconds longer due to clean + full pub get + full build, but this is acceptable for production deploys
- Benefit: Bypasses entire class of "stale ephemeral state" issues, guarantees reproducible builds

**Risk areas (all LOW probability):**

| Risk                                                           | Mitigation                                                                                                                      |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `flutter clean` fails (disk full, permission issue)            | Script already uses `set -euo pipefail` — will halt immediately with visible error. No partial-clean state.                     |
| Vercel timeout due to longer build time                        | Current deploy completes in ~60–90s. Adding ~15s for clean is well within Vercel's 45min timeout for Hobby plan. Not a concern. |
| Version bump commit happens before clean, creating dirty state | Not possible. Version commit happens at line 196. Clean happens after commit is pushed. Git state is clean before and after.    |
| Mitigation does not prevent recurrence of original error       | If error recurs, follow escalation path in Section 17. Mitigation narrows diagnostic space even if not fully effective.         |

---

## 14. Engineer Task Breakdown

Execute in strict order:

1. **Open `tools/deploy_web.sh` in editor**
2. **Locate line 196** (end of version commit section: `git push origin main`)
3. **Locate line 203** (start of analyze section: `step "Running flutter analyze"`)
4. **Insert 9 lines between these two sections** (after blank line following `git push`, before blank line preceding analyze step):

   ```bash
   # ─────────────────────────────────────────────────────────────
   # Clean build environment
   # ─────────────────────────────────────────────────────────────

   step "Cleaning build environment"

   flutter clean

   ok "Build environment clean"

   ```

5. **Verify formatting:** Ensure separator lines align with existing sections (78 hyphens), `step` and `ok` calls match existing style
6. **Run `shellcheck tools/deploy_web.sh`** — confirm 0 errors
7. **Run `bash -n tools/deploy_web.sh`** — confirm syntax is valid
8. **Manual test (dry-run):** Run `./tools/deploy_web.sh --preview` from a clean `main` branch — confirm clean step executes and build succeeds
9. **Produce git diff:** `git diff tools/deploy_web.sh > ENGINEER_REPORT_diff.txt`
10. **Document in `ENGINEER_REPORT.md`:** Confirm task completion, no deviations, ready for QA

---

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before commit)

**T1-1: Shellcheck validation**

```bash
shellcheck tools/deploy_web.sh
# Expected: 0 errors, 0 warnings
```

**T1-2: Bash syntax validation**

```bash
bash -n tools/deploy_web.sh
# Expected: silent (no output = syntax valid)
```

**T1-3: Verify insertion location**

```bash
# Line numbers should be approximately:
# - Line ~196: git push origin main
# - Lines ~198–206: new clean section
# - Line ~208: step "Running flutter analyze"

grep -n "flutter clean" tools/deploy_web.sh
# Expected: single match at line ~204
```

**T1-4: Compare with mobile build pattern**

```bash
grep -A2 -B2 "flutter clean" tools/build_mobile_release.sh
grep -A2 -B2 "flutter clean" tools/deploy_web.sh
# Expected: both show "Cleaning build environment" → flutter clean → "Build environment clean" (or equivalent)
```

**T1-5: Verify no other changes**

```bash
git diff tools/deploy_web.sh | grep -E '^\+|^\-' | grep -v "Clean" | grep -v "flutter clean"
# Expected: no output (only clean-related lines changed)
```

---

### Tier 2 — Post-deployment (run after commit)

**T2-1: Preview deploy dry-run**

```bash
# From clean main branch with no uncommitted changes
git checkout main
git pull
./tools/deploy_web.sh --preview
# Expected:
# - "Cleaning build environment" message appears
# - "flutter clean" runs (observe .dart_tool/ and build/ deletion)
# - "Build environment clean" message appears
# - flutter analyze runs
# - flutter test runs (or skipped if --skip-tests)
# - flutter build web runs
# - Vercel preview deploy succeeds
# - No "Unable to delete file or directory" error
```

**T2-2: Verify clean happens before analyze**

```bash
./tools/deploy_web.sh --preview 2>&1 | grep -E "(Cleaning|Running flutter analyze)" | head -2
# Expected output (order matters):
# ▸ Cleaning build environment
# ▸ Running flutter analyze
```

**T2-3: Smoke test with ephemeral state present**

```bash
# This is a smoke test, NOT a reproduction of the original error.
# The original error was not reproducible during diagnosis.
git checkout main
git pull
# Let pub get create ephemeral state
flutter pub get
# Verify .packages directory exists
ls -la ios/Flutter/ephemeral/Packages/.packages/
# Run deploy with mitigation (should succeed due to clean)
./tools/deploy_web.sh --preview
# Expected: succeeds, no "Unable to delete file or directory" error
# Note: This only verifies the mitigation (clean) works in the non-failure case.
# If the original error was intermittent, this test may not trigger it.
```

**T2-4: Production deploy**

```bash
# ONLY run this after QA APPROVED and Manager authorization
git checkout main
git pull
./tools/deploy_web.sh
# Expected: full production deploy succeeds, alias updated, deployment URL recorded
```

**T2-5: Post-deploy smoke test**

```bash
# Verify deployed web app
# 1. Open https://app.bandroadie.com in incognito
# 2. Confirm landing page loads
# 3. Confirm login flow works (magic link)
# 4. Confirm setlist page loads for authenticated user
# 5. Check browser console for errors
```

---

## 16. QA Regression Areas

QA must explicitly test:

1. **Primary:** `deploy_web.sh` completes successfully without "Unable to delete file or directory" error
2. **Primary:** Clean step executes and deletes `build/` and `.dart_tool/` directories before build
3. **Primary:** Web build produces correct artifacts in `build/web/`
4. **Secondary:** Deployed web app loads correctly at https://app.bandroadie.com (smoke test)
5. **Secondary:** Auth flow works (magic link)
6. **Secondary:** Setlist operations work (load, edit, reorder)
7. **Regression:** `build_mobile_release.sh` still works correctly (clean step not broken)
8. **Regression:** Deploy time increase is acceptable (~10–15s increase, confirm with timer)

---

## 17. Rollout / Migration Strategy

Not applicable. This is a build script change only. No data migration, no backend deployment, no user-facing feature flag.

**Deployment sequence:**

1. Merge PR to `main`
2. Pull latest `main` locally
3. Run `./tools/deploy_web.sh` — the script uses itself, so the mitigation is applied immediately
4. Monitor deployment logs for clean step execution

**Rollback:**

If the change causes unforeseen issues:

```bash
git revert <commit-sha>
git push origin main
./tools/deploy_web.sh --rollback <previous-deployment-url>
```

The Vercel alias can be rolled back instantly via `--rollback` flag without code changes.

---

### Escalation Path if Error Recurs

**If the "Unable to delete file or directory" error occurs again after this mitigation ships:**

This disproves the mitigation and indicates a deeper issue in Flutter's ephemeral cleanup logic or macOS filesystem behavior. If recurrence happens:

1. **Immediately capture diagnostic state** before cleaning manually:

   ```bash
   ls -lO@ ios/Flutter/ephemeral/Packages/.packages
   stat -f "%Sp %Sf %Su %Sg %z %N" ios/Flutter/ephemeral/Packages/.packages
   lsof | grep ".packages" | head -20
   ps aux | grep -E "flutter|dart" | grep -v grep
   ```

   Save full output to a diagnostic file for review.

2. **Search Flutter SDK GitHub issues** for known bugs matching "Unable to delete file or directory" + "ephemeral" + "Packages" or ".packages"

3. **Check Flutter SDK source** for ephemeral cleanup logic:
   - `<FLUTTER_ROOT>/packages/flutter_tools/lib/src/ios/` (iOS-specific cleanup)
   - `<FLUTTER_ROOT>/packages/flutter_tools/lib/src/flutter_plugins.dart` (plugin resolution)

4. **Escalate to Tony with:**
   - Full diagnostic output from step 1
   - Confirmation of Flutter SDK version at time of error
   - Any GitHub issues found in step 2
   - Recommendation: file Flutter SDK bug report if no known issue exists

**Alternative mitigation (only if recurrence confirmed):**

Add explicit permission reset before `flutter clean`:

```bash
chmod -R u+w ios/Flutter/ephemeral 2>/dev/null || true
flutter clean
```

This would bypass macOS file flag issues (e.g., `uchg`/`schg`) if present.

---

## 18. Out of Scope

Explicitly not part of this fix:

- Optimizing deploy time (clean adds ~10–15s, acceptable tradeoff for correctness)
- Upgrading Flutter version
- Fixing the 86 outdated-package warnings (informational, not errors)
- Cleaning Android or macOS ephemeral directories explicitly (flutter clean handles all platforms)
- Investigating why Flutter creates `.packages` as a directory instead of a file (Flutter SDK behavior, outside BandRoadie control)
- Removing iOS platform dependencies from web builds (Flutter requires all platform plugins to be resolved even for web targets)
- Changing the config injection model (constraint: must continue reading `.env` and injecting via `--dart-define`)
- Modifying `.gitignore` (already correct)
- Adding `.gitattributes` file (not needed)
- Running `pod install` explicitly (not needed)

---

**Plan complete. Ready for Engineer implementation.**
