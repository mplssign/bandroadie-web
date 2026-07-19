// Accept Invite Edge Function for Supabase (Deno)
// Accepts invitations for the authenticated user based on their email.
// If token is provided in request body, that invite is targeted first.
// Expects: { token?: string }
// Returns legacy keys + deterministic band id fields:
// { success, accepted_count, band_names, accepted_band_id, accepted_band_ids }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get env vars
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase env vars" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create admin client for privileged operations
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Get the JWT from the Authorization header to identify the current user
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Create a client with the user's JWT to get their identity
    const supabaseUser = createClient(
      supabaseUrl,
      Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey,
      {
        global: { headers: { Authorization: authHeader } },
      },
    );

    // Get the authenticated user
    const {
      data: { user: authUser },
      error: authError,
    } = await supabaseUser.auth.getUser();
    if (authError || !authUser || !authUser.email) {
      console.error("[accept-invite] Auth error:", authError);
      return new Response(
        JSON.stringify({
          error: "Invalid or expired session. Please sign in again.",
        }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    console.log(`[accept-invite] Processing invites for: ${authUser.email}`);

    const requestBody = await req.json().catch(() => ({}));
    const rawToken = requestBody?.token;
    const inviteToken =
      typeof rawToken === "string" && rawToken.trim().length > 0
        ? rawToken.trim()
        : null;

    let invitations: Array<{
      id: string;
      band_id: string;
      bands?: { name?: string } | null;
    }> = [];

    if (inviteToken) {
      const { data: inviteByToken, error: tokenInviteError } = await supabaseAdmin
        .from("band_invitations")
        .select("id, band_id, bands(name)")
        .eq("token", inviteToken)
        .eq("email", authUser.email.toLowerCase())
        .in("status", ["pending", "sent"])
        .maybeSingle();

      if (tokenInviteError) {
        console.error(
          "[accept-invite] Error fetching token invitation:",
          tokenInviteError,
        );
        return new Response(
          JSON.stringify({ error: "Failed to fetch invitation" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      if (inviteByToken) {
        invitations = [inviteByToken];
      }
    }

    if (!inviteToken || invitations.length === 0) {
      const { data: allInvites, error: inviteError } = await supabaseAdmin
        .from("band_invitations")
        .select("id, band_id, bands(name)")
        .eq("email", authUser.email.toLowerCase())
        .in("status", ["pending", "sent"]);

      if (inviteError) {
        console.error("[accept-invite] Error fetching invitations:", inviteError);
        return new Response(
          JSON.stringify({ error: "Failed to fetch invitations" }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      invitations = (allInvites ?? []) as Array<{
        id: string;
        band_id: string;
        bands?: { name?: string } | null;
      }>;
    }

    if (!invitations || invitations.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          accepted_count: 0,
          band_names: [],
          accepted_band_id: null,
          accepted_band_ids: [],
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const acceptedBands: string[] = [];
    const acceptedBandIds: string[] = [];

    for (const invite of invitations) {
      try {
        // Atomically: upsert band_members + mark invitation accepted.
        // Single RPC call wraps both writes in a PostgreSQL transaction.
        // band_id is derived from the invite row inside the function.
        // Role is hardcoded to 'member' inside the function.
        const { error: rpcError } = await supabaseAdmin.rpc(
          "accept_band_invite",
          {
            p_invite_id: invite.id,
            p_user_id: authUser.id,
          },
        );

        if (rpcError) {
          console.error(
            `[accept-invite] RPC error for invite ${invite.id}:`,
            rpcError.message,
          );
          continue;
        }

        const bandName =
          (invite.bands as { name?: string })?.name || "Unknown";
        acceptedBands.push(bandName);
        acceptedBandIds.push(invite.band_id);
        console.log(`[accept-invite] Accepted invite to: ${bandName}`);
      } catch (e) {
        console.error(
          `[accept-invite] Error accepting invite ${invite.id}:`,
          e,
        );
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        accepted_count: acceptedBands.length,
        band_names: acceptedBands,
        accepted_band_id: inviteToken ? (acceptedBandIds[0] ?? null) : null,
        accepted_band_ids: acceptedBandIds,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    console.error("[accept-invite] Unexpected error:", error);
    return new Response(
      JSON.stringify({
        error: "An unexpected error occurred. Please try again.",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
