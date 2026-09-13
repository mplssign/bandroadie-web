# QA_REPORT — web-band-avatar-file-picker

## Feature Slug

`web-band-avatar-file-picker`

## Feature Title

Use a desktop file picker for band avatar uploads on web

## Cycle Number

2

## Final Verdict

APPROVED

## Validation Summary

The implementation matches the revised Architect plan and passes every Tier 1
gate. Full and focused analysis are clean, all 310 tests observed by QA pass,
the web/native split remains correctly scoped, and the `+72/-0` implementation
delta is within the revised budget. QA Cycle 1's only Critical finding is
resolved mechanically: the implementation diff adds exactly zero
`debugPrint(` calls, while both revised catch contracts remain intact.

Validation was static code-path analysis only. No app, simulator, emulator, or
browser was launched or driven by QA.

## Architect Scope Review

- Branch, Architect plan, Engineer report, and requested feature slug all
  match `web-band-avatar-file-picker`; the Engineer report is Cycle 2.
- The implementation diff modifies only
  [lib/features/bands/band_form_screen.dart](../../../lib/features/bands/band_form_screen.dart).
- The untracked feature directory contains only the Architect plan, Engineer
  report, and this required QA report.
- No off-limits avatar contract, draft-state contract, test, dependency,
  Supabase, init, auth, routing, or non-Bands file changed.
- No database migration, RPC, policy, trigger, edge function, package, public
  API, provider, controller, repository, or service was added or changed.

## Completeness Check

All functional Architect tasks are present:

- `kIsWeb` is imported and guards the first executable branch of `_pickImage()`.
- Web calls `_pickImageFromWebFilePicker()` and returns before the bottom sheet,
  permission checks, `image_picker`, and `dart:io.File` path.
- The web picker requests `FileType.image` with `withData: true` and uploads
  `PlatformFile.bytes` directly.
- `_uploadPickedBytesToStorage()` scopes the object to the authenticated user,
  normalizes and whitelists `png|jpg|jpeg|gif|webp`, falls back to `png`, uses
  the existing `band-avatars` bucket, and returns its public URL.
- Cancellation/null bytes return silently. Async state updates and snackbar
  access are guarded by `mounted`; success and failure clear upload state.
- Edit mode propagates a successful URL through `draftBandProvider`; create and
  edit submission reuse `_uploadedImageUrl`; existing dirty-state comparison
  detects the new URL while `_selectedImage` remains null on web.
- The native/mobile/macOS picker body and `_uploadImageToStorage(File)` are
  unchanged after the new guard.

The implementation is complete against the revised plan. The two Cycle 1
catch-level debug logs are absent without any other functional change.

## Behavior Verification

Code-path analysis confirms:

- Web opens the browser file chooser directly with no web bottom sheet.
- Web bytes never pass through `File(image.path)` or `File.readAsBytes()`.
- iOS, Android, and macOS continue through the existing bottom-sheet and
  `image_picker` path because `kIsWeb` is false.
- A cancelled picker or null bytes does not mutate state or show a snackbar.
- Missing authentication prevents a storage upload and reaches the existing
  failure feedback path.
- Storage object keys cannot receive an arbitrary picker extension; the
  validated extension also supplies the planned `image/<extension>` content
  type.
- Successful edit-mode uploads update both the form URL and draft avatar URL;
  `_uploadedImageUrl != _initialImageUrl` marks the form dirty.

These outcomes were confirmed in code, not exercised at runtime. Runtime web
chooser, storage policy, rendering, and native platform behavior remain the
owner-run checks W1-W9 below.

## Regression Check

**Risk: LOW** based on code-path analysis.

| System area | Result |
|---|---|
| Bands — web avatar upload | Intended guarded behavior added; byte upload and URL propagation confirmed in code. |
| Bands — create/edit/delete/import/export | Existing submit paths preserved; no unrelated flow changed. |
| iOS / Android / macOS avatar upload | Existing branch is textually unchanged after the web guard. |
| Supabase Storage | Same bucket, authenticated user path, `uploadBinary`, upsert behavior, and public URL pattern. |
| Home / Calendar shells | `BandAvatar` and `DraftBandState.localImageFile` contracts untouched. |
| Gigs / Rehearsals / Setlists / Members / Contacts / Financials | No files changed. |
| Auth / routing / deep links / notifications | No files or flows changed. |
| App and Firebase initialization | `lib/main.dart` unchanged; init order unaffected. |
| RLS / RPCs / triggers / edge functions | No files changed. |

No controller or `FocusNode` lifecycle changed. Both new async paths check
`mounted` before post-gap `setState`, provider, context, or snackbar access.
Rebuild frequency changes only while the existing upload state and URL fields
are updated.

## Database Safety

Not applicable. No SQL migration, schema, RLS, RPC, trigger, storage policy, or
edge-function file changed. No ephemeral database branch/apply check was
required.

## Analyzer Results

- `flutter analyze`: PASS — no issues found in 5.6s.
- `flutter analyze lib/features/bands/band_form_screen.dart`: PASS — no issues
  found in 1.1s.

