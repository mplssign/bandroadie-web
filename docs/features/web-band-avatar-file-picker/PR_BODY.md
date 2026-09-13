## Summary

Fixes band avatar uploads on Flutter Web by opening the browser's native image file chooser directly instead of showing the mobile camera/photo-library bottom sheet.

## Changes

- Route web avatar selection through the existing `file_picker` dependency.
- Upload selected image bytes directly to the existing `band-avatars` storage bucket.
- Preserve the existing iOS, Android, and macOS camera/photo-library flow unchanged.
- Normalize and validate image extensions before upload.

## Verification

- Focused and full `flutter analyze`: passed with no issues.
- Full `flutter test`: passed with 0 failures.
- Independent QA approved the web/native split, upload state handling, storage path, extension validation, and unchanged native path through code review.
- Runtime browser and native-platform checks remain in the QA manual verification punch list.

## Scope

- No dependency changes.
- No database migrations, RLS changes, RPCs, or edge functions.
- No app build or deployment is included in this PR.
