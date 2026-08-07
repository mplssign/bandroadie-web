# Architect Plan: Group External Song Lookup Results

## Feature Overview

Split external song lookup results into two UI sections:

- **Songs**: Results where the query matches the song title
- **Artists**: Results where the query matches only the artist name (no title match)

This resolves ambiguity when users search for artist names (e.g., "Queen") that are also song titles.

## Problem Statement

The Song Lookup overlay (`song_lookup_overlay.dart` line 666) renders external results as a single flat list under "External Results". The ranking algorithm heavily favors title matches, causing artist searches to return songs with matching titles instead of the artist's catalog.

Example: Searching "Queen" returns a song literally titled "Queen" at the top, pushing Queen's actual catalog (Bohemian Rhapsody, We Will Rock You, etc.) below the fold.

## Solution Design

### Core Change: Grouped Results Structure

Create a new `GroupedSongResults` class defined in `external_song_lookup_service.dart`:

```dart
class GroupedSongResults {
  final List<SongLookupResult> songs;
  final List<SongLookupResult> artists;
  final List<SongLookupResult> _otherRanked;

  const GroupedSongResults({
    required this.songs,
    required this.artists,
    required List<SongLookupResult> otherRanked,
  }) : _otherRanked = otherRanked;

  SongLookupResult? get bestMatch =>
      songs.isNotEmpty ? songs.first :
      artists.isNotEmpty ? artists.first :
      _otherRanked.isNotEmpty ? _otherRanked.first :
      null;
}
```

**Rationale for `_otherRanked` bucket:**

- The `song_enrichment_orchestrator.dart` (line 196) constructs queries as `'${song.title} ${song.artist}'`
- Example: "bohemian rhapsody queen"
- When iTunes returns title="Bohemian Rhapsody", artist="Queen":
  - Title check: `"bohemian rhapsody".contains("bohemian rhapsody queen")` → FALSE (title is shorter)
  - Artist check: `"queen".contains("bohemian rhapsody queen")` → FALSE (artist is shorter)
  - Without a 3rd bucket, this result is discarded and `bestMatch` returns null
- The `_otherRanked` bucket keeps these "no-match" results ranked by popularity/API position
- UI never displays this bucket—only `bestMatch` accessor uses it

## Implementation Steps

### Step 1: Add GroupedSongResults Class

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** After line 67 (after SongLookupResult class)

Add the class shown above.

### Step 2: Update \_CacheEntry Results Type

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Line 80

**Change from:**

```dart
final List<SongLookupResult> results;
```

**Change to:**

```dart
final GroupedSongResults results;
```

**Rationale:** The cache now stores grouped results instead of flat lists.

### Step 3: Update \_inFlightRequests Map Type

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Line 99

**Change from:**

```dart
final Map<String, Future<List<SongLookupResult>>> _inFlightRequests = {};
```

**Change to:**

```dart
final Map<String, Future<GroupedSongResults>> _inFlightRequests = {};
```

**Rationale:** Tracks in-flight requests that now return grouped results.

### Step 4: Add Grouping Method

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** After line 424 (after \_rankResults method)

```dart
GroupedSongResults _groupResults(
  String query,
  List<SongLookupResult> results, {
  int songsLimit = 6,
  int artistsLimit = 6,
}) {
  final lowerQuery = query.toLowerCase().trim();

  final songMatches = <SongLookupResult>[];
  final artistMatches = <SongLookupResult>[];
  final otherMatches = <SongLookupResult>[];

  for (final result in results) {
    final lowerTitle = result.title.toLowerCase();
    final lowerArtist = result.artist.toLowerCase();

    final isTitleMatch =
        lowerTitle == lowerQuery ||
        lowerTitle.startsWith(lowerQuery) ||
        lowerTitle.contains(lowerQuery);

    if (isTitleMatch) {
      songMatches.add(result);
    } else if (lowerArtist.contains(lowerQuery)) {
      artistMatches.add(result);
    } else {
      otherMatches.add(result);
    }
  }

  final rankedSongs = _rankResults(query, songMatches);
  final rankedArtists = _rankResults(query, artistMatches);
  final rankedOthers = _rankResults(query, otherMatches);

  return GroupedSongResults(
    songs: rankedSongs.take(songsLimit).toList(),
    artists: rankedArtists.take(artistsLimit).toList(),
    otherRanked: rankedOthers.take(6).toList(),
  );
}
```

