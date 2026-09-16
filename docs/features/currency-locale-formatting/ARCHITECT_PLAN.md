# ARCHITECT_PLAN — currency-locale-formatting

## Feature Slug

`currency-locale-formatting`

## Feature Title

Currency amounts format with US conventions regardless of the band's selected currency/country

## Problem Summary

Every band financial amount (gig pay, financial entries, savings deposits, the
Financials totals, and the exported Financials PDF) renders with US
grouping/decimal conventions and US-style symbol-as-prefix placement, no matter
which currency/country the band selected. Two independent code defects produce
this, and a third data-model gap makes a correct fix impossible without a schema
change:

1. `BandCurrency.formatCents()` hardcodes `NumberFormat('#,##0.00', 'en_US')`
   and manually prepends the symbol as a prefix.
2. `financials_report_builder.dart` builds a **separate**
   `NumberFormat.currency(symbol: ..., decimalDigits: 2)` with **no `locale:`**,
   so the PDF falls back to the rendering device's locale (a different, also
   wrong result).
3. `bands.currency_code` alone cannot select a formatting convention: USD spans
   United States (`en_US`) and Ecuador (`es_EC`), and EUR spans generic Eurozone
   (`de_DE`) and Bulgaria (`bg_BG`) — same currency code, different real-world
   number formatting. A lookup keyed by currency code silently collapses each
   pair to whichever row wins map construction.

## Root Cause (confidence: HIGH — confirmed in code)

- `lib/features/bands/currency/band_currency.dart` lines 235–240:
  `symbolFor()` returns `symbol ?? code`; `formatCents()` calls
  `NumberFormat('#,##0.00', 'en_US')` and returns `'${symbolFor(code)}$amount'`
  — locale is pinned to `en_US` and placement is unconditionally prefix. HIGH.
- `lib/features/financials/financials_report_builder.dart` lines 31–34:
  `NumberFormat.currency(symbol: BandCurrency.symbolFor(currencyCode),
  decimalDigits: 2)` with no `locale:` argument. HIGH.
- `lib/features/bands/currency/band_currency.dart` `byIsoCode` (line 231) is
  keyed by `isoCode`; the shortlist was reduced to 30 rows in
  `feature/band-form-overlay-redesign`, merging US/Ecuador into one USD row and
  Eurozone/Bulgaria into one EUR row (`countryLabel: 'Eurozone / Bulgaria'`).
  Because two countries with different conventions share one code, currency code
  is provably insufficient — an independently authoritative `locale` is
  required. HIGH (verified against the reference table and the intl behavior
  documented in the Feature Input).
- **Cycle 2 runtime evidence (HIGH — probed live against `intl 0.20.3`):** the
  generalization that `NumberFormat.currency(locale: X, symbol: glyph,
  decimalDigits: 2)` yields the correct *symbol placement* for every locale is
  false for `es_CL`. intl carries es_CL's number *symbols* (grouping `.`,
  decimal `,`) but not an es_CL-specific currency *pattern*, so it falls back to
  the generic Spanish (`es`) suffix pattern and emits `1.234,50\u00A0$`. The
  Feature Input's authoritative expected string for Chile is the prefix
  `$1.234,50`, which is the real-world Chilean convention. Grouping and decimal
  are therefore correct; only placement is wrong, and only for Chile among the
  three locales the Feature Input pins (de_DE and de_CH already match intl — see
  Existing System Analysis).

## Existing System Analysis

Formatting funnels through `BandCurrency` everywhere except the PDF builder:

- Static entry points: `BandCurrency.formatCents(cents, code)` and
  `BandCurrency.symbolFor(code)`.
- Model convenience methods delegate to those statics:
  `Gig.formatPay(String)`, `FinancialEntry.formatAmount(String)`,
  `FinancialEntry.formatDepositToSavings(String)`,
  `GigPayDetails.formatAmount(String)`.
- Every widget call site resolves the code identically:
  `ref.watch(activeBandProvider).activeBand?.currencyCode ??
  BandCurrency.defaultCode`, then calls a format/symbol method with that string.
- The PDF path (`financials_report_builder.dart` +
  `financials_pdf_preview_screen.dart`) is, today, the one place that does
  **not** go through `BandCurrency` — it builds its own `NumberFormat`. Every
  money value it prints is an integer-cent amount rendered as
  `moneyFmt.format(amountCents / 100)`, and `moneyFmt` is threaded through seven
  private helpers. The fix (Proposed Solution item 5) deletes that threaded
  money `NumberFormat` and instead threads the shared `BandCurrency`, calling
  `currency.format(cents)` at each site so the PDF reuses the identical display
  path. A separate `DateFormat` for dates is threaded independently and is
  retained (so the intl import stays).
- `Band` (`lib/app/models/band.dart`) carries `currencyCode` (default `'USD'`,
  `fromJson`/`toJson`) but no `locale`.
