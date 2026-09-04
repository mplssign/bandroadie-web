## Summary

Brings the **Potential Gig** toggle into full parity with the already-shipped **Potential Rehearsal** toggle. The descriptive subtext ("Toggle off once confirmed to make it official.") is now hidden until the toggle is switched **on**, matching the rehearsal-side behavior from `potential-rehearsal-subtext-when-enabled`.

The toggle-position half of the original ask (switch to the left of the label) was already shipped for the gig side via `potential-toggle-left-of-label`, so this change closes the one remaining gap: the subtext gating.

## Change

In `lib/features/events/widgets/gig_form_fields.dart`, inside `_buildPotentialGigContainer`, the existing `SizedBox(height: 2)` + subtext `Text(...)` are wrapped in an `if (isPotentialGig) ...[ ... ]` collection-if so they only render when the toggle is enabled. This is a byte-for-byte mirror of the rehearsal-side pattern.

```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text('Potential Gig', style: ...),
    if (isPotentialGig) ...[
      const SizedBox(height: 2),
      Text('Toggle off once confirmed to make it official.', style: ...),
    ],
  ],
),
```

- Net change: **+2 / −0** structural lines, one file.
- No new widget, no shared extraction, no state/prop/callback changes.
- No database, RLS, RPC, or migration impact.
- Reference implementation (`rehearsal_form_fields.dart`) intentionally untouched.

## Verification

- `flutter analyze` — 0 issues.
- `flutter test test/features/events/widgets/rehearsal_form_fields_test.dart` — 3/3 pass (protects the shared collection-if pattern).
- QA: **APPROVED**, LOW regression risk, no Critical or Warning findings.

Runtime visual verification (macOS + web) — confirm the subtext is hidden when the Potential Gig toggle is off and appears when it is on, matching the Potential Rehearsal toggle — is recommended by the PR author before/after merge as usual for a UI-only change.
