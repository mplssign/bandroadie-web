// supabase/functions/send-bug-report/index.ts
// Edge function to send bug reports via Resend (no email client needed)
//
// IMPORTANT: The recipient email must match kSupportEmail in:
//   lib/app/constants/app_constants.dart
// Keep these in sync when changing the support email address.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Centralized support email - must match kSupportEmail in app_constants.dart
const RECIPIENT_EMAIL = "hello@bandroadie.com";

// Format timestamp as "2:20 PM, Jan 1, 2026"
function formatTimestamp(date: Date): string {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  let hours = date.getHours();
  const minutes = date.getMinutes();
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12; // 0 should be 12

  const minuteStr = minutes < 10 ? `0${minutes}` : `${minutes}`;
  const month = months[date.getMonth()];
  const day = date.getDate();
  const year = date.getFullYear();

  return `${hours}:${minuteStr} ${ampm}, ${month} ${day}, ${year}`;
}

Deno.serve(async (req) => {
  // CORS headers - must include all headers the Supabase client sends
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, x-client-info, apikey",
  };

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: corsHeaders,
    });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  try {
    const body = await req.json();
    const {
      type,
      description,
      screenName,
      bandId,
      userId,
      platform,
      osVersion,
      appVersion,
      buildNumber,
    } = body;

    if (!description || description.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Description is required" }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    if (!RESEND_API_KEY) {
      console.error("[send-bug-report] RESEND_API_KEY not set");
      return new Response(
        JSON.stringify({ error: "Email service not configured" }),
        { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    // Create Supabase client to fetch band names and user name
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fetch ALL bands the user is a member of
    let bandNames = "none";
    if (userId) {
      // Get all band IDs the user belongs to via band_members table
      const { data: memberships } = await supabase
        .from("band_members")
        .select("band_id")
        .eq("user_id", userId);

      if (memberships && memberships.length > 0) {
        const bandIds = memberships.map((m: { band_id: string }) => m.band_id);

        // Fetch band names for all those bands
        const { data: bands } = await supabase
          .from("bands")
          .select("name")
          .in("id", bandIds);

        if (bands && bands.length > 0) {
          bandNames = bands.map((b: { name: string }) => b.name).join(", ");
        }
      }
    }

    // Fetch user name (first + last) from users table
    let userName = "Unknown";
    if (userId) {
      const { data: user } = await supabase
        .from("users")
        .select("first_name, last_name")
        .eq("id", userId)
        .single();
      if (user) {
        const firstName = user.first_name || "";
        const lastName = user.last_name || "";
        userName = `${firstName} ${lastName}`.trim() || "Unknown";
      }
    }

    // Build subject line
    const reportType = type === "bug" ? "Bug Report" : "Feature Request";
    const screen = screenName || "Report Bugs";
    const platformName = platform || "Unknown";
    const subject = `BandRoadie ${reportType} — ${screen} — ${platformName}`;

    // Use client-provided local timestamp, or fall back to server UTC time
    const timestamp = body.localTimestamp || `${formatTimestamp(new Date())} (UTC)`;
    const emailBody = `
<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto;">
  <h2 style="color: #f43f5e;">🎸 BandRoadie ${reportType}</h2>
  
  <div style="background: #f8f9fa; padding: 16px; border-radius: 8px; margin-bottom: 24px;">
    <h3 style="margin-top: 0; color: #333;">Description</h3>
    <p style="white-space: pre-wrap; color: #333;">${escapeHtml(description)}</p>
  </div>
  
  <div style="background: #e9ecef; padding: 16px; border-radius: 8px;">
    <h3 style="margin-top: 0; color: #666; font-size: 14px;">Diagnostic Info</h3>
    <table style="width: 100%; font-size: 13px; color: #666;">
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">Band:</td><td>${escapeHtml(bandNames)}</td></tr>
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">User:</td><td>${escapeHtml(userName)}</td></tr>
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">Platform:</td><td>${platformName}</td></tr>
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">OS Version:</td><td>${osVersion || "unknown"}</td></tr>
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">App Version:</td><td>${appVersion || "unknown"} (${buildNumber || "?"})</td></tr>
      <tr><td style="padding: 4px 8px 4px 0; font-weight: 600;">Timestamp:</td><td>${timestamp}</td></tr>
    </table>
  </div>
</div>
`;

    // Plain text version
    const textBody = `
BandRoadie ${reportType}

DESCRIPTION:
${description}

--- Diagnostic Info ---
Band: ${bandNames}
User: ${userName}
Platform: ${platformName}
OS Version: ${osVersion || "unknown"}
App Version: ${appVersion || "unknown"} (${buildNumber || "?"})
Timestamp: ${timestamp}
`;

    // Send via Resend
    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "BandRoadie <noreply@bandroadie.com>",
        to: [RECIPIENT_EMAIL],
        reply_to: userId ? undefined : undefined, // Could add user email if available
        subject: subject,
        html: emailBody,
        text: textBody,
      }),
    });

    if (!resendResponse.ok) {
      const errorText = await resendResponse.text();
      console.error("[send-bug-report] Resend API error:", errorText);
      return new Response(
        JSON.stringify({ error: "Failed to send email" }),
        { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    const resendData = await resendResponse.json();
    console.log("[send-bug-report] Email sent successfully:", resendData.id);

    return new Response(
      JSON.stringify({ ok: true, emailId: resendData.id }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      }
    );
  } catch (error) {
    console.error("[send-bug-report] Error:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
});

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
