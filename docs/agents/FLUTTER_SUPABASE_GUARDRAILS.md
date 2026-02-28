# Flutter + Supabase Guardrails (BandRoadie)

These rules exist to prevent regressions across iOS/macOS/Android/Web.

---

## Configuration Rules (Single Source of Truth)

- documentation/RUNTIME_CONFIG.md is the source of truth.
- Config priority must remain:
  1) --dart-define (highest priority)
  2) .env via flutter_dotenv (fallback for native)
- Never introduce alternative config loaders.
- Never use service_role keys in client code.

---

## Initialization Order (Must Not Change)

The app must initialize in this exact sequence:

1. WidgetsFlutterBinding.ensureInitialized()
2. Set URL strategy (web only)
3. Lock portrait orientation
4. AppVersionService.init()
5. loadEnvConfig()          (flutter_dotenv loads .env)
6. validateSupabaseConfig() (checks dart-define + .env)
7. Supabase.initialize()
8. Firebase.initializeApp() (iOS/Android only)
9. DeepLinkService setup
10. runApp()

If any step changes:
- Update documentation/RUNTIME_CONFIG.md
- Record decision in docs/global/AI_DECISIONS.md

---

## Platform Differences (Do Not Blur)

Native (iOS/macOS/Android):
- Reads .env (asset) via flutter_dotenv
- PKCE auth flow
- Firebase initialized (iOS/Android only)
- Deep links handled via DeepLinkService

Web:
- Uses --dart-define injection (compile-time)
- Implicit auth flow
- No Firebase
- detectSessionInUri: true (web)

Any change must respect these constraints.

---

## Supabase Safety Rules

- Never embed service_role keys.
- Keep anon key usage only.
- Assume RLS is enforced and required.
- Avoid changing auth flow type unless explicitly approved.

---

## Code Change Discipline

- Prefer minimal edits in-place over new abstractions.
- Avoid refactors that touch unrelated features.
- Keep changes scoped to the files in the Architect plan.
- If a new file is necessary, Architect must approve first.

---

## Verification Checklist (Minimum)

Engineer should run:
- flutter analyze

When relevant:
- flutter test
- verify affected screen/flow manually on at least one target platform

QA must confirm:
- No init-order changes
- No config-path changes
- No platform behavior regressions
- No security violations (keys, auth flow changes)

