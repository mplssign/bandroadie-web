// supabase/functions/send-push/index.ts
// Edge function to send push notifications via Firebase Cloud Messaging
//
// Called AFTER notification record is created in database
// Only handles FCM delivery, does not create notification records

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

interface WebhookPayload {
    type: 'INSERT';
    table: 'notifications';
    record: {
        id: string;
        recipient_user_id: string;
        band_id: string;
        type: string;
        title: string;
        body: string;
        metadata: Record<string, any>;
    };
    old_record: null;
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
        const payload: WebhookPayload = await req.json();

        // Extract notification details from webhook
        const notification = payload.record;
        const recipientUserId = notification.recipient_user_id;

        console.log(`Processing push notification for user ${recipientUserId}`);

        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

        // Get FCM tokens for the recipient
        const { data: tokens, error: tokensError } = await supabase
            .from('device_tokens')
            .select('fcm_token')
            .eq('user_id', recipientUserId);

        if (tokensError) throw tokensError;

        if (!tokens || tokens.length === 0) {
            console.log(`No FCM tokens found for user ${recipientUserId}`);
            return new Response(
                JSON.stringify({ success: true, sent: 0, reason: 'no_tokens' }),
                { headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Send to FCM (multicast message to all user's devices)
        const fcmTokens = tokens.map(t => t.fcm_token);
        const fcmPayload = {
            registration_ids: fcmTokens,
            notification: {
                title: notification.title,
                body: notification.body,
            },
            data: {
                notification_id: notification.id,
                type: notification.type,
                band_id: notification.band_id,
                ...notification.metadata,
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

        let sentCount = 0;
        if (fcmResponse.ok) {
            const result = await fcmResponse.json();
            sentCount = result.success || 0;
            console.log(`FCM sent: ${sentCount}/${fcmTokens.length} for notification ${notification.id}`);

            // Clean up invalid tokens if any failed
            if (result.results) {
                const invalidTokens: string[] = [];
                result.results.forEach((res: any, index: number) => {
                    if (res.error === 'NotRegistered' || res.error === 'InvalidRegistration') {
                        invalidTokens.push(fcmTokens[index]);
                    }
                });

                if (invalidTokens.length > 0) {
                    console.log(`Removing ${invalidTokens.length} invalid tokens`);
                    await supabase
                        .from('device_tokens')
                        .delete()
                        .in('fcm_token', invalidTokens);
                }
            }
        } else {
            const errorText = await fcmResponse.text();
            console.error('FCM send failed:', errorText);
        }

        return new Response(
            JSON.stringify({
                success: true,
                notification_id: notification.id,
                devices: fcmTokens.length,
                sent: sentCount,
            }),
            { headers: { "Content-Type": "application/json", ...corsHeaders } }
        );

    } catch (error) {
        console.error('Error sending push notification:', error);
        // Return success anyway - push delivery failures should never block
        return new Response(
            JSON.stringify({
                success: true,
                sent: 0,
                error: error.message
            }),
            {
                status: 200, // Return 200 to prevent retries
                headers: { "Content-Type": "application/json", ...corsHeaders },
            }
        );
    }
});
