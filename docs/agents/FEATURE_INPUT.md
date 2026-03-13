# Feature Input Template — BandRoadie

This is the structured input the Manager produces before spawning the Architect.
Complete all required fields. Leave optional fields blank if unknown — do not invent.

---

## Feature Identifier (REQUIRED)

Format: `feature/<slug>` or `bug/<slug>`

Rules:
- lowercase, hyphen-separated
- max 40 characters after the type prefix
- descriptive and specific (no vague slugs like `fix`, `update`, `improve`)
- no trailing or double hyphens

Examples:
```
feature/rehearsal-delete-fix
feature/setlist-print-export
bug/band-switch-stale-state
```

**Feature Identifier:**

---

## Type (REQUIRED)

`feature` or `bug`

**Type:**

---

## Title (REQUIRED)

Short, plain-language title.

Example: `Rehearsal deletion silently fails on Android`

**Title:**

---

## Summary (REQUIRED)

Describe clearly:
- What the user is trying to do
- What currently happens (for bugs) or what currently does not exist (for features)
- Why the change is needed
- Any known constraints

Do not propose solutions here.

**Summary:**

---

## Reproduction Steps (BUGS ONLY)

Exact steps to reproduce. Number each step.

Example:
```
1. Open a rehearsal
2. Tap Delete
3. Confirm deletion dialog
4. Observe: nothing happens, no error shown
```

**Steps:**

---

## Expected Behavior (REQUIRED)

What should happen when the system is working correctly.

**Expected:**

---

## Actual Behavior (BUGS ONLY)

What currently happens instead.

**Actual:**

---

## Affected Platforms

Check all that apply: `Web` / `iOS` / `Android` / `macOS`

**Platforms:**

---

## Additional Context (OPTIONAL)

Any of the following that are relevant:
- Related features or recent changes
- Error messages or logs
- Screenshots or recordings
- Similar flows that do or don't work
- Known workarounds

**Context:**

---

*Return only this completed document. Do not include analysis or solutions.*
