// supabase/functions/calendar-feed/index.ts
// Edge function to generate iCalendar (.ics) feed for calendar subscriptions
//
// URL format: /calendar-feed?token={user_calendar_token}
// Returns: text/calendar (.ics) content
//
// Includes: Confirmed Gigs, Rehearsals, and (optionally) Block-out dates.
// Potential gigs are never included. Feed content is controlled per-subscriber
// via include_gigs / include_rehearsals / include_blockouts on band_calendar_subscriptions.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Get environment variables (checked at runtime)
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// iCalendar date format: YYYYMMDD or YYYYMMDDTHHMMSSZ
function formatIcsDate(date: string, includeTime = false): string {
    const d = new Date(date);
    const year = d.getUTCFullYear();
    const month = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');

    if (includeTime) {
        const hours = String(d.getUTCHours()).padStart(2, '0');
        const minutes = String(d.getUTCMinutes()).padStart(2, '0');
        const seconds = String(d.getUTCSeconds()).padStart(2, '0');
        return `${year}${month}${day}T${hours}${minutes}${seconds}Z`;
    }

    return `${year}${month}${day}`;
}

// Format date as all-day event (VALUE=DATE)
function formatAllDayDate(date: string): string {
    const d = new Date(date);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}${month}${day}`;
}

// Get next day for all-day event end date (exclusive)
function getNextDay(date: string): string {
    const d = new Date(date);
    d.setDate(d.getDate() + 1);
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}${month}${day}`;
}

// Escape special characters for iCalendar text
function escapeIcsText(text: string): string {
    if (!text) return '';
    return text
        .replace(/\\/g, '\\\\')
        .replace(/;/g, '\\;')
        .replace(/,/g, '\\,')
        .replace(/\n/g, '\\n');
}

// Fold long lines per iCalendar spec (max 75 octets per line)
function foldLine(line: string): string {
    const maxLength = 75;
    if (line.length <= maxLength) return line;

    let result = line.substring(0, maxLength);
    let remaining = line.substring(maxLength);

    while (remaining.length > 0) {
        const chunk = remaining.substring(0, maxLength - 1);
        result += '\r\n ' + chunk;
        remaining = remaining.substring(maxLength - 1);
    }

    return result;
}

// Parse time string like "7:00 PM" or "19:00" into { hours, minutes }
function parseTimeString(timeStr: string): { hours: number; minutes: number } {
    let hours = 0;
    let minutes = 0;

    // Try to match "H:MM AM/PM" or "HH:MM AM/PM"
    const amPmMatch = timeStr.match(/(\d{1,2}):(\d{2})\s*(AM|PM)/i);
    if (amPmMatch) {
        hours = parseInt(amPmMatch[1], 10);
        minutes = parseInt(amPmMatch[2], 10);
        const isPM = amPmMatch[3].toUpperCase() === 'PM';
        if (isPM && hours !== 12) hours += 12;
        if (!isPM && hours === 12) hours = 0;
    } else {
        // Try 24-hour format "HH:MM"
        const match24 = timeStr.match(/(\d{1,2}):(\d{2})/);
        if (match24) {
            hours = parseInt(match24[1], 10);
            minutes = parseInt(match24[2], 10);
        }
    }

    return { hours, minutes };
}

// Format a date string + time string as a local iCal datetime: YYYYMMDDTHHMMSS
function formatLocalDateTime(dateStr: string, timeStr: string): string {
    const [year, month, day] = dateStr.split('-').map(n => parseInt(n, 10));
    const { hours, minutes } = parseTimeString(timeStr);
    const y = String(year);
    const m = String(month).padStart(2, '0');
    const d = String(day).padStart(2, '0');
    const h = String(hours).padStart(2, '0');
    const min = String(minutes).padStart(2, '0');
    return `${y}${m}${d}T${h}${min}00`;
}

// Compute a default end time 2 hours after start, as local datetime string
function defaultEndLocalDateTime(dateStr: string, timeStr: string): string {
    const [year, month, day] = dateStr.split('-').map(n => parseInt(n, 10));
    const { hours, minutes } = parseTimeString(timeStr);
    // Simple 2-hour offset; if it crosses midnight, cap at 23:59
    let endHours = hours + 2;
    if (endHours >= 24) endHours = 23;
    const y = String(year);
    const m = String(month).padStart(2, '0');
    const d = String(day).padStart(2, '0');
    const h = String(endHours).padStart(2, '0');
    const min = String(minutes).padStart(2, '0');
    return `${y}${m}${d}T${h}${min}00`;
}

