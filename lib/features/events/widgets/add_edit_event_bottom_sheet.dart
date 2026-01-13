import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/utils/snackbar_helper.dart';
import '../../bands/active_band_controller.dart';
import '../models/event_form_data.dart';
import 'event_editor_drawer.dart';

// ============================================================================
// ADD/EDIT EVENT BOTTOM SHEET
// Thin wrapper around EventEditorDrawer for backward compatibility.
// All existing triggers continue to work unchanged.
//
// USAGE:
//   AddEditEventBottomSheet.show(
//     context,
//     ref: ref,
//     initialType: EventType.rehearsal,
//     initialDate: DateTime.now(),
//     onSaved: () => refreshCalendar(),
//   );
// ============================================================================

/// Mode for the bottom sheet (create or edit)
/// Kept for backward compatibility - maps to EventEditorMode internally.
enum EventFormMode { create, edit }

/// Thin wrapper class that delegates to EventEditorDrawer.
/// Maintains the same static API for all existing callers.
class AddEditEventBottomSheet {
  /// Private constructor - use static show() method
  AddEditEventBottomSheet._();

  /// Show the bottom sheet modally.
  ///
  /// All parameters maintain backward compatibility with existing callers.
  static Future<bool?> show(
    BuildContext context, {
    required WidgetRef ref,
    EventFormMode mode = EventFormMode.create,
    required EventType initialType,
    DateTime? initialDate,
    String? existingEventId,
    EventFormData? initialData,
    VoidCallback? onSaved,
  }) {
    // Check band context before showing
    final bandId = ref.read(activeBandIdProvider);
    if (bandId == null || bandId.isEmpty) {
      showErrorSnackBar(context, message: 'Please select a band first');
      return Future.value(false);
    }

    // Map old mode enum to new one
    final editorMode = mode == EventFormMode.edit
        ? EventEditorMode.edit
        : EventEditorMode.create;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EventEditorDrawer(
        mode: editorMode,
        initialEventType: initialType,
        initialDate: initialDate,
        existingEventId: existingEventId,
        existingEvent: initialData,
        bandId: bandId,
        onSaved: onSaved,
      ),
    );
  }
}
