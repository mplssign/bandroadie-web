# QA_REPORT — web-band-avatar-file-picker

## Feature Slug

`web-band-avatar-file-picker`

## Feature Title

Use a desktop file picker for band avatar uploads on web and macOS

## Cycle Number

3

## Final Verdict

APPROVED

## Validation Summary

The Cycle 3 implementation matches the revised Architect plan and passes every
Tier 1 gate. Full and focused analysis are clean, all 322 tests observed by QA
pass, the incremental source delta is exactly `+1/-1`, and the cumulative
source delta remains `+72/-0`. The guard is exactly
`kIsWeb || Platform.isMacOS`, with no Windows/Linux expansion and zero added
`debugPrint(` calls.

Validation was static code-path analysis only. No app, simulator, emulator, or
browser was launched or driven by QA.

## Architect Scope Review

- Branch, Architect plan, Engineer report, and requested feature slug match
  `web-band-avatar-file-picker`; both reports identify Cycle 3.
- The incremental implementation diff modifies only
  [lib/features/bands/band_form_screen.dart](../../../lib/features/bands/band_form_screen.dart),
  replacing one approved guard line. The revised Architect and Engineer
  reports are the only other pre-QA working-tree changes.
- The cumulative diff against `main` contains only the feature documentation
  and the same Bands screen. No other implementation file changed.
- No off-limits avatar/draft contract, test, dependency, platform file,
  Supabase surface, initialization, auth, routing, or non-Bands source changed.
- No database migration, RPC, policy, trigger, edge function, package, public
  API, provider, controller, repository, service, or test was added or changed.

## Completeness Check

The complete Cycle 3 task is present: `_pickImage()` now begins with the exact
three-line `if (kIsWeb || Platform.isMacOS)` branch, invokes the existing
file-picker helper, and returns before the bottom sheet. `||` evaluates
left-to-right, so Flutter Web's true `kIsWeb` operand short-circuits before
`Platform.isMacOS` is evaluated.

Every other source line is unchanged from the approved Cycle 2 baseline. The
existing bytes helper, extension whitelist/fallback, `File` upload helper,
permission helpers, imports, mobile bottom sheet, and private method names are
preserved. No required task or specified edge case is missing.

## Behavior Verification

Code-path analysis confirms:

- Web takes the first branch because `kIsWeb` is true, opens `FilePicker`, and
  returns before `showModalBottomSheet`.
- Native macOS evaluates `Platform.isMacOS` as true, uses the same direct
  `FilePicker` bytes path, and returns before the bottom sheet.
- iOS and Android evaluate both operands as false, then retain the existing
  camera/photo-library sheet, permission checks, `image_picker`, `File`, and
  `_uploadImageToStorage(File)` path unchanged.
- Windows and Linux also evaluate the predicate as false. They were not
  intentionally broadened and remain on the pre-existing fallthrough path.
- The Cycle 2 cancellation, bytes upload, extension validation, storage,
  snackbar, draft URL, and dirty-state behavior is unchanged.

These outcomes were confirmed by static code-path analysis and incremental plus
cumulative diff review, not exercised at runtime. Runtime picker, upload,
rendering, and native behavior remain the owner-run checks W1-W9 below.

## Regression Check

**Risk: LOW** based on code-path analysis.

| System area | Result |
|---|---|
| Bands — web avatar upload | Existing Cycle 2 direct file-picker route is preserved exactly. |
| Bands — macOS avatar upload | Intended guard expansion routes macOS through the existing direct file-picker bytes path. |
| Bands — create/edit/delete/import/export | Existing submit paths preserved; no unrelated flow changed. |
| iOS / Android avatar upload | Existing bottom-sheet and `File` upload branch is textually unchanged. |
| Windows / Linux avatar upload | Predicate does not include either platform; existing fallthrough remains. |
| Supabase Storage | Same bucket, authenticated user path, `uploadBinary`, upsert behavior, and public URL pattern. |
| Home / Calendar shells | `BandAvatar` and `DraftBandState.localImageFile` contracts untouched. |
| Gigs / Rehearsals / Setlists / Members / Contacts / Financials | No files changed. |
| Auth / routing / deep links / notifications | No files or flows changed. |
| App and Firebase initialization | `lib/main.dart` unchanged; init order unaffected. |
| RLS / RPCs / triggers / edge functions | No files changed. |

No controller, `FocusNode`, async state handling, rebuild trigger, or disposal
behavior changed in Cycle 3.

## Database Safety

Not applicable. No SQL migration, schema, RLS, RPC, trigger, storage policy, or
edge-function file changed. No ephemeral database branch/apply check was
required.

## Analyzer Results

- `flutter analyze`: PASS — no issues found in 5.7s.
- `flutter analyze lib/features/bands/band_form_screen.dart`: PASS — no issues
  found in 2.5s.

## Test Results

- Full Flutter test suite: PASS — 322 passed, 0 failed.
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
- Added `debugPrint(` count is exactly 0 in both the incremental Cycle 3 source
  diff and the cumulative source diff against `main`.
- `showModalBottomSheet` count is exactly 2; the widened guard has one hit; the
  narrower `if (kIsWeb) {` form has zero hits.
- Platform, dependency, public-contract, test, database, and initialization
  diffs are empty in both relevant scope checks.

## Change Budget Review

- Incremental Cycle 3 source delta: `+1/-1` in one approved source file,
  exactly matching the plan's budget.
- Cumulative source delta against `main`: `+72/-0`, within the approved
  `+53..+73` range and below the 1.5x warning threshold.
- New Cycle 3 implementation/test files: 0. New symbols: 0. New public API: 0.
  New dependencies: 0.
- The touched file is 2,425 lines. The Engineer report supplies the required
  one-line justification: the Architect confines the behavior to the existing
  owning screen and prohibits the broader extraction/refactor.

## Code Efficiency Review

- Cycle 3 adds no symbol or abstraction; it reuses the existing private
  file-picker helper exactly as prescribed.
- Independent search found other general file-picker usages but no second
  band-avatar bytes helper. The bytes helper still has one definition and one
  call site; the existing `File` upload sibling remains separate and untouched.
- No duplicate state, unused field/parameter, widget abstraction, provider,
  builder, collection helper, future flag, barrel file, or public API was
  introduced.

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

**W7. macOS — native file picker replaces bottom sheet (Cycle 3 fix confirmation)**
   1. Run the macOS build via `./run.sh macos` (or `flutter run -d macos`)
      against the built `bug/web-band-avatar-file-picker` binary. Sign in.
   2. Navigate to Settings → Edit Band (or Create Band).
   3. Tap the "+" upload icon at the left of the avatar color strip.
   4. **Expected:** The macOS native `NSOpenPanel` file-selection dialog
      opens immediately, filtered to image files. No "Choose Image
      Source" bottom sheet appears. No "Take Photo" / "Photo Library"
      row is visible anywhere.
   5. Pick a local `.png` (or `.jpeg`) from the Finder dialog.
   6. **Expected:** The dialog closes; the avatar area briefly shows the
      uploading spinner overlay; then displays the uploaded image. A
      "Image uploaded successfully" snackbar appears.
   7. Save the form; reopen the band. **Expected:** The avatar persists
      and loads via `Image.network`.
   8. Reopen the picker (repeat step 3) and dismiss the `NSOpenPanel`
      with Cancel.
   9. **Expected:** No snackbar, no state change, no error toast.
  10. Repeat step 5 with a `.webp` file. **Expected:** upload succeeds
      and the avatar renders (extension-whitelist parity with W8).

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