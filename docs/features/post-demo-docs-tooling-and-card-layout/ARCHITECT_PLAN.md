# Architect Plan

## Feature Slug
`post-demo-docs-tooling-and-card-layout`

## Feature Title
Consolidate documentation, screenshot tooling, and confirmed gig card refinements

---

## Revision History

**2026-09-05 — post-Cycle-4 verification adjustment.** QA Cycle 4 returned
REQUIRES CHANGES on two `[implementation-gap]` warnings that both concern
verification method rather than implementation quality. The implementation
itself is analyzer-clean, Node-clean, diff-clean, emoji-consistent, matches
the approved 11-file scope, and the Chrome layout smoke reached Home with
the widened cards rendering title / location / date / time rows without
overflow. This revision resolves the two verification gaps within the
same approved scope.

**Gap 1 — long-title runtime ellipsis fixture is not achievable within
this branch's scope.** The seeded demo band contains no confirmed gig
with a title long enough to visibly trigger the new ellipsis at the
widened 400 px maximum. Producing such a fixture would require **one of**
three options, and each is explicitly off-limits under this branch (see
"Files Off-Limits"):

- Editing the demo-band seed under `lib/**/*.dart` — a source change
  outside the one authorized Dart file (`confirmed_gig_card.dart`).
- Adding a widget or golden test that stubs a long-title `Gig` — a new
  file under `test/**`, which this plan disallows.
- Mutating a confirmed-gig row in Supabase to give it an artificially
  long title — a backend data touch on the app's real data, outside
  "safe test constraints" for this gate.

  Assessment: runtime verification of the title ellipsis with a
  long-title fixture is **not technically achievable** within the
  approved 11-file scope and safe test constraints. Because
  `Text(..., maxLines: 1, overflow: TextOverflow.ellipsis)` is a
  Flutter-framework primitive with well-defined semantics, and the
  Location and Date sibling rows in the same widget already carry the
  identical clamp with runtime rendering observable in the same Chrome
  layout smoke, **code inspection of the title hunk in
  `lib/features/home/widgets/confirmed_gig_card.dart` plus the successful
  Chrome layout smoke together give equivalent safety** for a two-line
  visual tweak of this size.

