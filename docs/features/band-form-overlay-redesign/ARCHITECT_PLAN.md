# Architect Plan — `feature/band-form-overlay-redesign`

## Feature Slug

`feature/band-form-overlay-redesign`

## Feature Title

Band Form Overlay Redesign (Create & Edit) — Shared Header, Sectioned Layout, Currency Setting, Inline Backup/Restore

## Cycle 4 Amendment (2026-09-15)

**Cumulative Cycle Number: 4.** QA Cycle 3 returned REQUIRES CHANGES with
two Critical and two Warning findings. This amendment resolves each in
place. All other settled behavior — the 30-code shortlist, composite
Bulgaria/Ecuador labels, migration shape, backup/restore surfacing,
delete-band placement, `create_band` RPC untouched, `get_band_full_state`
untouched, `data_backup_service.dart` untouched, and the
migration-remains-unapplied-in-this-pipeline rule — is preserved. QA reruns
Tier 1 after Engineer.

- **C1 [root-cause-diagnosis] corrected — `ActiveBandState` equality omits
  `currencyCode`.** The prior claim in Proposed Solution §1 that currency
  "does not need to be" part of `ActiveBandState.==` was wrong. Confirmed by
  direct read of
  [active_band_controller.dart lines 186–212](lib/features/bands/active_band_controller.dart#L186-L212):
  `ActiveBandState.==` compares `activeBand?.id / name / imageUrl /
avatarColor`, and `Object.hash(...)` in `hashCode` hashes the same four
  fields. Neither `currencyCode` nor `timezone` participates. Riverpod
  3.4.2 `Notifier` uses `previous != next` to decide notification (verified
  in `~/.pub-cache/hosted/pub.dev/riverpod-3.4.2/lib/src` per Cycle 3
  terminal history), so a currency-only `updateActiveBand(...)` produces a
  state where `previous == next` and every existing `activeBandProvider`
  watcher — Financials summary, transaction cards, entry-details sheet,
  savings sheet, gig-pay display/input, gig-expense display/input, event
  editor, view-gig drawer, PDF launch — silently retains the old symbol
  until an unrelated observed field changes. This is the owning fix
  because equality is the notification-decision gate for every consumer of
  the provider; adding a parallel notification mechanism would leave the
  contract broken and require every future field to opt in individually.
  `lib/features/bands/active_band_controller.dart` moves out of Files
  Off-Limits with a surgical, authorized change (Files to Modify) restricted
  to one comparison line and one `Object.hash` argument. Regression test
  spelled out in Verification T1-4b.

  **Timezone omission — assessed, not authorized in this feature.**
  `timezone` is identically omitted from both `==` and `hashCode`. This is
  a latent parallel silent-notification defect for timezone-only edits, but
  no visible in-app UI consumer today reads `activeBand.timezone` through
  `activeBandProvider` in a way that would produce a currency-style stale
  render (the calendar edge function reads `bands.timezone` server-side).
  Feature Input decision-scope and the Cycle 4 amendment brief both
  restrict broadening to unrelated equality fields. Timezone is documented
  as an observed adjacent defect in Out of Scope for a follow-up ticket;
  Engineer must **not** add `timezone` to `==` or `hashCode` in this
  cycle.

- **C2 [code-quality] — currency test compaction cap.**
  `test/features/bands/band_currency_test.dart` at 292 lines is 2.65× the
  60–110 Cycle 3 budget and exceeds QA's mandatory 2× Critical threshold.
  The complete ordered 30-record `countryLabel` / `isoCode` / `name` /
  `symbol-or-null` comparison and focused format assertions must be
  preserved verbatim. Budget for this file is corrected to **≤ 220 lines
  (hard cap; QA-mandated Cycle 4 target)**, ideally 110–180. Coverage is
  not reduced — only the vertically-expanded per-record `expect` shape is
  compacted into a single ordered list of expected records iterated with
  one indexed `expect` per field (see Change Budget § "Compaction
  pattern").

- **W1 [code-quality] — `gig_pay_bottom_sheet.dart` cap tightened.** The
  Riverpod-consumer conversion + active-band lookup landed at net +7
  against the +1 to +4 Cycle 3 budget. Budget is tightened to **≤ +6 net
  (Cycle 4 W1 cap)** with the smallest legitimate consolidation — collapse
  the two-line active-band `currencyCode` fallback into a single expression
  and fold the `currencySymbol:` argument onto the existing
  `CurrencyTextField(...)` constructor line. No unrelated refactor; no
  behavioral change; no new import beyond what Cycle 3 already added.

- **W2 [implementation-gap] — `@immutable` annotation contradiction
  resolved.** `lib/features/bands/currency/band_currency.dart` stays pure
  Dart. The `@immutable` annotation requirement is **removed** from
  Proposed Solution §2, from the file's allowed-import set in Engineer Task
  Breakdown step 3, and from all downstream references. `BandCurrency` and
  `BandCurrencyPickerGroup` remain immutable-by-`final`-fields with `const`
  constructors — this is idiomatic Dart and semantically equivalent to
  `@immutable` at zero dependency cost. `pubspec.yaml` stays off-limits;
  the Engineer's Cycle 3 decision to omit the annotation was correct given
  the off-limits `pubspec.yaml` constraint, and this amendment records the
  correction as an Architect-owned plan change, not an Engineer deviation.

- **Migration remains unapplied.** No database migration is applied or
  directed to apply as part of this pipeline. `20260915120000_add_currency_code_to_bands.sql`
  stays in the tree unapplied; Tony owns staging + production application
  per Rollout Strategy.

## Cycle 5 Amendment (2026-09-15)

**Cumulative Cycle Number: 5.** QA Cycle 4 returned REQUIRES CHANGES for a
single finding — C3 [database-safety]. All Cycle 3 findings — C1
(active-band notification equality), C2 (currency test compaction cap),
W1 (`gig_pay_bottom_sheet.dart` net delta), W2 (`@immutable` annotation) —
are CLOSED against the current uncommitted working tree, and
`flutter analyze`, `flutter test`, and T1-6 static SQL review pass. **C3 is
not a code defect. It is a plan-methodology contradiction.** Cycle 4's
Verification Plan classified T1-7 "Ephemeral DB apply check (Supabase
local or a scratch DB)" as a Tier 1 QA gate. Manager, Engineer, and QA
are categorically prohibited by this pipeline's operational-safety rules
from touching any database — local, scratch, branch, staging, or
production. QA Cycle 4 correctly refused to execute T1-7 and then blocked
APPROVED because the plan required it. This amendment resolves the
contradiction by reclassifying runtime DB execution as owner-run,
outside QA's executable gate. **No application source, no test file, and
no migration file changes for Cycle 5.** Engineer does not re-run;
Engineer Task Breakdown, Files to Modify, Files to Create, Change
Budget, Flutter Architecture Changes, System Impact Map, and Regression
Risk are all unchanged. Only the Verification Plan classification,
Rollout Strategy sequencing, and QA Regression Areas residual bookkeeping
change.

- **C3 [database-safety] resolved by reclassification, not code change.**
  T1-7 is removed from Tier 1 QA gates. Runtime migration verification —
  twice-apply idempotency, `'ZZZ'` CHECK rejection, DEFAULT `'USD'`
  application to existing rows — is reclassified as owner-run in Tier 2
  under a new "Ephemeral apply drill" block, alongside the existing
  staging/production apply punch list. QA's database-facing gate stops
  at T1-6 static SQL review. Every Cycle 3/4 finding on application code
  remains closed; C3 requires zero code change.
- **Static SQL verification remains the sole QA-executable DB gate.**
  T1-6 continues to parse and confirm, without executing SQL against any
  database:
  - Filename
    `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
    exists on the branch, sorts strictly after every other filename in
    `supabase/migrations/` at the branch point, and does not collide
    with any existing filename.
  - `ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD'`
    is present verbatim on `public.bands` — default is `'USD'`, column
    is `NOT NULL`, statement is `IF NOT EXISTS` idempotent.
  - `DROP CONSTRAINT IF EXISTS bands_currency_code_check` precedes
    `ADD CONSTRAINT bands_currency_code_check` — the pair-of-statements
    idempotent shape for the CHECK.
  - The CHECK `IN (...)` list parses to exactly 30 unique ISO code
    string literals, in the exact order and set specified in Database
    Impact § (`USD, CAD, MXN, EUR, GBP, CHF, PLN, CZK, HUF, DKK, SEK,
NOK, ISK, RON, RSD, ALL, MKD, MDL, UAH, ARS, BOB, BRL, CLP, COP,
GYD, PYG, PEN, SRD, UYU, VES`). Dedupe into a set; assert size 30;
    assert set-equality against the 30-code set T1-2 asserts against
    the Dart `BandCurrency.shortlist`.
  - The migration file contains no `CREATE OR REPLACE FUNCTION`, no
    `SECURITY DEFINER`, no `GRANT`, no `REVOKE`, no `CREATE POLICY`, no
    `ALTER POLICY`, and no `DROP POLICY` — a pure column-add plus a
    single CHECK constraint, and nothing else.
- **Runtime DB execution is an accepted residual / owner-run
  dependency.** The absence of any QA-executed migration apply,
  twice-apply idempotency verification, `'ZZZ'` CHECK rejection check,
  or DEFAULT `'USD'` verification is an accepted, documented residual
  of this pipeline's operational-safety rules (no agent touches any
  DB). By itself, this absence does **not** block QA APPROVED. When
  T1-1, T1-2, T1-2b, T1-3, T1-4, T1-4b, T1-5, T1-6, and T1-8 all pass
  and the Cycle 3/4 Change Budget caps (C1 active-band controller
  ≤ +3, C2 `band_currency_test.dart` ≤ 220 lines, W1
  `gig_pay_bottom_sheet.dart` ≤ +6) hold, QA issues APPROVED with an
  explicit "Accepted residual: runtime DB execution deferred to
  owner-run Tier 2 punch list" note in the QA report.
- **Migration must exist in the PR and precede client behavior — as a
  hard release-order dependency, not an authorization to act.** The
  migration file
  `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
  must be present, committed, and reviewed in the PR alongside the
  client code changes — this is enforced by T1-6, which fails APPROVED
  if the file is missing, malformed, or drifted from the Database
  Impact § contract. In every environment where the client change is
  exercised (staging, production), the migration must be applied
  **before** the client build that reads or writes
  `bands.currency_code` runs against that environment; otherwise every
  `SELECT` on the new column errors and every `UPDATE` including the
  column errors. Migration application is Tony's responsibility (see
  Rollout Strategy). **No agent — Architect, Engineer, QA, or Manager
  — applies it in this pipeline.** This is stated as a dependency the
  release must respect, not as an authorization for any agent to
  operate on a database.
- **QA_REPORT.md is malformed and must be rewritten from scratch in
  Cycle 5.**
  `docs/features/band-form-overlay-redesign/QA_REPORT.md` currently
  contains two concatenated `# QA Report` documents (headers at line 1
  and line 180) — the residue of a truncated Cycle 4 cleanup attempt.
  This amendment does **not** edit that file. The next QA cycle
  (Cycle 5) must **overwrite** `QA_REPORT.md` with a single, well-formed
  Cycle 5 QA report — do not attempt to merge, patch, or preserve either
  of the two concatenated Cycle 4 documents. The Cycle 5 report should
  summarize Cycle 4's disposition (C1, C2, W1, W2 closed against the
  current tree; C3 was the sole remaining blocker and is resolved by
  this Cycle 5 Amendment's reclassification, not by any code or
  migration change) in its history section, then record Cycle 5's own
  Tier 1 execution and verdict.
- **Migration remains unapplied — restated for Cycle 5.** No database
  migration is applied or directed to apply as part of this pipeline.
  `20260915120000_add_currency_code_to_bands.sql` stays in the tree
  unapplied; Tony owns staging + production application per Rollout
  Strategy.

## Cycle 6 Amendment (2026-09-15)

