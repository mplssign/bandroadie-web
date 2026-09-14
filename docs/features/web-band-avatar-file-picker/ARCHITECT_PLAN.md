# ARCHITECT_PLAN — web-band-avatar-file-picker

## Feature Slug

`web-band-avatar-file-picker`

## Feature Title

Use a desktop file picker for band avatar uploads on web and macOS

## Cycle Number

3

## Cycle 3 Revision Trigger

Tony's owner-test walkthrough of the Cycle 2 build (currently committed as
`7c68ab8` on branch `bug/web-band-avatar-file-picker`, open as PR #294)
surfaced a revised product requirement: the same file-chooser UX the Cycle 2
fix delivered on Flutter Web at `app.bandroadie.com` must also apply on the
native macOS app. Cycle 2's `kIsWeb`-scoped guard leaves macOS on the mobile
"Choose Image Source" bottom sheet path, which is the same mobile-oriented
UX Cycle 2 rejected for web. Cycle 3 broadens the platform predicate to
include macOS while leaving iOS, Android, Windows, and Linux untouched. No
Cycle 2 implementation is undone — the bytes upload helper, the file-chooser
helper, the extension whitelist, the `showModalBottomSheet` count, and the
zero-added-`debugPrint(` reconciliation from QA Cycle 1 are all retained.

## Problem Summary

The band-avatar upload control (the "+" icon on the color strip in
Create Band / Edit Band) presents a `showModalBottomSheet` titled
"Choose Image Source" with "Take Photo" / "Photo Library" options tied to
`image_picker`'s camera/gallery sources. Prior to Cycle 2 this was wrong on
web because web users cannot select a desktop file through a
camera/photo-library sheet — Cycle 2 shipped a `kIsWeb`-scoped file-chooser
branch that resolved that. Owner testing of Cycle 2 showed the same UX is
also wrong on macOS: the macOS app is a desktop native binary with no
phone-style camera, so a "Take Photo" / "Photo Library" sheet is a
mobile-oriented mismatch on that platform too. macOS users expect a native
`NSOpenPanel` file chooser. iOS and Android behavior is correct and must be
preserved. Windows and Linux are explicitly out of scope per Tony's product
decision (see Out of Scope for the rationale).

## Root Cause

**Confidence: HIGH** for both the Cycle 2 (web) diagnosis and the Cycle 3
(macOS) expansion. Every claim below is confirmed against the currently
committed source at `HEAD` on branch `bug/web-band-avatar-file-picker`
(commit `7c68ab8`).

