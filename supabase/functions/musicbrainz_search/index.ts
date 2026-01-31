// MusicBrainz Search Edge Function for Supabase (Deno)
// Searches MusicBrainz for recordings as a fallback when Spotify fails
// Expects: { query: string, limit?: number }
// Returns: { ok: boolean, data?: Recording[], error?: string }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface MusicBrainzRecording {
    title: string;
    artist: string;
    musicbrainz_id: string;
    duration_seconds?: number;
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

        // Search MusicBrainz
        // Note: MusicBrainz requires User-Agent header
        const searchUrl = `https://musicbrainz.org/ws/2/recording/?query=${encodeURIComponent(query)}&fmt=json&limit=${limit}`;
        const searchResponse = await fetch(searchUrl, {
            headers: {
                'User-Agent': 'BandRoadie/1.0.0 (https://bandroadie.com)',
                'Accept': 'application/json',
            },
        });

        if (!searchResponse.ok) {
            console.error('[musicbrainz_search] Search failed:', searchResponse.status);
            return new Response(
                JSON.stringify({ ok: false, error: "MusicBrainz search failed" }),
                { status: searchResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const searchData = await searchResponse.json();
        const recordings: MusicBrainzRecording[] = (searchData.recordings || []).map((recording: any) => ({
            title: recording.title || 'Unknown',
            artist: recording['artist-credit']?.[0]?.name || 'Unknown Artist',
            musicbrainz_id: recording.id,
            duration_seconds: recording.length ? Math.round(recording.length / 1000) : undefined,
        }));

        return new Response(
            JSON.stringify({ ok: true, data: recordings }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('[musicbrainz_search] Error:', error);
        return new Response(
            JSON.stringify({ ok: false, error: "Internal server error" }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
