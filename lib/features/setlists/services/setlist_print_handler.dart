import 'package:flutter/foundation.dart';

import '../models/print_template.dart';
import '../models/setlist_item.dart';
import 'setlist_print_service.dart';
// PLATFORM GUARD: Default to stub for native platforms (iOS/Android/macOS).
// Only load web implementation when dart.library.js_interop is available.
// This prevents dart:js_interop and package:web from being compiled for native.
import 'setlist_print_stub.dart'
    if (dart.library.js_interop) 'setlist_print_web.dart';

// ============================================================================
// SETLIST PRINT HANDLER
// Platform-aware print dispatcher for setlists.
//
// Automatically routes to the correct print implementation:
// - Web: Opens HTML in new window with window.print()
// - Native: Uses PDF generation with platform print dialog
// ============================================================================

class SetlistPrintHandler {
  SetlistPrintHandler._();

  /// Print the setlist using platform-appropriate method.
  ///
  /// On web: Opens print-optimized HTML in new window
  /// On native: Generates PDF and opens system print dialog
  static Future<void> print({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) async {
    if (kIsWeb) {
      // Web platform: use HTML + window.print()
      SetlistPrintWeb.printSetlist(
        setlistName: setlistName,
        items: items,
        template: template,
        bandName: bandName,
        gigDate: gigDate,
        venue: venue,
      );
    } else {
      // Native platforms: use PDF generation
      await SetlistPrintService.printSetlist(
        setlistName: setlistName,
        items: items,
        template: template,
        bandName: bandName,
        gigDate: gigDate,
        venue: venue,
      );
    }
  }
}
