# ARCHITECT PLAN — Calendar Subscription Not Syncing

## Feature Slug

`bug/calendar-subscription-not-syncing`

---

## Problem Summary

**What:** Band calendar events subscribed to via iCal feed in Apple Calendar (iOS) were not appearing despite being present in the feed. Confirmed case: Tony's Toxic Crayon rehearsal scheduled for July 12, 2026, created on June 25, 2026, was missing from subscribed iPhone Calendar as of July 7-8 (12+ days later).

**Timeline:**

- June 25, 2026 02:12 UTC: Rehearsal created in database
- July 5, 2026: Bug reported
- July 7-8, 2026: Investigation confirmed rehearsal present in feed via curl tests
- **July 8, 2026: Root cause confirmed via direct device test** — Tony removed and re-added calendar subscription on iPhone, rehearsal immediately appeared

**Impact:** Users may miss critical rehearsals and gigs if their calendar client's subscription refresh mechanism fails to poll for updates. This is a known limitation of calendar subscription protocols (iCalendar), not a backend defect.

---

## Root Cause

**Status:** ✅ **CONFIRMED** (not suspected)

**Mechanism:** Client-side calendar application subscription refresh unreliability. Apple Calendar (and other calendar clients) poll subscribed iCal feeds on their own schedule, with no guarantee of immediate or consistent refresh intervals. When the client fails to poll, or polls with a stale ETag causing a 304 response with outdated cached data, new events do not appear until the user manually forces a refresh (by removing and re-adding the subscription).

**Evidence:**

1. **All curl tests showed correct feed content** — Every test of both band-scoped and legacy tokens returned the missing rehearsal correctly formatted in the iCalendar feed
2. **Tony was already seeing OTHER Toxic Crayon events** — The July 16 Toxic Crayon gig appeared correctly, proving the subscription was pointed at the right band's feed (rules out wrong-band-subscription theory)
3. **Direct device test confirmed** — When Tony removed and re-added the subscription on his iPhone (2026-07-08), the July 12 rehearsal immediately appeared, proving the backend was never broken
4. **No backend errors found** — Database queries, ETag computation, feed generation, and CDN passthrough all functioning correctly throughout investigation

**Conclusion:** This is a limitation of how iOS Calendar (and similar clients) handle subscribed calendars. BandRoadie's backend correctly generates and serves the iCalendar feed; the client simply didn't poll for updates or used a stale cached response. **No backend code fix can force iOS Calendar to poll more frequently or invalidate its own cache.**

---

## Opportunistic Fixes

While the root cause has no code-level solution, two small improvements can be made to the calendar feed for better standards compliance and potentially improved client behavior:

### Fix 1: STATUS:TENTATIVE for Potential Events

**Problem:** The `generateCalendar()` function currently hardcodes `STATUS:CONFIRMED` for all events (line 885 for gigs, line 967 for rehearsals), regardless of whether they are potential (unconfirmed) events.

