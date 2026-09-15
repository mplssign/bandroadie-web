## Summary

Member invitations had two consecutive failures: the Members tab could not reliably open the invite workflow, and an invited user with a stale or different browser session could hit a generic error immediately after opening the original invitation link.

The acceptance solution was reviewed twice before implementation. The first proposal was rejected because it only fixed a later login-email path, not the original-link failure. The final implementation directly handles the first-link session failure and preserves a robust login handoff for signed-out invitees.

## Changes

- Route both empty and populated Members views to the existing Invite Members screen.
- Recover stale or wrong-account browser sessions by clearing only the local session and asking the invitee to sign in with the invited address.
- Send signed-out invitees through the standard `/auth/confirm` flow while preserving the invitation token.
- Give targeted invitation outcomes distinct responses: accepted, wrong account, unavailable invitation, authentication failure, and backend acceptance failure.
- Prevent a targeted invitation token from falling through to the broad email invitation sweep.
- Consolidate auth-confirm navigation so invitation acceptance runs once.
- Add focused Flutter and Deno regression coverage for the full invitation contract.

Group chat is explicitly out of scope and was not added. There are no migrations, RLS, RPC, schema, or dependency changes.

## Verification

- Changed-file `flutter analyze` - no issues.
- Invite, auth-confirm, and Members focused tests - 11 passed.
- `deno check` and invitation contract tests - 13 passed.
- Full `flutter test` - 321 passed.
- Independent QA reran every check and returned `APPROVED`.

## Manual Verification Punch List

1. **Owner-run/manual - NOT executed by QA:** deploy the updated `accept-invite` edge function and ship the web build. **Expected:** both complete successfully.
2. **Owner-run/manual - NOT executed by QA:** in Supabase Authentication URL Configuration, confirm Redirect URLs accept `https://app.bandroadie.com/auth/confirm` with an `invite_token` query parameter. If entries are exact-match only, add an appropriate `/auth/confirm` wildcard. **Expected:** invite login lands on `/auth/confirm?invite_token=...&code=...`, not the site root.
3. In a browser already signed in as one account, open a fresh invite link for a different email. **Expected:** no generic error or false acceptance; the page asks you to sign in with the invited email.
4. Invite a fresh address from Members, open the invitation, enter that email, request the login link, and open it. **Expected:** the flow returns through `/auth/confirm`, shows `You've joined <Band>!`, and creates one active membership without a double redirect.
5. While already signed in as the invited email, open a fresh invitation link. **Expected:** immediate acceptance with no error.
6. Request and open a normal non-invite web login link. **Expected:** it lands at `/app` with no Invite Members screen.
7. Complete a normal iOS/Android `bandroadie://login-callback/` login. **Expected:** native login remains unchanged.
8. Verify the deployed server contract with an authenticated request: a foreign-email token returns `403 email_mismatch`, a consumed token returns `409 invite_unavailable`, and a request with no token retains the email-wide sweep behavior.