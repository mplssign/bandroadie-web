# Blocked: net schema anonymous execute revoke

## Problem

The planned `net` schema hardening still cannot be applied from this environment because the schema is owned by `supabase_admin`, and the current session role (`postgres`) is not a member of that role.

## Exact blocked statement

```sql
SET ROLE supabase_admin;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA net FROM anon, authenticated;
RESET ROLE;
```

## Ownership diagnosis

Live verification from the Supabase project shows:

```sql
SELECT pg_get_userbyid(nspowner) AS schema_owner
FROM pg_namespace
WHERE nspname = 'net';
```

Result:

```json
[{ "schema_owner": "supabase_admin" }]
```

The current Postgres session can also confirm the role membership path is unavailable:

```sql
SELECT member.rolname AS member_role, role.rolname AS parent_role
FROM pg_auth_members am
JOIN pg_roles member ON am.member = member.oid
JOIN pg_roles role ON am.roleid = role.oid
WHERE role.rolname = 'supabase_admin' OR member.rolname = 'postgres';
```

Result: no `postgres` membership path to `supabase_admin` is present.

## Verified platform restriction

Tony tested the same statement directly in the Supabase Dashboard SQL Editor and received the same error:

```text
ERROR:  42501: permission denied to set role "supabase_admin"
```

This is a Supabase platform restriction, not a local migration issue. The fix remains blocked on a separate Supabase support ticket filed by Tony.
