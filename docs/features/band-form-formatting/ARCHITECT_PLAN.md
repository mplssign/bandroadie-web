# ARCHITECT_PLAN — band-form-formatting

## Feature Slug

`band-form-formatting`

## Feature Title

Normalize formatter output in the band form screen

## Problem Summary

Two locations in `lib/features/bands/band_form_screen.dart` are inconsistent with
the repository's Dart formatter output. Tony ran the formatter and preserved the
exact resulting diff on rescue branch `rescue/band-form-formatting-20260913`
at commit `a8e064a` (3 insertions, 3 deletions). Current `main` (HEAD
`f57c6bb`) matches that rescue commit's pre-image byte-for-byte at both sites,
so the same two edits are still pending on `main`. This maintenance ticket
lands those edits on a formal feature branch cut from clean `main`, without
using the rescue branch's history.

## Root Cause

The two sites were introduced by hand or by an older formatter version and were
never rewrapped to match current formatter output. Confidence:

- **HIGH — site identification and pre-image match.** `git show a8e064a --
  lib/features/bands/band_form_screen.dart` shows a 6-line diff at
  `@@ -326,7 +327,8 @@` and `@@ -2358,8 +2359,7 @@`. The current `main` blob
  (`git show HEAD:lib/features/bands/band_form_screen.dart | sed -n
  '325,332p;2355,2365p'`) matches the rescue commit's `-` (pre-image) lines
  exactly. Both changes touch only whitespace and newlines; no tokens change.
- **MEDIUM — formatter idempotence.** The rescue commit is presumed to be
  `dart format` output, but the Dart SDK version used to produce it is not
  recorded. If a later `dart format --set-exit-if-changed` (run under whatever
  SDK is bound to the `sdk: ">=3.3.0 <4.0.0"` constraint in `pubspec.yaml`)
  produces different wrapping, the edit will not be idempotent under CI. This
  is flagged as a Tier 1 verification step (see Verification Plan) rather
  than a blocker, because the rescue commit's shape is the exact target
  Tony asked to land.

### Discrepancy in Feature Input

The Feature Input's Additional Context describes site #2 as "collapse the
`Border.all(color: Colors.white.withValues(alpha: 0.8))` expression onto one
formatter-selected line." That description does not match the code or the
rescue commit. The actual site #2 is:

```dart
side: BorderSide(
    color: AppColors.primary.withValues(alpha: 0.6)),
```

collapsed to:

```dart
side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
```

The three `Border.all(...)` occurrences in the file (L1825, L1859, L1910) use
`width:` and none of them uses `withValues(alpha: 0.8)`. Per architect rules
("trust the code and note the discrepancy"), this plan targets the actual
`BorderSide` site confirmed by `git show a8e064a`. Engineer must not attempt
to also change any `Border.all(...)` line based on the Feature Input's
description.

## Existing System Analysis

`lib/features/bands/band_form_screen.dart` is the shared create/edit band
screen used across all platforms. It hosts the `_BandFormScreenState`
save flow (site #1, the `StorageException` throw inside the image-upload
guard) and the private `_BackupSheetPanel` widget (site #2, the outlined
action button style). Neither site is on a public API surface:

- Site #1 is inside a private `State` method that throws a
  `StorageException` only when image upload silently fails. The exception
  message is unchanged; only its constructor-argument line wrapping
  changes.
- Site #2 is a `BorderSide` inside `OutlinedButton.styleFrom(...)` in a
  private `StatelessWidget`. Only the argument wrapping changes; the
  `AppColors.primary.withValues(alpha: 0.6)` value is unchanged.

Neither Riverpod providers nor repositories are involved. No band-scoped
state, no `activeBandProvider` interaction, no Supabase call is touched.

## Proposed Solution

Apply the exact two edits from `git show a8e064a` to
`lib/features/bands/band_form_screen.dart` on the new feature branch. Do
not adopt the rescue branch's history. Engineer leaves the working-tree
change uncommitted through QA; Manager will land it as a fresh commit
on `feature/band-form-formatting` after literal QA APPROVED. The
resulting diff versus `main` must equal the rescue commit's diff
character-for-character within
`lib/features/bands/band_form_screen.dart`.

Engineer may produce the edit either by:

