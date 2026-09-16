# QA_REPORT — currency-locale-formatting

## Feature Slug

`currency-locale-formatting`

## Feature Title

Currency amounts format with US conventions regardless of the band's selected
currency/country

## Cycle Number

3

## Final Verdict

**APPROVED**

## Validation Summary

Every mechanically executable gate in the Architect plan's Tier 1 Verification
Plan was run and passed:

- `flutter analyze` on the 19 changed Dart files — **No issues found**.
- `flutter analyze` on the **full project** (to catch any cross-file compile
  break from the four model-method signature changes and the two removed
  statics) — **No issues found**.
- The four focused test files — **22 passed, 0 failed**.
- Static PDF-formatter source assertions on
  [financials_report_builder.dart](lib/features/financials/financials_report_builder.dart)
  — pass (0 money `NumberFormat`, 0 `moneyFmt`, exactly 4 `currency.format(`
  sites, `required BandCurrency currency` signature).
- Static SQL review of the migration — pass (ordering, 30-code CASE, 32-pair
  invalid-only backfill guard, 32-pair composite CHECK, no trigger/function,
  existing check left intact).
- **Ephemeral / scratch-DB apply-check** — run against a throwaway local
  PostgreSQL 18 cluster (unix-socket only, no TCP, torn down and its temp
  directory removed at the end). **Zero production access, no persistent side
  effects, no production UUIDs.** All assertions passed (see Database Safety).

This is the first cumulative QA cycle for which the plan's full Tier 1 gate —
including the ephemeral-DB apply-check — has been executed end-to-end. Verdict:
**APPROVED**.

## Architect Scope Review

Working tree is on branch `bug/currency-locale-formatting`, uncommitted (correct
and expected at this stage). The change set is exactly the plan's Files to
Modify + Files to Create and nothing else:

- 15 `lib/` files modified — all enumerated in the plan.
- 4 `test/` files modified — all enumerated in the plan.
- 1 migration created:
  [supabase/migrations/20260915130000_add_locale_to_bands.sql](supabase/migrations/20260915130000_add_locale_to_bands.sql).
- Untracked docs dir (`ARCHITECT_PLAN.md` / `ENGINEER_REPORT.md`) — expected.

Off-limits areas confirmed untouched: no `currency_input_*` / `CurrencyInputController`
/ `CurrencyTextField` widget edits (only their `currencySymbol:` call-site
argument now passes `currency.glyph`); no `supabase/functions/**`; no
`create_band` RPC or any DB function change; the shipped
`20260915120000_add_currency_code_to_bands.sql` is not edited; `main.dart` /
auth / session / routing / init-order untouched; `DraftBandNotifier` left as-is
(only the two `ActiveBandState` equality/hashCode lines in
[active_band_controller.dart](lib/features/bands/active_band_controller.dart)
changed). No unrelated formatting churn.

## Completeness Check

All ten Architect tasks are implemented:

1. `BandCurrency`: `locale` + `forceSymbolPrefix` fields added; shortlist rebuilt
   to **32 rows** (US/Ecuador and Eurozone/Bulgaria split; generic EUR labeled
   `Eurozone (generic)`); `forceSymbolPrefix: true` set on **only** the Chile
   (`es_CL`) row; `byLocale`, `fallback`, `glyph`, two-branch `format(int)`
   added; `pickerGroups()` maps `pickerLabel → locale`; `formatCents` /
   `symbolFor` / `defaultCode` removed. Verified in
   [band_currency.dart](lib/features/bands/currency/band_currency.dart).
2. `Band`: `locale` field (default `'en_US'`) + `fromJson`/`toJson` + `currency`
   getter + `band_currency` import.
3. Four model methods (`Gig.formatPay`, `FinancialEntry.formatAmount`,
   `FinancialEntry.formatDepositToSavings`, `GigPayDetails.formatAmount`) accept
   `BandCurrency` and call `currency.format(...)`.
4. PDF builder + preview: public `buildFinancialsReportContent` param is
   `required BandCurrency currency`; money `NumberFormat` deleted; the seven
   private helpers now take `BandCurrency currency`; `DateFormat`/`intl` retained.
5. All widget call sites resolve `activeBand?.currency ?? BandCurrency.fallback`
   and use `currency.format(...)` / `currency.glyph`.
