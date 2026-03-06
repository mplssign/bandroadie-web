# Handoff Template (Agent → Agent)

Use this template every time work moves from one stage to the next.

---

## 1) Feature Identity

- Feature Slug:
- Feature Title:
- Branch Name:
- Docs Folder:

---

## 2) Goal

- What are we trying to accomplish?

---

## 3) Current State

- What is the current behavior?
- Where in the app is it happening (screen / flow)?
- Reproduction steps (for bugs), including platform(s)

---

## 4) Constraints (Non-Negotiables)

- Follow the Architect plan
- Follow documentation/RUNTIME_CONFIG.md
- Minimal changes only
- No initialization order changes
- No new config loading paths
- No unrelated refactors
- Preserve platform-specific behavior

---

## 5) Proposed Solution (Architect → Engineer)

- Summary of approach
- Exact files to modify (paths)
- Exact files to create (paths)
- What NOT to touch
- Edge cases / risks
- System impact areas to watch

---

## 6) Implementation Notes (Engineer → QA)

- What was implemented (short summary)
- Files changed (paths)
- Files created (paths)
- Migrations changed or added
- Any assumptions made
- Any TODOs left intentionally (should be rare)

---

## 7) Verification Plan / Evidence

Commands run:
- flutter analyze
- flutter test (if run)
- other relevant commands

Results:
- pass/fail + important output summary

Manual checks:
- exact clicks / flows QA should verify

---

## 8) QA Focus Areas

- What QA should pay extra attention to
- Known risky areas
- Security / RLS review points
- Regression-sensitive systems

---

## 9) Diff Reference

- git diff included: yes / no
- Any especially important diff sections to inspect