### Step 5: Update searchExternalSongs Signature

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Line 113

**Change from:**

```dart
Future<List<SongLookupResult>> searchExternalSongs(
  String query, {
  int limit = 10,
  bool forceRefresh = false,
})
```

**Change to:**

```dart
Future<GroupedSongResults> searchExternalSongs(
  String query, {
  int songsLimit = 6,
  int artistsLimit = 6,
  bool forceRefresh = false,
})
```

### Step 6: Update searchExternalSongs Method Body

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Lines 112-157 (entire method)

**Replace the entire method body with:**

```dart
Future<GroupedSongResults> searchExternalSongs(
  String query, {
  int songsLimit = 6,
  int artistsLimit = 6,
  bool forceRefresh = false,
}) async {
  final normalizedQuery = _normalizeQuery(query);
  final cacheKey = '$normalizedQuery-$songsLimit-$artistsLimit';

  // Minimum query length
  if (normalizedQuery.length < 2) {
    return const GroupedSongResults(
      songs: [],
      artists: [],
      otherRanked: [],
    );
  }

  // Check cache first
  if (!forceRefresh && _cache.containsKey(cacheKey)) {
    final entry = _cache[cacheKey]!;
    if (!entry.isExpired) {
      if (kDebugMode) {
        debugPrint('[ExternalSongLookup] Cache hit for "$cacheKey"');
      }
      return entry.results;
    }
    _cache.remove(cacheKey);
  }

  // Return in-flight request if exists
  if (_inFlightRequests.containsKey(cacheKey)) {
    if (kDebugMode) {
      debugPrint(
        '[ExternalSongLookup] Returning in-flight request for "$cacheKey"',
      );
    }
    return _inFlightRequests[cacheKey]!;
  }

  // Create the request - CRITICAL: Pass normalizedQuery (the search text), not cacheKey
  final request = _performExternalSearch(
    normalizedQuery,
    songsLimit: songsLimit,
    artistsLimit: artistsLimit,
  );
  _inFlightRequests[cacheKey] = request;

  try {
    final results = await request;
    _cache[cacheKey] = _CacheEntry(results);
    return results;
  } finally {
    _inFlightRequests.remove(cacheKey);
  }
}
```

**Critical distinctions:**

- `cacheKey` (format: `"query-6-6"`) is used ONLY for `_cache` and `_inFlightRequests` map keys
- `normalizedQuery` (format: `"queen"`) is passed to `_performExternalSearch()` as the actual search text
- `normalizedQuery` flows through to `_groupResults()` for title/artist classification
- Mixing these up would corrupt API calls (searching for "queen-6-6" instead of "queen")

### Step 7: Update \_performExternalSearch Signature and fetchLimit

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Line 163

**Change from:**

```dart
Future<List<SongLookupResult>> _performExternalSearch(
  String query,
  int limit,
) async {
  final fetchLimit = (limit * 3).clamp(10, 50);
```

**Change to:**

```dart
Future<GroupedSongResults> _performExternalSearch(
  String query, {
  required int songsLimit,
  required int artistsLimit,
}) async {
  final fetchLimit = ((songsLimit + artistsLimit) * 3).clamp(10, 50);
```

### Step 8: Replace Truncation with Grouping

**File:** `lib/features/songs/external_song_lookup_service.dart`  
**Location:** Lines ~180-211

**Replace all three `.take(limit).toList()` calls with:**

```dart
return _groupResults(query, ranked, songsLimit: songsLimit, artistsLimit: artistsLimit);
```

**Specific changes:**

- Line ~183: Replace `return ranked.take(limit).toList();`
- Line ~192: Replace `return ranked.take(limit).toList();`
- Line ~202 and 210: Replace `return ranked.take(limit).toList();`

