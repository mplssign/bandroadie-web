# ENGINEER REPORT — Band-Scoped Calendar Feed

**Feature Branch:** `feature/band-scoped-calendar-feed`  
**Date:** 2026-03-05  
**Status:** Implementation Complete — Ready for QA

---

## Executive Summary

This release introduces band-scoped calendar subscriptions so each band in BandRoadie can publish its own iCalendar feed.

**Key improvements:**

- Each band now has its own calendar subscription URL
- Calendar feeds now respect the band's timezone
- ICS feeds include proper VTIMEZONE definitions for DST handling
- Membership validation prevents removed users from accessing band calendars
- Legacy all-band feeds remain fully supported

**This resolves two issues in the previous system:**

1. Subscribing to a band calendar returned events for all bands
2. Calendar times could appear incorrect due to UTC conversion

---

## Architecture Overview

```
BandRoadie App
      │
      ▼
Supabase RPC
(get_band_calendar_token)
      │
      ▼
band_calendar_subscriptions
      │
      ▼
Supabase Edge Function
/calendar-feed
      │
      ▼
iCalendar (.ics) response
      │
      ▼
Apple Calendar / Google Calendar / Outlook
```

The app retrieves a band-scoped calendar token through an RPC function. The token is used to request the calendar feed from the Supabase Edge Function. The edge function generates an iCalendar (.ics) document which is consumed by external calendar clients.

---

## Security & Timezone Audit

**Date:** 2026-03-05  
**Scope:** Edge function security, RPC security, ICS timezone correctness

### Membership Check Verification — PASS

The edge function verifies band membership after resolving a band-scoped token:

```ts
const { data: membership } = await supabase
    .from('band_members')
    .select('band_id')
    .eq('user_id', userId)
    .eq('band_id', bandScopedBandId)
    .single();

if (!membership) {
    return new Response("User is no longer a member of this band", { status: 404, ... });
}
```

Equivalent to `SELECT 1 FROM band_members WHERE band_id = $1 AND user_id = $2 LIMIT 1`. Returns 404 if the user has been removed from the band. Token alone is not trusted.

### RPC search_path Verification — PASS

Both SECURITY DEFINER functions include `SET search_path = public`:

- `get_band_calendar_token(p_band_id UUID)` — `SET search_path = public`
- `regenerate_band_calendar_token(p_band_id UUID)` — `SET search_path = public`

This prevents search_path hijacking attacks on SECURITY DEFINER functions.

### Token Lookup Performance Verification — PASS

The band-scoped token lookup queries:

```ts
.from('band_calendar_subscriptions')
.select('user_id, band_id')
.eq('token', token)
.single()
```

This hits the `idx_band_calendar_subs_token` index (created in migration). No unnecessary filters.

The token lookup uses a single indexed equality filter on `band_calendar_subscriptions.token`. This results in an O(log n) index lookup and avoids scanning `band_members` or event tables during token resolution. The index `idx_band_calendar_subs_token` ensures constant-time token resolution even with a large number of subscriptions.

### ICS Timezone Verification — FIXED

| Check                                                | Status                             |
| ---------------------------------------------------- | ---------------------------------- |
| `X-WR-TIMEZONE:{timezone}` header                    | PASS — present                     |
| `VTIMEZONE` block                                    | **FIXED** — was missing, now added |
| Timed events use `DTSTART;TZID={tz}:YYYYMMDDTHHMMSS` | PASS                               |
| All-day events use `DTSTART;VALUE=DATE:YYYYMMDD`     | PASS                               |
| Block-out dates remain all-day                       | PASS                               |
| No `DTSTART:...Z` on timed events                    | PASS                               |

**Issue found:** The ICS output was missing the required `BEGIN:VTIMEZONE...END:VTIMEZONE` component. Per RFC 5545, when `DTSTART;TZID=` references a timezone, the corresponding VTIMEZONE definition must be present in the calendar object. Without it, some calendar clients (notably Outlook) may fail to interpret the timezone correctly.

**Fix applied:** Added a `VTIMEZONE_DEFS` lookup table in the edge function containing proper VTIMEZONE definitions (with STANDARD/DAYLIGHT transition rules including DST) for all 11 supported timezones. The `generateCalendar` function now inserts the matching VTIMEZONE block after the calendar header.

Supported timezones with VTIMEZONE definitions:

- `America/New_York`, `America/Chicago`, `America/Denver`, `America/Los_Angeles`
- `America/Anchorage`, `Pacific/Honolulu`
- `Europe/London`, `Europe/Paris`, `Europe/Berlin`
- `Asia/Tokyo`, `Australia/Sydney`

---

## Files Created

