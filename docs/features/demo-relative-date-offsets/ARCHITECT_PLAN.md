# ARCHITECT_PLAN — feature/demo-relative-date-offsets

## Feature Slug

`feature/demo-relative-date-offsets`

## Feature Title

Make Demo Band Gig/Rehearsal/Financial Dates Relative to Provisioning Time Instead of Hardcoded

## Problem Summary

The two demo template bands ("The Banana Stand", "Figrin D'an and the Modal
Nodes") seeded in [supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql)
carry hardcoded absolute dates on every gig (`gigs.date`), rehearsal
(`rehearsals.date`), and financial entry (`financial_entries.entry_date`) — for
example `2026-05-15` for "Motherboy XXX" and `2027-02-14` for "Chalmun's
Anniversary". `provision_demo_session()` (see [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql),
steps 5h/5i/5j) clones those templates for each anonymous visitor and copies
those date columns **verbatim**. Every "future" gig therefore ages irreversibly
into the past as real time passes: Banana Stand's last upcoming gig expires
`2027-01-14` and Modal Nodes' expires `2027-02-14`, after which every new demo
visitor sees zero upcoming gigs on both bands, permanently, until someone
manually rewrites the seed. All financial entries and rehearsals degrade the
same way.

## Root Cause

**Confidence: HIGH.** Confirmed by reading the seed migration (dates authored as
`'2026-05-15'`-style DATE literals in the `INSERT ... VALUES` for `gigs`,
`rehearsals`, `financial_entries`) and the clone RPC (`INSERT INTO gigs (..., date, ...) VALUES (..., v_gig.date, ...)`,
`INSERT INTO rehearsals (..., date, ...) VALUES (..., v_rehearsal.date, ...)`,
`INSERT INTO financial_entries (..., entry_date, ...) VALUES (..., v_fe.entry_date, ...)`
— no offset computation, no `now()`-derived math on any date column anywhere in
the clone path). The root cause is the design choice to store demo template
dates as absolute calendar values in the same column the RPC copies straight
through, with no anchor-relative computation between authoring time and
provisioning time.

## Existing System Analysis

- **Template rows are anchored to a static authoring date.** The seed
  ([supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql),
  sections 9 / 10 / 12 around lines 502–700) was written on 2026-09-04 with the
  intent of "~3 past / 4 future" gigs per band. That relative shape only holds
  on the authoring day. Today (2026-09-12) the past window is already skewed
  further into the past.
