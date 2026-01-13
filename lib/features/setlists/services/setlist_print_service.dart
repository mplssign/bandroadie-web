import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';

// ============================================================================
// SETLIST PRINT SERVICE
// Centralized print formatting logic for stage-readable setlist output.
//
// DESIGN PRINCIPLES (shared across Web, iOS, Android):
// - Large, bold text optimized for low-light stage conditions
// - High contrast (black text on white background)
// - Song title + BPM only (no artist, duration, notes, icons)
// - Tuning section breaks with bold tuning labels when tuning changes
// - Maximum 2 pages with automatic font scaling if needed
// - Never split a tuning block across pages
//
// PLATFORM IMPLEMENTATIONS:
// - Native (iOS/Android/macOS): PDF generation via printing package
// - Web: HTML generation for window.print() (see setlist_print_web.dart)
//
// USAGE:
//   await SetlistPrintService.printSetlist(
//     setlistName: 'Friday Night Set',
//     songs: songsList,
//   );
// ============================================================================

/// Represents a group of songs in the same tuning.
/// Used to prevent splitting tuning blocks across pages.
class TuningBlock {
  final String tuning;
  final List<SetlistSong> songs;
  final int startIndex; // Original position in setlist (1-based for display)

  TuningBlock({
    required this.tuning,
    required this.songs,
    required this.startIndex,
  });
}

class SetlistPrintService {
  SetlistPrintService._(); // Prevent instantiation

  // ===========================================================================
  // PRINT CONFIGURATION
  // Centralized constants for stage-readable formatting.
  // These values are calibrated for legibility from 3-6 feet under stage lights.
  // ===========================================================================

  /// Font size for the setlist title header (largest element)
  static const double _titleFontSize = 28.0;

  /// Font size for each song entry (primary visual element)
  /// Large and bold for quick scanning during performance
  static const double _songFontSize = 18.0;

  /// Font size for BPM (slightly smaller, inline with title)
  static const double _bpmFontSize = 16.0;

  /// Font size for tuning section labels (smaller than songs, but bold)
  static const double _tuningLabelFontSize = 14.0;

  /// Vertical spacing between song entries
  static const double _songSpacing = 10.0;

  /// Height of tuning section divider line
  static const double _dividerHeight = 2.5;

  /// Spacing above/below tuning dividers
  static const double _dividerSpacingTop = 18.0;
  static const double _dividerSpacingBottom = 10.0;

  /// Page margins (ensures content doesn't clip on printers)
  static const double _pageMargin = 36.0;

  /// Minimum font scale factor to maintain legibility
  /// If content exceeds 2 pages, we scale down but never below this
  static const double _minFontScale = 0.75;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Print the setlist with stage-optimized formatting.
  ///
  /// [setlistName] - Display name for the header
  /// [songs] - Ordered list of songs to print (maintains exact order)
  static Future<void> printSetlist({
    required String setlistName,
    required List<SetlistSong> songs,
  }) async {
    final pdf = _buildPdfDocument(
      setlistName: setlistName,
      songs: songs,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '$setlistName - Setlist',
    );
  }

  /// Generate PDF bytes without printing (for testing or export).
  static Future<List<int>> generatePdfBytes({
    required String setlistName,
    required List<SetlistSong> songs,
  }) async {
    final pdf = _buildPdfDocument(
      setlistName: setlistName,
      songs: songs,
    );
    return pdf.save();
  }

