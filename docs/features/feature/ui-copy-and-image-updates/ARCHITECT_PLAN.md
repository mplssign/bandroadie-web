# ARCHITECT PLAN

## Feature: ui-copy-and-image-updates

**Branch:** `feature/ui-copy-and-image-updates`
**Docs path:** `docs/features/feature/ui-copy-and-image-updates/ARCHITECT_PLAN.md`
**Date:** 2026-05-22
**Status:** APPROVED — ready for Engineer

---

## Summary

Two independent, UI-only changes shipped together:

1. **Copy update** — Replace the subtext beneath the Potential toggle in both the Gig and Rehearsal forms with a unified string.
2. **Image update** — The landing page hero image (`phone_hands.png`) has already been updated in-place at `assets/images/phone_hands.png`. The code reference is already correct. **No code change required.** A rebuild and deploy is sufficient.

---

## Part 1 — Copy Update: Potential Toggle Subtext

### Diagnosis

Both the Gig form and the Rehearsal form render a labelled toggle inside a container. Below the toggle title is a single-line subtext string rendered with `AppTextStyles.footnote`.

**Current subtext (Gig):**

> `'Requires member confirmation before gig is official.'`

**Current subtext (Rehearsal):**

> `'Requires member confirmation before rehearsal is official.'`

The two strings are different today. The feature request requires them to be brought into parity with new copy.

**New subtext (both):**

> `'Toggle off once confirmed to make it official.'`

### Files to Modify

| #   | File                                                     | Change                             |
| --- | -------------------------------------------------------- | ---------------------------------- |
| 1   | `lib/features/events/widgets/gig_form_fields.dart`       | Replace subtext string (line ~503) |
| 2   | `lib/features/events/widgets/rehearsal_form_fields.dart` | Replace subtext string (line ~329) |

### Exact String Replacements

**File 1:** `lib/features/events/widgets/gig_form_fields.dart`

```
OLD: 'Requires member confirmation before gig is official.'
NEW: 'Toggle off once confirmed to make it official.'
```

Context (surrounding code, do not modify):

```dart
                    Text(
                      'Potential Gig',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requires member confirmation before gig is official.',  // ← REPLACE THIS LINE
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
```

**File 2:** `lib/features/events/widgets/rehearsal_form_fields.dart`

```
OLD: 'Requires member confirmation before rehearsal is official.'
NEW: 'Toggle off once confirmed to make it official.'
```

Context (surrounding code, do not modify):

```dart
                    Text(
                      'Potential Rehearsal',
                      style: AppTextStyles.callout.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Requires member confirmation before rehearsal is official.',  // ← REPLACE THIS LINE
                      style: AppTextStyles.footnote.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
```

### Scope Constraints

- Do **not** modify toggle behavior, switch value, `onChanged` callback, or any surrounding layout.
- Do **not** modify any other string in either file.
- Do **not** touch any controller, repository, provider, or model.

---

## Part 2 — Image Update: Homepage Hero

### Diagnosis

The landing page hero renders the phone-in-hands image via:

**File:** `lib/features/landing/widgets/hero_section.dart` (line ~232)

```dart
Image.asset(
  'assets/images/phone_hands.png',
  fit: BoxFit.contain,
),
```

**pubspec.yaml** (line 81) declares:

```yaml
- assets/images/
```

The `assets/images/` directory is declared as a Flutter asset bundle glob. Flutter bundles all files in the directory automatically.

**Asset on disk:** `assets/images/phone_hands.png` — confirmed present, last modified 2026-05-22 (new image placed by Tony prior to this session). File size: 685 KB.

### Conclusion: No Code Change Required

The code reference, the pubspec declaration, and the asset path are all already correct and consistent. The new image file is already in place at the expected path.

**What is required to ship this change:**

1. Flutter build must be run (to re-bundle the updated asset into the build output).
2. The web build must be deployed via `./tools/deploy_web.sh`.

The Engineer does **not** need to modify any source file for this part of the feature.

### Additional Context

- The QA report for `bug/potential-rehearsal-dates-not-displaying` confirms `assets/images/phone_hands.png` exists on `main` (the prior release included this file). The new version replaces that file in-place.
- Native platforms (iOS, Android) will also pick up the new image on the next native build — no native-specific change required.

---

## System Impact Assessment

| System              | Impact                                                                    |
| ------------------- | ------------------------------------------------------------------------- |
| Gigs                | **Affected** — subtext string changed in `gig_form_fields.dart`           |
| Rehearsals          | **Affected** — subtext string changed in `rehearsal_form_fields.dart`     |
| Landing page        | **Affected (deploy only)** — new image already in place; rebuild required |
| Setlists / Catalog  | Unaffected                                                                |
| Members / RBAC      | Unaffected                                                                |
| Auth / Session      | Unaffected                                                                |
| Notifications       | Unaffected                                                                |
| Database / Supabase | Unaffected                                                                |
| Routing             | Unaffected                                                                |

---

## Database Impact

**Database: not applicable.** No schema changes. No migrations. No RPC changes. No RLS changes.

---

## Engineer Instructions

### Task 1 — Gig form subtext

- File: `lib/features/events/widgets/gig_form_fields.dart`
- Replace the **single occurrence** of `'Requires member confirmation before gig is official.'` with `'Toggle off once confirmed to make it official.'`
- No other changes to this file.

### Task 2 — Rehearsal form subtext

- File: `lib/features/events/widgets/rehearsal_form_fields.dart`
- Replace the **single occurrence** of `'Requires member confirmation before rehearsal is official.'` with `'Toggle off once confirmed to make it official.'`
- No other changes to this file.

### Task 3 — Image (no code change)

- No source file modification required.
- Document in `ENGINEER_REPORT.md` that the image asset (`assets/images/phone_hands.png`) is already in place and the code reference is correct. The change will be live after `flutter build web --release` and `./tools/deploy_web.sh`.

### Task 4 — Run flutter analyze

- Run `flutter analyze` and confirm 0 errors before completing the report.

---

## QA Checklist

### Copy changes

- [ ] Open the **Add/Edit Gig** form. Enable the Potential Gig toggle. Confirm the subtext reads exactly: `Toggle off once confirmed to make it official.`
- [ ] Open the **Add/Edit Rehearsal** form. Enable the Potential Rehearsal toggle. Confirm the subtext reads exactly: `Toggle off once confirmed to make it official.`
- [ ] Confirm the toggle behavior (on/off, member grid appearance/disappearance) is unchanged.
- [ ] Confirm no other copy in either form has been altered.

### Image change

- [ ] Load `bandroadie.com` (or the deployed web build) in a browser.
- [ ] Confirm the hero section displays the updated `phone_hands.png` image.
- [ ] Confirm there are no broken image errors in the browser console.

### Flutter analyze

- [ ] `flutter analyze` returns 0 errors.

---

## Files Modified (Complete List)

| File                                                     | Change type                                            |
| -------------------------------------------------------- | ------------------------------------------------------ |
| `lib/features/events/widgets/gig_form_fields.dart`       | String literal replacement                             |
| `lib/features/events/widgets/rehearsal_form_fields.dart` | String literal replacement                             |
| `assets/images/phone_hands.png`                          | Asset replaced in-place (no code change — deploy only) |
