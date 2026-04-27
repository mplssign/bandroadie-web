# Database Schema

*Generated from live database — project `nekwjxvgbveheooyorjo`. Last verified: 2026-04-14.*

---

## Core Identity

| Table              | Rows | Description |
| ------------------ | ---: | ----------- |
| `users`            | 200  | User profiles (first_name, last_name, phone, address, city, zip, birthday, roles[], profile_completed, calendar_token) |
| `profiles`         | 283  | Auth-linked profile (full_name, avatar_url, email, phone, bio) — legacy/supplementary, separate from `users` |
| `bands`            | 91   | Band entities (name, image_url, created_by, avatar_color, timezone, last_used_print_template_id) |
| `band_members`     | 188  | Membership (band_id, user_id, role: `band_role_type` ENUM, status: invited/active/inactive/removed) |
| `band_invitations` | 154  | Pending invites (band_id, email, invited_by, token, status, expires_at, accepted_at) |
| `user_band_roles`  | 50   | Per-band instrument/musical roles for a user (user_id, band_id, roles[]) — separate from RBAC role |
| `feedback`         | 0    | In-app bug reports and feature requests (type: bug/feature, description, status) |
| `app_config`       | 1    | Global key-value config table |

## RBAC

| Table / Type              | Description |
| ------------------------- | ----------- |
| `band_role_type`          | PostgreSQL ENUM: `'admin'`, `'member'`, `'contributor'` |
| `contributor_permissions` | Fine-grained contributor access (can_create_gigs, can_create_potential_gigs_only, can_view_setlists, can_view_calendar, can_view_members) |

Three enforced roles: `admin` (full authority), `member` (CRUD, no destructive ops), `contributor` (limited, configured via `contributor_permissions`). New invited members default to `member`. New band creators default to `admin`. Existing active members were promoted to `admin` during migration.

## Events

| Table           | Rows | Description |
| --------------- | ---: | ----------- |
| `gigs`          | 267  | Gig events (band_id, name, date, start_time, end_time, location, is_potential, setlist_id, notes, gig_pay, load_in_time, created_by, required_member_ids[], venue_id) |
| `gig_dates`     | 0    | Multi-date support for gigs (gig_id, date) — linked from gig_responses |
| `gig_responses` | 67   | RSVP tracking (gig_id, user_id, response: yes/no, gig_date_id) |
| `rehearsals`    | 870  | Rehearsal sessions (band_id, date, start_time, end_time, location, notes, setlist_id, is_recurring, recurrence_frequency, recurrence_days[], recurrence_until, parent_rehearsal_id) |
| `block_dates`   | 697  | Member blackout/unavailability dates (user_id, band_id, date, reason) |

**Recurring rehearsals:** `is_recurring`, `recurrence_frequency` (weekly/biweekly/monthly), `recurrence_days[]` (0=Sun…6=Sat), `recurrence_until`, `parent_rehearsal_id` (links series instances to the first rehearsal).

## Setlist Management

| Table                  | Rows  | Description |
| ---------------------- | ----: | ----------- |
| `setlists`             | 204   | Setlists per band (band_id, name, setlist_type: regular/catalog, is_catalog, total_duration, position) |
| `songs`                | 1,733 | Song catalog (band_id, title, artist, bpm, duration_seconds, tuning, notes, lyrics, album_artwork, spotify_id, musicbrainz_id, deezer_id, youtube_links JSON) |
| `setlist_songs`        | 2,929 | Ordered items in a setlist (setlist_id, song_id, position, bpm override, duration_seconds override, tuning override, item_type: song/special, special_item_id) |
| `setlist_special_items`| 60    | Set breaks and pauses (band_id, type: set_break/pause, duration_minutes, duration_seconds, purposes[], custom_purposes[], is_saved_template) |
| `song_notes`           | 0     | Per-song, per-band notes (song_id, band_id, content, created_by) |

**Setlist song overrides:** `setlist_songs` stores per-setlist BPM, duration, and tuning overrides on top of the song's catalog values. `item_type` can be `'song'` or `'special'`; special items link to `setlist_special_items`.

## Venues & Contacts

| Table            | Rows | Description |
| ---------------- | ---: | ----------- |
| `venues`         | 16   | Venue directory (band_id, name, address, city, state, phone, notes) |
| `venue_contacts` | 1    | Venue contact persons (venue_id, band_id, name, title, phone, email, notes) |
| `contacts`       | 0    | General band contacts — agents, promoters, etc. (band_id, name, title, phone, email, notes) |

## Notifications

| Table                      | Rows  | Description |
| -------------------------- | ----: | ----------- |
| `notifications`            | 1,008 | Delivery queue (recipient_user_id, actor_user_id, band_id, type, title, body, metadata JSONB, read_at, sent_at) |
| `notification_preferences` | 35    | Per-user toggles — two generations of columns coexist (see below) |
| `device_tokens`            | 132   | FCM tokens (user_id, fcm_token unique, platform: ios/android/web/macos, device_name, last_seen) |

**notification_preferences columns (two generations):**
- Legacy: `gig_updates`, `rehearsal_updates`, `setlist_updates`, `availability_requests`, `member_updates`, `push_enabled`, `in_app_enabled`, `quiet_hours_start/end`, `timezone`
- Current: `notifications_enabled` (master toggle), `gigs_enabled`, `potential_gigs_enabled`, `rehearsals_enabled`, `blockouts_enabled`

