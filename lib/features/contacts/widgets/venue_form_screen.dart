import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import '../../../shared/utils/phone_input_formatter.dart';
import '../../bands/active_band_controller.dart';
import '../models/venue.dart';
import '../models/venue_contact.dart';
import '../venues_controller.dart';
import '../venues_repository.dart';
import 'venue_contact_block.dart';

// ============================================================================
// VENUE FORM SCREEN
// Full-screen create/edit form for venues with nested venue contacts.
// ============================================================================

class VenueFormScreen extends ConsumerStatefulWidget {
  final Venue? venue; // null = create mode, non-null = edit mode

  const VenueFormScreen({super.key, this.venue});

  @override
  ConsumerState<VenueFormScreen> createState() => _VenueFormScreenState();
}

class _VenueFormScreenState extends ConsumerState<VenueFormScreen> {
  final _repository = VenuesRepository();

  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  late FocusNode _nameFocus;
  late FocusNode _addressFocus;
  late FocusNode _cityFocus;
  late FocusNode _stateFocus;
  late FocusNode _phoneFocus;
  late FocusNode _notesFocus;

  final GlobalKey<AnimatedListState> _contactListKey =
      GlobalKey<AnimatedListState>();
  final List<_VenueContactEntry> _contactEntries = [];

  bool _isSaving = false;

  bool get _isEditMode => widget.venue != null;

