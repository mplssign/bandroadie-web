# ARCHITECT_PLAN.md

## Feature Slug

adaptive-toolbar-shared-default

## Context

This is a retroactive plan for already-implemented commit `1b7f29a` on branch `fix/adaptive-toolbar-shared-default`.

## Problem

The Cupertino localizations crash mitigation for text-selection context menus existed as duplicated private helpers at select call sites, so coverage depended on developers remembering to patch each field manually.

## Scope

Validate and merge the existing implementation without re-implementing it.

Files in scope:

- `lib/components/ui/adaptive_text_selection_toolbar.dart` (new)
- `lib/components/ui/app_text_field.dart`
- `lib/components/ui/app_text_form_field.dart`
- `lib/features/events/widgets/gig_form_fields.dart`

## Implemented Solution (Expected)

- Extract shared top-level helper `buildLocalizedAdaptiveTextSelectionToolbar`.
- Default `AppTextField` and `AppTextFormField` `contextMenuBuilder` to shared helper.
- Keep override capability via optional `contextMenuBuilder` parameter.
- Replace gig form private helper usage with shared helper.

## Acceptance Criteria

1. Commit scope is exactly the four files above.
2. Wrapper defaults apply shared toolbar localization helper app-wide for wrapper-backed fields.
3. Existing override behavior remains supported.
4. Gig form compiles and uses shared helper.
5. QA must include runtime validation of long-press/select/copy/paste/context menu behavior on the Gig form screen (not static-only validation).

## Out of Scope

- Additional refactors or behavioral changes outside commit `1b7f29a`.
- New feature work unrelated to toolbar localization defaults.
