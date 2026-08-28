// Unit tests for Phase A: matching accuracy improvements
// Run with: deno test --allow-env index.test.ts

import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";

// Copy helper functions from index.ts for testing
// (In production, these would be imported from a shared module)

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

function normalizeArtistName(name: string): string {
    return name
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .toLowerCase()
        .replace(/[^a-z0-9]/g, '');
}

function getPrimaryTitleFallback(title: string): string {
    const trimmed = title.replace(/\s*\([^()]*\)\s*$/, '').trim();
    return trimmed.length > 0 ? trimmed : title;
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

// Tests for detectVersionType
Deno.test("detectVersionType - detects live versions", () => {
    const result = detectVersionType("Come As You Are (Live)");
    assertEquals(result.live, true);
    assertEquals(result.remix, false);
    assertEquals(result.acoustic, false);
});

Deno.test("detectVersionType - detects unplugged as live", () => {
    const result = detectVersionType("Layla (Unplugged)");
    assertEquals(result.live, true);
});

Deno.test("detectVersionType - detects remix versions", () => {
    const result = detectVersionType("Song Name (Remix)");
    assertEquals(result.remix, true);
    assertEquals(result.live, false);
});

Deno.test("detectVersionType - detects acoustic versions", () => {
    const result = detectVersionType("Wonderful Tonight (Acoustic)");
    assertEquals(result.acoustic, true);
});

Deno.test("detectVersionType - detects cover versions", () => {
    const result = detectVersionType("All Along the Watchtower (Cover)");
    assertEquals(result.cover, true);
});

Deno.test("detectVersionType - detects demo versions", () => {
    const result = detectVersionType("New Song (Demo)");
    assertEquals(result.demo, true);
});

Deno.test("detectVersionType - plain version has no flags", () => {
    const result = detectVersionType("Come As You Are");
    assertEquals(result.live, false);
    assertEquals(result.remix, false);
    assertEquals(result.acoustic, false);
    assertEquals(result.cover, false);
    assertEquals(result.demo, false);
});

// Tests for titleSimilarity
Deno.test("titleSimilarity - exact match returns 'exact'", () => {
    const result = titleSimilarity("Come As You Are", "Come As You Are");
    assertEquals(result, "exact");
});

Deno.test("titleSimilarity - exact match ignores case and punctuation", () => {
    const result = titleSimilarity("Come As You Are", "come as you are");
    assertEquals(result, "exact");
});

Deno.test("titleSimilarity - parenthetical fallback match returns 'fallback'", () => {
    const result = titleSimilarity(
        "Come Out And Play (Keep 'Em Separated)",
        "Come Out And Play"
    );
    assertEquals(result, "fallback");
});

Deno.test("titleSimilarity - contiguous word sequence returns 'contains'", () => {
    // Use a case with non-parenthetical suffix so it can't resolve at fallback tier
    const result = titleSimilarity("Rhiannon", "Rhiannon - 1997 Remaster");
    assertEquals(result, "contains");
});

Deno.test("titleSimilarity - completely different titles return 'none'", () => {
    const result = titleSimilarity("Come As You Are", "Smells Like Teen Spirit");
    assertEquals(result, "none");
});

Deno.test("titleSimilarity - same artist different title returns 'none'", () => {
    const result = titleSimilarity("Song A", "Song B");
    assertEquals(result, "none");
});

// Regression tests
Deno.test("REGRESSION - parenthetical subtitle still matches via fallback", () => {
    // Regression guard for getsongbpm-title-fallback-parenthetical
    const result = titleSimilarity(
        "Come Out And Play (Keep 'Em Separated)",
        "Come Out And Play"
    );
    assertEquals(result, "fallback");
});

Deno.test("REGRESSION - diacritic artist still matches", () => {
    // Regression guard for getsongbpm-artist-diacritic-mismatch
    const artist1 = "Motörhead";
    const artist2 = "Motorhead";
    assertEquals(normalizeArtistName(artist1), normalizeArtistName(artist2));
});

Deno.test("REGRESSION - diacritic title still matches", () => {
    const result = titleSimilarity("Café", "Cafe");
    assertEquals(result, "exact");
});

// Version-type filtering tests
Deno.test("Version-type filtering - live candidate rejected when request is studio", () => {
    const requestType = detectVersionType("Come As You Are");
    const candidateType = detectVersionType("Come As You Are (Live)");
    
    // Request is plain (no live flag), candidate is live
    assertEquals(requestType.live, false);
    assertEquals(candidateType.live, true);
    
    // This should be rejected: candidate has a version type the request doesn't
    let shouldReject = false;
    for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
        if (candidateType[versionKey] && !requestType[versionKey]) {
            shouldReject = true;
            break;
        }
    }
    assertEquals(shouldReject, true);
});

Deno.test("Version-type filtering - remix candidate rejected when request is plain", () => {
    const requestType = detectVersionType("Song Name");
    const candidateType = detectVersionType("Song Name (Remix)");
    
    assertEquals(requestType.remix, false);
    assertEquals(candidateType.remix, true);
    
    let shouldReject = false;
    for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
        if (candidateType[versionKey] && !requestType[versionKey]) {
            shouldReject = true;
            break;
        }
    }
    assertEquals(shouldReject, true);
});

Deno.test("Version-type filtering - live candidate accepted when request is also live", () => {
    const requestType = detectVersionType("Come As You Are (Live)");
    const candidateType = detectVersionType("Come As You Are (Live)");
    
    assertEquals(requestType.live, true);
    assertEquals(candidateType.live, true);
    
    let shouldReject = false;
    for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
        if (candidateType[versionKey] && !requestType[versionKey]) {
            shouldReject = true;
            break;
        }
    }
    assertEquals(shouldReject, false);
});

Deno.test("Version-type filtering - plain candidate accepted when request is live", () => {
    // Request indicates live, candidate is plain - should be allowed as weaker fallback
    const requestType = detectVersionType("Come As You Are (Live)");
    const candidateType = detectVersionType("Come As You Are");
    
    assertEquals(requestType.live, true);
    assertEquals(candidateType.live, false);
    
    let shouldReject = false;
    for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
        if (candidateType[versionKey] && !requestType[versionKey]) {
            shouldReject = true;
            break;
        }
    }
    // Candidate has no version flags, so it shouldn't be rejected
    assertEquals(shouldReject, false);
});

Deno.test("Version-type filtering - both plain accepted", () => {
    const requestType = detectVersionType("Come As You Are");
    const candidateType = detectVersionType("Come As You Are");
    
    assertEquals(requestType.live, false);
    assertEquals(candidateType.live, false);
    
    let shouldReject = false;
    for (const versionKey of ['live', 'remix', 'acoustic', 'cover', 'demo'] as const) {
        if (candidateType[versionKey] && !requestType[versionKey]) {
            shouldReject = true;
            break;
        }
    }
    assertEquals(shouldReject, false);
});
