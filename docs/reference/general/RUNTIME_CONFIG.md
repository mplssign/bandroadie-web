# Runtime Configuration — BandRoadie

This document is the authoritative reference for app initialization order and configuration. Any change to initialization order or config loading requires an entry in `AI_DECISIONS.md` and explicit Architect approval.

---

## App Initialization Order

The following sequence is fixed. Never reorder. Never insert steps between existing steps without a logged decision.

```
1. WidgetsFlutterBinding.ensureInitialized()
2. URL strategy (web only)
3. Portrait orientation lock
4. AppVersionService.init()
5. validateSupabaseConfig()     ← validates --dart-define values, fails fast if missing
6. Supabase.initialize()
7. Firebase.initializeApp()     ← iOS / Android only, skipped on web
8. DeepLinkService setup
9. runApp()
```

**Entry point:** `lib/main.dart`

---

## Configuration Model

BandRoadie uses compile-time injection exclusively. There is no runtime config loading.

| Source | Status |
|--------|--------|
| `--dart-define` flags | ✅ Only permitted config source |
| Runtime `.env` file | ❌ Never — not permitted |
| `flutter_dotenv` or equivalent | ❌ Never — not permitted |
| Hardcoded credentials | ❌ Never — guardrails violation |

---

## Required `--dart-define` Keys

| Key | Description |
|-----|-------------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_ANON_KEY` | Supabase anon (public) key — never service_role |

`validateSupabaseConfig()` in `lib/main.dart` checks for these at startup and fails fast with a clear error if either is missing or malformed.

---

## Running the App Locally

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

### VS Code (Recommended)
A launch template is provided at `.vscode/launch.template.json`.

```bash
cp .vscode/launch.template.json .vscode/launch.json
```

Edit `launch.json` with your credentials. It is git-ignored.

---

## Production / Vercel Deployment

Web builds are deployed via Vercel. Config values are supplied as Vercel environment variables and injected at build time via the `build_web.sh` script as `--dart-define` flags.

```bash
flutter build web --release \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

Without these values, `validateSupabaseConfig()` fails and the app will not start.

---

## Platform Differences

| Area | Native (iOS / macOS / Android) | Web |
|------|-------------------------------|-----|
| Config | `--dart-define` only | `--dart-define` only |
| Auth flow | PKCE | PKCE (as of 2026-04-14 — was implicit) |
| Firebase | Initialized (step 7) | Not initialized |
| Deep links | Handled via `DeepLinkService` | Not applicable |

---

## Firebase Configuration

Firebase is initialized on native platforms only (iOS, Android, macOS). The web build skips Firebase initialization entirely.

| Platform | Config File |
|----------|------------|
| Android | `android/app/google-services.json` |
| iOS | `ios/Runner/GoogleService-Info.plist` |
| macOS | `macos/Runner/GoogleService-Info.plist` |

Firebase is used exclusively for push notification delivery via FCM. It is not used for authentication.

---

## Deep Link Configuration

Magic link authentication on native platforms uses:

```
bandroadie://login-callback/
```

Configured in Supabase Dashboard under **Authentication → URL Configuration → Redirect URLs**.

---

*Any proposed change to initialization order or config loading must produce a new entry in `AI_DECISIONS.md` before the Architect plan is written.*
