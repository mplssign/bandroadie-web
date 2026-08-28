# QA Report — Song Enrichment Confidence Display

Feature slug: `feature/song-enrichment-confidence-display`

## Scope

This QA pass targeted the live Flutter app in Chrome and the implementation in:

- [lib/features/songs/song_enrichment_service.dart](../../../lib/features/songs/song_enrichment_service.dart)
- [lib/features/songs/services/song_enrichment_orchestrator.dart](../../../lib/features/songs/services/song_enrichment_orchestrator.dart)
- [lib/features/songs/widgets/enrichment_results_overlay.dart](../../../lib/features/songs/widgets/enrichment_results_overlay.dart)

The app session reached the live Catalog detail screen, but the live tap/keyboard activation path in this QA session did not open the enrichment sheet or results overlay, so the numbered live behavior checks below are reported strictly as blocked rather than inferred.

## Checks

1. FAIL / BLOCKED - Could not complete a live enrichment of a song with BPM and/or Key match because the Enrich action in the live Chrome session did not open the enrichment flow during this QA run.
2. FAIL / BLOCKED - Could not reach the no-match `confidence: 'none'` path in the live app, so the `Not found` badge/no `%` case was not observed.
3. FAIL / BLOCKED - Could not reach the unchanged/no-overwrite live path, so the `Unchanged` badge/no `%` case was not observed.
4. FAIL / BLOCKED - Highest-risk error-path case was not reached in the live app, so I could not reproduce the lookup-success / RPC-write-fails scenario in-session. Static code evidence shows the suffix is gated on `updated` only at [enrichment_results_overlay.dart](../../../lib/features/songs/widgets/enrichment_results_overlay.dart#L300-L303), which prevents a `%` on `Error`, but I did not capture live screenshot/log evidence for this check because the enrichment sheet never opened.
5. FAIL / BLOCKED - Could not verify mixed-field behavior in the live app because the enrichment flow itself was not reachable.
6. FAIL / BLOCKED - Could not verify that badge text/icon logic is unchanged in the live app because the results overlay never rendered.
7. FAIL / BLOCKED - Could not verify that Duration never shows a `%` in the live app because the overlay was not reached.
8. FAIL / BLOCKED - Could not run a live batch enrichment and observe progress/summary counts in this QA session.
9. FAIL / BLOCKED - Could not open the single-song review sheet from the live app, so save/cancel behavior was not exercised.
10. PASS - `flutter analyze` completed with 0 errors.

## Analyzer Output

Command: `flutter analyze`

Result: 0 errors, 8 warnings.

Warnings present were pre-existing baseline issues outside this feature patch:

- `lib/features/setlists/widgets/reorderable_song_card.dart:187:18` - `sized_box_for_whitespace`
- `lib/features/setlists/widgets/song_card.dart:113:18` - `sized_box_for_whitespace`
- `lib/main.dart:62:7` - deprecated `anonKey`
- `lib/main.dart:88:7` - deprecated `anonKey`
- `test/components/ui/app_text_field_test.dart:312:15` - unused local variable
- `test/components/ui/app_text_field_test.dart:416:12` - unused local variable
- `test/components/ui/app_text_field_test.dart:438:12` - unused local variable
- `test/components/ui/app_text_form_field_test.dart:326:15` - unused local variable

## Implementation Evidence

- Confidence fields are parsed from the live lookup response in [song_enrichment_service.dart](../../../lib/features/songs/song_enrichment_service.dart#L104-L109).
- Confidence values are threaded through the orchestrator into each detail object in [song_enrichment_orchestrator.dart](../../../lib/features/songs/services/song_enrichment_orchestrator.dart#L201-L218) and [song_enrichment_orchestrator.dart](../../../lib/features/songs/services/song_enrichment_orchestrator.dart#L308-L318).
- The overlay only appends `NN%` when the field result is `updated` and the confidence value is non-null in [enrichment_results_overlay.dart](../../../lib/features/songs/widgets/enrichment_results_overlay.dart#L293-L303).

## Live Session Notes

- The live Chrome session reached the Catalog detail screen and showed the expected toolbar actions (`Add`, `Sort`, `Enrich`) and song rows, but the Enrich activation did not open the enrichment sheet during this QA run.
- Because the enrichment sheet never opened, no live screenshot or log excerpt exists for checks 1 through 9 in this report.
