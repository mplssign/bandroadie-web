# Commit Gate (QA Required Before Push)

This project uses a QA gate. No code is pushed until QA passes.

---

## Required Flow

1) Architect produces a plan
2) Engineer implements the plan in the workspace
3) Engineer runs baseline checks
4) QA reviews git diff and either PASS or FAIL
5) Only after PASS, changes may be committed and pushed

---

## Baseline Checks (Engineer Must Run)

Required (always):
- flutter analyze

Recommended (when relevant):
- flutter test
- platform run checks (as applicable)

Engineer must record results in the handoff.

---

## QA Review Inputs (Required)

QA must be given:
- Original goal (1–3 sentences)
- Architect plan summary (or link to it)
- Engineer summary + files changed
- git diff output

QA must return:
- PASS or FAIL
- Critical Issues (must fix)
- Warnings (should fix)
- Suggestions (optional)

---

## Commit Rules (Only After QA PASS)

1) Confirm working tree status
2) Commit with clear message
3) Push branch

Commands:

- git status
- git add .
- git commit -m "feat: <short description>"   # or fix:, chore:
- git push

---

## If QA FAILS

- Engineer fixes only the items QA marks as Critical
- Re-run baseline checks
- Provide updated git diff
- QA re-reviews until PASS

---

## Non-Negotiables

- No push without QA PASS
- No broad refactors under a feature/bug ticket
- No initialization order changes without an explicit architecture decision recorded in docs/global/AI_DECISIONS.md
- No new config paths without updating documentation/RUNTIME_CONFIG.md

