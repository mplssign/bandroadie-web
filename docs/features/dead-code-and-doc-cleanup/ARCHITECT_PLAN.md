# ARCHITECT_PLAN.md — bug/dead-code-and-doc-cleanup

## 1. Feature Slug

`bug/dead-code-and-doc-cleanup`

- Branch name: `bug/dead-code-and-doc-cleanup`
- Docs path: `docs/features/dead-code-and-doc-cleanup/ARCHITECT_PLAN.md`

---

## 2. Problem Summary

A repository audit surfaced seven pieces of stale state accumulated from prior
cleanups and abandoned scaffolding. None affect runtime behavior for real users, but
each currently misleads anyone reading the codebase or documentation:

1. Two 0-byte scaffolding files (`lib/app/app.dart`, `lib/app/app_router.dart`) —
   abandoned per prior architecture notes.
2. `go_router: ^17.0.1` declared in `pubspec.yaml` with zero import sites anywhere in
   `lib/`.
3. `lib/shared/widgets/banner_test_screen.dart` (335 lines) — dev-only screen with
   zero import sites.
4. `supabase/functions/acousticbrainz_bpm/` — Edge Function targeting an API
   (AcousticBrainz) shut down in November 2022. Dart caller (`_fetchAcousticBrainzBpm`)
   was already removed in the `bug/cleanup-p1-p2-p3` feature; the on-disk source and
   the `supabase/config.toml` stub are the last remnants.
5. Placeholder AI-generated comment at `lib/features/shell/app_shell.dart:208`
   referencing `github.com/user/repo/issues/XXX`.
6. `sql/` contains 35 historical/incident scripts across five subdirectories
   (`diagnostics`, `fixes`, `notifications`, `schema`, `triggers`), superseded by real
   migrations in `supabase/migrations/`.
7. `docs/agents/PROJECT_CONTEXT.md` Edge Functions inventory (§Edge Functions,
   lines ~266–278) is out of sync: it lists 10 functions but only 9 exist locally,
   omits two actively used functions (`getsongbpm_lookup`, `itunes_search`), and lists
   three functions (`spotify_search`, `spotify_audio_features`, `auth-confirm`) whose
   local sources are absent. `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`
   also documents `go_router` and a non-existent `app/router/` directory.

---

## 3. Root Cause

Accumulated drift from earlier partial cleanups:

- `cleanup-p1-p2-p3` (DECISION-002) removed `_fetchAcousticBrainzBpm()` from Dart but
  intentionally left `supabase/functions/acousticbrainz_bpm/` on disk for Tony to
  undeploy manually. That step happened at some point (see confidence note below), but
  no one deleted the local source or its `supabase/config.toml` entry.
- `stale-architecture-docs` reconciled `docs/reference/architecture/supabase_functions.md`
  against the live project but did not touch `docs/agents/PROJECT_CONTEXT.md`, so a
  second inventory drifted.
- `lib/app/app.dart` and `lib/app/app_router.dart` were seeded during an aborted
  router migration; PROJECT_CONTEXT.md already documents the fact that they are empty
  and that routing lives in `main.dart`. The scaffolding was never removed.
- `banner_test_screen.dart` is a diagnostic screen that lost its entry point.
- The `app_shell.dart` placeholder comment was AI-authored during a bug fix and never
  replaced with a real issue link.
- `sql/` incident scripts predate the migration workflow discipline; they were checked
  in as forensic evidence and never relocated once migrations became the authoritative
  channel.

**Confidence: HIGH** — every finding is directly observable in the current tree via
`grep`, `wc -c`, and directory listing. The one soft assumption is Finding 4's live
deploy status; see §5 for how the Engineer must re-verify before touching it.

---

## 4. Reference Docs Consulted

The Architect template Phase 4 (Notification Domain Reference) is **not applicable**
to this feature — no notification code paths are touched. In its place, the following
were read to confirm scope and precedent:

| File                                                   | Why                                                                                                                                              |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `docs/agents/GUARDRAILS.md`                            | Global rules; §1, §2, §7, §7a, §10 all directly apply.                                                                                           |
| `docs/agents/OPERATING_MODEL.md`                       | Role boundaries, minimal-diff principle, commit gate.                                                                                            |
| `docs/agents/ARCHITECT.md`                             | Phase discipline.                                                                                                                                |
| `docs/agents/PROJECT_CONTEXT.md`                       | Directory layout claims and Edge Functions inventory that must be corrected.                                                                     |
| `docs/reference/audits/CODEBASE_AUDIT.md`              | Point-in-time audit that originally flagged Findings 1 and 2.                                                                                    |
| `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`  | Legacy top-level docs still listing `go_router` and a fictional `router/` folder.                                                                |
| `docs/features/bug/cleanup-p1-p2-p3/ARCHITECT_PLAN.md` | Precedent for handling `acousticbrainz_bpm`: DECISION-002 removed the Dart caller and explicitly deferred local-source removal to a future pass. |
| `docs/features/bug/cleanup-p1-p2-p3/QA_REPORT.md`      | Confirms Dart caller was fully removed.                                                                                                          |
| `docs/features/stale-architecture-docs/QA_REPORT.md`   | Independent evidence that as of 2026-07 the live project had exactly 9 ACTIVE functions, and `acousticbrainz_bpm` was **not** among them.        |
| `docs/reference/general/AI_DECISIONS.md`               | DECISION-002 governs AcousticBrainz removal; no new decision entry required for this pass.                                                       |
| `supabase/config.toml`                                 | Confirms local config still declares `[functions.acousticbrainz_bpm]`.                                                                           |

