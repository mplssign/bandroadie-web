## Summary

- Refreshes BandRoadie agent and project guidance to match the current Forui, theme, authentication, and database conventions.
- Removes outdated emoji examples and cleans related reference documentation.
- Removes obsolete text from the App Store screenshot tooling.
- Widens confirmed gig cards and truncates long gig titles cleanly.

## Verification

- QA verdict: APPROVED.
- `flutter analyze lib/features/home/widgets/confirmed_gig_card.dart` passed.
- `node --check BandRoadie/src/app_store_screenshots/generate_slides.js` passed.
- `git diff --check` passed.
- Chrome smoke reached Home and confirmed the widened cards render without overflow with title, location, date, and time rows visible.
- The title one-line ellipsis behavior was verified by code inspection under the revised verification plan.
- The focused auth test has a documented pre-existing failure on `origin/main`.

## Scope

No database migrations, RLS, RPC, dependency, or runtime configuration changes are included. Three unrelated untracked migration files remain local and were intentionally excluded.
