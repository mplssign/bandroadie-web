import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/print_template.dart';
import '../models/setlist_item.dart';
import '../models/setlist_song.dart';
import '../tuning/tuning_helpers.dart';

// ============================================================================
// SETLIST PRINT SERVICE
// Template-driven print formatting for setlist output.
//
// Supports:
// - Set grouping by Set Break markers
// - Inline pause rendering
// - Configurable tuning display (grouped / inline)
// - Metadata toggles (BPM, capo, notes, song numbers)
// - Font size, paper size, column count
// - Header and page numbers
// ============================================================================

/// Represents a group of items between Set Break markers.
class SetGroup {
  final int setNumber; // 1-based
  final List<SetlistItem> items; // Songs + pauses only (breaks are delimiters)

  const SetGroup({required this.setNumber, required this.items});
}

class SetlistPrintService {
  SetlistPrintService._();

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Print the setlist with template-driven formatting.
  static Future<void> printSetlist({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) async {
    final pdf = await _buildPdfDocument(
      setlistName: setlistName,
      items: items,
      template: template,
      bandName: bandName,
      gigDate: gigDate,
      venue: venue,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '$setlistName - Setlist',
    );
  }

  /// Generate PDF bytes without printing (for testing or export).
  static Future<List<int>> generatePdfBytes({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) async {
    final pdf = await _buildPdfDocument(
      setlistName: setlistName,
      items: items,
      template: template,
      bandName: bandName,
      gigDate: gigDate,
      venue: venue,
    );
    return pdf.save();
  }

  /// Generate print-ready HTML for web platform.
  static String generatePrintHtml({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) {
    final setGroups = groupItemsBySets(items);
    final hasMultipleSets = setGroups.length > 1;
    final buffer = StringBuffer();

    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html lang="en">');
    buffer.writeln('<head>');
    buffer.writeln('<meta charset="UTF-8">');
    buffer.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    buffer.writeln('<title>${_escapeHtml(setlistName)} - Setlist</title>');
    buffer.writeln('<style>');
    buffer.writeln(_generatePrintCss(template));
    buffer.writeln('</style>');
    buffer.writeln('</head>');
    buffer.writeln('<body>');

    // Header
    if (template.showHeader || template.showBandName) {
      buffer.writeln('<div class="header">');
      if (template.showHeader) {
        buffer.writeln(
            '<h1 class="setlist-title">${_escapeHtml(setlistName)}</h1>');
      }
      if (template.showBandName && bandName != null && bandName.isNotEmpty) {
        buffer.writeln('<div class="band-name">${_escapeHtml(bandName)}</div>');
      }
      if (gigDate != null && gigDate.isNotEmpty) {
        buffer.writeln('<div class="gig-date">${_escapeHtml(gigDate)}</div>');
      }
      if (venue != null && venue.isNotEmpty) {
        buffer.writeln('<div class="venue">${_escapeHtml(venue)}</div>');
      }
      buffer.writeln('</div>');
      buffer.writeln('<hr class="title-divider">');
    }

    // Song list
    buffer.writeln('<div class="song-list">');

    for (final group in setGroups) {
      // Per-set song numbering — resets at each set boundary
      int songNumber = 0;
      String? lastTuning;

      // Set label
      if (hasMultipleSets) {
        buffer.writeln('<div class="set-label">Set ${group.setNumber}</div>');
      }

      for (final item in group.items) {
        if (item.isPause) {
          if (template.showPauses) {
            final label = item.specialItem?.displayLabel ?? 'Pause';
            buffer
                .writeln('<div class="pause-row">${_escapeHtml(label)}</div>');
          }
          continue;
        }

        if (!item.isSong || item.song == null) continue;

        final song = item.song!;
        songNumber++;

        // Grouped tuning: show divider when tuning changes
        if (template.showTuning && template.tuningDisplay == 'grouped') {
          final tuning = normalizeTuning(song.tuning);
          if (tuning != lastTuning) {
            lastTuning = tuning;
            buffer.writeln('<div class="tuning-divider">');
            buffer.writeln(
                '<span class="tuning-label">${_escapeHtml(tuning)}</span>');
            buffer.writeln('</div>');
          }
        }

        buffer.writeln('<div class="song-row">');

        // Song number
        if (template.showSongNumbers) {
          buffer.writeln('<span class="song-number">$songNumber.</span>');
        }

        // Song title
        buffer.write('<span class="song-title">${_escapeHtml(song.title)}');

        // Capo inline with title
        if (template.showCapo) {
          final parsed = parseCapoTuning(song.tuning);
          if (parsed.capoFret != null) {
            buffer.write(
                ' <span class="capo-label">Capo ${parsed.capoFret}</span>');
          }
        }
        buffer.writeln('</span>');

        // Right side: inline tuning and BPM (independent font sizes)
        final hasInlineTuning =
            template.showTuning && template.tuningDisplay == 'inline';
        final hasInlineBpm =
            template.showBpm && song.bpm != null && song.bpm! > 0;

        if (hasInlineTuning || hasInlineBpm) {
          buffer.write('<span class="song-meta">');
          if (hasInlineTuning) {
            buffer.write(
                '<span class="meta-tuning">${_escapeHtml(tuningShortLabel(song.tuning))}</span>');
          }
          if (hasInlineTuning && hasInlineBpm) {
            buffer.write(' &middot; ');
          }
          if (hasInlineBpm) {
            buffer.write('<span class="meta-bpm">${song.bpm} BPM</span>');
          }
          buffer.writeln('</span>');
        }

        buffer.writeln('</div>'); // Close song-row

        // Notes below title
        if (template.showNotes &&
            song.notes != null &&
            song.notes!.isNotEmpty) {
          buffer.writeln(
              '<div class="song-notes">${_escapeHtml(song.notes!)}</div>');
        }
      }
    }

    buffer.writeln('</div>'); // Close song-list
    buffer.writeln('</body>');
    buffer.writeln('</html>');

    return buffer.toString();
  }

  // ===========================================================================
  // SET GROUPING
  // ===========================================================================

  /// Split items into set groups by Set Break markers.
  /// If no set breaks exist, all items form one group with no set label.
  static List<SetGroup> groupItemsBySets(List<SetlistItem> items) {
    if (items.isEmpty) return [];

    final groups = <SetGroup>[];
    var currentItems = <SetlistItem>[];
    int setNumber = 1;

    for (final item in items) {
      if (item.isSetBreak) {
        // Save current group and start a new one
        if (currentItems.isNotEmpty) {
          groups.add(SetGroup(setNumber: setNumber, items: currentItems));
          currentItems = <SetlistItem>[];
          setNumber++;
        }
      } else {
        currentItems.add(item);
      }
    }

    // Don't forget the last group
    if (currentItems.isNotEmpty) {
      groups.add(SetGroup(setNumber: setNumber, items: currentItems));
    }

    return groups;
  }

  // ===========================================================================
  // CSS GENERATION (Web Print)
  // ===========================================================================

  static String _generatePrintCss(PrintTemplate template) {
    final fontSize = template.baseFontSize;
    final titleSize = template.headerFontSize.round();
    final numberSize = template.numberFontSize.round();
    final bpmSize = template.bpmFontSize.round();
    final bandNameSize = template.bandNameFontSize.round();
    final tuningLabelSize = template.tuningFontSize.round();
    final capoSize = template.capoFontSize.round();
    final notesSize = template.notesFontSize.round();
    final pauseSize = template.pauseFontSize.round();
    final pageSize = switch (template.paperSize) {
      'a4' => 'A4',
      'legal' => 'legal',
      'tabloid' => '11in 17in',
      _ => 'letter',
    };
    final columnCount = template.columnCount;

    return '''
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
${columnCount == 2 ? '  column-count: 2;\n  column-gap: 24px;' : ''}
}

.header {
  ${columnCount == 2 ? 'column-span: all;' : ''}
  margin-bottom: 8px;
}

.setlist-title {
  font-size: ${titleSize}pt;
  font-weight: 700;
  color: black;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.band-name {
  font-size: ${bandNameSize}pt;
  color: #444;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.gig-date, .venue {
  font-size: ${bpmSize}pt;
  color: #444;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.title-divider {
  border: none;
  border-top: 2px solid black;
  margin-bottom: 16px;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.song-list {
}

.set-label {
  font-size: ${(fontSize * 1.1).round()}pt;
  font-weight: 700;
  color: black;
  margin: 16px 0 8px 0;
  padding: 4px 0;
  border-bottom: 2px solid black;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.pause-row {
  font-size: ${pauseSize}pt;
  font-weight: 600;
  color: #333;
  padding: 6px 12px;
  margin: 6px 0;
  border: 1.5px solid #888;
  border-radius: 4px;
  text-align: center;
  ${columnCount == 2 ? 'column-span: all;' : ''}
}

.tuning-divider {
  display: flex;
  align-items: center;
  margin: 12px 0 8px 0;
  gap: 12px;
  break-inside: avoid;
}

.tuning-divider::before,
.tuning-divider::after {
  content: '';
  flex: 1;
  height: 2px;
  background: #666;
}

.tuning-label {
  font-size: ${tuningLabelSize}pt;
  font-weight: 700;
  color: #333;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  white-space: nowrap;
}

.song-row {
  display: flex;
  align-items: baseline;
  margin-bottom: ${(fontSize * 0.55 * template.lineSpacing).round()}px;
  gap: 8px;
  break-inside: avoid;
}

.song-number {
  font-size: ${numberSize}pt;
  font-weight: 700;
  color: black;
  min-width: ${(numberSize * 2).round()}px;
}

.song-title {
  font-size: ${fontSize.round()}pt;
  font-weight: 700;
  color: black;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.capo-label {
  font-size: ${capoSize}pt;
  font-weight: 600;
  color: #555;
}

.song-meta {
  font-weight: 600;
  color: #444;
  white-space: nowrap;
}

.meta-tuning {
  font-size: ${tuningLabelSize}pt;
}

.meta-bpm {
  font-size: ${bpmSize}pt;
}

.song-notes {
  font-size: ${notesSize}pt;
  color: #555;
  font-style: italic;
  margin: -${(fontSize * 0.2).round()}px 0 ${(fontSize * 0.4).round()}px 0;
  break-inside: avoid;
}

@media print {
  body {
    padding: 0.4in;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  @page {
    size: $pageSize;
    margin: 0.4in;

  }
}

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

  static Future<pw.Document> _buildPdfDocument({
    required String setlistName,
    required List<SetlistItem> items,
    required PrintTemplate template,
    String? bandName,
    String? gigDate,
    String? venue,
  }) async {
    // Load Noto Sans for full Unicode coverage (curly quotes, ♭, etc.)
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final fontItalic = await PdfGoogleFonts.notoSansItalic();
    final fontBoldItalic = await PdfGoogleFonts.notoSansBoldItalic();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: fontBold,
        italic: fontItalic,
        boldItalic: fontBoldItalic,
      ),
    );
    final setGroups = groupItemsBySets(items);
    final hasMultipleSets = setGroups.length > 1;

    final pageFormat = switch (template.paperSize) {
      'a4' => PdfPageFormat.a4,
      'legal' => PdfPageFormat.legal,
      'tabloid' =>
        const PdfPageFormat(11 * PdfPageFormat.inch, 17 * PdfPageFormat.inch),
      _ => PdfPageFormat.letter,
    };

    final baseFontSize = template.baseFontSize;

    // Build all content widgets
    final allWidgets = <pw.Widget>[];

    // Header
    if (template.showHeader || template.showBandName) {
      allWidgets.addAll(_buildHeader(
        setlistName: setlistName,
        bandName: bandName,
        gigDate: gigDate,
        venue: venue,
        template: template,
      ));
    }

    // Build song widgets per set group
    for (final group in setGroups) {
      // Per-set song numbering — resets at each set boundary
      int songNumber = 0;
      String? lastTuning;

      if (hasMultipleSets) {
        allWidgets.add(_buildSetLabel(group.setNumber, baseFontSize));
      }

      for (final item in group.items) {
        if (item.isPause) {
          if (template.showPauses) {
            allWidgets.add(_buildPauseRow(item, template.pauseFontSize));
          }
          continue;
        }

        if (!item.isSong || item.song == null) continue;

        final song = item.song!;
        songNumber++;

        // Grouped tuning: show divider when tuning changes
        if (template.showTuning && template.tuningDisplay == 'grouped') {
          final tuning = normalizeTuning(song.tuning);
          if (tuning != lastTuning) {
            lastTuning = tuning;
            allWidgets
                .add(_buildTuningDivider(tuning, template.tuningFontSize));
          }
        }

        allWidgets.add(_buildSongRow(
          song: song,
          songNumber: songNumber,
          template: template,
        ));

        // Notes below song
        if (template.showNotes &&
            song.notes != null &&
            song.notes!.isNotEmpty) {
          allWidgets.add(_buildNotesRow(song.notes!, template.notesFontSize));
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(36.0),
        build: (pw.Context context) {
          if (template.columnCount == 2) {
            return _buildTwoColumnLayout(allWidgets);
          }
          return allWidgets;
        },
      ),
    );

    return pdf;
  }

  /// Build two-column layout. Set labels and pause rows span full width;
  /// song rows and other items participate in column flow.
  static List<pw.Widget> _buildTwoColumnLayout(
    List<pw.Widget> allWidgets,
  ) {
    final result = <pw.Widget>[];
    var columnBuffer = <pw.Widget>[];

    void flushColumnBuffer() {
      if (columnBuffer.isEmpty) return;
      result.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: _takeFirstHalf(columnBuffer),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: _takeSecondHalf(columnBuffer),
              ),
            ),
          ],
        ),
      );
      columnBuffer = <pw.Widget>[];
    }

    for (final widget in allWidgets) {
      if (widget is _FullWidthMarker) {
        flushColumnBuffer();
        result.add(widget.child);
      } else {
        columnBuffer.add(widget);
      }
    }

    flushColumnBuffer();
    return result;
  }

  static List<pw.Widget> _takeFirstHalf(List<pw.Widget> widgets) {
    final mid = (widgets.length + 1) ~/ 2;
    return widgets.sublist(0, mid);
  }

  static List<pw.Widget> _takeSecondHalf(List<pw.Widget> widgets) {
    final mid = (widgets.length + 1) ~/ 2;
    return widgets.sublist(mid);
  }

  // ===========================================================================
  // PDF WIDGET BUILDERS
  // ===========================================================================

  static List<pw.Widget> _buildHeader({
    required String setlistName,
    String? bandName,
    String? gigDate,
    String? venue,
    required PrintTemplate template,
  }) {
    final widgets = <pw.Widget>[];
    final titleSize = template.headerFontSize;
    final bandNameSize = template.bandNameFontSize;
    final subtitleSize = template.bpmFontSize; // gig date / venue size

    if (template.showHeader) {
      widgets.add(
        _fullWidth(pw.Text(
          setlistName,
          style: pw.TextStyle(
            fontSize: titleSize,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
          ),
        )),
      );
    }

    if (template.showBandName && bandName != null && bandName.isNotEmpty) {
      widgets.add(
        _fullWidth(pw.Text(
          bandName,
          style: pw.TextStyle(
            fontSize: bandNameSize,
            color: PdfColors.grey700,
          ),
        )),
      );
    }

    if (gigDate != null && gigDate.isNotEmpty) {
      widgets.add(
        _fullWidth(pw.Text(
          gigDate,
          style: pw.TextStyle(
            fontSize: subtitleSize,
            color: PdfColors.grey700,
          ),
        )),
      );
    }

    if (venue != null && venue.isNotEmpty) {
      widgets.add(
        _fullWidth(pw.Text(
          venue,
          style: pw.TextStyle(
            fontSize: subtitleSize,
            color: PdfColors.grey700,
          ),
        )),
      );
    }

    // Divider below header
    widgets.add(
      _fullWidth(pw.Container(
        margin: const pw.EdgeInsets.only(top: 8, bottom: 16),
        height: 2,
        color: PdfColors.black,
      )),
    );

    return widgets;
  }

  static pw.Widget _buildSetLabel(int setNumber, double baseFontSize) {
    return _fullWidth(
      pw.Container(
        margin: pw.EdgeInsets.only(
          top: baseFontSize * 0.9,
          bottom: baseFontSize * 0.45,
        ),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.black, width: 2),
          ),
        ),
        child: pw.Text(
          'SET $setNumber',
          style: pw.TextStyle(
            fontSize: baseFontSize * 1.1,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.black,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildPauseRow(SetlistItem item, double pauseFontSize) {
    final label = item.specialItem?.displayLabel ?? 'Pause';
    return _fullWidth(
      pw.Container(
        margin: pw.EdgeInsets.symmetric(vertical: pauseFontSize * 0.4),
        padding: pw.EdgeInsets.symmetric(
          horizontal: pauseFontSize * 0.7,
          vertical: pauseFontSize * 0.35,
        ),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey600, width: 1.5),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Center(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: pauseFontSize,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey800,
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _buildTuningDivider(String tuning, double baseFontSize) {
    return pw.Container(
      margin: pw.EdgeInsets.only(
        top: baseFontSize * 1.0,
        bottom: baseFontSize * 0.55,
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Container(
              height: 2.5,
              color: PdfColors.grey600,
            ),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12),
            child: pw.Text(
              tuning.toUpperCase(),
              style: pw.TextStyle(
                fontSize: baseFontSize * 0.78,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              height: 2.5,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSongRow({
    required SetlistSong song,
    required int songNumber,
    required PrintTemplate template,
  }) {
    final titleFont = template.baseFontSize;
    final numberFont = template.numberFontSize;
    final bpmFont = template.bpmFontSize;
    final capoFont = template.capoFontSize;
    final tuningFont = template.tuningFontSize;
    final titleChildren = <pw.InlineSpan>[];

    // Build title text
    titleChildren.add(pw.TextSpan(
      text: song.title,
      style: pw.TextStyle(
        fontSize: titleFont,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.black,
      ),
    ));

    // Capo inline
    if (template.showCapo) {
      final parsed = parseCapoTuning(song.tuning);
      if (parsed.capoFret != null) {
        titleChildren.add(pw.TextSpan(
          text: '  Capo ${parsed.capoFret}',
          style: pw.TextStyle(
            fontSize: capoFont,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
          ),
        ));
      }
    }

    // Right side metadata widgets (each with own font size)
    final rightWidgets = <pw.Widget>[];

    if (template.showTuning && template.tuningDisplay == 'inline') {
      rightWidgets.add(pw.Text(
        tuningShortLabel(song.tuning),
        style: pw.TextStyle(
          fontSize: tuningFont,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey700,
        ),
      ));
    }

    if (template.showBpm && song.bpm != null && song.bpm! > 0) {
      rightWidgets.add(pw.Text(
        '${song.bpm} BPM',
        style: pw.TextStyle(
          fontSize: bpmFont,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey700,
        ),
      ));
    }

    return pw.Container(
      margin:
          pw.EdgeInsets.only(bottom: titleFont * 0.55 * template.lineSpacing),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Song number
          if (template.showSongNumbers)
            pw.SizedBox(
              width: numberFont * 2.0,
              child: pw.Text(
                '$songNumber.',
                style: pw.TextStyle(
                  fontSize: numberFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),

          // Title + capo (truncate, don't wrap)
          pw.Expanded(
            child: pw.ClipRect(
              child: pw.RichText(
                text: pw.TextSpan(children: titleChildren),
                maxLines: 1,
              ),
            ),
          ),

          // Right meta (tuning and BPM with independent font sizes)
          if (rightWidgets.isNotEmpty)
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                for (int i = 0; i < rightWidgets.length; i++) ...[
                  if (i > 0)
                    pw.Text(
                      ' · ',
                      style: pw.TextStyle(
                        fontSize: bpmFont,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                  rightWidgets[i],
                ],
              ],
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildNotesRow(String notes, double notesFontSize) {
    return pw.Container(
      margin: pw.EdgeInsets.only(
        bottom: notesFontSize * 0.56,
      ),
      child: pw.Text(
        notes,
        style: pw.TextStyle(
          fontSize: notesFontSize,
          fontStyle: pw.FontStyle.italic,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  // ===========================================================================
  // TUNING UTILITIES
  // ===========================================================================

  /// Normalize tuning string for comparison and display.
  static String normalizeTuning(String? tuning) {
    return tuningShortLabel(tuning);
  }

  // ===========================================================================
  // HTML UTILITIES
  // ===========================================================================

  /// Escape HTML special characters for safe output.
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  // ===========================================================================
  // TWO-COLUMN HELPERS
  // ===========================================================================

  /// Wrap a widget to mark it as full-width (spans both columns in 2-col).
  static pw.Widget _fullWidth(pw.Widget child) {
    return _FullWidthMarker(child: child);
  }
}

/// Marker widget for full-width elements in two-column PDF layout.
class _FullWidthMarker extends pw.StatelessWidget {
  final pw.Widget child;

  _FullWidthMarker({required this.child});

  @override
  pw.Widget build(pw.Context context) => child;
}
