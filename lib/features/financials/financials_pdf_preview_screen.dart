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
import '../members/member_vm.dart';
import 'financials_controller.dart';
import 'financials_report_builder.dart';
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
  final List<MemberVM> members;

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
    this.members = const [],
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

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(50),
        build: (ctx) => buildFinancialsReportContent(
          entries: widget.entries,
          bandName: widget.bandName,
          dateRangeLabel: _filterLabel,
          members: widget.members,
        ),
      ),
    );

    final bytes = await doc.save();
    _cachedPdf = Uint8List.fromList(bytes);
    return _cachedPdf!;
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