The class-of-bug is a single-platform guard in `_pickImage()`. Prior to
Cycle 2 the method unconditionally opened a `showModalBottomSheet<ImageSource>`
with "Take Photo" / "Photo Library" tied to `image_picker`'s camera/gallery
sources, and wrapped the result in `dart:io.File(image.path)`. Cycle 2
added a `kIsWeb`-scoped early-return that routes web through
`_pickImageFromWebFilePicker()` (bytes-based `file_picker` +
`_uploadPickedBytesToStorage(...)`). That guard is now committed at
[band_form_screen.dart#L1354-L1358](lib/features/bands/band_form_screen.dart#L1354-L1358):

```dart
Future<void> _pickImage() async {
  if (kIsWeb) {
    await _pickImageFromWebFilePicker();
    return;
  }
  // showModalBottomSheet<ImageSource>(...) → image_picker → File(image.path)
}
```

**Cycle 3 root cause:** the guard is scoped to `kIsWeb` only. On macOS
`kIsWeb == false`, so control falls through to the mobile bottom sheet and
the mobile-oriented `image_picker` camera/gallery path — the same UX
mismatch Cycle 2 rejected on web, for the same underlying reason (desktop
platform, no phone-style camera, users expect the native OS file chooser).
`grep -n "Platform.isMacOS" lib/features/bands/band_form_screen.dart`
returns zero hits — no macOS-specific branch exists anywhere in this file.

Every piece of machinery Cycle 3 needs is already on the branch and known
good from Cycle 2's APPROVED validation:

- `_pickImageFromWebFilePicker()` at
  [band_form_screen.dart#L1314](lib/features/bands/band_form_screen.dart#L1314)
  is platform-agnostic — it calls `FilePicker.platform.pickFiles(type:
  FileType.image, withData: true)`, reads `PlatformFile.bytes`, and
  delegates to the bytes-upload helper. `file_picker: ^8.1.2` at
  [pubspec.yaml#L34](pubspec.yaml#L34) already ships macOS support and
  populates `PlatformFile.bytes` from the native `NSOpenPanel` when
  `withData: true`.
- `_uploadPickedBytesToStorage(Uint8List, String)` at
  [band_form_screen.dart#L1144](lib/features/bands/band_form_screen.dart#L1144)
  is transport-agnostic — it accepts bytes from any source and writes to
  the existing `band-avatars` bucket. The `png|jpg|jpeg|gif|webp` whitelist
  and `png` fallback are unchanged.
- macOS's sandbox entitlements at
  [macos/Runner/Release.entitlements](macos/Runner/Release.entitlements)
  and
  [macos/Runner/DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements)
  already declare `com.apple.security.files.user-selected.read-write:
  true` — exactly what the sandboxed app needs to read a user-selected
  file returned from `NSOpenPanel`. No entitlements change is required.
- `dart:io` is already imported at
  [band_form_screen.dart#L1](lib/features/bands/band_form_screen.dart#L1),
  and this file already uses `Platform.isIOS` / `Platform.isAndroid`
  inside `_checkCameraPermission()` and `_checkPhotoLibraryPermission()`
  (both reached only from the mobile branch of `_pickImage()`, i.e. only
  when `kIsWeb == false`). Adding `Platform.isMacOS` to a short-circuit
  `||` after `kIsWeb` follows the existing pattern — on web the LHS is a
  compile-time `true` and the RHS is not evaluated at runtime.

Cycle 3 therefore needs only a single-line widening of the guard predicate,
from `if (kIsWeb)` to `if (kIsWeb || Platform.isMacOS)`. No new helper, no
new dependency, no new entitlement, no rename, no widget-contract change,
no new `debugPrint(` line.

## Existing System Analysis

**Cycle 3 note:** the pre-Cycle-2 code excerpts and line numbers below
(`_pickImage` at ~L1287, `_uploadImageToStorage` at ~L1110, avatar wiring at
~L1715, submit paths at ~L325 and ~L470) describe the surface as it was
when Cycle 1 was written. All of that reasoning still applies unchanged
for Cycle 3 — the widget-tree contracts, the dirty-tracking predicate,
the pre-uploaded submit paths, and the draft-band URL propagation all
remain the correct places to plug in a second desktop platform. The
current committed line numbers on branch `bug/web-band-avatar-file-picker`
differ because Cycle 2 added ~72 lines above them; the relevant symbols
now live at
[band_form_screen.dart#L1354](lib/features/bands/band_form_screen.dart#L1354)
(`_pickImage`),
[#L1314](lib/features/bands/band_form_screen.dart#L1314)
(`_pickImageFromWebFilePicker`),
[#L1144](lib/features/bands/band_form_screen.dart#L1144)
(`_uploadPickedBytesToStorage`), and
[#L1111](lib/features/bands/band_form_screen.dart#L1111)
(`_uploadImageToStorage(File)`).

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

Widen the existing `kIsWeb` guard at the top of `_pickImage()` to
`kIsWeb || Platform.isMacOS`. Every other line of the file, and every
other file in the repository, stays untouched.

### Cycle 3 change (the entire delta)

```dart
// Before (currently committed on this branch):
Future<void> _pickImage() async {
  if (kIsWeb) {
    await _pickImageFromWebFilePicker();
    return;
  }
  // mobile bottom sheet + image_picker path (unchanged)
}

// After (Cycle 3):
Future<void> _pickImage() async {
  if (kIsWeb || Platform.isMacOS) {
    await _pickImageFromWebFilePicker();
    return;
  }
  // mobile bottom sheet + image_picker path (unchanged)
}
```

One token change. `Platform.isMacOS` is safe to reference here:

- `dart:io` is already imported at
  [band_form_screen.dart#L1](lib/features/bands/band_form_screen.dart#L1);
  no import edit is required.
- On Flutter Web, `kIsWeb` is a compile-time constant `true`, so the
  `||`'s right-hand side is not evaluated at runtime. This matches the
  existing `Platform.isIOS` / `Platform.isAndroid` usage in
  `_checkCameraPermission()` and `_checkPhotoLibraryPermission()`, which
  are also reached only when `kIsWeb == false` and have shipped on web
  without incident.
- On native macOS, `kIsWeb == false` and `Platform.isMacOS == true`, so
  the branch takes and `_pickImageFromWebFilePicker()` handles the
  `NSOpenPanel` + bytes-upload flow. iOS / Android continue to fall
  through to the existing mobile branch unchanged (`Platform.isMacOS` is
  `false` on both).

### Method-name pragmatism

`_pickImageFromWebFilePicker` is a private symbol whose name will slightly
misdescribe its callers after Cycle 3 (it now handles web + macOS). A
rename is not part of Cycle 3: it would expand the diff surface beyond a
one-token guard change, force QA to re-grep for a new symbol, and provide
no behavioral value — the misleading name is a library-private
readability nit, not a correctness bug. A future cleanup PR may rename it
(see Out of Scope).

### Why the Cycle 2 helpers already cover macOS

- `FilePicker.platform.pickFiles(type: FileType.image, withData: true)`
  on macOS opens the native `NSOpenPanel` filtered to image types and
  populates `PlatformFile.bytes` in-memory. The Cycle 2 helper reads
  exactly that field and hands the bytes to
  `_uploadPickedBytesToStorage`.
- `_uploadPickedBytesToStorage`'s `png|jpg|jpeg|gif|webp` extension
  whitelist and `png` fallback are transport-agnostic and equally correct
  for a file picked from macOS Finder as for one picked from a browser
  file input.
- Extension is read from `PlatformFile.extension`, which on macOS is
  parsed from the picked file's name by the `file_picker` plugin. The
  whitelist gates any hostile or unexpected value before it reaches the
  Supabase Storage object key.
- `HapticFeedback.lightImpact()` is a no-op on macOS (the desktop `Haptic`
  channel is unimplemented on that platform) but does not throw — it is
  safe to leave in the shared helper. This matches the pre-existing
  behavior on web where the same call is also a no-op.
- Success → `showSuccessSnackBar`, failure → `showErrorSnackBar`,
  cancellation → silent return. All three paths are already exercised on
  web and require no macOS-specific handling.

### What does not change

- The mobile branch of `_pickImage()` (bottom sheet + `image_picker` +
  `dart:io.File`) is textually unchanged. iOS and Android continue on it
  byte-for-byte.
- `_uploadImageToStorage(File imageFile)` is untouched (still used by the
  mobile branch).
- `BandAvatar`, `DraftBandState.localImageFile`, and every downstream
  widget that threads `localImageFile: File?` remain on their existing
  contracts.
- No `debugPrint(` line is added anywhere in the file. The Cycle 1
  reconciliation stays in force.
- No macOS `Info.plist` change, no macOS Podfile change, no
  Runner.xcodeproj change.

## Database Impact

Not applicable. No schema, RLS, RPC, trigger, edge function, or storage
policy changes. The `band-avatars` bucket and its existing RLS/storage
policies handle the upload identically whether the bytes came from a `File`
or from a `Uint8List`.

## Flutter Architecture Changes

- No new controller, provider, repository, or service.
- No new package dependency. `file_picker: ^8.1.2` already supports macOS's
  native `NSOpenPanel` with `withData: true` — verified against the
  currently committed [pubspec.yaml](pubspec.yaml#L34).
- No new entitlement. macOS's sandbox already declares
  `com.apple.security.files.user-selected.read-write: true` in both
  [macos/Runner/Release.entitlements](macos/Runner/Release.entitlements)
  and
  [macos/Runner/DebugProfile.entitlements](macos/Runner/DebugProfile.entitlements),
  which is exactly what `NSOpenPanel`-returned files require to be read
  back by the sandboxed app.
- No init-order change (`WidgetsFlutterBinding` → URL strategy → orientation
  lock → `AppVersionService.init` → `validateSupabaseConfig` →
  `Supabase.initialize` → `Firebase.initializeApp` [native only] →
  `DeepLinkService` → `runApp` is untouched).
- No routing change.
- No auth-flow change (PKCE on both platforms unchanged).
- Platform conditionality remains confined to a single guard inside one
  method on one screen. iOS and Android retain their `image_picker` +
  `showModalBottomSheet` flow byte-for-byte; the mobile branch is
  textually unchanged from Cycle 2. macOS is the platform whose behavior
  changes in Cycle 3 — it moves off the mobile branch onto the Cycle 2
  file-chooser branch. Windows and Linux are not touched (see Out of Scope).
- Firebase and `DeepLinkService` are not touched.

## Files to Create

- None. No new files in `lib/`. No new test file — the widget-test path for
  the web pick is intentionally omitted; the tradeoffs and reasoning are in
  the Verification Plan below, and it is called out again in Out of Scope.

## Files to Modify

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart) —
  **one line edit only.** In `_pickImage()` at
  [line 1355](lib/features/bands/band_form_screen.dart#L1355), change the
  existing guard from

  ```dart
  if (kIsWeb) {
  ```

  to

  ```dart
  if (kIsWeb || Platform.isMacOS) {
  ```

  Every other line in this file, including the entire mobile branch of
  `_pickImage()`, both upload helpers, both permission helpers, the
  `kIsWeb` import, and the `dart:io` import, is textually unchanged.

## Files Off-Limits

- Every part of
  [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
  **except** the single guard-line change in `_pickImage()` described
  above. In particular: both upload helpers, both permission helpers, the
  mobile branch of `_pickImage()`, `_pickImageFromWebFilePicker()`, the
  imports, and the stale `// ignore: unused_element` above `_pickImage()`
  are all off-limits.
- [lib/features/bands/widgets/band_avatar.dart](lib/features/bands/widgets/band_avatar.dart) —
  Adding a bytes-based preview field ripples through ~14 downstream widgets.
  The fix does not require it.
- [lib/features/bands/active_band_controller.dart](lib/features/bands/active_band_controller.dart) —
  `DraftBandState.localImageFile` contract stays as `File?`; the macOS
  path (like the web path) simply doesn't populate it and lets
  `updateImageUrl(...)` handle the post-upload preview.
- All widgets that thread `localImageFile: File?`:
  `home_app_bar.dart`, `home_screen.dart`, `home_tab_content.dart`,
  `empty_home_state.dart`, `calendar_app_bar.dart`, `calendar_screen.dart`,
  `calendar_tab_content.dart`, `setlists_app_bar.dart`, `setlists_screen.dart`,
  `setlists_tab_content.dart`, `contacts_tab_content.dart`,
  `members_tab_content.dart`.
- `pubspec.yaml` and `pubspec.lock` — no dependency changes.
- All macOS platform files: `macos/Runner/Release.entitlements`,
  `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Info.plist`,
  `macos/Podfile`, `macos/Runner.xcodeproj/`, `macos/Runner.xcworkspace/`.
  The existing `com.apple.security.files.user-selected.read-write: true`
  entitlement is already sufficient.
- All iOS platform files (`ios/`), all Android platform files (`android/`),
  all Windows platform files (`windows/`), and all Linux platform files
  (`linux/`).
- All Supabase migrations, RPCs, storage policies, and edge functions.
- `lib/main.dart` — no init-order or config change.
- All non-Bands features (auth, gigs, rehearsals, setlists, notifications,
  routing, financials).

## Change Budget

### Cycle 3 delta (incremental, on top of the currently committed Cycle 2)

- [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart):
  **+1 / −1 lines** (a single line's condition changes from `if (kIsWeb) {`
  to `if (kIsWeb || Platform.isMacOS) {`). Net line delta: **0**.
- Test files: **+0 files, +0 lines** in `test/`.
- Expected new files anywhere in the repo: **0**.
- Expected new public classes / methods: **0** — no rename, no new symbol,
  no `@visibleForTesting` annotation.
- Expected new dependencies: **0**.
- Expected new `debugPrint(` lines: **0**.

### Cumulative branch budget (`main`..`HEAD` after Cycle 3 lands)

Because Cycle 3 modifies a line that was already added in Cycle 2 (an
in-place condition edit inside the already-added `if (kIsWeb) {` block),
the cumulative `git diff --stat main..HEAD -- lib/features/bands/band_form_screen.dart`
remains within the Cycle 2 approved budget:

- Net line delta versus `main`: **+53 to +73** (unchanged from Cycle 2).
  QA's Cycle 2 measurement was `+72/-0`; Cycle 3 does not shift that
  number because the token added on the modified line (` || Platform.isMacOS`)
  is small enough that the line does not re-wrap. If Engineer's local
  `dart format` re-wraps the line, the net delta may rise to `+73`; both
  outcomes remain in-bounds.
- Cumulative new files: **0**.
- Cumulative new public symbols: **0**.
- Cumulative new dependencies: **0**.

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
| Platforms — Web | unaffected in Cycle 3 (Cycle 2 already fixed this on branch) |
| Platforms — iOS | unaffected (mobile branch untouched) |
| Platforms — Android | unaffected (mobile branch untouched) |
| Platforms — macOS | **behavior fix in Cycle 3** (moves from mobile bottom sheet to `NSOpenPanel` file chooser via the Cycle 2 file-chooser helper) |
| Platforms — Windows | unaffected (out of scope per Tony) |
| Platforms — Linux | unaffected (out of scope per Tony) |
| macOS entitlements | unaffected (already sufficient) |
| App init order (`main.dart`) | unaffected |
| Firebase init (native only) | unaffected |
| `DeepLinkService` | unaffected |

## Regression Risk

**Cycle 3 delta risk: LOW.** The change is a one-token widening of an
already-shipped, QA-APPROVED guard. The Cycle 2 helpers it now delegates
to on macOS are platform-agnostic by construction (they accept bytes and
do not depend on `dart:io.File`).

**Cumulative branch risk: LOW.**

- No auth, session, routing, or init-order code is touched.
- No database, RLS, RPC, or edge-function surface is touched.
- The mobile `image_picker` + bottom-sheet code path is not edited — it is
  simply skipped when `kIsWeb == true` or `Platform.isMacOS == true`.
- iOS and Android remain on the mobile branch byte-for-byte; the guard
  widening's short-circuit `||` evaluates left-to-right and
  `Platform.isMacOS` is `false` on both platforms.
- The upload helper for `File` is not modified; the bytes-based sibling
  is reused.
- Widget-tree contracts (`BandAvatar`, `DraftBandState.localImageFile`)
  are unchanged, so the ~14 downstream avatar-preview call sites remain
  unaffected.
- macOS's `com.apple.security.files.user-selected.read-write`
  entitlement is already declared for both Debug and Release, so the
  sandboxed macOS binary can read the file returned from `NSOpenPanel`
  without any Xcode project change.
- Residual risk: a picked file's extension is unusual on macOS (e.g. a
  `.heic` still-image from a macOS Continuity import). The `png` fallback
  in `_uploadPickedBytesToStorage`'s whitelist normalizes any
  outside-whitelist extension to `png`; the upload still succeeds and
  `Image.network` still renders the resulting object.

## Engineer Task Breakdown

Cycle 3 is a single-token edit. The full task list is:

1. Open [lib/features/bands/band_form_screen.dart](lib/features/bands/band_form_screen.dart)
   and locate `_pickImage()` (currently at
   [line 1354](lib/features/bands/band_form_screen.dart#L1354)).

2. Change the existing guard at
   [line 1355](lib/features/bands/band_form_screen.dart#L1355) from:

   ```dart
   if (kIsWeb) {
     await _pickImageFromWebFilePicker();
     return;
   }
   ```

   to:

   ```dart
   if (kIsWeb || Platform.isMacOS) {
     await _pickImageFromWebFilePicker();
     return;
   }
   ```

   No other line in the method or the file is edited. Do not rename
   `_pickImageFromWebFilePicker`. Do not add any `debugPrint(` line. Do not
   add or remove any import (`dart:io` and `kIsWeb` are already imported).
   Do not modify the stale `// ignore: unused_element` above `_pickImage()`.
   Do not modify `_uploadImageToStorage(File)`,
   `_uploadPickedBytesToStorage`, `_pickImageFromWebFilePicker`,
   `_checkCameraPermission`, or `_checkPhotoLibraryPermission`. Do not
   modify `BandAvatar`, `DraftBandState`, or any widget that consumes
   `localImageFile: File?`. Do not annotate any method as
   `@visibleForTesting`. Do not create or modify any test file. Do not
   add, bump, or remove any entry in `dependencies` or `dev_dependencies`.
   Do not modify any file under `macos/`, `ios/`, `android/`, `windows/`,
   `linux/`, `supabase/`, or `lib/main.dart`.

3. Run `dart format lib/features/bands/band_form_screen.dart`. If the
   formatter re-wraps the guard line, keep the re-wrapped form and confirm
   the semantics still express `kIsWeb || Platform.isMacOS` (do not
   convert it to two nested `if` statements, do not add parentheses that
   change grouping).

4. Run `flutter analyze`; must be clean with no new warnings.

5. Run `flutter test`; the full suite passes with no regressions. No new
   test is added or expected in this PR (see Verification Plan for the
   ongoing Cycle 1 rationale).

## Verification Plan

### Why no behavioral widget test in this PR

A `flutter test` widget test that exercises the actual pick+upload flow
(on web or macOS) is intentionally omitted. The engineering cost is
disproportionate to a one-line guard-widening bug fix, and the coverage
gap is fully closed by the Tier 1 static gates plus the Tier 2 owner-run
punch list. The concrete blockers, all grounded in the current repo:

1. `_BandFormScreenState` is library-private. It cannot be referenced by
   name from `test/features/bands/*`, so casting a `StatefulElement`'s
   state to `_BandFormScreenState` and calling
   `_pickImageFromWebFilePicker()` is not legal Dart across libraries.
2. Making `_pickImageFromWebFilePicker` public — either by rename or by
   `@visibleForTesting` — would introduce a public API surface solely
   for a test. No file under `lib/` currently uses `@visibleForTesting`;
   this would be a first-time convention adopted for one test,
   contradicting both the "zero new public API surface" line in the
   Change Budget and the private-method design in Proposed Solution. Per
   the plan's own guardrails, that tradeoff is not justified for a bug
   fix.
3. Even if `_pickImageFromWebFilePicker` were callable from a test, the
   assertion the test needs to make — "the upload produced a public URL
   and `_uploadedImageUrl` is set" — depends on
   `supabase.storage.from('band-avatars').uploadBinary(...)` and
   `getPublicUrl(...)`. `SupabaseClient` is a global singleton
   (`Supabase.instance.client`, wrapped by the top-level
   [supabase](lib/app/services/supabase_client.dart#L13) getter). There
   is no dependency-injection provider for it, no fake/mocked storage
   client anywhere under `test/`
   (`grep -R "band-avatars\|uploadBinary\|storage.from" test/` returns no
   hits), and `dev_dependencies` contains neither `mockito` nor
   `mocktail` — only `flutter_test`. Wiring a fake storage seam would
   require either a real Supabase-mocking dev dependency (new dependency,
   out of budget) or a production-code refactor that injects the storage
   client (a genuine architectural change, out of scope for a
   guard-widening bug fix).
4. `FilePicker.platform` on its own is swappable (its `PlatformInterface`
   allows `FilePicker.platform = FakeFilePickerPlatform()`), but the
   value of a test that only proves "we called `pickFiles`" is small
   compared to what W1–W9 already prove on real browsers and native
   platforms.

The Tier 1 gates below therefore verify the exact code shape that
produces the fix — the widened `kIsWeb || Platform.isMacOS` guard, the
unchanged Cycle 2 helpers, the untouched mobile path, the untouched
`BandAvatar`/`DraftBandState` contracts, and the change-budget bounds —
and the Tier 2 punch list Tony runs at PR-test time exercises the actual
behavior end-to-end on the deployed web build plus all three native
platforms.

### Tier 1 — Pre-deploy (QA gate; mechanically executable without a running app)

Never call the code path being replaced. All working-tree gates use the
working tree (implementation is uncommitted through QA); commit-history
diffs `main..HEAD` reflect the Cycle 2 baseline and are checked separately
where noted.

1. **Static analysis:** `flutter analyze` — clean, no new warnings, no
   `avoid_web_libraries_in_flutter` / `dart:io` warnings introduced.
2. **Static grep — mobile path unchanged (bottom-sheet count):**
   `grep -c "showModalBottomSheet" lib/features/bands/band_form_screen.dart`
   returns exactly `2`. Both hits stay put — one for the invitation-email
   bottom sheet (currently
   [line 547](lib/features/bands/band_form_screen.dart#L547)) and one
   inside the mobile branch of `_pickImage()` (currently
   [line 1360](lib/features/bands/band_form_screen.dart#L1360)). Cycle 3
   does not introduce or remove any `showModalBottomSheet(` call.
3. **Static grep — widened guard present (Cycle 3 signature):**
   `grep -n "kIsWeb || Platform.isMacOS" lib/features/bands/band_form_screen.dart`
   returns exactly one hit. QA visually confirms it is the guard at the
   top of `_pickImage()`'s body — the exact three-line block below is
   present, with no parenthesization changes and no additional
   short-circuit terms (no `|| Platform.isWindows`, no `|| Platform.isLinux`):

   ```dart
   if (kIsWeb || Platform.isMacOS) {
     await _pickImageFromWebFilePicker();
     return;
   }
   ```

   In addition, `grep -c "if (kIsWeb) {" lib/features/bands/band_form_screen.dart`
   returns exactly `0` (the Cycle 2 narrower form is gone).
4. **Static grep — File-based upload preserved:**
   `grep -n "_uploadImageToStorage" lib/features/bands/band_form_screen.dart`
   still shows the definition
   `Future<String?> _uploadImageToStorage(File imageFile) async {`
   unchanged (currently at
   [line 1111](lib/features/bands/band_form_screen.dart#L1111)).
5. **Static grep — bytes-based upload unchanged:**
   `grep -n "_uploadPickedBytesToStorage" lib/features/bands/band_form_screen.dart`
   returns the definition (currently at
   [line 1144](lib/features/bands/band_form_screen.dart#L1144)) plus
   exactly one call site (inside `_pickImageFromWebFilePicker`, currently
   at
   [line 1328](lib/features/bands/band_form_screen.dart#L1328)). No
   second call site has been added.
6. **Static grep — extension whitelist present (unchanged from Cycle 2):**
   `grep -n "png\|jpg\|jpeg\|gif\|webp" lib/features/bands/band_form_screen.dart`
   returns at least one hit inside `_uploadPickedBytesToStorage`, and the
   `png` fallback branch for outside-whitelist values remains present.
   Tony validates the runtime behavior in W8.
7. **Widget-test file absence:** the pipeline deliberately leaves
   Engineer implementation uncommitted through QA, so this gate must
   inspect the working tree, not `main..HEAD`. Both of the following
   commands must produce empty output:
   - `git diff --stat -- test/` — no tracked-file changes under `test/`.
   - `git ls-files --others --exclude-standard -- test/` — no new
     (untracked) files under `test/`.

   This is a deliberate gate — the plan's Change Budget and the "Why no
   behavioral widget test" section above justify why. If either command
   produces any output, QA must reject the PR and route it back for
   reconciliation.
8. **`@visibleForTesting` absence:**
   `grep -rn "visibleForTesting" lib/features/bands/` returns no hits.
   This guards against Engineer working around the private-method
   boundary by quietly promoting `_pickImageFromWebFilePicker` to a
   testable public method — which the Change Budget explicitly disallows.
9. **`BandAvatar` and `DraftBandState` public API untouched:**
   working-tree check:
   `git diff --stat -- lib/features/bands/widgets/band_avatar.dart lib/features/bands/active_band_controller.dart`
   returns empty output (no modified lines against either file).
10. **No dependency drift:** working-tree check:
    `git diff -- pubspec.yaml pubspec.lock` returns empty output — no
    changes to `dependencies:` or `dev_dependencies:` (in particular no
    addition of `mockito` or `mocktail`).
11. **Change budget compliance:** two checks, both working-tree.
    - `git diff --stat -- lib/features/bands/band_form_screen.dart`
      versus the Cycle 2 baseline commit (`git diff HEAD --stat --
      lib/features/bands/band_form_screen.dart`) reports a Cycle 3
      incremental net line delta between `−1/+1` and `−2/+2`. Anything
      larger indicates Engineer over-reached.
    - `git diff --stat main -- lib/features/bands/band_form_screen.dart`
      reports a cumulative net line delta within +53 to +73 (Cycle 2
      approved budget carries forward; Cycle 3 does not shift it).
12. **No newly added `debugPrint(` calls (Cycle 1 diff-safety gate
    remains in force):** working-tree check:
    `git diff -- lib/features/bands/band_form_screen.dart | grep -c '^+.*debugPrint('`
    returns exactly `0`. The pre-existing `debugPrint` lines in the
    mobile branch of `_pickImage()` and in `_uploadImageToStorage(File)`
    are not modified by Cycle 3 and therefore do not appear as `^+`
    additions. If the count is anything other than `0`, QA must reject
    the PR and route it back for reconciliation.
13. **macOS / iOS / Android / Windows / Linux platform files untouched:**
    working-tree check:
    `git diff --stat -- macos/ ios/ android/ windows/ linux/`
    returns empty output. In particular no change to either macOS
    entitlements file, no change to any `Info.plist`, no change to any
    Xcode / Gradle / CMake project file.
14. **`flutter test` — full suite, no regressions:** `flutter test` runs
    to green with the existing suite. No new test is added or expected
    in this PR (see gate 7).

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

## QA Regression Areas

QA must run and report on:

- `flutter analyze` — clean.
- `flutter test` — full suite, all pass. No new test file is added or
  expected in this PR (see Tier 1 gate 7 and the "Why no behavioral
  widget test" note above).
- Static gates 2–13 in Tier 1 above, including gate 3's mandatory check
  that the guard reads exactly `if (kIsWeb || Platform.isMacOS) {`, gate
  11's incremental- and cumulative-budget checks, gate 12's zero-new-
  `debugPrint(` diff-safety check, and gate 13's macOS/iOS/Android/
  Windows/Linux platform-files-untouched check.
- Static SQL/migration review — **none applicable** (no migrations in
  this PR). QA must confirm no files under `supabase/migrations/` or
  `supabase/functions/` are modified.
- Ephemeral-DB apply-check — **not applicable** (no migrations).

QA must **not** attempt to run the app, spin up simulators/emulators, or
drive a browser. Tier 2 is delivered verbatim to Tony as the owner-run
punch list.

## Rollout Strategy

Single PR (#294) against `main` on branch `bug/web-band-avatar-file-picker`.

- Merge triggers the web deploy via `tools/deploy_web.sh` / Vercel; no
  feature flag, no phased rollout — the web behavior change is strictly
  additive (a bug fix that lands with Cycle 2 + Cycle 3 together on this
  branch).
- **macOS binary:** the Cycle 3 fix only reaches macOS users after a
  fresh macOS build is cut. iOS and Android continue on the mobile branch
  byte-for-byte and do **not** require a new binary; users on the current
  iOS/Android builds are unaffected. Tony chooses whether to cut a new
  macOS release now or fold it into the next scheduled desktop release.
- Windows and Linux users, if any exist on non-standard flutter builds
  from this repo, remain on the mobile bottom sheet code path
  (unchanged). See Out of Scope.
- Rollback: revert the single-line guard change (or revert the whole
  Cycle 2 + Cycle 3 branch merge commit) and redeploy the web build. No
  database or storage state is created or altered that would need
  cleanup.

## Out of Scope

- **Windows and Linux platform coverage.** Tony explicitly limited Cycle
  3's expansion to macOS + web. On Windows and Linux the current code
  falls through to the mobile bottom sheet + `image_picker` path. That
  path may be broken or partially unusable on those platforms today
  (`image_picker` has weaker desktop support than macOS/iOS/Android), but
  no code evidence forces us to widen scope now and the product
  requirement is explicit. If a future ticket asks for Windows/Linux, the
  same predicate widening pattern (`|| Platform.isWindows || Platform.isLinux`)
  can be re-applied — the Cycle 2 helpers are already platform-agnostic.
- **Renaming `_pickImageFromWebFilePicker`** to reflect that it now
  serves web + macOS. The name is a library-private readability nit; a
  rename would expand the diff surface beyond a one-token guard edit,
  force QA to re-grep for a new symbol, and provide no behavioral value.
  A future cleanup PR may rename it (a natural candidate is
  `_pickImageViaFileChooser`).
- **A behavioral `flutter test` widget test for the pick+upload path.**
  Explicitly out of scope for this PR. `_BandFormScreenState` and
  `_pickImageFromWebFilePicker` are library-private and cannot be
  reached from `test/features/bands/*` without either promoting them to
  public API or adding a first-ever `@visibleForTesting` annotation —
  both of which contradict this plan's zero-new-public-API budget. And
  even if the method were reachable, the flow's assertion
  (`_uploadedImageUrl` is set) depends on
  `supabase.storage.from('band-avatars').uploadBinary(...)`, for which
  the repo has no fake, no dependency-injection seam, and no
  `mockito`/`mocktail` dev dependency. Behavior is verified end-to-end
  by the Tier 2 owner-run punch list (W1–W9). A future PR that adds a
  general `SupabaseClient` mocking convention (or a
  `SupabaseStorageClient` provider seam) could revisit this, but it must
  not ride along with this bug fix.
- **The stale `// ignore: unused_element`** at
  [band_form_screen.dart#L1353](lib/features/bands/band_form_screen.dart#L1353)
  above `_pickImage()`. It is a false-positive suppressor that predates
  this bug; removing it is a lint-cleanup task and is not part of this
  fix.
- **Any refactor to unify `_uploadImageToStorage(File)` and
  `_uploadPickedBytesToStorage(Uint8List, String)`** behind a single
  helper. Keep them as siblings to guarantee iOS/Android behavior is
  untouched.
- **Any change to `BandAvatar`** to render `Image.memory` for a
  bytes-based local preview on web or macOS. The `_isUploadingImage`
  overlay plus fast post-upload `Image.network` render is sufficient; a
  bytes-based preview would ripple through ~14 downstream widgets (see
  Files Off-Limits).
- **Any change to how `avatar_color` is chosen or persisted.**
- **Any change to Supabase Storage bucket configuration, policies, or
  RLS.**
- **Any change to macOS entitlements, `Info.plist`, or Xcode project
  files.** The existing
  `com.apple.security.files.user-selected.read-write` entitlement is
  already correct.
- **Any change to the invitation email flow, band-creation RPC, or
  backup import/export flows** in the same screen.
