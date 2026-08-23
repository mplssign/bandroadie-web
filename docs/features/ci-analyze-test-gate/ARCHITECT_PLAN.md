# ARCHITECT_PLAN.md

## Feature Slug

`feature/ci-analyze-test-gate`

---

## Problem Summary

BandRoadie has no automated quality gate in CI. Despite having 24 test files covering UI components (buttons, dialogs, text fields), setlist parsing, event dropdowns, and feedback email generation, nothing enforces that `flutter analyze` or `flutter test` pass before code merges to `main`.

The only GitHub Actions workflow (`.github/workflows/weekly_backup.yml`) runs a weekly PostgreSQL backup cron. No workflow runs on push or pull request events.

This was flagged as the single most important gap in the 2026-08-04 Production Readiness Review. Since that review, the test suite has grown from 6 to 24 files, but none of it is enforced. A broken test or a new analyzer error can merge to `main` today with nothing catching it automatically.

This matters more than usual for BandRoadie specifically because the documented project history indicates QA sessions in this pipeline cannot reliably do interactive/device verification — static analysis and unit tests are the only mechanical safety net available, and it currently doesn't exist.

---

## Root Cause

**No GitHub Actions workflow exists to run `flutter analyze` and `flutter test` on push or pull request events.**

**Confidence Level:** `HIGH`

Confirmed via direct workspace inspection:

- Only one workflow file exists: `.github/workflows/weekly_backup.yml` (backup-only cron)
- File search for `.github/workflows/*.yml` returns exactly one result
- 24 test files confirmed to exist in `test/` directory
- `Makefile` contains an `analyze:` target (`flutter analyze`) but nothing invokes it in CI

---

## Reference Docs Consulted

Not applicable — this is a CI/tooling feature with no domain-specific reference requirements. The override note in the session input correctly identified that Phase 4's "Load Notification Domain Reference" requirement does not apply to this feature.

---

## Existing System Analysis

### Current CI Pipeline

- **Workflows:** Single workflow (`weekly_backup.yml`) runs weekly PostgreSQL dump to Google Drive
- **Quality gates:** None — no analyze, no test, no linting runs on push or PR
- **Test coverage:** 24 test files exist covering:
  - UI components (`test/components/ui/`)
  - Feature logic (`test/features/setlists/services/bulk_song_parser_test.dart`, `test/features/events/widgets/event_dropdown_test.dart`)
  - Utilities (`test/features/feedback/bug_report_email_test.dart`)
- **Makefile integration:** `analyze:` target defined but unused in CI

### Data Flow

No data flow — this is CI infrastructure only. The new workflow will:

1. Trigger on push to `main` or PR targeting `main`
2. Check out code
3. Setup Flutter stable channel
4. Install dependencies (`flutter pub get`)
5. Run analyzer (`flutter analyze`)
6. Run tests (`flutter test`)
7. Fail the check if either analyzer or test step exits non-zero

---

## Proposed Solution

Create a new GitHub Actions workflow file: `.github/workflows/flutter_ci.yml`

**Workflow configuration:**

- **Name:** "Flutter CI"
- **Triggers:**
  - `push` to `main` branch
  - `pull_request` targeting `main` branch
- **Job:** `analyze-and-test`
- **Runner:** `ubuntu-latest`
- **Steps:**
  1. Checkout code (`actions/checkout@v4`)
  2. Setup Flutter (`subosito/flutter-action@v2` with `channel: stable`)
  3. Install dependencies (`flutter pub get`)
  4. Run analyzer (`flutter analyze`)
  5. Run tests (`flutter test`)

**Why this solves the problem:**

- Mechanically enforces code quality before merge
- Catches regressions in the 24-file test suite that are currently unmonitored
- Aligns with the Production Readiness Review's top priority
- Uses stable Flutter channel (no pinned version exists in repo, so stable is the safe default per `pubspec.yaml` SDK constraint `">=3.3.0 <4.0.0"`)

**Why `--fatal-infos` is NOT included in this first pass:**

- The current analyzer warning baseline has not been verified (Flutter is not on PATH in the diagnostic environment used during this session)
- Enabling `--fatal-infos` blind risks blocking every future PR on pre-existing debt unrelated to this change
- The Engineer will discover the real baseline during Phase 5 verification
- Escalating to `--fatal-infos` is an explicit, separate follow-up task after the baseline is known

**Why no dart-defines are needed:**

- `flutter analyze` and `flutter test` do not require runtime config (Supabase URL, anon key)
- These commands analyze/test source code statically, not connected services

---

## Database Impact

**Not applicable** — this is a CI/tooling feature with no database changes.

- Migrations: Not required
- RLS policies: Not affected
- RPC functions: Not affected
- Triggers: Not affected
- Edge functions: Not affected

