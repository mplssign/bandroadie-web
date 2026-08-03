import 'package:intl/intl.dart';

// ============================================================================
// FINANCIAL ENTRY MODELS
// Data models for the financials feature.
// ============================================================================

/// The type of financial entry.
enum FinancialEntryType {
  gigPay,
  merchSale,
  equipmentSale,
  miscIncome,
  expense;

  bool get isIncome => this != expense;

  String get displayName {
    switch (this) {
      case FinancialEntryType.gigPay:
        return 'Gig Pay';
      case FinancialEntryType.merchSale:
        return 'Merch Sale';
      case FinancialEntryType.equipmentSale:
        return 'Equipment Sale';
      case FinancialEntryType.miscIncome:
        return 'Misc Income';
      case FinancialEntryType.expense:
        return 'Expense';
    }
  }

  String get dbValue {
    switch (this) {
      case FinancialEntryType.gigPay:
        return 'gig_pay';
      case FinancialEntryType.merchSale:
        return 'merch_sale';
      case FinancialEntryType.equipmentSale:
        return 'equipment_sale';
      case FinancialEntryType.miscIncome:
        return 'misc_income';
      case FinancialEntryType.expense:
        return 'expense';
    }
  }

  static FinancialEntryType fromDbValue(String value) {
    return FinancialEntryType.values.firstWhere(
      (t) => t.dbValue == value,
      orElse: () => FinancialEntryType.miscIncome,
    );
  }
}

/// Persisted model matching the `financial_entries` table.
class FinancialEntry {
  final String id;
  final String bandId;
  final FinancialEntryType entryType;
  final String category;
  final int amountCents;
  final bool isIncome;
  final String? description;
  final DateTime entryDate;
  final bool isReimbursed;
  final DateTime? reimbursedDate;
  final bool? is1099Expected;
  final String? payerName;
  final String? paidToName;
  final String? paidToUserId;
  final Map<String, int>? disbursements;
  final bool? depositToSavings;
  final int? depositToSavingsCents;
  final String? gigId;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const FinancialEntry({
    required this.id,
    required this.bandId,
    required this.entryType,
    required this.category,
    required this.amountCents,
    required this.isIncome,
    this.description,
    required this.entryDate,
    this.isReimbursed = false,
    this.reimbursedDate,
    this.is1099Expected,
    this.payerName,
    this.paidToName,
    this.paidToUserId,
    this.disbursements,
    this.depositToSavings,
    this.depositToSavingsCents,
    this.gigId,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FinancialEntry.fromJson(Map<String, dynamic> json) {
    return FinancialEntry(
      id: json['id'] as String,
      bandId: json['band_id'] as String,
      entryType: FinancialEntryType.fromDbValue(json['entry_type'] as String),
      category: json['category'] as String,
      amountCents: json['amount_cents'] as int,
      isIncome: json['is_income'] as bool,
      description: json['description'] as String?,
      entryDate: DateTime.parse(json['entry_date'] as String),
      isReimbursed: json['is_reimbursed'] as bool? ?? false,
      reimbursedDate: json['reimbursed_date'] != null
          ? DateTime.parse(json['reimbursed_date'] as String)
          : null,
      is1099Expected: json['is_1099_expected'] as bool?,
      payerName: json['payor_name'] as String?,
      paidToName: json['paid_to_name'] as String?,
      paidToUserId: json['paid_to_user_id'] as String?,
      disbursements: (json['disbursements'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())),
      depositToSavings: json['deposit_to_savings'] as bool?,
      depositToSavingsCents: json['deposit_to_savings_cents'] as int?,
      gigId: json['gig_id'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'band_id': bandId,
      'entry_type': entryType.dbValue,
      'category': category,
      'amount_cents': amountCents,
      'is_income': isIncome,
      'description': description,
      'entry_date': entryDate.toIso8601String().split('T').first,
      'is_reimbursed': isReimbursed,
      'reimbursed_date': reimbursedDate?.toIso8601String().split('T').first,
      'is_1099_expected': is1099Expected,
      'payor_name': payerName,
      'paid_to_name': paidToName,
      'paid_to_user_id': paidToUserId,
      'disbursements': disbursements,
      'deposit_to_savings': depositToSavings,
      'deposit_to_savings_cents': depositToSavingsCents,
      'gig_id': gigId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Formatted amount as a dollar string with commas (e.g., "$1,500.00")
  String get formattedAmount {
    final dollars = amountCents ~/ 100;
    final cents = amountCents % 100;
    final dollarsFormatted = NumberFormat('#,##0').format(dollars);
    return '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';
  }

  /// Formatted savings amount (e.g., "$250.00"). Returns null if cents is null.
  String? get formattedDepositToSavings {
    final c = depositToSavingsCents;
    if (c == null) return null;
    final dollars = c ~/ 100;
    final cents = c % 100;
    final dollarsFormatted = NumberFormat('#,##0').format(dollars);
    return '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';
  }
}

/// In-memory representation of payment details captured via GigPayBottomSheet.
/// Held in EventFormData while a gig is being created/edited.
/// Persisted to financial_entries on gig save.
class GigPayDetails {
  final int amountCents;
  final bool is1099Expected;
  final String? payerName;
  final String? paidToName;
  final String? paidToUserId;
  final Map<String, int>? disbursements;
  final DateTime paymentDate;
  final String? existingEntryId;

  const GigPayDetails({
    required this.amountCents,
    required this.is1099Expected,
    this.payerName,
    this.paidToName,
    this.paidToUserId,
    this.disbursements,
    required this.paymentDate,
    this.existingEntryId,
  });

  /// Factory to build from a FinancialEntry (edit mode — entry already exists).
  factory GigPayDetails.fromEntry(FinancialEntry entry) {
    return GigPayDetails(
      amountCents: entry.amountCents,
      is1099Expected: entry.is1099Expected ?? false,
      // payor_name is the canonical column; fall back to description for legacy entries
      payerName: entry.payerName ?? entry.description,
      paidToName: entry.paidToName,
      paidToUserId: entry.paidToUserId,
      paymentDate: entry.entryDate,
      existingEntryId: entry.id,
    );
  }

  /// Factory for legacy gigs where only the amount is known.
  factory GigPayDetails.fromAmountOnly({
    required int amountCents,
    required DateTime gigDate,
  }) {
    return GigPayDetails(
      amountCents: amountCents,
      is1099Expected: false,
      paymentDate: gigDate,
    );
  }

  /// Formatted amount as a dollar string with commas (e.g., "$1,500.00")
  String get formattedAmount {
    final dollars = amountCents ~/ 100;
    final cents = amountCents % 100;
    final dollarsFormatted = NumberFormat('#,##0').format(dollars);
    return '\$$dollarsFormatted.${cents.toString().padLeft(2, '0')}';
  }
}
