# Flutter + Supabase Guardrails (BandRoadie)

These rules exist to prevent regressions across iOS, macOS, Android, and Web.

---

## Configuration Rules (Single Source of Truth)

- documentation/RUNTIME_CONFIG.md is the source of truth
- Config priority must remain:
  1) --dart-define (highest priority)
  2) .env via flutter_dotenv (fallback for native)
- Never introduce alternative config loaders
- Never use service_role keys in client code

---

## Initialization Order (Must Not Change)

The app must initialize in this exact sequence:

1. WidgetsFlutterBinding.ensureInitialized()
2. Set URL strategy (web only)
3. Lock portrait orientation
4. AppVersionService.init()
5. loadEnvConfig()
6. validateSupabaseConfig()
7. Supabase.initialize()
8. Firebase.initializeApp() (iOS/Android only)
9. DeepLinkService setup
10. runApp()

If any step changes:
- update documentation/RUNTIME_CONFIG.md
- record the decision in docs/global/AI_DECISIONS.md
- require explicit architectural approval

---

## Platform Differences (Do Not Blur)

### Native (iOS / macOS / Android)
- Reads .env via flutter_dotenv
- Uses PKCE auth flow
- Firebase initialized on iOS/Android only
- Deep links handled via DeepLinkService

### Web
- Uses --dart-define injection at compile time
- Uses implicit auth flow
- No Firebase
- detectSessionInUri: true

Changes must preserve these differences.

---

## Supabase Safety Rules

- Never embed service_role keys
- Keep anon key usage only
- Assume RLS is required
- Avoid changing auth flow type unless explicitly approved
- Treat RPC and RLS changes as high-risk by default

---

## Database Change Discipline

If a change touches database behavior:
- inspect relevant migrations
- inspect triggers
- inspect RLS policies
- inspect foreign key and cascade behavior
- check for privilege escalation risk

Never make schema or policy changes casually.

---

## Code Change Discipline

- Prefer minimal edits in-place over new abstractions
- Avoid refactors that touch unrelated features
- Keep changes scoped to the Architect plan
- Preserve existing platform behavior unless the plan explicitly changes it
- If a new file is necessary, Architect must approve it first

---

## Verification Checklist (Minimum)

Engineer must run:
- flutter analyze

When relevant:
- flutter test
- manual verification of the affected flow on at least one target platform

QA must confirm:
- no init-order changes
- no config-path changes
- no platform behavior regressions
- no security violations
- no unauthorized widening of permissions

---

## High-Risk Change Categories

Treat these as high-risk and verify carefully:

- auth/session
- routing / deep links
- RLS policies
- RPC behavior
- migrations
- triggers
- shared controller state
- configuration loading

These areas require extra caution from Architect, Engineer, and QA.