---

## 5. Existing System Analysis

Per-finding current state, verified this session:

### Finding 1 — Empty scaffolding

- `lib/app/app.dart`: 0 bytes.
- `lib/app/app_router.dart`: 0 bytes.
- Zero import sites anywhere in the repo (`grep "app/app.dart|app/app_router.dart"` in
  the whole tree returns only two matches: a docs bullet in an off-limits feature plan
  and the `CODEBASE_AUDIT.md` finding itself).
- Parent directory `lib/app/` also contains active code (`constants/`,
  `firebase_config.dart`, `models/`, `services/`, `supabase_config.dart`, `theme/`,
  `utils/`), so the directory itself must remain.

### Finding 2 — Unused dependency

- `pubspec.yaml:24`: `go_router: ^17.0.1`.
- `pubspec.lock:480–481`: pinned as `direct main`.
- Zero references anywhere in `lib/` (`grep -r "go_router|GoRouter|GoRoute" lib` → 0
  hits). Only external references are: an Android NOTICES file, prior audit `.log`
  files, and doc entries. No import lines anywhere.

### Finding 3 — Dead screen

- `lib/shared/widgets/banner_test_screen.dart`: 10 178 bytes, exports
  `BannerTestScreen`.
- Zero import sites anywhere: `grep "banner_test_screen|BannerTestScreen"` matches
  only the file itself (self-references) and two documentation entries
  (`docs/reference/audits/ICON_AUDIT_AND_LUCIDE_MIGRATION.md`,
  `docs/features/light-mode-visibility-fixes/ARCHITECT_PLAN.md`). Neither documentation
  reference is an executable import.
- No route registration in `main.dart` — the screen is unreachable at runtime.

### Finding 4 — Dead Edge Function

- Local source present at `supabase/functions/acousticbrainz_bpm/index.ts` and
  `supabase/functions/acousticbrainz_bpm/deno.json`.
- Local config: `supabase/config.toml:95` declares `[functions.acousticbrainz_bpm]`.
- Zero `acousticbrainz` references in `lib/` (Dart caller was removed in the
  `cleanup-p1-p2-p3` feature per DECISION-002).
- **Live deploy status:** the `stale-architecture-docs` QA report independently
  confirmed that as of 2026-07 the live project (`nekwjxvgbveheooyorjo`) had 9 ACTIVE
  functions and `acousticbrainz_bpm` was NOT among them. Given no traffic in the
  trailing 24 h (Feature Input evidence) and no intermediate feature has redeployed
  it, HIGH confidence it remains undeployed. Engineer MUST still re-verify before
  proceeding (see Task E4).

### Finding 5 — Placeholder comment

- File: `lib/features/shell/app_shell.dart` (Feature Input path `lib/app_shell.dart`
  is incorrect — real path documented above).
- Line 208 exactly matches the placeholder pattern:
  `// See: https://github.com/user/repo/issues/XXX (blank screen bug)`.
- Adjacent lines 205–207 already document the real technical rationale
  ("Overlay widgets MUST only be added to tree when open… causes a blank screen bug
  on app startup because the overlay widgets don't render correctly when initialized
  closed"). Line 208 is therefore purely redundant; no real tracked issue exists.

### Finding 6 — Historical SQL scripts

- Actual count: 35 (`diagnostics`: 15, `fixes`: 10, `notifications`: 6, `schema`: 2,
  `triggers`: 2). Feature Input said "~41" — the discrepancy does not change scope.
- `sql/experiments/` and `sql/maintenance/` do NOT exist on disk. Feature Input said
  they "contain only placeholder stubs"; the correct statement is that they do not
  exist at all. Scope unchanged.
- 26 references from other `docs/features/**/ARCHITECT_PLAN.md` files cite these SQL
  files by their current `sql/…` path (e.g.
  `sql/fixes/backfill_tony_historical_blocks.sql`,
  `sql/diagnostics/investigate_partial_block_anomaly.sql`). Relocation will leave
  those references pointing at the old path — see §11 Off-Limits and §17.

### Finding 7 — Docs inventory drift

- `docs/agents/PROJECT_CONTEXT.md` Edge Functions table currently lists 10 rows.
  Verified against live `supabase/functions/`:
  - **Present locally but missing from the table**: `getsongbpm_lookup` (used by
    `lib/features/songs/song_enrichment_service.dart:85` — Feature Input path
    `lib/features/setlists/…` is incorrect), `itunes_search` (used by
    `lib/features/songs/external_song_lookup_service.dart:251` — same path correction).
  - **In the table but absent locally**: `spotify_search`, `spotify_audio_features`,
    `auth-confirm`. Zero Dart references to any of these three anywhere in `lib/`.
- `docs/agents/PROJECT_CONTEXT.md` also references the empty scaffolding at:
  - Line 116: `│   ├── router/  # app_router.dart (currently empty — routing is in main.dart)`
  - Line 317: "Routing logic lives in `main.dart` (not in `app_router.dart` which is
    empty)"
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` also carries stale claims:
  - Line 166: `- \`go_router\` - Declarative routing`
  - Line 179: `│   │   ├── router/               # GoRouter configuration`

