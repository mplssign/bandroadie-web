// iTunes Search Edge Function for Supabase (Deno)
// Proxies iTunes Search API to avoid CORS issues on Web
// Expects: { query: string, limit?: number }
// Returns: { ok: boolean, data?: Track[], error?: string }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ItunesTrack {
    title: string;
    artist: string;
    duration_seconds?: number;
    album_artwork?: string;
    itunes_id: number;
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        // Parse request body
        const body = await req.json();
        const query = body.query as string;
        const limit = Math.min(body.limit || 10, 25); // Max 25 results

        if (!query || query.trim().length === 0) {
            return new Response(
                JSON.stringify({ ok: false, error: "Query is required" }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Search iTunes
        const searchUrl = new URL('https://itunes.apple.com/search');
        searchUrl.searchParams.set('term', query);
        searchUrl.searchParams.set('entity', 'song');
        searchUrl.searchParams.set('limit', limit.toString());

        const searchResponse = await fetch(searchUrl.toString());

        if (!searchResponse.ok) {
            console.error('[itunes_search] Search failed:', searchResponse.status);
            return new Response(
                JSON.stringify({ ok: false, error: "iTunes search failed" }),
                { status: searchResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const searchData = await searchResponse.json();
        const tracks: ItunesTrack[] = (searchData.results || []).map((track: any) => ({
            title: track.trackName || 'Unknown',
            artist: track.artistName || 'Unknown Artist',
            duration_seconds: track.trackTimeMillis ? Math.round(track.trackTimeMillis / 1000) : undefined,
            album_artwork: track.artworkUrl100 || undefined,
            itunes_id: track.trackId,
        }));

        return new Response(
            JSON.stringify({ ok: true, data: tracks }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('[itunes_search] Error:', error);
        return new Response(
            JSON.stringify({ ok: false, error: "Internal server error" }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
