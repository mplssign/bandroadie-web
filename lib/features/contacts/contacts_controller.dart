import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/contact.dart';
import 'contacts_repository.dart';

// ============================================================================
// CONTACTS CONTROLLER
// Riverpod state management for the standalone Contacts view.
// ============================================================================

class ContactsState {
  final List<Contact> contacts;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final List<Contact> filteredContacts;

  const ContactsState({
    this.contacts = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
    this.filteredContacts = const [],
  });

  bool get hasContacts => contacts.isNotEmpty;

  ContactsState copyWith({
    List<Contact>? contacts,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? searchQuery,
    List<Contact>? filteredContacts,
  }) {
    return ContactsState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      filteredContacts: filteredContacts ?? this.filteredContacts,
    );
  }
}

class ContactsNotifier extends Notifier<ContactsState> {
  final ContactsRepository _repository = ContactsRepository();

  @override
  ContactsState build() => const ContactsState();

  Future<void> load(String? bandId) async {
    if (bandId == null || bandId.isEmpty) {
      state = state.copyWith(
        contacts: [],
        isLoading: false,
        error: 'No band selected',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final contacts = await _repository.fetchContacts(bandId: bandId);
      state = state.copyWith(
        contacts: contacts,
        isLoading: false,
        filteredContacts: _filterContacts(contacts, state.searchQuery),
      );

      if (kDebugMode) {
        debugPrint('[ContactsController] Loaded ${contacts.length} contacts');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      if (kDebugMode) {
        debugPrint('[ContactsController] Error loading contacts: $e');
      }
    }
  }

  Future<void> refresh(String? bandId) async {
    if (bandId == null || bandId.isEmpty) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final contacts =
          await _repository.fetchContacts(bandId: bandId, forceRefresh: true);
      state = state.copyWith(
        contacts: contacts,
        isLoading: false,
        filteredContacts: _filterContacts(contacts, state.searchQuery),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<Contact?> create({
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final contact =
          await _repository.createContact(bandId: bandId, data: data);
      await load(bandId);
      return contact;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ContactsController] Error creating contact: $e');
      }
      return null;
    }
  }

  Future<Contact?> update({
    required String id,
    required String bandId,
    required Map<String, dynamic> data,
  }) async {
    try {
      final contact = await _repository.updateContact(id: id, data: data);
      await load(bandId);
      return contact;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ContactsController] Error updating contact: $e');
      }
      return null;
    }
  }

  Future<bool> delete({
    required String id,
    required String bandId,
  }) async {
    try {
      await _repository.deleteContact(id: id, bandId: bandId);
      await load(bandId);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ContactsController] Error deleting contact: $e');
      }
      return false;
    }
  }

  void reset() {
    _repository.clearCache();
    state = const ContactsState();
  }

  void setSearchQuery(String query) {
    state = state.copyWith(
      searchQuery: query,
      filteredContacts: _filterContacts(state.contacts, query),
    );
  }

  List<Contact> _filterContacts(List<Contact> contacts, String query) {
    if (query.isEmpty) return contacts;
    final lower = query.toLowerCase();
    return contacts.where((c) => c.name.toLowerCase().contains(lower)).toList();
  }
}

final contactsProvider = NotifierProvider<ContactsNotifier, ContactsState>(
  ContactsNotifier.new,
);
