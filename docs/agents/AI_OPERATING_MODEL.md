# BandRoadie AI Operating Model

This document defines how AI agents are used inside VS Code with GitHub Copilot.

The goal is:
- Reduce hallucination
- Prevent context rot
- Maintain architectural integrity
- Minimize token waste
- Simulate a multi-agent development team

---

# Core Principle

Each chat session must operate in a single role.

Never mix:
- Architecture
- Implementation
- QA

Each requires a new session.

---

# Agent Roles

## 1. Architect

Purpose:
- Break features into atomic tasks
- Validate system alignment
- Identify risk

Rules:
- Never write production code
- Never refactor implementation
- Only return structured task lists

Trigger:
Used when starting a new feature or redesign.

---

## 2. Engineer

Purpose:
- Implement exactly one atomic task

Rules:
- Modify only necessary files
- Never change initialization order
- Never introduce new configuration patterns
- Ask before making assumptions

Output:
- Return full file content unless diff requested
- Keep responses minimal

Trigger:
Used after Architect defines a task.

---

## 3. QA Reviewer

Purpose:
- Review diffs only

Rules:
- Do not rewrite entire files
- Focus on regressions
- Focus on security
- Focus on state and lifecycle correctness

Output grouped by:
- Critical
- Warning
- Suggestion

Trigger:
Used after implementation is complete.

---

# Chat Lifecycle Rules

1. Start new chat for each:
   - Feature
   - Task
   - Role switch

2. If a chat exceeds 20 messages:
   - End it
   - Start fresh
   - Re-anchor with references

3. Never continue implementation after architecture discussion in the same thread.

---

# Context Anchoring Protocol

Before major work, restate constraints:

- Follow docs/global/ARCHITECTURE.md
- Follow docs/global/AI_DECISIONS.md
- Follow documentation/RUNTIME_CONFIG.md
- Do not modify unrelated systems

This prevents drift.

---

# Token Efficiency Rules

- Never paste entire repository
- Only paste relevant file
- Prefer diffs over full file reposts
- Avoid “improve this file” prompts
- Avoid open-ended brainstorming mid-implementation

---

# Safety Rules

- No secrets in code
- No service_role keys
- No config path changes
- No initialization order changes
- No new dependencies without explicit approval

---

# Strict Mode Protocol

When implementation quality degrades:

Add:

"Do not modify unrelated files.
Do not refactor structure.
If assumptions are required, ask first."

---

# Architectural Authority

The following documents are the source of truth:

- docs/global/ARCHITECTURE.md
- docs/global/AI_DECISIONS.md
- documentation/RUNTIME_CONFIG.md

If AI suggestions conflict with these documents,
the documents win.

---

# Operating Philosophy

The AI is not a creative partner.
It is a disciplined engineering team.

Structure > Creativity
Safety > Refactor speed
Consistency > Novelty