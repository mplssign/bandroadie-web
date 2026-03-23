import '../models/print_template.dart';
import '../models/setlist_item.dart';

// ============================================================================
// SETLIST PRINT SERVICE - NATIVE STUB
// Stub implementation for non-web platforms.
//
// This file is used when compiling for iOS/Android/macOS/Windows.
// The actual printing is handled by SetlistPrintService using the pdf package.
// This stub exists to allow conditional imports without compilation errors.
// ============================================================================

class SetlistPrintWeb {
  SetlistPrintWeb._();

  /// Stub - not used on native platforms.
  static void printSetlist({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) {
    throw UnsupportedError('SetlistPrintWeb is only available on web platform');
  }
}
