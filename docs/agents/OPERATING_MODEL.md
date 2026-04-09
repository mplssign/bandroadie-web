# BandRoadie — AI Development Operating Model

## Overview

BandRoadie uses a four-role structured AI pipeline for all development work:

```
Tony's Request
      ↓
  MANAGER ← orchestrates, gates, and coordinates all agents
      ↓
ARCHITECT → produces ARCHITECT_PLAN.md
      ↓
ENGINEER  → produces ENGINEER_REPORT.md + git diff
      ↓
    QA    → produces QA_REPORT.md + APPROVED or REQUIRES CHANGES
      ↓
  COMMIT  → only after QA APPROVED
```

---

## Roles

| Role | Purpose | Output |
|------|---------|--------|
| **Manager** | Orchestrates the pipeline, enforces gates, handles blockers, coordinates with Tony | Structured coordination, gate decisions |
| **Architect** | Diagnoses and designs the safest minimal solution | `ARCHITECT_PLAN.md` |
| **Engineer** | Implements exactly what the Architect plan specifies | Modified files + `ENGINEER_REPORT.md` |
| **QA** | Validates implementation against the Architect plan | `QA_REPORT.md` + verdict |

---

## Pipeline Gates

Each gate must pass before the pipeline advances. The Manager enforces all gates.

**Gate 1 — Input Gate**
- Feature input is complete and unambiguous
- Slug is valid
- Tony has confirmed the description

**Gate 2 — Architecture Gate**
- `ARCHITECT_PLAN.md` exists and is complete
- Root cause is confirmed (not hypothesized)
- Files to modify are explicitly listed
- Tony or Manager has reviewed the plan

**Gate 3 — Implementation Gate**
- `ENGINEER_REPORT.md` exists
- `flutter analyze` passes with 0 errors
- `git diff` has been generated
- All Architect tasks are reported as complete

**Gate 4 — Release Gate**
- QA verdict is **APPROVED**
- No critical issues exist
- Manager confirms commit is authorized

---

## Core Principles

**One role per session.** Never mix Architect, Engineer, and QA work in a single session. Each role operates from its own context.

**Server is authoritative.** Ordering, permissions, and data integrity live in Supabase. The Flutter client never overrides the server.

**Minimal diff surface.** Every change must be the smallest safe implementation. No opportunistic cleanup. No speculative refactors.

**No push without QA PASS.** The commit gate is non-negotiable.

---

## Document Paths

All feature documentation lives under:

```
<PROJECT_ROOT>/docs/features/<slug>/
├── ARCHITECT_PLAN.md
├── ENGINEER_REPORT.md
└── QA_REPORT.md
```

Agent reference docs live under:

```
<PROJECT_ROOT>/docs/agents/
├── OPERATING_MODEL.md
├── MANAGER_AGENT.md
├── ARCHITECT.md
├── ENGINEER.md
├── QA.md
└── GUARDRAILS.md
```

---

## Parallelization Policy

The Manager may authorize parallel Engineer execution **only** when all of the following are true:

- The Architect plan explicitly identifies tasks as independent
- The tasks touch different files with no shared state
- Each parallel task has its own defined scope

When in doubt, run sequentially.

---

## Escalation Protocol

When any agent is blocked, the Manager escalates to Tony immediately with:

1. Which agent is blocked
2. What is missing or ambiguous
3. What Tony needs to decide or provide
4. Whether the pipeline can continue in parallel while waiting

Tony resolves blockers. Agents wait.

---

## Safety Non-Negotiables

These rules cannot be overridden by any agent or any feature request:

- No secrets in code
- No service_role keys in client code
- No initialization order changes without explicit Architect decision recorded in `docs/reference/general/AI_DECISIONS.md`
- No new config loading paths without updating `docs/reference/general/RUNTIME_CONFIG.md`
- No Supabase RPC signature changes without migration
- No RLS self-referencing policies (causes infinite recursion)
- No async `setState` without `mounted` guard
- No controller or FocusNode leaks

---

## Deployment Protocol (Production Only)

After QA APPROVED and commit is pushed:

```bash
flutter clean
flutter build web --release
vercel deploy build/web --prod --yes
```

Post-deploy verification:
- Incognito load
- PWA install
- Auth flow (magic link)
- Setlist reorder
- Bulk entry
- RPC integrity check

---

*Structure > Creativity. Safety > Speed. Stability wins.*