---

## 6. Proposed Solution

Minimal, per-finding cleanup. No new abstractions. No runtime behavior changes.

| Finding | Action                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1       | Delete both 0-byte files. Update PROJECT_CONTEXT.md line 116 and line 317; update BAND_ROADIE_DOCUMENTATION.md line 179.                                                                                                                                                                                                                                                                                                                                                      |
| 2       | Remove the `go_router` line from `pubspec.yaml`. Run `flutter pub get` so `pubspec.lock` regenerates cleanly. Remove line 166 of BAND_ROADIE_DOCUMENTATION.md.                                                                                                                                                                                                                                                                                                                |
| 3       | Delete `lib/shared/widgets/banner_test_screen.dart`.                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 4       | Engineer re-verifies live deploy status (`supabase functions list --project-ref nekwjxvgbveheooyorjo`). If ACTIVE, undeploy via `supabase functions delete acousticbrainz_bpm` (or flag for Tony if Engineer lacks credentials). Once absent from live, delete `supabase/functions/acousticbrainz_bpm/` (both files + directory) and remove the `[functions.acousticbrainz_bpm]` block from `supabase/config.toml`.                                                           |
| 5       | Delete line 208 of `lib/features/shell/app_shell.dart`. The preceding three lines (205–207) already document the real reason; the fake-URL line adds no information. Do not replace it with a fabricated real-looking URL.                                                                                                                                                                                                                                                    |
| 6       | `git mv` all 35 scripts and their five subdirectories from `sql/` to `docs/reference/historical-incidents/`. Create a short `docs/reference/historical-incidents/README.md` explaining these are frozen forensic artifacts, not runnable migrations. Delete the now-empty top-level `sql/` directory (and its `.DS_Store`).                                                                                                                                                   |
| 7       | Rewrite the Edge Functions table in `docs/agents/PROJECT_CONTEXT.md` to reflect exactly what exists locally: add `getsongbpm_lookup` and `itunes_search` rows; delete the `acousticbrainz_bpm` row (source removed in this pass); annotate `spotify_search`, `spotify_audio_features`, and `auth-confirm` rows with `⚠ verify — not found locally` per Feature Input direction. Also update the header count from "All 10 deployed functions" to match the corrected reality. |

---

## 7. Database Impact

**Not applicable.**

No migrations, no RLS changes, no RPC changes, no trigger changes. The `sql/`
relocation touches only checked-in forensic scripts that are not part of any
automated deploy pipeline — no schema state changes.

---

## 8. Flutter Architecture Changes

**None.**

- No new state, no new widgets, no new repositories, no new controllers.
- No provider added or removed.
- No init-order change (Guardrails §1 preserved).
- No configuration loader added (Guardrails §2 preserved).
- Removing `go_router` from `pubspec.yaml` deletes an unused dependency only; no code
  imports it, no code path exercises it.

---

## 9. Files to Create

