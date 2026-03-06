# Database Schema

## Core Tables

| Table | Description |
|-------|-------------|
| `users` | User profiles (id, email, name, phone, birthday) |
| `bands` | Band entities (id, name, image_url, created_by) |
| `band_members` | Band membership (band_id, user_id, role) |
| `band_invitations` | Pending invites (band_id, email, token, expires_at) |

## Event Management

| Table | Description |
|-------|-------------|
| `gigs` | Gig events (band_id, name, venue, date, is_potential, setlist_id) |
| `rehearsals` | Rehearsal sessions (band_id, location, start_time, end_time) |
| `gig_responses` | RSVP tracking (gig_id, user_id, response) |

## Setlist Management

| Table | Description |
|-------|-------------|
| `setlists` | Setlists per band (band_id, name — "Catalog" is special) |
| `songs` | Song catalog (band_id, title, artist, bpm, duration_seconds, tuning) |
| `setlist_songs` | Song ordering (setlist_id, song_id, position) |

## RLS & RPC

Row Level Security is enforced on all tables. Legacy songs with `NULL band_id` use `SECURITY DEFINER` RPC functions (`update_song_metadata`, `clear_song_metadata`) to bypass RLS.

---

> See `BAND_ROADIE_DOCUMENTATION.md` for full schema details.
