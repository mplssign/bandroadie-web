# Hybrid BPM Enrichment Feature

## Overview
Optional BPM enrichment using a hybrid fallback strategy:
1. **Primary:** Spotify Audio Features API (when Spotify ID available)
2. **Secondary:** AcousticBrainz API (fallback when Spotify fails or unavailable)
3. **Final Fallback:** Manual entry only

This feature runs asynchronously after songs are saved and never blocks song creation.

## Architecture

### Strategy: Spotify → AcousticBrainz → Give Up

```
Song Saved (bpm = null)
    ↓
Fire-and-forget: _attemptBpmEnrichment()
    ↓
Has Spotify ID? → YES → Try Spotify Audio Features
    ↓                         ↓
   NO                    Success? → Update BPM (WHERE bpm IS NULL) → DONE
    ↓                         ↓
    ↓                       Fail
    ↓                         ↓
    └─────────────→ Try AcousticBrainz
                              ↓
                        Success? → Update BPM (WHERE bpm IS NULL) → DONE
                              ↓
                            Fail → GIVE UP (manual entry only)
```

### Edge Functions

#### 1. `spotify_audio_features` (Primary)
#### 1. `spotify_audio_features` (Primary)
**Location:** `supabase/functions/spotify_audio_features/index.ts`

**Purpose:** Fetches BPM/tempo directly from Spotify's audio analysis data.

**Flow:**
1. Receive Spotify track ID
2. Fetch OAuth token (with caching)
3. Call `/v1/audio-features/{id}` endpoint
4. Extract `tempo` field
5. Round to nearest integer

**API Endpoint:**
- Spotify: `https://api.spotify.com/v1/audio-features/{spotify_id}`

**Response:**
```json
{
  "tempo": 120.5  // or null if not found
}
```

**Authentication:** OAuth Client Credentials flow (cached for 1 hour)

**Advantages:**
- High accuracy (official Spotify data)
- Excellent coverage for popular songs
- Fast response time

#### 2. `acousticbrainz_bpm` (Fallback)

#### 2. `acousticbrainz_bpm` (Fallback)
**Location:** `supabase/functions/acousticbrainz_bpm/index.ts`

**Purpose:** Fetches BPM data from AcousticBrainz when Spotify unavailable or fails.

**Flow:**
1. Search MusicBrainz API for recording ID using song title and artist
2. Fetch AcousticBrainz high-level data using recording ID
3. Extract BPM from `rhythm.bpm.value` field
4. Round to nearest integer

**API Endpoints:**
- MusicBrainz: `https://musicbrainz.org/ws/2/recording/?query={searchQuery}&fmt=json&limit=1`
- AcousticBrainz: `https://acousticbrainz.org/api/v1/{recordingId}/high-level`

**Response:**
```json
{
  "bpm": 120  // or null if not found
}
```

**Authentication:** None required (free public APIs)

**Advantages:**
- No authentication required
- Good coverage for less popular songs
- Crowd-sourced data

**Limitations:**
- Variable accuracy
- Slower (two-step lookup)
- May not have data for all songs

### Repository Integration
**Location:** `lib/features/setlists/setlist_repository.dart`

**Main Method:** `_attemptBpmEnrichment()`
```dart
Future<void> _attemptBpmEnrichment({
  required String songId,
  required String bandId,
  required String title,
  required String artist,
  String? spotifyId,
}) async
```

**Helper Methods:**
- `_fetchSpotifyBpm()` - Returns int? from Spotify Audio Features
- `_fetchAcousticBrainzBpm()` - Returns int? from AcousticBrainz

**Triggered From:**
- `upsertExternalSong()` - After creating song from Spotify/MusicBrainz lookup

**Pattern:**
```dart
if (bpm == null) {
  _attemptBpmEnrichment(
    songId: newId,
    bandId: bandId,
    title: normalizedTitle,
    artist: normalizedArtist,
    spotifyId: spotifyId, // May be null
  ).then((_) {
    // Fire-and-forget - enrichment complete or failed silently
  });
}
```

**Update Method:**
Uses `update_song_metadata` RPC which has conditional BPM update logic:
```sql
bpm = CASE 
  WHEN p_bpm IS NOT NULL AND bpm IS NULL THEN p_bpm
  ELSE bpm
END
```

This ensures BPM only updates when currently NULL, preventing overwrites of user edits.

### BPM Clamping
All BPM values are clamped to sane musical range: **40-240 BPM**

This prevents:
- Data errors (e.g., 0 or 999999)
- Half/double tempo mistakes
- API anomalies

## Critical Rules

### Non-Blocking Behavior
✅ **DO:**
- Use fire-and-forget pattern (`.then()` without `await`)
- Return immediately after song creation
- Only log failures in debug mode

❌ **DON'T:**
- Never `await` enrichment calls
- Never block song save operations
- Never throw exceptions that could reach callers

### Data Integrity
✅ **DO:**
- Only enrich when `bpm == null`
- Use existing BPM values when available
- Allow manual BPM edits to override

❌ **DON'T:**
- Never overwrite existing BPM values
- Never make enrichment required for save to succeed
- Never assume enrichment will succeed

### Error Handling
✅ **DO:**
- Catch all exceptions in `_enrichBpmFromAcousticBrainz()`
- Log failures at debug level only
- Treat enrichment failures as non-fatal

❌ **DON'T:**
- Never propagate enrichment errors to UI
- Never show error messages to users for enrichment failures
- Never retry failed enrichments

## User Experience