| Path                                                 | Justification                                                                                                                                                                                      |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docs/reference/historical-incidents/README.md`      | Explains that the relocated scripts are frozen forensic evidence — not runnable migrations, not part of any deploy pipeline. States that current schema authority lives in `supabase/migrations/`. |
| `docs/reference/historical-incidents/diagnostics/`   | Target of `git mv sql/diagnostics/*.sql`.                                                                                                                                                          |
| `docs/reference/historical-incidents/fixes/`         | Target of `git mv sql/fixes/*.sql`.                                                                                                                                                                |
| `docs/reference/historical-incidents/notifications/` | Target of `git mv sql/notifications/*.sql`.                                                                                                                                                        |
| `docs/reference/historical-incidents/schema/`        | Target of `git mv sql/schema/*.sql`.                                                                                                                                                               |
| `docs/reference/historical-incidents/triggers/`      | Target of `git mv sql/triggers/*.sql`.                                                                                                                                                             |

No other new files.

---

## 10. Files to Modify

| Path                                                  | What changes                                                                                                                                                                                                                                                                                          |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pubspec.yaml`                                        | Delete line 24 (`  go_router: ^17.0.1`). Leave surrounding "# State / Routing" comment intact (routing = Riverpod + Navigator).                                                                                                                                                                       |
| `pubspec.lock`                                        | Regenerated automatically by `flutter pub get` after the pubspec edit. Engineer does not hand-edit; the diff is expected and reviewed as part of the PR.                                                                                                                                              |
| `lib/features/shell/app_shell.dart`                   | Delete only line 208 (the placeholder-URL comment). Do not touch the surrounding technical explanation comment block. Do not touch any other line in the file.                                                                                                                                        |
| `supabase/config.toml`                                | Delete the `[functions.acousticbrainz_bpm]` block (lines 95–96 in the current file). Leave every other `[functions.*]` block unchanged, including the currently-drifting `[functions.deliver-notifications]` and `[functions.auth-confirm]` blocks (see §18).                                         |
| `docs/agents/PROJECT_CONTEXT.md`                      | Rewrite the Edge Functions table per §6 Finding 7. Update line 116 to remove the `router/` line entirely (or replace with the actual `lib/app/` contents). Update line 317 to remove "not in `app_router.dart` which is empty" — leave the rest of the sentence stating routing lives in `main.dart`. |
| `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` | Delete the `- \`go_router\` - Declarative routing`bullet on line 166. Delete the`│ │ ├── router/ # GoRouter configuration` line in the directory diagram on line 179. Do not restructure the rest of the diagram.                                                                                     |

---

## 11. Files Off-Limits

| Path                                                                                                                                                                                                  | Reason                                                                                                                                                       |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/main.dart`                                                                                                                                                                                       | Initialization order (Guardrails §1). Also the current routing entry point.                                                                                  |
| `lib/app/constants/`, `lib/app/models/`, `lib/app/services/`, `lib/app/theme/`, `lib/app/utils/`, `lib/app/firebase_config.dart`, `lib/app/supabase_config.dart`                                      | All actively used — only the two 0-byte files may be deleted. Do not touch anything else in `lib/app/`.                                                      |
| Everything under `lib/features/` except the single line 208 of `app_shell.dart`                                                                                                                       | Guardrails §7 — no opportunistic changes.                                                                                                                    |
| `supabase/migrations/`                                                                                                                                                                                | No schema changes.                                                                                                                                           |
| Every other `supabase/functions/<name>/` directory (`accept-invite`, `calendar-feed`, `getsongbpm_lookup`, `itunes_search`, `musicbrainz_search`, `send-band-invite`, `send-bug-report`, `send-push`) | Not in scope.                                                                                                                                                |
| The `[functions.deliver-notifications]` and `[functions.auth-confirm]` blocks in `supabase/config.toml`                                                                                               | Feature Input directs "verify — not found locally" notes rather than deletion; do not delete config for functions whose deploy status is ambiguous. See §18. |
| Every `docs/features/**/ARCHITECT_PLAN.md` and QA/Engineer report                                                                                                                                     | Historical artifacts. Existing references to `sql/…` paths will become stale after relocation, but rewriting cross-feature docs is out of scope (§18).       |
| `docs/reference/audits/CODEBASE_AUDIT.md`                                                                                                                                                             | Point-in-time audit — leave as-is even though it flagged Findings 1 & 2.                                                                                     |
| `docs/reference/audits/ICON_AUDIT_AND_LUCIDE_MIGRATION.md`                                                                                                                                            | Contains a table with 4 rows referencing `banner_test_screen.dart`. Do not edit — historical audit output.                                                   |
| `macos/Podfile`, `macos/Podfile.lock`, `macos/Runner.xcodeproj/project.pbxproj`, both `Package.resolved` files                                                                                        | Pre-existing unstaged working-tree modifications unrelated to this task; must be excluded from every commit in this branch.                                  |
| `pubspec.yaml` sections other than the `go_router` line                                                                                                                                               | Guardrails §7. No opportunistic upgrades even though `flutter pub outdated` warnings will appear.                                                            |
| `.github/copilot-instructions.md`                                                                                                                                                                     | Off-limits — separate governance.                                                                                                                            |

**Migration policy:** not required.
**Edge function deploy:** required — `supabase functions delete acousticbrainz_bpm`
against project `nekwjxvgbveheooyorjo`, if it is still ACTIVE. If it is already
absent, no deploy action is needed.
**New dependencies:** not allowed.
**New files:** README + five relocation subdirectories under
`docs/reference/historical-incidents/` (see §9).

---

## 12. System Impact Map

| System                                 | Impact                                                                                                                                                                           |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gigs                                   | unaffected                                                                                                                                                                       |
| Rehearsals                             | unaffected                                                                                                                                                                       |
| Setlists / Catalog                     | unaffected                                                                                                                                                                       |
| Members / RBAC                         | unaffected                                                                                                                                                                       |
| Auth / Session                         | unaffected                                                                                                                                                                       |
| Routing                                | unaffected (routing already lives in `main.dart`; the deleted files were 0-byte and the removed dep was never imported)                                                          |
| Notifications                          | unaffected                                                                                                                                                                       |
| Platform (iOS / Android / Web / macOS) | unaffected — no platform-conditional imports of any deleted file (verified: none of the removed files appear behind `if (kIsWeb)` or `Platform.isX` guards anywhere in the tree) |
| Build / CI                             | pubspec.lock regenerates; the `flutter analyze` and web/mobile builds must both still pass. No `--dart-define` changes.                                                          |

---

## 13. Regression Risk

**LOW.**

Rationale:

- No runtime code paths change. Deleted files are 0-byte or have zero call sites.
- The one non-trivial deletion (`banner_test_screen.dart`) is confirmed unreachable —
  no routes and no imports.
- No init order, auth flow, RLS policy, RPC signature, or migration is touched.
- The comment deletion at `app_shell.dart:208` cannot affect behavior.
- Removing `go_router` from `pubspec.yaml` only changes the resolved dependency
  graph; nothing imports it, so no code changes.
- Removing `[functions.acousticbrainz_bpm]` from `supabase/config.toml` only affects
  local Supabase CLI behavior for that function — the function is being deleted
  in the same change.
- The SQL relocation is a `git mv`; content is unchanged and none of the scripts are
  invoked by any automated process.
- Documentation edits cannot affect runtime.

Residual risk items to watch:

- `flutter pub get` may pull minor patch updates in transitive dependencies. QA
  must verify `flutter analyze` remains clean and the full test suite passes.
- If `acousticbrainz_bpm` is still live at deploy time and the Engineer proceeds to
  delete `supabase/config.toml` and the local directory without first undeploying,
  redeploys of the project via `supabase functions deploy` would still be
  independent per-function — no accidental undeploy — but the live function would
  drift from the checked-in state. Task E4 gates this explicitly.

---

## 14. Engineer Task Breakdown

Execute **strictly in this order**. Each task is atomic and independently
committable, but the entire batch is intended to ship as one PR.

### E0 — Preflight

1. Confirm current branch is `bug/dead-code-and-doc-cleanup`
   (`git branch --show-current`).
2. Confirm the working tree still shows the five pre-existing unrelated macOS
   modifications and nothing else. Do NOT stage them into any commit in this branch.
3. Confirm `git diff --stat pubspec.yaml` is empty at HEAD (the Feature Input's
   claim of a pre-existing pubspec.yaml modification does not match reality — no
   action required, but note the discrepancy in the ENGINEER_REPORT).

### E1 — Remove empty scaffolding (Finding 1)

1. `git rm lib/app/app.dart`.
2. `git rm lib/app/app_router.dart`.
3. In `docs/agents/PROJECT_CONTEXT.md`, delete the `│   ├── router/` line at line 116.
4. In `docs/agents/PROJECT_CONTEXT.md`, edit line 317 to remove the parenthetical
   "(not in `app_router.dart` which is empty)".
5. In `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`, delete line 179
   (`│   │   ├── router/               # GoRouter configuration`).

