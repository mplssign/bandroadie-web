# ARCHITECT PLAN — Band-Scoped Calendar Feed

**Feature Branch:** `feature/band-scoped-calendar-feed`  
**Date:** 2026-03-05  
**Status:** Architecture Complete — Ready for Engineer

---

## 1. Problem Summary

BandRoadie provides a "Subscribe to Calendar" link in the calendar view. Two bugs exist:

1. **All-band feed instead of band-scoped feed:** The calendar subscription returns events from every band the user belongs to, not just the band they are currently viewing. There is no way for a user to subscribe to a single band's calendar.

2. **Incorrect event times:** Event times in the ICS feed are wrong due to timezone mishandling. Times stored in the database as local time strings (e.g., `"7:00 PM"`) are treated as UTC by the edge function, causing events to appear shifted by several hours in external calendar apps.

---

## 2. Existing System Analysis

### 2.1 Edge Function: `supabase/functions/calendar-feed/index.ts`

- Accepts a single query parameter: `?token={user_calendar_token}`
- Looks up the user by `calendar_token` in the `users` table
- Fetches ALL bands the user belongs to via `band_members` join
- Queries gigs, rehearsals, and block-out dates across ALL those bands
- Generates a single ICS feed with calendar name `BandRoadie - {UserName}`
- Returns `Content-Type: text/calendar`

### 2.2 Token System

- `users.calendar_token` — a single UUID column per user (migration `20260204_calendar_subscription.sql`)
- RPC `get_my_calendar_token()` — returns or creates the user's token (SECURITY DEFINER)
- RPC `regenerate_calendar_token(p_user_id)` — replaces the token (invalidates old URLs)
- Token is user-scoped, not band-scoped

### 2.3 Subscription Service: `lib/features/calendar/calendar_subscription_service.dart`

- `CalendarSubscriptionService` builds URL: `{base}/calendar-feed?token={token}`
- `calendarSubscriptionUrlProvider` — a `FutureProvider<String?>` (not band-aware)
- No band ID is passed to the service or included in the URL

### 2.4 Subscription UI: `lib/features/calendar/widgets/calendar_subscription_dialog.dart`

- `showCalendarSubscriptionDialog(context, ref)` — takes no band parameter
- Dialog watches `calendarSubscriptionUrlProvider` which is user-scoped
- Invoked from `calendar_tab_content.dart` and `calendar_screen.dart`

### 2.5 Time Storage in Database

- **Gigs:** `date` (DATE), `start_time` (TEXT, e.g. `"7:00 PM"`), `end_time` (TEXT), `load_in_time` (TEXT)
- **Rehearsals:** `date` (DATE), `start_time` (TEXT, e.g. `"7:00 PM"`), `end_time` (TEXT)
- **Block-out dates:** `date` (DATE) — all-day events, no time component
- All time strings are local/display times. No timezone column exists on gigs or rehearsals.

### 2.6 Timezone Bug Root Cause

In the edge function `combineDateAndTime()`:

```typescript
const date = new Date(Date.UTC(year, month - 1, day, hours, minutes, 0));
```

This places local time values (e.g., 19:00 = 7:00 PM) into UTC, so "7:00 PM Central" becomes "7:00 PM UTC" (which is 1:00 PM Central). The ICS output then uses the `Z` suffix (UTC designation), and the calendar header declares `X-WR-TIMEZONE:UTC`. External calendar apps interpret this literally as UTC, shifting the event by the user's timezone offset.

**Gig events** have a separate issue: they are emitted as all-day events (`VALUE=DATE`) regardless of whether they have start/end times, losing time-of-day information entirely.

---

## 3. Root Cause

### Band Scoping

The edge function queries all bands for the user because the token identifies only the user, and no band filter is applied. The URL has no band parameter.

### Timezone

`combineDateAndTime()` incorrectly constructs a UTC datetime from values that are actually local times. Since BandRoadie does not store an explicit timezone per event or per band, the system must adopt a convention (see Proposed Solution).

---

## 4. Proposed Solution

### 4.1 Band-Scoped Calendar Tokens

Introduce a new table `band_calendar_subscriptions` that maps a unique token to a (user, band) pair. Each subscription generates its own secure URL. Users can subscribe to multiple bands independently.

**New URL format:**

```
/calendar-feed?token={band_calendar_token}
```

The token alone identifies both the user AND the band — no additional query parameters are needed and no band ID is exposed in the URL.

