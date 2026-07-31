# Supabase Edge Functions

*Verified against live project `nekwjxvgbveheooyorjo` — 2026-07-23.*

---

## Deployed Edge Functions

All functions are `ACTIVE`. `verify_jwt` indicates whether a valid user JWT is required.

| Function | Version | verify_jwt | Purpose |
|----------|--------:|:----------:|---------|
| `spotify_search` | 19 | ✅ | Search Spotify for tracks — returns title, artist, duration, artwork, Spotify ID |
| `spotify_audio_features` | 18 | ✅ | Fetch BPM/tempo for a Spotify track ID via Audio Features API |
| `musicbrainz_search` | 19 | ✅ | Fallback song search via MusicBrainz — metadata only, no BPM |
| `getsongbpm_lookup` | — | ✅ | Fetch BPM/key for a new song by title+artist via GetSongBPM (`api.getsong.co`) |
| `send-band-invite` | 21 | ✅ | Send band invitation email via Resend |
| `send-bug-report` | 18 | ✅ | Send in-app bug/feature report email via Resend |
| `auth-confirm` | 15 | ✅ | Auth confirmation handler (PKCE token exchange) |
| `accept-invite` | 21 | ✅ | Process band invite acceptance — validates token, adds member |
| `send-push` | 17 | ❌ | FCM HTTP v1 push delivery — triggered by database webhook on `notifications` INSERT. Uses OAuth2 service account. |
| `calendar-feed` | 25 | ❌ | iCal feed generation — public URL auth via token param, no JWT required |

---

## Authentication Model

| Pattern | Functions | Auth mechanism |
|---------|-----------|----------------|
| User JWT required | `spotify_*`, `musicbrainz_*`, `getsongbpm_lookup`, `send-band-invite`, `send-bug-report`, `auth-confirm`, `accept-invite` | `Authorization: Bearer <anon-key + user session>` |
| Service role key | `send-push` | `Authorization: Bearer <service_role_key>` (webhook) |
| Token param | `calendar-feed` | `?token=<calendar_token>` in URL — no JWT |

---

## Required Secrets

Set via Supabase Dashboard → Edge Functions → Secrets (or `supabase secrets set --project-ref nekwjxvgbveheooyorjo`):

| Secret | Used By | Notes |
|--------|---------|-------|
| `SPOTIFY_CLIENT_ID` | `spotify_search`, `spotify_audio_features` | Spotify Developer App credentials |
| `SPOTIFY_CLIENT_SECRET` | `spotify_search`, `spotify_audio_features` | Cached OAuth token (1-hr TTL) |
| `FIREBASE_PROJECT_ID` | `send-push` | e.g. `bandroadie-65b18` |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | `send-push` | Full JSON service account key from Firebase Console |
| `RESEND_API_KEY` | `send-band-invite`, `send-bug-report` | Transactional email delivery |
| `GETSONGBPM_API_KEY` | `getsongbpm_lookup` | Static query-param key from getsongbpm.com/api registration |

Supabase automatically injects `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` into all functions.

---

## Deployment

```bash
# Deploy a single function
supabase functions deploy <function-name> --project-ref nekwjxvgbveheooyorjo

# View logs
supabase functions logs <function-name> --project-ref nekwjxvgbveheooyorjo

# Set a secret
supabase secrets set KEY=value --project-ref nekwjxvgbveheooyorjo
```

---

## Notes

- **`send-push`** is the sole, current push delivery path — triggered synchronously by a database webhook on `notifications` INSERT. See `docs/reference/notifications/NOTIFICATION_SYSTEM.md` for the current architecture.
- **`calendar-feed`** is the highest-version function (v25) — actively maintained.

---

> See `docs/reference/notifications/` for notification pipeline details and `docs/reference/bpm/` for Spotify BPM feature details.
