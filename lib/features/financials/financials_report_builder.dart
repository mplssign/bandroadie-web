import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../members/member_vm.dart';
import 'models/financial_entry.dart';

// ============================================================================
// FINANCIALS REPORT BUILDER
// Pure pw.Widget rendering helpers for the combined Income and Expense
// Report PDF (header + Income + Expenses + Band Savings Account + Band
// Disbursements). No state, no widget lifecycle — called from
// FinancialsPdfPreviewScreen._buildPdf.
// ============================================================================

// Clean, professional color palette (matches prior report styling)
const _dividerColor = PdfColor.fromInt(0xFFE5E7EB); // thin divider
const _thickDividerColor = PdfColor.fromInt(0xFF111827); // thick divider
const _textBlack = PdfColor.fromInt(0xFF000000);

/// Assembles the full report body: header, Income, Expenses, Band Savings
/// Account, and Band Disbursements sections, in that order.
List<pw.Widget> buildFinancialsReportContent({
  required List<FinancialEntry> entries,
  required String bandName,
  required String dateRangeLabel,
  required List<MemberVM> members,
}) {
  final moneyFmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final dateFmt = DateFormat('MMM d, yyyy');
  final widgets = <pw.Widget>[];

  widgets.addAll(_buildHeader(bandName, dateRangeLabel));

  if (entries.isEmpty) {
    widgets.add(
      pw.Center(
        child: pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 60),
          child: pw.Text(
            'No financial activity during this reporting period.',
            style: pw.TextStyle(fontSize: 13, color: _textBlack),
          ),
        ),
      ),
    );
    return widgets;
  }

  final incomeEntries = entries.where((e) => e.isIncome).toList();
  final expenseEntries = entries.where((e) => !e.isIncome).toList();

  widgets.addAll(_buildItemizedSection(
    title: 'Income',
    entries: incomeEntries,
    emptyText: 'No income during this period.',
    totalLabel: 'TOTAL INCOME',
    totalAmountColor: _textBlack,
    moneyFmt: moneyFmt,
    dateFmt: dateFmt,
    members: members,
  ));

  widgets.add(_buildThickDivider());

  widgets.addAll(_buildItemizedSection(
    title: 'Expenses',
    entries: expenseEntries,
    emptyText: 'No expenses during this period.',
    totalLabel: 'TOTAL EXPENSES',
    totalAmountColor: _textBlack,
    moneyFmt: moneyFmt,
    dateFmt: dateFmt,
    members: members,
  ));

  widgets.add(_buildThickDivider());

  widgets.addAll(_buildBandSavingsSection(entries, moneyFmt));

  widgets.addAll(_buildBandDisbursementsSection(entries, members, moneyFmt));

  return widgets;
}

// ---------------------------------------------------------------------------
// HEADER
// ---------------------------------------------------------------------------

List<pw.Widget> _buildHeader(String bandName, String dateRangeLabel) {
  return [
    pw.Center(
      child: pw.Text(
        'Income and Expense Report',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: _textBlack,
        ),
      ),
    ),
    pw.SizedBox(height: 8),
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          bandName,
          style: pw.TextStyle(
            fontSize: 24,
            fontWeight: pw.FontWeight.bold,
            color: _textBlack,
          ),
        ),
        pw.Text(
          dateRangeLabel,
          style: pw.TextStyle(fontSize: 11, color: _textBlack),
        ),
      ],
    ),
    pw.SizedBox(height: 24),
  ];
}

// ---------------------------------------------------------------------------
// INCOME / EXPENSES — ITEMIZED SECTION
// ---------------------------------------------------------------------------

List<pw.Widget> _buildItemizedSection({
  required String title,
  required List<FinancialEntry> entries,
  required String emptyText,
  required String totalLabel,
  required PdfColor totalAmountColor,
  required NumberFormat moneyFmt,
  required DateFormat dateFmt,
  required List<MemberVM> members,
}) {
  final widgets = <pw.Widget>[
    _buildSectionHeader(title, _textBlack),
  ];

  if (entries.isEmpty) {
    widgets.addAll([
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: pw.Text(
          emptyText,
          style: pw.TextStyle(fontSize: 11, color: _textBlack),
        ),
      ),
      pw.SizedBox(height: 8),
    ]);
    return widgets;
  }

  widgets.add(_buildItemizedColumnHeaders());

  final sorted = [...entries]
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
  final totalCents = entries.fold<int>(0, (s, e) => s + e.amountCents);
  final membersById = {for (final m in members) m.userId: m};

  for (final entry in sorted) {
    widgets.add(_buildItemRow(entry, membersById, moneyFmt, dateFmt));
  }

  widgets.addAll([
    pw.SizedBox(height: 4),
    _buildSubtotalRow(
        totalLabel, totalCents, moneyFmt, _textBlack, totalAmountColor),
    pw.SizedBox(height: 24),
  ]);

  return widgets;
}

