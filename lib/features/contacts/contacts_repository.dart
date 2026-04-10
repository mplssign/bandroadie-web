import 'package:flutter/foundation.dart';

import 'package:bandroadie/app/services/supabase_client.dart';
import 'models/contact.dart';

// ============================================================================
// CONTACTS REPOSITORY
// Handles all standalone contact data fetching from Supabase.
//
// ISOLATION RULES:
// - Every query REQUIRES a non-null bandId
// - If bandId is null, throws NoBandSelectedError
// ============================================================================

class NoBandSelectedContactsError extends Error {
  final String message;
  NoBandSelectedContactsError([
    this.message =
        'No band selected. Cannot fetch contacts without a band context.',
  ]);

  @override
  String toString() => 'NoBandSelectedContactsError: $message';
}

class ContactsRepository {
  final Map<String, _CacheEntry> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  Future<List<Contact>> fetchContacts({
    required String? bandId,
    bool forceRefresh = false,
  }) async {
    if (bandId == null || bandId.isEmpty) {
      throw NoBandSelectedContactsError();
    }

    if (!forceRefresh) {
      final cached = _cache[bandId];
      if (cached != null && !cached.isExpired) {
        return cached.data;
      }
    }

    if (kDebugMode) {
      debugPrint('[ContactsRepository] Fetching contacts for band: $bandId');
    }

    final response = await supabase
        .from('contacts')
        .select('*')
        .eq('band_id', bandId)
        .order('name', ascending: true);

    final rows = List<Map<String, dynamic>>.from(response);
    final contacts = rows.map((row) => Contact.fromJson(row)).toList();

    _cache[bandId] = _CacheEntry(data: contacts);

    if (kDebugMode) {
      debugPrint('[ContactsRepository] Fetched ${contacts.length} contacts');
    }

    return contacts;
  }

  Future<Contact> createContact({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    final insertData = {
      'band_id': bandId,
      ...data,
    };

    final response =
        await supabase.from('contacts').insert(insertData).select().single();

    _invalidateCache(bandId);
    return Contact.fromJson(response);
  }

  Future<Contact> updateContact({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final response = await supabase
        .from('contacts')
        .update(data)
        .eq('id', id)
        .select()
        .single();

    final contact = Contact.fromJson(response);
    _invalidateCache(contact.bandId);
    return contact;
  }

  Future<void> deleteContact({
    required String id,
    required String bandId,
  }) async {
    await supabase.from('contacts').delete().eq('id', id);
    _invalidateCache(bandId);
  }

  void _invalidateCache(String bandId) {
    _cache.remove(bandId);
  }

  void clearCache() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<Contact> data;
  final DateTime createdAt;

  _CacheEntry({required this.data}) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > ContactsRepository._cacheDuration;
}