**notifications.type** allowed values: `gig_created`, `gig_updated`, `gig_cancelled`, `gig_confirmed`, `potential_gig_created`, `rehearsal_created`, `rehearsal_updated`, `rehearsal_cancelled`, `blockout_created`, `setlist_updated`, `availability_request`, `availability_response`, `member_joined`, `member_left`, `role_changed`, `band_invitation`

## Calendar Subscriptions

| Table                      | Rows | Description |
| -------------------------- | ---: | ----------- |
| `band_calendar_subscriptions` | 19 | iCal feed subscriptions (user_id, band_id, token unique, include_gigs, include_rehearsals, include_blockouts) |

`users.calendar_token` provides a personal calendar token. `get_band_calendar_token` / `get_my_calendar_token` RPCs return subscription URLs.

## Print Templates

| Table             | Rows | Description |
| ----------------- | ---: | ----------- |
| `print_templates` | 6    | Setlist print layouts per band — extensive font size, column, and display toggle settings |

Key fields: `tuning_display` (grouped/inline), `show_capo/bpm/notes/tuning/pauses`, `column_count` (1 or 2), `paper_size` (letter/a4), `base_font_size`, plus individual font sizes for numbers, headers, band name, BPM, tuning, capo, notes, pauses, and `line_spacing`.

## Analytics & Audit

| Table               | Rows | Description |
| ------------------- | ---: | ----------- |
| `band_access_events`| 861  | Access tracking (band_id, user_id, accessed_at) |

---

## RLS

Row Level Security is enabled on all tables. Policies check `band_members.role` + `band_members.status` for band-scoped resources. The `band_role_type` ENUM prevents invalid role values at the storage layer.

---

## RPC Functions (public schema)

### RBAC & Band Management
| Function | Notes |
|----------|-------|
| `create_band(...)` | Creates band + adds creator as admin |
| `delete_band(p_band_id)` | Admin-only, FOR UPDATE lock, last-admin check |
| `update_member_role(p_band_id, p_user_id, p_new_role)` | Admin-only, prevents self-demotion if last admin |
| `remove_band_member(p_band_id, p_user_id)` | Admin-only, prevents last-admin removal |
| `get_user_band_role(p_band_id)` | SECURITY INVOKER (intentional) |
| `is_band_admin(band_id)` | Boolean helper |
| `is_band_member(band_id)` | Boolean helper |
| `is_band_member_with_role(band_id, role)` | Boolean helper |
| `accept_band_invite(...)` | Processes invite token, adds member |
| `delete_user_account()` | Full account deletion |

### Setlist Operations
| Function | Notes |
|----------|-------|
| `update_song_metadata(...)` | SECURITY DEFINER — bypasses RLS for legacy NULL band_id songs |
| `clear_song_metadata(...)` | SECURITY DEFINER — clears metadata overrides |
| `ensure_catalog_setlist(band_id)` | Creates Catalog setlist if missing |
| `auto_create_catalog_for_band()` | Trigger function |
| `delete_setlist(setlist_id)` | Handles cascade |
| `delete_song_from_setlist(...)` | Removes from setlist_songs |
| `delete_song_from_catalog(...)` | Removes from catalog |
| `reorder_setlist_songs(...)` | Batch position update |
| `reorder_setlist_items(...)` | Includes special items |
| `reorder_setlist_positions(...)` | Position recalculation |
| `increment_setlist_positions(...)` | Makes room for insert |
| `add_special_item_to_setlist(...)` | Inserts set break / pause |
| `recompute_setlist_stats(setlist_id)` | Recalculates total_duration |
| `get_band_full_state(band_id)` | Bulk-fetch for band context |

### Notifications
| Function | Notes |
|----------|-------|
| `notify_band_members(...)` | Core fanout — inserts notification records |
| `notify_gig_created()` | Trigger handler |
| `notify_rehearsal_created()` | Trigger handler |
| `notify_blockout_created()` | Trigger handler |
| `notify_new_band_member()` | Trigger handler |
| `should_receive_notification(user_id, type)` | Checks preferences |
| `get_or_create_notification_preferences(user_id)` | Upserts preferences |
| `get_unread_notification_count(user_id)` | Returns count |
| `mark_all_notifications_read()` | Marks all as read for current user |
| `upsert_device_token(...)` | Register/refresh FCM token |
| `trigger_send_push_notification()` | Trigger function |

### Calendar
| Function | Notes |
|----------|-------|
| `get_band_calendar_token(band_id)` | Returns subscription token |
| `get_my_calendar_token()` | Personal token |
| `regenerate_calendar_token()` | Rotates personal token |
| `regenerate_band_calendar_token(band_id)` | Rotates band token |
| `update_band_calendar_preferences(...)` | Updates include_* flags |

### Utilities
| Function | Notes |
|----------|-------|
| `get_user_band_ids()` | Returns all band IDs for current user |
| `get_bandmate_user_ids(band_id)` | Returns user IDs of bandmates |
| `generate_invite_token()` | Generates secure random token |
| `handle_new_user()` / `handle_new_user_profile()` | Auth triggers |
| `check_gig_response_access(...)` | RLS helper |
| `prevent_catalog_deletion()` / `prevent_catalog_rename()` | Guard triggers |
| `update_setlist_duration(...)` | Trigger to maintain total_duration |
| `update_updated_at_column()` | Generic updated_at trigger |

---

> See `BAND_ROADIE_DOCUMENTATION.md` for full feature descriptions.
