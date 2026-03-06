# Commit Gate (QA Required Before Push)

This project uses a QA gate.

No code is committed or pushed until QA passes.

---

## Required Flow

1. Architect produces a plan
2. Engineer implements the plan in the workspace
3. Engineer runs baseline checks
4. Engineer prepares QA handoff and report
5. QA reviews the plan, handoff, and git diff
6. QA returns APPROVED or REQUIRES CHANGES
7. Only after APPROVED may changes be committed and pushed

---

## Baseline Checks (Engineer Must Run)

Required:
- flutter analyze

When relevant:
- flutter test
- manual verification of the affected flow on at least one target platform

Engineer must record results in the handoff and ENGINEER_REPORT.md.

---

## QA Inputs (Required)

QA must be given:

- active feature slug
- Architect plan
- Engineer report / handoff
- files changed
- git diff output
- verification results

---

## QA Output (Required)

QA must return:

- APPROVED or REQUIRES CHANGES
- Regression Risk Level: LOW / MEDIUM / HIGH
- Critical Issues (must fix before commit)
- Warnings (should fix)
- Suggestions (optional)

---

## Commit Rules (Only After QA APPROVED)

1. Confirm working tree status
2. Commit with clear message
3. Push branch

Commands:

- git status
- git add .
- git commit -m "feat: <short description>"   # or fix:, chore:
- git push

---

## If QA REQUIRES CHANGES

- Engineer fixes only the Critical Issues first
- Re-run baseline checks
- Update ENGINEER_REPORT.md if needed
- Provide updated git diff
- QA re-reviews until APPROVED

---

## Non-Negotiables

- No commit or push without QA approval
- No broad refactors under a feature or bug ticket
- No initialization order changes without explicit architecture approval
- No new config paths without explicit documentation and approval
- No hidden scope expansion after Architect sign-off