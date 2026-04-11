# Feature Input — BandRoadie

## Feature Identifier (REQUIRED)

`feature/privacy-policy-content-updates`

---

## Type (REQUIRED)

`feature`

---

## Title (REQUIRED)

Privacy Policy Content Updates — Data Ownership, Licensing, Backup Marketing, and Lyrics Disclaimer

---

## Summary (REQUIRED)

**What the user is trying to do:**

Four targeted content additions to the existing `web/privacy.html` privacy policy page. No structural or layout changes. Text additions only, inserted into appropriate existing sections or as new sections where no applicable section exists.

**1. Data ownership statement**
Add an explicit sentence affirming that users retain full ownership of the content they create in BandRoadie:

> *"You retain full ownership of all content you create in BandRoadie, including band names, setlists, songs, and event data."*

**2. BandRoadie's limited license to user content**
Clarify the scope of BandRoadie's right to use stored data — storage and service delivery only, no broader rights:

> *"You grant BandRoadie a limited license to store and process your content solely to provide the app's services."*

**3. Data portability / backup marketing statement**
Surface the existing export/backup feature within the privacy policy to reassure users their data is portable. This should appear alongside or near the data ownership and retention sections:

> *"Your data is always yours — you can export a complete backup of your band's data at any time from within the app."*

**4. Lyrics and copyrighted content disclaimer**
BandRoadie allows users to enter song lyrics manually into songs in their catalog. BandRoadie does not provide, source, or display lyrics — users enter and manage their own. A disclaimer is needed to clarify user responsibility:

> *"BandRoadie allows users to store song lyrics and other content within the app. BandRoadie does not provide or supply lyrics. Users are solely responsible for ensuring that any lyrics or other copyrighted material they store comply with applicable copyright law. If you believe content stored on BandRoadie infringes your intellectual property rights, please contact us at hello@bandroadie.com."*

**Why the change is needed:**
The current policy is silent on data ownership, licensing, portability, and copyright. These are standard clauses expected in consumer app privacy policies and Terms of Service. Addressing them proactively reduces legal exposure and builds user trust.

**Known constraints:**
- Changes are to `web/privacy.html` only — no Flutter source code changes
- The HTML structure, dark theme styling, and visual design must not change
- The existing effective date line should be updated to reflect the revision
- Text additions must match the existing typographic style (font sizes, colors, spacing defined in the inline `<style>` block)
- Each addition should be placed in the most contextually appropriate existing section, or a new section added only if no existing section fits

---

## Reproduction Steps

*(Not applicable — content update, not a bug)*

---

## Expected Behavior (REQUIRED)

- `web/privacy.html` contains all four new content additions
- Data ownership and license statements appear in or near the existing "How We Use Information" or "Your Choices" section — whichever is the better contextual fit per Architect's assessment
- The backup/portability statement appears near the "Data Retention" or "Your Choices" section
- The lyrics/copyright disclaimer appears as a new "User Content and Copyright" section
- The effective date is updated (e.g. from "January 2026" to "April 2026")
- The page renders correctly with no visual regressions — existing layout, logo, styling, and footer link are preserved
- The Flutter `PrivacyPolicyScreen` (which renders the same content via a WebView or embedded HTML) should be verified to render the updated content correctly

---

## Affected Platforms

`Web` (primary — `web/privacy.html`)
`iOS` / `Android` / `macOS` (verify in-app privacy screen renders correctly)

---

## Additional Context (OPTIONAL)

- File to modify: `web/privacy.html`
- The in-app privacy policy screen: `lib/features/profile/` or settings — Architect should locate and verify the Flutter screen that displays this content renders the updated page
- The page uses inline CSS only (no external stylesheet) — all new text must use existing CSS classes or inline styles consistent with the existing design
- Reference the existing policy sections: Information We Collect, How We Use Information, Data Sharing, Data Retention, Data Security, Children's Privacy, Your Choices, Account and Data Deletion, Changes to This Policy, Contact
- No Terms of Service document exists — this update is scoped to the Privacy Policy only
- Effective date change: update from "January 2026" to "April 2026"
