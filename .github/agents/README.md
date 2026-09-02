# BandRoadie Copilot agents

Four VS Code Copilot custom agents implementing BandRoadie's Architect →
Engineer → QA pipeline (orchestrated by Manager) as native Copilot
subagents — no manual copy/paste between chats.

## Use

Open Copilot Chat, pick **manager** from the agent dropdown (or `/agents`),
and describe a feature or bug. Manager runs the whole thing end to end with
no clicks and almost no chat prompts: confirms it's actually on `main`
before touching anything (if it isn't, it stops and asks — see below), syncs
`main` (`git fetch` + `git pull --ff-only`, never a merge commit), resolves a
dirty tree itself via a rescue branch (never by asking, never by
discarding), delegates to `architect`/`engineer`/`qa` — verifying at the
Architecture Gate that the feature branch's actual merge-base is current
`main`, not just that a branch with the right name exists, a check this
pipeline's history says is easy to skip and expensive to skip — gates each
stage itself, resolves blockers and QA fix-loops itself, and on approval
commits, pushes, writes the PR description to a file and opens the PR from
it (`gh pr create --body-file`, never an inline `--body "..."`), and
**merges it** — the merge decision is the manager's to make, not something it
asks Tony about. It interrupts him for three things, all rare: an ambiguous
initial description, a genuine product/UX call with no technically-correct
answer, and finding the workspace on a branch other than `main` when a run
starts (usually a prior feature genuinely paused with real work on it — only
Tony knows whether to resume, merge, or abandon it, so Manager won't guess).
Only one Manager session should ever run against this repo at a time — this
is now backed by a real check, not just an instruction: every session (a
Manager run, or `architect`/`engineer`/`qa` invoked standalone) claims
`pipeline.lock` at the repo root before doing anything else and releases it
when it's done. A session that finds the lock already held stops and reports
it rather than guessing whether it's safe to proceed — see manager.agent.md's
Preflight for exactly how.

There is no VS Code confirmation-dialog backstop on any of this anymore —
see "Safety backstop" below for exactly what `.vscode/settings.json` does
and doesn't cover, including a gap that isn't specific to Manager. Merging
doesn't deploy anything by itself. Manager never touches the database in any
way, including applying migrations a merged PR added — QA verifies on an
ephemeral branch that a new migration actually applies cleanly (see
qa.agent.md), but running it against the live database is Tony's own manual
action, on his own schedule, same as building and deploying the
Flutter app itself — stays entirely separate, manual, and Tony's call alone;
Manager is explicitly told never to run, recommend, or comment on it.

`architect`, `engineer`, and `qa` are also individually invocable if you
want to run one stage by hand, but normally you only ever talk to
`manager`.

## Files

Each `*.agent.md` here is **self-contained** — the full operative rules for
that role are written directly in its body. Copilot loads a `.agent.md`
body automatically as the agent's instructions, with no runtime "go read
another file" step, so nothing here depends on a subagent actually
deciding to fetch anything else.

These four files are the **only** definition of this pipeline going
forward. The original spec in `docs/agents/*.md` (ARCHITECT.md, ENGINEER.md,
QA.md, MANAGER_AGENT.md, GUARDRAILS.md, OPERATING_MODEL.md, COMMIT_GATE.md)
was the source material distilled into these files — it is superseded, not
a parallel copy to keep in sync. If the pipeline's behavior needs to
change, change it here; `docs/agents/` is retired.

## Model choices

Pinned against the models in Tony's Copilot picker as of 2026-09-01
(multiplier = premium-request cost):

| Agent | Model | Why |
|---|---|---|
| architect | Claude Opus 4.7 (27x) | Usually once per feature — can be re-invoked for a fresh diagnosis if the same Issue Category survives 2 QA fix-loop cycles (manager.agent.md step 5). A wrong root-cause diagnosis invalidates everything downstream, so this is the one call worth paying up for even on a re-run. |
| engineer | Claude Sonnet 4.6 (9x) | Can run multiple times per feature — initial pass plus QA fix-loops, up to roughly 6 cycles total (across engineer/QA and any architect re-diagnosis) before Manager makes a defensible call instead of continuing indefinitely — strong at code, 3x cheaper than Opus, keeps repeated runs affordable. |
| qa | Claude Sonnet 4.6 (9x) | Also runs multiple times per feature; verification is checklist-driven against `ARCHITECT_PLAN.md`, so precise instruction-following matters more than frontier reasoning here. |
| manager | Claude Sonnet 4.6 (9x) | Active for the whole session — parsing, dispatching, gate review, commit sequence — cheap-per-call matters most here. |

If Sonnet 4.6 becomes unavailable, `GPT-5.4` (6x) is a reasonable same-tier
fallback for engineer/qa/manager.

## Safety backstop

`.vscode/settings.json`'s `chat.tools.terminal.autoApprove` auto-approves
the specific git add/commit/pull/checkout/push and `gh pr create`/`gh pr
merge` commands this pipeline actually runs — there is no VS Code
confirmation-dialog backstop left for those. `supabase db push` is never in
this list and never will be — Manager doesn't run it, doesn't have a step
for it, and applying migrations to the live database stays Tony's manual
action end to end. As of 2026-09-02 the patterns
are deliberately narrow (literal branch names only, no `--force`, no
pushing/merging `main`, no bare `git add .`/`-A` alongside real paths, no
`gh pr merge --admin`) rather than a bare `git push\b.*`-style wildcard,
because **this setting is not scoped per agent** — VS Code has no way to
approve a command only when `manager` runs it, so a matching pattern is
approved for `architect`/`engineer`/`qa` exactly as readily as for
`manager`, even though only `manager` is ever instructed to run these. The
content-level narrowing is the actual technical backstop for that gap;
`qa.agent.md`/`engineer.agent.md`'s own git-write prohibitions (itemized —
`checkout`/`merge`/`rebase`/`reset`/`clean` named explicitly, not just
"commit/push/gh") are the prompt-level one, since neither agent is ever
supposed to touch git beyond read-only `status`/`diff`/`branch`. The only
things standing between a feature request and a merged PR are those two
layers plus `manager.agent.md`'s own gates.

Separately, a gap with no fix available, and it's not just `architect`/`qa`:
every one of the four agents' Copilot tool grants is broader than its prompt
actually uses, because VS Code's `.agent.md` frontmatter can't scope `edit`
to one file or `execute` to specific commands. `architect` and `qa` hold
`edit`+`execute` but are meant to be read-only/report-only (Architect writes
only `ARCHITECT_PLAN.md`; QA writes only `QA_REPORT.md`). `engineer` holds
the same pair and does need both, but nothing stops it from touching a file
outside the plan's list beyond its own prompt saying not to. `manager` has
no `edit` tool at all — but it holds `execute`, which is unrestricted shell
access and can reproduce everything `edit` would do (`sed -i`, a heredoc
into a file, `cp`) just as completely; the missing `edit` grant is not real
enforcement, only the absence of the most obvious path. For all four agents,
the prompt-level Hard rules are the only thing actually enforcing scope —
there's no platform-level backstop for any of it, the way
`.vscode/settings.json` at least partially backstops git commands.