**Cumulative Cycle Number: 6. Confidence: HIGH.** Owner-requested,
open-PR (#307) label-only revision superseding QA Cycle 5 APPROVED.
Owner feedback verbatim: *"Under America, it lists 'United States /
Ecuador' it should just be 'United States'."* This is a product-copy
correction to a single record in
`lib/features/bands/currency/band_currency.dart` plus the two test
files that assert against it. Every non-USD row, all currency names,
all symbols, the 30-code CHECK migration, the `Band` model, the
`ActiveBandState` equality fix, the `SectionCard` widget, the
Backup/Restore inline redesign, the header-swap, the money-formatter
fan-out, the persistence contract, and every other Cycle 3/4/5
decision remain closed and unchanged. **Confirmed by direct read of
[lib/features/bands/currency/band_currency.dart line 25](lib/features/bands/currency/band_currency.dart#L25):
the shortlist entry currently reads `countryLabel: 'United States /
Ecuador'`. That is the sole product-copy defect this amendment
corrects.**

- **New product interpretation — USD row uses the single-country
  label.** In `BandCurrency.shortlist`, the record with `isoCode:
'USD'` must have exactly `countryLabel: 'United States'`. The
  derived `pickerLabel` — computed as `'$countryLabel — $name
($isoCode)'` — therefore becomes exactly `'United States — US
Dollar (USD)'`. No source-code path other than that single
  `countryLabel` string literal changes to accomplish this: the
  getter shape at
  [band_currency.dart line 18](lib/features/bands/currency/band_currency.dart#L18)
  is unchanged. USD remains one unique, selectable, persisted ISO
  code; `defaultCode` remains `'USD'`; no separate Ecuador picker
  row is added anywhere.
- **EUR remains the Bulgaria composite.** The EUR record's
  `countryLabel` continues to read exactly `'Eurozone / Bulgaria'`
  and the derived picker label continues to read exactly `'Eurozone
/ Bulgaria — Euro (EUR)'`. Tony has separately confirmed the EUR
  row stays as-is; the Cycle 6 correction does **not** touch the
  Europe group. If Tony issues a follow-up correction to the EUR
  label, that would be a separate cycle, not a bundled edit here.
- **Picker cardinalities are preserved exactly.** The picker still
  returns 30 unique ISO-backed rows, grouped America 3 / Europe 16
  / South America 11, in the Feature Input order. `USD` still sits
  in America as the first record. `EUR` still sits in Europe as the
  first record. No group loses a row; no group gains a row; no
  standalone Ecuador row is introduced anywhere.
- **Bulgaria stays visible in the picker; Ecuador is now fully
  absent from every visible label.** Bulgaria retains its composite
  presence via the EUR row. Ecuador — previously visible only inside
  the USD composite — is no longer surfaced in the picker at all.
  Existing System Analysis §, Root Cause §, and Proposed Solution §
  historical prose describing why Ecuador's ISO code coincides with
  USD in the supplied 32-row list is factually still accurate and
  remains, but every downstream assertion that Ecuador must appear
  in a picker label or `countryLabel` is inverted: Ecuador must
  **not** appear in any visible label after Cycle 6.
- **Exact source touches (three files, byte-narrow):**
  - `lib/features/bands/currency/band_currency.dart` — change
    exactly one string literal on
    [line 25](lib/features/bands/currency/band_currency.dart#L25)
    from `'United States / Ecuador'` to `'United States'`. No
    other line in this file changes.
  - `test/features/bands/band_currency_test.dart` — three
    focused changes: (a) the ordered fixture entry at
    [line 11](test/features/bands/band_currency_test.dart#L11)
    updates its `_country:` value to `'United States'`; (b) the
    focused test named `'USD preserves the Ecuador composite
mapping in America'` (currently
    [lines 115–124](test/features/bands/band_currency_test.dart#L115-L124))
    renames to `'USD is a single United States row in America'`,
    updates its `countryLabel` assertion to `'United States'`,
    and **removes** its `contains('Ecuador')` assertion —
    replaced by a positive assertion that
    `usd.countryLabel == 'United States'` (already covered by
    the fixture but restated at the focused test for a clear
    failure message); (c) the EUR-composite test at
    [lines 126–135](test/features/bands/band_currency_test.dart#L126-L135)
    is byte-frozen — `'Eurozone / Bulgaria'` and
    `contains('Bulgaria')` both remain.
  - `test/features/bands/band_currency_picker_test.dart` — two
    focused changes: (a) the USD picker-label assertion at
    [line 37](test/features/bands/band_currency_picker_test.dart#L37)
    updates its expected key to exactly `'United States — US
Dollar (USD)'`; the EUR assertion at
    [line 42](test/features/bands/band_currency_picker_test.dart#L42)
    remains exactly `'Eurozone / Bulgaria — Euro (EUR)'`; (b)
    the test named `'Bulgaria and Ecuador do not have standalone
rows'` (currently
    [lines 48–55](test/features/bands/band_currency_picker_test.dart#L48-L55))
    is renamed to `'Bulgaria retains composite row and Ecuador is
fully absent'` and its two assertions are updated so it
    (i) still asserts no `items` key across any group matches
    `RegExp(r'^Bulgaria —')` — the Bulgaria composite is inside
    the EUR label but Bulgaria never heads a standalone row —
    and (ii) newly asserts that no `items` key across any group
    contains the literal substring `'Ecuador'` anywhere (not
    just at the start of the label). This is stricter than the
    Cycle 5 `RegExp(r'^Ecuador —')` check by design: after
    Cycle 6 the word Ecuador must not appear anywhere in any
    picker label, including inside a composite.
- **`ARCHITECT_PLAN.md` prose sync.** Downstream in this file
  (Proposed Solution §2 label table, Proposed Solution §2 composite
  prose, Verification T1-2 composite-label bullet, Verification T1-2b
  USD assertion and Ecuador-exclusion bullet, Engineer Task Breakdown
  step 3, and Tier 2 PR-test step 3) each contain one or more literal
  references to the pre-Cycle-6 `'United States / Ecuador'` USD label
  or to Ecuador-appears-in-composite verification. Each of those
  spots is updated in place by this amendment so downstream sections
  read consistently with the Cycle 6 product interpretation; the
  Cycle 3/4/5 amendment history above is preserved verbatim as
  cycle history and not retroactively edited.
- **`FEATURE_INPUT.md` remains historical input and is NOT edited.**
  Confirmed by direct read: `FEATURE_INPUT.md` describes the redesign
  goals (shared header, sectioned layout, currency setting, inline
  backup/restore) and does not enumerate the country-string strings
  for the curated shortlist — it delegates the shortlist wording to
  Architect interpretation. The Cycle 6 correction is a product
  interpretation refinement over that same delegation, not a Feature
  Input revision. Architect does not touch `FEATURE_INPUT.md`;
  Engineer does not touch it; QA does not touch it.
- **`PR_BODY.md` is NOT edited by Architect; label references there
  need Manager sync.** The current open-PR body at
  [PR_BODY.md line 13](docs/features/band-form-overlay-redesign/PR_BODY.md#L13)
  still reads `- USD label: \`United States / Ecuador — US Dollar
(USD)\``. The Architect brief explicitly forbids Architect from
  editing `PR_BODY.md`. That single bullet will be updated by Manager
  during the standard PR body sync step after Engineer's Cycle 6
  code change lands and QA re-verifies — Architect flags this as a
  known-stale bullet requiring Manager sync, not as an Architect
  action.
- **`ENGINEER_REPORT.md` and `QA_REPORT.md` are NOT edited by
  Architect.** Both files contain stale prose referencing the
  Cycle 5 `'United States / Ecuador'` composite (ENGINEER_REPORT.md
  item 13; QA_REPORT.md items 57 and 147). Both will be rewritten
  from scratch by Engineer and QA respectively during their Cycle 6
  passes — Architect does not merge, patch, or edit either.
- **Prior QA Cycle 5 APPROVED is superseded.** The Cycle 5
  APPROVED verdict was rendered against the pre-Cycle-6 USD label.
  Owner acceptance testing (this Cycle 6 revision) reopens the QA
  gate. QA **must not** rely on the Cycle 5 report and **must**
  issue a fresh Cycle 6 verdict after Engineer's Cycle 6 pass. The
  Cycle 6 QA gate re-executes every Tier 1 check (T1-1, T1-2,
  T1-2b, T1-3, T1-4, T1-4b, T1-5, T1-6, T1-8) against the updated
  tree; APPROVED requires all of them to pass **and** the Cycle 6
  label-only source touches (single `countryLabel` line in
  `band_currency.dart`, three focused updates in
  `band_currency_test.dart`, two focused updates in
  `band_currency_picker_test.dart`) to hold under the Cycle 6
  change budget below.
- **Cycle 6 change budget — label-only correction.** Sub-budgets
  layered on top of the Cycle 3/4/5 caps, not replacing them.
  Measured against the current Cycle 5-APPROVED working tree
  (i.e. relative to the immediately preceding cycle's file
  contents, not against `main`). Any excursion beyond these
  sub-budgets is a scope breach QA must flag.
  - `lib/features/bands/currency/band_currency.dart`: **net delta
    = 0** (one literal string edit in place; no line added, no
    line removed). Cycle 5 file size 267 lines is preserved
    verbatim.
  - `test/features/bands/band_currency_test.dart`: **net delta
    ≤ ±3** (the fixture map entry update is a literal-string
    swap on one line; the renamed focused test's body changes
    from four `expect`s to three because the `contains('Ecuador')`
    assertion is removed; overall file stays at ≤ 220 lines per
    the Cycle 4 C2 hard cap and Cycle 5 file size 161 remains
    inside the cap).
  - `test/features/bands/band_currency_picker_test.dart`: **net
    delta ≤ +3** (the USD picker key updates to the new label;
    the renamed test replaces one regex assertion with one
    substring-containment assertion and preserves the Bulgaria
    regex assertion). Cycle 5 file size 56 lines. Post-Cycle 6
    ceiling remains inside the Cycle 3 60–100-line intended
    range for this file.
  - `docs/features/band-form-overlay-redesign/ARCHITECT_PLAN.md`:
    net delta accepted (this Cycle 6 amendment + downstream
    literal-reference sync). Architect is the sole owner of
    this file per the guardrails.
  - No other file in `lib/`, `test/`, `supabase/migrations/`,
    `supabase/functions/`, `pubspec.yaml`, `pubspec.lock`,
    `web/`, `ios/`, `android/`, `macos/`, or `linux/` may
    change under Cycle 6. In particular:
    `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
    is **byte-frozen** — the CHECK constraint's 30-code list is
    ISO-code-only and never referenced the string "Ecuador" or
    "United States" at the SQL layer.
  - New public classes/methods: 0. New dependencies: 0. New
    providers: 0. New migrations: 0. New RPCs/`SECURITY
    DEFINER` functions: 0. New RLS policies: 0.
- **Regression risk — LOW for Cycle 6.** The change is a single
  visible label. No data-model change, no persistence-format change,
  no equality-notification change, no formatter change, no
  permission-gate change, no init-order change, no platform-conditional
  change, no auth-flow change, no RLS change, no RPC change, no
  migration change. The bands-scoped MEDIUM-risk classification from
  Cycle 3 (formatter fan-out) and Cycle 4 (active-band notification
  equality) remains accurate for the cumulative feature but does not
  ratchet upward for this cycle. QA can re-run Tier 1 mechanically
  against the label-corrected tree.
- **Locale-aware number formatting stays out of scope for Cycle 6.**
  Tony's separate, prior broader request for locale-aware
  number-formatting behavior (locale-specific thousands separators,
  decimal separator, decimal-place precision per currency) **is not
  resolved** by this amendment and is not authorized for Engineer
  implementation in Cycle 6. The open product-choice questions —
  which locale drives grouping (band's country, device locale, or a
  new user-level setting), and what decimal precision each currency
  uses (all 2 decimals as today, or per-ISO-4217 minor-unit
  precision) — are **not** answered by the owner feedback quoted
  above, and Engineer must not silently choose defaults inside
  `BandCurrency.formatCents` under cover of this label revision. If
  Engineer's Cycle 6 diff modifies `NumberFormat` locale or
  `decimalDigits` inside `BandCurrency.formatCents` or the PDF
  builder, QA must flag that as a scope breach and REQUIRES CHANGES.
  The locale-formatting decision is a follow-up cycle that starts
  from a separate Feature Input and answered product questions, not
  a Cycle 6 side effect.
- **Migration remains unapplied — restated for Cycle 6.** No database
  migration is applied or directed to apply as part of this pipeline.
  `20260915120000_add_currency_code_to_bands.sql` stays in the tree
  unapplied and byte-frozen; Tony owns staging + production
  application per Rollout Strategy.

## Problem Summary

`BandFormScreen` — the single screen backing both Create New Band and Edit
Band — still uses a bespoke `FrostedGlassBar` header and a flat, sequentially
labeled field layout. It is the only user-facing full-screen form in the app
that hasn't been migrated to the shared `AppAppBar`/Forui `FHeader` pattern
plus titled section cards. In Edit mode, Backup and Restore are hidden behind
a single "Backup / Restore Data" button that opens a modal bottom sheet, so
those data-safety actions are always one extra tap away. There is no per-band
currency concept anywhere in the app — every money amount in Financials, Gigs,
and the Financials PDF export hardcodes a `$` symbol, so bands operating in
CAD, EUR, GBP, etc. still see USD chrome throughout the app.

## Root Cause

**Confidence: HIGH.** Two orthogonal, code-confirmed facts converge here:

1. **UI/structural drift.** [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
   (2425 lines) predates the shared `AppAppBar` migration and the section-card
   pattern introduced by [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
   and [add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart).
   `_buildAppBar()` at line 1705 returns a `FrostedGlassBar`, not the
   `AppAppBar` wrapper other overlays now use. Section grouping doesn't exist —
   fields render as `_buildSectionLabel(...)` + input pairs in a
   `SingleChildScrollView`. Backup/Restore is gated behind
   `_showBackupRestoreSheet()` (line ~540) which builds `_BackupSheetPanel`
   tiles in a modal bottom sheet; the shared "Backup / Restore Data"
   `OutlinedButton.icon` at line ~2202 is the only way to reach it.

2. **No currency abstraction.** `Band` at [lib/app/models/band.dart](lib/app/models/band.dart)
   has no currency field. `public.bands` has no `currency_code` column
   (repo-wide grep of `supabase/migrations/` confirms). Every money call site
   in the app hardcodes `$` directly in the format string, in one of two
   patterns: an ad-hoc `'\$$dollarsFormatted.${cents…}'` string interpolation
   (six occurrences across `financials_screen.dart`, `financial_entry.dart`,
   `gig_expense_subview.dart`, `gig.dart`, `add_financial_entry_bottom_sheet.dart`)
   or `NumberFormat.currency(symbol: '\$', ...)` in the PDF builder. There is
   no shared money formatter, so making the app currency-aware is inherently
   a cross-cutting change, not a single-file fix.

Neither is a bug — both are the natural residue of the shared form being older
than the shared header pattern, and the app never previously needing multi-
currency support.

## Existing System Analysis

### Shared header pattern (target)

- [lib/components/ui/app_app_bar.dart](lib/components/ui/app_app_bar.dart) —
  `AppAppBar` wraps Forui `FHeader` (or `FHeader.nested` when `leading` is
  provided). Adopted throughout the app (`venue_form_screen.dart`,
  `new_setlist_screen.dart`, `contact_form_screen.dart`, `financials_screen.dart`,
  `settings_screen.dart`).
- [lib/components/ui/app_icon_button.dart](lib/components/ui/app_icon_button.dart) —
  `AppIconButton` wraps `FButton.icon`. In [new_setlist_screen.dart](lib/features/setlists/new_setlist_screen.dart#L897-L904)
  the back-icon pattern is `AppIconButton(icon: AppIcons.arrowLeft, color:
AppColors.primary, onPressed: () => Navigator.of(context).pop())`. This is
  the pattern the redesigned Band Form should adopt (back icon, not close
  icon — matches the Feature Input's Expected Behavior).

### Section-card pattern (target)

- Two identical private `_SectionCard` widgets exist in the codebase — one in
  [event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart#L3554-L3587)
  and another copy in [add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L1375-L1408).
  Both hardcode `kEdCardBg` and `kEdCardBorder` from `event_editor_theme.dart`
  and `Color(0xFFFAFAFA)` for the title. That styling is coupled to the event
  editor's fixed dark palette — reusing it verbatim in the Band Form would
  break light/dark mode support that the rest of the screen already respects
  via `context.colors.*` tokens. Per Feature Input decision #4, the Band Form
  needs a **theme-aware** equivalent, not a copy of that private widget.

### Band Form current structure

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
  — 2425 lines. Key regions confirmed by direct read:
  - Enum + constructor + state (lines 1–150).
  - `initState`/`dispose` with edit-mode `draftBandProvider` wiring (lines 145–225).
  - `_submitForm` / `_createBand` (lines 296–459) — currency-agnostic today.
    Timezone persistence uses a follow-up `.update({'timezone': ...})` after
    the `create_band` RPC (lines 337–340). This is the precedent to follow
    for currency.
  - `_updateBand` (lines 461–553) — issues `supabase.from('bands').update({...})`
    then manually constructs an updated `Band` and calls
    `activeBandProvider.updateActiveBand(...)`. This construction site (line
    ~504) will need `currencyCode:` added.
  - `_showBackupRestoreSheet`, `_startExport`, `_showExportDialog` (unused),
    `_showImportDialog`, `_performExport`, `_performImport` (lines 540–1035).
    Backup/Restore business logic is fine — only the entry point moves from
    a bottom sheet into a visible Band Data section in Edit mode.
  - `_deleteBand` + confirmation dialog (lines 1050–1120) — untouched by this
    plan; Delete Band stays at the bottom of the overlay.
  - `build`, `_buildAppBar`, `_buildTimezoneSection`, `_buildEmailInput`,
    `_buildSubmitButton`, `_EmailPill`, `_BackupSheetPanel` (lines 1560–2425).
- [lib/features/bands/edit_band_screen.dart](lib/features/bands/edit_band_screen.dart)
  is a thin `StatelessWidget` wrapper (19 lines). Not touched.

### Timezone precedent (the pattern currency mirrors)

- `_timezoneOptions` list + `_buildTimezoneSections` + `_buildTimezoneSection`
  at [band_form_screen.dart](lib/features/bands/band_form_screen.dart#L2062-L2127)
  — a grouped `AppDropdown<String>` built on `FSelectSection<String>`.
  Permission gate: `currentUserPermissionsProvider` → `canEditBandSettings`
  in edit mode; always enabled in create mode. Currency uses the same
  pattern and the same gate (Feature Input decision #3).

### `AppDropdown<String>` / `FSelect<T>` selection semantics (constrains the currency picker)

- Confirmed by direct read of [lib/components/ui/app_dropdown.dart](lib/components/ui/app_dropdown.dart#L1-L125)
  and Forui 0.26.0 (`~/.pub-cache/hosted/pub.dev/forui-0.26.0/lib/src/widgets/select/select_item.dart`),
  which is the version resolved in `pubspec.lock`.
- `AppDropdown<T>` wraps `FSelect<T>.rich` with `FSelectControl<T>.lifted(value:
value, onChange: onChanged)` and a caller-supplied `format(T)` for the
  selected-value label. The `T` value is the sole selection identity —
  `format` receives only the value, not the row/section it came from.
- `FSelectSection<T>(items: Map<String, T>)` binds a display label (map key,
  unique per section by Dart-`Map` semantics) to a value `T`. Nothing at the
  Forui level enforces value uniqueness across a section or across the whole
  select, so a `Map<String, String>` may technically contain two keys pointing
  at the same value — but doing so is a bug for two hard reasons:
  (1) tapping either row emits the same value, so both rows visibly resolve
  to a single selected chrome; (2) on edit-mode reconstruction from a
  persisted string, the picker can only match by value, so the originally-
  chosen row is unrecoverable.
- **Design consequence for currency:** the picker's value type is
  `String` (ISO 4217 code, matching what persists to `bands.currency_code`),
  so every picker row **must have a globally unique ISO code**. Any duplicate
  ISO code — no matter which country label heads it — is architecturally
  invalid in this widget. This is the constraint that forces the composite-
  label representation in Proposed Solution §2.
- Timezone does not have this problem: every IANA timezone string in
  `_timezoneOptions` is unique. Currency does have it, because Bulgaria's
  official currency is EUR (Feature Input decision) and Ecuador's is USD —
  two of the 32 supplied country rows collide on ISO code with two other
  supplied rows.

### Currency call sites (13 occurrences across 8 files)

Confirmed by grep + inspection:

| #   | File                                                                                                                                                     | Line     | Kind                                                                                                       |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------- |
| 1   | [lib/shared/widgets/currency_input_field.dart](lib/shared/widgets/currency_input_field.dart#L47)                                                         | 47       | `CurrencyInputController.formattedValue` prefix `'\$'`                                                     |
| 2   | [lib/shared/widgets/currency_input_field.dart](lib/shared/widgets/currency_input_field.dart#L85)                                                         | 85, 256  | `CurrencyInputField.hint` / `CurrencyTextField.hint` default `'\$0.00'`                                    |
| 3   | [lib/app/models/gig.dart](lib/app/models/gig.dart#L244-L252)                                                                                             | 252      | `Gig.formattedPay` `'\$'` prefix                                                                           |
| 4   | [lib/features/events/widgets/gig_expense_subview.dart](lib/features/events/widgets/gig_expense_subview.dart#L40-L45)                                     | 44       | `GigExpenseDraft.formattedAmount` `'\$'` prefix                                                            |
| 5   | [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart#L168-L172)                                     | 172      | `FinancialEntry.formattedAmount` `'\$'` prefix                                                             |
| 6   | [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart#L176-L183)                                     | 182      | `FinancialEntry.formattedDepositToSavings` `'\$'` prefix                                                   |
| 7   | [lib/features/financials/models/financial_entry.dart](lib/features/financials/models/financial_entry.dart#L237-L242)                                     | 241      | `GigPayDetails.formattedAmount` `'\$'` prefix                                                              |
| 8   | [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart#L258-L263)                                               | 262      | `_SavingsSheet._fmt` `'\$'` prefix                                                                         |
| 9   | [lib/features/financials/financials_screen.dart](lib/features/financials/financials_screen.dart#L570-L572)                                               | 571      | `_SummaryHeader.totalFormatted` inline `'\$'`                                                              |
| 10  | [lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart](lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart#L120-L124) | 123      | `_formatSavingsCents` `'\$'` prefix                                                                        |
| 11  | [lib/features/financials/financials_report_builder.dart](lib/features/financials/financials_report_builder.dart#L29)                                     | 29       | `NumberFormat.currency(symbol: '\$', decimalDigits: 2)` for PDF                                            |
| 12  | [lib/features/gigs/widgets/view_gig_drawer.dart](lib/features/gigs/widgets/view_gig_drawer.dart#L613)                                                    | 613      | Consumes `gig.formattedPay` (transitively #3)                                                              |
| 13  | [lib/features/events/widgets/gig_form_fields.dart](lib/features/events/widgets/gig_form_fields.dart#L747-L858)                                           | 747, 858 | Consumes `gigPayDetails.formattedAmount` (transitively #7) and `expense.formattedAmount` (transitively #4) |

Also transitively downstream through model getters (no new prefix logic to
change, only the model getter behind them):
[financial_entry_details_bottom_sheet.dart](lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart#L106)
(reads `entry.formattedAmount` / `entry.formattedDepositToSavings`) and
[event_editor_drawer.dart](lib/features/events/widgets/event_editor_drawer.dart)
(uses `_gigPayDetails` around lines 2029/2053).

### Database precedent

- `bands.timezone` added via [supabase/migrations/20260305000000_band_scoped_calendar.sql](supabase/migrations/20260305000000_band_scoped_calendar.sql#L39):
  `ALTER TABLE bands ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'America/Chicago';`.
  Same idempotent `IF NOT EXISTS` + `NOT NULL` + `DEFAULT` shape works for
  currency and applies the default to all existing rows automatically — no
  separate backfill step is needed.
- [supabase/migrations/20260322100000_print_templates.sql](supabase/migrations/20260322100000_print_templates.sql#L50-L53)
  shows the same pattern for a nullable FK column on `bands`.

### RLS on `bands` (relevant)

Consolidated in [supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql](supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql#L20-L40):

- `bands_select_members` — `is_deleted = false AND is_band_member(id)`
- `bands_update_admins` — `is_band_admin(id)` (both USING and WITH CHECK)
- `bands_insert_authenticated` — `created_by = (select auth.uid())`
- `bands_delete_creator_or_admin` — `is_band_admin(id) OR created_by = (select auth.uid())`

Neither `bands_update_admins` nor `bands_select_members` references specific
columns — they gate the row, not the column set. Adding a new column to
`bands` therefore inherits admin-only update and member-visible read
authorization for free. This is critical: no new policy, no new RPC, no
`SECURITY DEFINER` needed.

### `get_band_full_state` and DataBackupService

- [supabase/migrations/20260521000000_add_start_time_to_date_tables.sql](supabase/migrations/20260521000000_add_start_time_to_date_tables.sql#L54-L56)
  builds the band block via `SELECT row_to_json(b.*)::jsonb INTO band_record`.
  Any new column on `bands` automatically flows through the RPC into
  `bandFullStateProvider` (`lib/features/bands/band_full_state.dart:68`) →
  `Band.fromJson`. **No RPC change required.**
- [lib/features/settings/data_backup_service.dart](lib/features/settings/data_backup_service.dart#L189-L195)
  builds the export via unqualified `SELECT` on `bands`; the restore path
  upserts the row. `currency_code` round-trips automatically. **No backup
  code change required.**

### `create_band` RPC

- [supabase/migrations/087_fix_create_band_no_profile.sql](supabase/migrations/087_fix_create_band_no_profile.sql#L9-L86)
  — `SECURITY DEFINER`, signature `(p_name text, p_avatar_color text,
p_image_url text)`. Timezone in create mode is applied via a post-create
  `bands.update({'timezone': _selectedTimezone}).eq('id', bandId)`
  (line 337–340 of band_form_screen). **Currency follows the same
  post-create UPDATE pattern.** No RPC signature change, no new grant.

## Proposed Solution

Single-track redesign scoped to `BandFormScreen` plus one new column on
`public.bands`. Everything downstream is a mechanical formatter swap; the
persistence pattern for currency mirrors the existing timezone pattern
one-to-one.

### 1. Data layer

- New migration adds `currency_code TEXT NOT NULL DEFAULT 'USD'` to
  `public.bands` with a CHECK constraint restricted to the 30-code shortlist
  from the Feature Input. No backfill logic — the `DEFAULT` handles existing
  rows.
- `Band` model gains `final String currencyCode` with `= 'USD'` in the
  constructor default. `fromJson` parses `json['currency_code'] as String? ??
'USD'`. `toJson` includes `'currency_code': currencyCode`. Adding an
  optional-with-default field keeps every existing `Band(...)` call site
  and every existing test constructing `Band(...)` compilable — validated by
  reading [test/features/auth/auth_gate_anonymous_recovery_test.dart](test/features/auth/auth_gate_anonymous_recovery_test.dart#L210)
  and [test/features/bands/active_band_controller_invalidation_test.dart](test/features/bands/active_band_controller_invalidation_test.dart#L26).
- `ActiveBandState.==` at [active_band_controller.dart lines 186–199](lib/features/bands/active_band_controller.dart#L186-L199)
  compares `activeBand?.id / name / imageUrl / avatarColor` plus
  `isLoading / error / userBands.length / first-userBand id`. `hashCode` at
  lines 202–212 hashes the same first four `activeBand` fields via
  `Object.hash(...)`. **Neither `currencyCode` nor `timezone` participates
  in either.** Riverpod 3.4.2 `Notifier` decides listener notification via
  `previous != next` (verified against
  `~/.pub-cache/hosted/pub.dev/riverpod-3.4.2/lib/src`), so a currency-only
  `updateActiveBand(...)` — the exact call the edit flow now makes at
  `band_form_screen.dart` line 501–522 — produces `previous == next` and
  silently suppresses notification. **`currencyCode` must therefore be
  added to both `==` and `hashCode`.** This is a one-line insertion in
  each: one comparison clause between the existing `avatarColor` clause
  and `isLoading`, and one field appended to `Object.hash(...)` in the
  matching position. Timezone-only edits share the same latent defect but
  are not fixed in this feature (see Cycle 4 Amendment C1 assessment and
  Out of Scope).

### 2. Currency shortlist / formatter (new shared module)

**Cardinalities (state these three separately and consistently everywhere
the plan mentions currency scope):**

- **32 supplied country mappings.** Tony's supplied 32-row list groups
  countries under **America / Europe / South America**. Two of those rows
  collide on ISO code with two other supplied rows: Bulgaria (Europe) maps
  to `EUR`, duplicating the primary Eurozone row; Ecuador (South America)
  maps to `USD`, duplicating the United States row.
- **30 unique persisted ISO codes.** After deduplicating on ISO code, the
  set persisted to `bands.currency_code` is exactly these 30 codes, in the
  ordering shown in the CHECK constraint (Database Impact §):
  America → `USD, CAD, MXN` (3); Europe → `EUR, GBP, CHF, PLN, CZK, HUF,
DKK, SEK, NOK, ISK, RON, RSD, ALL, MKD, MDL, UAH` (16); South America →
  `ARS, BOB, BRL, CLP, COP, GYD, PYG, PEN, SRD, UYU, VES` (11).
- **30 picker rows.** Exactly one selectable row per unique ISO code (per
  the `FSelect<String>` semantics documented in Existing System Analysis §).
  Each row lives in the group of its **first-occurrence** country in the
  supplied 32-row order: `USD` in America (first via United States), `EUR`
  in Europe (first via Eurozone). Bulgaria and Ecuador do **not** get their
  own picker rows.

**Preserving Bulgaria in the visible EUR label; USD uses the single
United States label (Cycle 6).**

For the 29 single-country codes, the picker label follows the format
`"<Country> — <Name> (<Code>)"` (e.g. `"Canada — Canadian Dollar (CAD)"`
and — per Cycle 6 — `"United States — US Dollar (USD)"`), sourcing
country / currency-name / symbol strings verbatim from Tony's supplied
32-row list, with `USD`'s `countryLabel` fixed at exactly `'United
States'` per the Cycle 6 owner correction.

For the single remaining composite code (`EUR`), the picker label uses a
slash-separated composite of both supplied country strings, in
supplied-order, on a single row. The exact strings are:

| ISO code | Group   | Exact picker label                          |
| -------- | ------- | ------------------------------------------- |
| `USD`    | America | `United States — US Dollar (USD)`           |
| `EUR`    | Europe  | `Eurozone / Bulgaria — Euro (EUR)`          |

("Eurozone" is the primary-country string Tony supplied for the EUR row;
Engineer must not paraphrase it — it is the source of truth for the
composite left-hand side.) The single-country USD label and the
composite EUR label both derive from the same `'$countryLabel — $name
($isoCode)'` getter shape at
[band_currency.dart line 18](lib/features/bands/currency/band_currency.dart#L18)
— the getter is not modified in Cycle 6, only the underlying
`countryLabel` string literal for the USD record.

**Module contents (`lib/features/bands/currency/band_currency.dart`):**

- `class BandCurrency { final String countryLabel; final String isoCode;
final String name; final String? symbol; ... }` — **exactly 30 records**,
  one per unique ISO code. For `EUR`, `countryLabel` is the composite
  string `"Eurozone / Bulgaria"`. For `USD`, `countryLabel` is exactly
  `"United States"` (Cycle 6 owner correction — no Ecuador substring
  anywhere). For the other 28, `countryLabel` is the single supplied
  country string.
- Group ordering matches the Feature Input: **America, Europe, South
  America**. `USD` sits in America (first-occurrence via United States);
  `EUR` sits in Europe (first-occurrence via Eurozone).
- `static const String defaultCode = 'USD'`.
- `static List<BandCurrency> shortlist` — the 30 entries, in the same
  order as the CHECK constraint list.
- `static Map<String, BandCurrency> byIsoCode` — `{ for (final e in
shortlist) e.isoCode: e }`; because `isoCode` values are unique across
  the 30 records, this map has exactly 30 entries and no
  earlier-overwrites-later ambiguity.
- `static String symbolFor(String code)` — returns the symbol if the
  shortlist entry has one, otherwise falls back to the ISO code (e.g. `CHF`
  is displayed as text — the supplied list carries no symbol for
  Switzerland, Serbia, or North Macedonia).
- `static String formatCents(int cents, String code)` — the single money
  formatter used by every call site. Delegates to `NumberFormat('#,##0.00',
'en_US')` for the numeric portion, then prefixes `symbolFor(code)`. This
  preserves the current visual (`\$1,234.56`) for USD while transparently
  swapping the prefix for other codes.
- `class BandCurrencyPickerGroup { final String label; final
Map<String, String> items; const BandCurrencyPickerGroup({required this.label,
required this.items}); }` plus
  `static List<BandCurrencyPickerGroup> pickerGroups()` — a pure, widget-free,
  ref-free builder that returns exactly three groups in Feature Input order —
  `America` (3 items), `Europe` (16 items), `South America` (11 items) —
  where each group's `items` map is keyed on the exact picker label
  (`'<Country> — <Name> (<Code>)'`, using the composite label for `USD` and
  `EUR`) and valued on the ISO code. The map preserves supplied-list order
  via Dart's insertion-ordered `Map` semantics; do not sort. This helper is
  the sole source of truth consumed both by production code
  (`_buildCurrencySection` in `band_form_screen.dart` maps each
  `BandCurrencyPickerGroup` to a Forui `FSelectSection<String>` at build
  time — see Proposed Solution §4) and by
  `test/features/bands/band_currency_picker_test.dart` (Verification T1-2b).
  Exposed as public API — not `@visibleForTesting` — because it has a
  legitimate non-test caller. It must not import `forui`, `flutter/widgets`,
  `riverpod`, `package:meta/meta.dart`, or `band_form_screen.dart`; the
  file stays pure Dart with zero third-party imports. Immutability of both
  `BandCurrency` and `BandCurrencyPickerGroup` is guaranteed structurally
  by `final` instance fields plus `const` constructors — no `@immutable`
  annotation is required (Cycle 4 Amendment W2; `pubspec.yaml` stays
  off-limits, no `package:meta` dependency added).

**Persistence contract.** The `AppDropdown<String>` value at rest is the
ISO code and only the ISO code — `countryLabel` is presentation-only and
never persisted, exported, backed up, or synced. Edit-mode reconstruction
is deterministic: a persisted `currency_code` string maps to exactly one
`BandCurrency` (via `byIsoCode`) and therefore to exactly one picker row.
There is no `AppDropdown` value that resolves to more than one row.

### 3. Theme-aware `SectionCard` (new shared widget)

- New `lib/features/bands/widgets/section_card.dart`:
  - Public `class SectionCard extends StatelessWidget` (not private —
    referenced from both create-mode and edit-mode branches of the Band Form,
    and could be reused later without a third copy).
  - Container: `color: context.colors.surfaceElevated`, `border:
Border.all(color: context.colors.border.withValues(alpha: 0.6))`,
    `borderRadius: BorderRadius.circular(Spacing.cardRadius)`, `padding:
EdgeInsets.all(Spacing.space20)`.
  - Title `Text` with `AppTypography.heading2`-shaped style but color
    `context.colors.textPrimary`.
  - This reproduces the **visual language** of the Add Event drawer's
    `_SectionCard` — title above grouped fields inside a rounded card — while
    reading from the theme tokens the rest of the Band Form already uses.
    Does not import or subclass either private `_SectionCard`. Feature Input
    decision #4 (theme-aware).

### 4. Band Form redesign — Create mode

Section order (top → bottom, each a `SectionCard`):

1. **About** — band name (`AppTextFormField` + `FieldHint`), band avatar
   (`_buildAvatarSection`). Existing behavior — including the live avatar
   preview listener, the color picker, and web/native image upload paths —
   is preserved verbatim. Move only the layout wrapper.
2. **Location** — timezone (`_buildTimezoneSection`, unchanged) plus new
   currency picker (`_buildCurrencySection`). Currency dropdown mirrors
   `_buildTimezoneSection`: `AppDropdown<String>` value = ISO code, `format`
   = the picker label defined in Proposed Solution §2 (composite for `USD`
   / `EUR`, single-country for the other 28), `children` = `FSelectSection<
String>` groups keyed on America (3 rows) / Europe (16 rows) / South
   America (11 rows) — **30 picker rows total, every value unique**. Always
   enabled in create mode (matches timezone).
3. **Invite Members** — existing email input + `EmailDomainShortcutBar` +
   `_EmailPill` block, moved verbatim inside a section card. Section header
   text stays "Invite Members" (matches current inline label). No behavioral
   change.
4. Below the last card: `AppButton` submit ("Create Band"), Cancel
   `TextButton`, then a `SizedBox` for bottom safe-area padding. No Delete /
   Backup / Restore in create mode.

### 5. Band Form redesign — Edit mode

Section order:

1. **About** — same fields as create mode.
2. **Location** — timezone + currency. Both gated by `canEditBandSettings`
   (identical helper text `'Only admins can change the timezone'` and a
   parallel `'Only admins can change the currency'` when disabled).
3. **Band Data** — replaces the current `_showBackupRestoreSheet` entry
   point. Two visible `AppButton`s (or `OutlinedButton.icon` matching the
   current `Backup Data` visual weight), side by side on wide layouts,
   stacked on narrow. Backup gated by `canExportBandData`; Restore gated by
   `canDeleteBand`. Loading states (`_isExporting` / `_isImporting`) drive
   the same `CircularProgressIndicator` swap already in `_BackupSheetPanel`.
   `_startExport` and `_showImportDialog` become the button `onPressed`
   callbacks directly — no bottom sheet. Bulleted description strings from
   `_BackupSheetPanel` may render inside the Band Data card body as static
   copy. No new backup/restore logic.
4. Below the last card: submit ("Save Changes"), Cancel `TextButton`, and
   Delete Band `TextButton` (admin-only via `canDeleteBand`). **Delete Band
   stays outside Band Data**, at the bottom of the overlay (Feature Input
   decision #5).

### 6. Shared overlay header

- Replace `_buildAppBar()` with `AppAppBar(backgroundColor: context.colors.appBarBg,
leading: AppIconButton(icon: AppIcons.arrowLeft, color: AppColors.primary,
onPressed: _handleBackPress), title: Text(_isEditMode ? 'Edit Band' : 'New
Band', style: AppTextStyles.title3))`. `_handleBackPress` cancels the
  `draftBandProvider` in edit mode (preserving the existing behavior in
  `_buildAppBar`'s current `GestureDetector.onTap`) then pops.
- Delete `FrostedGlassBar` import.

### 7. Currency plumbing at persistence boundaries

- **Create mode.** After the `create_band` RPC returns a band ID, insert the
  currency update alongside the existing timezone-non-default update block
  (line ~337 of band_form_screen). Two options both compile: (a) always
  update `{timezone, currency_code}` after create — one round trip, no
  early-out — or (b) update only when not USD. Plan chooses (a) because it
  removes the "if not default" branching, keeps create-mode UPDATE
  deterministic, and lets the trigger/notification layer see a single canonical
  post-create state. `create_band` RPC signature is unchanged.
- **Edit mode.** Append `'currency_code': _selectedCurrencyCode` to the
  existing `.update({...}).eq('id', band.id)` call at line ~495. Bump the
  manually constructed `updatedBand` Band(...) call at line ~504 to pass
  `currencyCode: _selectedCurrencyCode`. `activeBandProvider.updateActiveBand`
  already handles propagation.
- **Draft state.** `DraftBandNotifier` is only used for live header avatar
  preview (name / imageUrl / avatarColor) — currency does not need to plumb
  through draft state.

### 8. Money call-site fan-out

Replace all 13 hardcoded `$` sites with `BandCurrency.formatCents(cents,
code)` (or `symbolFor(code)` for input-field prefixes). The four model-level
getters (`Gig.formattedPay`, `GigExpenseDraft.formattedAmount`,
`FinancialEntry.formattedAmount`, `FinancialEntry.formattedDepositToSavings`,
`GigPayDetails.formattedAmount`) are converted **from parameterless getters
into methods taking `String currencyCode`**. This is the smallest change
that keeps the formatter close to the data (existing shape) while giving
call sites a place to inject the current band's code.

Call-site policy: **every UI widget that displays money reads the active
band's `currencyCode` via `ref.watch(activeBandProvider).activeBand?.currencyCode
?? BandCurrency.defaultCode`**. This is a one-line lookup; there's no need
for a dedicated `bandCurrencyCodeProvider` (though nothing in this plan
forbids Engineer from extracting one if all seven consumer widgets otherwise
duplicate the identical fallback expression — that's a mechanical extraction
allowed inside the change budget). The PDF preview screen accepts the ISO
code as a new constructor parameter; the call site in `financials_screen.dart`
reads the code once and threads it through.

The Financials PDF report builder swaps `NumberFormat.currency(symbol: '\$', ...)`
for `NumberFormat.currency(symbol: BandCurrency.symbolFor(code), ...)`. Only
the symbol changes; PDF layout and decimal precision are unchanged.

### 9. Explicitly rejected alternatives (and why)

- **One picker row per supplied country (32 rows, with Bulgaria and
  Ecuador as separate EUR/USD rows).** Rejected because
  `AppDropdown<String>` / `FSelect<String>` uses the value `T` (the ISO
  code) as sole selection identity: duplicate values collapse to a single
  observable selection, and edit-mode reconstruction from a persisted ISO
  string cannot deterministically recover which duplicate row was
  originally chosen. See Existing System Analysis § "AppDropdown /
  FSelect selection semantics" for the confirmed Forui 0.26.0 behavior.
  The composite-label approach in Proposed Solution §2 preserves Tony's
  intentional Bulgaria and Ecuador country information in the visible
  labels while keeping the picker value set uniquely 30-wide.
- **A `BandCurrency` picker value type that carries both country and ISO
  code (e.g. `AppDropdown<BandCurrency>` instead of
  `AppDropdown<String>`).** Would allow 32 distinct picker rows keyed by
  `(country, isoCode)`, but the persistence layer still stores only the
  ISO code — so edit-mode reconstruction still cannot recover which
  `(country, isoCode)` pair was chosen from the persisted string alone.
  Adds a new value type and a custom `format`/equality for zero
  observable benefit. Rejected.
- **Auto-suggest currency from timezone.** Feature Input decision #2 rules
  this out. Independent.
- **Full ISO 4217 list.** Feature Input decision #1 rules this out. Curated
  30-code shortlist only (30 unique ISO codes materialized as 30
  `BandCurrency` records producing 30 picker rows).
- **New `bandCurrencyCodeProvider` scoped provider.** Not required — the
  active band already exposes `currencyCode` via existing
  `activeBandProvider`. Adding another provider is bloat unless Engineer
  observes that every consumer duplicates the fallback string; if so, a
  small `Provider<String>` derived from `activeBandProvider` is inside
  scope. Not mandatory.
- **Currency as a new RPC param on `create_band`.** Would require a new
  `SECURITY DEFINER` migration with matching `REVOKE ALL FROM PUBLIC, anon`
  - `GRANT EXECUTE ... TO authenticated`, a `has_function_privilege`
    verification, and lockstep changes in `data_backup_service.dart`'s restore
    path (which also calls `create_band`). Timezone doesn't do this — it uses
    a post-create UPDATE — and there's no reason currency should. Rejected.
- **Reuse the existing private `_SectionCard`.** Would import
  `event_editor_theme.dart` colors into the Band Form, breaking light/dark
  parity. Rejected per Feature Input decision #4.
- **A "Rest of World" / free-form currency entry option.** Explicitly out
  of scope per Feature Input.

## Database Impact

**One new migration.** No RLS change, no RPC change, no `SECURITY DEFINER`
function change, no trigger change, no policy change.

**File:** `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`

**Filename collision check.** `ls supabase/migrations/ | grep 20260915`
returns no match at the branch point; the most recent existing migration
is `20260912130000_demo_session_capacity_hardening.sql`. `20260915120000`
sorts strictly after it and does not collide with any existing file.

**CHECK constraint cardinality.** The CHECK list contains **exactly 30
unique ISO codes** — the same 30 codes materialized as `BandCurrency`
records in Proposed Solution §2, in identical order. There are no
duplicates: `USD` and `EUR` each appear exactly once in the CHECK list,
even though Tony's supplied 32-row list references them from two country
rows each (Bulgaria/EUR, Ecuador/USD). This is Verification T1-2 case
"exact code set" and T1-6 static review target (a).

**Content shape:**

```sql
-- Add per-band currency setting.
-- Restricted to the curated shortlist from feature/band-form-overlay-redesign.
-- DEFAULT 'USD' applies to all existing rows (no backfill needed).
-- RLS: bands_update_admins already gates writes; bands_select_members
-- already gates reads — column-level authorization is inherited from the
-- row-level policies with no change required.

ALTER TABLE public.bands
  ADD COLUMN IF NOT EXISTS currency_code TEXT NOT NULL DEFAULT 'USD';

ALTER TABLE public.bands
  DROP CONSTRAINT IF EXISTS bands_currency_code_check;

ALTER TABLE public.bands
  ADD CONSTRAINT bands_currency_code_check
  CHECK (currency_code IN (
    'USD','CAD','MXN',
    'EUR','GBP','CHF','PLN','CZK','HUF','DKK','SEK','NOK','ISK',
    'RON','RSD','ALL','MKD','MDL','UAH',
    'ARS','BOB','BRL','CLP','COP','GYD','PYG','PEN','SRD','UYU','VES'
  ));

COMMENT ON COLUMN public.bands.currency_code IS
  'ISO 4217 currency code for this band. Restricted to the curated shortlist '
  'from feature/band-form-overlay-redesign. Defaults to USD.';
```

Row count in the `CHECK … IN (…)` clause: 3 (America) + 16 (Europe) + 11
(South America) = 30. Any Engineer-side re-typo of this list is caught by
Verification T1-6 static review case (c) and T1-2 case "exact code set".

**Idempotency.** `ADD COLUMN IF NOT EXISTS` + `DROP CONSTRAINT IF EXISTS`
before `ADD CONSTRAINT` means the migration is safe to re-apply.

**Backfill.** None. `NOT NULL DEFAULT 'USD'` applies to all existing rows
at `ALTER TABLE` time; no separate `UPDATE` statement is needed.

**Cascade impact.** `get_band_full_state` uses `SELECT row_to_json(b.*)`
(see [supabase/migrations/20260521000000_add_start_time_to_date_tables.sql](supabase/migrations/20260521000000_add_start_time_to_date_tables.sql#L54)) —
new column automatically appears in the returned JSON. Confirmed by direct
read. **RPC is not touched.**

**Tony must apply this migration to production before the app change is
deployed** so bands' `currency_code` reads succeed. Standard staging-first
release order applies; owner-run per Tony's usual schema-change practice.
Applying the migration on an older client is safe — clients ignore unknown
JSON keys, and the DEFAULT keeps writes without the column valid.

## Flutter Architecture Changes

- **Band model** (`lib/app/models/band.dart`) — one new optional-with-default
  field.
- **New shared module** (`lib/features/bands/currency/band_currency.dart`) —
  pure Dart, no dependencies on Flutter widgets. Tier 1 unit-testable.
- **New shared widget** (`lib/features/bands/widgets/section_card.dart`) —
  theme-aware, no state, no riverpod.
- **BandFormScreen restructure** — same file, same class, same state, same
  submission handlers. Adds `_selectedCurrencyCode` state field mirroring
  `_selectedTimezone` and `_initialCurrencyCode` mirroring
  `_initialTimezone`; `_isDirty` gains a currency check; build tree
  reorganizes into `SectionCard` wrappers.
- **No new controller. No new notifier. No new repository. No new provider**
  (unless Engineer opts into the mechanical extraction described in
  Proposed Solution §8 — inside scope, not required).

**Init order:** Unchanged. Not touched. [docs/reference/general/RUNTIME_CONFIG.md](docs/reference/general/RUNTIME_CONFIG.md)
does not need updating; [docs/reference/general/AI_DECISIONS.md](docs/reference/general/AI_DECISIONS.md)
does not need a new entry (no architectural exception is being taken).

## Files to Create

**Total: 6 new files** (1 migration, 2 lib, 3 test).

1. `supabase/migrations/20260915120000_add_currency_code_to_bands.sql` — new
   migration (see Database Impact).
2. `lib/features/bands/currency/band_currency.dart` — curated shortlist,
   symbol lookup, `formatCents`, `defaultCode`, plus the pure widget-free
   `pickerGroups()` builder and its `BandCurrencyPickerGroup` value type
   (Proposed Solution §2).
3. `lib/features/bands/widgets/section_card.dart` — theme-aware section
   card wrapping a title + child.
4. `test/features/bands/band_currency_test.dart` — Tier 1 unit test for
   the shortlist and formatter (Verification T1-2).
5. `test/features/bands/band_currency_picker_test.dart` — Tier 1 unit test
   for the pure picker group builder (`BandCurrency.pickerGroups()`), per
   Verification T1-2b. Consumes only `BandCurrency` and
   `BandCurrencyPickerGroup`; must not import `forui`, `flutter/material`,
   `flutter/widgets`, `riverpod`, or `band_form_screen.dart`.
6. `test/features/bands/band_model_test.dart` — Tier 1 unit test for
   `Band.fromJson` currency default and round-trip via `toJson`.

## Files to Modify

Each entry includes the specific change intent, not a rewrite.

- **`lib/app/models/band.dart`** — add `final String currencyCode` field
  (default `'USD'`), extend `Band.fromJson` and `Band.toJson`, extend the
  constructor. `toString()` unchanged.
- **`lib/features/bands/active_band_controller.dart`** — Cycle 4 Amendment
  C1 surgical fix. Add exactly one comparison clause
  (`activeBand?.currencyCode == other.activeBand?.currencyCode &&`) inside
  `ActiveBandState.==` between the existing `avatarColor` clause and the
  `isLoading` clause, and append `activeBand?.currencyCode` as one
  additional argument to `Object.hash(...)` in `hashCode` in the matching
  position (after `avatarColor`, before `isLoading`). No other change to
  this file: `updateActiveBand`, `selectBand`, `loadUserBands`,
  `loadAndSelectBand`, `refreshBands`, `handleBandDeletion`,
  `_invalidateBandScopedProviders`, `_persistBandId`, `_loadPersistedBandId`,
  and every other method must be byte-identical after the edit. Do **not**
  add `timezone` to either method — that is a separate follow-up per Out
  of Scope.
- **`lib/features/bands/band_form_screen.dart`** — the core redesign.
  Replace `_buildAppBar` with `AppAppBar` + back icon. Add
  `_selectedCurrencyCode` / `_initialCurrencyCode` state, `_isDirty` clause.
  Add `_buildCurrencySection` mirroring `_buildTimezoneSection`. Wrap
  About / Location / (Invite Members | Band Data) blocks in `SectionCard`.
  Add currency update to the existing timezone-non-default block in
  `_createBand` (become an always-run update of `{timezone, currency_code}`).
  Add `'currency_code'` to the `_updateBand` payload and to the manually
  constructed `updatedBand`. Replace the "Backup / Restore Data" button +
  `_showBackupRestoreSheet` entry with inline Band Data section buttons in
  edit mode. Delete `_showBackupRestoreSheet` (~130 lines), `_BackupSheetPanel`
  (~90 lines), the unused `_showExportDialog` marked `// ignore: unused_element`
  (~85 lines — dead code that the redesign obviates and can honestly be
  removed since it was never wired up). Keep Delete Band at the bottom.
- **`lib/shared/widgets/currency_input_field.dart`** — accept optional
  `String currencySymbol = '\$'` on both `CurrencyInputField` and
  `CurrencyTextField`. Thread the symbol into `hint` default and into
  `CurrencyInputController.formattedValue` — the controller becomes
  `CurrencyInputController(this._symbol, [int initialCents = 0])` or the
  widget prefixes the symbol at render time (Engineer picks the smaller
  diff). Symbol replaces the `\$` literal exactly once; no other behavior
  changes.
- **`lib/app/models/gig.dart`** — replace `String? get formattedPay` with
  `String? formatPay(String currencyCode) => …
BandCurrency.formatCents(gigPayCents!, currencyCode)`. Single call site
  (`view_gig_drawer.dart:613`) updated accordingly.
- **`lib/features/events/widgets/gig_expense_subview.dart`** — replace
  `String get formattedAmount` on `GigExpenseDraft` with
  `String formatAmount(String currencyCode) =>
BandCurrency.formatCents(amountCents, currencyCode)`. Any consumer
  updated. The `CurrencyTextField` widget instance at line ~275 gets the
  `currencySymbol` param wired through.
- **`lib/features/financials/models/financial_entry.dart`** — replace
  `String get formattedAmount`, `String? get formattedDepositToSavings`, and
  `String get formattedAmount` on `GigPayDetails` with methods taking
  `String currencyCode`. Consumers updated.
- **`lib/features/financials/financials_report_builder.dart`** — add
  required `String currencyCode` param to `buildFinancialsReportContent(...)`
  and to every internal helper that currently uses `moneyFmt`. Change
  line 29 to `final moneyFmt = NumberFormat.currency(symbol:
BandCurrency.symbolFor(currencyCode), decimalDigits: 2)`.
- **`lib/features/financials/financials_pdf_preview_screen.dart`** — add
  required `String currencyCode` constructor param, thread it into the
  `buildFinancialsReportContent(...)` call.
- **`lib/features/financials/financials_screen.dart`** — the PDF launch
  site (line ~908) reads the active band's `currencyCode` and passes it to
  `FinancialsPdfPreviewScreen`. `_SavingsSheet._fmt` and `_SummaryHeader`
  read `currencyCode` from the active band and pipe through
  `BandCurrency.formatCents`.
- **`lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`** —
  `_formatSavingsCents` becomes `_formatSavingsCents(int cents, String
code)`. Local `CurrencyTextField` instances get the `currencySymbol`
  parameter.
- **`lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart`** —
  reads the active band `currencyCode` in `build` and calls the new
  `entry.formatAmount(code)` / `entry.formatDepositToSavings(code)` methods.
- **`lib/features/gigs/widgets/view_gig_drawer.dart`** — reads the active
  band `currencyCode` in `build` and calls `gig.formatPay(code)` on line 613.
- **`lib/features/events/widgets/gig_form_fields.dart`** — reads currency
  code from ref and calls the new methods for lines 747 (`gigPayDetails`)
  and 858 (`expense`).
- **`lib/features/events/widgets/event_editor_drawer.dart`** — updates the
  ~2 formatter call sites around lines 2029 / 2053 that consume
  `_gigPayDetails.formattedAmount` to use the new method form.
- **`lib/features/financials/widgets/gig_pay_bottom_sheet.dart`** — wires
  `currencySymbol` through to the `CurrencyTextField` at line 226.
- **`test/features/bands/active_band_controller_invalidation_test.dart`** —
  extend with one new `group('updateActiveBand notifies on currency-only
change', ...)` (Cycle 4 Amendment C1 regression). Do not delete, rename,
  or alter the existing `selectBand invalidates band-scoped providers`
  group; do not modify existing helper bands, `_SeededActiveBandNotifier`,
  or the file's imports beyond adding a listener helper if needed. Cases
  spelled out in Verification T1-4b.
- **`test/features/financials/widgets/add_financial_entry_bottom_sheet_test.dart`,
  `test/features/financials/widgets/financial_entry_details_bottom_sheet_test.dart`,
  `test/features/financials/widgets/financials_screen_scroll_test.dart`,
  `test/features/financials/widgets/summary_header_test.dart`,
  `test/features/financials/widgets/transaction_card_test.dart`** — where
  each test currently asserts on a `$…` string produced by a model getter,
  update assertions to use the new `formatAmount(code)` / `formatDepositToSavings(code)`
  method output. If any pump misses an `activeBandProvider` override, add
  one seeded with a USD-defaulted `Band` — same test-friendly path as the
  existing `active_band_controller_invalidation_test.dart` fixture.

## Files Off-Limits

- **`supabase/migrations/087_fix_create_band_no_profile.sql`** — the
  `create_band` RPC. Do not change its signature; use the timezone-style
  post-create UPDATE.
- **`supabase/migrations/20260305000000_band_scoped_calendar.sql`** — the
  timezone precedent. Do not edit; only mirror its pattern.
- **`supabase/migrations/20260521000000_add_start_time_to_date_tables.sql`**
  and any other `get_band_full_state` migration. `row_to_json(b.*)` picks up
  the new column automatically; touching the RPC would risk regressing
  gig/rehearsal date shape.
- **`supabase/migrations/20260825120000_consolidate_permissive_rls_policies.sql`**
  and all other `bands_*` RLS policy migrations. `bands_update_admins` and
  `bands_select_members` already gate the new column at row level; no
  policy change.
- **`lib/features/settings/data_backup_service.dart`** — export uses
  `SELECT` on `bands` (auto-picks up the new column); restore upserts. No
  changes required or wanted; changing this would risk backup format drift.
- **`lib/main.dart`** and initialization sequence — untouched. Currency
  read has no impact on Supabase/Firebase/DeepLinkService/AppVersionService
  init order.
- **`lib/features/bands/edit_band_screen.dart`** — thin 19-line wrapper.
  Untouched.
- **`lib/features/bands/active_band_controller.dart`** — off-limits
  **except** the surgical `ActiveBandState.==` / `hashCode`
  `currencyCode` addition authorized by Cycle 4 Amendment C1 and
  described in Files to Modify. Every other method — `updateActiveBand`,
  `selectBand`, `loadUserBands`, `loadAndSelectBand`, `refreshBands`,
  `handleBandDeletion`, `_invalidateBandScopedProviders`, all
  persistence helpers — is byte-frozen. Do not add `timezone` to `==` or
  `hashCode` in this cycle.
- **`lib/features/bands/band_repository.dart`** — untouched.
- **The private `_SectionCard` in `event_editor_drawer.dart` and
  `add_financial_entry_bottom_sheet.dart`** — do not import into
  `band_form_screen.dart`. Do not consolidate them into the new
  `SectionCard`; that's an opportunistic refactor outside this feature's
  scope. Cross-file dedupe of the two `_SectionCard` copies belongs to a
  separate cleanup ticket.
- **`AppAppBar`, `AppIconButton`, `AppButton`, `AppDropdown`,
  `AppTextFormField`, `AppScaffold`, `AppDialog`** — reuse only. Do not
  extend or subclass.
- **`pubspec.yaml`** — no new dependencies. `intl: ^0.20.2` and `forui`
  are already present and sufficient.
- **`.github/copilot-instructions.md`, `docs/reference/general/RUNTIME_CONFIG.md`,
  `docs/reference/general/AI_DECISIONS.md`** — no changes; no guardrail
  exception is being taken.

## Change Budget

Line-count numbers below are **net deltas** measured against `main` at
`b0f3c90257aa`. Sign convention: `+` adds lines, `-` removes lines.

### New files

**Count: 6.** Adding any additional new file counts as a scope breach and QA
must flag it.

| Path                                                                | Expected size                                                                                                                                                                                                                                                              |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `supabase/migrations/20260915120000_add_currency_code_to_bands.sql` | 25–45 lines                                                                                                                                                                                                                                                                |
| `lib/features/bands/currency/band_currency.dart`                    | 150–210 lines (pure Dart, no `package:meta` import; includes `pickerGroups()` + `BandCurrencyPickerGroup`)                                                                                                                                                                 |
| `lib/features/bands/widgets/section_card.dart`                      | 35–60 lines                                                                                                                                                                                                                                                                |
| `test/features/bands/band_currency_test.dart`                       | **≤ 220 lines (Cycle 4 C2 hard cap; target 110–180)** — preserves the complete ordered 30-record `countryLabel` / `isoCode` / `name` / `symbol-or-null` comparison and all focused format assertions from Cycle 3; see "Compaction pattern" below. Do not reduce coverage. |
| `test/features/bands/band_currency_picker_test.dart`                | 50–100 lines                                                                                                                                                                                                                                                               |
| `test/features/bands/band_model_test.dart`                          | 40–80 lines                                                                                                                                                                                                                                                                |

### Modified files

| Path                                                                        | Expected net delta                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/features/bands/band_form_screen.dart`                                  | −350 to −150 (net removal: sheet + panel + unused dialog − section wrappers + currency dropdown)                                                                                                                                                                                                                                                                                                                        |
| `lib/app/models/band.dart`                                                  | +6 to +10                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/features/bands/active_band_controller.dart`                            | **+2 to +3 (Cycle 4 C1 cap)** — one comparison line in `ActiveBandState.==` plus one `Object.hash(...)` argument in `hashCode`; no method-body reordering, no rename, no import change                                                                                                                                                                                                                                  |
| `lib/shared/widgets/currency_input_field.dart`                              | +12 to +25                                                                                                                                                                                                                                                                                                                                                                                                              |
| `lib/app/models/gig.dart`                                                   | −4 to +5                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/events/widgets/gig_expense_subview.dart`                      | −2 to +8                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/financials/models/financial_entry.dart`                       | −10 to +6                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/features/financials/financials_report_builder.dart`                    | +3 to +8                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/financials/financials_pdf_preview_screen.dart`                | +3 to +6                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/financials/financials_screen.dart`                            | +6 to +14                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart`     | +5 to +12                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` | +2 to +6                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/gigs/widgets/view_gig_drawer.dart`                            | +2 to +6                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/events/widgets/gig_form_fields.dart`                          | +4 to +10                                                                                                                                                                                                                                                                                                                                                                                                               |
| `lib/features/events/widgets/event_editor_drawer.dart`                      | +2 to +6                                                                                                                                                                                                                                                                                                                                                                                                                |
| `lib/features/financials/widgets/gig_pay_bottom_sheet.dart`                 | **+1 to +6 (Cycle 4 W1 cap)** — the smallest legitimate consolidation is (a) fold the two-line `ref.watch(activeBandProvider).activeBand?.currencyCode ?? BandCurrency.defaultCode` fallback into a single-line local, and (b) add the `currencySymbol:` argument to the existing `CurrencyTextField(...)` on its existing constructor line rather than on a new line. No other behavior change; no unrelated refactor. |
| `test/features/bands/active_band_controller_invalidation_test.dart`         | +25 to +50 (one added `group(...)` per Verification T1-4b; existing group untouched)                                                                                                                                                                                                                                                                                                                                    |
| existing financials/widgets test files (5 files)                            | +5 to +20 each                                                                                                                                                                                                                                                                                                                                                                                                          |

### Other

- **New public classes/methods.** `BandCurrency` (+ its static members,
  including `pickerGroups()`); `BandCurrencyPickerGroup` (value type
  consumed by both `_buildCurrencySection` and the T1-2b picker test);
  `SectionCard`; one converted method per money-formatting model
  (`Gig.formatPay`, `GigExpenseDraft.formatAmount`,
  `FinancialEntry.formatAmount`, `FinancialEntry.formatDepositToSavings`,
  `GigPayDetails.formatAmount`) — five method conversions, no getters
  survive them.
- **New dependencies.** 0. `pubspec.yaml` is off-limits and no
  `package:meta` import is added anywhere in this feature (Cycle 4
  Amendment W2).

### Compaction pattern (Cycle 4 C2 required approach)

`test/features/bands/band_currency_test.dart` must retain the exhaustive
30-record contract while fitting inside 220 lines. The required shape:

- Declare **one** ordered `const List<Map<String, Object?>>` at the top of
  the file with exactly 30 entries in shortlist order, each entry keyed on
  `countryLabel`, `isoCode`, `name`, `symbol` (with `null` for the three
  symbol-less records CHF, RSD, MKD, and also MDL per the Cycle 3
  correction — confirmed in QA). This is the whole fixture.
- Iterate `shortlist` and the expected list once inside a single
  `test('shortlist matches the exact 30-record ordered contract', ...)`
  block, asserting each of the four fields per index with an indexed
  `expect(shortlist[i].countryLabel, expected[i]['countryLabel'], reason:
'index $i')`. Four `expect`s per row × 30 rows compiles into ~120 lines
  of assertions if declared vertically, but compacts to ~40 lines when the
  fixture is written as tight one-line `Map` literals and iterated. This
  preserves the same 120 individual assertions (same coverage) inside the
  cap.
- Keep the focused format assertions (`formatCents(150000, 'USD') ==
'\$1,500.00'`, `formatCents(150000, 'EUR') == '€1,500.00'`,
  `formatCents(0, 'USD') == '\$0.00'`, `formatCents(99, 'USD') ==
'\$0.99'`, MXN `\$`, GYD `G\$`, MDL fallback to `MDL`, CHF/RSD/MKD
  fallback) as individual `expect`s inside a single `group('formatCents
and symbolFor', ...)`. Do not fold these into a table — the failure
  messages need to point at specific codes.
- Keep the singleton composite-label assertions
  (`BandCurrency.byIsoCode['USD']!.countryLabel == 'United States /
Ecuador'` and `['EUR']!.countryLabel == 'Eurozone / Bulgaria'`) as
  standalone `test(...)` blocks so a regression there is obvious in the
  report.
- Do **not** remove or weaken any assertion present in the Cycle 3 file.
  Compaction is shape-only: fewer vertical lines, identical failure
  surface.
- **New RPCs / SECURITY DEFINER functions.** 0.
- **New RLS policies.** 0.
- **New providers.** 0 required. Optional 1 (a derived
  `Provider<String>` for the active band's `currencyCode`) — inside scope
  only if it strictly reduces duplication.

## System Impact Map

- **Bands / active band switching** — affected. `Band` gains a field;
  `updateActiveBand` propagates it. No provider invalidation logic change.
- **Financials (screen, PDF export, entry sheet, details sheet, savings
  sheet)** — affected. Every display + input path reads the active band's
  currency instead of hardcoding `$`.
- **Gigs (view drawer, form fields, expense subview, gig pay sheet)** —
  affected. Same as above.
- **Events (editor drawer, gig form fields)** — affected transitively via
  the model-method conversion.
- **Setlists** — unaffected.
- **Members / permissions** — unaffected. Reuses existing
  `canEditBandSettings`, `canExportBandData`, `canDeleteBand`.
- **Auth (magic link, PKCE, deep links, invite flow)** — unaffected.
- **Routing / navigation shell** — unaffected. Same route entries; only
  the screen internals change.
- **Notifications** — unaffected. No FCM or trigger touch.
- **Calendar / iCal feed** — unaffected. `calendar-feed` edge function
  reads `bands.timezone` and `bands.name`, not `bands.currency_code`.
- **Backup / restore (`data_backup_service.dart`)** — unaffected code path
  wise, but the exported JSON now round-trips the new `currency_code`
  column automatically (verified against
  `data_backup_service.dart:189-195`).
- **Init order / RuntimeConfig / dart-defines** — unaffected.
- **Platforms.** iOS, Android, Web, macOS — all four inherit the same
  behavior. The new column and the new UI are platform-agnostic. Firebase
  and `DeepLinkService` init on native, skipped on web — that split is
  unchanged by this feature. Web-only auth confirm route unchanged.

## Regression Risk

**MEDIUM.** Ranked reasoning:

- **Cross-cutting formatter fan-out** — 13 call sites across 8 files
  changing from a hardcoded prefix to a runtime lookup. Any missed site is
  a visual bug (wrong symbol) but not a data-loss or auth risk. Mitigated
  by exhaustive enumeration in the Existing System Analysis table above.
- **Active-band notification equality (Cycle 4 C1 authorized fix).** The
  Cycle 3 gap — currency-only `updateActiveBand` producing `previous ==
next` and suppressing listener notification — is closed by adding
  `currencyCode` to `ActiveBandState.==` and `hashCode`. This raises the
  bands-scoped risk from LOW to MEDIUM for one cycle because the
  notification-decision gate for every `activeBandProvider` watcher is
  edited. Mitigated by the direct falsifiability test T1-4b (must fail
  pre-fix, must pass post-fix), and by the tight two-line surface
  authorized in Files to Modify. The `timezone` field remains omitted by
  design (Out of Scope) — that pre-existing latent defect is not
  worsened by this change.
- **Model getter → method conversion** — every consumer of five model
  getters must be updated in the same PR. Missing one is a compile error
  caught by `flutter analyze` (Tier 1).
- **Financials PDF export** — one new required constructor param on
  `FinancialsPdfPreviewScreen` and `buildFinancialsReportContent`. Compile-
  caught.
- **Backup/Restore inline re-wiring** — the underlying `DataBackupService`
  calls are unchanged; only the entry-point widget hierarchy moves.
  Loading state and permission gates preserved. Low behavioral risk.
- **Auth / RLS / init order / DB migration idempotency** — untouched. Low
  risk.

## Engineer Task Breakdown

Ordered, atomic. Steps are sequenced so that `flutter analyze` is clean at
the end of each step's file edits, but **Engineer does not commit or push
at any step boundary — all implementation stays uncommitted through QA.
Manager makes the single commit only after literal QA APPROVED.** The
step order exists to keep Engineer's local analyzer green as each layer
lands, not to fence commit points.

1.  **DB migration.** Create
    `supabase/migrations/20260915120000_add_currency_code_to_bands.sql` per
    Database Impact. Do not apply — Tony applies at PR-test / release time.
2.  **Band model.** Add `currencyCode` to `lib/app/models/band.dart` with
    default `'USD'`, and to `fromJson` / `toJson` / constructor. Add
    `test/features/bands/band_model_test.dart` covering default,
    round-trip, and legacy-row-missing-column parsing.
    2b. **Active-band notification equality fix (Cycle 4 Amendment C1).** In
    `lib/features/bands/active_band_controller.dart`, add exactly one
    comparison clause `activeBand?.currencyCode ==
    other.activeBand?.currencyCode &&` inside `ActiveBandState.==` between
    the existing `avatarColor` clause and the `isLoading` clause, and
    append `activeBand?.currencyCode` to the `Object.hash(...)` argument
    list in `hashCode` in the matching position (after `avatarColor`,
    before `isLoading`). No other change to this file: do not touch
    `updateActiveBand`, `selectBand`, `loadUserBands`, `loadAndSelectBand`,
    `refreshBands`, `handleBandDeletion`,
    `_invalidateBandScopedProviders`, or any persistence helper. Do **not**
    add `timezone` to either method (Out of Scope).

        Then extend
        `test/features/bands/active_band_controller_invalidation_test.dart`
        with a new group per Verification T1-4b. Do not alter the existing
        `selectBand invalidates band-scoped providers` group. This test must
        fail against the pre-fix controller (proving falsifiability) and pass
        against the fixed controller.

3.  **Currency module.** Create
    `lib/features/bands/currency/band_currency.dart` with **exactly 30
    `BandCurrency` records** — one per unique ISO code — using the country
    strings, currency names, and symbols verbatim from Tony's supplied
    32-row list, with `USD`'s `countryLabel` set to exactly `"United
    States"` (Cycle 6 owner correction — single-country label, no
    Ecuador substring) and `EUR`'s `countryLabel` set to the composite
    `"Eurozone / Bulgaria"` per Proposed Solution §2. Implement
    `symbolFor`, `formatCents`, `defaultCode`. Add the public,
    widget-free `BandCurrencyPickerGroup` value type and the
    `static List<BandCurrencyPickerGroup> pickerGroups()` builder in the
    same file (Proposed Solution §2). Do not import `forui`,
    `flutter/widgets`, `riverpod`, or `package:meta/meta.dart` from this
    file — immutability is guaranteed by `final` fields + `const`
    constructors on both types (Cycle 4 Amendment W2). Create
    `test/features/bands/band_currency_test.dart` per Verification T1-2 and
    the Change Budget § "Compaction pattern" (≤ 220 lines, full 30-record
    coverage preserved), **and**
    `test/features/bands/band_currency_picker_test.dart` per Verification
    T1-2b — the picker test calls `BandCurrency.pickerGroups()` directly
    (no widget pump, no `ProviderContainer`).
4.  **SectionCard widget.** Create
    `lib/features/bands/widgets/section_card.dart`.
5.  **Currency-aware inputs.** Update
    `lib/shared/widgets/currency_input_field.dart` to accept optional
    `currencySymbol`, defaulting to `'\$'` — analyzer clean, existing call
    sites untouched.
6.  **Model-getter → method conversion.** Convert `Gig.formattedPay`,
    `GigExpenseDraft.formattedAmount`, `FinancialEntry.formattedAmount`,
    `FinancialEntry.formattedDepositToSavings`, `GigPayDetails.formattedAmount`
    into methods taking `String currencyCode`. Update all in-repo callers
    in the same step so `flutter analyze` is clean at the end of this
    step's edits.
7.  **PDF preview + report builder.** Add required `currencyCode` param;
    wire through from `financials_screen.dart` PDF launch site.
8.  **Financials screen internals.** Update `_SavingsSheet._fmt`,
    `_SummaryHeader.totalFormatted`, and `add_financial_entry_bottom_sheet.dart`
    `_formatSavingsCents` + `CurrencyTextField` instances.
9.  **View-gig / financial-details / gig-pay / gig-form-fields / gig-expense
    / event-editor call sites.** Feed the new methods with the active band's
    `currencyCode`.
10. **Band Form redesign — Create mode.** Swap `_buildAppBar` for
    `AppAppBar` + back icon. Wrap About / Location (+ new currency
    dropdown, built by mapping each `BandCurrencyPickerGroup` returned by
    `BandCurrency.pickerGroups()` to a `FSelectSection<String>` — 30 rows
    across the 3 groups) / Invite Members in `SectionCard`. Wire currency
    into the post-create UPDATE.
11. **Band Form redesign — Edit mode.** Same header change. Wrap About /
    Location (+ currency dropdown built the same way — 30 rows across the
    3 groups) / **Band Data (inline Backup / Restore buttons)** in
    `SectionCard`. Delete `_showBackupRestoreSheet`, `_BackupSheetPanel`,
    and the unused `_showExportDialog`. Keep Delete Band at the bottom.
    Wire currency into the edit UPDATE payload and the manually
    constructed updated `Band(...)`.
12. **Existing widget tests.** Update the five financials-widget tests to
    override `activeBandProvider` with a USD Band where the test currently
    depends on default `$` output, and to consume the new method form.
13. **Full `flutter analyze` + `flutter test` local run** — Engineer's own
    verification before handing off to QA. Leave the working tree
    uncommitted for QA.

## Verification Plan

### Tier 1 (pre-deploy — QA-gate mechanical checks)

QA can execute all of the following without launching the app:

- **T1-1 `flutter analyze` clean.** Full project. Gate: zero errors, zero
  new warnings (existing warnings on unmodified files may persist).
- **T1-2 `flutter test test/features/bands/band_currency_test.dart`.**
  Cases (each falsifiable — a wrong shortlist fails at least one):
  - `BandCurrency.shortlist.length == 30`.
  - `BandCurrency.shortlist.map((e) => e.isoCode).toSet().length == 30`
    — every `isoCode` is unique across the shortlist. This is the guard
    that fails if a future edit re-introduces a per-supplied-row entry.
  - `BandCurrency.shortlist.map((e) => e.isoCode).toSet()` equals exactly
    the 30-code set from the CHECK constraint:
    `{'USD','CAD','MXN','EUR','GBP','CHF','PLN','CZK','HUF','DKK',
'SEK','NOK','ISK','RON','RSD','ALL','MKD','MDL','UAH','ARS','BOB',
'BRL','CLP','COP','GYD','PYG','PEN','SRD','UYU','VES'}`.
  - `BandCurrency.byIsoCode.length == 30` and
    `BandCurrency.byIsoCode.keys.toSet()` equals the same 30-code set.
  - `BandCurrency.defaultCode == 'USD'`.
  - Label contract (Cycle 6 owner-corrected — USD is single-country,
    EUR keeps the Bulgaria composite):
    - `BandCurrency.byIsoCode['USD']!.countryLabel == 'United States'`
      (exact string; no Ecuador substring anywhere in the value).
    - `BandCurrency.byIsoCode['EUR']!.countryLabel == 'Eurozone / Bulgaria'`.
    - The EUR `countryLabel` contains the literal substring `'Bulgaria'`
      — asserted separately so the test catches accidental removal of
      the Bulgaria composite. The USD `countryLabel` must **not**
      contain the literal substring `'Ecuador'` — asserted separately
      so a future regression that reintroduces Ecuador into the USD
      label (in any casing or position) fails visibly.
  - Symbol fallback: `symbolFor('USD') == '\$'`,
    `symbolFor('EUR') == '€'`, `symbolFor('CHF') == 'CHF'` (no symbol →
    falls back to code), `symbolFor('RSD') == 'RSD'`,
    `symbolFor('MKD') == 'MKD'`.
  - Formatting: `formatCents(150000, 'USD') == '\$1,500.00'`,
    `formatCents(150000, 'EUR') == '€1,500.00'`,
    `formatCents(0, 'USD') == '\$0.00'`,
    `formatCents(99, 'USD') == '\$0.99'`.
  - Group placement (single row per code): a single
    `BandCurrency.shortlist.where((e) => e.isoCode == 'USD')` returns
    exactly one record whose group is America; same test for `'EUR'`
    returns exactly one record whose group is Europe.
- **T1-2b `flutter test test/features/bands/band_currency_picker_test.dart`
  (new file, listed in Files to Create item 5).** Pure builder-level check
  on the currency picker's group-building helper. The helper is
  `BandCurrency.pickerGroups()` — a public static on `BandCurrency`
  returning `List<BandCurrencyPickerGroup>` (Proposed Solution §2). It is
  widget-free and ref-free by contract, so the test calls it directly
  without pumping a widget or spinning up a `ProviderContainer`. Cases:
  - `BandCurrency.pickerGroups().length == 3` and the three group
    `label`s in list order are `['America', 'Europe', 'South America']`.
  - Flattening every `BandCurrencyPickerGroup.items` map yields exactly
    30 entries in total (America group `.items.length == 3`, Europe
    group `.items.length == 16`, South America group `.items.length ==
11`).
  - `Set` of all ISO code values across every group has size 30 — no
    duplicate picker values.
  - `Set` of all display-label keys across every group has size 30 — no
    duplicate picker labels.
  - The `'USD'` value appears in exactly one group, and that group's
    `label` reads `'America'`; the display-label key mapping to `'USD'`
    is exactly `'United States — US Dollar (USD)'` (Cycle 6
    owner-corrected — single-country label, no Ecuador substring
    anywhere).
  - The `'EUR'` value appears in exactly one group, and that group's
    `label` reads `'Europe'`; the display-label key mapping to `'EUR'`
    is exactly `'Eurozone / Bulgaria — Euro (EUR)'`.
  - No group contains an `items` key matching `RegExp(r'^Bulgaria —')`
    — Bulgaria's composite presence lives inside the EUR label but
    Bulgaria never heads a standalone row.
  - No group contains an `items` key that contains the literal
    substring `'Ecuador'` anywhere in the key — Cycle 6 requires
    Ecuador to be fully absent from every visible picker label, not
    merely absent from the row heading. This is stricter than the
    Cycle 5 `RegExp(r'^Ecuador —')` check by design.
- **T1-3 `flutter test test/features/bands/band_model_test.dart`.** Cases:
  - `Band.fromJson({...no currency_code})` yields `currencyCode == 'USD'`.
  - `Band.fromJson({...'currency_code': 'EUR'})` yields `currencyCode ==
'EUR'`.
  - `toJson()` round-trip preserves the code.
  - `Band(...)` constructor without `currencyCode` argument defaults to
    `'USD'`.
- **T1-4 `flutter test test/features/bands/active_band_controller_invalidation_test.dart`
  and `test/features/auth/auth_gate_anonymous_recovery_test.dart`.**
  These files construct `Band(...)` directly; they must still compile and
  pass with the new default-valued field.
- **T1-4b Currency-only `updateActiveBand` notification (Cycle 4
  Amendment C1).** New `group('updateActiveBand notifies on currency-only
change', ...)` inside
  `test/features/bands/active_band_controller_invalidation_test.dart`; do
  not touch the existing group. This test provably fails against the
  pre-fix controller (`ActiveBandState.==` / `hashCode` omitting
  `currencyCode`) and passes against the fixed controller. Cases:
  - Build a `ProviderContainer` with a seeded `ActiveBandNotifier`
    whose initial `activeBand` is a `Band` copy with
    `currencyCode: 'USD'` and whose seeded `userBands` contains that
    same band. Reuse the file's existing `_SeededActiveBandNotifier`
    pattern; add a currency-explicit variant if needed.
  - Register a listener via
    `container.listen<ActiveBandState>(activeBandProvider, (prev, next)
=> received.add(next.activeBand?.currencyCode))` with
    `fireImmediately: false`, into a local `final received =
<String?>[]`.
  - Call
    `container.read(activeBandProvider.notifier).updateActiveBand(band)`
    with a `Band` copy where every non-currency field — `id`, `name`,
    `imageUrl`, `avatarColor`, `createdBy`, `timezone`, `createdAt`,
    `updatedAt` — equals the seeded band's field, and only
    `currencyCode` differs (`'USD'` → `'CAD'`).
  - Assert `container.read(activeBandProvider).activeBand!.currencyCode
== 'CAD'` (state actually stored the update) **and** `received`
    contains at least one `'CAD'` entry (Riverpod actually notified
    the listener because `previous != next` after the equality fix).
  - Also assert the reciprocal case: a second `updateActiveBand` with
    the same `'CAD'` band and every other field identical produces no
    new listener entry (i.e. equality still deduplicates identical
    states, so the fix does not over-notify).
  - Do **not** assert anything about `timezone` propagation — that is
    an out-of-scope adjacent defect.
- **T1-5 `flutter test test/features/financials/widgets/`.** All five
  financials widget tests pass with their updated string expectations
  (still `$…` in USD-defaulted test bands — the symbol changes but tests
  can override to a non-USD band to exercise the swap explicitly, adding
  at least one such case to `transaction_card_test.dart`).
- **T1-6 SQL migration static review.** QA reads the new migration file
  and confirms: (a) filename `supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
  does not collide with any existing migration filename in
  `supabase/migrations/` (last-modified filenames on `main` at
  `b0f3c90257aa` are `20260912130000_*` and earlier — `20260915120000`
  sorts strictly after all of them), (b) `ADD COLUMN IF NOT EXISTS`, (c)
  `NOT NULL DEFAULT 'USD'`, (d) CHECK constraint contains exactly 30
  literal ISO codes — parse the `IN (...)` list, dedupe into a set,
  assert size 30, and assert the set equals the 30-code set from T1-2 —
  (e) `DROP CONSTRAINT IF EXISTS` before `ADD CONSTRAINT`, (f) no
  `SECURITY DEFINER` function, no `GRANT`, no `REVOKE`, no RLS policy
  statements.
- **T1-7 (removed — Cycle 5 Amendment C3).** The Cycle 4 "Ephemeral DB
  apply check" is **no longer a QA gate**. Manager, Engineer, and QA
  cannot touch any database in this pipeline — local, scratch, branch,
  staging, or production. Runtime migration verification (twice-apply
  idempotency, `'ZZZ'` CHECK rejection, DEFAULT `'USD'` application) is
  reclassified as owner-run in Tier 2 → "Ephemeral apply drill" and
  "Apply/release-time" punch lists. QA's database-facing gate stops at
  T1-6 static SQL review; QA does not open a Supabase client, does not
  spin up a scratch database, does not execute `psql`, and does not
  invoke `supabase db push` / `supabase migration up` / `supabase db
reset` in any form. The absence of an executed apply is documented as
  an accepted residual in QA Regression Areas and does not block
  APPROVED.
- **T1-8 Model consumers compile-clean.** Grep for
  `\.formattedPay|\.formattedAmount|\.formattedDepositToSavings` — no
  matches should remain in `lib/`. If any remain, the getter → method
  conversion missed a site.

### Tier 2 (owner-run punch list)

QA cannot launch the app and cannot touch any database (Cycle 5
Amendment C3). Everything below is handed to **Tony** as a numbered
walkthrough to run at pre-staging, PR-test, and apply/release time.
Each step lists the exact action and the exact expected result. None of
these steps are gated by QA; QA APPROVED depends only on Tier 1.

**Ephemeral apply drill (owner-run — pre-staging; Tony's local Supabase
or a scratch DB he controls; runtime replacement for the deleted
T1-7):**

E1. On a scratch database (local Supabase CLI stack or a disposable
Postgres branch), apply
`supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
once. **Expected:** applies cleanly with no errors.
E2. Re-apply the same migration against the same scratch database.
**Expected:** second apply is a no-op — the `ADD COLUMN IF NOT
    EXISTS` and `DROP CONSTRAINT IF EXISTS` guards fire; no error.
E3. Attempt `INSERT INTO bands (…, currency_code) VALUES (…, 'ZZZ');`
(or `UPDATE bands SET currency_code = 'ZZZ' WHERE id = <any>;` on a
seeded row). **Expected:** `bands_currency_code_check` violation.
E4. Insert a band row without specifying `currency_code` (or observe an
existing row after the apply). **Expected:** `currency_code` reads
`'USD'` — the `NOT NULL DEFAULT 'USD'` populates every row that
doesn't provide a value.

If any of E1–E4 fails, stop and file back to Architect before applying
to staging. The plan expects E1–E4 to pass because T1-6 already
confirmed the file's static shape.

**PR-test (staging or dev build; migration applied):**

1. Open Create New Band. **Expected:** the top of the screen shows the
   shared `AppAppBar` with a left-facing back arrow icon (no
   `FrostedGlassBar` band). Title reads "New Band".
2. Scroll the form. **Expected:** three visually distinct titled
   section cards — "About", "Location", "Invite Members". Each has a
   heading above the fields inside a rounded card that adapts to
   light/dark mode.
3. In the Location section, tap the currency dropdown. **Expected:**
   dropdown lists exactly **30 selectable rows**, grouped under three
   headers `America` (3 rows) / `Europe` (16 rows) / `South America`
   (11 rows), in the Feature Input's order. Under `America`, `USD`
   appears exactly once, labeled exactly `United States — US Dollar
(USD)` (Cycle 6 owner-corrected — single-country label, Ecuador
   must not appear anywhere in the USD row). Under `Europe`, `EUR`
   appears exactly once, labeled `Eurozone / Bulgaria — Euro (EUR)`.
   There is **no** standalone `Bulgaria — …` row under `Europe`;
   Bulgaria appears only inside the composite EUR label. There is
   **no** row anywhere in the picker whose visible label contains
   the substring `Ecuador` — Ecuador is fully absent from every
   picker label after Cycle 6. South America therefore has 11
   selectable rows, not 12.
4. Select "Canadian Dollar (CAD)". **Expected:** the picker collapses;
   the field shows "Canada — Canadian Dollar (CAD)". No error.
5. Fill in a band name, add one invite email, tap Create Band.
   **Expected:** the band is created; you land on the dashboard; the
   band's persisted `currency_code` is `CAD` (verifiable in
   Supabase Studio: `SELECT id, name, currency_code FROM bands WHERE
id = '<new id>'`).
6. Switch to the newly created band, open Financials. **Expected:**
   the summary total and each entry displays with a `C$` prefix (not
   `$`).
7. Open Add Financial Entry sheet. **Expected:** the Amount field
   currency prefix and hint use `C$`.
8. Open a gig with pay set. **Expected:** the gig pay display in the
   View Gig drawer shows `C$…`.
9. In Edit Band on the new band, open the form. **Expected:** header
   is `AppAppBar` with back arrow; body shows About / Location / Band
   Data sections. Delete Band is at the bottom of the overlay,
   outside Band Data.
10. In the Band Data section, tap Backup Data. **Expected:** the
    native file picker opens directly — no bottom sheet appears.
    Save the file.
11. As an admin, tap Restore Data. **Expected:** the file picker
    opens; select the file saved in step 10; the Restore confirmation
    dialog appears; tap Replace Data. The restore succeeds and the
    Financials screen still shows `C$`.
12. Change currency from CAD to EUR; tap Save Changes. **Expected:**
    save succeeds; Financials totals and PDF export both render `€`.
13. Export a Financials PDF for this band. **Expected:** every money
    figure in the generated PDF shows `€`, not `$` or `C$`.
14. As a non-admin (member role): open Edit Band. **Expected:** the
    currency dropdown is disabled and shows "Only admins can change
    the currency" (mirroring the timezone gate). Backup Data is
    visible; Restore Data is hidden.
15. As a contributor: open Edit Band. **Expected:** Backup Data is
    hidden; Restore Data is hidden (matches current
    `canExportBandData` / `canDeleteBand` gates).

**Apply/release-time (production migration apply):**

16. Before applying: capture `SELECT count(*) FROM bands` and `SELECT
count(*) FROM bands WHERE currency_code = 'USD'`. Expected pre-
    apply: the second query errors (column doesn't exist yet). Skip
    if pre-migration.
17. Apply the migration. **Expected:** exits cleanly.
18. Re-apply the migration. **Expected:** no-op — `IF NOT EXISTS`
    guards fire.
19. After applying: `SELECT count(*) FROM bands` matches the pre-apply
    total; `SELECT count(*) FROM bands WHERE currency_code = 'USD'`
    equals that total (every existing band now defaults to USD).
20. Attempt `UPDATE bands SET currency_code = 'ZZZ' WHERE id = <any>;`.
    **Expected:** CHECK constraint rejects with `bands_currency_code_check`
    violation.
21. As Tony (admin), on a production band, change currency in Edit
    Band to a non-USD code; save. **Expected:** save succeeds; the
    Financials screen and PDF reflect the new symbol.

## QA Regression Areas

QA runs the mechanically-executable Tier 1 checks and validates:

- No compile errors introduced.
- All existing widget tests still pass (some updated per Engineer Task
  Breakdown item 12; the updates are additive assertions and provider
  overrides, not deletions).
- The Cycle 4 C1 regression test T1-4b passes — currency-only
  `updateActiveBand` notifies `activeBandProvider` listeners.
- The Cycle 4 C2 currency test file is at or under **220 lines** while
  preserving the complete ordered 30-record `countryLabel` / `isoCode` /
  `name` / `symbol-or-null` comparison and every focused format
  assertion. Coverage arithmetic: the number of individual `expect`
  assertions targeting record fields and format outputs must be at least
  what Cycle 3 shipped; no assertion may be deleted or merged into a
  weaker check.
- The Cycle 4 W1 net delta for `gig_pay_bottom_sheet.dart` is **≤ +6**.
- `lib/features/bands/active_band_controller.dart` diff is limited to
  one added comparison clause in `==` and one added argument in
  `Object.hash(...)`; no other line in that file changed.
- No net changes to `main.dart`, `supabase/functions/`, `.dart-defines`
  usage, or Firebase/DeepLinkService init.
- No new `SECURITY DEFINER` function or new `GRANT`.
- Static grep confirms every hardcoded literal `'\$'` in `lib/` outside
  of `band_currency.dart` and `currency_input_field.dart` (where the
  default fallback lives) has been removed.
- No new import of `package:meta/meta.dart` anywhere in `lib/` (Cycle 4
  W2 — `pubspec.yaml` off-limits and the annotation is not required).
- **Accepted residual — runtime DB execution deferred (Cycle 5
  Amendment C3).** QA does not execute the migration against any
  database and does not verify twice-apply idempotency, `'ZZZ'` CHECK
  rejection, or DEFAULT `'USD'` application at runtime — those are
  owner-run in Tier 2 (Ephemeral apply drill E1–E4 + Apply/release-time
  steps 16–21). This absence is an accepted, documented residual of
  the pipeline's no-agent-touches-any-DB rule and, by itself, does
  **not** block APPROVED. QA must record this residual explicitly in
  the Cycle 5 QA report ("Accepted residual: runtime DB execution
  deferred to owner-run Tier 2 punch list"). APPROVED requires T1-1,
  T1-2, T1-2b, T1-3, T1-4, T1-4b, T1-5, T1-6, and T1-8 to pass and the
  Cycle 3/4 Change Budget caps (C1 ≤ +3, C2 ≤ 220 lines, W1 ≤ +6) to
  hold.

## Rollout Strategy

**Release-order dependency (not an agent action — Cycle 5 Amendment
C3).** The migration file
`supabase/migrations/20260915120000_add_currency_code_to_bands.sql`
must be present, committed, and reviewed in the PR alongside the client
code changes; T1-6 enforces this at the QA gate. In every environment
where the client change is exercised, the migration must be applied
**before** the client build that reads or writes `bands.currency_code`
runs against that environment. Migration application is owner-run at
every step below; **no agent applies it in this pipeline.**

1. Engineer opens the PR; QA runs Tier 1 gates (T1-1, T1-2, T1-2b,
   T1-3, T1-4, T1-4b, T1-5, T1-6, T1-8 — T1-7 is removed per Cycle 5
   Amendment C3).
2. On QA APPROVED (with the accepted-residual note), Tony reviews the
   migration SQL manually per his standard schema-change practice, then
   runs the Tier 2 Ephemeral apply drill (E1–E4) on his local Supabase
   or a scratch DB. If E1–E4 fail, stop and file back to Architect
   before proceeding to staging.
3. Tony applies the migration to staging first; runs the PR-test punch
   list steps 1–15.
4. On staging pass, Tony applies to production, then runs the
   Apply/release-time punch list steps 16–21.
5. Deploy the client change (web via Vercel, native via existing build
   pipeline), sequenced after the production migration apply in step 4
   so `bands.currency_code` reads and writes always resolve.

**Rollback plan.** Migration is column-add; rollback is
`ALTER TABLE public.bands DROP COLUMN IF EXISTS currency_code;` executed by
Tony from Supabase Studio. Client code changes revert via
`git revert <merge>`. No data loss risk — the column has a default and the
backup format transparently round-trips it.

## Out of Scope

- Consolidating the two private `_SectionCard` copies in
  `event_editor_drawer.dart` and `add_financial_entry_bottom_sheet.dart`
  into the new shared `SectionCard`. Belongs to a follow-up cleanup ticket.
- Fixing the parallel `activeBand?.timezone` omission from
  `ActiveBandState.==` / `hashCode`. Confirmed in code at
  [active_band_controller.dart lines 186–212](lib/features/bands/active_band_controller.dart#L186-L212)
  as an adjacent latent silent-notification defect for timezone-only
  edits, but not authorized in this cycle: no visible in-app UI consumer
  today watches `activeBand.timezone` in a way that would produce a
  currency-style stale render (the calendar edge function reads
  `bands.timezone` server-side), and the Cycle 4 amendment brief
  explicitly forbids broadening equality to unrelated fields. Documented
  here for a follow-up ticket; Engineer must **not** add `timezone` to
  `==` or `hashCode` in this feature.
- Auto-suggesting currency from timezone (Feature Input decision #2 rejects
  it).
- Extending the shortlist beyond the 30 entries (Feature Input decision #1
  rejects it).
- Adding a "Rest of world" free-entry option or a user-supplied custom
  code.
- Changing the Backup / Restore JSON schema, or migrating existing backups.
- Localizing the currency display (`en_US` grouping stays in
  `NumberFormat`).
- Any changes to the `create_band` RPC signature.
- Any changes to `bands_*` RLS policies.
- Any changes to `get_band_full_state`.
- Any changes to `data_backup_service.dart` logic.
- Any changes to Firebase / DeepLinkService / init order / dart-defines.
- Any deletion of `BackOnlyAppBar` dead code observed at
  `lib/features/setlists/widgets/back_only_app_bar.dart` (noted in the
  Feature Input but not this feature's responsibility).
- Any deletion of unrelated `// ignore: unused_element` widgets outside
  `band_form_screen.dart`.
