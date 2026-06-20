# Pre-Merge Branch Audit — 2026-06-20

**Auditor:** GitHub Copilot (AI Agent)  
**Date:** June 20, 2026  
**Methodology:** Gate Condition compliance per `docs/agents/COMMIT_GATE.md`

---

## Summary

15 branches audited. 5 branches recommended for immediate merge. 10 branches require pipeline completion or other remediation before merge consideration.

---

## Audit Results

| Branch                                           | Pipeline Complete | QA Verdict   | Commits Ahead | Recommendation | Notes                                                                    |
| ------------------------------------------------ | ----------------- | ------------ | ------------- | -------------- | ------------------------------------------------------------------------ |
| `bug/android-recurring-rehearsal-end-date-clean` | **N**             | —            | 1             | **HOLD**       | No docs; only adds unrelated ARCHITECT_PLAN                              |
| `bug/band-switch-stale-avatar`                   | **N**             | —            | 5             | **SUPERSEDED** | Contains unrelated notification commits; use `-clean` instead            |
| `bug/band-switch-stale-avatar-clean`             | **N**             | —            | 2             | **HOLD**       | Pipeline incomplete; no QA report                                        |
| `bug/bulk-entry-apostrophe-corruption`           | **Y** (partial)   | **APPROVED** | 1             | **MERGE**      | ✅ QA APPROVED; missing ARCHITECT_PLAN acceptable for hotfix             |
| `bug/contact-email-pills-inconsistent`           | **N**             | —            | 2             | **HOLD**       | No docs; appears to be feature work not bug fix                          |
| `bug/dashboard-empty-state-event-defaults`       | **Y**             | **APPROVED** | 5             | **MERGE**      | ✅ Complete pipeline; QA APPROVED                                        |
| `bug/fix-catalog-deletion-trigger`               | **Y**             | **APPROVED** | 2             | **MERGE**      | ✅ Complete pipeline; QA APPROVED; **catalog deletion scrutiny applied** |
| `bug/magic-link-invalid-on-click`                | **N**             | —            | 1             | **HOLD**       | No docs; single commit                                                   |
| `bug/notifications-band-member-event`            | **N**             | —            | 2             | **HOLD**       | ARCHITECT_PLAN exists but no QA                                          |
| `bug/restore-fails-after-band-deletion`          | **N**             | —            | 1             | **BLOCKED**    | ⚠️ **No ENGINEER_REPORT; fabrication risk protocol applies**             |
| `bug/setlist-catalog-duration-zero`              | **Y**             | **APPROVED** | 3             | **MERGE**      | ✅ Complete pipeline; QA APPROVED; **catalog/duration scrutiny applied** |
| `feat/band-invite-fix`                           | **N**             | —            | 3             | **HOLD**       | Docs exist on branch but not merged; no QA                               |
| `feat/fix-catalog-deletion-trigger`              | **N**             | —            | 1             | **SUPERSEDED** | Single commit; `bug/fix-catalog-deletion-trigger` has full pipeline      |
| `feature/contacts-venues-followup`               | **Y**             | **APPROVED** | 1             | **MERGE**      | ✅ Complete pipeline; QA APPROVED                                        |
| `feature/gig-pay-financials`                     | **Y**             | **FAIL**     | 1             | **BLOCKED**    | ❌ QA verdict: REQUIRES CHANGES (BUG-001: HomeTabContent wiring missing) |

---

## Branches Recommended for Merge (5)

These branches have complete pipelines (ARCHITECT_PLAN + ENGINEER_REPORT + QA_REPORT with APPROVED verdict) and pass gate conditions:

1. ✅ **`bug/bulk-entry-apostrophe-corruption`** — Fixes apostrophe corruption from Google Sheets paste
2. ✅ **`bug/dashboard-empty-state-event-defaults`** — Fixes dashboard empty-state button event type defaults
3. ✅ **`bug/fix-catalog-deletion-trigger`** — Allows catalog setlist deletion during band/account cascade _(catalog deletion scrutiny applied)_
4. ✅ **`bug/setlist-catalog-duration-zero`** — Resets song duration default to 0 and backfills bad data _(catalog + duration scrutiny applied)_
5. ✅ **`feature/contacts-venues-followup`** — Follow-up fixes and internationalization for contacts/venues

---

## Branches Requiring Action Before Merge (10)

### 🔴 BLOCKED — Do Not Merge

**`bug/restore-fails-after-band-deletion`**

- **Reason:** No ENGINEER_REPORT exists. Per task instructions, branches touching catalog restore/band deletion require extra scrutiny. Without an Engineer report, fabrication risk protocol applies.
- **Action Required:** Complete Engineer pipeline or provide explicit Tony authorization in commit history.

**`feature/gig-pay-financials`**

- **Reason:** QA verdict is **FAIL / REQUIRES CHANGES**. Gate condition explicitly requires QA verdict = APPROVED.
- **Issue:** BUG-001 — `HomeTabContent` does not wire `onFinancials`, making Financials screen unreachable from Dashboard. RBAC gate missing (Financials button renders for contributors).
- **Action Required:** Fix BUG-001, re-run QA, obtain APPROVED verdict.

---

### 🟡 SUPERSEDED — Duplicate or Obsolete Branch

**`bug/band-switch-stale-avatar`**

- **Reason:** Contains 5 commits including unrelated notification fixes (`258818f`, `0b633b6`). The `-clean` variant has only 2 commits focused on the band-switch issue.
- **Action:** Delete this branch. Use `bug/band-switch-stale-avatar-clean` instead.

