# Deployment

## Web (Vercel)

Web builds are built and deployed using `tools/deploy_web.sh`. The script reads credentials from a local `.env` file (git-ignored) and passes them to `flutter build web` as `--dart-define` flags. The compiled output is uploaded to Vercel via the CLI. **Vercel does not run the build.**

```bash
./tools/deploy_web.sh            # Production deploy
./tools/deploy_web.sh --preview  # Preview/staging deploy
```

The `.env` file must define:
- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_ANON_KEY` — Supabase anon (public) key

**Do not** set these as Vercel environment variables — they are injected at build time via `--dart-define`, not at runtime.

**Vercel project:** `web` (aliases: `bandroadie.com`, `app.bandroadie.com`)

Both `bandroadie.com` and `app.bandroadie.com` are aliases for the same deployment. Flutter's `_isMarketingHost()` in `lib/main.dart` routes the request to the marketing landing page or the app shell based on the hostname.

Auth confirmation is handled via the `/auth/confirm` route using PKCE flow on all platforms.

> **Note:** `tools/build_web.sh` exists in the repo but is not used by any build or deploy process. Do not reference it in new documentation or agent plans.

### Local Web Dev

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

---

## iOS

Build for simulator:
```bash
flutter run -d "iPhone" \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

Requires signing configuration in Xcode. Credentials passed via `--dart-define` only — no `.env` loaded at runtime.

---

## Android

Build for emulator:
```bash
flutter run -d emulator-5554 \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

Uses Kotlin DSL (`build.gradle.kts`). Deep links configured in `AndroidManifest.xml`.

---

## macOS

```bash
flutter run -d macos \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key-here
```

Requires network entitlements in `macos/Runner/*.entitlements`.

---

## Supabase

Migrations: `supabase/migrations/`
Edge Functions: `supabase/functions/`

```bash
supabase db push                    # Apply migrations
supabase functions deploy <name>    # Deploy edge functions
```

---

## VS Code Launch Configuration

A launch template is provided at `.vscode/launch.template.json`. Copy it and fill in your credentials:

```bash
cp .vscode/launch.template.json .vscode/launch.json
```

`launch.json` is git-ignored. Add your `--dart-define` values there to avoid passing them on the command line every run.
