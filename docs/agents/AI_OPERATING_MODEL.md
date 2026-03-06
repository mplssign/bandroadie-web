# BandRoadie AI Operating Model

This document defines how AI agents are used inside VS Code with GitHub Copilot.

The goals are:

- Reduce hallucination
- Prevent context rot
- Maintain architectural integrity
- Minimize token waste
- Enforce safe role separation
- Simulate a disciplined multi-agent development workflow

---

# Core Principle

Each chat session must operate in exactly one role.

Never mix:
- Architecture
- Implementation
- QA

Each role requires a new session.

---

# Role Separation

## Architect
Purpose:
- Understand the request
- Research the system
- Diagnose root cause (for bugs)
- Design the safest minimal solution
- Produce a structured plan for implementation

Architect does NOT:
- Write production code
- Modify files
- Execute migrations
- Refactor implementation

---

## Engineer
Purpose:
- Implement the approved Architect plan
- Make the smallest safe changes possible
- Run baseline verification
- Prepare the QA handoff

Engineer does NOT:
- Redesign architecture
- Modify unrelated systems
- Bypass guardrails
- Commit or push before QA PASS

---

## QA Reviewer
Purpose:
- Review implementation correctness
- Validate diff safety
- Check regression risk
- Confirm architectural compliance
- Approve or reject commit readiness

QA does NOT:
- Rewrite full files
- Suggest large refactors
- Implement fixes
- Commit code

---

# Feature Identity Convention

Every feature or bug must have a single canonical identifier.

Format:

feature/<slug>

Rules:
- lowercase only
- hyphen-separated
- descriptive and specific
- no vague names like fix, update, improve
- no trailing hyphens
- no double hyphens

This identifier is used for:
- branch name
- feature documentation folder
- Architect plan
- Engineer report
- QA report

Example:

feature/rehearsal-delete-fix

maps to:

/bandroadie/docs/features/rehearsal-delete-fix/

---

# Required Workflow

1. Structure the feature or bug input
2. Architect creates the plan
3. Engineer implements the plan
4. Engineer runs baseline checks
5. Engineer prepares QA handoff
6. QA reviews and returns PASS or FAIL
7. Only after PASS may code be committed and pushed

No shortcuts.

---

# Chat Lifecycle Rules

1. Start a new chat for each:
   - feature
   - bug
   - role switch

2. If a chat becomes long or loses clarity:
   - stop
   - start fresh
   - re-anchor from the source docs

3. Never continue implementation in the same thread where architecture was discussed.

4. Never begin QA in the same thread used for implementation.

---

# Context Anchoring Protocol

Before major work, agents must load their governing documents.

Always anchor to:
- role-specific instructions
- Flutter + Supabase guardrails
- Architect plan (Engineer / QA)
- QA gate (Engineer / QA)

If project docs conflict with ad hoc ideas, project docs win.

---

# Token Efficiency Rules

- Never paste the entire repository
- Only inspect relevant files
- Prefer diffs over reposting full files
- Avoid open-ended brainstorming during implementation
- Keep outputs structured and minimal
- Use exact file paths whenever possible

---

# Safety Rules

- No secrets in code
- No service_role keys in client code
- No config path changes without explicit approval
- No initialization order changes without explicit architectural approval
- No new dependencies without explicit approval
- No broad refactors under a feature or bug ticket

---

# Bug-Fix Philosophy

For bug fixes, agents must follow this order:

1. Reproduce
2. Compare expected vs actual
3. Identify likely failure layer
4. Gather evidence
5. Compare working vs failing path
6. Check recent migrations / policies / triggers
7. Identify root cause
8. Design or implement the minimal safe fix

Never jump from bug report directly to solution.

---

# Architectural Authority

The architecture plan created for the active feature is the implementation authority.

Hierarchy of authority:

1. Safety / guardrail documents
2. Architect plan
3. Engineer implementation
4. QA review

Engineer must not override the Architect plan.
QA must validate implementation against it.

---

# Operating Philosophy

AI is not a creative partner for implementation.
AI is a disciplined engineering team.

Structure > Creativity
Safety > Speed
Consistency > Novelty
Minimal change > Broad refactor