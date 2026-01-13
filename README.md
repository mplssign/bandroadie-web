# Band Roadie

Band Roadie is a mobile app for managing the real-life logistics of being in a band —
gigs, rehearsals, setlists, calendars, and members — without the chaos.

Built by a musician who got tired of group texts, spreadsheets, and
“wait, what key is this in?”

---

## What Band Roadie Does

- Magic-link login (no passwords)
- Band dashboards with upcoming rehearsals and gigs
- Song catalog and fast setlist creation
- Drag-and-drop setlist management
- Calendar with gigs, rehearsals, and blackout dates
- Member directory for quick contact info
- Private band data — no ads, no selling user data

---

## Tech Stack

- **Flutter** (iOS, Android, Web)
- **Material 3** (dark mode)
- **Supabase**
  - Authentication (magic link)
  - Database & row-level security
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

### Run with runtime configuration
Supabase credentials are passed at runtime using `--dart-define`.
Never hardcode secrets.

#### iOS Simulator
```bash
flutter run -d "iPhone" \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here

Android Emulator

flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here

Web (Chrome)

flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here


⸻

VS Code Launch Config (Recommended)

A template is provided at:

.vscode/launch.template.json

To use it:

cp .vscode/launch.template.json .vscode/launch.json

Edit the file with your Supabase URL and anon key.

.vscode/launch.json is git-ignored to keep secrets local.

⸻

Magic Link Deep Linking

Band Roadie uses deep linking for authentication:

bandroadie://login-callback

In Supabase:
	•	Authentication → URL Configuration
	•	Add the above to Redirect URLs

⸻

Privacy & Data
	•	User data is only accessible to the user’s band
	•	No ads
	•	No data selling
	•	Data is encrypted in transit
	•	Account deletion is supported

Privacy policy:
https://bandroadie.com/privacy

⸻

Status

Active development.
Private repository.

⸻

© Band Roadie