---

## Flutter Architecture Changes

**None** — no application code is modified.

This feature touches only CI infrastructure (`.github/workflows/` directory). No Dart files, no state management, no widgets, no repositories are affected.

---

## Files to Create

| File                               | Justification                                                                             |
| ---------------------------------- | ----------------------------------------------------------------------------------------- |
| `.github/workflows/flutter_ci.yml` | Required to enable CI quality gate — no existing workflow runs analyze/test on push or PR |

---

## Files to Modify

**None** — the solution requires only one new file.

---

## Files Off-Limits

| File                                  | Reason                                                   |
| ------------------------------------- | -------------------------------------------------------- |
| `.github/workflows/weekly_backup.yml` | Unrelated backup workflow — must not be modified         |
| `Makefile`                            | Already has `analyze:` target — no changes needed        |
| `lib/**`                              | Application code — not touched by CI-only feature        |
| `test/**`                             | Test files — not modified, only executed by new workflow |
| `pubspec.yaml`                        | Dependencies — no new packages required                  |

---

## System Impact Map

| System                                 | Impact     |
| -------------------------------------- | ---------- |
| Gigs                                   | unaffected |
| Rehearsals                             | unaffected |
| Setlists / Catalog                     | unaffected |
| Members / RBAC                         | unaffected |
| Auth / Session                         | unaffected |
| Routing                                | unaffected |
| Notifications                          | unaffected |
| Platform (iOS / Android / Web / macOS) | unaffected |

**Rationale:** This is CI infrastructure only. No application code, database schema, or runtime behavior is modified.

---

## Regression Risk

**Level:** `LOW`

**Rationale:**

- Zero application code changes
- Zero database changes
- New workflow only observes code quality (analyze/test), does not modify runtime behavior
- Existing `weekly_backup.yml` workflow is untouched and continues to run independently
- Worst case: workflow misconfiguration causes CI to fail, but does not affect the deployed app or user experience
- No platform-specific logic, no auth changes, no init order changes, no RLS changes

**Risk mitigation:**

- The Engineer will verify the workflow runs successfully on the feature branch before merge
- The first CI run may fail if pre-existing analyzer warnings or test failures exist — this is expected and desirable (it surfaces the real baseline)
- If the first run fails, the Engineer must report exactly what failed and whether it's pre-existing debt or a real issue introduced by the workflow itself

---

## Engineer Task Breakdown

Execute in strict order:

### Task 1: Create Flutter CI Workflow File

- Create `.github/workflows/flutter_ci.yml` with the following structure:
  - Name: "Flutter CI"
  - Triggers: `push` to `main`, `pull_request` targeting `main`
  - Job: `analyze-and-test` on `ubuntu-latest`
  - Steps:
    1. `actions/checkout@v4` (checkout code)
    2. `subosito/flutter-action@v2` with `channel: stable` (setup Flutter)
    3. `flutter pub get` (install dependencies)
    4. `flutter analyze` (run static analysis)
    5. `flutter test` (run test suite)
- Ensure each step that can fail (`flutter analyze`, `flutter test`) causes the job to fail if it exits non-zero (this is the default GitHub Actions behavior — explicitly document it if overriding with `continue-on-error`)

### Task 2: Verify Workflow Syntax

- Validate YAML syntax using `yamllint` or GitHub's workflow validator (via commit to feature branch and checking Actions tab)
- Confirm the workflow file is in the correct directory (`.github/workflows/`)
- Confirm the workflow file has the `.yml` extension (not `.yaml` — GitHub Actions supports both, but existing workflow uses `.yml`)

### Task 3: Test Workflow Execution

- Push the feature branch to trigger the workflow
- Observe the Actions tab in GitHub to confirm the workflow runs
- Document the outcome:
  - If `flutter analyze` passes: note pass, capture any warnings
  - If `flutter analyze` fails: report exact errors (filename, line number, message)
  - If `flutter test` passes: note pass, capture test count
  - If `flutter test` fails: report exact failures (test name, assertion, stack trace)
- If the workflow fails due to pre-existing issues (analyzer warnings elevated to errors, failing tests), this is expected — document it explicitly in ENGINEER_REPORT.md and do NOT attempt to fix the underlying issues (that is out of scope)

### Task 4: Generate ENGINEER_REPORT.md

- Document completion of all tasks
- Include workflow execution results from Task 3
- Report the real analyzer/test baseline discovered during verification
- Note any pre-existing issues that surfaced (if any)
- Confirm `flutter analyze` exit code and `flutter test` exit code
- Include `git diff` output showing the new workflow file

---

## Verification Plan

### Tier 1 — Pre-deployment (not applicable)

