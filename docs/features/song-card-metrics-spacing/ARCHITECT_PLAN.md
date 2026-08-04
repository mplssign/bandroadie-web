# ARCHITECT_PLAN.md

## 1. Feature Slug

bug/song-card-metrics-spacing

## 2. Problem Summary

Song cards render four metric values in a constrained horizontal row: BPM, Duration, Key, and Tuning. In the current layout, fixed-width leading columns and 12px gutters consume too much width before the trailing tuning badge, which currently only gets leftover space through an expanded region. This causes tuning truncation (ellipsis in reorder card) or clipping under tighter layouts, especially when a key badge is present. The bug affects the shared Flutter layout across Web, iOS, Android, and macOS.

## 3. Root Cause

Primary root cause: insufficient reserved horizontal space for the tuning value in both live metric-row implementations, combined with overly generous inter-column spacing and fixed leading widths.

Confirmed code evidence (HIGH confidence):

- `song_card.dart` uses fixed slots for BPM and Duration, then conditionally inserts key and key gutter, and finally gives tuning only remaining space via `Expanded` with no minimum reservation.
- `reorderable_song_card.dart` similarly gives tuning only remaining space via `Expanded`; all three 12px gutters plus fixed leading slots reduce available tuning width on narrow cards.
- `SongCardLayout.trailingColWidth` exists but is not used by either live card.
- `reorderable_song_card.dart` explicitly ellipsizes tuning text (`maxLines: 1`, `overflow: TextOverflow.ellipsis`) so truncation is guaranteed when width runs short.

Confidence: HIGH (directly observed in source).

## 4. Reference Docs Consulted

- `docs/agents/ARCHITECT.md`
- `docs/agents/GUARDRAILS.md`
- `docs/agents/OPERATING_MODEL.md`
- `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` (setlist/song-card domain context)

No dedicated reference document specific to this exact song-card metrics-spacing bug was found.

## 5. Existing System Analysis

Current live metric rows:

- `lib/features/setlists/widgets/song_card.dart` (`_buildMetricsRow`):
  - BPM fixed width
  - Gutter
  - Duration fixed width
  - Conditional gutter + key badge only when key exists
  - Tuning in `Expanded` (right-aligned, no reserved minimum width)
- `lib/features/setlists/widgets/reorderable_song_card.dart` (`_buildMetricsRow`):
  - BPM fixed width
  - Gutter
  - Duration fixed width
  - Gutter
  - Key fixed slot
  - Gutter
  - Tuning in `Expanded` (right-aligned, no reserved minimum width)

Shared tokens:

- `lib/app/theme/design_tokens.dart` class `SongCardLayout`
  - `metricsGutter = 12`
  - `bpmColWidth = 68`
  - `durationColWidth = 60`
  - `keyColWidth = 64`
  - `trailingColWidth = 128` (currently unused)

Dead-code check:

- `lib/features/setlists/widgets/song_metrics_row.dart` appears unused (search for `SongMetricsRow(` returns only the constructor definition in the same file).

Behavioral conclusion:

- The layout currently prioritizes spacing/leading columns over the trailing tuning label, violating the requirement that built-in tuning labels remain legible.

## 6. Proposed Solution

Use a token-driven layout tightening plus a guarded minimum-width strategy for tuning.

Planned changes:

1. Reduce spacing between all four metrics by tightening shared `SongCardLayout` tokens (gutter and leading fixed-column widths).
2. Normalize both live cards to the same four-slot row structure (`BPM | Duration | Key | Tuning`) so behavior is consistent between detail and reorder views.
3. Apply `SongCardLayout.trailingColWidth` as a tuning minimum-width target in the live rows only if needed to meet the no-truncation bar for built-in labels with capo suffixes; keep tuning flexible via `Expanded` so narrow screens still degrade gracefully for long custom names.
4. Keep text-overflow behavior for custom/unbounded tuning names (expected), while ensuring built-in short labels are not truncated in standard card widths.

What must not change:

- No changes to key business logic, tuning selection logic, BPM/Duration edit flows, providers/controllers/repositories, or data persistence.
- No changes to `song_metrics_row.dart` (dead code, out of scope for this bug).

## 7. Database Impact

Database: not applicable.

- Migrations: unaffected
- RLS: unaffected
- RPCs: unaffected
- Triggers: unaffected

## 8. Flutter Architecture Changes

- State management: unaffected (no provider/controller/model changes)
- Repositories/services: unaffected
- Widgets affected:
  - `song_card.dart` metrics-row layout only
  - `reorderable_song_card.dart` metrics-row layout only
- Theme tokens affected:
  - `SongCardLayout` spacing/width constants in `design_tokens.dart`

## 9. Files to Create

none

## 10. Files to Modify

| File                                                       | What changes                                                                                                                     |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `lib/app/theme/design_tokens.dart`                         | Tighten shared `SongCardLayout` spacing/column tokens to reclaim width for tuning; keep token-level single source of truth.      |
| `lib/features/setlists/widgets/song_card.dart`             | Align `_buildMetricsRow` to shared four-slot structure, consume updated tokens, and ensure tuning gets sufficient trailing room. |
| `lib/features/setlists/widgets/reorderable_song_card.dart` | Consume updated tokens and keep layout consistent with `song_card.dart` for tuning room and alignment behavior.                  |

