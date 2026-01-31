# BPM Feature - Deployment Guide

## Overview

This implementation adds automatic BPM (tempo) fetching from Spotify when songs are added via Song Lookup. The feature is completely non-blocking and will never prevent song creation if Spotify API fails.

## What Changed

### 1. Edge Functions Created
Three new Supabase Edge Functions were added:

- **spotify_search** - Searches Spotify for tracks
- **spotify_audio_features** - Fetches BPM/tempo for a specific Spotify track
- **musicbrainz_search** - Fallback search using MusicBrainz

Location: `supabase/functions/`

### 2. Repository Updates
Updated `lib/features/setlists/setlist_repository.dart`:

- Added BPM enrichment logic to `upsertExternalSong()` method
- Added fallback BPM fetching for existing songs without BPM
- All BPM fetching is asynchronous and fire-and-forget

### 3. UI Updates
Updated `lib/features/setlists/widgets/song_lookup_overlay.dart`:

- Now passes BPM from search results to `upsertExternalSong()`
- Includes album artwork in song creation

## Deployment Steps

### Step 1: Deploy Edge Functions

The Edge Functions need to be deployed to Supabase. You'll need the Supabase CLI installed.

```bash
# Install Supabase CLI if not already installed
brew install supabase/tap/supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Deploy the functions
supabase functions deploy spotify_search
supabase functions deploy spotify_audio_features
supabase functions deploy musicbrainz_search
```

### Step 2: Set Spotify API Credentials

The Edge Functions require Spotify API credentials. You need to:

1. Create a Spotify Developer App at https://developer.spotify.com/dashboard
2. Get your Client ID and Client Secret
3. Store them in Supabase Vault or as environment variables

#### Option A: Using Supabase Vault (Recommended)

```sql
-- In Supabase SQL Editor
INSERT INTO vault.secrets (name, secret) 
VALUES 
  ('SPOTIFY_CLIENT_ID', 'your_spotify_client_id'),
  ('SPOTIFY_CLIENT_SECRET', 'your_spotify_client_secret');
```

Then create a helper function to retrieve secrets:

```sql
CREATE OR REPLACE FUNCTION get_secrets(secret_names TEXT[])
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_object_agg(name, decrypted_secret)
  INTO result
  FROM vault.decrypted_secrets
  WHERE name = ANY(secret_names);
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION get_secrets(TEXT[]) TO service_role;
```

#### Option B: Using Environment Variables

Set environment variables for each function:

```bash
supabase secrets set SPOTIFY_CLIENT_ID=your_spotify_client_id
supabase secrets set SPOTIFY_CLIENT_SECRET=your_spotify_client_secret
```

### Step 3: Verify Database Schema

The `songs` table should already have a nullable `bpm` column. Verify with:

```sql
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'songs' AND column_name = 'bpm';
```

Expected result:
```
column_name | data_type | is_nullable
------------|-----------|-------------
bpm         | integer   | YES
```

If the column doesn't exist (unlikely), add it:

```sql
ALTER TABLE public.songs 
ADD COLUMN bpm INTEGER;
```

### Step 4: Test the Implementation

1. **Build and run the Flutter app:**
   ```bash
   flutter clean
   flutter pub get
   flutter run -d macos  # or chrome, ios, etc.
   ```

2. **Test Song Lookup flow:**
   - Open a setlist
   - Tap "Add Songs"
   - Search for a song from Spotify
   - Add the song
   - Verify BPM appears in the song details (may take a few seconds)

3. **Check logs:**
   - Watch for `[SetlistRepository]` debug prints
   - Check Supabase Edge Function logs in dashboard

## How It Works

### Normal Flow (Spotify Success)

1. User searches for a song via Song Lookup
2. `ExternalSongLookupService` calls `spotify_search` Edge Function
3. For each result, `spotify_audio_features` Edge Function is called to get BPM
4. Song results include BPM if available
5. When user adds song, `upsertExternalSong` is called with BPM
6. Song is created/updated with BPM immediately

### Fallback Flow (BPM Missing)

1. If BPM wasn't fetched during search, song is still created
2. A background task (`enrichSongBpmFromSpotify`) is triggered
3. Task searches Spotify for the song
4. If found, fetches audio features
5. Updates song record with BPM via `update_song_metadata` RPC
6. User sees BPM appear when they next view the song

### Error Handling

All BPM fetching is wrapped in try-catch blocks:
- Spotify API failures are logged but don't block song creation
- Missing credentials are logged as errors
- Network timeouts are handled gracefully
- BPM remains `null` if fetching fails

## Validation Checklist

After deployment, verify:

- ✅ Songs can be added even if Spotify API is down
- ✅ BPM appears for new Spotify songs
- ✅ BPM can be manually edited by users
- ✅ No crashes on slow network
- ✅ Edge Function logs show successful token caching
- ✅ `flutter analyze` passes with no new errors

## Monitoring

### Edge Function Logs

View logs in Supabase Dashboard:
1. Go to Edge Functions
2. Click on function name
3. View "Logs" tab

Look for:
- Token caching messages
- API failures
- Performance metrics

### Database Monitoring

Check BPM population rate:

```sql
-- Songs with BPM
SELECT COUNT(*) as songs_with_bpm
FROM songs
WHERE bpm IS NOT NULL;

-- Songs without BPM (that have Spotify ID)
SELECT COUNT(*) as missing_bpm
FROM songs
WHERE bpm IS NULL AND spotify_id IS NOT NULL;
```

## Rollback Plan

If issues arise:

1. **Disable Edge Functions** (doesn't break app):
   ```bash
   # Functions can be disabled in Supabase dashboard
   # App will continue working, just won't fetch BPM
   ```

2. **Revert code changes:**
   ```bash
   git revert <commit-hash>
   ```

3. **Remove BPM column** (optional, only if major issues):
   ```sql
   ALTER TABLE songs DROP COLUMN bpm;
   ```

## Performance Notes

- Spotify token is cached in Edge Function memory (1 hour TTL)
- BPM fetching adds ~200-500ms per song during search
- Background enrichment doesn't block UI
- MusicBrainz doesn't provide BPM (fallback only for basic search)

## Future Enhancements (Out of Scope)

These were explicitly excluded from this implementation:

- Lyrics fetching
- Guitar tuning detection
- Batch BPM backfilling for existing songs
- Real-time BPM updates via WebSockets
- Push notifications for BPM enrichment completion

## Support

If issues occur:

1. Check Edge Function logs in Supabase dashboard
2. Verify Spotify credentials are set correctly
3. Test Edge Functions directly via Supabase dashboard
4. Review `[SetlistRepository]` debug logs in Flutter
5. Verify `update_song_metadata` RPC exists and is accessible

## Additional Resources

- Spotify Web API Docs: https://developer.spotify.com/documentation/web-api
- Supabase Edge Functions: https://supabase.com/docs/guides/functions
- BandRoadie Documentation: See `BAND_ROADIE_DOCUMENTATION.md`