### E2 — Remove unused `go_router` dependency (Finding 2)

1. In `pubspec.yaml`, delete the single line `  go_router: ^17.0.1` (line 24). Leave
   the surrounding `# State / Routing` comment and the `flutter_riverpod` line
   untouched.
2. In `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md`, delete line 166
   (`- \`go_router\` - Declarative routing`).
3. Run `flutter pub get` to regenerate `pubspec.lock`. Commit both file changes.
4. Run `flutter analyze` — must exit 0.

### E3 — Delete dead banner test screen (Finding 3)

1. `git rm lib/shared/widgets/banner_test_screen.dart`.
2. Run `flutter analyze` — must exit 0.

### E4 — Remove dead AcousticBrainz Edge Function (Finding 4)

1. Verify live deploy status:
   `supabase functions list --project-ref nekwjxvgbveheooyorjo`. Expected: 9 ACTIVE
   functions, with `acousticbrainz_bpm` absent.
2. **If `acousticbrainz_bpm` IS listed as ACTIVE:** run
   `supabase functions delete acousticbrainz_bpm --project-ref nekwjxvgbveheooyorjo`.
   If the Engineer lacks credentials, STOP and escalate to Tony — do not proceed to
   step 3 until the function is confirmed undeployed.
3. **Only after the function is confirmed absent from live:**
   - `git rm -r supabase/functions/acousticbrainz_bpm/`.
   - In `supabase/config.toml`, delete the two lines forming the
     `[functions.acousticbrainz_bpm]` block. Do not touch any other `[functions.*]`
     block.

### E5 — Remove placeholder AI comment (Finding 5)

1. In `lib/features/shell/app_shell.dart`, delete exactly line 208
   (`          // See: https://github.com/user/repo/issues/XXX (blank screen bug)`).
   Leave lines 205–207 (the real technical rationale) and line 209 (the trade-off
   comment) intact.
