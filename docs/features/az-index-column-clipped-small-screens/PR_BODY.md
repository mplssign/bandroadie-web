## Bug Fix: A-Z index column clipped on small-height screens

### Problem

On short-height devices (iPhone SE class), the right-edge A-Z index column
in Contacts and Venues renders all 27 letters at a fixed `fontSize: 18` with
`FontWeight.w600`. At ~17.3 pt of available slot height per letter on an
iPhone SE, the fixed 18 pt font exceeds the slot, causing crowding and
clipping. Tap-to-scroll continued to work; only the visual rendering was
broken.

### Fix

Wrapped the `Column` in `AzIndexColumn.build()` in a `LayoutBuilder` so the
widget observes its actual available height at layout time. Font size is now:

```dart
final slotHeight = constraints.maxHeight / _allLetters.length;
final adaptiveFontSize = (slotHeight * 0.75).clamp(10.0, 18.0);
```

On iPhone SE: ~13 pt (fits cleanly). On tall devices: clamps back to 18 pt
(identical to previous behavior). No change to tap targets, hit-test
behavior, color semantics, scroll logic, or letter ordering.

### Scope

Single file: `lib/features/contacts/widgets/az_index_column.dart`. The fix
automatically benefits both `ContactsView` and `VenuesView`, which share this
widget. No data-flow, provider, repository, backend, or database changes.

### Verification

- `flutter analyze` → 0 issues
- Simulators booted (iPhone 17e short-height + iPhone 17 Pro Max tall); build
  succeeded. Navigation to Contacts/Venues blocked by PKCE auth (no test
  bypass in project); mathematical analysis confirmed old font exceeded slot
  on SE (reproducing the bug) while adaptive font fits safely on all form
  factors.
- Regression risk: LOW (presentation-only, single widget, no logic change)