6. `ActiveBandState.==` and `hashCode` include `activeBand?.locale`.
7. Picker keyed on `locale`; `_selectedLocale`/`_initialLocale` added and folded
   into `_isDirty`; `currency_code` derived from the selected locale; **both**
   `bands.update` payloads (create follow-up and update) write `currency_code`
   **and** `locale`, and the reconstructed `updatedBand` sets `locale`.
8. Migration authored per Database Impact (column → invalid-only backfill →
   composite CHECK → comment; no trigger, no function).
9. Four test files updated to the new API/data.
10. Analyzer and focused tests clean.

No partial implementation or missing edge case was found.

## Behavior Verification

Method: **runtime-exercised for the core formatting logic** (unit + widget tests
executed, not merely read), plus **code-path/static analysis** for the wiring
and the PDF surface.

- **Root cause fixed, not symptoms.** The two code defects (the `en_US`-pinned
  `formatCents` and the locale-less PDF `NumberFormat`) are both removed at the
  source; the data-model gap is closed by the additive `locale` column and the
  `byLocale` resolver. Formatting now flows through the single
  `BandCurrency.format(int cents)` path on every surface, including the PDF.
- **Runtime-exercised (tests passed):** `byLocale['en_US'].format(123450) ==
  $1,234.50`; `de_DE == 1.234,50\u00A0€` (NBSP separator, verified as U+00A0 in
  the source, not a plain space); `es_CL == $1.234,50` (Chile prefix override);
  `de_CH` contains `1'234.50` and `CHF`; integer-cents rounding
  `en_US.format(123500) == $1,235.00`; `glyph` fallbacks (`CHF`, `RSD`);
  override scoping (`es_CL.forceSymbolPrefix == true`, `es_AR`/`de_DE == false`,
  `es_AR.format(123450) == 1.234,50\u00A0$`). The `CAD`/`en_CA` on-screen card
  renders `C$150.00` (widget test).
- **Two-decimal semantics:** `decimalDigits: 2` is pinned on both `format`
  branches for every currency (no ISO-minor-unit adoption), matching the plan.
- **Fallback:** null-active-band sites use `BandCurrency.fallback` (US/`en_US`);
  `Band.currency` resolves `byLocale[locale] ?? byIsoCode[currencyCode] ??
  fallback`, so a legacy row without `locale` resolves to `en_US` via the model
  default (confirmed by `band_model_test`).
- **PDF (verified by construction, not by a rendered export):** the builder now
  calls the identical `BandCurrency.format(int cents)` path already asserted for
  every locale in `band_currency_test`; the static grep guard confirms no
  `NumberFormat`/`moneyFmt` money path remains. Therefore the PDF amount equals
  the on-screen amount **by construction**. The actual rendered-PDF visual match
  is an owner-run check (Punch List step 5) — QA did **not** exercise a live PDF
  export.

## Regression Check

Overall residual risk: **LOW** (plan pre-rated MEDIUM; the implementation is a
clean mechanical value-object swap with full analyzer + test + apply-check
coverage).

- **Auth / session / routing / init-order:** **untouched** — no files in these
  areas changed. LOW.
- **Supabase RPC signatures / parameter order:** no RPC changed; `create_band`
  untouched; the app still sets currency/locale in the post-create
  `bands.update`. LOW.
- **`ActiveBandState` equality (rebuild trigger):** adds one `locale` term to
  `==`/`hashCode`; a same-code locale switch (USD `en_US` → USD `es_EC`) now
  compares unequal and hashes differently — asserted by
  `active_band_controller_invalidation_test`. Rebuild frequency is unchanged for
  all other transitions. LOW.
- **Platform parity (iOS/Android/macOS/web):** shared Dart display code + one
  shared migration; no platform-conditional branch touched — behavior stays in
  lockstep. On-device iOS/Android confirmation is owner-run (Punch List step 6).
  LOW.
- **Controller/FocusNode disposal, `setState` after async gaps:** no widget
  lifecycle, focus, or async-mounted logic changed — only in-place
  resolve-and-format substitutions. LOW.
- **No straggler call sites:** a full-tree grep found zero remaining references
  to `formatCents` / `symbolFor` / `BandCurrency.defaultCode` and zero remaining
  `.currencyCode ?? BandCurrency…` resolve patterns; the only surviving
  `.currencyCode` reads are the field default and the (correct) equality terms.
  The full-project analyzer confirms no compile break outside the diff. LOW.

## Database Safety