2. Run `flutter analyze` — must exit 0.

### E6 — Relocate historical SQL scripts (Finding 6)

1. `mkdir -p docs/reference/historical-incidents/{diagnostics,fixes,notifications,schema,triggers}`.
2. For each subdirectory in `sql/`, run:
   `git mv sql/<sub>/*.sql docs/reference/historical-incidents/<sub>/`.
   Do NOT use plain `mv` — history preservation is required.
3. `git rm sql/.DS_Store` if present.
4. `rmdir sql/{diagnostics,fixes,notifications,schema,triggers} && rmdir sql`.
5. Create `docs/reference/historical-incidents/README.md` with content:

   ```markdown
   # Historical Incident SQL Scripts

   Frozen forensic artifacts from prior incidents and one-off backfills. **Not
   runnable as migrations.** Kept for historical reference only.

   The authoritative schema lives in `supabase/migrations/`. Any change to
   production schema must go through a proper migration — never through these
   scripts.

   ## Layout

   - `diagnostics/` — read-only investigation queries.
   - `fixes/` — one-off remediation scripts already applied by hand.
   - `notifications/` — obsolete notification-system experiments (superseded by
     current `send-push` architecture).
   - `schema/` — pre-migration schema exploration.
   - `triggers/` — trigger investigation.

   Relocated from `sql/` in `bug/dead-code-and-doc-cleanup` (2026-08-30).
   ```

6. Do not update any cross-references in other `docs/features/**/ARCHITECT_PLAN.md`
   files — see §18.

### E7 — Reconcile PROJECT_CONTEXT.md Edge Functions inventory (Finding 7)

1. In `docs/agents/PROJECT_CONTEXT.md`, rewrite the Edge Functions section header
   from "All 10 deployed functions" to reflect actual count (11 rows post-edit; the
   header should read simply "Edge Functions" without a hardcoded count, to avoid
   the same drift recurring).
2. Update the table to exactly this set of rows (order: keep the existing ordering
   convention of user-facing → integrations → internal → public feeds):

   | Function                 | verify_jwt | Purpose                                                      |
   | ------------------------ | :--------: | ------------------------------------------------------------ |
   | `spotify_search`         |     ✅     | ⚠ verify — not found locally                                 |
   | `spotify_audio_features` |     ✅     | ⚠ verify — not found locally                                 |
   | `musicbrainz_search`     |     ✅     | Fallback song search via MusicBrainz                         |
   | `getsongbpm_lookup`      |     ✅     | Fetches BPM + musical key for a new song                     |
   | `itunes_search`          |     ✅     | iTunes song search (CORS proxy for web + native fallback)    |
   | `send-band-invite`       |     ✅     | Send band invitation email via Resend                        |
   | `send-bug-report`        |     ✅     | Send in-app bug/feature report email via Resend              |
   | `auth-confirm`           |     ✅     | ⚠ verify — not found locally                                 |
   | `accept-invite`          |     ✅     | Process invite acceptance — validates token, adds member     |
   | `send-push`              |     ❌     | FCM HTTP v1 push delivery (current production push delivery) |
   | `calendar-feed`          |     ❌     | iCal feed — public URL auth via token param                  |

3. Do not remove the `acousticbrainz_bpm` row separately here — E4 already removed
   the function; this table simply must not reintroduce it.
4. Leave the paragraph immediately below the table
   ("Functions with `verify_jwt: false` use either service role key…") unchanged.

### E8 — Final verification

1. `flutter analyze` → 0 errors, 0 warnings introduced by this branch.
2. `flutter test` → all existing tests pass (this branch adds none).
3. `git status` → only the five pre-existing macOS modifications remain unstaged.
4. `git diff --stat main...HEAD` → confirm scope: no changes outside the paths listed
   in §10 and §9.

---

## 15. Verification Plan

No database migrations exist in this feature, so the standard Tier 1 (pre-DB-push) /
Tier 2 (post-DB-push) split is adapted: **Tier 1 = pre-merge** (must pass before the
PR merges) and **Tier 2 = post-merge** (verified on `main` after merge and deploy).

### Tier 1 — Pre-merge (must pass before PR is merged)

