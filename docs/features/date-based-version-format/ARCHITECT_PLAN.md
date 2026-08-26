# ARCHITECT PLAN — Date-Based Version Format

## 1. Feature Slug

`feature/date-based-version-format`

## 2. Problem Summary

BandRoadie currently uses single-field semver in `pubspec.yaml` (`MAJOR.MINOR.PATCH+BUILD`), and the deploy/version-sync automation assumes that pattern across web and mobile. The desired behavior is to switch the publicly visible version to date-based `YY.M.D` while keeping the single source of truth in `pubspec.yaml` and generating a separate build integer that follows the exact date-based formula provided by the Manager.

This change is not just cosmetic: the version-sync scripts, the live web version metadata, and the in-app version display must all remain synchronized while the build number remains monotonically increasing across releases, including multiple releases on the same calendar date.

## 3. Root Cause

The root cause is the shared version-sync logic in `tools/generate_version.sh`, `tools/build_web.sh`, and `tools/deploy_web.sh`. All three parse `pubspec.yaml` with a semver regex (`version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)`) and increment only the trailing build integer, which is incompatible with the new `YY.M.D+BUILD` scheme.

This causes the release tooling to preserve the wrong semantics: the display version is treated as semver instead of a date-derived marketing string, and the build number is treated as a linear integer instead of a date-aware counter with same-day rollover logic. The bug is systemic and is present at the production release orchestration layer, not in the Flutter runtime code.

Confidence: HIGH

## 4. Reference Docs Consulted

- No files under `docs/reference/notifications/` were present for this feature, and the change does not rely on the notification domain. This is a versioning/release pipeline feature rather than a notification system fix.
- Direct code review of:
  - `pubspec.yaml`
  - `tools/generate_version.sh`
  - `tools/build_web.sh`
  - `tools/deploy_web.sh`
  - `lib/app/services/app_version_service.dart`
  - `lib/app/services/version_check_service.dart`
  - Android/iOS build metadata sources as documented in the feature input and project setup notes

## 5. Existing System Analysis

### Current versioning model

The app is currently driven by a single `version:` field in `pubspec.yaml`.

Example observed in the workspace:

- `version: 1.4.6+246`
- `web/version.json` reads the semver `version` and the numeric `build_number`
- Flutter-generated platform metadata is driven by the generated values at build time from this field

### Current build-sync scripts

All three scripts currently do the same thing:

1. Read the `version:` entry in `pubspec.yaml`
2. Parse it as `MAJOR.MINOR.PATCH+BUILD`
3. Increment the build integer by 1
4. Write the new version back to `pubspec.yaml` and `web/version.json`

The version logic is therefore side-effectful, stateful only in the committed file, and not date-aware.

### Runtime version display logic

`lib/app/services/app_version_service.dart` reads `PackageInfo.version` and `PackageInfo.buildNumber` and formats them for display. Its comments describe the old semver strategy, but the runtime logic is format-agnostic: it does not parse or reinterpret the version string mathematically. It simply prints the version and build number from the platform package metadata.

`lib/app/services/version_check_service.dart` compares `build_number` as an opaque string for inequality when deciding whether to force a reload. This is also format-agnostic and should continue to work unchanged as long as the stale-web check compares two strings from the same version metadata source.

### Native platform integration

The architecture remains consistent with the feature input:

- Android reads from `flutter.versionCode` / `flutter.versionName`
- iOS/macOS read from `$(FLUTTER_BUILD_NAME)` / `$(FLUTTER_BUILD_NUMBER)`
- No hand-editing is done in `ios/Flutter/Generated.xcconfig` or platform metadata; those are generated from `pubspec.yaml` during the build

### Release date + build number design

The correct future behavior is:

- display version = `YY.M.D` from the release date, with no zero-padding for month/day
- build number = `date_num * 100 + same_day_counter` where `date_num = YY * 10000 + MM * 100 + DD`
- same-day counter is derived from the currently committed `pubspec.yaml` version before writing the new one, by reading the leading 6 digits as `YYMMDD` and incrementing the trailing 2-digit counter if the same date matches

Explicit legacy-compatibility rule:

- Before attempting the `YYMMDD` same-day comparison, the script must detect whether the committed `version:` is still in the old semver format (`MAJOR.MINOR.PATCH+BUILD`), which is the actual current repo state (`1.4.6+246`)
- If the committed value does not match the date-based `YYMMDDNN` build pattern or matches the legacy semver pattern instead, the script must treat it as `no prior same-day release` and start the same-day counter at `01` for the current date
- The old semver build integer (for example `246`) must never be interpreted as a date or date-based counter; it is simply ignored as a legacy value when computing the first date-based release

This keeps the logic stateless and self-contained while remaining strictly monotonic across calendar boundaries and safely handling the real cutover state in this repository.

## 6. Proposed Solution

