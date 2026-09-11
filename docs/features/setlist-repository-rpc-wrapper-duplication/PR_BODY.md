## Summary

- consolidate 11 duplicated song metadata mutation methods behind two private helpers
- preserve each method's existing RPC order, fallback behavior, validation, and surfaced exceptions
- remove the unreachable repository smoke test and its dead controller wrapper

## Verification

- `flutter analyze`
- `flutter test` (284 tests passed in independent QA)
- static side-by-side equivalence review of all 11 wrappers and both helpers
- confirmed no Supabase, migration, RLS, dependency, public API, or call-site changes
- confirmed `debugFetchSongsRaw` and `debugSmokeTest` have no remaining references

## Manual Verification

1. Set and clear BPM, then reload and confirm both states persist.
2. Set and clear tuning, then reload and confirm both states persist.
3. Set and clear musical key, then reload and confirm both states persist.
4. Set duration to 3:30, then reload and confirm it persists.
5. Change title, artist, and notes together, then reload and confirm they persist.
6. Add a YouTube link and lyrics, then reload and confirm they persist.
7. Confirm no snackbar error, red overlay, or unexpected reload occurs.

The PGRST202/42883 missing-RPC fallback was verified statically; exercising it live would require removing an RPC and is outside this refactor.