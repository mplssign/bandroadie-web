// AcousticBrainz BPM Edge Function for Supabase (Deno)
// Fetches BPM/tempo for a song using AcousticBrainz API
// Expects: { title: string, artist: string }
// Returns: { bpm: number | null }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

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
        // Parse request body
        const body = await req.json();
        const title = (body.title as string)?.trim();
        const artist = (body.artist as string)?.trim();

        if (!title || !artist) {
            return new Response(
                JSON.stringify({ bpm: null }),
                { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        console.log(`[acousticbrainz_bpm] Looking up: "${title}" by ${artist}`);

        // Step 1: Search MusicBrainz for the recording ID
        const searchQuery = `${title} ${artist}`.replace(/\s+/g, '%20');
        const searchUrl = `https://musicbrainz.org/ws/2/recording/?query=${searchQuery}&fmt=json&limit=1`;

        const searchResponse = await fetch(searchUrl, {
            headers: {
                'User-Agent': 'BandRoadie/1.0.0 (https://bandroadie.com)',
                'Accept': 'application/json',
            },
        });

        if (!searchResponse.ok) {
            console.error(`[acousticbrainz_bpm] MusicBrainz search failed: ${searchResponse.status}`);
            return new Response(
                JSON.stringify({ bpm: null }),
                { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const searchData = await searchResponse.json();
        const recordings = searchData.recordings || [];

        if (recordings.length === 0) {
            console.log('[acousticbrainz_bpm] No MusicBrainz recordings found');
            return new Response(
                JSON.stringify({ bpm: null }),
                { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const recordingId = recordings[0].id;
        console.log(`[acousticbrainz_bpm] Found recording ID: ${recordingId}`);

        // Step 2: Fetch high-level data from AcousticBrainz
        const acousticUrl = `https://acousticbrainz.org/api/v1/${recordingId}/high-level`;

        const acousticResponse = await fetch(acousticUrl, {
            headers: {
                'Accept': 'application/json',
            },
        });

        if (!acousticResponse.ok) {
            console.log(`[acousticbrainz_bpm] AcousticBrainz data not available: ${acousticResponse.status}`);
            return new Response(
                JSON.stringify({ bpm: null }),
                { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const acousticData = await acousticResponse.json();

        // Step 3: Extract BPM from rhythm.bpm
        const bpmValue = acousticData?.highlevel?.rhythm?.all?.bpm?.value;

        if (bpmValue && typeof bpmValue === 'number' && bpmValue > 0) {
            const roundedBpm = Math.round(bpmValue);
            console.log(`[acousticbrainz_bpm] Found BPM: ${roundedBpm}`);

            return new Response(
                JSON.stringify({ bpm: roundedBpm }),
                { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        console.log('[acousticbrainz_bpm] No BPM data in response');
        return new Response(
            JSON.stringify({ bpm: null }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('[acousticbrainz_bpm] Error:', error);
        return new Response(
            JSON.stringify({ bpm: null }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
