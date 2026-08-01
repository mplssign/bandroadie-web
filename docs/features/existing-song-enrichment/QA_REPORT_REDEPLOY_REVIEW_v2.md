# QA Report — Redeploy Review (v2)

## Scope

Review target: Migration 20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql  
Review date: 2026-07-31  
Review type: Redeploy safety assessment (migration-only)  
Reviewer: QA Agent

This report replaces the previously rejected redeploy review and is based only on direct source inspection and read-only production verification performed in this session.

Out of scope: full feature QA for existing-song-enrichment UI/orchestration.

---

## Final Verdict

**APPROVED**

The migration is safe to redeploy to production.

---

## Executive Summary

1. The migration SQL implements the required fill-missing-only behavior for BPM, duration_seconds, and musical_key.
2. The architect requirement is explicit: fill missing fields only, never overwrite existing values.
3. Production is currently running rollback behavior (always-overwrite for duration_seconds and musical_key), which does not match the architect requirement for this phase.
4. Staging evidence is directionally credible for key behavior and methodology, but the provided EVIDENCE.log in this repository does not fully substantiate BPM and duration claims by itself.

Conclusion: redeploying 20260801000000 to production is the correct and safe action for requirement alignment.

---

## What I Read Before Verification

Required process docs:

- docs/agents/QA.md
- docs/agents/GUARDRAILS.md

Feature docs:

- docs/features/existing-song-enrichment/ARCHITECT_PLAN.md
- docs/features/existing-song-enrichment/ENGINEER_REPORT.md
- docs/features/existing-song-enrichment/QA_REPORT.md
- docs/features/existing-song-enrichment/EVIDENCE.log

Migration files:

- supabase/migrations/20260801000000_fix_musical_key_duration_overwrite_in_update_song_rpc.sql
- supabase/migrations/20260801000001_rollback_musical_key_duration_overwrite.sql

---

## Requirement Check (Architect Plan)

Architect requirement (Phase 2.1): fill missing only, never overwrite existing value.

Migration 20260801000000 matches this requirement:

- bpm: CASE WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm ELSE bpm END
- duration_seconds: CASE WHEN p_duration_seconds IS NOT NULL AND duration_seconds = 0 THEN p_duration_seconds ELSE duration_seconds END
- musical_key: CASE WHEN p_musical_key IS NOT NULL AND musical_key IS NULL THEN p_musical_key ELSE musical_key END

Rollback 20260801000001 does not match this requirement:

- duration_seconds uses COALESCE(p_duration_seconds, duration_seconds) (overwrites when input provided)
- musical_key overwrites whenever p_musical_key is non-null (except empty-string clear path)

---

## Read-Only Production Verification

Production ref: nekwjxvgbveheooyorjo  
Staging ref: hpjvbagybmmaykamsgpd

Verification approach was strictly read-only and used only:

- supabase migration list --linked
- supabase db query --linked with SELECT against pg_proc + pg_get_functiondef

### Verified production state

1. Migration list on production shows both:

- 20260801000000
- 20260801000001

2. Live production function definition for public.update_song_metadata currently contains rollback logic:

- duration_seconds = COALESCE(p_duration_seconds, duration_seconds)
- musical_key CASE branch that overwrites when p_musical_key IS NOT NULL

This independently confirms production is currently on old always-overwrite behavior, consistent with Tony's dashboard confirmation.

---

## Git Diff Review

git branch: main

Observed working tree includes feature-related edits and untracked files.  
Migration 20260801000000 exists as untracked in this workspace snapshot; migration 20260801000001 is present in repository history.

This does not change the redeploy verdict because the production function body was verified directly from pg_get_functiondef.

---

## EVIDENCE.log Assessment (Staging Claims)

Assessment standard: treat EVIDENCE.log as a claim to analyze, not an authority.

### What is methodologically sound

1. It distinguishes SQL with faked claims from REST with real GoTrue JWT.
2. It includes before/after state examples for REST calls.
3. It uses the RPC endpoint path consistent with Flutter client behavior (PostgREST RPC route).

### What is incomplete or internally weak

1. The checked-in EVIDENCE.log content in this repository primarily demonstrates musical_key scenarios (fill and preserve).
2. The file claims broader confidence, but this artifact alone does not fully prove BPM and duration outcomes end-to-end.
3. It documents use of a manual minimal schema in staging, which is valid for targeted RPC logic checks but not a full-fidelity proof of complete production parity.

### Net assessment

EVIDENCE.log is credible as supporting evidence for key non-overwrite behavior and auth-path methodology, but partial as a sole artifact for BPM/duration claims.

This does not block redeploy approval because:

- the migration SQL itself is straightforward and deterministic;
- the logic exactly matches architect requirements;
- production is currently on known non-compliant rollback behavior.

---

## Risk Assessment

Risk level: **LOW to MEDIUM**

Why not HIGH:

- Change scope is narrowly localized to CASE logic in one RPC.
- No signature change.
- No auth/RLS model change.
- New logic is directly aligned with requirement language.

Residual risk:

- Operational rollout risk remains if deployment process/drift is not controlled.
- Staging artifact incompleteness for BPM/duration should be cleaned up for audit quality.

---

## Explicit Read-Only Attestation

I performed zero writes to any database in this session.

Specifically, I did not run:

- INSERT / UPDATE / DELETE
- CREATE / DROP
- supabase db push / db reset
- any RPC invocation (including update_song_metadata)

All database commands executed were read-only:

- supabase migration list --linked
- supabase db query --linked with SELECT + pg_get_functiondef

I also stated the linked project ref immediately before each database command.

---

## Recommended Next Actions

1. Redeploy migration 20260801000000 to production.
2. Ensure deployment sequencing keeps 20260801000001 from re-applying the overwrite logic.
3. Update evidence artifacts to include explicit BPM and duration before/after outputs in the same rigor as musical_key for future audits.

---

Report file: docs/features/existing-song-enrichment/QA_REPORT_REDEPLOY_REVIEW_v2.md
Status: Complete