- **No `SECURITY DEFINER` function, no trigger, no RLS change** — so no
  `has_function_privilege` grant verification is applicable. The migration is
  additive: one column, one composite CHECK constraint, one column comment.
- **NULL-safe backfill:** the backfill `CASE` covers exactly the 30 currency
  codes admitted by the pre-existing `bands_currency_code_check` (verified by
  reading
  [20260915120000_add_currency_code_to_bands.sql](supabase/migrations/20260915120000_add_currency_code_to_bands.sql)),
  so no existing row can select the `CASE` into `NULL` against the `NOT NULL`
  column.
- **Ephemeral apply-check (throwaway local PG18 cluster, socket-only, removed
  afterward — no production access, no persistent side effects):** the migration
  **applies cleanly** and every plan-mandated assertion passed:
  - Column shape: `locale` is `TEXT NOT NULL DEFAULT 'en_US'`.
  - Backfill correctness: seeded `EUR → de_DE`, `CHF → de_CH`, `USD` stayed
    `en_US`; every seeded row landed valid before the CHECK.
  - Idempotency / selection preservation: after setting intentional valid
    non-primary pairs `('USD','es_EC')` and `('EUR','bg_BG')`, re-applying the
    **entire migration verbatim** left both **unchanged** (the `NOT IN (32
    pairs)` guard skips already-valid rows) and the `DROP…IF EXISTS`/`ADD`
    constraint pattern re-applied without error.
  - Valid write `('CLP','es_CL')` succeeds.
  - Invalid pairs **rejected by the CHECK** (fail closed): the old-client shape
    (`UPDATE … SET currency_code='EUR'` leaving `locale='en_US'` → `('EUR',
    'en_US')`) and a direct non-member pair `('CLP','de_DE')` both raised
    `check_violation`; nothing was silently normalized.
  - All **32** reference `(currency_code, locale)` pairs inserted successfully in
    one statement (exactly 32 rows), proving the CHECK admits the intended set.
- Existing `bands_currency_code_check` left intact; all 32 pairs use codes within
  its 30-code set. Additive and reversible per the plan's Rollout Strategy.

> Note for Tony: this apply-check ran on a **local throwaway** cluster only. It
> confirms the migration SQL is syntactically and semantically correct and
> behaves as specified. The production database is applied by you manually,
> outside this pipeline.

## Analyzer Results

`flutter analyze` on the 19 changed files: **No issues found (ran in 3.5s).**
`flutter analyze` on the full project: **No issues found (ran in 6.2s).** Clean
at every severity.

## Test Results

`flutter test` on the four touched files: **22 passed, 0 failed.**

- `band_currency_test.dart` — 2 tests (32-row/`byLocale`/`byIsoCode`/`fallback`
  shape; instance `format`/`glyph`/override-scoping with exact `intl 0.20.3`
  strings incl. verified U+00A0 separators).
- `band_model_test.dart` — 5 tests (`locale` default/`fromJson`/`toJson`
  round-trip; `Band.currency` locale-first resolution + legacy fallback).
- `active_band_controller_invalidation_test.dart` — 3 tests (provider
  invalidation; currency-only notify/dedup; **locale-only** USD change compares
  unequal + different hash).
- `transaction_card_test.dart` — 12 tests (locale seeded; `C$150.00` for
  CAD/`en_CA`).

> Minor, immaterial: `ENGINEER_REPORT.md` states "24 passed"; the actual focused
> run reports **22**. All pass; the count discrepancy has no bearing on the
> verdict.

## Diff Safety Review

- No secrets / API keys / tokens in added lines (scanned).
- No `TODO` / `FIXME` / `debugPrint(` / stray `print(` / `console.` in added
  lines (grepped, not eyeballed).
- No leftover test scaffolding, accidental deletions, or unrelated churn. The
  migration file contains no debug output or credentials.

## Change Budget Review

Within budget; nothing at Warning/Critical arithmetic thresholds.

| File | Actual (+/−) | Plan budget | Assessment |
|---|---|---|---|
| `band_currency.dart` | +80 / −8 | ~+105 / −18 | under |
| `band.dart` | +11 | ~+12 | on target |
| `band_form_screen.dart` | +17 / −14 | ~+14 / −6 | +1.2x adds; in-place picker key swap, fine |
| `active_band_controller.dart` | +2 | +2 | exact |
| `financials_report_builder.dart` | +22 / −26 (net −4) | ~−3 net | on target |
| remaining ~10 source call-site files | net ~0 to +2 each | ~0 to +2 | on target |
| 4 test files | within rewrite budget | per plan | on target |
| migration (new) | 113 lines (109 non-blank) | ~90 | 1.26x — within ~1.5x tolerance |