// Generate a stable UID for an event
function generateUid(type: string, id: string, domain: string): string {
    return `${type}-${id}@${domain}`;
}

// Compute a deterministic ETag from event data and calendar metadata using SHA-1
async function computeEtag(
    gigs: GigEvent[],
    rehearsals: RehearsalEvent[],
    blockOuts: BlockOutEvent[],
    calendarName: string,
    timezone: string,
): Promise<string> {
    const source = JSON.stringify({
        band: calendarName,
        tz: timezone,
        g: gigs.map(g => [g.id, g.date, g.start_time, g.end_time]),
        r: rehearsals.map(r => [
            r.id,
            r.date,
            r.start_time,
            r.end_time,
            r.is_recurring ?? false,
            r.recurrence_frequency ?? null,
            r.recurrence_until ?? null,
            (r.recurrence_days ?? []).join(','),
            r.parent_rehearsal_id ?? null,
        ]),
        b: blockOuts.map(b => [b.id, b.date]),
    });
    const hash = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(source));
    return `"${Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("")}"`;
}

// Map a day-of-week index (0=Sun..6=Sat) to its iCal BYDAY token.
const BYDAY_MAP: Record<number, string> = {
    0: 'SU', 1: 'MO', 2: 'TU', 3: 'WE', 4: 'TH', 5: 'FR', 6: 'SA',
};

// Format a YYYY-MM-DD date as end-of-day UTC for an RRULE UNTIL value.
function formatRruleUntil(dateStr: string): string {
    const parts = dateStr.split('-');
    if (parts.length !== 3) return '';
    const [y, m, d] = parts;
    return `${y}${m.padStart(2, '0')}${d.padStart(2, '0')}T235959Z`;
}