Implementation boundary policy:

- Migration policy: not required
- Edge function deploy: not required
- New dependencies: not allowed
- New files: none

## 11. Files Off-Limits

| File                                                   | Reason                                                                       |
| ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `lib/features/setlists/widgets/song_metrics_row.dart`  | Verified unused; this bug is scoped to live card widgets only.               |
| `lib/features/setlists/tuning/tuning_helpers.dart`     | Tuning label mapping/logic is not the root cause; layout-only fix requested. |
| `lib/features/setlists/setlist_repository.dart`        | No data-layer change required for a spacing/layout bug.                      |
| `lib/features/setlists/setlist_detail_controller.dart` | No state-flow changes required.                                              |
| `lib/main.dart`                                        | Guardrail: initialization order must not change.                             |

## 12. System Impact Map

| System                                 | Impact                                  |
| -------------------------------------- | --------------------------------------- |
| Gigs                                   | unaffected                              |
| Rehearsals                             | unaffected                              |
| Setlists / Catalog                     | affected (song-card rendering only)     |
| Members / RBAC                         | unaffected                              |
| Auth / Session                         | unaffected                              |
| Routing                                | unaffected                              |
| Notifications                          | unaffected                              |
| Platform (iOS / Android / Web / macOS) | affected (shared Flutter widget layout) |

## 13. Regression Risk

LOW.

Rationale:

- Change scope is small and UI-only.
- No backend/data/auth/routing/init-order touch points.
- Affected behavior is localized to two rendering widgets plus shared layout tokens.
- Main risk is visual regressions (column alignment/overflow) across screen widths and with/without key badge.

## 14. Engineer Task Breakdown

1. Update `SongCardLayout` token values in `design_tokens.dart` to reduce inter-metric spacing and reclaim trailing width.
2. Refactor `song_card.dart` `_buildMetricsRow` to match deterministic four-slot structure using shared tokens (including key slot handling consistency).
3. Update `reorderable_song_card.dart` `_buildMetricsRow` to use the same slot strategy and tokenized spacing.
4. Evaluate built-in tuning labels with capo suffixes under representative narrow widths; if still truncating, apply `SongCardLayout.trailingColWidth` as minimum reservation strategy in both live rows.
5. Confirm `SongMetricsRow(` remains unreferenced and untouched.
6. Run `git diff --stat` and verify only planned files changed.

## 15. Verification Plan

Exactly two tiers.

### Tier 1 — Pre-deployment (must pass before `supabase db push`)

(No schema/function changes in this feature. `supabase db push` is not required; tier retained for pipeline consistency.)

- `-- PRE-DEPLOY TEST 1:` Static usage check
  - Confirm `SongMetricsRow(` has zero call sites outside `song_metrics_row.dart`.
- `-- PRE-DEPLOY TEST 2:` Token propagation check
  - Confirm both live widgets reference `SongCardLayout` token constants (no hardcoded per-widget spacing).
- `-- PRE-DEPLOY TEST 3:` Source-scope check
  - `git diff --stat` shows only planned files under this feature scope.

### Tier 2 — Post-deployment (run after `supabase db push` succeeds)

(Not DB-related; treat as post-implementation validation after app build/run.)

- `-- POST-DEPLOY TEST 1:` Repro regression test (with key present)
  - Use songs populated with BPM + Duration + Key + built-in tuning labels (`Standard`, `Half-Step`, `Drop D`, `Open G`) and capo suffixes (` • C1` to ` • C12`).
  - Verify tuning remains legible in both setlist detail card and reorder card.
- `-- POST-DEPLOY TEST 2:` Repro regression test (without key)
  - Verify column alignment remains stable and tuning remains fully legible.
- `-- POST-DEPLOY TEST 3:` Cross-platform spot-check
  - Validate on Web and at least one native platform emulator/device that no clipping or unexpected wrapping occurs.
- `-- POST-DEPLOY TEST 4:` Custom long-name behavior
  - Verify very long custom tuning names may ellipsize without breaking row layout (expected out-of-scope behavior).

## 16. QA Regression Areas

- Primary: song-card tuning visibility when BPM, Duration, Key, and Tuning are all present.
- Both surfaces: setlist detail card (`song_card.dart`) and reorder card (`reorderable_song_card.dart`).
- With/without key badge: confirm no tuning regression either way.
- Built-in tuning catalog + capo suffix labels: confirm fully legible under typical narrow mobile widths.
- Cross-platform parity: Web, iOS, Android, macOS rendering consistency.
- Non-target behaviors sanity: BPM/Duration edit interactions and tuning picker behavior unchanged.

## 17. Rollout / Migration Strategy

- No migration or backend rollout required.
- Ship as a normal Flutter client patch.
- QA sign-off required before merge.

## 18. Out of Scope

- Any tuning business-logic changes (mapping, parsing, capo encoding).
- Any key badge behavior/business-logic changes.
- Any BPM/Duration editing behavior changes.
- Any cleanup/removal/refactor of unused `song_metrics_row.dart`.
- Any database, RPC, Supabase, or notification work.