| File                                                          | Purpose                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| `supabase/migrations/20260305000000_band_scoped_calendar.sql` | New table, RPC functions, RLS policies, bands.timezone column |

## Files Modified

| File                                                              | Change                                                                   |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `supabase/functions/calendar-feed/index.ts`                       | Band-scoped token resolution, timezone fix, gig timed events             |
| `lib/features/calendar/calendar_subscription_service.dart`        | Added band-scoped methods and family provider                            |
| `lib/features/calendar/widgets/calendar_subscription_dialog.dart` | Accepts bandId + bandName, uses band-scoped provider                     |
| `lib/features/calendar/calendar_tab_content.dart`                 | Passes activeBandId/bandName to subscription dialog                      |
| `lib/features/calendar/calendar_screen.dart`                      | Passes activeBandId/bandName to subscription dialog                      |
| `lib/app/models/band.dart`                                        | Added `timezone` field to Band model                                     |
| `lib/features/bands/band_form_screen.dart`                        | Added timezone picker (edit mode, admin-gated), timezone in update logic |
| `lib/features/bands/active_band_controller.dart`                  | Preserves timezone field in Band reconstruction                          |

---

## Migration Details

**File:** `supabase/migrations/20260305000000_band_scoped_calendar.sql`

### Table: `band_calendar_subscriptions`

- `id` UUID PRIMARY KEY (gen_random_uuid)
- `user_id` UUID NOT NULL → auth.users(id) ON DELETE CASCADE
- `band_id` UUID NOT NULL → bands(id) ON DELETE CASCADE
- `token` UUID NOT NULL UNIQUE (gen_random_uuid)
- `created_at` TIMESTAMPTZ NOT NULL DEFAULT now()
- UNIQUE(user_id, band_id)
- Index: `idx_band_calendar_subs_token`

### RLS

- Enabled on `band_calendar_subscriptions`
- Policy: `user_id = auth.uid()` for ALL operations

### Column Addition

- `bands.timezone` TEXT NOT NULL DEFAULT 'America/Chicago' (IF NOT EXISTS)

### RPC Functions

1. **`get_band_calendar_token(p_band_id UUID)`** — SECURITY DEFINER
   - Verifies auth + band membership
   - Returns existing token or creates new subscription
2. **`regenerate_band_calendar_token(p_band_id UUID)`** — SECURITY DEFINER
   - Verifies auth + band membership
   - Replaces token via UPSERT, returns new token

---

## Edge Function Changes

**File:** `supabase/functions/calendar-feed/index.ts`

### Token Resolution (dual-path)

1. Check `band_calendar_subscriptions.token` first
2. If found → resolve user_id + band_id, verify membership, get band timezone
3. If not found → fallback to legacy `users.calendar_token` (all-band feed)

### Timezone Fix

- Replaced `combineDateAndTime()` (UTC-based) with `formatLocalDateTime()` / `parseTimeString()` / `defaultEndLocalDateTime()` (local time preserving)
- Rehearsals emit `DTSTART;TZID={timezone}:YYYYMMDDTHHMMSS` instead of `DTSTART:...Z`
- `X-WR-TIMEZONE` set to band's timezone (or 'America/Chicago' for legacy)

### Gig Time Handling

- Gigs with `start_time` → timed events with `DTSTART;TZID={tz}:...`
- Gigs without `start_time` → all-day events (unchanged)
- Default gig duration: 2 hours when no `end_time`

### Calendar Name

- Band-scoped: `X-WR-CALNAME:{BandName}`
- Legacy: `X-WR-CALNAME:BandRoadie - {UserName}`

### Membership Check

- Band-scoped tokens verify user is still a band member before serving feed
- Returns 404 if user has been removed from band

---

## Flutter Changes

### Subscription Service (`calendar_subscription_service.dart`)

- Added `getBandSubscriptionUrl(String bandId)` — calls `get_band_calendar_token` RPC
- Added `regenerateBandToken(String bandId)` — calls `regenerate_band_calendar_token` RPC
- Added `calendarBandSubscriptionUrlProvider` — FutureProvider.family by bandId
- Legacy `calendarSubscriptionUrlProvider` preserved (deprecated)

### Subscription Dialog (`calendar_subscription_dialog.dart`)

- `showCalendarSubscriptionDialog` now requires `bandId` + `bandName` parameters
- Dialog header shows "Subscribe to {BandName} Calendar"
- Watches `calendarBandSubscriptionUrlProvider(bandId)` instead of legacy provider

### Calendar Screens

- `calendar_tab_content.dart` — reads active band and passes bandId/bandName to dialog
- `calendar_screen.dart` — reads active band and passes bandId/bandName to dialog

### Band Model (`band.dart`)

