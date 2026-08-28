// GetSongBPM Lookup Edge Function for Supabase (Deno)
// Fetches tempo (BPM) and musical key for a song by title+artist.
// Expects: { title: string, artist: string, duration_seconds?: number, isrc?: string }
// Returns: { ok: boolean, data?: { bpm: number|null, musicalKey: string|null, confidence: 'medium'|'none' }, error?: string }
//
// Matching accuracy improvements (feature/song-enrichment-accuracy-confidence Phase A):
// - Exact-artist matches now require title similarity (exact/fallback/contains tier)
// - Version-type detection (live/remix/acoustic/cover/demo) rejects mismatched candidates
// - Both exact-artist and artist-variant paths enforce title+version filtering
//
// ----------------------------------------------------------------------------
// Task 1 live API spike findings (docs/features/new-song-key-enrichment/ARCHITECT_PLAN.md §14
// Task 1 / §6.4). Confirmed against the real API this session — supersedes the
// plan's pre-spike assumptions:
//
// - Correct base URL is https://api.getsong.co/ — NOT api.getsongbpm.com, which is a
//   stale legacy domain that is Cloudflare-challenge-walled and unusable server-side.
// - Response envelope: {"search": [...]} on match. On no match: the API returns
//   {"search": {"error": "no result"}} — an object, not an empty array. Callers must
//   check for this shape explicitly rather than assuming `.length === 0` is safe.
// - Combined song+artist disambiguation: `type=both` is correct and required for this
//   use case. The `lookup` param format is strict: `song:<title> artist:<artist>`
//   (literal `song:`/`artist:` prefixes) — plain concatenation returns a 400
//   {"error":"Bad query."}. `type=multi` is not a valid type (also 400) — only
//   `artist` | `song` | `both` are accepted.
// - ISRC-based lookup: confirmed absent. Both `type=isrc` and passing `isrc=` as an
//   extra param return 400 {"error":"Bad query."}. No ISRC parameter is attempted
//   below — matches the already-agreed medium-confidence-only scope (plan §19).
// - `key_of` notation: always Unicode sharp (♯), never flat, across a ~40-result
//   sample spanning sharp-heavy songs. Normalization here converts ♯→#, then maps
//   D#→Eb, G#→Ab, A#→Bb (majors and minors) to match the app's 24-key vocabulary;
//   C#/F# pass through unchanged since they're already in that vocabulary.
// - Malformed entries are real and recurring: results with `"key_of":"m"` (no root
//   note) and tempo/open_key/danceability/acousticness all null appear across
//   unrelated queries. A bare "m" (and anything else that doesn't normalize to one
//   of the app's 24 keys) is rejected to `musicalKey: null` rather than passed through.
// - Duration is not present in any response field — no design change; duration
//   continues to come from the search result that triggered this lookup, not this API.
// - Auth/error shapes: bad key → 401 + {"error":"Invalid API Key, or inactive."}.
//   Good key, no results → 200 + the no-result shape above (not an error status).
// ----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const GETSONGBPM_BASE_URL = 'https://api.getsong.co';

// The app's exact 24-key vocabulary (lib/features/setlists/widgets/key_picker_bottom_sheet.dart)
const VALID_MAJOR_KEYS = new Set(['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B']);
const VALID_MINOR_KEYS = new Set(['Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'Abm', 'Am', 'Bbm', 'Bm']);

// GetSongBPM always returns sharps; map the three that don't match the app's
// vocabulary directly to their enharmonic flat equivalents.
const SHARP_TO_FLAT: Record<string, string> = { 'D#': 'Eb', 'G#': 'Ab', 'A#': 'Bb' };

interface LookupResult {
    bpm: number | null;
    musicalKey: string | null;
    confidence: 'medium' | 'none';
}

/// Normalize a GetSongBPM `key_of` value (e.g. "D#", "Fm", "m") to the app's
/// 24-key vocabulary, or null if it can't be represented.
function normalizeKey(raw: unknown): string | null {
    if (typeof raw !== 'string' || raw.length === 0) return null;

    // GetSongBPM uses Unicode sharp (♯); normalize to ASCII '#' first.
    let key = raw.replace(/♯/g, '#').trim();

    const isMinor = key.endsWith('m');
    let root = isMinor ? key.slice(0, -1) : key;

    // Reject malformed entries with no root note (e.g. bare "m").
    if (root.length === 0) return null;

    if (SHARP_TO_FLAT[root]) {
        root = SHARP_TO_FLAT[root];
    }

    const normalized = isMinor ? `${root}m` : root;

    if (isMinor ? VALID_MINOR_KEYS.has(normalized) : VALID_MAJOR_KEYS.has(normalized)) {
        return normalized;
    }

    return null;
}

/// Normalize an artist name for loose comparison (lowercase, alphanumeric only).
function normalizeArtistName(name: string): string {
    return name
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/[^a-z0-9]/g, '');
}

function normalizeWords(value: string): string[] {
    return value
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/&/g, ' and ')
        .replace(/[^a-z0-9]+/g, ' ')
        .trim()
        .split(/\s+/)
        .filter(Boolean);
}

