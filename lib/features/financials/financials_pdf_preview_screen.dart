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

  /// Null means a combined report containing both income and expenses.
  final FinancialViewMode? viewMode;

  const FinancialsPdfPreviewScreen({
    super.key,
    required this.entries,
    required this.bandName,
    required this.dateFilter,
    this.viewMode,
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

  String get _viewModeLabel {
    switch (widget.viewMode) {
      case FinancialViewMode.income:
        return 'Income';
      case FinancialViewMode.expenses:
        return 'Expenses';
      case null:
        return 'Income & Expenses';
    }
  }

  String get _fileName =>
      '${widget.bandName} – Financial Report ($_filterLabel).pdf';

  // ---------------------------------------------------------------------------
  // PDF GENERATION
  // ---------------------------------------------------------------------------

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    if (_cachedPdf != null) return _cachedPdf!;

    final moneyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final doc = pw.Document();

    // Clean, professional color palette
    const sectionHeaderBg = PdfColor.fromInt(0xFFF3F4F6); // light gray
    const subtotalBg = PdfColor.fromInt(0xFFF9FAFB); // subtle tint
    const netIncomeBg = PdfColor.fromInt(0xFFDCFCE7); // light green tint
    const dividerColor = PdfColor.fromInt(0xFFE5E7EB); // thin divider
    const textDark = PdfColor.fromInt(0xFF111827);
    const textMuted = PdfColor.fromInt(0xFF6B7280);
    const incomeGreen = PdfColor.fromInt(0xFF059669);
    const expenseRed = PdfColor.fromInt(0xFFDC2626);

    // Calculate totals
    final incomeEntries = widget.entries.where((e) => e.isIncome).toList();
    final expenseEntries = widget.entries.where((e) => !e.isIncome).toList();

    final incomeCents = incomeEntries.fold<int>(0, (s, e) => s + e.amountCents);
    final expenseCents = expenseEntries.fold<int>(0, (s, e) => s + e.amountCents);
    final netIncomeCents = incomeCents - expenseCents;

    // Group income by category
    final incomeByCategory = <String, List<FinancialEntry>>{};
    for (final entry in incomeEntries) {
      incomeByCategory.putIfAbsent(entry.category, () => []).add(entry);
    }

    // Group expenses by category
    final expensesByCategory = <String, List<FinancialEntry>>{};
    for (final entry in expenseEntries) {
      expensesByCategory.putIfAbsent(entry.category, () => []).add(entry);
    }

    // Calculate savings
    final savingsCents = widget.entries
        .where((e) => e.depositToSavings == true)
        .fold<int>(0, (sum, e) => sum + (e.depositToSavingsCents ?? 0));

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(50),
        build: (ctx) {
          final widgets = <pw.Widget>[];

          // HEADER
          widgets.addAll([
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Left side: Band name and title
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      widget.bandName,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '$_viewModeLabel Report',
                      style: pw.TextStyle(
                        fontSize: 16,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
                // Right side: Date range and generated date
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      _filterLabel,
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Generated ${DateFormat('MMMM d, yyyy').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),
          ]);

          // Empty state: no entries at all
          if (widget.entries.isEmpty) {
            widgets.add(
              pw.Center(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 60),
                  child: pw.Text(
                    'No financial activity during this reporting period.',
                    style: pw.TextStyle(fontSize: 13, color: textMuted),
                  ),
                ),
              ),
            );
            return widgets;
          }

          // INCOME SECTION
          widgets.add(_buildSectionHeader('Income', sectionHeaderBg, textDark));

          if (incomeEntries.isEmpty) {
            widgets.addAll([
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: pw.Text(
                  'No income during this period.',
                  style: pw.TextStyle(fontSize: 11, color: textMuted),
                ),
              ),
              pw.SizedBox(height: 8),
            ]);
          } else {
            // Income categories
            final sortedIncomeCategories = incomeByCategory.keys.toList()..sort();
            for (final category in sortedIncomeCategories) {
              final categoryTotal = incomeByCategory[category]!
                  .fold<int>(0, (s, e) => s + e.amountCents);
              widgets.add(_buildLineItem(
                category,
                categoryTotal,
                moneyFmt,
                textDark,
                dividerColor,
              ));
            }

            // Total Income subtotal
            widgets.addAll([
              pw.SizedBox(height: 4),
              _buildSubtotalRow(
                'Total Income',
                incomeCents,
                moneyFmt,
                subtotalBg,
                textDark,
                incomeGreen,
              ),
              pw.SizedBox(height: 24),
            ]);
          }

          // EXPENSES SECTION
          widgets.add(_buildSectionHeader('Expenses', sectionHeaderBg, textDark));

          if (expenseEntries.isEmpty) {
            widgets.addAll([
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: pw.Text(
                  'No expenses during this period.',
                  style: pw.TextStyle(fontSize: 11, color: textMuted),
                ),
              ),
              pw.SizedBox(height: 8),
            ]);
          } else {
            // Expense categories
            final sortedCategories = expensesByCategory.keys.toList()..sort();
            for (final category in sortedCategories) {
              final categoryTotal = expensesByCategory[category]!
                  .fold<int>(0, (s, e) => s + e.amountCents);
              widgets.add(_buildLineItem(
                category,
                categoryTotal,
                moneyFmt,
                textDark,
                dividerColor,
              ));
            }

            // Total Expenses subtotal
            widgets.addAll([
              pw.SizedBox(height: 4),
              _buildSubtotalRow(
                'Total Expenses',
                expenseCents,
                moneyFmt,
                subtotalBg,
                textDark,
                expenseRed,
              ),
              pw.SizedBox(height: 24),
            ]);
          }

          // NET INCOME (most prominent row)
          widgets.add(_buildNetIncomeRow(
            netIncomeCents,
            moneyFmt,
            netIncomeBg,
            textDark,
            netIncomeCents >= 0 ? incomeGreen : expenseRed,
          ));
          widgets.add(pw.SizedBox(height: 24));

          // SAVINGS SECTION (if exists)
          if (savingsCents > 0) {
            widgets.addAll([
              _buildSectionHeader('Savings', sectionHeaderBg, textDark),
              _buildLineItem(
                'Current Savings Balance',
                savingsCents,
                moneyFmt,
                textDark,
                dividerColor,
              ),
              pw.SizedBox(height: 24),
            ]);
          }

          // OPTIONAL SUMMARY BOX
          widgets.add(_buildSummaryBox(
            incomeCents,
            expenseCents,
            netIncomeCents,
            savingsCents,
            moneyFmt,
            textDark,
            textMuted,
            dividerColor,
          ));

          return widgets;
        },
      ),
    );

    final bytes = await doc.save();
    _cachedPdf = Uint8List.fromList(bytes);
    return _cachedPdf!;
  }

  pw.Widget _buildSectionHeader(
    String title,
    PdfColor backgroundColor,
    PdfColor textColor,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildLineItem(
    String label,
    int amountCents,
    NumberFormat moneyFmt,
    PdfColor textColor,
    PdfColor dividerColor,
  ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 11, color: textColor),
          ),
          pw.Text(
            moneyFmt.format(amountCents / 100),
            style: pw.TextStyle(fontSize: 11, color: textColor),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSubtotalRow(
    String label,
    int amountCents,
    NumberFormat moneyFmt,
    PdfColor backgroundColor,
    PdfColor textColor,
    PdfColor amountColor,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: pw.BoxDecoration(color: backgroundColor),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
          pw.Text(
            moneyFmt.format(amountCents / 100),
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildNetIncomeRow(
    int netIncomeCents,
    NumberFormat moneyFmt,
    PdfColor backgroundColor,
    PdfColor textColor,
    PdfColor amountColor,
  ) {
    final amountStr = netIncomeCents < 0
        ? '−${moneyFmt.format(netIncomeCents.abs() / 100)}'
        : moneyFmt.format(netIncomeCents / 100);

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: pw.BoxDecoration(
        color: backgroundColor,
        border: pw.Border.all(color: amountColor, width: 1.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Net Income',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: textColor,
            ),
          ),
          pw.Text(
            amountStr,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummaryBox(
    int incomeCents,
    int expenseCents,
    int netIncomeCents,
    int savingsCents,
    NumberFormat moneyFmt,
    PdfColor textColor,
    PdfColor textMuted,
    PdfColor dividerColor,
  ) {
    final netStr = netIncomeCents < 0
        ? '−${moneyFmt.format(netIncomeCents.abs() / 100)}'
        : moneyFmt.format(netIncomeCents / 100);

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: dividerColor),
        color: const PdfColor.fromInt(0xFFFAFAFA),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _buildSummaryLine(
            'Income',
            moneyFmt.format(incomeCents / 100),
            textColor,
            textMuted,
          ),
          pw.SizedBox(height: 6),
          _buildSummaryLine(
            'Expenses',
            moneyFmt.format(expenseCents / 100),
            textColor,
            textMuted,
          ),
          pw.SizedBox(height: 6),
          _buildSummaryLine(
            'Net Income',
            netStr,
            textColor,
            textColor,
            bold: true,
          ),
          if (savingsCents > 0) ...[
            pw.SizedBox(height: 6),
            _buildSummaryLine(
              'Savings Balance',
              moneyFmt.format(savingsCents / 100),
              textColor,
              textMuted,
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _buildSummaryLine(
    String label,
    String amount,
    PdfColor labelColor,
    PdfColor amountColor, {
    bool bold = false,
  }) {
    return pw.Row(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8),
            child: pw.Divider(
              color: const PdfColor.fromInt(0xFFD1D5DB),
              height: 1,
            ),
          ),
        ),
        pw.Text(
          amount,
          style: pw.TextStyle(
            fontSize: 10,
            color: amountColor,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
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
