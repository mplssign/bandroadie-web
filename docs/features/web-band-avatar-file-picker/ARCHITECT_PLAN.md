# ARCHITECT_PLAN — web-band-avatar-file-picker

## Feature Slug

`web-band-avatar-file-picker`

## Feature Title

Use a desktop file picker for band avatar uploads on web

## Problem Summary

On the web app, activating the band avatar upload control (the "+" icon on the
color strip in Create Band / Edit Band) presents the mobile-oriented
`showModalBottomSheet` titled "Choose Image Source" with "Take Photo" and
"Photo Library" options. Web users cannot select an image file from their
desktop file system through this UI. Mobile (iOS/Android) behavior is correct
and must be preserved.

## Root Cause

**Confidence: HIGH** (confirmed directly in code).

In [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart#L1287-L1385),
`_pickImage()` unconditionally opens a `showModalBottomSheet<ImageSource>` and
then calls `_imagePicker.pickImage(source: ImageSource.camera | .gallery)` with
no `kIsWeb` branch. Both selected sources are mobile-oriented.

Two things go wrong on web:

1. The bottom sheet itself is the wrong UX — web users expect a direct browser
   file chooser, not a camera/photo-library sheet.
2. The result path builds
   `File(image.path)` from `dart:io` (imported at
   [line 1](lib/features/bands/band_form_screen.dart#L1) of the same file),
   which is not usable on Flutter Web — `XFile.path` on web is a `blob:` URL
   and `dart:io.File` cannot open it. Even if the user got past the sheet, the
   downstream upload path (which does `imageFile.readAsBytes()` via
   `dart:io.File`) is not a working web path.

`grep -n "kIsWeb" lib/features/bands/band_form_screen.dart` returns zero hits.
There is no platform branch in this file's picker or upload flow.

The `file_picker` package (`^8.1.2`) is already a project dependency
([pubspec.yaml](pubspec.yaml#L34)) and is already used successfully on web
elsewhere in this same file at
[line 788](lib/features/bands/band_form_screen.dart#L788)
(`FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions:
['json'], withData: true)` for JSON backup import). The web-safe picker
pattern is already established in the same class.

## Existing System Analysis

The relevant surface is contained entirely inside
[lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
plus its collaborators:

- **State on the form** (`_BandFormScreenState`):
  - `File? _selectedImage` — the picked file used as a local preview via
    `Image.file` and as the upload input.
  - `String? _uploadedImageUrl` — the Supabase Storage public URL after upload
    completes.
  - `bool _isUploadingImage` — spinner overlay flag.
  - `_uploadImageToStorage(File imageFile)` at
    [line 1110](lib/features/bands/band_form_screen.dart#L1110) reads
    `imageFile.readAsBytes()` and calls
    `supabase.storage.from('band-avatars').uploadBinary(...)`.

- **Local preview propagation** — `_selectedImage` is passed as
  `localImageFile: File?` into
  [`BandAvatar`](lib/features/bands/widgets/band_avatar.dart#L58) at
  [line 1715](lib/features/bands/band_form_screen.dart#L1715). The same
  `File? localImageFile` field is threaded from `DraftBandState`
  ([active_band_controller.dart#L28](lib/features/bands/active_band_controller.dart#L28))
  through ~14 downstream widgets (`HomeAppBar`, `CalendarAppBar`,
  `SetlistsAppBar`, tab contents, empty-home-state, etc.). Changing the
  `BandAvatar` public contract to accept bytes would ripple across all of
  those — out of proportion for this fix.

- **Dirty tracking** at
  [line 255](lib/features/bands/band_form_screen.dart#L255) treats the form as
  dirty when either `_selectedImage != null` **or**
  `_uploadedImageUrl != _initialImageUrl`. Setting `_uploadedImageUrl` alone
  is sufficient to mark the form dirty and trigger the save button.

- **Submit paths** at
  [line 325](lib/features/bands/band_form_screen.dart#L325) and
  [line 470](lib/features/bands/band_form_screen.dart#L470) run
  `_uploadImageToStorage(_selectedImage!)` only when `_selectedImage != null
  && _uploadedImageUrl == null`. If `_uploadedImageUrl` is already set (i.e.
  the pick step already uploaded), submission just uses it as-is. This
  already-uploaded path is exactly what the mobile flow uses today — the pick
  handler uploads inline at [line 1433](lib/features/bands/band_form_screen.dart#L1433).

- **Draft state update** — after upload,
  `ref.read(draftBandProvider.notifier).updateImageUrl(uploadedUrl)` at
  [line 1447](lib/features/bands/band_form_screen.dart#L1447) drives the
  header avatar preview app-wide via `Image.network`.

Because the existing flow already uploads inline during pick and uses the
URL-based preview post-upload, a web branch that skips the `File`-based local
preview and just goes straight to bytes-in → upload → URL-based preview is a
minimal, natural fit.

`_pickImage` at [line 1287](lib/features/bands/band_form_screen.dart#L1287)
is preceded by a stale `// ignore: unused_element` at
[line 1286](lib/features/bands/band_form_screen.dart#L1286). The method IS
used at
[line 1779](lib/features/bands/band_form_screen.dart#L1779)
(`onTap: _pickImage` inside the avatar-color strip). The stale ignore is not
this bug's concern and is out of scope for this fix (see Out of Scope).

## Proposed Solution

Add a single `kIsWeb` branch at the top of
`_pickImage()`. On web, skip the bottom sheet entirely and call
`FilePicker.platform.pickFiles(type: FileType.image, withData: true)`, then
upload the returned bytes directly to the same Supabase Storage bucket
(`band-avatars`) via a new sibling method that takes bytes + extension. On
mobile (and macOS), the existing `showModalBottomSheet` + `image_picker` path
is preserved unchanged.

Do **not** change `BandAvatar`'s public contract. Do **not** add a
`Uint8List? localImageBytes` field to `DraftBandState`. On web, `_selectedImage`
stays `null`; the local preview during the brief upload window shows the
color-block-with-initials that `BandAvatar` already renders when both
`localImageFile` and `imageUrl` are null. Once `_uploadedImageUrl` is set,
the network image renders through the existing `Image.network` path.

Rationale for skipping local `Image.memory` preview on web:

- Adding byte-based preview requires threading `Uint8List?` through
  `BandAvatar` and the ~14 downstream widgets (see Existing System Analysis).
  That is disproportionate to the fix and increases regression surface across
  Home, Calendar, Setlists, Contacts, Members, and the empty-home state.
- Uploads to `band-avatars` are fast for a 512×512-class image at 85 quality
  (single Supabase Storage `uploadBinary` call with `upsert: true`), so the
  window between pick and network-image display is short and already covered
  by `_isUploadingImage` (the existing spinner overlay).
- The existing `_isUploadingImage` overlay renders on top of `BandAvatar`
  ([line 1720ish](lib/features/bands/band_form_screen.dart#L1716)); the user
  gets clear feedback during the upload gap on web with zero widget-tree
  changes.

### Upload helper

Introduce a new private method
`Future<String?> _uploadPickedBytesToStorage(Uint8List bytes, String extension)`
alongside the existing `_uploadImageToStorage(File imageFile)`. It performs
the same three-step Supabase Storage flow (name → `uploadBinary` → `getPublicUrl`),
using bytes directly with `contentType: 'image/$extension'`. The existing
`_uploadImageToStorage(File)` is untouched so mobile behavior cannot regress.

### Extension handling

`FilePicker.platform.pickFiles(type: FileType.image, ...)` returns
`PlatformFile.extension`. Normalize to lowercase; if missing, default to
`'png'` (arbitrary safe fallback that matches an allowed content type).
Do **not** allow arbitrary extensions to flow into the storage key
unvalidated — restrict to `png|jpg|jpeg|gif|webp` and fall back to `png` if
the extension is outside that set. This prevents a malformed extension (e.g.
`../foo`) from ending up in the storage object name.

### No permission checks on web

The existing `_checkCameraPermission()` and `_checkPhotoLibraryPermission()`
already special-case Android and iOS; on web the browser's file input
requires no `permission_handler` gate and any attempt to run it there is a
no-op / logic hole. Skip both on the web path.

### Code organization

Extract the web pick+upload sequence into a small private helper
`_pickImageFromWebFilePicker()` on `_BandFormScreenState` that:

1. Calls `FilePicker.platform.pickFiles(type: FileType.image, withData: true)`.
2. Validates non-null bytes.
3. Calls `_uploadPickedBytesToStorage(...)`.
4. Updates `_isUploadingImage`, `_uploadedImageUrl`, and the draft-band
   `updateImageUrl(...)` on success; shows the existing success/error
   snackbars.

`_pickImage()`'s top becomes:

```dart
if (kIsWeb) {
  await _pickImageFromWebFilePicker();
  return;
}
// existing mobile path unchanged from here
```

This extraction is for readability inside `_BandFormScreenState`, not for
testability. Both `_BandFormScreenState` and `_pickImageFromWebFilePicker`
are library-private and are **not** annotated `@visibleForTesting`; adding
that annotation would introduce a public API surface solely for tests, which
is not proportionate to a web-only bug fix and would contradict the "zero
new public API surface" budget below. Behavior verification is instead
static (analyzer + grep gates in the QA harness) plus a numbered owner-run
punch list Tony executes at PR-test time. See Verification Plan for the
concrete reasoning (SupabaseClient, `FilePicker.platform`, and the
plugin/storage boundary all lack existing dependency-injection or mocking
seams in this repo).

## Database Impact

Not applicable. No schema, RLS, RPC, trigger, edge function, or storage
policy changes. The `band-avatars` bucket and its existing RLS/storage
policies handle the upload identically whether the bytes came from a `File`
or from a `Uint8List`.

## Flutter Architecture Changes

- No new controller, provider, repository, or service.
- No new package dependency (`file_picker` already present, already used on
  web in this file).
- No init-order change (`WidgetsFlutterBinding` → URL strategy → orientation
  lock → `AppVersionService.init` → `validateSupabaseConfig` →
  `Supabase.initialize` → `Firebase.initializeApp` [native only] →
  `DeepLinkService` → `runApp` is untouched).
- No routing change.
- No auth-flow change (PKCE on both platforms unchanged).
- Platform conditionality is confined to a single `kIsWeb` branch inside one
  method on one screen. iOS, Android, and macOS retain their current
  `image_picker` + `showModalBottomSheet` flow byte-for-byte. Firebase and
  `DeepLinkService` are not touched.

## Files to Create

- None. No new files in `lib/`. No new test file — the widget-test path for
  the web pick is intentionally omitted; the tradeoffs and reasoning are in
  the Verification Plan below, and it is called out again in Out of Scope.

## Files to Modify

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart) —
  - Add `import 'package:flutter/foundation.dart' show kIsWeb;` (if not
    already present via another import — currently not).
  - Add a `kIsWeb` early-return branch at the top of `_pickImage()` that
    calls a new `_pickImageFromWebFilePicker()`.
  - Add `_pickImageFromWebFilePicker()`: pick via
    `FilePicker.platform.pickFiles(type: FileType.image, withData: true)`,
    validate bytes, upload via new helper, update
    `_isUploadingImage` / `_uploadedImageUrl`, call
    `draftBandProvider.notifier.updateImageUrl(...)` in edit mode, wire the
    existing success/error snackbars.
  - Add `_uploadPickedBytesToStorage(Uint8List bytes, String extension)`:
    same three-step flow as `_uploadImageToStorage`, but takes bytes and a
    validated extension. Normalize/whitelist the extension to
    `png|jpg|jpeg|gif|webp`, fallback `png`.
  - Do **not** modify the mobile branch of `_pickImage()`.
  - Do **not** modify `_uploadImageToStorage(File)`.

## Files Off-Limits

- [lib/features/bands/widgets/band_avatar.dart](lib/features/bands/widgets/band_avatar.dart) —
  Adding a bytes-based preview field ripples through ~14 downstream widgets.
  The fix does not require it.
- [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) —
  `DraftBandState.localImageFile` contract stays as `File?`; the web path
  simply doesn't populate it and lets `updateImageUrl(...)` handle the
  post-upload preview.
- All widgets that thread `localImageFile: File?`:
  `home_app_bar.dart`, `home_screen.dart`, `home_tab_content.dart`,
  `empty_home_state.dart`, `calendar_app_bar.dart`, `calendar_screen.dart`,
  `calendar_tab_content.dart`, `setlists_app_bar.dart`, `setlists_screen.dart`,
  `setlists_tab_content.dart`, `contacts_tab_content.dart`,
  `members_tab_content.dart`.
- `pubspec.yaml` — no dependency changes. `file_picker` and `image_picker`
  stay at their current versions.
- All Supabase migrations, RPCs, storage policies, and edge functions.
- `lib/main.dart` — no init-order or config change.
- All non-Bands features (auth, gigs, rehearsals, setlists, notifications,
  routing, financials).
- The stale `// ignore: unused_element` at
  [band_form_screen.dart#L1286](lib/features/bands/band_form_screen.dart#L1286)
  — do not touch it in this fix (see Out of Scope).

## Change Budget

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart):
  **+53 to +73 lines net** (~20 lines for the web-branch method call +
  guard, ~34 lines for the new `_pickImageFromWebFilePicker()`, ~24 lines
  for the new `_uploadPickedBytesToStorage(...)`, ~1 import line). No line
  deletions from the mobile path. QA Cycle 1 reconciliation: neither new
  helper adds a `debugPrint` line, so each helper's line count drops by 1
  versus the pre-QA-Cycle-1 contract (the previous range was +55 to +75).
- Test files: **+0 files, +0 lines** in `test/`. No new or modified test
  file is required — see Verification Plan for why the widget test is
  omitted.
- Expected new files anywhere in the repo: **0**.
- Expected new public classes / methods (public API surface): **0**. Both
  new methods are private (`_pickImageFromWebFilePicker`,
  `_uploadPickedBytesToStorage`) on `_BandFormScreenState`. No
  `@visibleForTesting` annotation is added.
- Expected new dependencies: **0** (neither runtime nor `dev_dependencies`).

## System Impact Map

| Area | Status |
|---|---|
| Gigs | unaffected |
| Rehearsals | unaffected |
| Setlists | unaffected |
| Members | unaffected |
| Contacts / Venues | unaffected |
| Auth (PKCE, magic link) | unaffected |
| Routing / Deep links | unaffected |
| Notifications | unaffected |
| Financials | unaffected |
| Home / Calendar shells | unaffected (BandAvatar contract preserved) |
| Bands — avatar upload | **affected (fix target)** |
| Bands — create/edit/delete/import/export flows | unaffected |
| Supabase Storage (`band-avatars` bucket) | unaffected (same bucket, same object naming pattern, same upload API) |
| Supabase RLS / RPCs / triggers | unaffected |
| Edge functions | unaffected |
| Platforms — Web | **behavior fix** |
| Platforms — iOS | unaffected (mobile branch untouched) |
| Platforms — Android | unaffected (mobile branch untouched) |
| Platforms — macOS | unaffected (mobile branch untouched, macOS continues to hit the existing `image_picker` code path exactly as today) |
| App init order (`main.dart`) | unaffected |
| Firebase init (native only) | unaffected |
| `DeepLinkService` | unaffected |

## Regression Risk

**LOW.**

- No auth, session, routing, or init-order code is touched.
- No database, RLS, RPC, or edge-function surface is touched.
- The mobile `image_picker` + bottom-sheet code path is not edited — it is
  simply skipped when `kIsWeb == true`.
- The upload helper for `File` is not modified; a sibling bytes-based helper
  is added instead.
- Widget-tree contracts (`BandAvatar`, `DraftBandState.localImageFile`) are
  unchanged, so the ~14 downstream avatar-preview call sites are unaffected.
- The primary residual risk is a wrong file extension flowing into the
  storage object name; the whitelist + fallback in
  `_uploadPickedBytesToStorage` closes that.

## Engineer Task Breakdown

1. In [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart),
   add `import 'package:flutter/foundation.dart' show kIsWeb;` alongside the
   other `flutter/foundation`-adjacent imports. Confirm no duplicate import.

2. In the same file, add a new private async method
   `_uploadPickedBytesToStorage(Uint8List bytes, String extension)` beside
   `_uploadImageToStorage(File)`:
   - Read `supabase.auth.currentUser?.id`; return `null` if missing.
   - Normalize `extension` to lowercase; if not in `{png, jpg, jpeg, gif,
     webp}`, replace with `png`.
   - Build `fileName = '$userId/$timestamp.$extension'`.
   - Call
     `supabase.storage.from('band-avatars').uploadBinary(fileName, bytes,
     fileOptions: FileOptions(contentType: 'image/$extension', upsert:
     true))`.
   - Return
     `supabase.storage.from('band-avatars').getPublicUrl(fileName)`.
   - Wrap in `try/catch`; on catch, return `null` silently. Do **not** add
     any `debugPrint(...)` line inside this catch. QA Cycle 1 rejected the
     earlier "matching the existing helper's style" instruction because
     `_uploadImageToStorage(File)`'s pre-existing `debugPrint('[Upload] …')`
     is a legacy line that stays where it is; the web-only sibling does
     **not** replicate it. The user-facing error surfaces via the caller's
     `showErrorSnackBar(context, message: 'Failed to upload image')` in
     `_pickImageFromWebFilePicker` when this method returns `null`.

3. In the same file, add a new private async method
   `_pickImageFromWebFilePicker()`:
   - `final result = await FilePicker.platform.pickFiles(type: FileType.image,
     withData: true);`
   - If `result == null` or the single file has null `bytes`, return silently
     (mirrors the existing "user cancelled" behavior).
   - Read `bytes = result.files.single.bytes!` and
     `extension = result.files.single.extension ?? 'png'`.
   - `setState(() { _isUploadingImage = true; _uploadedImageUrl = null; });`
   - `HapticFeedback.lightImpact();` (parity with the existing mobile flow).
   - `final uploadedUrl = await _uploadPickedBytesToStorage(bytes,
     extension);`
   - On `mounted`, `setState(() { _uploadedImageUrl = uploadedUrl;
     _isUploadingImage = false; });`.
   - If `_isEditMode && uploadedUrl != null`, call
     `ref.read(draftBandProvider.notifier).updateImageUrl(uploadedUrl);`.
   - Show `showSuccessSnackBar(context, message: 'Image uploaded
     successfully')` on success, `showErrorSnackBar(context, message: 'Failed
     to upload image')` on `null`.
   - Wrap the pick+upload sequence in `try/catch`. On catch:
     1. Guard on `mounted` — return early if the state is unmounted.
     2. `setState(() => _isUploadingImage = false);` — reset the spinner
        overlay so the UI does not stay stuck in the uploading state.
     3. `showErrorSnackBar(context, message: 'Failed to pick image. Please
        try again.');` — surface the failure to the user.
     Do **not** add any `debugPrint(...)` line inside this catch. The
     pre-existing `debugPrint('[PickImage] Error: $e')` in the mobile
     branch's catch is a legacy line that stays where it is; the web
     branch does **not** replicate it. QA Cycle 1 rejected the earlier
     "matching the mobile branch's generic-error handling" phrasing
     because it invited that debug-log parity.

4. In `_pickImage()`, at the very first line of the method body, add:
   ```dart
   if (kIsWeb) {
     await _pickImageFromWebFilePicker();
     return;
   }
   ```
   Leave every line after that block unchanged.

5. Do not modify the stale `// ignore: unused_element` directive above
   `_pickImage()`. Do not modify `_uploadImageToStorage(File)`. Do not
   modify `BandAvatar`, `DraftBandState`, or any widget that consumes
   `localImageFile: File?`. Do not annotate any method as
   `@visibleForTesting`, do not create or modify any test file, and do not
   add or bump any entry in `dev_dependencies` (no `mockito`, no `mocktail`,
   no test-only helpers).

6. Run `flutter analyze`; ensure clean, no new `dart:io`-on-web warnings, no
   unused imports.

7. Run `flutter test`; the full suite passes with no regressions. No new
   test is added in this PR (see Verification Plan for rationale).

## Verification Plan

### Why no behavioral widget test in this PR

A `flutter test` widget test that exercises the actual web pick+upload flow
is intentionally omitted. The engineering cost is disproportionate to a
web-only bug fix, and the coverage gap is fully closed by the Tier 1 static
gates plus the Tier 2 owner-run punch list. The concrete blockers, all
grounded in the current repo:

1. `_BandFormScreenState` is library-private. It cannot be referenced by
   name from `test/features/bands/*`, so casting a `StatefulElement`'s
   state to `_BandFormScreenState` and calling `_pickImageFromWebFilePicker()`
   is not legal Dart across libraries.
2. Making `_pickImageFromWebFilePicker` public — either by rename or by
   `@visibleForTesting` — would introduce a public API surface solely for a
   test. No file under `lib/` currently uses `@visibleForTesting`; this
   would be a first-time convention adopted for one test, contradicting
   both the "zero new public API surface" line in the Change Budget and the
   private-method design in Proposed Solution. Per the plan's own
   guardrails, that tradeoff is not justified for a bug fix.
3. Even if `_pickImageFromWebFilePicker` were callable from a test, the
   assertion the test needs to make — "the upload produced a public URL and
   `_uploadedImageUrl` is set" — depends on
   `supabase.storage.from('band-avatars').uploadBinary(...)` and
   `getPublicUrl(...)`. `SupabaseClient` is a global singleton
   (`Supabase.instance.client`, wrapped by the top-level
   [supabase](lib/app/services/supabase_client.dart#L13) getter). There is
   no dependency-injection provider for it, no fake/mocked storage client
   anywhere under `test/` (`grep -R "band-avatars\|uploadBinary\|storage.from" test/`
   returns no hits), and `dev_dependencies` contains neither `mockito` nor
   `mocktail` — only `flutter_test`. Wiring a fake storage seam would
   require either a real Supabase-mocking dev dependency (new dependency,
   out of budget) or a production-code refactor that injects the storage
   client (a genuine architectural change, out of scope for a `kIsWeb`
   branch bug fix).
4. `FilePicker.platform` on its own is swappable (its `PlatformInterface`
   allows `FilePicker.platform = FakeFilePickerPlatform()`), but the value
   of a test that only proves "we called `pickFiles`" is small compared to
   what W1–W9 already prove on a real browser.

The Tier 1 gates below therefore verify the exact code shape that produces
the fix — the `kIsWeb` guard, the bytes-based sibling helper, the untouched
mobile path, the untouched `BandAvatar`/`DraftBandState` contracts, and the
change-budget bounds — and the Tier 2 punch list Tony runs at PR-test time
exercises the actual behavior end-to-end on the deployed web build plus the
three mobile platforms.

### Tier 1 — Pre-deploy (QA gate; mechanically executable without a running app)

Never call the code path being replaced.

1. **Static analysis:** `flutter analyze` — clean, no new warnings, no
   `avoid_web_libraries_in_flutter` / `dart:io` warnings introduced.
2. **Static grep — mobile path unchanged (bottom-sheet count):**
   `grep -c "showModalBottomSheet" lib/features/bands/band_form_screen.dart`
   returns exactly `2`. Both hits stay put — one for the invitation-email
   bottom sheet (currently
   [line 546](lib/features/bands/band_form_screen.dart#L546)) and one
   inside the mobile branch of `_pickImage()` (currently
   [line 1288](lib/features/bands/band_form_screen.dart#L1288)). No third
   `showModalBottomSheet(` call is introduced by
   `_pickImageFromWebFilePicker()`.
3. **Static grep — web branch present:**
   `grep -n "kIsWeb" lib/features/bands/band_form_screen.dart` returns at
   least one hit. QA visually confirms it is the guard at the top of
   `_pickImage()`'s body (i.e., the surrounding lines match the snippet in
   Proposed Solution) and is followed by `await _pickImageFromWebFilePicker();`
   then `return;`.
4. **Static grep — File-based upload preserved:**
   `grep -n "_uploadImageToStorage" lib/features/bands/band_form_screen.dart`
   still shows the definition
   `Future<String?> _uploadImageToStorage(File imageFile) async {`
   unchanged (currently at
   [line 1110](lib/features/bands/band_form_screen.dart#L1110)).
5. **Static grep — bytes-based upload added:**
   `grep -n "_uploadPickedBytesToStorage" lib/features/bands/band_form_screen.dart`
   returns the new method definition and exactly one call site (inside
   `_pickImageFromWebFilePicker()`).
6. **Static grep — extension whitelist present:**
   `grep -n "png\|jpg\|jpeg\|gif\|webp" lib/features/bands/band_form_screen.dart`
   returns at least one hit inside `_uploadPickedBytesToStorage`. QA
   visually confirms the fallback (`'png'`) branch is executed when the
   picked extension is outside the whitelist. This is the only guard on the
   extension flowing into the Supabase Storage object key; Tony validates
   the runtime behavior in W8.
7. **Widget-test file absence:** the pipeline deliberately leaves Engineer
   implementation uncommitted through QA, so this gate must inspect the
   working tree, not `main..HEAD`. Both of the following commands must
   produce empty output:
   - `git diff --stat -- test/` — no tracked-file changes under `test/`.
   - `git ls-files --others --exclude-standard -- test/` — no new
     (untracked) files under `test/`.

   This is a deliberate gate — the plan's Change Budget and the "Why no
   behavioral widget test" section above justify why. If either command
   produces any output, QA must reject the PR and route it back for
   reconciliation.
8. **`@visibleForTesting` absence:**
   `grep -rn "visibleForTesting" lib/features/bands/` returns no hits. This
   guards against Engineer working around the private-method boundary by
   quietly promoting `_pickImageFromWebFilePicker` to a testable public
   method — which the Change Budget explicitly disallows.
9. **`BandAvatar` and `DraftBandState` public API untouched:** working-tree
   check (implementation is uncommitted through QA, so `main..HEAD` would
   falsely show no changes):
   `git diff --stat -- lib/features/bands/widgets/band_avatar.dart lib/features/bands/active_band_controller.dart`
   returns empty output (no modified lines against either file).
10. **No dev-dependency drift:** working-tree check (implementation is
    uncommitted through QA):
    `git diff -- pubspec.yaml pubspec.lock` returns empty output — no
    changes to `dependencies:` or `dev_dependencies:` (in particular no
    addition of `mockito` or `mocktail`).
11. **Change budget compliance:** working-tree check (implementation is
    uncommitted through QA):
    `git diff --stat -- lib/features/bands/band_form_screen.dart`
    reports a net line delta (insertions minus deletions) within +53 to
    +73.
12. **No newly added `debugPrint(` calls (mandatory diff-safety gate):**
    working-tree check (implementation is uncommitted through QA):
    `git diff -- lib/features/bands/band_form_screen.dart | grep -c '^+.*debugPrint('`
    returns exactly `0`. Neither new helper
    (`_uploadPickedBytesToStorage`, `_pickImageFromWebFilePicker`) logs
    via `debugPrint`. The pre-existing `debugPrint` lines in the mobile
    branch of `_pickImage()` and in `_uploadImageToStorage(File)` are not
    modified by this PR and therefore do not appear as `^+` additions in
    the diff. This gate reconciles QA Cycle 1's Critical `[code-quality]`
    finding and is non-negotiable — if the count is anything other than
    `0`, QA must reject the PR and route it back for reconciliation.
13. **`flutter test` — full suite, no regressions:** `flutter test` runs
    to green with the existing suite. No new test is added or expected in
    this PR (see gate 7).

### Tier 2 — Post-deploy (owner-run punch list; Tony executes at PR-test / apply time)

QA must not attempt these; they require a running app and are not
mechanically executable in the QA harness. Deliver as an exact punch list.

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

## QA Regression Areas

QA must run and report on:

- `flutter analyze` — clean.
- `flutter test` — full suite, all pass. No new test file is added or
  expected in this PR (see Tier 1 gate 7 and the "Why no behavioral widget
  test" note above).
- Static gates 2–12 in Tier 1 above, including gate 12's mandatory
  diff-safety check that the implementation diff adds zero new
  `debugPrint(` calls.
- Static SQL/migration review — **none applicable** (no migrations in this
  PR). QA must confirm no files under `supabase/migrations/` or
  `supabase/functions/` are modified.
- Ephemeral-DB apply-check — **not applicable** (no migrations).

QA must **not** attempt to run the app, spin up simulators/emulators, or
drive a browser. Tier 2 is delivered verbatim to Tony as the owner-run
punch list.

## Rollout Strategy

Single PR against `main`.

- Merge triggers the web deploy via `tools/deploy_web.sh` / Vercel; no
  feature flag, no phased rollout — the behavior change is web-only and
  strictly additive (a bug fix).
- iOS / Android / macOS builds require no coordinated release: the mobile
  code path is byte-identical, so the fix does not need to ship in a mobile
  binary. Users on existing mobile builds are unaffected.
- Rollback: revert the single commit and redeploy the web build. No database
  or storage state is created or altered that would need cleanup.

## Out of Scope

- **A behavioral `flutter test` widget test for the web pick+upload path.**
  Explicitly out of scope for this PR. `_BandFormScreenState` and
  `_pickImageFromWebFilePicker` are library-private and cannot be reached
  from `test/features/bands/*` without either promoting them to public API
  or adding a first-ever `@visibleForTesting` annotation — both of which
  contradict this plan's zero-new-public-API budget. And even if the method
  were reachable, the flow's assertion (`_uploadedImageUrl` is set) depends
  on `supabase.storage.from('band-avatars').uploadBinary(...)`, for which
  the repo has no fake, no dependency-injection seam, and no
  `mockito`/`mocktail` dev dependency. Behavior is verified end-to-end by
  the Tier 2 owner-run punch list (W1–W9). A future PR that adds a general
  `SupabaseClient` mocking convention (or a `SupabaseStorageClient`
  provider seam) could revisit this, but it must not ride along with this
  bug fix.
- The stale `// ignore: unused_element` at
  [band_form_screen.dart#L1286](lib/features/bands/band_form_screen.dart#L1286)
  above `_pickImage()`. It is a false-positive suppressor that predates this
  bug; removing it is a lint-cleanup task and is not part of this fix.
- Any refactor to unify `_uploadImageToStorage(File)` and
  `_uploadPickedBytesToStorage(Uint8List, String)` behind a single helper.
  Keep them as siblings to guarantee mobile behavior is untouched.
- Any change to `BandAvatar` to render `Image.memory` for a bytes-based
  local preview on web. The `_isUploadingImage` overlay plus fast post-upload
  `Image.network` render is sufficient; a bytes-based preview would ripple
  through ~14 downstream widgets (see Files Off-Limits).
- Any change to macOS's picker experience. macOS currently uses the mobile
  `image_picker` path; that behavior is preserved. If desktop-native macOS
  file picking is desired, it is a separate feature.
- Any change to how `avatar_color` is chosen or persisted.
- Any change to Supabase Storage bucket configuration, policies, or RLS.
- Any change to the invitation email flow, band-creation RPC, or backup
  import/export flows in the same screen.
