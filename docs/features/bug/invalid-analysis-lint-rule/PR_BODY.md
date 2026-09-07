## Summary

Remove the invalid `unnecessary_non_null_assertion` lint entry from the Dart analyzer configuration. The valid `unnecessary_null_checks` rule remains enabled.

## Verification

- `flutter analyze --no-pub analysis_options.yaml` passes with no issues.
- The full analyzer no longer reports the invalid lint diagnostic; its remaining 561 info-level findings are pre-existing.
- QA independently confirmed the diff is exactly one deleted line and found no scope or regression issues.

## Scope

- No application code, tests, dependencies, database migrations, or runtime behavior changed.