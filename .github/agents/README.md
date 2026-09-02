# BandRoadie Copilot agents

Four VS Code Copilot custom agents implementing BandRoadie's Architect →
Engineer → QA pipeline (orchestrated by Manager) as native Copilot
subagents — no manual copy/paste between chats.

## Use

Open Copilot Chat, pick **manager** from the agent dropdown (or `/agents`),
and describe a feature or bug. Manager runs the whole thing end to end with
no clicks and almost no chat prompts: confirms it's actually on `main`
before touching anything (if it isn't, it stops and asks — see below), syncs
`main`, resolves a dirty tree itself via a rescue branch (never by asking,
never by discarding), delegates to `architect`/`engineer`/`qa`, gates each
stage itself, resolves blockers and QA fix-loops itself, and on approval
commits, pushes, opens the PR, and **merges it** — the merge decision is the
manager's to make, not something it asks Tony about. It interrupts him for
three things, all rare: an ambiguous initial description, a genuine
product/UX call with no technically-correct answer, and finding the
workspace on a branch other than `main` when a run starts (usually a prior
feature genuinely paused with real work on it — only Tony knows whether to
resume, merge, or abandon it, so Manager won't guess).

There is no VS Code confirmation-dialog backstop on any of this anymore —
see "Safety backstop" below for exactly what `.vscode/settings.json` does
and doesn't cover, including a gap that isn't specific to Manager. Merging
doesn't deploy anything by itself — BandRoadie's deploy step is separate and
still manual.

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

Sonnet 4.6 showed a warning icon in the model picker when this was set up —
worth checking what VS Code's tooltip says on it (usually a deprecation or
temporary-availability notice) before relying on it long-term. If it's been
pulled, `GPT-5.4` (6x) is a reasonable same-tier fallback for engineer/qa/
manager.

## Safety backstop

`.vscode/settings.json`'s `chat.tools.terminal.autoApprove` auto-approves
the specific git add/commit/pull/checkout/push and `gh pr create`/`gh pr
merge` commands this pipeline actually runs — there is no VS Code
confirmation-dialog backstop left for those. As of 2026-09-02 the patterns
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

Separately, a gap with no fix available: `architect` and `qa`'s Copilot tool
grants (`edit`, `execute`) are broader than their prompts actually use — both
are instructed to be read-only/report-only (Architect writes only
`ARCHITECT_PLAN.md`; QA writes only `QA_REPORT.md` and runs only
read-only/analyzer commands), but VS Code's `.agent.md` frontmatter can't
scope `edit` down to one file or `execute` down to specific commands. The
prompt-level Hard rules in each file are the only thing enforcing this —
there's no platform-level backstop for it, the way `.vscode/settings.json`
at least partially backstops git commands.
