import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/print_template.dart';
import '../models/setlist_item.dart';
import 'setlist_print_service.dart';

// ============================================================================
// SETLIST PRINT SERVICE - WEB IMPLEMENTATION
// Platform-specific print implementation for web using window.print().
// ============================================================================

class SetlistPrintWeb {
  SetlistPrintWeb._();

  /// Print the setlist using browser's native print dialog.
  static void printSetlist({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) {
    // Generate the print-ready HTML using shared service
    final htmlContent = SetlistPrintService.generatePrintHtml(
      setlistName: setlistName,
      items: items,
      template: template,
      bandName: bandName,
      gigDate: gigDate,
      venue: venue,
    );

    // Open a new window for printing
    final printWindow = web.window.open(
      '',
      '_blank',
      'width=850,height=1100,scrollbars=yes,resizable=yes,toolbar=no,menubar=no',
    );

    if (printWindow != null) {
      printWindow.document.write(htmlContent.toJS);
      printWindow.document.close();

      // Trigger print after a short delay to ensure content loads
      Future.delayed(const Duration(milliseconds: 500), () {
        printWindow.print();
      });
    }
  }
}