**This feature has no deployment step** — it is CI infrastructure only. There is no database migration, no Supabase edge function, no client code deploy.

Skip Tier 1 entirely.

---

### Tier 2 — Post-implementation Verification

Run after the feature branch is created and the workflow file is committed.

#### Test 1: Workflow File Exists and Is Discoverable

**Goal:** Confirm GitHub Actions can find and parse the workflow.

**Steps:**

1. Push the feature branch to GitHub
2. Navigate to the repository's "Actions" tab in the GitHub UI
3. Confirm "Flutter CI" appears in the workflow list (left sidebar)
4. Confirm the workflow shows as enabled (not disabled/grayed out)

**Expected outcome:** Workflow is visible and enabled.

---

#### Test 2: Workflow Triggers on Push

**Goal:** Confirm the workflow runs when code is pushed to `main` or a PR is opened targeting `main`.

**Steps:**

1. Push the feature branch (which is not `main`) — workflow should NOT run
2. Open a pull request targeting `main` — workflow SHOULD run
3. Observe the Actions tab for a new workflow run
4. Click into the run and confirm all steps execute in order:
   - Checkout
   - Setup Flutter
   - Install dependencies
   - Run analyzer
   - Run tests

**Expected outcome:** Workflow runs automatically on PR creation, all steps execute.

---

#### Test 3: Analyzer Step Reports Correctly

**Goal:** Confirm `flutter analyze` runs and reports its exit status correctly.

**Steps:**

1. In the workflow run from Test 2, expand the "Run analyzer" step
2. Read the output logs
3. Confirm the step shows exit code (0 for pass, non-zero for fail)
4. If analyzer fails, document the specific errors reported (file, line, message)

**Expected outcome:** Analyzer step completes and reports pass/fail. If it fails due to pre-existing warnings, this is expected — do NOT attempt to fix them in this feature.

---

#### Test 4: Test Step Reports Correctly

**Goal:** Confirm `flutter test` runs and reports test results correctly.

**Steps:**

1. In the workflow run from Test 2, expand the "Run tests" step
2. Read the output logs
3. Confirm the step shows:
   - Number of tests run
   - Number of tests passed
   - Number of tests failed (if any)
   - Exit code (0 for all pass, non-zero for any failure)
4. If tests fail, document the specific test names and assertions that failed

**Expected outcome:** Test step completes and reports pass/fail. If tests fail due to pre-existing issues, this is expected — do NOT attempt to fix them in this feature.

---

#### Test 5: Workflow Fails Check on Analyzer Failure (Negative Test)

**Goal:** Confirm the workflow correctly fails the CI check if `flutter analyze` fails.

**Steps:**

1. In a separate temporary branch (NOT the feature branch), introduce an intentional analyzer error:
   - Add `import 'dart:nonexistent';` to `lib/main.dart`
2. Commit and push the temporary branch
3. Open a PR targeting `main`
4. Observe the Actions tab
5. Confirm the workflow run fails at the "Run analyzer" step
6. Confirm the PR shows a failed check (red X)
7. Delete the temporary branch (do NOT merge)

**Expected outcome:** Workflow fails, PR check fails, error is reported in logs.

---

#### Test 6: Workflow Fails Check on Test Failure (Negative Test)

**Goal:** Confirm the workflow correctly fails the CI check if `flutter test` fails.

**Steps:**

1. In a separate temporary branch (NOT the feature branch), introduce an intentional test failure:
   - Modify `test/widget_test.dart` to have a failing assertion (e.g., `expect(1, equals(2))`)
2. Commit and push the temporary branch
3. Open a PR targeting `main`
4. Observe the Actions tab
5. Confirm the workflow run fails at the "Run tests" step
6. Confirm the PR shows a failed check (red X)
7. Delete the temporary branch (do NOT merge)

**Expected outcome:** Workflow fails, PR check fails, test failure is reported in logs.

---

#### Test 7: Existing Weekly Backup Workflow Unaffected

**Goal:** Confirm the new workflow does not interfere with the existing `weekly_backup.yml` workflow.

**Steps:**

1. Navigate to the Actions tab
2. Confirm both workflows are listed:
   - "Flutter CI"
   - "Weekly Database Backup"
3. Confirm "Weekly Database Backup" is still scheduled (cron: `0 10 * * 0`)
4. Confirm the last run of "Weekly Database Backup" (if any) completed successfully

**Expected outcome:** Both workflows coexist independently. The backup workflow remains scheduled and functional.

---

### Baseline Discovery (Engineer Responsibility)

The Engineer must report in ENGINEER_REPORT.md:

1. **Analyzer baseline:** Does `flutter analyze` pass or fail on the feature branch?
   - If it passes: report "0 issues" and any warnings logged
   - If it fails: report exact errors (file, line, message)
   - Note: If it fails due to pre-existing issues, this is expected — document them but do NOT fix them in this feature

2. **Test baseline:** Does `flutter test` pass or fail on the feature branch?
   - If it passes: report number of tests run and "all pass"
   - If it fails: report which tests fail and why
   - Note: If it fails due to pre-existing issues, this is expected — document them but do NOT fix them in this feature

3. **First CI run outcome:** What happened when the workflow ran for the first time on the PR?
   - Did both steps pass?
   - Did one or both steps fail?
   - If either failed, was it due to pre-existing debt or a workflow misconfiguration?

This baseline report informs the follow-up decision on whether to escalate to `--fatal-infos` in a future feature.

---

## QA Regression Areas

QA must verify:

### Primary Verification

1. **New workflow exists and runs:**
   - Navigate to the repository's Actions tab
   - Confirm "Flutter CI" workflow is listed and enabled
   - Confirm the workflow ran on the PR for this feature
   - Confirm all steps executed (checkout, setup, pub get, analyze, test)

2. **Workflow reports pass/fail correctly:**
   - Review the workflow run logs
   - Confirm `flutter analyze` step shows exit code and output
   - Confirm `flutter test` step shows test count and exit code
   - Confirm the PR check (green checkmark or red X) matches the workflow outcome

3. **Negative test: workflow fails on bad code:**
   - QA creates a temporary branch with an intentional analyzer error
   - Opens a PR targeting `main`
   - Confirms the workflow fails and the PR shows a failed check
   - Deletes the temporary branch

4. **Existing workflow unaffected:**
   - Confirm `weekly_backup.yml` is still present and unchanged
   - Confirm the backup workflow's schedule is intact (cron: `0 10 * * 0`)
   - Confirm no interference between the two workflows

### Baseline Documentation

5. **Real baseline captured:**
   - Review ENGINEER_REPORT.md for the analyzer/test baseline
   - Confirm the Engineer documented:
     - Whether `flutter analyze` passed or failed
     - Whether `flutter test` passed or failed
     - Any pre-existing issues discovered
   - If the first run failed, confirm it was due to pre-existing debt (not workflow misconfiguration)

### No Regression

6. **Application behavior unchanged:**
   - This is CI-only — no application code was modified
   - No user-facing behavior should change
   - No database changes, no API changes, no UI changes
   - QA confirms the app still builds and runs on at least one platform (macOS or web)

---

## Rollout / Migration Strategy

**Not applicable** — this is CI infrastructure only.

There is no migration, no deployment, no rollback plan required. The workflow takes effect immediately upon merge to `main` and will run on all subsequent pushes and PRs.

If the workflow causes issues (e.g., false positives blocking PRs), it can be disabled or deleted by removing `.github/workflows/flutter_ci.yml` in a follow-up commit.

---

## Out of Scope

Explicitly NOT included in this feature:

1. **Enabling `--fatal-infos` for `flutter analyze`:**
   - The current analyzer warning baseline is unverified
   - Escalating to `--fatal-infos` is a separate follow-up task after the Engineer reports the real baseline
   - Rationale: Enabling it blind risks blocking every PR on pre-existing debt unrelated to this change

2. **Fixing pre-existing analyzer warnings or test failures:**
   - If the first CI run discovers pre-existing issues, the Engineer must document them but NOT fix them
   - Fixing pre-existing issues is out of scope for this feature
   - Rationale: This feature's scope is to enable the quality gate, not to resolve existing debt

3. **Code coverage reporting:**
   - No code coverage tool integration (e.g., `codecov`, `coveralls`)
   - Rationale: Not requested in the feature input, adds complexity without immediate value

4. **Build verification (platform artifacts):**
   - The workflow does not run `flutter build macos`, `flutter build web`, etc.
   - Rationale: Not requested, and build verification requires platform-specific secrets/config

5. **Integration tests or end-to-end tests:**
   - The workflow runs only unit tests (`flutter test`)
   - No Appium, no Selenium, no device-based testing
   - Rationale: Not requested, and the project history indicates interactive/device verification is unreliable in this pipeline

6. **Scheduled workflow runs (cron):**
   - The new workflow runs on push/PR only, not on a schedule
   - Rationale: Not requested, and the existing `weekly_backup.yml` already handles scheduled tasks

7. **Custom Flutter version pinning:**
   - The workflow uses `channel: stable` without a specific version pin
   - Rationale: No `.fvmrc` or pinned version exists in the repo, so stable is the safe default
   - If version pinning is needed, it's a separate follow-up task

---

**END OF ARCHITECT_PLAN.md**