- **The clone RPC copies dates verbatim.** In
  [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql):
  step 5h reads `v_gig.date` and passes it directly to the clone's `INSERT INTO
  gigs`; step 5i does the same for `v_rehearsal.date`; step 5j for
  `v_fe.entry_date`. `gig_dates` / `rehearsal_dates` clones (nested inside 5h /
  5i) copy `gd.date` / `rd.date` verbatim too, though those template tables
  currently have zero rows.
- **`now()` is transaction-stable.** Postgres `now()` returns
  `transaction_timestamp()`, which is fixed for the duration of one transaction
  — so any expression using `now()::date` inside the RPC will return the same
  anchor date at every call site within a single provision, without any need for
  explicit caching. (I still cache it in a local for readability — see Task 4.)
- **Schema constraints on the target columns:**
  - `financial_entries.entry_date` is `DATE NOT NULL` ([supabase/migrations/20260601000000_create_financial_entries.sql](supabase/migrations/20260601000000_create_financial_entries.sql), line 18).
  - `rehearsal_dates.date` is `DATE NOT NULL` ([supabase/migrations/20260519160119_add_rehearsal_multi_date_support.sql](supabase/migrations/20260519160119_add_rehearsal_multi_date_support.sql), line 23).
  - `gigs.date`, `gig_dates.date`, `rehearsals.date` predate the tracked
    migration history but the seed populates every row with a non-null DATE
    literal, and the existing clone RPC assumes not-null. Treating these as
    `NOT NULL DATE` is safe.
  - **Implication:** we cannot leave the template rows' `date` / `entry_date`
    columns NULL, so any design that "empties out" the template dates and stores
    only the offset would require `ALTER TABLE ... DROP NOT NULL` on production
    tables that real bands write to every day. That's a materially wider blast
    radius than this feature needs.
- **Template-write-guard trigger** (`prevent_anonymous_template_write` in
  [supabase/migrations/20260904120000_demo_bands_schema.sql](supabase/migrations/20260904120000_demo_bands_schema.sql), lines 66–98)
  only fires for anonymous JWT sessions and only against the `bands`, `songs`,
  `setlists`, `gigs`, `rehearsals`, `venues`, `contacts`, `financial_entries`
  tables. A new offset lookup table sits outside its coverage — that's fine and
  intentional: the trigger's purpose is preventing anonymous mutations of demo
  data, and a lookup table whose only writer is the seed migration
  (postgres/superuser, RLS-bypassing by definition) doesn't need it.
- **`bands_real` view** ([supabase/migrations/20260904120000_demo_bands_schema.sql](supabase/migrations/20260904120000_demo_bands_schema.sql), lines 143–146)
  filters out `is_demo_template = true` and `is_demo_clone = true` rows from
  admin/analytics queries. Unaffected by this change (no bands schema touch).

## Proposed Solution

Introduce a new `demo_template_date_offsets` lookup table keyed by template row
UUID, storing the intended day-offset (positive or negative integer) from
provisioning time. Update `provision_demo_session()` so each clone-loop
iteration for gigs / gig_dates / rehearsals / rehearsal_dates /
financial_entries looks up the offset for that template row and inserts
`v_anchor_date + offset` instead of the template row's hardcoded date, where
`v_anchor_date := now()::date` is captured once at the top of the RPC.

**Why a separate lookup table (option b in the Feature Input) rather than
adding an offset column to each affected table (option a):**

1. Zero schema changes on the hot production tables (`gigs`, `rehearsals`,
   `gig_dates`, `rehearsal_dates`, `financial_entries`) that every real band
   writes to constantly. No `ALTER TABLE` and no `DROP NOT NULL` on
   `date` / `entry_date` (which option (a) requires per the schema constraints
   noted above).
2. Template rows' existing `date` / `entry_date` values are preserved as a
   harmless authoring-time reference and act as the safe fallback when an
   offset row is missing (see the fallback semantics under Task 4).
3. Single-file, self-contained change: one new table + 32 offset rows + one
   `CREATE OR REPLACE` on the RPC, all in one migration. Trivial to review,
   revert (drop the table, revert the RPC), or audit (`SELECT * FROM
   demo_template_date_offsets` shows the entire demo timeline in one query).
4. The offset table is scoped exclusively to demo templates — no real band data
   touches it, so it has no bearing on any real-band code path.

**Anchor semantics:** `v_anchor_date := now()::date` at the start of the RPC.
Every clone in that provision uses the same anchor. Two demo entries that share
a semantic relationship (e.g. "PA rental the night before Motherboy XXX" =
Motherboy XXX offset `-112` plus PA rental offset `-113`) stay exactly one day
apart because they're both computed from the same anchor.

## Database Impact

New migration file, timestamp-prefixed per repo convention: **`supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql`** (Engineer picks the concrete `HHMMSS` at authoring time from UTC). Contents:

1. `CREATE TABLE IF NOT EXISTS public.demo_template_date_offsets`:

   ```
   template_row_id UUID        PRIMARY KEY
   template_table  TEXT        NOT NULL CHECK (template_table IN
                                   ('gigs','gig_dates','rehearsals',
                                    'rehearsal_dates','financial_entries'))
   day_offset      INTEGER     NOT NULL
   created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
   ```

   `template_row_id` is unique on its own because the seed intentionally
   partitions UUID prefixes per table (`...8301-*` gigs, `...8401-*` rehearsals,
   `...8701-*` financial_entries, and the still-empty `gig_dates` /
   `rehearsal_dates` would follow the same scheme). RPC lookups still filter
   `AND template_table = '<table>'` as defense-in-depth.

2. `CREATE INDEX IF NOT EXISTS idx_demo_template_date_offsets_template_table
   ON public.demo_template_date_offsets(template_table)` — cheap, supports the
   RPC's per-table lookup filter cleanly.

3. `ALTER TABLE public.demo_template_date_offsets ENABLE ROW LEVEL SECURITY`.
   **No policies** — this lookup table is only read via the `SECURITY DEFINER`
   `provision_demo_session()` RPC (which bypasses RLS), and only written by the
   migration itself (as postgres, also bypassing RLS). No direct client access
   is needed. This is the tightest posture: RLS on, no policies, no grants
   beyond the default that gets stripped by the standard `REVOKE ALL ... FROM
   PUBLIC, anon` pattern the RPC itself carries.

4. 32 `INSERT ... ON CONFLICT (template_row_id) DO UPDATE SET day_offset =
   EXCLUDED.day_offset, template_table = EXCLUDED.template_table` rows, one per
   currently-seeded template row, using the exact offsets from the Feature
   Input's offset table (transcribed below into the Task Breakdown for
   Engineer). The `ON CONFLICT` clause makes the migration idempotent on
   re-apply.

5. `CREATE OR REPLACE FUNCTION public.provision_demo_session()` — the full
   function body from
   [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql)
   copied verbatim except for the offset-lookup and date-computation changes
   detailed in Task 4. Same signature (`RETURNS jsonb`), same
   `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public`, same idempotency
   contract, same capacity ceiling, same idempotency-race handling.

6. `REVOKE ALL ON FUNCTION public.provision_demo_session() FROM PUBLIC, anon;
   GRANT EXECUTE ON FUNCTION public.provision_demo_session() TO authenticated;`
   — identical to the grant posture on the original RPC.

**No `ALTER TABLE` on any existing production table.** No changes to `bands`,
`gigs`, `gig_dates`, `rehearsals`, `rehearsal_dates`, `financial_entries`,
`demo_sessions`, `songs`, `setlists`, `venues`, `contacts`, `band_members`, or
any other shared table.

**No new triggers, no new RLS policies on existing tables, no changes to the
`prevent_anonymous_template_write` trigger or its coverage.**

## Flutter Architecture Changes

n/a

## Files to Create

- **[supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql](supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql)** —
  the single migration described in Database Impact. Engineer picks `HHMMSS`
  from UTC at authoring time to preserve migration order.

## Files to Modify

None. This feature is purely additive:
- The new migration file `CREATE OR REPLACE`s the RPC (repo-standard pattern —
  see [supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql](supabase/migrations/20260814120002_restore_setlist_rpc_definitions.sql)
  for prior art of superseding an RPC in a later migration).
- The template seed migration keeps its existing hardcoded dates. Once the new
  migration runs, those dates are unused by the RPC on the happy path but
  remain valid `NOT NULL DATE` values in the template rows (needed to satisfy
  schema constraints) and act as the fallback if a given template row's offset
  is missing.

## Files Off-Limits

- **All `lib/**` client code** — no Flutter changes. The client reads
  `gigs.date`, `rehearsals.date`, `financial_entries.entry_date` from the
  cloned rows and doesn't care whether they were computed at clone time or
  authored statically.
- **[supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql)** —
  do not modify. Template dates stay put; the offset table supersedes them at
  clone time and the hardcoded dates remain as the safety fallback.
- **[supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql)** —
  do not modify. The new migration `CREATE OR REPLACE`s the function; the
  original migration file stays as-is (repo convention preserves migration
  history).
- **[supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql](supabase/migrations/20260904120005_cleanup_demo_sessions_cron.sql)
  and [supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql)** —
  explicitly out of scope per the Feature Input's Additional Context.
- **Any `ALTER TABLE` on `gigs`, `gig_dates`, `rehearsals`, `rehearsal_dates`,
  `financial_entries`, `bands`, `demo_sessions`** — schema of those tables is
  unchanged by this feature.
- **Any change to `prevent_anonymous_template_write` or its trigger coverage,
  or to the `bands_real` view** — unrelated to this feature.

## Change Budget

- New files: 1 (`supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql`).
- Modified files: 0.
- New Postgres objects: 1 table (`public.demo_template_date_offsets`), 1 index
  (`idx_demo_template_date_offsets_template_table`).
- New Postgres functions: 0 (the RPC is replaced in place via `CREATE OR
  REPLACE`, not added as a new function).
- New Dart classes / methods / providers / repositories: 0.
- New dependencies (any language): 0.
- Expected net line delta:
  - **`supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql`**:
    +350 to +450 lines. Roughly ~40 lines for the table + index + RLS-enable,
    ~55 lines for the 32 offset row inserts (with inline "Banana Stand: 3
    past gigs" style comments matching the seed migration's format), ~270–370
    lines for the `CREATE OR REPLACE FUNCTION` body copied from the current
    RPC (~340 lines today) plus the offset lookups (~15 lines of new logic in
    total across the five loops).
  - All other files: 0 net change.

## System Impact Map

- **Gigs:** unaffected in real bands. Demo clones now compute
  `gigs.date` (and cloned `gig_dates.date`, currently zero rows) from anchor +
  offset instead of copying the template date.
- **Rehearsals:** same as Gigs — no real-band impact. Demo clones compute
  `rehearsals.date` (and `rehearsal_dates.date`, currently zero rows) from
  anchor + offset.
- **Setlists:** unaffected. The RPC's setlist clone path (5e) doesn't touch
  dates.
- **Members:** unaffected. Band member clone (5b/5c) doesn't touch dates.
- **Auth:** unaffected. No changes to sign-in, PKCE, session lifecycle, JWT
  handling, or the anonymous auth path.
- **Routing:** unaffected. Deep links, `bandroadie://login-callback/`, web
  `/auth/confirm` — none touched.
- **Notifications:** unaffected. No notification triggers fire from RPC
  `SECURITY DEFINER` writes into cloned tables (existing behavior, unchanged).
- **Platforms (Web / iOS / Android / macOS):** all identically affected because
  this is 100% backend. No `--dart-define` config touched, no
  platform-conditional code touched. The init order chain
  (`WidgetsFlutterBinding` → URL strategy → orientation → `AppVersionService.init`
  → `validateSupabaseConfig` → `Supabase.initialize` → `Firebase.initializeApp`
  [native] → `DeepLinkService` → `runApp`) is not touched. No AI_DECISIONS.md
  or RUNTIME_CONFIG.md update is required.
- **Real (non-demo) bands:** explicitly unaffected. The RPC is only reachable
  by anonymous JWTs (guard on line ~57 of the current RPC:
  `IF NOT ((auth.jwt() ->> 'is_anonymous')::boolean IS TRUE) THEN RAISE
  EXCEPTION 'Not an anonymous session';`), and even inside the RPC the writes
  only target the clone's `demo_session_id`-scoped bands, never any
  `is_demo_template = false AND is_demo_clone = false` band. The offset lookup
  table only holds template row UUIDs, never any real band data.

## Regression Risk

**MEDIUM.**

The change touches a `SECURITY DEFINER` RPC on the critical path of every
anonymous demo provision — an outright bug (e.g. bad offset math, wrong table
filter, missing lookup) would surface as visible-to-visitor demo breakage.
However:

- No schema alters on any production table used by real bands.
- No changes to authentication, session lifecycle, RLS, or routing.
- No changes to the RPC's overall structure — the clone loops, idempotency
  handling, capacity ceiling, and race handling are copied verbatim. Only the
  `date` / `entry_date` value computations change.
- The change has a built-in safe fallback (see Task 4): if the offset lookup
  returns NULL for a given template row, the RPC reverts to the template's
  hardcoded date + `RAISE NOTICE` — so a bad or partial offset seed degrades
  gracefully instead of breaking provisioning outright.
- The RPC replacement is atomic within the migration transaction — no
  partial-deploy window where some fields are offset and others aren't.

## Engineer Task Breakdown

Each task is one atomic edit to the single new migration file. Do them in
order; do not split across files.

### Task 1 — Create the new migration file

Path: **`supabase/migrations/20260912HHMMSS_demo_relative_date_offsets.sql`**.
Use `date -u +%H%M%S` to pick `HHMMSS` at authoring time. Header comment:
identify the file, describe the two things it does (offsets table + RPC
replacement), and reference `feature/demo-relative-date-offsets`.

### Task 2 — Create `demo_template_date_offsets` table + index + RLS-enable

```sql
CREATE TABLE IF NOT EXISTS public.demo_template_date_offsets (
  template_row_id UUID         PRIMARY KEY,
  template_table  TEXT         NOT NULL CHECK (template_table IN (
                                  'gigs','gig_dates','rehearsals',
                                  'rehearsal_dates','financial_entries'
                                )),
  day_offset      INTEGER      NOT NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_demo_template_date_offsets_template_table
  ON public.demo_template_date_offsets(template_table);

ALTER TABLE public.demo_template_date_offsets ENABLE ROW LEVEL SECURITY;
-- Intentionally no policies: reads only via SECURITY DEFINER RPC path;
-- writes only via this migration running as postgres.
```

### Task 3 — Insert 32 offset rows

Use the exact offsets from the Feature Input's offset table, all
`ON CONFLICT (template_row_id) DO UPDATE SET day_offset = EXCLUDED.day_offset,
template_table = EXCLUDED.template_table` for idempotent re-apply. Comment
groups exactly as the seed migration does ("Banana Stand: 3 past gigs" /
"Banana Stand: 4 future gigs" / "Modal Nodes: 3 past gigs" / etc.).

**Banana Stand gigs (7):**

| Template row UUID | Table | Offset (days) |
|---|---|---|
| `00000000-0000-4000-8301-000000000001` (Motherboy XXX) | `gigs` | `-112` |
| `00000000-0000-4000-8301-000000000002` (Cornballer Fundraiser) | `gigs` | `-76` |
| `00000000-0000-4000-8301-000000000003` (Banana Stand Grand Opening) | `gigs` | `-62` |
| `00000000-0000-4000-8301-000000000004` (Sudden Valley Block Party) | `gigs` | `+27` |
| `00000000-0000-4000-8301-000000000005` (Gob's Magic Show Afterparty) | `gigs` | `+72` |
| `00000000-0000-4000-8301-000000000006` (Bluth Company Holiday Party) | `gigs` | `+107` |
| `00000000-0000-4000-8301-000000000007` (Tobias Nevernude Benefit) | `gigs` | `+132` |

**Modal Nodes gigs (7):**

| Template row UUID | Table | Offset (days) |
|---|---|---|
| `00000000-0000-4000-8302-000000000001` (Mos Eisley Grand Opening) | `gigs` | `-156` |
| `00000000-0000-4000-8302-000000000002` (Mandalorian Bar Mitzvah) | `gigs` | `-107` |
| `00000000-0000-4000-8302-000000000003` (Imperial Celebration) | `gigs` | `-34` |
| `00000000-0000-4000-8302-000000000004` (Spice Mine Benefit) | `gigs` | `+36` |
| `00000000-0000-4000-8302-000000000005` (Rebel Alliance Fundraiser) | `gigs` | `+82` |
| `00000000-0000-4000-8302-000000000006` (Galactic New Year) | `gigs` | `+118` |
| `00000000-0000-4000-8302-000000000007` (Chalmun's Anniversary) | `gigs` | `+163` |

**Banana Stand rehearsals (4):**

| Template row UUID | Table | Offset (days) |
|---|---|---|
| `00000000-0000-4000-8401-000000000001` | `rehearsals` | `-25` |
| `00000000-0000-4000-8401-000000000002` | `rehearsals` | `-3` |
| `00000000-0000-4000-8401-000000000003` | `rehearsals` | `+31` |
| `00000000-0000-4000-8401-000000000004` | `rehearsals` | `+66` |

**Modal Nodes rehearsals (4):**

| Template row UUID | Table | Offset (days) |
|---|---|---|
| `00000000-0000-4000-8402-000000000001` | `rehearsals` | `-51` |
| `00000000-0000-4000-8402-000000000002` | `rehearsals` | `-15` |
| `00000000-0000-4000-8402-000000000003` | `rehearsals` | `+21` |
| `00000000-0000-4000-8402-000000000004` | `rehearsals` | `+58` |

**Banana Stand financial_entries (5):**

| Template row UUID | Table | Offset (days) | Notes |
|---|---|---|---|
| `00000000-0000-4000-8701-000000000001` | `financial_entries` | `-112` | gig_pay, linked to Motherboy XXX (offset must match `-112`) |
| `00000000-0000-4000-8701-000000000002` | `financial_entries` | `-76` | gig_pay, linked to Cornballer Fundraiser (must match `-76`) |
| `00000000-0000-4000-8701-000000000003` | `financial_entries` | `-62` | merch, unlinked |
| `00000000-0000-4000-8701-000000000004` | `financial_entries` | `-113` | expense "PA rental for Motherboy XXX" — one day before Motherboy XXX (`-112`) by intent |
| `00000000-0000-4000-8701-000000000005` | `financial_entries` | `-95` | expense, unlinked |

**Modal Nodes financial_entries (5):**

| Template row UUID | Table | Offset (days) | Notes |
|---|---|---|---|
| `00000000-0000-4000-8702-000000000001` | `financial_entries` | `-156` | gig_pay, linked to Mos Eisley Grand Opening (must match `-156`) |
| `00000000-0000-4000-8702-000000000002` | `financial_entries` | `-34` | gig_pay, linked to Imperial Celebration (must match `-34`) |
| `00000000-0000-4000-8702-000000000003` | `financial_entries` | `-156` | merch, unlinked |
| `00000000-0000-4000-8702-000000000004` | `financial_entries` | `-65` | expense, unlinked |
| `00000000-0000-4000-8702-000000000005` | `financial_entries` | `-20` | expense, unlinked |

Total: **32 rows** (14 gigs + 8 rehearsals + 10 financial_entries).
`gig_dates` / `rehearsal_dates` intentionally get zero rows here (no template
rows exist to point at) — see Out of Scope.

### Task 4 — `CREATE OR REPLACE FUNCTION public.provision_demo_session()`

Copy the entire current function body from
[supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql)
verbatim (keep the signature, `LANGUAGE plpgsql SECURITY DEFINER SET
search_path = public`, all the existing DECLARE variables, the anonymous-guard,
idempotency check, capacity ceiling, and every clone loop). Then make **only**
these narrow changes:

1. **Add to DECLARE block:**
   ```
   v_anchor_date  DATE  := now()::date;
   v_gig_date     DATE;
   v_rehearsal_date DATE;
   v_gd_date      DATE;
   v_rd_date      DATE;
   v_fe_date      DATE;
   ```

2. **In the gigs LOOP (step 5h)** — before the `INSERT INTO gigs (...) VALUES (...)`:
   ```
   SELECT v_anchor_date + day_offset INTO v_gig_date
   FROM demo_template_date_offsets
   WHERE template_row_id = v_old_gig_id AND template_table = 'gigs';

   IF v_gig_date IS NULL THEN
     RAISE NOTICE 'No offset row for gig %; falling back to template date %',
       v_old_gig_id, v_gig.date;
     v_gig_date := v_gig.date;
   END IF;
   ```
   Then replace `v_gig.date` with `v_gig_date` in the `INSERT INTO gigs (...)
   VALUES (..., v_gig_date, ...)` — every other column stays exactly as it is.

3. **In the nested `gig_dates` clone (still inside step 5h)** — replace the
   current single-statement `INSERT INTO gig_dates ... SELECT gen_random_uuid(),
   v_new_gig_id, gd.date, gd.start_time FROM gig_dates gd WHERE gd.gig_id =
   v_old_gig_id` with a per-row loop that looks up each candidate date's offset:
   ```
   FOR v_gd IN
     SELECT id, date, start_time FROM gig_dates WHERE gig_id = v_old_gig_id
   LOOP
     SELECT v_anchor_date + day_offset INTO v_gd_date
     FROM demo_template_date_offsets
     WHERE template_row_id = v_gd.id AND template_table = 'gig_dates';

     IF v_gd_date IS NULL THEN
       RAISE NOTICE 'No offset row for gig_date %; falling back to template date %',
         v_gd.id, v_gd.date;
       v_gd_date := v_gd.date;
     END IF;

     INSERT INTO gig_dates (id, gig_id, date, start_time)
     VALUES (gen_random_uuid(), v_new_gig_id, v_gd_date, v_gd.start_time);
   END LOOP;
   ```
   Add `v_gd RECORD;` to the DECLARE block.

4. **In the rehearsals LOOP (step 5i)** — mirror of step (2), reading from the
   `rehearsals` filter:
   ```
   SELECT v_anchor_date + day_offset INTO v_rehearsal_date
   FROM demo_template_date_offsets
   WHERE template_row_id = v_old_rehearsal_id AND template_table = 'rehearsals';

   IF v_rehearsal_date IS NULL THEN
     RAISE NOTICE 'No offset row for rehearsal %; falling back to template date %',
       v_old_rehearsal_id, v_rehearsal.date;
     v_rehearsal_date := v_rehearsal.date;
   END IF;
   ```
   Replace `v_rehearsal.date` with `v_rehearsal_date` in the `INSERT INTO
   rehearsals (...)` VALUES clause.

5. **In the nested `rehearsal_dates` clone** — same restructuring as step (3)
   but for the `rehearsal_dates` table + `template_table = 'rehearsal_dates'`.
   Add `v_rd RECORD;` to DECLARE.

6. **In the financial_entries LOOP (step 5j)** — mirror of step (2):
   ```
   SELECT v_anchor_date + day_offset INTO v_fe_date
   FROM demo_template_date_offsets
   WHERE template_row_id = v_fe.id AND template_table = 'financial_entries';

   IF v_fe_date IS NULL THEN
     RAISE NOTICE 'No offset row for financial_entry %; falling back to template date %',
       v_fe.id, v_fe.entry_date;
     v_fe_date := v_fe.entry_date;
   END IF;
   ```
   Replace `v_fe.entry_date` with `v_fe_date` in the `INSERT INTO
   financial_entries (...)` VALUES clause. Note that the current inner loop
   selects `entry_type, category, amount_cents, is_income, description,
   entry_date, gig_id` from `financial_entries WHERE band_id = v_template.id`
   — the `SELECT` also needs to include `id` so the offset lookup can key on
   `v_fe.id`. Add `id` to that SELECT list.

7. **Do not touch** any other line of the function body. Do not "improve", "refactor",
   or "rename". No new variables beyond the six declared in step (1) plus `v_gd`,
   `v_rd`. No comment-only edits inside unrelated blocks.

### Task 5 — Grants

At the end of the migration:

```sql
REVOKE ALL ON FUNCTION public.provision_demo_session() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provision_demo_session() TO authenticated;
```

Identical to the original RPC's grant posture. No grants on
`demo_template_date_offsets` — the RLS-on/no-policy stance combined with
`SECURITY DEFINER` RPC access is the tightest correct posture.

### Task 6 — Nothing else

Do not modify any other file. No Dart, no other migration, no doc changes, no
`AI_DECISIONS.md` entry (this change doesn't touch init order or any
cross-cutting architectural decision).

## Verification Plan

### Tier 1 — pre-deploy (no calls to the replaced RPC)

QA gates that are mechanically executable without a running app:

1. **`flutter analyze`** — must pass. No client code changed, so no new
   analyzer output is expected. Non-zero exit is a fail.
2. **`flutter test`** — must pass. No new Flutter tests are required for this
   change (backend-only). Existing test suite must continue to pass.
3. **Static SQL cross-check on the new migration file** — parse the SQL text
   with `psql --dry-run` or equivalent (or `pg_prove --dry-run` on an ephemeral
   Postgres), verify no syntax errors, and grep-cross-check that every
   `template_row_id` in the offset row inserts exists as a `gigs.id`,
   `rehearsals.id`, or `financial_entries.id` in
   [supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql).
   Expected: 32 hits, one per row. Zero hits or fewer than 32 = fail.
4. **Ephemeral-DB apply-check.** Spin up a scratch Postgres, apply every
   migration in
   [supabase/migrations/](supabase/migrations) in filename order, verify the
   new migration applies without error, then run:
   ```sql
   SELECT template_table, count(*)
   FROM public.demo_template_date_offsets
   GROUP BY template_table
   ORDER BY template_table;
   ```
   Expected: `financial_entries=10, gigs=14, rehearsals=8`. Any other row
   count = fail.
5. **`SECURITY DEFINER` grant posture check** (repo-standard verification —
   never a string match on the raw ACL array):
   ```sql
   SELECT has_function_privilege('anon',          'public.provision_demo_session()'::regprocedure, 'EXECUTE') AS anon_execute,
          has_function_privilege('authenticated', 'public.provision_demo_session()'::regprocedure, 'EXECUTE') AS authenticated_execute,
          has_function_privilege('public',        'public.provision_demo_session()'::regprocedure, 'EXECUTE') AS public_execute;
   ```
   Expected: `anon_execute=false, authenticated_execute=true, public_execute=false`.
   Any other combination = fail. (This also proves the `REVOKE ALL FROM
   PUBLIC, anon` and `GRANT EXECUTE ... TO authenticated` posture survived
   the `CREATE OR REPLACE`.)

### Tier 2 — post-deploy (calls to the replaced RPC, wrapped in ROLLBACK)

Run inside a `BEGIN; ... ROLLBACK;` block against the ephemeral / staging DB so
no test data leaks. Do not hardcode production UUIDs — use the deterministic
template UUIDs already seeded in
[supabase/migrations/20260904120001_seed_demo_templates.sql](supabase/migrations/20260904120001_seed_demo_templates.sql).

1. **Provision harness.** Create an anonymous auth user, `SET LOCAL ROLE
   authenticated` with a JWT claim `is_anonymous=true`, then
   `SELECT provision_demo_session();`. Capture the returned `banana_stand_band_id`
   and `modal_nodes_band_id`.
2. **Anchor idempotency.** Confirm every cloned `gigs.date`,
   `rehearsals.date`, and `financial_entries.entry_date` on the two clone bands
   is within `[now()::date - 200, now()::date + 200]` — proves anchor-relative
   computation ran on every row.
3. **Ratio check.** For both clone bands, count
   `SELECT count(*) FILTER (WHERE date < now()::date) AS past, count(*) FILTER
   (WHERE date >= now()::date) AS future FROM gigs WHERE band_id = <clone id>`.
   Expected: `past=3, future=4` on each band. Any other split = fail.
4. **Rehearsal count.** `SELECT count(*) FROM rehearsals WHERE band_id =
   <clone id>` on each band. Expected: `4` per band.
5. **Financial entry count.** `SELECT count(*) FROM financial_entries WHERE
   band_id = <clone id>` on each band. Expected: `5` per band.
6. **Gig-linked financial relationship.** On the Banana Stand clone:
   ```sql
   SELECT
     (SELECT date FROM gigs WHERE band_id = <clone id> AND name = 'Motherboy XXX')
     - (SELECT entry_date FROM financial_entries
        WHERE band_id = <clone id> AND description = 'PA rental for Motherboy XXX');
   ```
   Expected: `1` (one day). Any other value = fail (proves the offset-preserved-relationship
   guarantee held).
7. **Same-day gig_pay relationship.** On the Banana Stand clone:
   ```sql
   SELECT
     (SELECT date FROM gigs WHERE band_id = <clone id> AND name = 'Cornballer Fundraiser')
     - (SELECT entry_date FROM financial_entries
        WHERE band_id = <clone id> AND description = 'Cornballer Fundraiser gig pay');
   ```
   Expected: `0`. Any other value = fail.
8. **No-NULL guard.** `SELECT count(*) FROM gigs WHERE band_id IN (<both clone
   ids>) AND date IS NULL;` — expected `0`. Same for `rehearsals.date` and
   `financial_entries.entry_date`. Any non-zero = fail.
9. **Real-band regression guard.** `SELECT id, name, date FROM gigs WHERE
   band_id NOT IN (SELECT id FROM bands WHERE is_demo_template OR is_demo_clone);`
   before and after the RPC call — snapshot must be identical (byte-for-byte).
   Any diff = fail (the RPC accidentally touched a real band's data, which the
   `is_anonymous` guard should have prevented).
10. **`ROLLBACK;`** to leave the DB clean.

### Owner-run checks (Tony's punch list — hand this verbatim to Tony at
apply / PR-test time, not a QA gate)

QA can't launch the app or drive a running instance, so these are Tony's to
run against the deployed staging or prod environment after the migration is
applied.

1. In Supabase Studio → SQL editor, run:
   ```sql
   SELECT template_table, count(*)
   FROM public.demo_template_date_offsets
   GROUP BY template_table
   ORDER BY template_table;
   ```
   **Expected:** three rows — `financial_entries=10, gigs=14, rehearsals=8`.
2. Sign out entirely; on the marketing landing page, click "Try demo" (or the
   equivalent anonymous demo entry point).
3. Wait for provisioning; land on the Banana Stand dashboard.
4. On Banana Stand, verify the **Upcoming Gigs** list shows exactly 4 gigs
   ("Sudden Valley Block Party", "Gob's Magic Show Afterparty", "Bluth Company
   Holiday Party", "Tobias Nevernude Benefit") and every date is in the future
   relative to today. **Expected:** 4 upcoming, all future dates.
5. On Banana Stand, verify the **Past Gigs** list shows exactly 3 gigs
   ("Motherboy XXX", "Cornballer Fundraiser", "Banana Stand Grand Opening")
   and every date is in the past. **Expected:** 3 past, all past dates.
6. Switch to Modal Nodes; repeat steps 4–5 with the Modal Nodes gig set (4
   upcoming: "Spice Mine Benefit", "Rebel Alliance Fundraiser", "Galactic New
   Year", "Chalmun's Anniversary"; 3 past: "Mos Eisley Grand Opening",
   "Mandalorian Bar Mitzvah", "Imperial Celebration").
7. Open the Financials view for Banana Stand. Find the "PA rental for
   Motherboy XXX" expense. **Expected:** its date is exactly one day before
   the Motherboy XXX gig's date. Find the "Cornballer Fundraiser gig pay"
   entry. **Expected:** its date is the same day as the Cornballer Fundraiser
   gig.
8. Exit the demo. Sign in as a real (non-demo) user in a real band. Open
   Gigs, Rehearsals, and Financials in that real band. **Expected:** no dates
   changed relative to the last known state (regression sanity — proves the
   RPC didn't accidentally touch a real band).

## QA Regression Areas

- `provision_demo_session()` behavior for anonymous users — must remain
  idempotent (second call with same `auth.uid()` returns existing clone band
  IDs without re-computing).
- Real-band `gigs` / `rehearsals` / `financial_entries` rows — must be
  byte-identical before and after RPC call, on real bands (the anonymous-only
  guard in step 1 of the RPC prevents this, but Tier 2 test #9 verifies it).
- `demo_sessions.expires_at` TTL and cleanup — unchanged. Should still be
  `now() + interval '15 minutes'` (per
  [supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql](supabase/migrations/20260908194500_reduce_demo_session_ttl_to_15min.sql)),
  and the 5-minute pg_cron sweep should still delete expired ones.
- Capacity ceiling (30 concurrent demo sessions) — unchanged.
- Template-write-guard trigger — must still block anonymous writes to
  template bands and their child rows.
- `bands_real` view — must still exclude both `is_demo_template=true` and
  `is_demo_clone=true` bands.
- Grant posture on `provision_demo_session()` — must remain
  `anon: no execute, authenticated: execute, public: no execute` (Tier 1 test #5).

## Rollout Strategy

1. Merge the migration PR to `main` after QA passes.
2. Apply the new migration to Supabase (repo-standard flow — the migration is
   idempotent on re-apply thanks to `ON CONFLICT DO UPDATE` on the offset
   inserts and `CREATE OR REPLACE` on the RPC).
3. Tony runs the owner-run punch list above against the applied environment.
4. No feature flag or gradual rollout — the change is a strictly
   backward-compatible internal replacement of an RPC that only affects
   anonymous demo sessions. All authenticated user flows are untouched.
5. **In-flight demo sessions** provisioned before the migration keep running
   with their stale hardcoded dates until their 15-min TTL expires; no live
   demo user experiences a mid-session change. New demo sessions provisioned
   after the migration applies pick up the evergreen offsets automatically.
6. **Rollback path:** revert with a small follow-up migration that (a) reverts
   `provision_demo_session()` to the pre-change body (still preserved verbatim
   in
   [supabase/migrations/20260904120003_provision_demo_session_rpc.sql](supabase/migrations/20260904120003_provision_demo_session_rpc.sql)),
   and (b) optionally `DROP TABLE public.demo_template_date_offsets` (harmless
   to leave in place if the RPC no longer references it).

## Out of Scope

- **`gig_dates` / `rehearsal_dates` template row backfill.** Both template
  tables currently have zero rows; the RPC's clone paths for these tables still
  work correctly with an empty template (nothing to clone). The new offset
  mechanism supports them if/when they're ever populated — but populating them
  is a separate design decision (which multi-date potential gig / rehearsal
  looks good for the demo?) that's not part of this feature. If a future
  migration adds rows to these tables without also adding offset rows to
  `demo_template_date_offsets`, the RPC's `RAISE NOTICE` + fallback-to-template-date
  path will surface it in logs.
- **`demo_sessions.expires_at` TTL / cron cleanup.** Explicitly out of scope
  per Feature Input; the 15-minute TTL and pg_cron sweep behavior are
  independent and already correct.
- **Client-side (Flutter) changes.** The client reads `gigs.date`,
  `rehearsals.date`, `financial_entries.entry_date` from the cloned rows and
  doesn't care whether they were computed at clone time or hardcoded. No Dart
  code touches this.
- **Non-date columns on demo template rows** (`start_time`, `end_time`,
  `load_in_time`, `location`, `address`, `venue_id`, `setlist_id`, `notes`,
  `gig_pay`, `is_potential`, etc.). Preserved verbatim by both the current
  and the replaced clone RPC — no time-of-day computation, no venue rotation,
  no setlist shuffling.
- **Any change to the "3 past / 4 future" per-band shape** (gig counts,
  rehearsal counts, financial entry counts, spacing between events).
  Preserved exactly per the Feature Input's offset table.
- **The `prevent_anonymous_template_write` trigger** and its coverage — no
  changes.
- **The `bands_real` view** — no changes.
- **Init-order / config surface / `--dart-define` / RUNTIME_CONFIG.md /
  AI_DECISIONS.md** — no changes; this is a Supabase-only migration.
