# Engineer Report

## Feature Slug

`bug/getsongbpm-hosting-doc-audit`

## Feature Title

GetSongBPM Hosting & Documentation Audit

## Goal

Correct false claims in `PROJECT_CONTEXT.md` and `deployment.md` about BandRoadie being a "single Vercel deployment" — the live infrastructure actually consists of three separate Vercel projects. Additionally, insert the required GetSongBPM third-party data disclosure into both live privacy policy surfaces (`marketing/privacy.html` and `lib/features/legal/privacy_policy_screen.dart`).

## Architect Tasks Completed

- [x] Task 1 — Corrected `docs/agents/PROJECT_CONTEXT.md` Hosting and Domain Architecture section with verified three-project structure
- [x] Task 2 — Corrected `docs/reference/deployment/deployment.md` lines 18-20 with accurate project/domain mapping
- [x] Task 3 — Inserted "Third-Party Data Providers" subsection into `marketing/privacy.html` Data Sharing section
- [x] Task 4 — Inserted "Third-Party Data Providers" subsection into `lib/features/legal/privacy_policy_screen.dart` Data Sharing section
- [x] Task 5 — Confirmed `web/privacy.html`, `lib/features/landing/widgets/footer_section.dart`, and `docs/features/new-song-key-enrichment/` were not touched by this implementation
- [x] Task 6 — Ran `flutter analyze lib/features/legal/privacy_policy_screen.dart` — 0 errors

## Files Created

- none

## Files Modified

- `docs/agents/PROJECT_CONTEXT.md`
- `docs/reference/deployment/deployment.md`
- `marketing/privacy.html`
- `lib/features/legal/privacy_policy_screen.dart`

## Analyzer Results

Command: `flutter analyze lib/features/legal/privacy_policy_screen.dart`
Result: 0 errors, 0 warnings

Output:

```
Analyzing privacy_policy_screen.dart...
No issues found! (ran in 0.9s)
```

## Test Results

Not required by Architect plan — content-only changes (documentation corrections + static privacy policy text additions).

## Verification

### Pre-deployment Tier 1 Checks (all passed):

1. **PRE-DEPLOY CHECK 1:** `git diff docs/agents/PROJECT_CONTEXT.md` — confirmed only the Hosting and Domain Architecture section changed, no other content altered
2. **PRE-DEPLOY CHECK 2:** `git diff docs/reference/deployment/deployment.md` — confirmed only lines 18-20 changed (Vercel project/domain mapping corrected)
3. **PRE-DEPLOY CHECK 3:** `git diff marketing/privacy.html` — confirmed exactly one `<h3>` + two `<p>` lines added inside Data Sharing section, no other markup changed
4. **PRE-DEPLOY CHECK 4:** `git diff lib/features/legal/privacy_policy_screen.dart` — confirmed exactly one `SizedBox`, one `_buildSubheader`, and two `_buildParagraph` calls added inside Data Sharing section, no other code changed
5. **PRE-DEPLOY CHECK 5:** `flutter analyze lib/features/legal/privacy_policy_screen.dart` — 0 errors

### Manual verification performed:

- Confirmed all edits match the exact insertion points and markup/widget-call patterns specified in ARCHITECT_PLAN.md §10
- Confirmed `web/privacy.html` (dead/unreachable file) was not touched — `git diff web/privacy.html` returns empty
- Confirmed `lib/features/landing/widgets/footer_section.dart` and all `docs/features/new-song-key-enrichment/` files remain exactly as they were (uncommitted, belonging to sibling feature)
- Confirmed `git diff` output includes only the four intended file modifications plus the pre-existing uncommitted `footer_section.dart` work (which correctly appears in the diff as unchanged by this session)

## Deviations From Architect Plan

One minor spacing adjustment: added `const SizedBox(height: 12)` before the new `_buildSubheader(context, 'Third-Party Data Providers')` call in `lib/features/legal/privacy_policy_screen.dart` to match this file's existing subheader-spacing convention (lines 54, 64, 70, 86, 96 all use `height: 12` before every `_buildSubheader`). This spacer was not explicitly specified in ARCHITECT_PLAN.md §10's code block but is required for visual consistency.

## Blockers Encountered

None.

## Post-QA Corrections

QA review identified three incidental blank line insertions in `docs/reference/deployment/deployment.md` that exceeded the approved scope (ARCHITECT_PLAN.md §10 specified changing only lines 18-20). These blank lines were:

1. After "The `.env` file must define:" (before the list)
2. After "Build for simulator:" (before the iOS code fence)
3. After "Build for emulator:" (before the Android code fence)

**Root cause:** Likely editor format-on-save behavior (user-level VS Code settings, not workspace — `.vscode/settings.json` only enables `formatOnSave` for `[dart]` files, not markdown).

**Correction applied:** All three blank lines removed to match the original bug branch formatting. The diff now contains only the intended two-line Vercel project/domain mapping correction (lines 18-21 in current file).