- `ActiveBandState.==`/`hashCode`
  (`lib/features/bands/active_band_controller.dart` lines 195, 208) compare
  `activeBand?.currencyCode` but not a locale. A USD→USD change (United States →
  Ecuador) keeps `currencyCode == 'USD'` while the convention changes, so
  without a locale term the state compares equal and currency-dependent widgets
  do not rebuild (this repo has a documented history of stale-state-after-band-
  switch bugs).
- Picker (`band_form_screen.dart` `_buildCurrencySection`, lines 1988–2054) is a
  closed `AppDropdown<String>` keyed on `currencyCode` via `pickerGroups()`.
- Band writes: `_createBand` (line ~369) does `create_band` RPC then a follow-up
  `bands.update({timezone, currency_code})`; `_updateBand` (line ~500) does
  `bands.update({..., currency_code})` and constructs an `updatedBand` for
  `updateActiveBand`. The `create_band` RPC does not touch currency/locale (the
  app sets them in the follow-up update), so **no RPC change is needed**.

Verified formatting mechanics (Cycle 2 — probed live against pinned
`intl 0.20.3` for all 32 locales): `NumberFormat.currency(locale: X, symbol:
glyph, decimalDigits: 2)` yields the correct grouping and decimal separator for
every one of the 32 locales, and passing `name:` (ISO code) instead of `symbol:`
prints the bare code and is wrong. Symbol *placement*, however, is intl's locale
currency pattern and is **not** uniformly the real-world convention:

- Of the three locales the Feature Input pins an exact expected string for,
  **two already match intl**: de_DE → `1.234,50\u00A0€` (suffix) equals the
  generic-Eurozone expectation `1.234,50 €`, and de_CH → `CHF\u00A01'234.50`
  (prefix) equals the Swiss expectation `CHF 1'234.50` (the visible space is a
  no-break space, U+00A0).
- The third, **Chile, does not**: es_CL → `1.234,50\u00A0$` (suffix), but the
  authoritative expectation and real-world convention is the prefix `$1.234,50`.
  intl lacks an es_CL-specific currency pattern and falls back to generic `es`.
- The remaining 29 locales have **no** authoritative expected string in the
  Feature Input, so intl's emitted placement is accepted as-is for them (per the
  "no speculative overrides without evidence" constraint). For the record the
  probe shows most South-American pesos land on intl's suffix (e.g., es_AR/es_CO
  → `1.234,50\u00A0$`) and the 8 prefix locales are en_US, es_MX, en_CA, en_GB,
  en_GY, de_CH, pt_BR, nl_SR.

Locales intl lacks curated *symbol* data for still fall back to their language
family — never to `en_US`.

## Proposed Solution

Resolve a single `BandCurrency` value object once from the band and thread that
object (not bare strings) through every display surface, so `currencyCode` and
`locale` can never drift apart across the ~13 call sites. Concretely:

1. **`BandCurrency`**: add a `locale` field to every entry; restore the
   shortlist to the 32 rows in the reference table (split US/Ecuador and
   Eurozone/Bulgaria into separate rows, each keeping its currency's existing
   symbol). Add `static Map<String, BandCurrency> byLocale` (locale is unique
   across all 32 rows) as the canonical resolver; keep `byIsoCode` only as a
   legacy fallback. Add:
   - `String get glyph => symbol ?? isoCode;` (preserves today's
     `symbolFor`→ISO-fallback behavior for CHF/RSD/MKD/MDL).
   - a narrow placement-override data field `final bool forceSymbolPrefix;`
     (default `false`), set `true` on **only** the Chile (`es_CL`) row — the
     single locale where intl's placement contradicts an authoritative
     Feature-Input expected string.
   - `String format(int cents)` that delegates grouping/decimal/rounding to intl
     and overrides only placement when required:
     - default (`forceSymbolPrefix == false`, all 31 other rows) →
       `NumberFormat.currency(locale: locale, symbol: glyph, decimalDigits: 2).format(cents / 100)`
       (unchanged behavior).
     - Chile (`forceSymbolPrefix == true`) → build the bare number with
       `NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: 2).format(cents / 100)`
       (locale grouping/decimal, no symbol, no trailing space) and return
       `'$glyph$number'` — i.e. `$1.234,50`. intl still owns grouping, decimal,
       and rounding; the app supplies only the no-space prefix placement.
       (Probed live on `intl 0.20.3`: `decimalPatternDigits(locale:'es_CL',
       decimalDigits:2).format(1234.50)` → `1.234,50`, so the result is exactly
       `$1.234,50`. `decimalPatternDigits` is part of the already-imported
       `package:intl/intl.dart` — no new import or dependency.)
   - `static const BandCurrency fallback` (the `USD`/`en_US` row) for the
     null-active-band case.
   Remove the broken static `formatCents(cents, code)` and `symbolFor(code)` so
   the `en_US`-hardcoded path is no longer callable. `pickerGroups()` maps
   `pickerLabel → locale` instead of `→ isoCode`.
2. **`Band`**: add `locale` (default `'en_US'`, mirroring `currencyCode` in
   `fromJson`/`toJson`) and a getter
   `BandCurrency get currency => BandCurrency.byLocale[locale] ??
   BandCurrency.byIsoCode[currencyCode] ?? BandCurrency.fallback;`.