### Replace semver-driven automation with date-based release arithmetic

Update the version-sync step in:

- `tools/generate_version.sh`
- `tools/build_web.sh`
- `tools/deploy_web.sh`

Each script will:

1. read the current committed `version:` from `pubspec.yaml`
2. detect whether the current value is still legacy semver (`MAJOR.MINOR.PATCH+BUILD`) or already date-based (`YY.M.D+YYMMDDNN`)
3. if the committed value is legacy semver or otherwise does not parse as a valid date-based `YYMMDDNN` build, treat it as `no prior same-day release` and reset the same-day counter to `01` for today
4. if the committed value is already date-based and its leading 6 digits equal today’s `YYMMDD`, increment the trailing 2-digit counter by 1
5. if the committed value is date-based but for a different date, reset the same-day counter to `01`
6. compute the next display version string as `YY.M.D`
7. compute the next build number with the exact formula:
   - `date_num = YY * 10000 + MM * 100 + DD`
   - `build = date_num * 100 + same_day_counter`
8. write back the new canonical value as `YY.M.D+BUILD` (for example `26.8.26+26082601`)
9. generate `web/version.json` with the same display version and build number fields

This guard is mandatory because the actual repo starts from `version: 1.4.6+246`, which must not be misread as a date-based build value.

### Keep the single source of truth unchanged

`pubspec.yaml` remains the only source of truth. No new state file or database-based tracking is introduced. The same-day counter is derived by reading the current committed value before writing the new one, as required by the feature input.

### App Store edge case handling

Document and enforce the following policy in release operations:

- The display version `YY.M.D` is the marketing version string in App Store Connect
- Because it changes only once per calendar day, two public releases on the same date would collide on the same App Store marketing version
- The operational plan is to not support same-day public re-releases; if one becomes necessary, it must be deferred to the next day rather than silently creating an invalid version string

### Runtime code review and confirm no logic change required

`lib/app/services/app_version_service.dart` should be updated only to rewrite the docblock to describe the new date-based scheme. Its runtime logic is format-agnostic and should continue to work without behavioral changes.

`lib/app/services/version_check_service.dart` should remain unchanged because it compares the build string as an opaque value and does not assume semver semantics.

## 7. Database Impact

Database: not applicable.

This feature is a release/versioning pipeline change and does not require database migrations, RLS policy edits, RPC changes, or trigger updates. No schema changes are introduced, and no persistence layer is added for version history.

## 8. Flutter Architecture Changes

No application state, widget tree changes, repository changes, or provider changes are required.

The only relevant Flutter-side touchpoint is documentation and confirmation in:

- `lib/app/services/app_version_service.dart`

No UI logic needs to change because the runtime code reads the platform package metadata and formats it for display without semantic assumptions about `MAJOR.MINOR.PATCH`.

## 9. Files to Create

None.

The work product here is the architecture plan itself, which is written under `docs/features/date-based-version-format/ARCHITECT_PLAN.md` in the clean feature worktree. No implementation files are created as part of this phase.

## 10. Files to Modify

| File                                        | What changes                                                                                                      |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `tools/generate_version.sh`                 | Replace semver regex + increment logic with date-based computation and same-day counter derivation                |
| `tools/build_web.sh`                        | Replace the same semver parsing logic and emit date-based `pubspec.yaml` + `web/version.json` values              |
| `tools/deploy_web.sh`                       | Replace the same semver parsing logic in production deploy flow and maintain the new date-based build formula     |
| `lib/app/services/app_version_service.dart` | Rewrite the doc comment to describe the new `YY.M.D` + build scheme; confirm runtime code remains format-agnostic |

## 11. Files Off-Limits

| File                                          | Reason                                                                                           |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `lib/app/services/version_check_service.dart` | Compares the build value as an opaque string and is format-agnostic; no functional change needed |
| `android/app/build.gradle`                    | Reads Flutter-generated version fields; not hand-edited                                          |
| `ios/Runner/Info.plist`                       | Reads Flutter-generated version fields; not hand-edited                                          |
| `ios/Flutter/Generated.xcconfig`              | Regenerated automatically at build time; not hand-edited                                         |
| `web/version.json`                            | Generated artifact, updated by the script rather than manually edited                            |
| `pubspec.yaml`                                | Single source of truth and is intentionally rewritten by the version-sync tooling                |

## 12. System Impact Map

| System                                 | Impact                                                                                               |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                           |
| Rehearsals                             | unaffected                                                                                           |
| Setlists / Catalog                     | unaffected                                                                                           |
| Members / RBAC                         | unaffected                                                                                           |
| Auth / Session                         | unaffected                                                                                           |
| Routing                                | unaffected                                                                                           |
| Notifications                          | unaffected                                                                                           |
| Platform (iOS / Android / Web / macOS) | affected — all platform version metadata must remain synchronized with the new `YY.M.D+BUILD` scheme |