- New public API added = exactly the 7 planned (`byLocale`, `fallback`, `glyph`,
  `format`, `forceSymbolPrefix`, `Band.locale`, `Band.currency`); removed = the
  2 planned (`formatCents`, `symbolFor`; `defaultCode` const also removed). No
  unlisted new file, public class, or dependency.
- New dependencies: **0** (`decimalPatternDigits` comes from the already-imported
  `package:intl/intl.dart`).
- New DB objects: 1 column + 1 CHECK (no trigger, no function) — matches plan.

The migration's 1.26x overage is within the ~1.5x note-and-move-on band; every
extra line is a required currency code or `(code, locale)` pair spelled out
verbatim exactly as the plan prescribed (the 30-code CASE plus the 32-pair set
appearing in both the backfill guard and the CHECK). Not bloat.

## Code Efficiency Review

- No new helper, extension, utility, provider, notifier, or private widget class
  was introduced. `format`/`glyph`/`byLocale`/`fallback` live on the existing
  `BandCurrency`, which the plan designates as the required owner.
- Independently grepped `lib/` for a pre-existing locale-aware currency
  formatter before accepting the new API — none exists; `BandCurrency` was the
  sole formatting owner and remains so.
- No single-use `_buildX()` extraction, no `FutureBuilder`/`StreamBuilder`
  re-fetch, no hand-rolled dedupe/grouping that `package:collection` covers, no
  log-and-rethrow `try/catch`, no unread field/parameter/`copyWith` entry, no
  speculative flags/enum cases, no comment restating the next line.
- The fix deletes lines (removed statics + swapped call sites), so the
  "zero-deletion bug fix" Warning does not apply.
- No changed file crosses a size target requiring a justification.

## Manual Verification Punch List

The plan's Verification Plan classifies these as **Owner-run checks (Tony, at
PR-test / apply time)** — they require a running app / on-device build / live
PDF export, which QA does not launch. They are **not** a QA gate and do **not**
count against completeness. Execute each and confirm the exact expected result.

1. **Chile (CLP) on screen.** Run the app; edit a band → Currency = **Chile —
   Chilean Peso (CLP)** → save. Add/open a financial entry of `1234.50`.
   *Expected on the Financials screen and the gig-pay/expense fields:*
   `$1.234,50` (prefix `$`, dot grouping, comma decimals — the Chile-only
   placement override). Other South-American pesos (e.g. Argentina) intentionally
   render with intl's suffix `1.234,50 $` — that is expected, not a bug.
2. **Eurozone (generic) EUR.** Set the same band's Currency = **Eurozone
   (generic) — Euro (EUR)** → save. *Expected:* `1.234,50 €` (symbol suffix,
   with a no-break space).
3. **Bulgaria EUR (same-code locale switch).** Set Currency = **Bulgaria — Euro
   (EUR)** → save. *Expected:* the `bg_BG` Euro convention, and — critically —
   the amount rebuilds **immediately** on this EUR→EUR switch **without** a band
   re-select (validates the `ActiveBandState` locale equality change).
4. **Switzerland CHF.** Set Currency = **Switzerland — Swiss Franc (CHF)** →
   save. *Expected:* `CHF 1'234.50` (apostrophe thousands separator).
5. **PDF export match.** Export the Financials PDF for a band in each currency
   above. *Expected:* each PDF amount is **character-for-character identical** to
   the on-screen amount for the same entry (grouping, decimal, symbol
   placement). In particular the **Chile (CLP)** PDF must read `$1.234,50` (not
   intl's `1.234,50 $`), and the **Eurozone (generic) EUR** PDF must read
   `1.234,50 €`.
6. **Platform parity.** On both an iOS build and an Android build, repeat step 1
   once and confirm identical output.

## Issues Found

**Critical:** None.

**Warnings:** None.

**Suggestions:**

- *(Issue Category: `code-quality`)* `ENGINEER_REPORT.md` reports "24 passed" for
  the focused suite; the actual focused run reports **22 passed, 0 failed**.
  Cosmetic reporting mismatch only — no code impact, does not affect the verdict.
  Optional to correct the report count.
