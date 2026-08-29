import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/components/ui/app_scaffold.dart';
import 'package:bandroadie/components/ui/app_app_bar.dart';
import 'package:bandroadie/components/ui/app_icon_button.dart';
import 'models/print_template.dart';
import 'models/setlist_item.dart';
import 'services/setlist_print_service.dart';

class SetlistPdfPreviewScreen extends StatefulWidget {
  final String setlistName;
  final List<SetlistItem> items;
  final PrintTemplate template;
  final String? bandName;
  final String? gigDate;
  final String? venue;

  const SetlistPdfPreviewScreen({
    super.key,
    required this.setlistName,
    required this.items,
    required this.template,
    this.bandName,
    this.gigDate,
    this.venue,
  });

  @override
  State<SetlistPdfPreviewScreen> createState() =>
      _SetlistPdfPreviewScreenState();
}

class _SetlistPdfPreviewScreenState extends State<SetlistPdfPreviewScreen> {
  Uint8List? _cachedPdf;

  PdfPageFormat get _pageFormat => switch (widget.template.paperSize) {
        'a4' => PdfPageFormat.a4,
        'legal' => PdfPageFormat.legal,
        'tabloid' =>
          const PdfPageFormat(11 * PdfPageFormat.inch, 17 * PdfPageFormat.inch),
        _ => PdfPageFormat.letter,
      };

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    if (_cachedPdf != null) return _cachedPdf!;
    final bytes = await SetlistPrintService.generatePdfBytes(
      setlistName: widget.setlistName,
      items: widget.items,
      template: widget.template,
      bandName: widget.bandName,
      gigDate: widget.gigDate,
      venue: widget.venue,
    );
    _cachedPdf = Uint8List.fromList(bytes);
    return _cachedPdf!;
  }

  Future<void> _handleShare(BuildContext context) async {
    final bytes = await _buildPdf(_pageFormat);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${widget.setlistName} - Setlist.pdf',
    );
  }

  Future<void> _handlePrint() async {
    // Build PDF bytes while preview is still visible
    final bytes = await _buildPdf(_pageFormat);

    if (!mounted) return;

    // Pop the preview screen to release the printing channel
    Navigator.of(context).pop();

    // Wait for the frame to complete so PdfPreview is fully disposed
    // before opening the system print dialog (avoids macOS channel contention)
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Now open the system print dialog without contention
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: '${widget.setlistName} - Setlist',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      backgroundColor: context.colors.background,
      appBar: AppAppBar(
        backgroundColor: context.colors.background,
        leading: AppIconButton(
          icon: AppIcons.back,
          color: context.colors.textPrimary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Print Preview',
          style:
              AppTextStyles.title3.copyWith(color: context.colors.textPrimary),
        ),
        actions: [
          AppIconButton(
            onPressed: _handlePrint,
            icon: Icons.print_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          AppIconButton(
            onPressed: () => _handleShare(context),
            icon: AppIcons.share,
            size: 20,
            color: AppColors.primary,
          ),
        ],
      ),
      body: PdfPreview(
        build: _buildPdf,
        pdfFileName: '${widget.setlistName} - Setlist',
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        scrollViewDecoration: BoxDecoration(
          color: context.colors.background,
        ),
        pdfPreviewPageDecoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