### Step 9: Update Orchestrator Consumer

**File:** `lib/features/songs/services/song_enrichment_orchestrator.dart`  
**Location:** Lines 197-207

**Change from:**

```dart
final searchResults = await _lookupService.searchExternalSongs(
  query,
  limit: 1,
);

if (searchResults.isEmpty ||
    searchResults.first.durationSeconds == null) {
  durationNotFound = true;
} else {
  fetchedDuration = searchResults.first.durationSeconds;
}
```

**Change to:**

```dart
final groupedResults = await _lookupService.searchExternalSongs(query);
final bestResult = groupedResults.bestMatch;

if (bestResult == null || bestResult.durationSeconds == null) {
  durationNotFound = true;
} else {
  fetchedDuration = bestResult.durationSeconds;
}
```

**Rationale:** Uses default limits (6+6+6 = 18 fetched). The `bestMatch` accessor returns songs→artists→otherRanked priority, ensuring combined queries like "bohemian rhapsody queen" still find results via the `_otherRanked` bucket.

### Step 10: Update Overlay State

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`  
**Location:** Line 106

**Change from:**

```dart
List<SongLookupResult> _externalResults = [];
```

**Change to:**

```dart
List<SongLookupResult> _songResults = [];
List<SongLookupResult> _artistResults = [];
```

### Step 11: Update \_searchExternal Method

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`  
**Location:** Lines 187-226

**Change from:**

```dart
Future<void> _searchExternal(String query) async {
  if (query.isEmpty || query.length < 3) {
    setState(() {
      _externalResults = [];
      _isSearchingExternal = false;
      _externalError = null;
    });
    return;
  }

  setState(() {
    _isSearchingExternal = true;
    _externalError = null;
  });

  try {
    final results = await _externalService.searchExternalSongs(query);

    final catalogKeys = _filteredSongs
        .map((s) => '${s.title.toLowerCase()}|${s.artist.toLowerCase()}')
        .toSet();

    final filtered = results.where((result) {
      final key =
          '${result.title.toLowerCase()}|${result.artist.toLowerCase()}';
      return !catalogKeys.contains(key);
    }).toList();

    if (mounted) {
      setState(() {
        _externalResults = filtered;
        _isSearchingExternal = false;
      });
    }
  } catch (e) {
    debugPrint('[SongLookup] External search error: $e');
    if (mounted) {
      setState(() {
        _externalResults = [];
        _isSearchingExternal = false;
        _externalError = e.toString();
      });
    }
  }
}
```

**Change to:**

```dart
Future<void> _searchExternal(String query) async {
  if (query.isEmpty || query.length < 3) {
    setState(() {
      _songResults = [];
      _artistResults = [];
      _isSearchingExternal = false;
      _externalError = null;
    });
    return;
  }

  setState(() {
    _isSearchingExternal = true;
    _externalError = null;
  });

  try {
    final groupedResults = await _externalService.searchExternalSongs(query);

    final catalogKeys = _filteredSongs
        .map((s) => '${s.title.toLowerCase()}|${s.artist.toLowerCase()}')
        .toSet();

    final filteredSongs = groupedResults.songs.where((result) {
      final key =
          '${result.title.toLowerCase()}|${result.artist.toLowerCase()}';
      return !catalogKeys.contains(key);
    }).toList();

    final filteredArtists = groupedResults.artists.where((result) {
      final key =
          '${result.title.toLowerCase()}|${result.artist.toLowerCase()}';
      return !catalogKeys.contains(key);
    }).toList();

    if (mounted) {
      setState(() {
        _songResults = filteredSongs;
        _artistResults = filteredArtists;
        _isSearchingExternal = false;
      });
    }
  } catch (e) {
    debugPrint('[SongLookup] External search error: $e');
    if (mounted) {
      setState(() {
        _songResults = [];
        _artistResults = [];
        _isSearchingExternal = false;
        _externalError = e.toString();
      });
    }
  }
}
```

