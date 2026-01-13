import '../models/setlist_song.dart';

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
  /// Native platforms use SetlistPrintService.printSetlist() directly.
  static void printSetlist({
    required String setlistName,
    required List<SetlistSong> songs,
  }) {
    // This should never be called on native platforms
    throw UnsupportedError('SetlistPrintWeb is only available on web platform');
  }
}