3. **Model methods**: change `Gig.formatPay`, `FinancialEntry.formatAmount`,
   `FinancialEntry.formatDepositToSavings`, and `GigPayDetails.formatAmount` to
   accept a `BandCurrency` and call `currency.format(cents)`.
4. **Call sites**: replace
   `...activeBand?.currencyCode ?? BandCurrency.defaultCode` +
   `formatCents/symbolFor(...)` with
   `...activeBand?.currency ?? BandCurrency.fallback` +
   `currency.format(cents)` / `currency.glyph`.
5. **PDF**: `buildFinancialsReportContent` takes `required BandCurrency currency`
   (was `String currencyCode`) and threads that **same `BandCurrency`** through
   its private rendering helpers — it builds **no** `NumberFormat` for money.
   Every private helper that currently receives a `NumberFormat moneyFmt`
   (`_buildItemizedSection`, `_buildItemRow`, `_buildBandSavingsSection`,
   `_buildDateLineItem`, `_buildBandDisbursementsSection`,
   `_buildDisbursementLineItem`, `_buildSubtotalRow`) instead receives
   `BandCurrency currency`, and each money-rendering call
   `moneyFmt.format(amountCents / 100)` becomes `currency.format(amountCents)` —
   the **exact** integer-cents path every display surface uses. This is what
   makes the PDF honor the Chile placement override (`$1.234,50`) instead of
   intl's raw `1.234,50\u00A0$` suffix, so PDF output matches on-screen output
   for every currency (satisfying the manual requirement that PDF match
   on-screen formatting). The `DateFormat` date formatter (`dateFmt`) is
   untouched and still threaded, so `package:intl/intl.dart` stays imported and
   is **not** removed solely for dropping the money `NumberFormat`.
   `financials_report_builder.dart` already imports `band_currency.dart`, so no
   new import is added. `FinancialsPdfPreviewScreen.currencyCode` becomes
   `currency`; its caller `_openCombinedReport` passes
   `activeBand?.currency ?? BandCurrency.fallback`. The public builder and
   preview signatures therefore carry the `BandCurrency` object, not a bare
   string.
6. **Active band equality**: add `activeBand?.locale` to `ActiveBandState.==`
   and `hashCode`.
7. **Picker**: key the dropdown on `locale`; on save derive
   `currency_code = BandCurrency.byLocale[selectedLocale]!.isoCode`. Write both
   `currency_code` and `locale` in the two `bands.update` calls and set both on
   the `updatedBand` object.
8. **Migration** (see Database Impact).

Display-only. Integer-cents storage semantics are untouched; `decimalDigits: 2`
is pinned for every currency (no ISO-minor-unit adoption). Only one locale
(Chile/`es_CL`) carries a placement override; every other row formats purely
through intl, and no override is added for any locale lacking an authoritative
expected string in the Feature Input. The live-typing `CurrencyInput*` widgets
are out of scope and keep prefix-only US-grouped display during active entry.

## Database Impact

One new migration:
`supabase/migrations/20260915130000_add_locale_to_bands.sql`. In order:

1. `ALTER TABLE public.bands ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL
   DEFAULT 'en_US';` The `ADD COLUMN` default populates every existing row's
   `locale` with `'en_US'` (the column does not exist beforehand, so no row can
   already carry an invalid non-`en_US` value).
2. **Conditional (invalid-only) backfill** — correct only rows whose current
   `(currency_code, locale)` pair is **not** one of the 32 valid pairs, setting
   `locale` to the **primary** locale for that `currency_code`:
   `UPDATE public.bands SET locale = CASE currency_code … END
   WHERE (currency_code, locale) NOT IN (<the 32 valid pairs>);`. The CASE maps
   the ambiguous codes to their primary country — `USD → 'en_US'`,
   `EUR → 'de_DE'` — and the other 28 to their unique locale (`CAD→en_CA,
   MXN→es_MX, GBP→en_GB, CHF→de_CH, PLN→pl_PL, CZK→cs_CZ, HUF→hu_HU, DKK→da_DK,
   SEK→sv_SE, NOK→nb_NO, ISK→is_IS, RON→ro_RO, RSD→sr_RS, ALL→sq_AL, MKD→mk_MK,
   MDL→ro_MD, UAH→uk_UA, ARS→es_AR, BOB→es_BO, BRL→pt_BR, CLP→es_CL, COP→es_CO,
   GYD→en_GY, PYG→es_PY, PEN→es_PE, SRD→nl_SR, UYU→es_UY, VES→es_VE`). On the
   one-time apply this repairs every non-`USD` row (each carries the `'en_US'`
   default, invalid for its code) to its primary locale and leaves `USD` rows at
   the valid `('USD','en_US')`, so no row is left mispaired before the CHECK is
   added. The `WHERE … NOT IN (32 pairs)` guard makes the statement **genuinely
   idempotent and selection-preserving**: a re-run matches zero rows because
   every row is already valid, and an intentionally selected valid non-primary
   pair such as `USD/es_EC` or `EUR/bg_BG` is a member of the 32-pair set and is
   therefore **never overwritten** back to `en_US`/`de_DE`. The migration is
   still authored as a single ordered apply; the guard only guarantees re-run
   safety.