  @override
  void initState() {
    super.initState();
    final v = widget.venue;
    _nameController = TextEditingController(text: v?.name ?? '');
    _addressController = TextEditingController(text: v?.address ?? '');
    _cityController = TextEditingController(text: v?.city ?? '');
    _stateController = TextEditingController(text: v?.state ?? '');
    _phoneController = TextEditingController(text: v?.phone ?? '');
    _notesController = TextEditingController(text: v?.notes ?? '');
    _nameFocus = FocusNode();
    _addressFocus = FocusNode();
    _cityFocus = FocusNode();
    _stateFocus = FocusNode();
    _phoneFocus = FocusNode();
    _notesFocus = FocusNode();

    // Pre-populate contacts in edit mode
    if (v != null) {
      for (final vc in v.contacts) {
        _contactEntries.add(_VenueContactEntry.fromVenueContact(vc));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _nameFocus.dispose();
    _addressFocus.dispose();
    _cityFocus.dispose();
    _stateFocus.dispose();
    _phoneFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _addContact() {
    final index = _contactEntries.length;
    _contactEntries.add(_VenueContactEntry());
    _contactListKey.currentState?.insertItem(
      index,
      duration: AppDurations.normal,
    );
  }

  void _removeContact(int index) {
    final removed = _contactEntries.removeAt(index);
    _contactListKey.currentState?.removeItem(
      index,
      (context, animation) => _buildContactAnimation(removed, animation),
      duration: AppDurations.normal,
    );
  }

  Widget _buildContactAnimation(
      _VenueContactEntry entry, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: VenueContactBlock(
          initialName: entry.name,
          initialTitle: entry.title,
          initialPhone: entry.phone,
          initialEmail: entry.email,
          initialNotes: entry.notes,
          timezone: ref.read(activeBandProvider).activeBand?.timezone,
          onRemove: () {},
          onChanged: (_) {},
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    setState(() => _isSaving = true);

    try {
      final venueData = <String, dynamic>{
        'name': name,
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'state': _stateController.text.trim().isEmpty
            ? null
            : _stateController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      };

      if (_isEditMode) {
        // Update venue
        await _repository.updateVenue(id: widget.venue!.id, data: venueData);

        // Handle venue contacts: remove old, add/update current
        final existingContactIds =
            widget.venue!.contacts.map((c) => c.id).toSet();
        final currentEntryIds = _contactEntries
            .where((e) => e.existingId != null)
            .map((e) => e.existingId!)
            .toSet();

        // Remove deleted contacts
        for (final id in existingContactIds.difference(currentEntryIds)) {
          await _repository.removeVenueContact(contactId: id, bandId: bandId);
        }

        // Update/add contacts
        for (final entry in _contactEntries) {
          final contactData = <String, dynamic>{
            'name': entry.name ?? '',
            'title': entry.title,
            'phone': entry.phone,
            'email': entry.email,
            'notes': entry.notes,
          };

          if (entry.existingId != null) {
            await _repository.updateVenueContact(
              contactId: entry.existingId!,
              bandId: bandId,
              data: contactData,
            );
          } else {
            await _repository.addVenueContact(
              venueId: widget.venue!.id,
              bandId: bandId,
              data: contactData,
            );
          }
        }
      } else {
        // Create venue
        final newVenue =
            await _repository.createVenue(bandId: bandId, data: venueData);

        // Add contacts
        for (final entry in _contactEntries) {
          final contactName = entry.name?.trim() ?? '';
          if (contactName.isEmpty) continue;
          await _repository.addVenueContact(
            venueId: newVenue.id,
            bandId: bandId,
            data: {
              'name': contactName,
              'title': entry.title,
              'phone': entry.phone,
              'email': entry.email,
              'notes': entry.notes,
            },
          );
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteVenue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBgElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Venue?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final bandId = ref.read(activeBandProvider).activeBandId;
    if (bandId == null) return;

    final success = await ref
        .read(venuesProvider.notifier)
        .delete(id: widget.venue!.id, bandId: bandId);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      }
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  List<TextInputFormatter> _getPhoneFormatters() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    return isUSTimezone(tz) ? [USPhoneInputFormatter(isUSTimezone: true)] : [];
  }

  List<TextInputFormatter> _getStateFormatters() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    return isUSTimezone(tz) ? [UpperCaseTextFormatter()] : [];
  }

  String _getStateLabel() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    if (isCanadianTimezone(tz)) return 'Province';
    if (isUKTimezone(tz)) return 'County';
    if (isUSTimezone(tz)) return 'State';
    return '';
  }

  bool _showStateField() {
    final tz = ref.read(activeBandProvider).activeBand?.timezone;
    return isUSTimezone(tz) || isCanadianTimezone(tz) || isUKTimezone(tz);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(AppIcons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEditMode ? 'Edit Venue' : 'New Venue',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.pagePadding),
        children: [
          // Venue fields
          TextField(
            controller: _nameController,
            focusNode: _nameFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Name *'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _addressController,
            focusNode: _addressFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Address'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cityController,
                  focusNode: _cityFocus,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 16),
                  decoration: _inputDecoration('City'),
                ),
              ),
              if (_showStateField()) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _stateController,
                    focusNode: _stateFocus,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 16),
                    decoration: _inputDecoration(_getStateLabel()),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: _getStateFormatters(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            focusNode: _phoneFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Phone'),
            keyboardType: TextInputType.phone,
            inputFormatters: _getPhoneFormatters(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            focusNode: _notesFocus,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _inputDecoration('Notes'),
            maxLines: 3,
          ),

          const SizedBox(height: 32),

          // Venue contacts section
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Contacts at this venue',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _addContact,
                icon: const Icon(AppIcons.add, size: 18),
                label: const Text('Add Contact'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // AnimatedList of venue contacts
          AnimatedList(
            key: _contactListKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            initialItemCount: _contactEntries.length,
            itemBuilder: (context, index, animation) {
              if (index >= _contactEntries.length) {
                return const SizedBox.shrink();
              }
              final entry = _contactEntries[index];
              return SizeTransition(
                sizeFactor: animation,
                child: FadeTransition(
                  opacity: animation,
                  child: VenueContactBlock(
                    key: ValueKey(entry.key),
                    initialName: entry.name,
                    initialTitle: entry.title,
                    initialPhone: entry.phone,
                    initialEmail: entry.email,
                    initialNotes: entry.notes,
                    timezone: ref.read(activeBandProvider).activeBand?.timezone,
                    onRemove: () => _removeContact(index),
                    onChanged: (data) {
                      entry.name = data['name'];
                      entry.title = data['title'];
                      entry.phone = data['phone'];
                      entry.email = data['email'];
                      entry.notes = data['notes'];
                    },
                  ),
                ),
              );
            },
          ),

          // Delete button (edit mode only)
          if (_isEditMode) ...[
            const SizedBox(height: 32),
            Center(
              child: TextButton(
                onPressed: _deleteVenue,
                child: const Text(
                  'Delete Venue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          ],

          // Bottom padding
          SizedBox(
            height:
                Spacing.space48 + MediaQuery.of(context).padding.bottom + 32,
          ),
        ],
      ),
    );
  }
}

/// Internal model for tracking venue contact entries in the form.
class _VenueContactEntry {
  final String key;
  final String? existingId;
  String? name;
  String? title;
  String? phone;
  String? email;
  String? notes;

  _VenueContactEntry({
    String? key,
    this.existingId,
    this.name,
    this.title,
    this.phone,
    this.email,
    this.notes,
  }) : key = key ?? UniqueKey().toString();

  factory _VenueContactEntry.fromVenueContact(VenueContact vc) {
    return _VenueContactEntry(
      existingId: vc.id,
      name: vc.name,
      title: vc.title,
      phone: vc.phone,
      email: vc.email,
      notes: vc.notes,
    );
  }
}