**Gap 2 — the pre-existing auth test failure is a known limitation, not
a regression.** `flutter test test/features/auth/login_screen_demo_button_test.dart`
failed at line 53 (`expect(find.text('Check Out the Demo Band'), findsOneWidget)`).
Engineer's Cycle 4 report reproduced the identical failure from a
disposable side-checkout of `origin/main` at commit `5cd19969` (this
branch's merge-base), confirming the failure predates this branch and is
unrelated to the approved 11-file scope. Fixing that test would either
touch `test/**` or `lib/features/auth/**`, both off-limits under this
plan. It is preserved as a documented known limitation, not a
plan-required green check.

**Adjustments applied below.** Only Tier 1 §3 and Tier 1 §4 in the
Verification Plan are amended to (a) accept code-path verification of the
title ellipsis clamp plus the successful Chrome layout smoke as
sufficient, (b) explicitly record the unavailable long-title fixture and
the three off-limits options that would produce it, and (c) preserve the
`origin/main`-baseline auth test failure as a known limitation rather
than a plan-required green check. No other section of this plan is
revised. No implementation source, test, migration, dependency, or
unrelated file is modified as part of this revision. The Change Budget
table and the QA-observed 92/45 totals remain within tolerance and are
unchanged.

---

## Problem Summary

Following the merge of PR #255 (interactive demo experience), Tony's local
branch `feature/interactive-demo-band-experience` still carries 11 uncommitted,
tracked modifications that he has explicitly approved for merge. They are a
mixed bag of unrelated but individually small housekeeping items:

- A brand-voice policy reversal (retire the 🎸 emoji from docs and one SVG
  mockup — the current guidance to use it is being replaced with "no emoji,
  ever").
- A manager agent policy hardening that inserts a mandatory human test gate
  between opening and merging a PR (`.github/agents/manager.agent.md`).
- Markdownlint-style refresh of `.github/copilot-instructions.md` (blank lines
  after headings + code fences) and removal of the outdated emoji-guidance
  bullet.
- A single Flutter UI refinement to `ConfirmedGigCard` — widen the max size and
  clamp the title to a single ellipsized line, matching the pattern already
  used by every other row in the same card.

None of these belongs on `feature/interactive-demo-band-experience`, whose
namesake work has already shipped. They need to move to a dedicated, narrowly
scoped branch that reads cleanly as one consolidation and merges without
dragging anything else in.

---

## Root Cause
**Confidence: HIGH.**

This is not a defect — it is an approved-scope consolidation. The full diff
against `origin/main` is exactly the 11 files Tony named, and each file's
change is small and self-contained (`git diff --stat` totals 89 insertions
and 42 deletions across all 11 files). The reason a plan is needed at all is
procedural: the work is sitting on a mis-labeled branch and, if left there,
would either get lost when that branch is deleted or accidentally bundled
into an unrelated future change.

Root cause of the consolidation-vs-scattered-commit choice: five different
concerns (brand voice, agent policy, lint hygiene, screenshot mockup, and one
UI polish) that would each be too small to justify their own branch on their
own, and that all reflect a single "post-PR-#255 sweep." Treating them as one
approved batch keeps the PR queue clean without splitting a two-line UI tweak
into its own PR.

---

## Existing System Analysis

### The 11 files, grouped by concern

**Group A — Brand-voice policy reversal (retire 🎸 emoji everywhere).**
The current `copilot-instructions.md` and `docs/agents/PROJECT_CONTEXT.md`
both instruct agents to use the 🎸 emoji in user-facing strings and doc
headings. That guidance is being retracted app-wide. The relevant edits:

- [docs/agents/PROJECT_CONTEXT.md](docs/agents/PROJECT_CONTEXT.md) — Brand
  Voice section: `"…with 🎸 emoji where appropriate."` → `"No emoji, ever
  (updated Sept 2026 — reverses the earlier emoji-prefixed style)."` Example
  strings de-emojified. Adds a one-line note that the legacy demo-login /
  demo-exit strings in `login_screen.dart` / `app_shell.dart` have been
  de-emojified (2026-09-05).
- [.github/copilot-instructions.md](.github/copilot-instructions.md) — Brand
  Voice section: removes the "Use 🎸 emoji for song-related feedback" and
  "Reference music/band culture" bullets; keeps "short and playful, not
  corporate" and "clear and actionable" guidance. Also adds blank lines
  after all headings and before/after every fenced code block (markdownlint
  MD022 / MD031 fixes) — cosmetic, no semantic change.
- [docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md](docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md) — remove 🎸
  from a section heading.
- [docs/reference/banners/NATIVE_APP_BANNER_README.md](docs/reference/banners/NATIVE_APP_BANNER_README.md) — remove 🎸 from
  two headings and body copy; replace "🎸 emoji + title" with "Icon +
  title" in a layout description.
- [docs/reference/bpm/BPM_QUICK_REFERENCE.md](docs/reference/bpm/BPM_QUICK_REFERENCE.md) — de-emojify heading and
  example strings.
- [docs/reference/general/BAND_ROADIE_DOCUMENTATION.md](docs/reference/general/BAND_ROADIE_DOCUMENTATION.md) — de-emojify
  a "Coming Soon" snackbar copy example and a checklist bullet.
- [docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md](docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md) — de-emojify
  heading and closing "Rock on!" line.

**Group B — Manager agent policy hardening.**
[.github/agents/manager.agent.md](.github/agents/manager.agent.md) refactors Step 6 into 6a/6b/6c:

- 6a — automatic once QA is APPROVED: `git add` exact files → commit → push
  → `gh pr create --body-file …/PR_BODY.md`. Unchanged from before.
- 6b — new: **stop** and ask Tony to test the PR before merging.
- 6c — new "Test Gate": never run `gh pr merge` until Tony explicitly
  approves (e.g. "merge it" / "ship it"); a QA APPROVED verdict alone does
  not authorize the merge; if Tony reports a problem, treat it as a QA
  `REQUIRES CHANGES` and re-invoke `engineer` before returning to 6b.

Also updates the frontmatter `description` and the "never do this" tail
paragraph to state the same rule ("QA approval authorizes opening the PR,
not merging it").

**Group C — App Store screenshot mockup cleanup.**
[BandRoadie/src/app_store_screenshots/generate_slides.js](BandRoadie/src/app_store_screenshots/generate_slides.js) and
[BandRoadie/src/app_store_screenshots/preview.html](BandRoadie/src/app_store_screenshots/preview.html) each drop a single
`<text>…🎸…</text>` element from the venue-card SVG in the contacts slide.
These files are **not** shipped in any Flutter build — they live in a
separate `BandRoadie/` subtree used to generate App Store screenshots. No
runtime effect.

**Group D — Confirmed gig card UI refinement.**
[lib/features/home/widgets/confirmed_gig_card.dart](lib/features/home/widgets/confirmed_gig_card.dart) — two edits, both in
`_ConfirmedGigCardState.build`:

1. Outer `Container.constraints`:
   `BoxConstraints(minWidth: 200, maxWidth: 300)` → `maxWidth: 400`.
2. Title `Text(widget.gig.name, …)`: add
   `maxLines: 1, overflow: TextOverflow.ellipsis`.

The card is rendered in a horizontally-scrolling `Row` (see
[lib/features/home/home_screen.dart](lib/features/home/home_screen.dart#L925-L945) `_buildHorizontalGigsList` and
[lib/features/home/home_tab_content.dart](lib/features/home/home_tab_content.dart#L1205)) so nothing upstream constrains
the card's width — the widget's own `BoxConstraints` fully determine it.
Every other row in the card (`locationDisplay`, formatted date, time range)
already uses `maxLines: 1` + `TextOverflow.ellipsis`; only the title was
missing that protection. This is a consistency fix plus a 100-px maximum
size increase for wider-layout devices.

### Baseline parity check (why this move is safe)

`git diff origin/main..HEAD --stat` — for the exact 11 files and for the
tree as a whole — returns zero output. That means every file in the current
branch's tree is byte-identical to `origin/main`, and the 11 uncommitted
working-tree modifications apply cleanly on top of `origin/main` without
conflict. The current branch's own commit (3e798f3) contributed no residual
diff vs `origin/main` post-squash — everything on it either landed in PR
#255 or is one of these 11 uncommitted files.

---

## Proposed Solution

Move the exact 11 uncommitted modifications, and nothing else, to a fresh
branch `feature/post-demo-docs-tooling-and-card-layout` cut from the current
tip of `origin/main`. Because the tracked baseline for those 11 files is
byte-identical between `origin/main` and the current branch, the working-tree
changes carry forward with no conflict. Ship as one PR titled after the
consolidation.

Engineer's role here is unusually thin: the code changes were already made
by Tony and approved. Engineer's job is to confirm the branch contains
exactly the intended 11-file diff vs `origin/main` (no more, no less), run
`flutter analyze` on the branch as a smoke check, and stop. No new code is
written.

---

## Database Impact
n/a

---

## Flutter Architecture Changes
n/a — the single Flutter edit is a two-line constraint tweak inside one
existing `StatefulWidget`. No new providers, controllers, repositories,
models, or dependencies.

---

## Files to Create
n/a

---

## Files to Modify

Exactly these 11 files — the diff is already present in Tony's working tree
and must be carried over unchanged:

1. `.github/agents/manager.agent.md` — Step 6 restructured into 6a/6b/6c
   with the new pre-merge test gate; frontmatter `description` updated;
   tail paragraph amended.
2. `.github/copilot-instructions.md` — markdownlint blank-line hygiene
   after headings and around code fences; two brand-voice bullets removed.
3. `BandRoadie/src/app_store_screenshots/generate_slides.js` — remove one
   `<text>…🎸…</text>` line from the contacts-slide venue card SVG.
4. `BandRoadie/src/app_store_screenshots/preview.html` — same single-line
   removal in the preview markup.
5. `docs/agents/PROJECT_CONTEXT.md` — Brand Voice section rewritten to say
   "no emoji, ever"; two example strings de-emojified; one-line note added
   about the 2026-09-05 de-emojification of the legacy demo strings.
6. `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` — remove 🎸 from
   one heading.
7. `docs/reference/banners/NATIVE_APP_BANNER_README.md` — remove 🎸 from
   two headings and one body line; replace the "🎸 emoji + title" layout
   descriptor with "Icon + title".
8. `docs/reference/bpm/BPM_QUICK_REFERENCE.md` — de-emojify one heading
   and two example strings.
9. `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` — de-emojify one
   snackbar copy example and one checklist bullet.
10. `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` — de-emojify one
    heading and one closing line.
11. `lib/features/home/widgets/confirmed_gig_card.dart` — outer `Container`
    `maxWidth: 300` → `maxWidth: 400`; title `Text` adds `maxLines: 1` +
    `overflow: TextOverflow.ellipsis`.

---

## Files Off-Limits

**Everything else in the repo.** This plan authorizes zero additional file
changes. Notably off-limits (all of the following would push scope past what
Tony approved):

- `lib/main.dart` and anything else in the app initialization chain
  (`AppVersionService`, `validateSupabaseConfig`, `Supabase.initialize`,
  `Firebase.initializeApp`, `DeepLinkService`). The init-order guardrail
  applies even though nothing here touches init.
- `pubspec.yaml`, `pubspec.lock`, `Podfile.lock`, `gradle.properties` — no
  dependency changes.
- Any Supabase migration (`supabase/migrations/**`), edge function
  (`supabase/functions/**`), RLS policy, or RPC. There is no database
  impact here at all.
- Auth code: `lib/features/auth/login_screen.dart`, `auth_confirm_screen.dart`,
  `app_shell.dart`. The `PROJECT_CONTEXT.md` diff mentions these files in a
  historical note only — it does **not** authorize touching them.
- Any other widget or feature under `lib/features/**` beyond
  `confirmed_gig_card.dart`.
- Any lint / formatter / analyzer config (`analysis_options.yaml`, etc.).
- Any additional file under `docs/` beyond the six listed above.
- Any tests under `test/**`. This scope does not add new test coverage —
  see the Verification Plan for why.
- The engineer may not run `dart format` on any file whose only modification
  in this branch is a doc-string change; auto-format would drag in unrelated
  whitespace churn. The Flutter file (`confirmed_gig_card.dart`) may only be
  auto-formatted if the analyzer flags the two-line hunk as ill-formatted —
  the current diff is already properly indented so this should be a no-op.

---

## Change Budget

Measured as net line delta (`+` insertions minus `-` deletions) against
`origin/main`. Numbers taken from `git diff --stat origin/main..HEAD` in
Tony's current working tree (which is exactly what the new branch must
contain).

| File | Expected `+` | Expected `-` | Notes |
|---|---|---|---|
| `.github/agents/manager.agent.md` | ~40 | ~23 | 6a/6b/6c restructure |
| `.github/copilot-instructions.md` | ~30 | ~2 | markdownlint hygiene + 2 bullets removed |
| `BandRoadie/src/app_store_screenshots/generate_slides.js` | 0 | 1 | one SVG `<text>` line |
| `BandRoadie/src/app_store_screenshots/preview.html` | 0 | 1 | same |
| `docs/agents/PROJECT_CONTEXT.md` | ~4 | ~2 | brand-voice rewrite |
| `docs/reference/auth/MAGIC_LINK_FIX_VERIFICATION.md` | 1 | 1 | heading only |
| `docs/reference/banners/NATIVE_APP_BANNER_README.md` | 3 | 3 | headings + body |
| `docs/reference/bpm/BPM_QUICK_REFERENCE.md` | 3 | 3 | heading + strings |
| `docs/reference/general/BAND_ROADIE_DOCUMENTATION.md` | 2 | 2 | two lines |
| `docs/reference/ui/LANDING_PAGE_PREVIEW_GUIDE.md` | 2 | 2 | heading + closing line |
| `lib/features/home/widgets/confirmed_gig_card.dart` | 3 | 1 | 2-line title clamp + 1-char maxWidth |
| **Total** | **~89** | **~42** | matches the stat baseline |

**Expected new files:** 0.
**Expected new public classes/methods:** 0.
**Expected new dependencies:** 0.
**Expected migrations/RPCs:** 0.

QA measures the actual diff against these numbers. Deviations larger than ~5
lines per file, in either direction, are a signal that scope has drifted.

---

## System Impact Map

| System | Affected? | Notes |
|---|---|---|
| Gigs | Affected (visual only) | `ConfirmedGigCard` max-size grows 300→400 px and title ellipsizes at one line. No data, state, or navigation change. |
| Rehearsals | Unaffected | — |
| Setlists | Unaffected | — |
| Members | Unaffected | — |
| Auth | Unaffected | The doc reference to `login_screen.dart` / `app_shell.dart` is historical only; no code in the auth flow is touched. |
| Routing | Unaffected | — |
| Notifications | Unaffected | — |
| Init order (`main.dart` sequence) | Unaffected | — |
| Supabase (RLS, RPC, migrations, edge functions) | Unaffected | — |
| Config (`--dart-define`, entitlements) | Unaffected | — |
| Platforms (iOS / Android / macOS / Web) | All affected identically | `ConfirmedGigCard` is platform-agnostic Flutter; the visual tweak applies everywhere the card renders. No platform-conditional code touched. |
| Agent pipeline (Architect / Engineer / QA / Manager) | Affected (docs only) | The Manager and Copilot instruction docs change future agent behavior. No runtime code impact. |
| App Store screenshot pipeline | Affected (mockup only) | Two `BandRoadie/src/app_store_screenshots/*` mockup files lose a decorative emoji. Not shipped in any Flutter build. |

---

## Regression Risk

**LOW.**

- Nine of the eleven files are pure Markdown or standalone JS/HTML mockup
  assets. None can regress runtime app behavior.
- `.github/agents/manager.agent.md` changes future manager-agent behavior
  but does not affect the running app; the worst case is that a future
  automated merge misinterprets the 6b/6c gate, which is a process bug
  fixable by editing the same file.
- `lib/features/home/widgets/confirmed_gig_card.dart` is a two-hunk
  Container/Text tweak in a single stateful widget with no state, provider,
  or navigation dependency. Widening `maxWidth` from 300 → 400 in a widget
  used inside a horizontally-scrolling Row cannot overflow anything —
  horizontal scroll adjusts automatically. Adding `maxLines: 1` +
  `TextOverflow.ellipsis` to the title matches every other row's existing
  overflow behavior in the same widget.
- No auth, session, routing, init-order, RLS, RPC, migration, or edge
  function is touched.
- No new dependencies. No new public classes or methods.

---

## Engineer Task Breakdown

Because the code changes are already in the working tree, Engineer's job
here is verification, not authoring. Do these tasks in order.

1. **Land the plan and this branch first.** Confirm the working tree is on
   `feature/post-demo-docs-tooling-and-card-layout` (branched from
   `origin/main`), and `git status --short` shows exactly the 11 modified
   files listed in "Files to Modify" — no more, no less. If there are
   extra files listed, stop and report; do not `git add .`, do not
   `restore`, do not blanket-revert.
2. **Confirm every file's diff is intentional.** For each of the 11 files,
   spot-check `git --no-pager diff -- <file>` against the "Files to Modify"
   description. Any hunk not described there is scope drift and must be
   raised before proceeding.
3. **Run `flutter analyze`.** Expect zero *new* errors, warnings, or lint
   issues attributable to the two-hunk edit in
   `confirmed_gig_card.dart`. Pre-existing analyzer output on files this
   plan doesn't touch is not a blocker (record it in
   `ENGINEER_REPORT.md` for QA context but don't fix it here — that would
   be scope drift).
4. **Verify at least one existing test suite still passes.** Run
   `flutter test` and confirm no regression. This plan does not require
   authoring new tests (see Verification Plan §Tier 1 for the reason).
5. **Do not `dart format` doc-only files.** Only allow auto-formatting on
   `confirmed_gig_card.dart` and only if analyzer flags formatting on the
   changed hunk. Every other file in this branch is Markdown / JS / HTML
   and must not be reformatted.
6. **Write `ENGINEER_REPORT.md`.** Under "Files Modified" list exactly the
   11 files (matching this plan). Under "Ready For QA" answer Yes if
   analyzer and tests are clean, otherwise No with a stated reason. Do not
   open a PR — that is the Manager's Step 6a.

---

## Verification Plan

### Tier 1 — Pre-deploy (Engineer + QA)

1. **Diff shape.** `GIT_OPTIONAL_LOCKS=0 git diff --stat origin/main..HEAD`
   must list exactly 11 files and total roughly the numbers in the Change
   Budget table. QA fails the run if either the file list or the totals
   drift materially (more than ~5 lines per file, or any extra/missing
   file). Rationale: this is the highest-signal check that scope was
   preserved.
2. **Analyzer.** `flutter analyze` produces no new findings attributable
   to the `confirmed_gig_card.dart` edit.
3. **Existing tests.** `flutter test` runs. The single pre-existing
   failure in `test/features/auth/login_screen_demo_button_test.dart`
   at line 53 (`expect(find.text('Check Out the Demo Band'), findsOneWidget)`)
   is a **known limitation** and does not block approval — it is
   identical to the `origin/main` baseline at commit `5cd19969` (this
   branch's merge-base), was reproduced from a disposable side-checkout
   in Engineer's Cycle 4 report, and lives in `test/**` which is
   off-limits under this scope. No **other** test may newly fail; any
   additional failure is a regression and blocks approval.
4. **Visual smoke on `ConfirmedGigCard` (manual, Engineer only).** In a
   local run, verify the confirmed gig card:
   - Renders at up to 400 px wide instead of clipping/wrapping at 300 px.
   - Location, date, and time rows are visually unchanged; Location and
     Date continue to ellipsize on their existing single-line clamp, and
     the time row renders on its existing single-line layout.
   - **Title behavior is confirmed by code inspection** of
     `lib/features/home/widgets/confirmed_gig_card.dart` — the title
     `Text(widget.gig.name, …)` carries `maxLines: 1` and
     `overflow: TextOverflow.ellipsis`, identical to the same-widget
     Location and Date rows whose runtime ellipsis rendering is
     observable in the same Chrome layout smoke.

   **Long-title runtime fixture — unavailable within this scope.** The
   seeded demo band contains no confirmed gig whose title is long enough
   to visibly trigger the new ellipsis at 400 px. Producing one would
   require editing the demo seed under `lib/**/*.dart` (off-limits),
   authoring a widget or golden test under `test/**` (off-limits), or
   mutating a confirmed-gig row in Supabase (off-limits). Because
   `maxLines: 1` + `TextOverflow.ellipsis` is a Flutter-framework
   primitive with well-defined semantics and the Location and Date
   sibling rows already exercise the identical pattern in the same
   widget with observable runtime behavior in the Chrome layout smoke,
   **code-inspection of the title hunk plus the successful Chrome layout
   smoke is accepted as sufficient runtime evidence** for this two-line
   visual tweak. No new golden or widget test is required — Testing
   Conventions in `copilot-instructions.md` state "coverage is minimal"
   and adding one here would exceed scope. QA confirms on Chrome (the
   fastest platform).
5. **Markdownlint spot-check (QA).** For each of the six `docs/**` files
   and the two `.github/**` files, confirm the diff is limited to
   heading blank-line hygiene, code-fence spacing, brand-voice bullet
   changes, and the 6a/6b/6c restructure described above. Any hunk
   touching a semantic instruction *not* listed here is scope drift.
6. **SVG mockup (QA).** For `generate_slides.js` and `preview.html`, the
   only removed content is exactly one `<text>` element containing the 🎸
   emoji. QA opens the two files and reads the surrounding SVG structure
   to confirm no adjacent element was accidentally deleted.

### Tier 2 — Post-deploy
n/a. No backend, RPC, or migration is deployed. The manager-agent doc
change takes effect on the next agent run; observing that in production is
QA's own regression area, not this plan's Tier-2 responsibility.

### Idempotency / submission flow
n/a. No submission or ordering flow is introduced or modified.

### RLS / `SECURITY DEFINER`
n/a. No RPCs, no policies, no `SECURITY DEFINER` functions.

---

## QA Regression Areas

- **Confirmed gig card rendering on the Home screen.** Both call sites
  (`home_screen.dart` `_buildHorizontalGigsList`, `home_tab_content.dart`
  around line 1205) render the widget inside a horizontally scrollable
  `Row`. Confirm no horizontal-overflow warning appears in debug console
  and the row still scrolls smoothly.
- **Manager-agent pipeline dry-read.** QA reads `.github/agents/manager.agent.md`
  end-to-end after the edit and confirms Step 6a/6b/6c are internally
  consistent (no dangling reference to the old single-Step-6 flow, no
  contradictory "merge immediately after PR open" text elsewhere in the
  file).
- **Copilot instructions readability.** QA renders `.github/copilot-instructions.md`
  in a markdown preview and confirms the blank-line hygiene doesn't break
  section grouping. Confirm the brand-voice section no longer instructs
  the use of the 🎸 emoji.
- **Regression search — remaining 🎸 in shipped code.** QA runs a
  workspace-wide search for `🎸` inside `lib/**/*.dart` and confirms **no
  new** occurrences are introduced by this branch. Pre-existing
  occurrences (if any survive from before) are not this plan's problem to
  fix — that would be scope drift — but QA should record their count in
  the report as context for a future sweep.

---

## Rollout Strategy

Standard PR flow — no phased rollout, no feature flag, no schema migration
gate. Because the app-code change is a two-line visual tweak inside a
single widget and everything else is documentation or a screenshot mockup,
the merge is safe to ship as one squash-merged PR. Once merged, no
follow-up deploy step is required beyond the normal CI build.

If the `ConfirmedGigCard` visual change produces an unexpected result in
production, the fix is a two-line revert of that file — no data migration
or state rollback needed.

---

## Out of Scope

- **Any code change to remove existing 🎸 emoji occurrences from
  `lib/**/*.dart`.** The `PROJECT_CONTEXT.md` diff mentions that the demo
  login / demo exit strings *have been* de-emojified as of 2026-09-05, but
  this branch does not touch those files — that work is either already
  landed or belongs in a separate sweep.
- **Any refactor of `ConfirmedGigCard` beyond the two-hunk constraint /
  overflow change.** The card has other opportunities (the animated
  gradient border comment vs current border, the hard-coded green tint
  colors), and none of them are approved here.
- **Any addition of widget tests, golden tests, or unit tests.** Testing
  Conventions in `copilot-instructions.md` explicitly permit skipping new
  coverage for cosmetic UI changes, and none of the doc changes is
  testable.
- **Fast-forwarding local `main`** as an end-goal. Local `main` will be
  fast-forwarded as a side effect of creating this branch cleanly from
  `origin/main`, but no other local-branch cleanup is authorized.
- **Deleting the old `feature/interactive-demo-band-experience` branch.**
  It remains in place after this move so nothing is lost. Its cleanup, if
  desired, is a separate manual action Tony can take at will and is not
  Engineer's or QA's responsibility.
- **Any additional Manager or Architect agent policy edits.** Only the one
  6a/6b/6c change described above is in scope for `manager.agent.md`.
