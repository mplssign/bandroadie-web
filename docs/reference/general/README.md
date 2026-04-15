# BandRoadie

BandRoadie is a mobile app for managing the real-life logistics of being in a band —
gigs, rehearsals, setlists, calendars, and members — without the chaos.

Built by a musician who got tired of group texts, spreadsheets, and  
"wait, what key is this in?"

---

## What BandRoadie Does

- Magic-link login (no passwords)
- Band dashboards with upcoming rehearsals and gigs
- Song catalog and fast setlist creation
- Drag-and-drop setlist management
- Calendar with gigs, rehearsals, and blackout dates
- Member directory for quick contact info
- Private band data — no ads, no selling user data

---

## Tech Stack

- **Flutter** (iOS, Android, macOS, Web)
- **Material 3** (dark mode)
- **Supabase**
  - Authentication (magic link, PKCE flow)
  - Database & row-level security
  - Edge Functions (push notifications, external song lookup)
- **Firebase** (iOS/Android push notifications via FCM)
- **Vercel** (web deployment)

---

## Running the App Locally

### Prerequisites
- Flutter SDK (3.10+)
- A Supabase project

### Supabase Setup
1. Go to your Supabase Dashboard
2. Open your project → **Settings → API**
3. Copy:
   - Project URL
   - anon public key

---

## Run with Runtime Configuration

Supabase credentials are passed at build/run time using `--dart-define`.  
**Never hardcode secrets.**

### iOS Simulator
```bash
flutter run -d "iPhone" \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

### Android Emulator
```bash
flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

### Web (Chrome)
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

---

## VS Code Launch Config (Recommended)

A template is provided at `.vscode/launch.template.json`. To use it:

```bash
cp .vscode/launch.template.json .vscode/launch.json
```

Edit the file with your Supabase URL and anon key. `.vscode/launch.json` is git-ignored to keep secrets local.

---

## Deploying the Web App

Web builds are deployed using `tools/deploy_web.sh`. The script reads credentials from a local `.env` file (git-ignored) and passes them to `flutter build web` as `--dart-define` flags. Vercel does not run the build.

```bash
./tools/deploy_web.sh            # Production deploy
./tools/deploy_web.sh --preview  # Preview deploy
```

The `.env` file must define:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

> **Note:** `tools/build_web.sh` exists in the repo but is not used by any process. Use `deploy_web.sh`.

---

## Magic Link Deep Linking

BandRoadie uses deep linking for authentication on native platforms:

```
bandroadie://login-callback/
```

In Supabase: **Authentication → URL Configuration → Redirect URLs** — add the above URL.

Web magic link authentication uses PKCE flow (migrated from implicit flow April 2026). The `code_verifier` is stored in browser `localStorage`, preventing email scanner pre-fetch from consuming the token. See `docs/reference/general/AI_DECISIONS.md` DECISION-001.

---

## Privacy & Data

- User data is only accessible to the user's band
- No ads
- No data selling
- Data is encrypted in transit
- Account deletion is supported

Privacy policy: https://bandroadie.com/privacy

---

## Status

Active development. Private repository.

---

© BandRoadie