### 4.2 Timezone Fix

Add a `timezone` column to the `bands` table (e.g., `"America/Chicago"`). This is the most natural scope because a band's events generally occur in one timezone.

In the edge function:

- Look up the band's timezone when resolving the token
- Generate VTIMEZONE components in the ICS output for the band's timezone
- Emit `DTSTART;TZID={timezone}` instead of `DTSTART:...Z` for timed events
- Set `X-WR-TIMEZONE` to the band's timezone

This ensures external calendar apps display events at the correct local time.

### 4.3 Gig Time Handling

Gigs with `start_time` / `end_time` should be emitted as timed events (not all-day). Only gigs without time information should remain all-day events. This matches user expectations — a gig at "7:00 PM" should appear at 7:00 PM on the calendar.

### 4.4 Backward Compatibility

- The existing `users.calendar_token` column and user-scoped RPC functions remain untouched for now (they can be deprecated later)
- The edge function will support the new band-scoped tokens. If a legacy user token is provided, it can either return a 404 with a message to re-subscribe, or continue returning the all-band feed. Recommended: **continue supporting legacy tokens** as a transitional measure, but emit a deprecation note.
- The UI will switch to generating band-scoped URLs immediately.

---

## 5. Database Impact

### 5.1 New Table: `band_calendar_subscriptions`

```sql
CREATE TABLE band_calendar_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    band_id UUID NOT NULL REFERENCES bands(id) ON DELETE CASCADE,
    token UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id, band_id)
);

CREATE INDEX idx_band_calendar_subs_token ON band_calendar_subscriptions(token);
```

### 5.2 New Column on `bands`

```sql
ALTER TABLE bands ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/Chicago';
```

Default to `'America/Chicago'` since the majority of current users are US-Central. The UI should allow band admins to change this in band settings.

### 5.3 No Changes to Existing Tables

- `users.calendar_token` remains (backward compatibility)
- No changes to `gigs`, `rehearsals`, or `block_dates` schema

---

## 6. RLS / RPC Changes

### 6.1 RLS on `band_calendar_subscriptions`

```sql
-- Users can read/insert/delete their own subscriptions
ALTER TABLE band_calendar_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own calendar subscriptions"
    ON band_calendar_subscriptions
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
```

### 6.2 New RPC: `get_band_calendar_token(p_band_id UUID)`

SECURITY DEFINER function that:

1. Checks the user is a member of the band
2. Returns existing token from `band_calendar_subscriptions` if one exists
3. Creates a new row and returns the token if none exists

### 6.3 New RPC: `regenerate_band_calendar_token(p_band_id UUID)`

SECURITY DEFINER function that:

1. Checks the user is a member of the band
2. Generates a new token, replacing the existing one
3. Returns the new token

### 6.4 RLS on `bands.timezone`

No new RLS needed — the `bands` table already has RLS. The `timezone` column will be readable/writable under existing band member policies. Only admins/managers should update it (enforced at app level via existing role checks).

### 6.5 Edge Function Token Lookup

The edge function uses `SUPABASE_SERVICE_ROLE_KEY` (bypasses RLS) to look up tokens. The new flow:

1. First, check `band_calendar_subscriptions.token`
2. If found → return events for that specific band only
3. If not found → fall back to checking `users.calendar_token` (legacy support)

---

## 7. Flutter Architecture Changes

### 7.1 `CalendarSubscriptionService` Changes

- Add method `getBandSubscriptionUrl(String bandId)` that calls `get_band_calendar_token` RPC
- Add method `regenerateBandToken(String bandId)` that calls `regenerate_band_calendar_token` RPC
- Update `_feedBaseUrl` usage to construct band-scoped URLs

### 7.2 Provider Changes

- Replace `calendarSubscriptionUrlProvider` (user-scoped FutureProvider) with a family provider:
  `calendarSubscriptionUrlProvider(String bandId)` — so URLs are generated per-band
- The dialog and tab content will pass the active band ID

### 7.3 UI Changes

- `showCalendarSubscriptionDialog` will accept the active band ID
- Dialog header will show band name (e.g., "Subscribe to {BandName} Calendar")
- Calendar tab content passes `activeBandId` to the dialog

### 7.4 Band Settings (Timezone)

- Add a timezone picker to the band settings/edit screen
- Use a dropdown with common IANA timezone identifiers
- Only users with admin/manager role can change the timezone