- Added `timezone` field (default: 'America/Chicago')
- `fromJson` parses `timezone` with fallback
- `toJson` includes `timezone`

### Band Form Screen (`band_form_screen.dart`)

- Added timezone state tracking (`_selectedTimezone`, `_initialTimezone`)
- Timezone included in dirty-check logic
- Timezone saved in band update call
- Added `_buildTimezoneSection()` with dropdown of 11 IANA timezone options
- Timezone editing gated to admin via `canEditBandSettings`

### Active Band Controller (`active_band_controller.dart`)

- All Band construction calls now preserve `timezone` field

---

## Verification Steps

### flutter analyze

```
$ flutter analyze
Analyzing bandroadie...
warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19 • dead_code
1 issue found. (ran in 3.6s)
```

- **0 errors** — clean
- 1 pre-existing warning (dead code in lyrics, not related to this feature)

### Post-Migration Verification

```bash
# Verify new table exists
psql -c "SELECT * FROM band_calendar_subscriptions LIMIT 0;"

# Verify bands.timezone column
psql -c "SELECT timezone FROM bands LIMIT 1;"

# Verify RPC functions exist
psql -c "SELECT proname FROM pg_proc WHERE proname IN ('get_band_calendar_token', 'regenerate_band_calendar_token');"
```

### Post-Deploy Verification

```bash
# Test band-scoped token
curl "https://{project}.supabase.co/functions/v1/calendar-feed?token={band_token}"
# Verify: only band events, X-WR-CALNAME is band name, DTSTART uses TZID

# Test legacy token still works
curl "https://{project}.supabase.co/functions/v1/calendar-feed?token={legacy_user_token}"
# Verify: all-band events, X-WR-CALNAME is "BandRoadie - {UserName}"
```

### Manual App Verification

1. Open calendar in Band A → Subscribe → URL contains band-scoped token
2. Switch to Band B → Subscribe → different token
3. Import feed into Apple Calendar → only that band's events appear
4. Event times match BandRoadie app times
5. Band settings → Timezone picker visible for admins only
6. Change timezone → saved on update

---

## Backward Compatibility

- `users.calendar_token` column untouched
- Legacy RPC functions (`get_my_calendar_token`, `regenerate_calendar_token`) untouched
- Edge function falls back to legacy token if band token not found
- Legacy feeds continue working with all-band events

---

## Feed Caching Behavior

Calendar feeds support conditional requests via ETag headers.

Each feed response includes a deterministic SHA-1 ETag derived from event IDs, timestamps, calendar name, and timezone. If the client sends `If-None-Match` and the ETag has not changed, the edge function returns:

**304 Not Modified**

This avoids regenerating the ICS file and significantly reduces load from frequent calendar polling.

Response headers on every calendar feed:

| Header            | Value                                   |
| ----------------- | --------------------------------------- |
| `Content-Type`    | `text/calendar; charset=utf-8`          |
| `Cache-Control`   | `no-cache`                              |
| `ETag`            | Deterministic SHA-1 hash of event state |
| `Last-Modified`   | Current UTC timestamp                   |
| `X-PUBLISHED-TTL` | `PT15M`                                 |

---

## Calendar Client Refresh Behavior

External calendar clients refresh subscribed ICS feeds on their own schedule.

Typical behavior:

| Client          | Refresh Interval      |
| --------------- | --------------------- |
| Apple Calendar  | ~15–60 minutes        |
| Google Calendar | 12–24 hours (default) |
| Outlook         | ~3 hours              |

BandRoadie includes `X-PUBLISHED-TTL: PT15M` to hint a 15-minute refresh interval. Combined with ETag support, clients only download the full feed when event data has actually changed.

---

## Token Revocation Behavior

Band calendar tokens remain in the `band_calendar_subscriptions` table even if a user leaves the band.

However, the edge function performs a membership check on every request before generating the calendar feed.

If the user is no longer a band member:

**HTTP 404** is returned and the calendar client stops receiving updates.

This prevents former members from accessing future band events without requiring explicit token cleanup.

---

## Handoff Notes for QA

- The timezone default is `America/Chicago` — existing bands get this automatically
- The timezone picker only appears in edit mode (not create mode)
- 11 IANA timezone options are provided; additional timezones can be added later
- Block-out dates remain all-day events (no timezone change needed)
- The `calendarSubscriptionUrlProvider` (legacy) is still in the codebase but unused by the dialog

---

### flutter analyze — PASS

```
$ flutter analyze
Analyzing bandroadie...
warning • Dead code • lib/features/lyrics/widgets/lyrics_view_screen.dart:347:19 • dead_code
1 issue found. (ran in 3.9s)
```

0 errors. 1 pre-existing warning (unrelated).