3. **Composite CHECK** `bands_currency_locale_check` on the 32 valid
   `(currency_code, locale)` pairs. Add it **after** the backfill (by then every
   row is valid). Use the `DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT` pattern
   already used by `bands_currency_code_check`.
4. Leave the existing `bands_currency_code_check` in place — all 32 rows use
   codes already in its 30-code set, so it stays satisfied.
5. `COMMENT ON COLUMN public.bands.locale`.

**No normalization trigger or function is added** — it is out of scope. The
additive column, deterministic invalid-only backfill, and composite CHECK are
together sufficient to guarantee no invalid `(currency_code, locale)` pair is
ever persisted. The current app always writes a valid pair, so it is unaffected.
The only write path that could attempt an invalid pair is an older intermediate
client build — one that shipped the `feature/band-form-overlay-redesign`
currency picker but not this locale fix — that updates `currency_code` without
`locale`; such a write now **fails closed** (rejected by
`bands_currency_locale_check`) rather than silently persisting a mismatch. That
exposure is unconfirmed (MEDIUM confidence) and, per the Architecture Gate, does
not justify adding speculative repair behavior — failing closed is the correct,
minimal outcome. RLS is unchanged — `bands_update_admins` /
`bands_select_members` already gate writes/reads and column authorization is
inherited from the row policies (same as the `currency_code` migration).

## Flutter Architecture Changes

No new providers, controllers, or repositories. Changes are: two model fields +
a getter (`Band`), a value-object API on the existing `BandCurrency`
(instance `format`/`glyph`, `byLocale`, `fallback`, one `forceSymbolPrefix` bool
field used only by Chile; removal of two broken statics), signature changes on
four existing model methods (String → value object), and in-place edits at the
existing resolve-and-format call sites. The `activeBandProvider` equality gains
one term.

## Files to Create

- `supabase/migrations/20260915130000_add_locale_to_bands.sql` — column,
  conditional (invalid-only) backfill, composite CHECK, column comment
  (per Database Impact). No trigger or function.

## Files to Modify

- `lib/features/bands/currency/band_currency.dart` — add `locale` field and the
  `forceSymbolPrefix` bool field (default `false`, set `true` only on the Chile
  row); restore 32 rows with locales/symbols from the reference table; add
  `byLocale`, `fallback`, `glyph`, and `format(int)` (branching on
  `forceSymbolPrefix` as in Proposed Solution); map `pickerGroups()` to
  `locale`; remove static `formatCents` and `symbolFor`.
- `lib/app/models/band.dart` — add `locale` field (default `'en_US'`) +
  `fromJson`/`toJson`; add `BandCurrency get currency`; import `band_currency`.
- `lib/features/bands/active_band_controller.dart` — add `activeBand?.locale` to
  `ActiveBandState.==` and `hashCode`.
- `lib/app/models/gig.dart` — `formatPay(BandCurrency currency)` →
  `currency.format(gigPayCents!)`.
- `lib/features/financials/models/financial_entry.dart` —
  `formatAmount(BandCurrency)`, `formatDepositToSavings(BandCurrency)`,
  `GigPayDetails.formatAmount(BandCurrency)`.
- `lib/features/financials/financials_report_builder.dart` — public
  `buildFinancialsReportContent` param `currencyCode` → `required BandCurrency
  currency`; **delete** the money `NumberFormat.currency(...)` formatter
  entirely; change the seven private helpers that take `NumberFormat moneyFmt`
  (`_buildItemizedSection`, `_buildItemRow`, `_buildBandSavingsSection`,
  `_buildDateLineItem`, `_buildBandDisbursementsSection`,
  `_buildDisbursementLineItem`, `_buildSubtotalRow`) to take `BandCurrency
  currency`; replace each `moneyFmt.format(amountCents / 100)` with
  `currency.format(amountCents)`. Keep the `DateFormat dateFmt` threading and the
  `package:intl/intl.dart` import (still used by `DateFormat`);
  `band_currency.dart` is already imported.
- `lib/features/financials/financials_pdf_preview_screen.dart` — `currencyCode`
  field → `currency`; pass `currency:` into `buildFinancialsReportContent`.
- `lib/features/financials/financials_screen.dart` — resolve `currency` at each
  site (lines ~260, ~293, ~572–574, ~788, ~837) and pass
  `currency:` into `FinancialsPdfPreviewScreen` (line ~916).
- `lib/features/financials/widgets/add_financial_entry_bottom_sheet.dart` —
  lines ~119 (`formatCents`), ~709/~711, ~993 → resolve `currency`, use
  `currency.format` / `currency.glyph`.
- `lib/features/financials/widgets/gig_pay_bottom_sheet.dart` — lines ~178/~231
  → `currency.glyph` for `currencySymbol:`.
