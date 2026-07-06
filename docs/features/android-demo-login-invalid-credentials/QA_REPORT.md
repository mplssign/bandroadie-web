# QA Report

## Feature Slug

`android-demo-login-invalid-credentials`

## Final Verdict

**APPROVED**

## Validation Method

Device test of the exact release artifact, plus independent binary inspection. Because this fix targets the build pipeline (dart-define injection into Android release builds), source-level review alone cannot validate it — the shipped artifact is the product. QA therefore exercised the artifact itself, not a fresh local build.

## Artifact Under Test

- Path: `build/app/outputs/bundle/release/app-release.aab`
- Version: 1.3.29 (206)
- Size: 97,041,779 bytes
- SHA-256: `69432ab63ac45028471dac4eace4ba61328ee0cf6677fafd224d4952a2646b65`
- Built: 2026-07-06 08:35 (local)

## Independent Binary Verification (Manager, 2026-07-06)

Performed independently of the Engineer's claims — `libapp.so` extracted from the AAB and string-scanned:

| Check | Result |
|-------|--------|
| Demo email (`hello@bandroadie.com`) | 4 occurrences ✅ |
| Demo password sentinel | 1 occurrence ✅ |
| Production Supabase ref (`nekwjxvgbveheooyorjo`) | 6 occurrences ✅ |
| Staging ref (`hpjvbagybmmaykamsgpd`) | 0 occurrences ✅ |
| Non-prod ref (`ixmx…`) | 0 occurrences ✅ |

Counts match the Engineer's report exactly. This is the verification the Build 204 incident lacked: evidence from the artifact on disk, independently reproduced.

## Device Test (Tony, 2026-07-06)

- Device: Samsung, serial R5CNC05HJXT (physical device)
- Install method: `bundletool build-apks --mode=universal` from the verified AAB (locally signed), `bundletool install-apks` after uninstalling the Play-signed copy
- Test: launched app → demo login
- Result: **PASS** — demo login succeeded, landed in demo band

## Regression Notes

- Fix is confined to build tooling (dart-define injection + artifact verification steps) and a version bump; no app source logic changed
- Prior commits on branch also restore the production sentinel check that had been corrupted by an accidentally committed test pattern (37e690d)
- No RLS/RPC/migration impact; no client code paths altered

## Release Warning

Production release 1.3.27 (204) currently in Play review is the defective empty-define build this branch fixes. Submit 1.3.29 (206) — this exact AAB — to production as soon as this gate closes to minimize the exposure window.