### Expected Behavior
1. User adds song via Spotify search (e.g., "Rockstar" by Nickelback)
2. Song saves immediately to database with `bpm: null`
3. Song appears in UI instantly
4. **If Spotify ID available:** ~500ms-1s later, BPM populates from Spotify
5. **If no Spotify ID or Spotify fails:** ~1-2 seconds later, tries AcousticBrainz
6. **If both fail:** BPM remains empty (user can edit manually)
7. BPM is clamped to 40-240 range if outside bounds

### Success Rates (Estimated)
- **Spotify:** ~95% success for popular songs with Spotify ID
- **AcousticBrainz:** ~60% success for songs not in Spotify
- **Combined:** ~97% success rate overall

### No UI Changes
- No loading indicators
- No error messages for failed enrichment
- BPM field just appears when ready (or stays empty)
- Same manual editing behavior as before

## Testing

### Manual Test Steps
1. Launch app on iPhone: `flutter run -d 00008130-001665323488001C`
2. Search for a song (e.g., "Rockstar")
3. Add song to setlist
4. Observe song saves immediately
5. Wait 1-2 seconds
6. Check if BPM field populates
7. Verify manual BPM editing still works

### Edge Cases to Test
- **Song not in AcousticBrainz:** Should save with `bpm: null`, no errors
- **Network failure:** Should save with `bpm: null`, no errors
- **Existing BPM value:** Should not overwrite, enrichment skipped
- **Manual BPM edit after enrichment:** Should persist, not be overwritten

### Debug Logging
Look for these messages in Flutter console:
```
[SetlistRepository] 🎵 Attempting BPM enrichment for "Song Title" by Artist
[SetlistRepository] ✓ Spotify BPM=120 for "Song Title"
[SetlistRepository] ✓ Updated BPM to 120 for song abc123
```

Or fallback to AcousticBrainz:
```
[SetlistRepository] 🎵 Attempting BPM enrichment for "Song Title" by Artist
[SetlistRepository] Spotify BPM fetch failed: [error]
[SetlistRepository] ✓ AcousticBrainz BPM=118 for "Song Title" by Artist
[SetlistRepository] ✓ Updated BPM to 118 for song abc123
```

Or on complete failure:
```
[SetlistRepository] No BPM found for "Song Title" by Artist
```

Clamping:
```
[SetlistRepository] ⚠️ Clamped BPM from 300 to 240
```

## Deployment

### Edge Functions
Both functions must be deployed:

```bash
cd /Users/tonyholmes/Documents/Apps/bandroadie
supabase functions deploy spotify_audio_features --project-ref nekwjxvgbveheooyorjo
supabase functions deploy acousticbrainz_bpm --project-ref nekwjxvgbveheooyorjo
```

### Database Migration
Migration 084 adds conditional BPM update logic:

```bash
supabase db push --include-all
```

This ensures `update_song_metadata` RPC only updates BPM when it's currently NULL.

### Secrets Required
Spotify API requires credentials (set in Supabase Dashboard):
- `SPOTIFY_CLIENT_ID`
- `SPOTIFY_CLIENT_SECRET`

AcousticBrainz requires no authentication.

## Comparison to Manual-Only BPM

| Aspect | Manual Only (Before) | Hybrid Enrichment (Now) |
|--------|----------------------|-------------------------|
| **Song creation speed** | Instant | Instant (enrichment is async) |
| **BPM availability** | Only when user enters | Auto-populated ~97% of time |
| **Blocking** | None | None (fire-and-forget) |
| **Accuracy** | User-dependent | High (Spotify) → Medium (AB) |
| **Editability** | Always | Always (same behavior) |
| **Error handling** | N/A | Silent failures, never surfaces |
| **Data source** | User | Spotify → AcousticBrainz → User |
| **Philosophy** | Band-owned only | Best-effort hints + band-owned |

## Future Considerations

### Potential Enhancements (Not Implemented)
- Batch enrichment for existing songs with `bpm: null`
- Retry logic with exponential backoff
- Cache AcousticBrainz results in Supabase
- Fallback to other BPM APIs (e.g., TheAudioDB)

### Why These Aren't Implemented
Per user requirements:
- "Do not add any retry logic"
- "Do not add any batch processing"
- Keep it simple and non-invasive

## Troubleshooting

### BPM Not Appearing
1. Check Supabase Edge Function logs for errors
2. Verify Edge Function is deployed: `supabase functions list --project-ref nekwjxvgbveheooyorjo`
3. Check Flutter debug console for enrichment messages
4. Try different song (may not be in AcousticBrainz database)

### Songs Saving Slowly
- Enrichment is fire-and-forget and should **not** slow saves
- If saves are slow, issue is **not** related to BPM enrichment
- Check network connectivity or Supabase RLS policies

### BPM Overwriting Manual Edits
- Should never happen - enrichment only runs when `bpm == null`
- If observed, file bug report with reproduction steps

### Code Locations

### Edge Functions
- `supabase/functions/spotify_audio_features/index.ts` - Spotify BPM fetch (primary)
- `supabase/functions/acousticbrainz_bpm/index.ts` - AcousticBrainz BPM fetch (fallback)
- `supabase/functions/spotify_audio_features/deno.json` - Deno config
- `supabase/functions/acousticbrainz_bpm/deno.json` - Deno config

### Repository Layer
- `lib/features/setlists/setlist_repository.dart`
  - Line ~3540: `_attemptBpmEnrichment()` main coordinator method
  - Line ~3610: `_fetchSpotifyBpm()` Spotify helper
  - Line ~3635: `_fetchAcousticBrainzBpm()` AcousticBrainz helper
  - Line ~2905: Fire-and-forget call in `upsertExternalSong()`

### Database Migration
- `supabase/migrations/084_update_song_metadata_conditional_bpm.sql` - Conditional BPM update logic

### No UI Changes
- No modifications to song lookup overlay
- No modifications to song cards
- BPM field already exists and is reactive
