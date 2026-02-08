# BPM Feature - Quick Reference

## 🎯 What It Does

Automatically fetches BPM (tempo) from Spotify when users add songs via Song Lookup.

## 🔑 Key Points

- ✅ **Non-blocking**: Song creation never fails due to BPM issues
- ✅ **Automatic**: BPM is fetched in background if needed
- ✅ **Editable**: Users can manually change BPM anytime
- ✅ **Graceful**: Falls back to null if Spotify API unavailable

## 📝 Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Database | ✅ Already exists | `songs.bpm` column (nullable INTEGER) |
| Edge Functions | ✅ Created | 3 new functions (see below) |
| Repository | ✅ Updated | BPM enrichment in `upsertExternalSong()` |
| UI | ✅ Updated | Passes BPM from search results |
| Testing | ⏳ Needs deployment | Deploy Edge Functions first |

## 🛠️ Edge Functions Created

### 1. spotify_search
- **Purpose**: Search Spotify for tracks
- **Input**: `{ query: string, limit?: number }`
- **Output**: `{ ok: boolean, data: Track[] }`
- **File**: `supabase/functions/spotify_search/index.ts`

### 2. spotify_audio_features
- **Purpose**: Fetch BPM for a Spotify track
- **Input**: `{ spotify_id: string }`
- **Output**: `{ ok: boolean, data: { bpm: number | null } }`
- **File**: `supabase/functions/spotify_audio_features/index.ts`

### 3. musicbrainz_search
- **Purpose**: Fallback search (no BPM data)
- **Input**: `{ query: string, limit?: number }`
- **Output**: `{ ok: boolean, data: Recording[] }`
- **File**: `supabase/functions/musicbrainz_search/index.ts`

## 🚀 Quick Deployment

```bash
# 1. Deploy Edge Functions
supabase functions deploy spotify_search
supabase functions deploy spotify_audio_features
supabase functions deploy musicbrainz_search

# 2. Set Spotify credentials (choose one method)

## Option A: Environment variables
supabase secrets set SPOTIFY_CLIENT_ID=your_client_id
supabase secrets set SPOTIFY_CLIENT_SECRET=your_client_secret

## Option B: Vault (in SQL Editor)
INSERT INTO vault.secrets (name, secret) VALUES 
  ('SPOTIFY_CLIENT_ID', 'your_client_id'),
  ('SPOTIFY_CLIENT_SECRET', 'your_client_secret');

# 3. Test
flutter run -d macos
# → Open setlist → Add song → Search Spotify → Verify BPM appears
```

## 🔍 How to Get Spotify Credentials

1. Go to https://developer.spotify.com/dashboard
2. Log in with Spotify account
3. Click "Create an App"
4. Fill in app details (name: "BandRoadie", description: anything)
5. Copy "Client ID" and "Client Secret"
6. Use in deployment step above

## 🧪 Testing Checklist

- [ ] Song lookup returns BPM in search results
- [ ] Adding song stores BPM immediately
- [ ] Song details display BPM
- [ ] BPM can be manually edited
- [ ] Songs still added if Spotify fails
- [ ] No errors in Edge Function logs
- [ ] `flutter analyze` passes

## 📊 Monitoring

### Check BPM Coverage
```sql
SELECT 
  COUNT(*) FILTER (WHERE bpm IS NOT NULL) as with_bpm,
  COUNT(*) as total
FROM songs
WHERE spotify_id IS NOT NULL;
```

### View Recent Songs with BPM
```sql
SELECT title, artist, bpm, created_at
FROM songs
WHERE bpm IS NOT NULL
ORDER BY created_at DESC
LIMIT 10;
```

## 🐛 Troubleshooting

| Problem | Solution |
|---------|----------|
| BPM not appearing | Check Edge Function logs for errors |
| "Spotify API not configured" | Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET |
| Songs not being added | Check RLS policies (unrelated to BPM) |
| BPM wrong value | Verify Spotify has correct tempo data |
| Slow search | Normal - fetching BPM adds 200-500ms |

## 📚 Documentation

- **Full Implementation**: `BPM_FEATURE_IMPLEMENTATION.md`
- **Deployment Guide**: `BPM_FEATURE_DEPLOYMENT.md`
- **Project Docs**: `BAND_ROADIE_DOCUMENTATION.md`

## 🔗 Useful Links

- Spotify Web API: https://developer.spotify.com/documentation/web-api
- Audio Features API: https://developer.spotify.com/documentation/web-api/reference/get-audio-features
- Supabase Edge Functions: https://supabase.com/docs/guides/functions

## 💡 Pro Tips

1. **Token Caching**: Edge Functions cache Spotify tokens for 1 hour (reduces API calls)
2. **Fire and Forget**: Background BPM enrichment never blocks the UI
3. **Defensive Design**: All BPM operations are wrapped in try-catch
4. **User Control**: BPM is always editable, never locked

## 🎸 Brand Voice

Error messages follow BandRoadie's style:
- "🎸 Couldn't fetch BPM from Spotify — the tempo gods were busy."
- "🎸 BPM not available for this track — sometimes even Spotify doesn't know!"

## ⚠️ Constraints Followed

- ❌ No modifications to event creation logic
- ❌ No notification trigger changes
- ❌ No push notification infrastructure added
- ❌ No tuning detection (out of scope)
- ❌ No lyrics fetching (out of scope)
- ✅ Song creation never blocks on BPM fetch

---

**Questions?** See full documentation or check Edge Function logs in Supabase dashboard.