---

## 8. Exact Files to Create

| File                                                          | Purpose                                                       |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| `supabase/migrations/20260305000000_band_scoped_calendar.sql` | New table, RPC functions, RLS policies, bands.timezone column |

---

## 9. Exact Files to Modify

| File                                                              | Change                                                                                   |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `supabase/functions/calendar-feed/index.ts`                       | Add band-scoped token lookup, fix timezone handling, emit VTIMEZONE, fix gig time events |
| `lib/features/calendar/calendar_subscription_service.dart`        | Add band-scoped methods, update providers to family pattern                              |
| `lib/features/calendar/widgets/calendar_subscription_dialog.dart` | Accept bandId + bandName, update provider reference, show band name in header            |
| `lib/features/calendar/calendar_tab_content.dart`                 | Pass activeBandId to `showCalendarSubscriptionDialog`                                    |
| `lib/features/calendar/calendar_screen.dart`                      | Pass activeBandId to `showCalendarSubscriptionDialog`                                    |
| `lib/app/models/band.dart` (if band model exists)                 | Add `timezone` field to Band model                                                       |
| Band settings/edit screen (identify exact file)                   | Add timezone picker UI                                                                   |

---

## 10. Risks / Edge Cases

### 10.1 Timezone Default

- Existing bands will get `'America/Chicago'` as default. If a band operates in a different timezone, their calendar feed will be wrong until an admin updates the timezone setting.
- **Mitigation:** On first access to the new subscription flow, prompt users to confirm their band's timezone. Or display a note in the subscription dialog if timezone hasn't been explicitly set.

### 10.2 Legacy Subscriptions

- Users with existing calendar subscriptions (using old user-scoped URLs) will continue receiving all-band feeds until they re-subscribe.
- **Mitigation:** Legacy tokens continue working. UI should inform users to re-subscribe for band-specific feeds.

### 10.3 Token Security

- Tokens are UUIDs — unguessable but not cryptographically signed. This matches the existing pattern.
- Tokens grant read-only access to event data (names, locations, times) for a single band.
- If a user is removed from a band, their subscription row should be deleted via `CASCADE` on `band_members` deletion. **Risk:** The FK is on `bands(id)` and `auth.users(id)`, not `band_members`. A separate cleanup trigger or check in the edge function is needed.
- **Mitigation:** In the edge function, verify the user is still a member of the band when serving the feed. If not, return 404.

### 10.4 External Calendar Refresh Lag

- External calendar apps (Apple Calendar, Google Calendar) cache ICS feeds and refresh on their own schedule (15 minutes to 24 hours). Users cannot force an immediate refresh.
- Already documented in the subscription dialog notes.

### 10.5 Band Deletion

- If a band is deleted, `band_calendar_subscriptions` rows cascade-delete, and the token becomes invalid. Edge function returns 404. External calendars will show stale data until next refresh, then stop updating.

### 10.6 DST Transitions

- Using IANA timezone identifiers (e.g., `America/Chicago`) with proper VTIMEZONE components handles DST transitions correctly. The ICS standard has well-defined rules for this.

---

## 11. Verification Plan

### After Migration

```bash
# Verify new table exists
psql -c "SELECT * FROM band_calendar_subscriptions LIMIT 0;"

# Verify bands.timezone column
psql -c "SELECT timezone FROM bands LIMIT 1;"

# Verify RPC functions exist
psql -c "SELECT proname FROM pg_proc WHERE proname IN ('get_band_calendar_token', 'regenerate_band_calendar_token');"
```

### After Edge Function Update

```bash
# Test with a band-scoped token
curl "https://{project}.supabase.co/functions/v1/calendar-feed?token={band_token}"

# Verify:
# 1. Only events from the specific band appear
# 2. X-WR-CALNAME matches the band name
# 3. VTIMEZONE component is present
# 4. DTSTART uses TZID= format for timed events
# 5. Rehearsal times match what's in the app
# 6. Gigs with start_time appear as timed events

# Test legacy token still works
curl "https://{project}.supabase.co/functions/v1/calendar-feed?token={legacy_user_token}"
```

### After Flutter Changes