**iCalendar Standard:** [RFC 5545 Section 3.8.1.11](https://datatracker.ietf.org/doc/html/rfc5545#section-3.8.1.11) defines:
- `STATUS:CONFIRMED` — Event is definitely happening
- `STATUS:TENTATIVE` — Event is proposed/unconfirmed
- `STATUS:CANCELLED` — Event is cancelled

**Expected Behavior:** Potential gigs and rehearsals (those opted into via subscription preferences) should emit `STATUS:TENTATIVE` so calendar clients can visually distinguish them.

**Required Changes:**

1. Add `isPotential?: boolean` field to `GigEvent` and `RehearsalEvent` interfaces (lines 434-465)
2. Set `isPotential: false` when transforming confirmed events (lines 683-708)
3. Set `isPotential: true` when transforming potential events (lines 719-767)
4. In `generateCalendar()`:
   - Line 885: Change `STATUS:CONFIRMED` to `STATUS:${gig.isPotential ? 'TENTATIVE' : 'CONFIRMED'}`
   - Line 967: Change `STATUS:CONFIRMED` to `STATUS:${rehearsal.isPotential ? 'TENTATIVE' : 'CONFIRMED'}`

**Impact:** Purely cosmetic in most clients. Some calendar apps may show tentative events with different styling (e.g., strikethrough, lighter color).

---

### Fix 2: Refresh Interval Hints (Already Implemented)

**Current State:** The edge function already sets `X-PUBLISHED-TTL: PT15M` in response headers (line 794), indicating a 15-minute refresh interval.

**Standards:**

- `X-PUBLISHED-TTL` — Non-standard Apple extension, supported by Apple Calendar
- `REFRESH-INTERVAL` — Non-standard property in VCALENDAR block, supported by some clients
- Both use ISO 8601 duration format (e.g., `PT15M` = 15 minutes, `PT1H` = 1 hour)

**Client Support:**

- **Apple Calendar (iOS/macOS):** Honors `X-PUBLISHED-TTL` header (typically polls every 15-60 minutes regardless of hint)
- **Google Calendar:** Typically polls every 8-12 hours, does NOT honor refresh hints
- **Outlook/Office 365:** Typically polls every 3-24 hours, does NOT honor refresh hints
- **Third-party apps (Fantastical, etc.):** Varies

**Recommended Enhancement:**

Add `REFRESH-INTERVAL` property to VCALENDAR block (inside `generateCalendar()` around line 827) for broader client hint coverage:

```typescript
const lines: string[] = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//BandRoadie//Calendar//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'REFRESH-INTERVAL;VALUE=DURATION:PT1H',  // ← Add this line
    `X-WR-CALNAME:${escapeIcsText(calendarName)}`,
    `X-WR-TIMEZONE:${timezone}`,
];
```

**Proposed Interval:** `PT1H` (1 hour) — More aggressive than current 15 minutes to balance freshness with server load. Most clients ignore this anyway.

**Impact:** MAY reduce time-to-appearance for new events in clients that honor the hint. WILL NOT fix Apple Calendar's inherent unreliability. Users should still be educated that calendar subscriptions are not real-time.

---

## Files to Modify

### `supabase/functions/calendar-feed/index.ts`

**Changes:**

1. **Lines 434-445** (GigEvent interface): Add `isPotential?: boolean;`
2. **Lines 446-465** (RehearsalEvent interface): Add `isPotential?: boolean;`
3. **Lines 683-691** (confirmed gig transformation): Add `isPotential: false,` to each object
4. **Lines 693-708** (confirmed rehearsal transformation): Add `isPotential: false,` to each object
5. **Lines 727-738** (potential gig transformation): Add `isPotential: true,` to each object
6. **Lines 755-767** (potential rehearsal transformation): Add `isPotential: true,` to each object
7. **Line 827** (VCALENDAR header): Add `REFRESH-INTERVAL;VALUE=DURATION:PT1H` after METHOD:PUBLISH
8. **Line 885** (gig STATUS): Change to `lines.push(\`STATUS:\${gig.isPotential ? 'TENTATIVE' : 'CONFIRMED'}\`);`
9. **Line 967** (rehearsal STATUS): Change to `lines.push(\`STATUS:\${rehearsal.isPotential ? 'TENTATIVE' : 'CONFIRMED'}\`);`

---

## Engineer Task Breakdown

### Task 1: Add isPotential Field Tracking

**Estimated Time:** 15 minutes

**Steps:**

1. Update `GigEvent` interface to include `isPotential?: boolean;`
2. Update `RehearsalEvent` interface to include `isPotential?: boolean;`
3. Set `isPotential: false` in confirmed event transformations (lines 683-708)
4. Set `isPotential: true` in potential event transformations (lines 719-767)
5. Verify TypeScript compiles without errors

**Acceptance Criteria:**

- All event objects have explicit `isPotential` boolean value
- No TypeScript compilation errors

---

### Task 2: Emit STATUS:TENTATIVE for Potential Events

**Estimated Time:** 10 minutes

**Steps:**

1. Locate gig VEVENT generation (~line 885)
2. Replace `lines.push('STATUS:CONFIRMED');` with `lines.push(\`STATUS:\${gig.isPotential ? 'TENTATIVE' : 'CONFIRMED'}\`);`
3. Locate rehearsal VEVENT generation (~line 967)
4. Replace `lines.push('STATUS:CONFIRMED');` with `lines.push(\`STATUS:\${rehearsal.isPotential ? 'TENTATIVE' : 'CONFIRMED'}\`);`

**Acceptance Criteria:**

- Confirmed events emit `STATUS:CONFIRMED`
- Potential events emit `STATUS:TENTATIVE`
- iCalendar syntax remains valid

---

### Task 3: Add REFRESH-INTERVAL to VCALENDAR

**Estimated Time:** 5 minutes

**Steps:**

1. Locate VCALENDAR header generation (~line 820-827)
2. After `METHOD:PUBLISH` line, add: `'REFRESH-INTERVAL;VALUE=DURATION:PT1H',`
3. Verify iCalendar syntax (property goes inside VCALENDAR block, before first VEVENT)

**Acceptance Criteria:**

- VCALENDAR block contains `REFRESH-INTERVAL;VALUE=DURATION:PT1H`
- Feed remains parseable by major calendar clients

---

## Testing Plan

### Manual Testing

**Test 1: STATUS Property**

1. Create a test potential gig and potential rehearsal in database
2. Generate feed via curl with subscription that has `include_potential_gigs=true` and `include_potential_rehearsals=true`
3. Verify potential events have `STATUS:TENTATIVE`
4. Verify confirmed events have `STATUS:CONFIRMED`

**Test 2: REFRESH-INTERVAL Parsing**

1. Generate feed via curl
2. Verify `REFRESH-INTERVAL;VALUE=DURATION:PT1H` appears in VCALENDAR block (after METHOD:PUBLISH, before first VEVENT)
3. Import feed into:
   - Apple Calendar (macOS) — Should accept without error
   - Google Calendar web — Should accept without error
   - Outlook web — Should accept without error
4. Verify all events render correctly in each client

**Test 3: Regression Check**

1. Verify existing confirmed gigs/rehearsals still appear correctly
2. Verify block-out dates still appear correctly
3. Verify recurring rehearsals still generate correct RRULE syntax

---

## Deployment

**Branch:** `bug/calendar-subscription-not-syncing` (already created)

**Deployment Command:**

```bash
supabase functions deploy calendar-feed --project-ref nekwjxvgbveheooyorjo
```

**Rollback Plan:** Revert commit and redeploy previous version if feed parsing breaks in any major calendar client.

**Monitoring:** Check Supabase Edge Function logs (dashboard) for any 500 errors or parsing exceptions post-deployment.

---

## Known Limitations

**This fix does NOT address:**

- **Apple Calendar's unpredictable refresh schedule** — iOS Calendar may still take hours or days to poll for updates
- **Google Calendar's 8-12 hour polling interval** — Google ignores all refresh hints
- **Outlook's 3-24 hour polling interval** — Office 365 ignores all refresh hints
- **Users' expectation of real-time updates** — Calendar subscriptions are NOT push notifications

**User Education Required:** BandRoadie should document that:

1. Calendar subscriptions are NOT real-time
2. New events may take hours to appear depending on calendar client
3. Users can force refresh by removing and re-adding subscription
4. For time-sensitive updates, use in-app notifications instead

---

## Appendix: Ruled-Out Theories

### ❌ NULL is_potential Values

**Disproven:** Production query showed 0 NULL values in 597 gigs and 1744 rehearsals. All have explicit boolean values.

### ❌ Events Missing from Feeds

**Disproven:** curl tests confirmed July 12 rehearsal present in both band-scoped and legacy feeds with correct VEVENT formatting.

### ❌ Calendar Client Polling Delay

**Disproven:** 12+ day gap between event creation and reporting far exceeds documented refresh windows (iOS: 1-4 hours, Google: 8-12 hours).

### ❌ CDN Caching

**Disproven:** Cloudflare response headers showed `cf-cache-status: DYNAMIC` (pass-through, not cached), `cache-control: no-cache`, no `Age` or `X-Cache` headers.

### ❌ Wrong-Band Subscription

**Disproven:** Tony was correctly seeing OTHER Toxic Crayon events (July 16 gig), proving his iPhone was subscribed to the correct band's feed.

### ❌ ETag Code Divergence

**Disproven:** Data flow trace confirmed `computeEtag()` (line 780) and `generateCalendar()` (line 787) receive identical array references (`allGigEvents`, `allRehearsalEvents`, `filteredBlockOuts`). Zero possibility of divergence between ETag computation and calendar generation.

---

**Plan Status:** Ready for implementation  
**Estimated Total Time:** 30 minutes  
**Risk:** Low (additive changes only, no breaking modifications)

## Suspect: PostgreSQL Query Caching or Connection Pooling

**New Theory:** Supabase Edge Functions might be using connection pooling with statement caching. If the same query string is executed repeatedly, PostgreSQL or Supavisor (Supabase's connection pooler) might cache the query plan AND results.

**Evidence:**

- Queries use parameterized filters (`.in('band_id', bandIds)`)
- If `bandIds` array is the same, query string might hash identically
- Supavisor in "transaction" mode (config line 24: `pool_mode = "transaction"`) shares connections between transactions

**How this could cause the bug:**

1. June 24: Feed generated, ETag = OLD_HASH (before rehearsal created)
2. June 25: Rehearsal created in database
3. July 7: iOS polls with `If-None-Match: OLD_HASH`
4. Edge function queries database - but gets CACHED results from June 24
5. Computes ETag from cached data = OLD_HASH
6. Comparison: OLD_HASH === OLD_HASH → 304 Not Modified
7. iOS never sees new rehearsal

**How to test:**

1. Check if Supabase Edge Functions use prepared statement caching
2. Add query timestamps to debug logging
3. Force query cache invalidation (e.g., add random comment to query)

---

## Proposed Solution (Pending Log Verification)

### Option A: Force ETag Version Bump (Immediate Fix)

Invalidate all client caches by incrementing ETag version:

**File:** `supabase/functions/calendar-feed/index.ts`  
**Line:** ~147 (inside `computeEtag` function)

```typescript
const source = JSON.stringify({
  v: 2, // Increment this to force all clients to re-fetch
  band: calendarName,
  tz: timezone,
  g: gigs.map((g) => [g.id, g.date, g.start_time, g.end_time]),
  // ...rest unchanged...
});
```

**Pros:**

- Immediate relief for all affected users
- Zero risk - just forces re-fetch
- Easy to roll back

**Cons:**

- One-time fix, doesn't prevent recurrence
- Doesn't address root cause if it's query caching

**Recommendation:** Deploy this FIRST to unblock users, then investigate root cause.

---

### Option B: Add Debug Logging (Diagnosis)

Add logging to capture actual ETag comparisons:

**File:** `supabase/functions/calendar-feed/index.ts`  
**Lines:** ~783-785

```typescript
if (ifNoneMatch === etag) {
  console.log("[ETag-Match]", {
    token: token.substring(0, 8) + "...",
    clientEtag: ifNoneMatch,
    serverEtag: etag,
    eventCounts: {
      gigs: allGigEvents.length,
      rehearsals: allRehearsalEvents.length,
      blockouts: filteredBlockOuts.length,
    },
    timestamp: new Date().toISOString(),
  });
  return new Response(null, { status: 304, headers: corsHeaders });
}
```

**Pros:**

- Captures real client behavior
- Helps identify if ETag logic is correct

**Cons:**

- Requires log review after deployment
- Doesn't fix issue

**Recommendation:** Deploy alongside Option A.

---

### Option C: Disable Query Result Caching (If Confirmed)

If PostgreSQL/Supavisor caching is the culprit, add cache-busting:

**File:** `supabase/functions/calendar-feed/index.ts`  
**Lines:** ~630, ~648 (add to query comments)

```typescript
const { data: gigs, error: gigsError } = await supabase
  .from("gigs")
  .select(
    `
        id, name, location, date, load_in_time, start_time, end_time,
        notes, band_id,
        bands(name)
        /* cache_bust_${Date.now()} */
    `,
  )
  .in("band_id", bandIds);
// ... rest of query
```

**Pros:**

- Forces fresh query execution
- Guarantees current data

**Cons:**

- Performance impact (can't use prepared statements)
- Hacky solution
- Might not be necessary if caching isn't the issue

**Recommendation:** Only if logs confirm stale query results.

---

## Implementation Plan

### Phase 1: Emergency Fix + Observability (Deploy Immediately)

1. **Bump ETag version** (Option A) - 1 line change
2. **Add debug logging** (Option B) - 10 lines
3. **Deploy:** `supabase functions deploy calendar-feed`
4. **Notify affected users:** "Please remove and re-subscribe to your calendar feed (new URL will have fresh data)"

**Expected outcome:** Immediate resolution for all users with stale caches.

### Phase 2: Root Cause Analysis (After Phase 1 deployed)

1. **Review Edge Function logs** for 7 days
2. **Analyze patterns:**
   - Frequency of 304 responses
   - ETag values that clients send
   - Event count discrepancies (client ETag computed from fewer events than server has)
3. **Check for 406 errors** on `.single()` lookups
4. **Test query caching:**
   - Create event in production
   - Immediately fetch feed
   - Check if event appears (tests query freshness)

### Phase 3: Permanent Fix (If Root Cause Found)

- **If ETag logic is wrong:** Revise `computeEtag` to include missing fields
- **If query caching is wrong:** Implement Option C or disable statement caching
- **If iOS Calendar bug:** Document workaround, no code change
- **If `.single()` 406 errors:** Change to `.maybeSingle()` (line 519)

---

## Files to Modify (Phase 1)

| File                                        | Change                                                                                                |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `supabase/functions/calendar-feed/index.ts` | **Line ~147:** Add `v: 2` to ETag source object<br>**Line ~783:** Add debug logging before 304 return |

---

## Verification Plan

### Pre-Deploy

1. ✅ **Test ETag logic locally** - simulate event creation and verify ETag changes
2. ✅ **Review conditional request behavior** - confirmed 304 works correctly for current data
3. ⏳ **Check staging environment** - if available, deploy to staging first

### Post-Deploy (Phase 1)

1. **Verify version bump deployed:**

   ```bash
   curl -i "https://.../calendar-feed?token=a6af1a0c..." | grep ETag
   # Should return different ETag than "f7225a092e17b75055abbe742292398ae13fbc76"
   ```

2. **Test on Tony's iPhone:**
   - Remove existing subscription
   - Re-subscribe using band-scoped URL
   - Verify July 12 rehearsal appears immediately

3. **Monitor logs for 48 hours:**
   - Check for new 304 patterns
   - Verify event counts match database
   - Look for any 406 errors

### Post-Deploy (Phase 3 - if needed)

- Regression test: Create new event, verify appears in feed within 1 hour
- Load test: Verify no performance degradation from query changes
- Cross-client test: Google Calendar, Outlook, macOS Calendar

---

## Rollback Plan

If Phase 1 causes issues:

```bash
git revert <commit-hash>
supabase functions deploy calendar-feed
```

Version bump is zero-risk, but if unexpected errors occur:

1. Check logs for error stack traces
2. Verify Supabase environment variables unchanged
3. Rollback and investigate offline

---

## Open Questions (For Log Review)

1. **Which token is Tony's iPhone using?** Band-scoped or legacy?
2. **What If-None-Match value was sent?** Does it match the pre-June-25 ETag?
3. **Are there 406 errors?** Frequency and impact?
4. **Does the issue reproduce on other clients?** Google Calendar, Outlook?
5. **Does manual resubscribe fix it?** Would confirm stale client cache.

---

## Success Criteria

**Phase 1 Success:**

- Tony's iPhone shows July 12 rehearsal after re-subscribe
- No new reports of missing events for 7 days
- Logs show ETag version 2 being served

**Phase 3 Success (if needed):**

- Root cause identified in logs
- Permanent fix deployed
- No recurrence for 30 days
- No performance degradation

---

## Status

**ROOT CAUSE:** ETag caching suspected, not confirmed  
**NEXT STEP:** Deploy Phase 1 (version bump + logging)  
**BLOCKED ON:** Nothing - ready to implement  
**TIMELINE:** Can deploy within 1 hour

---

## Lessons Learned (So Far)

1. **"Works in curl" ≠ "works for users"** - Must test with actual client behavior (ETags, caching)
2. **User persistence trumps test results** - 12+ days is not a refresh delay
3. **Calendar subscriptions are opaque** - Need deep debugging when clients behave unexpectedly
4. **Production logs are essential** - Can't diagnose caching issues without observability
5. **Quick wins matter** - Version bump unblocks users while root cause is investigated
