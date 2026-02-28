# Handoff Template (Agent → Agent)

Use this template every time work moves from one stage to the next.

---

## 1) Goal

- What are we trying to accomplish?

---

## 2) Current State

- What is the current behavior?
- Where in the app is it happening (screen / flow)?
- Repro steps (for bugs), including platform(s)

---

## 3) Constraints (Non-negotiables)

- Follow docs/global/ARCHITECTURE.md
- Follow docs/global/AI_DECISIONS.md
- Follow documentation/RUNTIME_CONFIG.md
- Minimal changes only
- No initialization order changes
- No new config loading paths

---

## 4) Proposed Solution (Architect → Engineer)

- Summary of approach
- Exact files to modify (paths)
- What NOT to touch
- Edge cases / risks

---

## 5) Implementation Notes (Engineer → QA)

- What was implemented (short summary)
- Files changed (paths)
- Any assumptions made
- Any TODOs left intentionally (should be rare)

---

## 6) Verification Plan / Evidence

Commands run:
- (paste command list)

Results:
- (brief results: pass/fail + key output)

Manual checks:
- (what to click/verify in app)

---

## 7) QA Focus Areas

- What QA should pay extra attention to
- Known risky areas (auth/session, routing, init order, config, platform differences)