function normalizeTitleName(title: string): string {
    return normalizeWords(title).join('');
}

function getPrimaryTitleFallback(title: string): string {
    const trimmed = title.replace(/\s*\([^()]*\)\s*$/, '').trim();
    return trimmed.length > 0 ? trimmed : title;
}

function getCandidateTitle(candidate: any): string | null {
    if (typeof candidate?.title === 'string') return candidate.title;
    if (typeof candidate?.song?.title === 'string') return candidate.song.title;
    return null;
}

function isContiguousWordSequence(shorterWords: string[], longerWords: string[]): boolean {
    if (shorterWords.length === 0 || shorterWords.length > longerWords.length) {
        return false;
    }

    for (let start = 0; start <= longerWords.length - shorterWords.length; start += 1) {
        let matches = true;
        for (let offset = 0; offset < shorterWords.length; offset += 1) {
            if (longerWords[start + offset] !== shorterWords[offset]) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }

    return false;
}

function isArtistVariantMatch(requestArtist: string, candidateArtist: string): boolean {
    const requestWords = normalizeWords(requestArtist);
    const candidateWords = normalizeWords(candidateArtist);
    if (requestWords.length === 0 || candidateWords.length === 0) {
        return false;
    }

    const requestCompact = requestWords.join('');
    const candidateCompact = candidateWords.join('');
    if (requestCompact === candidateCompact) {
        return false;
    }

    const shorterWords = requestCompact.length <= candidateCompact.length ? requestWords : candidateWords;
    const longerWords = requestCompact.length <= candidateCompact.length ? candidateWords : requestWords;
    const shorterCompact = shorterWords.join('');
    const longerCompact = longerWords.join('');

    if (!isContiguousWordSequence(shorterWords, longerWords)) {
        return false;
    }

    if (shorterWords.length === 1) {
        return shorterCompact.length >= 6 && (shorterCompact.length / longerCompact.length) >= 0.6;
    }

    return shorterCompact.length >= 8;
}

/// Detect version types indicated by a title's normalized word tokens.
/// Returns flags for live/remix/acoustic/cover/demo.
function detectVersionType(title: string): {
    live: boolean;
    remix: boolean;
    acoustic: boolean;
    cover: boolean;
    demo: boolean;
} {
    const words = new Set(normalizeWords(title));
    return {
        live: words.has('live') || words.has('unplugged'),
        remix: words.has('remix') || words.has('remixed'),
        acoustic: words.has('acoustic'),
        cover: words.has('cover'),
        demo: words.has('demo'),
    };
}

/// Compare title similarity in tiers: exact > fallback (parenthetical trim) > contains > none.
/// Reuses existing normalization helpers unchanged.
function titleSimilarity(requestTitle: string, candidateTitle: string): 'exact' | 'fallback' | 'contains' | 'none' {
    const normalizedRequest = normalizeTitleName(requestTitle);
    const normalizedCandidate = normalizeTitleName(candidateTitle);

    if (normalizedRequest === normalizedCandidate) {
        return 'exact';
    }

    const requestFallback = normalizeTitleName(getPrimaryTitleFallback(requestTitle));
    const candidateFallback = normalizeTitleName(getPrimaryTitleFallback(candidateTitle));

    if (requestFallback === candidateFallback) {
        return 'fallback';
    }

    const requestWords = normalizeWords(requestTitle);
    const candidateWords = normalizeWords(candidateTitle);

    if (isContiguousWordSequence(requestWords, candidateWords) ||
        isContiguousWordSequence(candidateWords, requestWords)) {
        return 'contains';
    }

    return 'none';
}

function noneResult(): LookupResult {
    return { bpm: null, musicalKey: null, confidence: 'none' };
}

function parseTempo(raw: unknown): number | null {
    const tempo = typeof raw === 'string' ? parseFloat(raw) : raw;
    if (typeof tempo === 'number' && !Number.isNaN(tempo)) {
        return Math.round(tempo);
    }
    return null;
}

function selectBestAvailableMatch(matches: any[]): {
    bpm: number | null;
    musicalKey: string | null;
    hasNumericTempo: boolean;
    hasNormalizableKey: boolean;
    index: number;
} | null {
    let bestAvailableMatch: {
        bpm: number | null;
        musicalKey: string | null;
        hasNumericTempo: boolean;
        hasNormalizableKey: boolean;
        index: number;
    } | null = null;

    for (let i = 0; i < matches.length; i += 1) {
        const candidate = matches[i];
        const bpm = parseTempo(candidate?.tempo);
        const musicalKey = normalizeKey(candidate?.key_of);
        const hasNumericTempo = bpm !== null;
        const hasNormalizableKey = musicalKey !== null;

        const isBetterThanCurrent = !bestAvailableMatch ||
            Number(hasNumericTempo) > Number(bestAvailableMatch.hasNumericTempo) ||
            (
                Number(hasNumericTempo) === Number(bestAvailableMatch.hasNumericTempo) &&
                Number(hasNormalizableKey) > Number(bestAvailableMatch.hasNormalizableKey)
            );

        if (isBetterThanCurrent) {
            bestAvailableMatch = {
                bpm,
                musicalKey,
                hasNumericTempo,
                hasNormalizableKey,
                index: i,
            };
        }
    }

    return bestAvailableMatch;
}

async function lookupGetSongBpmForTitle(
    apiKey: string,
    title: string,
    artist: string,
    attempt: 'first' | 'fallback',
): Promise<LookupResult> {
    const lookup = `song:${title} artist:${artist}`;
    // GetSongBPM API expects spaces encoded as '+' (application/x-www-form-urlencoded),
    // not '%20' (encodeURIComponent). Replace spaces after encoding.
    const encodedLookup = encodeURIComponent(lookup).replace(/%20/g, '+');
    const url = `${GETSONGBPM_BASE_URL}/search/?api_key=${encodeURIComponent(apiKey)}&type=both&lookup=${encodedLookup}`;

    const response = await fetch(url, {
        headers: { 'Accept': 'application/json' },
    });

    // Never surface a provider error to the caller — bad key (401), bad query
    // (400), or any other non-2xx all degrade to a "not found" result.
    if (!response.ok) {
        console.log(`[getsongbpm_lookup] attempt=${attempt} reason=provider_non_2xx status=${response.status}`);
        return noneResult();
    }

    const data = await response.json();
    const search = data?.search;

    // No-result shape is {"search": {"error": "no result"}} — an object, not
    // an array. Only treat a real array as candidates.
    if (!Array.isArray(search)) {
        console.log(`[getsongbpm_lookup] attempt=${attempt} reason=no_usable_match detail=no_search_array`);
        return noneResult();
    }

    const normalizedRequestArtist = normalizeArtistName(artist);
    const normalizedRequestTitle = normalizeTitleName(title);
    const requestVersionType = detectVersionType(title);

    // Exact-artist path: require both artist match AND title similarity (not just artist).
    // Also enforce version-type gate: reject candidates with version types the request lacks.
    const exactArtistMatches = search.filter((candidate: any) => {
        const candidateArtist = candidate?.artist?.name;
        const candidateTitle = getCandidateTitle(candidate);
        if (typeof candidateArtist !== 'string' || typeof candidateTitle !== 'string') {
            return false;
        }

        const artistMatches = normalizeArtistName(candidateArtist) === normalizedRequestArtist;
        if (!artistMatches) {
            return false;
        }

        const titleSim = titleSimilarity(title, candidateTitle);
        if (titleSim === 'none') {
            return false;
        }

        const candidateVersionType = detectVersionType(candidateTitle);

        // Reject candidate if it has a version type the request doesn't.
        for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
            if (candidateVersionType[versionKey] && !requestVersionType[versionKey]) {
                return false;
            }
        }

        return true;
    });

    const bestExactArtistMatch = selectBestAvailableMatch(exactArtistMatches);
    if (exactArtistMatches.length > 0 && bestExactArtistMatch &&
        (bestExactArtistMatch.bpm !== null || bestExactArtistMatch.musicalKey !== null)) {
        console.log(
            `[getsongbpm_lookup] attempt=${attempt} reason=exact_artist_match matches=${exactArtistMatches.length} selected_index=${bestExactArtistMatch.index} has_bpm=${bestExactArtistMatch.hasNumericTempo} has_key=${bestExactArtistMatch.hasNormalizableKey}`,
        );
        return {
            bpm: bestExactArtistMatch.bpm,
            musicalKey: bestExactArtistMatch.musicalKey,
            confidence: 'medium',
        };
    }

    // Artist-variant path: already requires title match; add version-type gate.
    if (exactArtistMatches.length === 0) {
        const artistVariantMatches = search.filter((candidate: any) => {
            const candidateArtist = candidate?.artist?.name;
            const candidateTitle = getCandidateTitle(candidate);
            if (typeof candidateArtist !== 'string' || typeof candidateTitle !== 'string') {
                return false;
            }

            const titleMatches = normalizeTitleName(candidateTitle) === normalizedRequestTitle;
            if (!titleMatches) {
                return false;
            }

            const artistVariantMatches = isArtistVariantMatch(artist, candidateArtist);
            if (!artistVariantMatches) {
                return false;
            }

            const candidateVersionType = detectVersionType(candidateTitle);

            // Reject candidate if it has a version type the request doesn't.
            for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
                if (candidateVersionType[versionKey] && !requestVersionType[versionKey]) {
                    return false;
                }
            }

            return true;
        });

        const bestArtistVariantMatch = selectBestAvailableMatch(artistVariantMatches);
        if (artistVariantMatches.length > 0 && bestArtistVariantMatch &&
            (bestArtistVariantMatch.bpm !== null || bestArtistVariantMatch.musicalKey !== null)) {
            console.log(
                `[getsongbpm_lookup] attempt=${attempt} reason=artist_variant_match matches=${artistVariantMatches.length} selected_index=${bestArtistVariantMatch.index} has_bpm=${bestArtistVariantMatch.hasNumericTempo} has_key=${bestArtistVariantMatch.hasNormalizableKey}`,
            );
            return {
                bpm: bestArtistVariantMatch.bpm,
                musicalKey: bestArtistVariantMatch.musicalKey,
                confidence: 'medium',
            };
        }

        console.log(
            `[getsongbpm_lookup] attempt=${attempt} reason=no_usable_match total_candidates=${search.length} exact_matches=0 variant_matches=${artistVariantMatches.length}`,
        );
        return noneResult();
    }

    console.log(
        `[getsongbpm_lookup] attempt=${attempt} reason=no_usable_match total_candidates=${search.length} exact_matches=${exactArtistMatches.length} variant_matches=0`,
    );
    return noneResult();
}