const double _colWidthDate = 80;
const double _colWidthEntryType = 70;
const double _colWidthPayer = 80;
const double _colWidthPaidTo = 80;
const double _colWidthAmount = 60;

pw.Widget _buildItemizedColumnHeaders() {
  final labelStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: _textBlack,
  );
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 16),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.SizedBox(
          width: _colWidthDate,
          child: pw.Text('Date', style: labelStyle),
        ),
        pw.SizedBox(
          width: _colWidthEntryType,
          child: pw.Text('Entry type', style: labelStyle),
        ),
        pw.SizedBox(
          width: _colWidthPayer,
          child: pw.Text('Payer', style: labelStyle),
        ),
        pw.SizedBox(
          width: _colWidthPaidTo,
          child: pw.Text('Paid to', style: labelStyle),
        ),
        pw.Expanded(
          child: pw.Text('Description', style: labelStyle),
        ),
        pw.SizedBox(
          width: _colWidthAmount,
          child: pw.Text(
            'Amount',
            style: labelStyle,
            textAlign: pw.TextAlign.right,
          ),
        ),
      ],
    ),
  );
}

String _resolvePaidTo(FinancialEntry entry, Map<String, MemberVM> membersById) {
  final userId = entry.paidToUserId;
  if (userId != null && userId.isNotEmpty) {
    final member = membersById[userId];
    if (member != null) return member.name;
    return entry.paidToName ??
        'Member ${userId.substring(0, userId.length < 8 ? userId.length : 8)}';
  }
  return entry.paidToName ?? '';
}

