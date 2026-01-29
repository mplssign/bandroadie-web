// supabase/functions/send-notification/index.ts
// Edge function to send push notifications via Firebase Cloud Messaging
//
// Triggered by database changes (gig_created, rehearsal_created, etc.)
// Respects user notification preferences

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

interface NotificationPayload {
    bandId: string;
    actorUserId: string; // User who performed the action
    notificationType: 'gig_created' | 'potential_gig_created' | 'rehearsal_created' | 'blockout_created';
    title: string;
    body: string;
    metadata?: Record<string, any>;
}

// Format date as "MAR 17, 2026"
function formatEventDate(dateString: string): string {
    const date = new Date(dateString);
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    const month = months[date.getMonth()];
    const day = date.getDate();
    const year = date.getFullYear();
    return `${month} ${day}, ${year}`;
}

// Format date range as "MAY 3 – JUN 5, 2026"
function formatDateRange(startDate: string, endDate: string): string {
    const start = new Date(startDate);
    const end = new Date(endDate);
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

    const startMonth = months[start.getMonth()];
    const startDay = start.getDate();
    const endMonth = months[end.getMonth()];
    const endDay = end.getDate();
    const year = end.getFullYear();

    // If same month, show "MAY 3 – 5, 2026"
    if (start.getMonth() === end.getMonth()) {
        return `${startMonth} ${startDay} – ${endDay}, ${year}`;
    }

    // Different months: "MAY 3 – JUN 5, 2026"
    return `${startMonth} ${startDay} – ${endMonth} ${endDay}, ${year}`;
}

Deno.serve(async (req) => {
    const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
    };

    if (req.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: corsHeaders });
    }

    if (req.method !== "POST") {
        return new Response(JSON.stringify({ error: "Method not allowed" }), {
            status: 405,
            headers: { "Content-Type": "application/json", ...corsHeaders },
        });
    }

    try {
        const payload: NotificationPayload = await req.json();
        const { bandId, actorUserId, notificationType, title, body, metadata } = payload;

        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

        // 1. Get all band members except the actor
        const { data: members, error: membersError } = await supabase
            .from('band_members')
            .select('user_id, users!inner(id, name)')
            .eq('band_id', bandId)
            .neq('user_id', actorUserId);

        if (membersError) throw membersError;
        if (!members || members.length === 0) {
            console.log('No recipients found (no other members in band)');
            return new Response(JSON.stringify({ success: true, sent: 0 }), {
                headers: { "Content-Type": "application/json", ...corsHeaders },
            });
        }

        const recipientUserIds = members.map(m => m.user_id);

        // 2. Check each user's notification preferences
        const { data: preferences, error: prefsError } = await supabase
            .from('notification_preferences')
            .select('user_id, notifications_enabled, gigs_enabled, potential_gigs_enabled, rehearsals_enabled, blockouts_enabled')
            .in('user_id', recipientUserIds);

        if (prefsError) throw prefsError;

        // Filter recipients based on preferences
        const eligibleUserIds = recipientUserIds.filter(userId => {
            const pref = preferences?.find(p => p.user_id === userId);

            // If no preferences found, assume enabled (default behavior)
            if (!pref) return true;

            // Check master toggle
            if (!pref.notifications_enabled) return false;

            // Check category-specific toggle
            switch (notificationType) {
                case 'gig_created':
                    return pref.gigs_enabled;
                case 'potential_gig_created':
                    return pref.potential_gigs_enabled;
                case 'rehearsal_created':
                    return pref.rehearsals_enabled;
                case 'blockout_created':
                    return pref.blockouts_enabled;
                default:
                    return true;
            }
        });

        if (eligibleUserIds.length === 0) {
            console.log('No eligible recipients (all have notifications disabled)');
            return new Response(JSON.stringify({ success: true, sent: 0 }), {
                headers: { "Content-Type": "application/json", ...corsHeaders },
            });
        }

        // 3. Get FCM tokens for eligible users
        const { data: tokens, error: tokensError } = await supabase
            .from('device_tokens')
            .select('fcm_token, user_id')
            .in('user_id', eligibleUserIds);

        if (tokensError) throw tokensError;

        if (!tokens || tokens.length === 0) {
            console.log('No FCM tokens found for eligible users');
            // Still create in-app notifications
        }

        // 4. Create in-app notifications for all eligible users
        const notificationsToInsert = eligibleUserIds.map(userId => ({
            band_id: bandId,
            recipient_user_id: userId,
            actor_user_id: actorUserId,
            type: notificationType,
            title,
            body,
            metadata: metadata || {},
        }));

        const { error: insertError } = await supabase
            .from('notifications')
            .insert(notificationsToInsert);

        if (insertError) throw insertError;

        // 5. Send FCM push notifications
        let sentCount = 0;
        if (tokens && tokens.length > 0) {
            const fcmTokens = tokens.map(t => t.fcm_token);

            // Send to FCM (multicast message)
            const fcmPayload = {
                registration_ids: fcmTokens,
                notification: {
                    title,
                    body,
                },
                data: {
                    type: notificationType,
                    band_id: bandId,
                    ...metadata,
                },
            };

            const fcmResponse = await fetch('https://fcm.googleapis.com/fcm/send', {
                method: 'POST',
                headers: {
                    'Authorization': `key=${FCM_SERVER_KEY}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(fcmPayload),
            });

            if (fcmResponse.ok) {
                const result = await fcmResponse.json();
                sentCount = result.success || 0;
                console.log(`FCM sent: ${sentCount}/${fcmTokens.length}`);
            } else {
                console.error('FCM send failed:', await fcmResponse.text());
            }
        }

        return new Response(
            JSON.stringify({
                success: true,
                recipients: eligibleUserIds.length,
                sent: sentCount,
            }),
            { headers: { "Content-Type": "application/json", ...corsHeaders } }
        );

    } catch (error) {
        console.error('Error sending notification:', error);
        return new Response(
            JSON.stringify({ error: error.message }),
            {
                status: 500,
                headers: { "Content-Type": "application/json", ...corsHeaders },
            }
        );
    }
});
