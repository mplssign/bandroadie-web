// supabase/functions/send-push/index.ts
// Edge function to send push notifications via Firebase Cloud Messaging HTTP v1 API
//
// Called AFTER INSERT on notifications via a pg_net trigger.
// Only handles FCM delivery — does not create notification records.
//
// SECURITY:
//   • The SQL trigger sends a non-privileged shared secret in X-Internal-Secret.
//   • This function validates that header against PUSH_TRIGGER_SECRET (env var).
//   • SUPABASE_SERVICE_ROLE_KEY is read from Deno.env (auto-injected by runtime)
//     and used ONLY inside this function to create the Supabase admin client.
//   • No service_role key ever touches SQL.
//   • verify_jwt = false in config.toml (no JWT required).
//   • Secrets are NEVER logged or returned in responses.
//
// Required environment variables:
//   Auto-provided by Supabase:
//     SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//   Set via Dashboard → Edge Functions → Secrets:
//     PUSH_TRIGGER_SECRET          (must match Vault push_trigger_secret)
//     FIREBASE_PROJECT_ID
//     FIREBASE_SERVICE_ACCOUNT_KEY (full JSON, stringified)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PUSH_TRIGGER_SECRET = Deno.env.get("PUSH_TRIGGER_SECRET") ?? "";
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID");
const FIREBASE_SERVICE_ACCOUNT_KEY = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_KEY");

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

// Generate a JWT for Google OAuth2 service account authentication
async function getAccessToken(serviceAccountKey: any): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const expiry = now + 3600; // 1 hour

    const header = {
        alg: "RS256",
        typ: "JWT",
    };

    const payload = {
        iss: serviceAccountKey.client_email,
        sub: serviceAccountKey.client_email,
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: expiry,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
    };

    // Base64url encode
    const base64UrlEncode = (obj: any) => {
        const json = JSON.stringify(obj);
        const base64 = btoa(json);
        return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    };

    const headerB64 = base64UrlEncode(header);
    const payloadB64 = base64UrlEncode(payload);
    const unsignedToken = `${headerB64}.${payloadB64}`;

    // Import the private key and sign
    const privateKeyPem = serviceAccountKey.private_key;
    const pemContents = privateKeyPem
        .replace(/-----BEGIN PRIVATE KEY-----/, '')
        .replace(/-----END PRIVATE KEY-----/, '')
        .replace(/\n/g, '');

    const binaryKey = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));

    const cryptoKey = await crypto.subtle.importKey(
        "pkcs8",
        binaryKey,
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["sign"]
    );

    const encoder = new TextEncoder();
    const signature = await crypto.subtle.sign(
        "RSASSA-PKCS1-v1_5",
        cryptoKey,
        encoder.encode(unsignedToken)
    );

    const signatureB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');

    const jwt = `${unsignedToken}.${signatureB64}`;

    // Exchange JWT for access token
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    });

    if (!tokenResponse.ok) {
        const error = await tokenResponse.text();
        throw new Error(`Failed to get access token: ${error}`);
    }

    const tokenData = await tokenResponse.json();
    return tokenData.access_token;
}

Deno.serve(async (req) => {
    const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-Internal-Secret, x-client-info, apikey",
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
        // Validate the request using the shared internal secret (NOT a service role key)
        const internalSecret = req.headers.get("X-Internal-Secret");
        if (!PUSH_TRIGGER_SECRET || !internalSecret || internalSecret !== PUSH_TRIGGER_SECRET) {
            return new Response(
                JSON.stringify({ error: "Unauthorized" }),
                { status: 401, headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

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

        // Count unread notifications for badge (including this new one)
        const { count: unreadCount, error: countError } = await supabase
            .from('notifications')
            .select('*', { count: 'exact', head: true })
            .eq('recipient_user_id', recipientUserId)
            .is('read_at', null);

        if (countError) {
            console.error('Error counting unread notifications:', countError);
        }
        const badgeCount = unreadCount ?? 1;
        console.log(`Badge count for user: ${badgeCount}`);

        if (!tokens || tokens.length === 0) {
            console.log(`No FCM tokens found for user ${recipientUserId}`);
            return new Response(
                JSON.stringify({ success: true, sent: 0, reason: 'no_tokens' }),
                { headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Check if Firebase is configured
        if (!FIREBASE_PROJECT_ID || !FIREBASE_SERVICE_ACCOUNT_KEY) {
            console.error('Firebase not configured: missing FIREBASE_PROJECT_ID or FIREBASE_SERVICE_ACCOUNT_KEY');
            return new Response(
                JSON.stringify({ success: true, sent: 0, reason: 'firebase_not_configured' }),
                { headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Parse service account key
        let serviceAccountKey;
        try {
            serviceAccountKey = JSON.parse(FIREBASE_SERVICE_ACCOUNT_KEY);
        } catch (e) {
            console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY:', e);
            return new Response(
                JSON.stringify({ success: true, sent: 0, reason: 'invalid_service_account' }),
                { headers: { "Content-Type": "application/json", ...corsHeaders } }
            );
        }

        // Get OAuth2 access token
        const accessToken = await getAccessToken(serviceAccountKey);

        // Send to each device using FCM HTTP v1 API
        const fcmTokens = tokens.map(t => t.fcm_token);
        let sentCount = 0;
        const invalidTokens: string[] = [];

        for (const fcmToken of fcmTokens) {
            const fcmPayload = {
                message: {
                    token: fcmToken,
                    notification: {
                        title: notification.title,
                        body: notification.body,
                    },
                    data: {
                        notification_id: notification.id,
                        type: notification.type,
                        band_id: notification.band_id,
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        ...Object.fromEntries(
                            Object.entries(notification.metadata || {}).map(([k, v]) => [k, String(v)])
                        ),
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: 'default',
                                badge: badgeCount,
                            },
                        },
                    },
                    android: {
                        priority: 'high',
                        notification: {
                            sound: 'default',
                            click_action: 'FLUTTER_NOTIFICATION_CLICK',
                        },
                    },
                },
            };

            const fcmResponse = await fetch(
                `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
                {
                    method: 'POST',
                    headers: {
                        'Authorization': `Bearer ${accessToken}`,
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(fcmPayload),
                }
            );

            if (fcmResponse.ok) {
                sentCount++;
                console.log(`FCM sent to token ${fcmToken.substring(0, 20)}...`);
            } else {
                const errorData = await fcmResponse.json();
                console.error(`FCM send failed for token:`, errorData);

                // Check if token is invalid and should be removed
                if (errorData.error?.details) {
                    const isInvalidToken = errorData.error.details.some((d: any) =>
                        d.errorCode === 'UNREGISTERED' ||
                        d.errorCode === 'INVALID_ARGUMENT'
                    );
                    if (isInvalidToken) {
                        invalidTokens.push(fcmToken);
                    }
                }
            }
        }

        console.log(`FCM sent: ${sentCount}/${fcmTokens.length} for notification ${notification.id}`);

        // Clean up invalid tokens
        if (invalidTokens.length > 0) {
            console.log(`Removing ${invalidTokens.length} invalid tokens`);
            await supabase
                .from('device_tokens')
                .delete()
                .in('fcm_token', invalidTokens);
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
        // Log internally but never expose secret-adjacent details in response
        console.error('Error sending push notification:', error);
        // Return success anyway - push delivery failures should never block
        return new Response(
            JSON.stringify({
                success: true,
                sent: 0,
                error: 'internal_error'
            }),
            {
                status: 200, // Return 200 to prevent retries
                headers: { "Content-Type": "application/json", ...corsHeaders },
            }
        );
    }
});