  /// Generate print-ready HTML for web platform.
  /// Returns complete HTML document with embedded print styles.
  static String generatePrintHtml({
    required String setlistName,
    required List<SetlistSong> songs,
  }) {
    final tuningBlocks = groupSongsByTuning(songs);
    final buffer = StringBuffer();

    // HTML document with embedded print-optimized CSS
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>$setlistName - Setlist</title>');
    buffer.writeln('<style>');
    buffer.writeln(_generatePrintCss());
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // Setlist title header
    buffer.writeln('<h1 class="setlist-title">${_escapeHtml(setlistName)}</h1>');
    buffer.writeln('<hr class="title-divider">');

    // Song list with tuning sections
    buffer.writeln('<div class="song-list">');
    
    for (final block in tuningBlocks) {
      // Tuning section header (only show if not first block or if tuning differs)
      buffer.writeln('<div class="tuning-block">');
      buffer.writeln('<div class="tuning-divider">');
      buffer.writeln('<span class="tuning-label">${_escapeHtml(block.tuning)}</span>');
      buffer.writeln('</div>');

      // Songs in this tuning block
      for (int i = 0; i < block.songs.length; i++) {
        final song = block.songs[i];
        final songNumber = block.startIndex + i;
        final bpmText = song.bpm != null && song.bpm! > 0 
            ? '(${song.bpm} BPM)' 
            : '';

        buffer.writeln('<div class="song-row">');
        buffer.writeln('<span class="song-number">$songNumber.</span>');
        buffer.writeln('<span class="song-title">${_escapeHtml(song.title)}</span>');
        buffer.writeln('<span class="song-bpm">$bpmText</span>');
        buffer.writeln('</div>');
      }

      buffer.writeln('</div>'); // Close tuning-block
    }

    buffer.writeln('</div>'); // Close song-list
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  // ===========================================================================
  // CSS GENERATION (Web Print)
  // ===========================================================================

  /// Generate print-optimized CSS for web printing.
  /// Uses @media print to ensure proper rendering when printing.
  static String _generatePrintCss() {
    return '''
/* ============================================================================
   STAGE-READABLE PRINT STYLES
   Optimized for low-light conditions and quick scanning during live shows.
   ============================================================================ */

/* Reset and base styles */
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  background: white;
  color: black;
  padding: 0.5in;
  /* Maximum 2 pages - content will scale if needed */
  max-height: 21in; /* ~2 pages at letter size */
}

/* Setlist title - largest element for quick identification */
.setlist-title {
  font-size: 28pt;
  font-weight: 700;
  margin-bottom: 8px;
  color: black;
}

.title-divider {
  border: none;
  border-top: 2px solid black;
  margin-bottom: 20px;
}

/* Song list container */
.song-list {
  display: flex;
  flex-direction: column;
}

/* Tuning block - keeps songs in same tuning together */
.tuning-block {
  break-inside: avoid; /* Never split tuning blocks across pages */
  page-break-inside: avoid;
  margin-bottom: 8px;
}

/* Tuning section divider with centered label */
.tuning-divider {
  display: flex;
  align-items: center;
  margin: 16px 0 10px 0;
  gap: 12px;
}

.tuning-divider::before,
.tuning-divider::after {
  content: '';
  flex: 1;
  height: 2.5px;
  background: #666;
}

.tuning-label {
  font-size: 14pt;
  font-weight: 700;
  color: #333;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  white-space: nowrap;
}

/* Individual song row */
.song-row {
  display: flex;
  align-items: baseline;
  margin-bottom: 10px;
  gap: 8px;
}

.song-number {
  font-size: 18pt;
  font-weight: 700;
  color: black;
  min-width: 36px;
}

.song-title {
  font-size: 18pt;
  font-weight: 700;
  color: black;
  flex: 1;
}

.song-bpm {
  font-size: 16pt;
  font-weight: 600;
  color: #444;
  white-space: nowrap;
}

/* Print-specific overrides */
@media print {
  body {
    padding: 0.4in;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  /* Ensure max 2 pages by scaling if needed */
  @page {
    size: letter;
    margin: 0.4in;
  }

  /* Hide any browser chrome */
  @page :first {
    margin-top: 0.4in;
  }
}

/* Screen preview styles (when viewing before print) */
@media screen {
  body {
    max-width: 8.5in;
    margin: 0 auto;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
  }
}
''';
  }

  // ===========================================================================
  // PDF GENERATION (Native Platforms)
  // ===========================================================================

  /// Build the PDF document with all songs.
  /// Automatically scales content to fit within 2 pages.
  static pw.Document _buildPdfDocument({
    required String setlistName,
    required List<SetlistSong> songs,
  }) {
    final pdf = pw.Document();
    final tuningBlocks = groupSongsByTuning(songs);

    // Calculate if we need to scale down to fit 2 pages
    // Start with default scale and reduce if needed
    double fontScale = 1.0;
    
    // Estimate content height (rough calculation)
    // Header ~50pt, each song ~30pt, each tuning break ~50pt
    final estimatedHeight = 50.0 + 
        (songs.length * 30.0) + 
        (tuningBlocks.length * 50.0);
    
    // Letter page usable height: ~10in * 72pt = 720pt, minus margins = ~640pt
    // 2 pages = ~1280pt usable
    const maxHeight = 1280.0;
    
    if (estimatedHeight > maxHeight) {
      fontScale = (maxHeight / estimatedHeight).clamp(_minFontScale, 1.0);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: pw.EdgeInsets.all(_pageMargin),
        maxPages: 2, // Enforce 2-page maximum
        build: (pw.Context context) => [
          // Setlist title header
          pw.Text(
            setlistName,
            style: pw.TextStyle(
              fontSize: _titleFontSize * fontScale,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),

          // Horizontal rule below title
          pw.Container(
            margin: pw.EdgeInsets.only(top: 8, bottom: 16),
            height: 2,
            color: PdfColors.black,
          ),

          // Song list organized by tuning blocks
          ..._buildTuningBlockWidgets(tuningBlocks, fontScale),
        ],
      ),
    );

    return pdf;
  }

  /// Build widgets for all tuning blocks.
  /// Each block has a tuning header and its songs.
  static List<pw.Widget> _buildTuningBlockWidgets(
    List<TuningBlock> blocks,
    double fontScale,
  ) {
    final widgets = <pw.Widget>[];

    for (final block in blocks) {
      // Tuning section with divider and label
      // Wrapped to prevent page break within a tuning block
      widgets.add(
        pw.Wrap(
          children: [
            // Tuning divider with centered label
            _buildTuningDivider(block.tuning, fontScale),
            // Songs in this tuning
            ..._buildBlockSongRows(block, fontScale),
          ],
        ),
      );
    }

    return widgets;
  }

  /// Build song rows for a single tuning block.
  static List<pw.Widget> _buildBlockSongRows(
    TuningBlock block,
    double fontScale,
  ) {
    final widgets = <pw.Widget>[];

    for (int i = 0; i < block.songs.length; i++) {
      final song = block.songs[i];
      final songNumber = block.startIndex + i;
      widgets.add(_buildSongRow(song, songNumber, fontScale));
    }

    return widgets;
  }

  /// Build a single song row: "[number]. Title                 (### BPM)"
  static pw.Widget _buildSongRow(
    SetlistSong song,
    int songNumber,
    double fontScale,
  ) {
    // Format BPM: show "(### BPM)" or empty if not set
    final bpmText = song.bpm != null && song.bpm! > 0 
        ? '(${song.bpm} BPM)' 
        : '';

    return pw.Container(
      margin: pw.EdgeInsets.only(bottom: _songSpacing * fontScale),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Song number (fixed width for alignment)
          pw.SizedBox(
            width: 36 * fontScale,
            child: pw.Text(
              '$songNumber.',
              style: pw.TextStyle(
                fontSize: _songFontSize * fontScale,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),

          // Song title (expands to fill available space)
          pw.Expanded(
            child: pw.Text(
              song.title,
              style: pw.TextStyle(
                fontSize: _songFontSize * fontScale,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),

          // BPM (inline, slightly smaller)
          if (bpmText.isNotEmpty)
            pw.Text(
              bpmText,
              style: pw.TextStyle(
                fontSize: _bpmFontSize * fontScale,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
        ],
      ),
    );
  }

  /// Build a tuning section divider with centered tuning label.
  ///
  /// VISUAL DESIGN:
  /// - Thick horizontal line with centered tuning name
  /// - Bold uppercase label for quick identification
  /// - Signals to guitarist: "switch to this tuning"
  static pw.Widget _buildTuningDivider(String tuning, double fontScale) {
    return pw.Container(
      margin: pw.EdgeInsets.only(
        top: _dividerSpacingTop * fontScale,
        bottom: _dividerSpacingBottom * fontScale,
      ),
      child: pw.Row(
        children: [
          // Left line
          pw.Expanded(
            child: pw.Container(
              height: _dividerHeight,
              color: PdfColors.grey600,
            ),
          ),
          // Centered tuning label
          pw.Container(
            padding: pw.EdgeInsets.symmetric(horizontal: 12),
            child: pw.Text(
              tuning.toUpperCase(),
              style: pw.TextStyle(
                fontSize: _tuningLabelFontSize * fontScale,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          // Right line
          pw.Expanded(
            child: pw.Container(
              height: _dividerHeight,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TUNING BLOCK UTILITIES
  // ===========================================================================

  /// Group songs by consecutive tuning sections.
  /// Maintains setlist order while creating logical tuning blocks.
  /// Public for use by web print implementation.
  static List<TuningBlock> groupSongsByTuning(List<SetlistSong> songs) {
    if (songs.isEmpty) return [];

    final blocks = <TuningBlock>[];
    String? currentTuning;
    List<SetlistSong> currentSongs = [];
    int blockStartIndex = 1;

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final tuning = normalizeTuning(song.tuning);

      if (currentTuning == null) {
        // First song
        currentTuning = tuning;
        currentSongs = [song];
        blockStartIndex = i + 1;
      } else if (tuning == currentTuning) {
        // Same tuning, add to current block
        currentSongs.add(song);
      } else {
        // Tuning changed, save current block and start new one
        blocks.add(TuningBlock(
          tuning: currentTuning,
          songs: currentSongs,
          startIndex: blockStartIndex,
        ));
        currentTuning = tuning;
        currentSongs = [song];
        blockStartIndex = i + 1;
      }
    }

    // Don't forget the last block
    if (currentSongs.isNotEmpty && currentTuning != null) {
      blocks.add(TuningBlock(
        tuning: currentTuning,
        songs: currentSongs,
        startIndex: blockStartIndex,
      ));
    }

    return blocks;
  }

  /// Normalize tuning string for comparison and display.
  /// Public for use by web print implementation.
  static String normalizeTuning(String? tuning) {
    return tuningShortLabel(tuning);
  }

  /// Escape HTML special characters for safe output.
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
