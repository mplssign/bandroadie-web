## Summary

Fixes band avatar uploads on Flutter Web and macOS by opening the native image file chooser directly instead of showing the mobile camera/photo-library bottom sheet.

## Changes

- Route web and macOS avatar selection through the existing `file_picker` dependency.
- Upload selected image bytes directly to the existing `band-avatars` storage bucket.
- Preserve the existing iOS and Android camera/photo-library flow unchanged.
- Normalize and validate image extensions before upload.

## Verification

- Focused and full `flutter analyze`: passed with no issues.
- Full `flutter test`: passed with 0 failures.
- Independent QA approved the web/macOS versus iOS/Android split, upload state handling, storage path, extension validation, and unchanged mobile path through code review.
- Runtime browser and native-platform checks remain in the QA manual verification punch list.

## Scope

- No dependency changes.
- No database migrations, RLS changes, RPCs, or edge functions.
- No app build or deployment is included in this PR.