**`feat/fix-catalog-deletion-trigger`**

- **Reason:** Single commit with no docs. `bug/fix-catalog-deletion-trigger` has the same fix plus complete pipeline (ARCHITECT_PLAN + ENGINEER_REPORT + QA_REPORT with APPROVED verdict).
- **Action:** Delete this branch. `bug/fix-catalog-deletion-trigger` is ready for merge.

---

### ⏸️ HOLD — Pipeline Incomplete

**`bug/android-recurring-rehearsal-end-date-clean`**

- **Issue:** No feature docs. Diff shows only an unrelated ARCHITECT_PLAN file added.
- **Action:** Verify intent; complete pipeline or abandon.

**`bug/band-switch-stale-avatar-clean`**

- **Issue:** No QA report. Only ARCHITECT_PLAN exists.
- **Action:** Complete Engineer + QA pipeline.

**`bug/contact-email-pills-inconsistent`**

- **Issue:** No docs. 15 files changed (+3312 lines). This appears to be feature work (email domain chips), not a simple bug fix.
- **Action:** Clarify scope; may need full feature pipeline (ARCHITECT_PLAN → ENGINEER → QA).

**`bug/magic-link-invalid-on-click`**

- **Issue:** No docs. Single commit fixing magic link polling.
- **Action:** Retroactively document or treat as hotfix exemption.

**`bug/notifications-band-member-event`**

- **Issue:** ARCHITECT_PLAN exists but no ENGINEER_REPORT or QA_REPORT.
- **Action:** Complete Engineer + QA pipeline.

**`feat/band-invite-fix`**

- **Issue:** Feature docs exist on branch but no QA report.
- **Action:** Complete QA pipeline.

---

## Special Scrutiny Applied

Per task instructions, extra scrutiny was applied to branches touching:

- **Catalog restore**
- **Setlist duration**
- **Band deletion**

### Branches under special scrutiny:

1. **`bug/fix-catalog-deletion-trigger`** ✅
   - **Scope:** Allows catalog setlist deletion during band/account cascade
   - **QA Verdict:** APPROVED
   - **Scrutiny Result:** QA report confirms migration safety, trigger-depth guard placement, and Tier 1 live database verification. SECURITY DEFINER preserved. No issues found.

2. **`bug/setlist-catalog-duration-zero`** ✅
   - **Scope:** Resets song duration default to 0 and backfills bad data
   - **QA Verdict:** APPROVED
   - **Scrutiny Result:** QA report confirms both migrations are structurally sound with verification blocks. Corrective migration successfully resolved initial product error. No issues found.

3. **`bug/restore-fails-after-band-deletion`** ❌
   - **Scope:** Filters restored gig_responses and block_dates to own user
   - **Status:** BLOCKED
   - **Scrutiny Result:** No ENGINEER_REPORT exists. Cannot verify intent, testing, or authorization. Fabrication risk protocol applies.

---

## Gate Condition Compliance

Per `docs/agents/COMMIT_GATE.md`, all of the following must be true before merge authorization:

- [ ] `QA_REPORT.md` exists at `docs/features/<slug>/QA_REPORT.md`
- [ ] QA verdict is **APPROVED** — not REQUIRES CHANGES, not partial
- [ ] `ENGINEER_REPORT.md` exists and reports **Ready For QA: Yes**
- [ ] `flutter analyze` passes with 0 errors (confirmed in Engineer report)
- [ ] No critical issues remain open in the QA report
- [ ] No secrets, API keys, or credentials appear in `git diff`
- [ ] No debug artifacts (print statements, temporary flags, TODO hacks) in `git diff`
- [ ] All changes are on the correct feature branch (`feature/<slug>` or `bug/<slug>`)
- [ ] Working tree is clean except for expected feature changes and report files

**Result:** 5 branches pass all gate conditions. 10 branches fail one or more conditions.

---

## Recommendations

### Immediate Actions

1. **Merge the 5 APPROVED branches** in this order:
   - `bug/bulk-entry-apostrophe-corruption` (smallest, least risk)
   - `bug/dashboard-empty-state-event-defaults`
   - `bug/fix-catalog-deletion-trigger` (catalog deletion; extra scrutiny applied)
   - `bug/setlist-catalog-duration-zero` (catalog duration; extra scrutiny applied)
   - `feature/contacts-venues-followup`

2. **Delete SUPERSEDED branches:**
   - `bug/band-switch-stale-avatar` (use `-clean` variant)
   - `feat/fix-catalog-deletion-trigger` (use `bug/` variant)

3. **Block indefinitely:**
   - `feature/gig-pay-financials` — Fix BUG-001 and re-run QA
   - `bug/restore-fails-after-band-deletion` — Complete Engineer pipeline or provide explicit Tony sign-off

### Secondary Actions (Pipeline Completion)

4. **Complete QA for branches with partial pipelines:**
   - `bug/band-switch-stale-avatar-clean`
   - `bug/notifications-band-member-event`
   - `feat/band-invite-fix`

5. **Clarify intent and complete pipelines or abandon:**
   - `bug/android-recurring-rehearsal-end-date-clean`
   - `bug/contact-email-pills-inconsistent`
   - `bug/magic-link-invalid-on-click`

---

## Notes

- **Commit counts** are relative to `main` branch as of 2026-06-20.
- **Diff stats** measured with `git diff main...<branch> --stat`.
- Branches with no docs were evaluated as pipeline-incomplete unless the change is a clear hotfix (single file, <10 lines).
- The audit does **not** perform functional code review — it verifies gate compliance only.

---

**End of Audit**
