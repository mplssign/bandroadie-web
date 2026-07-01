import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services/supabase_client.dart';
import 'models/financial_entry.dart';

// ============================================================================
// FINANCIAL ENTRY REPOSITORY
// Supabase data access for financial_entries table.
// BAND ISOLATION: All operations require a non-null bandId.
// ============================================================================

/// Exception thrown when a band context is required but not provided.
class NoBandSelectedError extends Error {
  final String message;
  NoBandSelectedError([this.message = 'No band selected']);
  @override
  String toString() => 'NoBandSelectedError: $message';
}

class FinancialEntryRepository {
  /// Fetch all financial entries for a band, ordered by entry_date DESC.
  Future<List<FinancialEntry>> fetchEntriesForBand(String bandId) async {
    if (bandId.isEmpty) throw NoBandSelectedError();

    final response = await supabase
        .from('financial_entries')
        .select()
        .eq('band_id', bandId)
        .order('entry_date', ascending: false);

    return response
        .map<FinancialEntry>((json) => FinancialEntry.fromJson(json))
        .toList();
  }

  /// Fetch the gig_pay entry for a specific gig (at most one).
  Future<FinancialEntry?> fetchGigPayEntry(String gigId) async {
    final response = await supabase
        .from('financial_entries')
        .select()
        .eq('gig_id', gigId)
        .eq('entry_type', 'gig_pay')
        .maybeSingle();

    if (response == null) return null;
    return FinancialEntry.fromJson(response);
  }

  /// Create or update a gig_pay entry.
  /// Uses existingEntryId from details to decide INSERT vs UPDATE.
  Future<FinancialEntry> upsertGigPayEntry({
    required String bandId,
    required String gigId,
    required DateTime gigDate,
    required GigPayDetails details,
  }) async {
    if (bandId.isEmpty) throw NoBandSelectedError();

    final createdBy = supabase.auth.currentUser?.id;
    if (createdBy == null) throw StateError('No authenticated user');

    final payload = {
      'band_id': bandId,
      'entry_type': 'gig_pay',
      'category': 'Gig Pay',
      'amount_cents': details.amountCents,
      'is_income': true,
      'entry_date': details.paymentDate.toIso8601String().split('T').first,
      'is_1099_expected': details.is1099Expected,
      'payor_name':
          details.payerName?.isEmpty == true ? null : details.payerName,
      'paid_to_name':
          details.paidToName?.isEmpty == true ? null : details.paidToName,
      'paid_to_user_id': details.paidToUserId,
      'gig_id': gigId,
      'created_by': createdBy,
    };

    Map<String, dynamic> result;
    if (details.existingEntryId != null) {
      // UPDATE existing entry
      final updated = await supabase
          .from('financial_entries')
          .update({
            ...payload,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', details.existingEntryId!)
          .eq('band_id', bandId)
          .select()
          .single();
      result = updated;
    } else {
      // No existingEntryId — query for an existing gig_pay row before inserting
      // to avoid violating the uniq_gig_pay_entry unique partial index.
      final existingRow = await supabase
          .from('financial_entries')
          .select('id')
          .eq('gig_id', gigId)
          .eq('entry_type', 'gig_pay')
          .eq('band_id', bandId)
          .maybeSingle();

      if (existingRow != null) {
        final updated = await supabase
            .from('financial_entries')
            .update({
              ...payload,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existingRow['id'] as String)
            .eq('band_id', bandId)
            .select()
            .single();
        result = updated;
      } else {
        final inserted = await supabase
            .from('financial_entries')
            .insert(payload)
            .select()
            .single();
        result = inserted;
      }
    }

    return FinancialEntry.fromJson(result);
  }

  /// Insert a new manual financial entry (income or expense).
  Future<FinancialEntry> insertEntry({
    required String bandId,
    required FinancialEntryType entryType,
    required String category,
    required int amountCents,
    required DateTime entryDate,
    String? description,
    bool? is1099Expected,
    String? payerName,
    String? paidToName,
    String? paidToUserId,
    Map<String, int>? disbursements,
    bool? depositToSavings,
    int? depositToSavingsCents,
  }) async {
    if (bandId.isEmpty) throw NoBandSelectedError();

    final createdBy = supabase.auth.currentUser?.id;
    if (createdBy == null) throw StateError('No authenticated user');

    final payload = {
      'band_id': bandId,
      'entry_type': entryType.dbValue,
      'category': category,
      'amount_cents': amountCents,
      'is_income': entryType.isIncome,
      'description': description?.isEmpty == true ? null : description,
      'entry_date': entryDate.toIso8601String().split('T').first,
      'is_1099_expected': is1099Expected,
      'payor_name': payerName?.isEmpty == true ? null : payerName,
      'paid_to_name': paidToName?.isEmpty == true ? null : paidToName,
      'paid_to_user_id': paidToUserId,
      'disbursements': disbursements,
      'deposit_to_savings': depositToSavings,
      'deposit_to_savings_cents': depositToSavingsCents,
      'created_by': createdBy,
    };

    final result = await supabase
        .from('financial_entries')
        .insert(payload)
        .select()
        .single();

    return FinancialEntry.fromJson(result);
  }

  /// Update an existing manual financial entry.
  Future<FinancialEntry> updateEntry({
    required String entryId,
    required String bandId,
    required FinancialEntryType entryType,
    required String category,
    required int amountCents,
    required DateTime entryDate,
    String? description,
    bool? is1099Expected,
    String? payerName,
    String? paidToName,
    String? paidToUserId,
    Map<String, int>? disbursements,
    bool? depositToSavings,
    int? depositToSavingsCents,
  }) async {
    if (bandId.isEmpty) throw NoBandSelectedError();

    final result = await supabase
        .from('financial_entries')
        .update({
          'entry_type': entryType.dbValue,
          'category': category,
          'amount_cents': amountCents,
          'is_income': entryType.isIncome,
          'description': description?.isEmpty == true ? null : description,
          'entry_date': entryDate.toIso8601String().split('T').first,
          'is_1099_expected': is1099Expected,
          'payor_name': payerName?.isEmpty == true ? null : payerName,
          'paid_to_name': paidToName?.isEmpty == true ? null : paidToName,
          'paid_to_user_id': paidToUserId,
          'disbursements': disbursements,
          'deposit_to_savings': depositToSavings,
          'deposit_to_savings_cents': depositToSavingsCents,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', entryId)
        .eq('band_id', bandId)
        .select()
        .single();

    return FinancialEntry.fromJson(result);
  }

  /// Delete a financial entry by ID.
  Future<void> deleteEntry(String entryId, String bandId) async {
    if (bandId.isEmpty) throw NoBandSelectedError();

    await supabase
        .from('financial_entries')
        .delete()
        .eq('id', entryId)
        .eq('band_id', bandId);
  }
}

final financialEntryRepositoryProvider = Provider<FinancialEntryRepository>(
  (_) => FinancialEntryRepository(),
);
