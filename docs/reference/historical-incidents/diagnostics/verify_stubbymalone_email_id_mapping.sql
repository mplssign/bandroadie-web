-- PREREQUISITE: Verify email-to-ID mapping before running Task 2 diagnostics
-- Console log from "Test Gig 2" showed: Auto-blocking 1 date(s) for user: 4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925
-- Tony confirmed this account's email is: stubbymalone@gmail.com
--
-- This query verifies that the email and user_id match expectations before building diagnostics on top of it.
-- If they don't match, STOP and flag the discrepancy.

-- Check auth.users (canonical source for email)
SELECT 
  id,
  email,
  created_at
FROM auth.users
WHERE email = 'stubbymalone@gmail.com';

-- Expected result: id = '4b8b4b6c-1e2a-4c0e-ad77-01e9749b2925'
-- If NULL or doesn't match, do NOT proceed with Task 2 diagnostics.