// Returns the first occurrence date (YYYY-MM-DD) on or after parentDateStr
// whose day-of-week matches targetDayIndex (0=Sun..6=Sat).
function computeFirstOccurrenceDate(parentDateStr: string, targetDayIndex: number): string {
    const [year, month, day] = parentDateStr.split('-').map(n => parseInt(n, 10));
    const startDate = new Date(year, month - 1, day);
    const daysOffset = (targetDayIndex - startDate.getDay() + 7) % 7;
    const firstOccurrence = new Date(year, month - 1, day + daysOffset);
    const y = String(firstOccurrence.getFullYear());
    const m = String(firstOccurrence.getMonth() + 1).padStart(2, '0');
    const d = String(firstOccurrence.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

// Build an RRULE value (without the leading 'RRULE:') for a recurring rehearsal
// parent row. Returns null if the recurrence metadata is missing or unsupported,
// signaling callers to fall back to a single-instance VEVENT.
function buildRehearsalRrule(rehearsal: RehearsalEvent): string | null {
    const freq = rehearsal.recurrence_frequency;
    let rrule: string;
    if (freq === 'weekly') {
        rrule = 'FREQ=WEEKLY';
    } else if (freq === 'biweekly') {
        rrule = 'FREQ=WEEKLY;INTERVAL=2';
    } else if (freq === 'monthly') {
        rrule = 'FREQ=MONTHLY';
    } else {
        return null;
    }

    const days = rehearsal.recurrence_days;
    if (days && days.length > 0) {
        const tokens = days
            .map(d => BYDAY_MAP[d])
            .filter((t): t is string => Boolean(t));
        if (tokens.length > 0) {
            if (freq === 'monthly') {
                const firstDateStr = computeFirstOccurrenceDate(rehearsal.date, days[0]);
                const firstDay = parseInt(firstDateStr.split('-')[2], 10);
                const N = Math.ceil(firstDay / 7);
                rrule += `;BYDAY=${tokens.map(t => `${N}${t}`).join(',')}`;
            } else {
                rrule += `;BYDAY=${tokens.join(',')}`;
            }
        }
    }

    if (rehearsal.recurrence_until) {
        const until = formatRruleUntil(rehearsal.recurrence_until);
        if (until) {
            rrule += `;UNTIL=${until}`;
        }
    }

    return rrule;
}

// Known VTIMEZONE definitions for IANA timezone identifiers.
// These include standard/daylight transition rules for proper DST handling.
const VTIMEZONE_DEFS: Record<string, string> = {
    'America/New_York': [
        'BEGIN:VTIMEZONE',
        'TZID:America/New_York',
        'BEGIN:STANDARD',
        'DTSTART:19701101T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
        'TZOFFSETFROM:-0400',
        'TZOFFSETTO:-0500',
        'TZNAME:EST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700308T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
        'TZOFFSETFROM:-0500',
        'TZOFFSETTO:-0400',
        'TZNAME:EDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'America/Chicago': [
        'BEGIN:VTIMEZONE',
        'TZID:America/Chicago',
        'BEGIN:STANDARD',
        'DTSTART:19701101T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
        'TZOFFSETFROM:-0500',
        'TZOFFSETTO:-0600',
        'TZNAME:CST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700308T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
        'TZOFFSETFROM:-0600',
        'TZOFFSETTO:-0500',
        'TZNAME:CDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'America/Denver': [
        'BEGIN:VTIMEZONE',
        'TZID:America/Denver',
        'BEGIN:STANDARD',
        'DTSTART:19701101T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
        'TZOFFSETFROM:-0600',
        'TZOFFSETTO:-0700',
        'TZNAME:MST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700308T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
        'TZOFFSETFROM:-0700',
        'TZOFFSETTO:-0600',
        'TZNAME:MDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'America/Los_Angeles': [
        'BEGIN:VTIMEZONE',
        'TZID:America/Los_Angeles',
        'BEGIN:STANDARD',
        'DTSTART:19701101T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
        'TZOFFSETFROM:-0700',
        'TZOFFSETTO:-0800',
        'TZNAME:PST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700308T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
        'TZOFFSETFROM:-0800',
        'TZOFFSETTO:-0700',
        'TZNAME:PDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'America/Anchorage': [
        'BEGIN:VTIMEZONE',
        'TZID:America/Anchorage',
        'BEGIN:STANDARD',
        'DTSTART:19701101T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU',
        'TZOFFSETFROM:-0800',
        'TZOFFSETTO:-0900',
        'TZNAME:AKST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700308T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU',
        'TZOFFSETFROM:-0900',
        'TZOFFSETTO:-0800',
        'TZNAME:AKDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Pacific/Honolulu': [
        'BEGIN:VTIMEZONE',
        'TZID:Pacific/Honolulu',
        'BEGIN:STANDARD',
        'DTSTART:19700101T000000',
        'TZOFFSETFROM:-1000',
        'TZOFFSETTO:-1000',
        'TZNAME:HST',
        'END:STANDARD',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Europe/London': [
        'BEGIN:VTIMEZONE',
        'TZID:Europe/London',
        'BEGIN:STANDARD',
        'DTSTART:19701025T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
        'TZOFFSETFROM:+0100',
        'TZOFFSETTO:+0000',
        'TZNAME:GMT',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700329T010000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
        'TZOFFSETFROM:+0000',
        'TZOFFSETTO:+0100',
        'TZNAME:BST',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Europe/Paris': [
        'BEGIN:VTIMEZONE',
        'TZID:Europe/Paris',
        'BEGIN:STANDARD',
        'DTSTART:19701025T030000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
        'TZOFFSETFROM:+0200',
        'TZOFFSETTO:+0100',
        'TZNAME:CET',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700329T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
        'TZOFFSETFROM:+0100',
        'TZOFFSETTO:+0200',
        'TZNAME:CEST',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Europe/Berlin': [
        'BEGIN:VTIMEZONE',
        'TZID:Europe/Berlin',
        'BEGIN:STANDARD',
        'DTSTART:19701025T030000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
        'TZOFFSETFROM:+0200',
        'TZOFFSETTO:+0100',
        'TZNAME:CET',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19700329T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
        'TZOFFSETFROM:+0100',
        'TZOFFSETTO:+0200',
        'TZNAME:CEST',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Asia/Tokyo': [
        'BEGIN:VTIMEZONE',
        'TZID:Asia/Tokyo',
        'BEGIN:STANDARD',
        'DTSTART:19700101T000000',
        'TZOFFSETFROM:+0900',
        'TZOFFSETTO:+0900',
        'TZNAME:JST',
        'END:STANDARD',
        'END:VTIMEZONE',
    ].join('\r\n'),
    'Australia/Sydney': [
        'BEGIN:VTIMEZONE',
        'TZID:Australia/Sydney',
        'BEGIN:STANDARD',
        'DTSTART:19700405T030000',
        'RRULE:FREQ=YEARLY;BYMONTH=4;BYDAY=1SU',
        'TZOFFSETFROM:+1100',
        'TZOFFSETTO:+1000',
        'TZNAME:AEST',
        'END:STANDARD',
        'BEGIN:DAYLIGHT',
        'DTSTART:19701004T020000',
        'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=1SU',
        'TZOFFSETFROM:+1000',
        'TZOFFSETTO:+1100',
        'TZNAME:AEDT',
        'END:DAYLIGHT',
        'END:VTIMEZONE',
    ].join('\r\n'),
};

interface GigEvent {
    id: string;
    name: string;
    location: string | null;
    date: string;
    load_in_time: string | null;
    start_time: string | null;
    end_time: string | null;
    band_name: string;
    notes: string | null;
    isPotential?: boolean;
}

interface RehearsalEvent {
    id: string;
    date: string;          // The date (YYYY-MM-DD)
    location: string | null;
    start_time: string;    // Time string like "7:00 PM"
    end_time: string | null;
    band_name: string;
    notes: string | null;
    is_recurring?: boolean | null;
    recurrence_frequency?: string | null;  // 'weekly' | 'biweekly' | 'monthly'
    recurrence_days?: number[] | null;     // 0=Sun..6=Sat
    recurrence_until?: string | null;      // YYYY-MM-DD
    parent_rehearsal_id?: string | null;
    isPotential?: boolean;
}

interface BlockOutEvent {
    id: string;
    date: string;  // Single date column
    user_name: string;
    reason: string;
}

Deno.serve(async (req) => {
    const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    };

    if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (req.method !== "GET") {
        return new Response("Method not allowed", { status: 405, headers: corsHeaders });
    }

    // Check environment variables early
    if (!SUPABASE_URL) {
        return new Response("Missing SUPABASE_URL", { status: 500, headers: corsHeaders });
    }
    if (!SUPABASE_SERVICE_ROLE_KEY) {
        return new Response("Missing SUPABASE_SERVICE_ROLE_KEY", { status: 500, headers: corsHeaders });
    }

    try {
        const url = new URL(req.url);
        const token = url.searchParams.get("token");

        if (!token) {
            return new Response("Missing token parameter", { status: 400, headers: corsHeaders });
        }

        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

        // ---- Token resolution: band-scoped first, then legacy user token ----
        let userId: string;
        let userName: string;
        let bandScopedBandId: string | null = null;
        let bandTimezone = 'America/Chicago';
        let calendarName: string;

        // Feed preferences — defaults match the DB column defaults
        let includeGigs = true;
        let includeRehearsal = true;
        let includeBlockouts = false;
        let includePotentialGigs = false;
        let includePotentialRehearsal = false;

        // 1. Try band_calendar_subscriptions token
        const { data: bandSub, error: bandSubError } = await supabase
            .from('band_calendar_subscriptions')
            .select('user_id, band_id, include_gigs, include_rehearsals, include_blockouts, include_potential_gigs, include_potential_rehearsals')
            .eq('token', token)
            .single();

        if (bandSub && !bandSubError) {
            userId = bandSub.user_id;
            bandScopedBandId = bandSub.band_id;

            // Read per-subscriber preferences (nullish fallback to defaults)
            includeGigs              = bandSub.include_gigs               ?? true;
            includeRehearsal         = bandSub.include_rehearsals          ?? true;
            includeBlockouts         = bandSub.include_blockouts           ?? false;
            includePotentialGigs     = bandSub.include_potential_gigs      ?? false;
            includePotentialRehearsal = bandSub.include_potential_rehearsals ?? false;

            // Verify user is still a member of the band
            const { data: membership } = await supabase
                .from('band_members')
                .select('band_id')
                .eq('user_id', userId)
                .eq('band_id', bandScopedBandId)
                .single();

            if (!membership) {
                return new Response("User is no longer a member of this band", { status: 404, headers: corsHeaders });
            }

            // Get band info including timezone
            const { data: band } = await supabase
                .from('bands')
                .select('name, timezone')
                .eq('id', bandScopedBandId)
                .single();

            const bandName = band?.name || 'Band';
            bandTimezone = band?.timezone || 'America/Chicago';
            calendarName = bandName;

            // Get user name for block-out events
            const { data: userRow } = await supabase
                .from('users')
                .select('first_name, last_name')
                .eq('id', userId)
                .single();

            userName = `${userRow?.first_name || ''} ${userRow?.last_name || ''}`.trim() || 'User';
        } else {
            // 2. Fallback: legacy user token
            const { data: user, error: userError } = await supabase
                .from('users')
                .select('id, first_name, last_name, calendar_token')
                .eq('calendar_token', token)
                .single();

            if (userError || !user) {
                console.error('Invalid calendar token:', token, 'Error:', userError?.message);
                return new Response("Invalid or expired calendar token", { status: 404, headers: corsHeaders });
            }

            userId = user.id;
            userName = `${user.first_name || ''} ${user.last_name || ''}`.trim() || 'User';
            calendarName = `BandRoadie - ${userName}`;
        }

        // Determine which bands to query
        let bandIds: string[];

        if (bandScopedBandId) {
            // Band-scoped: single band only
            bandIds = [bandScopedBandId];
        } else {
            // Legacy: all bands the user belongs to
            const { data: bandMemberships, error: bandsError } = await supabase
                .from('band_members')
                .select('band_id, bands(id, name)')
                .eq('user_id', userId);

            if (bandsError) throw bandsError;

            bandIds = bandMemberships?.map(m => m.band_id) || [];
        }

        if (bandIds.length === 0) {
            // Return empty calendar
            const etag = await computeEtag([], [], [], calendarName, bandTimezone ?? 'America/Chicago');
            const ifNoneMatch = req.headers.get("if-none-match");
            if (ifNoneMatch === etag) {
                return new Response(null, { status: 304, headers: corsHeaders });
            }
            const emptyCalendar = generateCalendar([], [], [], calendarName, bandTimezone ?? 'America/Chicago');
            return new Response(emptyCalendar, {
                headers: {
                    "Content-Type": "text/calendar; charset=utf-8",
                    "Content-Disposition": "attachment; filename=bandroadie.ics",
                    "Cache-Control": "no-cache",
                    "ETag": etag,
                    "Last-Modified": new Date().toUTCString(),
                    "X-PUBLISHED-TTL": "PT15M",
                    ...corsHeaders,
                },
            });
        }

        // Past-year cutoff shared across all queries
        const pastYearDate = new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];

        // Fetch confirmed gigs only — potential gigs are never included in the feed
        const { data: gigs, error: gigsError } = await supabase
            .from('gigs')
            .select(`
                id, name, location, date, load_in_time, start_time, end_time,
                notes, band_id,
                bands(name)
            `)
            .in('band_id', bandIds)
            .eq('is_potential', false)
            .gte('date', pastYearDate)
            .order('date', { ascending: true });

        if (gigsError) throw gigsError;

        // Fetch confirmed rehearsals only — potential rehearsals are excluded
        // from the feed for consistency with how potential gigs are handled.
        const { data: rehearsals, error: rehearsalsError } = await supabase
            .from('rehearsals')
            .select(`
                id, date, location, start_time, end_time, notes, band_id,
                is_recurring, recurrence_frequency, recurrence_days,
                recurrence_until, parent_rehearsal_id,
                bands(name)
            `)
            .in('band_id', bandIds)
            .eq('is_potential', false)
            .gte('date', pastYearDate)
            .order('date', { ascending: true });

        if (rehearsalsError) throw rehearsalsError;

        // Fetch block-out dates for the user's bands
        const { data: blockOuts, error: blockOutsError } = await supabase
            .from('block_dates')
            .select('id, date, reason, user_id')
            .in('band_id', bandIds)
            .gte('date', pastYearDate);

        if (blockOutsError) throw blockOutsError;

        // Get unique user IDs from block outs to fetch their names
        const blockOutUserIds = [...new Set((blockOuts || []).map(b => b.user_id))];
        let userNameMap: Record<string, string> = {};

        if (blockOutUserIds.length > 0) {
            const { data: blockOutUsers } = await supabase
                .from('users')
                .select('id, first_name, last_name')
                .in('id', blockOutUserIds);

            userNameMap = (blockOutUsers || []).reduce((acc, u) => {
                const name = `${u.first_name || ''} ${u.last_name || ''}`.trim() || 'Member';
                acc[u.id] = name;
                return acc;
            }, {} as Record<string, string>);
        }

        // Transform data
        const gigEvents: GigEvent[] = (gigs || []).map(g => ({
            id: g.id,
            name: g.name || 'Gig',
            location: g.location,
            date: g.date,
            load_in_time: g.load_in_time,
            start_time: g.start_time,
            end_time: g.end_time,
            band_name: (g.bands as any)?.name || 'Band',
            notes: g.notes,
            isPotential: false,
        }));

        const rehearsalEvents: RehearsalEvent[] = (rehearsals || []).map(r => ({
            id: r.id,
            date: r.date,
            location: r.location,
            start_time: r.start_time,
            end_time: r.end_time,
            band_name: (r.bands as any)?.name || 'Band',
            notes: r.notes,
            is_recurring: (r as any).is_recurring ?? null,
            recurrence_frequency: (r as any).recurrence_frequency ?? null,
            recurrence_days: (r as any).recurrence_days ?? null,
            recurrence_until: (r as any).recurrence_until ?? null,
            parent_rehearsal_id: (r as any).parent_rehearsal_id ?? null,
            isPotential: false,
        }));

        const blockOutEvents: BlockOutEvent[] = (blockOuts || []).map(b => ({
            id: b.id,
            date: b.date,
            user_name: userNameMap[b.user_id] || 'Member',
            reason: b.reason || '',
        }));

        // Fetch potential gigs (only when subscriber has opted in)
        let potentialGigEvents: GigEvent[] = [];
        if (includePotentialGigs) {
            const { data: potentialGigs, error: potentialGigsError } = await supabase
                .from('gigs')
                .select(`id, name, location, date, load_in_time, start_time, end_time, notes, band_id, bands(name)`)
                .in('band_id', bandIds)
                .eq('is_potential', true)
                .gte('date', pastYearDate)
                .order('date', { ascending: true });
            if (potentialGigsError) throw potentialGigsError;
            potentialGigEvents = (potentialGigs || []).map(g => ({
                id: g.id,
                name: `(Potential) ${g.name || 'Gig'}`,
                location: g.location,
                date: g.date,
                load_in_time: g.load_in_time,
                start_time: g.start_time,
                end_time: g.end_time,
                band_name: (g.bands as any)?.name || 'Band',
                notes: g.notes,
                isPotential: true,
            }));
        }

        // Fetch potential rehearsals (only when subscriber has opted in)
        let potentialRehearsalEvents: RehearsalEvent[] = [];
        if (includePotentialRehearsal) {
            const { data: potentialRehearsals, error: potentialRehearsalsError } = await supabase
                .from('rehearsals')
                .select(`id, date, location, start_time, end_time, notes, band_id, is_recurring, recurrence_frequency, recurrence_days, recurrence_until, parent_rehearsal_id, bands(name)`)
                .in('band_id', bandIds)
                .eq('is_potential', true)
                .gte('date', pastYearDate)
                .order('date', { ascending: true });
            if (potentialRehearsalsError) throw potentialRehearsalsError;
            potentialRehearsalEvents = (potentialRehearsals || []).map(r => ({
                id: r.id,
                date: r.date,
                location: r.location,
                start_time: r.start_time,
                end_time: r.end_time,
                band_name: (r.bands as any)?.name || 'Band',
                notes: r.notes,
                is_recurring: (r as any).is_recurring ?? null,
                recurrence_frequency: (r as any).recurrence_frequency ?? null,
                recurrence_days: (r as any).recurrence_days ?? null,
                recurrence_until: (r as any).recurrence_until ?? null,
                parent_rehearsal_id: (r as any).parent_rehearsal_id ?? null,
                isPotential: true,
            }));
        }

        // Apply feed preferences — filter event arrays before generating the calendar
        const filteredGigs       = includeGigs      ? gigEvents      : [];
        const filteredRehearsal  = includeRehearsal ? rehearsalEvents : [];
        const filteredBlockOuts  = includeBlockouts ? blockOutEvents  : [];

        // Merge potential events into their respective arrays for feed generation.
        // Potential events are always emitted as flat VEVENTs (no RRULE) regardless
        // of recurrence metadata, and their titles are already prefixed with "(Potential)".
        const allGigEvents         = [...filteredGigs, ...potentialGigEvents];
        const allRehearsalEvents   = [...filteredRehearsal, ...potentialRehearsalEvents];

        const etag = await computeEtag(allGigEvents, allRehearsalEvents, filteredBlockOuts, calendarName, bandTimezone);
        const ifNoneMatch = req.headers.get("if-none-match");

        if (ifNoneMatch === etag) {
            return new Response(null, { status: 304, headers: corsHeaders });
        }

        const calendar = generateCalendar(allGigEvents, allRehearsalEvents, filteredBlockOuts, calendarName, bandTimezone);

        return new Response(calendar, {
            headers: {
                "Content-Type": "text/calendar; charset=utf-8",
                "Content-Disposition": "attachment; filename=bandroadie.ics",
                "Cache-Control": "no-cache",
                "ETag": etag,
                "Last-Modified": new Date().toUTCString(),
                "X-PUBLISHED-TTL": "PT15M",
                ...corsHeaders,
            },
        });

    } catch (error) {
        console.error('Error generating calendar feed:', error);
        let errorMessage: string;
        if (error instanceof Error) {
            errorMessage = `${error.name}: ${error.message}`;
        } else if (typeof error === 'object' && error !== null) {
            errorMessage = JSON.stringify(error);
        } else {
            errorMessage = String(error);
        }
        return new Response(`Error: ${errorMessage}`, { status: 500, headers: corsHeaders });
    }
});

function generateCalendar(
    gigs: GigEvent[],
    rehearsals: RehearsalEvent[],
    blockOuts: BlockOutEvent[],
    calendarName: string,
    timezone: string
): string {
    const domain = "bandroadie.com";
    const now = formatIcsDate(new Date().toISOString(), true);

    const lines: string[] = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//BandRoadie//Calendar//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        'REFRESH-INTERVAL;VALUE=DURATION:PT1H',
        `X-WR-CALNAME:${escapeIcsText(calendarName)}`,
        `X-WR-TIMEZONE:${timezone}`,
    ];

    // Add VTIMEZONE block if a definition is available for this timezone
    const vtimezone = VTIMEZONE_DEFS[timezone];
    if (vtimezone) {
        lines.push(vtimezone);
    }

    // Add confirmed gigs (potential gigs are excluded at query time)
    for (const gig of gigs) {
        const uid = generateUid('gig', gig.id, domain);

        // Build description
        let description = `Band: ${gig.band_name}`;
        if (gig.location) description += `\\nVenue: ${gig.location}`;
        if (gig.load_in_time) description += `\\nLoad-in: ${gig.load_in_time}`;
        if (gig.start_time) description += `\\nStart: ${gig.start_time}`;
        if (gig.end_time) description += `\\nEnd: ${gig.end_time}`;
        if (gig.notes) description += `\\n\\nNotes: ${gig.notes}`;

        lines.push('BEGIN:VEVENT');
        lines.push(foldLine(`UID:${uid}`));
        lines.push(foldLine(`DTSTAMP:${now}`));

        if (gig.start_time) {
            // Timed event with TZID
            const startDt = formatLocalDateTime(gig.date, gig.start_time);
            lines.push(foldLine(`DTSTART;TZID=${timezone}:${startDt}`));
            if (gig.end_time) {
                const endDt = formatLocalDateTime(gig.date, gig.end_time);
                lines.push(foldLine(`DTEND;TZID=${timezone}:${endDt}`));
            } else {
                // Default 2 hours for gigs
                const endDt = defaultEndLocalDateTime(gig.date, gig.start_time);
                lines.push(foldLine(`DTEND;TZID=${timezone}:${endDt}`));
            }
        } else {
            // All-day event (no time info)
            const startDate = formatAllDayDate(gig.date);
            const endDate = getNextDay(gig.date);
            lines.push(foldLine(`DTSTART;VALUE=DATE:${startDate}`));
            lines.push(foldLine(`DTEND;VALUE=DATE:${endDate}`));
        }

        lines.push(foldLine(`SUMMARY:${escapeIcsText(gig.name)}`));
        if (gig.location) {
            lines.push(foldLine(`LOCATION:${escapeIcsText(gig.location)}`));
        }
        lines.push(foldLine(`DESCRIPTION:${escapeIcsText(description)}`));
        lines.push('CATEGORIES:GIG');
        lines.push(`STATUS:${gig.isPotential ? 'TENTATIVE' : 'CONFIRMED'}`);
        lines.push('END:VEVENT');
    }

    // Build an index of child rows per parent so the loop below can decide
    // whether to emit an RRULE (no children materialized) or fall back to
    // emitting each child row individually (deletion-safe).
    const childRowsByParent = new Map<string, RehearsalEvent[]>();
    for (const r of rehearsals) {
        if (r.parent_rehearsal_id) {
            const arr = childRowsByParent.get(r.parent_rehearsal_id) ?? [];
            arr.push(r);
            childRowsByParent.set(r.parent_rehearsal_id, arr);
        }
    }

    // Add rehearsals
    for (const rehearsal of rehearsals) {
        const isRecurring = rehearsal.is_recurring === true;
        const isChild = !!rehearsal.parent_rehearsal_id;

        // Recurring parent: if children exist, they cover occurrence 2 onwards.
        // The parent row IS occurrence 1 — do NOT skip it. Instead, fall through
        // and emit it as a flat VEVENT (no RRULE) so the first date isn't dropped.
        // Only emit RRULE when no children have been materialized yet.
        const parentHasChildren =
            isRecurring && !isChild &&
            (childRowsByParent.get(rehearsal.id) ?? []).length > 0;

        const uid = generateUid('rehearsal', rehearsal.id, domain);
        const summary = `Rehearsal - ${rehearsal.band_name}`;

        let description = `Band: ${rehearsal.band_name}`;
        if (rehearsal.location) description += `\\nLocation: ${rehearsal.location}`;
        if (rehearsal.notes) description += `\\n\\nNotes: ${rehearsal.notes}`;

        // For monthly recurring parent rows with recurrence_days, DTSTART must
        // land on the first actual occurrence of the series, not the parent date.
        // When the parent has children, use the parent's own date (it IS occurrence 1).
        const freq = rehearsal.recurrence_frequency;
        const effectiveDate =
            isRecurring && !isChild && !parentHasChildren &&
            freq === 'monthly' &&
            rehearsal.recurrence_days && rehearsal.recurrence_days.length > 0
                ? computeFirstOccurrenceDate(rehearsal.date, rehearsal.recurrence_days[0])
                : rehearsal.date;

        // Format as local time with TZID
        const startDt = formatLocalDateTime(effectiveDate, rehearsal.start_time);
        const endDt = rehearsal.end_time
            ? formatLocalDateTime(effectiveDate, rehearsal.end_time)
            : defaultEndLocalDateTime(effectiveDate, rehearsal.start_time);

        // For recurring parent rows, build an RRULE. If the metadata is
        // incomplete or the frequency is unsupported, fall back to a flat
        // VEVENT so the series is not silently dropped.
        // When the parent has materialized children, skip the RRULE entirely —
        // children emit their own flat VEVENTs covering the remaining occurrences.
        let rrule: string | null = null;
        let recurrenceIncomplete = false;
        if (isRecurring && !isChild && !parentHasChildren && rehearsal.recurrence_frequency === 'monthly') {
            rrule = buildRehearsalRrule(rehearsal);
            if (rrule === null) {
                recurrenceIncomplete = true;
            }
        }

        lines.push('BEGIN:VEVENT');
        lines.push(foldLine(`UID:${uid}`));
        lines.push(foldLine(`DTSTAMP:${now}`));
        lines.push(foldLine(`DTSTART;TZID=${timezone}:${startDt}`));
        lines.push(foldLine(`DTEND;TZID=${timezone}:${endDt}`));
        if (rrule) {
            lines.push(foldLine(`RRULE:${rrule}`));
        }
        if (recurrenceIncomplete) {
            lines.push(foldLine('X-BANDROADIE-NOTE:RECURRENCE-DATA-INCOMPLETE'));
        }
        lines.push(foldLine(`SUMMARY:${escapeIcsText(summary)}`));
        if (rehearsal.location) {
            lines.push(foldLine(`LOCATION:${escapeIcsText(rehearsal.location)}`));
        }
        lines.push(foldLine(`DESCRIPTION:${escapeIcsText(description)}`));
        lines.push('CATEGORIES:REHEARSAL');
        lines.push(`STATUS:${rehearsal.isPotential ? 'TENTATIVE' : 'CONFIRMED'}`);
        lines.push('END:VEVENT');
    }

    // Add block-out dates
    for (const blockOut of blockOuts) {
        const uid = generateUid('blockout', blockOut.id, domain);
        const summary = `${blockOut.user_name} - Unavailable`;

        let description = `${blockOut.user_name} is unavailable`;
        if (blockOut.reason) description += `\\nReason: ${blockOut.reason}`;

        // Single date format (block_dates table has only a 'date' column)
        const startDate = formatAllDayDate(blockOut.date);
        const endDate = getNextDay(blockOut.date);  // End date is exclusive in iCal

        lines.push('BEGIN:VEVENT');
        lines.push(foldLine(`UID:${uid}`));
        lines.push(foldLine(`DTSTAMP:${now}`));
        lines.push(foldLine(`DTSTART;VALUE=DATE:${startDate}`));
        lines.push(foldLine(`DTEND;VALUE=DATE:${endDate}`));
        lines.push(foldLine(`SUMMARY:${escapeIcsText(summary)}`));
        lines.push(foldLine(`DESCRIPTION:${escapeIcsText(description)}`));
        lines.push('CATEGORIES:BLOCK OUT');
        lines.push('TRANSP:TRANSPARENT');
        lines.push('STATUS:CONFIRMED');
        lines.push('END:VEVENT');
    }

    lines.push('END:VCALENDAR');

    return lines.join('\r\n');
}