## 13. Regression Risk

Risk: LOW

Reasoning:

- The change is centered in release automation rather than app runtime state or business logic
- The runtime version-display code is format-agnostic and does not depend on semver parsing
- The app’s version checking path compares build strings as opaque values and should not regress
- No database, auth, routing, or feature logic is touched
- The primary behavioral risk is release-script miscalculation, which is mitigated by deterministic date arithmetic and the same-day counter derived from the committed version in `pubspec.yaml`

## 14. Engineer Task Breakdown

1. Update `tools/generate_version.sh` to compute `YY.M.D` and build value using the required date arithmetic and same-day counter derivation.
2. Update `tools/build_web.sh` with the same logic and keep `web/version.json` consistent.
3. Update `tools/deploy_web.sh` with the same logic in the production deploy flow.
4. Rewrite the doc comment in `lib/app/services/app_version_service.dart` to reflect the new version scheme and confirm no runtime logic change is needed.
5. Confirm `version_check_service.dart` remains unchanged and still works with opaque build strings.
6. Validate the final behavior by checking generated output for sample dates and ensuring no script uses the old semver regex.

## 15. Verification Plan

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

This feature does not involve database changes. Tier 1 validation is therefore script-level and deterministic, with zero schema changes applied.

- `-- PRE-DEPLOY TEST 1:` Verify the old regex is absent from all three versioning scripts and replaced by date-based parsing logic.
- `-- PRE-DEPLOY TEST 2:` Start from the actual current committed value in this repo: `version: 1.4.6+246`. Confirm the first date-based release on the same real date (for example Aug 26, 2026) produces `26.8.26+26082601` rather than crashing or treating `246` as a date-derived counter.
- `-- PRE-DEPLOY TEST 3:` Run a shell-level check for a known date sample: given `version: 26.8.26+26082601`, the next build should be `26082602` when the current date is Aug 26, 2026.
- `-- PRE-DEPLOY TEST 4:` Run a shell-level check for a new date sample: given `version: 26.8.26+26082602`, the next build on Sep 1, 2026 should be `26090101` and the display version should be `26.9.1`.
- `-- PRE-DEPLOY TEST 5:` Verify the script logic does not add leading zeros for month/day in the display version.
- `-- PRE-DEPLOY TEST 6:` Confirm the generated `web/version.json` structure is still `{"app_name":"bandroadie","version":"YY.M.D","build_number":"BUILD","package_name":"bandroadie"}` and does not add a second source of truth.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

This feature does not require a database deployment; Tier 2 validation is therefore release-flow validation for the generated artifacts and app metadata.

- `-- POST-DEPLOY TEST 1:` Run the release script on a date sample and verify the resulting `pubspec.yaml` value matches the exact format `YY.M.D+BUILD` with no malformed semver content.
- `-- POST-DEPLOY TEST 2:` Confirm `web/version.json` contains the same display string and build number as the `pubspec.yaml` value, proving the web artifact is generated from the same source of truth.
- `-- POST-DEPLOY TEST 3:` Validate the same-day counter behavior using two consecutive releases on the same date; confirm build numbers increase as `...01`, `...02`, `...03` and do not reset incorrectly.
- `-- POST-DEPLOY TEST 4:` Confirm `app_version_service.dart` still renders the human-visible string in the expected pattern and does not throw on a date-based version string.
- `-- POST-DEPLOY TEST 5:` Confirm stale-tab reload behavior still works by checking that `version_check_service.dart` treats the build number as an opaque string and reloads when changed.
- `-- POST-DEPLOY TEST 6:` Production verification query: inspect the committed version values in the release branch and confirm there is no record of a semver format left in the generated version output. This is a release artifact verification, not a DB mutation.

## 16. QA Regression Areas

- Web deployment version metadata sync
- Mobile build metadata sync via the `pubspec.yaml` single source of truth
- In-app version display formatting in the About/version area
- Stale-tab update prompt behavior on web
- Same-day build counter behavior across multiple releases on one calendar date
- App Store Connect marketing version collision policy for same-day public re-releases

## 17. Rollout / Migration Strategy

No database migration is needed.

Rollout is operational and script-driven:

1. Update the script logic to the new formula
2. Run the version sync on the next production release date
3. Publish the resulting `pubspec.yaml` in the canonical `YY.M.D+BUILD` format
4. Keep `version_check_service.dart` unchanged and verify the web stale-tab reload logic still works
5. If a same-day public App Store release becomes necessary, defer it to the next day instead of reusing the same marketing version string

## 18. Out of Scope

- Any new persistent version-tracking database or state file
- Any change to native platform build metadata generation logic
- Any change to the runtime update-check behavior
- Any migration or refactor unrelated to versioning release automation
- Any attempt to support same-day public App Store re-releases with the same marketing version
