# ARCHITECT PLAN TEMPLATE

## 1. Problem Summary
Brief description of the issue or feature.

## 2. Existing System Analysis
Explain how the current system works.

Include:
• relevant Flutter layers
• repositories
• controllers/providers
• Supabase tables
• RPCs
• RLS policies
• migrations

## 3. Root Cause
Explain the root cause.

If feature work:
"Not applicable".

## 4. Proposed Solution
Describe the minimal architectural solution.

Goals:
• minimal change surface
• backward compatible
• production safe

## 5. Database Impact
Describe any database changes.

Include:
• migrations
• RLS changes
• RPC changes
• triggers

If none:
"No database changes required."

## 6. RLS / RPC Changes
List exact policy or RPC modifications.

## 7. Flutter Architecture Changes
Describe repository/controller/UI changes.

## 8. Exact Files to Create
List new files.

## 9. Exact Files to Modify
List existing files.

## 10. Risks / Edge Cases
Identify possible regressions.

## 11. Verification Plan
Describe testing steps.

Include:
• SQL verification
• Flutter test flow
• QA scenarios

## 12. Engineer Task Breakdown
Provide step-by-step instructions.

## 13. Rollout / Migration Strategy
Explain deployment order.

Include:
• migration order
• cache reload if needed

## 14. Out of Scope
Clarify what will not change.
