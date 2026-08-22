# Pre-Migration ACL State — feature/security-definer-revoke-public

**Captured:** 2026-08-21  
**Source:** Production database (`nekwjxvgbveheooyorjo`)  
**Purpose:** Baseline for rollback plans — exact pre-migration ACL state per function signature

## Summary

**Total signatures captured:** 58 rows representing 56 unique function names

- Overloaded functions: `is_band_admin` (2 signatures), `update_band_calendar_preferences` (2 signatures)

**Grant patterns identified:**

- **55 signatures with PUBLIC grant** (acl_array starts with `{=X/postgres,...}`)
- **3 signatures with direct anon grant, NO PUBLIC** (`accept_band_invite`, `create_band`, `is_band_member`)
- **1 signature with PUBLIC and service_role, NO authenticated** (`is_band_member_with_role`)

## Critical Findings

### Functions WITHOUT PUBLIC Grant (3)

These have explicit role grants but no PUBLIC default:

| Function             | Signature                                            | Grants                                      |
| -------------------- | ---------------------------------------------------- | ------------------------------------------- |
| `accept_band_invite` | `p_invite_id uuid, p_user_id uuid`                   | postgres, anon, authenticated, service_role |
| `create_band`        | `p_name text, p_avatar_color text, p_image_url text` | postgres, anon, authenticated, service_role |
| `is_band_member`     | `p_band_id uuid`                                     | postgres, service_role, authenticated, anon |

**Rollback for these 3:** Use `GRANT EXECUTE ... TO anon, authenticated;` (not PUBLIC)

### Functions WITH PUBLIC Grant (53)

All other functions have `{=X/postgres,...}` pattern indicating PUBLIC has EXECUTE.

**Rollback for these:** Use `GRANT EXECUTE ... TO PUBLIC;`

### Special Case: `is_band_member_with_role`

- Has PUBLIC and service_role grants
- Does NOT have authenticated grant
- **Rollback:** `GRANT EXECUTE ... TO PUBLIC;` (do not grant to authenticated)

## Complete ACL State Per Signature