```bash
# PRE-MERGE TEST 1: Analyzer clean
flutter analyze
# Expected exit code: 0. Expected output: "No issues found!" or unchanged pre-existing warnings only.

# PRE-MERGE TEST 2: Full test suite green
flutter test
# Expected: all 176/176 tests pass (baseline from recent PR — this branch adds no tests).

# PRE-MERGE TEST 3: Web build succeeds
flutter build web --release
# Expected exit code: 0. No import errors from removed files.

# PRE-MERGE TEST 4: Verify no lingering references to removed symbols in lib/
grep -rn "app/app.dart\|app/app_router.dart\|go_router\|GoRouter\|GoRoute\|banner_test_screen\|BannerTestScreen\|acousticbrainz\|fetchAcousticBrainzBpm" lib/
# Expected: 0 matches.

# PRE-MERGE TEST 5: Verify placeholder comment gone
grep -n "user/repo/issues/XXX" lib/features/shell/app_shell.dart
# Expected: 0 matches.

# PRE-MERGE TEST 6: Verify sql/ tree is empty
test ! -d sql && echo "OK: sql/ removed"
# Expected: "OK: sql/ removed"

# PRE-MERGE TEST 7: Verify relocation preserved every file
ls docs/reference/historical-incidents/diagnostics/ | wc -l   # Expected: 15
ls docs/reference/historical-incidents/fixes/ | wc -l         # Expected: 10
ls docs/reference/historical-incidents/notifications/ | wc -l # Expected: 6
ls docs/reference/historical-incidents/schema/ | wc -l        # Expected: 2
ls docs/reference/historical-incidents/triggers/ | wc -l      # Expected: 2

# PRE-MERGE TEST 8: Verify git recorded the relocation as renames (history preserved)
git log --diff-filter=R --name-status main...HEAD -- 'docs/reference/historical-incidents/*.sql' | head -20
# Expected: R  sql/<sub>/<file>.sql  docs/reference/historical-incidents/<sub>/<file>.sql (for each of the 35 scripts).

# PRE-MERGE TEST 9: Confirm no accidental macOS Podfile changes committed
git diff --stat main...HEAD -- macos/
# Expected: 0 files changed.

# PRE-MERGE TEST 10: Confirm supabase/config.toml only lost the acousticbrainz_bpm block
git diff main...HEAD -- supabase/config.toml
# Expected diff: exactly two removed lines forming the [functions.acousticbrainz_bpm] block. No other change.

# PRE-MERGE TEST 11: Confirm pubspec.yaml only lost the go_router line
git diff main...HEAD -- pubspec.yaml
# Expected diff: exactly one removed line: `  go_router: ^17.0.1`.

# PRE-MERGE TEST 12: PROJECT_CONTEXT.md Edge Functions table matches §14 E7
grep -c "getsongbpm_lookup\|itunes_search" docs/agents/PROJECT_CONTEXT.md
# Expected: >= 2 (each table row).
grep -c "acousticbrainz_bpm" docs/agents/PROJECT_CONTEXT.md
# Expected: 0.
```

**All Tier 1 tests are runnable with zero schema changes applied.** This branch
introduces no schema changes at all.

### Tier 2 — Post-merge (run after merge to `main` and after any live-project undeploy)

```bash
# POST-MERGE TEST 1: Confirm live Edge Function inventory
supabase functions list --project-ref nekwjxvgbveheooyorjo
# Expected: `acousticbrainz_bpm` is NOT in the ACTIVE list. Actual live count should be <= 9 (may be less depending on the state of the "verify — not found locally" trio).

# POST-MERGE TEST 2: Web production deploy succeeds
./tools/deploy_web.sh
# Expected exit code: 0. App loads at bandroadie.com in incognito.

# POST-MERGE TEST 3: Regression sanity — key user flows still work in prod
# Manual verification per docs/agents/OPERATING_MODEL.md deployment protocol:
#   - Incognito load
#   - PWA install
#   - Auth flow (magic link)
#   - Setlist reorder
#   - Bulk entry
#   - RPC integrity check (any Songs > Edit BPM/tuning/duration on a legacy NULL-band_id song)

# POST-MERGE TEST 4: Historical SQL scripts still accessible on main
test -f docs/reference/historical-incidents/README.md \
  && test -f docs/reference/historical-incidents/fixes/backfill_tony_historical_blocks.sql \
  && echo "OK: relocation intact on main"
```

### SQL test authoring rules

No SQL tests are authored in this feature because no database objects are created or
modified. The standard rules (transactional cleanup, no hardcoded UUIDs, etc.) are
therefore vacuously satisfied.

---

## 16. QA Regression Areas

QA must specifically verify:

- **Analyzer & tests**: `flutter analyze` clean and full test suite green
  (`flutter test`). This is the primary functional gate.
- **Build integrity per platform**:
  - `flutter build web --release` succeeds.
  - `flutter build ios --release --no-codesign` succeeds (mobile build is not a
    strict blocker but should be spot-checked).
  - `flutter build apk --release` or `./tools/build_mobile_release.sh android-aab`
    is optional but recommended given the recent bug/android-build history.
- **Routing sanity**: cold-boot the app on web and native — the app must land on the
  same route it did before this change. Auth flow (magic link) must still complete.
  Deep link `bandroadie://login-callback/` still resolves.
- **Songs / setlists sanity**: `getsongbpm_lookup` and `itunes_search` still work
  end-to-end when adding a new song (these are the two Edge Functions this branch
  documents but did not modify).
- **AcousticBrainz absence**: no runtime error appears when adding a song whose
  Spotify enrichment fails. The previously-dead fallback path was already removed;
  this branch just deletes the last remnants. QA must confirm no code path attempts
  to call `acousticbrainz_bpm`.
