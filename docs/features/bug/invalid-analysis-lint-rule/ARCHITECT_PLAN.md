# Feature Slug
bug/invalid-analysis-lint-rule

# Feature Title
Fix unrecognized Dart analyzer lint in Problems tab

# Problem Summary
`analysis_options.yaml` line 66 enables `unnecessary_non_null_assertion` under
`linter: rules:`. This is not a real Dart lint rule name, so the analyzer
(and VS Code's Problems tab) reports a configuration warning: "isn't a
recognized lint rule."

# Root Cause (confidence: HIGH)
Confirmed by extracting the full lint rule registry compiled into the
installed Dart SDK's `analysis_server.dart.snapshot`
(`/opt/homebrew/share/flutter/bin/cache/dart-sdk`, Dart 3.13.1 / flutter_lints
6.0.0, matching this repo's pinned `flutter_lints: ^6.0.0` in
[pubspec.yaml](../../../pubspec.yaml)). No rule named
`unnecessary_non_null_assertion` exists in `package:linter/src/rules/`. The
only related valid rules are `unnecessary_null_checks` (already listed on the
line directly above, line 65) and `cast_nullable_to_non_nullable`. The invalid
entry is a duplicate/typo of `unnecessary_null_checks`, not a distinct rule
that needs replacing — the correct intent (flagging unneeded non-null
assertions) is already covered by `unnecessary_null_checks`.

Corroborating evidence: `git log` shows this line was already present as of
commit `b78dd4a` (tooling change unrelated to lint content); it is referenced
nowhere else in the codebase except one QA report
([docs/features/revert-sheet-scroll-collapse-header-footer/QA_REPORT.md](../../../docs/features/revert-sheet-scroll-collapse-header-footer/QA_REPORT.md))
that logged it as a pre-existing, non-blocking warning — confirming no other
plan, doc, or CI gate depends on this literal rule name.

# Existing System Analysis
`analysis_options.yaml` is a single flat config file: `include:
package:flutter_lints/flutter.yaml`, an `analyzer: errors:` severity-override
block, and a `linter: rules:` block that pins additional lints on top of
`flutter_lints`. All other 15 rules in that block (`avoid_unnecessary_containers`,
`use_colored_box`, `unnecessary_null_checks`, `avoid_print`, etc.) are valid
registered lint names — verified against the same extracted rule list. This is
the only invalid entry in the file.

# Proposed Solution
Delete the single invalid line (`unnecessary_non_null_assertion: true`, line
66). Do not add a replacement rule: `unnecessary_null_checks` on the
preceding line already provides the intended coverage, so adding another rule
would be scope creep not requested by this bug and not justified by any gap
in current coverage.

# Database Impact
n/a

# Flutter Architecture Changes
n/a — no Dart source, widget, controller, or provider changes. Config-only.

# Files to Create
None.

# Files to Modify
- [analysis_options.yaml](../../../analysis_options.yaml) — remove line 66
  (`    unnecessary_non_null_assertion: true`) only. No other line in this
  file changes.

# Files Off-Limits
- All application/test/migration/config files other than
  `analysis_options.yaml` — this is a single-line lint-config typo fix with
  no functional code path to touch.
- `pubspec.yaml` / `pubspec.lock` — no dependency change; `flutter_lints`
  version is not the problem (the rule name has never existed in this
  package).
- `docs/features/revert-sheet-scroll-collapse-header-footer/QA_REPORT.md` —
  historical record of a prior run; do not edit past QA reports.

# Change Budget
- `analysis_options.yaml`: -1 line, 0 lines added (net -1).
- New files: 0
- New public classes/methods: 0
- New dependencies: 0

# System Impact Map
- Gigs: unaffected
- Rehearsals: unaffected
- Setlists: unaffected
- Members: unaffected
- Auth: unaffected
- Routing: unaffected
- Notifications: unaffected
- Platforms: unaffected (analyzer config applies uniformly; no
  platform-conditional code touched)

# Regression Risk
LOW. Single-line removal of a rule that has never been recognized or enforced
by the analyzer (an unrecognized rule name is ignored for linting purposes
itself, only surfaced as its own separate config warning) — no lint that was
ever actually active changes behavior. No auth/session/routing/init-order/DB
paths touched.

# Engineer Task Breakdown
1. In `analysis_options.yaml`, delete line 66
   (`    unnecessary_non_null_assertion: true`) from the `linter: rules:`
   block. Leave line 65 (`unnecessary_null_checks: true`) and all surrounding
   lines untouched.

# Verification Plan
Tier 1 (pre-deploy, static, no running app):
1. Run `flutter analyze` (or open the Problems tab) and confirm the specific
   diagnostic "`unnecessary_non_null_assertion` isn't a recognized lint rule"
   no longer appears anywhere in the output.
2. Confirm `flutter analyze` issue count for `analysis_options.yaml` itself
   is zero (no new config warnings introduced by the edit).
3. Diff `analysis_options.yaml` against `main` and confirm the only change is
   the deletion of line 66 — no other rule, `analyzer:` entry, or `include:`
   line was touched.

Tier 2 (post-deploy): n/a — this is a local static-config fix with no runtime
or deployed-function behavior to re-verify after merge.

# QA Regression Areas
- Confirm `flutter analyze` overall error/warning count did not increase
  elsewhere (ensures no accidental edit beyond the one line).
- Confirm the `analyzer: errors:` severity-override block (unused_import,
  use_build_context_synchronously, etc.) is unchanged, since those are the
  gates the Copilot pipeline actually depends on.

# Rollout Strategy
Standard PR merge to `main`; no migration, no feature flag, no staged
rollout — config-only change takes effect on next analyzer run.

# Out of Scope
- Auditing or changing any of the other lint rules already in
  `analysis_options.yaml`.
- Upgrading `flutter_lints` or `lints` package versions.
- Adding a replacement/stronger rule for non-null-assertion checking beyond
  the existing `unnecessary_null_checks`.
