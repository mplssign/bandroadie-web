Feature: drawer-no-size-unresponsive
Cycle: 1
Summary: Changed mainAxisSize from min to max on the root Column in EventEditorDrawer.build() so Flexible gets finite height. Because MainAxisSize.max is the default, the argument was removed entirely to satisfy the avoid_redundant_argument_values lint.
Files Modified: lib/features/events/widgets/event_editor_drawer.dart
flutter analyze: 0 errors
Ready For QA: Yes
