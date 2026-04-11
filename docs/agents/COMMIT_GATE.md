# Commit Gate — BandRoadie

The commit gate is the final checkpoint before code enters the repository. It is non-negotiable. No commit is authorized until every condition below is met.

---

## Gate Conditions

All of the following must be true before the Manager authorizes a commit:

- [ ] `QA_REPORT.md` exists at `docs/features/<slug>/QA_REPORT.md`
- [ ] QA verdict is **APPROVED** — not REQUIRES CHANGES, not partial
- [ ] `ENGINEER_REPORT.md` exists and reports **Ready For QA: Yes**
- [ ] `flutter analyze` passes with 0 errors (confirmed in Engineer report)
- [ ] No critical issues remain open in the QA report
- [ ] No secrets, API keys, or credentials appear in `git diff`
- [ ] No debug artifacts (print statements, temporary flags, TODO hacks) in `git diff`
- [ ] All changes are on the correct feature branch (`feature/<slug>` or `bug/<slug>`)
- [ ] Working tree is clean except for expected feature changes and report files

---

## Authorized Commit Sequence

The Manager executes this sequence exactly. Do not deviate.

```bash
# 1. Confirm branch
git branch --show-current

# 2. Confirm diff surface (review before staging)
git diff

# 3. Stage only the files listed in the Architect plan
git add <file1> <file2> ...

# 4. Stage the feature docs
git add docs/features/<slug>/ARCHITECT_PLAN.md
git add docs/features/<slug>/ENGINEER_REPORT.md
git add docs/features/<slug>/QA_REPORT.md

# 5. Commit
git commit -m "<type>(<scope>): <short description>"

# 6. Push
git push origin <feature-identifier>
```

**Commit message format:** `type(scope): short description`

| Type | When to use |
|------|-------------|
| `feat` | New feature or capability |
| `fix` | Bug fix |
| `chore` | Build, config, or tooling change |
| `refactor` | Code restructure with no behavior change |
| `test` | Test additions or changes |
| `docs` | Documentation only |

---

## Hard Prohibitions

- Never use `git add .` or `git add -A` — stage files explicitly
- Never commit directly to `main`
- Never use `--no-verify` to bypass hooks
- Never force-push (`--force`) to any branch
- Never commit if any gate condition is unmet — resolve it first

---

## After Commit

1. Confirm the commit appears on the remote branch
2. Open a PR from `<feature-identifier>` → `main`
3. Summarize for Tony: what was built, what was tested, what to verify manually
4. Do not merge the PR — Tony merges after final review

---

## Gate Failure Protocol

If any condition fails at commit time:

1. Do not commit
2. Identify the exact failing condition
3. Return to the appropriate agent (Engineer or QA) with specific instructions
4. Re-run from that stage
5. Do not re-run the full pipeline unless the root cause was architectural

---

*No exceptions. No shortcuts. QA APPROVED is the only key that opens this gate.*