- `lib/features/financials/widgets/financial_entry_details_bottom_sheet.dart` —
  lines ~44/~109 → `currency` + `formatAmount(currency)`/
  `formatDepositToSavings(currency)`.
- `lib/features/events/widgets/gig_expense_subview.dart` — lines ~44/~264/~280.
- `lib/features/events/widgets/gig_form_fields.dart` — lines ~727/~752/~778.
- `lib/features/gigs/widgets/view_gig_drawer.dart` — lines ~418/~618
  (`gig.formatPay(currency)`).
- `lib/features/bands/band_form_screen.dart` — currency picker keyed on
  `locale`; add `_selectedLocale`/`_initialLocale`; derive `currency_code` from
  the selected locale; write `locale` in both `bands.update` calls; set `locale`
  on the `updatedBand` object.
- `test/features/bands/band_currency_test.dart` — rewrite for 32 rows, `locale`
  field, `byLocale`, and instance `format`/`glyph` (see Verification Plan).
- `test/features/bands/band_model_test.dart` — add `locale`
  default/`fromJson`/`toJson` round-trip and `Band.currency` resolution cases.
- `test/features/bands/active_band_controller_invalidation_test.dart` — add a
  case proving a locale-only change (USD `en_US` → USD `es_EC`) makes
  `ActiveBandState` compare unequal.
- `test/features/financials/widgets/transaction_card_test.dart` — seed `locale`
  in `_SeededActiveBandNotifier` and update any expected formatted strings.

## Files Off-Limits

- `lib/features/**/currency_input_*.dart` / `CurrencyInputController` /
  `CurrencyTextField` — live-typing widgets, explicitly out of scope.
- `supabase/functions/**` — no edge-function change.
- `create_band` RPC / any existing DB function — unchanged (app sets
  currency/locale in the post-create `bands.update`).
- `supabase/migrations/20260915120000_add_currency_code_to_bands.sql` — do not
  edit a shipped migration; the new one is additive.
- Init sequence in `main.dart` and any auth/session/routing code — untouched.
- `DraftBandNotifier` in `active_band_controller.dart` — its `Band(...)`
  reconstructions already drop `currencyCode` (draft state drives only the
  header avatar preview, never the currency source, and is never persisted as
  the active band). It does not compile-break with the new default and does not
  regress; leave it as-is.

## Change Budget

- `band_currency.dart`: ~+105 / −18 net (32 rows × `locale:` line + split 2
  rows; `byLocale`/`fallback`/`glyph` added; `format` added with the two-branch
  body; `forceSymbolPrefix` field added and set on the Chile row;
  `formatCents`/`symbolFor` removed).
- New migration file: ~90 lines (verbose only because the 30-code CASE, the
  32-pair `NOT IN` backfill guard, and the 32-pair CHECK are each spelled out).
- `band.dart`: ~+12.
- `band_form_screen.dart`: ~+14 / −6.
- `active_band_controller.dart`: +2.
- `financials_report_builder.dart`: ~−3 net (delete the ~4-line money
  `NumberFormat.currency(...)` formatter; swap seven `NumberFormat moneyFmt`
  helper params 1:1 to `BandCurrency currency`; swap the three section-call args
  and the four `moneyFmt.format(cents / 100)` sites 1:1 to
  `currency.format(cents)`; no import change, no new public API).
- Each of the ~10 remaining source call-site files: net ~0 to +2 (in-place
  substitutions).
- 4 test files: `band_currency_test.dart` ~+40 net (rewrite);
  others +6 to +12 each.
- New public API added: `BandCurrency.byLocale`, `BandCurrency.fallback`,
  `BandCurrency.glyph`, `BandCurrency.format`, `BandCurrency.forceSymbolPrefix`,
  `Band.locale`, `Band.currency` (7). Public API removed:
  `BandCurrency.formatCents`, `BandCurrency.symbolFor` (2).
- New DB objects: 1 column, 1 CHECK constraint (no trigger, no function).
- New dependencies: 0.

## System Impact Map

- Financials: **affected** (screen totals, entry lists, bottom sheets, PDF).
- Gigs / Events: **affected** (gig pay display, expense subview, form fields,
  view drawer).
- Members / Auth / Routing / Notifications: **unaffected**.
- Init order: **unaffected** (no change to `main.dart` sequence).
- Bands: **affected** (model + picker + active-band equality).
- Platforms: iOS/Android/macOS/web **all affected identically** — this is shared
  Dart display code and one shared migration; no platform-conditional branch is
  touched, so per-platform behavior stays in lockstep.

## Regression Risk

