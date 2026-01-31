// Spotify Search Edge Function for Supabase (Deno)
// Searches Spotify for tracks using the Spotify Web API
// Expects: { query: string, limit?: number }
// Returns: { ok: boolean, data?: Track[], error?: string }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface SpotifyTrack {
    title: string;
    artist: string;
    spotify_id: string;
    duration_seconds?: number;
    album_artwork?: string;
}

// Global token cache to avoid repeated auth requests
let cachedToken: string | null = null;
let tokenExpiry: number = 0;

async function getSpotifyToken(clientId: string, clientSecret: string): Promise<string | null> {
    // Return cached token if still valid (with 60s buffer)
    if (cachedToken && Date.now() < tokenExpiry - 60000) {
        return cachedToken;
    }

    try {
        const response = await fetch('https://accounts.spotify.com/api/token', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Authorization': `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
            },
            body: 'grant_type=client_credentials',
        });

        if (!response.ok) {
            console.error('[spotify_search] Token request failed:', response.status);
            return null;
        }

        const data = await response.json();
        cachedToken = data.access_token;
        // Spotify tokens typically expire in 3600 seconds (1 hour)
        tokenExpiry = Date.now() + (data.expires_in * 1000);

        return cachedToken;
    } catch (error) {
        console.error('[spotify_search] Error getting token:', error);
        return null;
    }
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        // Get Spotify credentials from Supabase Vault
        const supabaseUrl = Deno.env.get("SUPABASE_URL");
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

        if (!supabaseUrl || !serviceRoleKey) {
            return new Response(
                JSON.stringify({ ok: false, error: "Server configuration error" }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const supabase = createClient(supabaseUrl, serviceRoleKey);

        // Get Spotify credentials from vault
        const { data: secrets } = await supabase.rpc('get_secrets', {
            secret_names: ['SPOTIFY_CLIENT_ID', 'SPOTIFY_CLIENT_SECRET']
        }).single();

        const clientId = secrets?.SPOTIFY_CLIENT_ID || Deno.env.get("SPOTIFY_CLIENT_ID");
        const clientSecret = secrets?.SPOTIFY_CLIENT_SECRET || Deno.env.get("SPOTIFY_CLIENT_SECRET");

        if (!clientId || !clientSecret) {
            console.error('[spotify_search] Missing Spotify credentials');
            return new Response(
                JSON.stringify({ ok: false, error: "Spotify API not configured" }),
                { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Parse request body
        const body = await req.json();
        const query = body.query as string;
        const limit = Math.min(body.limit || 10, 50); // Max 50 results

        if (!query || query.trim().length === 0) {
            return new Response(
                JSON.stringify({ ok: false, error: "Query is required" }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Get Spotify access token
        const token = await getSpotifyToken(clientId, clientSecret);
        if (!token) {
            return new Response(
                JSON.stringify({ ok: false, error: "Failed to authenticate with Spotify" }),
                { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Search Spotify
        const searchUrl = `https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=track&limit=${limit}`;
        const searchResponse = await fetch(searchUrl, {
            headers: {
                'Authorization': `Bearer ${token}`,
            },
        });

        if (!searchResponse.ok) {
            console.error('[spotify_search] Search failed:', searchResponse.status);
            return new Response(
                JSON.stringify({ ok: false, error: "Spotify search failed" }),
                { status: searchResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const searchData = await searchResponse.json();
        const tracks: SpotifyTrack[] = (searchData.tracks?.items || []).map((track: any) => ({
            title: track.name,
            artist: track.artists?.[0]?.name || 'Unknown Artist',
            spotify_id: track.id,
            duration_seconds: track.duration_ms ? Math.round(track.duration_ms / 1000) : undefined,
            album_artwork: track.album?.images?.[0]?.url,
        }));

        return new Response(
            JSON.stringify({ ok: true, data: tracks }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('[spotify_search] Error:', error);
        return new Response(
            JSON.stringify({ ok: false, error: "Internal server error" }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
