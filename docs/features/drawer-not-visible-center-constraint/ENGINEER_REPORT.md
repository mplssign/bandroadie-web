Feature: drawer-not-visible-center-constraint
Cycle: 1
Summary: Removed Center > ConstrainedBox(maxWidth: 680) wrapper from EventEditorDrawer.build() so the DecoratedBox is a direct child of FTheme. This lets ShiftedSheet correctly measure and position the drawer.
Files Modified: lib/features/events/widgets/event_editor_drawer.dart
flutter analyze: 0 errors
Ready For QA: Yes
