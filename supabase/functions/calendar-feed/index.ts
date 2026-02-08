// supabase/functions/calendar-feed/index.ts
// Edge function to generate iCalendar (.ics) feed for calendar subscriptions
//
// URL format: /calendar-feed?token={user_calendar_token}
// Returns: text/calendar (.ics) content
//
// Includes: Gigs, Potential Gigs, Rehearsals, Block-out dates for all user's bands

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

// Parse time string like "7:00 PM" or "19:00" and combine with date
function combineDateAndTime(dateStr: string, timeStr: string): string {
    // Parse the date (YYYY-MM-DD)
    const [year, month, day] = dateStr.split('-').map(n => parseInt(n, 10));

    // Parse the time string
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

    // Create UTC date string
    const date = new Date(Date.UTC(year, month - 1, day, hours, minutes, 0));
    return date.toISOString();
}

// Generate a stable UID for an event
function generateUid(type: string, id: string, domain: string): string {
    return `${type}-${id}@${domain}`;
}

interface GigEvent {
    id: string;
    name: string;
    location: string | null;
    date: string;
    load_in_time: string | null;
    start_time: string | null;
    end_time: string | null;
    is_potential: boolean;
    band_name: string;
    notes: string | null;
}

interface RehearsalEvent {
    id: string;
    date: string;          // The date (YYYY-MM-DD)
    location: string | null;
    start_time: string;    // Time string like "7:00 PM"
    end_time: string | null;
    band_name: string;
    notes: string | null;
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

        // Look up user by calendar token
        const { data: user, error: userError } = await supabase
            .from('users')
            .select('id, first_name, last_name, calendar_token')
            .eq('calendar_token', token)
            .single();

        if (userError || !user) {
            console.error('Invalid calendar token:', token, 'Error:', userError?.message);
            return new Response("Invalid or expired calendar token", { status: 404, headers: corsHeaders });
        }

        const userId = user.id;
        const userName = `${user.first_name || ''} ${user.last_name || ''}`.trim() || 'User';

        // Get all bands the user is a member of
        const { data: bandMemberships, error: bandsError } = await supabase
            .from('band_members')
            .select('band_id, bands(id, name)')
            .eq('user_id', userId);

        if (bandsError) throw bandsError;

        const bandIds = bandMemberships?.map(m => m.band_id) || [];

        if (bandIds.length === 0) {
            // Return empty calendar
            const emptyCalendar = generateCalendar([], [], [], userName);
            return new Response(emptyCalendar, {
                headers: {
                    "Content-Type": "text/calendar; charset=utf-8",
                    "Content-Disposition": "attachment; filename=bandroadie.ics",
                    ...corsHeaders,
                },
            });
        }