1. Applying the rescue commit's patch directly (`git show a8e064a --
   lib/features/bands/band_form_screen.dart | git apply --index`), or
2. Running `dart format lib/features/bands/band_form_screen.dart` and
   confirming the resulting diff equals the rescue commit's diff.

Path 2 is preferred because it also validates the MEDIUM-confidence
formatter-idempotence concern. If Path 2 produces a diff that differs
from the rescue commit's diff, Engineer must stop and report; the
plan does not authorize any wrapping other than the rescue commit's.

## Database Impact

Not applicable. No migrations, no RLS policy changes, no RPC changes,
no `SECURITY DEFINER` functions, no triggers. No data reads or writes
are affected — the exception throw only fires on a pre-existing error
path.

## Flutter Architecture Changes

None. No new controllers, providers, notifiers, repositories, models,
services, screens, or widgets. No changes to state management, band
isolation, deep-link handling, init order (`WidgetsFlutterBinding` →
URL strategy → orientation → `AppVersionService.init` →
`validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp`
[native] → `DeepLinkService` → `runApp`), or platform-conditional code.
No `--dart-define` config changes. No dependency changes.

## Files to Create

- `docs/features/band-form-formatting/ARCHITECT_PLAN.md` — this file
  (Architect-created, not Engineer-created).
- `docs/features/band-form-formatting/ENGINEER_REPORT.md` — Engineer
  creates this per pipeline convention. It documents the two edits
  and ends with the literal line `Ready For QA: Yes`, added only
  after every Engineer-run validation check in the Engineer Task
  Breakdown passes. Engineer leaves this file uncommitted through
  QA; Manager performs the sole commit and push after literal QA
  APPROVED.
- `docs/features/band-form-formatting/QA_REPORT.md` — QA will create per
  pipeline convention.

No source files, tests, migrations, config, assets, or lockfiles are
created.

## Files to Modify

- `lib/features/bands/band_form_screen.dart` — apply the two edits
  described in "Proposed Solution". Expected diff versus `main`:
  exactly 3 insertions and 3 deletions, matching
  `git show a8e064a -- lib/features/bands/band_form_screen.dart`
  character-for-character.

## Files Off-Limits

- Any other file under `lib/**` — no drive-by refactors, no
  formatter runs on other files, no import reordering, no unrelated
  wrapping changes.
- `test/**` — no test changes; there is no runtime behavior to test.
- `supabase/**` — no migrations, no edge functions, no RPCs.
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`,
  `dart_defines.json` — no dependency, lint, or config changes.
- `android/**`, `ios/**`, `macos/**`, `web/**`, `windows/**`,
  `linux/**` — no platform config or entitlements changes.
- `assets/**`, `marketing/**`, `scripts/**`, `tools/**`, `Makefile`,
  `run.sh`, `vercel.json`, `package.json`, `capacitor.config.json` —
  no build, tooling, or deploy changes.
- `rescue/band-form-formatting-20260913` branch — do not merge from,
  rebase against, or cherry-pick out of the rescue branch. It exists
  only as a reference artifact of the preserved diff.

## Change Budget

- `lib/features/bands/band_form_screen.dart`: net line delta = **0**
  (`+3`, `-3`). Site #1 gains 1 line (single-line throw → two-line
  wrap). Site #2 loses 1 line (two-line `BorderSide` → single line).
  Net zero.
- Expected new source files: **0**.
- Expected new public classes / methods / functions / top-level
  variables: **0**.
- Expected new imports: **0**.
- Expected new dependencies (pub / native / edge): **0**.
- Expected new tests: **0** (pure formatting; nothing to assert at
  runtime).
- Expected new documentation files: **3** under
  `docs/features/band-form-formatting/` (architect plan, engineer
  report, QA report) — standard pipeline artifacts, not source.

QA must fail-closed on any diff that exceeds this budget, even by
one line, even in whitespace elsewhere in the file.

## System Impact Map

| System | Status |
| --- | --- |
| Gigs | Unaffected |
| Rehearsals | Unaffected |
| Setlists | Unaffected |
| Members / Bands | Unaffected (this file is the shared band form; formatting-only edit does not change any user-facing behavior in the create/edit-band flow) |
| Auth / PKCE / DeepLinks | Unaffected |
| Routing | Unaffected |
| Notifications | Unaffected |
| Supabase RLS / RPC / Migrations | Unaffected |
| Init order / RuntimeConfig | Unaffected |
| iOS | Unaffected |
| macOS | Unaffected |
| Android | Unaffected |
| Web | Unaffected |
| Windows | Unaffected |
| Linux | Unaffected |

## Regression Risk

**LOW.** The edit changes only whitespace and newlines within existing
Dart expressions. No token changes, no semantic changes, no
compilation-unit boundary changes, no imports, no public API. Neither
site is on an auth, session, routing, init-order, or database path.
`StorageException` is thrown identically (same const constructor, same
message string). `BorderSide` is constructed identically (same color
value, same alpha). Every downstream caller sees byte-identical
runtime behavior.

The only residual risk is that a stray extra whitespace edit slips in
from Engineer's local formatter. That is caught by the diff-budget
check in the Verification Plan.

## Engineer Task Breakdown

1. On `feature/band-form-formatting` (already cut from `main` at
   `f57c6bb`), open `lib/features/bands/band_form_screen.dart`.
2. At the site of `throw const StorageException('Image upload failed.
   Please try again.');` (currently a single line around L329), wrap
   the constructor argument onto a second line so the source matches
   the `+` side of `git show a8e064a` for that hunk.
3. At the site of `side: BorderSide(` / `    color:
   AppColors.primary.withValues(alpha: 0.6)),` (currently two lines
   around L2362-2363, inside `_BackupSheetPanel`'s
   `OutlinedButton.styleFrom(...)`), collapse the two lines onto a
   single line so the source matches the `+` side of `git show
   a8e064a` for that hunk.
4. Do not touch any other line, any other file, or run `dart format`
   over any file other than
   `lib/features/bands/band_form_screen.dart` (if the formatter is
   used at all — the direct patch path is acceptable).
5. Run the full Tier 1 verification suite (all six items in the
   Verification Plan: diff-stat check, diff-body equality versus
   `git show a8e064a`, `dart format … --set-exit-if-changed`,
   `flutter analyze`, `flutter test`, and the forbidden-string
   ripgrep sweep) locally against the working-tree changes as an
   Engineer pre-check. Only once every item passes, write
   `docs/features/band-form-formatting/ENGINEER_REPORT.md`
   documenting the two edits, capturing the exact `git diff --stat`
   output and the result of each Tier 1 check, and ending with the
   literal line `Ready For QA: Yes`. Leave the source edit and the
   report file uncommitted through QA.

Engineer must not commit, push, merge, rebase, or cherry-pick anything
on `feature/band-form-formatting`. The rescue branch
`rescue/band-form-formatting-20260913` is also off-limits for merge,
rebase, or cherry-pick. Manager performs the sole commit and push
after literal QA APPROVED.

## Verification Plan

### Tier 1 — pre-deploy, mechanically executable without a running app

QA runs all of the following and gates on each:

1. `GIT_OPTIONAL_LOCKS=0 git diff --stat main -- lib/features/bands/band_form_screen.dart`
   must print exactly one line, and that line must end with
   `| 6 +++---` (3 insertions, 3 deletions in that file). Any other
   file appearing in a wider `git diff --stat main` is a budget
   violation — fail.
2. `GIT_OPTIONAL_LOCKS=0 git diff main -- lib/features/bands/band_form_screen.dart >
   /tmp/feature.diff` and `git show a8e064a --
   lib/features/bands/band_form_screen.dart > /tmp/rescue.diff`,
   then `diff -u /tmp/rescue.diff /tmp/feature.diff` must show
   identical hunk bodies (patch author, hash, and commit-message
   headers may differ; the `@@ … @@` hunk headers and every `+`/`-`
   line must match). Fail on any body difference.
3. `dart format lib/features/bands/band_form_screen.dart
   --output=none --set-exit-if-changed` must exit `0` (formatter is
   idempotent on the post-edit file). If this fails, the wrapping
   Engineer applied does not match the current formatter's output;
   stop and report — do not "fix" it by reformatting, because the
   Feature Input authorized only the rescue-commit shape.
4. `flutter analyze` must report zero new errors and zero new
   warnings versus `main`. Because no new symbols or imports are
   introduced, the expected delta is zero.
5. `flutter test` must pass with no new failures versus `main`.
   Because no runtime code changes, existing tests must remain
   green; no new test is required or expected.
6. A ripgrep sweep confirms none of the following strings appear
   anywhere in the feature-branch diff versus `main`:
   `import `, `class `, `void `, `Future`, `provider`, `Notifier`,
   `Supabase`, `rpc(`, `.from(`, `RLS`, `security definer`,
   `Border.all`, `Colors.white`, `alpha: 0.8`. Presence of any of
   these in the diff indicates scope creep — fail. (`Border.all`,
   `Colors.white`, and `alpha: 0.8` are called out specifically
   because the Feature Input's misdescription could tempt an
   Engineer or QA reviewer to expect those tokens in the diff; they
   must not appear.)

### Tier 2 — post-deploy

Not applicable. No deployed surface changes. No RPC, migration, edge
function, or client-visible behavior is altered.

### Owner-run checks (Tony, at PR-review or apply/release time)

None required. This change has no user-visible behavior. Tony may
optionally spot-check that the create-band screen still renders and
that a deliberate image-upload failure still surfaces the same
`StorageException` message, but neither is a gate — both are
guaranteed by the token-level identity of the change.

## QA Regression Areas

None functionally. QA's real gate is the Tier 1 static checks above.
There is no runtime surface to regress, so no widget-test or
integration-test walkthrough is scoped.

## Rollout Strategy

Standard PR merge into `main`. No feature flag, no phased rollout, no
migration ordering, no cache invalidation, no client version pin, no
edge-function redeploy. Once merged, the change is live on every
platform's next build with zero user-visible impact.

## Out of Scope

- Any other formatting fix in `band_form_screen.dart` or elsewhere.
- Any refactor of `_BandFormScreenState.save`, image-upload retry
  logic, or `StorageException` handling.
- Any refactor of `_BackupSheetPanel`, its outlined-button style, or
  its color tokens.
- Any change to `Border.all(...)` occurrences at L1825, L1859, or
  L1910 — the Feature Input's mention of a `Border.all(color:
  Colors.white.withValues(alpha: 0.8))` change is a misdescription;
  no such site exists and no such change is authorized.
- Bulk `dart format` across the repository.
- Any adoption or merge of `rescue/band-form-formatting-20260913`.
- Any change to `analysis_options.yaml`, `pubspec.yaml`, or CI
  configuration.