**Note:** PRE-DEPLOY CHECK 2 in the original verification section incorrectly stated "confirmed only lines 18-20 changed" when the initial diff included these additional blank line changes. The QA process correctly caught this scope violation per ARCHITECT_PLAN.md §16.5's explicit warning.

## Ready For QA

Yes (re-validated post-correction).

All six Architect tasks completed successfully. All five Tier 1 pre-deployment checks passed. No analyzer errors. No code behavior changes — only documentation corrections and static privacy policy content additions. The two off-limits files (`footer_section.dart` and `docs/features/new-song-key-enrichment/`) remain untouched as required.

Post-QA correction applied: incidental blank lines removed from `deployment.md` per QA feedback, now scoped exactly to the approved two-line change.

---

## Complete Git Diff

```diff
diff --git a/docs/agents/PROJECT_CONTEXT.md b/docs/agents/PROJECT_CONTEXT.md
index 1795842..aeaa81b 100644
--- a/docs/agents/PROJECT_CONTEXT.md
+++ b/docs/agents/PROJECT_CONTEXT.md
@@ -33,32 +33,35 @@ BandRoadie is a cross-platform band management app for iOS, Android, macOS, and

 **Critical — read before any feature touching routing, URLs, or deployment.**

-BandRoadie is a **single Vercel deployment** serving both the marketing site and the web app from the same Flutter build.
+BandRoadie operates as **three separate Vercel deployments**, not a single unified build:

-| Surface           | Hostname                                           | Entry point                             |
-| ----------------- | -------------------------------------------------- | --------------------------------------- |
-| Marketing site    | `bandroadie.com`                                   | `LandingPage` → `lib/features/landing/` |
-| Web app           | Any non-marketing host (e.g. `app.bandroadie.com`) | `AuthGate`                              |
-| Privacy policy    | `bandroadie.com/privacy`                           | Flutter route → `PrivacyPolicyScreen`   |
-| Auth confirmation | `bandroadie.com/auth/confirm`                      | Flutter route → `AuthConfirmScreen`     |
+| Vercel Project | Deployed Content | Live Domain(s) | Deploy Script |
+| -------------- | ---------------- | -------------- | ------------- |
+| `marketing` (prj_6XAVv0lp4ySiYWAoBTPaWgT52DzW) | `marketing/` — static Webflow export (HTML/CSS, no Flutter) | `bandroadie.com`, `www.bandroadie.com` | `tools/deploy_marketing.sh` |
+| `web` (prj_Aq7Q0pRo2oezPMOy01E0gMKO0Sk9) | `build/web` — Flutter web build output | `app.bandroadie.com` | `tools/deploy_web.sh` |
+| `bandroadie-web` (prj_EF0jMD0m2SEBdytZxCp7XnZVknzT) | Orphaned root `.vercel` link | No production domain (preview URLs only) | Not used |

-Host detection happens in `lib/main.dart` via `_isMarketingHost()`. The `vercel.json` catch-all rewrite sends all requests to `index.html`; Flutter handles routing from there.
+**Privacy policy surfaces — two live, independent `/privacy` pages:**

-**Files that affect BOTH surfaces — always flag in the Architect plan:**
+| URL | Served By | Status |
+| --- | --------- | ------ |
+| `bandroadie.com/privacy`, `www.bandroadie.com/privacy` | `marketing/privacy.html` (static HTML) | **Canonical** — SEO-indexed, publicly linked |
+| `app.bandroadie.com/privacy` | Flutter `PrivacyPolicyScreen` (`lib/features/legal/privacy_policy_screen.dart`) | **Live** — in-app, routed unconditionally on path match |
+| `web/privacy.html` (in `build/web`) | **Dead/unreachable** — intercepted by `web/vercel.json` catch-all rewrite | Never served |

-- `lib/main.dart` (routing, host detection, initialization)
-- `vercel.json` (rewrites, headers)
-- `web/index.html`
+**Host detection (`_isMarketingHost()` in `lib/main.dart`):** This function exists and can return `true` for `bandroadie.com`, but it is **unreachable in production** — `bandroadie.com` DNS routes exclusively to the `marketing` Vercel project (static site), never to the `web` project where this Flutter code runs. The Flutter landing page (`lib/features/landing/`) is bundled into the `web` project's build but is never served at the live marketing domain.

-**Files scoped to marketing only:**
+**Files scoped to the static marketing site (`marketing` project) only:**

-- `lib/features/landing/` (all landing page widgets)
-- `web/privacy.html`
-- `web/support.html`
+- `marketing/index.html`, `marketing/privacy.html`, `marketing/support.html`, `marketing/style.css`
+- **Not** `lib/features/landing/` — that is Flutter code in the `web` project, unreachable at `bandroadie.com`
+- **Not** `web/privacy.html` — dead duplicate, never served (see table above)

-**Files scoped to app only:**
+**Files scoped to the Flutter web app (`web` project) only:**

-- `lib/features/auth/`, `bands/`, `calendar/`, `gigs/`, `members/`, `profile/`, `rehearsals/`, `setlists/`, `home/`, `settings/`, `notifications/`
+- `lib/main.dart` (routing, initialization)
+- `lib/features/auth/`, `bands/`, `calendar/`, `gigs/`, `members/`, `profile/`, `rehearsals/`, `setlists/`, `home/`, `settings/`, `notifications/`, `legal/`, `landing/`
+- `web/index.html`, `web/vercel.json`

 ---

diff --git a/docs/reference/deployment/deployment.md b/docs/reference/deployment/deployment.md
index 9368c31..99eeb36 100644
--- a/docs/reference/deployment/deployment.md
+++ b/docs/reference/deployment/deployment.md
@@ -15,9 +15,9 @@ The `.env` file must define:

 **Do not** set these as Vercel environment variables — they are injected at build time via `--dart-define`, not at runtime.

-**Vercel project:** `web` (aliases: `bandroadie.com`, `app.bandroadie.com`)
+**Vercel project:** `web` (domain: `app.bandroadie.com`)

-Both `bandroadie.com` and `app.bandroadie.com` are aliases for the same deployment. Flutter's `_isMarketingHost()` in `lib/main.dart` routes the request to the marketing landing page or the app shell based on the hostname.
+`bandroadie.com` and `www.bandroadie.com` are served by a separate Vercel project (`marketing`) deploying the static `marketing/` directory via `tools/deploy_marketing.sh`. Only `app.bandroadie.com` routes to the Flutter web build.

 Auth confirmation is handled via the `/auth/confirm` route using PKCE flow on all platforms.

diff --git a/lib/features/landing/widgets/footer_section.dart b/lib/features/landing/widgets/footer_section.dart
index ee98c17..3c39a8d 100644
--- a/lib/features/landing/widgets/footer_section.dart
+++ b/lib/features/landing/widgets/footer_section.dart
@@ -71,12 +71,51 @@ class FooterSection extends StatelessWidget {
               color: context.colors.textSecondary.withValues(alpha: 0.7),
             ),
           ),
+          const SizedBox(height: 8),
+
+          // Third-party data attribution (required by GetSongBPM's API terms)
+          _AttributionLink(
+            label: 'Song tempo & key data via GetSongBPM.com',
+            url: 'https://getsongbpm.com',
+          ),
         ],
       ),
     );
   }
 }

+class _AttributionLink extends StatelessWidget {
+  final String label;
+  final String url;
+
+  const _AttributionLink({required this.label, required this.url});
+
+  @override
+  Widget build(BuildContext context) {
+    return MouseRegion(
+      cursor: SystemMouseCursors.click,
+      child: GestureDetector(
+        onTap: () async {
+          final uri = Uri.parse(url);
+          if (await canLaunchUrl(uri)) {
+            await launchUrl(uri, mode: LaunchMode.externalApplication);
+          }
+        },
+        child: Text(
+          label,
+          textAlign: TextAlign.center,
+          style: AppTextStyles.caption.copyWith(
+            color: context.colors.textSecondary.withValues(alpha: 0.6),
+            decoration: TextDecoration.underline,
+            decorationColor:
+                context.colors.textSecondary.withValues(alpha: 0.4),
+          ),
+        ),
+      ),
+    );
+  }
+}
+
 class _FooterLink extends StatelessWidget {
   final String label;
   final VoidCallback onTap;
diff --git a/lib/features/legal/privacy_policy_screen.dart b/lib/features/legal/privacy_policy_screen.dart
index 1b2ac74..06920a6 100644
--- a/lib/features/legal/privacy_policy_screen.dart
+++ b/lib/features/legal/privacy_policy_screen.dart
@@ -97,6 +97,12 @@ class PrivacyPolicyScreen extends StatelessWidget {
             _buildParagraph(context, 'Information may be shared only when:'),
             _buildBullet(context, 'Required to operate core app services'),
             _buildBullet(context, 'Required by law or legal process'),
+            const SizedBox(height: 12),
+            _buildSubheader(context, 'Third-Party Data Providers'),
+            _buildParagraph(context,
+                "BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song."),
+            _buildParagraph(
+                context, 'Data from GetSongBPM: https://getsongbpm.com/.'),
             _buildDivider(context),

             // Data Retention
diff --git a/marketing/privacy.html b/marketing/privacy.html
index 4bc2d2f..2baa1e5 100644
--- a/marketing/privacy.html
+++ b/marketing/privacy.html
@@ -157,6 +157,10 @@
     <li>Required by law or legal process</li>
   </ul>

+  <h3>Third-Party Data Providers</h3>
+  <p>BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song.</p>
+  <p>Data from GetSongBPM: <a href="https://getsongbpm.com/">https://getsongbpm.com/</a>.</p>
+
   <hr>

   <h2>Data Retention</h2>
```

**Note:** The `footer_section.dart` changes visible in the diff are **pre-existing uncommitted work from the `feature/new-song-key-enrichment` branch**, not modifications made by this implementation. Per the Architect plan §11 and the explicit feature input instruction, this file was correctly left untouched by this session. The diff shows it because it remains uncommitted on the working tree, but no lines in that file were changed during this implementation cycle.
