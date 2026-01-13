// Accept Invite Edge Function for Supabase (Deno)
// Accepts all pending invitations for the authenticated user based on their email
// This is a fallback/helper - the main invite acceptance happens client-side in AuthGate
// Expects: {} (no body required, uses JWT to identify user)
// Returns: { success, accepted_count, band_names }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Get env vars
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase env vars" }), 
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create admin client for privileged operations
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Get the JWT from the Authorization header to identify the current user
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }), 
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Create a client with the user's JWT to get their identity
    const supabaseUser = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") || serviceRoleKey, {
      global: { headers: { Authorization: authHeader } }
    });

    // Get the authenticated user
    const { data: { user: authUser }, error: authError } = await supabaseUser.auth.getUser();
    if (authError || !authUser || !authUser.email) {
      console.error("[accept-invite] Auth error:", authError);
      return new Response(
        JSON.stringify({ error: "Invalid or expired session. Please sign in again." }), 
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`[accept-invite] Processing invites for: ${authUser.email}`);

    // Find all pending invitations for this user's email
    const { data: invitations, error: inviteError } = await supabaseAdmin
      .from("band_invitations")
      .select("id, band_id, bands(name)")
      .eq("email", authUser.email.toLowerCase())
      .in("status", ["pending", "sent"]);

    if (inviteError) {
      console.error("[accept-invite] Error fetching invitations:", inviteError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch invitations" }), 
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    if (!invitations || invitations.length === 0) {
      return new Response(
        JSON.stringify({ success: true, accepted_count: 0, band_names: [] }), 
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const acceptedBands: string[] = [];

    for (const invite of invitations) {
      try {
        // Add user to band_members
        await supabaseAdmin.from("band_members").upsert({
          band_id: invite.band_id,
          user_id: authUser.id,
          role: 'member',
        }, { onConflict: "band_id,user_id" });

        // Mark invitation as accepted
        await supabaseAdmin
          .from("band_invitations")
          .update({ status: "accepted", accepted_at: new Date().toISOString() })
          .eq("id", invite.id);

        const bandName = (invite.bands as { name?: string })?.name || "Unknown";
        acceptedBands.push(bandName);
        console.log(`[accept-invite] Accepted invite to: ${bandName}`);
      } catch (e) {
        console.error(`[accept-invite] Error accepting invite ${invite.id}:`, e);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        accepted_count: acceptedBands.length,
        band_names: acceptedBands,
      }), 
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error("[accept-invite] Unexpected error:", error);
    return new Response(
      JSON.stringify({ error: "An unexpected error occurred. Please try again." }), 
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