async function lookupGetSongBpm(
    apiKey: string,
    title: string,
    artist: string,
): Promise<LookupResult> {
    const firstAttemptResult = await lookupGetSongBpmForTitle(apiKey, title, artist, 'first');
    if (firstAttemptResult.confidence !== 'none') {
        console.log('[getsongbpm_lookup] fallback_attempted=false result_attempt=first');
        return firstAttemptResult;
    }

    const fallbackTitle = getPrimaryTitleFallback(title);
    if (fallbackTitle === title) {
        console.log('[getsongbpm_lookup] fallback_attempted=false result_attempt=first');
        return firstAttemptResult;
    }

    console.log(`[getsongbpm_lookup] fallback_attempted=true fallback_title="${fallbackTitle}"`);
    const fallbackAttemptResult = await lookupGetSongBpmForTitle(apiKey, fallbackTitle, artist, 'fallback');
    console.log('[getsongbpm_lookup] fallback_attempted=true result_attempt=fallback');
    return fallbackAttemptResult;
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL");
        const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

        if (!supabaseUrl || !serviceRoleKey) {
            return new Response(
                JSON.stringify({ ok: false, error: "Server configuration error" }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Secrets set via `supabase secrets set` are available as environment variables
        const apiKey = Deno.env.get("GETSONGBPM_API_KEY");

        if (!apiKey) {
            console.error('[getsongbpm_lookup] Missing GetSongBPM API key');
            return new Response(
                JSON.stringify({ ok: false, error: "GetSongBPM API not configured" }),
                { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        const body = await req.json();
        const title = body.title as string;
        const artist = body.artist as string;
        const isrc = body.isrc as string | undefined;

        if (!title || !artist) {
            return new Response(
                JSON.stringify({ ok: false, error: "title and artist are required" }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        if (isrc) {
            // Confirmed absent from the API (see header comment) — logged for
            // future-phase telemetry only, falls through to the title+artist path.
            console.log('[getsongbpm_lookup] isrc provided but not queryable, falling through:', isrc);
        }

        // Never throws — any failure degrades to a "not found" result so the
        // review screen never blocks on this call (same contract as spotify_audio_features).
        let result: LookupResult;
        try {
            result = await lookupGetSongBpm(apiKey, title, artist);
        } catch (error) {
            console.error('[getsongbpm_lookup] Lookup failed:', error);
            result = noneResult();
        }

        return new Response(
            JSON.stringify({ ok: true, data: result }),
            { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('[getsongbpm_lookup] Error:', error);
        return new Response(
            JSON.stringify({ ok: false, error: "Internal server error" }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