pw.Widget _buildItemRow(
  FinancialEntry entry,
  Map<String, MemberVM> membersById,
  NumberFormat moneyFmt,
  DateFormat dateFmt,
) {
  final singleLineStyle = pw.TextStyle(fontSize: 10, color: _textBlack);

  return pw.Container(
    decoration: pw.BoxDecoration(
      border:
          pw.Border(bottom: pw.BorderSide(color: _dividerColor, width: 0.5)),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: _colWidthDate,
          child: pw.Text(
            dateFmt.format(entry.entryDate),
            style: singleLineStyle,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
        pw.SizedBox(
          width: _colWidthEntryType,
          child: pw.Text(
            entry.category,
            style: singleLineStyle,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
        pw.SizedBox(
          width: _colWidthPayer,
          child: pw.Text(
            entry.payerName ?? '',
            style: singleLineStyle,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
        pw.SizedBox(
          width: _colWidthPaidTo,
          child: pw.Text(
            _resolvePaidTo(entry, membersById),
            style: singleLineStyle,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            entry.description ?? '',
            style: pw.TextStyle(fontSize: 9, color: _textBlack),
          ),
        ),
        pw.SizedBox(
          width: _colWidthAmount,
          child: pw.Text(
            moneyFmt.format(entry.amountCents / 100),
            style: singleLineStyle,
            textAlign: pw.TextAlign.right,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// BAND SAVINGS ACCOUNT
// ---------------------------------------------------------------------------

List<pw.Widget> _buildBandSavingsSection(
  List<FinancialEntry> entries,
  NumberFormat moneyFmt,
) {
  final deposits = entries.where((e) => e.depositToSavings == true).toList()
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));

  if (deposits.isEmpty) return const [];

  final dateFmt = DateFormat('MMM d, yyyy');
  final totalCents =
      deposits.fold<int>(0, (s, e) => s + (e.depositToSavingsCents ?? 0));

  final widgets = <pw.Widget>[
    _buildSectionHeader('Band Savings Account', _textBlack),
  ];

  for (final entry in deposits) {
    final label = (entry.description != null && entry.description!.isNotEmpty)
        ? entry.description!
        : entry.category;
    widgets.add(_buildDateLineItem(
      dateFmt.format(entry.entryDate),
      label,
      entry.depositToSavingsCents ?? 0,
      moneyFmt,
    ));
  }

  widgets.addAll([
    pw.SizedBox(height: 4),
    _buildSubtotalRow(
        'TOTAL DEPOSITS', totalCents, moneyFmt, _textBlack, _textBlack),
    pw.SizedBox(height: 24),
  ]);

  return widgets;
}

pw.Widget _buildDateLineItem(
  String dateLabel,
  String description,
  int amountCents,
  NumberFormat moneyFmt,
) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border:
          pw.Border(bottom: pw.BorderSide(color: _dividerColor, width: 0.5)),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.SizedBox(
          width: 80,
          child: pw.Text(
            dateLabel,
            style: pw.TextStyle(fontSize: 10, color: _textBlack),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            description,
            style: pw.TextStyle(fontSize: 11, color: _textBlack),
          ),
        ),
        pw.Text(
          moneyFmt.format(amountCents / 100),
          style: pw.TextStyle(fontSize: 11, color: _textBlack),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// BAND DISBURSEMENTS
// ---------------------------------------------------------------------------

class _DisbursementLineItem {
  final String description;
  final int amountCents;
  final DateTime entryDate;

  const _DisbursementLineItem({
    required this.description,
    required this.amountCents,
    required this.entryDate,
  });
}

List<pw.Widget> _buildBandDisbursementsSection(
  List<FinancialEntry> entries,
  List<MemberVM> members,
  NumberFormat moneyFmt,
) {
  final byUserId = <String, List<_DisbursementLineItem>>{};

  for (final entry in entries) {
    final disbursements = entry.disbursements;
    if (disbursements == null || disbursements.isEmpty) continue;
    final label = (entry.description != null && entry.description!.isNotEmpty)
        ? entry.description!
        : entry.category;
    for (final e in disbursements.entries) {
      byUserId.putIfAbsent(e.key, () => []).add(_DisbursementLineItem(
            description: label,
            amountCents: e.value,
            entryDate: entry.entryDate,
          ));
    }
  }

  if (byUserId.isEmpty) return const [];

  final membersById = {for (final m in members) m.userId: m};

  String nameFor(String userId) {
    final member = membersById[userId];
    if (member != null) return member.name;
    return 'Member ${userId.substring(0, userId.length < 8 ? userId.length : 8)}';
  }

  final userIds = byUserId.keys.toList()
    ..sort((a, b) => nameFor(a).compareTo(nameFor(b)));

  int totalCents = 0;
  final widgets = <pw.Widget>[
    _buildSectionHeader('Band Disbursements', _textBlack),
  ];

  for (final userId in userIds) {
    final items = byUserId[userId]!
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));

    widgets.add(pw.Padding(
      padding:
          const pw.EdgeInsets.only(top: 10, left: 16, right: 16, bottom: 2),
      child: pw.Text(
        nameFor(userId),
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: _textBlack,
        ),
      ),
    ));

    for (final item in items) {
      totalCents += item.amountCents;
      widgets.add(_buildDisbursementLineItem(item, moneyFmt));
    }
  }

  widgets.addAll([
    pw.SizedBox(height: 4),
    _buildThickDivider(),
    _buildSubtotalRow(
        'TOTAL DISBURSEMENTS', totalCents, moneyFmt, _textBlack, _textBlack),
    _buildThickDivider(),
  ]);

  return widgets;
}

pw.Widget _buildDisbursementLineItem(
  _DisbursementLineItem item,
  NumberFormat moneyFmt,
) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      border:
          pw.Border(bottom: pw.BorderSide(color: _dividerColor, width: 0.5)),
    ),
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8),
          child: pw.Text(
            item.description,
            style: pw.TextStyle(fontSize: 10, color: _textBlack),
          ),
        ),
        pw.Text(
          moneyFmt.format(item.amountCents / 100),
          style: pw.TextStyle(fontSize: 11, color: _textBlack),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// SHARED HELPERS
// ---------------------------------------------------------------------------

pw.Widget _buildSectionHeader(
  String title,
  PdfColor textColor,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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

pw.Widget _buildSubtotalRow(
  String label,
  int amountCents,
  NumberFormat moneyFmt,
  PdfColor textColor,
  PdfColor amountColor,
) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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

pw.Widget _buildThickDivider() {
  return pw.Container(
    margin: const pw.EdgeInsets.symmetric(vertical: 8),
    height: 2,
    color: _thickDividerColor,
  );
}
