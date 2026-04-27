# BandRoadie — Technical Guardrails

These rules are non-negotiable. They govern every agent in every session.
When an agent's action conflicts with a rule here, the rule wins.

---

## 1. Initialization Order (Do Not Change)

The app must initialize in this exact sequence. Never reorder:

```
1. WidgetsFlutterBinding.ensureInitialized()
2. URL strategy (web only)
3. Portrait orientation lock
4. AppVersionService.init()
5. validateSupabaseConfig()     ← checks --dart-define values
6. Supabase.initialize()
7. Firebase.initializeApp()     ← iOS/Android only
8. DeepLinkService setup
9. runApp()
```

Any change to initialization order requires:

- Explicit Architect approval
- A new decision recorded in `docs/reference/general/AI_DECISIONS.md`
- Update to `docs/reference/general/RUNTIME_CONFIG.md`

---

## 2. Configuration (Single Source of Truth)

Config priority must remain:

1. `--dart-define` (compile-time injection — the only config source)

Never introduce alternative config loaders (no runtime .env, no flutter_dotenv).
Never use `service_role` keys in client code. Anon key only.
Never hardcode Supabase or Firebase credentials in source code.

---

## 3. Platform Differences (Do Not Blur)

| Area       | Native (iOS / macOS / Android) | Web                                          |
| ---------- | ------------------------------ | -------------------------------------------- |
| Config     | `--dart-define` only           | `--dart-define` only                         |
| Auth flow  | PKCE                           | PKCE (migrated from implicit — April 2026, DECISION-001) |
| Firebase   | Initialized                    | Not initialized                              |
| Deep links | Handled via DeepLinkService    | Not applicable                               |

Any change must respect these per-platform constraints.

---

## 4. Supabase Safety

- RLS policies are the final authority. Never bypass them from the client.
- Never change auth flow type without explicit Architect approval.
- Never call an RPC with partial parameters — PostgREST fails to resolve overloads.
- Pass all parameters explicitly, use `null` for unused optional fields.
- Never create RLS policies that query the table they protect (infinite recursion — PostgreSQL error 42P17). Use SECURITY DEFINER helper functions instead.
- When adding SECURITY DEFINER functions, always include `SET search_path = public`.

---

## 5. Dart / Flutter Safety

**Async lifecycle:**

- Never call `setState` after an `async` gap without a `mounted` guard
- Never use a `FocusNode`, `TextEditingController`, or `ScrollController` after `dispose()`
- If a method becomes `async`, re-audit its lifecycle

**Disposal:**

- Every `TextEditingController`, `FocusNode`, and `ScrollController` must be disposed
- Unfocus before disposing rows in lists

**Rebuild discipline:**

- Evaluate what triggers rebuilds before every state change
- Use `ListView.builder` correctly — no rebuilds of unchanged items
- Never scan entire lists inside `build()`

---

## 6. Data Integrity

- Ordering logic lives in Supabase RPC. Never implement client-side ordering that can drift from the server.
- All data writes must be atomic.
- Submission flows must serialize cleanly, re-parse cleanly, and produce identical output for identical input.
- No UI state should become the source of truth for persisted data.

---

## 7. Code Change Discipline

- Modify only files in the Architect plan
- Never refactor opportunistically — even if the code looks bad
- Never rename symbols unless the Architect plan requires it
- Never introduce new dependencies without explicit Architect approval
- Prefer localized in-place edits over new abstractions

---

## 8. File Size Targets

| File type            | Target maximum |
| -------------------- | -------------- |
| Dart files (general) | 500 lines      |
| Container widgets    | 350 lines      |
| Feature widgets      | 400 lines      |
| Helper widgets       | 200 lines      |

Exceeding these is a warning, not a hard stop. Architect may permit localized modifications to oversized files if the change is minimal and does not worsen maintainability.

---

## 9. Unidirectional Data Flow

- Parents own state, perform mutations, call repositories
- Children receive state via constructor
- Children emit callbacks upward
- Leaf widgets do not perform cross-feature mutations
- Providers are for repositories, shared controllers, and cross-feature state — not for UI-local state

---

## 10. Git Discipline

Branch lifecycle — never reverse this order:

1. Create branch
2. Implement and commit
3. Push
4. Open PR
5. Merge into main
6. Confirm main contains commit
7. Delete branch

Commit message format: `type(scope): short description`
Types: `feat`, `fix`, `chore`, `refactor`, `test`, `docs`

---

## 11. No Push Without QA PASS

This is the non-negotiable commit gate. No exceptions.

See `docs/agents/COMMIT_GATE.md` for the full protocol.

---

## 12. Performance Reality Check

Flutter debug mode adds assertions, slows rendering, and inflates frame time.
Release mode is the only truth.

Before optimizing anything:

- Measure parse time
- Measure rebuild time
- Compare debug vs. release
- Never optimize based on debug-mode perception alone