| Function Name                          | Signature                                                                                                                                                                                    | PUBLIC | anon | authenticated | service_role | ACL Array                                                                                          |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ---- | ------------- | ------------ | -------------------------------------------------------------------------------------------------- |
| accept_band_invite                     | p_invite_id uuid, p_user_id uuid                                                                                                                                                             | ✓      | ✓    | ✓             | ✓            | {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}             |
| add_special_item_to_setlist            | p_setlist_id uuid, p_special_item_id uuid, p_item_type text                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| auto_create_catalog_for_band           | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| bulk_add_songs_to_setlist              | p_band_id uuid, p_setlist_id uuid, p_song_ids uuid[]                                                                                                                                         | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| check_band_member                      | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| check_financial_view_permission        | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| check_gig_response_access              | p_gig_id uuid                                                                                                                                                                                | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| check_rehearsal_response_access        | p_rehearsal_id uuid, p_user_id uuid                                                                                                                                                          | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| clear_song_metadata                    | p_song_id uuid, p_band_id uuid, p_clear_bpm boolean, p_clear_duration boolean, p_clear_tuning boolean, p_clear_musical_key boolean                                                           | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| create_band                            | p_name text, p_avatar_color text, p_image_url text                                                                                                                                           | ✓      | ✓    | ✓             | ✓            | {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}             |
| create_venue_for_gig_save              | p_band_id uuid, p_name text, p_city text, p_address text, p_state text, p_is_potential boolean                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| delete_setlist                         | p_band_id uuid, p_setlist_id uuid                                                                                                                                                            | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| delete_song_from_catalog               | p_band_id uuid, p_song_id uuid                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| delete_song_from_setlist               | p_setlist_id uuid, p_song_id uuid                                                                                                                                                            | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| ensure_catalog_setlist                 | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_band_calendar_token                | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_bandmate_user_ids                  | user_uuid uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_my_calendar_token                  | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_or_create_calendar_preferences     | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_or_create_notification_preferences | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_unread_notification_count          | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| get_user_band_ids                      | user_uuid uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| handle_new_user                        | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| handle_new_user_profile                | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| increment_setlist_positions            | p_setlist_id uuid                                                                                                                                                                            | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| is_band_admin                          | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| is_band_admin                          | user_uuid uuid, check_band_id uuid                                                                                                                                                           | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| is_band_member                         | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres,anon=X/postgres}             |
| is_band_member_with_role               | p_band_id uuid, p_roles text[]                                                                                                                                                               | ✓      | ✓    | ✗             | ✓            | {=X/postgres,postgres=X/postgres,service_role=X/postgres}                                          |
| mark_all_notifications_read            | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| move_song_between_setlists             | p_source_setlist_id uuid, p_target_setlist_id uuid, p_song_id uuid, p_band_id uuid                                                                                                           | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| notify_band_members                    | p_band_id uuid, p_actor_user_id uuid, p_notification_type text, p_title text, p_body text, p_metadata jsonb                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| notify_blockout_created                | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| notify_gig_created                     | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| notify_new_band_member                 | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| notify_rehearsal_created               | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| prevent_catalog_deletion               | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| prevent_catalog_rename                 | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| regenerate_band_calendar_token         | p_band_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| regenerate_calendar_token              | p_user_id uuid                                                                                                                                                                               | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| recompute_setlist_stats                | p_setlist_id uuid                                                                                                                                                                            | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| reorder_band_members                   | p_band_id uuid, p_member_ids uuid[]                                                                                                                                                          | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| reorder_setlist_items                  | p_setlist_id uuid, p_row_ids uuid[]                                                                                                                                                          | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| reorder_setlist_positions              | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| reorder_setlist_songs                  | p_setlist_id uuid, p_row_ids uuid[]                                                                                                                                                          | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| reorder_setlists                       | p_band_id uuid, p_setlist_ids uuid[]                                                                                                                                                         | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| restore_band_members                   | p_band_id uuid, p_members jsonb                                                                                                                                                              | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| sync_gig_location_from_venue           | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| sync_gig_pay_from_financial_entry      | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| trigger_recompute_setlist_stats        | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| trigger_send_push_notification         | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_band_calendar_preferences       | p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean                                                                                            | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_band_calendar_preferences       | p_band_id uuid, p_include_gigs boolean, p_include_rehearsals boolean, p_include_blockouts boolean, p_include_potential_gigs boolean, p_include_potential_rehearsals boolean                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_calendar_preferences            | p_one_calendar_enabled boolean, p_apply_to_mode text, p_selected_band_ids uuid[], p_auto_block_conflicts_enabled boolean                                                                     | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_setlist_duration                | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_song_metadata                   | p_song_id uuid, p_band_id uuid, p_bpm integer, p_duration_seconds integer, p_tuning text, p_notes text, p_title text, p_artist text, p_youtube_links text, p_lyrics text, p_musical_key text | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| update_song_notes_updated_at           | (no params)                                                                                                                                                                                  | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |
| upsert_device_token                    | p_fcm_token text, p_platform text, p_device_name text, p_old_token text                                                                                                                      | ✓      | ✓    | ✓             | ✓            | {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres} |

## Rollback Reference

### Pattern 1: Functions with PUBLIC Grant (53 signatures)

All functions except `accept_band_invite`, `create_band`, and `is_band_member`.

**Rollback command:**

```sql
GRANT EXECUTE ON FUNCTION function_name(signature) TO PUBLIC;
```

### Pattern 2: Functions with Direct Anon Grant (3 signatures)

`accept_band_invite`, `create_band`, `is_band_member`

**Rollback commands:**

```sql
GRANT EXECUTE ON FUNCTION accept_band_invite(p_invite_id uuid, p_user_id uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION create_band(p_name text, p_avatar_color text, p_image_url text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION is_band_member(p_band_id uuid) TO anon, authenticated;
```

**Note:** These three also need service_role restored if revoked, but since the plan is to keep service_role for `accept_band_invite` and likely revoke for the other two, refer to per-batch requirements.

### Pattern 3: Special Case (`is_band_member_with_role`)

Has PUBLIC but NOT authenticated.

**Rollback command:**

```sql
GRANT EXECUTE ON FUNCTION is_band_member_with_role(p_band_id uuid, p_roles text[]) TO PUBLIC;
```

## Manager Correction Applied

**For `accept_band_invite`:** The plan's Task 4 text says "already has service_role-only grant" but the actual captured state shows it has postgres, anon, authenticated, and service_role. The correct rollback if only service_role is desired is:

**Current state:** postgres, anon, authenticated, service_role all have EXECUTE  
**Desired end state:** Only service_role has EXECUTE  
**Rollback to pre-migration:** `GRANT EXECUTE ... TO anon, authenticated;` (restoring anon + authenticated access)
