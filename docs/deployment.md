# Deployment

## Web (Vercel)

```bash
flutter build web --release
cd build/web && vercel --prod
```

Deployed to `bandroadie.com`. Auth confirmation handled via `/auth/confirm` route.

## iOS

```bash
flutter run -d ios
```

Requires signing configuration in Xcode.

## Android

```bash
flutter run -d android
```

Uses Kotlin DSL (`build.gradle.kts`). Deep links configured in `AndroidManifest.xml`.

## macOS

```bash
flutter run -d macos
```

Requires network entitlements in `macos/Runner/*.entitlements`.

## Supabase

Migrations: `supabase/migrations/`
Edge Functions: `supabase/functions/`

```bash
supabase db push        # Apply migrations
supabase functions deploy <name>  # Deploy edge functions
```
