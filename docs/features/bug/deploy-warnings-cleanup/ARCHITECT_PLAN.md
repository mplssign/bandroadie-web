# Feature Slug

`bug/deploy-warnings-cleanup`

# Problem Summary

Resolve three flagged deploy/analyzer concerns with minimal-risk, behavior-preserving edits:

1. Remove discontinued `golden_toolkit` dev dependency.
2. Eliminate CupertinoIcons font warning path cleanly.
3. Resolve five reported `duplicate_definition` analyzer errors in band and setlist screens.

# Inputs and Evidence Read

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `pubspec.yaml`
- `lib/features/bands/band_form_screen.dart`
- `lib/features/setlists/new_setlist_screen.dart`
- `tools/build_mobile_release.sh`
- workspace-wide symbol search for `golden_toolkit`, `cupertino_icons`, and `CupertinoIcons`

# Baseline Diagnostics

- `flutter analyze` baseline result in current workspace state: **No issues found**.
- `golden_toolkit` still present in `pubspec.yaml` under `dev_dependencies`.
- No Dart source usage of `CupertinoIcons` found in `lib/` or `test/`.
- `cupertino_icons` references appear in generated artifact files under `android/app/src/main/assets/public/` (for example, `assets/FontManifest.json`, `flutter_service_worker.js`, `assets/AssetManifest.bin`, `assets/NOTICES`).
- Requested `duplicate_definition` errors are not reproducible in current local state; likely already resolved in existing uncommitted changes or previously stale diagnostics.

# Root Cause Assessment

1. **golden_toolkit warning**
   - Root cause: direct declaration in `pubspec.yaml`.
   - Confidence: **HIGH**.

2. **CupertinoIcons font warning**
   - Root cause: stale/generated artifact manifests under `android/app/src/main/assets/public` still reference Cupertino font package paths.
   - Confidence: **MEDIUM-HIGH** (consistent with search results and absence of Dart-level usage).

3. **duplicate_definition analyzer errors**
   - Root cause in current state: **not present / not reproducible**.
   - Confidence: **HIGH** for baseline status, **LOW** for historical cause without prior failing analyzer snapshot.

# Proposed Solution (Minimal and Surgical)

1. Remove `golden_toolkit` from `dev_dependencies` in `pubspec.yaml`.
2. Run `flutter pub get` to sync dependency graph and lockfile.
3. Regenerate mobile/web-derived artifacts through the standard build flow so stale Cupertino font manifest entries are replaced by current dependency outputs.
   - Do **not** hand-edit generated binary manifests.
4. Re-run `flutter analyze` to confirm 0 errors.
5. If duplicate-definition errors reappear during implementation, fix only duplicate symbol declarations in:
   - `lib/features/bands/band_form_screen.dart`
   - `lib/features/setlists/new_setlist_screen.dart`
     by removing/renaming duplicates with no behavior or UI changes.

# Files to Modify

| File                                                           | Planned change                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------- |
| `pubspec.yaml`                                                 | Remove `golden_toolkit` from `dev_dependencies`.                |
| `pubspec.lock`                                                 | Update via `flutter pub get` to reflect dependency removal.     |
| `docs/features/bug/deploy-warnings-cleanup/ENGINEER_REPORT.md` | Engineer execution report only (implementation phase artifact). |

# Conditional Files to Modify (Only If Needed)

| File                                            | Condition                                                       | Planned change                            |
| ----------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------- |
| `lib/features/bands/band_form_screen.dart`      | Only if duplicate symbols are actually present when re-verified | Remove/rename duplicate definitions only. |
| `lib/features/setlists/new_setlist_screen.dart` | Only if duplicate symbols are actually present when re-verified | Remove/rename duplicate definitions only. |

# Files Explicitly Off-Limits

| File/Area                                                                  | Reason                                           |
| -------------------------------------------------------------------------- | ------------------------------------------------ |
| `lib/main.dart`                                                            | Initialization order is guarded and unrelated.   |
| Supabase migrations, SQL, edge functions                                   | Out of scope; no backend behavior change needed. |
| Feature widgets/controllers unrelated to these warnings                    | Prevent opportunistic refactors/regression risk. |
| Manual edits inside generated binary artifacts (`AssetManifest.bin`, etc.) | Must be regenerated, not hand-edited.            |

# Forbidden Work

- No dependency replacement for `golden_toolkit`.
- No broad dependency upgrade pass.
- No WASM compatibility work.
- No deploy script (`--pwa-strategy`) changes.
- No formatting-only churn.
- No UI/behavior changes.

# Verification Plan

1. `flutter pub get` completes successfully.
2. Confirm `pubspec.yaml` contains no `golden_toolkit` reference.
3. Confirm `pubspec.lock` no longer contains `golden_toolkit`.
4. Execute the existing mobile release build path used in deployment (`./tools/build_mobile_release.sh android-aab`) and verify Cupertino font warning is absent.
5. Run `flutter analyze` and confirm **0 errors**.
6. If analyzer remains clean, treat duplicate-definition item as already-resolved and document that no source edits were needed for item 6.

# Regression Risk

**LOW**

Rationale: targeted dependency removal and artifact refresh only; no intended runtime logic/UI changes.

# Engineer Task Breakdown

1. Remove `golden_toolkit` from `pubspec.yaml`.
2. Run `flutter pub get`.
3. Validate no remaining `golden_toolkit` references in dependency manifests.
4. Run release build command to refresh/validate generated asset manifests and warnings.
5. Run `flutter analyze`.
6. Only if duplicate-definition errors are present: apply smallest possible symbol-level fix in the two scoped files.
7. Produce `ENGINEER_REPORT.md` with exact command outputs and file diffs.

# Out of Scope

- Broad dependency updates.
- WASM-specific package/deprecation issues.
- PWA strategy/deploy script modernization.
- Any architecture or backend changes.
