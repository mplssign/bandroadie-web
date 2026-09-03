Feature: event-type-selector-layout-builder-recursion
Cycle: 1
Summary: Replaced LayoutBuilder + Container(width: segmentWidth) with Stack(fit: expand) + FractionallySizedBox(widthFactor: 1/N). Eliminates the layout-phase callback that triggered markNeedsLayout on the header Column.
Files Modified: lib/features/events/widgets/event_type_selector.dart
flutter analyze: 0 errors
Ready For QA: Yes
