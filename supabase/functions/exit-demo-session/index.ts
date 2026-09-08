// supabase/functions/exit-demo-session/index.ts
// Edge function to fully tear down a demo (anonymous) session.
//
// Orchestrates two steps that must run in this order:
//   1. Call exit_demo_session() RPC (user-scoped client) — deletes the
//      demo_sessions row, cascading the visitor's clone bands and every
//      band-scoped child row, including any setlists/gigs row referencing
//      the visitor via created_by.
//   2. Call auth.admin.deleteUser() (service-role client) — safe only after
//      step 1, since nothing references the visitor's uid anymore.
//
// Follows the delete_user_account precedent: the SQL RPC boundary stays at
// public.*, and the final auth.users deletion is routed through this
// Edge Function using auth.admin.deleteUser() under the service role.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Accept only anonymous (demo) sessions — the inverse polarity of the
// reject-anon guard used by send-bug-report/send-band-invite. verify_jwt=true
// only checks that the JWT is validly signed; it does not distinguish a real
// user from an anonymous demo session, so this function must never be
// reachable from a real-user session.
function isAnonymousDemo(req: Request): { ok: true; uid: string } | { ok: false } {
  const authHeader = req.headers.get("Authorization") || "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const parts = token.split(".");
  if (parts.length !== 3) return { ok: false };
  try {
    const base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(base64));
    if (payload?.is_anonymous === true && typeof payload?.sub === "string") {
      return { ok: true, uid: payload.sub };
    }
    return { ok: false };
  } catch {
    return { ok: false };
  }
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

  const authHeader = req.headers.get("Authorization") || "";
  const anonCheck = isAnonymousDemo(req);
  if (!anonCheck.ok) {
    return new Response(
      JSON.stringify({ error: "Not a demo session" }),
      { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
  const uid = anonCheck.uid;

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { error: rpcError } = await userClient.rpc("exit_demo_session");
  if (rpcError) {
    console.error("[exit-demo-session] exit_demo_session RPC failed:", rpcError);
    return new Response(
      JSON.stringify({ error: `Demo exit failed: ${rpcError.message}` }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error: deleteError } = await serviceClient.auth.admin.deleteUser(uid);
  if (deleteError) {
    console.error("[exit-demo-session] auth.admin.deleteUser failed:", deleteError);
    return new Response(
      JSON.stringify({ error: `Demo exit failed: ${deleteError.message}` }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});