**MEDIUM.** Wide call-site surface (~13 files), a change to `ActiveBandState`
equality (drives currency-widget rebuilds), and a DB migration that adds a
column, an invalid-only backfill, and a composite CHECK. It does **not** touch
auth/session/routing/init-order. Principal risks: (a) a missed call site still
calling a now-removed static (caught by `flutter analyze`); (b) an existing row
left mispaired before the CHECK is added (mitigated by the ordered invalid-only
backfill, which corrects every default `'en_US'` sitting on a non-`USD` code);
(c) an older intermediate client that updates `currency_code` without `locale` —
this now **fails closed** at the CHECK rather than persisting a mismatch
(accepted, by design; see Database Impact), and no speculative repair trigger is
added to mask it; (d) a stale currency widget after a same-code locale switch
(mitigated by the equality change and its dedicated test). The Cycle 2 Chile
placement override is a single additive branch gated by one boolean set on one
row; it cannot alter any other locale's output (asserted by the override-scoping
tests) and does not raise the overall risk. The Cycle 3 PDF change **removes**
rather than adds risk: it deletes the builder's independent money `NumberFormat`
and reuses `BandCurrency.format`, so the PDF can no longer disagree with
on-screen output (both the previous Chile PDF mismatch and the device-locale
fallback are eliminated). It is a mechanical 1:1 param/type swap across seven
private helpers with no behavioral branch of its own; the static source
assertion catches any residual `NumberFormat` money path.

## Engineer Task Breakdown (ordered, atomic)

1. `band_currency.dart`: add `locale` and `forceSymbolPrefix` (bool, default
   `false`) to the entry constructor/fields; rebuild `shortlist` as the 32
   reference rows (each with its `locale` and existing `symbol`, US/Ecuador and
   Eurozone/Bulgaria split; generic EUR labeled `Eurozone (generic)`); set
   `forceSymbolPrefix: true` on **only** the Chile (`es_CL`) row; add
   `byLocale`, `fallback`, `glyph`, and `format(int)` with the two-branch body
   from Proposed Solution (default → `NumberFormat.currency(...)`; Chile →
   `glyph` prepended to the `NumberFormat.decimalPatternDigits(locale: locale,
   decimalDigits: 2)` number, no space); change `pickerGroups()` items to
   `pickerLabel → locale`; remove `formatCents` and `symbolFor`.
2. `band.dart`: add `locale` field/default/`fromJson`/`toJson` and the
   `currency` getter; import `band_currency`.
3. `gig.dart`, `financial_entry.dart`: change the four format methods to accept
   `BandCurrency` and call `currency.format(...)`.