```bash
flutter analyze

# Manual verification:
# 1. Open calendar in Band A → Subscribe → URL contains band-scoped token
# 2. Switch to Band B → Subscribe → URL contains DIFFERENT token
# 3. Import Band A feed into Apple Calendar → only Band A events appear
# 4. Import Band B feed into Google Calendar → only Band B events appear
# 5. Calendar name shows band name, not user name
# 6. Event times match BandRoadie app times exactly
# 7. Regenerate token → old URL stops working, new URL works
```

---

## 12. Engineer Task Breakdown

### Task 1: Database Migration

- Create `band_calendar_subscriptions` table with RLS
- Add `timezone` column to `bands` table
- Create `get_band_calendar_token(p_band_id)` RPC
- Create `regenerate_band_calendar_token(p_band_id)` RPC
- **File:** `supabase/migrations/20260305000000_band_scoped_calendar.sql`

### Task 2: Edge Function — Band-Scoped Token Resolution

- Update token lookup to check `band_calendar_subscriptions` first
- Filter gigs, rehearsals, block-outs to the specific band
- Fall back to legacy `users.calendar_token` if band token not found
- Set `X-WR-CALNAME` to band name (not user name) for band-scoped feeds
- Verify user is still a band member before serving feed
- **File:** `supabase/functions/calendar-feed/index.ts`

### Task 3: Edge Function — Timezone Fix

- Look up `bands.timezone` for the target band
- Replace `X-WR-TIMEZONE:UTC` with the band's timezone
- Generate proper VTIMEZONE component for the band's IANA timezone
- Change rehearsal DTSTART/DTEND from `...Z` to `DTSTART;TZID={tz}:YYYYMMDDTHHMMSS`
- Change gig events with start_time/end_time to timed events with TZID
- Keep gigs without times as all-day events
- Keep block-out dates as all-day events (no timezone change needed)
- Remove `combineDateAndTime()` UTC conversion — use local time directly
- **File:** `supabase/functions/calendar-feed/index.ts`

### Task 4: Flutter — Update Subscription Service & Providers

- Add `getBandSubscriptionUrl(String bandId)` method
- Add `regenerateBandToken(String bandId)` method
- Create family provider: `calendarSubscriptionUrlProvider(String bandId)`
- Deprecate (but keep) existing user-scoped provider
- **File:** `lib/features/calendar/calendar_subscription_service.dart`

### Task 5: Flutter — Update Subscription Dialog & Calendar Screens

- Update `showCalendarSubscriptionDialog` to accept `bandId` and `bandName`
- Update dialog to watch band-scoped provider
- Update dialog header to show band name
- Update `calendar_tab_content.dart` to pass active band context
- Update `calendar_screen.dart` to pass active band context
- **Files:** `calendar_subscription_dialog.dart`, `calendar_tab_content.dart`, `calendar_screen.dart`

### Task 6: Flutter — Band Timezone Setting

- Add `timezone` field to Band model
- Add timezone picker to band settings/edit UI
- Gate timezone editing to admin/manager roles
- **Files:** Band model file, band settings/edit screen

---

## 13. Rollout / Migration Strategy

### Phase 1: Database Migration (Non-Breaking)

- Deploy migration adding `band_calendar_subscriptions` table and `bands.timezone` column
- Existing data is not affected — `timezone` defaults to `'America/Chicago'`
- Legacy `users.calendar_token` untouched

### Phase 2: Edge Function Update

- Deploy updated edge function with dual-path token resolution
- Legacy user tokens continue working (all-band feed, still UTC — unchanged behavior)
- New band-scoped tokens serve band-filtered, timezone-correct feeds
- **Zero downtime, no breaking changes**

### Phase 3: Flutter App Update

- Deploy app update with band-scoped subscription UI
- New subscriptions automatically use band-scoped tokens
- Users with old subscriptions see unchanged behavior until they re-subscribe
- Subscription dialog can include a note: "Re-subscribe for band-specific events"

### Phase 4: Future Cleanup (Out of Scope)

- After sufficient adoption, consider deprecating legacy user-scoped tokens
- Remove fallback logic from edge function
- Drop `users.calendar_token` column

---

## 14. Out of Scope

- Deprecating or removing `users.calendar_token` (legacy support preserved)
- Per-event timezone support (band-level timezone is sufficient)
- Push-based calendar sync (webcal is pull-based by design)
- Calendar write access (feeds are read-only)
- Automated timezone detection based on user location
- Multi-timezone bands (a band has one timezone)
- Notification when calendar feed URL changes
- Calendar feed analytics or usage tracking
- UI for managing multiple band subscriptions in a single view
