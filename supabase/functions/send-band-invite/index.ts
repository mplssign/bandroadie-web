// supabase/functions/send-band-invite/index.ts
// Edge function to send band invitation emails via Resend
//
// Called from Flutter app after creating a band_invitations row
// Sends a magic link email so the invitee can join the band

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

// App URL for deep links (production)
const APP_URL = "https://app.bandroadie.com";

interface InvitePayload {
    bandInvitationId: string;
}

Deno.serve(async (req) => {
    const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers":
            "Content-Type, Authorization, x-client-info, apikey",
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
        const payload: InvitePayload = await req.json();
        const { bandInvitationId } = payload;

        if (!bandInvitationId) {
            return new Response(
                JSON.stringify({ error: "bandInvitationId is required" }),
                {
                    status: 400,
                    headers: { "Content-Type": "application/json", ...corsHeaders },
                }
            );
        }

        console.log(`Processing band invitation: ${bandInvitationId}`);

        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

        // Fetch the invitation details
        const { data: invitation, error: inviteError } = await supabase
            .from("band_invitations")
            .select("id, email, token, status, band_id, invited_by")
            .eq("id", bandInvitationId)
            .single();

        if (inviteError || !invitation) {
            console.error("Failed to fetch invitation:", inviteError);
            return new Response(
                JSON.stringify({ error: "Invitation not found" }),
                {
                    status: 404,
                    headers: { "Content-Type": "application/json", ...corsHeaders },
                }
            );
        }

        // Fetch band name separately
        const { data: band } = await supabase
            .from("bands")
            .select("name")
            .eq("id", invitation.band_id)
            .single();

        // Fetch inviter name from users table
        let inviterName = "Someone";
        if (invitation.invited_by) {
            const { data: inviter } = await supabase
                .from("users")
                .select("first_name, last_name")
                .eq("id", invitation.invited_by)
                .single();

            if (inviter) {
                inviterName = `${inviter.first_name || ""} ${inviter.last_name || ""}`.trim() || "Someone";
            }
        }

        const recipientEmail = invitation.email;
        const bandName = band?.name || "a band";

        console.log(
            `Sending invite to ${recipientEmail} for band "${bandName}" from ${inviterName}`
        );

        // Always use the invite token URL
        // The InviteScreen will handle authentication if needed
        // This avoids the complexity of magic link fragment handling
        const inviteLink = `${APP_URL}/invite?token=${invitation.token}`;
        console.log(`Generated invite link: ${inviteLink}`);

        // Send email via Resend
        const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>You're invited to join ${bandName}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #1a1a1a; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #1a1a1a; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table width="100%" cellpadding="0" cellspacing="0" style="max-width: 480px; background-color: #2a2a2a; border-radius: 16px; overflow: hidden;">
          <!-- Header -->
          <tr>
            <td style="padding: 32px 32px 24px; text-align: center;">
              <h1 style="margin: 0; color: #F43F5E; font-size: 28px; font-weight: 700;">BandRoadie</h1>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td style="padding: 0 32px 32px;">
              <h2 style="margin: 0 0 16px; color: #ffffff; font-size: 22px; font-weight: 600; text-align: center;">
                You're invited to join ${bandName}!
              </h2>
              <p style="margin: 0 0 24px; color: #a0a0a0; font-size: 16px; line-height: 1.5; text-align: center;">
                ${inviterName} has invited you to join their band on BandRoadie – the app for managing rehearsals, gigs, and setlists.
              </p>

              <!-- CTA Button -->
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td align="center" style="padding: 8px 0 24px;">
                    <a href="${inviteLink}" style="display: inline-block; padding: 14px 32px; background-color: #F43F5E; color: #ffffff; font-size: 16px; font-weight: 600; text-decoration: none; border-radius: 8px;">
                      Accept Invitation
                    </a>
                  </td>
                </tr>
              </table>

              <p style="margin: 0; color: #666666; font-size: 14px; text-align: center;">
                If the button doesn't work, copy and paste this link:<br>
                <a href="${inviteLink}" style="color: #F43F5E; word-break: break-all;">${inviteLink}</a>
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 24px 32px; background-color: #222222; text-align: center;">
              <p style="margin: 0; color: #666666; font-size: 12px;">
                © ${new Date().getFullYear()} BandRoadie. All rights reserved.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`;

        const resendResponse = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${RESEND_API_KEY}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from: "BandRoadie <noreply@bandroadie.com>",
                to: recipientEmail,
                subject: `${inviterName} invited you to join ${bandName} on BandRoadie`,
                html: emailHtml,
            }),
        });

        if (!resendResponse.ok) {
            const errorText = await resendResponse.text();
            console.error("Resend API error:", errorText);

            // Update invitation status to error
            await supabase
                .from("band_invitations")
                .update({ status: "error" })
                .eq("id", bandInvitationId);

            return new Response(
                JSON.stringify({ error: "Failed to send email", details: errorText }),
                {
                    status: 500,
                    headers: { "Content-Type": "application/json", ...corsHeaders },
                }
            );
        }

        const resendResult = await resendResponse.json();
        console.log("Email sent successfully:", resendResult);

        // Update invitation status to sent
        await supabase
            .from("band_invitations")
            .update({ status: "sent" })
            .eq("id", bandInvitationId);

        return new Response(
            JSON.stringify({ success: true, emailId: resendResult.id }),
            {
                status: 200,
                headers: { "Content-Type": "application/json", ...corsHeaders },
            }
        );
    } catch (error) {
        console.error("Error processing invitation:", error);
        return new Response(
            JSON.stringify({ error: "Internal server error" }),
            {
                status: 500,
                headers: { "Content-Type": "application/json", ...corsHeaders },
            }
        );
    }
});