        // Fetch all gigs for user's bands
        const { data: gigs, error: gigsError } = await supabase
            .from('gigs')
            .select(`
                id, name, location, date, load_in_time, start_time, end_time, 
                is_potential, notes, band_id,
                bands(name)
            `)
            .in('band_id', bandIds)
            .gte('date', new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]) // Past year
            .order('date', { ascending: true });

        if (gigsError) throw gigsError;

        // Fetch all rehearsals for user's bands
        const { data: rehearsals, error: rehearsalsError } = await supabase
            .from('rehearsals')
            .select(`
                id, date, location, start_time, end_time, notes, band_id,
                bands(name)
            `)
            .in('band_id', bandIds)
            .gte('date', new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]) // Past year
            .order('date', { ascending: true });

        if (rehearsalsError) throw rehearsalsError;

        // Fetch block-out dates for the user's bands
        const { data: blockOuts, error: blockOutsError } = await supabase
            .from('block_dates')
            .select('id, date, reason, user_id')
            .in('band_id', bandIds)
            .gte('date', new Date(Date.now() - 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]);

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
            is_potential: g.is_potential || false,
            band_name: (g.bands as any)?.name || 'Band',
            notes: g.notes,
        }));

        const rehearsalEvents: RehearsalEvent[] = (rehearsals || []).map(r => ({
            id: r.id,
            date: r.date,
            location: r.location,
            start_time: r.start_time,
            end_time: r.end_time,
            band_name: (r.bands as any)?.name || 'Band',
            notes: r.notes,
        }));

        const blockOutEvents: BlockOutEvent[] = (blockOuts || []).map(b => ({
            id: b.id,
            date: b.date,
            user_name: userNameMap[b.user_id] || 'Member',
            reason: b.reason || '',
        }));

        const calendar = generateCalendar(gigEvents, rehearsalEvents, blockOutEvents, userName);

        return new Response(calendar, {
            headers: {
                "Content-Type": "text/calendar; charset=utf-8",
                "Content-Disposition": "attachment; filename=bandroadie.ics",
                "Cache-Control": "no-cache, no-store, must-revalidate",
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
    userName: string
): string {
    const domain = "bandroadie.com";
    const now = formatIcsDate(new Date().toISOString(), true);

    const lines: string[] = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//BandRoadie//Calendar//EN',
        'CALSCALE:GREGORIAN',
        'METHOD:PUBLISH',
        `X-WR-CALNAME:BandRoadie - ${escapeIcsText(userName)}`,
        'X-WR-TIMEZONE:UTC',
    ];

    // Add gigs
    for (const gig of gigs) {
        const uid = generateUid('gig', gig.id, domain);
        const summary = gig.is_potential
            ? `[POTENTIAL] ${gig.name}`
            : gig.name;

        // Build description
        let description = `Band: ${gig.band_name}`;
        if (gig.location) description += `\\nVenue: ${gig.location}`;
        if (gig.load_in_time) description += `\\nLoad-in: ${gig.load_in_time}`;
        if (gig.start_time) description += `\\nStart: ${gig.start_time}`;
        if (gig.end_time) description += `\\nEnd: ${gig.end_time}`;
        if (gig.notes) description += `\\n\\nNotes: ${gig.notes}`;
        if (gig.is_potential) description += `\\n\\n⚠️ This is a potential gig (not yet confirmed)`;

        // Use all-day event for gigs (date only)
        const startDate = formatAllDayDate(gig.date);
        const endDate = getNextDay(gig.date);

        lines.push('BEGIN:VEVENT');
        lines.push(foldLine(`UID:${uid}`));
        lines.push(foldLine(`DTSTAMP:${now}`));
        lines.push(foldLine(`DTSTART;VALUE=DATE:${startDate}`));
        lines.push(foldLine(`DTEND;VALUE=DATE:${endDate}`));
        lines.push(foldLine(`SUMMARY:${escapeIcsText(summary)}`));
        if (gig.location) {
            lines.push(foldLine(`LOCATION:${escapeIcsText(gig.location)}`));
        }
        lines.push(foldLine(`DESCRIPTION:${escapeIcsText(description)}`));
        lines.push(`CATEGORIES:${gig.is_potential ? 'POTENTIAL GIG' : 'GIG'}`);
        lines.push('STATUS:CONFIRMED');
        lines.push('END:VEVENT');
    }

    // Add rehearsals
    for (const rehearsal of rehearsals) {
        const uid = generateUid('rehearsal', rehearsal.id, domain);
        const summary = `Rehearsal - ${rehearsal.band_name}`;

        let description = `Band: ${rehearsal.band_name}`;
        if (rehearsal.location) description += `\\nLocation: ${rehearsal.location}`;
        if (rehearsal.notes) description += `\\n\\nNotes: ${rehearsal.notes}`;

        // Combine date + time strings to create proper timestamps
        const startTimeISO = combineDateAndTime(rehearsal.date, rehearsal.start_time);
        const endTimeISO = rehearsal.end_time
            ? combineDateAndTime(rehearsal.date, rehearsal.end_time)
            : new Date(new Date(startTimeISO).getTime() + 2 * 60 * 60 * 1000).toISOString(); // Default 2 hours

        const startTime = formatIcsDate(startTimeISO, true);
        const endTime = formatIcsDate(endTimeISO, true);

        lines.push('BEGIN:VEVENT');
        lines.push(foldLine(`UID:${uid}`));
        lines.push(foldLine(`DTSTAMP:${now}`));
        lines.push(foldLine(`DTSTART:${startTime}`));
        lines.push(foldLine(`DTEND:${endTime}`));
        lines.push(foldLine(`SUMMARY:${escapeIcsText(summary)}`));
        if (rehearsal.location) {
            lines.push(foldLine(`LOCATION:${escapeIcsText(rehearsal.location)}`));
        }
        lines.push(foldLine(`DESCRIPTION:${escapeIcsText(description)}`));
        lines.push('CATEGORIES:REHEARSAL');
        lines.push('STATUS:CONFIRMED');
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