### Step 12: Update \_buildResultsList UI

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`  
**Location:** Lines 666-754

**Change from:**

```dart
Widget _buildResultsList() {
  final hasCatalogResults = _filteredSongs.isNotEmpty;
  final hasExternalResults = _externalResults.isNotEmpty;

  return ListView(
    // ... catalog section unchanged ...

    // External results section
    else if (hasExternalResults) ...[
      if (hasCatalogResults) const SizedBox(height: Spacing.space12),
      _buildSectionHeader('External Results', Icons.cloud_rounded),
      ...(_externalResults.map(
        (result) => _ExternalSongRow(
          result: result,
          onTap: () => _handleExternalSongTap(result),
          isAdding: _isAdding,
        ),
      )),
    ],
```

**Change to:**

```dart
Widget _buildResultsList() {
  final hasCatalogResults = _filteredSongs.isNotEmpty;
  final hasSongResults = _songResults.isNotEmpty;
  final hasArtistResults = _artistResults.isNotEmpty;

  return ListView(
    // ... catalog section unchanged ...

    // Songs section
    else if (hasSongResults) ...[
      if (hasCatalogResults) const SizedBox(height: Spacing.space12),
      _buildSectionHeader('Songs', Icons.music_note_rounded),
      ...(_songResults.map(
        (result) => _ExternalSongRow(
          result: result,
          onTap: () => _handleExternalSongTap(result),
          isAdding: _isAdding,
        ),
      )),
    ],

    // Artists section
    if (hasArtistResults) ...[
      if (hasCatalogResults || hasSongResults)
        const SizedBox(height: Spacing.space12),
      _buildSectionHeader('Artists', Icons.person_rounded),
      ...(_artistResults.map(
        (result) => _ExternalSongRow(
          result: result,
          onTap: () => _handleExternalSongTap(result),
          isAdding: _isAdding,
        ),
      )),
    ],
```

**Also update empty state check** (line ~675):

```dart
if (_filteredSongs.isEmpty &&
    _songResults.isEmpty &&
    _artistResults.isEmpty &&
    !_isSearchingExternal &&
    _externalError == null) {
  return _buildNoResultsState();
}
```

### Step 13: Update \_buildBody Condition

**File:** `lib/features/setlists/widgets/song_lookup_overlay.dart`  
**Location:** Line ~500

**Change from:**

```dart
if (_filteredSongs.isEmpty &&
    _externalResults.isEmpty &&
    !_isSearchingExternal &&
    _externalError == null) {
  return _buildNoResultsState();
}
```

**Change to:**

```dart
if (_filteredSongs.isEmpty &&
    _songResults.isEmpty &&
    _artistResults.isEmpty &&
    !_isSearchingExternal &&
    _externalError == null) {
  return _buildNoResultsState();
}
```

## Test Cases

### Test 1: Search "Queen" (Artist Ambiguity)

**Steps:**

1. Open Song Lookup overlay
2. Type "queen"

**Expected:**

- **Songs section:** Shows song titled "Queen" (if exists)
- **Artists section:** Shows Queen's catalog:
  - "Bohemian Rhapsody" by Queen
  - "We Will Rock You" by Queen
  - "Don't Stop Me Now" by Queen

### Test 2: Search "Yesterday" (Title Match)

**Steps:**

1. Search "yesterday"

**Expected:**

- **Songs section:** "Yesterday" by The Beatles
- **Artists section:** Empty (no artist named "Yesterday")

### Test 3: Orchestrator Duration Lookup

**Steps:**

1. Add "Bohemian Rhapsody" by "Queen" to catalog (no duration)
2. Trigger enrichment

**Expected:**

- Query constructed: "bohemian rhapsody queen"
- iTunes returns: title="Bohemian Rhapsody", artist="Queen"
- Classification:
  - Title check: "bohemian rhapsody" cannot contain longer string "bohemian rhapsody queen" → FALSE
  - Artist check: "queen" cannot contain "bohemian rhapsody queen" → FALSE
  - Result goes to `_otherRanked` bucket
- `bestMatch` returns first from `_otherRanked` (ranked by popularity ~90+)
- Duration (354 seconds) extracted successfully

### Test 4: Catalog Deduplication

**Steps:**

1. Add "Bohemian Rhapsody" to catalog
2. Search "bohemian rhapsody"

**Expected:**

- **In Catalog:** Shows local copy
- **Songs section:** Does NOT show duplicate from iTunes
- Both lists filtered by same catalog key pattern

## Risks & Mitigation

### Risk 1: API Return Type Breaking Change

**Impact:** `searchExternalSongs()` changes from `List<SongLookupResult>` to `GroupedSongResults`

**Mitigation:** Only two call sites exist:

1. `song_lookup_overlay.dart` line 205 (updated in Step 11)
2. `song_enrichment_orchestrator.dart` line 197 (updated in Step 9)

Both are updated in this plan. No other consumers found via grep.

### Risk 2: Orchestrator Regression

**Impact:** Duration lookup could fail if `bestMatch` returns null

**Mitigation:**

- `_otherRanked` bucket ensures combined queries still find results
- Fallback chain: songs → artists → otherRanked → null
- Test Case 3 validates this specific scenario

### Risk 3: Cache Key Collisions

**Impact:** New format `"query-songsLimit-artistsLimit"` vs old `"query"`

**Mitigation:**

- Cache has 5-minute TTL (line 86) - stale entries auto-expire
- No manual migration needed
- Worst case: one extra API call per query after deploy

## Out of Scope

The following items are explicitly excluded from this implementation:

- **Edge Functions:** No changes to `itunes_search` or `musicbrainz_search` Supabase Edge Functions. The existing CORS proxy logic remains unchanged.
- **CORS Proxy:** No modifications to CORS proxy work (already merged as PR #127).
- **Dead Code:** Leave `_debounceTimer` and `cancelPendingSearch()` untouched in `external_song_lookup_service.dart`. These are unused but not removed in this plan.
- **UI Copy:** No guitar or musical-instrument emoji (🎸, 🎵, etc.) in any new section headers or empty states. Use standard iOS glyphs only (`Icons.music_note_rounded`, `Icons.person_rounded`). This is a standing brand override.

## Files Modified

| File                                                            | Lines Modified                       | Changes                                                                                         |
| --------------------------------------------------------------- | ------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `lib/features/songs/external_song_lookup_service.dart`          | ~68, ~113, ~118-157, ~163-211, ~425+ | Add GroupedSongResults, \_groupResults method, update signatures, change fetchLimit computation |
| `lib/features/setlists/widgets/song_lookup_overlay.dart`        | ~106, ~187-226, ~500, ~666-754       | Split state, update \_searchExternal, modify UI rendering                                       |
| `lib/features/songs/services/song_enrichment_orchestrator.dart` | ~197-207                             | Use bestMatch accessor                                                                          |

**Total estimated:** ~150 lines changed/added across 3 files

## Validation Checklist

Before marking complete, verify:

- [ ] `GroupedSongResults` class added with `_otherRanked` field and `bestMatch` getter
- [ ] `_groupResults()` method added and classifies into 3 buckets
- [ ] `searchExternalSongs()` signature updated with `songsLimit`/`artistsLimit`
- [ ] `fetchLimit = ((songsLimit + artistsLimit) * 3).clamp(10, 50)` implemented
- [ ] Cache keys include both limits
- [ ] Orchestrator uses `bestMatch` accessor
- [ ] Overlay splits results into `_songResults` and `_artistResults`
- [ ] UI renders two sections: "Songs" and "Artists"
- [ ] Section icons: `Icons.music_note_rounded` and `Icons.person_rounded`
- [ ] Test Case 3 (orchestrator) passes with worked example
- [ ] No compiler errors
- [ ] `flutter analyze` passes

## Notes for Engineer

- All line numbers are approximate—use grep to find exact locations
- The `_otherRanked` bucket is critical for orchestrator compatibility
- Do not add new files—work only in the three files listed
- Test on macOS first, then Web
- Pay special attention to Step 9 (orchestrator)—this is the regression risk area