- **Documentation coherence**: skim `docs/agents/PROJECT_CONTEXT.md` and
  `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` for internal consistency
  after edits.
- **Historical-incidents README readability**: renders correctly on GitHub.
- **No opportunistic changes**: `git diff main...HEAD` matches exactly the file list
  in §9 + §10. No file outside those lists is modified.

Notifications regression testing is **not required** — this branch does not touch
the notification code path (Guardrails §7).

---

## 17. Rollout / Migration Strategy

- Single PR, single merge to `main`.
- No feature flag needed.
- No user-visible change.
- No client cache invalidation.
- Web deploy via existing `./tools/deploy_web.sh`.
- No mobile release required — mobile behavior is unchanged.
- **Prerequisite deployment step**: `supabase functions delete acousticbrainz_bpm`
  (only if E4 step 1 shows the function still ACTIVE). This is the only
  server-side action.
- **No data migration.** The `sql/` → `docs/reference/historical-incidents/`
  relocation is filesystem-only and preserves git history via `git mv`.

Rollback: `git revert` the merge commit. Because there are no schema changes and no
runtime behavior changes, revert is safe with no data implications. If E4's live
undeploy already happened, redeploying `acousticbrainz_bpm` is possible only by
restoring the source files from the pre-revert state and running
`supabase functions deploy acousticbrainz_bpm`; there is no reason to do so.

---

## 18. Out of Scope

The following adjacent items were observed during diagnosis and deliberately
excluded per Guardrails §7 ("Never refactor opportunistically"):

- **`[functions.deliver-notifications]` and `[functions.auth-confirm]` blocks in
  `supabase/config.toml`.** Both reference Edge Functions absent from the local tree.
  Feature Input directs "verify — not found locally" notes for `auth-confirm` in
  docs, and does not mention `deliver-notifications` (already partially handled by
  the `stale-architecture-docs` feature). Both are left in place pending Tony's
  confirmation of their live status.
- **`docs/reference/audits/CODEBASE_AUDIT.md`** and
  **`docs/reference/audits/ICON_AUDIT_AND_LUCIDE_MIGRATION.md`**. Both reference
  files being deleted here (empty scaffolding, `banner_test_screen.dart`). They are
  point-in-time audit snapshots and are not updated retroactively.
- **Cross-feature docs referencing `sql/…` paths.** 26 references across other
  `docs/features/**/ARCHITECT_PLAN.md` files cite the old `sql/` paths. Rewriting
  those historical plan documents is out of scope; the referenced scripts still
  exist (just at a new path) so no forensic data is lost.
- **`docs/reference/bpm/ACOUSTICBRAINZ_BPM_FEATURE.md`**. Already flagged at the top
  as historical ("AcousticBrainz is shut down… retained for historical reference"),
  so no edit needed.
- **`.github/copilot-instructions.md`**. Its wording about `setlists/` is outdated
  with respect to `song_enrichment_service.dart` (which lives under `features/songs/`
  now), but that is a general governance file and not in this Feature Input.
- **The five pre-existing unstaged macOS working-tree modifications**
  (`macos/Podfile`, `macos/Podfile.lock`,
  `macos/Runner.xcodeproj/project.pbxproj`, two `Package.resolved` files).
  Guardrails §7. The Engineer must exclude these from every commit in this branch.
- **Dependency version upgrades.** `flutter pub outdated` reports `go_router 17.0.1
→ 17.3.0`; not relevant since we're removing `go_router` entirely, but the
  Engineer must not opportunistically upgrade any other package.
- **Cleanup of `.DS_Store` files outside the `sql/` tree** even where they exist in
  other directories under `supabase/functions/`, `docs/reference/`, etc. Not in
  scope.

---

## Discrepancies Between Feature Input and Codebase Reality

Documented here for transparency; none change the scope of the fix:

| #   | Feature Input claim                                                   | Verified reality                                                               |
| --- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| 1   | Placeholder comment at `lib/app_shell.dart:208`                       | Real path is `lib/features/shell/app_shell.dart:208` — verified line matches.  |
| 2   | `lib/features/setlists/song_enrichment_service.dart:85`               | Real path is `lib/features/songs/song_enrichment_service.dart:85`.             |
| 3   | `lib/features/setlists/external_song_lookup_service.dart:251`         | Real path is `lib/features/songs/external_song_lookup_service.dart:251`.       |
| 4   | `sql/experiments/` and `sql/maintenance/` contain "placeholder stubs" | Neither directory exists on disk. Only five subdirs exist (as itemized in §5). |
| 5   | ~41 SQL scripts in `sql/`                                             | 35 scripts total.                                                              |
| 6   | Pre-existing unstaged working-tree change to `pubspec.yaml`           | No such change. Working tree shows five macOS-related modifications instead.   |
| 7   | Docs list 10 Edge Functions and 9 exist locally                       | Confirmed exactly.                                                             |

---