4. `financials_report_builder.dart` + `financials_pdf_preview_screen.dart`:
   change `buildFinancialsReportContent`'s `currencyCode` param to `required
   BandCurrency currency` and `FinancialsPdfPreviewScreen.currencyCode` →
   `currency` (its `_buildPdf` passes `currency: widget.currency`). In the
   builder, **delete** the money `NumberFormat.currency(...)` formatter; change
   the seven private helpers that take `NumberFormat moneyFmt`
   (`_buildItemizedSection`, `_buildItemRow`, `_buildBandSavingsSection`,
   `_buildDateLineItem`, `_buildBandDisbursementsSection`,
   `_buildDisbursementLineItem`, `_buildSubtotalRow`) to take `BandCurrency
   currency`; replace each `moneyFmt.format(amountCents / 100)` with
   `currency.format(amountCents)`. Leave `DateFormat dateFmt` and the intl
   import in place.
5. Update every widget call site (`financials_screen.dart`,
   `add_financial_entry_bottom_sheet.dart`, `gig_pay_bottom_sheet.dart`,
   `financial_entry_details_bottom_sheet.dart`, `gig_expense_subview.dart`,
   `gig_form_fields.dart`, `view_gig_drawer.dart`) to resolve
   `activeBand?.currency ?? BandCurrency.fallback` and call
   `currency.format(...)` / `currency.glyph`.
6. `active_band_controller.dart`: add `activeBand?.locale` to `==` and
   `hashCode`.
7. `band_form_screen.dart`: key the picker on `locale`; add
   `_selectedLocale`/`_initialLocale` and include locale in `_isDirty`; derive
   `currency_code` from the selected locale; write `locale` in both
   `bands.update` payloads and on the `updatedBand`.
8. Author `20260915130000_add_locale_to_bands.sql` per Database Impact
   (column → invalid-only conditional backfill → composite CHECK → comment, in
   that order; no trigger, no function).
9. Update the four test files to the new API/data (see Verification Plan).
10. `flutter analyze` and `flutter test` clean.

## Verification Plan

**Tier 1 — pre-deploy, mechanically executable by QA without a running app
(this is QA's gate for APPROVED):**

- `flutter analyze` — zero new issues (also confirms no residual caller of the
  removed `formatCents`/`symbolFor`).
- **Static source assertion on `financials_report_builder.dart`** (grep-level,
  mechanically executable without a running app — this is the mechanical guard
  that falsifies a Chile PDF mismatch): after the change the file contains
  **no** `NumberFormat.currency(` and **no** `moneyFmt.format(` occurrence;
  every money-rendering site instead calls `currency.format(` (expect exactly 4
  such sites — `_buildItemRow`, `_buildDateLineItem`,
  `_buildDisbursementLineItem`, `_buildSubtotalRow`), and
  `buildFinancialsReportContent`'s signature reads `required BandCurrency
  currency`. Because the PDF now calls the identical `BandCurrency.format(int
  cents)` already asserted for `es_CL` in `band_currency_test.dart`
  (`byLocale['es_CL']!.format(123450) == r'$1.234,50'`), the Chile PDF amount is
  equal to the on-screen amount **by construction**; any regression that
  re-introduces a `NumberFormat`-based PDF money path is caught by this grep.
  **No PDF-content widget test is added:** there is no existing
  pw.Widget/pw.Text introspection harness in `test/`, so asserting rendered
  text out of `pdf`-package widgets would require standing up new
  rendering/introspection infrastructure (out of scope and over the change
  budget). The static assertion here plus the shared-path `es_CL` unit
  assertion in `band_currency_test.dart` mechanically falsify a Chile PDF
  mismatch without a running app; the on-device PDF export is the owner
  punch-list confirmation (step 5).
- `flutter test` on the four touched test files. Required assertions:
  - `band_currency_test.dart`: `shortlist` has length 32; `byLocale` has 32
    keys and covers all 32 locales; `byIsoCode` has 30 keys and `['USD']` /
    `['EUR']` still resolve (legacy fallback intact); `fallback.locale ==
    'en_US'`. Instance `format`, using explicit `expect`s (not a table), with
    the **exact** strings probed live on `intl 0.20.3` (the between-number-and-
    symbol separator intl emits is a no-break space, U+00A0 — assert that
    literal, never a regular space):
    `byLocale['en_US']!.format(123450) == r'$1,234.50'`;
    `byLocale['de_DE']!.format(123450) == '1.234,50\u00A0€'` (intl suffix;
    matches the generic-Eurozone expectation — note the separator is `\u00A0`,
    **not** a regular space);
    `byLocale['es_CL']!.format(123450) == r'$1.234,50'` (the placement-override
    result — prefix, no space);
    `byLocale['de_CH']!.format(123450)` contains `1'234.50` **and** `CHF`
    (assert on the actual emitted string; the full value is `CHF\u00A01'234.50`);
    rounding on the integer-cents path: `byLocale['en_US']!.format(123500) ==
    r'$1,235.00'`; `glyph` fallback: `byLocale['de_CH']!.glyph == 'CHF'`,
    `byLocale['sr_RS']!.glyph == 'RSD'`.
    **Override-scoping (proves the Chile prefix override did not globally flip
    placement):** `byLocale['es_CL']!.forceSymbolPrefix == true`;
    `byLocale['es_AR']!.forceSymbolPrefix == false` and
    `byLocale['de_DE']!.forceSymbolPrefix == false`;
    `byLocale['es_AR']!.format(123450) == '1.234,50\u00A0$'` (a sibling peso
    stays on intl's default suffix).
    Pin every expected string by reading the intl output during implementation
    rather than hand-deriving spacing/NBSP.
  - `band_model_test.dart`: `locale` defaults to `'en_US'`; `fromJson` reads it;
    `toJson` round-trips it; `Band(currencyCode:'EUR', locale:'bg_BG').currency`
    resolves to the Bulgaria row; a legacy row (locale absent) resolves via the
    `en_US` default.
  - `active_band_controller_invalidation_test.dart`: two `ActiveBandState`s
    differing only in `activeBand.locale` (both `USD`, `en_US` vs `es_EC`)
    compare **unequal** and hash differently.
  - `transaction_card_test.dart`: seeds `locale`; formatted-amount expectations
    updated to the locale-correct strings.
- **Static SQL review** of the migration: statement order (column → backfill →
  CHECK); confirm **no trigger and no function** are present; the column is
  `TEXT NOT NULL DEFAULT 'en_US'`; the backfill `UPDATE` is guarded by
  `WHERE (currency_code, locale) NOT IN (<the 32 pairs>)` (invalid-only, so it
  never rewrites an already-valid pair) and its `CASE` covers all 30 codes,
  mapping `USD→en_US` / `EUR→de_DE` and the other 28 each to their unique locale;
  the composite CHECK `bands_currency_locale_check` lists **exactly** the 32
  reference pairs (check each pair line-by-line against the reference table — no
  missing pair, no extra pair); the existing `bands_currency_code_check` is left
  intact and the CHECK uses the `DROP CONSTRAINT IF EXISTS` → `ADD CONSTRAINT`
  pattern.
- **Ephemeral-DB apply-check** (scratch/throwaway DB, must clean up after
  itself, no production UUIDs). Seed pre-migration rows that exercise the
  backfill — a `EUR` row, a `CHF` row, and a `USD` row (none has a `locale`
  column yet) — then apply the migration and assert:
  - **Column shape:** `locale` exists as `TEXT NOT NULL DEFAULT 'en_US'`.
  - **Backfill correctness:** the `EUR` row is now `('EUR','de_DE')`, the `CHF`
    row is `('CHF','de_CH')`, and the `USD` row stayed `('USD','en_US')` — every
    seeded row lands on a valid pair, none left mispaired before the CHECK.
  - **Idempotency / selection preservation:** set one row explicitly to the
    valid non-primary pair `('USD','es_EC')` and another to `('EUR','bg_BG')`,
    re-run the backfill `UPDATE` verbatim, and assert **both are unchanged** —
    the `NOT IN (32 pairs)` guard skips already-valid rows, so an intentional
    Ecuador/Bulgaria selection is not clobbered back to `en_US`/`de_DE`.
  - **Valid write succeeds:** a normal app-style write of
    `(currency_code='CLP', locale='es_CL')` succeeds.
  - **Invalid pair rejected by the CHECK:** with no normalizing trigger present,
    an explicit invalid write is **rejected** by `bands_currency_locale_check` —
    test both the old-intermediate-client shape (`UPDATE … SET
    currency_code='EUR'` while `locale` stays `'en_US'`, yielding the invalid
    `('EUR','en_US')`) and a direct non-member pair (`('CLP','de_DE')`). The
    write fails closed; nothing is silently normalized.
  - **All 32 pairs accepted:** each of the 32 reference `(currency_code, locale)`
    pairs updates/inserts successfully, proving the CHECK admits exactly the
    intended set and rejects everything else.

**Idempotency:** display-only change; no submission/parse flow is added or
altered, integer-cents storage is untouched, and `format` is a pure function of
`(cents, currency)` — identical input yields identical output. The migration
backfill is deterministic and re-run-safe by construction (the
`NOT IN (32 pairs)` guard), and that re-run/selection-preservation property is
asserted directly in the ephemeral-DB apply-check above. No separate
idempotency test file is required.

**Owner-run checks (Tony, at PR-test / apply time — NOT a QA gate; require the
running app, which QA cannot launch). Exact punch list:**

1. Run the app; edit a band, set Currency to **Chile — Chilean Peso (CLP)**;
   save. Add/open a financial entry of `1234.50`. Expected on the Financials
   screen and the gig-pay/expense fields: `$1.234,50` (prefix `$`, dot
   grouping, comma decimals — this is the Chile-only placement override). Note
   other South-American pesos such as Argentina intentionally render with intl's
   suffix, e.g. `1.234,50 $` — that is expected, not a bug.
2. Set the same band's Currency to **Eurozone (generic) — Euro (EUR)**; save.
   Expected: `1.234,50 €` (symbol suffix, space).
3. Set Currency to **Bulgaria — Euro (EUR)**; save. Expected: Bulgarian EUR
   convention (grouping/decimal per `bg_BG`), distinct from step 2's German
   layout — confirm the amount still reads as a Euro value and the app rebuilds
   immediately on this same-code (EUR→EUR) locale switch without needing a band
   re-select (validates the equality change).
4. Set Currency to **Switzerland — Swiss Franc (CHF)**; save. Expected:
   `CHF 1'234.50` (apostrophe thousands separator).
5. Export the Financials PDF for a band in each of the above currencies;
   confirm each PDF amount is **character-for-character identical** to the
   on-screen amount for the same entry (same grouping, decimal, and symbol
   placement). In particular, for the **Chile (CLP)** band the PDF must read
   `$1.234,50` (prefix `$`, no space) — the same as on screen — not intl's raw
   `1.234,50 $` suffix; and the **Eurozone (generic) — EUR** band's PDF must
   read `1.234,50 €`. This confirms the PDF uses the shared
   `BandCurrency.format` path and no longer builds its own `NumberFormat` /
   falls back to device locale.
6. On both an iOS build and an Android build, repeat step 1 once to confirm
   identical output across platforms.

## QA Regression Areas

- Financials screen totals, income/expense lists, and the three financials
  bottom sheets render without exceptions after the API swap.
- Gig pay display in `view_gig_drawer`, `gig_form_fields`, and
  `gig_expense_subview`.
- Financials PDF export builds without exceptions and its amounts use the
  shared `BandCurrency.format` path — no money `NumberFormat` remains in
  `financials_report_builder.dart` (static source assertion), and Chile PDF
  reads `$1.234,50` matching on-screen.
- Band edit/save (currency picker) persists both `currency_code` and `locale`;
  band create persists both; switching bands or changing only the locale
  refreshes currency-dependent widgets.
- No caller of the removed `formatCents`/`symbolFor` remains (analyzer).

## Rollout Strategy

Standard single-PR rollout on `bug/currency-locale-formatting`. Ship the
migration with the app release so the paired-write app and the composite CHECK
land together. Because the new app always writes a valid `(currency_code,
locale)` pair, no ordering fragility exists for it; only an older intermediate
client that writes `currency_code` alone would be rejected by the CHECK (it
fails closed — never a silent mismatch), which is the intended safety behavior
rather than something the migration must accommodate. No feature flag.
Reversible: the column and CHECK are additive; reverting the app code leaves the
column harmlessly populated (and the CHECK can be dropped independently if
ever needed).

## Out of Scope

- Live-typing `CurrencyInput*` widgets (prefix-only US grouping during entry).
- Adopting ISO 4217 minor units (0 decimals for CLP/PYG/ISK) — rejected; keep 2
  decimals everywhere.
- Any change to stored-amount (integer-cents) semantics.
- Refactoring `DraftBandNotifier`'s pre-existing currency/locale drop (header-
  preview-only, non-persisted).
