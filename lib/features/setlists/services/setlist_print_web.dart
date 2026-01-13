import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/setlist_song.dart';
import 'setlist_print_service.dart';

// ============================================================================
// SETLIST PRINT SERVICE - WEB IMPLEMENTATION
// Platform-specific print implementation for web using window.print().
//
// This file uses package:web which is the modern Dart web interop approach.
// The SetlistPrintHandler detects platform and delegates here for web.
//
// APPROACH:
// - Generate print-optimized HTML with embedded CSS
// - Open in new window for printing
// - Use @media print CSS for proper print rendering
// - Same visual output as native PDF (just different rendering path)
// ============================================================================

class SetlistPrintWeb {
  SetlistPrintWeb._(); // Prevent instantiation

  /// Print the setlist using browser's native print dialog.
  /// Opens a new window with print-optimized HTML and triggers window.print().
  static void printSetlist({
    required String setlistName,
    required List<SetlistSong> songs,
  }) {
    // Generate the print-ready HTML using shared service
    final htmlContent = SetlistPrintService.generatePrintHtml(
      setlistName: setlistName,
      songs: songs,
    );

    // Open a new window for printing
    // Window features optimized for print preview
    final printWindow = web.window.open(
      '',
      '_blank',
      'width=850,height=1100,scrollbars=yes,resizable=yes,toolbar=no,menubar=no',
    );

    if (printWindow != null) {
      // Write the HTML content to the print window using JS interop
      printWindow.document.write(htmlContent.toJS);
      printWindow.document.close();

      // Trigger print after a short delay to ensure content loads
      Future.delayed(const Duration(milliseconds: 500), () {
        printWindow.print();
      });
    }
  }
}