## Test Results

- Full `flutter test`: PASS — 310 passed, 0 failed.
- The Engineer report records 322 passes; QA reports the exact total produced
  by the Cycle 2 validation run. The suite completed successfully, so the count
  discrepancy does not change the gate result.
- Tracked test diff: empty.
- Untracked test status: empty. QA used targeted `git status --short -- test/`
  as the policy-compliant equivalent of the plan's `git ls-files` command,
  because QA may only run the explicitly permitted read-only git commands.
- No test file was added or modified, as required by the plan.

## Diff Safety Review

- `git diff --check`: PASS.
- No added `TODO` or `FIXME` marker.
- No secret, API key, token, password, service-role credential, or private-key
  material detected in added lines.
- No accidental deletion or unrelated formatting churn detected.
- Mandatory Cycle 2 gate: added `debugPrint(` count is exactly 0. The two calls
  rejected in Cycle 1 have been removed.

## Change Budget Review

- Actual implementation delta: `+72/-0` in one approved source file.
- Revised Architect budget: net `+53..+73`; actual is within budget and below the 1.5x
  warning threshold.
- New implementation/test files: 0. New public symbols: 0. New dependencies: 0.
- Zero deletions are justified in the Engineer report: this bug required a
  missing web guard and bytes path while the plan requires the native path to
  remain unchanged.
- The touched file is 2,425 lines. The Engineer report supplies the required
  one-line justification: the Architect confines the behavior to the existing
  owning screen and prohibits the broader extraction/refactor.

## Code Efficiency Review

- Both new methods are private and explicitly required by the Architect plan.
- Independent search found no existing web band-avatar picker or direct
  band-avatar bytes upload helper elsewhere under `lib/`.
- The only other matching upload is the existing `File`-based sibling helper,
  which the plan requires to remain separate and untouched.
- No duplicate provider state, unused field/parameter, new widget abstraction,
  re-fetching builder, hand-rolled collection helper, future flag, barrel file,
  or public API was introduced.
- Although each helper has one call site, both extractions are explicitly
  prescribed by the Architect and keep the platform branch readable; they are
  not out-of-scope abstractions.

## Manual Verification Punch List

**W1. Web — file picker replaces bottom sheet (fix confirmation)**
   1. Open the deployed web build (Vercel preview URL for this PR) in
      Chrome on desktop.
   2. Sign in and navigate to Settings → Edit Band (or Create Band).
   3. Tap the "+" upload icon at the left of the avatar color strip.
   4. **Expected:** The browser's native file-selection dialog opens
      immediately, filtered to image files. No "Choose Image Source" bottom
      sheet appears.

**W2. Web — successful upload**
   1. In dialog W1.3, pick a local PNG.
   2. **Expected:** The dialog closes, the avatar area briefly shows the
      uploading spinner overlay, then displays the uploaded image. A
      "Image uploaded successfully" snackbar appears.
   3. Save the form; reopen the band; **expected:** the avatar persists and
      loads via `Image.network`.

**W3. Web — cancel is silent**
   1. Reopen the picker (W1.3), dismiss the browser dialog with Cancel.
   2. **Expected:** No snackbar, no state change, no error toast.

**W4. Web — Safari desktop parity (regression guard)**
   1. Repeat W1–W2 in Safari on macOS.
   2. **Expected:** identical behavior.

**W5. iOS — mobile bottom sheet preserved**
   1. Run on an iOS device or simulator (Tony's harness).
   2. Sign in, open Edit Band, tap the "+" upload icon.
   3. **Expected:** "Choose Image Source" bottom sheet appears with "Take
      Photo" and "Photo Library" rows (byte-identical to today's behavior).
   4. Pick Photo Library, choose an image, confirm upload succeeds and
      persists — same as prior release.

**W6. Android — mobile bottom sheet preserved**
   1. Repeat W5 on an Android device (Pixel or emulator).
   2. **Expected:** identical prior behavior; both Take Photo and Photo
      Library paths work.

**W7. macOS — mobile bottom sheet preserved**
   1. Repeat W5 in the macOS build (`flutter run -d macos`).
   2. **Expected:** identical prior behavior. The macOS path uses the
      existing `image_picker` flow unchanged.

**W8. Web — extension normalization spot-check**
   1. On web, pick a `.jpeg` file (not `.jpg`).
   2. **Expected:** upload succeeds; the storage object URL ends in
      `.jpeg`; the avatar renders.
   3. On web, pick a `.webp` file. Same expectation with `.webp`.

**W9. Web — form dirty state**
   1. In Edit Band, upload a new image via the web picker.
   2. Before saving, note that the "Update Band" button is enabled (form
      is dirty).
   3. **Expected:** enabled. (Confirms `_uploadedImageUrl != _initialImageUrl`
      registers as dirty even without `_selectedImage`.)

QA did not perform W1-W9. They require a deployed/running app and are reserved
for Tony at PR-test/apply time.

## Issues Found

### Critical

None.

### Warnings

None.

### Suggestions

None.