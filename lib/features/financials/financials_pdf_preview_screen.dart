import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../app/theme/app_icons.dart';
import '../../app/theme/brand_colors.dart';
import '../../app/theme/design_tokens.dart';
import 'financials_controller.dart';
import 'models/financial_entry.dart';

// ============================================================================
// FINANCIALS PDF PREVIEW SCREEN
// Generates a PDF report of filtered financial entries and shows a preview
// with device share options (print, email, save, message, etc).
// ============================================================================

class FinancialsPdfPreviewScreen extends StatefulWidget {
  final List<FinancialEntry> entries;
  final String bandName;
  final FinancialDateFilter dateFilter;
  final DateTime? customStartDate;
  final DateTime? customEndDate;
  final FinancialViewMode viewMode;

  const FinancialsPdfPreviewScreen({
    super.key,
    required this.entries,
    required this.bandName,
    required this.dateFilter,
    required this.viewMode,
    this.customStartDate,
    this.customEndDate,
  });

  @override
  State<FinancialsPdfPreviewScreen> createState() =>
      _FinancialsPdfPreviewScreenState();
}

class _FinancialsPdfPreviewScreenState
    extends State<FinancialsPdfPreviewScreen> {
  Uint8List? _cachedPdf;

  // ---------------------------------------------------------------------------
  // LABEL HELPERS
  // ---------------------------------------------------------------------------

  String get _filterLabel {
    switch (widget.dateFilter) {
      case FinancialDateFilter.allTime:
        return 'All Time';
      case FinancialDateFilter.thisYear:
        return 'Year ${DateTime.now().year}';
      case FinancialDateFilter.thisMonth:
        final now = DateTime.now();
        return DateFormat('MMMM yyyy').format(now);
      case FinancialDateFilter.custom:
        if (widget.customStartDate != null && widget.customEndDate != null) {
          final fmt = DateFormat('MMM d, yyyy');
          return '${fmt.format(widget.customStartDate!)} – ${fmt.format(widget.customEndDate!)}';
        }
        return 'Custom';
    }
  }

  String get _viewModeLabel =>
      widget.viewMode == FinancialViewMode.income ? 'Income' : 'Expenses';

  String get _fileName =>
      '${widget.bandName} – $_viewModeLabel ($_filterLabel).pdf';

  // ---------------------------------------------------------------------------
  // PDF GENERATION
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    if (_cachedPdf != null) return _cachedPdf!;

    final moneyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dateFmt = DateFormat('MMM d, yyyy');

    final doc = pw.Document();

    // Color palette mirroring the app's dark theme in print-friendly tones
    const headerBg = PdfColor.fromInt(0xFF1F1F23);
    const rowAlt = PdfColor.fromInt(0xFFF7F7F8);
    const accentRed = PdfColor.fromInt(0xFFF43F5E);
    const incomeGreen = PdfColor.fromInt(0xFF22C55E);
    const expenseRed = PdfColor.fromInt(0xFFEF4444);
    const textDark = PdfColor.fromInt(0xFF111827);
    const textMuted = PdfColor.fromInt(0xFF6B7280);

    final totalCents = widget.entries.fold<int>(0, (s, e) => s + e.amountCents);
    final totalStr = moneyFmt.format(totalCents / 100);
    final isIncome = widget.viewMode == FinancialViewMode.income;

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      widget.bandName,
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '$_viewModeLabel Report · $_filterLabel',
                      style: pw.TextStyle(fontSize: 11, color: textMuted),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Total',
                      style: pw.TextStyle(fontSize: 10, color: textMuted),
                    ),
                    pw.Text(
                      totalStr,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: isIncome ? incomeGreen : expenseRed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(color: accentRed, thickness: 1.5),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: textMuted),
            ),
            pw.Text(
              'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: textMuted),
            ),
          ],
        ),
        build: (ctx) {
          if (widget.entries.isEmpty) {
            return [
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 60),
                  child: pw.Text(
                    'No entries for this period.',
                    style: pw.TextStyle(color: textMuted, fontSize: 13),
                  ),
                ),
              ),
            ];
          }

          // Table header row
          final headerRow = pw.TableRow(
            decoration: const pw.BoxDecoration(color: headerBg),
            children: [
              _headerCell('Amount'),
              _headerCell('Date'),
              _headerCell('Type'),
              _headerCell('From / Description'),
              _headerCell('1099', align: pw.Alignment.centerRight),
            ],
          );

          // Data rows
          final dataRows = widget.entries.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final bg = i.isEven ? PdfColors.white : rowAlt;
            final amtColor = e.isIncome ? incomeGreen : expenseRed;
            final prefix = e.isIncome ? '+' : '−';
            final amtStr = '$prefix${moneyFmt.format(e.amountCents / 100)}';
            final fromStr = [e.payerName, e.description]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(' · ');

            return pw.TableRow(
              decoration: pw.BoxDecoration(color: bg),
              children: [
                _dataCell(amtStr, color: amtColor, bold: true),
                _dataCell(dateFmt.format(e.entryDate)),
                _dataCell(e.category),
                _dataCell(fromStr.isNotEmpty ? fromStr : '—'),
                _dataCell(
                  e.is1099Expected == true ? '✓' : '',
                  align: pw.Alignment.centerRight,
                ),
              ],
            );
          }).toList();

          return [
            pw.Table(
              border: pw.TableBorder.symmetric(
                outside: const pw.BorderSide(color: PdfColors.grey300),
                inside: const pw.BorderSide(color: PdfColors.grey200),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.5),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(2.5),
                3: const pw.FlexColumnWidth(4),
                4: const pw.FlexColumnWidth(1),
              },
              children: [headerRow, ...dataRows],
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    _cachedPdf = Uint8List.fromList(bytes);
    return _cachedPdf!;
  }

  pw.Widget _headerCell(String text,
      {pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
        ),
      ),
    );
  }

  pw.Widget _dataCell(String text,
      {PdfColor? color,
      bool bold = false,
      pw.Alignment align = pw.Alignment.centerLeft}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? const PdfColor.fromInt(0xFF111827),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRINT & SHARE
  // ---------------------------------------------------------------------------

  /// Waits for [count] rendered frames. More reliable than a fixed delay for
  /// ensuring widgets are fully disposed before calling Printing APIs.
  Future<void> _waitForFrames(int count) async {
    for (var i = 0; i < count; i++) {
      final completer = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;
    }
  }

  Future<void> _handlePrint() async {
    final bytes = await _buildPdf(PdfPageFormat.letter);
    if (!mounted) return;

    // macOS: PdfPreview holds the printing channel. We must pop the screen
    // and wait for it to be fully disposed before calling layoutPdf,
    // otherwise the print dialog deadlocks/freezes.
    // We wait for two post-frame callbacks (not a fixed timer) to guarantee
    // the widget tree has settled regardless of machine speed.
    if (!kIsWeb && Platform.isMacOS) {
      Navigator.of(context).pop();
      await _waitForFrames(2);
    }

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: _fileName,
    );
  }

  Future<void> _handleShare(BuildContext context) async {
    final bytes = await _buildPdf(PdfPageFormat.letter);
    await Printing.sharePdf(bytes: bytes, filename: _fileName);
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '$_viewModeLabel Report',
          style: AppTextStyles.displayMedium
              .copyWith(color: context.colors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.print_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            tooltip: 'Print PDF',
            onPressed: _handlePrint,
          ),
          IconButton(
            icon:
                const Icon(AppIcons.share, size: 20, color: AppColors.primary),
            tooltip: 'Share PDF',
            onPressed: () => _handleShare(context),
          ),
        ],
      ),
      body: PdfPreview(
        maxPageWidth: 800,
        pdfFileName: _fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        actions: const [],
        build: _buildPdf,
        onError: (context, error) => Center(
          child: Text(
            'Could not generate PDF.',
            style: AppTextStyles.body.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}
